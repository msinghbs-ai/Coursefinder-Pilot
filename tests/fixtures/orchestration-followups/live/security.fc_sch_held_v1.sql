CREATE OR REPLACE FUNCTION security.fc_sch_held_v1(p_provider_id uuid, p_discovery boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  return coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false)
     and ((p_discovery and not security.fc_sch_eligible_v1(p_provider_id))
          or (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > security.fc_sch_cap_since_v1(p_provider_id))
             >= security.fc_setting_num_v1('scholarship_cap_per_uni', 150));
end $function$
