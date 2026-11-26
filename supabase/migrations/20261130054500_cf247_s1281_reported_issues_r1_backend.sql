-- CF-247 s1281 (S1-Build; SS-Programme-Control 26 Nov 2026 22:22 AEDT, "Reported Data Issues: R1 shared backend implementation"; design admin #1220
-- section 8, mock-ups and release plan admin #1223, Master Plan lane item 16; UI reservation s1278 is S1-API-Frontend-Delivery's).
-- R1, additive, on the existing in-app report store (pipeline.counsellor_feedback, s1025) and its Layer 4 kind counsellor_feedback. Zoho
-- (pipeline.data_flags 'reported', zoho-api-v3) is R4 and is not touched. No consumer API object changes (G3).
-- 1. Submission (public.counsellor_feedback_submit_v1, same signature): exact field (pipeline.field_register), displayed value, audience, year,
--    origin (admin or portal: the signed-in app; Portal users reach the same RPCs with the same role ranks) and an idempotency key. A retry with the
--    same key returns the first report; a second open report by the same person on the same course and field returns the open one (duplicate).
-- 2. Reporter-owned reads (rank 2 and above, own reports only): public.report_summary_v1, public.report_inbox_v1 (active, in_progress, awaiting_input,
--    resolved, history), public.report_detail_v1 (the report as sent, its stage, a safe timeline and the outcome), public.report_ack_v1 (seen,
--    acknowledge, archive). Unread, acknowledgement and archive are per person in pipeline.counsellor_feedback_reader_state (new; nothing deleted).
-- 3. Stages (pipeline.counsellor_feedback.stage): received, investigating, awaiting_input, awaiting_verification, fixed, not_changed. status keeps
--    open, fixed, not_changed for the existing screens. Fixed needs verification: the Layer 4 choice Fixed moves the report to awaiting_verification
--    and runs security.counsellor_feedback_verify_v1, which closes it as fixed only when the field is held and verified in the catalogue
--    (security.field_state_entity_v1 completeness verified) and the consumer read (public.website_v2_course) serves a value for it that differs from
--    the value the reporter saw (and holds the expected value when the operator names one). The field to consumer key map is data (pipeline.report_field_targets).
--    A report that cannot be verified stays awaiting verification (re-checked by the Layer 4 choice Verify and when the reporter opens it).
-- 4. Timeline and history from the existing pipeline.admin_control_events (target counsellor_feedback:<id>); only stage, time and the note written
--    for the reporter are shown, never the operator, internal evidence or another reporter.
-- G1: no job. G2: existing settings (feedback.*, lookups.intake_years_ahead). G3: no consumer object changed (checked). Locks and cron checked.
-- Replaces: public.counsellor_feedback_submit_v1 (md5 1ff7aba7), public.counsellor_feedback_list_v1 (a3155444, anchored edit),
--   security.layer4_counsellor_feedback_kind_v1 (3b6e2b89), security.layer4_counsellor_feedback_inbox_detail_v1 (dc680d75),
--   security.layer4_counsellor_feedback_inbox_decide_v1 (5dec1f38). Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the table changes and function replaces

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('public.counsellor_feedback_submit_v1(jsonb)'::regprocedure)) <> '1ff7aba7fe16f1373f6ca61e56799b26' then raise exception 'guard: submit changed'; end if;
  if md5(pg_get_functiondef('public.counsellor_feedback_list_v1(jsonb)'::regprocedure)) <> 'a3155444f05eac3f4d39f847935d32b5' then raise exception 'guard: list changed'; end if;
  if md5(pg_get_functiondef('security.layer4_counsellor_feedback_kind_v1()'::regprocedure)) <> '3b6e2b893551dd874ef8c552a8ee4220' then raise exception 'guard: kind changed'; end if;
  if md5(pg_get_functiondef('security.layer4_counsellor_feedback_inbox_detail_v1(text)'::regprocedure)) <> 'dc680d754072e72372df3ec6b28402fc' then raise exception 'guard: detail changed'; end if;
  if md5(pg_get_functiondef('security.layer4_counsellor_feedback_inbox_decide_v1(text,text,text,text)'::regprocedure)) <> '5dec1f38a4b6a4205b63bf86dffe6b69' then raise exception 'guard: decide changed'; end if;
end $g$;
create temp table s1281_guard on commit drop as select (select count(*) from pipeline.manual_locks) as locks_before;
create temp table s1281_cron on commit drop as select jobid from cron.job;  -- the job ids: this change creates none

