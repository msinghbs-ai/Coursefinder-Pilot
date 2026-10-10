-- CF-247 Phase 3, round 2: the shadow run with a stronger adapter model.
-- Platform Admin decision 9 Oct 2026 (multiple choice): "Stronger adapter model". Round 1 (Qwen3 30B, the builder default)
-- agreed with Layer 3 where both found a value but found fewer values; no field met the retire rule.
-- Round 2 uses Xiaomi MiMo v2.6 Pro (profile openrouter-intake-l3c-mimo-v2-6-pro-v1), the stronger model Layer 3 already
-- escalates intake answers to, as the single pinned adapter model for all three fields; nothing else changes (same task
-- contracts and checks, same retire rule, nothing admitted). Round 1 rows are kept and reported beside round 2.
-- Each round reads courses no earlier round read (one read per Layer 3 work item). The daily read limit counts the
-- current round; the US$15 daily spend limit counts every round. Replaced functions are md5-checked against live first.
-- No adapter's own model choice is changed: the override applies to the shadow run only.

do $guard$
declare want jsonb := '{"svc_adapter_shadow_claim(text,integer,text)":"b4ffa421d92d75ad16fdd98394a4be0e",
  "security.adapter_shadow_summary_v1()":"39af66f64cc8e16f1500df039227c636"}'; k text; v text;
begin
  for k, v in select * from jsonb_each_text(want) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v then raise exception 'live % differs from the definition this change replaces', k; end if;
  end loop;
  if not exists (select 1 from pipeline.layer3_model_profiles where code = 'openrouter-intake-l3c-mimo-v2-6-pro-v1' and enabled and not paused and retired_at is null)
    then raise exception 'the round 2 model profile is not enabled'; end if;
end $guard$;

alter table pipeline.adapter_shadow_reads add column if not exists round int not null default 1;
alter table pipeline.adapter_shadow_settings add column if not exists round int not null default 1;
alter table pipeline.adapter_shadow_settings add column if not exists model_profile_code text;
update pipeline.adapter_shadow_settings set round = 2, model_profile_code = 'openrouter-intake-l3c-mimo-v2-6-pro-v1',
  reason = 'Platform Admin 9 Oct 2026: round 2 with a stronger adapter model (MiMo v2.6 Pro); same contracts, checks and retire rule',
  updated_at = now() where id = 1;

