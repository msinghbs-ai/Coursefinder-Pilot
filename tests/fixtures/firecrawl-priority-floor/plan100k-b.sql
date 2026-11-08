-- after the first apply
do $$ declare bc jsonb; begin
  select billing_config into bc from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  perform fx.ok('P1 plan record: limit 100000, tier standard_100k, the account owner''s note',
                bc->>'monthly_vendor_units_limit' = '100000' and bc->>'plan_tier' = 'standard_100k'
                and bc->>'plan_note' = 'Standard plan, 100,000 credits a month ($99 a month), billing period 8 Nov to 8 Dec 2026, as shown on the Firecrawl billing page by the account owner on 8 Nov 2026 12:09 (the vendor balance reading confirms)');
  perform fx.ok('P1 plan record: every other key untouched, including the reserve 0, 2 percent and no_silent_paid_fallback',
                md5((bc - 'monthly_vendor_units_limit' - 'plan_tier' - 'plan_note')::text) = (select v from fx.snap where k = 'billing_rest')
                and bc->>'stop_at_vendor_units_remaining' = '0' and bc->>'safety_reserve_percent' = '2' and bc->>'no_silent_paid_fallback' = 'true');
  perform fx.ok('P1 the six shares are the new values in the priority order and add up to the total',
                (select string_agg(key || '=' || (value #>> '{}'), ',' order by key) from pipeline.platform_toolset_settings where key like 'daily_%' and key <> 'daily_budget_on') =
                'daily_budget_total=4000,daily_share_central=1000,daily_share_course_search=800,daily_share_other=200,daily_share_reads=1200,daily_share_scholarships=800'
                and (select sum((value #>> '{}')::numeric) from pipeline.platform_toolset_settings where key like 'daily_share_%') = 4000);
  perform fx.ok('P1 each is inside its setting range (unchanged ranges 0 to 100000) and carries the reason',
                not exists (select 1 from pipeline.platform_toolset_settings s where s.key like 'daily_%' and s.key <> 'daily_budget_on'
                              and ((s.value #>> '{}')::numeric < s.min_value or (s.value #>> '{}')::numeric > s.max_value or s.reason <> 'account owner moved the plan to the Standard 100,000 credits a month, 8 Nov 2026')));
  perform fx.ok('P1 no other Firecrawl setting changed (the priority floor included)',
                (select md5(string_agg(key || '=' || value::text, ',' order by key)) from pipeline.platform_toolset_settings
                  where toolset_key = 'firecrawl' and key not in ('daily_budget_total', 'daily_share_central', 'daily_share_reads', 'daily_share_scholarships', 'daily_share_course_search', 'daily_share_other'))
                = (select v from fx.snap where k = 'settings'));
  perform fx.ok('P1 one audit event for the plan record and one for each share, with before and after, actor null',
                (select count(*) from pipeline.admin_control_events where area = 'firecrawl' and action = 'plan_limit') = 1
                and (select count(*) from pipeline.admin_control_events where area = 'firecrawl' and action = 'daily_shares') = 6
                and (select count(*) from pipeline.admin_control_events where action in ('plan_limit', 'daily_shares') and actor is null and detail ? 'before' and detail ? 'after'
                       and detail->>'reason' = 'account owner moved the plan to the Standard 100,000 credits a month, 8 Nov 2026') = 7
                and (select detail->'before'->>'monthly_vendor_units_limit' from pipeline.admin_control_events where action = 'plan_limit') = '500000'
                and (select detail->>'after' from pipeline.admin_control_events where target = 'firecrawl/daily_share_course_search') = '800');
  create table fx.ev as select count(*) n, md5(string_agg(detail::text, '|' order by id)) m from pipeline.admin_control_events where action in ('plan_limit', 'daily_shares');
end $$;
