-- CF-247 (21 Oct 2026). Platform Admin 08:42: "go ahead with next step for Field Stalled and action to resolve it" (the platform raises a
-- field that is below target and not moving, instead of a person finding it).
--   1 pipeline.field_coverage_daily: each field's filled share per country, one row a day (kept 120 days); history back-filled from the
--     coverage build's daily counts (29 Sep on, the 7 fields it counted) and the Enrich fields hourly snapshots (14 Oct on).
--   2 security.field_stalled_v1(): for every field of the register with a target, in every country:
--       flat      below target and moved less than stall.min_points (1 point) in stall.days (7 days)
--       behind    below target and stall.country_gap_points (30) or more behind the best country
--       no_reader the field has a target but nothing reads it yet
--     with the main cause (from the hourly coverage build: not stated on the page, page not read, no course page, waiting for a person,
--     being filled, register value missing), the action that resolves it and the five universities missing it most.
--   3 Platform health check field_stalled (every 3 hours): one issue per country listing its flat and behind fields (warning when a field is
--     flat, information when only behind), one for fields with no reader, one when the standing Fill the gaps queue is switched on but has
--     not run for 7 hours. Issues close themselves when the field moves again. Records today's row of field_coverage_daily.
--     (One block added to security.platform_health_check_v1, md5-guarded.)
--   4 public.admin_field_coverage: 'stalled' (the list with causes and actions); 'fill_now' (Pipeline Operator: one Enrich fields task for
--     the field in that country, AI on, new page reads within the limits); 'release_and_fill' (Platform Admin, with a reason: releases the
--     soft "page did not state it" holds for that field and country, then fills; use after an adapter or reader change).
-- Replaces: public.admin_field_coverage (three actions added, nothing else changes); security.platform_health_check_v1 (one check added)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"public.admin_field_coverage(text,jsonb)": "033c4e56a3f4433136a596938592fafd",
                              "security.platform_health_check_v1(boolean)": "cfcaeda41a7b519ff7170cc597d3f625"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'stall.days', 'A field is stalled when it has not moved for', 'A field below its target is raised in Platform health when its filled share has moved less than the minimum over this many days.', 'number', to_jsonb(7), 3, 30, 'days', 108, 'CF-247, Platform Admin 21 Oct 2026 "go ahead with next step for Field Stalled"', 'Re-read and retry', 'Platform health check field_stalled; Coverage › Attributes › Stalled fields'),
 ('pipeline', 'stall.min_points', 'A field is moving when it gains at least', 'Percentage points a field below target must gain over the stall period to count as moving.', 'number', to_jsonb(1), 0, 20, 'points', 109, 'CF-247, Platform Admin 21 Oct 2026 "go ahead with next step for Field Stalled"', 'Re-read and retry', 'Platform health check field_stalled'),
 ('pipeline', 'stall.country_gap_points', 'A country is behind when it trails the best country by', 'Percentage points a country may trail the best country on a field (below target) before it is raised.', 'number', to_jsonb(30), 5, 100, 'points', 110, 'CF-247, Platform Admin 21 Oct 2026 "same attributes completeness across the board"', 'Re-read and retry', 'Platform health check field_stalled'),
 ('pipeline', 'stall.queue_hours', 'Fill the gaps has not run for', 'Hours without a standing Fill the gaps check (while it is switched on) before Platform health raises it.', 'number', to_jsonb(7), 1, 48, 'hours', 111, 'CF-247, Platform Admin 21 Oct 2026 "go ahead with next step for Field Stalled"', 'Re-read and retry', 'Platform health check field_stalled')
on conflict (toolset_key, key) do nothing;

-- 1 Daily field coverage ---------------------------------------------------------------------------------------------------------
create table if not exists pipeline.field_coverage_daily (
  snapshot_date date not null,
  country_code text not null,
  field text not null,
  total int not null,
  filled int not null,
  computed_at timestamptz not null default now(),
  primary key (snapshot_date, country_code, field));
alter table pipeline.field_coverage_daily enable row level security;
comment on table pipeline.field_coverage_daily is 'CF-247 21 Oct 2026: each field of the field register, filled share per country, one row a day (the latest reading of the day; kept 120 days). Platform health check field_stalled compares it over stall.days.';

