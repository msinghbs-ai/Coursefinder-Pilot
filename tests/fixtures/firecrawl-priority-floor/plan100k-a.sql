-- before migration 20261108061000: the state to compare with (live values of 8 Nov 2026), and the audit count
-- the plan record as live on 8 Nov 2026
update pipeline.layer2_acquisition_providers set billing_config = billing_config || '{"currency": "USD", "plan_note": "Growth plan, 500,000 credits a month as reported by Firecrawl (period 2 Oct to 2 Nov 2026)", "plan_tier": "growth_500k", "unit_cost_usd": 0, "vendor_unit_name": "page", "entitlement_basis": "vendor_reported_plan", "plan_confirmed_at": "2026-10-04T05:09:36.207447+00:00", "safety_reserve_percent": 2}'::jsonb
 where provider_key = 'firecrawl';
update pipeline.platform_toolset_settings set value = to_jsonb(25000) where toolset_key = 'firecrawl' and key = 'daily_budget_total';
create table fx.snap as select 'settings'::text k, md5(string_agg(key || '=' || value::text, ',' order by key)) v from pipeline.platform_toolset_settings
  where toolset_key = 'firecrawl' and key not in ('daily_budget_total', 'daily_share_central', 'daily_share_reads', 'daily_share_scholarships', 'daily_share_course_search', 'daily_share_other')
  union all select 'billing_rest', md5((billing_config - 'monthly_vendor_units_limit' - 'plan_tier' - 'plan_note')::text) from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl'
  union all select 'events', count(*)::text from pipeline.admin_control_events;
