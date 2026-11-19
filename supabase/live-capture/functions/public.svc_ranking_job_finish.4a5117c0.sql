CREATE OR REPLACE FUNCTION public.svc_ranking_job_finish(p_job_id uuid, p_status text, p_result jsonb DEFAULT '{}'::jsonb, p_error_text text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'public'
AS $function$
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
end $function$
