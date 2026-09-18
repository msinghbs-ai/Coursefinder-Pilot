-- CF-CHG-20260915-247
-- Count actual provider calls, not interpretation rows, and include governed benchmark
-- calls in profile quota telemetry. Prevents both false quota burn and benchmark omission.
begin;

create or replace function public.layer3_usage_window_service(p_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','pipeline'
as $function$
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
$function$;

revoke all on function public.layer3_usage_window_service(uuid) from public,anon,authenticated;
grant execute on function public.layer3_usage_window_service(uuid) to service_role;

create or replace function public.layer3_dispatch_headroom_service(
  p_task_class text default 'provider_current_tuition_validation'
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','pipeline'
as $$
declare
  v_caller text;
  v_p pipeline.layer3_model_profiles%rowtype;
  v_usage jsonb;
  v_minute integer;
  v_day integer;
  v_minute_headroom integer;
  v_day_headroom integer;
begin
  v_caller:=coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    nullif(current_setting('request.jwt.role',true),''),
    nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',
    auth.role(),
    session_user
  );
  if v_caller not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_p
  from pipeline.layer3_model_profiles
  where p_task_class=any(allowed_task_classes)
    and enabled and not paused
    and coalesce((quality_benchmark->>'pass')::boolean,false)
  order by updated_at desc,id
  limit 1;

  if not found then
    return jsonb_build_object(
      'ok',false,'reason','no_qualified_executable_profile',
      'task_class',p_task_class,'minute_headroom',0,'day_headroom',0,'dispatch_headroom',0
    );
  end if;

  v_usage:=public.layer3_usage_window_service(v_p.id);
  v_minute:=coalesce((v_usage->>'minute_calls')::integer,0);
  v_day:=coalesce((v_usage->>'day_calls')::integer,0);
  v_minute_headroom:=greatest(v_p.requests_per_minute-v_minute,0);
  v_day_headroom:=greatest(v_p.requests_per_day-v_day,0);

  return jsonb_build_object(
    'ok',true,
    'profile_id',v_p.id,
    'profile_code',v_p.code,
    'task_class',p_task_class,
    'minute_calls',v_minute,
    'minute_limit',v_p.requests_per_minute,
    'minute_headroom',v_minute_headroom,
    'day_calls',v_day,
    'day_limit',v_p.requests_per_day,
    'day_headroom',v_day_headroom,
    'dispatch_headroom',least(v_minute_headroom,v_day_headroom),
    'day_cost_usd',coalesce((v_usage->>'day_cost_usd')::numeric,0),
    'day_input_tokens',coalesce((v_usage->>'day_input_tokens')::bigint,0),
    'day_output_tokens',coalesce((v_usage->>'day_output_tokens')::bigint,0),
    'live_day_calls',coalesce((v_usage->>'live_day_calls')::integer,0),
    'benchmark_day_calls',coalesce((v_usage->>'benchmark_day_calls')::integer,0),
    'day_resets_at',date_trunc('day',now())+interval '1 day'
  );
end $$;

revoke all on function public.layer3_dispatch_headroom_service(text) from public,anon,authenticated;
grant execute on function public.layer3_dispatch_headroom_service(text) to service_role;

commit;
