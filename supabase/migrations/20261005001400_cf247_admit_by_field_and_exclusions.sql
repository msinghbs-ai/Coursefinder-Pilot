-- CF-247 Decision 254 (5 Oct 2026). Admission by field and course exclusions (Platform Admin 05:50 "switch on the admissions").
-- Waves 3 and 4 showed universities where one field is right and another is not yet (Griffith fees and IELTS right, intakes
-- waiting on a term check), and single courses whose page reading is wrong (Massey and Charles Darwin short-course totals,
-- a James Cook Singapore fee, a Lincoln domestic fee). The one admit switch covered every field of every course.
--   * pipeline.uni_adapters.admit_fields: the fields admitted when admission is on (intakes, english, fee). Adapters already
--     admitting keep all three.
--   * pipeline.uni_adapter_exclusions: a course and field the adapter must not admit, with a reason. Switched off, not removed.
--   * admin_uni_adapter_control: admit takes an optional fields list, new action exclude.
--   * The overwrite, the country identity rule and the page record honour both.
-- md5-guarded. Snippet patches are each found exactly once. No text value in this file contains a semicolon.

alter table pipeline.uni_adapters add column if not exists admit_fields text[] not null default array['english', 'fee', 'intakes'];

create table if not exists pipeline.uni_adapter_exclusions (
  course_id uuid not null references catalogue.courses(id),
  field text not null check (field in ('intakes', 'english', 'fee')),
  provider_id uuid not null references catalogue.providers(id),
  active boolean not null default true,
  reason text not null,
  set_by uuid,
  set_at timestamptz not null default now(),
  primary key (course_id, field)
);
alter table pipeline.uni_adapter_exclusions enable row level security;
revoke all on pipeline.uni_adapter_exclusions from anon, authenticated;

create or replace function security.uni_adapter_excluded(p_course_id uuid, p_field text) returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from pipeline.uni_adapter_exclusions x where x.course_id = p_course_id and x.field = p_field and x.active)
$f$;
revoke all on function security.uni_adapter_excluded(uuid, text) from public, anon, authenticated;

do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_adapter_page_record(uuid,text,text,jsonb)'::regprocedure) is distinct from 'c3661b790649c1511f40032350f5bfbb' then
    raise exception 'svc_adapter_page_record changed, not replacing'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_control(text,jsonb)'::regprocedure) is distinct from '3ad6d2ce34fd287eb67fd5625788fa31' then
    raise exception 'admin_uni_adapter_control changed, not replacing'; end if;
end $g$;

create or replace function public.svc_adapter_page_record(p_course_id uuid, p_identity text, p_how text, p_candidates jsonb) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_pg pipeline.coverage_course_pages%rowtype; v_c jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_identity not in ('adapter_code', 'adapter_title') or p_candidates is null then return 'nothing'; end if;
  -- 5 Oct (Platform Admin 05:50): a field excluded for this course is not taken from the adapter, and an earlier adapter reading of it is cleared below
  if security.uni_adapter_excluded(p_course_id, 'intakes') then p_candidates := p_candidates - 'intakes' - 'intake_context' - 'intakes_by'; end if;
  if security.uni_adapter_excluded(p_course_id, 'fee') then p_candidates := p_candidates - 'fee' - 'fee_by'; end if;
  if security.uni_adapter_excluded(p_course_id, 'english') then p_candidates := p_candidates - 'english' - 'english_by'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = p_course_id;
  if v_pg.course_id is null or v_pg.evidence_id is null then return 'no_page'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  if v_pg.read_status = 'identity_mismatch' then
    update pipeline.coverage_course_pages set read_status = 'read', status = 'bound', identity_basis = p_identity, candidates = p_candidates || jsonb_build_object('final_url', v_pg.url), next_read_at = now() + interval '90 days' where course_id = p_course_id and read_status = 'identity_mismatch';
    update pipeline.search_pass_links set state = 'verified', updated_at = now() where course_id = p_course_id and bound_url = v_pg.url;
  elsif v_pg.read_status = 'read' and v_pg.identity_basis is not null then
    v_c := coalesce(v_pg.candidates, '{}'::jsonb);
    -- 5 Oct: an earlier adapter reading the adapter no longer makes is taken out, so a corrected pattern leaves no stale value
    if v_c->>'intakes_by' = 'adapter' and coalesce(p_candidates->>'intakes_by', '') <> 'adapter' then v_c := v_c - 'intakes' - 'intake_context' - 'intakes_by'; end if;
    if v_c->>'fee_by' = 'adapter' and coalesce(p_candidates->>'fee_by', '') <> 'adapter' then v_c := v_c - 'fee' - 'fee_by'; end if;
    if v_c->>'english_by' = 'adapter' and coalesce(p_candidates->>'english_by', '') <> 'adapter' then v_c := v_c - 'english' - 'english_by'; end if;
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

