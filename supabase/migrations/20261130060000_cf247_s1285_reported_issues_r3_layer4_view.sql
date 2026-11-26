-- CF-247 s1285 (S2-Build; Reported data issues R3, SS-Programme-Control 26 Nov 2026 22:52 AEDT "Complete DR-19 diagnostic UI integration"; design
-- admin docs/platform/2026-11-26-dr19-record-journey-and-diagnosis-design.md section 8): one read for the Layer 4 "Reported data issues" view.
-- It joins the two existing report stores without changing either: in-app reports (pipeline.counsellor_feedback, origin Admin or Portal from R1's
-- origin column, s1281) and Zoho reports (pipeline.data_flags with flag_code 'reported', origin Zoho). Version above R1's 20261130041500 (s1281,
-- Pilot #1702), which it needs, and the open 20261130044500 (s1176b, #1699) and 20261130051500 (s1284, #1703). Numbered s1285: s1283 and s1284 were taken by other lanes.
-- public.admin_reported_issues_v1(p_args), Curator and above (as Layer 4):
--   mode 'list'  : counts by origin and state, figures (submitted, open, resolved, resolution time, recurrence) and one page of reports, each with
--                  its origin, Layer 4 kind and reference, course, provider, register field, issue, value at report, stage, resolution and evidence;
--   mode 'course': the Reported and Resolved indicators of one course, by field.
-- Evidence-backed resolution: a report closed as fixed carries R1's verification (catalogue and consumer read) when there is one; otherwise the
-- current field state of the course (security.field_state_entity_v1) is shown as current state, not as a check made at closing, and a Fixed with
-- no held value is flagged. Nothing is closed, changed or verified here.
-- Read only beyond one reference table: pipeline.report_origin_field_map (data: which register field a Zoho report field answers). No job, no
-- model call, no spend. Not the consumer API (G3 checked; data_flags is read, never altered). G1: no job. G2: two settings (reports.l4_view_page_max,
-- reports.recurrence_days). Locks untouched. Nothing dropped.
-- Replaces: nothing (new read beside the Layer 4 kinds counsellor_feedback and counsellor_report, which keep their cards and decisions).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the new objects

create temp table s1285_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before;

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'pipeline' and table_name = 'counsellor_feedback' and column_name = 'origin')
     or to_regclass('pipeline.report_field_targets') is null then
    raise exception 'pre-check: R1 (s1281, 20261130041500) is not applied: counsellor_feedback.origin or report_field_targets is missing';
  end if;
  if to_regprocedure('security.field_state_entity_v1(text,uuid)') is null or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'pre-check: security.field_state_entity_v1 or security.current_role_rank is missing';
  end if;
end $pre$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'reports.l4_view_page_max', 'Reported data issues: reports per page',
   'How many reports the Layer 4 Reported data issues view reads in one page. The counts and figures above the list always cover every report.',
   'number', to_jsonb(50), 10, 200, 'reports', 893, 'Layer 4', 'security.reported_issues_v1 (public.admin_reported_issues_v1)', 'CF-247 s1285 (Reported data issues R3, SS-Programme-Control 26 Nov 2026 22:52)'),
  ('pipeline', 'reports.recurrence_days', 'Reported data issues: recurrence window',
   'A course and field reported more than once in this many days counts as recurring in the Layer 4 Reported data issues figures.',
   'number', to_jsonb(90), 7, 730, 'days', 894, 'Layer 4', 'security.reported_issues_v1 (public.admin_reported_issues_v1)', 'CF-247 s1285 (Reported data issues R3, SS-Programme-Control 26 Nov 2026 22:52)')
on conflict do nothing;

create table if not exists pipeline.report_origin_field_map (
  origin text not null,
  reported_field text not null,
  field_code text not null,
  note text,
  primary key (origin, reported_field)
);
comment on table pipeline.report_origin_field_map is 'CF-247 s1285: for a report from an origin that names its own field (Zoho), the field register field it answers; read by security.reported_issues_v1 (data, not code). A reported field with no row (title, scholarship, CRICOS code, address, other) is shown without a register field.';
alter table pipeline.report_origin_field_map enable row level security;
revoke all on pipeline.report_origin_field_map from public, anon, authenticated;
insert into pipeline.report_origin_field_map (origin, reported_field, field_code, note) values
  ('zoho', 'english', 'english', 'English requirements'),
  ('zoho', 'entry_requirements', 'academic_entry', 'Academic entry requirements'),
  ('zoho', 'tuition', 'provider_tuition', 'International tuition'),
  ('zoho', 'intakes', 'intakes', 'Intakes'),
  ('zoho', 'official_url', 'official_url', 'Course page link'),
  ('zoho', 'duration', 'duration', 'Duration'),
  ('zoho', 'delivery', 'delivery', 'Delivery mode'),
  ('zoho', 'campus', 'campus', 'Campuses'),
  ('zoho', 'study_level', 'level', 'Study level'),
  ('zoho', 'study_area', 'field_of_study', 'Study area'),
  ('zoho', 'description', 'description', 'Course description')
