-- Cases after 20261104370000. Each block raises on failure and prints NOTICE "ok ..." on success.
create or replace function pg_temp.ok(p boolean, p_msg text) returns void language plpgsql as $$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok %', p_msg; end $$;
create or replace function pg_temp.st(p_key text) returns text language sql as $$ select state from pipeline.scholarship_coverage_items where item_key = p_key and present $$;
create or replace function pg_temp.set(p_key text, p_v numeric) returns void language sql as $$
  update pipeline.platform_toolset_settings set value = to_jsonb(p_v) where toolset_key = 'pipeline' and key = p_key $$;
create or replace function pg_temp.wi(p_provider text, p_state text) returns text language sql as $$
  select stage || coalesce('/' || failure_class, '') from pipeline.work_items where lane = 'sch_coverage' and entity = p_provider and work_kind = 'state:' || p_state $$;

-- 1 the switches ship off; classification ships on ------------------------------------------------------------------------------------------------
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where key in ('sch_cov.legal_name_identity_on', 'sch_cov.policy_disposition_on', 'sch_cov.recover_register_pages_on',
                   'sch_cov.recover_stored_reads_on', 'sch_cov.recover_listings_on') and (value #>> '{}')::numeric = 0) = 5, 'every spending or admitting switch ships 0');
select pg_temp.ok((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where key = 'sch_cov.classify_on') = 1, 'classification ships on');
select pg_temp.ok((select count(*) from pipeline.platform_toolset_settings where key like 'sch_cov.%' or key like 'batch.sch_coverage_%') = 13
                  and not exists (select 1 from pipeline.platform_toolset_settings where (key like 'sch_cov.%' or key like 'batch.sch_coverage_%')
                                   and (label is null or unit is null or used_by is null or min_value is null or max_value is null)), 'G2: 13 settings, each with label, range, unit and used_by');
select pg_temp.ok((select count(*) from pipeline.scholarship_coverage_state_codes) = 13, '13 coverage states');
select pg_temp.ok(not exists (select 1 from cron.job where jobname like 'scholarship-coverage-%' and command ~ '[(,]\s*[0-9]'), 'G2: job commands carry no number');

-- 2 D1 legal-name identity (switch) ----------------------------------------------------------------------------------------------------------------
select pg_temp.ok(not security.scholarship_university('10000000-0000-0000-0000-000000000001'), 'D1 off: Torrens refused as before');
select pg_temp.set('sch_cov.legal_name_identity_on', 1);
select pg_temp.ok(security.scholarship_university('10000000-0000-0000-0000-000000000001') and security.scholarship_admission_provider_ok_v1('10000000-0000-0000-0000-000000000001'),
                  'D1 on: Torrens is a university on its legal name; admission eligibility true');
select pg_temp.ok(not security.scholarship_university('10000000-0000-0000-0000-000000000002') and not security.scholarship_university('10000000-0000-0000-0000-000000000003'),
                  'D1 on: TAFE SA and Box Hill are not universities');
select pg_temp.set('sch_cov.legal_name_identity_on', 0);

-- 3 D5 policy disposition (switch) -----------------------------------------------------------------------------------------------------------------
select pg_temp.ok((select disposition from security.scholarship_coverage_v1(array['10000000-0000-0000-0000-000000000002'::uuid])) = 'zero', 'D5 off: TAFE SA reported as before');
select pg_temp.set('sch_cov.policy_disposition_on', 1);
select pg_temp.ok((select disposition from security.scholarship_coverage_v1(array['10000000-0000-0000-0000-000000000002'::uuid])) = 'blocked_policy'
                  and (select disposition from security.scholarship_coverage_v1(array['10000000-0000-0000-0000-000000000003'::uuid])) = 'blocked_policy',
                  'D5 on: TAFE SA and Box Hill blocked by policy');
select pg_temp.ok((select disposition from security.scholarship_coverage_v1(array['10000000-0000-0000-0000-000000000001'::uuid])) <> 'blocked_policy',
                  'D5 on: a university refused by the name rule is never hidden as policy (Torrens stays a defect)');
select pg_temp.set('sch_cov.policy_disposition_on', 0);

-- 4 D7 Read again --------------------------------------------------------------------------------------------------------------------------------------
do $$
declare v jsonb := public.svc_scholarship_read_next(10);
begin
  perform pg_temp.ok(jsonb_array_length(v) = 1 and v @> '[{"scholarship_id": "30000000-0000-0000-0000-000000000001"}]',
                     'D7: the page asked for since its last read is picked; not requested, waiting for the scraper, or leased pages are not');
  -- the recorder clears the request after the read (svc_scholarship_read_record, unchanged): never read twice for one request
  update pipeline.scholarship_pages set requested_at = null, read_at = now(), leased_until = null, next_read_at = now() + interval '90 days', attempts = 0
   where scholarship_id = '30000000-0000-0000-0000-000000000001';
  perform pg_temp.ok(jsonb_array_length(public.svc_scholarship_read_next(10)) = 0, 'D7: read once per request');
end $$;

-- 5 classification -------------------------------------------------------------------------------------------------------------------------------------
set fx.consumer_missing = '20000000-0000-0000-0000-000000000002';
select pg_temp.ok((security.scholarship_coverage_classify_v1()->>'providers')::int = 5, 'the job classifies the five reconciled providers');
select pg_temp.ok(pg_temp.st('cand:1') = 'rejected_incorrectly' and (select reason from pipeline.scholarship_coverage_items where item_key = 'cand:1') = 'provider_identity_name_rule'
                  and (select recovery from pipeline.scholarship_coverage_items where item_key = 'cand:1') = 'reread_stored', 'IQ-00215: Motivational Scholarship rejected incorrectly (name rule), reread from stored copy');
select pg_temp.ok(pg_temp.st('cand:2') = 'rejected_incorrectly' and (select recovery from pipeline.scholarship_coverage_items where item_key = 'cand:2') = 'reopen_read',
                  'IQ-00215: register provider page never read: rejected incorrectly, one read');
select pg_temp.ok(pg_temp.st('cand:3') = 'rejected_correctly' and pg_temp.st('cand:4') = 'rejected_correctly' and pg_temp.st('cand:5') = 'rejected_correctly',
                  'IQ-00215: listing with a listing source, not a scholarship, news: rejected correctly');
select pg_temp.ok(pg_temp.st('reg:au_study_australia:bm1') = 'ownership_conflict', 'IQ-00215: BMIHMS award on the sub-brand host is an ownership conflict');
select pg_temp.ok(pg_temp.st('list:1:torrens.edu.au/scholarships/international-scholarships/family-scholarship') = 'traversal_incomplete'
                  and not exists (select 1 from pipeline.scholarship_coverage_items where item_key like 'list:1:%pepea%')
                  and not exists (select 1 from pipeline.scholarship_coverage_items where item_key like 'list:1:%bluemountains%'),
                  'IQ-00215: Family Scholarship not traversed (listing read before fan-out); items already candidates or off-site are not counted');
select pg_temp.ok(pg_temp.st('cand:6') = 'traversal_incomplete' and pg_temp.st('cand:7') = 'domestic_only' and pg_temp.st('cand:8') = 'awaiting_layer4'
                  and pg_temp.st('cand:9') = 'international_unresolved', 'IQ-00216: listing not traversed, domestic only, awaiting Layer 4, international unresolved');
select pg_temp.ok((select count(*) from pipeline.scholarship_coverage_items where item_key = 'provider') = 1 and (select state from pipeline.scholarship_coverage_items where provider_id = '10000000-0000-0000-0000-000000000003' and item_key = 'provider') = 'source_not_discovered',
                  'IQ-00219: Box Hill source not discovered (map kept nothing), not evidence of absence');
select pg_temp.ok(pg_temp.st('sch:20000000-0000-0000-0000-000000000001') = 'published_verified' and pg_temp.st('sch:20000000-0000-0000-0000-000000000002') = 'admitted_not_published'
                  and pg_temp.st('sch:20000000-0000-0000-0000-000000000003') = 'expired', 'published and consumer-verified; published but missing from the consumer API; ended');
select pg_temp.ok(pg_temp.st('cand:10') = 'rejected_incorrectly' and pg_temp.st('cand:11') = 'traversal_incomplete' and pg_temp.st('cand:13') = 'rejected_correctly'
                  and pg_temp.st('listing:2') = 'source_found_unread', 'a register page on a directory site stays rejected; a suggested listing is found but unread');
select pg_temp.ok((select provider_state from pipeline.scholarship_coverage_providers where provider_id = '10000000-0000-0000-0000-000000000005') = 'evidence_backed_none',
                  'a complete listing read with every case resolved and none published: evidence-backed none');
select pg_temp.ok((select provider_state from pipeline.scholarship_coverage_providers where provider_id = '10000000-0000-0000-0000-000000000001') = 'traversal_incomplete'
                  and (select unresolved from pipeline.scholarship_coverage_providers where provider_id = '10000000-0000-0000-0000-000000000001') = 4, 'Torrens: 4 unresolved cases');
select pg_temp.ok(not exists (select 1 from pipeline.scholarship_coverage_items i join pipeline.scholarship_coverage_state_codes k on k.code = i.state
                               where not k.resolved and (i.owner is null or i.next_recovery_at is null or i.escalation is null or i.evidence = '{}'::jsonb)),
                  'every unresolved case has an owner, evidence, a next recovery time and an escalation condition');
select pg_temp.ok(not exists (select 1 from pipeline.scholarship_coverage_items i join pipeline.scholarship_coverage_state_codes k on k.code = i.state
                               where k.resolved and (i.next_recovery_at is not null or i.escalation is not null)), 'resolved cases carry no recovery time or escalation');

-- 6 the work-continuity record ------------------------------------------------------------------------------------------------------------------------
select pg_temp.ok(pg_temp.wi('10000000-0000-0000-0000-000000000001', 'rejected_incorrectly') = 'deferred'
                  and pg_temp.wi('10000000-0000-0000-0000-000000000001', 'ownership_conflict') = 'quarantined/identity_conflict'
                  and pg_temp.wi('10000000-0000-0000-0000-000000000002', 'awaiting_layer4') = 'awaiting_review/human_review'
                  and pg_temp.wi('10000000-0000-0000-0000-000000000002', 'international_unresolved') = 'parked/ambiguity'
                  and pg_temp.wi('10000000-0000-0000-0000-000000000003', 'source_not_discovered') = 'deferred',
                  'work items: recoverable deferred, ownership quarantined, Layer 4 awaiting review, ambiguity parked');
select pg_temp.ok((select count(*) from pipeline.work_items where lane = 'sch_coverage' and work_kind like 'state:%'
                    and work_kind in ('state:rejected_correctly', 'state:domestic_only', 'state:expired', 'state:published_verified', 'state:evidence_backed_none')) = 0,
                  'resolved states raise no work item');
select pg_temp.ok((security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000003',
                   '10000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000005']::uuid[])->>'work_reports')::int = 0, 'unchanged cases are not reported again (no repeated reports)');
