-- CF-247 Decision 253 (4 Oct 2026). University adapters read more than page data: text patterns, extra fields, and the
-- adapter's own readings are kept apart from the general reader's. Platform Admin, 21:50: Flinders shows its location and
-- delivery under the course offerings, its duration, English by course category at one central page, and start dates
-- that may come from a central or a campus calendar - "Prepare the adapter ... Help with adapter config".
--   * patterns: field to pattern on the page text (one bracketed part is the value), for intakes, fee, IELTS overall,
--     campus, mode, duration, study level, student type, not admitting and AQF level. pick: first, last or all matches
--     (a page with a domestic and an international view prints some fields twice).
--   * The worker (v0.16.0) marks a value read by the adapter's own pattern or page data (intakes_by, english_by, fee_by =
--     adapter) and keeps the extra fields (adapter_extra). They are shown for testing on the adapter panel.
--   * Admission. Intakes found by the adapter are admitted only when that adapter's admit switch is on, and only intakes
--     the adapter itself read (the general reader's intakes stay unadmitted, as before). English read by the adapter
--     likewise needs the admit switch. A new schedule (coverage-admit-intakes, every 10 minutes) admits intakes on that
--     basis. Every adapter's admit switch is off today, so nothing new is admitted until the Platform Admin tests the
--     adapter and switches it on. Tuition is still not admitted from pages.
-- No text value in this file contains a semicolon.

alter table pipeline.uni_adapters add column if not exists patterns jsonb not null default '{}'::jsonb;
alter table pipeline.uni_adapters add column if not exists pick jsonb not null default '{}'::jsonb;

create or replace function security.uni_adapter_pattern_fields() returns text[]
language sql immutable set search_path = '' as $f$
  select array['intakes', 'fee', 'ielts_overall', 'campus', 'mode', 'duration', 'study_level', 'student_type', 'not_admitting', 'aqf_level']
$f$;
revoke all on function security.uni_adapter_pattern_fields() from public, anon, authenticated;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.uni_adapter_json(uuid)'::regprocedure) is distinct from 'abb901f187655984ef77f2fde374e593' then
    raise exception 'uni_adapter_json changed, not replacing'; end if;
end $g$;
create or replace function security.uni_adapter_json(p_provider uuid) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('title_strip', a.title_strip, 'course_title_strip', a.course_title_strip, 'json_source', a.json_source, 'json_paths', a.json_paths,
                            'sections', a.sections, 'patterns', a.patterns, 'pick', a.pick, 'section_chars', a.section_chars, 'enabled', a.enabled, 'notes', a.notes, 'reason', a.reason, 'updated_at', a.updated_at)
  from pipeline.uni_adapters a where a.provider_id = p_provider
$f$;
revoke all on function security.uni_adapter_json(uuid) from public, anon, authenticated;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_write(text,jsonb)'::regprocedure) is distinct from 'a82ba44debd6906a8446a00d1e460fd1' then
    raise exception 'admin_uni_adapter_write changed, not replacing'; end if;
end $g$;
create or replace function public.admin_uni_adapter_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid; v_a jsonb := coalesce(p_args->'adapter', '{}'::jsonb);
        v_id uuid; k text; v text; v_before jsonb; v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
  if p_action in ('save', 'preview') then
    if jsonb_typeof(coalesce(v_a->'json_paths', '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(v_a->'sections', '{}'::jsonb)) <> 'object' then raise exception 'json_paths and sections must be field to text maps'; end if;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'sections', '{}'::jsonb)) x union all select 'title_strip', v_a->>'title_strip' union all select 'course_title_strip', v_a->>'course_title_strip' loop
      if not security.uni_adapter_pattern_ok(v) then raise exception 'the pattern for % cannot be read: %', k, v; end if;
    end loop;
    if jsonb_typeof(coalesce(v_a->'patterns', '{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(v_a->'pick', '{}'::jsonb)) <> 'object' then raise exception 'patterns and pick must be field to text maps'; end if;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'patterns', '{}'::jsonb)) x loop
      if k <> all (security.uni_adapter_pattern_fields()) then raise exception 'a pattern can only be set for: %', array_to_string(security.uni_adapter_pattern_fields(), ', '); end if;
      if not security.uni_adapter_pattern_ok(v) then raise exception 'the pattern for % cannot be read: %', k, v; end if;
    end loop;
    for k, v in select x.key, x.value from jsonb_each_text(coalesce(v_a->'pick', '{}'::jsonb)) x loop
      if v not in ('first', 'last', 'all') then raise exception 'pick for % must be first, last or all', k; end if;
    end loop;
    if coalesce(v_a->>'json_source', '') !~ '^[A-Za-z0-9_-]*$' then raise exception 'the JSON script id may only hold letters, digits, _ and -'; end if;
  end if;
  if p_action = 'save' then
    v_before := security.uni_adapter_json(v_pid);
    insert into pipeline.uni_adapters(provider_id, enabled, title_strip, course_title_strip, json_source, json_paths, sections, patterns, pick, section_chars, notes, reason, updated_by, updated_at)
      values (v_pid, coalesce((v_a->>'enabled')::boolean, false), nullif(btrim(v_a->>'title_strip'), ''), nullif(btrim(v_a->>'course_title_strip'), ''), nullif(btrim(v_a->>'json_source'), ''),
              coalesce(v_a->'json_paths', '{}'::jsonb), coalesce(v_a->'sections', '{}'::jsonb), coalesce(v_a->'patterns', '{}'::jsonb), coalesce(v_a->'pick', '{}'::jsonb), greatest(200, least(coalesce((v_a->>'section_chars')::int, 2000), 10000)), v_a->>'notes', v_reason, auth.uid(), now())
    on conflict (provider_id) do update set enabled = excluded.enabled, title_strip = excluded.title_strip, course_title_strip = excluded.course_title_strip, json_source = excluded.json_source, json_paths = excluded.json_paths, sections = excluded.sections, patterns = excluded.patterns, pick = excluded.pick, section_chars = excluded.section_chars, notes = excluded.notes, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now() where pipeline.uni_adapters.provider_id = excluded.provider_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_save', v_pid::text, jsonb_build_object('before', v_before, 'after', security.uni_adapter_json(v_pid), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'adapter', security.uni_adapter_json(v_pid));
  elsif p_action = 'preview' then
    insert into pipeline.uni_adapter_previews(provider_id, adapter, requested_by) values (v_pid, v_a, auth.uid()) returning id into v_id;
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_preview', 'preview_id', v_id));
    return jsonb_build_object('ok', true, 'preview_id', v_id);
  elsif p_action = 'apply' then
    if not exists (select 1 from pipeline.uni_adapters a where a.provider_id = v_pid and a.enabled) then raise exception 'save the adapter switched on first'; end if;
    v_n := security.uni_adapter_requeue_v1(v_pid, v_reason);
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_apply', v_pid::text, jsonb_build_object('adapter', security.uni_adapter_json(v_pid), 'pages_read_again', v_n, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_apply', 'provider_id', v_pid));
    return jsonb_build_object('ok', true, 'pages_read_again', v_n);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_uni_adapter_write(text, jsonb) from public, anon;
grant execute on function public.admin_uni_adapter_write(text, jsonb) to authenticated;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_adapter_page_record(uuid,text,text,jsonb)'::regprocedure) is distinct from '2207de5ed96031a99397539671580a95' then
    raise exception 'svc_adapter_page_record changed, not replacing'; end if;
end $g$;
create or replace function public.svc_adapter_page_record(p_course_id uuid, p_identity text, p_how text, p_candidates jsonb) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_pg pipeline.coverage_course_pages%rowtype; v_c jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_identity not in ('adapter_code', 'adapter_title') or p_candidates is null then return 'nothing'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = p_course_id;
  if v_pg.course_id is null or v_pg.evidence_id is null then return 'no_page'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  if v_pg.read_status = 'identity_mismatch' then
    update pipeline.coverage_course_pages set read_status = 'read', status = 'bound', identity_basis = p_identity, candidates = p_candidates || jsonb_build_object('final_url', v_pg.url), next_read_at = now() + interval '90 days' where course_id = p_course_id and read_status = 'identity_mismatch';
    update pipeline.search_pass_links set state = 'verified', updated_at = now() where course_id = p_course_id and bound_url = v_pg.url;
  elsif v_pg.read_status = 'read' and v_pg.identity_basis is not null then
    v_c := coalesce(v_pg.candidates, '{}'::jsonb);
    -- v0.16.0: the adapter's own reading (marked intakes_by, english_by, fee_by) replaces the general reader's
    if p_candidates->>'intakes_by' = 'adapter' and jsonb_array_length(coalesce(p_candidates->'intakes', '[]'::jsonb)) > 0 then v_c := v_c || jsonb_build_object('intakes', p_candidates->'intakes', 'intake_context', p_candidates->'intake_context', 'intakes_by', 'adapter');
    elsif jsonb_array_length(coalesce(v_c->'intakes', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(p_candidates->'intakes', '[]'::jsonb)) > 0 then v_c := v_c || jsonb_build_object('intakes', p_candidates->'intakes', 'intake_context', p_candidates->'intake_context'); end if;
    if p_candidates->>'english_by' = 'adapter' and p_candidates->'english' ? 'ielts_overall' then v_c := v_c || jsonb_build_object('english', p_candidates->'english', 'english_by', 'adapter');
    elsif coalesce(v_c->'english'->>'ielts_overall', v_c->'english'->>'pte_overall', v_c->'english'->>'toefl_overall') is null and coalesce(p_candidates->'english'->>'ielts_overall', p_candidates->'english'->>'pte_overall', p_candidates->'english'->>'toefl_overall') is not null then v_c := v_c || jsonb_build_object('english', p_candidates->'english'); end if;
    if p_candidates->>'fee_by' = 'adapter' and coalesce(p_candidates->'fee'->>'value', '') <> '' then v_c := v_c || jsonb_build_object('fee', p_candidates->'fee', 'fee_by', 'adapter');
    elsif coalesce(v_c->'fee'->>'value', '') = '' and coalesce(p_candidates->'fee'->>'value', '') <> '' then v_c := v_c || jsonb_build_object('fee', p_candidates->'fee'); end if;
    if p_candidates ? 'adapter_extra' then v_c := v_c || jsonb_build_object('adapter_extra', p_candidates->'adapter_extra'); end if;
    if v_c = coalesce(v_pg.candidates, '{}'::jsonb) then return 'no_new_field'; end if;
    update pipeline.coverage_course_pages set candidates = v_c || jsonb_build_object('adapter', true) where course_id = p_course_id;
  else
    return 'not_applicable';
  end if;
  insert into pipeline.uni_adapter_results(provider_id, course_id, before_read_status, before_identity, identity, how, fields)
    values (v_pg.provider_id, p_course_id, v_pg.read_status, v_pg.identity_basis, p_identity, p_how, jsonb_build_object('intakes', p_candidates->'intakes', 'intakes_by', p_candidates->'intakes_by', 'english', p_candidates->'english'->'ielts_overall', 'fee', p_candidates->'fee'->'value', 'extra', p_candidates->'adapter_extra'));
  return case when v_pg.read_status = 'identity_mismatch' then 'confirmed' else 'fields_added' end;
end $f$;
revoke all on function public.svc_adapter_page_record(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_adapter_page_record(uuid, text, text, jsonb) to service_role;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_review(uuid)'::regprocedure) is distinct from '2d1eeb434aea34e33515d55387341d61' then
    raise exception 'admin_uni_adapter_review changed, not replacing'; end if;
end $g$;
create or replace function public.admin_uni_adapter_review(p_provider_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'admit', (select jsonb_build_object('on', u.admit, 'reason', u.admit_reason, 'changed_at', u.admit_changed_at) from pipeline.uni_adapters u where u.provider_id = p_provider_id),
    'confirmed', coalesce((select jsonb_agg(x) from (
        select jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'url', pg.url, 'identity', pg.identity_basis,
                                  'intakes', pg.candidates->'intakes', 'ielts', pg.candidates->'english'->'ielts_overall', 'english_context', left(pg.candidates->'english'->>'context', 160),
                                  'link_admitted', exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.url = pg.url and l.status = 'active'),
                                  'english_admitted', exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and e.evidence_id = pg.evidence_id and coalesce(e.status, 'active') = 'active')) x
        from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
        where pg.provider_id = p_provider_id and pg.identity_basis in ('adapter_code', 'adapter_title') and pg.read_status = 'read'
        order by pg.read_at desc nulls last limit 40) q), '[]'::jsonb),
    'confirmed_total', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = p_provider_id and pg.identity_basis in ('adapter_code', 'adapter_title') and pg.read_status = 'read'),
    -- v0.16.0: what the adapter read on pages confirmed another way (CRICOS code on the page): its own readings and the
    -- extra fields, and whether an intake would be admitted (only with the admit switch on)
    'readings', coalesce((select jsonb_agg(x) from (
        select jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'url', pg.url, 'identity', pg.identity_basis,
                                  'intakes', pg.candidates->'intakes', 'intakes_by', pg.candidates->>'intakes_by', 'intake_context', pg.candidates->'intake_context'->>0,
                                  'fee', pg.candidates->'fee'->'value', 'fee_by', pg.candidates->>'fee_by', 'ielts', pg.candidates->'english'->'ielts_overall', 'english_by', pg.candidates->>'english_by',
                                  'extra', pg.candidates->'adapter_extra',
                                  'intakes_now', (select jsonb_agg(i.intake_label) from catalogue.course_intakes i where i.course_id = c.id and coalesce(i.status, 'active') = 'active')) x
        from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
        where pg.provider_id = p_provider_id and pg.read_status = 'read' and (pg.candidates ? 'intakes_by' or pg.candidates ? 'adapter_extra' or pg.candidates ? 'fee_by' or pg.candidates ? 'english_by')
        order by pg.read_at desc nulls last limit 60) q), '[]'::jsonb),
    'readings_total', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = p_provider_id and pg.read_status = 'read' and (pg.candidates ? 'intakes_by' or pg.candidates ? 'adapter_extra' or pg.candidates ? 'fee_by' or pg.candidates ? 'english_by')),
    'intakes_by_adapter', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.candidates->>'intakes_by' = 'adapter'),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'request', r.request, 'status', r.status, 'answer', r.answer, 'requested_at', r.requested_at, 'answered_at', r.answered_at) order by r.requested_at desc) from pipeline.uni_adapter_requests r where r.provider_id = p_provider_id), '[]'::jsonb)
  );
