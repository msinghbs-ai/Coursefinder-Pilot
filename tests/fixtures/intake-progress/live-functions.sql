-- Guards: Platform Admin decision 5 Nov 2026 19:14 §8 (production function signatures): the live definitions the Automation Progress layer calls,
-- copied verbatim from production fxcwkweaxjtknorudmwp (pg_get_functiondef, read 5 Nov 2026 19:18-19:30 AEDT). run.sh checks each md5 against the
-- value read from production and refuses to continue on any difference. security.calendar_dated_periods_v2 is a stub (same name, argument and the
-- four columns the failure-class trigger reads); it is not called by the progress layer.
CREATE OR REPLACE FUNCTION security.current_role_rank()
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'security', 'auth'
AS $function$
select coalesce(max(r.rank),0)::smallint
from security.user_roles ur join security.roles r on r.code=ur.role_code
where ur.user_id=auth.uid() and (ur.expires_at is null or ur.expires_at>now()) and r.status='active'
$function$
;
CREATE OR REPLACE FUNCTION security.pipeline_num_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$
;
CREATE OR REPLACE FUNCTION security.toolset_setting(p_toolset text, p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s.value from pipeline.platform_toolset_settings s where s.toolset_key = p_toolset and s.key = p_key
$function$
;
CREATE OR REPLACE FUNCTION security.intake_ui_scopes_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'active_courses',n) order by n desc,md5(id::text)),'[]')
 from (select p.id,coalesce(p.display_name,p.canonical_name) name,count(c.id) n
 from catalogue.providers p join ref.countries co on co.id=p.country_id and co.iso_alpha2='AU'
 join ref.provider_types t on t.id=p.provider_type_id and t.code='university'
 join catalogue.courses c on c.provider_id=p.id and c.lifecycle_status='active'
 where p.lifecycle_status='active' group by p.id,2 order by count(c.id) desc,md5(p.id::text)
 limit security.pipeline_num_v1('run_now.cohort_top_au_universities',10)::int) u
$function$
;
CREATE OR REPLACE FUNCTION security.integration_issue_allowed_v1(p_check text, p_value text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 SS-021 F2: whether a value is one the named check on pipeline.integration_issues allows (its quoted literals). A check that does not
-- exist does not restrict the value.
  select coalesce((select p_value = any (array(select m[1] from regexp_matches(pg_get_constraintdef(c.oid), '''([^'']*)''', 'g') m))
                     from pg_constraint c where c.conrelid = 'pipeline.integration_issues'::regclass and c.conname = p_check), true)
$function$
;
CREATE OR REPLACE FUNCTION security.integration_issue_upsert_v1(p jsonb, p_actor text DEFAULT 'integration-validate'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 mandate §3/§5: create or update an integration issue by its deterministic fingerprint. An unchanged problem updates last_observed_at
-- and retry_count only (no new row, no history line); new affected entities or a higher severity add one history line; a recurrence after
-- Closed reopens the same row as a regression. Severity is never lowered automatically.
declare v_fp text := btrim(coalesce(p->>'fingerprint', ''));
        v_max int := security.pipeline_num_v1('integration.entity_ids_max', 500)::int;
        v_sev text := coalesce(nullif(p->>'severity', ''), 'P2');
        v_prov uuid[] := coalesce((select array_agg(distinct x::uuid) from jsonb_array_elements_text(coalesce(p->'provider_ids', '[]'::jsonb)) x), '{}');
        v_course uuid[] := coalesce((select array_agg(distinct x::uuid) from jsonb_array_elements_text(coalesce(p->'course_ids', '[]'::jsonb)) x), '{}');
        v_cc text[] := coalesce((select array_agg(distinct upper(x)) from jsonb_array_elements_text(coalesce(p->'country_codes', '[]'::jsonb)) x), '{}');
        v_refs text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'evidence_refs', '[]'::jsonb)) x), '{}');
        v_deps text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'depends_on', '[]'::jsonb)) x), '{}');
        v_blk bigint[];
        r pipeline.integration_issues; v_new_prov uuid[]; v_new_course uuid[]; v_more boolean; v_action text; v_status text;
        v_rcc text; v_ws text; v_vl text; v_unmapped jsonb := '{}'::jsonb;
