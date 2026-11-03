-- Workstream C cases after the migration (applied twice). Each block raises 'FAIL: ...' on the first broken expectation.

-- C1 shipped state: switches on, jobs active and catalogued, remedies registered with the right authority, coverage never automatic
do $$
begin
  perform fx.ok(security.scholarship_flag_v1('scholarship.discovery_settle_on', false), 'C1 settle ships on');
  perform fx.ok(security.scholarship_flag_v1('coverage.reconcile_on', false) and security.scholarship_flag_v1('coverage.investigations_on', false), 'C1 reconcile ships on');
  perform fx.ok((select count(*) from cron.job where jobname in ('scholarship-discovery-settle', 'coverage-reconcile') and active and command !~ '\(\s*\d') = 2, 'C1 two active jobs, no number in a command');
  perform fx.ok((select authority from pipeline.ops_remedies where code = 'sch_discovery_settle') = 'auto', 'C1 settle remedy is auto');
  perform fx.ok((select action_fn::text from pipeline.ops_remedies where code = 'sch_discovery_settle') = 'security.scholarship_discovery_settle_remedy_v1(bigint)', 'C1 settle action');
  perform fx.ok((select authority from pipeline.ops_remedies where code = 'coverage_investigation') = 'admin' and (select action_fn from pipeline.ops_remedies where code = 'coverage_investigation') is null, 'C1 investigations are admin, no action');
  perform fx.ok((select count(*) from pipeline.ops_root_causes) = 16, 'C1 sixteen root causes, found ' || (select count(*) from pipeline.ops_root_causes));
  perform fx.ok(not exists (select 1 from pipeline.ops_remedies r cross join unnest(r.treats) t where not exists (select 1 from pipeline.ops_root_causes c where c.code = t)), 'C1 every treated cause is registered');
  perform fx.ok((select count(*) from pipeline.platform_toolset_settings where (key like 'coverage.%' or key in ('scholarship.discovery_settle_on', 'batch.scholarship_discovery_settle', 'batch.coverage_reconcile'))
                  and (label is null or used_by is null or (kind = 'number' and (min_value is null or max_value is null or unit is null)))) = 0, 'C1 every setting has a label, used_by and a range and unit');
  raise notice 'C1 shipped state: switches and jobs on, remedies registered (settle auto; investigations admin), settings complete';
end $$;

-- C2 the AER coverage reader counts courses by lifecycle
do $$
declare s record;
begin
  select * into s from security.aer_provider_states_v1() x where x.provider_id = 'd0000000-0000-0000-0000-000000000002';
  perform fx.ok(s.courses_eligible = 40, 'C2 Harbour counts 40 courses, got ' || s.courses_eligible);
  select * into s from security.aer_provider_states_v1() x where x.provider_id = 'd0000000-0000-0000-0000-000000000009';
  perform fx.ok(s.course_req_proposed = 10, 'C2 River''s 10 proposed course rows are seen (' || s.course_req_proposed || ', ' || s.disposition || ')');
  raise notice 'C2 aer_provider_states_v1 counts 40 courses at Harbour and 10 proposed course rows at River';
end $$;

