CREATE OR REPLACE FUNCTION security.ai_use_allowed_v1(p_use text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_mode text; v_bal numeric; v_floor numeric; g record;
begin
  select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';
  if coalesce(v_mode, 'observe') <> 'stop' then return true; end if;
  select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is not null and v_bal < v_floor then return false; end if;
  select * into g from security.ai_spend_today_v1() x where x.use = p_use;
  return not (coalesce(g.guard, 0) > 0 and coalesce(g.spent, 0) >= g.guard);
end $function$
;