create or replace function public.svc_adapter_shadow_claim(p_task text, p_limit int, p_worker text)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare s pipeline.adapter_shadow_settings; v_spent numeric; v_reads int; v_task_reads int; v_cap int; v_limit int;
        v_class text; v_items jsonb := '[]'::jsonb; r record; v_prof jsonb; v_tp jsonb; v_id uuid; v_l3 jsonb; v_l3_found boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_task not in ('intake','english','tuition') then raise exception 'task must be intake, english or tuition'; end if;
  v_class := case p_task when 'intake' then 'provider_intake_validation' when 'english' then 'provider_english_validation' else 'provider_current_tuition_validation' end;
  select * into s from pipeline.adapter_shadow_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('items', v_items, 'reason', 'shadow run switched off'); end if;
  perform pg_advisory_xact_lock(hashtext('adapter-shadow-claim'));
  -- a claim left by a lost worker is closed as an error after 30 minutes
  update pipeline.adapter_shadow_reads set status = 'error', errors = '["stale claim released"]'::jsonb, completed_at = now()
   where status = 'claimed' and claimed_at < now() - interval '30 minutes';
  -- spend counts every round today; the read limit counts the current round only
  select coalesce(sum(cost_usd), 0) into v_spent
    from pipeline.adapter_shadow_reads where claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  select count(*), count(*) filter (where task = p_task) into v_reads, v_task_reads
    from pipeline.adapter_shadow_reads where round = s.round and claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';
  if v_spent >= s.daily_usd_max then return jsonb_build_object('items', v_items, 'reason', format('daily spend limit: %s of %s USD', round(v_spent, 4), s.daily_usd_max)); end if;
  v_cap := s.daily_reads_max / 3;
  if v_task_reads >= v_cap or v_reads >= s.daily_reads_max then return jsonb_build_object('items', v_items, 'reason', format('daily read limit: %s of %s for %s', v_task_reads, v_cap, p_task)); end if;
  v_limit := greatest(1, least(coalesce(p_limit, 3), 10, v_cap - v_task_reads));
  -- tuition: the tuition task's own contract (prompt, checks, input length) with the adapter's model
  if p_task = 'tuition' then
    v_tp := (select to_jsonb(p) from pipeline.layer3_routed_profile(v_class) p where p.id is not null);
    if v_tp is null then return jsonb_build_object('items', v_items, 'reason', 'no routed tuition profile for the task contract'); end if;
  end if;
  for r in
    select w.id work_item_id, w.status l3_status, w.candidate_context, co.id course_id, co.provider_id, i.evidence_id, e.storage_path,
           e.source_url, e.mime_type, i.candidate_value, i.status i_status, i.estimated_cost_usd, to_jsonb(ua) adapter
      from pipeline.layer3_work_items w
      join pipeline.layer3_interpretations i on i.id = w.interpretation_id
      join pipeline.evidence_artifacts e on e.id = i.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id = w.entity_id
      join pipeline.uni_adapters ua on ua.provider_id = co.provider_id and ua.enabled
     where w.task_class = v_class and w.entity_type = 'course'
       and w.status in ('admitted','no_candidate','layer4_required','validated')
       and w.completed_at > now() - interval '30 days'
       and not exists (select 1 from pipeline.adapter_shadow_reads x where x.work_item_id = w.id)
     order by w.completed_at desc
     limit v_limit
  loop
    v_prof := (select to_jsonb(p) - 'prompt_system' - 'structured_output_schema' - 'deterministic_validators' - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                 from pipeline.layer3_model_profiles p
                where p.code = coalesce(s.model_profile_code, security.adapter_builder_model_for_v1(r.provider_id)->>'code')
                  and p.enabled and not p.paused and p.retired_at is null);
    if v_prof is null then continue; end if;
    if p_task = 'tuition' then
      -- the adapter's model and credential; the tuition task's prompt, checks and limits
      v_prof := v_tp - 'quality_benchmark' - 'holdout_qualification' - 'last_validation_result'
                || jsonb_build_object('id', v_prof->'id', 'code', v_prof->'code', 'model_identifier', v_prof->'model_identifier',
                                      'base_url', v_prof->'base_url', 'secret_env_key', v_prof->'secret_env_key', 'task_contract_profile', v_tp->'code');
      v_l3 := case when r.i_status <> 'provider_error' and security.adapter_shadow_found_v1('tuition', r.candidate_value) then r.candidate_value end;
      v_l3_found := v_l3 is not null;
    else
      v_l3 := case when r.i_status = 'validated' then r.candidate_value end;
      v_l3_found := r.i_status = 'validated' and security.adapter_shadow_found_v1(p_task, r.candidate_value);
    end if;
    insert into pipeline.adapter_shadow_reads(task, work_item_id, course_id, provider_id, evidence_id, profile_code, model, layer3_status,
           layer3_value, layer3_found, layer3_cost_usd, round)
    values (p_task, r.work_item_id, r.course_id, r.provider_id, r.evidence_id, v_prof->>'code', v_prof->>'model_identifier', r.l3_status,
           v_l3, v_l3_found, r.estimated_cost_usd, s.round)
    returning id into v_id;
    v_items := v_items || jsonb_build_object('shadow_id', v_id, 'course_id', r.course_id, 'provider_id', r.provider_id,
      'storage_path', r.storage_path, 'source_url', r.source_url, 'mime_type', r.mime_type,
      'context', case when p_task = 'tuition' then r.candidate_context end,
      'adapter', r.adapter - 'notes' - 'reason' - 'updated_by' - 'admit_reason', 'profile', v_prof);
  end loop;
  return jsonb_build_object('items', v_items, 'round', s.round, 'spent_today_usd', v_spent, 'reads_today', v_reads, 'worker', p_worker);
