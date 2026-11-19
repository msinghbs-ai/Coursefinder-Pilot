-- CF-247 s777: Coverage & completeness › Pipeline & field ETA (Platform Admin 19 Nov 2026 15:36 AEDT, chat S1-Build), and the snapshot it and the hourly
-- Stakeholder_Course_Readiness_Summary refresh (s776) read.
-- Measured in rolled-back live dry runs (GitHub Actions, 19 Nov 2026 15:45-16:00 AEDT): the per-course readiness of
-- scripts/telemetry/course-field-readiness.sql takes 27.6 s for one eighth of the 36,031 active courses and 5.5-15 s for one sixteenth, too long
-- for a screen read (8 s) and for the hourly sheet sync to run in full. pipeline.course_field_readiness_v does not exist.
-- What it adds (no table, no column; G3 untouched: every function is in schema security, and the screen reads through the existing
-- public.admin_field_coverage):
--   1. security.course_field_readiness_build_v1(part): one sixteenth of the courses (readiness.snapshot_parts) a run, counted by provider, field
--      and state, kept in pipeline.job_input_marks (this job's own state: course-field-readiness:p<n>); the rules are the export's, verbatim
--      (spec s777 holds them equal). Once a day, when every part was built that day, the admitted counts by provider and field are kept as the
--      day's mark (course-field-readiness:days, readiness.days_kept days) for the observed velocity.
--   2. security.course_field_readiness_summary_v1(): after each part, the parts merged by provider and summed for all courses and each country,
--      with each scope's velocity over the last 7 days of marks (course-field-readiness:summary). The screen and the sheet read only this row.
--   3. security.course_field_eta_v1(scope, country, provider, query): per field Admitted, Trying, Needs a source, Not possible, Wave 2, the
--      observed daily velocity, the primary bottleneck and the expected 100% achievable date; and the providers matching a search.
--   4. public.admin_field_coverage gains action pipeline_eta (the existing internal coverage read; any StudySearch role).
--   5. security.course_field_readiness_tabs_v1(): the rows of the three summary tabs of the Google Sheet Stakeholder_Course_Readiness_Summary
--      (Executive_Summary, Field_ETA_Forecast, By_Provider_Action_List), read by the hourly telemetry sync (s776).
--   6. Rollup target course-field-readiness, every 4 minutes (one part a run, all 16 parts about every hour).
-- Replaces: nothing (the daily per-course CSV export stays on its 07:30 schedule).
-- Retires: nothing.
-- G1: one rollup target (rollup-scheduler; no cron job). G2: two settings (readiness.snapshot_parts, readiness.days_kept). G3: untouched.

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'readiness.snapshot_parts', 'Course field readiness: parts', 'The readiness snapshot is built one part of the active courses a run; with more parts each run is shorter and a full refresh takes more runs.',
   'number', to_jsonb(16), 4, 64, 'parts', 103, 'Job sizes', 'security.course_field_readiness_build_v1',
   'CF-247 s777 (Platform Admin 19 Nov 2026 15:36): readiness snapshot for Pipeline & field ETA and the hourly stakeholder sheet'),
  ('pipeline', 'readiness.days_kept', 'Course field readiness: daily marks kept', 'Days of admitted counts kept for the observed velocity on Pipeline & field ETA (7 days are used).',
   'number', to_jsonb(15), 8, 60, 'days', 104, 'Job sizes', 'security.course_field_readiness_build_v1',
   'CF-247 s777 (Platform Admin 19 Nov 2026 15:36): observed velocity')
on conflict do nothing;

create or replace function security.course_field_readiness_summary_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- s777: the parts merged by provider and summed for all courses and each country, with a 7-day observed velocity per field (admitted courses a day)
declare v_parts int := greatest(1, security.pipeline_num_v1('readiness.snapshot_parts', 16)::int);
        v_days jsonb := (select s.last_result->'days' from pipeline.job_input_marks s where s.job_key = 'course-field-readiness:days');
        v_now text; v_base text; v_gap int; v jsonb;
