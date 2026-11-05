-- Guards: Platform Admin decision 5 Nov 2026 16:36 §8 (database-backed UI tests with production-representative fixtures): the platform state the
-- migration expects before it is applied: the live settings it reads (values as in production on 5 Nov 2026), the two live jobs and their live
-- commands, their catalogue rows, the six live roles, and twelve Australian universities plus two other providers. Synthetic names and identifiers;
-- no production rows are copied.
set client_min_messages = warning;
create schema if not exists fx;
create or replace function fx.id(p text) returns uuid language sql immutable as $$ select md5('intake-progress:' || p)::uuid $$;

insert into pipeline.platform_toolsets(key) values ('pipeline') on conflict do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, section, used_by) values
 ('pipeline', 'intake_dates.apply_enabled', 'Intake dates: apply', 'boolean', 'true', null, null, null, 'Intake dates', 'security.intake_dates_apply_v1'),
 ('pipeline', 'batch.intake_dates_apply', 'Intake dates: rows a run', 'number', '200', 10, 2000, 'rows', 'Job sizes', 'job intake-dates-apply'),
 ('pipeline', 'intake_dates.revisit_days', 'Intake dates: revisit after', 'number', '14', 1, 90, 'days', 'Intake dates', 'security.intake_dates_plan_v3'),
 ('pipeline', 'intake_dates.provider_share', 'Intake dates: rows a provider a round', 'number', '25', 1, 200, 'rows', 'Intake dates', 'security.intake_dates_plan_v3'),
 ('pipeline', 'intake_dates.pilot_batch_share', 'Intake dates: pilot share', 'number', '60', 0, 100, 'per cent', 'Intake dates', 'security.intake_dates_plan_v3'),
 ('pipeline', 'process_results.validation_rows', 'Process results: rows shown', 'number', '25', 5, 200, 'rows', 'Process results', 'public.admin_process_results_v1'),
 ('pipeline', 'process_results.history_rows', 'Process results: measurements listed', 'number', '30', 5, 500, 'measurements', 'Process results', 'public.admin_process_results_v1'),
 ('pipeline', 'process_results.window_days', 'Process results: window', 'number', '7', 1, 90, 'days', 'Process results', 'security.process_results_intake_dates_v1'),
 ('pipeline', 'run_now.cohort_top_au_universities', 'Run now: Australian universities', 'number', '10', 1, 50, 'universities', 'Run now', 'security.intake_ui_scopes_v1'),
 ('pipeline', 'central.calendar_refresh_credit_budget', 'Calendar refresh: credits', 'number', '40', 0, 40, 'credits', 'Intake dates', 'public.svc_calendar_refresh_v1'),
 ('pipeline', 'retry.intake_publication_checks', 'Publication check: tries', 'number', '3', 1, 10, 'checks', 'Intake dates', 'security.intake_publication_check_v1')
on conflict (toolset_key, key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('intake-dates-apply', 'Admission', 65, 'Intake dates apply', 'Hourly at :26: admits intake years, start dates and deadlines from approved calendars (security.intake_dates_apply_v1). After applying, checks admitted values against the Website API v2 source (security.intake_publication_check_v1; mandate 5 Nov 2026 §6).', 5, true),
 ('process-results', 'Admission', 67, 'Process results (intake dates)', 'Hourly at :53: records a dated measurement of the intake dates process for the top Australian universities (pipeline.process_results). Before measuring, checks admitted intake values against the Website API v2 source (publication check), and records the intake recovery measurement (process intake-recovery) (mandate 5 Nov 2026 §6, §10).', 5, false)
on conflict (jobname) do nothing;
-- the live commands (cron.job, read 5 Nov 2026 19:21 AEDT)
select cron.schedule('intake-dates-apply', '26 * * * *', 'select security.intake_dates_apply_v1(security.pipeline_num_v1(''batch.intake_dates_apply'', 200)::int); select security.intake_publication_check_v1()');
select cron.schedule('process-results', '53 * * * *', 'select security.intake_publication_check_v1(); select security.process_results_record_v1(); select security.process_results_recovery_record_v1()');

insert into security.roles(code, name, rank, status) values ('viewer', 'Viewer', 1, 'active'), ('counsellor', 'Counsellor', 2, 'active'), ('curator', 'Curator', 3, 'active'),
  ('pipeline_operator', 'Pipeline Operator', 4, 'active'), ('pim_admin', 'PIM Operator', 5, 'active'), ('platform_admin', 'Platform Admin', 6, 'active') on conflict do nothing;
insert into auth.users(id) select fx.id('user:' || r) from generate_series(2, 6) r on conflict do nothing;
insert into security.user_roles(user_id, role_code)
select fx.id('user:' || r.rank), r.code from security.roles r where r.rank between 2 and 6 on conflict do nothing;

insert into ref.countries(id, iso_alpha2) values (fx.id('AU'), 'AU'), (fx.id('NZ'), 'NZ') on conflict do nothing;
insert into ref.provider_types(id, code) values (fx.id('university'), 'university'), (fx.id('college'), 'college') on conflict do nothing;
-- twelve Australian universities (the ten with most active courses are the pilot) and two other providers
with u(k, name, courses, country, ptype) as (values
  ('unsw', 'UNSW Sydney', 30, 'AU', 'university'), ('sydney', 'The University of Sydney', 29, 'AU', 'university'), ('monash', 'Monash University', 28, 'AU', 'university'),
  ('uts', 'UTS', 27, 'AU', 'university'), ('rmit', 'RMIT University', 26, 'AU', 'university'), ('adelaide', 'Adelaide University', 25, 'AU', 'university'),
  ('flinders', 'Flinders University', 24, 'AU', 'university'), ('newcastle', 'The University of Newcastle', 23, 'AU', 'university'),
  ('melbourne', 'The University of Melbourne', 22, 'AU', 'university'), ('swinburne', 'Swinburne University', 21, 'AU', 'university'),
  ('jcu', 'James Cook University', 12, 'AU', 'university'), ('latrobe', 'La Trobe University', 11, 'AU', 'university'),
  ('torrens', 'Torrens University Australia', 9, 'AU', 'college'), ('auckland', 'University of Auckland', 8, 'NZ', 'university'))
, reg as (insert into pim.entity_registry(id) select fx.id('p:' || k) from u on conflict do nothing returning id)
insert into catalogue.providers(id, canonical_name, display_name, country_id, provider_type_id)
select fx.id('p:' || k), name, name, fx.id(country), fx.id(ptype) from u, (select count(*) from reg) r on conflict do nothing;
create table if not exists fx.provider_keys(k text primary key, courses int);
insert into fx.provider_keys values ('unsw', 30), ('sydney', 29), ('monash', 28), ('uts', 27), ('rmit', 26), ('adelaide', 25), ('flinders', 24), ('newcastle', 23),
  ('melbourne', 22), ('swinburne', 21), ('jcu', 12), ('latrobe', 11), ('torrens', 9), ('auckland', 8) on conflict do nothing;
insert into pim.entity_registry(id) select fx.id('c:' || k || ':' || n) from fx.provider_keys, generate_series(1, courses) n on conflict do nothing;
insert into catalogue.courses(id, provider_id, canonical_title, course_url)
select fx.id('c:' || k || ':' || n), fx.id('p:' || k), 'Course ' || n || ' of ' || k, 'https://example.edu.au/' || k || '/course-' || n
  from fx.provider_keys, generate_series(1, courses) n on conflict do nothing;
-- two intakes a course (February and July 2027), none dated yet
insert into catalogue.course_intakes(id, course_id, intake_year, intake_label)
select fx.id('i:' || k || ':' || n || ':' || m), fx.id('c:' || k || ':' || n), 2027, m from fx.provider_keys, generate_series(1, courses) n, unnest(array['February', 'July']) m
on conflict do nothing;

-- the generic progress contract as in production (decision 20:03): its settings, its job and its sixteen transitions (configuration rows from
-- migration 20261104460000, as live on 5 Nov 2026 20:05 AEDT)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, section, used_by) values
 ('pipeline', 'progress.on', 'Progress contract: read every pipeline transition', 'number', '1', 0, 1, 'switch', 'First-run verification and progress', 'security.progress_read_v1'),
 ('pipeline', 'progress.window_hours', 'Progress contract: counting window', 'number', '24', 1, 168, 'hours', 'First-run verification and progress', 'security.progress_measure_v1'),
 ('pipeline', 'progress.stall_hours', 'Progress contract: a transition with eligible work is stalled after', 'number', '6', 1, 168, 'hours', 'First-run verification and progress', 'security.progress_read_v1')
