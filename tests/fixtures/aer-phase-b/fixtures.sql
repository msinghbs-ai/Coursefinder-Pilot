-- AER Phase B fixtures: mandate §17 scenarios 14, 15, 16, 17, 18, 19, 20, 21, 23 and 24, on setup.sql's data (real RMIT runs and rows,
-- labelled synthetic providers). Each block raises 'FAIL: ...' or prints its PASS line. No synthetic row holds an admission value.
set timezone = 'UTC';  -- as live
create function fx.n(p_cause text) returns bigint language sql stable as $f$ select count(*) from pipeline.aer_gap_findings where root_cause = p_cause and state <> 'resolved' $f$;
create function fx.m(p_cc text) returns pipeline.aer_coverage_daily language sql stable as $f$ select * from pipeline.aer_coverage_daily where country = p_cc order by day desc limit 1 $f$;
create function fx.raises(p_sql text) returns text language plpgsql as $f$ begin execute p_sql; return null; exception when others then return sqlerrm; end $f$;

-- 0 applying the migration ran nothing and switched nothing on --------------------------------------------------------------------
do $t$
begin
  perform fx.ok(not exists (select 1 from pipeline.aer_gap_findings) and not exists (select 1 from pipeline.aer_coverage_daily), 'migration does not reconcile');
  perform fx.ok((select not active from cron.job where jobname = 'aer-reconcile'), 'job created paused');
  perform fx.ok((select schedule from cron.job where jobname = 'aer-reconcile') = '27 * * * *', 'hourly at :27');
  perform fx.ok(exists (select 1 from pipeline.automation_catalogue where jobname = 'aer-reconcile'), 'job catalogued (G1)');
  perform fx.ok((select value from pipeline.platform_toolset_settings where key = 'aer.weekly_email_enabled') = 'false'::jsonb, 'Monday e-mail off (D-A7)');
  perform fx.ok((select count(*) from pipeline.aer_gap_root_causes) = 23, '23 root causes');
  raise notice 'PASS migration: nothing run, job paused and catalogued, Monday e-mail off';
end $t$;