create or replace function public.admin_uni_adapter_control(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid; v_id bigint;
        v_field text := p_args->>'field'; v_on boolean := coalesce((p_args->>'exclude')::boolean, true); v_courses uuid[];
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action = 'admit' then
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if not exists (select 1 from pipeline.uni_adapters u where u.provider_id = v_pid and u.enabled) then raise exception 'save the adapter switched on first'; end if;
    if p_args ? 'fields' and (jsonb_typeof(p_args->'fields') <> 'array' or exists (select 1 from jsonb_array_elements_text(p_args->'fields') f where f not in ('intakes', 'english', 'fee'))) then raise exception 'fields must be a list of intakes, english and fee'; end if;
    update pipeline.uni_adapters set admit = coalesce((p_args->>'admit')::boolean, false), admit_fields = case when p_args ? 'fields' then array(select distinct f from jsonb_array_elements_text(p_args->'fields') f order by f) else admit_fields end, admit_reason = v_reason, admit_changed_at = now() where provider_id = v_pid;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_admit', v_pid::text, jsonb_build_object('admit', p_args->'admit', 'fields', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = v_pid), 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'fields', (select to_jsonb(u.admit_fields) from pipeline.uni_adapters u where u.provider_id = v_pid));
  elsif p_action = 'exclude' then
    -- 5 Oct: a course and field the adapter must not admit (its page reading is wrong). Switched off with exclude false.
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if coalesce(v_field, '') not in ('intakes', 'english', 'fee') then raise exception 'field must be intakes, english or fee'; end if;
    v_courses := array(select distinct pg.course_id from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
                        where pg.provider_id = v_pid and (pg.course_id::text = p_args->>'course_id' or (coalesce(p_args->>'code', '') <> '' and c.course_code = p_args->>'code') or (coalesce(p_args->>'url', '') <> '' and pg.url = p_args->>'url')));
    if cardinality(v_courses) = 0 then raise exception 'no course of this university has that course id, code or page'; end if;
    insert into pipeline.uni_adapter_exclusions(course_id, field, provider_id, active, reason, set_by, set_at)
      select x, v_field, v_pid, v_on, v_reason, auth.uid(), now() from unnest(v_courses) x
    on conflict (course_id, field) do update set active = excluded.active, reason = excluded.reason, set_by = excluded.set_by, set_at = now() where pipeline.uni_adapter_exclusions.course_id = excluded.course_id;
    if v_on and v_field = 'intakes' then update pipeline.coverage_course_pages pg set candidates = pg.candidates - 'intakes' - 'intake_context' - 'intakes_by' where pg.course_id = any (v_courses) and pg.candidates->>'intakes_by' = 'adapter'; end if;
    if v_on and v_field = 'fee' then update pipeline.coverage_course_pages pg set candidates = pg.candidates - 'fee' - 'fee_by' where pg.course_id = any (v_courses) and pg.candidates->>'fee_by' = 'adapter'; end if;
    if v_on and v_field = 'english' then update pipeline.coverage_course_pages pg set candidates = pg.candidates - 'english' - 'english_by' where pg.course_id = any (v_courses) and pg.candidates->>'english_by' = 'adapter'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_exclude', v_pid::text, jsonb_build_object('courses', to_jsonb(v_courses), 'field', v_field, 'exclude', v_on, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'courses', cardinality(v_courses));
  elsif p_action = 'request' then
    if length(btrim(coalesce(p_args->>'request', ''))) < 4 then raise exception 'write the improvement you want'; end if;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    insert into pipeline.uni_adapter_requests(provider_id, request, requested_by) values (v_pid, btrim(p_args->>'request'), auth.uid()) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_request', v_pid::text, jsonb_build_object('request_id', v_id, 'request', p_args->>'request'), auth.uid());
    return jsonb_build_object('ok', true, 'id', v_id);
  elsif p_action = 'answer' then
    if p_args->>'status' not in ('done', 'declined', 'open') then raise exception 'status must be done, declined or open'; end if;
    update pipeline.uni_adapter_requests set status = p_args->>'status', answer = nullif(btrim(coalesce(p_args->>'answer', '')), ''), answered_at = now() where id = (p_args->>'id')::bigint;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'uni_adapter_request_answer', p_args->>'id', jsonb_build_object('status', p_args->>'status', 'answer', p_args->>'answer'), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_uni_adapter_control(text, jsonb) from public, anon;
grant execute on function public.admin_uni_adapter_control(text, jsonb) to authenticated;

-- Snippet patches of the live definitions (each snippet must be found exactly once)
do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  -- the overwrite honours the admitted fields and the course exclusions
  if (select md5(prosrc) from pg_proc where oid = 'security.adapter_overwrite_v1(integer)'::regprocedure) is distinct from '7b1e9a975b86b1bcd5fd1fd1799f9bee' then
    raise exception 'adapter_overwrite_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.adapter_overwrite_v1(integer)'::regprocedure);
  v_pairs := array[
    array[$s$pg.candidates c, pg.identity_basis ib,$s$, $s$pg.candidates c, pg.identity_basis ib, u.admit_fields af,$s$],
    array[$s$and security.coverage_identity_allowed(r.provider_id, r.ib, 'intakes')$s$, $s$and security.coverage_identity_allowed(r.provider_id, r.ib, 'intakes') and 'intakes' = any (r.af) and not security.uni_adapter_excluded(r.course_id, 'intakes')$s$],
    array[$s$and security.coverage_identity_allowed(r.provider_id, r.ib, 'english')$s$, $s$and security.coverage_identity_allowed(r.provider_id, r.ib, 'english') and 'english' = any (r.af) and not security.uni_adapter_excluded(r.course_id, 'english')$s$],
    array[$s$and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('tuition', 'fee', 'fees'))$s$, $s$and 'fee' = any (r.af) and not security.uni_adapter_excluded(r.course_id, 'fee') and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = r.course_id and k.field in ('tuition', 'fee', 'fees'))$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'overwrite snippet not found exactly once: %', left(v_pair[1], 60); end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;

  -- the country identity rule: an adapter identity admits only the fields switched on for admission
  if (select md5(prosrc) from pg_proc where oid = 'security.coverage_identity_allowed(uuid,text,text)'::regprocedure) is distinct from '5ce87659b65b763823a74e998b9dd0b9' then
    raise exception 'coverage_identity_allowed changed, not patching'; end if;
  v_def := pg_get_functiondef('security.coverage_identity_allowed(uuid,text,text)'::regprocedure);
  v_pair := array[$s$where u.provider_id = p_provider_id and u.enabled and u.admit)$s$, $s$where u.provider_id = p_provider_id and u.enabled and u.admit and (p_attr is null or p_attr not in ('intakes', 'english', 'tuition') or (case p_attr when 'tuition' then 'fee' else p_attr end) = any (u.admit_fields)))$s$];
  if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'identity snippet not found exactly once'; end if;
  execute replace(v_def, v_pair[1], v_pair[2]);

  -- the adapter review shows the admitted fields and the exclusions
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_review(uuid)'::regprocedure) is distinct from '22a6bb03cb18be6dab8562075d62b22b' then
    raise exception 'admin_uni_adapter_review changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_review(uuid)'::regprocedure);
  v_pair := array[$s$'admit', (select jsonb_build_object('on', u.admit, 'reason', u.admit_reason, 'changed_at', u.admit_changed_at) from pipeline.uni_adapters u where u.provider_id = p_provider_id),$s$,
                  $s$'admit', (select jsonb_build_object('on', u.admit, 'fields', to_jsonb(u.admit_fields), 'reason', u.admit_reason, 'changed_at', u.admit_changed_at) from pipeline.uni_adapters u where u.provider_id = p_provider_id),
    'exclusions', (select coalesce(jsonb_agg(jsonb_build_object('course_id', x.course_id, 'course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'field', x.field, 'reason', x.reason, 'set_at', x.set_at) order by x.set_at desc), '[]'::jsonb)
                     from pipeline.uni_adapter_exclusions x join catalogue.courses c on c.id = x.course_id where x.provider_id = p_provider_id and x.active),$s$];
  if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'review snippet not found exactly once'; end if;
  execute replace(v_def, v_pair[1], v_pair[2]);
end $p$;