on conflict (toolset_key, key) do nothing;
select cron.schedule('first-run-verify', '2,32 * * * *', 'select security.first_run_verify_tick_v1()');
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('first-run-verify', 'Platform upkeep', 18, 'First-run verification, progress and recovery routing', 'At :02 and :32: first runs of released jobs, the progress contract, links and routes (live label, area, sort and control rank; description shortened).', 6, false)
on conflict (jobname) do nothing;
insert into pipeline.progress_transitions(key, chain, step, title, producer_jobs, switch_keys) values
 ('sch_classification', 'scholarship', 10, 'Coverage classification', '{scholarship-coverage-classify}', '{sch_cov.classify_on}'),
 ('sch_source_recovery', 'scholarship', 20, 'Source recovery', '{scholarship-coverage-recover}', '{sch_cov.recover_register_pages_on,sch_cov.recover_stored_reads_on,sch_cov.recover_listings_on}'),
 ('sch_listing_traversal', 'scholarship', 30, 'Listing traversal', '{scholarship-listing}', '{}'),
 ('sch_candidate_matching', 'scholarship', 40, 'Candidate matching', '{scholarship-discover,scholarship-listing}', '{}'),
 ('sch_reading', 'scholarship', 50, 'Reading', '{scholarship-read,scholarship-ai-extract}', '{}'),
 ('sch_eligibility', 'scholarship', 60, 'Eligibility validation', '{scholarship-ai-extract}', '{}'),
 ('sch_layer4', 'scholarship', 70, 'Layer 4 where required', '{}', '{}'),
 ('sch_admission', 'scholarship', 80, 'Admission', '{scholarship-ai-extract}', '{}'),
 ('sch_publication', 'scholarship', 90, 'Publication', '{scholarship-auto-publish}', '{}'),
 ('aer_source_discovery', 'aer', 10, 'Source discovery', '{coverage-discover,coverage-discover-2}', '{}'),
 ('aer_extraction', 'aer', 20, 'Extraction', '{aer-scheduled-read,entry-matrix-read}', '{}'),
 ('aer_completeness', 'aer', 30, 'Completeness validation', '{aer-scheduled-read}', '{}'),
 ('aer_technical_correction', 'aer', 40, 'Technical correction where needed', '{work-continuity}', '{}'),
 ('aer_layer4_review', 'aer', 50, 'Layer 4 review', '{}', '{}'),
 ('aer_active_records', 'aer', 60, 'Active entry records', '{}', '{}'),
 ('aer_publication', 'aer', 70, 'Consumer publication', '{}', '{}')
on conflict (key) do nothing;
update pipeline.progress_transitions t set next_key = n.key from pipeline.progress_transitions n
 where n.chain = t.chain and n.step = (select min(x.step) from pipeline.progress_transitions x where x.chain = t.chain and x.step > t.step) and t.next_key is null;
