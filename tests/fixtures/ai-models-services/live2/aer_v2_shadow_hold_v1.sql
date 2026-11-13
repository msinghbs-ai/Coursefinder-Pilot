CREATE OR REPLACE FUNCTION security.aer_v2_shadow_hold_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record; v_spent numeric; v_today numeric; v_budget numeric := security.pipeline_num_v1('aer.v2_shadow_budget_usd', 20);
        v_daily numeric := security.pipeline_num_v1('aer.v2_shadow_daily_usd', 3);
begin
  select x.version, x.system_text, x.system_sha256, x.model, x.quote_max_chars into v
    from pipeline.aer_prompt_versions x where x.purpose = 'course_page' and x.status = 'trial' order by x.created_at desc limit 1;
  select coalesce(sum(r.cost_usd), 0),
         coalesce(sum(r.cost_usd) filter (where r.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'), 0)  -- fixed: the UTC day, as the AI ledger counts it
    into v_spent, v_today from pipeline.aer_v2_shadow_results r;
  return jsonb_build_object(
    'held', case when security.pipeline_num_v1('aer.v2_shadow_on', 0) < 1 then 'switched off (aer.v2_shadow_on)'
                 when v.version is null then 'no trial prompt version'
                 when v_spent >= v_budget then format('trial budget reached: US$%s of US$%s (aer.v2_shadow_budget_usd)', round(v_spent, 4), v_budget)
                 when v_today >= v_daily then format('daily share reached: US$%s of US$%s today (aer.v2_shadow_daily_usd)', round(v_today, 4), v_daily) end,
    'version', case when v.version is not null then jsonb_build_object('version', v.version, 'system_text', v.system_text, 'system_sha256', v.system_sha256,
                                                                        'model', v.model, 'quote_max_chars', v.quote_max_chars) end,
    'budget', jsonb_build_object('usd', v_budget, 'spent', v_spent, 'daily_usd', v_daily, 'today', v_today));
end $function$