select pg_temp.ok((security.scholarship_coverage_classify_v1()->>'providers')::int = 0, 'a provider classified within sch_cov.reclassify_hours is not picked again');

-- 7 bounded recovery ---------------------------------------------------------------------------------------------------------------------------------
select pg_temp.ok((security.scholarship_coverage_recover_v1()->>'ran')::boolean = false, 'every recovery switch off: nothing happens');
select pg_temp.set('sch_cov.recover_register_pages_on', 1); select pg_temp.set('sch_cov.recover_stored_reads_on', 1); select pg_temp.set('sch_cov.recover_listings_on', 1);
do $$
declare v jsonb := security.scholarship_coverage_recover_v1();
begin
  perform pg_temp.ok((v->>'actions')::int = 2 and (v->'by_action'->>'reopen_read')::int = 1 and (v->'by_action'->>'promote_listing')::int = 1,
                     'switches on: only the admission-eligible provider recovers (Example: one register page, one listing); Torrens (name rule off) and TAFE SA (policy) wait');
  perform pg_temp.ok((select admit_status is null and next_read_at <= now() and attempts = 0 from pipeline.scholarship_page_candidates where id = 10), 'reopen_read: the page is due for the candidate reader once');
  perform pg_temp.ok((select source = 'auto' and active and status = 'waiting' and next_read_at <= now() from pipeline.scholarship_listing_pages where id = 2), 'promote_listing: the suggested listing becomes a source, due now');
  perform pg_temp.ok((select admit_status = 'rejected' from pipeline.scholarship_page_candidates where id = 13), 'a register page on a directory site is never reopened');
  perform pg_temp.ok(not exists (select 1 from pipeline.scholarship_coverage_recoveries where provider_id in ('10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002')),
                     'skipped cases are not used up: they are tried when their provider becomes eligible');
