CREATE OR REPLACE FUNCTION security.ai_use_refusal_v1(p_use text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Decision 5 E-7 (2 Nov 2026): why an AI use is refused now, or null. Only in Stop at limits (pipeline.platform_toolsets 'openrouter');
-- Observe only never refuses. Checked before work is claimed or fired, never during a call: what is claimed finishes and records its cost.
declare v_mode text; v_bal numeric; v_at timestamptz; v_floor numeric; v_ceiling numeric; v_total numeric; g record;
begin
  select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';
  if coalesce(v_mode, 'observe') <> 'stop' then return null; end if;
  -- the credit floor: the latest balance (read every 15 minutes) less the spend recorded since; at or below the floor is refused
  select o.remaining_usd, o.observed_at into v_bal, v_at from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
  if v_bal is not null then
    v_bal := v_bal - coalesce((select sum(l.cost_usd) from pipeline.ai_spend_ledger l where l.at > v_at and l.source <> 'opening'), 0);
    if v_bal <= v_floor then
      return format('credit floor: balance about US$%s, at or below the floor of US$%s (openrouter.credit_floor_usd)', round(v_bal, 2), v_floor);
    end if;
  end if;
  -- the daily ceiling: every lane together, today (UTC)
  v_ceiling := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14);
  select coalesce(sum(x.spent), 0) into v_total from security.ai_spend_today_v1() x;
  if v_ceiling > 0 and v_total >= v_ceiling then
    return format('daily ceiling: US$%s spent today (UTC) across all AI lanes, ceiling US$%s (budgets.ai_daily_ceiling_usd)', v_total, v_ceiling);
  end if;
  -- the lane's own guard (0 = no guard)
  select * into g from security.ai_spend_today_v1() x where x.use = p_use;
  if coalesce(g.guard, 0) > 0 and coalesce(g.spent, 0) >= g.guard then
    return format('lane guard: %s spent US$%s today (UTC), guard US$%s (openrouter.guard_%s)', p_use, g.spent, g.guard, p_use);
  end if;
  return null;
end $function$

