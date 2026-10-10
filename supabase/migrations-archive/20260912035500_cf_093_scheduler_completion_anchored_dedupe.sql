-- CF-CHG-20260910-093
-- Large-scope recent-dispatch dedupe correction.
-- A legitimate completed/partial Layer 2 batch remains recent for the governed
-- dedupe horizon measured from completion, not only from initial dispatch.
-- Cancelled batches are never reusable as a prior dispatch.

create or replace function security.scheduler_workflow_dispatch_dedupe_anchor_v1(
  p_dispatch_result jsonb,
  p_consumed_at timestamptz
) returns timestamptz
language sql
stable
security definer
set search_path to ''
as $function$
  with batch_ids as (
    select distinct nullif(e->>'batch_id','')::uuid as batch_id
    from jsonb_array_elements(coalesce(p_dispatch_result->'profiles','[]'::jsonb)) e
    where nullif(e->>'batch_id','') is not null
  ), batch_state as (
    select count(*)::integer as referenced_count,
           max(b.completed_at) filter (
             where b.status in ('completed','partial') and b.completed_at is not null
           ) as latest_completed_at
    from batch_ids x
    left join pipeline.layer2_run_batches b on b.id=x.batch_id
  )
  select case
    when bs.referenced_count>0 then bs.latest_completed_at
    else p_consumed_at
  end
  from batch_state bs
$function$;

revoke all on function security.scheduler_workflow_dispatch_dedupe_anchor_v1(jsonb,timestamptz) from public,anon,authenticated;
grant execute on function security.scheduler_workflow_dispatch_dedupe_anchor_v1(jsonb,timestamptz) to service_role;

-- Patch only the already-governed recent-dispatch predicate in the current bridge.
-- Fail closed if the expected predicate is no longer present so migration drift
-- cannot silently alter scheduler behaviour.
do $migration$
declare
  v_reg regprocedure := 'security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text)'::regprocedure;
  v_def text;
  v_old text := $old$and (j.payload->>'consumed_at')::timestamptz>=now()-make_interval(mins=>v_dedupe_minutes)$old$;
  v_new text := $new$and security.scheduler_workflow_dispatch_dedupe_anchor_v1(j.payload->'dispatch_result',(j.payload->>'consumed_at')::timestamptz)>=now()-make_interval(mins=>v_dedupe_minutes)$new$;
begin
  select pg_get_functiondef(v_reg) into v_def;
  if position(v_old in v_def)=0 then
    raise exception 'CF-093 completion-anchored dedupe patch target not found';
  end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;
