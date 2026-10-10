-- CF-CHG-20260915-247, Track G (live end-to-end UI progress).
-- Read-only live queue status for the automated Layer 3 dispatcher/queue
-- (pipeline.layer3_work_items), generic across any task class using it,
-- not tuition-specific. Reuses security.scholarship_ai_role_rank() (a
-- generic role-rank lookup despite its name) rather than duplicating an
-- identical check.
--
-- Governance note: applied directly to the live Pilot Supabase project
-- before being committed here; this file brings the checked-in migration
-- history back in sync with what is actually live.
CREATE OR REPLACE FUNCTION security.layer3_queue_status_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_rank int := security.scholarship_ai_role_rank(); v_result jsonb;
begin
  if v_rank < 3 then raise exception 'curator role required' using errcode='42501'; end if;
  with counts as (
    select task_class, status, count(*) as n
    from pipeline.layer3_work_items
    group by task_class, status
  ), by_task as (
    select
      task_class,
      jsonb_object_agg(status, n) as status_counts,
      sum(n) as total
    from counts
    group by task_class
  ), oldest_pending as (
    select task_class, min(available_at) as oldest_available_at
    from pipeline.layer3_work_items
    where status = 'pending'
    group by task_class
  ), last_completed as (
    select task_class, max(completed_at) as last_completed_at
    from pipeline.layer3_work_items
    where completed_at is not null
    group by task_class
  )
  select jsonb_build_object(
    'by_task_class', coalesce((
      select jsonb_agg(jsonb_build_object(
        'task_class', bt.task_class,
        'status_counts', bt.status_counts,
        'total', bt.total,
        'oldest_pending_seconds', case when op.oldest_available_at is null then null
          else extract(epoch from (now() - op.oldest_available_at))::int end,
        'last_completed_at', lc.last_completed_at
      ) order by bt.task_class)
      from by_task bt
      left join oldest_pending op on op.task_class = bt.task_class
      left join last_completed lc on lc.task_class = bt.task_class
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end $function$;
