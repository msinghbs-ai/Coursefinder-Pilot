-- CF-247 F-INT: Rule B qualification register and one approval for all qualified universities (Platform Admin 11 Nov 2026 20:34 / 20:40 AEDT:
-- "i dont want to add univ 1 by 1, develope another strategy to run and execute on demand correction"; option B chosen: the platform qualifies every
-- university and the Platform Admin approves everything that passed in one click; a passing qualification never switches anything on by itself).
-- What:
--   1. pipeline.intake_rule_b_qualifications: one row per university with an intake calendar: status (pending, qualified, held, listed, paused, error),
--      the measures of its last trial, the reasons, a sample of the dates Rule B would give, and who approved it.
--   2. security.intake_rule_b_qualify_one_v1(provider): runs the live intake planner (security.intake_dates_plan_v3) for the university's courses with the
--      university added to intake_dates.nearest_start_providers inside a sub-transaction that is always rolled back (nothing is written by the trial), and
--      checks what Rule B would add: (a) each date's page wording states that month as an intake (security.intake_course_applicability_v1, the planner's own
--      offering check); (b) no vocational, pathway or research course is dated; (c) every date has its calendar evidence; (d) each intake month maps to one
--      date across the university (the trial's dates and the Rule B dates already admitted); (e) at least intake_dates.rule_b_qualify_min_rows rows.
--   3. security.intake_rule_b_qualify_v1(): the job. Requested universities first, then any not checked within intake_dates.rule_b_requalify_hours;
--      batch.intake_rule_b_qualify universities a run. A listed university that fails (a) to (d) is taken off the list when intake_dates.rule_b_auto_pause
--      is on (a stop, never a start), with a hard flag and an admin_control_events line.
--   4. public.admin_intake_rule_b_read_v1, admin_intake_rule_b_request_v1 (queue a university or all for the next run), admin_intake_rule_b_approve_v1
--      (adds every currently qualified university, checked within the re-check window, to the list in one write with a reason; rank 6).
--   5. Job intake-rule-b-qualify every 10 minutes (catalogued; its command holds no number).
-- Guards: G1 (job catalogued), G2 (sizes, window, threshold and the pause switch are settings), G3 (no consumer API object), G4 (cf-247-s536).
-- Replaces: the one-provider-at-a-time switch-on of Operating Model v1.12 "Switching on a gated rule" rule 3 (per-provider manual check and listing):
--   the checks become this register and the listing one approval for all qualified universities.
-- Retires: nothing (no object is switched off; the manual route stays possible on Settings > Pipeline settings).
-- Reversal: unschedule the job and drop the objects by paste file; the provider list is unchanged by this migration.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'batch.intake_rule_b_qualify', 'Intake dates: universities qualified for the nearest start per run',
  'How many universities the Rule B qualification job tries each run (every 10 minutes). Each trial runs the intake planner for one university''s courses.',
  'number', '1'::jsonb, 1, 10, 'universities', 1016, 'Intake dates', 'security.intake_rule_b_qualify_v1 (job intake-rule-b-qualify)',
  'CF-247 F-INT (11 Nov 2026): Rule B qualification register'),
 ('pipeline', 'intake_dates.rule_b_requalify_hours', 'Intake dates: re-check each university for the nearest start every',
  'A university''s Rule B qualification is tried again after this many hours, so new pages, calendars and readings are picked up. Approval only takes universities checked within this window.',
  'number', '24'::jsonb, 1, 168, 'hours', 1017, 'Intake dates', 'security.intake_rule_b_qualify_v1, public.admin_intake_rule_b_approve_v1',
  'CF-247 F-INT (11 Nov 2026): Rule B qualification register'),
 ('pipeline', 'intake_dates.rule_b_qualify_min_rows', 'Intake dates: fewest dates the nearest start must add to qualify a university',
  'A university qualifies for Rule B only when it would add at least this many dates (with every check passed). Below it the university is held as "nothing worth adding".',
  'number', '5'::jsonb, 1, 1000, 'dates', 1018, 'Intake dates', 'security.intake_rule_b_qualify_one_v1',
  'CF-247 F-INT (11 Nov 2026): Rule B qualification register'),
 ('pipeline', 'intake_dates.rule_b_qualify_row_limit', 'Intake dates: intake rows looked at in one qualification trial',
  'The most intake rows the planner looks at when it tries one university for Rule B.',
  'number', '3000'::jsonb, 100, 10000, 'rows', 1019, 'Intake dates', 'security.intake_rule_b_qualify_one_v1',
  'CF-247 F-INT (11 Nov 2026): Rule B qualification register'),
 ('pipeline', 'intake_dates.rule_b_auto_pause', 'Intake dates: take a failing university off the nearest-start list',
  'When on, a listed university whose Rule B trial fails a quality check (wording, level, calendar evidence, one date per month) is taken off intake_dates.nearest_start_providers at once, with a hard flag. Dates already given stay until reviewed.',
  'boolean', 'true'::jsonb, null, null, null, 1020, 'Intake dates', 'security.intake_rule_b_qualify_v1',
  'CF-247 F-INT (11 Nov 2026): Rule B qualification register')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.intake_rule_b_qualifications (
  provider_id uuid primary key references catalogue.providers(id),
  status text not null default 'pending' check (status in ('pending', 'qualified', 'held', 'listed', 'paused', 'error')),
  checked_at timestamptz,
  requested_at timestamptz,
  requested_by uuid,
  rule_b_rows int,
  other_rows int,
  looked int,
  checks jsonb not null default '{}'::jsonb,
  reasons text[] not null default '{}',
  dates jsonb not null default '{}'::jsonb,
  sample jsonb not null default '[]'::jsonb,
  approved_at timestamptz,
  approved_by uuid,
  paused_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);
