-- Every case with plans.step_needs_work_on and onboarding.website_check_on on (as shipped).
-- P. the plan builder proposes a scholarships step only when the scan has eligible work now (IQ-00066)
select fx.reset2();
select fx.provider(false, interval '3 hours') \gset p1_
select fx.ok(not ('scholarships' = any (fx.steps_of(:'p1_provider'))), 'P1 the 12:41 case: a provider the scholarship reader refuses (below scholarship_min_courses) gets no scholarships step');
select fx.ok(security.enrich_plan_v1(:'p1_provider')->'not_proposed'->0->>'code' = 'not_eligible'
             and security.enrich_plan_v1(:'p1_provider')->'not_proposed'->0->>'reason' like 'not eligible for scholarship reading%', 'P1 it is listed as not proposed, with the reason');
select fx.provider(true, interval '3 hours') \gset p2_
select fx.ok(not ('scholarships' = any (fx.steps_of(:'p2_provider'))) and security.enrich_plan_v1(:'p2_provider')->'not_proposed'->0->>'code' = 'nothing_due'
             and security.enrich_plan_v1(:'p2_provider')->'not_proposed'->0->>'reason' like 'site mapped for scholarships % (0 scholarship page(s) kept); next mapping due %; no candidate or listing page is waiting',
             'P2 an eligible provider whose site was mapped and whose next mapping is not due, with nothing waiting: not proposed (nothing due)');
select fx.provider(true, null) \gset p3_
select fx.ok('scholarships' = any (fx.steps_of(:'p3_provider')), 'P3 never mapped: proposed');
select fx.provider(true, interval '-1 minute') \gset p4_
select fx.ok('scholarships' = any (fx.steps_of(:'p4_provider')), 'P4 its next mapping is due: proposed');
insert into pipeline.scholarship_page_candidates(provider_id, source, attempts) values (:'p2_provider', 'auto', 0);
select fx.ok('scholarships' = any (fx.steps_of(:'p2_provider')), 'P5 not due, but a candidate page waits to be screened: proposed');
insert into pipeline.scholarship_listing_pages(provider_id, url, active, source) values (:'p1_provider', 'https://www.example-college.edu.au/scholarships', true, 'auto');
select fx.ok(not ('scholarships' = any (fx.steps_of(:'p1_provider'))), 'P6 a refused provider stays not proposed whatever waits (the reader would refuse it)');
insert into pipeline.coverage_vendor_usage(units, purpose, provider_id) values (150, 'sch_scrape', :'p4_provider');
select fx.ok(security.enrich_plan_v1(:'p4_provider')->'not_proposed'->0->>'code' = 'credit_cap', 'P7 its scholarship credit cap is used: not proposed (credit_cap)');
insert into pipeline.provider_scholarship_search values (:'p3_provider', false);
select fx.ok(security.enrich_plan_v1(:'p3_provider')->'not_proposed'->0->>'code' = 'search_off', 'P8 scholarship search switched off: not proposed (search_off)');
select fx.ok(security.plan_step_work_v1(:'p1_provider', 'fields')->>'work' = 'true', 'P9 the other steps keep their own rules');

-- T. the plan tick: a pending step with no eligible work is not needed; no task starts; the plan's outcome (IQ-00066)
select fx.plan_pending(:'p1_provider') run \gset t1_
select security.enrich_plan_tick_v1(:'t1_run');
select fx.ok((fx.run(:'t1_run')).steps->0->>'status' = 'not_needed' and (fx.run(:'t1_run')).steps->0->>'note' like 'Not needed: not eligible for scholarship reading%'
             and (fx.run(:'t1_run')).steps->0 ? 'finished_at' and (fx.run(:'t1_run')).steps->0->'not_needed'->>'code' = 'not_eligible', 'T1 a pending step with no eligible work ends not_needed with the reason; no task is started');
select fx.ok((fx.run(:'t1_run')).steps->0->'ref' is null and not exists (select 1 from pipeline.admin_jobs j where j.scope = :'p1_provider'), 'T1 no task');
select security.enrich_plan_tick_v1(:'t1_run');
select fx.ok((fx.run(:'t1_run')).state = 'done' and (fx.run(:'t1_run')).actual->>'outcome' = 'not_needed', 'T2 the plan finishes with outcome not_needed (no data moved), not counted as moved');
select fx.plan_pending(:'p2_provider') run \gset t3_
select security.enrich_plan_tick_v1(:'t3_run');
select fx.ok((fx.run(:'t3_run')).steps->0->>'status' = 'running', 'T3 a step with eligible work starts as before');
select fx.ok(security.plan_run_outcome_v1('[{"status": "done"}, {"status": "not_needed"}]') = 'moved' and security.plan_run_outcome_v1('[{"status": "failed"}]') = 'no_movement'
             and security.plan_run_outcome_v1('[{"status": "not_needed"}, {"status": "person"}]') = 'not_needed' and security.plan_run_outcome_v1('[{"status": "not_needed"}, {"status": "skipped"}]') = 'no_movement',
             'T4 outcomes: a done step moved data; not needed (person steps aside); anything else moved nothing');

