-- CF-247 s1011 (S1-Build; Platform Admin 23 Nov 2026 20:38 AEDT): security and index hardening from the architecture audit bundle
-- (coursefinder-architecture-audit-bundle.md, sections 2.2, 8 and 9.4), all read against live in rolled-back runs first.
-- 1. Row-level security on every application table that had it off: 93 tables (the audit named 13; the live catalogue holds 93), among them
--    private.zoho_integration_credentials and private.zoho_integration_rate_windows. Every one is owned by postgres, and 92 grant nothing to
--    anon or authenticated, so they are read only by postgres-owned security definer functions, service_role or postgres, all of which bypass
--    row-level security. Turning it on therefore changes no read or write today and closes the tables to any future grant made by mistake.
--    ref.nationality_terms is the one table signed-in users may read (its existing grant); it gets an explicit read policy so that read keeps working.
--    The consumer API check compares function definitions and column types only; no column, type or function changes (75/48 before and after).
-- 2. pipeline.saved_courses (s997): the three policies read auth.uid() once per statement, (select auth.uid()), which clears the advisor's
--    auth_rls_initplan warning. Same rows allowed as before.
-- 3. Missing foreign-key indexes: catalogue.course_entry_requirements (country_id) and catalogue.provider_entry_matrix (study_level_id; the
--    existing provider_entry_matrix_lookup_ix holds it only in third place). Built inside a short lock retry so a busy writer never queues
--    behind this change. The three duplicate index pairs are dropped by the Platform Admin's paste file (admin docs/paste/), not here.
-- G1: no job. G2: no operational value (the lock waits are fixed technical values). G3: no consumer object changed. Manual locks and active
-- cron jobs checked unchanged. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the table and policy changes

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1011_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1011_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1011_rls on commit drop as select unnest(array[
    'catalogue.course_identifiers',
    'catalogue.provider_qualification_requirements',
    'pipeline.aer_discovery_campaigns',
    'pipeline.aer_discovery_spare_spends',
    'pipeline.aer_matrix_machine_admissions',
    'pipeline.aer_matrix_machine_validations',
    'pipeline.aer_read_supersessions',
    'pipeline.aer_schedule_checks',
    'pipeline.aer_schedule_runs',
    'pipeline.aer_source_attachments',
    'pipeline.aer_v2_eval_cases',
    'pipeline.aer_v2_eval_plans',
    'pipeline.aer_v2_identity_fixture',
    'pipeline.aer_v2_identity_settlements',
    'pipeline.aer_v2_sample',
    'pipeline.aer_v3_eval_gold',
    'pipeline.ai_spend_ledger',
    'pipeline.ca_course_scope_keys',
    'pipeline.country_scope_levels',
    'pipeline.course_credential_reads',
    'pipeline.course_field_absence',
    'pipeline.course_scope_changes',
    'pipeline.credential_level_map',
    'pipeline.credential_rules',
    'pipeline.enrich_ai_answers',
    'pipeline.enrich_plan_auto_runs',
    'pipeline.enrich_plan_noop',
    'pipeline.environment_source_gates',
    'pipeline.evidence_capacity_policy',
    'pipeline.evidence_entity_links',
    'pipeline.evidence_lineage_stats',
    'pipeline.field_absence_classes',
    'pipeline.field_absence_rules',
    'pipeline.important_dates',
    'pipeline.important_links',
    'pipeline.layer2_provider_environment_gates',
    'pipeline.layer3_interpretations',
    'pipeline.layer3_model_profiles',
    'pipeline.layer3_profile_environment_gates',
    'pipeline.layer4_block_decisions',
    'pipeline.layer4_decisions',
    'pipeline.layer4_review_items',
    'pipeline.on_demand_requests',
    'pipeline.ops_cost_breakers',
    'pipeline.ops_cost_waste_measures',
    'pipeline.ops_lane_priority_snapshots',
    'pipeline.performance_workload_profiles',
    'pipeline.platform_capacity_observations',
    'pipeline.platform_capacity_policy',
    'pipeline.platform_uat_catalogue',
    'pipeline.programme_candidates',
    'pipeline.programme_sources',
    'pipeline.provider_identity_findings',
    'pipeline.provider_identity_investigations',
    'pipeline.provider_lifecycle_events',
    'pipeline.queue_watch',
    'pipeline.queue_watch_alerts',
    'pipeline.queue_watch_events',
    'pipeline.queue_watch_fixes',
    'pipeline.queue_watch_retries',
    'pipeline.queue_watch_state',
    'pipeline.refresh_policies',
    'pipeline.refresh_requests',
    'pipeline.register_end_date_runs',
    'pipeline.retention_class_policies',
    'pipeline.scholarship_attribute_sync',
    'pipeline.scholarship_coverage_items',
    'pipeline.scholarship_coverage_providers',
    'pipeline.scholarship_coverage_recoveries',
    'pipeline.scholarship_coverage_state_codes',
    'pipeline.scholarship_owner_proposals',
    'pipeline.scholarship_read_requests',
    'pipeline.scholarship_read_retry_cycles',
    'pipeline.source_find_countries',
    'pipeline.source_find_paths',
    'pipeline.source_find_runs',
    'pipeline.source_proof_feed_runs',
    'pipeline.source_record_staging',
    'pipeline.stats_15m',
    'private.zoho_integration_credentials',
    'private.zoho_integration_rate_windows',
    'publishing.publication_approvals',
    'publishing.publication_events',
    'publishing.publication_profiles',
    'ranking.edition_status_changes',
    'ref.aer_qualifications',
    'ref.au_regional_postcode_ranges',
    'ref.nationality_terms',
    'scholarship.audience_readings',
    'scholarship.nationality_readings',
    'search.enrichment_gates',
    'search.enrichment_source_gates',
    'search.projection_country_gates'
  ]::text[]) nm;