comment on table pipeline.intake_rule_b_qualifications is 'CF-247 F-INT (11 Nov 2026): Rule B qualification register. One row per university with an intake calendar: the last rolled-back trial of the intake planner with the university on the nearest-start list, its checks, reasons and sample dates, and the approval. Written by security.intake_rule_b_qualify_v1; read by public.admin_intake_rule_b_read_v1.';
alter table pipeline.intake_rule_b_qualifications enable row level security;

create or replace function security.intake_rule_b_qualify_one_v1(p_provider uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_list jsonb := coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_providers'
                            and jsonb_typeof(s.value) = 'array'), '[]'::jsonb);
  v_listed boolean;
  v_limit int := security.pipeline_num_v1('intake_dates.rule_b_qualify_row_limit', 3000)::int;
  v_min int := security.pipeline_num_v1('intake_dates.rule_b_qualify_min_rows', 5)::int;
  v_names text[] := array['january','february','march','april','may','june','july','august','september','october','november','december'];
  v_hold text[] := array['doctorate', 'masters_research'] || coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                            where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_hold_levels' and jsonb_typeof(s.value) = 'array'), '{}');
  v_m jsonb;
  v_reasons text[] := '{}';
  v_quality_fail boolean := false;
begin
  v_listed := v_list ? p_provider::text;
  -- the trial: the university on the list, the live planner, then always rolled back (sqlstate CF001); only the measures leave the block
  begin
    if not v_listed then
      update pipeline.platform_toolset_settings set value = v_list || jsonb_build_array(p_provider::text)
       where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers';
    end if;
    with t as (
      select p.*, i.intake_label, array_position(v_names, lower(btrim(i.intake_label))) mon, l.code lvl, coalesce(c.display_title, c.canonical_title) title
        from security.intake_dates_plan_v3((select array_agg(c2.id) from catalogue.courses c2 where c2.provider_id = p_provider and c2.lifecycle_status = 'active'), v_limit) p
        join catalogue.course_intakes i on i.id = p.intake_id
        join catalogue.courses c on c.id = p.course_id
        left join ref.study_levels l on l.id = c.study_level_id),
    rb as (select * from t where t.outcome = 'filled' and t.rule = 'calendar-v3-nearest-start'),
    admitted as (select i.intake_label, i.start_date from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id
                  where d.provider_id = p_provider and d.outcome = 'filled' and d.rule = 'calendar-v3-nearest-start' and i.start_date is not null),
    alld as (select rb.intake_label, rb.new_start d from rb union all select a.intake_label, a.start_date from admitted a),
    per as (select z.intake_label, count(*) nd, jsonb_object_agg(z.d::text, z.n) dates
              from (select alld.intake_label, alld.d, count(*) n from alld group by 1, 2) z group by 1)
    select jsonb_build_object(
      'looked', (select count(*) from t),
      'rule_b_rows', (select count(*) from rb),
      'other_rows', (select count(*) from t where t.outcome = 'filled' and t.rule is distinct from 'calendar-v3-nearest-start'),
      'wording_missing', (select count(*) from rb where rb.mon is null
                            or security.intake_course_applicability_v1(rb.page_quote, rb.mon, extract(year from rb.new_start)::int, '[]'::jsonb, false) is not null),
      'held_level_dated', (select count(*) from rb where rb.lvl = any (v_hold)),
      'calendar_missing', (select count(*) from rb where rb.calendar_url is null),
      'months_with_two_dates', coalesce((select jsonb_agg(per.intake_label) from per where per.nd > 1), '[]'::jsonb),
      'dates', coalesce((select jsonb_object_agg(per.intake_label, per.dates) from per), '{}'::jsonb),
      'sample', coalesce((select jsonb_agg(x) from (select jsonb_build_object('course', rb.title, 'intake', rb.intake_label, 'date', rb.new_start,
                                                               'page', right(rb.page_quote, 160), 'calendar', left(rb.start_quote, 160), 'calendar_url', rb.calendar_url) x
                                                      from rb order by md5(rb.intake_id::text) limit 6) s), '[]'::jsonb))
      into v_m;
    raise exception using errcode = 'CF001', message = 'cf247 rule b trial rolled back';
  exception when sqlstate 'CF001' then
    null;  -- the trial is undone; v_m keeps the measures
  end;
  if (v_m->>'wording_missing')::int > 0 then v_quality_fail := true;
    v_reasons := v_reasons || format('%s dates have page wording that does not state the month as an intake', v_m->>'wording_missing'); end if;
  if (v_m->>'held_level_dated')::int > 0 then v_quality_fail := true;
    v_reasons := v_reasons || format('%s vocational, pathway or research courses would be dated', v_m->>'held_level_dated'); end if;
  if (v_m->>'calendar_missing')::int > 0 then v_quality_fail := true;
    v_reasons := v_reasons || format('%s dates have no calendar evidence', v_m->>'calendar_missing'); end if;
  if jsonb_array_length(v_m->'months_with_two_dates') > 0 then v_quality_fail := true;
    v_reasons := v_reasons || ('an intake month maps to more than one date: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_m->'months_with_two_dates') x)); end if;
  if not v_listed and (v_m->>'rule_b_rows')::int < v_min then
    v_reasons := v_reasons || format('nothing worth adding: %s dates (fewest to qualify: %s)', v_m->>'rule_b_rows', v_min); end if;
  return v_m || jsonb_build_object('listed', v_listed, 'quality_fail', v_quality_fail, 'reasons', to_jsonb(v_reasons),
    'status', case when v_listed and v_quality_fail then 'paused' when v_listed then 'listed' when cardinality(v_reasons) = 0 then 'qualified' else 'held' end);
end $function$;
comment on function security.intake_rule_b_qualify_one_v1(uuid) is 'CF-247 F-INT (11 Nov 2026): one rolled-back Rule B trial for a university (the live planner with the university on the nearest-start list) and its checks. Writes nothing.';
revoke all on function security.intake_rule_b_qualify_one_v1(uuid) from public, anon, authenticated;

create or replace function security.intake_rule_b_qualify_v1()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_batch int := security.pipeline_num_v1('batch.intake_rule_b_qualify', 1)::int;
  v_hours int := security.pipeline_num_v1('intake_dates.rule_b_requalify_hours', 24)::int;
  v_pause boolean := coalesce((security.toolset_setting('pipeline', 'intake_dates.rule_b_auto_pause') #>> '{}')::boolean, true);
  v_list jsonb; v_after jsonb; r record; v_m jsonb; v_done int := 0; v_out jsonb := '[]'::jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('cf247 rule b qualify'));  -- fixed: one run at a time
  -- every university with an intake calendar, and every listed one, has a row
  insert into pipeline.intake_rule_b_qualifications(provider_id)
  select distinct d.provider_id from pipeline.course_intake_dates d where d.calendar_set is not null
  union
  select x::uuid from pipeline.platform_toolset_settings s, jsonb_array_elements_text(case when jsonb_typeof(s.value) = 'array' then s.value else '[]'::jsonb end) x
   where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_providers' and x ~ '^[0-9a-f-]{36}$'
  on conflict (provider_id) do nothing;
  for r in select q.provider_id from pipeline.intake_rule_b_qualifications q
            where q.requested_at is not null or q.checked_at is null or q.checked_at < now() - make_interval(hours => v_hours)
            order by (q.requested_at is null), q.requested_at, q.checked_at nulls first
            limit v_batch loop
    begin
      v_m := security.intake_rule_b_qualify_one_v1(r.provider_id);
      update pipeline.intake_rule_b_qualifications q set
        status = case when v_m->>'status' = 'paused' and not v_pause then 'listed' else v_m->>'status' end,
        checked_at = now(), requested_at = null, rule_b_rows = (v_m->>'rule_b_rows')::int, other_rows = (v_m->>'other_rows')::int, looked = (v_m->>'looked')::int,
        checks = jsonb_build_object('wording_missing', v_m->'wording_missing', 'held_level_dated', v_m->'held_level_dated', 'calendar_missing', v_m->'calendar_missing',
                                    'months_with_two_dates', v_m->'months_with_two_dates'),
        reasons = array(select jsonb_array_elements_text(v_m->'reasons')), dates = v_m->'dates', sample = v_m->'sample', last_error = null,
        paused_at = case when v_m->>'status' = 'paused' and v_pause then now() else q.paused_at end, updated_at = now()
       where q.provider_id = r.provider_id;
      -- a listed university that fails a quality check is taken off the list (a stop, never a start)
      if v_m->>'status' = 'paused' and v_pause then
        select s.value into v_list from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_providers' for update;
        v_after := coalesce((select jsonb_agg(x) from jsonb_array_elements(v_list) x where x #>> '{}' <> r.provider_id::text), '[]'::jsonb);
        update pipeline.platform_toolset_settings set value = v_after,
               reason = left('Rule B qualification job: taken off after a failed check: ' || array_to_string(array(select jsonb_array_elements_text(v_m->'reasons')), '; '), 500), updated_at = now()
         where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers';
        insert into pipeline.admin_control_events(area, action, target, detail, actor)
        values ('toolsets', 'setting', 'pipeline.intake_dates.nearest_start_providers',
                jsonb_build_object('before', v_list, 'after', v_after, 'reason', 'intake-rule-b-qualify: failed check', 'checks', v_m - 'sample' - 'dates'), null);
        perform security.flag_raise_v1('provider', r.provider_id::text, r.provider_id, 'intakes', 'rule_b_paused',
          'Rule B paused for this university: ' || array_to_string(array(select jsonb_array_elements_text(v_m->'reasons')), '; '), 'hard', 'intake-rule-b-qualify', 'auto',
          v_m - 'sample', null, null);
      end if;
      v_out := v_out || jsonb_build_object('provider_id', r.provider_id, 'status', v_m->>'status', 'rule_b_rows', v_m->'rule_b_rows');
    exception when others then
      update pipeline.intake_rule_b_qualifications q set status = 'error', checked_at = now(), requested_at = null, last_error = left(sqlerrm, 500), updated_at = now()
       where q.provider_id = r.provider_id;
      v_out := v_out || jsonb_build_object('provider_id', r.provider_id, 'status', 'error', 'error', left(sqlerrm, 200));
    end;
    v_done := v_done + 1;
  end loop;
  return jsonb_build_object('tried', v_done, 'results', v_out);
end $function$;
comment on function security.intake_rule_b_qualify_v1() is 'CF-247 F-INT (11 Nov 2026): job intake-rule-b-qualify. Tries requested and due universities (batch.intake_rule_b_qualify) and records the result; takes a failing listed university off the nearest-start list when intake_dates.rule_b_auto_pause is on. Never adds a university.';
revoke all on function security.intake_rule_b_qualify_v1() from public, anon, authenticated;

create or replace function public.admin_intake_rule_b_read_v1()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare v_rank int := security.current_role_rank();
        v_hours int := security.pipeline_num_v1('intake_dates.rule_b_requalify_hours', 24)::int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_request', v_rank >= 4, 'can_approve', v_rank >= 6, 'requalify_hours', v_hours,
    'approvable', (select count(*) from pipeline.intake_rule_b_qualifications q where q.status = 'qualified' and q.checked_at >= now() - make_interval(hours => v_hours)),
    'approvable_rows', (select coalesce(sum(q.rule_b_rows), 0) from pipeline.intake_rule_b_qualifications q where q.status = 'qualified' and q.checked_at >= now() - make_interval(hours => v_hours)),
    'counts', (select coalesce(jsonb_object_agg(z.status, z.n), '{}'::jsonb) from (select q.status, count(*) n from pipeline.intake_rule_b_qualifications q group by 1) z),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', q.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2,
                       'status', q.status, 'checked_at', q.checked_at, 'requested_at', q.requested_at, 'rule_b_rows', q.rule_b_rows, 'other_rows', q.other_rows,
                       'looked', q.looked, 'checks', q.checks, 'reasons', q.reasons, 'dates', q.dates, 'sample', q.sample, 'approved_at', q.approved_at,
                       'paused_at', q.paused_at, 'last_error', q.last_error, 'fresh', q.checked_at >= now() - make_interval(hours => v_hours))
                     order by case q.status when 'qualified' then 0 when 'paused' then 1 when 'error' then 2 when 'listed' then 3 when 'held' then 4 else 5 end,
                              q.rule_b_rows desc nulls last, coalesce(p.display_name, p.canonical_name)), '[]'::jsonb)
               from pipeline.intake_rule_b_qualifications q join catalogue.providers p on p.id = q.provider_id left join ref.countries k on k.id = p.country_id));
