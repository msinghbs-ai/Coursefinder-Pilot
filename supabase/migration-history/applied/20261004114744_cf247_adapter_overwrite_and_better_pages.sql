-- CF-247 Decision 253 (4 Oct 2026, Platform Admin 22:43). Three decisions:
--   1. Admit from the Flinders adapter (switched on separately, with the reason, after this migration).
--   2. "adapter is exact auto read and can overwrite all except manual ones". When a university adapter is switched on
--      and admitting, what it read itself (intakes_by or english_by = adapter) replaces the held value: intakes not on
--      the page are withdrawn and the page's months written, and the IELTS score is replaced. A value a person entered
--      or locked is never touched (manual locks, and intakes with no source). Every change is logged in
--      pipeline.adapter_overwrite_changes, and review items that asked about the same field are marked superseded.
--      Schedule adapter-overwrite, every 10 minutes.
--   3. Find better pages with Firecrawl: a run for one university's courses whose confirmed page lacks the fields its
--      adapter reads (Flinders: handbook pages, while intakes and fees are on the study pages). The search wording and
--      the page pattern are the run's own. Only a result matching the pattern replaces the page, never a page entered by hand.
-- No text value in this file contains a semicolon.

create table if not exists pipeline.adapter_overwrite_changes (
  id bigserial primary key,
  course_id uuid not null,
  provider_id uuid not null,
  field text not null,
  before jsonb,
  after jsonb,
  evidence_id uuid,
  page_url text,
  at timestamptz not null default now()
);
alter table pipeline.adapter_overwrite_changes enable row level security;
revoke all on pipeline.adapter_overwrite_changes from anon, authenticated;

