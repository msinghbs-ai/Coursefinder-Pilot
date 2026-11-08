-- after the second apply
do $$ begin
  perform fx.ok('P2 a second run changed nothing: still 7 events, same rows, same values',
                (select n from fx.ev) = (select count(*) from pipeline.admin_control_events where action in ('plan_limit', 'daily_shares'))
                and (select m from fx.ev) = (select md5(string_agg(detail::text, '|' order by id)) from pipeline.admin_control_events where action in ('plan_limit', 'daily_shares')));
  -- a person (or another change) moved some values after the first run: rewind to a mixed state for the guard
  update pipeline.platform_toolset_settings set value = to_jsonb(25000) where toolset_key = 'firecrawl' and key = 'daily_budget_total';
  update pipeline.platform_toolset_settings set value = to_jsonb(4321) where toolset_key = 'firecrawl' and key = 'daily_share_reads';      -- changed by someone: not the old value
  update pipeline.platform_toolset_settings set value = to_jsonb(2500) where toolset_key = 'firecrawl' and key = 'daily_share_central';
  update pipeline.platform_toolset_settings set value = to_jsonb(3500) where toolset_key = 'firecrawl' and key = 'daily_share_scholarships';
  update pipeline.platform_toolset_settings set value = to_jsonb(13000) where toolset_key = 'firecrawl' and key = 'daily_share_course_search';
  update pipeline.platform_toolset_settings set value = to_jsonb(1000) where toolset_key = 'firecrawl' and key = 'daily_share_other';
  update pipeline.layer2_acquisition_providers set billing_config = jsonb_set(jsonb_set(billing_config, '{monthly_vendor_units_limit}', '300000'), '{plan_tier}', '"custom"') where provider_key = 'firecrawl';
  create table fx.ev2 as select count(*) n from pipeline.admin_control_events where action in ('plan_limit', 'daily_shares');
end $$;
