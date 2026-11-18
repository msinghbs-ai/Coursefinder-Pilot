-- CF-247 Phase 5 hardening (19 Oct 2026; Platform Admin 09:29 "Phase 5: hardening"; 17:05 "Proceed with task 4,5 and 6").
-- Found while dry-running the evidence purge paste file: 20 columns that refer to pipeline.evidence_artifacts by foreign key have no
-- index, so removing one evidence row reads each of those tables in full (the dry run of 8,531 rows did not finish within 100 seconds).
-- Each column gets an index (built here, before the paste file runs). The tables keep their rows, columns and grants; the consumer
-- API reads nothing differently (an index changes no answer).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

create index if not exists provider_discovery_links_evidence_id_fk_idx on pipeline.provider_discovery_links (evidence_id);
create index if not exists course_mappings_evidence_id_fk_idx on scholarship.course_mappings (evidence_id);
create index if not exists course_mapping_candidates_evidence_id_fk_idx on scholarship.course_mapping_candidates (evidence_id);
create index if not exists course_financial_calculations_fee_evidence_id_fk_idx on scholarship.course_financial_calculations (fee_evidence_id);
create index if not exists course_financial_calculations_scholarship_evidence_id_fk_idx on scholarship.course_financial_calculations (scholarship_evidence_id);
create index if not exists scholarship_acquisition_trace_verification_evidence_id_fk_idx on pipeline.scholarship_acquisition_trace (verification_evidence_id);
create index if not exists scholarship_acquisition_trace_discovery_evidence_id_fk_idx on pipeline.scholarship_acquisition_trace (discovery_evidence_id);
create index if not exists provider_fact_sources_evidence_id_fk_idx on pipeline.provider_fact_sources (evidence_id);
create index if not exists layer2_field_admissions_evidence_id_fk_idx on pipeline.layer2_field_admissions (evidence_id);
create index if not exists layer1_course_retirements_evidence_id_fk_idx on pipeline.layer1_course_retirements (evidence_id);
create index if not exists layer3_holdout_cases_evidence_id_fk_idx on pipeline.layer3_holdout_cases (evidence_id);
create index if not exists layer3_intake_benchmark_cases_evidence_id_fk_idx on pipeline.layer3_intake_benchmark_cases (evidence_id);
create index if not exists layer1_run_plans_zip_evidence_id_fk_idx on pipeline.layer1_run_plans (zip_evidence_id);
create index if not exists layer1_run_plans_course_evidence_id_fk_idx on pipeline.layer1_run_plans (course_evidence_id);
create index if not exists provider_directory_observations_evidence_id_fk_idx on pipeline.provider_directory_observations (evidence_id);
create index if not exists layer3_fact_handoffs_evidence_id_fk_idx on pipeline.layer3_fact_handoffs (evidence_id);
create index if not exists layer2_course_discovery_candidates_evidence_id_fk_idx on pipeline.layer2_course_discovery_candidates (evidence_id);
create index if not exists layer2_scale_qualification_items_evidence_id_fk_idx on pipeline.layer2_scale_qualification_items (evidence_id);
create index if not exists layer4_scope_rules_evidence_id_fk_idx on pipeline.layer4_scope_rules (evidence_id);
create index if not exists scholarship_ai_run_items_evidence_id_fk_idx on pipeline.scholarship_ai_run_items (evidence_id);

do $post$
declare v_left text;
begin
  select string_agg(k.conrelid::regclass::text || '.' || a.attname, ', ') into v_left
    from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
   where k.contype = 'f' and k.confrelid = 'pipeline.evidence_artifacts'::regclass
     and not exists (select 1 from pg_index i where i.indrelid = k.conrelid and i.indkey[0] = k.conkey[1]);
  if v_left is not null then raise exception 'post-check: still without an index: %', v_left; end if;
  if jsonb_array_length(security.consumer_api_check_v1() -> 'drift') <> 0 then raise exception 'post-check: consumer API drift'; end if;
end $post$;