-- 14, 15, 16, 17: the first reconcile ---------------------------------------------------------------------------------------------
do $t$
declare r jsonb := security.aer_reconcile_v1(); a pipeline.aer_coverage_daily := fx.m('ALL');
begin
  perform fx.ok((r->>'opened')::int = 24 and (r->>'found')::int = 24, 'first run opens 24 findings: ' || r::text);
  -- 14: a source marked read whose extraction failed is a finding, and the source still counts as discovered
  perform fx.ok((select status from pipeline.entry_matrix_sources where id = fx.src('united-kingdom')) = 'read', 'UK source is read');
  perform fx.ok(exists (select 1 from pipeline.aer_gap_findings where source_id = fx.src('united-kingdom') and root_cause = 'reader_omission' and severity = 'P1'
                          and scope_kind = 'country' and scope_key = 'GB' and state = 'open'), '14: UK read but held: P1 reader_omission, scope GB');
  perform fx.ok(a.discovery_n = 4 and a.extraction_n = 2, format('14: discovery 4 (RMIT read), extraction 2 (RMIT not): %s / %s', a.discovery_n, a.extraction_n));
  -- 15: a column or section omitted: the guard's hold (Nigeria) and an unguarded run whose stored check is incomplete (Institute B)
  perform fx.ok(exists (select 1 from pipeline.aer_gap_findings where source_id = fx.src('nigeria') and root_cause = 'reader_omission' and scope_key = 'NG'), '15: Nigeria column left out (NG, not Niger)');
  perform fx.ok(exists (select 1 from pipeline.aer_gap_findings where source_id = fx.src('aub') and root_cause = 'reader_omission' and evidence->>'completeness' = 'incomplete'),
                '15: an omission found in a run the guard did not hold');
  perform fx.ok((select omitted_cells from pipeline.aer_source_manifests where source_id = fx.src('aub')) = 2
                and (select expected_cells from pipeline.aer_source_manifests where source_id = fx.src('aub')) = 9, '15: the manifest keeps 9 expected, 2 omitted');
  -- 16: a global qualification with no country heading is a qualification-scoped finding, with no country invented
  perform fx.ok((select count(*) from pipeline.aer_gap_findings where root_cause = 'non_country_heading' and scope_kind = 'qualification') = 2, '16: IB and GAC qualification scope');
  perform fx.ok(exists (select 1 from pipeline.aer_gap_findings where source_id = fx.src('international-baccalaureate') and scope_label = 'International Baccalaureate Diploma'
                          and scope_key = 'international baccalaureate diploma'), '16: IB labelled by its heading');
  perform fx.ok((select shape from pipeline.aer_source_manifests where source_id = fx.src('international-baccalaureate')) = 'qualification_page'
                and (select scope_country from pipeline.aer_source_manifests where source_id = fx.src('international-baccalaureate')) is null, '16: manifest shape qualification_page, no country');
  -- RMIT: 7 P1 source findings under 5 root causes, plus the held master's course read
  perform fx.ok((select count(*) from pipeline.aer_gap_findings where provider_id = fx.rmit() and source_id is not null) = 7
                and (select count(distinct root_cause) from pipeline.aer_gap_findings where provider_id = fx.rmit() and source_id is not null) = 5, 'RMIT: 7 findings, 5 root causes');
  perform fx.ok(exists (select 1 from pipeline.aer_gap_findings where provider_id = fx.rmit() and root_cause = 'course_read_held' and study_level = 'MC'), 'held master''s course read');
  -- 17: providers with no AER source: one root cause linked to every one of them; not-eligible providers are not counted
  perform fx.ok(fx.n('no_source') = 13 and (select count(distinct provider_id) from pipeline.aer_gap_findings where root_cause = 'no_source') = 13
                and (select count(*) from pipeline.aer_gap_root_causes where code = 'no_source') = 1, '17: thirteen providers, one root cause');
  perform fx.ok((select count(*) from pipeline.aer_gap_findings where root_cause = 'no_source' and provider_id = any (fx.eight())) = 8, '17: the eight universities, with no hand registration');
  perform fx.ok(not exists (select 1 from pipeline.aer_gap_findings where provider_id in (fx.prov('au_unpub'), fx.prov('nz_unknown'), fx.prov('au_arch'), fx.prov('ca1'))), '17: not-eligible providers have no finding');
  perform fx.ok(a.eligible = 18 and (fx.m('AU')).eligible = 17 and (fx.m('NZ')).eligible = 1 and not exists (select 1 from pipeline.aer_coverage_daily where country = 'CA'), 'denominator AU/NZ only: 18');
  perform fx.ok(a.open_p0 = 0 and a.open_p1 = 9 and a.open_p2 = 15 and a.new_findings = 24, format('open P0 0, P1 9, P2 15: %s %s %s', a.open_p0, a.open_p1, a.open_p2));
  perform fx.ok(a.admission_n = 3 and a.consumer_n = 2, format('admission 3 (RMIT, NZ polytechnic, Institute C), consumer 2 (RMIT, NZ polytechnic): %s %s', a.admission_n, a.consumer_n));
  perform fx.ok((select count(*) from pipeline.aer_gap_events where event = 'opened') = 24, 'one opened event each');
  perform fx.ok(not exists (select 1 from pipeline.platform_issues where check_key like 'aer:%'), 'no P0: no Platform health issue, no alert for P1/P2');
  raise notice 'PASS 14 15 16 17: read-but-held and omitted sections found; global qualification scoped without a country; one root cause for every provider without a source';
end $t$;

-- 18: an unchanged source produces no duplicate --------------------------------------------------------------------------------------
do $t$
declare b timestamptz := (select max(last_seen) from pipeline.aer_gap_findings); r jsonb;
begin
  r := security.aer_reconcile_v1();
  perform fx.ok((r->>'opened')::int = 0 and (r->>'resolved')::int = 0 and (r->>'reopened')::int = 0 and (r->>'observed')::int = 24, '18: second run observes 24, opens none: ' || r::text);
  perform fx.ok((select count(*) from pipeline.aer_gap_findings) = 24 and (select count(*) from pipeline.aer_gap_events) = 24, '18: no new finding, no new event');
  perform fx.ok((r->'population'->'joined') = '[]'::jsonb and (r->'population'->'left') = '[]'::jsonb and (r->>'queue_rows')::int = 18, '18: the queue is the same 18 providers');
  perform fx.ok((select min(last_seen) from pipeline.aer_gap_findings) >= b, '18: last seen moves on');
  perform fx.ok((select count(*) from pipeline.aer_source_manifests) = 11, '18: one manifest per source and hash, not one per run');
  raise notice 'PASS 18: an unchanged source adds no finding, event or manifest';