end $function$;
comment on function public.admin_intake_rule_b_read_v1() is 'CF-247 F-INT (11 Nov 2026): the Rule B qualification register for Process results (role rank 3 or more). Read only.';
revoke all on function public.admin_intake_rule_b_read_v1() from public, anon;
grant execute on function public.admin_intake_rule_b_read_v1() to authenticated, service_role;

create or replace function public.admin_intake_rule_b_request_v1(p_provider uuid default null)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_rank int := security.current_role_rank(); v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 4 then raise exception 'role rank 4 or more required' using errcode = '42501'; end if;
  update pipeline.intake_rule_b_qualifications q set requested_at = now(), requested_by = auth.uid(), updated_at = now()
   where p_provider is null or q.provider_id = p_provider;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake_dates', 'rule_b_request', coalesce(p_provider::text, 'all'), jsonb_build_object('universities', v_n), auth.uid());
  return jsonb_build_object('ok', true, 'queued', v_n);
end $function$;
comment on function public.admin_intake_rule_b_request_v1(uuid) is 'CF-247 F-INT (11 Nov 2026): queue one university (or all) for the next Rule B qualification run (role rank 4 or more). Switches nothing on.';
revoke all on function public.admin_intake_rule_b_request_v1(uuid) from public, anon;
grant execute on function public.admin_intake_rule_b_request_v1(uuid) to authenticated, service_role;