end $$;
select pg_temp.set('sch_cov.legal_name_identity_on', 1); select pg_temp.set('sch_cov.recover_per_provider_max', 2);
insert into pipeline.fx_held values ('10000000-0000-0000-0000-000000000001');
select pg_temp.ok((security.scholarship_coverage_recover_v1()->>'actions')::int = 0, 'a provider held by its Firecrawl cap is not recovered');
delete from pipeline.fx_held;
do $$
declare v jsonb := security.scholarship_coverage_recover_v1(); v2 jsonb;
begin
  perform pg_temp.ok((v->>'actions')::int = 2 and (v->>'providers')::int = 1, 'name rule on: Torrens recovers, at most sch_cov.recover_per_provider_max (2) a run');
  v2 := security.scholarship_coverage_recover_v1();
  perform pg_temp.ok((v2->>'actions')::int = 1, 'the next run takes the remaining Torrens case');
  perform pg_temp.ok((security.scholarship_coverage_recover_v1()->>'actions')::int = 0, 'a third run takes nothing: each case once');
  perform pg_temp.ok((select count(*) from pipeline.scholarship_ai_queue where candidate_id = 1) = 1
                     and (select storage_path = 'sch/7887.gz' and run_kind = 'admit' from pipeline.scholarship_ai_queue where candidate_id = 1)
                     and (select admit_status is null and next_read_at = 'infinity' from pipeline.scholarship_page_candidates where id = 1),
                     'reread_stored: one AI read from the stored copy; the candidate reader (Firecrawl) never takes it');
  perform pg_temp.ok((select next_read_at <= now() from pipeline.scholarship_listing_pages where id = 1), 'refresh_listing: the listing read before fan-out is due now');
  perform pg_temp.ok(not exists (select 1 from pipeline.scholarship_coverage_recoveries where provider_id = '10000000-0000-0000-0000-000000000002'),
                     'TAFE SA (outside the admission policy) is never recovered: no spend on a provider that cannot admit');