end $f$;
revoke all on function public.admin_uni_adapter_review(uuid) from public, anon;
grant execute on function public.admin_uni_adapter_review(uuid) to authenticated;

-- The admission plan: intakes only from the adapter's own reading with its admit switch on, English read by an adapter
-- only with its admit switch on. md5-guarded, each snippet must be found exactly once, the rest of the function unchanged.
do $p$
declare v_def text := pg_get_functiondef('security.coverage_admission_plan_v1(text)'::regprocedure);
        v_old1 text := $s$from pg where jsonb_array_length(coalesce(pg.c->'intakes','[]'))>0 and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'intakes')),$s$;
        v_new1 text := $s$from pg where jsonb_array_length(coalesce(pg.c->'intakes','[]'))>0 and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'intakes') and pg.c->>'intakes_by'='adapter' and exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit)),$s$;
        v_old2 text := $s$from pg where pg.c->'english' ?| array['ielts_overall','pte_overall','toefl_overall'] and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'english')),$s$;
        v_new2 text := $s$from pg where pg.c->'english' ?| array['ielts_overall','pte_overall','toefl_overall'] and security.coverage_identity_allowed(pg.provider_id, pg.ib, 'english') and (coalesce(pg.c->>'english_by','')<>'adapter' or exists (select 1 from pipeline.uni_adapters u where u.provider_id=pg.provider_id and u.enabled and u.admit))),$s$;
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.coverage_admission_plan_v1(text)'::regprocedure) is distinct from '2043cdcd8cf89b27c83197a6d11f6ca9' then
    raise exception 'coverage_admission_plan_v1 changed, not replacing'; end if;
  if (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1) <> 1 then raise exception 'intakes snippet not found exactly once'; end if;
  if (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2) <> 1 then raise exception 'english snippet not found exactly once'; end if;
  execute replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
end $p$;

select cron.schedule('coverage-admit-intakes', '*/10 * * * *', $c$select security.coverage_admission_apply_v1(300, 'coverage-sweep-v0.5.6', array['intakes'])$c$);
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values ('coverage-admit-intakes', 2, now()) on conflict (jobname) do nothing;