create or replace function public.admin_intake_rule_b_approve_v1(p_reason text, p_exclude uuid[] default '{}')
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_rank int := security.current_role_rank();
        v_hours int := security.pipeline_num_v1('intake_dates.rule_b_requalify_hours', 24)::int;
        v_ids uuid[]; v_before jsonb; v_after jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 8 then raise exception 'give the reason for the approval' using errcode = '22023'; end if;  -- fixed: a reason of a few words, as the other admin writes
  select coalesce(array_agg(q.provider_id), '{}') into v_ids from pipeline.intake_rule_b_qualifications q
   where q.status = 'qualified' and q.checked_at >= now() - make_interval(hours => v_hours) and not (q.provider_id = any (coalesce(p_exclude, '{}')));
  if cardinality(v_ids) = 0 then return jsonb_build_object('ok', true, 'approved', 0); end if;
  select s.value into v_before from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'intake_dates.nearest_start_providers' for update;
  v_after := coalesce(v_before, '[]'::jsonb) || coalesce((select jsonb_agg(x::text) from unnest(v_ids) x where not (coalesce(v_before, '[]'::jsonb) ? x::text)), '[]'::jsonb);
  update pipeline.platform_toolset_settings set value = v_after, reason = left(btrim(p_reason), 500), updated_by = auth.uid(), updated_at = now()
   where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('toolsets', 'setting', 'pipeline.intake_dates.nearest_start_providers',
          jsonb_build_object('before', v_before, 'after', v_after, 'reason', btrim(p_reason), 'approved', to_jsonb(v_ids), 'via', 'admin_intake_rule_b_approve_v1'), auth.uid());
  update pipeline.intake_rule_b_qualifications q set status = 'listed', approved_at = now(), approved_by = auth.uid(), updated_at = now() where q.provider_id = any (v_ids);
  return jsonb_build_object('ok', true, 'approved', cardinality(v_ids), 'providers', to_jsonb(v_ids));