-- 1. row-level security on (owner and bypass roles unaffected)
do $r$
declare t record; n int := 0; v_try int;
begin
  for t in select r.nm, c.oid from s1011_rls r join pg_class c on c.oid = to_regclass(r.nm) loop
    if exists (select 1 from pg_class c where c.oid = t.oid and pg_get_userbyid(c.relowner) <> 'postgres') then
      raise exception 'guard: % is not owned by postgres; this change was written for postgres-owned tables', t.nm;
    end if;
    -- each table inside a short lock retry: busy ledgers (for example pipeline.ai_spend_ledger) are written all the time
    v_try := 0;
    loop
      begin
        perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
        execute format('alter table %s enable row level security', t.nm);
        exit;
      exception when lock_not_available then
        v_try := v_try + 1;
        if v_try >= 10 then raise exception 'could not take the lock on % to turn row-level security on', t.nm; end if;  -- fixed: tries before giving up
        perform pg_sleep(2);  -- fixed: pause between tries
      end;
    end loop;
    n := n + 1;
  end loop;
  if n <> 93 then raise exception 'guard: % of the 93 tables were found', n; end if;
end $r$;
create policy nationality_terms_read on ref.nationality_terms for select to authenticated using (true);

-- 2. saved courses: auth.uid() read once per statement
alter policy saved_courses_own_select on pipeline.saved_courses using (user_id = (select auth.uid()));
alter policy saved_courses_own_insert on pipeline.saved_courses with check (user_id = (select auth.uid()));
alter policy saved_courses_own_delete on pipeline.saved_courses using (user_id = (select auth.uid()));

-- 3. foreign-key indexes, each inside a short lock retry
do $i$
declare v_sql text; v_try int;
begin
  foreach v_sql in array array[
    'create index if not exists course_entry_requirements_country_id_idx on catalogue.course_entry_requirements (country_id)',
    'create index if not exists provider_entry_matrix_study_level_id_idx on catalogue.provider_entry_matrix (study_level_id)'] loop
    v_try := 0;
    loop
      begin
        perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
        execute v_sql;
        exit;
      exception when lock_not_available then
        v_try := v_try + 1;
        if v_try >= 5 then raise exception 'could not take the lock for: %', v_sql; end if;  -- fixed: tries before giving up
        perform pg_sleep(2);  -- fixed: pause between tries
      end;
    end loop;
  end loop;
end $i$;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1011_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1011_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if exists (select 1 from s1011_rls r join pg_class c on c.oid = to_regclass(r.nm) where not c.relrowsecurity) then
    raise exception 'post-check: a table still has row-level security off';
  end if;
  if exists (select 1 from pg_policies p where p.schemaname = 'pipeline' and p.tablename = 'saved_courses'
              and coalesce(p.qual, p.with_check) not like '%SELECT auth.uid()%') then
    raise exception 'post-check: a saved_courses policy still calls auth.uid() per row';
  end if;
  if to_regclass('catalogue.course_entry_requirements_country_id_idx') is null or to_regclass('catalogue.provider_entry_matrix_study_level_id_idx') is null then
    raise exception 'post-check: a foreign-key index is missing';
  end if;
  if not has_table_privilege('authenticated', 'ref.nationality_terms', 'select') then raise exception 'post-check: signed-in users lost the nationality terms read'; end if;
end $post$;