begin
  if v_fp = '' then raise exception 'an integration issue needs a fingerprint' using errcode = '22023'; end if;
  if v_sev not in ('P0', 'P1', 'P2') then raise exception 'severity must be P0, P1 or P2' using errcode = '22023'; end if;
  select coalesce(array_agg(i.id), '{}') into v_blk from pipeline.integration_issues i
   where i.fingerprint in (select jsonb_array_elements_text(coalesce(p->'blocked_by_fingerprints', '[]'::jsonb)));
  perform pg_advisory_xact_lock(hashtext('cf247:integration_issue:' || v_fp));  -- fixed: one writer per fingerprint
  select * into r from pipeline.integration_issues i where i.fingerprint = v_fp for update;
  if not found then
    v_status := coalesce(nullif(p->>'status', ''), 'detected');
    if v_status not in ('detected', 'triaged', 'assigned', 'in_progress') then raise exception 'a new issue starts as detected, triaged, assigned or in_progress' using errcode = '22023'; end if;
    -- 4 Nov 2026 (SS-021 F2, IQ-00077): a root cause class, workstream or validation layer the queue's checks refuse is mapped (unclassified, A10,
    -- manual) and the value sent is kept in evidence.unmapped, so a reporting job's own issue write never aborts its run
    v_rcc := coalesce(nullif(p->>'root_cause_class', ''), 'unclassified');
    v_ws := coalesce(nullif(p->>'workstream', ''), 'A10');
    v_vl := coalesce(nullif(p->>'validation_layer', ''), 'manual');
    if not security.integration_issue_allowed_v1('integration_issues_root_cause_class_check', v_rcc) then
      v_unmapped := v_unmapped || jsonb_build_object('root_cause_class', v_rcc); v_rcc := 'unclassified'; end if;
    if not security.integration_issue_allowed_v1('integration_issues_workstream_check', v_ws) then
      v_unmapped := v_unmapped || jsonb_build_object('workstream', v_ws); v_ws := 'A10'; end if;
    if not security.integration_issue_allowed_v1('integration_issues_validation_layer_check', v_vl) then
      v_unmapped := v_unmapped || jsonb_build_object('validation_layer', v_vl); v_vl := 'manual'; end if;
    if v_unmapped <> '{}'::jsonb then v_unmapped := jsonb_build_object('unmapped', v_unmapped); end if;
    insert into pipeline.integration_issues(fingerprint, title, layer, subsystem, provider_ids, course_ids, country_codes, entities_truncated, failure, expected,
           detection_source, validation_layer, evidence, evidence_refs, root_cause_class, severity, impact, workstream, blocked_by, depends_on, status, assignee,
           fix_commit, fix_migration, aer_root_cause_ref, detected_at, last_observed_at)
    values (v_fp, left(coalesce(p->>'title', v_fp), 300), coalesce(nullif(p->>'layer', ''), 'Platform'), p->>'subsystem',
           v_prov[1:v_max], v_course[1:v_max], v_cc, cardinality(v_prov) > v_max or cardinality(v_course) > v_max,
           coalesce(nullif(p->>'failure', ''), 'not stated'), coalesce(nullif(p->>'expected', ''), 'not stated'),
           coalesce(nullif(p->>'source', ''), p_actor), v_vl, coalesce(p->'evidence', '{}'::jsonb) || v_unmapped, v_refs,
           v_rcc, v_sev, p->>'impact', v_ws, v_blk, v_deps,
           v_status, p->>'assignee', p->>'fix_commit', p->>'fix_migration', nullif(p->>'aer_root_cause_ref', ''),
           coalesce((p->>'detected_at')::timestamptz, now()), now())
    returning * into r;
    insert into pipeline.integration_issue_events(issue_id, kind, to_status, actor, note, detail)
    values (r.id, 'detected', r.status, p_actor, left(r.failure, 500), jsonb_build_object('severity', r.severity, 'workstream', r.workstream, 'source', r.detection_source,
            'providers', cardinality(v_prov), 'courses', cardinality(v_course), 'evidence', r.evidence));
    return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', 'created', 'status', r.status, 'severity', r.severity);
  end if;

  select coalesce(array_agg(x), '{}') into v_new_prov from unnest(v_prov) x where not x = any(r.provider_ids);
  select coalesce(array_agg(x), '{}') into v_new_course from unnest(v_course) x where not x = any(r.course_ids);
  v_more := r.entities_truncated or cardinality(r.provider_ids) + cardinality(v_new_prov) > v_max or cardinality(r.course_ids) + cardinality(v_new_course) > v_max;

  if r.status = 'closed' and coalesce((p->>'observed_at')::timestamptz, now()) <= r.closed_at then
    -- P0 IQ-00067 (3 Nov 2026 16:51): evidence observed at or before the close (a trailing 24-hour count, an old failed run) is not a
    -- recurrence: the issue stays closed and unchanged
    return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', 'closed_evidence_before_close', 'status', r.status,
                              'observed_at', coalesce((p->>'observed_at')::timestamptz, now()), 'closed_at', r.closed_at);
  end if;
  if r.status = 'closed' then
    -- §5: the same issue after closure reopens the original row as a regression
    update pipeline.integration_issues i set status = 'reopened', regression_count = i.regression_count + 1, reopened_at = now(), retry_count = i.retry_count + 1,
           last_observed_at = now(), condition_cleared_at = null, verification_outcome = 'regressed',
           severity = case when v_sev < i.severity and i.severity_decided_at is null then v_sev else i.severity end,
           provider_ids = (i.provider_ids || v_new_prov)[1:v_max], course_ids = (i.course_ids || v_new_course)[1:v_max], entities_truncated = v_more,
           country_codes = (select coalesce(array_agg(distinct c), '{}') from unnest(i.country_codes || v_cc) c),
           evidence = i.evidence || coalesce(p->'evidence', '{}'::jsonb), evidence_refs = (select coalesce(array_agg(distinct e), '{}') from unnest(i.evidence_refs || v_refs) e),
           updated_at = now()
     where i.id = r.id returning * into r;
    insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
    values (r.id, 'reopened_regression', 'closed', 'reopened', p_actor, left(coalesce(p->>'failure', r.failure), 500),
            jsonb_build_object('regression_count', r.regression_count, 'evidence', coalesce(p->'evidence', '{}'::jsonb), 'new_providers', cardinality(v_new_prov), 'new_courses', cardinality(v_new_course),
                               'observed_at', coalesce((p->>'observed_at')::timestamptz, now()), 'closed_at', r.closed_at));
    return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', 'reopened', 'status', r.status, 'severity', r.severity, 'regression_count', r.regression_count);
  end if;

  v_action := case when v_sev < r.severity and r.severity_decided_at is null then 'escalated' when cardinality(v_new_prov) + cardinality(v_new_course) > 0 then 'observed'
                   when r.condition_cleared_at is not null then 'observed_again' else 'unchanged' end;
  update pipeline.integration_issues i set retry_count = i.retry_count + 1, last_observed_at = now(), condition_cleared_at = null,
         severity = case when v_sev < i.severity and i.severity_decided_at is null then v_sev else i.severity end,
         provider_ids = (i.provider_ids || v_new_prov)[1:v_max], course_ids = (i.course_ids || v_new_course)[1:v_max], entities_truncated = v_more,
         country_codes = case when v_cc <@ i.country_codes then i.country_codes else (select coalesce(array_agg(distinct c), '{}') from unnest(i.country_codes || v_cc) c) end,
         evidence = case when v_action = 'unchanged' then i.evidence else i.evidence || coalesce(p->'evidence', '{}'::jsonb) end,
         updated_at = case when v_action = 'unchanged' then i.updated_at else now() end
   where i.id = r.id returning * into r;
  if v_action <> 'unchanged' then
    insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
    values (r.id, v_action, r.status, r.status, p_actor, null, jsonb_build_object('severity', r.severity, 'new_providers', cardinality(v_new_prov), 'new_courses', cardinality(v_new_course),
            'evidence', coalesce(p->'evidence', '{}'::jsonb)));
  end if;
  return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', v_action, 'status', r.status, 'severity', r.severity, 'retry_count', r.retry_count);