end $t$;

-- 19: the corrected source closes its gap after verification (synthetic later run, checked complete against its 31-cell manifest) ------
do $t$
declare r jsonb; f pipeline.aer_gap_findings;
begin
  insert into pipeline.entry_matrix_runs(id, provider_id, source_id, content_hash, state, result, created_at) values
    (fx.uid('run:uk2'), fx.rmit(), fx.src('united-kingdom'), md5('hash:united-kingdom:2'), 'done',
     '{"completeness": {"status": "complete", "basis": "manifest-v1", "expected": 31, "matched": 31}, "rows": []}', now());
  r := security.aer_reconcile_v1();
  select * into f from pipeline.aer_gap_findings where source_id = fx.src('united-kingdom');
  perform fx.ok(f.state = 'resolved' and f.closure_evidence->>'completeness' = 'complete' and (f.closure_evidence->>'matched')::int = 31
                and f.closure_evidence->>'run_id' = fx.uid('run:uk2')::text, '19: resolved with the run and 31 of 31 cells: ' || coalesce(f.closure_evidence::text, 'none'));
  perform fx.ok((select count(*) from pipeline.aer_gap_events where finding_id = f.id and event = 'resolved') = 1, '19: one resolved event');
  -- not found again but without evidence: kept open (unknown is never complete)
  update pipeline.entry_matrix_sources set status = 'found' where id = fx.src('vietnam');
  r := security.aer_reconcile_v1();
  perform fx.ok((select state from pipeline.aer_gap_findings where source_id = fx.src('vietnam')) = 'open', '19: no closure evidence, stays open');
  update pipeline.entry_matrix_sources set status = 'read' where id = fx.src('vietnam');
  raise notice 'PASS 19: a corrected source closes its gap only with verified closure evidence';
end $t$;

-- 20: a later regression reopens the same gap ---------------------------------------------------------------------------------------
do $t$
declare r jsonb; f pipeline.aer_gap_findings;
begin
  insert into pipeline.entry_matrix_runs(id, provider_id, source_id, content_hash, state, error, created_at) values
    (fx.uid('run:uk3'), fx.rmit(), fx.src('united-kingdom'), md5('hash:united-kingdom:3'), 'failed', 'held_incomplete: 2 of 31 published minimums not read', now() + interval '1 second');
  r := security.aer_reconcile_v1();
  select * into f from pipeline.aer_gap_findings where source_id = fx.src('united-kingdom');
  perform fx.ok(f.state = 'reopened' and f.reopen_count = 1 and f.resolved_at is null and (r->>'reopened')::int = 1, '20: same fingerprint reopened: ' || r::text);
  perform fx.ok((select count(*) from pipeline.aer_gap_findings where source_id = fx.src('united-kingdom')) = 1, '20: not a second finding');
  perform fx.ok((select array_agg(event order by id) from pipeline.aer_gap_events where finding_id = f.id) = array['opened', 'resolved', 'reopened'], '20: history opened, resolved, reopened');
  perform fx.ok((fx.m('ALL')).reopened_findings = 1 and (fx.m('ALL')).resolved_findings = 1, '20: the day counts one resolved and one reopened');
  raise notice 'PASS 20: a regression reopens the earlier gap with its history';
end $t$;

