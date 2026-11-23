-- CF-247 s1025 (S1-Build; Platform Admin 24 Nov 2026 05:54 and 09:06 AEDT; UI-UX plan v1.2 slice 7): in-app counsellor feedback, backend.
-- A signed-in Counsellor (rank 2) reports what looked wrong on a course, with the categories, a note, the source page and a snapshot of what the
-- screen showed. Rank 2 inserts and reads their own; Curator (rank 3) and above read and triage all, through the Layer 4 Inbox kind
-- counsellor_feedback (Fixed, Not changed, Open the course). This is a channel beside the Zoho counsellor reports (pipeline.data_flags
-- flag_code 'reported', Inbox kind counsellor_report), which are unchanged.
-- 1. pipeline.counsellor_feedback (new), row-level security: insert own at rank 2+, read own at rank 2, read and update all at rank 3+ (reached
--    through the RPCs; the schema is not granted to signed-in users).
-- 2. pipeline.counsellor_feedback_categories (new): the categories as rows (standing rule s930, no list in code); the screen reads them from
--    counsellor_feedback_list_v1.
-- 3. public.counsellor_feedback_submit_v1(jsonb) and public.counsellor_feedback_list_v1(jsonb): additive RPCs (not consumer API objects).
-- 4. Settings (G2): feedback.max_per_user_day, feedback.notes_max_chars, feedback.snapshot_max_kb.
-- The screen (course detail Report an issue, My reports) is S1-API-Frontend-Delivery's (master plan hand-off).
-- G1: no job. G3: no consumer object changed (checked). Manual locks and active cron checked unchanged. Nothing dropped or deleted.
-- Replaces: nothing (new channel).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1025_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1025_cron on commit drop as select count(*) n from cron.job where active;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'feedback.max_per_user_day', 'Counsellor feedback: reports per person per day',
        'How many issue reports one counsellor may send in 24 hours. Further reports are refused with a message until the window passes.',
        'number', to_jsonb(30), 1, 500, 'reports', 1220, 'Layer 4 review', 'public.counsellor_feedback_submit_v1', 'CF-247 s1025: UI-UX plan v1.2 slice 7 (Platform Admin 24 Nov 2026)'),
       ('pipeline', 'feedback.notes_max_chars', 'Counsellor feedback: longest note',
        'The most characters a counsellor''s note may have.', 'number', to_jsonb(2000), 200, 10000, 'characters', 1221, 'Layer 4 review',
        'public.counsellor_feedback_submit_v1', 'CF-247 s1025: UI-UX plan v1.2 slice 7 (Platform Admin 24 Nov 2026)'),
       ('pipeline', 'feedback.snapshot_max_kb', 'Counsellor feedback: largest screen snapshot',
        'The largest snapshot of what the screen showed that a report may carry, in kilobytes.', 'number', to_jsonb(32), 4, 256, 'KB', 1222, 'Layer 4 review',
        'public.counsellor_feedback_submit_v1', 'CF-247 s1025: UI-UX plan v1.2 slice 7 (Platform Admin 24 Nov 2026)')
on conflict do nothing;

create table if not exists pipeline.counsellor_feedback_categories (
  key text primary key,
  label text not null,
  sort int not null,
  active boolean not null default true
);
comment on table pipeline.counsellor_feedback_categories is 'CF-247 s1025: the issue categories a counsellor can choose in Report an issue (read by counsellor_feedback_list_v1; no list in code).';
insert into pipeline.counsellor_feedback_categories (key, label, sort) values
  ('tuition_fee', 'Tuition fee or fee year', 10), ('english', 'English requirement (IELTS, PTE, TOEFL bands)', 20), ('academic_entry', 'Academic entry requirement', 30),
  ('intake', 'Intake or start date', 40), ('campus', 'Campus or location', 50), ('scholarship', 'Scholarship', 60), ('duration', 'Duration or study load', 70),
  ('course_link', 'Course page link', 80), ('description', 'Description', 90), ('other', 'Something else', 100)
on conflict do nothing;
alter table pipeline.counsellor_feedback_categories enable row level security;
revoke all on pipeline.counsellor_feedback_categories from public, anon, authenticated;

