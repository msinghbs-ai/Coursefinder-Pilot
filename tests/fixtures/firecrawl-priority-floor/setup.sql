-- CF-247 Firecrawl priority floor: the state before the migration, with the values read live on 8 Nov 2026 (settings, the Firecrawl plan row). Test helpers in schema fx.
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('firecrawl', 'daily_budget_on', 'Keep to the daily budget', 'x', 'boolean', 'true', null, null, null, 100, 'Daily budget', null, 'live'),
 ('firecrawl', 'daily_budget_total', 'Credits a day (billed)', 'x', 'number', '25000', 0, 100000, 'credits', 610, 'Daily budget', null, 'live'),
 ('firecrawl', 'daily_share_course_search', 'Share: finding course pages (search)', 'x', 'number', '13000', 0, 100000, 'credits', 620, 'Daily budget', null, 'live'),
 ('firecrawl', 'daily_share_reads', 'Share: reading pages Firecrawl must read', 'x', 'number', '5000', 0, 100000, 'credits', 630, 'Daily budget', null, 'live'),
 ('firecrawl', 'daily_share_scholarships', 'Share: scholarships', 'x', 'number', '3500', 0, 100000, 'credits', 640, 'Daily budget', null, 'live'),
 ('firecrawl', 'daily_share_central', 'Share: central pages', 'x', 'number', '2500', 0, 100000, 'credits', 650, 'Daily budget', null, 'live'),
 ('firecrawl', 'daily_share_other', 'Share: other', 'x', 'number', '1000', 0, 100000, 'credits', 660, 'Daily budget', null, 'live'),
 ('firecrawl', 'ondemand_credits_per_day', 'On-demand allowance (Run now)', 'x', 'number', '2000', 0, 20000, 'credits', 90, 'Daily budget', 'svc_fc_spend', 'live'),
 ('firecrawl', 'central_refresh_days', 'Read central pages again after', 'x', 'number', '30', 1, 365, 'days', 100, 'Notices', null, 'live'),
 ('firecrawl', 'scholarship_cap_per_uni', 'Scholarship credits per university (30 days)', 'x', 'number', '150', 0, 5000, 'credits', 100, 'Notices', null, 'live');
-- the Firecrawl plan as live: monthly limit 500,000 as reported, reserve 0, one credit a call
insert into pipeline.layer2_acquisition_providers(id, provider_key, display_name, adapter_type, change_control_ref, billing_config, request_template)
values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', 'firecrawl', 'Firecrawl', 'http', 'fixture',
        '{"monthly_vendor_units_limit": 500000, "stop_at_vendor_units_remaining": 0, "no_silent_paid_fallback": true}', '{"fixed_credit_units": 1}');
insert into pipeline.platform_health_checks(key, area, label, status, detail)
values ('budgets', 'budgets', 'Budgets', 'ok', '{"firecrawl": {"used": 4038, "limit": 5000, "reserve": 0, "remaining": 962}}');

create or replace function fx.ok(p_name text, p_cond boolean) returns void language plpgsql as $f$
begin
  if p_cond is not true then raise exception 'FAIL %', p_name; end if;
  raise notice 'PASS %', p_name;
end $f$;
-- a clean state with one fresh vendor balance (p_bal credits, read p_age ago); the plan's stop reserve p_stop
create or replace function fx.reset(p_bal numeric, p_age interval default interval '1 minute', p_stop numeric default 0) returns void language plpgsql as $f$
declare v_id constant uuid := '6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88';
begin
  delete from pipeline.vendor_credit_observations; delete from pipeline.coverage_vendor_usage; delete from pipeline.layer2_provider_attempts;
  delete from pipeline.firecrawl_budget_refusals; delete from pipeline.firecrawl_refusals_by_provider; delete from pipeline.enrich_plan_runs;
  update pipeline.layer2_acquisition_providers set billing_config = jsonb_set(billing_config, '{stop_at_vendor_units_remaining}', to_jsonb(p_stop)) where id = v_id;
  insert into pipeline.vendor_credit_observations(provider_id, remaining_units, plan_units, period_end, observed_at) values (v_id, p_bal, 5000, now() + interval '24 days', now() - p_age);
end $f$;
create or replace function fx.floor(p_v numeric) returns void language sql as
  $f$ update pipeline.platform_toolset_settings set value = to_jsonb(p_v) where toolset_key = 'firecrawl' and key = 'priority_floor_course_search' $f$;
create or replace function fx.setting(p_key text, p_v jsonb) returns void language sql as
  $f$ update pipeline.platform_toolset_settings set value = p_v where toolset_key = 'firecrawl' and key = p_key $f$;
create or replace function fx.use(p_units numeric, p_purpose text, p_at timestamptz default now()) returns void language sql as
  $f$ insert into pipeline.coverage_vendor_usage(acquisition_provider_id, units, purpose, at) values ('6d99eba5-83e1-4fd8-a46f-d2b8dd8ffd88', p_units, p_purpose, p_at) $f$;
create or replace function fx.refusals(p_grp text, p_reason text) returns int language sql as
  $f$ select coalesce((select sum(n) from pipeline.firecrawl_budget_refusals where grp = p_grp and reason = p_reason), 0)::int $f$;
