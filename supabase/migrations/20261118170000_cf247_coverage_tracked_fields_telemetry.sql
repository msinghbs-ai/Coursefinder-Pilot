-- CF-247 Coverage & completeness modernisation (S1-RM-Design; Platform Admin 18 Nov 2026 12:19: "metadata-driven tracked-field registry with
-- no hardcoded 15-attribute ceiling", "Courses by attributes admitted 0 of N through N of N", "field-by-field coverage bar chart with a +7d velocity
-- sparkline", "country x domain readiness grid: AU, NZ, CA, UK, IE, US x Courses, Providers & Campuses, AER & Grade Scales, Scholarships,
-- Destination Editions").
-- What it adds:
--   * pipeline.tracked_fields: what the coverage screen shows for each field recorded in pipeline.field_coverage_daily (domain, label, target,
--     whether it counts in the course score, where to act). Separate from pipeline.field_register, which drives the readers: a row here changes
--     no reader. A field recorded daily with no row here is still shown (under its code, flagged Not labelled), so a new field never needs code.
--   * security.tracked_field_coverage_v1(): the generic recorder for the domains field_coverage_daily did not measure: scholarships (award
--     value, closing date, course links, published), destination editions (published with approved terms) and grade scale conversions (active).
--     field_coverage_record_v1 (hourly, rollup-scheduler) adds its rows; replaced only from its known definition.
--   * public.admin_coverage_telemetry_v1(jsonb): fields with the latest fill, the change over coverage.velocity_days and a daily series of
--     coverage.spark_days; courses by in-score fields admitted (0 of N to N of N, N from the registry); the country x domain grid.
--   * Settings coverage.velocity_days and coverage.spark_days (G2).
-- Nothing is dropped or deleted. No consumer API object (G3 75/48). No new job (G1: the recorder runs in the existing hourly target).
-- Replaces: the hardcoded attribute list and the 7-attribute score bands of Coverage & completeness › Courses (src/course-coverage.jsx, kept for
--   the per-attribute stages and course lists).
-- Retires: the screens Coverage & completeness › Courses › Portals that supply course links (Link refresh supply rows) and Coverage &
--   completeness › Attributes › Stalled fields (counters); marked retiring below. Their functions stay (security.field_stalled_v1 is still read
--   by the health checks); a deep link to Layer 4 › Inbox or Platform health › Queues & yield appears only where a field is below its target.

-- 0. Pre-check: the recorder is replaced only from the definition read live on 18 Nov 2026
do $pre$
begin
  if md5(pg_get_functiondef('security.field_coverage_record_v1()'::regprocedure)) <> '769e1a9dfe1c9219c3bba02fa63e5e40' then
    raise exception 'pre-check: security.field_coverage_record_v1 differs from the definition this change extends';
  end if;
end $pre$;

-- 1. Settings
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'coverage.velocity_days', 'Coverage: change measured over',
   'Coverage & completeness compares each field''s fill now with its fill this many days earlier (the +7d figure beside each bar).',
   'number', to_jsonb(7), 1, 60, 'days', 980, 'Coverage', 'public.admin_coverage_telemetry_v1 (Coverage & completeness › Courses)', 'CF-247 S1-RM-Design, Platform Admin 18 Nov 2026 12:19 (+7d velocity)'),
  ('pipeline', 'coverage.spark_days', 'Coverage: days in each field''s trend line',
   'The small trend line beside each field shows its daily fill for this many days (field_coverage_daily keeps 120).',
   'number', to_jsonb(14), 7, 120, 'days', 981, 'Coverage', 'public.admin_coverage_telemetry_v1 (Coverage & completeness › Courses)', 'CF-247 S1-RM-Design, Platform Admin 18 Nov 2026 12:19 (velocity sparkline)')
on conflict (toolset_key, key) do nothing;

