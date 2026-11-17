-- CF-247 (20 Oct 2026). Usage audit decision D11 (Platform Admin, 19 Oct 2026: "Retire all but embeddings"); 20 Oct 10:35 "Proceed with task 4".
-- The idle groups the usage audit found (no rows written since 12 Oct): the workflow schema, the Layer 2 trials and earlier phases, the Layer 3
-- benchmarks, the onboarding cases, the scholarship leftovers, the directory and identity sets and two Canadian scope tables. The search
-- embeddings (search.course_embeddings, embedding_jobs, query_embedding_cache, profiles) are kept, as decided.
-- Each table is marked retiring in pipeline.component_register (retire_after 3 Nov 2026, the housekeeping rule of 14 days) with the database
-- functions that still name it. Before the drop paste file is issued, each of those functions is removed or changed so it no longer reads
-- the table (several are live: the platform health check, Evidence, the data quality refresh, user deletion, onboarding's step function,
-- Scholarships › Layer 1 and 2, Models & services). Nothing else changes now: no table, row or function is touched.
-- Replaces: nothing
-- Retires: the tables listed below (dropped by a paste file after 3 Nov 2026, once their readers are moved)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

with t(tbl, grp) as (values
  ('workflow.export_jobs','workflow schema'),('workflow.handover_events','workflow schema'),('workflow.import_errors','workflow schema'),('workflow.import_jobs','workflow schema'),
  ('workflow.import_rows','workflow schema'),('workflow.migration_entity_map','workflow schema'),('workflow.migration_runs','workflow schema'),('workflow.reconciliation_checks','workflow schema'),
  ('workflow.review_actions','workflow schema'),('workflow.review_queue','workflow schema'),('workflow.suggestions','workflow schema'),
  ('pipeline.layer2_auto_discovery_attempts','Layer 2 trials'),('pipeline.layer2_auto_discovery_settings','Layer 2 trials'),('pipeline.layer2_auto_discovery_settings_audit','Layer 2 trials'),
  ('pipeline.layer2_completeness_trial_courses','Layer 2 trials'),('pipeline.layer2_completeness_trials','Layer 2 trials'),('pipeline.layer2_provider_trial_results','Layer 2 trials'),
  ('pipeline.layer2_scale_qualification_runs','Layer 2 trials'),('pipeline.layer2_scale_qualification_items','Layer 2 trials'),('pipeline.layer2_tuning_events','Layer 2 trials'),
  ('pipeline.coverage_identity_cases','identity and directory sets'),('pipeline.coverage_identity_results','identity and directory sets'),('pipeline.coverage_identity_sets','identity and directory sets'),
  ('pipeline.directory_institutions','identity and directory sets'),('pipeline.directory_pages','identity and directory sets'),('pipeline.provider_directory_observations','identity and directory sets'),
  ('pipeline.ca_course_scope_keys','Canadian scope'),('pipeline.ca_source_qualifications','Canadian scope'),
  ('pipeline.layer3_benchmark_jobs','Layer 3 benchmarks'),('pipeline.layer3_holdout_cases','Layer 3 benchmarks'),('pipeline.layer3_holdout_results','Layer 3 benchmarks'),
  ('pipeline.layer3_holdout_sets','Layer 3 benchmarks'),('pipeline.layer3_intake_benchmark_cases','Layer 3 benchmarks'),('pipeline.layer3_intake_benchmark_results','Layer 3 benchmarks'),
  ('pipeline.layer3_intake_gold_sets','Layer 3 benchmarks'),('pipeline.layer3_task_contract_freezes','Layer 3 benchmarks'),('pipeline.layer3_quality_benchmark_runs','Layer 3 benchmarks'),
  ('pipeline.layer3_profile_activation_events','Layer 3 benchmarks'),('pipeline.layer3_provider_credential_audit','Layer 3 benchmarks'),
  ('pipeline.onboarding_cases','onboarding cases'),('pipeline.onboarding_lifecycle_events','onboarding cases'),
  ('pipeline.scholarship_coverage_benchmarks','scholarship leftovers'),('pipeline.scholarship_ai_runs','scholarship leftovers'),('pipeline.scholarship_ai_run_items','scholarship leftovers'),
  ('pipeline.scholarship_ai_settings','scholarship leftovers'),('pipeline.scholarship_runtime_settings','scholarship leftovers'),('pipeline.scholarship_maintenance_runs','scholarship leftovers'),
  ('pipeline.scholarship_etl_schedules','scholarship leftovers'),('pipeline.scholarship_catalogue_runs','scholarship leftovers'),('pipeline.scholarship_scope_acquisition_requests','scholarship leftovers'),
  ('pipeline.scholarship_source_qualifications','scholarship leftovers'),('pipeline.scholarship_coverage_checks','scholarship leftovers'),('pipeline.scholarship_jobs','scholarship leftovers'),
  ('pipeline.pim_source_candidates','scholarship leftovers')),
r as (  -- the database functions that still name each table (to remove or change before the drop)
  select t.tbl, t.grp, (select string_agg(distinct n.nspname || '.' || p.proname, ', ' order by n.nspname || '.' || p.proname)
                          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname not in ('pg_catalog', 'information_schema') and p.prosrc ~ ('\m' || split_part(t.tbl, '.', 2) || '\M')) readers
    from t where to_regclass(t.tbl) is not null)
insert into pipeline.component_register(kind, name, layer, purpose, status, replaced_by, retire_after, note, introduced_in)
select 'table', r.tbl, 'Housekeeping', 'Idle since 12 Oct 2026 (' || r.grp || ')', 'retiring', 'nothing: idle (usage audit D11)', date '2026-11-03',
       'D11 (Platform Admin 19 Oct 2026 "Retire all but embeddings"). Before the drop, remove or change: ' || coalesce(r.readers, 'no function reads it'), '20261020080000'
  from r
on conflict (kind, name) do update set status = 'retiring', replaced_by = excluded.replaced_by, retire_after = excluded.retire_after,
       note = coalesce(pipeline.component_register.note || '; ', '') || excluded.note, updated_at = now()
 where pipeline.component_register.status <> 'retired';