-- 1. the report, additively
alter table pipeline.counsellor_feedback
  add column if not exists field_code text,
  add column if not exists displayed_value text,
  add column if not exists audience text,
  add column if not exists study_year int,
  add column if not exists origin text not null default 'admin',
  add column if not exists idempotency_key text,
  add column if not exists stage text not null default 'received',
  add column if not exists stage_at timestamptz,
  add column if not exists verify_expected text,
  add column if not exists verified_at timestamptz,
  add column if not exists verification jsonb;
alter table pipeline.counsellor_feedback add constraint counsellor_feedback_origin_chk check (origin in ('admin', 'portal'));
alter table pipeline.counsellor_feedback add constraint counsellor_feedback_audience_chk check (audience is null or audience in ('international', 'domestic', 'all'));
alter table pipeline.counsellor_feedback add constraint counsellor_feedback_stage_chk
  check (stage in ('received', 'investigating', 'awaiting_input', 'awaiting_verification', 'fixed', 'not_changed'));
create unique index if not exists counsellor_feedback_idem_idx on pipeline.counsellor_feedback (created_by, idempotency_key) where idempotency_key is not null;
create index if not exists counsellor_feedback_dup_idx on pipeline.counsellor_feedback (created_by, course_id, field_code) where status = 'open';
update pipeline.counsellor_feedback set stage = status where status in ('fixed', 'not_changed') and stage = 'received';  -- existing closed reports keep their outcome

create table if not exists pipeline.counsellor_feedback_reader_state (
  feedback_id uuid not null references pipeline.counsellor_feedback(id),
  user_id uuid not null,
  seen_at timestamptz,
  acknowledged_at timestamptz,
  archived_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (feedback_id, user_id)
);
comment on table pipeline.counsellor_feedback_reader_state is 'CF-247 s1281: per-reporter state of an in-app data issue report (seen, acknowledged, archived); presentation only, never an investigation or admission decision. Rows are not deleted.';
alter table pipeline.counsellor_feedback_reader_state enable row level security;
revoke all on pipeline.counsellor_feedback_reader_state from public, anon, authenticated;

create table if not exists pipeline.report_field_targets (
  field_code text primary key,
  category_key text,
  consumer_key text not null,
  note text
);
comment on table pipeline.report_field_targets is 'CF-247 s1281: for a reported course field, the issue category it answers and the Website v2 course key a verified correction must be served under (read by security.counsellor_feedback_verify_v1; data, not code).';
alter table pipeline.report_field_targets enable row level security;
revoke all on pipeline.report_field_targets from public, anon, authenticated;
insert into pipeline.report_field_targets (field_code, category_key, consumer_key, note) values
  ('academic_entry', 'academic_entry', 'entry_requirements', 'Academic entry requirements'),
  ('english', 'english', 'english_requirements', 'English requirements'),
  ('provider_tuition', 'tuition_fee', 'tuition', 'International tuition'),
  ('registered_tuition', null, 'tuition', 'Registered tuition'),
  ('intakes', 'intake', 'intakes', 'Intakes'),
  ('deadline', null, 'intakes', 'Application deadlines are served with the intakes'),
  ('campus', 'campus', 'campuses', 'Campuses'),
  ('campus_city', null, 'campus_city', 'Campus city'),
  ('duration', 'duration', 'duration_months', 'Duration'),
  ('delivery', null, 'delivery_modes', 'Delivery mode'),
  ('official_url', 'course_link', 'official_url', 'Course page link'),
  ('description', 'description', 'description', 'Course description'),
  ('field_of_study', null, 'study_area', 'Study area'),
  ('level', null, 'study_level', 'Study level')
on conflict do nothing;

