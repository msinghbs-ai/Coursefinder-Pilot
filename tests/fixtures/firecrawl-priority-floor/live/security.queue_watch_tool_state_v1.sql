CREATE OR REPLACE FUNCTION security.queue_watch_tool_state_v1(p_tool text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_kind text := split_part(p_tool, ':', 1); v_part text := split_part(p_tool, ':', 2); v_fc jsonb; v_bal numeric; v_floor numeric; v_mode text; g record;
begin
  if v_kind = 'firecrawl' then
    select c.detail->'firecrawl' into v_fc from pipeline.platform_health_checks c where c.key = 'budgets';
    if v_fc ? 'remaining' and v_fc ? 'reserve' and (v_fc->>'remaining')::numeric <= (v_fc->>'reserve')::numeric then return 'out'; end if;
    if security.fc_budget_left_v1(case v_part when 'course_search' then 'course_link_search' when 'reads' then 'scrape' when 'central' then 'central_map'
                                             when 'scholarships' then 'sch_map' else 'map' end) <= 0 then return 'waiting'; end if;
    return 'ok';
  elsif v_kind = 'ai' then
    select t.enforcement into v_mode from pipeline.platform_toolsets t where t.key = 'openrouter';
    if coalesce(v_mode, 'observe') <> 'stop' then return 'ok'; end if;
    select o.remaining_usd into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;  -- fixed: the latest reading
    v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);
    if v_bal is not null and v_bal < v_floor then return 'out'; end if;
    select * into g from security.ai_spend_today_v1() x where x.use = v_part;
    if coalesce(g.guard, 0) > 0 and coalesce(g.spent, 0) >= g.guard then return 'waiting'; end if;
    return 'ok';
  end if;
  return 'ok';
end $function$