create table if not exists pipeline.counsellor_feedback (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  course_id uuid not null,
  provider_id uuid,
  campus_id uuid,
  issue_categories text[] not null check (cardinality(issue_categories) between 1 and 10),
  notes text,
  source_url text,
  displayed_snapshot jsonb,
  status text not null default 'open' check (status in ('open', 'fixed', 'not_changed')),
  triage_note text,
  triaged_by uuid,
  triaged_at timestamptz
);
comment on table pipeline.counsellor_feedback is 'CF-247 s1025: in-app issue reports from counsellors on a course (what was wrong, what the screen showed), triaged in Layer 4 (kind counsellor_feedback).';
create index if not exists counsellor_feedback_open_idx on pipeline.counsellor_feedback (provider_id, created_at) where status = 'open';
create index if not exists counsellor_feedback_by_idx on pipeline.counsellor_feedback (created_by, created_at desc);
alter table pipeline.counsellor_feedback enable row level security;
-- Signed-in users reach the table only through the two RPCs and the Inbox (the pipeline schema is not granted to them); the policies below
-- are a second layer that holds the same rule if the table is ever granted.
revoke all on pipeline.counsellor_feedback from public, anon, authenticated;
create policy counsellor_feedback_insert_own on pipeline.counsellor_feedback for insert to authenticated
  with check (created_by = auth.uid() and coalesce(security.current_role_rank(), 0) >= 2 and status = 'open');  -- fixed: Counsellor (rank 2) reports
create policy counsellor_feedback_read_own on pipeline.counsellor_feedback for select to authenticated
  using (created_by = auth.uid() or coalesce(security.current_role_rank(), 0) >= 3);  -- fixed: Curator (rank 3) triages
create policy counsellor_feedback_triage on pipeline.counsellor_feedback for update to authenticated
  using (coalesce(security.current_role_rank(), 0) >= 3) with check (coalesce(security.current_role_rank(), 0) >= 3);  -- fixed: Curator (rank 3) triages

CREATE OR REPLACE FUNCTION public.counsellor_feedback_submit_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_course uuid; v_provider uuid; v_campus uuid; v_cats text[]; v_notes text; v_url text; v_snap jsonb; v_id uuid; v_n int;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 2 then raise exception 'Counsellor (rank 2) or above is needed to report an issue' using errcode = '42501'; end if;  -- fixed: who reports
  begin
    v_course := nullif(a->>'course_id', '')::uuid; v_campus := nullif(a->>'campus_id', '')::uuid;
  exception when invalid_text_representation then raise exception 'INVALID_INPUT: course_id and campus_id are ids' using errcode = '22023';
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
  v_notes := nullif(btrim(coalesce(a->>'notes', '')), '');
  if length(coalesce(v_notes, '')) > security.pipeline_num_v1('feedback.notes_max_chars', 2000) then raise exception 'INVALID_INPUT: the note is too long' using errcode = '22023'; end if;
  v_url := nullif(btrim(coalesce(a->>'source_url', '')), '');
  if v_url is not null and (v_url !~* '^https://[^\s/]+' or length(v_url) > 2000) then raise exception 'INVALID_INPUT: source_url must be an https address' using errcode = '22023'; end if;  -- fixed: URL length
  v_snap := case when jsonb_typeof(a->'displayed_snapshot') = 'object' then a->'displayed_snapshot' end;
  if v_snap is not null and octet_length(v_snap::text) > security.pipeline_num_v1('feedback.snapshot_max_kb', 32) * 1024 then
    raise exception 'INVALID_INPUT: the screen snapshot is too large' using errcode = '22023';
  end if;
  select count(*) into v_n from pipeline.counsellor_feedback f where f.created_by = auth.uid() and f.created_at > now() - interval '24 hours';  -- fixed: the day the limit counts
  if v_n >= security.pipeline_num_v1('feedback.max_per_user_day', 30) then
    raise exception 'LIMIT: you have sent the most reports allowed in 24 hours; try again later' using errcode = 'P0001';
  end if;
  insert into pipeline.counsellor_feedback(created_by, course_id, provider_id, campus_id, issue_categories, notes, source_url, displayed_snapshot)
  values (auth.uid(), v_course, v_provider, v_campus, v_cats, v_notes, v_url, v_snap) returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'status', 'open');
end $function$;
revoke all on function public.counsellor_feedback_submit_v1(jsonb) from public, anon;
grant execute on function public.counsellor_feedback_submit_v1(jsonb) to authenticated, service_role;

