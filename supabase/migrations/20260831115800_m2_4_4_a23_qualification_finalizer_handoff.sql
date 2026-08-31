-- M2.4.4 A23 — complete background qualification finalisation and governed cross-layer handoff.
-- CF-CHG-20260830-048
-- Layer 2 owns deterministic source-pattern controls and queue creation only.
-- Layer 3 AI execution remains separately authenticated/role-gated and is NOT invoked here.

alter table pipeline.layer2_execution_policy
  add column if not exists qualification_finalizer_run_limit integer not null default 2,
  add column if not exists qualification_pattern_provider_limit integer not null default 3;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conname='layer2_execution_policy_qualification_finalizer_run_limit_check'
  ) then
    alter table pipeline.layer2_execution_policy
      add constraint layer2_execution_policy_qualification_finalizer_run_limit_check
      check (qualification_finalizer_run_limit between 1 and 10);
  end if;
  if not exists(
    select 1 from pg_constraint
    where conname='layer2_execution_policy_qualification_pattern_provider_limit_check'
  ) then
    alter table pipeline.layer2_execution_policy
      add constraint layer2_execution_policy_qualification_pattern_provider_limit_check
      check (qualification_pattern_provider_limit between 1 and 5);
  end if;
end $$;

create or replace function public.layer2_execution_policy_service(
  p_actor uuid,p_action text,p_patch jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','security'
as $function$
declare
 v_rank integer:=0;
 v_policy pipeline.layer2_execution_policy%rowtype;
 v_firecrawl pipeline.layer2_acquisition_providers%rowtype;
 v_budget jsonb:='{}'::jsonb;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select coalesce(max(r.rank),0) into v_rank
 from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

 if p_action='update' then
   if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
   update pipeline.layer2_execution_policy p set
     qualification_provider_wave_size=least(greatest(coalesce(nullif(p_patch->>'qualification_provider_wave_size','')::integer,p.qualification_provider_wave_size),1),500),
     qualification_provider_wave_max=least(greatest(coalesce(nullif(p_patch->>'qualification_provider_wave_max','')::integer,p.qualification_provider_wave_max),1),500),
     qualification_sample_size=least(greatest(coalesce(nullif(p_patch->>'qualification_sample_size','')::integer,p.qualification_sample_size),1),50),
     qualification_retry_hours=least(greatest(coalesce(nullif(p_patch->>'qualification_retry_hours','')::integer,p.qualification_retry_hours),1),2160),
     qualification_finalizer_run_limit=least(greatest(coalesce(nullif(p_patch->>'qualification_finalizer_run_limit','')::integer,p.qualification_finalizer_run_limit),1),10),
     qualification_pattern_provider_limit=least(greatest(coalesce(nullif(p_patch->>'qualification_pattern_provider_limit','')::integer,p.qualification_pattern_provider_limit),1),5),
     production_target_wave_size=least(greatest(coalesce(nullif(p_patch->>'production_target_wave_size','')::integer,p.production_target_wave_size),1),5000),
     production_max_wave_size=least(greatest(coalesce(nullif(p_patch->>'production_max_wave_size','')::integer,p.production_max_wave_size),1),5000),
     schedule_remaining=coalesce((p_patch->>'schedule_remaining')::boolean,p.schedule_remaining),
     route_mode=case when p_patch->>'route_mode' in('scraper_first','managed') then p_patch->>'route_mode' else p.route_mode end,
     updated_by=p_actor,updated_at=now(),change_control_ref='CF-CHG-20260830-048'
   where p.policy_key='default';
 end if;

 select * into v_policy from pipeline.layer2_execution_policy where policy_key='default';
 select * into v_firecrawl from pipeline.layer2_acquisition_providers where provider_key='firecrawl' limit 1;
 if v_firecrawl.id is not null then
   v_budget:=security.layer2_provider_budget_status(
     v_firecrawl.id,
     coalesce(nullif(v_firecrawl.request_template->>'fixed_credit_units','')::numeric,1)
   );
 end if;

 return jsonb_build_object(
  'policy',to_jsonb(v_policy)-'updated_by',
  'firecrawl',jsonb_build_object(
    'provider_id',v_firecrawl.id,'provider_key',v_firecrawl.provider_key,'display_name',v_firecrawl.display_name,
    'enabled',v_firecrawl.enabled,'credential_configured',v_firecrawl.vault_secret_id is not null,
    'rate_limit_per_minute',v_firecrawl.rate_limit_per_minute,'concurrency',v_firecrawl.concurrency,
    'timeout_seconds',v_firecrawl.timeout_seconds,'billing_config',v_firecrawl.billing_config,
    'budget_status',v_budget
  ),
  'qualification_note','Course samples are identity checks against one acquired Provider seed page; they are not separate production scrapes.',
  'finalizer_note','Deterministic 3-of-3 source-pattern controls are finalised in policy-bounded background slices; unresolved outcomes are queued to governed Layer 3 or Layer 4 without autonomous Layer 3 AI execution.',
  'production_note','Production Course waves are queued in the background and clamped by the Firecrawl entitlement/reserve.'
 );
end
$function$;

create or replace function public.layer2_scale_cross_layer_handoff(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','catalogue','ref'
as $function$
declare
  v_l3 integer:=0;
  v_l4 integer:=0;
  v_l3_profile uuid;
  v_l3_ready boolean:=false;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if not exists(select 1 from pipeline.layer2_scale_qualification_runs where id=p_run_id) then
    raise exception 'qualification run not found' using errcode='22023';
  end if;

  select p.id into v_l3_profile
  from pipeline.layer3_model_profiles p
  where p.code='openrouter-source-pattern-v1'
    and p.enabled and not p.paused
    and coalesce((p.quality_benchmark->>'pass')::boolean,false)
  limit 1;
  v_l3_ready:=v_l3_profile is not null;

  with targets as (
    select distinct
      qi.provider_id,
      qi.evidence_id,
      nullif(qi.outcome->>'qualification_source_id','')::uuid source_id,
      nullif(qi.outcome->>'qualification_profile_id','')::uuid source_profile_id,
      co.iso_alpha2::text country_code,
      qr.requested_by,
      'A23-SOURCE-PATTERN:'||p_run_id::text||':'||qi.provider_id::text revalidation_ref
    from pipeline.layer2_scale_qualification_items qi
    join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
    join ref.countries co on co.id=qr.country_id
    where qi.run_id=p_run_id
      and qi.status='layer3_required'
      and qi.evidence_id is not null
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      evidence_id,layer3_profile_id,revalidation_ref,reason,trigger_type,status,
      requested_by,change_control_ref,schedule_error
    )
    select
      3,t.country_code,t.source_id,t.source_profile_id,'provider',t.provider_id,
      t.evidence_id,v_l3_profile,t.revalidation_ref,
      'Interpret first-party Course discovery/source pattern from governed Layer 2 Evidence. Do not infer or change Layer 1 identity. Return any candidate to Layer 2 strict identity control before promotion.',
      'manual_governed',case when v_l3_ready then 'queued' else 'blocked' end,
      t.requested_by,'CF-CHG-20260830-048',
      case when v_l3_ready then null else 'source_pattern_profile_not_executable' end
    from targets t
    where not exists(
      select 1 from pipeline.refresh_requests rr
      where rr.revalidation_ref=t.revalidation_ref
    )
    returning 1
  )
  select count(*) into v_l3 from ins;

  with targets as (
    select distinct
      qi.provider_id,
      co.iso_alpha2::text country_code,
      qr.requested_by,
      coalesce(qi.outcome->>'reason',
        case qi.status when 'blocked' then 'qualification_blocked'
                       when 'layer4_required' then 'layer4_resolution_required'
                       else 'missing_or_invalid_first_party_source_seed' end) reason,
      'A23-SOURCE-RESOLUTION:'||p_run_id::text||':'||qi.provider_id::text revalidation_ref
    from pipeline.layer2_scale_qualification_items qi
    join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
    join ref.countries co on co.id=qr.country_id
    where qi.run_id=p_run_id
      and qi.status in ('source_limited','blocked','layer4_required')
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,entity_type,entity_id,revalidation_ref,
      reason,trigger_type,status,requested_by,change_control_ref,schedule_error
    )
    select
      4,t.country_code,'provider',t.provider_id,t.revalidation_ref,
      'Resolve/verify the first-party Provider Course source before Layer 2 qualification can continue. Reason: '||t.reason,
      'manual_governed','queued',t.requested_by,'CF-CHG-20260830-048',
      'provider_source_resolution_required'
    from targets t
    where not exists(
      select 1 from pipeline.refresh_requests rr
      where rr.revalidation_ref=t.revalidation_ref
    )
    returning 1
  )
  select count(*) into v_l4 from ins;

  update pipeline.layer2_scale_qualification_runs
  set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
    'cross_layer_handoff_at',now(),
    'layer3_source_pattern_requests_created',v_l3,
    'layer3_profile_id',v_l3_profile,
    'layer3_execution_state',case when v_l3_ready then 'queued_for_governed_operator_execution' else 'blocked_profile_not_executable' end,
    'layer4_source_resolution_requests_created',v_l4,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  )
  where id=p_run_id;

  return jsonb_build_object(
    'ok',true,'run_id',p_run_id,
    'layer3_source_pattern_requests_created',v_l3,
    'layer3_profile_id',v_l3_profile,
    'layer3_execution_state',case when v_l3_ready then 'queued_for_governed_operator_execution' else 'blocked_profile_not_executable' end,
    'layer4_source_resolution_requests_created',v_l4,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end
$function$;

create or replace function security.layer2_qualification_finalizer_tick_impl()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','security','public','pipeline'
as $function$
declare
  v_policy pipeline.layer2_execution_policy%rowtype;
  v_run_limit integer:=2;
  v_pattern_limit integer:=3;
  r record;
  v_dispatch jsonb;
  v_reconcile jsonb;
  v_handoff jsonb;
  v_pending_dispatch integer;
  v_pending_control integer;
  v_profile_qualified integer;
  v_l3 integer;
  v_l4 integer;
  v_blocked integer;
  v_complete boolean;
  v_processed integer:=0;
  v_results jsonb:='[]'::jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_policy
  from pipeline.layer2_execution_policy
  where policy_key='default' and enabled;
  if found then
    v_run_limit:=least(greatest(coalesce(v_policy.qualification_finalizer_run_limit,2),1),10);
    v_pattern_limit:=least(greatest(coalesce(v_policy.qualification_pattern_provider_limit,3),1),5);
  end if;

  for r in
    select q.id
    from pipeline.layer2_scale_qualification_runs q
    where q.status in ('completed','partial')
      and not coalesce((q.result_summary->>'qualification_finalization_complete')::boolean,false)
      and exists(
        select 1 from pipeline.layer2_scale_qualification_items qi
        where qi.run_id=q.id
          and qi.status in ('source_pattern_candidate','layer3_required','source_limited','blocked','layer4_required')
      )
    order by q.completed_at nulls last,q.created_at
    limit v_run_limit
    for update skip locked
  loop
    begin
      v_dispatch:=security.layer2_scale_pattern_dispatch(r.id,v_pattern_limit);
      v_reconcile:=public.layer2_scale_pattern_reconcile(r.id);
      v_handoff:=public.layer2_scale_cross_layer_handoff(r.id);

      select
        count(distinct provider_id) filter(
          where status='source_pattern_candidate'
            and coalesce(outcome->>'pattern_dispatch_version_id','')=''
        ),
        count(distinct provider_id) filter(
          where status='source_pattern_candidate'
            and coalesce(outcome->>'pattern_dispatch_version_id','')<>''
        ),
        count(distinct provider_id) filter(where status='profile_qualified'),
        count(distinct provider_id) filter(where status='layer3_required'),
        count(distinct provider_id) filter(where status in ('source_limited','layer4_required')),
        count(distinct provider_id) filter(where status='blocked')
      into v_pending_dispatch,v_pending_control,v_profile_qualified,v_l3,v_l4,v_blocked
      from pipeline.layer2_scale_qualification_items
      where run_id=r.id;

      v_complete:=coalesce(v_pending_dispatch,0)=0 and coalesce(v_pending_control,0)=0;

      update pipeline.layer2_scale_qualification_runs
      set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
        'qualification_finalizer_at',now(),
        'qualification_finalization_complete',v_complete,
        'pending_pattern_dispatch_providers',coalesce(v_pending_dispatch,0),
        'pending_pattern_control_providers',coalesce(v_pending_control,0),
        'profile_qualified_providers',coalesce(v_profile_qualified,0),
        'layer3_required_providers',coalesce(v_l3,0),
        'layer4_required_or_source_limited_providers',coalesce(v_l4,0),
        'blocked_providers',coalesce(v_blocked,0),
        'finalizer_run_limit',v_run_limit,
        'pattern_provider_limit',v_pattern_limit,
        'canonical_mutation_authorised',false,
        'search_mutation_authorised',false,
        'publication_mutation_authorised',false
      )
      where id=r.id;

      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'run_id',r.id,'dispatch',v_dispatch,'reconcile',v_reconcile,'handoff',v_handoff,
        'finalization_complete',v_complete,
        'pending_pattern_dispatch_providers',coalesce(v_pending_dispatch,0),
        'pending_pattern_control_providers',coalesce(v_pending_control,0)
      ));
      v_processed:=v_processed+1;
    exception when others then
      v_results:=v_results||jsonb_build_array(jsonb_build_object('run_id',r.id,'error',sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'ok',true,'processed_runs',v_processed,
    'run_limit',v_run_limit,'pattern_provider_limit',v_pattern_limit,
    'results',v_results,'ran_at',now()
  );
end
$function$;

revoke all on function public.layer2_scale_cross_layer_handoff(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scale_cross_layer_handoff(uuid) to service_role;
revoke all on function security.layer2_qualification_finalizer_tick_impl() from public,anon,authenticated;
grant execute on function security.layer2_qualification_finalizer_tick_impl() to service_role;

do $$
begin
  if exists(select 1 from cron.job where jobname='coursefinder-layer2-qualification-finalizer') then
    perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-layer2-qualification-finalizer' limit 1));
  end if;
  perform cron.schedule(
    'coursefinder-layer2-qualification-finalizer',
    '2-59/5 * * * *',
    'select security.layer2_qualification_finalizer_tick_impl();'
  );
end $$;
