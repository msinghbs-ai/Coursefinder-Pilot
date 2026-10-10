begin;

create or replace function public.svc_ranking_job_start(
  p_job_type text,
  p_source_id uuid,
  p_requested_by uuid,
  p_payload jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','public'
as $$
declare v_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  insert into pipeline.jobs(job_type,domain,source_id,status,requested_by,started_at,attempt_count,payload)
  values(p_job_type,'ranking',p_source_id,'running',p_requested_by,now(),1,coalesce(p_payload,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.svc_ranking_job_finish(
  p_job_id uuid,
  p_status text,
  p_result jsonb default '{}'::jsonb,
  p_error_text text default null
) returns void
language plpgsql
security definer
set search_path to 'pg_catalog','pipeline','public'
as $$
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  if p_status not in ('completed','failed') then
    raise exception 'invalid ranking job terminal status' using errcode='22023';
  end if;
  update pipeline.jobs
  set status=p_status,completed_at=now(),result=coalesce(p_result,'{}'::jsonb),error_text=p_error_text
  where id=p_job_id and domain='ranking';
end $$;

revoke all on function public.svc_ranking_job_start(text,uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.svc_ranking_job_finish(uuid,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.svc_ranking_job_start(text,uuid,uuid,jsonb) to service_role;
grant execute on function public.svc_ranking_job_finish(uuid,text,jsonb,text) to service_role;

commit;