-- C3 discovery outcomes: refused rows settle with their reason; takeable, leased and not-yet-due rows are untouched; updated_at kept
do $$
declare v jsonb; r record;
begin
  perform fx.ok(not (security.scholarship_discovery_settle_verify_v1(0)->>'passed')::boolean, 'C3 verify fails before the settle');
  v := security.scholarship_discovery_settle_remedy_v1(0);
  perform fx.ok((v->>'ok')::boolean and (v->>'changed')::int = 4, 'C3 remedy settles 4 rows: ' || v::text);
  perform fx.ok((v->'evidence'->'settled_by_reason') = '{"not_eligible": 3, "unpublished": 1}'::jsonb, 'C3 reasons ' || (v->'evidence'->'settled_by_reason')::text);
  for r in select * from pipeline.scholarship_discovery_providers order by provider_id loop
    case r.provider_id::text
      when 'd0000000-0000-0000-0000-000000000001' then perform fx.ok(r.status = 'not_eligible' and r.settled_from = 'pending' and r.settle_reason = 'not_eligible' and r.next_discover_at is null and r.updated_at = '2026-10-13', 'C3 small VET settled, updated_at kept');
      when 'd0000000-0000-0000-0000-000000000002' then perform fx.ok(r.status = 'mapped' and r.settle_reason is null, 'C3 eligible university untouched');
      when 'd0000000-0000-0000-0000-000000000003' then perform fx.ok(r.status = 'not_eligible' and r.settled_from = 'mapped', 'C3 re-held mapped school settled from mapped');
      when 'd0000000-0000-0000-0000-000000000004' then perform fx.ok(r.status = 'empty', 'C3 empty VET not due yet: untouched');
      when 'd0000000-0000-0000-0000-000000000005' then perform fx.ok(r.status = 'not_eligible' and r.settle_reason = 'unpublished', 'C3 unpublished provider settled as unpublished');
      when 'd0000000-0000-0000-0000-000000000006' then perform fx.ok(r.status = 'pending', 'C3 leased row untouched');
      when 'd0000000-0000-0000-0000-000000000009' then perform fx.ok(r.status = 'not_eligible' and r.settle_reason = 'not_eligible', 'C3 small university settled');
      else null;
    end case;
  end loop;
  -- the leased row waits for its lease; verify still sees it, then passes once the lease has gone and the job runs again
  perform fx.ok(((security.scholarship_discovery_settle_verify_v1(0))->'measure'->>'waiting_refused')::int = 1, 'C3 one refused row (leased) still waiting');
  update pipeline.scholarship_discovery_providers set leased_until = now() - interval '1 minute' where provider_id = 'd0000000-0000-0000-0000-000000000006';
  v := security.scholarship_discovery_settle_v1();
  perform fx.ok((v->>'settled')::int = 1 and (v->>'waiting_takeable')::int = 0 and (v->>'not_eligible')::int = 5, 'C3 second run: ' || v::text);
  perform fx.ok((security.scholarship_discovery_settle_verify_v1(0)->>'passed')::boolean, 'C3 verify passes');
  v := security.scholarship_discovery_settle_v1();
  perform fx.ok((v->>'settled')::int = 0 and (v->>'restored')::int = 0, 'C3 a third run changes nothing');
  raise notice 'C3 refused rows (pending, deferred, re-held mapped) get not_eligible with the reason; eligible, leased and not-due rows untouched; idempotent';
end $$;

