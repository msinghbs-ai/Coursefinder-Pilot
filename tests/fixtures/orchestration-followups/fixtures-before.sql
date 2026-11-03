-- The three defects reproduced on the live definitions (v2.15.424), before the migration.
select fx.reset2();

-- IQ-00066: an ineligible provider mapped a month ago (nothing due for 3 hours) is proposed a scholarships step
select fx.provider(false, interval '3 hours') \gset b_
select fx.ok('scholarships' = any (fx.steps_of(:'b_provider')), 'before IQ-00066: the plan builder proposes Find and read scholarships for a provider the scholarship reader refuses');
-- its scan task (mapping the site, total 0) stalls 31 minutes: the watcher ends it done "0 of 0", the plan step and the plan are done
select fx.scan(:'b_provider', interval '31 minutes') \gset bs_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'bs_scan')).state = 'done' and (fx.job(:'bs_scan')).result->>'note' like '%0 of 0 done, nothing more for 30 minutes%', 'before IQ-00066: the scan ends done "0 of 0 done, nothing more for 30 minutes"');
select security.enrich_plan_tick_v1(null); select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'bs_scan')->>'status' = 'done' and fx.run_state(:'bs_scan') = 'done', 'before IQ-00066: the step and the plan are done although no data moved');

-- IQ-00063: a website with a user part goes round website -> course pages -> stopped no_website -> website ...
select fx.onb('https://info@newgen.edu.au', 'stopped', 'no_website') \gset bo_
select security.provider_onboarding_tick_v1();
select fx.ok((fx.onb_row(:'bo_onb')).status = 'website' and fx.stepped_n(:'bo_onb') = 1, 'before IQ-00063: a stopped no_website row with an email-address website is sent back to the website stage and stepped');

-- IQ-00053 residual: the description check's answers on the live definition, kept to compare after the migration
select count(*) from fx.desc_cases();  -- seeds the provider's descriptions first (a stable check reads the statement's snapshot)
insert into fx.desc_answers select k, security.course_description_check_v1(course, result) from fx.desc_cases();
select fx.ok((select count(*) from fx.desc_answers) = 6 and (select count(*) from fx.desc_answers where answer->>'rule' = 'duplicate_other_course') = 4,
             'before IQ-00053: 6 description answers recorded (4 duplicates: of another course, one with an inserted word, one of 15 words with 14 shared, one of a Layer 4 proposal)');