-- 21: proposed or held rows stay unavailable to consumers; an active row without admission is P0 -------------------------------------
do $t$
declare r jsonb; a pipeline.aer_coverage_daily;
begin
  -- synthetic proposed row (no minimum) at RMIT, and a course of Institute B waiting for review
  insert into catalogue.provider_entry_matrix(id, provider_id, country_id, country_code, qualification_name, quote, source_url, source_id, status)
    values (fx.uid('m:prop'), fx.rmit(), fx.country('CH'), 'CH', 'Synthetic qualification', 'Synthetic quote', 'https://synthetic.example/rmit', fx.src('nepal'), 'proposed');
  insert into catalogue.courses(id, provider_id, canonical_title) values (fx.uid('course:aub'), fx.prov('aub'), 'Synthetic course B');
  insert into pipeline.aer_course_outcomes(course_id, provider_id, country, provider_published, outcome, detail, built_at)
    values (fx.uid('course:aub'), fx.prov('aub'), 'AU', true, 'awaiting_review', 'synthetic', now());
  r := security.aer_reconcile_v1(); a := fx.m('ALL');
  perform fx.ok(fx.n('awaiting_layer4') = 2 and a.admission_n = 2, '21: RMIT has a row waiting: not verified-admission complete');
  perform fx.ok(a.consumer_n = 2, '21: consumer-resolvable still RMIT and the NZ polytechnic; the waiting course of Institute B is not counted');
  -- synthetic active row whose reading run has no approved Layer 4 item: a P0
  insert into catalogue.provider_entry_matrix(id, provider_id, country_id, country_code, qualification_name, quote, source_url, source_id, evidence_id, run_id, status)
    values (fx.uid('m:p0'), fx.prov('aub'), fx.country('NG'), 'NG', 'Synthetic qualification', 'Synthetic quote', 'https://synthetic.example/aub/entry', fx.src('aub'), fx.ev('aub'), fx.uid('run:aub'), 'active');
  r := security.aer_reconcile_v1();
  perform fx.ok(fx.n('consumer_unadmitted') = 1 and (select severity from pipeline.aer_gap_findings where root_cause = 'consumer_unadmitted') = 'P0', '21: active without admission is P0');
  perform fx.ok((fx.m('ALL')).open_p0 = 1, '21: open P0 counted');
  raise notice 'PASS 21: proposed and waiting rows are not counted as consumer coverage; an active row without admission is P0';
end $t$;

-- 23: alert deduplication and recovery through the existing alert job ------------------------------------------------------------------
do $t$
declare e jsonb;
begin
  perform fx.ok((select count(*) from pipeline.platform_issues where check_key = 'aer:p0' and resolved_at is null and severity = 'critical' and area = 'admission') = 1, '23: one P0 issue');
  perform security.aer_reconcile_v1();
  perform fx.ok((select count(*) from pipeline.platform_issues where check_key = 'aer:p0') = 1 and (select occurrences from pipeline.platform_issues where check_key = 'aer:p0') = 2, '23: seen again, same issue');
  e := security.platform_alerts_evaluate_v1(); e := security.platform_alerts_evaluate_v1();
  perform fx.ok((select count(*) from pipeline.platform_alerts where check_key = 'aer:p0' and kind = 'raised') = 1, '23: raised once');
  perform fx.ok((select status from pipeline.platform_alerts where check_key = 'aer:p0' and kind = 'raised') = 'pending', '23: queued for the existing delivery');
  -- the row is quarantined: the P0 finding closes, the issue resolves, one recovery notice
  update catalogue.provider_entry_matrix set status = 'unverified' where id = fx.uid('m:p0');
  perform security.aer_reconcile_v1();
  perform fx.ok((select state from pipeline.aer_gap_findings where root_cause = 'consumer_unadmitted') = 'resolved', '23: P0 finding resolved');
  perform fx.ok(not exists (select 1 from pipeline.platform_issues where check_key = 'aer:p0' and resolved_at is null), '23: issue resolved');
  e := security.platform_alerts_evaluate_v1(); e := security.platform_alerts_evaluate_v1();
  perform fx.ok((select count(*) from pipeline.platform_alerts where check_key = 'aer:p0' and kind = 'recovered') = 1, '23: one recovery notice');
  -- a fall in consumer-resolvable providers against yesterday's snapshot (synthetic yesterday row) opens one regression issue, then clears
  insert into pipeline.aer_coverage_daily(day, country, eligible, discovery_n, extraction_n, admission_n, consumer_n)
    values ((now() at time zone 'Australia/Sydney')::date - 1, 'ALL', 18, 4, 2, 2, 5);
  perform security.aer_reconcile_v1();
  perform fx.ok((select count(*) from pipeline.platform_issues where check_key = 'aer:regression' and resolved_at is null) = 1, '23: regression issue (5 -> 2)');
  update pipeline.aer_coverage_daily set consumer_n = 2 where day = (now() at time zone 'Australia/Sydney')::date - 1 and country = 'ALL';
  perform security.aer_reconcile_v1();
  perform fx.ok(not exists (select 1 from pipeline.platform_issues where check_key = 'aer:regression' and resolved_at is null), '23: regression cleared');
  -- P1/P2 never alert; the Monday e-mail is off
  perform fx.ok(not exists (select 1 from pipeline.platform_alerts where check_key not in ('aer:p0', 'aer:regression')), '23: no alert per country or qualification; no weekly e-mail while off');
  perform fx.ok((select status from pipeline.platform_health_checks where key = 'aer') = 'ok', '23: health row ok once cleared');
  raise notice 'PASS 23: one issue per check, raised once, one recovery notice; no flood; Monday e-mail off';