create or replace function security.adapter_overwrite_v1(p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_src uuid; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}'; v_payload jsonb; v_itk text[]; v_ielts numeric; v_band numeric;
begin
  for r in
    select pg.course_id, pg.provider_id, pg.url, pg.evidence_id, e.content_hash, pg.candidates c, pg.identity_basis ib,
           (select pr.registration_code from catalogue.provider_registrations pr where pr.provider_id = pg.provider_id and lower(pr.registration_scheme) = 'cricos' and coalesce(pr.status, 'active') not in ('inactive', 'cancelled', 'archived') order by pr.checked_at desc nulls last limit 1) pc,
           (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) cc,
           (select array_agg(distinct i.intake_label order by i.intake_label) from catalogue.course_intakes i where i.course_id = pg.course_id and i.status = 'active') cur_itk,
           (select r2.overall_score from catalogue.course_english_requirements r2 join ref.english_tests t on t.id = r2.english_test_id where r2.course_id = pg.course_id and t.code = 'IELTS' and coalesce(r2.status, 'active') = 'active' limit 1) cur_ielts
      from pipeline.coverage_course_pages pg
      join pipeline.evidence_artifacts e on e.id = pg.evidence_id
      join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
      join pipeline.uni_adapters u on u.provider_id = pg.provider_id and u.enabled and u.admit
     where pg.read_status = 'read' and pg.identity_basis is not null
       and (pg.candidates->>'intakes_by' = 'adapter' or pg.candidates->>'english_by' = 'adapter')
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
    continue when v_payload = '{}'::jsonb;
    begin
      v_src := security.coverage_sweep_source(r.provider_id);
      insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
        select 'courses', d, v_src, 'approved', 'CF-CHG-20260915-247, Decision 253, Platform Admin 4 Oct 2026 22:43 (adapter readings replace held values)', now(), now(), now()
        from unnest(array_remove(array[case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end], null)) d
        where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = d and g.source_id = v_src);
      if v_payload ? 'intakes' then
        update catalogue.course_intakes set status = 'withdrawn' where course_id = r.course_id and status = 'active' and source_id is not null and intake_label <> all (v_itk);
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'intakes', to_jsonb(r.cur_itk), to_jsonb(v_itk), r.evidence_id, r.url);
      end if;
      if v_payload ? 'english_requirements' then
        insert into pipeline.adapter_overwrite_changes(course_id, provider_id, field, before, after, evidence_id, page_url) values (r.course_id, r.provider_id, 'english_ielts', to_jsonb(r.cur_ielts), to_jsonb(v_ielts), r.evidence_id, r.url);
      end if;
      if r.pc is null or r.cc is null then
        perform security.coverage_apply_course_v1(r.course_id, v_src, r.evidence_id, r.url, r.content_hash, v_payload);
      else
        perform public.svc_coursefacts_apply_record(v_src, r.evidence_id, r.pc, r.cc, 'coverage:' || r.course_id, r.url, r.content_hash, v_payload, true);
      end if;
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where entity_type = 'course' and entity_id = r.course_id and status = 'pending' and field_code in (case when v_payload ? 'intakes' then 'course_intake' end, case when v_payload ? 'english_requirements' then 'course_english' end);
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then perform search.refresh_course_enrichment_scoped_v1(v_courses, true); end if;
  return jsonb_build_object('replaced', v_ok, 'errors', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.adapter_overwrite_v1(int) from public, anon, authenticated;

select cron.schedule('adapter-overwrite', '*/10 * * * *', $c$select security.adapter_overwrite_v1(200)$c$);
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values ('adapter-overwrite', 2, now()) on conflict (jobname) do nothing;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_fc_find_bind(uuid,jsonb)'::regprocedure) is distinct from '151e73570a4ce33435647073a8047d4b' then
    raise exception 'svc_fc_find_bind changed, not replacing'; end if;
end $g$;
create or replace function public.svc_fc_find_bind(p_item_id uuid, p_candidates jsonb) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_i pipeline.firecrawl_run_items%rowtype; v_c jsonb := coalesce(p_candidates, '[]'::jsonb); v_url text; v_pg pipeline.coverage_course_pages%rowtype; v_up boolean; v_pat text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_i from pipeline.firecrawl_run_items where id = p_item_id;
  if v_i.id is null or v_i.course_id is null then return 'no_course'; end if;
  if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) = 0 then return 'no_candidate'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = v_i.course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = v_i.course_id;
  -- Decision 253 (Platform Admin 22:43): a better page for a course whose page is confirmed but lacks the fields (the
  -- university adapter reads them on another kind of page). Only a result matching the run's page pattern is taken.
  v_up := coalesce((v_i.input->>'upgrade')::boolean, false) and coalesce(v_i.input->>'upgrade_pattern', '') <> '';
  if v_up then
    v_pat := v_i.input->>'upgrade_pattern';
    select x.u into v_url from jsonb_array_elements_text(v_c) with ordinality x(u, n) where x.u ~* v_pat order by x.n limit 1;
    if v_url is null then return 'no_better_page'; end if;
    if v_pg.course_id is not null and v_pg.url = v_url then return 'same_page'; end if;
    insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason, run_id)
      values (v_i.course_id, v_i.provider_id, v_pg.url, v_url, 'firecrawl search: page with the fields the adapter reads', v_i.run_id);
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
      values (v_i.course_id, v_i.provider_id, v_url, 'firecrawl_upgrade', 'bound', now(), now(), 0)
    on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(), score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now() where pipeline.coverage_course_pages.course_id = excluded.course_id;
    insert into pipeline.search_pass_links(course_id, provider_id, run_id, candidates, cand_idx, bound_url, refind, state, updated_at, engine)
      values (v_i.course_id, v_i.provider_id, v_i.run_id, v_c, 1, v_url, true, 'found', now(), 'firecrawl')
    on conflict (course_id) do update set run_id = excluded.run_id, candidates = excluded.candidates, cand_idx = excluded.cand_idx, bound_url = excluded.bound_url, refind = excluded.refind, state = 'found', updated_at = now(), engine = 'firecrawl' where pipeline.search_pass_links.course_id = excluded.course_id;
    return 'bound';
  end if;
  if v_pg.course_id is not null and v_pg.status in ('bound', 'ambiguous') and not (v_pg.evidence_id is null and v_pg.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin') and coalesce((v_i.input->>'refind')::boolean, false)) then return 'page_already_bound'; end if;
  v_url := v_c->>0;
  if v_pg.course_id is not null and v_pg.url = v_url then
    if jsonb_array_length(v_c) < 2 then return 'already_refused'; end if;
    v_url := v_c->>1;
  end if;
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason, run_id)
    values (v_i.course_id, v_i.provider_id, v_pg.url, v_url, case when coalesce((v_i.input->>'refind')::boolean, false) then 'firecrawl search: better page for an unreadable one' else 'firecrawl search: page found' end, v_i.run_id);
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (v_i.course_id, v_i.provider_id, v_url, 'firecrawl_search', 'bound', now(), now(), 0)
  on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(), score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now() where pipeline.coverage_course_pages.status not in ('bound', 'ambiguous') or (pipeline.coverage_course_pages.evidence_id is null and pipeline.coverage_course_pages.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin'));
  insert into pipeline.search_pass_links(course_id, provider_id, run_id, candidates, cand_idx, bound_url, refind, state, updated_at, engine)
    values (v_i.course_id, v_i.provider_id, v_i.run_id, v_c, case when v_url = v_c->>0 then 1 else 2 end, v_url, coalesce((v_i.input->>'refind')::boolean, false), 'found', now(), 'firecrawl')
  on conflict (course_id) do update set run_id = excluded.run_id, candidates = excluded.candidates, cand_idx = excluded.cand_idx, bound_url = excluded.bound_url, refind = excluded.refind, state = 'found', updated_at = now(), engine = 'firecrawl' where pipeline.search_pass_links.course_id = excluded.course_id;
  return 'bound';
end $f$;
revoke all on function public.svc_fc_find_bind(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_fc_find_bind(uuid, jsonb) to service_role;

-- A Firecrawl run that looks for a better page for one university's courses (logged, capped, Firecrawl reserve kept).
create or replace function security.firecrawl_upgrade_run_v1(p_provider_id uuid, p_query text, p_page_pattern text, p_cap numeric, p_reason text, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_settings jsonb; v_run uuid; v_n int; v_budget jsonb; v_domain text;
begin
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if not security.uni_adapter_pattern_ok(p_page_pattern) or coalesce(p_page_pattern, '') = '' then raise exception 'the page pattern cannot be read'; end if;
  if exists (select 1 from pipeline.firecrawl_runs r where r.use_case = 'find_page' and r.status = 'running') then raise exception 'a Find pages run is still open. Let it finish or stop it first'; end if;
  v_budget := security.layer2_provider_budget_status((select p.id from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl'), 1);
  if not coalesce((v_budget->>'allowed')::boolean, false) then raise exception 'Firecrawl is at its reserve'; end if;
  select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) into v_settings from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl';
  v_settings := v_settings || jsonb_build_object('find_query', to_jsonb(p_query));
  v_domain := (select c.domain from pipeline.firecrawl_target_cache c where c.provider_id = p_provider_id);
  insert into pipeline.firecrawl_runs(use_case, settings, reason, requested_by, credits_cap) values ('find_page', v_settings, p_reason, p_actor, p_cap) returning id into v_run;
  insert into pipeline.firecrawl_run_items(run_id, course_id, provider_id, country, url, input)
    select v_run, pg.course_id, pg.provider_id, k.iso_alpha2::text, null,
           jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'provider', coalesce(p.display_name, p.canonical_name), 'domain', v_domain,
                              'upgrade', true, 'upgrade_pattern', p_page_pattern, 'earlier_url', pg.url, 'earlier_status', pg.read_status, 'refind', true)
      from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status = 'active'
      join catalogue.providers p on p.id = pg.provider_id join ref.countries k on k.id = p.country_id
     where pg.provider_id = p_provider_id and pg.url !~* p_page_pattern
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = pg.course_id and l.field = 'official_url')
     order by pg.course_id;
  get diagnostics v_n = row_count;
  update pipeline.firecrawl_runs set items = v_n, status = case when v_n = 0 then 'done' else 'running' end, finished_at = case when v_n = 0 then now() end where id = v_run;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_run_start', 'find_page', jsonb_build_object('run_id', v_run, 'items', v_n, 'credits_cap', p_cap, 'upgrade_pattern', p_page_pattern, 'query', p_query, 'provider_id', p_provider_id, 'reason', p_reason), p_actor);
  if v_n > 0 then perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', v_run)); end if;
  return jsonb_build_object('run_id', v_run, 'items', v_n);
end $f$;
revoke all on function security.firecrawl_upgrade_run_v1(uuid, text, text, numeric, text, uuid) from public, anon, authenticated;
