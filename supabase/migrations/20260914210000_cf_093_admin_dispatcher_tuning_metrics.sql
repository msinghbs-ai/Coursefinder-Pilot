-- CF-CHG-20260910-093
-- Admin dispatcher tuning + comparable run metrics.
-- Forward-only. Existing batch policy_snapshot remains immutable; tuning affects later runs only.

begin;

create table if not exists pipeline.layer2_tuning_events (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references pipeline.layer2_source_profiles(id) on delete restrict,
  actor_id uuid not null,
  governance_reason text not null,
  changed_fields text[] not null default '{}',
  before_policy jsonb not null,
  after_policy jsonb not null,
  change_control_ref text not null default 'CF-CHG-20260910-093',
  created_at timestamptz not null default now()
);

create index if not exists layer2_tuning_events_profile_created_idx
  on pipeline.layer2_tuning_events(profile_id,created_at desc);

revoke all on table pipeline.layer2_tuning_events from public,anon,authenticated;
grant select,insert on table pipeline.layer2_tuning_events to service_role;

create or replace function public.layer2_ops_policy_update(p_actor uuid,p_profile_id uuid,p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','security','pipeline'
as $function$
declare
  v_rank integer:=0;
  v_row pipeline.layer2_execution_policies%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_reason text:=nullif(btrim(coalesce(p_patch->>'_governance_reason','')),'');
  v_changed text[];
begin
  if p_actor is null or p_actor<>auth.uid() then raise exception 'actor mismatch' using errcode='42501'; end if;
  select coalesce(max(r.rank),0) into v_rank
  from security.user_roles ur join security.roles r on r.code=ur.role_code
  where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
  if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
  if not exists(select 1 from pipeline.layer2_source_profiles where id=p_profile_id and domain in ('course_facts','scholarship')) then
    raise exception 'layer2 enrichment profile required' using errcode='22023';
  end if;

  insert into pipeline.layer2_execution_policies(profile_id) values(p_profile_id) on conflict(profile_id) do nothing;
  select to_jsonb(ep)-'updated_by' into v_before from pipeline.layer2_execution_policies ep where ep.profile_id=p_profile_id for update;

  update pipeline.layer2_execution_policies set
    schedule_mode=coalesce(nullif(p_patch->>'schedule_mode',''),schedule_mode),
    scheduled_hour_utc=case when p_patch ? 'scheduled_hour_utc' then nullif(p_patch->>'scheduled_hour_utc','')::smallint else scheduled_hour_utc end,
    batch_size=case when p_patch ? 'batch_size' then (p_patch->>'batch_size')::integer else batch_size end,
    routing_strategy=coalesce(nullif(p_patch->>'routing_strategy',''),routing_strategy),
    max_paid_attempts_per_entity=case when p_patch ? 'max_paid_attempts_per_entity' then (p_patch->>'max_paid_attempts_per_entity')::smallint else max_paid_attempts_per_entity end,
    max_vendor_units_per_entity=case when p_patch ? 'max_vendor_units_per_entity' then nullif(p_patch->>'max_vendor_units_per_entity','')::numeric else max_vendor_units_per_entity end,
    max_cost_usd_per_entity=case when p_patch ? 'max_cost_usd_per_entity' then nullif(p_patch->>'max_cost_usd_per_entity','')::numeric else max_cost_usd_per_entity end,
    max_concurrency=case when p_patch ? 'max_concurrency' then (p_patch->>'max_concurrency')::smallint else max_concurrency end,
    stale_after_minutes=case when p_patch ? 'stale_after_minutes' then (p_patch->>'stale_after_minutes')::integer else stale_after_minutes end,
    auto_handoff_layer3=case when p_patch ? 'auto_handoff_layer3' then (p_patch->>'auto_handoff_layer3')::boolean else auto_handoff_layer3 end,
    stop_on_identity_mismatch=case when p_patch ? 'stop_on_identity_mismatch' then (p_patch->>'stop_on_identity_mismatch')::boolean else stop_on_identity_mismatch end,
    updated_by=p_actor,updated_at=now()
  where profile_id=p_profile_id returning * into v_row;

  v_after:=to_jsonb(v_row)-'updated_by';
  select coalesce(array_agg(k order by k),'{}'::text[]) into v_changed
  from jsonb_object_keys(coalesce(p_patch,'{}'::jsonb)) k
  where left(k,1)<>'_';

  if v_reason is not null then
    if length(v_reason)<5 then raise exception 'governance reason must be at least 5 characters' using errcode='22023'; end if;
    insert into pipeline.layer2_tuning_events(profile_id,actor_id,governance_reason,changed_fields,before_policy,after_policy)
    values(p_profile_id,p_actor,v_reason,v_changed,v_before,v_after);
  end if;

  return jsonb_build_object('ok',true,'policy',v_after,'changed_fields',v_changed,'audit_recorded',v_reason is not null);
end
$function$;

revoke all on function public.layer2_ops_policy_update(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_ops_policy_update(uuid,uuid,jsonb) to service_role;

create or replace function security.admin_layer2_dispatcher_tuning_read_v1(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','security','pipeline','auth'
as $function$
declare
  v_rank integer:=0;
  v_profile_id uuid;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  begin v_profile_id:=nullif(p_args->>'profile_id','')::uuid; exception when invalid_text_representation then raise exception 'valid profile_id required' using errcode='22023'; end;
  if v_profile_id is null then raise exception 'profile_id required' using errcode='22023'; end if;

  with recent_batches as (
    select b.* from pipeline.layer2_run_batches b
    where b.profile_id=v_profile_id
    order by b.created_at desc limit 12
  ), run_metrics as (
    select b.id,
      count(i.*) item_count,
      count(*) filter(where i.status='resolved_l2') resolved_l2,
      count(*) filter(where i.status='layer3_required') layer3_required,
      count(*) filter(where i.status='blocked') blocked,
      count(*) filter(where i.status in ('queued','acquiring','extracting','discovering')) active_items,
      coalesce(sum(i.retry_count),0) retry_count,
      round(avg(i.response_ms) filter(where i.response_ms is not null),1) avg_response_ms,
      round(avg(i.extraction_ms) filter(where i.extraction_ms is not null),1) avg_extraction_ms,
      coalesce(sum(i.evidence_count),0) evidence_count,
      coalesce(sum(i.fields_targeted),0) fields_targeted,
      coalesce(sum(i.fields_resolved),0) fields_resolved
    from recent_batches b left join pipeline.layer2_run_items i on i.batch_id=b.id
    group by b.id
  ), runs as (
    select jsonb_build_object(
      'id',b.id,'status',b.status,'trigger_type',b.trigger_type,'created_at',b.created_at,'started_at',b.started_at,'completed_at',b.completed_at,
      'target_count',b.target_count,'processed_count',b.processed_count,'resolved_l2_count',b.resolved_l2_count,'escalated_l3_count',b.escalated_l3_count,'blocked_count',b.blocked_count,
      'vendor_units',b.vendor_units,'vendor_cost_usd',b.vendor_cost_usd,
      'policy_snapshot',jsonb_build_object(
        'batch_size',b.policy_snapshot->'batch_size','max_concurrency',b.policy_snapshot->'max_concurrency','stale_after_minutes',b.policy_snapshot->'stale_after_minutes',
        'max_paid_attempts_per_entity',b.policy_snapshot->'max_paid_attempts_per_entity','routing_strategy',b.policy_snapshot->'routing_strategy'),
      'runtime_seconds',case when b.started_at is not null then round(extract(epoch from (coalesce(b.completed_at,now())-b.started_at))::numeric,1) end,
      'throughput_items_per_min',case when b.started_at is not null and b.processed_count>0 and coalesce(b.completed_at,now())>b.started_at then round((b.processed_count::numeric/nullif(extract(epoch from (coalesce(b.completed_at,now())-b.started_at)),0))*60,2) end,
      'item_count',m.item_count,'active_items',m.active_items,'retry_count',m.retry_count,'avg_response_ms',m.avg_response_ms,'avg_extraction_ms',m.avg_extraction_ms,
      'evidence_count',m.evidence_count,'fields_targeted',m.fields_targeted,'fields_resolved',m.fields_resolved,
      'field_resolution_percent',case when m.fields_targeted>0 then round(100.0*m.fields_resolved/m.fields_targeted,1) end
    ) row_json,b.created_at
    from recent_batches b join run_metrics m on m.id=b.id
  ), provider_metrics as (
    select jsonb_build_object(
      'provider_key',ap.provider_key,'display_name',ap.display_name,'enabled',ap.enabled,'priority',r.priority,
      'vendor_concurrency',ap.concurrency,'rate_limit_per_minute',ap.rate_limit_per_minute,'timeout_seconds',ap.timeout_seconds,
      'attempts_24h',count(pa.*) filter(where pa.created_at>=now()-interval '24 hours'),
      'success_24h',count(pa.*) filter(where pa.created_at>=now()-interval '24 hours' and pa.status='succeeded'),
      'failed_24h',count(pa.*) filter(where pa.created_at>=now()-interval '24 hours' and pa.status='failed'),
      'http_429_24h',count(pa.*) filter(where pa.created_at>=now()-interval '24 hours' and pa.response_http_status=429),
      'avg_attempt_ms_24h',round(avg(extract(epoch from (pa.completed_at-pa.started_at))*1000) filter(where pa.created_at>=now()-interval '24 hours' and pa.completed_at is not null and pa.started_at is not null)::numeric,1)
    ) row_json,r.priority
    from pipeline.layer2_provider_routes r
    join pipeline.layer2_acquisition_providers ap on ap.id=r.acquisition_provider_id
    left join pipeline.layer2_provider_attempts pa on pa.acquisition_provider_id=ap.id
      and pa.profile_version_id=(select pv.id from pipeline.layer2_source_profile_versions pv where pv.profile_id=v_profile_id and pv.validation_status='valid' order by pv.version_no desc limit 1)
    where r.profile_id=v_profile_id and r.enabled
    group by ap.id,ap.provider_key,ap.display_name,ap.enabled,ap.priority,ap.concurrency,ap.rate_limit_per_minute,ap.timeout_seconds,r.priority
  )
  select jsonb_build_object(
    'profile',(select jsonb_build_object('id',p.id,'profile_key',p.profile_key,'source_label',s.display_name,'country_code',p.country_code,'domain',p.domain,'enabled',p.enabled,'paused',p.paused)
               from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id where p.id=v_profile_id),
    'policy',(select to_jsonb(ep)-'updated_by' from pipeline.layer2_execution_policies ep where ep.profile_id=v_profile_id),
    'system_guardrails',jsonb_build_object('transport_wave_cap',4,'scraper_first_wave_cap',2,'pg_net_timeout_ms',120000,'tuning_mode','manual_governed'),
    'recent_runs',(select coalesce(jsonb_agg(row_json order by created_at desc),'[]'::jsonb) from runs),
    'providers',(select coalesce(jsonb_agg(row_json order by priority),'[]'::jsonb) from provider_metrics),
    'recent_tuning',(select coalesce(jsonb_agg(jsonb_build_object('created_at',e.created_at,'governance_reason',e.governance_reason,'changed_fields',e.changed_fields,'before_policy',e.before_policy,'after_policy',e.after_policy) order by e.created_at desc),'[]'::jsonb)
                     from (select * from pipeline.layer2_tuning_events where profile_id=v_profile_id order by created_at desc limit 10)e)
  ) into v_result;
  return v_result;
end
$function$;

revoke all on function security.admin_layer2_dispatcher_tuning_read_v1(jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer2_dispatcher_tuning_read_v1(jsonb) to authenticated;

-- Preserve the current public.admin_read router and add the new read operation without
-- replacing unrelated parallel routes in this forward-only migration.
do $router$
declare v_def text;
begin
  select pg_get_functiondef('public.admin_read(text,jsonb)'::regprocedure) into v_def;
  if position('layer2_dispatcher_tuning' in v_def)=0 then
    if position('if p_operation=''jobs_runtime'' then return security.admin_jobs_runtime_read_v1(p_args); end if;' in v_def)=0 then
      raise exception 'admin_read insertion anchor not found';
    end if;
    v_def:=replace(v_def,
      'if p_operation=''jobs_runtime'' then return security.admin_jobs_runtime_read_v1(p_args); end if;',
      'if p_operation=''layer2_dispatcher_tuning'' then return security.admin_layer2_dispatcher_tuning_read_v1(p_args); end if;'||E'\n '||
      'if p_operation=''jobs_runtime'' then return security.admin_jobs_runtime_read_v1(p_args); end if;');
    execute v_def;
  end if;
end
$router$;

commit;