end $t$;

-- 24: the Admin figures reconcile to the database; the role gate -------------------------------------------------------------------
do $t$
declare c jsonb; p jsonb; m jsonb;
begin
  insert into auth.session values (gen_random_uuid(), 2);
  perform fx.ok(fx.raises($q$select public.admin_aer('coverage', '{}')$q$) like 'curator role required%', '24: a counsellor (rank 2) is refused');
  update auth.session set rank = 3;
  c := public.admin_aer('coverage', '{}');
  m := (select x from jsonb_array_elements(c->'measures') x where x->>'country' = 'ALL');
  perform fx.ok((m->>'eligible')::int = (select count(*) from security.aer_eligible_v1()), '24: eligible = recount');
  perform fx.ok((m->>'discovery_n')::int = (select count(*) from security.aer_eligible_v1() e where exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id and s.status = 'read')), '24: discovery = recount');
  perform fx.ok((m->>'consumer_n')::int = (select count(distinct o.provider_id) from pipeline.aer_course_outcomes o join security.aer_eligible_v1() e on e.provider_id = o.provider_id
                                           where o.outcome in ('admitted_course', 'admitted_provider')), '24: consumer = recount');
  perform fx.ok((c->'open'->>'P1')::int = (select count(*) from pipeline.aer_gap_findings where state <> 'resolved' and severity = 'P1')
                and (c->'open'->>'P2')::int = (select count(*) from pipeline.aer_gap_findings where state <> 'resolved' and severity = 'P2')
                and (c->'open'->>'P0')::int = 0, '24: open counts = findings');
  perform fx.ok((select (x->>'providers')::int from jsonb_array_elements(c->'root_causes') x where x->>'code' = 'no_source') = 13, '24: root cause linked to 13 providers');
  perform fx.ok((c->'providers'->>'total')::int = 18 and (public.admin_aer('coverage', '{"country": "NZ"}')->'providers'->>'total')::int = 1, '24: drill-down 18, NZ 1');
  perform fx.ok((c->'providers'->'items'->0->>'name') = 'RMIT University' and (c->'providers'->'items'->0->>'disposition') = 'source_held', '24: the queue opens with the held university');
  perform fx.ok((public.admin_aer('coverage', '{"disposition": "not_discovered"}')->'providers'->>'total')::int = (select count(*) from pipeline.aer_provider_coverage where eligible and disposition = 'not_discovered'), '24: disposition filter = table');
  perform fx.ok((c->'dispositions'->>'not_discovered')::int = (select count(*) from pipeline.aer_provider_coverage where eligible and disposition = 'not_discovered'), '24: disposition counts = table');
  perform fx.ok((c->'changes_7d'->>'opened')::int = (select count(*) from pipeline.aer_gap_events where event = 'opened'), '24: opened = events');
  p := public.admin_aer('coverage_provider', jsonb_build_object('provider_id', fx.rmit()));
  perform fx.ok(jsonb_array_length(p->'sources') = 8 and (p->'active'->>'rows')::int = 11, '24: RMIT 8 sources, 11 active rows');
  perform fx.ok((select count(*) from jsonb_array_elements(p->'findings') x where x->>'state' = 'reopened') = 1, '24: drill-down shows the reopened UK gap');
  perform fx.ok((c->'job'->>'active')::boolean = false, '24: shows the job paused');
  -- the weekly scorecard keeps the AER section
  perform security.ops_scorecard_record_v1();
  perform fx.ok((select scorecard ? 'aer' from pipeline.ops_scorecards order by week_start desc limit 1), '24: weekly scorecard has the AER section');
  perform fx.ok((select (scorecard->'aer'->>'eligible')::int from pipeline.ops_scorecards order by week_start desc limit 1) = 18, '24: weekly eligible = 18');
  raise notice 'PASS 24: Admin figures equal the database; counsellors refused; weekly scorecard section';