-- 2. The registry
create table if not exists pipeline.tracked_fields (
  field text primary key,
  domain text not null check (domain in ('courses', 'providers', 'aer', 'scholarships', 'destinations')),
  label text,
  level text not null default 'course' check (level in ('course', 'provider', 'scholarship', 'edition', 'reference')),
  target_pct numeric check (target_pct is null or (target_pct >= 0 and target_pct <= 100)),
  in_score boolean not null default false,
  action_href text check (action_href is null or action_href ~ '^#[a-z0-9-]+(\?[a-z0-9_=&-]+)?$'),
  action_label text,
  sort integer not null default 100,
  active boolean not null default true,
  note text,
  added_on date not null default ((now() at time zone 'Australia/Melbourne')::date),
  updated_at timestamptz not null default now()
);
comment on table pipeline.tracked_fields is 'CF-247 S1-RM-Design (Platform Admin 18 Nov 2026 12:19): how Coverage & completeness shows each field recorded in pipeline.field_coverage_daily: its domain (courses, providers, aer, scholarships, destinations), label (null follows pipeline.field_register), target, whether it counts in the course score (fields admitted, 0 of N to N of N) and where to act when it is below target. Read by public.admin_coverage_telemetry_v1 only; no reader or job reads it. A recorded field with no row is still shown, under its code.';
alter table pipeline.tracked_fields enable row level security;
revoke all on pipeline.tracked_fields from public, anon, authenticated;

insert into pipeline.tracked_fields (field, domain, label, level, target_pct, in_score, action_href, action_label, sort, note) values
  -- Courses (labels and targets follow pipeline.field_register where it has the field)
  ('official_url', 'courses', null, 'course', null, true, '#layer-4-review?kind=course_link', 'Course links in Layer 4', 10, null),
  ('level', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 11, null),
  ('field_of_study', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 12, null),
  ('duration', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 13, null),
  ('delivery', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 14, null),
  ('campus', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 15, null),
  ('campus_city', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 16, null),
  ('international', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 17, null),
  ('provider_tuition', 'courses', null, 'course', null, true, '#layer-4-review?kind=fee_check', 'Fee checks in Layer 4', 18, null),
  ('registered_tuition', 'courses', null, 'course', null, true, null, null, 19, 'From the register; nothing to act on here'),
  ('intakes', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 20, null),
  ('deadline', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 21, null),
  ('english', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 22, null),
  ('description', 'courses', null, 'course', null, true, '#platform-health?tab=queues', 'Queues & yield', 23, null),
  ('v3_study_load', 'courses', 'Study load (API v3)', 'course', 80, false, '#platform-health?tab=queues', 'Boost queue', 24, 'Read by Boost; refused readings go to Layer 4'),
  ('v3_empty_reason', 'courses', 'Empty reason, courses with no campus (API v3)', 'course', 80, false, null, null, 25, null),
  -- Providers & campuses
  ('p_website', 'providers', null, 'provider', null, false, '#layer-4-review?kind=website_needed', 'Website needed in Layer 4', 30, null),
  ('p_address', 'providers', null, 'provider', null, false, '#platform-health?tab=queues', 'Queues & yield', 31, null),
  ('p_campuses', 'providers', null, 'provider', null, false, '#platform-health?tab=queues', 'Queues & yield', 32, null),
  ('p_type', 'providers', null, 'provider', null, false, null, null, 33, 'From the register'),
  ('p_international', 'providers', null, 'provider', null, false, null, null, 34, 'From the register'),
  ('p_logo', 'providers', null, 'provider', null, false, '#platform-health?tab=queues', 'Queues & yield', 35, null),
  ('p_contact', 'providers', null, 'provider', null, false, '#platform-health?tab=queues', 'Queues & yield', 36, null),
  ('p_description', 'providers', null, 'provider', null, false, '#layer-4-review?kind=provider_description', 'Descriptions in Layer 4', 37, null),
  ('p_registrations', 'providers', 'Registrations', 'provider', 80, false, null, null, 38, null),
  ('v3_campus_primary', 'providers', 'Primary campus set (API v3)', 'provider', 80, false, null, null, 39, null),
  ('v3_accreditations', 'providers', 'Accreditations (API v3)', 'provider', 80, false, null, null, 40, 'Loaded from Layer 1 sources (provider_accreditations)'),
  -- AER & grade scales
  ('academic_entry', 'aer', null, 'course', null, true, '#layer-4-review?kind=aer_review', 'Entry requirements in Layer 4', 50, null),
  ('p_entry_matrix', 'aer', 'Provider entry matrix', 'provider', 80, false, '#layer-4-review?kind=aer_review', 'Entry requirements in Layer 4', 51, null),
  ('v3_grade_normalised', 'aer', 'Grades normalised to 0-100 (API v3)', 'provider', 80, false, '#reference-data', 'Reference data', 52, 'Needs active grade scale conversions'),
  ('g_scale_conversions', 'aer', 'Grade scale conversions active', 'reference', 80, false, '#reference-data', 'Reference data', 53, 'Loaded inactive; a person reviews them'),
  -- Scholarships
  ('p_scholarships', 'scholarships', null, 'provider', null, false, '#scholarships?tab=coverage', 'Scholarships › Coverage', 60, null),
  ('s_award_value', 'scholarships', 'Award value held', 'scholarship', 80, false, '#scholarships?tab=coverage', 'Scholarships › Coverage', 61, null),
  ('s_close_date', 'scholarships', 'Closing date held', 'scholarship', 80, false, '#scholarships?tab=coverage', 'Scholarships › Coverage', 62, null),
  ('s_course_links', 'scholarships', 'Linked to courses', 'scholarship', 80, false, '#layer-4-review', 'Scholarship course links in Layer 4', 63, null),
  ('s_published', 'scholarships', 'Published', 'scholarship', 80, false, '#scholarships?tab=coverage', 'Scholarships › Coverage', 64, null),
  -- Destination editions
  ('d_editions_published', 'destinations', 'Editions published with approved terms', 'edition', 100, false, '#destination-data', 'Destination data', 70, null),
  ('v3_destination', 'destinations', 'Destination rows in published editions (API v3)', 'edition', 100, false, '#destination-data', 'Destination data', 71, null)