begin
  select max(d) into v_now from jsonb_object_keys(coalesce(v_days, '{}'::jsonb)) d;
  select coalesce(max(d) filter (where d::date <= v_now::date - 7), min(d) filter (where d < v_now)) into v_base from jsonb_object_keys(coalesce(v_days, '{}'::jsonb)) d;  -- fixed: a 7-day window
  v_gap := case when v_base is not null then v_now::date - v_base::date end;
  with p as (select x from pipeline.job_input_marks s cross join lateral jsonb_array_elements(s.last_result->'providers') x
              where s.job_key like 'course-field-readiness:p%' and (s.last_result->>'parts')::int = v_parts),
  pf as (select x->>'provider_id' pid, f.key field, sum((f.value->>0)::int) a, sum((f.value->>1)::int) t, sum((f.value->>2)::int) ns, sum((f.value->>3)::int) np, sum((f.value->>4)::int) em
           from p cross join lateral jsonb_each(x->'f') f group by 1, 2),
  pi as (select x->>'provider_id' pid, max(x->>'name') name, max(x->>'cc') cc, sum((x->>'courses')::int) n from p group by 1),
  pv as (select n.pid, f.key field, ((f.value #>> '{}')::numeric - (v_days->v_base->n.pid->>f.key)::numeric) / v_gap d
           from jsonb_each(case when v_gap > 0 then v_days->v_now end) n(pid, m) cross join lateral jsonb_each(n.m) f
          where v_days->v_base ? n.pid),
  prov as (select pi.pid, pi.name, pi.cc, pi.n,
                  (select jsonb_object_agg(pf.field, jsonb_build_array(pf.a, pf.t, pf.ns, pf.np, pf.em)) from pf where pf.pid = pi.pid) f,
                  (select jsonb_object_agg(pv.field, round(pv.d, 1)) from pv where pv.pid = pi.pid) v
             from pi),
  sc as (select s.scope, pf.field, sum(pf.a) a, sum(pf.t) t, sum(pf.ns) ns, sum(pf.np) np, sum(pf.em) em
           from pf join pi using (pid) cross join lateral (values ('ALL'), (pi.cc)) s(scope) group by 1, 2),
  scv as (select s.scope, pv.field, sum(pv.d) d from pv join pi using (pid) cross join lateral (values ('ALL'), (pi.cc)) s(scope) group by 1, 2),
  scn as (select s.scope, sum(pi.n) n from pi cross join lateral (values ('ALL'), (pi.cc)) s(scope) group by 1)
  select jsonb_build_object(
           'built_at', now(), 'parts', v_parts,
           'oldest_part_at', (select min(s.last_run_at) from pipeline.job_input_marks s where s.job_key like 'course-field-readiness:p%' and (s.last_result->>'parts')::int = v_parts),
           'parts_built', (select count(*) from pipeline.job_input_marks s where s.job_key like 'course-field-readiness:p%' and (s.last_result->>'parts')::int = v_parts),
           'velocity_from', v_base, 'velocity_to', v_now, 'velocity_days', v_gap,
           'scopes', (select jsonb_object_agg(scn.scope, jsonb_build_object('courses', scn.n,
                        'f', (select jsonb_object_agg(sc.field, jsonb_build_array(sc.a, sc.t, sc.ns, sc.np, sc.em)) from sc where sc.scope = scn.scope),
                        'v', (select jsonb_object_agg(scv.field, round(scv.d, 1)) from scv where scv.scope = scn.scope))) from scn),
           'providers', (select jsonb_object_agg(prov.pid, jsonb_build_object('name', prov.name, 'cc', prov.cc, 'courses', prov.n, 'f', prov.f, 'v', prov.v)) from prov))
    into v;
  insert into pipeline.job_input_marks as s (job_key, last_full_at, last_run_at, last_result, runs_done, runs_skipped)
  values ('course-field-readiness:summary', now(), now(), v, 1, 0)
  on conflict (job_key) do update set last_full_at = excluded.last_full_at, last_run_at = excluded.last_run_at, last_result = excluded.last_result, runs_done = s.runs_done + 1;
  return jsonb_build_object('scopes', (select count(*) from jsonb_object_keys(v->'scopes')), 'providers', (select count(*) from jsonb_object_keys(v->'providers')));
end $function$;

create or replace function security.course_field_eta_v1(p_scope text default 'all', p_country text default null, p_provider uuid default null, p_query text default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
-- s777: Pipeline & field ETA for all courses, one country or one provider, from course-field-readiness:summary (one row read)
declare v_s jsonb := (select s.last_result from pipeline.job_input_marks s where s.job_key = 'course-field-readiness:summary');
        v_scope text := lower(coalesce(nullif(btrim(p_scope), ''), 'all')); v_node jsonb; v_label text; v_q text := nullif(btrim(coalesce(p_query, '')), '');
begin
  if v_s is null then return jsonb_build_object('ready', false, 'note', 'The readiness snapshot is being built; it fills within the hour.'); end if;
  if v_scope = 'provider' and p_provider is not null then
    v_node := v_s->'providers'->(p_provider::text); v_label := v_node->>'name';
  elsif v_scope = 'country' and p_country is not null then
    v_node := v_s->'scopes'->upper(p_country); v_label := upper(p_country);
  else
    v_scope := 'all'; v_node := v_s->'scopes'->'ALL'; v_label := 'All courses';
  end if;
  return jsonb_build_object(
    'ready', true, 'scope', v_scope, 'label', v_label, 'courses', coalesce((v_node->>'courses')::int, 0),
    'built_at', v_s->'built_at', 'oldest_part_at', v_s->'oldest_part_at', 'parts', v_s->'parts', 'parts_built', v_s->'parts_built',
    'velocity_from', v_s->'velocity_from', 'velocity_to', v_s->'velocity_to', 'velocity_days', v_s->'velocity_days',
    'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', k, 'courses', (v_s->'scopes'->k->>'courses')::int) order by k), '[]'::jsonb)
                    from jsonb_object_keys(v_s->'scopes') k where k <> 'ALL'),
    'fields', (select coalesce(jsonb_agg(jsonb_build_object(
                 'field', f.key, 'admitted', (f.value->>0)::int, 'trying', (f.value->>1)::int, 'needs_source', (f.value->>2)::int,
                 'not_possible', (f.value->>3)::int, 'wave2', (f.value->>4)::int, 'velocity', (v_node->'v'->>f.key)::numeric,
                 'bottleneck', case greatest((f.value->>1)::int, (f.value->>2)::int, (f.value->>3)::int, (f.value->>4)::int)
                                 when 0 then null when (f.value->>1)::int then 'trying' when (f.value->>2)::int then 'needs_source'
                                 when (f.value->>3)::int then 'not_possible' else 'wave2' end,
                 'remaining', (f.value->>1)::int + (f.value->>2)::int,
                 'eta_days', case when (f.value->>1)::int + (f.value->>2)::int = 0 then 0
                                  when (v_node->'v'->>f.key)::numeric > 0 then ceil(((f.value->>1)::int + (f.value->>2)::int) / (v_node->'v'->>f.key)::numeric) end,
                 'eta_state', case when (f.value->>1)::int + (f.value->>2)::int = 0 then 'complete'
                                   when (v_node->'v'->>f.key) is null then 'not_measured'
                                   when (v_node->'v'->>f.key)::numeric > 0 then 'forecast' else 'no_progress' end)
               order by (f.value->>0)::int desc, f.key), '[]'::jsonb) from jsonb_each(v_node->'f') f),
    'providers', case when v_q is not null or v_scope = 'provider' then
                   (select coalesce(jsonb_agg(jsonb_build_object('id', p.key, 'name', p.value->>'name', 'country', p.value->>'cc', 'courses', (p.value->>'courses')::int)
                                              order by (p.value->>'courses')::int desc, p.value->>'name'), '[]'::jsonb)
                      from (select p0.key, p0.value from jsonb_each(v_s->'providers') p0
                             where (v_q is null or p0.value->>'name' ilike '%' || v_q || '%') and (p_country is null or p0.value->>'cc' = upper(p_country))
                             order by (p0.value->>'courses')::int desc, p0.value->>'name' limit 25) p) end);  -- fixed: a search list, not a report