end $$;

-- per field, for the current round: compared reads, agreement where both found, how often each finds a value, cost; the
-- retire test; and each earlier round's figures for comparison
create or replace function security.adapter_shadow_summary_v1()
returns jsonb language sql stable set search_path to '' as $$
  with s as (select * from pipeline.adapter_shadow_settings where id = 1),
  d as (select * from pipeline.adapter_shadow_reads where status = 'done'),
  t as (
    select d.round, d.task, count(*) compared,
           count(*) filter (where d.shadow_found and d.layer3_found) both_found,
           count(*) filter (where d.agree) agree_n,
           count(*) filter (where d.shadow_found) shadow_found_n,
           count(*) filter (where d.layer3_found) layer3_found_n,
           count(*) filter (where d.shadow_found and not d.layer3_found) shadow_only,
           count(*) filter (where d.layer3_found and not d.shadow_found) layer3_only,
           round(sum(d.cost_usd), 4) shadow_cost_usd, round(sum(d.layer3_cost_usd), 4) layer3_cost_usd,
           round(avg(d.input_chars)) avg_input_chars,
           count(*) filter (where d.input_basis <> 'page') adapter_input_n
      from d group by d.round, d.task)
  select jsonb_build_object(
    'settings', (select to_jsonb(s) from s),
    'round', (select s.round from s),
    'today', (select jsonb_build_object('reads', count(*), 'cost_usd', round(coalesce(sum(cost_usd), 0), 4), 'errors', count(*) filter (where status = 'error'))
                from pipeline.adapter_shadow_reads where claimed_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'),
    'fields', coalesce((select jsonb_agg(jsonb_build_object(
        'task', t.task, 'compared', t.compared, 'both_found', t.both_found, 'agree_n', t.agree_n,
        'agreement', case when t.both_found > 0 then round(t.agree_n::numeric / t.both_found, 4) end,
        'shadow_found_rate', round(t.shadow_found_n::numeric / nullif(t.compared, 0), 4),
        'layer3_found_rate', round(t.layer3_found_n::numeric / nullif(t.compared, 0), 4),
        'shadow_only', t.shadow_only, 'layer3_only', t.layer3_only,
        'shadow_cost_usd', t.shadow_cost_usd, 'layer3_cost_usd', t.layer3_cost_usd,
        'avg_input_chars', t.avg_input_chars, 'adapter_input_n', t.adapter_input_n,
        'eligible_to_retire', t.compared >= s.min_compared and t.both_found > 0
            and t.agree_n::numeric / t.both_found >= s.retire_match and t.shadow_found_n >= t.layer3_found_n) order by t.task)
      from t, s where t.round = s.round), '[]'::jsonb),
    'earlier_rounds', coalesce((select jsonb_agg(jsonb_build_object('round', t.round, 'task', t.task, 'compared', t.compared, 'both_found', t.both_found,
        'agreement', case when t.both_found > 0 then round(t.agree_n::numeric / t.both_found, 4) end,
        'shadow_found_rate', round(t.shadow_found_n::numeric / nullif(t.compared, 0), 4),
        'layer3_found_rate', round(t.layer3_found_n::numeric / nullif(t.compared, 0), 4), 'shadow_cost_usd', t.shadow_cost_usd) order by t.round, t.task)
      from t, s where t.round < s.round), '[]'::jsonb))
$$;


revoke all on function public.svc_adapter_shadow_claim(text, int, text) from public, anon, authenticated;
grant execute on function public.svc_adapter_shadow_claim(text, int, text) to service_role;
revoke all on function security.adapter_shadow_summary_v1() from public, anon, authenticated;