-- C4 return when the reason clears: a pending row returns due now; a mapped row returns to mapped at its re-read date; published again returns
do $$
declare v jsonb; r record;
begin
  insert into catalogue.courses(provider_id, canonical_title, publication_status) select 'd0000000-0000-0000-0000-000000000001', 'More ' || g, 'unpublished' from generate_series(1, 25) g;
  insert into catalogue.courses(provider_id, canonical_title, publication_status) select 'd0000000-0000-0000-0000-000000000003', 'School ' || g, 'unpublished' from generate_series(1, 30) g;
  update catalogue.providers set publication_status = 'published' where id = 'd0000000-0000-0000-0000-000000000005';
  v := security.scholarship_discovery_settle_v1();
  perform fx.ok((v->>'restored')::int = 2 and v->'restored_to' = '{"pending": 1, "mapped": 1}'::jsonb, 'C4 two return (the hidden VET is published but still has no course): ' || v::text);
  select * into r from pipeline.scholarship_discovery_providers where provider_id = 'd0000000-0000-0000-0000-000000000001';
  perform fx.ok(r.status = 'pending' and r.next_discover_at <= now() and r.settle_reason is null and r.settled_from is null, 'C4 small VET pending, due now');
  select * into r from pipeline.scholarship_discovery_providers where provider_id = 'd0000000-0000-0000-0000-000000000003';
  perform fx.ok(r.status = 'mapped' and r.next_discover_at = greatest(now(), r.discovered_at + interval '30 days'), 'C4 school back to mapped, due at its re-read date');
  select * into r from pipeline.scholarship_discovery_providers where provider_id = 'd0000000-0000-0000-0000-000000000005';
  perform fx.ok(r.status = 'not_eligible' and r.settle_reason = 'not_eligible', 'C4 the published-again VET keeps an outcome, its reason now eligibility');
  -- switched off: nothing moves
  update pipeline.platform_toolset_settings set value = 'false' where key = 'scholarship.discovery_settle_on';
  update pipeline.scholarship_discovery_providers set status = 'pending', settle_reason = null, settled_from = null where provider_id = 'd0000000-0000-0000-0000-000000000006';
  v := security.scholarship_discovery_settle_v1();
  perform fx.ok(not (v->>'on')::boolean and (select status from pipeline.scholarship_discovery_providers where provider_id = 'd0000000-0000-0000-0000-000000000006') = 'pending', 'C4 off: nothing settles');
  update pipeline.platform_toolset_settings set value = 'true' where key = 'scholarship.discovery_settle_on';
  perform security.scholarship_discovery_settle_v1();
  raise notice 'C4 rows return to their status when the reason clears (pending due now; mapped at its re-read date); off changes nothing';
end $$;

-- C5 scholarship coverage: under-represented, categories missing, listing not fanned out, facts incomplete, zero, no evidence
do $$
declare s record;
begin
  select * into s from security.scholarship_coverage_v1(array['d0000000-0000-0000-0000-000000000002'::uuid]);
  perform fx.ok((s.measures->>'anchor')::int = 10 and (s.measures->>'admitted')::int = 2 and (s.measures->>'held')::int = 1 and (s.measures->>'published')::int = 1, 'C5 Harbour 10 listed, 2 held: ' || s.measures::text);
  perform fx.ok(s.disposition = 'under_represented' and s.shortfall = 8, 'C5 under-represented, shortfall 8: ' || s.disposition);
  perform fx.ok(s.gaps @> array['under_represented', 'listing_partial', 'listing_not_fanned_out', 'category_missing:postgraduate', 'category_missing:research'], 'C5 gaps ' || s.gaps::text);
  perform fx.ok(not ('category_missing:undergraduate' = any (s.gaps)) and not ('category_missing:international' = any (s.gaps)), 'C5 undergraduate and international are held');
  perform fx.ok((s.categories->'listed'->>'postgraduate')::int = 6 and (s.categories->'held'->>'undergraduate')::int = 2, 'C5 categories ' || s.categories::text);
  perform fx.ok((s.measures->'fields'->>'value')::int = 1 and (s.measures->'fields'->>'funding_type')::int = 1 and (s.measures->'fields'->>'study_level')::int = 2, 'C5 facts ' || (s.measures->'fields')::text);
  perform fx.ok(not exists (select 1 from unnest(s.gaps) x where x like 'fields_incomplete:%') and (s.measures->'fields'->>'academic_requirements')::int = 0, 'C5 Harbour holds 2 (below the minimum to judge facts); academic measured: ' || s.gaps::text);
  select * into s from security.scholarship_coverage_v1(array['d0000000-0000-0000-0000-000000000007'::uuid]);
  perform fx.ok(s.disposition = 'zero' and s.gaps = array['zero_scholarships'], 'C5 a university with zero scholarships: ' || s.gaps::text);
  select * into s from security.scholarship_coverage_v1(array['d0000000-0000-0000-0000-000000000004'::uuid]);
  perform fx.ok(s.disposition = 'no_evidence' and cardinality(s.gaps) = 0, 'C5 a VET with no listing and no records is not a gap');
  select * into s from security.scholarship_coverage_v1(array['d0000000-0000-0000-0000-000000000006'::uuid]);
  perform fx.ok(s.disposition = 'no_evidence', 'C5 a settled VET without evidence is not reported as a gap');
  select * into s from security.scholarship_coverage_v1(array['d0000000-0000-0000-0000-000000000011'::uuid]);
  perform fx.ok(s.disposition = 'not_applicable' and cardinality(s.gaps) = 0 and (s.measures->>'register')::int = 3, 'C5 a school named by the register is not applicable');
  select * into s from security.scholarship_coverage_v1(array['d0000000-0000-0000-0000-000000000012'::uuid]);
  perform fx.ok(s.disposition = 'blocked_policy' and s.gaps = array['admission_policy'], 'C5 an HE institute the admission rule refuses: policy, not missing data');
  raise notice 'C5 scholarship coverage: Harbour under-represented (10 listed, 2 held), postgraduate and research missing, listing not fanned out; Plains zero';
