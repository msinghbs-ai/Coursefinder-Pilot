CREATE OR REPLACE FUNCTION security.admin_automations_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object('generated_at',now(),'rank',security.current_role_rank(),
    'jobs',(select coalesce(jsonb_agg(jsonb_build_object(
        'job',j.jobname,'area',coalesce(c.area,'Other'),'sort',coalesce(c.sort,999),'label',coalesce(c.label,j.jobname),'description',coalesce(c.description,''),
        'schedule',j.schedule,'active',j.active,'control_rank',coalesce(c.control_rank,6),
        'batch',case when coalesce(c.batch_editable,false) then security.automation_batch(j.command) end,
        'last',(select jsonb_build_object('at',d.start_time,'status',d.status,'seconds',round(extract(epoch from (d.end_time-d.start_time))::numeric,1),'message',case when d.status<>'succeeded' then left(d.return_message,200) end)
                  from cron.job_run_details d where d.jobid=j.jobid order by d.start_time desc limit 1),
        'runs_24h',(select count(*) from cron.job_run_details d where d.jobid=j.jobid and d.start_time>=now()-interval '24 hours'),
        'failed_24h',(select count(*) from cron.job_run_details d where d.jobid=j.jobid and d.start_time>=now()-interval '24 hours' and d.status='failed')
      ) order by coalesce(c.area,'Other'), coalesce(c.sort,999), j.jobname),'[]'::jsonb) from cron.job j left join pipeline.automation_catalogue c on c.jobname=j.jobname),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='automations' order by created_at desc limit 15) e));
end $function$