CREATE OR REPLACE FUNCTION public.counsellor_feedback_list_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb); v_rank int; v_all boolean; v_status text := nullif(a->>'status', ''); v_provider uuid; v_course uuid;
        v_lim int := least(greatest(coalesce(nullif(a->>'limit', '')::int, 50), 1), 200);  -- fixed: page size bounds of the screen
        v_off int := greatest(coalesce(nullif(a->>'offset', '')::int, 0), 0);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := coalesce(security.current_role_rank(), 0);
  if v_rank < 2 then raise exception 'Counsellor (rank 2) or above is needed' using errcode = '42501'; end if;  -- fixed: who reads reports
  v_all := v_rank >= 3 and coalesce(a->>'scope', 'all') = 'all';  -- fixed: Curator (rank 3) sees every report
  if v_status is not null and v_status not in ('open', 'fixed', 'not_changed') then raise exception 'INVALID_INPUT: status is open, fixed or not_changed' using errcode = '22023'; end if;
  begin
    v_provider := nullif(a->>'provider_id', '')::uuid; v_course := nullif(a->>'course_id', '')::uuid;
  exception when invalid_text_representation then raise exception 'INVALID_INPUT: provider_id and course_id are ids' using errcode = '22023';
  end;
  return (
    with f as (
      select x.*, count(*) over () total from pipeline.counsellor_feedback x
       where (v_all or x.created_by = auth.uid()) and (v_status is null or x.status = v_status)
         and (v_provider is null or x.provider_id = v_provider) and (v_course is null or x.course_id = v_course)
       order by x.created_at desc limit v_lim offset v_off)
    select jsonb_build_object('scope', case when v_all then 'all' else 'mine' end, 'can_triage', v_rank >= 3, 'total', coalesce((select max(total) from f), 0),
      'categories', (select jsonb_agg(jsonb_build_object('key', k.key, 'label', k.label) order by k.sort) from pipeline.counsellor_feedback_categories k where k.active),
      'items', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'created_at', f.created_at, 'mine', f.created_by = auth.uid(), 'course_id', f.course_id,
          'course', (select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = f.course_id), 'provider_id', f.provider_id,
          'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = f.provider_id), 'campus_id', f.campus_id,
          'issue_categories', to_jsonb(f.issue_categories), 'notes', f.notes, 'source_url', f.source_url, 'status', f.status, 'triage_note', f.triage_note, 'triaged_at', f.triaged_at,
          'displayed_snapshot', case when v_rank >= 3 or f.created_by = auth.uid() then f.displayed_snapshot end) order by f.created_at desc) from f), '[]'::jsonb)));
end $function$;
revoke all on function public.counsellor_feedback_list_v1(jsonb) from public, anon;
grant execute on function public.counsellor_feedback_list_v1(jsonb) to authenticated, service_role;

-- Layer 4 Inbox kind (triage)
CREATE OR REPLACE FUNCTION security.layer4_counsellor_feedback_kind_v1()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select '{"label": "Counsellor feedback (in app)", "order": 11, "choices": [
     {"key": "fixed", "label": "Fixed", "rank": 3, "reason": true, "returns": "Closed as fixed with your note; the counsellor sees it in My reports"},
     {"key": "not_changed", "label": "Not changed", "rank": 3, "reason": true, "returns": "Closed as not changed with your reason; the counsellor sees it in My reports"},
     {"key": "course", "label": "Open the course", "link": "course", "rank": 3, "returns": "Correct the value on the course, then close the report here"}]}'::jsonb
$function$;