end $$;

-- C6 AER coverage: countries and pathways the source names but are not held, cells omitted, course-level and intake gaps, outside the population,
-- domestic-only source, routes into the scheduled AER reader
do $$
declare s record;
begin
  select * into s from security.aer_coverage_v1(array['d0000000-0000-0000-0000-000000000002'::uuid]);
  perform fx.ok(s.gaps @> array['cells_omitted', 'countries_missing', 'course_level_gap', 'intake_gap', 'deadline_gap', 'pathway_missing:IB', 'pathway_missing:Nepal'], 'C6 Harbour gaps ' || s.gaps::text);
  perform fx.ok(not ('pathway_missing:India' = any (s.gaps)) and not ('pathway_missing:GCE A Level' = any (s.gaps)), 'C6 a pathway the source does not name is never a gap: ' || s.gaps::text);
  perform fx.ok(s.categories->'countries_missing' = '["NP"]'::jsonb and s.categories->'pathways_held' = '["India"]'::jsonb, 'C6 categories ' || s.categories::text);
  perform fx.ok((s.measures->>'courses')::int = 40 and (s.measures->>'courses_with_page')::int = 20 and (s.measures->>'courses_req_any')::int = 0, 'C6 courses ' || s.measures::text);
  perform fx.ok(s.measures->'routes' ? 'courses_due' and s.measures->'routes' ? 'courses_without_page' and s.measures->'routes' ? 'matrix', 'C6 routes ' || (s.measures->'routes')::text);
  perform fx.ok(s.shortfall = 20 + 1 + 2 + 2, 'C6 shortfall ' || s.shortfall);
  select * into s from security.aer_coverage_v1(array['d0000000-0000-0000-0000-000000000008'::uuid]);
  perform fx.ok(s.gaps @> array['outside_aer_population'] and not (s.measures->>'eligible')::boolean, 'C6 a university the eligibility rule leaves out is reported: ' || s.gaps::text);
  select * into s from security.aer_coverage_v1(array['d0000000-0000-0000-0000-000000000009'::uuid]);
  perform fx.ok(s.gaps @> array['domestic_only_source'] and not (s.gaps && array['intake_gap', 'deadline_gap']), 'C6 River: domestic-only source flagged, intakes held: ' || s.gaps::text);
  select * into s from security.aer_coverage_v1(array['d0000000-0000-0000-0000-000000000010'::uuid]);
  perform fx.ok(s.gaps @> array['no_source'] and not (s.measures->>'provider_level')::boolean, 'C6 Valley VET: no source, not provider-level');
  raise notice 'C6 AER coverage: Nepal and IB named by the source but not held, cells omitted, course and intake gaps; Fiord outside the population; River domestic only';
end $$;