end $function$;

create or replace function security.course_field_readiness_build_v1(p_part integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
-- s777 (Platform Admin 19 Nov 2026 15:36): one part of the per-course field readiness (the rules of scripts/telemetry/course-field-readiness.sql,
-- copied verbatim between the markers below and held equal by spec s777), counted by provider, field and state, kept in
-- pipeline.job_input_marks (this job's own state) under course-field-readiness:p<part>. With no part given, the part built longest ago is built. After a part is
-- built, the day's mark (admitted courses per provider and field) is kept once a day for the observed velocity (course-field-readiness:days).
declare v_parts int := greatest(1, security.pipeline_num_v1('readiness.snapshot_parts', 16)::int); v_part int; v_t0 timestamptz := clock_timestamp();
        v_payload jsonb; v_n int; v_day date := (now() at time zone 'Australia/Sydney')::date; v_keep int := greatest(2, security.pipeline_num_v1('readiness.days_kept', 15)::int);
begin
  v_part := coalesce(p_part, (select k.p from generate_series(0, v_parts - 1) k(p)
                               left join pipeline.job_input_marks s on s.job_key = 'course-field-readiness:p' || k.p
                              order by s.last_run_at nulls first, k.p limit 1));
  if v_part < 0 or v_part >= v_parts then raise exception 'part % is outside 0..%', v_part, v_parts - 1 using errcode = '22023'; end if;
  -- readiness rules: begin (verbatim from scripts/telemetry/course-field-readiness.sql; only the part filter reads v_parts and v_part)
with c as (
  select co.id course_id, co.provider_id, coalesce(pr.display_name, pr.canonical_name) provider_name, k.iso_alpha2::text cc,
         coalesce(co.display_title, co.canonical_title) title, co.description, co.duration_value, co.duration_unit, co.study_load, co.empty_reason_code
    from catalogue.courses co join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
   where co.lifecycle_status = 'active' and mod(abs(hashtext(co.id::text)), v_parts) = v_part),
cov as (
  select x.course_id, jsonb_object_agg(x.attribute, jsonb_build_object('s', x.state, 'a', x.absence_class)) m
    from pipeline.course_attribute_coverage x join c using (course_id) group by x.course_id),
lnk as (
  select distinct on (l.course_id) l.course_id, l.url
    from catalogue.course_links l join c using (course_id)
   where l.status = 'active' and l.link_type = 'official_course' order by l.course_id, l.is_primary desc nulls last, l.updated_at desc nulls last),
fee as (
  select distinct on (f.course_id) f.course_id, f.amount, f.currency_code, f.fee_year, coalesce(f.basis, f.load_basis) basis
    from catalogue.course_fees f join c using (course_id)
   where f.status = 'active' and f.fee_type in ('provider_current_tuition', 'tuition') and f.amount is not null
   order by f.course_id, (f.fee_type = 'provider_current_tuition') desc, f.fee_year desc nulls last),
itk as (
  select i.course_id,
         string_agg(distinct to_char(i.start_date, 'YYYY-MM-DD'), ' ') filter (where i.start_date is not null) dates,
         count(*) filter (where i.start_date is null and nullif(btrim(coalesce(i.intake_label, '')), '') is not null) label_only,
         string_agg(distinct to_char(i.application_deadline, 'YYYY-MM-DD'), ' ') filter (where i.application_deadline is not null) deadlines
    from catalogue.course_intakes i join c using (course_id) where coalesce(i.status, 'active') = 'active' group by i.course_id),
eng as (
  select e.course_id, string_agg(distinct coalesce(t.code, t.name) || ' ' || e.overall_score::text, ', ') v
    from catalogue.course_english_requirements e join c using (course_id) left join ref.english_tests t on t.id = e.english_test_id
   where e.status = 'active' and e.overall_score is not null group by e.course_id),
aca as (select distinct a.course_id from catalogue.course_academic_options a join c using (course_id)),
cmp as (
  select distinct on (x.course_id) x.course_id, k.postcode, k.city
    from catalogue.course_campuses x join c using (course_id) join catalogue.campuses k on k.id = x.campus_id
   order by x.course_id, x.is_primary desc nulls last, k.is_primary desc nulls last),
loc as (
  select m.course_id, l.id locality_id, l.name,
         exists (select 1 from destination.locality_postcodes q where q.country_code = c.cc and q.postcode = m.postcode and q.needs_layer4_review) pending
    from cmp m join c using (course_id)
    left join lateral (select l2.id, l2.name from destination.locality_postcodes p join destination.localities l2 on l2.id = p.locality_id
                        where p.country_code = c.cc and p.postcode = nullif(btrim(m.postcode), '') and p.is_primary_match and l2.status in ('approved', 'published')
                        order by p.boundary_vintage desc limit 1) l on true),
lm as (select locality_id, count(*) n from destination.locality_metrics where status = 'approved' group by locality_id),
loc_on as (select distinct country_code from destination.localities where status in ('approved', 'published')),
lm_on as (select distinct l.country_code from destination.locality_metrics m join destination.localities l on l.id = m.locality_id where m.status = 'approved'),
car as (select k.iso_alpha2::text cc, count(*) n from destination.career_outcomes o join ref.countries k on k.id = o.country_id where o.status = 'approved' group by 1),
sch as (
  select m.course_id, count(distinct m.scholarship_id) n
    from scholarship.course_mappings m join c using (course_id) join scholarship.scholarships s on s.id = m.scholarship_id
   where m.mapping_state = 'mapped' and s.lifecycle_status = 'active' and s.publication_status = 'published' group by m.course_id),
psch as (
  select s.provider_id, count(*) filter (where s.publication_status = 'published') published, count(*) filter (where s.publication_status = 'unpublished') pending
    from scholarship.scholarships s where s.lifecycle_status = 'active' and s.provider_id in (select provider_id from c) group by s.provider_id),
cell as (
  select c.*, cov.m, lnk.url, fee.amount, fee.currency_code, fee.fee_year, fee.basis, itk.dates, itk.label_only, itk.deadlines, eng.v eng_v,
         (aca.course_id is not null or cov.m->'academic_entry'->>'s' = 'admitted') aca_ok, cmp.course_id is not null has_campus, cmp.postcode,
         loc.name loc_name, loc.locality_id, coalesce(loc.pending, false) loc_pending, lm.n lm_n, car.n car_n, sch.n sch_n,
         psch.published p_sch_pub, psch.pending p_sch_pending,
         c.cc in (select country_code from loc_on) loc_country_on, c.cc in (select country_code from lm_on) lm_country_on
    from c left join cov using (course_id) left join lnk using (course_id) left join fee using (course_id) left join itk using (course_id)
    left join eng using (course_id) left join aca using (course_id) left join cmp using (course_id) left join loc using (course_id)
    left join lm on lm.locality_id = loc.locality_id left join car on car.cc = c.cc left join sch using (course_id) left join psch on psch.provider_id = c.provider_id),
st as (  -- the coverage state of each attribute as a readiness state
  select x.course_id, k.attr,
         case when x.m->k.attr->>'s' in ('in_queue', 'in_review', 'awaiting_l3', 'candidate', 'page_found') then 'TRYING'
              when x.m->k.attr->>'a' = 'evidence_pending' then 'TRYING'
              when x.m->k.attr->>'s' = 'not_on_page' or x.m->k.attr->>'a' in ('explicitly_not_stated', 'not_applicable', 'not_on_this_page') then 'NOT_POSSIBLE'
              else 'POSSIBLE_NEEDS_SOURCE' end s
    from cell x cross join unnest(array['official_url', 'description', 'provider_tuition', 'intakes', 'deadline', 'duration', 'campus', 'academic_entry', 'english']) k(attr)),
sx as (select course_id, jsonb_object_agg(attr, s) s from st group by course_id),
  r as (
    select x.course_id, x.cc country_code, x.provider_id, left(x.provider_name, 120) provider_name, left(x.title, 160) course_title,
      jsonb_build_object(
        'official_url', coalesce(left(x.url, 80), sx.s->>'official_url'),
        'description', case when nullif(btrim(coalesce(x.description, '')), '') is not null then left(regexp_replace(btrim(x.description), '\s+', ' ', 'g'), 80) else sx.s->>'description' end,
        'study_load', case when x.study_load is not null then left(x.study_load::text, 80)
                           when x.empty_reason_code = 'pending_extraction' then 'TRYING'
                           when x.empty_reason_code in ('not_published_by_provider', 'online_only_no_campus') then 'NOT_POSSIBLE'
                           when x.empty_reason_code in ('source_unavailable', 'not_listed_on_register') then 'POSSIBLE_NEEDS_SOURCE'
                           when x.url is not null then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
        'tuition_fee', case when x.amount is not null then left(coalesce(x.currency_code, '') || ' ' || trim(to_char(x.amount, 'FM999,999,990.00')) || coalesce(' (' || x.fee_year || ')', ''), 80)
                            else sx.s->>'provider_tuition' end,
        'fee_basis', case when x.amount is not null and x.basis is not null then left(x.basis, 80) when x.amount is not null then 'NOT_POSSIBLE' else sx.s->>'provider_tuition' end,
        'intake_dates', case when x.dates is not null then left(x.dates, 80) when x.label_only > 0 then 'NOT_POSSIBLE' else sx.s->>'intakes' end,
        'application_deadlines', coalesce(left(x.deadlines, 80), sx.s->>'deadline'),
        'duration', case when x.duration_value is not null then left(x.duration_value::text || coalesce(' ' || x.duration_unit, ''), 80) else sx.s->>'duration' end,
        'campus_locality', case when x.loc_name is not null then left(x.loc_name, 80) when not x.loc_country_on then 'EMPTY_NOT_STARTED'
                                when not x.has_campus then case when x.empty_reason_code = 'online_only_no_campus' then 'NOT_POSSIBLE' else sx.s->>'campus' end
                                when x.loc_pending then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
        'aer_academic', case when x.aca_ok then 'Admitted' when x.cc = 'CA' then 'EMPTY_NOT_STARTED' else sx.s->>'academic_entry' end,
        'english_requirements', coalesce(left(x.eng_v, 80), sx.s->>'english'),
        'scholarships', case when x.sch_n > 0 then x.sch_n || ' scholarship' || case when x.sch_n > 1 then 's' else '' end
                             when coalesce(x.p_sch_pub, 0) > 0 then 'NOT_POSSIBLE' when coalesce(x.p_sch_pending, 0) > 0 then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
        'destination_city_stats', case when not x.lm_country_on then 'EMPTY_NOT_STARTED' when x.lm_n > 0 then left(x.lm_n || ' figures, ' || x.loc_name, 80)
                                       when not x.has_campus and x.empty_reason_code = 'online_only_no_campus' then 'NOT_POSSIBLE'
                                       when x.loc_pending then 'TRYING' else 'POSSIBLE_NEEDS_SOURCE' end,
        'career_outcomes', case when x.car_n > 0 then x.car_n || ' occupations (national)' else 'EMPTY_NOT_STARTED' end
      ) cells
    from cell x left join sx using (course_id)),
  -- readiness rules: end
  e as (select r.provider_id, r.provider_name, r.country_code, f.key field,
               case when f.value #>> '{}' in ('TRYING', 'POSSIBLE_NEEDS_SOURCE', 'NOT_POSSIBLE', 'EMPTY_NOT_STARTED') then f.value #>> '{}' else 'ADMITTED' end s
          from r cross join lateral jsonb_each(r.cells) f),
  pc as (select r.provider_id, count(*) n from r group by 1),
  g as (select e.provider_id, max(e.provider_name) name, max(e.country_code) cc, e.field,
               jsonb_build_array(count(*) filter (where e.s = 'ADMITTED'), count(*) filter (where e.s = 'TRYING'), count(*) filter (where e.s = 'POSSIBLE_NEEDS_SOURCE'),
                                 count(*) filter (where e.s = 'NOT_POSSIBLE'), count(*) filter (where e.s = 'EMPTY_NOT_STARTED')) c
          from e group by e.provider_id, e.field)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.provider_id, 'name', p.name, 'cc', p.cc, 'courses', pc.n, 'f', p.f) order by p.provider_id), '[]'::jsonb), count(*)
    into v_payload, v_n
    from (select g.provider_id, max(g.name) name, max(g.cc) cc, jsonb_object_agg(g.field, g.c) f from g group by g.provider_id) p join pc using (provider_id);
  insert into pipeline.job_input_marks as s (job_key, last_full_at, last_run_at, last_result, runs_done, runs_skipped)
  values ('course-field-readiness:p' || v_part, now(), now(),
          jsonb_build_object('part', v_part, 'parts', v_parts, 'providers', v_payload, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000)), 1, 0)
  on conflict (job_key) do update set last_full_at = excluded.last_full_at, last_run_at = excluded.last_run_at, last_result = excluded.last_result, runs_done = s.runs_done + 1;
  -- the day's mark, once every part has been built today: admitted courses by provider and field
  if not exists (select 1 from generate_series(0, v_parts - 1) k(p) left join pipeline.job_input_marks s on s.job_key = 'course-field-readiness:p' || k.p
                  where s.last_run_at is null or (s.last_run_at at time zone 'Australia/Sydney')::date < v_day or (s.last_result->>'parts')::int <> v_parts)
     and not coalesce((select s.last_result->'days' ? v_day::text from pipeline.job_input_marks s where s.job_key = 'course-field-readiness:days'), false) then
    insert into pipeline.job_input_marks as s (job_key, last_full_at, last_run_at, last_result, runs_done, runs_skipped)
    select 'course-field-readiness:days', now(), now(), jsonb_build_object('days', jsonb_build_object(v_day::text, m.marks)), 1, 0
      from (select jsonb_object_agg(x->>'provider_id', (select jsonb_object_agg(f.key, f.value->0) from jsonb_each(x->'f') f)) marks
              from pipeline.job_input_marks s0 cross join lateral jsonb_array_elements(s0.last_result->'providers') x
             where s0.job_key like 'course-field-readiness:p%' and (s0.last_result->>'parts')::int = v_parts) m
    on conflict (job_key) do update
       set last_result = jsonb_build_object('days', (select jsonb_object_agg(d.key, d.value) from (select d0.key, d0.value from jsonb_each(coalesce(s.last_result->'days', '{}'::jsonb) || excluded.last_result->'days') d0
                                                                                              order by d0.key desc limit v_keep) d)),
           last_run_at = now(), runs_done = s.runs_done + 1;
  end if;
  perform security.course_field_readiness_summary_v1();
  return jsonb_build_object('part', v_part, 'parts', v_parts, 'providers', v_n, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $function$;

create or replace function security.course_field_readiness_tabs_v1()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
-- s776: the rows of the summary tabs of the Google Sheet Stakeholder_Course_Readiness_Summary (Drive › Monitoring), from
-- course-field-readiness:summary, written from A1 by the hourly telemetry sync. Executive_Summary and By_Provider_Action_List keep the layout of
-- scripts/telemetry/course-field-readiness.mjs (sheetTabs); Field_ETA_Forecast keeps its columns. Read only.
declare v_s jsonb := (select s.last_result from pipeline.job_input_marks s where s.job_key = 'course-field-readiness:summary');
        v_all jsonb; v_n int; v_at text; v_title text; v_exec jsonb; v_eta jsonb; v_prov jsonb; v_from text; v_days int;
begin
  if v_s is null then return null; end if;
  v_all := v_s->'scopes'->'ALL'; v_n := (v_all->>'courses')::int; v_from := v_s->>'velocity_from'; v_days := (v_s->>'velocity_days')::int;
  v_at := to_char((v_s->>'oldest_part_at')::timestamptz at time zone 'Australia/Sydney', 'YYYY-MM-DD HH24:MI');
  v_title := format('Course field readiness, %s (AEDT), %s active courses: %s', v_at, to_char(v_n, 'FM999,999,999'),
             (select string_agg(k || ' ' || to_char((v_s->'scopes'->k->>'courses')::int, 'FM999,999,999'), ', ' order by k) from jsonb_object_keys(v_s->'scopes') k where k <> 'ALL'));
  -- Executive_Summary: counts as values, percentages and the row check as formulas over them (B2 is the number of active courses)
  select jsonb_build_array(jsonb_build_array(v_title),
           jsonb_build_array('Active courses', v_n, format('Source: hourly readiness snapshot (rollup target course-field-readiness), oldest part built %s AEDT', v_at)),
           '[]'::jsonb,
           jsonb_build_array('Field', 'Admitted', 'Admitted %', 'Trying', 'Trying %', 'Possible, needs a source', 'Possible, needs a source %', 'Not possible', 'Not possible %',
                             'Empty, not started', 'Empty, not started %', 'Row check (equals B2)'))
         || coalesce(jsonb_agg(jsonb_build_array(x.field, x.a, format('=IF($B$2=0,0,B%s/$B$2)', x.r), x.t, format('=IF($B$2=0,0,D%s/$B$2)', x.r), x.ns,
                     format('=IF($B$2=0,0,F%s/$B$2)', x.r), x.np, format('=IF($B$2=0,0,H%s/$B$2)', x.r), x.em, format('=IF($B$2=0,0,J%s/$B$2)', x.r),
                     format('=B%1$s+D%1$s+F%1$s+H%1$s+J%1$s', x.r)) order by x.r), '[]'::jsonb)
    into v_exec
    from (select f.field, (v_all->'f'->f.field->>0)::int a, (v_all->'f'->f.field->>1)::int t, (v_all->'f'->f.field->>2)::int ns, (v_all->'f'->f.field->>3)::int np,
                 (v_all->'f'->f.field->>4)::int em, f.ord + 4 r
            from unnest(array['official_url', 'description', 'study_load', 'tuition_fee', 'fee_basis', 'intake_dates', 'application_deadlines', 'duration',
                              'campus_locality', 'aer_academic', 'english_requirements', 'scholarships', 'destination_city_stats', 'career_outcomes']) with ordinality f(field, ord)) x;
  -- Field_ETA_Forecast: the same columns as before, one row per field, most admitted first
  select jsonb_build_array(
           jsonb_build_array('Course Field Pipeline Readiness & 100% Achievable Target ETA Forecast'),
           jsonb_build_array(format('Snapshot: %s (AEDT, refreshed hourly) | Scope: %s Active Courses (%s) | Velocity: %s | API: v3 Canonical', v_at, to_char(v_n, 'FM999,999,999'),
             (select string_agg(k || ': ' || to_char((v_s->'scopes'->k->>'courses')::int, 'FM999,999,999'), ' • ' order by k) from jsonb_object_keys(v_s->'scopes') k where k <> 'ALL'),
             case when v_days is null then 'measured from the second day of marks' else format('admitted courses a day over %s day%s since %s', v_days, case when v_days = 1 then '' else 's' end, v_from) end)),
           jsonb_build_array('TOTAL ACTIVE COURSES', '', '', 'FIELDS ABOVE 70% ADMITTED', '', '', 'ACTIVE PIPELINE QUEUE'),
           jsonb_build_array(to_char(v_n, 'FM999,999,999'), '', '',
             format('%s of 14 fields', (select count(*) from jsonb_each(v_all->'f') f where (f.value->>0)::numeric >= 0.7 * v_n)), '', '',
             format('%s in Trying', to_char((select sum((f.value->>1)::int) from jsonb_each(v_all->'f') f), 'FM999,999,999'))),
           '[]'::jsonb, '[]'::jsonb,
           jsonb_build_array('Canonical API v3 Field', 'Admitted Now', 'Trying / In Pipeline', 'Possible / Needs Source', 'Not Possible / Not Published', 'Empty / Wave 2',
                             'Current Observed Velocity', 'Primary Bottleneck / Dependency', 'Expected 100% Achievable Target ETA'))
         || coalesce(jsonb_agg(jsonb_build_array(e->>'field',
              format('%s (%s%%)', to_char((e->>'admitted')::int, 'FM999,999,990'), to_char(100.0 * (e->>'admitted')::int / nullif(v_n, 0), 'FM990.0')),
              format('%s (%s%%)', to_char((e->>'trying')::int, 'FM999,999,990'), to_char(100.0 * (e->>'trying')::int / nullif(v_n, 0), 'FM990.0')),
              format('%s (%s%%)', to_char((e->>'needs_source')::int, 'FM999,999,990'), to_char(100.0 * (e->>'needs_source')::int / nullif(v_n, 0), 'FM990.0')),
              format('%s (%s%%)', to_char((e->>'not_possible')::int, 'FM999,999,990'), to_char(100.0 * (e->>'not_possible')::int / nullif(v_n, 0), 'FM990.0')),
              format('%s (%s%%)', to_char((e->>'wave2')::int, 'FM999,999,990'), to_char(100.0 * (e->>'wave2')::int / nullif(v_n, 0), 'FM990.0')),
              case when e->>'velocity' is null then 'Not measured yet' else format('%s%s admitted/day', case when (e->>'velocity')::numeric > 0 then '+' else '' end, to_char((e->>'velocity')::numeric, 'FM999,990.0')) end,
              case e->>'bottleneck' when 'trying' then format('%s in the pipeline (queued or being read)', to_char((e->>'trying')::int, 'FM999,999,990'))
                                    when 'needs_source' then format('%s need a source page found', to_char((e->>'needs_source')::int, 'FM999,999,990'))
                                    when 'not_possible' then format('%s not published by the provider', to_char((e->>'not_possible')::int, 'FM999,999,990'))
                                    when 'wave2' then format('%s in Wave 2 (country scope not started)', to_char((e->>'wave2')::int, 'FM999,999,990')) else 'None' end,
              case e->>'eta_state' when 'complete' then 'Complete for every achievable course'
                                   when 'forecast' then format('~%s days (%s) for %s remaining', e->>'eta_days', to_char((now() at time zone 'Australia/Sydney')::date + (e->>'eta_days')::int, 'DD Mon YYYY'), to_char((e->>'remaining')::int, 'FM999,999,990'))
                                   when 'no_progress' then format('No admitted gain over the window; %s remaining', to_char((e->>'remaining')::int, 'FM999,999,990'))
                                   else format('Forecast once velocity is measured; %s remaining', to_char((e->>'remaining')::int, 'FM999,999,990')) end)
              order by (e->>'admitted')::int desc, e->>'field'), '[]'::jsonb)
    into v_eta
    from jsonb_array_elements(security.course_field_eta_v1('all')->'fields') e;
  -- By_Provider_Action_List: providers with cells needing a source, most first (top 100), as the daily export
  select jsonb_build_array(jsonb_build_array('rank', 'provider_name', 'country_code', 'active_courses', 'cells_possible_needs_source', 'cells_trying', 'top_fields_needing_a_source', 'provider_id'))
         || coalesce(jsonb_agg(jsonb_build_array(y.rk, y.name, y.cc, y.n, y.ns, y.t, y.top, y.pid) order by y.rk), '[]'::jsonb)
    into v_prov
    from (select row_number() over (order by x.ns desc, x.n desc, x.name) rk, x.* from (
            select p.key pid, p.value->>'name' name, p.value->>'cc' cc, (p.value->>'courses')::int n,
                   (select sum((f.value->>2)::int) from jsonb_each(p.value->'f') f) ns, (select sum((f.value->>1)::int) from jsonb_each(p.value->'f') f) t,
                   (select string_agg(format('%s (%s)', z.key, z.c), '; ' order by z.c desc, z.key) from (select f.key, (f.value->>2)::int c from jsonb_each(p.value->'f') f
                     where (f.value->>2)::int > 0 order by 2 desc, 1 limit 3) z) top
              from jsonb_each(v_s->'providers') p) x where x.ns > 0 order by x.ns desc, x.n desc, x.name limit 100) y;  -- fixed: the top 100, as the daily export
  return jsonb_build_object('snapshot_at', v_s->'oldest_part_at', 'Executive_Summary', v_exec, 'Field_ETA_Forecast', v_eta, 'By_Provider_Action_List', v_prov);
end $function$;

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- 4. the screen's read: one more action on the existing internal coverage read
select pg_temp.cf_edit_def('public.admin_field_coverage(text,jsonb)'::regprocedure, 'bc8b60cb359741753cecabe2449aa30e',
  array[$o$  elsif p_action = 'run_now' then
$o$],
  array[$n$  elsif p_action = 'pipeline_eta' then
    -- s777 (Platform Admin 19 Nov 2026 15:36): Coverage & completeness › Pipeline & field ETA, from the readiness snapshot (any StudySearch role)
    return security.course_field_eta_v1(coalesce(p_args->>'scope', 'all'), v_cc, v_pid, p_args->>'q');
  elsif p_action = 'run_now' then
$n$]);

-- 6. one part a run on the rollup scheduler
insert into pipeline.rollup_targets(target_code, legacy_job, call_sql, call_md5, schedule, rollup_group, priority, enabled, mode, expected_ms, note)
values ('course-field-readiness', null, 'select security.course_field_readiness_build_v1()', md5('select security.course_field_readiness_build_v1()'), '*/4 * * * *', 'A', 90, true, 'live', 20000,
        's777 (19 Nov 2026): one part of the course field readiness snapshot a run (readiness.snapshot_parts, 16), all parts about every hour; '
        || 'read by Coverage & completeness › Pipeline & field ETA and the hourly stakeholder sheet (s776). expected_ms is the measured run.');

revoke all on function security.course_field_readiness_build_v1(integer) from public, anon, authenticated;
revoke all on function security.course_field_readiness_summary_v1() from public, anon, authenticated;
revoke all on function security.course_field_eta_v1(text, text, uuid, text) from public, anon, authenticated;
revoke all on function security.course_field_readiness_tabs_v1() from public, anon, authenticated;

comment on function security.course_field_readiness_build_v1(integer) is 's777 (19 Nov 2026): builds one part of the course field readiness snapshot (pipeline.job_input_marks course-field-readiness:p<n>), keeps the day''s mark, merges the summary.';
comment on function security.course_field_readiness_summary_v1() is 's777 (19 Nov 2026): merges the readiness parts by provider, country and all courses, with the 7-day observed velocity (course-field-readiness:summary).';
comment on function security.course_field_eta_v1(text, text, uuid, text) is 's777 (19 Nov 2026): Pipeline & field ETA rows for all courses, a country or a provider, from course-field-readiness:summary. Read only.';
comment on function security.course_field_readiness_tabs_v1() is 's776 (19 Nov 2026): the rows of the Stakeholder_Course_Readiness_Summary summary tabs, from course-field-readiness:summary. Read only.';

-- post-checks
do $$
declare v_t timestamptz; v_ms numeric; v jsonb; v_e jsonb; v_tabs jsonb; v_ms_eta numeric; v_ms_tabs numeric; v_ms_rpc numeric;
begin
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'course-field-readiness' and mode = 'live' and enabled and call_md5 = md5(call_sql)) then
    raise exception 'post-check: rollup target course-field-readiness is not live';
  end if;
  if position('pipeline_eta' in (select prosrc from pg_proc where oid = 'public.admin_field_coverage(text,jsonb)'::regprocedure)) = 0 then
    raise exception 'post-check: admin_field_coverage has no pipeline_eta action';
  end if;
  -- two parts built, as two runs would
  v_t := clock_timestamp();
  v := security.course_field_readiness_build_v1(0);
  perform security.course_field_readiness_build_v1(1);
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000 / 2;
  v_t := clock_timestamp(); v_e := security.course_field_eta_v1('all'); v_ms_eta := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp(); perform security.course_field_eta_v1('country', 'AU', null, 'univ'); v_ms_rpc := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp(); v_tabs := security.course_field_readiness_tabs_v1(); v_ms_tabs := extract(epoch from clock_timestamp() - v_t) * 1000;
  if jsonb_array_length(v_e->'fields') <> 14 then raise exception 'post-check: % fields in the ETA rows, not 14', jsonb_array_length(v_e->'fields'); end if;
  if jsonb_array_length(v_tabs->'Executive_Summary') <> 18 or jsonb_array_length(v_tabs->'Field_ETA_Forecast') <> 21 then
    raise exception 'post-check: the sheet tabs have % and % rows (18 and 21 expected)', jsonb_array_length(v_tabs->'Executive_Summary'), jsonb_array_length(v_tabs->'Field_ETA_Forecast');
  end if;
  perform set_config('cf.diag', format('s777 part_ms=%s eta_ms=%s eta_country_ms=%s tabs_ms=%s courses_in_2_parts=%s first=%s tabs_rows=%s/%s/%s; ', round(v_ms), round(v_ms_eta), round(v_ms_rpc), round(v_ms_tabs),
     v_e->>'courses', v_e->'fields'->0, jsonb_array_length(v_tabs->'Executive_Summary'), jsonb_array_length(v_tabs->'Field_ETA_Forecast'), jsonb_array_length(v_tabs->'By_Provider_Action_List')), true);
  if v_ms_eta > 500 or v_ms_rpc > 500 then raise exception 'post-check: the ETA read took % ms and % ms', round(v_ms_eta), round(v_ms_rpc); end if;  -- fixed: the screen budget
  if v_ms > 30000 then raise exception 'post-check: one readiness part took % ms', round(v_ms); end if;  -- fixed: post-check bound
end $$;
