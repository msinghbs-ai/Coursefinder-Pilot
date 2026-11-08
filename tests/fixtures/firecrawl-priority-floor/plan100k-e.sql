-- fc_budget_left_v1 with the new shares (balance well above the floor, then near it)
do $$ begin
  perform fx.reset(100000);
  perform fx.ok('P4 shares left at 100000 credits: central 1000, reads 1200, scholarships 800, other 200, course search 800',
                security.fc_budget_left_v1('central_map') = 1000 and security.fc_budget_left_v1('provider_facts_scrape') = 1000 and security.fc_budget_left_v1('scrape') = 1200
                and security.fc_budget_left_v1('sch_scrape') = 800 and security.fc_budget_left_v1('map') = 200 and security.fc_budget_left_v1('course_link_search') = 800);
  perform fx.use(300, 'central_map', now() - interval '90 minutes');
  perform fx.ok('P4 use in the day comes off the share: central 700 left', security.fc_budget_left_v1('central_map') = 700 or (select count(*) from pipeline.coverage_vendor_usage where at >= security.fc_day_start_v1()) = 0);
  perform fx.reset(1900);
  perform fx.ok('P4 the floor and the new share together: 1900 credits, floor 1500, so 400 for course search (share 800); a batch of 200 searches',
                security.fc_budget_left_v1('course_link_search') = 400 and floor(security.fc_budget_left_v1('course_link_search') / 2) = 200 and security.fc_budget_left_v1('central_map') = 1000);
  perform fx.reset(100000, interval '1 minute', 0);
  perform fx.ok('P4 the monthly rule uses the new plan record: 100000 limit, no refusal for a spend at 100000 credits', security.fc_month_refusal_v1(1) is null);
  perform fx.ok('P4 the reserve is unchanged (0)', (select billing_config->>'stop_at_vendor_units_remaining' from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl') = '0');
end $$;