on conflict (field) do nothing;

-- 3. The generic recorder for the domains field_coverage_daily did not measure
create or replace function security.tracked_field_coverage_v1()
returns table(country_code text, field text, total bigint, filled bigint)
language sql stable security definer set search_path to 'pg_catalog', 'public' as $function$
  with s as (
    select k.iso_alpha2::text cc, x.id, x.award_amount, x.award_percentage, x.application_close_date, x.publication_status
      from scholarship.scholarships x
      join catalogue.providers p on p.id = x.provider_id
      join ref.countries k on k.id = p.country_id
     where x.lifecycle_status = 'active')
  select cc, 's_award_value', count(*), count(*) filter (where award_amount is not null or award_percentage is not null) from s group by cc
  union all
  select cc, 's_close_date', count(*), count(*) filter (where application_close_date is not null) from s group by cc
  union all
  select cc, 's_course_links', count(*), count(*) filter (where exists (select 1 from scholarship.course_mappings m where m.scholarship_id = s.id)) from s group by cc
  union all
  select cc, 's_published', count(*), count(*) filter (where publication_status = 'published') from s group by cc
  union all
  select k.iso_alpha2::text, 'd_editions_published', count(*), count(*) filter (where e.status = 'published' and e.terms_status = 'approved')
    from destination.editions e join ref.countries k on k.id = e.country_id group by 1
  union all
  select k.iso_alpha2::text, 'g_scale_conversions', count(*), count(*) filter (where g.is_active)
    from ref.grade_scale_conversions g join ref.countries k on k.id = g.country_id group by 1
$function$;
comment on function security.tracked_field_coverage_v1() is 'CF-247 S1-RM-Design (18 Nov 2026): per country, the scholarship, destination edition and grade scale figures recorded hourly into pipeline.field_coverage_daily by security.field_coverage_record_v1.';
revoke all on function security.tracked_field_coverage_v1() from public, anon, authenticated;

create or replace function security.field_coverage_record_v1()
 returns integer
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
  union all  -- 16 Nov 2026: API v3 and request-register fields (security.api_v3_field_coverage_v1)
  select (now() at time zone 'Australia/Melbourne')::date, v.country_code, v.field, v.total, v.filled from security.api_v3_field_coverage_v1() v
  union all  -- 18 Nov 2026: scholarships, destination editions and grade scales (security.tracked_field_coverage_v1)
  select (now() at time zone 'Australia/Melbourne')::date, t.country_code, t.field, t.total, t.filled from security.tracked_field_coverage_v1() t
  on conflict (snapshot_date, country_code, field) do update set total = excluded.total, filled = excluded.filled, computed_at = now();
  get diagnostics v = row_count;
  delete from pipeline.field_coverage_daily where snapshot_date < current_date - 120;  -- fixed: history kept 120 days (derived figures, rebuilt hourly)
  return v;