end $function$
;
CREATE OR REPLACE FUNCTION security.automation_batch(p_command text)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  -- v2.15.269: a job that reads its size from a setting shows that setting
  select coalesce((select (s.value #>> '{}')::int from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = substring(p_command from 'pipeline_num_v1\(''([^'']+)''')),
                  (select s.value::int from pipeline.scholarship_layer_settings s where s.key = substring(p_command from 'scholarship_setting\(''([^'']+)''')),
                  (substring(p_command from '"limit"\s*:\s*(\d+)'))::int, (substring(p_command from '\(\s*(\d+)\s*\)'))::int)
$function$
;
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
        'failed_24h',coalesce(a.failed_24h,0),
        -- UR-07 (1 Nov 2026): a retiring or retired job says so, with its replacement and removal date
        'retirement',(select jsonb_build_object('status',cr.status,'replaced_by',cr.replaced_by,'retire_after',cr.retire_after,'note',cr.note,'purpose',cr.purpose) from pipeline.component_register cr
                       where cr.kind='job' and cr.name=j.jobname and cr.status in ('retiring','retired') limit 1)
      ) order by coalesce(c.area,'Other'), coalesce(c.sort,999), j.jobname),'[]'::jsonb) from cron.job j left join pipeline.automation_catalogue c on c.jobname=j.jobname left join agg a on a.jobid=j.jobid),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='automations' order by created_at desc limit 15) e)));