-- W. the task watcher and runner (IQ-00066): the 12:41 task ends not needed at once, never done
select fx.reset2();
select fx.provider(false, interval '3 hours') \gset w1_
select fx.scan(:'w1_provider', interval '2 minutes') \gset w1s_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'w1s_scan')).state = 'cancelled' and (fx.job(:'w1s_scan')).result->>'end_state' = 'not_needed', 'W1 the 12:41 case: the scan with no eligible work ends not needed at once (closed cancelled), not done after 30 minutes');
select fx.ok((fx.job(:'w1s_scan')).error like 'Not needed: not eligible for scholarship reading%No scholarship page, site mapping or candidate page was due for this task'
             and (fx.job(:'w1s_scan')).result->>'phase_detail' = 'not needed' and (fx.job(:'w1s_scan')).finished_at is not null, 'W1 its error and note give the reason');
select security.enrich_plan_tick_v1(null); select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'w1s_scan')->>'status' = 'not_needed' and fx.step(:'w1s_scan')->>'note' like 'Not needed: not eligible%', 'W2 the plan step is not_needed with the task''s reason');
select fx.ok(fx.run_state(:'w1s_scan') = 'done' and (fx.run(((fx.job(:'w1s_scan')).args->>'plan_run')::uuid)).actual->>'outcome' = 'not_needed', 'W2 the plan ends with outcome not_needed');
-- an eligible mapping waiting its turn is held, never done
select fx.provider(true, interval '-5 minutes') \gset w3_
select fx.scan(:'w3_provider', interval '40 minutes') \gset w3s_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'w3s_scan')).state = 'running' and (fx.job(:'w3s_scan')).result->'held'->>'code' = 'waiting_turn' and (fx.job(:'w3s_scan')).result->>'unprocessed' = '1',
             'W3 an eligible site mapping that waits 40 minutes is held (still running), not done "0 of 0"');
select fx.ok((fx.job(:'w3s_scan')).result->>'note' like 'Held: 1 item(s) waiting their turn (mapping the site). 1 of 1 item(s) still to process;%', 'W3 the note says what waits');
select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'w3s_scan')->>'status' = 'running' and fx.step(:'w3s_scan')->'held'->>'code' = 'waiting_turn', 'W3 the plan step stays running and shows the hold');
-- the mapping happens: the row is mapped (next mapping in 30 days), nothing was kept: the scan finishes done as before
update pipeline.scholarship_discovery_providers set status = 'mapped', attempts = 1, next_discover_at = now() + interval '30 days', discovered_at = now() where provider_id = :'w3_provider';
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'w3s_scan')).state = 'done' and (fx.job(:'w3s_scan')).result->>'end_state' is null, 'W4 once its site is mapped the scan finishes done (it did its work)');
-- a scan of an eligible provider whose mapping is not due but a candidate page waits: screening, held while it waits
select fx.provider(true, interval '2 hours') \gset w5_
insert into pipeline.scholarship_page_candidates(provider_id, source, attempts, next_read_at) values (:'w5_provider', 'auto', 0, now() - interval '1 minute');
select fx.scan(:'w5_provider', interval '40 minutes') \gset w5s_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'w5s_scan')).state = 'running' and (fx.job(:'w5s_scan')).result->>'phase_detail' = 'screening candidate pages' and (fx.job(:'w5s_scan')).result->'held' is not null,
             'W5 mapping not due, a candidate waits: screening, held (not mapping, not not-needed)');
-- a scan with a scholarship page in scope is not judged by the eligibility check (total > 0): it reads as before
select fx.provider(false, interval '3 hours') \gset w6_
insert into scholarship.scholarships(id, provider_id) values ('33333333-3333-3333-3333-333333333333', :'w6_provider');
insert into pipeline.scholarship_pages(scholarship_id, requested_at, read_at) values ('33333333-3333-3333-3333-333333333333', null, now());
select fx.scan(:'w6_provider', interval '2 minutes') \gset w6s_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'w6s_scan')).state = 'done' and (fx.job(:'w6s_scan')).result->>'note' like '%1 known scholarship page(s) read again%', 'W6 a scan with its page read finishes done as before');