on conflict do nothing;

-- every report of both stores, one row each, in one shape
create or replace function security.reported_issue_rows_v1()
returns table(store text, l4_kind text, ref text, origin text, entity text, course_id uuid, provider_id uuid, field_code text, reported_field text,
              issue text[], note text, displayed text, status text, stage text, state text, created_at timestamptz, resolved_at timestamptz,
              resolution_note text, verification jsonb)
language sql stable security definer set search_path = '' as $function$
  select 'counsellor_feedback', 'counsellor_feedback', f.id::text, f.origin, 'course', f.course_id, coalesce(f.provider_id, c.provider_id),
         coalesce(f.field_code, (select t.field_code from pipeline.report_field_targets t where t.category_key = any (f.issue_categories) order by t.field_code limit 1)),
         f.field_code, f.issue_categories, f.notes, f.displayed_value, f.status, f.stage,
         case when f.status = 'open' then 'open' else 'resolved' end, f.created_at,
         case when f.status <> 'open' then coalesce(f.verified_at, f.stage_at, f.triaged_at) end, f.triage_note, f.verification
    from pipeline.counsellor_feedback f
    left join catalogue.courses c on c.id = f.course_id
  union all
  select 'data_flags', 'counsellor_report', d.id::text,
         case when d.detail->>'source' = 'zoho' then 'zoho' else coalesce(nullif(d.detail->>'source', ''), 'unknown') end,
         d.entity_type, case when d.entity_type = 'course' then d.entity_id end,
         case d.entity_type when 'course' then c.provider_id when 'provider' then d.entity_id end,
         m.field_code, d.field_code,
         case when nullif(d.detail->>'issue', '') is not null then array[d.detail->>'issue'] else array[]::text[] end,
         d.detail->>'note',
         left(case when jsonb_typeof(d.detail->'value_at_report') = 'string' then d.detail->>'value_at_report' else nullif(d.detail->'value_at_report', 'null'::jsonb)::text end, 500),
         case d.status when 'open' then 'open' when 'corrected' then 'fixed' else 'not_changed' end,
         case d.status when 'open' then 'received' when 'corrected' then 'fixed' else 'not_changed' end,
         case when d.status = 'open' then 'open' else 'resolved' end, d.created_at, d.resolved_at, d.resolution->>'reason', null::jsonb
    from pipeline.data_flags d
    left join catalogue.courses c on d.entity_type = 'course' and c.id = d.entity_id
    left join pipeline.report_origin_field_map m on m.origin = 'zoho' and m.reported_field = d.field_code
   where d.flag_code = 'reported'
$function$;
comment on function security.reported_issue_rows_v1() is 'CF-247 s1285: every reported data issue of both stores (in-app counsellor_feedback, Zoho data_flags reported) in one shape; read by security.reported_issues_v1.';
revoke all on function security.reported_issue_rows_v1() from public, anon, authenticated;