-- 2. submission
create or replace function public.counsellor_feedback_submit_v1(p_args jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_course uuid; v_provider uuid; v_campus uuid; v_cats text[]; v_notes text; v_url text; v_snap jsonb; v_id uuid; v_n int;
        v_field text := nullif(btrim(coalesce(a->>'field_code', '')), ''); v_shown text := nullif(btrim(coalesce(a->>'displayed_value', '')), '');
        v_aud text := nullif(btrim(coalesce(a->>'audience', '')), ''); v_year int; v_origin text := coalesce(nullif(btrim(coalesce(a->>'origin', '')), ''), 'admin');
        v_key text := nullif(btrim(coalesce(a->>'idempotency_key', '')), ''); v_y0 int := extract(year from now() at time zone 'Australia/Melbourne')::int; r record;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed to report an issue' using errcode = '42501'; end if;  -- fixed: who reports
  if v_key is not null and (length(v_key) > 100 or v_key !~ '^[A-Za-z0-9._:-]+$') then raise exception 'INVALID_INPUT: idempotency_key is up to 100 letters, digits, dots, dashes, colons or underscores' using errcode = '22023'; end if;  -- fixed: key format
  if v_key is not null then
    select f.id, f.status, f.stage into r from pipeline.counsellor_feedback f where f.created_by = auth.uid() and f.idempotency_key = v_key;
    if found then return jsonb_build_object('ok', true, 'id', r.id, 'status', r.status, 'stage', r.stage, 'idempotent', true); end if;
  end if;
  begin
    v_course := nullif(a->>'course_id', '')::uuid; v_campus := nullif(a->>'campus_id', '')::uuid;
    v_year := nullif(a->>'year', '')::int;
  exception when invalid_text_representation then raise exception 'INVALID_INPUT: course_id and campus_id are ids and year is a number' using errcode = '22023';
  end;
  select c.provider_id into v_provider from catalogue.courses c where c.id = v_course;
  if v_provider is null then raise exception 'INVALID_INPUT: course not found' using errcode = '22023'; end if;
  if v_campus is not null and not exists (select 1 from catalogue.campuses k where k.id = v_campus and k.provider_id = v_provider) then
    raise exception 'INVALID_INPUT: the campus is not one of this course''s university campuses' using errcode = '22023';
  end if;
  select array_agg(distinct x) into v_cats from jsonb_array_elements_text(case when jsonb_typeof(a->'issue_categories') = 'array' then a->'issue_categories' else '[]'::jsonb end) x;
  if coalesce(cardinality(v_cats), 0) = 0 then raise exception 'INVALID_INPUT: choose at least one issue category' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_cats) x where not exists (select 1 from pipeline.counsellor_feedback_categories k where k.key = x and k.active)) then
    raise exception 'INVALID_INPUT: unknown issue category' using errcode = '22023';
  end if;
  if v_field is not null and not exists (select 1 from pipeline.field_register f where f.field = v_field and f.active) then
    raise exception 'INVALID_INPUT: unknown field' using errcode = '22023';
  end if;
  if v_aud is not null and v_aud not in ('international', 'domestic', 'all') then raise exception 'INVALID_INPUT: audience is international, domestic or all' using errcode = '22023'; end if;
  if v_origin not in ('admin', 'portal') then raise exception 'INVALID_INPUT: origin is admin or portal' using errcode = '22023'; end if;
  if v_year is not null and (v_year < v_y0 - 1 or v_year > v_y0 + security.pipeline_num_v1('lookups.intake_years_ahead', 2)::int) then  -- fixed: last year is still reported
    raise exception 'INVALID_INPUT: year is outside the years the data holds' using errcode = '22023';
  end if;
  v_notes := nullif(btrim(coalesce(a->>'notes', '')), '');
  if length(coalesce(v_notes, '')) > security.pipeline_num_v1('feedback.notes_max_chars', 2000) then raise exception 'INVALID_INPUT: the note is too long' using errcode = '22023'; end if;
  if length(coalesce(v_shown, '')) > security.pipeline_num_v1('feedback.notes_max_chars', 2000) then raise exception 'INVALID_INPUT: the displayed value is too long' using errcode = '22023'; end if;
  v_url := nullif(btrim(coalesce(a->>'source_url', '')), '');
  if v_url is not null and (v_url !~* '^https://[^\s/]+' or length(v_url) > 2000) then raise exception 'INVALID_INPUT: source_url must be an https address' using errcode = '22023'; end if;  -- fixed: URL length
  v_snap := case when jsonb_typeof(a->'displayed_snapshot') = 'object' then a->'displayed_snapshot' end;
  if v_snap is not null and octet_length(v_snap::text) > security.pipeline_num_v1('feedback.snapshot_max_kb', 32) * 1024 then
    raise exception 'INVALID_INPUT: the screen snapshot is too large' using errcode = '22023';
  end if;
  -- the same person's open report on the same course and field is the one to follow (no second investigation)
  select f.id, f.status, f.stage into r from pipeline.counsellor_feedback f
   where f.created_by = auth.uid() and f.course_id = v_course and f.status = 'open'
     and (case when v_field is not null then f.field_code = v_field else f.field_code is null and f.issue_categories = v_cats end)
   order by f.created_at limit 1;
  if found then return jsonb_build_object('ok', true, 'id', r.id, 'status', r.status, 'stage', r.stage, 'duplicate', true); end if;
  select count(*) into v_n from pipeline.counsellor_feedback f where f.created_by = auth.uid() and f.created_at > now() - interval '24 hours';  -- fixed: the day the limit counts
  if v_n >= security.pipeline_num_v1('feedback.max_per_user_day', 30) then
    raise exception 'LIMIT: you have sent the most reports allowed in 24 hours; try again later' using errcode = 'P0001';
  end if;
  insert into pipeline.counsellor_feedback(created_by, course_id, provider_id, campus_id, issue_categories, notes, source_url, displayed_snapshot,
                                           field_code, displayed_value, audience, study_year, origin, idempotency_key)
  values (auth.uid(), v_course, v_provider, v_campus, v_cats, v_notes, v_url, v_snap, v_field, v_shown, v_aud, v_year, v_origin, v_key) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'status', 'open', 'stage', 'received');
