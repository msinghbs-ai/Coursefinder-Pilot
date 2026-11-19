-- CF-CHG-20260830-048
-- M2.4.4 A26: expose only the acquisition state needed to resume a stale
-- extracting item without issuing another vendor request.

create or replace function public.layer2_run_item_resume_context(p_item_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','pipeline'
as $$
declare v_result jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select jsonb_build_object(
    'item_id',i.id,
    'batch_id',i.batch_id,
    'job_id',j.id,
    'attempt_id',nullif(j.result->>'attempt_id','')::uuid,
    'evidence_id',nullif(j.result->>'evidence_id','')::uuid,
    'provider_id',nullif(j.result->>'provider_id','')::uuid,
    'provider_key',j.result->>'provider_key',
    'content_changed',coalesce((j.result->>'content_changed')::boolean,true),
    'estimated_request_cost_usd',coalesce((j.result->>'estimated_request_cost_usd')::numeric,0)
  )
  into v_result
  from pipeline.layer2_run_items i
  join pipeline.jobs j on j.id=i.job_id
  where i.id=p_item_id
    and i.status='extracting'
    and j.status='succeeded'
    and nullif(j.result->>'attempt_id','') is not null
    and nullif(j.result->>'evidence_id','') is not null;

  return v_result;
end $$;

revoke all on function public.layer2_run_item_resume_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_run_item_resume_context(uuid) to service_role;
