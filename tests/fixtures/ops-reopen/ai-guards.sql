create or replace function security.ai_spend_capture_v1() returns trigger
language plpgsql security definer set search_path to '' as $$
-- Decision 5 E-7 (2 Nov 2026): records the AI cost a row gains. tg_argv: lane, how ('delta' = the increase of an accumulated cost;
-- 'decision' = the cost of each decision of a leased item, as svc_coverage_ai_match_record overwrites it), the path of the cost in the row.
declare v_new jsonb := to_jsonb(new); v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end; v_path text[] := tg_argv[2]::text[];
        v_add numeric;
begin
  if tg_argv[1] = 'decision' then
    if tg_op = 'UPDATE' and not (v_old->>'state' = 'leased' and v_new->>'state' <> 'leased'
                                 and (v_new->>'decided_at') is distinct from (v_old->>'decided_at')) then return null; end if;
    v_add := coalesce((v_new #>> v_path)::numeric, 0);
  else
    v_add := coalesce((v_new #>> v_path)::numeric, 0) - coalesce((v_old #>> v_path)::numeric, 0);
  end if;
  if v_add > 0 then
    insert into pipeline.ai_spend_ledger(lane, source, source_id, cost_usd) values (tg_argv[0], tg_table_name, v_new->>'id', v_add);
  end if;
  return null;
end $$;
create or replace function security.ai_use_refusal_v1(p_use text) returns text
language plpgsql stable security definer set search_path to '' as $$
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
end $$;
