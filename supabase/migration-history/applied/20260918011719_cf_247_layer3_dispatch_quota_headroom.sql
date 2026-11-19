-- CF-CHG-20260915-247
-- Service-only quota preflight for the bounded Layer 3 dispatcher.
-- Prevents reservation/retry burn when configured model headroom is exhausted.
begin;

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
  v_minute integer;
  v_day integer;
  v_cost numeric;
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
      'ok',false,
      'reason','no_qualified_executable_profile',
      'task_class',p_task_class,
      'minute_headroom',0,
      'day_headroom',0,
      'dispatch_headroom',0
    );
  end if;

  select
    count(*) filter(where created_at>=now()-interval '1 minute' and status<>'cancelled')::integer,
    count(*) filter(where created_at>=date_trunc('day',now()) and status<>'cancelled')::integer,
    coalesce(sum(estimated_cost_usd) filter(where created_at>=date_trunc('day',now())),0)
  into v_minute,v_day,v_cost
  from pipeline.layer3_interpretations
  where profile_id=v_p.id;

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
    'day_cost_usd',v_cost,
    'day_resets_at',date_trunc('day',now())+interval '1 day'
  );
end $$;

revoke all on function public.layer3_dispatch_headroom_service(text)
from public,anon,authenticated;
grant execute on function public.layer3_dispatch_headroom_service(text)
to service_role;

commit;
