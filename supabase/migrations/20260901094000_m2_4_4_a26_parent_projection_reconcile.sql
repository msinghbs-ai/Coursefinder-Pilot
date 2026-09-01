-- CF-CHG-20260830-048
-- M2.4.4 A26: eliminate fan-out in parent-run reconciliation and retain
-- cancelled/retry history as separately labelled lineage.

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
    'scheduled_remainder',greatest(r.total_items-r.dispatched_items,0),
    'last_wave_at',r.last_wave_at,
    'next_wave_not_before',r.next_wave_not_before,
    'created_at',r.created_at,
    'updated_at',r.updated_at,
    'child_batches',coalesce(bs.child_batches,0),
    'active_batches',coalesce(bs.active_batches,0),
    'cancelled_batches',coalesce(bs.cancelled_batches,0),
    'processed_items',coalesce(bs.processed_items,0),
    'resolved_l2',coalesce(bs.resolved_l2,0),
    'escalated_l3',coalesce(bs.escalated_l3,0),
    'blocked',coalesce(bs.blocked,0),
    'vendor_units',coalesce(bs.vendor_units,0),
    'vendor_cost_usd',coalesce(bs.vendor_cost_usd,0),
    'heartbeat_at',bs.heartbeat_at,
    'historical_cancelled_processed',coalesce(bs.historical_cancelled_processed,0),
    'child_jobs',coalesce(js.child_jobs,0),
    'evidence_count',coalesce(js.evidence_count,0),
    'latest_evidence_at',js.latest_evidence_at
  ) order by r.created_at desc),'[]'::jsonb)
  into v_result
  from recent r
  left join lateral (
    select
      count(*)::int child_batches,
      count(*) filter(where b.status in('queued','running'))::int active_batches,
      count(*) filter(where b.status='cancelled')::int cancelled_batches,
      coalesce(sum(b.processed_count) filter(where b.status<>'cancelled'),0)::int processed_items,
      coalesce(sum(b.resolved_l2_count) filter(where b.status<>'cancelled'),0)::int resolved_l2,
      coalesce(sum(b.escalated_l3_count) filter(where b.status<>'cancelled'),0)::int escalated_l3,
      coalesce(sum(b.blocked_count) filter(where b.status<>'cancelled'),0)::int blocked,
      coalesce(sum(b.vendor_units) filter(where b.status<>'cancelled'),0) vendor_units,
      coalesce(sum(b.vendor_cost_usd) filter(where b.status<>'cancelled'),0) vendor_cost_usd,
      max(b.heartbeat_at) filter(where b.status<>'cancelled') heartbeat_at,
      coalesce(sum(b.processed_count) filter(where b.status='cancelled'),0)::int historical_cancelled_processed
    from pipeline.layer2_run_batches b
    where b.policy_snapshot->>'scope_wave_request_id'=r.id::text
  ) bs on true
  left join lateral (
    select
      count(distinct i.job_id) filter(where i.job_id is not null)::int child_jobs,
      count(distinct e.id)::int evidence_count,
      max(e.captured_at) latest_evidence_at
    from pipeline.layer2_run_batches b
    left join pipeline.layer2_run_items i on i.batch_id=b.id
    left join pipeline.evidence_artifacts e on e.job_id=i.job_id
    where b.policy_snapshot->>'scope_wave_request_id'=r.id::text
  ) js on true;

  return v_result;
end $$;

revoke all on function security.admin_layer2_parent_runs(integer) from public,anon;
grant execute on function security.admin_layer2_parent_runs(integer) to authenticated,service_role;