create or replace function security.provider_field_coverage_v1()
 returns table(country_code text, field text, total bigint, filled bigint)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select p.cc, f.field, count(*), count(*) filter (where f.has)
    from (select p.*, security.coverage_country(p.id) cc from catalogue.providers p
           where coalesce(p.lifecycle_status, 'active') = 'active' and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')) p
    cross join lateral (values
      ('p_website', nullif(btrim(p.website), '') is not null),
      ('p_address', nullif(btrim(p.address_line1), '') is not null),
      ('p_campuses', exists (select 1 from catalogue.campuses k where k.provider_id = p.id)),
      ('p_type', p.provider_type_id is not null),
      ('p_international', p.enrols_international is not null),
      ('p_logo', nullif(btrim(p.logo_url), '') is not null or exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.asset_type = 'logo')),
      ('p_contact', nullif(btrim(p.phone), '') is not null or nullif(btrim(p.email), '') is not null),
      ('p_scholarships', exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')),
      ('p_description', nullif(btrim(p.description), '') is not null)) f(field, has)
   group by 1, 2
$function$;
revoke execute on function security.provider_field_coverage_v1() from public, anon, authenticated;

create or replace function security.field_coverage_record_v1()
 returns int
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v int;
begin
  insert into pipeline.field_coverage_daily(snapshot_date, country_code, field, total, filled)
  select (now() at time zone 'Australia/Melbourne')::date, a.country_code, a.attribute, count(*), count(*) filter (where a.state = 'admitted')  -- fixed: the day is Melbourne's
    from pipeline.course_attribute_coverage a group by 2, 3
  union all
  select (now() at time zone 'Australia/Melbourne')::date, x.country_code, x.field, x.total, x.filled from security.provider_field_coverage_v1() x
  on conflict (snapshot_date, country_code, field) do update set total = excluded.total, filled = excluded.filled, computed_at = now();
  get diagnostics v = row_count;
  delete from pipeline.field_coverage_daily where snapshot_date < current_date - 120;  -- fixed: history kept 120 days (derived figures, rebuilt hourly)
  return v;
end $function$;
revoke execute on function security.field_coverage_record_v1() from public, anon, authenticated;

-- history: Enrich fields hourly snapshots (last of each day), then the coverage build's daily counts where it has the field
insert into pipeline.field_coverage_daily(snapshot_date, country_code, field, total, filled)
select distinct on ((s.at at time zone 'Australia/Melbourne')::date, s.country_code, s.field)
       (s.at at time zone 'Australia/Melbourne')::date, s.country_code, case s.field when 'provider_address' then 'p_address' else s.field end, s.courses, s.filled
  from pipeline.enrich_coverage_snapshots s
 order by (s.at at time zone 'Australia/Melbourne')::date, s.country_code, s.field, s.at desc
on conflict (snapshot_date, country_code, field) do nothing;
insert into pipeline.field_coverage_daily(snapshot_date, country_code, field, total, filled)
select d.snapshot_date, d.country_code, d.attribute, sum(d.courses), coalesce(sum(d.courses) filter (where d.state = 'admitted'), 0)
  from pipeline.course_coverage_daily_by_country d
 where d.snapshot_date >= current_date - 120 and d.attribute in (select f.field from pipeline.field_register f)
 group by 1, 2, 3 having sum(d.courses) > 0
on conflict (snapshot_date, country_code, field) do update set total = excluded.total, filled = excluded.filled;
select security.field_coverage_record_v1();

-- 2 Stalled fields -------------------------------------------------------------------------------------------------------------------
create or replace function security.field_stalled_v1()
 returns jsonb
 language sql
 stable security definer
 set search_path to ''
as $function$
  with s as (select security.pipeline_num_v1('stall.days', 7)::int d, security.pipeline_num_v1('stall.min_points', 1) mp, security.pipeline_num_v1('stall.country_gap_points', 30) gp),
  today as (select max(snapshot_date) t from pipeline.field_coverage_daily),
  cur as (select x.country_code cc, x.field, x.total, x.filled, round(100.0 * x.filled / nullif(x.total, 0), 1) pct
            from pipeline.field_coverage_daily x, today where x.snapshot_date = today.t and x.total > 0),
  ago as (select distinct on (x.country_code, x.field) x.country_code cc, x.field, x.snapshot_date, round(100.0 * x.filled / nullif(x.total, 0), 1) pct
            from pipeline.field_coverage_daily x, today, s where x.snapshot_date <= today.t - s.d and x.total > 0
           order by x.country_code, x.field, x.snapshot_date desc),
  best as (select field, max(pct) pct, (array_agg(cc order by pct desc))[1] cc from cur group by field),
  cause as (select z.country_code cc, z.attribute field, jsonb_object_agg(z.c, z.n) counts, (array_agg(z.c order by z.n desc))[1] main
              from (select a.country_code, a.attribute,
                           case when a.state = 'not_on_page' then 'not_stated' when a.state = 'in_queue' then 'in_queue'
                                when a.state in ('in_review', 'candidate', 'awaiting_l3') then 'in_review' when a.state in ('page_found', 'blocked') then 'not_read'
                                when a.state in ('site_known', 'no_website') then 'no_page' when a.state = 'missing_l1' then 'register' when a.state = 'no_reader' then 'no_reader' end c,
                           count(*) n
                      from pipeline.course_attribute_coverage a where a.state <> 'admitted' group by 1, 2, 3) z
             group by 1, 2),
  rows as (
    select c.cc, c.field, r.label, r.reader, r.level, c.total, c.filled, c.pct, r.target_pct target, g.pct pct_ago, g.snapshot_date ago_date,
           round(c.pct - g.pct, 1) moved, b.cc best_cc, b.pct best_pct,
           case when r.reader = 'none' then 'no_reader'
                when g.pct is not null and c.pct - g.pct < s.mp then 'flat'
                when b.pct - c.pct >= s.gp then 'behind' end reason,
           case when r.reader = 'none' then 'no_reader' when r.level = 'provider' then 'provider' else coalesce(k.main, 'not_read') end main_cause,
           k.counts
      from cur c join pipeline.field_register r on r.field = c.field and r.active and r.target_pct > 0
      cross join s left join ago g on g.cc = c.cc and g.field = c.field left join best b on b.field = c.field
      left join cause k on k.cc = c.cc and k.field = c.field
     where c.pct < r.target_pct)
  select coalesce(jsonb_agg(jsonb_build_object(
           'country', r.cc, 'field', r.field, 'label', r.label, 'reader', r.reader, 'level', r.level, 'total', r.total, 'filled', r.filled, 'pct', r.pct,
           'target', r.target, 'pct_ago', r.pct_ago, 'ago_date', r.ago_date, 'moved', r.moved, 'days', (select d from s), 'best_country', r.best_cc, 'best_pct', r.best_pct,
           'reason', r.reason, 'cause', r.main_cause, 'causes', r.counts,
           'can_fill', r.field in ('level', 'field_of_study', 'duration', 'delivery', 'campus', 'campus_city', 'international', 'p_address'),
           'action', case
              when r.reason = 'no_reader' then 'Nothing reads this field yet: a reader is a build task. Set the target to 0 until it exists, so the field is not raised.'
              when r.main_cause = 'in_queue' then 'Being filled now by Fill the gaps or an Enrich fields task: check again after the run.'
              when r.main_cause = 'in_review' then 'Waiting for a person: Layer 4 › Inbox, and For review in the Enrich fields task results.'
              when r.main_cause = 'register' then 'The register does not give it: check the register run on Layer 1 Register.'
              when r.main_cause = 'not_stated' and r.reader = 'enrich' then 'The course pages read do not state it. Add a central page or an adapter rule for the universities below (Layer 2/3 › Universities › Builder), then Release holds and fill; or lower the target if the universities do not publish it.'
              when r.main_cause = 'not_stated' then 'The course pages read do not state it. Add a central page or an adapter rule for the universities below (Layer 2/3 › Universities › Builder); or lower the target if the universities do not publish it.'
              when r.main_cause in ('not_read', 'no_page') and r.reader = 'enrich' then 'Pages not read for this field yet: Fill now starts an Enrich fields task for it in this country (AI on, new page reads within the daily limits).'
              when r.main_cause in ('not_read', 'no_page') then 'Course pages not found or not read: check course-page search for the universities below on Layer 2/3 › Operations and Universities.'
              when r.field = 'p_address' then 'Fill now reads each provider''s contact or home page for its street address.'
              else 'Provider field: open the providers missing it on Providers and add it, or lower the target.' end,
           'top_providers', case when r.level = 'course' then (
              select coalesce(jsonb_agg(jsonb_build_object('id', t.provider_id, 'name', t.name, 'missing', t.n) order by t.n desc), '[]'::jsonb) from (
                select a.provider_id, max(coalesce(p.display_name, p.canonical_name)) name, count(*) n from pipeline.course_attribute_coverage a join catalogue.providers p on p.id = a.provider_id
                 where a.country_code = r.cc and a.attribute = r.field and a.state <> 'admitted' group by 1 order by 3 desc limit 5) t) end)
         order by r.cc, case r.reason when 'flat' then 1 when 'behind' then 2 when 'no_reader' then 3 else 4 end, r.target - r.pct desc), '[]'::jsonb)
    from rows r
$function$;
revoke execute on function security.field_stalled_v1() from public, anon, authenticated;

-- 3 Platform health check ------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_health_checks(key, area, label, status, detail, cadence_minutes, slow, sort_order)
values ('field_stalled', 'coverage sweep', 'Fields below target are moving', 'ok', '{}'::jsonb, 180, false, 140)
on conflict (key) do nothing;

select pg_temp.edit_once('security.platform_health_check_v1(boolean)', 'cfcaeda41a7b519ff7170cc597d3f625', array[
  array[$x$  -- 5. record issues (dedup on check_key), auto-resolve what cleared, store check status$x$,
        $x$  -- CF-247 21 Oct 2026: fields below target that are not moving, by country; fields with no reader; the standing queue not running
  if security.platform_health_due_v1('field_stalled',p_force) then
    v_t:=clock_timestamp();
    begin
      perform security.field_coverage_record_v1();
      v_x:=security.field_stalled_v1();
      for r in select x->>'country' cc, count(*) filter (where x->>'reason'='flat') flat, count(*) filter (where x->>'reason'='behind') behind,
                      string_agg(case when x->>'reason' in ('flat','behind') then (x->>'label')||' '||(x->>'pct')||'%' end, ', ' order by (x->>'reason'), (x->>'label')) fields,
                      jsonb_agg(jsonb_build_object('field',x->>'field','pct',x->'pct','target',x->'target','moved',x->'moved','reason',x->>'reason','cause',x->>'cause') order by x->>'field') filter (where x->>'reason' in ('flat','behind')) det
                 from jsonb_array_elements(v_x) x group by 1 loop
        if r.flat+r.behind>0 then
          v_found:=v_found||security.platform_health_issue_v1('field_stalled:'||r.cc, case when r.flat>0 then 'warning' else 'info' end, 'coverage sweep',
            coalesce((select k.name from ref.countries k where k.iso_alpha2=r.cc limit 1), r.cc)||': '||(r.flat+r.behind)||' field(s) below target and '||
            case when r.flat>0 then 'not moving' else 'behind other countries' end||' ('||r.fields||')',
            jsonb_build_object('country',r.cc,'flat',r.flat,'behind',r.behind,'fields',r.det,'resolve','Coverage › Attributes › Stalled fields'));
        end if;
      end loop;
      select string_agg(distinct x->>'label', ', ') into v_txt from jsonb_array_elements(v_x) x where x->>'reason'='no_reader';
      if v_txt is not null then
        v_found:=v_found||security.platform_health_issue_v1('field_stalled:no_reader','info','coverage sweep','Fields with a target but no reader yet: '||v_txt,
          jsonb_build_object('fields',v_txt,'resolve','Build a reader, or set the target to 0 on Coverage › Attributes'));
      end if;
      if (select enabled from pipeline.field_gap_queue_control where id=1) then
        select max(d.start_time) into v_ts from cron.job_run_details d join cron.job j on j.jobid=d.jobid where j.jobname='field-gap-queue' and d.status='succeeded';
        if not exists (select 1 from cron.job j where j.jobname='field-gap-queue' and j.active)
           or coalesce(v_ts, (select min(d.start_time) from cron.job_run_details d where d.jobid>(select j.jobid from cron.job j where j.jobname='field-gap-queue'))) < now()-make_interval(hours=>security.pipeline_num_v1('stall.queue_hours',7)::int) then
          v_found:=v_found||security.platform_health_issue_v1('field_stalled:queue','warning','coverage sweep','Fill the gaps (standing queue) is switched on but has not run since '||coalesce(to_char(v_ts at time zone 'Australia/Melbourne','DD Mon HH24:MI'),'it was scheduled'),
            jsonb_build_object('last_success',v_ts,'resolve','Scheduled jobs › field-gap-queue; Check now on Coverage › Attributes'));
        end if;
      end if;
      v_det:=v_det||jsonb_build_object('field_stalled',jsonb_build_object('flat',(select count(*) from jsonb_array_elements(v_x) x where x->>'reason'='flat'),
                                                                         'behind',(select count(*) from jsonb_array_elements(v_x) x where x->>'reason'='behind'),
                                                                         'no_reader',(select count(*) from jsonb_array_elements(v_x) x where x->>'reason'='no_reader')));
      v_ok:=array_append(v_ok,'field_stalled');
    exception when others then
      v_ok:=array_append(v_ok,'field_stalled');
      v_found:=v_found||security.platform_health_issue_v1('field_stalled:check_error','warning','coverage sweep','The stalled fields check could not run',jsonb_build_object('error',left(sqlerrm,300)));
    end;
    v_ms:=v_ms||jsonb_build_object('field_stalled',round(extract(epoch from clock_timestamp()-v_t)*1000));
  end if;

  -- 5. record issues (dedup on check_key), auto-resolve what cleared, store check status$x$]]);

-- 4 Coverage actions -----------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.admin_field_coverage(text,jsonb)', '033c4e56a3f4433136a596938592fafd', array[
  array[$x$  elsif p_action = 'run_now' then$x$,
        $x$  elsif p_action = 'stalled' then
    -- CF-247 21 Oct 2026: fields below target that are not moving or are behind, with the cause and the action that resolves it
    return jsonb_build_object('items', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(security.field_stalled_v1()) x
                                         where (v_cc is null or x->>'country' = v_cc) and x->>'reason' is not null),
                              'days', security.pipeline_num_v1('stall.days', 7), 'min_points', security.pipeline_num_v1('stall.min_points', 1),
                              'gap_points', security.pipeline_num_v1('stall.country_gap_points', 30),
                              'history_from', (select min(snapshot_date) from pipeline.field_coverage_daily),
                              'can_fill', v_rank >= 4, 'can_release', v_rank >= 6);
  elsif p_action in ('fill_now', 'release_and_fill') then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    if v_cc is null then raise exception 'choose a country'; end if;
    v_ef := case p_args->>'field' when 'campus_city' then 'campus' when 'p_address' then 'provider_address' else p_args->>'field' end;
    if not exists (select 1 from security.enrich_fields_v1() e where e.field = v_ef) then raise exception 'this field is not filled by Enrich fields'; end if;
    if p_action = 'release_and_fill' then
      if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
      if length(v_reason) < 4 then raise exception 'give a reason (kept with each released hold)'; end if;
      v_actor := coalesce((select u.email from auth.users u where u.id = auth.uid()), auth.uid()::text);
      for v_id in select f.id from pipeline.enrichment_flags f
                   where f.entity = 'course' and f.field = v_ef and f.reason_code = 'enrich_no_value' and f.state = 'counting'
                     and security.coverage_country(f.provider_id) = v_cc loop
        perform security.flag_release_v1(v_id, v_actor, 'person', 'Coverage › Stalled fields: ' || v_reason, jsonb_build_object('country', v_cc, 'field', v_ef), false);
        v_released := v_released + 1;
      end loop;
    end if;
    v_r := public.admin_enrich_fields('start', jsonb_build_object('countries', jsonb_build_array(v_cc), 'fields', jsonb_build_array(v_ef), 'ai', true, 'scraper', true,
             'reason', coalesce(nullif(v_reason, ''), 'Coverage › Stalled fields: Fill now')));
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_stalled', p_action, v_cc || '.' || v_ef, jsonb_build_object('released', v_released, 'task', v_r, 'reason', v_reason), auth.uid());
    return coalesce(v_r, '{}'::jsonb) || jsonb_build_object('released', v_released);
  elsif p_action = 'run_now' then$x$],
  array[$x$        v_job pipeline.admin_jobs%rowtype;$x$,
        $x$        v_job pipeline.admin_jobs%rowtype; v_ef text; v_actor text; v_id bigint; v_released int := 0; v_r jsonb;$x$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.field_coverage_daily', 'Layer 2', 'Each field''s filled share per country, one row a day', 'active', '20261021130000'),
 ('function', 'security.field_coverage_record_v1', 'Layer 2', 'Records today''s field coverage row per country', 'active', '20261021130000'),
 ('function', 'security.provider_field_coverage_v1', 'Layer 2', 'Provider fields filled per country', 'active', '20261021130000'),
 ('function', 'security.field_stalled_v1', 'Layer 2', 'Fields below target that are not moving or are behind, with cause and action', 'active', '20261021130000')
on conflict (kind, name) do nothing;