end $function$;
revoke all on function public.counsellor_feedback_submit_v1(jsonb) from public, anon;
grant execute on function public.counsellor_feedback_submit_v1(jsonb) to authenticated, service_role;

-- list: the new fields, additively
do $l$
declare d text := pg_get_functiondef('public.counsellor_feedback_list_v1(jsonb)'::regprocedure);
        a constant text := '''triaged_at'', f.triaged_at,';
        b constant text := '''triaged_at'', f.triaged_at, ''field_code'', f.field_code, ''displayed_value'', case when v_rank >= 3 or f.created_by = auth.uid() then f.displayed_value end, ''audience'', f.audience, ''year'', f.study_year, ''origin'', f.origin, ''stage'', f.stage, ''verified_at'', f.verified_at,';
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the list anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $l$;

-- 3. verification of a correction
create or replace function security.counsellor_feedback_verify_v1(p_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r pipeline.counsellor_feedback; v_field text; t pipeline.report_field_targets; c record; fs jsonb; w jsonb; v_served jsonb; v_txt text; v_ok boolean; v_why text; v jsonb; v_at timestamptz;
        norm constant text := '[^a-z0-9]+';
begin
  select * into r from pipeline.counsellor_feedback where id = p_id for update;
  if not found or r.status <> 'open' or r.stage <> 'awaiting_verification' then return jsonb_build_object('ok', false, 'why', 'not awaiting verification'); end if;
  v_field := coalesce(r.field_code, (select x.field_code from pipeline.report_field_targets x where x.category_key = any (r.issue_categories) order by x.field_code limit 1));
  select * into t from pipeline.report_field_targets x where x.field_code = v_field;
  select x.id, x.course_code into c from catalogue.courses x where x.id = r.course_id;
  if t.field_code is null then
    v_ok := false; v_why := 'unsupported_field';
  else
    fs := security.field_state_entity_v1(v_field, r.course_id);
    v_at := nullif(fs#>>'{freshness,last_verified_at}', '')::timestamptz;
    w := case when c.course_code is not null then public.website_v2_course(c.course_code) end;
    v_served := coalesce(w->'item', w)->t.consumer_key;
    v_txt := lower(coalesce(case when jsonb_typeof(v_served) = 'string' then v_served #>> '{}' else v_served::text end, ''));
    if coalesce(fs->>'completeness', '') <> 'verified' then v_ok := false; v_why := 'catalogue_not_verified';
    elsif v_served is null or jsonb_typeof(v_served) = 'null' or regexp_replace(v_txt, norm, '', 'g') in ('', 'null', '[]', '{}') then v_ok := false; v_why := 'consumer_not_serving';
    elsif r.displayed_value is not null and regexp_replace(v_txt, norm, '', 'g') = regexp_replace(lower(r.displayed_value), norm, '', 'g') then v_ok := false; v_why := 'consumer_unchanged';
    elsif r.verify_expected is not null and position(regexp_replace(lower(r.verify_expected), norm, '', 'g') in regexp_replace(v_txt, norm, '', 'g')) = 0 then v_ok := false; v_why := 'consumer_not_expected_value';
    else v_ok := true; v_why := 'verified';
    end if;
  end if;
  v := jsonb_build_object('checked_at', now(), 'field', v_field, 'consumer_key', t.consumer_key, 'outcome', v_why,
         'catalogue', jsonb_build_object('completeness', fs->>'completeness', 'last_verified_at', v_at),
         'consumer', jsonb_build_object('served', v_served is not null and jsonb_typeof(v_served) <> 'null', 'value', left(case when jsonb_typeof(v_served) = 'string' then v_served #>> '{}' else v_served::text end, 2000)));
  if v_ok then
    update pipeline.counsellor_feedback set status = 'fixed', stage = 'fixed', stage_at = now(), verified_at = now(), verification = v where id = r.id;
  else
    update pipeline.counsellor_feedback set verification = v where id = r.id;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'report_verify', 'counsellor_feedback:' || r.id, jsonb_build_object('outcome', v_why, 'field', v_field, 'verified', v_ok), auth.uid());
  return jsonb_build_object('ok', v_ok, 'outcome', v_why, 'verification', v);
end $function$;
comment on function security.counsellor_feedback_verify_v1(uuid) is 'CF-247 s1281: closes an in-app report as fixed only when the catalogue field is verified and the consumer read serves a changed (and, when named, the expected) value.';
revoke all on function security.counsellor_feedback_verify_v1(uuid) from public, anon, authenticated;

-- Layer 4: choices, detail and decision
create or replace function security.layer4_counsellor_feedback_kind_v1()
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select '{"label": "Counsellor feedback (in app)", "order": 11, "choices": [
     {"key": "investigating", "label": "Investigating", "rank": 3, "reason": false, "returns": "The reporter sees that the report is being looked at"},
     {"key": "awaiting_input", "label": "Ask the reporter", "rank": 3, "reason": true, "returns": "The reporter sees your question in My reports"},
     {"key": "fixed", "label": "Fixed", "rank": 3, "reason": true, "value": "expected", "returns": "Awaiting verification: it closes as fixed once the catalogue and the consumer read show the corrected value"},
     {"key": "verify", "label": "Verify now", "rank": 3, "reason": false, "returns": "Checks the catalogue and the consumer read again"},
     {"key": "not_changed", "label": "Not changed", "rank": 3, "reason": true, "returns": "Closed as not changed with your reason; the counsellor sees it in My reports"},
     {"key": "course", "label": "Open the course", "link": "course", "rank": 3, "returns": "Correct the value on the course, then close the report here"}]}'::jsonb
$function$;

create or replace function security.layer4_counsellor_feedback_inbox_detail_v1(p_ref text)
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  select jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'report', 'title', 'The report', 'body', jsonb_build_object(
        'Categories', (select string_agg(coalesce(k.label, u), ', ') from unnest(r.issue_categories) u left join pipeline.counsellor_feedback_categories k on k.key = u),
        'Field', coalesce((select f.label from pipeline.field_register f where f.field = r.field_code), r.field_code, '(not given)'),
        'Value shown', coalesce(r.displayed_value, '(not given)'), 'Audience', coalesce(r.audience, '(not given)'), 'Year', coalesce(r.study_year::text, '(not given)'),
        'From', case r.origin when 'portal' then 'Portal' else 'Admin' end,
        'Note', coalesce(r.notes, '(no note)'), 'Source page', coalesce(r.source_url, '(none given)'),
        'Campus', coalesce((select k.name from catalogue.campuses k where k.id = r.campus_id), '(not given)'),
        'Sent', to_char(r.created_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'),
        'Stage', replace(r.stage, '_', ' '))),
      jsonb_build_object('key', 'verification', 'title', 'Verification', 'body', coalesce(r.verification, '{}'::jsonb)),
      jsonb_build_object('key', 'snapshot', 'title', 'What the screen showed', 'body', coalesce(r.displayed_snapshot, '{}'::jsonb))),
    'actions', jsonb_build_array(jsonb_build_object('key', 'investigating', 'allowed', r.stage = 'received'), jsonb_build_object('key', 'awaiting_input', 'allowed', true),
      jsonb_build_object('key', 'fixed', 'allowed', r.stage <> 'awaiting_verification'), jsonb_build_object('key', 'verify', 'allowed', r.stage = 'awaiting_verification'),
      jsonb_build_object('key', 'not_changed', 'allowed', true), jsonb_build_object('key', 'course', 'allowed', true)))
    from pipeline.counsellor_feedback r
   where r.id::text = p_ref and r.status = 'open'
$function$;

create or replace function security.layer4_counsellor_feedback_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r pipeline.counsellor_feedback; v_ev bigint; v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_value text := nullif(btrim(coalesce(p_value, '')), ''); v jsonb;
begin
  if p_choice not in ('investigating', 'awaiting_input', 'fixed', 'verify', 'not_changed') then raise exception 'unknown choice %', p_choice using errcode = '22023'; end if;
  if v_reason is null and p_choice in ('awaiting_input', 'fixed', 'not_changed') then
    return jsonb_build_object('ok', false, 'kind', 'counsellor_feedback', 'choice', p_choice, 'ref', p_ref, 'request', 'Write a note for the counsellor; they see it in My reports.');
  end if;
  select * into r from pipeline.counsellor_feedback where id::text = p_ref and status = 'open' for update;
  if not found then
    return jsonb_build_object('ok', false, 'kind', 'counsellor_feedback', 'choice', p_choice, 'ref', p_ref, 'request', 'This report has already been closed; refresh the Inbox.');
  end if;
  if p_choice = 'not_changed' then
    update pipeline.counsellor_feedback set status = 'not_changed', stage = 'not_changed', stage_at = now(), triage_note = v_reason, triaged_by = auth.uid(), triaged_at = now() where id = r.id;
  elsif p_choice = 'fixed' then
    update pipeline.counsellor_feedback set stage = 'awaiting_verification', stage_at = now(), triage_note = v_reason, triaged_by = auth.uid(), triaged_at = now(),
           verify_expected = coalesce(v_value, verify_expected) where id = r.id;
  elsif p_choice = 'verify' then
    if r.stage <> 'awaiting_verification' then
      return jsonb_build_object('ok', false, 'kind', 'counsellor_feedback', 'choice', p_choice, 'ref', p_ref, 'request', 'Only a report awaiting verification can be verified.');
    end if;
  else
    update pipeline.counsellor_feedback set stage = p_choice, stage_at = now(), triage_note = coalesce(v_reason, triage_note), triaged_by = auth.uid(), triaged_at = now() where id = r.id;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'counsellor_feedback:' || p_ref, jsonb_build_object('kind', 'counsellor_feedback', 'ref', p_ref, 'choice', p_choice, 'reason', v_reason,
          'expected', v_value, 'course_id', r.course_id, 'provider_id', r.provider_id, 'issue_categories', to_jsonb(r.issue_categories)), auth.uid()) returning id into v_ev;
  if p_choice in ('fixed', 'verify') then v := security.counsellor_feedback_verify_v1(r.id); end if;
  return jsonb_build_object('ok', true, 'kind', 'counsellor_feedback', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'verification', v,
                            'returns', case when p_choice in ('fixed', 'verify') and coalesce((v->>'ok')::boolean, false) then 'Verified and closed as fixed; the counsellor sees your note.'
                                            when p_choice in ('fixed', 'verify') then 'Awaiting verification (' || replace(coalesce(v->>'outcome', 'not checked'), '_', ' ') || '); it closes as fixed once verified.'
                                            when p_choice = 'not_changed' then 'Closed as not changed; the counsellor sees your reason.'
                                            when p_choice = 'awaiting_input' then 'The counsellor sees your question.' else 'The counsellor sees that the report is being investigated.' end);
end $function$;
revoke all on function security.layer4_counsellor_feedback_inbox_decide_v1(text, text, text, text) from public, anon;

-- 4. reporter-owned reads and state
create or replace function security.report_view_v1()
 returns table(id uuid, created_at timestamptz, course_id uuid, provider_id uuid, field_code text, issue_categories text[], status text, stage text,
               last_update_at timestamptz, updated boolean, unread boolean, terminal boolean, acknowledged_at timestamptz, archived_at timestamptz, origin text)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select f.id, f.created_at, f.course_id, f.provider_id, f.field_code, f.issue_categories, f.status, f.stage,
         greatest(f.created_at, coalesce(f.stage_at, f.created_at), coalesce(f.triaged_at, f.created_at), coalesce(f.verified_at, f.created_at)) last_update_at,
         greatest(coalesce(f.stage_at, f.created_at), coalesce(f.triaged_at, f.created_at), coalesce(f.verified_at, f.created_at)) > f.created_at updated,
         greatest(coalesce(f.stage_at, f.created_at), coalesce(f.triaged_at, f.created_at), coalesce(f.verified_at, f.created_at)) > coalesce(s.seen_at, f.created_at) unread,
         f.status in ('fixed', 'not_changed') terminal, s.acknowledged_at, s.archived_at, f.origin
    from pipeline.counsellor_feedback f
    left join pipeline.counsellor_feedback_reader_state s on s.feedback_id = f.id and s.user_id = auth.uid()
   where f.created_by = auth.uid()
$function$;
revoke all on function security.report_view_v1() from public, anon, authenticated;

create or replace function public.report_summary_v1()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed' using errcode = '42501'; end if;  -- fixed: who reports
  return (select jsonb_build_object('as_of', now(),
      'active', count(*) filter (where not v.terminal),
      'in_progress', count(*) filter (where v.stage in ('investigating', 'awaiting_verification')),
      'awaiting_input', count(*) filter (where v.stage = 'awaiting_input'),
      'resolved_unread', count(*) filter (where v.terminal and v.acknowledged_at is null),
      'unread_updates', count(*) filter (where v.updated and v.unread and v.archived_at is null),
      'history', count(*) filter (where v.terminal and v.acknowledged_at is not null))
    from security.report_view_v1() v);
end $function$;
revoke all on function public.report_summary_v1() from public, anon;
grant execute on function public.report_summary_v1() to authenticated, service_role;

create or replace function public.report_inbox_v1(p_args jsonb)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_view text := coalesce(nullif(a->>'view', ''), 'active');
        v_lim int := least(greatest(coalesce(nullif(a->>'limit', '')::int, 50), 1), 200);  -- fixed: page size bounds of the screen
        v_off int := greatest(coalesce(nullif(a->>'offset', '')::int, 0), 0);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed' using errcode = '42501'; end if;  -- fixed: who reports
  if v_view not in ('active', 'in_progress', 'awaiting_input', 'resolved', 'history') then
    raise exception 'INVALID_INPUT: view is active, in_progress, awaiting_input, resolved or history' using errcode = '22023';
  end if;
  return (
    with x as (
      select v.*, count(*) over () total from security.report_view_v1() v
       where case v_view when 'active' then not v.terminal
                         when 'in_progress' then v.stage in ('investigating', 'awaiting_verification')
                         when 'awaiting_input' then v.stage = 'awaiting_input'
                         when 'resolved' then v.terminal and v.acknowledged_at is null
                         else v.terminal and v.acknowledged_at is not null end
       order by v.last_update_at desc, v.id limit v_lim offset v_off)
    select jsonb_build_object('view', v_view, 'as_of', now(), 'total', coalesce((select max(total) from x), 0),
      'items', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'created_at', x.created_at, 'last_update_at', x.last_update_at, 'stage', x.stage, 'status', x.status,
          'unread', x.updated and x.unread, 'acknowledged', x.acknowledged_at is not null, 'archived', x.archived_at is not null, 'origin', x.origin,
          'course_id', x.course_id, 'course', (select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = x.course_id),
          'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
          'field_code', x.field_code, 'field', (select f.label from pipeline.field_register f where f.field = x.field_code),
          'issue_categories', to_jsonb(x.issue_categories)) order by x.last_update_at desc, x.id) from x), '[]'::jsonb)));
