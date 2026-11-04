-- Production definitions read 5 Nov 2026 09:25 AEDT (pg_get_functiondef, project fxcwkweaxjtknorudmwp), unchanged. run.sh checks each md5
-- against live before migration 20261105020000 edits them: svc_provider_policy_record 16b04b31, svc_central_ai_next fc8273f8,
-- svc_central_ai_record 2f386c25, policy_auto_approve_v1 12cce3d8.
CREATE OR REPLACE FUNCTION public.svc_provider_policy_record(p_source_id uuid, p_parsed jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.provider_fact_sources%rowtype; v_id uuid; v_status text; v_parser text := coalesce(p_parsed->>'parser', 'unknown');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_source_id;
  if f.id is null or f.kind not in ('english_policy', 'intake_calendar') then raise exception 'not an English policy or calendar document'; end if;
  if jsonb_typeof(p_parsed) <> 'object' then raise exception 'parsed result must be an object'; end if;
  v_status := case
    when f.kind = 'english_policy' and (coalesce(p_parsed->'defaults', '{}'::jsonb) <> '{}'::jsonb
           or exists (select 1 from jsonb_array_elements(coalesce(p_parsed->'exceptions', '[]'::jsonb)) e
                       where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0)) then 'proposed'
    when f.kind = 'intake_calendar' and jsonb_array_length(coalesce(p_parsed->'periods', '[]'::jsonb)) > 0 then 'proposed'
    else 'no_values' end;
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
  values (f.provider_id, f.id, f.kind, v_parser, f.content_hash, f.evidence_id, f.url, left(p_parsed->>'style', 40), p_parsed, v_status)
  on conflict on constraint provider_policy_proposals_key do update
     set proposal = excluded.proposal, style = excluded.style, evidence_id = excluded.evidence_id,
         status = case when pipeline.provider_policy_proposals.status in ('proposed', 'no_values') then excluded.status else pipeline.provider_policy_proposals.status end,
         updated_at = now()
  returning id, status into v_id, v_status;
  update pipeline.provider_policy_proposals set status = 'superseded', updated_at = now()
   where fact_source_id = f.id and id <> v_id and status in ('proposed', 'no_values') and parser <> 'written out from the central page';
  return jsonb_build_object('id', v_id, 'status', v_status);
end $function$
;
CREATE OR REPLACE FUNCTION public.svc_central_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; s pipeline.central_ai_settings%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into s from pipeline.central_ai_settings where id = 1;
  if not coalesce(s.enabled, false) then return '[]'::jsonb; end if;
  with pick as (select q.id from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                   and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
                 order by q.id limit greatest(1, least(coalesce(p_limit, 6), 10)) for update skip locked),
  upd as (update pipeline.central_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'id', u.fact_source_id, 'kind', u.kind, 'url', f.url, 'provider', coalesce(p.display_name, p.canonical_name),
           'storage_path', e.storage_path, 'model', s.model_identifier, 'model_code', s.model_code)), '[]'::jsonb) into v
    from upd u join pipeline.provider_fact_sources f on f.id = u.fact_source_id join pipeline.evidence_artifacts e on e.id = f.evidence_id
    join catalogue.providers p on p.id = u.provider_id;
  return v;
end $function$
;
CREATE OR REPLACE FUNCTION public.svc_central_ai_record(p_queue_id bigint, p_parsed jsonb, p_cost numeric, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q pipeline.central_ai_queue%rowtype; r jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.central_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false); end if;
  if p_error is not null then
    update pipeline.central_ai_queue set state = case when p_error = 'time budget' then 'queued' when attempts >= 3 then 'failed' else 'queued' end,
           attempts = case when p_error = 'time budget' then greatest(attempts - 1, 0) else attempts end, leased_until = null, error = left(p_error, 400), cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0)
     where id = q.id;
    return jsonb_build_object('ok', true, 'status', 'error');
  end if;
  r := public.svc_provider_policy_record(q.fact_source_id, p_parsed);
  update pipeline.central_ai_queue set state = 'done', done_at = now(), leased_until = null, status = r->>'status', cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0), error = null where id = q.id;
  if r->>'status' = 'proposed' then
    update pipeline.provider_onboarding o set stop_reason = 'approve_central', updated_at = now(),
           note = 'The AI read its central pages; approve or reject them in the Adapter builder (1.3) or Providers › Onboarding › Approvals waiting.'
     where o.provider_id = q.provider_id and o.status = 'stopped' and o.stop_reason = 'nothing_ready';
  end if;
  return jsonb_build_object('ok', true, 'status', r->>'status');
end $function$
;
CREATE OR REPLACE FUNCTION security.policy_auto_approve_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_sum jsonb; v_ag int; v_df int; v_ok int := 0; v_refused int := 0;
        v_max numeric := security.pipeline_num_v1('central.max_disagree_pct', 50);
        v_min int := security.pipeline_num_v1('central.min_compare', 10)::int;
        v_note text := 'Automatic: AI reading of the central page, every value quoted on the page (Platform Admin 15 Oct 2026: "Central pages, per course group", "Auto-approve checked AI proposals")';
begin
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve'), false) then
    return jsonb_build_object('off', true);
  end if;
  for r in select x.* from pipeline.provider_policy_proposals x
             left join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id
            where x.status = 'proposed' and x.parser like 'ai:%' and x.kind in ('english_policy', 'intake_calendar')
              -- 23 Oct 2026 (Platform Admin 12:40): English rules for every university, not only the focus list
              and (coalesce(f.in_focus, false)
                   or (x.kind = 'english_policy' and coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve_english_all'), false)))
            order by f.rank nulls last, x.created_at loop
    if r.kind = 'english_policy' then
      v_sum := security.provider_policy_refresh_one_v1(r.id);
      v_ag := coalesce((v_sum->>'agrees')::int, 0); v_df := coalesce((v_sum->>'differs')::int, 0);
      if v_ag + v_df >= v_min and 100.0 * v_df / (v_ag + v_df) > v_max then
        insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
        values ('policy', r.id::text, r.provider_id, 'english', 'policy_disagrees',
                format('Not approved automatically: %s course pages agree and %s disagree with this default; a person decides (%s)', v_ag, v_df, r.url), 'policy-auto-approve')
        on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
        v_refused := v_refused + 1;
        continue;
      end if;
    end if;
    update pipeline.provider_policy_proposals set status = 'approved', decided_by = null, decided_at = now(), decision_note = v_note, updated_at = now() where id = r.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'approve', r.kind || ': ' || r.url, jsonb_build_object('decision', 'Platform Admin 15 Oct 2026: automatic approval of checked AI readings', 'proposal_id', r.id, 'provider_id', r.provider_id), null);
    update pipeline.provider_policy_proposals
       set status = 'superseded', decided_at = now(), updated_at = now(), decision_note = 'Closed: another document for this university was approved (' || r.url || ')'
     where provider_id = r.provider_id and kind = r.kind and status = 'proposed' and id <> r.id;
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('approved', v_ok, 'refused', v_refused);
end $function$
;
