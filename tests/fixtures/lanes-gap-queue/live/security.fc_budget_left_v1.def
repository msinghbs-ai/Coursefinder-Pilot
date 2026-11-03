CREATE OR REPLACE FUNCTION security.fc_budget_left_v1(p_purpose text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_grp text := security.fc_purpose_group_v1(p_purpose); v_used numeric;
begin
  -- Decision 5 E-8 F2 (2 Nov 2026): nothing is left on any path once the monthly plan limit is reached
  if security.fc_month_refusal_v1(1) is not null then return 0; end if;
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then return 1000000; end if;
  -- CF-247 21 Oct 2026: on-demand spends (manual enrichment plan runs) have their own allowance and do not use up the automatic budget
  if security.fc_billed_today_v1() - security.fc_on_demand_today_v1() >= security.fc_setting_num_v1('daily_budget_total', 15000) then return 0; end if;
  select coalesce(sum(x.units), 0) into v_used from pipeline.coverage_vendor_usage x where x.at >= security.fc_day_start_v1() and security.fc_purpose_group_v1(x.purpose) = v_grp and x.on_demand_run is null;
  return greatest(0, security.fc_setting_num_v1('daily_share_' || v_grp, 0) - v_used);
end $function$
