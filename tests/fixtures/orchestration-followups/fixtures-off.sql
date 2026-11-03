-- With plans.step_needs_work_on and onboarding.website_check_on set 0, the edited definitions behave as before.
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key in ('plans.step_needs_work_on', 'onboarding.website_check_on');
select fx.reset2();
select fx.provider(false, interval '3 hours') \gset f_
select fx.ok('scholarships' = any (fx.steps_of(:'f_provider')) and jsonb_array_length(security.enrich_plan_v1(:'f_provider')->'not_proposed') = 0, 'off: the scholarships step is proposed as before, nothing listed as not proposed');
select fx.scan(:'f_provider', interval '31 minutes') \gset fs_
select security.admin_jobs_tick_v1(10);
select fx.ok((fx.job(:'fs_scan')).state = 'done' and (fx.job(:'fs_scan')).result->>'note' like '%0 of 0 done, nothing more for 30 minutes%', 'off: the scan ends done "0 of 0" as before');
select security.enrich_plan_tick_v1(null); select security.enrich_plan_tick_v1(null);
select fx.ok(fx.step(:'fs_scan')->>'status' = 'done' and fx.run_state(:'fs_scan') = 'done', 'off: the step and the plan are done as before');
select fx.ok((fx.run(((fx.job(:'fs_scan')).args->>'plan_run')::uuid)).actual->>'outcome' = 'moved', 'off: the outcome is recorded (a done step counts as moved)');
select fx.onb('https://info@newgen.edu.au', 'stopped', 'no_website') \gset fo_
select security.provider_onboarding_tick_v1();
select fx.ok((fx.onb_row(:'fo_onb')).status = 'website' and fx.stepped_n(:'fo_onb') = 1, 'off: a no_website row with an email-address website goes back to the website stage as before');
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key in ('plans.step_needs_work_on', 'onboarding.website_check_on');
