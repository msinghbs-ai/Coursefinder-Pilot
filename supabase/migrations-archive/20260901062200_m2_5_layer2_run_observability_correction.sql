-- CF-CHG-20260901-052
-- M2.5 Layer 2 run observability correction.
-- Preserve terminal child Job/Evidence lineage and distinguish qualification retry/no-op from newly scheduled work.
-- No canonical, Search, Publication, quota or authority expansion.

CREATE OR REPLACE FUNCTION public.layer2_background_scope_service(p_actor uuid, p_action text, p_country_code text, p_scope_type text DEFAULT 'country'::text, p_scope_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security'
AS $function$
declare
 v_rank integer:=0;
 v_policy pipeline.layer2_execution_policy%rowtype;
 v_firecrawl pipeline.layer2_acquisition_providers%rowtype;
 v_budget jsonb:='{}'::jsonb;
 v_preview jsonb;
 v_qual jsonb;
 v_wave jsonb;
 v_remaining integer:=0;
 v_reserve integer:=0;
 v_usable integer:=0;
 v_accepted integer:=0;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 select * into v_policy from pipeline.layer2_execution_policy where policy_key='default' and enabled;
 if not found then raise exception 'Layer 2 execution policy missing' using errcode='55000'; end if;
 select * into v_firecrawl from pipeline.layer2_acquisition_providers where provider_key='firecrawl' limit 1;
 if v_firecrawl.id is null or not v_firecrawl.enabled or v_firecrawl.vault_secret_id is null then
   raise exception 'Firecrawl is not ready for Layer 2 execution' using errcode='55000';
 end if;
 v_budget:=security.layer2_provider_budget_status(v_firecrawl.id,coalesce(nullif(v_firecrawl.request_template->>'fixed_credit_units','')::numeric,1));
 v_remaining:=greatest(coalesce((v_budget->>'remaining_units')::integer,0),0);
 v_reserve:=greatest(coalesce((v_budget->>'stop_at_remaining_units')::integer,0),0);
 v_usable:=greatest(v_remaining-v_reserve,0);
 v_accepted:=least(v_policy.production_target_wave_size,v_policy.production_max_wave_size,v_usable);

 v_preview:=public.layer2_scale_scope_service(p_actor,'preview',p_country_code,p_scope_type,p_scope_id,0,0);
 v_preview:=v_preview||jsonb_build_object(
   'execution_policy',to_jsonb(v_policy)-'updated_by',
   'firecrawl_budget',v_budget,
   'firecrawl',jsonb_build_object(
      'display_name',v_firecrawl.display_name,'provider_key',v_firecrawl.provider_key,
      'rate_limit_per_minute',v_firecrawl.rate_limit_per_minute,'concurrency',v_firecrawl.concurrency,
      'monthly_limit',v_firecrawl.billing_config->'monthly_vendor_units_limit',
      'reserve_units',v_reserve,'usable_remaining_units',v_usable
   ),
   'production_accepted_wave_size',v_accepted,
   'qualification_sample_note','The per-Provider Course sample is an identity check against one acquired Provider seed page, not one scrape per sampled Course.',
   'observed_at',now()
 );

 if p_action='preview' then return v_preview; end if;
 if p_action<>'start' then raise exception 'unsupported action' using errcode='22023'; end if;

 if coalesce((v_preview->>'qualification_required_count')::integer,0)>0 then
   v_qual:=public.layer2_scale_scope_service(p_actor,'qualify_wave',p_country_code,p_scope_type,p_scope_id,0,0);
   if coalesce(v_qual->>'status','')='nothing_to_qualify' then
     return v_preview||jsonb_build_object(
       'ok',true,'status','qualification_waiting',
       'qualification',v_qual,
       'reason',format('No Providers are eligible for a new qualification batch inside the current %s-hour retry window.',v_policy.qualification_retry_hours),
       'next_step','No new production Course wave was created by this request. Existing qualification outcomes and retry/deferred states remain in force.'
     );
   end if;
   return v_preview||jsonb_build_object(
     'ok',true,'status','background_qualification_scheduled',
     'qualification',v_qual,
     'next_step','Qualification runs in background; production Course waves auto-start after the current scope is exhausted or deferred.'
   );
 end if;

 if upper(p_country_code)='NZ' then
   return v_preview||jsonb_build_object('ok',true,'status','production_deferred','reason','NZ Layer 2 Course enrichment remains deferred');
 end if;
 if v_accepted<1 then
   return v_preview||jsonb_build_object('ok',false,'status','budget_blocked','reason','Firecrawl monthly safety reserve reached');
 end if;
 if coalesce((v_preview->>'queueable_count')::integer,0)<1 then
   return v_preview||jsonb_build_object('ok',true,'status','nothing_queueable');
 end if;

 v_wave:=public.layer2_wave_scope_service(
   p_actor,'start',p_country_code,p_scope_type,p_scope_id,v_accepted,v_policy.schedule_remaining,v_policy.route_mode,null
 );
 return v_preview||jsonb_build_object(
   'ok',true,'status','background_enrichment_started','production',v_wave,
   'next_step','Production Course waves are scheduled in the background.'
 );
end $function$
;

revoke all on function public.layer2_background_scope_service(uuid,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_background_scope_service(uuid,text,text,text,uuid) to service_role;

create or replace function security.admin_layer2_parent_runs(p_limit integer default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','pipeline','auth'
as $$
declare v_rank integer:=0; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  with recent as (
    select r.*
    from pipeline.layer2_scope_wave_requests r
    order by r.created_at desc
    limit greatest(1,least(coalesce(p_limit,10),50))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'parent_run_id',coalesce(r.metadata->>'parent_run_id',r.id::text),
    'scope_wave_request_id',r.id,
    'status',r.status,
    'country_code',r.country_code,
    'scope_type',r.scope_type,
    'scope_id',r.scope_id,
    'route_mode',r.route_mode,
    'total_items',r.total_items,
    'dispatched_items',r.dispatched_items,
    'completed_items',r.completed_items,
    'failed_items',r.failed_items,
    'scheduled_remainder',greatest(r.total_items-r.completed_items-r.failed_items,0),
    'last_wave_at',r.last_wave_at,
    'next_wave_not_before',r.next_wave_not_before,
    'created_at',r.created_at,
    'updated_at',r.updated_at,
    'child_batches',coalesce(items.child_batches,0),
    'active_batches',coalesce(items.active_batches,0),
    'cancelled_batches',coalesce(hist.cancelled_batches,0),
    'processed_items',r.completed_items+r.failed_items,
    'resolved_l2',coalesce(items.resolved_l2,0),
    'escalated_l3',coalesce(items.escalated_l3,0),
    'blocked',coalesce(items.blocked,0),
    'vendor_units',coalesce(items.vendor_units,0),
    'vendor_cost_usd',coalesce(items.vendor_cost_usd,0),
    'heartbeat_at',items.heartbeat_at,
    'historical_cancelled_processed',coalesce(hist.historical_cancelled_processed,0),
    'child_jobs',coalesce(items.child_jobs,0),
    'evidence_count',coalesce(ev.evidence_count,0),
    'latest_evidence_at',ev.latest_evidence_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_result
  from recent r
  left join lateral (
    select
      count(distinct wi.batch_id) filter(where wi.batch_id is not null)::int child_batches,
      count(distinct b.id) filter(where b.status in('queued','running'))::int active_batches,
      count(*) filter(where i.status='resolved_l2')::int resolved_l2,
      count(*) filter(where i.status='layer3_required')::int escalated_l3,
      count(*) filter(where i.status='blocked')::int blocked,
      coalesce(sum(i.vendor_units),0) vendor_units,
      coalesce(sum(i.vendor_cost_usd),0) vendor_cost_usd,
      max(b.heartbeat_at) heartbeat_at,
      count(distinct i.job_id) filter(where i.job_id is not null)::int child_jobs
    from pipeline.layer2_scope_wave_items wi
    left join pipeline.layer2_run_batches b on b.id=wi.batch_id
    left join pipeline.layer2_run_items i
      on i.batch_id=wi.batch_id and i.entity_id=wi.course_id
    where wi.request_id=r.id
      and wi.status in('dispatched','completed','failed')
  ) items on true
  left join lateral (
    select
      count(distinct e.id)::int evidence_count,
      max(e.captured_at) latest_evidence_at
    from pipeline.layer2_scope_wave_items wi
    join pipeline.layer2_run_items i
      on i.batch_id=wi.batch_id and i.entity_id=wi.course_id
    join pipeline.evidence_artifacts e on e.job_id=i.job_id
    where wi.request_id=r.id
      and wi.status in('dispatched','completed','failed')
  ) ev on true
  left join lateral (
    select
      count(*) filter(where b.status='cancelled')::int cancelled_batches,
      coalesce(sum(b.processed_count) filter(where b.status='cancelled'),0)::int historical_cancelled_processed
    from pipeline.layer2_run_batches b
    where b.policy_snapshot->>'scope_wave_request_id'=r.id::text
  ) hist on true;

  return v_result;
end $$;

revoke all on function security.admin_layer2_parent_runs(integer) from public,anon;
grant execute on function security.admin_layer2_parent_runs(integer) to authenticated,service_role;
