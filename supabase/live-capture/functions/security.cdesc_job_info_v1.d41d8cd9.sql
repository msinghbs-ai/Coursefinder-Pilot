CREATE OR REPLACE FUNCTION security.cdesc_job_info_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_s text;
begin
  begin select j.schedule into v_s from cron.job j where j.jobname = 'course-description-machine' limit 1; exception when others then v_s := null; end;
  return jsonb_build_object('schedule', v_s);
end $function$
