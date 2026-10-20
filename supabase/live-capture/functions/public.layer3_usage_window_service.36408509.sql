CREATE OR REPLACE FUNCTION public.layer3_usage_window_service(p_profile_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
with live as (
  select
    coalesce(sum(external_call_count) filter(where created_at>=now()-interval '1 minute' and status<>'cancelled'),0)::integer minute_calls,
    coalesce(sum(external_call_count) filter(where created_at>=date_trunc('day',now()) and status<>'cancelled'),0)::integer day_calls,
    coalesce(sum(estimated_cost_usd) filter(where created_at>=date_trunc('day',now())),0)::numeric day_cost_usd,
    coalesce(sum(input_tokens) filter(where created_at>=date_trunc('day',now())),0)::bigint day_input_tokens,
    coalesce(sum(output_tokens) filter(where created_at>=date_trunc('day',now())),0)::bigint day_output_tokens
  from pipeline.layer3_interpretations
  where profile_id=p_profile_id
),
bench as (
  select
    coalesce(sum(external_call_count) filter(where created_at>=now()-interval '1 minute'),0)::integer minute_calls,
    coalesce(sum(external_call_count) filter(where created_at>=date_trunc('day',now())),0)::integer day_calls,
    coalesce(sum(estimated_cost_usd) filter(where created_at>=date_trunc('day',now())),0)::numeric day_cost_usd,
    coalesce(sum(input_tokens) filter(where created_at>=date_trunc('day',now())),0)::bigint day_input_tokens,
    coalesce(sum(output_tokens) filter(where created_at>=date_trunc('day',now())),0)::bigint day_output_tokens
  from pipeline.layer3_quality_benchmark_runs
  where profile_id=p_profile_id
)
select jsonb_build_object(
  'minute_calls',live.minute_calls+bench.minute_calls,
  'day_calls',live.day_calls+bench.day_calls,
  'day_cost_usd',live.day_cost_usd+bench.day_cost_usd,
  'day_input_tokens',live.day_input_tokens+bench.day_input_tokens,
  'day_output_tokens',live.day_output_tokens+bench.day_output_tokens,
  'live_day_calls',live.day_calls,
  'benchmark_day_calls',bench.day_calls
)
from live,bench
$function$
