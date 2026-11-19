CREATE OR REPLACE FUNCTION public.admin_intake_run_now_v1(p_cohort_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.intake_ui_requests%rowtype; v_result jsonb;
begin
 if auth.uid() is null then raise exception 'sign in required' using errcode='42501'; end if;
 select * into r from pipeline.intake_ui_requests where cohort_id=p_cohort_id and requested_by=auth.uid();
 if not found then raise exception 'fixed request is unavailable to this operator' using errcode='42501'; end if;
 if security.current_role_rank()<coalesce((select control_rank from pipeline.automation_catalogue where jobname='intake-dates-apply'),6) then
 raise exception 'your role cannot start this job' using errcode='42501'; end if;
 if not pg_try_advisory_xact_lock(hashtextextended('intake ui request:'||p_cohort_id,0)) then -- fixed: serialise duplicate request before shared runner
 insert into pipeline.admin_control_events(area,action,target,detail,actor)
 values('run_now','duplicate_ui_request','intake-dates-apply',jsonb_build_object('cohort_id',p_cohort_id),auth.uid());
 return jsonb_build_object('state','in_progress','cohort_id',p_cohort_id,'next_action','Read the saved cohort after the in-flight request finishes; no second run was dispatched.'); end if;
 v_result:=public.admin_job_run_now_v1('intake-dates-apply',r.reason,jsonb_build_object('cohort_id',r.cohort_id,'idempotency_key',r.request_key));
 return v_result||(select jsonb_build_object('outcome',j.outcome,'started_at',j.started_at,'finished_at',j.finished_at) from pipeline.admin_jobs j where j.id=(v_result->>'run_id')::uuid);
end $function$
