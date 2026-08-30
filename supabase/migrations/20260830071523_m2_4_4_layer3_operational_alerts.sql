-- M2.4.4 cross-layer operations: Layer 3 operator alert surface.
-- Read-only operational visibility for stale execution, model qualification/state,
-- repeated provider errors and recorded cost-ceiling breaches.
-- Does not mutate canonical data, governed Evidence or history.

create or replace function security.layer3_operational_alerts_read()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','auth'
as $function$
declare
  v_rank integer;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 4 then
    raise exception 'pipeline_operator role required' using errcode='42501';
  end if;

  with alerts as (
    select
      'critical'::text severity,
      'stale_execution'::text code,
      'Layer 3 execution exceeded recovery window'::text title,
      ('Interpretation '||i.id::text||' has remained '||i.status||' beyond the governed 20-minute recovery window.')::text message,
      i.profile_id,
      i.id interpretation_id,
      i.created_at occurred_at
    from pipeline.layer3_interpretations i
    where i.status in ('reserved','calling')
      and i.created_at < now()-interval '20 minutes'

    union all

    select
      'warning','paused_profile','Layer 3 model profile is paused',
      (p.code||' is enabled but paused; governed AI execution is blocked until explicitly resumed.'),
      p.id,null::uuid,p.updated_at
    from pipeline.layer3_model_profiles p
    where p.enabled and p.paused

    union all

    select
      'critical','unqualified_profile','Layer 3 enabled profile is not benchmark-qualified',
      (p.code||' is enabled/unpaused but its current governed quality benchmark is not PASS.'),
      p.id,null::uuid,p.updated_at
    from pipeline.layer3_model_profiles p
    where p.enabled and not p.paused
      and not coalesce((p.quality_benchmark->>'pass')::boolean,false)

    union all

    select
      'warning','latest_benchmark_failed','Latest Layer 3 benchmark failed',
      (p.code||' latest benchmark status is '||b.status||'; retain failure evidence and requalify before relying on the profile.'),
      p.id,null::uuid,b.created_at
    from pipeline.layer3_model_profiles p
    join lateral (
      select q.status,q.created_at
      from pipeline.layer3_quality_benchmark_runs q
      where q.profile_id=p.id
      order by q.created_at desc
      limit 1
    ) b on true
    where p.enabled and not p.paused and b.status <> 'pass'

    union all

    select
      'warning','provider_error_streak','Layer 3 profile has repeated provider errors',
      (p.code||' has '||x.failure_count||' provider_error result(s) in its latest 10 interpretations.'),
      p.id,null::uuid,x.latest_at
    from pipeline.layer3_model_profiles p
    cross join lateral (
      select
        count(*) filter(where z.status='provider_error') failure_count,
        max(z.created_at) latest_at
      from (
        select i.status,i.created_at
        from pipeline.layer3_interpretations i
        where i.profile_id=p.id
        order by i.created_at desc
        limit 10
      ) z
    ) x
    where p.enabled and x.failure_count>=5

    union all

    select
      'warning','cost_ceiling_exceeded','Layer 3 recorded cost exceeded profile ceiling',
      (p.code||' has a recent recorded call cost above its configured per-execution ceiling; review provider/model billing telemetry.'),
      p.id,null::uuid,max(i.created_at)
    from pipeline.layer3_model_profiles p
    join pipeline.layer3_interpretations i on i.profile_id=p.id
    where i.created_at>=now()-interval '30 days'
      and coalesce(i.external_call_count,0)>0
      and i.estimated_cost_usd is not null
      and p.cost_ceiling_usd is not null
      and i.estimated_cost_usd>p.cost_ceiling_usd
    group by p.id,p.code
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'severity',severity,
    'code',code,
    'title',title,
    'message',message,
    'profile_id',profile_id,
    'interpretation_id',interpretation_id,
    'occurred_at',occurred_at
  ) order by case severity when 'critical' then 1 when 'warning' then 2 else 3 end, occurred_at desc),'[]'::jsonb)
  into v_result
  from alerts;

  return v_result;
end
$function$;

revoke all on function security.layer3_operational_alerts_read() from public;
revoke all on function security.layer3_operational_alerts_read() from anon;
grant execute on function security.layer3_operational_alerts_read() to authenticated;
grant execute on function security.layer3_operational_alerts_read() to service_role;

comment on function security.layer3_operational_alerts_read() is
'M2.4.4 operator alert surface for Layer 3 stale execution, profile qualification/state, provider-error streaks and recorded cost-ceiling breaches. Does not mutate canonical, Evidence or history.';
