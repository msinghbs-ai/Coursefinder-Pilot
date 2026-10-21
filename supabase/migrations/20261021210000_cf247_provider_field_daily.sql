-- CF-247 (21 Oct 2026). Platform Admin 18:27: "Prepare the nz data per uni including all fields before and at present." 18:32: "Produce it
-- daily please".
-- The platform kept field counts a day per country only (pipeline.field_coverage_daily), so a provider's "before" had to be worked out.
-- This keeps one row a day per provider: courses, how many courses hold each course field, and which provider fields are held, so the
-- daily NZ report compares real days.
--   1 pipeline.provider_field_daily (one row per provider per Melbourne day; course_filled and provider_held as jsonb, so a day is about
--     2,000 rows for all countries).
--   2 security.provider_field_daily_record_v1(date): writes the day from pipeline.course_attribute_coverage (refreshed hourly) and the
--     provider fields (same rules as security.provider_field_coverage_v1); a second run the same day replaces that day. Rows older than
--     retention.provider_field_daily_days (120) are removed by the job.
--   3 job provider-field-daily, daily at 19:55 UTC (6:55 am Melbourne in daylight time), catalogued.
--   4 Seed: 20 Oct 2026 for New Zealand, worked out as held now minus the values Enrich fields tasks and enrichment plans filled on 21 Oct
--     (source 'reconstructed', the baseline of the report sent on 21 Oct); 21 Oct 2026 for every country as held when this is applied.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted by this migration. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'retention.provider_field_daily_days', 'Keep daily field counts per provider for',
  'Days of per-provider field counts kept for the daily coverage report; older days are removed by the daily job.',
  'number', to_jsonb(120), 30, 730, 'days', 326, 'CF-247, Platform Admin 21 Oct 2026 18:32 "Produce it daily please"', 'Storage & retention', 'job provider-field-daily')
on conflict do nothing;

create table if not exists pipeline.provider_field_daily (
  snapshot_date date not null,
  provider_id uuid not null,
  country_code text,
  courses int not null default 0,
  course_filled jsonb not null default '{}'::jsonb,
  provider_held jsonb not null default '{}'::jsonb,
  source text not null default 'job' check (source in ('job', 'reconstructed')),
  computed_at timestamptz not null default now(),
  primary key (snapshot_date, provider_id)
);
create index if not exists provider_field_daily_country on pipeline.provider_field_daily(country_code, snapshot_date);
comment on table pipeline.provider_field_daily is 'CF-247 21 Oct 2026: one row a day (Melbourne date) per provider with active courses: courses, the number of courses holding each course field (course_filled) and which provider fields are held (provider_held). Written by job provider-field-daily; read by the daily per-provider coverage report. Source reconstructed = worked out afterwards (NZ, 20 Oct 2026).';
alter table pipeline.provider_field_daily enable row level security;

create or replace function security.provider_field_daily_record_v1(p_date date default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_date date := coalesce(p_date, (now() at time zone 'Australia/Melbourne')::date); v_n int; v_old int;
begin
  insert into pipeline.provider_field_daily(snapshot_date, provider_id, country_code, courses, course_filled, provider_held, source, computed_at)
  select v_date, p.id, c.cc, c.courses, c.filled,
         jsonb_build_object(
           'p_website', nullif(btrim(p.website), '') is not null,
           'p_address', nullif(btrim(p.address_line1), '') is not null,
           'p_campuses', exists (select 1 from catalogue.campuses k where k.provider_id = p.id),
           'p_type', p.provider_type_id is not null,
           'p_international', p.enrols_international is not null,
           'p_logo', nullif(btrim(p.logo_url), '') is not null or exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.asset_type = 'logo'),
           'p_contact', nullif(btrim(p.phone), '') is not null or nullif(btrim(p.email), '') is not null,
           'p_scholarships', exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active'),
           'p_description', nullif(btrim(p.description), '') is not null),
         'job', now()
    from (select x.provider_id, max(x.cc) cc, max(x.courses) courses, jsonb_object_agg(x.attribute, x.filled) filled
            from (select a.provider_id, a.attribute, max(a.country_code) cc, count(distinct a.course_id) courses, count(*) filter (where a.state = 'admitted') filled
                    from pipeline.course_attribute_coverage a group by 1, 2) x
           group by x.provider_id) c
    join catalogue.providers p on p.id = c.provider_id
  on conflict (snapshot_date, provider_id) do update
     set country_code = excluded.country_code, courses = excluded.courses, course_filled = excluded.course_filled,
         provider_held = excluded.provider_held, source = 'job', computed_at = now();
  get diagnostics v_n = row_count;
  delete from pipeline.provider_field_daily
   where snapshot_date < v_date - security.pipeline_num_v1('retention.provider_field_daily_days', 120)::int;
  get diagnostics v_old = row_count;
  return jsonb_build_object('date', v_date, 'providers', v_n, 'removed', v_old);
end $function$;
revoke execute on function security.provider_field_daily_record_v1(date) from public, anon, authenticated;

-- Seed 1: today, every country
select security.provider_field_daily_record_v1('2026-10-21');

-- Seed 2: New Zealand at the start of 21 Oct 2026 (the baseline of the report sent that evening), worked out
insert into pipeline.provider_field_daily(snapshot_date, provider_id, country_code, courses, course_filled, provider_held, source, computed_at)
select '2026-10-20', d.provider_id, d.country_code, d.courses,
       (select jsonb_object_agg(k, greatest(0, v::int - coalesce((
                 select count(distinct e.course_id) from pipeline.field_enrich_items e
                  join pipeline.course_attribute_coverage a on a.course_id = e.course_id and a.attribute = k and a.state = 'admitted'
                 where e.provider_id = d.provider_id and e.state = 'filled' and e.updated_at >= '2026-10-20 13:00+00'
                   and (case when e.field = 'campus_list' then 'campus' else e.field end) = case when k = 'campus_city' then 'campus' else k end), 0)))
          from jsonb_each_text(d.course_filled) j(k, v)),
       d.provider_held || case when exists (select 1 from pipeline.field_enrich_items e where e.provider_id = d.provider_id and e.field = 'provider_address'
                                             and e.state = 'filled' and e.updated_at >= '2026-10-20 13:00+00')
                               then jsonb_build_object('p_address', false) else '{}'::jsonb end,
       'reconstructed', now()
  from pipeline.provider_field_daily d
 where d.snapshot_date = '2026-10-21' and d.country_code = 'NZ'
on conflict (snapshot_date, provider_id) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('provider-field-daily', 'Reporting', 40, 'Daily field counts per provider', 'Daily at 6:55 am Melbourne (daylight time): records each provider''s courses, the courses holding each field and the provider fields held, for the daily per-provider coverage report. Keeps Settings › Pipeline settings › Storage & retention days.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('provider-field-daily', '55 19 * * *', $$select security.provider_field_daily_record_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.provider_field_daily', 'Reporting', 'Daily field counts per provider', 'active', '20261021210000'),
 ('function', 'security.provider_field_daily_record_v1', 'Reporting', 'Writes a day of field counts per provider', 'active', '20261021210000'),
 ('job', 'provider-field-daily', 'Reporting', 'Daily field counts per provider', 'active', '20261021210000')
on conflict (kind, name) do nothing;
