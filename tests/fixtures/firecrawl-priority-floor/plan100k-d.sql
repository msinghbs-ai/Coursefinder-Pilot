-- after the apply on the mixed state
do $$ begin
  perform fx.ok('P3 a value that is no longer the old one is left alone (reads stays 4321; the plan record stays 300000 / custom)',
                (select value from pipeline.platform_toolset_settings where key = 'daily_share_reads') = '4321'::jsonb
                and (select billing_config->>'monthly_vendor_units_limit' || '/' || (billing_config->>'plan_tier') from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl') = '300000/custom');
  perform fx.ok('P3 the other five shares were applied',
                (select string_agg(key || '=' || (value #>> '{}'), ',' order by key) from pipeline.platform_toolset_settings where key like 'daily_%' and key not in ('daily_budget_on', 'daily_share_reads')) =
                'daily_budget_total=4000,daily_share_central=1000,daily_share_course_search=800,daily_share_other=200,daily_share_scholarships=800');
  perform fx.ok('P3 five new events, none for the skipped ones',
                (select count(*) from pipeline.admin_control_events where action in ('plan_limit', 'daily_shares')) = (select n from fx.ev2) + 5
                and (select count(*) from pipeline.admin_control_events where target = 'firecrawl/daily_share_reads') = 1);
  -- back to the agreed state for the next checks
  update pipeline.platform_toolset_settings set value = to_jsonb(1200) where toolset_key = 'firecrawl' and key = 'daily_share_reads';
  update pipeline.layer2_acquisition_providers set billing_config = jsonb_set(jsonb_set(billing_config, '{monthly_vendor_units_limit}', '100000'), '{plan_tier}', '"standard_100k"') where provider_key = 'firecrawl';
end $$;
