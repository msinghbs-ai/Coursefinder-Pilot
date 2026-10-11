-- CF-247 (11 Oct 2026, Fix 4 follow-up, found in the live check of 20261011009800): the Automations read still took 10 s because the
-- "last run" set was worked out again for each of the 94 jobs. It is now worked out once. md5-checked before and after.
do $guard$
declare v_expected jsonb := '{"security.admin_automations_read_v1()": "e4564f611f4bcc79cd26991d42bf4500"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION security.admin_automations_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;
  -- v2.15.246 (Fix 4): one pass over the last 8 days of run history instead of three lookups per job (34 s, so the list failed with
  -- a server error); the last run, runs and failures in 24 hours are read from it. Jobs not yet in the catalogue are named.
  return (with r as materialized (select d.jobid, d.start_time, d.end_time, d.status, d.return_message from cron.job_run_details d where d.start_time >= now() - interval '8 days'),
               agg as (select jobid, count(*) filter (where start_time >= now() - interval '24 hours') runs_24h,
                              count(*) filter (where start_time >= now() - interval '24 hours' and status = 'failed') failed_24h, max(start_time) last_at from r group by jobid),
               last as materialized (select r.* from r join agg on agg.jobid = r.jobid and agg.last_at = r.start_time)
    select jsonb_build_object('generated_at',now(),'rank',security.current_role_rank(),
    'jobs',(select coalesce(jsonb_agg(jsonb_build_object(
        'job',j.jobname,'area',coalesce(c.area,'Other'),'sort',coalesce(c.sort,999),'label',coalesce(c.label,j.jobname),'description',coalesce(c.description,''),
        'schedule',j.schedule,'active',j.active,'control_rank',coalesce(c.control_rank,6),'catalogued',c.jobname is not null,
        'batch',case when coalesce(c.batch_editable,false) then security.automation_batch(j.command) end,
        'last',(select jsonb_build_object('at',l.start_time,'status',l.status,'seconds',round(extract(epoch from (l.end_time-l.start_time))::numeric,1),'message',case when l.status<>'succeeded' then left(l.return_message,200) end)
                  from last l where l.jobid=j.jobid limit 1),
        'runs_24h',coalesce(a.runs_24h,0),
        'failed_24h',coalesce(a.failed_24h,0)
      ) order by coalesce(c.area,'Other'), coalesce(c.sort,999), j.jobname),'[]'::jsonb) from cron.job j left join pipeline.automation_catalogue c on c.jobname=j.jobname left join agg a on a.jobid=j.jobid),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='automations' order by created_at desc limit 15) e)));
end $function$;

do $post$
declare v_expected jsonb := '{"security.admin_automations_read_v1()": "81d5e16a3b3101c9e308696377886c68"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