end $t$;

-- Platform Admin 15:43: the catalogue-first gap queue -------------------------------------------------------------------------------
do $t$
declare q pipeline.aer_provider_coverage; r jsonb;
begin
  -- the eight universities: not discovered, first tier, no hand registration
  perform fx.ok((select count(*) from pipeline.aer_provider_coverage where provider_id = any (fx.eight()) and disposition = 'not_discovered' and discovery_state = 'not_discovered'
                   and priority_tier = 1) = 8, 'queue: the eight universities are not_discovered, tier 1');
  perform fx.ok(not exists (select 1 from pipeline.entry_matrix_sources where provider_id = any (fx.eight())), 'queue: found without a source row');
  -- RMIT and UWA: source present, with distinct extraction and admission states; never "no source"
  select * into q from pipeline.aer_provider_coverage where provider_id = fx.rmit();
  perform fx.ok(q.disposition = 'source_held' and q.discovery_state = 'source_read' and q.extraction_state = 'held' and q.admission_state = 'active_and_awaiting'  -- scenario 21 left one RMIT row waiting
                and q.runs_held = 7 and q.matrix_active = 11, 'queue: RMIT source_held, extraction held, admission active and awaiting: ' || row_to_json(q)::text);
  perform fx.ok((select count(*) from jsonb_array_elements(q.held_scopes) x where x->>'kind' = 'qualification') = 2, 'queue: IB and GAC held as global qualification scopes');
  perform fx.ok(not exists (select 1 from jsonb_array_elements(q.held_scopes) x where x->>'kind' = 'country' and x->>'scope' ilike '%baccalaureate%'), 'queue: IB is not a country clone');
  perform fx.ok(jsonb_array_length(q.evidence->'sources') = 8 and (q.evidence->'sources'->0) ? 'run_id', 'queue: exact source and run ids');
  select * into q from pipeline.aer_provider_coverage where provider_id = fx.uwa();
  perform fx.ok(q.disposition = 'awaiting_layer4' and q.discovery_state = 'source_read' and q.extraction_state = 'complete' and q.admission_state = 'awaiting'
                and q.matrix_other = 3 and (q.layer4->>'matrix_pending')::int = 1, 'queue: UWA awaiting_layer4 with its review item: ' || row_to_json(q)::text);
  perform fx.ok((select evidence->'sources'->0->>'review_item_id' from pipeline.aer_provider_coverage where provider_id = fx.uwa()) = fx.uid('l4:uwa')::text, 'queue: UWA exact review item id');
  -- related identities kept apart
  perform fx.ok((select disposition from pipeline.aer_provider_coverage where provider_id = 'c5c5d225-3d4c-4e41-8275-78eddd261073') = 'not_discovered'
                and (select disposition from pipeline.aer_provider_coverage where provider_id = 'd090e283-9894-49ce-baf3-e9d47f80e468') = 'reader_failed', 'queue: Deakin University is not Deakin College');
  perform fx.ok((select disposition from pipeline.aer_provider_coverage where provider_id = '30b81368-9003-4775-81af-60439fc3b109') = 'not_discovered', 'queue: RMIT UP is not RMIT');
  -- no matrix but course-level requirements: course_only, not "no entry requirements"
  perform fx.ok((select disposition from pipeline.aer_provider_coverage where provider_id = fx.prov('auc')) = 'course_only'
                and (select disposition from pipeline.aer_provider_coverage where provider_id = fx.prov('nz1')) = 'course_only', 'queue: course_only');
  -- not applicable only with evidence: the type list is empty, so nothing is reported not applicable
  perform fx.ok(not exists (select 1 from pipeline.aer_provider_coverage where disposition = 'not_applicable_evidenced'), 'queue: no not-applicable without evidence');
  -- priority: tier 1 (universities and tertiary) before every other provider; the held university first
  perform fx.ok((select max(priority_rank) from pipeline.aer_provider_coverage where eligible and priority_tier = 1)
                < (select min(priority_rank) from pipeline.aer_provider_coverage where eligible and priority_tier = 2), 'queue: tier 1 first');
  perform fx.ok((select priority_rank from pipeline.aer_provider_coverage where provider_id = fx.rmit()) = 1, 'queue: the held university first');
  -- dispositions are report words: no admission status was written
  perform fx.ok(not exists (select 1 from catalogue.provider_entry_matrix where status not in ('active', 'proposed', 'unverified')), 'queue: admission vocabulary unchanged');
  -- population against the baseline, exactly
  r := (select result->'population' from pipeline.aer_reconcile_runs order by id desc limit 1);
  perform fx.ok((r#>>'{by_country,AU,eligible}')::int = 17 and (r#>>'{by_country,AU,baseline}')::int = 1279 and (r#>>'{by_country,AU,delta}')::int = -1262
                and (r#>>'{by_country,NZ,delta}')::int = -196, 'queue: delta against the 1,279/197 baseline: ' || r::text);
  raise notice 'PASS queue: eight universities not_discovered; RMIT and UWA source-present with distinct states; course_only; related identities apart; global IB/GAC; priority';
end $t$;

do $t$
declare r jsonb; v jsonb;
begin
  -- a provider leaves (unpublished) and a new one joins: the run names both exactly
  update catalogue.providers set publication_status = 'unpublished' where id = fx.prov('au3');
  insert into catalogue.providers(id, display_name, country_id, enrols_international, provider_type_id) values (fx.prov('nz2'), 'Synthetic NZ Polytechnic 2', fx.country('NZ'), true, fx.ptype('tafe_polytechnic'));
  v := security.aer_coverage_verify_v1();
  perform fx.ok(not (v->>'ok')::boolean and v->'missing_from_queue' = jsonb_build_array(fx.prov('nz2')) and v->'not_eligible_now' = jsonb_build_array(fx.prov('au3')),
                'verify: the stored queue differs from a fresh anti-join, exactly: ' || v::text);
  r := security.aer_reconcile_v1();
  perform fx.ok(r->'population'->'left' = jsonb_build_array(fx.prov('au3')) and r->'population'->'joined' = jsonb_build_array(fx.prov('nz2')), 'population: left and joined exactly: ' || (r->'population')::text);
  perform fx.ok((select not eligible from pipeline.aer_provider_coverage where provider_id = fx.prov('au3')), 'population: the row is kept, marked not eligible');
  v := security.aer_coverage_verify_v1();
  perform fx.ok((v->>'ok')::boolean and (v#>>'{fresh,AU}')::int = (v#>>'{stored,AU}')::int and (v#>>'{fresh,no_source}')::int = (v#>>'{stored,not_discovered_state}')::int,
                'verify: after the run the queue equals the fresh anti-join: ' || v::text);
  raise notice 'PASS population: each run reports the exact providers that joined or left; the verification query matches a fresh anti-join';
end $t$;

-- Layer 4 mandate 16:33 §9: review readiness classes on the same root causes; D-A7 weekly copy ----------------------------------------
do $t$
declare r jsonb; n int; md text;
begin
  -- every pending AER item has a readiness row (UWA's matrix item; Institute B's waiting course has no Layer 4 item in these fixtures)
  perform fx.ok((select readiness from pipeline.aer_review_readiness where review_item_id = fx.uid('l4:uwa')) = 'awaiting_human_review'
                and (select basis from pipeline.aer_review_readiness where review_item_id = fx.uid('l4:uwa')) = 'reconcile_default', 'readiness: pending item awaits human review by default');
  perform fx.ok(not exists (select 1 from pipeline.aer_review_readiness where review_item_id in (fx.uid('l4:nepal'), fx.uid('l4:auc'))), 'readiness: settled items are not queued');
  -- a loaded classification (synthetic: classes only, no admission value): unknown class, unknown cause and settled items are refused
  r := security.aer_review_readiness_load_v1(jsonb_build_array(
         jsonb_build_object('review_item_id', fx.uid('l4:uwa'), 'readiness', 'reader_correction_required', 'root_cause', 'row_cap', 'reason', 'synthetic: eight rows dropped'),
         jsonb_build_object('review_item_id', fx.uid('l4:nepal'), 'readiness', 'review_ready'),
         jsonb_build_object('review_item_id', fx.uid('l4:uwa'), 'readiness', 'approved'),
         jsonb_build_object('review_item_id', fx.uid('l4:uwa'), 'readiness', 'evidence_required', 'root_cause', 'no_such_cause')), 'synthetic fixture classification');
  perform fx.ok((r->>'loaded')::int = 1 and jsonb_array_length(r->'skipped') = 3, 'readiness: one loaded, three refused: ' || r::text);
  perform fx.ok((select status from pipeline.layer4_review_items where id = fx.uid('l4:uwa')) = 'pending', 'readiness: no Layer 4 item changed');
  -- the defect becomes one finding for the provider, linked to its items, counted against extraction
  perform security.aer_reconcile_v1();
  perform fx.ok(exists (select 1 from pipeline.aer_gap_findings where provider_id = fx.uwa() and root_cause = 'row_cap' and scope_kind = 'review_items'
                          and state <> 'resolved' and (evidence->>'items')::int = 1), 'readiness: row_cap finding for UWA');
  perform fx.ok((select disposition from pipeline.aer_provider_coverage where provider_id = fx.uwa()) = 'awaiting_layer4', 'readiness: the queue disposition is unchanged');
  -- the item is settled in Layer 4: the readiness row is closed (kept), the finding resolves with evidence, nothing reopens
  update pipeline.layer4_review_items set status = 'approved' where id = fx.uid('l4:uwa');
  perform security.aer_reconcile_v1();
  perform fx.ok((select settled_at is not null and item_status = 'approved' from pipeline.aer_review_readiness where review_item_id = fx.uid('l4:uwa')), 'readiness: settled, kept');
  perform fx.ok((select state from pipeline.aer_gap_findings where provider_id = fx.uwa() and root_cause = 'row_cap') = 'resolved', 'readiness: finding resolved once no pending item has the defect');
  r := security.aer_review_readiness_load_v1(jsonb_build_array(jsonb_build_object('review_item_id', fx.uid('l4:uwa'), 'readiness', 'review_ready')), 'synthetic');
  perform fx.ok((r->>'loaded')::int = 0, 'readiness: a settled item is not reclassified');
  update pipeline.layer4_review_items set status = 'pending' where id = fx.uid('l4:uwa');  -- restore
  -- D-A7: the Markdown copy and the dashboard carry the same weekly section
  md := security.aer_weekly_markdown_v1(date_trunc('week', now() at time zone 'Australia/Sydney')::date);
  perform fx.ok(md like '# AER weekly report, week of %' and md like '%- Eligible AU/NZ providers: %' and md like '%## Root causes%' and md like '%## Layer 4 review readiness%', 'weekly: Markdown copy');
  perform fx.ok(has_function_privilege('supabase_read_only_user', 'security.aer_weekly_markdown_v1(date)', 'execute'), 'weekly: the workflow reads it as the read-only role');
  perform fx.ok(public.admin_aer('coverage', '{}') ? 'weekly' and public.admin_aer('coverage', '{}') ? 'readiness', 'weekly: on the dashboard');
  raise notice 'PASS readiness and weekly: classes loaded only for pending AER items; one finding per defect; settled never reopened; Markdown copy and dashboard';
end $t$;

-- the reconcile reads only: no catalogue row, run, source or Layer 4 item was changed by it --------------------------------------------
do $t$
declare h1 text; h2 text;
begin
  h1 := md5((select string_agg(t::text, ',' order by t::text) from catalogue.provider_entry_matrix t) || (select string_agg(t::text, ',' order by t::text) from pipeline.entry_matrix_runs t)
            || (select string_agg(t::text, ',' order by t::text) from pipeline.entry_matrix_sources t) || (select string_agg(t::text, ',' order by t::text) from pipeline.layer4_review_items t));
  perform security.aer_reconcile_v1();
  h2 := md5((select string_agg(t::text, ',' order by t::text) from catalogue.provider_entry_matrix t) || (select string_agg(t::text, ',' order by t::text) from pipeline.entry_matrix_runs t)
            || (select string_agg(t::text, ',' order by t::text) from pipeline.entry_matrix_sources t) || (select string_agg(t::text, ',' order by t::text) from pipeline.layer4_review_items t));
  perform fx.ok(h1 = h2, 'reconcile changes no AER data');
  raise notice 'PASS read-only: the reconcile changes no catalogue row, source, run or Layer 4 item';
end $t$;
