CREATE OR REPLACE FUNCTION security.platform_health_stall_v1(p_key text, p_area text, p_label text, p_job text, p_last_progress timestamp with time zone, p_pending_sql text, p_default_interval_s integer DEFAULT 600)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security', 'public', 'catalogue', 'scholarship'
AS $function$
declare v_int int; v_active boolean; v_warn interval; v_crit interval; v_pending bigint; v_age interval:=now()-coalesce(p_last_progress,'-infinity'::timestamptz);
begin
  select security.platform_cron_interval_seconds(j.schedule), j.active into v_int, v_active from cron.job j where j.jobname=p_job;
  v_int:=coalesce(v_int,p_default_interval_s);
  v_warn:=greatest(make_interval(secs=>3*v_int), interval '15 minutes');
  v_crit:=greatest(make_interval(secs=>12*v_int), interval '2 hours');
  if v_age <= v_warn then
    return jsonb_build_object('queue',p_key,'status','moving','last_progress',p_last_progress);
  end if;
  execute p_pending_sql into v_pending;
  if coalesce(v_pending,0)=0 then
    return jsonb_build_object('queue',p_key,'status','idle','pending',0,'last_progress',p_last_progress);
  end if;
  return jsonb_build_object('queue',p_key,'status','stalled','pending',v_pending,'last_progress',p_last_progress,
    'job',p_job,'job_active',coalesce(v_active,false),'stalled_minutes',round(extract(epoch from least(v_age, interval '365 days'))/60),
    'threshold_minutes',round(extract(epoch from v_warn)/60),
    'issue',security.platform_health_issue_v1(p_key,
      case when v_age>v_crit or coalesce(v_active,false)=false then 'critical' else 'warning' end, p_area,
      p_label||' has stopped: '||v_pending||' waiting, nothing processed for '||
        case when p_last_progress is null then 'as long as records exist' else round(extract(epoch from v_age)/60)||' minutes' end||
        case when v_active is distinct from true then ' (its scheduled job is missing or paused)' else '' end,
      jsonb_build_object('pending',v_pending,'last_progress',p_last_progress,'job',p_job,'job_active',coalesce(v_active,false),
        'threshold_minutes',round(extract(epoch from v_warn)/60))));
end $function$