end $$;
select pg_temp.set('sch_cov.recover_per_provider_max', 3);

-- 8 verification of recoveries, escalation, resolution -----------------------------------------------------------------------------------------------
do $$
declare v jsonb;
begin
  v := security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004']::uuid[]);
  perform pg_temp.ok((select count(*) from pipeline.scholarship_coverage_recoveries where outcome = 'succeeded') = 4
                     and pg_temp.st('cand:1') = 'source_found_unread' and pg_temp.st('cand:10') = 'source_found_unread' and pg_temp.st('cand:11') = 'rejected_correctly',
                     'recoveries verified: the cases moved (waiting for the readers; the listing is now a source)');
  -- the listing was not read again within sch_cov.verify_after_hours: the recovery failed and the case escalates
  update pipeline.scholarship_coverage_recoveries set at = now() - interval '3 days' where action = 'refresh_listing';
  v := security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000001']::uuid[]);
  perform pg_temp.ok((select outcome from pipeline.scholarship_coverage_recoveries where action = 'refresh_listing') = 'failed'
                     and (select (escalation->>'due')::boolean from pipeline.scholarship_coverage_items where item_key like 'list:1:%family%')
                     and pg_temp.wi('10000000-0000-0000-0000-000000000001', 'traversal_incomplete') = 'parked/authority',
                     'a recovery that did not move its case fails and is escalated (work item parked, authority)');
  -- Box Hill unresolved past sch_cov.escalate_after_hours
  update pipeline.scholarship_coverage_items set first_seen = now() - interval '4 days' where provider_id = '10000000-0000-0000-0000-000000000003';
  v := security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000003']::uuid[]);
  perform pg_temp.ok(pg_temp.wi('10000000-0000-0000-0000-000000000003', 'source_not_discovered') = 'parked/authority', 'unresolved past the escalation time: escalated');
  -- TAFE SA's listing becomes a source by another route: the case resolves and its work item is done
  insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status)
  values ('10000000-0000-0000-0000-000000000002', 'https://www.tafesa.edu.au/international/before-starting/int-scholarships', 'tafesa.edu.au/international/before-starting/int-scholarships', 'manual', true, 'waiting');
  v := security.scholarship_coverage_classify_v1(array['10000000-0000-0000-0000-000000000002']::uuid[]);
  perform pg_temp.ok(pg_temp.st('cand:6') = 'rejected_correctly' and pg_temp.wi('10000000-0000-0000-0000-000000000002', 'traversal_incomplete') like 'done%', 'a resolved state closes its work item (done)');
