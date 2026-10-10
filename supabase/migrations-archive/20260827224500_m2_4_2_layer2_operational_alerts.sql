-- M2.4.2 — computed Layer 2 operational alerts through the existing rank-4 admin_read boundary.

begin;

create or replace function security.layer2_operational_alerts_read()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','public'
as $$
declare v_rank integer; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  with alerts as (
    select
      'critical'::text severity,
      'stuck_run'::text code,
      'Layer 2 managed run is stale'::text title,
      ('Run '||b.id::text||' exceeded its '||coalesce(ep.stale_after_minutes,30)||'-minute heartbeat threshold.')::text message,
      b.profile_id,b.id run_id,null::uuid provider_id,
      coalesce(b.heartbeat_at,b.updated_at,b.started_at,b.created_at) occurred_at
    from pipeline.layer2_run_batches b
    join pipeline.layer2_execution_policies ep on ep.profile_id=b.profile_id
    where b.status='running'
      and coalesce(b.heartbeat_at,b.updated_at,b.started_at,b.created_at)
          < now()-make_interval(mins=>coalesce(ep.stale_after_minutes,30))

    union all

    select
      'warning','paused_profile','Layer 2 Course profile is paused',
      (coalesce(cp.canonical_name,s.label,p.profile_key)||' is paused; scheduled/discovery execution is blocked until explicitly resumed.'),
      p.id,null::uuid,null::uuid,p.updated_at
    from pipeline.layer2_source_profiles p
    join pipeline.sources s on s.id=p.source_id
    left join catalogue.providers cp on cp.id=s.provider_id
    where p.domain='course_facts' and p.enabled and p.paused

    union all

    select
      'warning','blocked_items','Layer 2 run items are blocked',
      (count(*)::text||' Layer 2 item(s) are blocked and require source or route review.'),
      null::uuid,null::uuid,null::uuid,max(updated_at)
    from pipeline.layer2_run_items
    where status='blocked'
    having count(*)>0

    union all

    select
      'warning','provider_failure_streak','Acquisition provider has repeated failures',
      (ap.display_name||' has '||x.failure_count||' failures/blocks in its latest 10 attempts.'),
      null::uuid,null::uuid,ap.id,x.latest_at
    from pipeline.layer2_acquisition_providers ap
    cross join lateral (
      select count(*) filter(where z.status in ('failed','error','blocked')) failure_count,
             max(z.created_at) latest_at
      from (
        select a.status,a.created_at
        from pipeline.layer2_provider_attempts a
        where a.acquisition_provider_id=ap.id
        order by a.created_at desc
        limit 10
      ) z
    ) x
    where ap.enabled and x.failure_count>=5

    union all

    select
      'warning','provider_quota_reserve','Acquisition provider is near quota reserve',
      (ap.display_name||' has '||q.remaining_units||' unit(s) remaining; configured stop reserve is '||q.stop_units||'.'),
      null::uuid,null::uuid,ap.id,q.latest_at
    from pipeline.layer2_acquisition_providers ap
    cross join lateral (
      select
        nullif(a.metrics#>>'{budget_at_start,remaining_after_planned}','')::numeric remaining_units,
        coalesce(nullif(ap.billing_config->>'stop_at_vendor_units_remaining','')::numeric,0) stop_units,
        a.created_at latest_at
      from pipeline.layer2_provider_attempts a
      where a.acquisition_provider_id=ap.id
        and a.metrics#>>'{budget_at_start,remaining_after_planned}' is not null
      order by a.created_at desc
      limit 1
    ) q
    where ap.enabled
      and q.remaining_units is not null
      and q.remaining_units <= q.stop_units + greatest(50,q.stop_units*0.2)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'severity',severity,'code',code,'title',title,'message',message,
    'profile_id',profile_id,'run_id',run_id,'provider_id',provider_id,'occurred_at',occurred_at
  ) order by case severity when 'critical' then 1 when 'warning' then 2 else 3 end, occurred_at desc),'[]'::jsonb)
  into v_result
  from alerts;

  return v_result;
end $$;

revoke all on function security.layer2_operational_alerts_read() from public,anon;
grant execute on function security.layer2_operational_alerts_read() to authenticated,service_role;

do $$
declare v_def text; v_oid oid;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb'
  limit 1;
  if v_oid is null then raise exception 'public.admin_read(text,jsonb) not found'; end if;
  select pg_get_functiondef(v_oid) into v_def;
  if position('layer2_ops_alerts' in v_def)=0 then
    if position('if p_operation in (''layer2_ops_overview'',''layer2_ops_run_detail'') then' in v_def)=0 then
      raise exception 'Layer 2 admin_read dispatch marker not found';
    end if;
    v_def:=replace(
      v_def,
      'if p_operation in (''layer2_ops_overview'',''layer2_ops_run_detail'') then',
      'if p_operation=''layer2_ops_alerts'' then return security.layer2_operational_alerts_read(); end if;'||chr(10)||
      ' if p_operation in (''layer2_ops_overview'',''layer2_ops_run_detail'') then'
    );
    execute v_def;
  end if;
end $$;

commit;