end $function$
;
CREATE OR REPLACE FUNCTION security.job_idle_flag_person_release_v1(p_job text, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f record; v_n int := 0;
begin
  -- D14 (31 Oct 2026): a person switching a job on releases that job's automatic idle-pause flag; the audit row is kept in
  -- pipeline.enrichment_flag_events, and the flag unit's idle guard applies to the job again. No other job is touched.
  for f in select x.id from pipeline.enrichment_flags x
            where x.entity = 'job' and x.entity_key = p_job and x.field = '' and x.reason_code = 'idle_paused' and x.cleared_at is null and coalesce(x.state, 'raised') = 'raised' loop
    perform security.flag_release_v1(f.id, coalesce(auth.uid()::text, 'person'), 'person', 'Switched on by a person on Automations: ' || left(coalesce(p_reason, ''), 200),
                                     jsonb_build_object('source', 'Automations', 'decision', 'D14'), true);
    v_n := v_n + 1;
  end loop;
  return v_n;
end $function$
;
CREATE OR REPLACE FUNCTION security.admin_automation_control_v1(p_job text, p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'cron', 'security'
 SET statement_timeout TO '100s'
AS $function$
declare j cron.job%rowtype; c pipeline.automation_catalogue%rowtype; v_rank int:=security.current_role_rank(); v_n int; v_every int; v_sched text; v_cmd text; r record;
begin
  -- SS-016 (Platform Admin 1 Nov 2026 21:02): the floor is rank 5, so the refusal names the PIM Admin; the boundary is unchanged
  if auth.uid() is null or v_rank<5 then raise exception 'PIM Admin role or above required to change automations. A Pipeline Operator records the issue and raises it with the PIM Admin' using errcode='42501'; end if;
  if p_action in ('pause_area','resume_area') then
    for r in select j2.jobid, j2.jobname from cron.job j2 join pipeline.automation_catalogue c2 on c2.jobname=j2.jobname where c2.area=p_args->>'area' and c2.control_rank<=v_rank
                 -- UR-07 (1 Nov 2026): an area resume never switches on a retiring or retired job
                 and not (p_action='resume_area' and exists (select 1 from pipeline.component_register cr where cr.kind='job' and cr.name=j2.jobname and cr.status in ('retiring','retired'))) loop
      perform cron.alter_job(r.jobid, active => p_action='resume_area');
      if p_action='resume_area' then perform security.job_idle_flag_person_release_v1(r.jobname, coalesce(nullif(p_args->>'reason',''),'area '||coalesce(p_args->>'area','')||' switched on')); end if;  -- D14
    end loop;
    insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('automations',p_action,p_args->>'area',p_args,auth.uid());
    return security.admin_automations_read_v1();
  end if;
  select * into j from cron.job where jobname=p_job;
  if j.jobid is null then raise exception 'unknown automation'; end if;
  select * into c from pipeline.automation_catalogue where jobname=p_job;
  -- SS-016 acceptance S1 (1 Nov 2026): the refusal names the role that changes this automation; the check is unchanged
  if v_rank<coalesce(c.control_rank,6) then raise exception 'this automation is changed by the %', case when coalesce(c.control_rank,6)>=6 then 'Platform Admin' when c.control_rank=5 then 'PIM Admin' else 'Pipeline Operator or above' end using errcode='42501'; end if;
  -- UR-07 (1 Nov 2026): a retiring or retired job cannot be switched on, run or re-scheduled; it can still be paused
  if p_action <> 'pause' and exists (select 1 from pipeline.component_register cr where cr.kind='job' and cr.name=p_job and cr.status in ('retiring','retired')) then
    raise exception 'this automation is retired (%); it cannot be switched on, run or changed',
      coalesce((select 'replaced by '||cr.replaced_by from pipeline.component_register cr where cr.kind='job' and cr.name=p_job and cr.status in ('retiring','retired') and cr.replaced_by is not null limit 1), 'no replacement recorded');
  end if;
  if p_action in ('pause','resume') then
    perform cron.alter_job(j.jobid, active => p_action='resume');
    -- D14 (31 Oct 2026): a person switching the job on releases its automatic idle-pause flag, so Flags matches and the idle guard applies again
    if p_action='resume' then perform security.job_idle_flag_person_release_v1(p_job, coalesce(nullif(p_args->>'reason',''),'switched on')); end if;
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
    -- v2.15.269: the size lives in a setting; change the setting (its own range applies), never the job
    if j.command ~ 'pipeline_num_v1\(''' then
      v_sched:=substring(j.command from 'pipeline_num_v1\(''([^'']+)''');
      if v_n is null or exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key='pipeline' and s.key=v_sched and ((s.min_value is not null and v_n<s.min_value) or (s.max_value is not null and v_n>s.max_value))) then
        raise exception 'batch size out of range for %', v_sched; end if;
      update pipeline.platform_toolset_settings set value=to_jsonb(v_n), reason=coalesce(nullif(p_args->>'reason',''),'Automations: batch size'), updated_by=auth.uid(), updated_at=now() where toolset_key='pipeline' and key=v_sched;
      insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('toolsets','setting','pipeline.'||v_sched,jsonb_build_object('after',v_n,'from','Automations'),auth.uid());
    elsif j.command ~ 'scholarship_setting\(''' then
      if v_n is null or v_n<1 or v_n>500 then raise exception 'batch size must be 1-500'; end if;
      update pipeline.scholarship_layer_settings set value=v_n where key=substring(j.command from 'scholarship_setting\(''([^'']+)''');
    else
    if v_n is null or v_n<1 or v_n>500 then raise exception 'batch size must be 1-500'; end if;
    v_cmd:=case when j.command ~ '"limit"\s*:\s*\d+' then regexp_replace(j.command,'"limit"\s*:\s*\d+','"limit":'||v_n)
                else regexp_replace(j.command,'\(\s*\d+\s*\)','('||v_n||')') end;
    perform cron.alter_job(j.jobid, command => v_cmd);
    end if;
  else raise exception 'unknown action'; end if;
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values ('automations',p_action,p_job,p_args,auth.uid());
  return security.admin_automations_read_v1();
end $function$
;
CREATE OR REPLACE FUNCTION public.admin_automation_control(p_job text, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'public', 'extensions'
AS $function$ select security.admin_automation_control_v1(p_job,p_action,coalesce(p_args,'{}'::jsonb)) $function$
;
CREATE OR REPLACE FUNCTION security.ops_remedy_guard_active_v1()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(current_setting('cf247.ops_remedy', true), '') = 'on'
$function$
;
CREATE OR REPLACE FUNCTION security.ops_guard_issue_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- While a remedy runs it cannot close an issue (only the controller closes, after a verification on a later run) or change its controller fields.
begin
  if new.status = 'closed' and old.status <> 'closed' then raise exception 'ops guard: a remedy cannot close an issue; the controller closes on verified evidence' using errcode = '42501'; end if;
  if new.remedy_attempts is distinct from old.remedy_attempts or new.remedy_code is distinct from old.remedy_code or new.ops_state is distinct from old.ops_state
     or new.diagnosis is distinct from old.diagnosis or new.next_action_at is distinct from old.next_action_at then
    raise exception 'ops guard: a remedy cannot change the controller''s record of an issue' using errcode = '42501';
  end if;
  return new;
end $function$
;
-- stub (see header): the failure-class trigger reads only kind, year, month and year_ok
create or replace function security.calendar_dated_periods_v2(p_provider uuid) returns table(kind text, year int, month int, year_ok boolean)
language sql stable as $$ select null::text, null::int, null::int, null::boolean where false $$;
CREATE OR REPLACE FUNCTION security.intake_failure_class_v1(p_outcome text, p_reason text, p_complete boolean, p_deadline_kind text, p_provider uuid, p_intake_year integer, p_month integer)
 RETURNS TABLE(failure_class text, deterministic boolean, revisit_trigger text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_latest int; v_target int := coalesce(p_intake_year, extract(year from (now() at time zone 'Australia/Melbourne'))::int + 1);  -- fixed: the calendar year in Australia
        v_key text := 'cf247.intake_cal_' || replace(coalesce(p_provider::text, 'none'), '-', ''); v_cal jsonb;
begin
  if p_outcome in ('filled', 'nothing_new') then
    if p_complete then return; end if;
    if p_deadline_kind = 'not_stated' then
      failure_class := 'missing_application_deadline_evidence'; deterministic := true; revisit_trigger := 'the calendar or the course page prints a closing date'; return next; return;
    end if;
    return;
  end if;
  failure_class := case
    when p_reason in ('intakes locked by hand', 'course held', 'kept by a lock or the same-month guard') then 'admission_held'
    -- direction 5 Nov 2026 15:50 §1: offering evidence missing, a governed withdrawal, another academic calendar
    when p_reason like 'the course page does not state % as %intake (offering evidence missing%' or p_reason like 'withdrawn:%' then 'course_level_exception'
    when p_reason like 'the course''s intakes (%) do not all start in%' then 'wrong_institution_or_campus'
    when p_reason like 'no valid academic calendar%set aside%' then 'wrong_institution_or_campus'
    when p_reason like 'no valid academic calendar%' then 'no_valid_calendar_source'
    when p_reason in ('no page behind the intake', 'page refused for this course') or p_reason like 'page not proved%' then 'course_identity_unresolved'
    when p_reason like 'no stored reading of the page%' then 'calendar_interpretation_failed'
    when p_reason like 'the calendar does not print the year%' or p_reason like 'the year of the named period is not printed%' then 'academic_year_unproven'
    when p_reason like 'several study periods start%' or p_reason like 'two start days%' then 'multiple_periods_match'
    when p_reason like 'the course page gives its own start date%' or p_reason like 'the page excludes this month%' or p_reason = 'intake is not a month' then 'course_level_exception'
    when p_reason like 'the course page names no study period%' or p_reason = 'the named period does not start in this month' then 'no_matching_commencement_period'
    when p_reason like '%past%' or p_reason like 'the calendar has no future start%' or p_reason like 'the calendar prints no start%' then 'waiting'
    else 'calendar_interpretation_failed' end;
  if failure_class = 'waiting' then
    -- a start in this month whose year is not proved (none printed, or claimed for the intake's year without evidence): the year is unproven;
    -- else no proved edition reaches the intake's year: the edition is stale; else the next start is a later year's
    -- the university's dated starts, read once a transaction (a run classifies many rows of one university)
    v_cal := nullif(current_setting(v_key, true), '')::jsonb;
    if v_cal is null then
      v_cal := jsonb_build_object('latest', (select max(s.year) from security.calendar_dated_periods_v2(p_provider) s where s.kind = 'start' and s.year_ok),
                                  'unproven', coalesce((select jsonb_agg(distinct jsonb_build_object('m', s.month, 'y', s.year)) from security.calendar_dated_periods_v2(p_provider) s
                                                         where s.kind = 'start' and not coalesce(s.year_ok, false)), '[]'::jsonb));
      perform set_config(v_key, v_cal::text, true);
    end if;
    if exists (select 1 from jsonb_array_elements(v_cal->'unproven') u where (u->>'m')::int = p_month and (u->>'y' is null or (u->>'y')::int = p_intake_year)) then
      failure_class := 'academic_year_unproven';
    else
      v_latest := (v_cal->>'latest')::int;
      failure_class := case when v_latest is null then 'academic_year_unproven' when v_latest < v_target then 'stale_calendar_edition' else 'waiting_for_next_academic_year' end;
    end if;
  end if;
  -- a lock, a hold or a person's decision is not an input of the fingerprint, so those rows are looked at again on the revisit timer
  deterministic := failure_class not in ('course_identity_unresolved', 'waiting_for_next_academic_year', 'consumer_publication_failed', 'admission_held', 'course_level_exception');
  revisit_trigger := case failure_class
    when 'admission_held' then 'the revisit date (a removed lock or hold is seen then)'
    when 'wrong_institution_or_campus' then 'the main campus teaching calendar is approved'
    when 'no_valid_calendar_source' then 'an official main teaching calendar is approved'
    when 'course_identity_unresolved' then 'the course page is proved (Course Link) or the revisit date'
    when 'calendar_interpretation_failed' then 'the calendar reader or the stored page changes'
    when 'academic_year_unproven' then 'the calendar reader or the stored calendar changes'
    when 'stale_calendar_edition' then 'a newer calendar edition is stored (calendar refresh or provider facts)'
    when 'multiple_periods_match' then 'the course page names its period, or the calendar changes'
    when 'course_level_exception' then 'the course page changes, or the revisit date (a person''s decision is seen then)'
    when 'no_matching_commencement_period' then 'the course page or the calendar changes'
    when 'waiting_for_next_academic_year' then 'the revisit date (intake_dates.revisit_days)' end;
  return next;
end $function$
;
CREATE OR REPLACE FUNCTION security.intake_failure_class_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c record; v_year int; v_month int;
begin
  select i.intake_year, array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(i.intake_label)))
    into v_year, v_month from catalogue.course_intakes i where i.id = new.intake_id;
  select * into c from security.intake_failure_class_v1(new.outcome, new.reason, new.next_action = 'complete', new.deadline_kind, new.provider_id, v_year, v_month);
  new.failure_class := c.failure_class; new.deterministic := c.deterministic; new.revisit_trigger := c.revisit_trigger;
  new.evidence_year := coalesce((new.after_value->>'year')::int, v_year);
  new.reader := (select p.parser from pipeline.provider_policy_proposals p where p.id = new.proposal_id);
  new.related_case := case when c.failure_class in ('wrong_institution_or_campus', 'no_valid_calendar_source', 'stale_calendar_edition', 'academic_year_unproven')
                             then 'calendar:' || coalesce(new.calendar_evidence_id::text, new.provider_id::text)
                           when c.failure_class = 'course_identity_unresolved' then 'course:' || new.course_id end;
  -- mandate §9: an unchanged deterministic failure is never repeated on a timer; only a change of its inputs brings it back
  if c.deterministic then new.next_revisit_at := null;
  elsif c.failure_class in ('admission_held', 'course_level_exception') and new.next_revisit_at is null then
    new.next_revisit_at := now() + make_interval(days => security.pipeline_num_v1('intake_dates.revisit_days', 14)::int);
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.admin_process_results_v1(p_view text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid; v_rows int := security.pipeline_num_v1('process_results.validation_rows', 25)::int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Operations read permission required' using errcode = '42501'; end if;
  if p_view = 'latest' then
    return (select jsonb_build_object('id', r.id, 'measured_at', r.measured_at, 'measured_by', r.measured_by, 'summary', r.summary)
              from pipeline.process_results r where r.process_key = coalesce(p_args->>'process', 'intake-dates') order by r.measured_at desc limit 1);
  elsif p_view = 'history' then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'measured_at', r.measured_at, 'measured_by', r.measured_by, 'totals', r.summary->'totals') order by r.measured_at desc), '[]'::jsonb)
              from (select * from pipeline.process_results r where r.process_key = coalesce(p_args->>'process', 'intake-dates') order by r.measured_at desc
                     limit security.pipeline_num_v1('process_results.history_rows', 30)::int) r);
  elsif p_view = 'measure' then
    if v_rank < 4 then raise exception 'Operator permission required to measure' using errcode = '42501'; end if;
    return security.process_results_record_v1();
  elsif p_view = 'university' then
    v_pid := (p_args->>'provider_id')::uuid;
    if not exists (select 1 from jsonb_array_elements(security.intake_ui_scopes_v1()) e where (e->>'id')::uuid = v_pid) then raise exception 'not a university in this process scope' using errcode = '22023'; end if;
    return jsonb_build_object(
      'calendars', (select coalesce(jsonb_agg(jsonb_build_object('proposal_id', s.proposal_id, 'url', s.url, 'evidence_id', s.evidence_id, 'parser', s.parser, 'decided_at', s.decided_at,
                      'scope', s.scope, 'used', s.used, 'set_aside_reason', s.set_aside_reason,
                      'starts', (select coalesce(jsonb_agg(jsonb_build_object('period', d.period, 'date', d.on_date, 'year', d.year, 'month', d.month, 'quote', d.quote) order by d.year, d.month), '[]'::jsonb)
                                   from security.calendar_proposal_dates_v1(s.proposal_id) d where d.kind = 'start'),
                      'deadlines', (select coalesce(jsonb_agg(jsonb_build_object('period', d.period, 'date', d.on_date, 'applies_to', d.applies_to, 'quote', d.quote)), '[]'::jsonb)
                                      from security.calendar_proposal_dates_v1(s.proposal_id) d where d.kind = 'deadline'))), '[]'::jsonb)
                    from security.calendar_sources_v1(v_pid) s),
      'reread', (select coalesce(jsonb_agg(jsonb_build_object('url', f.url, 'state', s.state, 'reason', s.reason, 'reader', s.reader, 'last_at', s.last_at, 'summary', s.parser_summary)), '[]'::jsonb)
                   from pipeline.calendar_reread_state s join pipeline.provider_fact_sources f on f.id = s.fact_source_id where s.provider_id = v_pid),
      'findings', (select coalesce(jsonb_agg(jsonb_build_object('code', f.code, 'detail', f.detail, 'example', f.example, 'times', f.times, 'last_seen', f.last_seen) order by f.last_seen desc), '[]'::jsonb)
                     from pipeline.calendar_reader_findings f where f.provider_id = v_pid and f.resolved_at is null),
      'flags', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'reason', g.reason, 'flagged_at', g.flagged_at)), '[]'::jsonb)
                  from pipeline.enrichment_flags g where g.provider_id = v_pid and g.field = 'intake_calendar' and g.cleared_at is null),
      'recent', (select coalesce(jsonb_agg(x order by x->>'run_at' desc), '[]'::jsonb) from (
                   select jsonb_build_object('run_at', e.run_at, 'course_id', e.course_id, 'course_title', coalesce(c.display_title, c.canonical_title), 'course_url', c.course_url,
                     'outcome', e.outcome, 'reason', e.reason, 'next_action', e.next_action, 'next_revisit_at', e.next_revisit_at, 'rule', e.rule,
                     'before', e.before_value, 'after', e.after_value, 'page_quote', e.page_quote, 'start_quote', e.start_quote, 'deadline_quote', e.deadline_quote,
                     'calendar_url', e.calendar_url, 'calendar_evidence_id', e.calendar_evidence_id, 'bounded', e.bounded) x
                     from pipeline.course_intake_date_events e join catalogue.courses c on c.id = e.course_id
                    where e.provider_id = v_pid and (p_args->>'outcome' is null or e.outcome = p_args->>'outcome')
                    order by e.run_at desc limit v_rows) y));
  elsif p_view = 'recovery' then
    -- CF-247 mandate 5 Nov 2026 §10: the intake recovery measurement, live (read only)
    return security.process_results_recovery_v1();
  end if;
  raise exception 'unknown view %', p_view using errcode = '22023';
