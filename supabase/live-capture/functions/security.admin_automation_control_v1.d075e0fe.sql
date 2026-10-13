CREATE OR REPLACE FUNCTION security.admin_automation_control_v1(p_job text, p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
 SET statement_timeout TO '100s'
AS $function$
declare j cron.job%rowtype; c pipeline.automation_catalogue%rowtype; v_rank int:=security.current_role_rank(); v_n int; v_every int; v_sched text; v_cmd text; r record;
begin
  if auth.uid() is null or v_rank<5 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_action in ('pause_area','resume_area') then
    for r in select j2.jobid, j2.jobname from cron.job j2 join pipeline.automation_catalogue c2 on c2.jobname=j2.jobname where c2.area=p_args->>'area' and c2.control_rank<=v_rank loop
      perform cron.alter_job(r.jobid, active => p_action='resume_area');
    end loop;
    insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('automations',p_action,p_args->>'area',p_args,auth.uid());
    return security.admin_automations_read_v1();
  end if;
  select * into j from cron.job where jobname=p_job;
  if j.jobid is null then raise exception 'unknown automation'; end if;
  select * into c from pipeline.automation_catalogue where jobname=p_job;
  if v_rank<coalesce(c.control_rank,6) then raise exception 'this automation needs a higher role to change' using errcode='42501'; end if;
  if p_action in ('pause','resume') then
    perform cron.alter_job(j.jobid, active => p_action='resume');
  elsif p_action='run_now' then
    execute j.command;
  elsif p_action='set_every' then
    v_every:=(p_args->>'minutes')::int;
    if v_every not in (1,2,3,5,10,15,20,30,60,120,360,1440) then raise exception 'choose 1, 2, 3, 5, 10, 15, 20, 30 or 60 minutes, or 2, 6 or 24 hours'; end if;
    v_sched:=case when v_every=1 then '* * * * *'
                  when v_every<60 then (abs(hashtext(p_job))%v_every)::text||'-59/'||v_every||' * * * *'
                  when v_every=60 then (abs(hashtext(p_job))%60)::text||' * * * *'
                  when v_every=1440 then (abs(hashtext(p_job))%60)::text||' '||(abs(hashtext(p_job||'h'))%24)::text||' * * *'
                  else (abs(hashtext(p_job))%60)::text||' */'||(v_every/60)||' * * *' end;
    perform cron.alter_job(j.jobid, schedule => v_sched);
  elsif p_action='set_batch' then
    if not coalesce(c.batch_editable,false) then raise exception 'batch size cannot be changed for this automation'; end if;
    v_n:=(p_args->>'batch')::int;
    if v_n is null or v_n<1 or v_n>500 then raise exception 'batch size must be 1-500'; end if;
    v_cmd:=case when j.command ~ '"limit"\s*:\s*\d+' then regexp_replace(j.command,'"limit"\s*:\s*\d+','"limit":'||v_n)
                else regexp_replace(j.command,'\(\s*\d+\s*\)','('||v_n||')') end;
    perform cron.alter_job(j.jobid, command => v_cmd);
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('automations',p_action,p_job,p_args,auth.uid());
  return security.admin_automations_read_v1();
end $function$
