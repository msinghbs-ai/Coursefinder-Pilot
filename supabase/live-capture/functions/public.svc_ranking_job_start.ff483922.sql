CREATE OR REPLACE FUNCTION public.svc_ranking_job_start(p_job_type text, p_source_id uuid, p_requested_by uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'public'
AS $function$
declare v_id uuid;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  insert into pipeline.jobs(job_type,domain,source_id,status,requested_by,started_at,attempt_count,payload)
  values(p_job_type,'ranking',p_source_id,'running',p_requested_by,now(),1,coalesce(p_payload,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end $function$