-- the evidence behind a report's resolution, never a check of its own
create or replace function security.reported_issue_evidence_v1(p_field text, p_course uuid, p_verification jsonb, p_status text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare fs jsonb; v_basis text; v_ok boolean;
begin
  if p_verification is not null and p_verification <> '{}'::jsonb then
    v_ok := p_verification->>'outcome' = 'verified';
    return jsonb_build_object('basis', 'verification', 'outcome', p_verification->>'outcome', 'checked_at', p_verification->>'checked_at',
      'catalogue', p_verification->'catalogue', 'consumer', (p_verification->'consumer') - 'value', 'consumer_key', p_verification->>'consumer_key',
      'fixed_without_evidence', p_status = 'fixed' and not coalesce(v_ok, false));
  end if;
  if p_field is null or p_course is null then
    return jsonb_build_object('basis', 'none', 'why', case when p_course is null then 'not a course report' else 'no register field for this report' end,
      'fixed_without_evidence', p_status = 'fixed');
  end if;
  begin
    fs := security.field_state_entity_v1(p_field, p_course);
  exception when others then
    return jsonb_build_object('basis', 'none', 'why', 'the field state could not be read', 'fixed_without_evidence', p_status = 'fixed');
  end;
  return jsonb_build_object('basis', 'current_state', 'completeness', fs->>'completeness', 'last_verified_at', fs#>>'{freshness,last_verified_at}',
    'applicable', fs#>'{applicability,applicable}', 'protected_hold', fs->'protected_hold',
    'fixed_without_evidence', p_status = 'fixed' and coalesce(fs->>'completeness', '') <> 'verified');
end $function$;
comment on function security.reported_issue_evidence_v1(text, uuid, jsonb, text) is 'CF-247 s1285: the evidence behind a reported issue: R1''s verification when held, else the current field state (not a check made at closing); flags a Fixed with no held value.';
revoke all on function security.reported_issue_evidence_v1(text, uuid, jsonb, text) from public, anon, authenticated;

create or replace function security.reported_issues_v1(p_args jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  a jsonb := coalesce(p_args, '{}'::jsonb);
  v_mode text := coalesce(nullif(btrim(a->>'mode'), ''), 'list');
  v_origin text := coalesce(nullif(btrim(a->>'origin'), ''), 'all');
  v_state text := coalesce(nullif(btrim(a->>'state'), ''), 'open');
  v_max int := greatest(security.pipeline_num_v1('reports.l4_view_page_max', 50)::int, 1);
  v_days int := greatest(security.pipeline_num_v1('reports.recurrence_days', 90)::int, 1);
  v_limit int; v_offset int; v_course uuid;
begin
  if v_mode not in ('list', 'course') then raise exception 'INVALID_INPUT: mode is list or course' using errcode = '22023'; end if;
  if v_origin not in ('all', 'admin', 'portal', 'zoho') then raise exception 'INVALID_INPUT: origin is all, admin, portal or zoho' using errcode = '22023'; end if;
  if v_state not in ('open', 'resolved', 'all') then raise exception 'INVALID_INPUT: state is open, resolved or all' using errcode = '22023'; end if;
  if coalesce(a->>'limit', '') !~ '^\d{0,4}$' or coalesce(a->>'offset', '') !~ '^\d{0,7}$' then raise exception 'INVALID_INPUT: limit and offset are whole numbers' using errcode = '22023'; end if;
  v_limit := least(greatest(coalesce(nullif(a->>'limit', '')::int, v_max), 1), v_max);
  v_offset := coalesce(nullif(a->>'offset', '')::int, 0);

  if v_mode = 'course' then
    if coalesce(a->>'course_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'INVALID_INPUT: give course_id' using errcode = '22023';
    end if;
    v_course := (a->>'course_id')::uuid;
    return (
      with r as (select * from security.reported_issue_rows_v1() x where x.course_id = v_course)
      select jsonb_build_object('course_id', v_course, 'measured_at', now(),
        'open', count(*) filter (where r.state = 'open'), 'resolved', count(*) filter (where r.state = 'resolved'),
        'fixed', count(*) filter (where r.status = 'fixed'), 'not_changed', count(*) filter (where r.status = 'not_changed'),
        'by_field', coalesce((select jsonb_object_agg(k, v) from (
            select coalesce(r2.field_code, '(no register field)') k, jsonb_build_object(
              'open', count(*) filter (where r2.state = 'open'), 'resolved', count(*) filter (where r2.state = 'resolved'),
              'fixed', count(*) filter (where r2.status = 'fixed'),
              'origins', to_jsonb(array_agg(distinct r2.origin order by r2.origin)),
              'last_reported_at', max(r2.created_at), 'last_resolved_at', max(r2.resolved_at)) v
            from r r2 group by 1) q), '{}'::jsonb),
        'items', coalesce((select jsonb_agg(jsonb_build_object('ref', r3.ref, 'l4_kind', r3.l4_kind, 'origin', r3.origin, 'field_code', r3.field_code,
            'status', r3.status, 'stage', r3.stage, 'state', r3.state, 'created_at', r3.created_at, 'resolved_at', r3.resolved_at) order by r3.created_at desc)
          from (select * from r order by r.created_at desc limit v_max) r3), '[]'::jsonb))
      from r);
  end if;

  return (
    with r as (select * from security.reported_issue_rows_v1()),
    rep as (select x.course_id, x.field_code, count(*) n from r x where x.created_at > now() - make_interval(days => v_days) and x.course_id is not null and x.field_code is not null group by 1, 2),
    sel as (select x.* from r x where (v_origin = 'all' or x.origin = v_origin) and (v_state = 'all' or x.state = v_state)),
    pg as (select x.* from sel x order by x.created_at desc, x.ref limit v_limit offset v_offset)
    select jsonb_build_object('measured_at', now(), 'origin', v_origin, 'state', v_state, 'limit', v_limit, 'offset', v_offset,
      'total', (select count(*) from sel),
      'counts', jsonb_build_object(
        'by_origin', coalesce((select jsonb_object_agg(o, jsonb_build_object('open', op, 'resolved', rs)) from (
            select x.origin o, count(*) filter (where x.state = 'open') op, count(*) filter (where x.state = 'resolved') rs from r x group by 1) q), '{}'::jsonb),
        'origins_known', jsonb_build_array('admin', 'portal', 'zoho')),
      'figures', jsonb_build_object(
        'submitted', (select count(*) from r), 'open', (select count(*) from r x where x.state = 'open'), 'resolved', (select count(*) from r x where x.state = 'resolved'),
        'fixed', (select count(*) from r x where x.status = 'fixed'), 'not_changed', (select count(*) from r x where x.status = 'not_changed'),
        'awaiting_verification', (select count(*) from r x where x.stage = 'awaiting_verification'),
        'median_resolution_hours', (select round((percentile_cont(0.5) within group (order by extract(epoch from x.resolved_at - x.created_at)) / 3600)::numeric, 1)
                                      from r x where x.state = 'resolved' and x.resolved_at is not null),
        'recurring_course_fields', (select count(*) from rep where rep.n > 1), 'recurrence_days', v_days),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
          'ref', p.ref, 'store', p.store, 'l4_kind', p.l4_kind, 'origin', p.origin, 'entity', p.entity,
          'course_id', p.course_id, 'course', coalesce(c.display_title, c.canonical_title), 'course_code', c.course_code,
          'provider_id', p.provider_id, 'provider', coalesce(pv.display_name, pv.canonical_name),
          'field_code', p.field_code, 'field', fr.label, 'reported_field', p.reported_field,
          'issue', to_jsonb(p.issue), 'issue_labels', (select to_jsonb(array_agg(coalesce(k.label, u) order by u)) from unnest(p.issue) u left join pipeline.counsellor_feedback_categories k on k.key = u),
          'note', left(p.note, 500), 'displayed', p.displayed, 'status', p.status, 'stage', p.stage, 'state', p.state,
          'created_at', p.created_at, 'resolved_at', p.resolved_at, 'resolution_note', left(p.resolution_note, 500),
          'repeat', coalesce((select rep.n from rep where rep.course_id = p.course_id and rep.field_code = p.field_code), 1),
          'evidence', security.reported_issue_evidence_v1(p.field_code, p.course_id, p.verification, p.status)) order by p.created_at desc, p.ref)
        from pg p
        left join catalogue.courses c on c.id = p.course_id
        left join catalogue.providers pv on pv.id = p.provider_id
        left join pipeline.field_register fr on fr.field = p.field_code), '[]'::jsonb)));