end $function$;

-- 4. The read
create or replace function public.admin_coverage_telemetry_v1(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v_cc text := nullif(upper(btrim(coalesce(p_args->>'country', ''))), '');
  v_vel int := security.pipeline_num_v1('coverage.velocity_days', 7)::int;
  v_spark int := security.pipeline_num_v1('coverage.spark_days', 14)::int;
  v_day date; v_then date; v_out jsonb;
begin
  if auth.uid() is null and current_user <> 'postgres' then raise exception 'authentication required' using errcode = '42501'; end if;
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 1 then raise exception 'a role is required' using errcode = '42501'; end if;
  select max(snapshot_date) into v_day from pipeline.field_coverage_daily;
  select max(snapshot_date) into v_then from pipeline.field_coverage_daily where snapshot_date <= v_day - v_vel;
  with f as (  -- every field recorded on the latest day, and every registry row, whether or not it has data yet
    select coalesce(d.field, t.field) field from (select distinct field from pipeline.field_coverage_daily where snapshot_date = v_day) d
      full join (select field from pipeline.tracked_fields where active) t on t.field = d.field),
  now_ as (select field, sum(total) total, sum(filled) filled from pipeline.field_coverage_daily where snapshot_date = v_day and (v_cc is null or country_code = v_cc) group by 1),
  then_ as (select field, sum(total) total, sum(filled) filled from pipeline.field_coverage_daily where snapshot_date = v_then and (v_cc is null or country_code = v_cc) group by 1),
  series as (
    select field, jsonb_agg(jsonb_build_object('day', snapshot_date, 'pct', case when tot > 0 then round(100.0 * fil / tot, 1) end) order by snapshot_date) pts
      from (select field, snapshot_date, sum(total) tot, sum(filled) fil from pipeline.field_coverage_daily
             where snapshot_date > v_day - v_spark and (v_cc is null or country_code = v_cc) group by 1, 2) x group by 1),
  rows_ as (
    select f.field, t.domain, coalesce(t.label, r.label, f.field) label, t.field is null or (t.label is null and r.label is null) unlabelled,
           coalesce(t.level, r.level, 'course') level, coalesce(t.target_pct, r.target_pct, 80) target_pct, coalesce(t.in_score, false) in_score,
           t.action_href, t.action_label, coalesce(t.sort, 1000) sort, t.note,
           n.total, n.filled, case when n.total > 0 then round(100.0 * n.filled / n.total, 1) end pct,
           case when th.total > 0 then round(100.0 * th.filled / th.total, 1) end pct_then, s.pts
      from f left join pipeline.tracked_fields t on t.field = f.field and t.active
      left join pipeline.field_register r on r.field = f.field
      left join now_ n on n.field = f.field left join then_ th on th.field = f.field left join series s on s.field = f.field),
  score_fields as (select field from pipeline.tracked_fields where active and in_score),
  per_course as (
    select a.course_id, count(*) filter (where a.state = 'admitted') admitted
      from pipeline.course_attribute_coverage a
     where a.attribute in (select field from score_fields) and (v_cc is null or a.country_code = v_cc)
     group by a.course_id),
  bands as (
    select g.n admitted, coalesce(c.courses, 0) courses
      from generate_series(0, (select count(*) from score_fields)::int) g(n)
      left join (select admitted, count(*) courses from per_course group by 1) c on c.admitted = g.n),
  grid as (
    select d.country_code, t.domain, sum(d.total) total, sum(d.filled) filled, count(distinct d.field) fields
      from pipeline.field_coverage_daily d join pipeline.tracked_fields t on t.field = d.field and t.active
     where d.snapshot_date = v_day group by 1, 2)
  select jsonb_build_object(
    'generated_at', now(), 'day', v_day, 'then', v_then, 'velocity_days', v_vel, 'spark_days', v_spark, 'country', v_cc,
    'domains', jsonb_build_array(
      jsonb_build_object('code', 'courses', 'label', 'Courses'), jsonb_build_object('code', 'providers', 'label', 'Providers & campuses'),
      jsonb_build_object('code', 'aer', 'label', 'AER & grade scales'), jsonb_build_object('code', 'scholarships', 'label', 'Scholarships'),
      jsonb_build_object('code', 'destinations', 'label', 'Destination editions')),
    -- fixed: the six launch destinations shown first (Platform Admin 18 Nov 2026 12:19); any other country with figures follows
    'countries', (select jsonb_agg(c order by o, c) from (
       select c, array_position(array['AU', 'NZ', 'CA', 'GB', 'IE', 'US'], c) o from unnest(array['AU', 'NZ', 'CA', 'GB', 'IE', 'US']) c
       union select distinct country_code, 99 from grid where country_code not in ('AU', 'NZ', 'CA', 'GB', 'IE', 'US')) z),
    'fields', coalesce((select jsonb_agg(to_jsonb(r) - 'sort' order by r.sort, r.field) from rows_ r), '[]'::jsonb),
    'unlabelled', (select count(*) from rows_ where unlabelled),
    'score', jsonb_build_object('n', (select count(*) from score_fields), 'courses', (select count(*) from per_course),
                                'fields', coalesce((select jsonb_agg(field order by field) from score_fields), '[]'::jsonb),
                                'bands', coalesce((select jsonb_agg(jsonb_build_object('admitted', admitted, 'courses', courses) order by admitted) from bands), '[]'::jsonb)),
    'grid', coalesce((select jsonb_agg(jsonb_build_object('country', country_code, 'domain', domain, 'total', total, 'filled', filled, 'fields', fields,
                                                          'pct', case when total > 0 then round(100.0 * filled / total, 1) end)) from grid), '[]'::jsonb))
  into v_out;
  return v_out;
end $function$;
comment on function public.admin_coverage_telemetry_v1(jsonb) is 'CF-247 S1-RM-Design (Platform Admin 18 Nov 2026 12:19): Coverage & completeness › Courses. Every recorded or registered field with its fill, change over coverage.velocity_days and daily series over coverage.spark_days; courses by in-score fields admitted (0 of N to N of N); the country x domain grid. Optional {"country": "AU"}. Read-only.';
revoke all on function public.admin_coverage_telemetry_v1(jsonb) from public, anon;
grant execute on function public.admin_coverage_telemetry_v1(jsonb) to authenticated, service_role;

-- 5. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, 'Platform', 'Coverage', v.purpose, 'active', '20261118170000'
  from (values
    ('table', 'pipeline.tracked_fields', 'How Coverage & completeness shows each recorded field (domain, label, target, score, action)'),
    ('function', 'security.tracked_field_coverage_v1', 'Scholarship, destination edition and grade scale figures recorded hourly into field_coverage_daily'),
    ('function', 'public.admin_coverage_telemetry_v1', 'Coverage & completeness › Courses: fields, velocity, score bands and the readiness grid')) v(kind, name, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaced_by, retire_after, introduced_in)
select v.kind, v.name, 'Platform', 'Coverage', v.purpose, 'retiring', v.rb, date '2026-12-02', '20261118170000'
  from (values
    ('screen', 'Coverage & completeness › Courses › Portals that supply course links', 'Link refresh supply rows (SATAC, VTAC, TISC)', 'Coverage & completeness › Courses field chart: a deep link only where a field is below target'),
    ('screen', 'Coverage & completeness › Attributes › Stalled fields', 'Stalled fields counters', 'Coverage & completeness › Courses field chart: a deep link to Layer 4 › Inbox or Platform health › Queues & yield only where a field is below target')) v(kind, name, purpose, rb)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- 6. Record once so the new fields have today's figures, then post-checks
select security.field_coverage_record_v1();

do $c$
declare v jsonb;
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
  if not exists (select 1 from pipeline.field_coverage_daily where field = 's_award_value') then
    raise exception 'post-check: the recorder did not record the scholarship figures';
  end if;
  v := public.admin_coverage_telemetry_v1('{}'::jsonb);
  if (v->'score'->>'n')::int < 15 or jsonb_array_length(v->'score'->'bands') <> (v->'score'->>'n')::int + 1 then
    raise exception 'post-check: the score bands are not 0 of N to N of N (n %)', v->'score'->>'n';
  end if;
  if jsonb_array_length(v->'fields') < 36 then
    raise exception 'post-check: fewer fields than recorded and registered (%)', jsonb_array_length(v->'fields');
  end if;
end $c$;