end $function$;
comment on function public.admin_intake_rule_b_approve_v1(text, uuid[]) is 'CF-247 F-INT (11 Nov 2026): the Platform Admin approves every university the qualification job passed (checked within intake_dates.rule_b_requalify_hours) in one write to intake_dates.nearest_start_providers, with a reason. The only way the register adds a university.';
revoke all on function public.admin_intake_rule_b_approve_v1(text, uuid[]) from public, anon;
grant execute on function public.admin_intake_rule_b_approve_v1(text, uuid[]) to authenticated, service_role;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('intake-rule-b-qualify', 'Enrichment', 34, 'Intake dates: qualify universities for the nearest start (Rule B)',
  'Every 10 minutes: tries Settings > Pipeline settings > Intake dates: universities qualified for the nearest start per run (1) universities, requested ones first, then any not checked within the re-check window (24 hours). Each trial runs the intake planner for the university''s courses with Rule B on and rolls it back, then checks the wording, levels, calendar evidence and one date per month. Qualified universities wait for the Platform Admin''s one approval on Process results; a listed university that fails a check is taken off the list with a hard flag. Never adds a university.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'intake-rule-b-qualify') then
    perform cron.schedule('intake-rule-b-qualify', '7-59/10 * * * *', $j$select security.intake_rule_b_qualify_v1()$j$);
  end if;
end $c$;

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.intake_rule_b_qualifications', 'Layer 3', 'Rule B qualification register: last trial, checks, reasons, sample, approval', 'active', '{}', '20261112010000'),
 ('function', 'security.intake_rule_b_qualify_one_v1', 'Layer 3', 'One rolled-back Rule B trial for a university and its checks', 'active', '{}', '20261112010000'),
 ('function', 'security.intake_rule_b_qualify_v1', 'Layer 3', 'Job: qualify requested and due universities; pause failing listed ones', 'active', '{}', '20261112010000'),
 ('function', 'public.admin_intake_rule_b_read_v1', 'Layer 3', 'Read the Rule B qualification register', 'active', '{}', '20261112010000'),
 ('function', 'public.admin_intake_rule_b_request_v1', 'Layer 3', 'Queue universities for qualification now', 'active', '{}', '20261112010000'),
 ('function', 'public.admin_intake_rule_b_approve_v1', 'Layer 3', 'Approve every qualified university in one write', 'active', '{}', '20261112010000'),
 ('job', 'intake-rule-b-qualify', 'Layer 3', 'Runs the Rule B qualification register', 'active', '{}', '20261112010000')
on conflict do nothing;

do $post$ begin
  if to_regclass('pipeline.intake_rule_b_qualifications') is null then raise exception 'post-check: register table missing'; end if;
  if not exists (select 1 from cron.job where jobname = 'intake-rule-b-qualify' and command = 'select security.intake_rule_b_qualify_v1()') then raise exception 'post-check: job missing'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('batch.intake_rule_b_qualify', 'intake_dates.rule_b_requalify_hours',
      'intake_dates.rule_b_qualify_min_rows', 'intake_dates.rule_b_qualify_row_limit', 'intake_dates.rule_b_auto_pause')) <> 5 then raise exception 'post-check: settings missing'; end if;
end $post$;