end $function$;
revoke all on function public.report_inbox_v1(jsonb) from public, anon;
grant execute on function public.report_inbox_v1(jsonb) to authenticated, service_role;

create or replace function public.report_detail_v1(p_args jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_id uuid; r pipeline.counsellor_feedback; s pipeline.counsellor_feedback_reader_state;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed' using errcode = '42501'; end if;  -- fixed: who reports
  begin v_id := nullif(p_args->>'id', '')::uuid;
  exception when invalid_text_representation then raise exception 'INVALID_INPUT: id is a report id' using errcode = '22023'; end;
  select * into r from pipeline.counsellor_feedback where id = v_id and created_by = auth.uid();
  if not found then raise exception 'NOT_FOUND: no such report of yours' using errcode = 'P0002'; end if;
  -- a correction awaiting verification is checked again when its reporter opens it (no scheduler)
  if r.status = 'open' and r.stage = 'awaiting_verification' then perform security.counsellor_feedback_verify_v1(r.id); select * into r from pipeline.counsellor_feedback where id = v_id; end if;
  insert into pipeline.counsellor_feedback_reader_state(feedback_id, user_id, seen_at) values (r.id, auth.uid(), now())
  on conflict (feedback_id, user_id) do update set seen_at = now(), updated_at = now() returning * into s;
  return jsonb_build_object('id', r.id, 'created_at', r.created_at, 'origin', r.origin, 'status', r.status, 'stage', r.stage,
    'course_id', r.course_id, 'course', (select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = r.course_id),
    'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = r.provider_id),
    'campus', (select k.name from catalogue.campuses k where k.id = r.campus_id),
    'field_code', r.field_code, 'field', (select f.label from pipeline.field_register f where f.field = r.field_code),
    'issue_categories', (select jsonb_agg(jsonb_build_object('key', u, 'label', coalesce(k.label, u))) from unnest(r.issue_categories) u left join pipeline.counsellor_feedback_categories k on k.key = u),
    'sent', jsonb_build_object('displayed_value', r.displayed_value, 'audience', r.audience, 'year', r.study_year, 'notes', r.notes, 'source_url', r.source_url, 'displayed_snapshot', r.displayed_snapshot),
    'timeline', (select jsonb_agg(e order by e->>'at') from (
        select jsonb_build_object('at', r.created_at, 'stage', 'received', 'label', 'Report received') e
        union all
        select jsonb_build_object('at', a.created_at, 'stage', coalesce(nullif(a.detail->>'choice', 'verify'), 'awaiting_verification'),
               'label', case a.detail->>'choice' when 'investigating' then 'Being investigated' when 'awaiting_input' then 'Question for you'
                                                 when 'fixed' then 'Correction made, awaiting verification' when 'not_changed' then 'Closed: not changed' else 'Checked again' end)
          from pipeline.admin_control_events a where a.target = 'counsellor_feedback:' || r.id::text and a.action = 'inbox_decide'
        union all
        select jsonb_build_object('at', r.verified_at, 'stage', 'fixed', 'label', 'Verified and fixed') where r.verified_at is not null) z),
    'outcome', case when r.status = 'fixed' then jsonb_build_object('result', 'fixed', 'note', r.triage_note, 'verified_at', r.verified_at, 'served_value', r.verification#>>'{consumer,value}')
                    when r.status = 'not_changed' then jsonb_build_object('result', 'not_changed', 'note', r.triage_note)
                    when r.stage = 'awaiting_input' then jsonb_build_object('result', 'awaiting_input', 'question', r.triage_note)
                    when r.stage = 'awaiting_verification' then jsonb_build_object('result', 'awaiting_verification', 'note', r.triage_note) end,
    'reader', jsonb_build_object('seen_at', s.seen_at, 'acknowledged_at', s.acknowledged_at, 'archived_at', s.archived_at));
end $function$;
revoke all on function public.report_detail_v1(jsonb) from public, anon;
grant execute on function public.report_detail_v1(jsonb) to authenticated, service_role;

create or replace function public.report_ack_v1(p_args jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_action text := nullif(a->>'action', ''); v_ids uuid[]; v_n int := 0; v_refused int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed' using errcode = '42501'; end if;  -- fixed: who reports
  if v_action not in ('seen', 'acknowledge', 'archive') then raise exception 'INVALID_INPUT: action is seen, acknowledge or archive' using errcode = '22023'; end if;
  begin
    select array_agg(distinct x::uuid) into v_ids from jsonb_array_elements_text(case when jsonb_typeof(a->'ids') = 'array' then a->'ids' else '[]'::jsonb end) x;
  exception when invalid_text_representation then raise exception 'INVALID_INPUT: ids are report ids' using errcode = '22023'; end;
  if coalesce(cardinality(v_ids), 0) = 0 or cardinality(v_ids) > 100 then raise exception 'INVALID_INPUT: between 1 and 100 report ids' using errcode = '22023'; end if;  -- fixed: bulk bar bound
  -- only the reporter's own reports; acknowledge and archive only a closed report (an open one keeps its updates)
  select count(*) into v_refused from unnest(v_ids) i where not exists (select 1 from pipeline.counsellor_feedback f where f.id = i and f.created_by = auth.uid()
                                                                          and (v_action = 'seen' or f.status in ('fixed', 'not_changed')));
  insert into pipeline.counsellor_feedback_reader_state(feedback_id, user_id, seen_at, acknowledged_at, archived_at)
  select f.id, auth.uid(), now(), case when v_action in ('acknowledge', 'archive') then now() end, case when v_action = 'archive' then now() end
    from pipeline.counsellor_feedback f
   where f.id = any (v_ids) and f.created_by = auth.uid() and (v_action = 'seen' or f.status in ('fixed', 'not_changed'))
  on conflict (feedback_id, user_id) do update
     set seen_at = now(),
         acknowledged_at = case when v_action in ('acknowledge', 'archive') then coalesce(pipeline.counsellor_feedback_reader_state.acknowledged_at, now()) else pipeline.counsellor_feedback_reader_state.acknowledged_at end,
         archived_at = case when v_action = 'archive' then coalesce(pipeline.counsellor_feedback_reader_state.archived_at, now()) else pipeline.counsellor_feedback_reader_state.archived_at end,
         updated_at = now();
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'action', v_action, 'updated', v_n, 'refused', v_refused);
end $function$;
revoke all on function public.report_ack_v1(jsonb) from public, anon;
grant execute on function public.report_ack_v1(jsonb) to authenticated, service_role;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1281_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;  -- fixed: the standing cron limit
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1281_guard) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from pipeline.report_field_targets t where not exists (select 1 from pipeline.field_register f where f.field = t.field_code)) then raise exception 'post-check: a target names an unknown field'; end if;
  if exists (select 1 from pipeline.report_field_targets t where t.category_key is not null and not exists (select 1 from pipeline.counsellor_feedback_categories k where k.key = t.category_key)) then
    raise exception 'post-check: a target names an unknown category';
  end if;
  if not exists (select 1 from pipeline.layer4_inbox_kind_hooks where kind = 'counsellor_feedback' and enabled) then raise exception 'post-check: the Inbox kind is not registered'; end if;
end $c$;
