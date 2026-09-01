-- CF-CHG-20260901-053
-- M2.5 Layer 2 qualification finalizer fairness and historical wave classification.
-- Dispatchable deterministic Provider-pattern work is prioritised over already-dispatched
-- pending controls. Historical acceptance-isolation audit rows remain retained.
-- No canonical, Search, Publication, Layer 3 execution, Layer 4 authority or quota expansion.

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
  v_before_pending_dispatch integer;
  v_before_pending_control integer;
  v_selection_class text;
  v_progressed boolean;
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
    select q.id,
      case
        when exists(
          select 1 from pipeline.layer2_scale_qualification_items qi
          where qi.run_id=q.id
            and qi.status='source_pattern_candidate'
            and coalesce(qi.outcome->>'pattern_dispatch_version_id','')=''
        ) then 'pending_dispatch'
        when exists(
          select 1 from pipeline.layer2_scale_qualification_items qi
          where qi.run_id=q.id
            and qi.status='source_pattern_candidate'
            and coalesce(qi.outcome->>'pattern_dispatch_version_id','')<>''
        ) then 'pending_control'
        else 'handoff_only'
      end selection_class
    from pipeline.layer2_scale_qualification_runs q
    where q.status in ('completed','partial')
      and not coalesce((q.result_summary->>'qualification_finalization_complete')::boolean,false)
      and exists(
        select 1 from pipeline.layer2_scale_qualification_items qi
        where qi.run_id=q.id
          and qi.status in ('source_pattern_candidate','layer3_required','source_limited','blocked','layer4_required')
      )
    order by
      case
        when exists(
          select 1 from pipeline.layer2_scale_qualification_items qi
          where qi.run_id=q.id
            and qi.status='source_pattern_candidate'
            and coalesce(qi.outcome->>'pattern_dispatch_version_id','')=''
        ) then 0
        when exists(
          select 1 from pipeline.layer2_scale_qualification_items qi
          where qi.run_id=q.id
            and qi.status='source_pattern_candidate'
            and coalesce(qi.outcome->>'pattern_dispatch_version_id','')<>''
        ) then 1
        else 2
      end,
      coalesce(nullif(q.result_summary->>'qualification_finalizer_at','')::timestamptz,'-infinity'::timestamptz),
      q.completed_at nulls last,q.created_at
    limit v_run_limit
    for update skip locked
  loop
    begin
      v_selection_class:=r.selection_class;
      select
        count(distinct provider_id) filter(
          where status='source_pattern_candidate'
            and coalesce(outcome->>'pattern_dispatch_version_id','')=''
        ),
        count(distinct provider_id) filter(
          where status='source_pattern_candidate'
            and coalesce(outcome->>'pattern_dispatch_version_id','')<>''
        )
      into v_before_pending_dispatch,v_before_pending_control
      from pipeline.layer2_scale_qualification_items
      where run_id=r.id;

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
      v_progressed:=coalesce(v_pending_dispatch,0)<coalesce(v_before_pending_dispatch,0)
        or coalesce(v_pending_control,0)<coalesce(v_before_pending_control,0);

      update pipeline.layer2_scale_qualification_runs
      set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
        'qualification_finalizer_at',now(),
        'qualification_finalizer_selection_class',v_selection_class,
        'qualification_finalizer_progressed',v_progressed,
        'qualification_finalizer_no_progress_count',
          case when v_progressed then 0
               else coalesce(nullif(result_summary->>'qualification_finalizer_no_progress_count','')::integer,0)+1 end,
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
        'run_id',r.id,'selection_class',v_selection_class,
        'dispatch',v_dispatch,'reconcile',v_reconcile,'handoff',v_handoff,
        'progressed',v_progressed,'finalization_complete',v_complete,
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

revoke all on function security.layer2_qualification_finalizer_tick_impl() from public,anon,authenticated;
grant execute on function security.layer2_qualification_finalizer_tick_impl() to service_role;

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
    'failed_items',greatest(r.failed_items-coalesce(classify.acceptance_isolation_items,0),0),
    'recorded_failed_items',r.failed_items,
    'rescheduled_items',coalesce(classify.acceptance_isolation_items,0),
    'acceptance_isolation_items',coalesce(classify.acceptance_isolation_items,0),
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
      count(*) filter(
        where wi.status='failed'
          and (
            lower(coalesce(wi.blocker,'')) like '%acceptance%isolation%'
            or exists(
              select 1
              from pipeline.layer2_run_items ai
              where ai.batch_id=wi.batch_id
                and lower(coalesce(ai.blocker,'')) like '%acceptance isolation%'
            )
          )
      )::int acceptance_isolation_items
    from pipeline.layer2_scope_wave_items wi
    where wi.request_id=r.id
  ) classify on true
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
