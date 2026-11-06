CREATE OR REPLACE FUNCTION public.admin_job_run_now_v1(p_job text, p_reason text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then raise exception 'sign in required' using errcode = '42501'; end if;
  if security.current_role_rank() < coalesce((select a.control_rank from pipeline.automation_catalogue a where a.jobname = p_job), 6) then
    raise exception 'your role cannot start this job' using errcode = '42501';
  end if;
  return security.job_run_now_v1(p_job, p_reason, coalesce(p_args, '{}'::jsonb), auth.uid());
end $function$

