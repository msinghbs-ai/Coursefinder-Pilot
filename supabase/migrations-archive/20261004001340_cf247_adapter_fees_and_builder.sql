-- CF-247 Decision 254 (4 Oct 2026, Platform Admin 23:41).
--   * Fees: the international annual fee an admitting adapter reads itself (fee_by = adapter) is admitted, and replaces
--     the held fee of the same year from automatic sources. A fee entered or locked by hand is never changed. Whole-course
--     fees still go to Layer 4. Logged in pipeline.adapter_overwrite_changes.
--   * The visual adapter builder: drafts (sample pages, Firecrawl screenshots in the private bucket adapter-captures,
--     the Platform Admin's marks and comments, the model's proposals and their output on the samples). The model is the
--     preferred cheapest vetted one, pinned by name in settings, with a daily allowance in US dollars and in proposals.
--     A proposal only fills the adapter form. Saving, applying and admission stay Platform Admin actions.
-- No text value in this file contains a semicolon.

insert into storage.buckets(id, name, public) values ('adapter-captures', 'adapter-captures', false) on conflict (id) do nothing;

create table if not exists pipeline.uni_adapter_drafts (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null,
  status text not null default 'capturing',
  samples jsonb not null default '[]'::jsonb,
  captures jsonb not null default '[]'::jsonb,
  marks jsonb not null default '[]'::jsonb,
  comments text,
  proposals jsonb not null default '[]'::jsonb,
  model text,
  model_profile text,
  cost_usd numeric not null default 0,
  reason text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists uni_adapter_drafts_provider on pipeline.uni_adapter_drafts(provider_id, created_at desc);
alter table pipeline.uni_adapter_drafts enable row level security;
revoke all on pipeline.uni_adapter_drafts from anon, authenticated;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('firecrawl', 'builder_model', 'Model that proposes adapters', 'The one model the adapter builder asks, pinned by name (the preferred cheapest vetted model). No automatic routing.', 'text', '"qwen/qwen3-30b-a3b-instruct-2507"', null, null, null, 500, 'Decision 254, Platform Admin 23:41', 'Adapter builder'),
  ('firecrawl', 'builder_model_profile', 'Its Models and services profile', 'The Layer 3 profile that holds this model''s credential.', 'text', '"openrouter-intake-l3c-qwen3-30b-a3b-2507-v1"', null, null, null, 510, 'Decision 254, Platform Admin 23:41', 'Adapter builder'),
  ('firecrawl', 'builder_ai_daily_usd', 'AI allowance a day', 'The most the adapter builder may spend on model proposals in a day (Melbourne time).', 'number', '0.5', 0, 20, 'US$', 520, 'Decision 254, Platform Admin 23:41', 'Adapter builder'),
  ('firecrawl', 'builder_proposals_per_day', 'Proposals a day', 'The most model proposals the adapter builder may ask for in a day.', 'number', '30', 0, 500, 'calls', 530, 'Decision 254, Platform Admin 23:41', 'Adapter builder'),
  ('firecrawl', 'builder_samples', 'Sample pages', 'How many course pages the builder captures for a university (Firecrawl, about 1 credit each with the screenshot).', 'number', '3', 1, 6, 'pages', 540, 'Decision 254, Platform Admin 23:41', 'Adapter builder')
on conflict (toolset_key, key) do nothing;

create or replace function security.adapter_builder_budget() returns jsonb
language sql stable security definer set search_path = '' as $f$
  with today as (select (now() at time zone 'Australia/Melbourne')::date d),
  rounds as (select (p->>'cost')::numeric cost from pipeline.uni_adapter_drafts dr cross join lateral jsonb_array_elements(dr.proposals) p, today
             where ((p->>'at')::timestamptz at time zone 'Australia/Melbourne')::date = today.d)
  select jsonb_build_object('used_usd', coalesce((select sum(cost) from rounds), 0), 'proposals', (select count(*) from rounds),
                            'limit_usd', coalesce((security.firecrawl_setting('builder_ai_daily_usd') #>> '{}')::numeric, 0.5),
                            'limit_proposals', coalesce((security.firecrawl_setting('builder_proposals_per_day') #>> '{}')::int, 30),
                            'model', security.firecrawl_setting('builder_model') #>> '{}')
$f$;
revoke all on function security.adapter_builder_budget() from public, anon, authenticated;

create or replace function public.admin_adapter_builder(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_id uuid; v_d pipeline.uni_adapter_drafts%rowtype; v_n int; v_b jsonb; v_samples jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object('budget', security.adapter_builder_budget(), 'can_manage', v_rank >= 6,
      'drafts', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from (select * from pipeline.uni_adapter_drafts where provider_id = v_pid order by created_at desc limit 3) d), '[]'::jsonb));
  end if;
  if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'start' then
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    v_n := coalesce((security.firecrawl_setting('builder_samples') #>> '{}')::int, 3);
    select coalesce(jsonb_agg(jsonb_build_object('course_id', x.course_id, 'course', x.title, 'code', x.code, 'url', x.url, 'kind', x.kind) order by x.rk), '[]'::jsonb) into v_samples from (
      select distinct on (q.kind) q.*, row_number() over (order by q.kind) rk from (
        select pg.course_id, coalesce(c.display_title, c.canonical_title) title, (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code, pg.url,
               case when coalesce(c.display_title, c.canonical_title) ~* '/|, bachelor|and bachelor|double' then 'double' when coalesce(c.display_title, c.canonical_title) ~* 'master|graduate|doctor|postgrad' then 'postgraduate' else 'undergraduate' end kind
          from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status = 'active'
         where pg.provider_id = v_pid and pg.read_status = 'read' and pg.url is not null order by random()) q order by q.kind limit greatest(1, v_n)) x;
    if jsonb_array_length(coalesce(v_samples, '[]'::jsonb)) = 0 then raise exception 'no confirmed course page for this university yet - find pages first'; end if;
    insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, v_samples, v_reason, auth.uid()) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_start', v_pid::text, jsonb_build_object('draft_id', v_id, 'samples', v_samples, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  select * into v_d from pipeline.uni_adapter_drafts where id = (p_args->>'draft_id')::uuid;
  if v_d.id is null then raise exception 'unknown draft'; end if;
  if p_action = 'marks' then
    if jsonb_typeof(coalesce(p_args->'marks', '[]'::jsonb)) <> 'array' then raise exception 'marks must be a list'; end if;
    update pipeline.uni_adapter_drafts set marks = coalesce(p_args->'marks', '[]'::jsonb), comments = left(coalesce(p_args->>'comments', ''), 4000), updated_at = now() where id = v_d.id;
    return jsonb_build_object('ok', true);
  elsif p_action = 'propose' then
    if jsonb_array_length(v_d.captures) = 0 then raise exception 'capture the sample pages first'; end if;
    v_b := security.adapter_builder_budget();
    if (v_b->>'used_usd')::numeric >= (v_b->>'limit_usd')::numeric then raise exception 'the AI allowance for today is used (US$ % of %). It is a setting under Adapter builder', v_b->>'used_usd', v_b->>'limit_usd'; end if;
    if (v_b->>'proposals')::int >= (v_b->>'limit_proposals')::int then raise exception 'the proposals for today are used (% of %). It is a setting under Adapter builder', v_b->>'proposals', v_b->>'limit_proposals'; end if;
    update pipeline.uni_adapter_drafts set status = 'proposing', marks = coalesce(p_args->'marks', marks), comments = coalesce(left(p_args->>'comments', 4000), comments), model = security.firecrawl_setting('builder_model') #>> '{}', model_profile = security.firecrawl_setting('builder_model_profile') #>> '{}', updated_at = now() where id = v_d.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_propose', v_d.provider_id::text, jsonb_build_object('draft_id', v_d.id, 'budget', v_b), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_propose', 'draft_id', v_d.id));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_adapter_builder(text, jsonb) from public, anon;
grant execute on function public.admin_adapter_builder(text, jsonb) to authenticated;

create or replace function public.svc_adapter_draft_get(p_draft_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select to_jsonb(d) || jsonb_build_object('provider_name', coalesce(p.display_name, p.canonical_name), 'country', security.coverage_country(d.provider_id))
            from pipeline.uni_adapter_drafts d join catalogue.providers p on p.id = d.provider_id where d.id = p_draft_id);
end $f$;
revoke all on function public.svc_adapter_draft_get(uuid) from public, anon, authenticated;
grant execute on function public.svc_adapter_draft_get(uuid) to service_role;

create or replace function public.svc_adapter_draft_record(p_draft_id uuid, p_kind text, p_data jsonb, p_cost numeric, p_model text) returns text
language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_kind = 'capture' then
    update pipeline.uni_adapter_drafts set captures = coalesce(p_data->'captures', '[]'::jsonb), status = 'captured', updated_at = now() where id = p_draft_id;
  elsif p_kind in ('proposal', 'error') then
    update pipeline.uni_adapter_drafts set proposals = proposals || jsonb_build_array(p_data || jsonb_build_object('at', now(), 'kind', p_kind, 'model', p_model, 'cost', coalesce(p_cost, 0))), cost_usd = cost_usd + coalesce(p_cost, 0), status = case when p_kind = 'proposal' then 'proposed' else 'error' end, updated_at = now() where id = p_draft_id;
  else
    return 'unknown';
  end if;
  return 'ok';
end $f$;
revoke all on function public.svc_adapter_draft_record(uuid, text, jsonb, numeric, text) from public, anon, authenticated;
grant execute on function public.svc_adapter_draft_record(uuid, text, jsonb, numeric, text) to service_role;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.adapter_overwrite_v1(int)'::regprocedure) is distinct from 'd6bc6366ca49095f401718a423ef4f77' then
    raise exception 'adapter_overwrite_v1 changed, not replacing'; end if;
end $g$;
create or replace function security.adapter_overwrite_v1(p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_src uuid; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}'; v_payload jsonb; v_itk text[]; v_ielts numeric; v_band numeric; v_fee numeric; v_fy int; v_cur text;
begin
  for r in
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, e.content_hash, pg.candidates c, pg.identity_basis ib,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id = pg.provider_id and lower(pr.registration_scheme) = 'cricos' and coalesce(pr.status, 'active') not in ('inactive', 'cancelled', 'archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) cc,
           (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') cur_itk,
           (select r2.overall_score from catalogue.course_english_requirements r2 join ref.english_tests t on t.id = r2.english_test_id where r2.course_id = pg.course_id and t.code = 'IELTS' and coalesce(r2.status, 'active') = 'active' limit 1) cur_ielts,
           (select f.amount from catalogue.course_fees f where f.course_id = pg.course_id and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international' order by f.fee_year desc nulls last limit 1) cur_fee
      from pipeline.coverage_course_pages pg
      join pipeline.evidence_artifacts e on e.id = pg.evidence_id
      join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
      join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled and u.admit
     where pg.read_status = 'read' and pg.identity_basis is not null
       and (pg.candidates->>'intakes_by' = 'adapter' or pg.candidates->>'english_by' = 'adapter' or pg.candidates->>'fee_by' = 'adapter')
       and security.coverage_identity_allowed(pg.provider_id, pg.identity_basis, null)
       and not security.layer4_entity_or_parent_blocked('course', pg.course_id, 'operational')
  loop
    exit when v_ok >= greatest(1, least(coalesce(p_limit, 200), 1000));
    v_payload := '{}'::jsonb;
    v_itk := (select array_agg(distinct m order by m) from jsonb_array_elements_text(coalesce(r.c->'intakes', '[]'::jsonb)) m);
    if r.c->>'intakes_by' = 'adapter' and v_itk is not null and r.cur_itk is distinct from v_itk
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'intakes')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('intakes', 'intake')) then
      v_payload := v_payload || jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', m, 'source_intake_key', lower(coalesce(r.cc, r.course_id::text)) || ':current:' || lower(m))) from unnest(v_itk) m));
    end if;
    v_ielts := nullif(r.c->'english'->>'ielts_overall', '')::numeric;
    v_band := nullif(r.c->'english'->>'ielts_min_band', '')::numeric;
    if r.c->>'english_by' = 'adapter' and v_ielts is not null and r.cur_ielts is distinct from v_ielts
       and security.coverage_identity_allowed(r.provider_id, r.ib, 'english')
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('english', 'english_requirements')) then
      v_payload := v_payload || jsonb_build_object('english_requirements', jsonb_build_array(jsonb_build_object('test_code', 'IELTS', 'overall_score', v_ielts,
                      'component_scores', case when v_band is null then '{}'::jsonb else jsonb_build_object('listening', v_band, 'reading', v_band, 'writing', v_band, 'speaking', v_band) end,
                      'notes', 'University adapter reading of the course page')));
    end if;
    -- v0.17 (Platform Admin 23:41, decision 4): the international annual fee the adapter read is admitted too
    v_fee := nullif(r.c->'fee'->>'value', '')::numeric;
    v_fy := nullif(r.c->'fee'->>'fee_year', '')::int;
    v_cur := coalesce(nullif(r.c->'fee'->>'currency', ''), case security.coverage_country(r.provider_id) when 'NZ' then 'NZD' when 'CA' then 'CAD' else 'AUD' end);
    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_fee between 1000 and 500000 and r.cur_fee is distinct from v_fee
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('tuition', 'fee', 'fees')) then
      v_payload := v_payload || jsonb_build_object('fee_amount', v_fee, 'fee_year', v_fy, 'currency_code', v_cur, 'fee_basis', 'annual', 'audience', 'international',
                     'fee_notes', 'University adapter reading of the course page (international annual fee)',
                     'fee_key', lower(coalesce(r.cc, r.course_id::text)) || ':international:' || coalesce(v_fy::text, 'current') || ':annual');
    end if;
    continue when v_payload = '{}'::jsonb;
    begin
      v_src := security.coverage_sweep_source(r.provider_id);
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
        select 'courses', d, v_src, 'approved', 'CF-CHG-20260915-247, Decision 253, Platform Admin 4 Oct 2026 22:43 (adapter readings replace held values)', now(), now(), now()
        from unnest(array_remove(array[case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'provider_current_tuition' end], null)) d
        where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = d and g.source_id = v_src);
      if v_payload ? 'intakes' then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'intakes', to_jsonb(r.cur_itk), to_jsonb(v_itk), r.evidence_id, r.url);
      end if;
      if v_payload ? 'english_requirements' then
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'english_ielts', to_jsonb(r.cur_ielts), to_jsonb(v_ielts), r.evidence_id, r.url);
      end if;
      if v_payload ? 'fee_amount' then
        update catalogue.course_fees set status = 'superseded', updated_at = now() where course_id = r.course_id and status = 'active' and fee_type = 'provider_current_tuition' and audience = 'international' and source_id is not null and coalesce(fee_year, 0) = coalesce(v_fy, 0) and amount <> v_fee;
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'fee', to_jsonb(r.cur_fee), jsonb_build_object('amount', v_fee, 'year', v_fy, 'currency', v_cur), r.evidence_id, r.url);
      end if;
      if r.pc is null or r.cc is null then
        perform security.coverage_apply_course_v1(r.course_id, v_src, r.evidence_id, r.url, r.content_hash, v_payload);
      else
        perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'coverage:' || r.course_id, r.url, r.content_hash, v_payload, true);
      end if;
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where entity_type = 'course' and entity_id = r.course_id and status = 'pending' and field_code in (case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end, case when v_payload ? 'fee_amount' then 'course_tuition' end);
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('replaced', v_ok, 'errors', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.adapter_overwrite_v1(int) from public, anon, authenticated;