-- C7 reconciliation: ledger for every provider, one investigation per provider (never per record), grouped long tail, new-issue cap
do $$
declare v jsonb; n int;
begin
  update pipeline.platform_toolset_settings set value = '3' where key = 'coverage.investigations_per_run';
  v := security.coverage_reconcile_v1();
  perform fx.ok((v->'scholarship'->>'looked_at')::int = 12 and (v->'aer'->>'looked_at')::int = 12, 'C7 first run looks at every provider: ' || v::text);
  perform fx.ok((select count(*) from pipeline.coverage_provider_reconciliation) = 24, 'C7 ledger rows');
  perform fx.ok((v->'scholarship'->>'investigations_new')::int = 3 and (v->'scholarship'->>'investigations_waiting')::int = 1 and (v->'aer'->>'investigations_new')::int = 3 and (v->'aer'->>'investigations_waiting')::int = 1, 'C7 cap of 3 new a run: ' || v::text);
  perform fx.ok(exists (select 1 from pipeline.integration_issues where fingerprint = 'coverage:scholarship:d0000000-0000-0000-0000-000000000002' and workstream = 'A2' and severity = 'P2'
                         and provider_ids = array['d0000000-0000-0000-0000-000000000002'::uuid] and evidence->'coverage'->>'disposition' = 'under_represented'), 'C7 Harbour scholarship investigation');
  perform fx.ok((select severity from pipeline.integration_issues where fingerprint = 'coverage:scholarship:d0000000-0000-0000-0000-000000000007') = 'P1', 'C7 a university with zero scholarships is P1');
  perform fx.ok(exists (select 1 from pipeline.integration_issues where fingerprint = 'coverage:aer:AU:no_source' and provider_ids @> array['d0000000-0000-0000-0000-000000000010'::uuid]), 'C7 grouped: AU providers with no source');
  perform fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'coverage:%') = 3 + 3 + (v->'aer'->>'groups')::int + (v->'scholarship'->>'groups')::int, 'C7 one issue per provider and domain, plus groups');
  perform fx.ok(exists (select 1 from pipeline.integration_issues where fingerprint = 'coverage:scholarship:AU:admission_policy' and provider_ids = array['d0000000-0000-0000-0000-000000000012'::uuid]), 'C7 grouped: the policy-refused HE institute');
  perform fx.ok(not exists (select 1 from pipeline.integration_issues where 'd0000000-0000-0000-0000-000000000011'::uuid = any (provider_ids) and fingerprint like 'coverage:scholarship:%'), 'C7 the school has no scholarship issue');
  perform fx.ok((select issue_fingerprint from pipeline.coverage_provider_reconciliation where domain = 'scholarship' and provider_id = 'd0000000-0000-0000-0000-000000000002') = 'coverage:scholarship:d0000000-0000-0000-0000-000000000002', 'C7 ledger links the issue');
  raise notice 'C7 reconcile: 24 ledger rows, 6 provider investigations within the cap of 3 a domain (1 waiting in each), grouped long tail: %', v::text;
end $$;

