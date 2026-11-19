-- CF-CHG-20260827-044
-- M2.4.2 additive Layer 2 operational observability, concurrency guard and recovery substrate.

alter table pipeline.layer2_execution_policies
  add column if not exists max_concurrency smallint not null default 1,
  add column if not exists stale_after_minutes integer not null default 30;

alter table pipeline.layer2_execution_policies
  drop constraint if exists layer2_execution_policies_max_concurrency_check,
  add constraint layer2_execution_policies_max_concurrency_check check (max_concurrency between 1 and 8),
  drop constraint if exists layer2_execution_policies_stale_after_minutes_check,
  add constraint layer2_execution_policies_stale_after_minutes_check check (stale_after_minutes between 5 and 240);

alter table pipeline.layer2_run_batches
  add column if not exists heartbeat_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists idempotency_key text,
  add column if not exists cancellation_reason text;

alter table pipeline.layer2_run_items
  add column if not exists outcome_code text,
  add column if not exists failure_class text,
  add column if not exists response_ms integer,
  add column if not exists extraction_ms integer,
  add column if not exists evidence_bytes bigint,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists layer2_one_active_batch_per_profile_idx
  on pipeline.layer2_run_batches(profile_id)
  where status in ('queued','running');
create unique index if not exists layer2_batch_idempotency_idx
  on pipeline.layer2_run_batches(profile_id,idempotency_key)
  where idempotency_key is not null;
create index if not exists layer2_batch_heartbeat_idx
  on pipeline.layer2_run_batches(status,heartbeat_at,updated_at);
create index if not exists layer2_item_outcome_idx
  on pipeline.layer2_run_items(batch_id,outcome_code,failure_class);

create or replace function public.layer2_run_batch_start(p_batch_id uuid)
returns boolean
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  update pipeline.layer2_run_batches
  set status='running',started_at=coalesce(started_at,now()),heartbeat_at=now(),updated_at=now()
  where id=p_batch_id and status in ('queued','running','partial');
  return found;
end $$;

create or replace function public.layer2_run_batch_heartbeat(p_batch_id uuid)
returns boolean
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  update pipeline.layer2_run_batches
  set heartbeat_at=now(),updated_at=now()
  where id=p_batch_id and status='running';
  return found;
end $$;

create or replace function public.layer2_run_batch_cancel(p_batch_id uuid,p_reason text default 'operator_cancelled')
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_items integer;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  update pipeline.layer2_run_items
  set status='cancelled',outcome_code='deferred',blocker=coalesce(nullif(p_reason,''),'operator_cancelled'),completed_at=now(),updated_at=now()
  where batch_id=p_batch_id and status in ('queued','discovering','acquiring','extracting');
  get diagnostics v_items=row_count;
  update pipeline.layer2_run_batches
  set status='cancelled',cancellation_reason=coalesce(nullif(p_reason,''),'operator_cancelled'),completed_at=now(),heartbeat_at=now(),updated_at=now()
  where id=p_batch_id and status in ('queued','running','partial');
  return jsonb_build_object('batch_id',p_batch_id,'cancelled_items',v_items,'reason',coalesce(nullif(p_reason,''),'operator_cancelled'));
end $$;

