CREATE OR REPLACE FUNCTION security.ops_hold_outcome_v1(p_code text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 ops D: the outcome of a lane hold: a policy (cap, budget, switch, rule), missing evidence, or waiting for another step's work
  select case when p_code = any (security.pipeline_list_v1('ops.policy_hold_codes', '["daily_cap", "day_budget", "month_cap", "credit_refused", "credits_reserve", "search_off", "lane_paused", "provider_hidden", "search_stopped", "not_target", "skipped_provider"]')) then 'blocked_policy'
              when p_code = any (security.pipeline_list_v1('ops.evidence_hold_codes', '["no_site", "directory_site", "no_website", "needs_source_discovery"]')) then 'blocked_evidence'
              else 'deferred_dependency' end
$function$