end $$;

-- 9 report, verification function, remedies ------------------------------------------------------------------------------------------------------------
select pg_temp.ok((security.scholarship_coverage_report_v1()->'cases') ? 'ownership_conflict'
                  and jsonb_array_length(security.scholarship_coverage_report_v1('10000000-0000-0000-0000-000000000001')->'detail') > 0, 'the report reads the cases');
select pg_temp.ok(((security.scholarship_coverage_verify_v1((select id from pipeline.integration_issues where issue_ref = 'IQ-00215')))->>'passed')::boolean = false,
                  'IQ-00215 does not verify while Torrens has recoverable cases');
select pg_temp.ok((select authority from pipeline.ops_remedies where code = 'sch_coverage_classify') = 'auto'
                  and (select authority from pipeline.ops_remedies where code = 'sch_coverage_recover') = 'release'
                  and (select count(*) from pipeline.ops_root_causes where code in ('sch_provider_identity_joined_names', 'sch_register_pages_never_read', 'sch_listing_verdict_not_traversed',
                       'sch_listing_read_before_fanout', 'sch_policy_reported_as_zero', 'sch_subbrand_host_unowned', 'sch_read_again_not_due')) = 7,
                  'root causes registered; classification is auto, recovery needs a release switch');
select pg_temp.ok((security.scholarship_coverage_classify_remedy_v1((select id from pipeline.integration_issues where issue_ref = 'IQ-00215'))->>'ok')::boolean, 'the auto remedy classifies the issue''s provider');
-- nothing admitted, decided or published by any of it
select pg_temp.ok(not exists (select 1 from pipeline.scholarship_page_candidates where admit_status = 'admitted')
                  and (select count(*) from pipeline.scholarship_ai_reviews where status = 'pending') = 1
                  and (select count(*) from scholarship.scholarships where publication_status = 'published') = 6, 'nothing admitted, no Layer 4 item decided or added, nothing published');