create or replace function public.layer2_run_batch_recover_stuck(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_stale integer; v_requeued integer;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  select coalesce(ep.stale_after_minutes,30) into v_stale
  from pipeline.layer2_run_batches b
  join pipeline.layer2_execution_policies ep on ep.profile_id=b.profile_id
  where b.id=p_batch_id;
  if v_stale is null then raise exception 'batch not found'; end if;
  if not exists(
    select 1 from pipeline.layer2_run_batches
    where id=p_batch_id and status='running'
      and coalesce(heartbeat_at,updated_at,started_at,created_at) < now()-make_interval(mins=>v_stale)
  ) then raise exception 'batch is not stale'; end if;
  update pipeline.layer2_run_items
  set status='queued',failure_class='stale_recovery',blocker=null,completed_at=null,updated_at=now()
  where batch_id=p_batch_id and status in ('discovering','acquiring','extracting');
  get diagnostics v_requeued=row_count;
  update pipeline.layer2_run_batches
  set status='queued',heartbeat_at=null,completed_at=null,updated_at=now()
  where id=p_batch_id;
  return jsonb_build_object('batch_id',p_batch_id,'requeued_items',v_requeued,'stale_after_minutes',v_stale);
end $$;

revoke all on function public.layer2_run_batch_heartbeat(uuid) from public,anon,authenticated;
revoke all on function public.layer2_run_batch_cancel(uuid,text) from public,anon,authenticated;
revoke all on function public.layer2_run_batch_recover_stuck(uuid) from public,anon,authenticated;
grant execute on function public.layer2_run_batch_heartbeat(uuid) to service_role;
grant execute on function public.layer2_run_batch_cancel(uuid,text) to service_role;
grant execute on function public.layer2_run_batch_recover_stuck(uuid) to service_role;

create or replace function security.admin_layer2_ops_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path='pg_catalog','security','pipeline','catalogue','ref','public'
as $$
declare v_rank integer; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  if p_operation='layer2_ops_overview' then
    select jsonb_build_object(
      'health',jsonb_build_object(
        'enabled_profiles',(select count(*) from pipeline.layer2_source_profiles where enabled and not paused and domain in ('course_facts','scholarship')),
        'active_runs',(select count(*) from pipeline.layer2_run_batches where status in ('queued','running')),
        'stuck_runs',(select count(*) from pipeline.layer2_run_batches b join pipeline.layer2_execution_policies ep on ep.profile_id=b.profile_id where b.status='running' and coalesce(b.heartbeat_at,b.updated_at,b.started_at,b.created_at)<now()-make_interval(mins=>coalesce(ep.stale_after_minutes,30))),
        'layer3_candidates',(select count(*) from pipeline.layer2_run_items where status='layer3_required'),
        'blocked_items',(select count(*) from pipeline.layer2_run_items where status='blocked')
      ),
      'sources',(select coalesce(jsonb_agg(jsonb_build_object(
        'profile_id',p.id,'profile_key',p.profile_key,'country_code',c.iso_alpha2,
        'data_type',case when p.domain='course_facts' then 'Courses' else 'Scholarships' end,
        'source_label',s.label,'provider_name',cp.canonical_name,'enabled',p.enabled,'paused',p.paused,
        'schedule_mode',coalesce(ep.schedule_mode,'manual'),'batch_size',coalesce(ep.batch_size,10),
        'max_concurrency',coalesce(ep.max_concurrency,1),'stale_after_minutes',coalesce(ep.stale_after_minutes,30),
        'routing_strategy',coalesce(ep.routing_strategy,'direct_then_best_value'),
        'max_paid_attempts_per_entity',coalesce(ep.max_paid_attempts_per_entity,2),
        'next_run_at',ep.next_run_at,'last_run_at',ep.last_run_at,'current_version_id',p.current_version_id,
        'current_version',pv.version_no,'freshness_sla_hours',p.freshness_sla_hours,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,
        'total_catalogue_count',case when p.domain='course_facts' and s.provider_id is not null then (select count(*) from catalogue.courses cc where cc.provider_id=s.provider_id) when p.domain='scholarship' then (select count(*) from pipeline.scholarship_source_records) else 0 end,
        'queueable_count',case when p.domain='course_facts' and s.provider_id is not null then (select count(*) from catalogue.courses cc where cc.provider_id=s.provider_id and (nullif(cc.course_url,'') is not null or exists(select 1 from pipeline.layer2_course_discovery_candidates dc where dc.course_id=cc.id and dc.source_profile_version_id=p.current_version_id and dc.selected and nullif(dc.discovered_url,'') is not null))) when p.domain='scholarship' then (select count(*) from pipeline.scholarship_source_records) else 0 end,
        'selected_discovery_count',case when p.domain='course_facts' then (select count(distinct dc.course_id) from pipeline.layer2_course_discovery_candidates dc where dc.source_profile_version_id=p.current_version_id and dc.selected) else 0 end
      ) order by c.iso_alpha2,case when p.domain='course_facts' then 1 else 2 end,coalesce(cp.canonical_name,s.label)),'[]'::jsonb)
      from pipeline.layer2_source_profiles p join pipeline.sources s on s.id=p.source_id left join ref.countries c on c.id=s.country_id left join catalogue.providers cp on cp.id=s.provider_id left join pipeline.layer2_execution_policies ep on ep.profile_id=p.id left join pipeline.layer2_source_profile_versions pv on pv.id=p.current_version_id where p.domain in ('course_facts','scholarship')),
      'providers',(select coalesce(jsonb_agg(jsonb_build_object(
        'id',ap.id,'provider_key',ap.provider_key,'display_name',ap.display_name,'enabled',ap.enabled,
        'credential_configured',ap.vault_secret_id is not null,'priority',ap.priority,'rate_limit_per_minute',ap.rate_limit_per_minute,
        'concurrency',ap.concurrency,'last_tested_at',ap.last_tested_at,'last_test_status',ap.last_test_status,
        'billing_config',security.layer2_provider_sanitise_json(ap.billing_config),
        'attempts',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id),
        'successes',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.status in ('completed','success','succeeded')),
        'failures',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.status in ('failed','error','blocked')),
        'http_429',(select count(*) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.response_http_status=429),
        'avg_response_ms',(select round(avg(extract(epoch from (a.completed_at-a.started_at))*1000)) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.completed_at is not null and a.started_at is not null),
        'last_success_at',(select max(a.completed_at) from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id and a.status in ('completed','success','succeeded')),
        'recent_failure_streak',(select count(*) from (select a.status from pipeline.layer2_provider_attempts a where a.acquisition_provider_id=ap.id order by a.created_at desc limit 10) z where z.status in ('failed','error','blocked'))
      ) order by ap.priority,ap.display_name),'[]'::jsonb) from pipeline.layer2_acquisition_providers ap where ap.enabled=true),
      'recent_runs',(select coalesce(jsonb_agg(jsonb_build_object(
        'id',b.id,'profile_id',b.profile_id,'trigger_type',b.trigger_type,'status',b.status,'target_count',b.target_count,
        'processed_count',b.processed_count,'resolved_l2_count',b.resolved_l2_count,'escalated_l3_count',b.escalated_l3_count,
        'blocked_count',b.blocked_count,'vendor_units',b.vendor_units,'vendor_cost_usd',b.vendor_cost_usd,'created_at',b.created_at,
        'started_at',b.started_at,'completed_at',b.completed_at,'heartbeat_at',b.heartbeat_at,'updated_at',b.updated_at,
        'runtime_seconds',case when b.started_at is null then null else round(extract(epoch from (coalesce(b.completed_at,now())-b.started_at))) end,
        'progress_percent',case when b.target_count>0 then round((100.0*b.processed_count/b.target_count)::numeric,1) else 0 end
      ) order by b.created_at desc),'[]'::jsonb) from (select * from pipeline.layer2_run_batches order by created_at desc limit 20)b),
      'outcomes',(select jsonb_build_object(
        'queued',count(*) filter(where status='queued'),'processing',count(*) filter(where status in ('discovering','acquiring','extracting')),
        'enriched',count(*) filter(where status='resolved_l2'),'unresolved',count(*) filter(where status='layer3_required'),
        'failed',count(*) filter(where status='blocked'),'deferred',count(*) filter(where status='cancelled'),
        'fields_targeted',coalesce(sum(fields_targeted),0),'fields_resolved',coalesce(sum(fields_resolved),0)
      ) from pipeline.layer2_run_items),
      'evidence_summary',(select jsonb_build_object('count',count(*),'unreviewed',count(*) filter(where review_state='unreviewed'),'retained_until_365',count(*) filter(where retention_class='standard_365'),'held',count(*) filter(where retention_class='hold'),'latest',max(captured_at)) from pipeline.evidence_artifacts where coalesce(metadata->>'layer','')='2'),
      'scope_summary',jsonb_build_object(
        'authorised_country_codes',jsonb_build_array('AU'),
        'nz_layer2_course_status','DEFERRED — source qualification/onboarding required',
        'course_catalogue_total',(select count(*) from catalogue.courses cc join catalogue.providers cp2 on cp2.id=cc.provider_id where cp2.canonical_name in ('Federation University Australia','RMIT University (RMIT)','The University of Queensland')),
        'course_queueable_total',(select count(*) from catalogue.courses cc where exists(select 1 from pipeline.layer2_source_profiles p2 join pipeline.sources s2 on s2.id=p2.source_id where p2.domain='course_facts' and p2.enabled and not p2.paused and s2.provider_id=cc.provider_id) and (nullif(cc.course_url,'') is not null or exists(select 1 from pipeline.layer2_course_discovery_candidates dc where dc.course_id=cc.id and dc.selected and nullif(dc.discovered_url,'') is not null)))
      )
    ) into v_result;
    return v_result;
  end if;
  if p_operation='layer2_ops_run_detail' then
    return (select jsonb_build_object('run',to_jsonb(b),'items',(select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at),'[]'::jsonb) from pipeline.layer2_run_items i where i.batch_id=b.id)) from pipeline.layer2_run_batches b where b.id=nullif(p_args->>'id','')::uuid);
  end if;
  raise exception 'unsupported layer2 ops read operation: %',p_operation using errcode='22023';
end $$;

revoke all on function security.admin_layer2_ops_read(text,jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer2_ops_read(text,jsonb) to authenticated,service_role;