-- C8 incremental: nothing changed means nothing looked at; a change or a due recheck brings back exactly those providers; issues are updated, not duplicated
do $$
declare v jsonb; n int;
begin
  select count(*) into n from pipeline.integration_issues;
  v := security.coverage_reconcile_v1();
  perform fx.ok((v->'scholarship'->>'looked_at')::int = 0 and (v->'aer'->>'looked_at')::int = 0, 'C8 nothing changed: nothing looked at: ' || v::text);
  update scholarship.scholarships set updated_at = now() + interval '1 second' where id = 'e0000000-0000-0000-0000-000000000002';
  update pipeline.coverage_provider_reconciliation set computed_at = computed_at - interval '7 hours' where domain = 'aer' and provider_id = 'd0000000-0000-0000-0000-000000000002';
  v := security.coverage_reconcile_v1();
  perform fx.ok((v->'scholarship'->>'looked_at')::int = 1 and v->'scholarship'->'why' = '{"changed": 1}'::jsonb, 'C8 the changed provider only: ' || v::text);
  -- (the fixture's AER rows were all written after the back-dated reconciliation, so the provider counts as changed, which ranks first)
  perform fx.ok((v->'aer'->>'looked_at')::int = 1 and (v->'aer'->'why' ? 'discrepancy' or v->'aer'->'why' ? 'changed'), 'C8 the provider due a recheck only: ' || v::text);
  perform fx.ok((select count(*) from pipeline.integration_issues) = n, 'C8 no duplicate issue');
  perform fx.ok((select retry_count from pipeline.integration_issues where fingerprint = 'coverage:scholarship:d0000000-0000-0000-0000-000000000002') = 1, 'C8 re-observed once');
  update pipeline.coverage_provider_reconciliation set computed_at = computed_at - interval '25 hours' where domain = 'scholarship';
  v := security.coverage_reconcile_v1('scholarship');
  perform fx.ok((v->'scholarship'->>'looked_at')::int = 12 and not v ? 'aer', 'C8 the periodic broad check takes every provider again: ' || v::text);
  update pipeline.platform_toolset_settings set value = '2' where key = 'batch.coverage_reconcile';
  update pipeline.coverage_provider_reconciliation set computed_at = computed_at - interval '25 hours' where domain = 'scholarship';
  v := security.coverage_reconcile_v1('scholarship');
  perform fx.ok((v->'scholarship'->>'looked_at')::int = 2, 'C8 batch.coverage_reconcile bounds a run');
  update pipeline.platform_toolset_settings set value = '300' where key = 'batch.coverage_reconcile';
  raise notice 'C8 incremental: unchanged providers are not looked at; changed and due-recheck providers are; broad check every 24 h; batch bounded';
end $$;

-- C9 the verify functions: an investigation passes once the provider's coverage has no gap; the AER course count passes after aer-reconcile
do $$
declare v jsonb; i bigint;
begin
  select id into i from pipeline.integration_issues where fingerprint = 'coverage:scholarship:d0000000-0000-0000-0000-000000000007';
  perform fx.ok(not (security.coverage_investigation_verify_v1(i)->>'passed')::boolean, 'C9 Plains still has zero scholarships');
  insert into scholarship.scholarships(provider_id, name, audience, award_value_type, award_amount, application_close_date)
  values ('d0000000-0000-0000-0000-000000000007', 'Plains Merit', 'international', 'fixed_amount', 2000, '2027-02-01');
  v := security.coverage_investigation_verify_v1(i);
  perform fx.ok((v->>'passed')::boolean, 'C9 verify passes once Plains holds a scholarship: ' || v::text);
  select id into i from pipeline.integration_issues where fingerprint = 'coverage:aer:AU:no_source';
  perform fx.ok(not (security.coverage_investigation_verify_v1(i)->>'passed')::boolean, 'C9 grouped issue still open');
  perform fx.ok(not (security.aer_course_counts_verify_v1(0)->>'passed')::boolean, 'C9 stored AER coverage not yet refreshed');
  perform security.aer_reconcile_v1(null);
  v := security.aer_course_counts_verify_v1(0);
  perform fx.ok((v->>'passed')::boolean, 'C9 AER course counts verified after aer-reconcile: ' || v::text);
  raise notice 'C9 verify functions: investigation passes when the gap is gone; AER course counts pass after aer-reconcile';
end $$;

-- C10 nothing is admitted, published or read: Layer 4, scholarships' publication and discovery reads are untouched by every run
do $$
begin
  perform fx.ok((select count(*) from pipeline.layer4_review_items) = 0, 'C10 no Layer 4 item created');
  perform fx.ok((select count(*) from scholarship.scholarships where publication_status = 'published') = 2, 'C10 publication unchanged');
  perform fx.ok((select coalesce(sum(attempts), 0) from pipeline.scholarship_discovery_providers) = 4, 'C10 no discovery attempt spent (4 as loaded)');
  perform fx.ok((select count(*) from catalogue.course_entry_requirements where status = 'active') = 0, 'C10 no requirement admitted');
  raise notice 'C10 nothing admitted, published or read';
end $$;