-- Y. Pipeline yield shows the plan outcomes
select fx.ok((security.plan_outcomes_v1())->>'not_needed' = '1' and (security.plan_outcomes_v1())->>'moved' = '0' and (security.plan_outcomes_v1())->'steps_not_needed'->>'scholarships' = '1'
             and (security.plan_outcomes_v1())->>'tasks_not_needed' = '1' and (security.plan_outcomes_v1())->'auto'->>'not_needed' = '1', 'Y1 plan_outcomes_v1: the not-needed plan, step and task are counted apart from plans that moved data');
select fx.ok(public.admin_pipeline_yield('{}') ? 'plan_outcomes' and public.admin_pipeline_yield('{}') ? 'lane_status' and public.admin_pipeline_yield('{}') ? 'field_backlog', 'Y2 admin_pipeline_yield returns plan_outcomes beside lane_status and field_backlog');
update pipeline.enrich_plan_runs set finished_at = now() - interval '2 days';
select fx.ok((security.plan_outcomes_v1())->>'plans_done' = '0', 'Y3 plans.outcome_window_hours bounds the report');

-- D. the description duplicate check gives the same answers as before (IQ-00053 residual)
select count(*) from fx.desc_cases();
select fx.ok((select count(*) from fx.desc_answers a join fx.desc_cases() c on c.k = a.k where security.course_description_check_v1(c.course, c.result) = a.answer) = 6,
             'D1 the six answers (four duplicates, one new text, one too short) are the same as on the live definition');
update pipeline.platform_toolset_settings set value = '1' where key = 'enrich.course_description_duplicate_window';
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value) values ('pipeline', 'enrich.course_description_duplicate_window', 'number', '1') on conflict do nothing;
select fx.ok((select count(*) from fx.desc_cases() c where security.course_description_check_v1(c.course, c.result)->>'rule' = 'duplicate_other_course') < 4, 'D2 the window setting still bounds the scan');
update pipeline.platform_toolset_settings set value = '500' where key = 'enrich.course_description_duplicate_window';

-- O. onboarding refuses a website that is not a site address (IQ-00063)
select fx.reset2();
select fx.onb('https://info@newgen.edu.au', 'course_pages') \gset o1_
select fx.onb('https://www.example-college.edu.au', 'course_pages') \gset o2_
select security.provider_onboarding_tick_v1();
select fx.ok((fx.onb_row(:'o1_onb')).status = 'stopped' and (fx.onb_row(:'o1_onb')).stop_reason = 'needs_source_discovery' and fx.stepped_n(:'o1_onb') = 0,
             'O1 the d5dfc2ea case: course_pages with an email-address website stops needs_source_discovery and is not stepped');
select fx.ok((fx.onb_row(:'o1_onb')).note like 'The recorded website (https://info@newgen.edu.au) cannot be used: it has a user part ("info@"), as an email address does. Its website has to be found again%', 'O1 the note says why and what to do');
select fx.ok(fx.stepped_n(:'o2_onb') = 1 and (fx.onb_row(:'o2_onb')).status = 'course_pages', 'O2 a row with a site address is stepped as before');
select security.provider_onboarding_tick_v1();
select fx.ok((fx.onb_row(:'o1_onb')).status = 'stopped' and fx.stepped_n(:'o1_onb') = 0, 'O3 it stays stopped: no loop, updated_at no longer moves each run');
select fx.onb('https://info@newgen.edu.au', 'stopped', 'no_website') \gset o4_
select security.provider_onboarding_tick_v1();
select fx.ok((fx.onb_row(:'o4_onb')).stop_reason = 'needs_source_discovery' and fx.stepped_n(:'o4_onb') = 0, 'O4 a stopped no_website row with a refused website is not sent back; it waits as needs_source_discovery');
update catalogue.providers set website = 'https://newgen.edu.au' where id = (fx.onb_row(:'o1_onb')).provider_id;
select security.provider_onboarding_tick_v1();
select fx.ok((fx.onb_row(:'o1_onb')).status = 'website' and fx.stepped_n(:'o1_onb') = 1, 'O5 once the website is corrected it carries on by itself');
select fx.ok(security.website_refusal_v1('https://info@newgen.edu.au') like 'it has a user part%' and security.website_refusal_v1('newgen.edu.au') = 'it is not an http or https address'
             and security.website_refusal_v1('https://new gen.edu.au') = 'it contains spaces' and security.website_refusal_v1('http://localhost') = 'its host is not a domain name'
             and security.website_refusal_v1('mailto:info@newgen.edu.au') is not null and security.website_refusal_v1('') is null and security.website_refusal_v1(null) is null
             and security.website_refusal_v1('https://www.example.edu.au:8443/courses?x=1#a') is null and security.website_refusal_v1('HTTPS://XN--80AK6AA92E.COM/') is null
             and security.website_refusal_v1('https://sub.domain.ac.nz') is null, 'O6 website_refusal_v1: user part, no scheme, spaces, no domain refused; site addresses (port, path, IDN, case) accepted; empty is the no_website path');
