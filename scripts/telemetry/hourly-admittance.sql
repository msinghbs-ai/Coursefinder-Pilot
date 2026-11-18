-- CF-247 s717: hourly admittance telemetry (Platform Admin 19 Nov 2026 06:57). Read only. One row; its column names are the header of the
-- Google Sheet Hourly_Admittance_Telemetry (Drive folder Monitoring) and of Hourly_Admittance_Telemetry.csv. The hourly scheduled task
-- "Hourly admittance telemetry" runs this file as written on project fxcwkweaxjtknorudmwp and appends the row; nothing here writes.
-- Coverage comes from public.admin_coverage_telemetry_v1 (read as the Platform Admin account, inside this read-only transaction).
begin transaction read only;
set local statement_timeout = '20s';
select set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
with tel as (select public.admin_coverage_telemetry_v1('{}'::jsonb) j),
l4 as (select entity_type,
              count(*) filter (where status in ('approved', 'edited_approved')) admitted,
              count(*) filter (where status = 'pending') held,
              count(*) filter (where status = 'rejected') rejected
         from pipeline.layer4_review_items where entity_type in ('course', 'provider') group by entity_type),
dest as (select count(*) filter (where s = 'approved') admitted, count(*) filter (where s in ('draft', 'in_review')) held, count(*) filter (where s = 'withdrawn') rejected
           from (select m.status s from destination.locality_metrics m
                 union all select o.status from destination.career_outcomes o
                 union all select r.approval_status from destination.study_rules r join destination.editions e on e.id = r.edition_id where e.status <> 'superseded') x)
select to_char(now() at time zone 'Australia/Melbourne', 'YYYY-MM-DD HH24:MI') as snapshot_aedt,
       to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') as snapshot_utc,
       (select admitted from l4 where entity_type = 'course') as courses_admitted,
       (select held from l4 where entity_type = 'course') as courses_held,
       (select rejected from l4 where entity_type = 'course') as courses_rejected,
       (select admitted from l4 where entity_type = 'provider') as providers_admitted,
       (select held from l4 where entity_type = 'provider') as providers_held,
       (select rejected from l4 where entity_type = 'provider') as providers_rejected,
       (select count(*) filter (where publication_status = 'published') from scholarship.scholarships) as scholarships_admitted,
       (select count(*) filter (where publication_status = 'unpublished') from scholarship.scholarships) as scholarships_held,
       (select count(*) filter (where publication_status = 'withdrawn') from scholarship.scholarships) as scholarships_rejected,
       (select count(*) filter (where status = 'active') from catalogue.course_entry_requirements) as aer_admitted,
       (select count(*) filter (where status = 'proposed') from catalogue.course_entry_requirements) as aer_held,
       (select count(*) filter (where status = 'inactive') from catalogue.course_entry_requirements) as aer_rejected,
       (select admitted from dest) as destination_admitted,
       (select held from dest) as destination_held,
       (select rejected from dest) as destination_rejected,
       (select (j->'score'->>'courses')::int from tel) as coverage_courses,
       (select (j->'score'->>'n')::int from tel) as coverage_fields_n,
       (select coalesce(sum((b->>'courses')::int) filter (where (b->>'admitted')::int = (j->'score'->>'n')::int), 0) from tel, jsonb_array_elements(j->'score'->'bands') b) as coverage_courses_all_n,
       (select coalesce(sum((b->>'courses')::int) filter (where (b->>'admitted')::int = 0), 0) from tel, jsonb_array_elements(j->'score'->'bands') b) as coverage_courses_zero,
       (select round(sum((b->>'courses')::numeric * (b->>'admitted')::int) / nullif(sum((b->>'courses')::numeric), 0), 2) from tel, jsonb_array_elements(j->'score'->'bands') b) as coverage_mean_fields_admitted,
       (select jsonb_array_length(coalesce(j->'fields', '[]'::jsonb)) from tel) as coverage_tracked_fields,
       (select count(*) from cron.job where active) as jobs_active,
       (select count(*) from cron.job where not active) as jobs_off,
       (select count(*) from cron.job_run_details where start_time > now() - interval '1 hour' and status = 'succeeded') as job_runs_1h_succeeded,
       (select count(*) from cron.job_run_details where start_time > now() - interval '1 hour' and status = 'failed') as job_runs_1h_failed;
