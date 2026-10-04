-- CF-247 Decision 252: Serper and ScrapingBee registered as Layer 2 services, switched OFF (part 3 of the trials change).
-- Keys are saved from Platform settings › Environment & integrations into the vault.
insert into pipeline.layer2_acquisition_providers(provider_key, display_name, adapter_type, base_url, auth_scheme, auth_field_name, capabilities,
    billing_config, request_template, priority, concurrency, timeout_seconds, enabled, operational_owner, change_control_ref)
values
  ('serper', 'Serper (web search, trial)', 'structured_api_proxy', 'https://google.serper.dev/search', 'header', 'X-API-KEY',
   '{"search": true, "html": false, "javascript": false}'::jsonb,
   '{"currency": "USD", "vendor_unit_name": "query", "plan_tier": "trial", "no_silent_paid_fallback": true}'::jsonb,
   '{"trial_only": true, "method": "POST_JSON", "note": "Search API, not a page fetcher: keep switched off for page fetching."}'::jsonb,
   95, 4, 30, false, 'Platform Operations', 'CF-247 Decision 252'),
  ('scrapingbee', 'ScrapingBee (browser rendering, trial)', 'scraper_api', 'https://app.scrapingbee.com/api/v1/', 'query_param', 'api_key',
   '{"raw": true, "html": true, "javascript": true, "anti_bot": true, "proxy": true, "screenshot": false}'::jsonb,
   '{"currency": "USD", "vendor_unit_name": "credit", "plan_tier": "trial", "no_silent_paid_fallback": true}'::jsonb,
   '{"trial_only": true, "target_url_parameter": "url", "credit_cost_header": "Spb-cost"}'::jsonb,
   96, 3, 90, false, 'Platform Operations', 'CF-247 Decision 252')
on conflict (provider_key) do nothing;