CREATE OR REPLACE FUNCTION security.layer4_counsellor_feedback_inbox_counts_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select * from pipeline.counsellor_feedback where status = 'open')
  select jsonb_build_object('kind', 'counsellor_feedback', 'n', (select count(*) from o), 'oldest', (select min(o.created_at) from o),
    'late', (select count(*) from o where o.created_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.created_at) oldest from o group by 1) z), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION security.layer4_counsellor_feedback_inbox_page_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with o as (select r.* from pipeline.counsellor_feedback r
              where r.status = 'open' and (nullif(p_args->>'provider_id', '') is null or r.provider_id = (p_args->>'provider_id')::uuid)),
  x as (select o.* from o
         where nullif(p_args->>'after_ref', '') is null or (o.created_at, o.id::text) > ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')
         order by o.created_at, o.id::text
         limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'counsellor_feedback',
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from o where (o.created_at, o.id::text) <= ((p_args->>'after_at')::timestamptz, p_args->>'after_ref')) end,
    'items', coalesce((select jsonb_agg(jsonb_build_object('kind', 'counsellor_feedback', 'ref', x.id::text, 'provider_id', x.provider_id, 'course_id', x.course_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id),
           'subject', coalesce((select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = x.course_id), 'Course') || ' · ' ||
                      (select string_agg(coalesce(k.label, u), ', ') from unnest(x.issue_categories) u left join pipeline.counsellor_feedback_categories k on k.key = u),
           'why', coalesce(left(x.notes, 200), 'A counsellor reported an issue'), 'suggestion', 'Check the course against its source; fix it or say why not',
           'created_at', x.created_at,
           'late', x.created_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)) order by x.created_at, x.id::text) from x), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION security.layer4_counsellor_feedback_inbox_detail_v1(p_ref text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'report', 'title', 'The report', 'body', jsonb_build_object(
        'Categories', (select string_agg(coalesce(k.label, u), ', ') from unnest(r.issue_categories) u left join pipeline.counsellor_feedback_categories k on k.key = u),
        'Note', coalesce(r.notes, '(no note)'), 'Source page', coalesce(r.source_url, '(none given)'),
        'Campus', coalesce((select k.name from catalogue.campuses k where k.id = r.campus_id), '(not given)'),
        'Sent', to_char(r.created_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'))),
      jsonb_build_object('key', 'snapshot', 'title', 'What the screen showed', 'body', coalesce(r.displayed_snapshot, '{}'::jsonb))),
    'actions', jsonb_build_array(jsonb_build_object('key', 'fixed', 'allowed', true), jsonb_build_object('key', 'not_changed', 'allowed', true), jsonb_build_object('key', 'course', 'allowed', true)))
    from pipeline.counsellor_feedback r
   where r.id::text = p_ref and r.status = 'open'
$function$;

CREATE OR REPLACE FUNCTION security.layer4_counsellor_feedback_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.counsellor_feedback; v_ev bigint; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if p_choice not in ('fixed', 'not_changed') then raise exception 'unknown choice %', p_choice using errcode = '22023'; end if;
  if v_reason is null then
    return jsonb_build_object('ok', false, 'kind', 'counsellor_feedback', 'choice', p_choice, 'ref', p_ref, 'request', 'Write a note for the counsellor; they see it in My reports.');
  end if;
  select * into r from pipeline.counsellor_feedback where id::text = p_ref and status = 'open' for update;
  if not found then
    return jsonb_build_object('ok', false, 'kind', 'counsellor_feedback', 'choice', p_choice, 'ref', p_ref, 'request', 'This report has already been closed; refresh the Inbox.');
  end if;
  update pipeline.counsellor_feedback set status = p_choice, triage_note = v_reason, triaged_by = auth.uid(), triaged_at = now() where id = r.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'counsellor_feedback:' || p_ref, jsonb_build_object('kind', 'counsellor_feedback', 'ref', p_ref, 'choice', p_choice, 'reason', v_reason,
          'course_id', r.course_id, 'provider_id', r.provider_id, 'issue_categories', to_jsonb(r.issue_categories)), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'kind', 'counsellor_feedback', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev,
                            'returns', case p_choice when 'fixed' then 'Closed as fixed; the counsellor sees your note.' else 'Closed as not changed; the counsellor sees your reason.' end);
end $function$;
revoke all on function security.layer4_counsellor_feedback_inbox_decide_v1(text, text, text, text) from public, anon;

insert into pipeline.layer4_inbox_kind_hooks(kind, mode, kind_fn, counts_fn, page_fn, detail_fn, decide_fn, enabled, owner, note)
values ('counsellor_feedback', 'kind', 'security.layer4_counsellor_feedback_kind_v1()', 'security.layer4_counsellor_feedback_inbox_counts_v1()', 'security.layer4_counsellor_feedback_inbox_page_v1(jsonb)',
        'security.layer4_counsellor_feedback_inbox_detail_v1(text)', 'security.layer4_counsellor_feedback_inbox_decide_v1(text,text,text,text)', true,
        'Counsellor feedback (CF-247 s1025)', 'In-app counsellor issue reports triaged by a Curator or above (Platform Admin 24 Nov 2026, UI-UX plan v1.2 slice 7)')
on conflict do nothing;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1025_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1025_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if not exists (select 1 from pipeline.layer4_inbox_kind_hooks where kind = 'counsellor_feedback' and enabled) then raise exception 'post-check: the Inbox kind is not registered'; end if;
  if (select count(*) from pg_policies where schemaname = 'pipeline' and tablename = 'counsellor_feedback') <> 3 then raise exception 'post-check: the row-level policies are not in place'; end if;
end $post$;