end $function$;
comment on function security.reported_issues_v1(jsonb) is 'CF-247 s1285 (Reported data issues R3): the Layer 4 unified view of in-app (Admin, Portal) and Zoho reports, with counts, figures, evidence and the course indicators; read only.';
revoke all on function security.reported_issues_v1(jsonb) from public, anon, authenticated;

create or replace function public.admin_reported_issues_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;  -- fixed: as the Layer 4 kinds it joins
  return security.reported_issues_v1(p_args);
end $function$;
comment on function public.admin_reported_issues_v1(jsonb) is 'CF-247 s1285 (Reported data issues R3): Layer 4 Reported data issues view and the course drawer indicators; Curator and above; read only.';
revoke all on function public.admin_reported_issues_v1(jsonb) from public, anon;
grant execute on function public.admin_reported_issues_v1(jsonb) to authenticated;

do $post$
declare v jsonb := security.consumer_api_check_v1(); x jsonb; y jsonb; v_c uuid;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> (select cron_before from s1285_guard) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1285_guard) then raise exception 'post-check: manual locks changed'; end if;
  if has_function_privilege('anon', 'public.admin_reported_issues_v1(jsonb)', 'execute') or has_function_privilege('authenticated', 'security.reported_issues_v1(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'security.reported_issue_rows_v1()', 'execute') then
    raise exception 'post-check: execute privileges are not as released';
  end if;
  -- the list covers both stores: its total equals the two stores' counts
  x := security.reported_issues_v1('{"state": "all"}'::jsonb);
  if (x->>'total')::int <> (select count(*) from pipeline.counsellor_feedback) + (select count(*) from pipeline.data_flags where flag_code = 'reported') then
    raise exception 'post-check: the view does not cover both stores: %', left(x::text, 300);
  end if;
  if (x->'figures'->>'submitted')::int <> (x->>'total')::int then raise exception 'post-check: figures and total disagree'; end if;
  select id into v_c from catalogue.courses limit 1;
  y := security.reported_issues_v1(jsonb_build_object('mode', 'course', 'course_id', v_c));
  if y->'by_field' is null or y->>'open' is null then raise exception 'post-check: the course indicators are not as designed: %', left(y::text, 300); end if;
end $post$;