end $function$
;
-- live triggers
drop trigger if exists intake_failure_class on pipeline.course_intake_date_events;
CREATE TRIGGER intake_failure_class BEFORE INSERT ON pipeline.course_intake_date_events FOR EACH ROW EXECUTE FUNCTION security.intake_failure_class_trg_v1();
drop trigger if exists intake_failure_class on pipeline.course_intake_dates;
CREATE TRIGGER intake_failure_class BEFORE INSERT OR UPDATE OF outcome, reason, next_action, deadline_kind ON pipeline.course_intake_dates FOR EACH ROW EXECUTE FUNCTION security.intake_failure_class_trg_v1();
drop trigger if exists ops_guard_issue on pipeline.integration_issues;
CREATE TRIGGER ops_guard_issue BEFORE UPDATE ON pipeline.integration_issues FOR EACH ROW WHEN (security.ops_remedy_guard_active_v1()) EXECUTE FUNCTION security.ops_guard_issue_v1();
-- live function privileges
revoke all on all functions in schema security from public;
grant execute on function security.current_role_rank(), security.admin_automations_read_v1(), security.admin_automation_control_v1(text,text,jsonb) to authenticated;
revoke all on function public.admin_automation_control(text,text,jsonb) from public; grant execute on function public.admin_automation_control(text,text,jsonb) to authenticated, service_role;
revoke all on function public.admin_process_results_v1(text,jsonb) from public; grant execute on function public.admin_process_results_v1(text,jsonb) to authenticated, service_role;
