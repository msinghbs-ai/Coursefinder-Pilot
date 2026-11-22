CREATE OR REPLACE FUNCTION security.platform_health_stall_v1(p_key text, p_area text, p_label text, p_job text, p_last_progress timestamp with time zone, p_pending_sql text, p_default_interval_s integer DEFAULT 600)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security', 'public', 'catalogue', 'scholarship'
AS $function$
declare v_int int; v_active boolean; v_warn interval; v_crit interval; v_pending bigint; v_age interval:=now()-coalesce(p_last_progress,'-infinity'::timestamptz); v_unit boolean:=false;
        v_disp text; v_pause jsonb;
begin
  select security.platform_cron_interval_seconds(j.schedule), j.active into v_int, v_active from cron.job j where j.jobname=p_job;
  -- 18 Nov 2026 (S2-Build): a legacy job a dispatcher runs live is running, on the dispatcher's own schedule for it
  v_disp:=security.job_dispatched_v1(p_job);
  if v_disp is not null then
    v_active:=true;
    v_int:=coalesce(security.platform_cron_interval_seconds(coalesce(
             (select r.schedule from pipeline.rollup_targets r where r.legacy_job=p_job and r.enabled and r.mode='live' limit 1),
             (select f.schedule from pipeline.field_execution_registry f where f.legacy_job=p_job and f.enabled and f.mode='live' limit 1),
             (select a.schedule from pipeline.admission_rules a where a.legacy_job=p_job and a.enabled and a.mode='live' limit 1))), v_int);
  end if;
  v_int:=coalesce(v_int,p_default_interval_s);
  v_warn:=greatest(make_interval(secs=>3*v_int), interval '15 minutes');  -- fixed: the stall rule of this check (three runs, at least 15 minutes)
  v_crit:=greatest(make_interval(secs=>12*v_int), interval '2 hours');    -- fixed: as above (twelve runs, at least 2 hours)
  if v_age <= v_warn then
    return jsonb_build_object('queue',p_key,'status','moving','last_progress',p_last_progress) || case when v_disp is not null then jsonb_build_object('dispatcher',v_disp) else '{}'::jsonb end;
  end if;
  execute p_pending_sql into v_pending;
  if coalesce(v_pending,0)=0 then
    return jsonb_build_object('queue',p_key,'status','idle','pending',0,'last_progress',p_last_progress);
  end if;
  -- 18 Nov 2026 (S2-Build): a job a person switched off with a recorded pause (Automations, or a migration that logged it) waits by decision
  if v_active is false then
    v_pause:=security.job_paused_by_person_v1(p_job);
    if v_pause is not null then
      return jsonb_build_object('queue',p_key,'status','paused','pending',v_pending,'last_progress',p_last_progress,'job',p_job,'job_active',false,
        'paused_at',v_pause->>'at','paused_reason',v_pause->>'reason','temporary',(v_pause->>'temporary')::boolean);
    end if;
  end if;
  -- SS-014 (31 Oct 2026): a job the flag unit paused because its runs found nothing is switched on again by the flag unit when work
  -- waits (security.flag_jobs_v1, security.waste_idle_guard_v1); until the critical age that is information, not a breakage
  if v_active is false then
    select true into v_unit from pipeline.enrichment_flags f
     where f.entity='job' and f.entity_key=p_job and f.field='' and f.reason_code='idle_paused' and f.cleared_at is null and coalesce(f.state,'raised')='raised' limit 1;
    v_unit:=coalesce(v_unit,false);
  end if;
  return jsonb_build_object('queue',p_key,'status','stalled','pending',v_pending,'last_progress',p_last_progress,
    'job',p_job,'job_active',coalesce(v_active,false),'dispatcher',v_disp,'paused_by_flag_unit',v_unit,'stalled_minutes',round(extract(epoch from least(v_age, interval '365 days'))/60),
    'threshold_minutes',round(extract(epoch from v_warn)/60),
    'issue',security.platform_health_issue_v1(p_key,
      case when v_age>v_crit or (coalesce(v_active,false)=false and not v_unit) then 'critical' when v_unit then 'info' else 'warning' end, p_area,
      p_label||' has stopped: '||v_pending||' waiting, nothing processed for '||
        case when p_last_progress is null then 'as long as records exist' else round(extract(epoch from v_age)/60)||' minutes' end||
        case when v_unit then ' (its job is paused because its recent runs found nothing; the flag unit switches it on again when work is waiting)'
             when v_active is distinct from true then ' (its scheduled job is missing, or switched off with no recorded pause)'
             when v_disp is not null then ' (run by '||v_disp||')' else '' end,
      jsonb_build_object('pending',v_pending,'last_progress',p_last_progress,'job',p_job,'job_active',coalesce(v_active,false),'dispatcher',v_disp,
        'threshold_minutes',round(extract(epoch from v_warn)/60))));
end $function$
