-- CF-247 API v3 daily admittance telemetry (Platform Admin 16 Nov 2026 20:17): daily admitted count and gain per API v3 and request-register
-- field, so live admittance can be reported to the developers from one source.
-- Replaces: security.field_coverage_record_v1 (same name; md5-guarded text edit: one more union branch).
-- Retires: nothing.
--
-- Design (no new job, no new table, no new column):
--   * pipeline.field_coverage_daily already keeps one row per (day, country, field) with total and filled, written by
--     security.field_coverage_record_v1 inside the existing platform-health job (every 10 minutes; the day's last value stands; 120 days kept).
--     The rollup scheduler (PR 1) is not involved, so tonight's PR 1 cutover is untouched.
--   * security.api_v3_field_coverage_v1() returns the same shape for the API v3 and request-register fields; field_coverage_record_v1 adds it.
--   * security.api_v3_daily_admittance_v1(p_date) reads that history: per field, today's admitted count, yesterday's, the daily gain
--     (today - yesterday), the eligible total and the share. The Telemetry sheet tab API_v3_Daily_Admittance and the 08:15 report read it.
-- Fields (country = the provider's coverage country; v3 = API v3 field, p_ = provider level):
--   v3_study_load (REQ-52)        active courses; admitted = study_load held
--   v3_empty_reason (REQ-53)      active courses with no campus; admitted = empty_reason_code held
--   v3_campus_primary (REQ-75)    providers with an active campus; admitted = one campus marked primary
--   v3_accreditations (REQ-57)    providers with active courses; admitted = at least one active accreditation (AACSB, EQUIS, AMBA)
--   v3_grade_normalised (REQ-19)  active entry matrix rows; admitted = 0 until PR E adds the normalisation table (PR E replaces this line)
--   v3_destination (REQ-65/67)    destination rows (AU); admitted = rows in a published edition with approved terms
--   p_entry_matrix                providers with active courses; admitted = at least one active entry matrix row
--   p_registrations               providers with active courses; admitted = at least one regulator registration
-- All counts are indexed aggregates (no text scans). Measured in the rolled-back dry run. No consumer API object (G3).

create or replace function security.api_v3_field_coverage_v1()
returns table (country_code text, field text, total bigint, filled bigint)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with ap as (
    select p.id, security.coverage_country(p.id) cc
      from catalogue.providers p
     where coalesce(p.lifecycle_status, 'active') = 'active'
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
  ac as (
    select c.id, ap.cc, c.study_load, c.empty_reason_code
      from catalogue.courses c join ap on ap.id = c.provider_id
     where c.lifecycle_status = 'active')
  select cc, 'v3_study_load', count(*), count(*) filter (where study_load is not null) from ac group by cc
  union all
  select cc, 'v3_empty_reason', count(*), count(*) filter (where empty_reason_code is not null)
    from ac where not exists (select 1 from catalogue.course_campuses k where k.course_id = ac.id) group by cc
  union all
  select ap.cc, 'v3_campus_primary', count(*), count(*) filter (where exists (select 1 from catalogue.campuses k where k.provider_id = ap.id and k.is_primary))
    from ap where exists (select 1 from catalogue.campuses k where k.provider_id = ap.id and k.status = 'active') group by ap.cc
  union all
  select ap.cc, 'v3_accreditations', count(*), count(*) filter (where exists (select 1 from catalogue.provider_accreditations a where a.provider_id = ap.id and a.status = 'active'))
    from ap group by ap.cc
  union all
  select ap.cc, 'v3_grade_normalised', count(*), 0::bigint  -- PR E: admitted rows from the normalisation table
    from catalogue.provider_entry_matrix m join ap on ap.id = m.provider_id where m.status = 'active' group by ap.cc
  union all
  select 'AU', 'v3_destination', count(*), count(*) filter (where e.status = 'published' and e.terms_status = 'approved')
    from (select edition_id from destination.study_rules union all select edition_id from destination.city_profiles
          union all select edition_id from destination.career_outcomes) d
    left join destination.editions e on e.id = d.edition_id
  union all
  select ap.cc, 'p_entry_matrix', count(*), count(*) filter (where exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = ap.id and m.status = 'active'))
    from ap group by ap.cc
  union all
  select ap.cc, 'p_registrations', count(*), count(*) filter (where exists (select 1 from catalogue.provider_registrations r where r.provider_id = ap.id))
    from ap group by ap.cc
$function$;
comment on function security.api_v3_field_coverage_v1() is
  'CF-247 API v3 daily admittance (Platform Admin 16 Nov 2026 20:17): total and admitted per country for the API v3 and request-register fields; recorded daily into pipeline.field_coverage_daily by security.field_coverage_record_v1.';
revoke all on function security.api_v3_field_coverage_v1() from public, anon, authenticated;

create or replace function security.api_v3_daily_admittance_v1(p_date date default null)
returns table (field text, req_ids text, snapshot_date date, admitted bigint, yesterday_admitted bigint, daily_admitted_gain bigint, eligible bigint, pct numeric, computed_at timestamptz)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with d as (select coalesce(p_date, (select max(f.snapshot_date) from pipeline.field_coverage_daily f)) t),
  m(field, req_ids, ord) as (values
    ('v3_study_load', 'REQ-52', 1), ('v3_empty_reason', 'REQ-53', 2), ('v3_campus_primary', 'REQ-75 (D-4)', 3), ('v3_accreditations', 'REQ-57 (D-3)', 4),
    ('v3_grade_normalised', 'REQ-19', 5), ('v3_destination', 'REQ-65, REQ-67, REQ-68', 6), ('official_url', 'core', 7), ('description', 'core', 8),
    ('academic_entry', 'core', 9), ('english', 'core', 10), ('intakes', 'core', 11), ('provider_tuition', 'core', 12), ('registered_tuition', 'core', 13),
    ('p_entry_matrix', 'core', 14), ('p_registrations', 'core', 15)),
  td as (select f.field, sum(f.filled) filled, sum(f.total) total, max(f.computed_at) at from pipeline.field_coverage_daily f, d where f.snapshot_date = d.t group by f.field),
  yd as (select f.field, sum(f.filled) filled from pipeline.field_coverage_daily f, d where f.snapshot_date = d.t - 1 group by f.field)
  select m.field, m.req_ids, (select t from d), td.filled, yd.filled, td.filled - yd.filled, td.total,
         round(100.0 * td.filled / nullif(td.total, 0), 1), td.at
    from m left join td on td.field = m.field left join yd on yd.field = m.field
   order by m.ord
$function$;
comment on function security.api_v3_daily_admittance_v1(date) is
  'CF-247 API v3 daily admittance (Platform Admin 16 Nov 2026 20:17): per field, admitted today, admitted yesterday, daily admitted gain, eligible total and share, from pipeline.field_coverage_daily. Read by the Telemetry sheet tab API_v3_Daily_Admittance and the 08:15 report.';
revoke all on function security.api_v3_daily_admittance_v1(date) from public, anon, authenticated;
grant execute on function security.api_v3_daily_admittance_v1(date) to service_role;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.field_coverage_record_v1()', '9e7e5bc441936a4feaa87afdd2f6e51d', 'ec8cf0c3988103a9f9fdaf6d25b924c1',
  array[$o1$x.field, x.total, x.filled from security.provider_field_coverage_v1() x
$o1$],
  array[$n1$x.field, x.total, x.filled from security.provider_field_coverage_v1() x
  union all  -- 16 Nov 2026: API v3 and request-register fields (security.api_v3_field_coverage_v1)
  select (now() at time zone 'Australia/Melbourne')::date, v.country_code, v.field, v.total, v.filled from security.api_v3_field_coverage_v1() v
$n1$]);

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in)
values
  ('function', 'security.api_v3_field_coverage_v1', 'consumer', 'api_v3', 'Daily admitted and eligible counts per country for the API v3 and request-register fields (recorded by field_coverage_record_v1)', 'active', '{}', '20261116170000'),
  ('function', 'security.api_v3_daily_admittance_v1', 'consumer', 'api_v3', 'Per-field admitted today, yesterday, daily gain, eligible and share, for the Telemetry sheet and the developers', 'active', '{}', '20261116170000')
on conflict (kind, name) do nothing;

do $post$
begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.field_coverage_record_v1()'::regprocedure)) <> 'ec8cf0c3988103a9f9fdaf6d25b924c1' then
    raise exception 'post-check: security.field_coverage_record_v1 does not have the recorded body'; end if;
end $post$;
