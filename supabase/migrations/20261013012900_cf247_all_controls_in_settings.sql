-- CF-247 v2.15.269 (Platform Admin, 13 Oct 2026 21:43: "Bring all controls to UI and make sure in future it's not getting hard coded. All controls
-- need to be reflected and control in UI. Use current recommended settings and choices"; after the settings control audit, docs/platform/
-- SETTINGS-CONTROL-AUDIT.md v1.0).
--   1 One settings register: toolset "pipeline" in pipeline.platform_toolset_settings (the same table, write path and log as Toolsets & limits),
--     with a "used by" line on every setting. security.pipeline_num_v1(key, default) reads it at run time.
--   2 Every scheduled job reads its batch size from the register (30 jobs, was written into the job). The Automations batch box and
--     Pipeline settings now change the register instead of rewriting the job.
--   3 Re-read and retry times and the onboarding rules that were fixed in 14 functions read the register. Each default is today's value,
--     so nothing changes on the day (scholarship pages keep 90 days, as recommended).
--   4 The worker reads the Firecrawl proxy, site map sizes and search result counts from settings (svc_worker_settings_v1).
--   5 Policy tables without a screen can be changed on Pipeline settings: capacity and evidence capacity thresholds, retention days and
--     delete limits, provider fee profiles and basis rules (switch on or off, review date). admin_policy_tables_read / _write.
--   6 Guard against new fixed values: security.controls_check_v1() lists any running job with a number written into it; it shows on
--     Pipeline settings and raises a Toolsets notice. Values that must stay in code (technical time-outs, the month roll-over) carry "-- fixed:".
--   7 The Layer 3 items left on Pipeline settings are removed (their jobs no longer exist).
-- Nothing dropped or deleted. The two settings tables nothing reads are left for a paste file.

do $guard$
declare v_expected jsonb := '{"public.admin_toolsets_read()": "75ed6d4d7150010164f985689a326fc4", "security.automation_batch(text)": "99e4ea70dafebf2245ef906fa31faf26", "security.admin_automation_control_v1(text,text,jsonb)": "888be41ff0545cd44fd505f1dfd48433", "public.admin_pipeline_settings_read()": "57d168ba2854b11919884a80ecc75133", "public.admin_pipeline_settings_write(text,jsonb)": "ba05b863b4797044b24cf8a76bd36b68", "public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)": "9f6de9ffbfbf6c3fe86a9ce4353bbcb2", "public.svc_coverage_discovery_record(uuid,text,text,integer,jsonb,text)": "8d48bf1e02bc9181b836adb6b36f585d", "public.svc_coverage_site_next(integer)": "a9b60629be9529185cb767d0f641493d", "public.svc_coverage_site_record(uuid,text,jsonb)": "1720c7382c1374d85c59b01f80cfffaf", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "a3a99cb0a27e4014ab6c8af19e5abb0f", "public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)": "4f685ff54a3806408e75c4eb71ef260f", "public.svc_scholarship_listing_record(bigint,text,integer,jsonb,text)": "631825c7a6a646f290111b842aaac545", "public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)": "46ed31a16023e656f790e3e8633e7ccb", "security.fc_search_stopped_v1()": "52f4f34ec18f4e3330330d3c15591e81", "security.provider_onboarding_step_v1(uuid)": "1ce3f7b61b36cbeda0092901e5f0759e", "security.provider_onboarding_tick_v1()": "5196a85f41ad09f4393815dc35dabe98", "public.svc_provider_facts_search_next(integer)": "ad0e080213c7317450144a5137f00498", "public.svc_provider_facts_read_next(integer)": "bcc118122628b820d864081b99e215c5", "public.svc_cricos_peo_next(integer)": "448741d90d54f25862567a6caa1af5ec", "security.platform_notices_v1()": "080766262c43abd2e6db0db5a258d364"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1 The register
insert into pipeline.platform_toolsets(key, label, kind, layers, help, sort, reason, updated_at)
values ('pipeline', 'Pipeline (job sizes, re-reads and retries)', 'platform', array[0,1,2,4],
        'How much each scheduled job takes in a run, how often pages are read again, when failed work is tried again, and the onboarding rules. Jobs read these values each time they run.',
        5, 'CF-247 v2.15.269: settings register (Platform Admin, 13 Oct 2026 21:43)', now())
on conflict (key) do nothing;
alter table pipeline.platform_toolset_settings add column if not exists used_by text;

CREATE OR REPLACE FUNCTION security.pipeline_num_v1(p_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;

-- 6 Running jobs with a number written into them (a setting call is not counted)
CREATE OR REPLACE FUNCTION security.controls_check_v1()
 RETURNS TABLE(jobname text, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select j.jobname::text, left(j.command, 240)
    from cron.job j
   where j.active
     and (regexp_replace(regexp_replace(j.command, '(pipeline_num_v1|scholarship_setting|fc_setting_num_v1)\(''[^'']+'',\s*\d+(\.\d+)?\)', 'S', 'g'), '''[^'']*''', 'T', 'g')
            ~ '(\(|,)\s*\d+(\.\d+)?\s*(\)|,)'
          or j.command ~ '"\w+"\s*:\s*\d')
   order by 1
$function$;

-- 4 Settings the worker reads at the start of each call
CREATE OR REPLACE FUNCTION public.svc_worker_settings_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) from pipeline.platform_toolset_settings s
           where s.toolset_key = 'firecrawl' and s.key in ('read_proxy', 'map_limit_course_site', 'map_limit_central', 'map_limit_central_search', 'map_limit_scholarships',
                                                          'search_results_website', 'search_results_register', 'search_results_cricos',
                                                          'search_results_scholarship_search', 'search_results_scholarship_discover'));
end $function$;
revoke all on function public.svc_worker_settings_v1() from public, anon, authenticated;
grant execute on function public.svc_worker_settings_v1() to service_role;

-- The register as one read for Pipeline settings
CREATE OR REPLACE FUNCTION public.admin_settings_register_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'sections', (select coalesce(jsonb_agg(jsonb_build_object('section', z.section, 'settings', z.settings) order by z.first_sort), '[]'::jsonb)
                   from (select s.section, min(s.sort) first_sort,
                                jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                                          'unit', s.unit, 'used_by', s.used_by, 'reason', s.reason, 'updated_at', s.updated_at) order by s.sort, s.key) settings
                           from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' group by s.section) z),
    'check', (select coalesce(jsonb_agg(jsonb_build_object('job', c.jobname, 'detail', c.detail)), '[]'::jsonb) from security.controls_check_v1() c),
    'jobs', (select count(*) from cron.job where active));
end $function$;
revoke all on function public.admin_settings_register_read() from public, anon;
grant execute on function public.admin_settings_register_read() to authenticated;

-- 5 Policy tables: read and change the safe columns, with a reason (Platform Admin)
CREATE OR REPLACE FUNCTION security.policy_columns_v1()
 RETURNS TABLE(tbl text, key_col text, col text, label text, unit text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select * from (values
    ('platform_capacity_policy', 'environment', 'database_warn_bytes', 'Database size: warning', 'bytes'),
    ('platform_capacity_policy', 'environment', 'database_high_bytes', 'Database size: high', 'bytes'),
    ('platform_capacity_policy', 'environment', 'database_critical_bytes', 'Database size: critical', 'bytes'),
    ('platform_capacity_policy', 'environment', 'temp_spill_warn_bytes_per_day', 'Temporary files a day: warning', 'bytes'),
    ('platform_capacity_policy', 'environment', 'temp_spill_high_bytes_per_day', 'Temporary files a day: high', 'bytes'),
    ('platform_capacity_policy', 'environment', 'temp_spill_critical_bytes_per_day', 'Temporary files a day: critical', 'bytes'),
    ('platform_capacity_policy', 'environment', 'failed_orphan_upload_warn_count', 'Failed or orphan uploads: warning', 'files'),
    ('platform_capacity_policy', 'environment', 'integrity_warn_count', 'Integrity findings: warning', 'findings'),
    ('platform_capacity_policy', 'environment', 'integrity_high_count', 'Integrity findings: high', 'findings'),
    ('platform_capacity_policy', 'environment', 'integrity_critical_count', 'Integrity findings: critical', 'findings'),
    ('platform_capacity_policy', 'environment', 'observation_retention_days', 'Keep capacity readings for', 'days'),
    ('evidence_capacity_policy', 'id', 'planning_capacity_bytes', 'Evidence storage planned', 'bytes'),
    ('evidence_capacity_policy', 'id', 'warn_pct', 'Evidence storage: warning at', '%'),
    ('evidence_capacity_policy', 'id', 'high_pct', 'Evidence storage: high at', '%'),
    ('evidence_capacity_policy', 'id', 'critical_pct', 'Evidence storage: critical at', '%'),
    ('retention_class_policies', 'class_key', 'default_retention_days', 'Keep for', 'days'),
    ('retention_class_policies', 'class_key', 'bounded_delete_limit', 'Most rows removed at a time', 'rows'),
    ('provider_fee_profiles', 'id', 'active', 'Applied', null),
    ('provider_fee_profiles', 'id', 'review_by', 'Review by', 'date'),
    ('provider_fee_basis_rules', 'rule_code', 'active', 'Applied', null),
    ('provider_fee_basis_rules', 'rule_code', 'review_by', 'Review by', 'date')) v(tbl, key_col, col, label, unit)
$function$;

CREATE OR REPLACE FUNCTION public.admin_policy_tables_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v jsonb := '[]'::jsonb; t record; v_rows jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  for t in select p.tbl, min(p.key_col) key_col, jsonb_agg(jsonb_build_object('col', p.col, 'label', p.label, 'unit', p.unit,
                    'type', (select c.data_type from information_schema.columns c where c.table_schema = 'pipeline' and c.table_name = p.tbl and c.column_name = p.col))) cols
             from security.policy_columns_v1() p group by p.tbl loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.%I::text), ''[]''::jsonb) from pipeline.%I x', t.key_col, t.tbl) into v_rows;
    v := v || jsonb_build_object('table', t.tbl, 'key', t.key_col, 'columns', t.cols, 'rows', v_rows);
  end loop;
  return jsonb_build_object('can_manage', v_rank >= 6, 'tables', v,
    'providers', (select coalesce(jsonb_object_agg(p.id, coalesce(p.display_name, p.canonical_name)), '{}'::jsonb) from catalogue.providers p
                   where p.id in (select provider_id from pipeline.provider_fee_profiles union select provider_id from pipeline.provider_fee_basis_rules)));
end $function$;
revoke all on function public.admin_policy_tables_read() from public, anon;
grant execute on function public.admin_policy_tables_read() to authenticated;

CREATE OR REPLACE FUNCTION public.admin_policy_tables_write(p_table text, p_row text, p_column text, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_key text; v_type text; v_before jsonb; v_txt text := p_value #>> '{}';
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select p.key_col into v_key from security.policy_columns_v1() p where p.tbl = p_table and p.col = p_column;
  if v_key is null then raise exception 'this value cannot be changed here'; end if;
  select c.data_type into v_type from information_schema.columns c where c.table_schema = 'pipeline' and c.table_name = p_table and c.column_name = p_column;
  if v_type in ('integer', 'bigint', 'numeric') and (v_txt is null or v_txt !~ '^\d+(\.\d+)?$') then raise exception 'a number of 0 or more is needed'; end if;
  if v_type = 'boolean' and v_txt not in ('true', 'false') then raise exception 'yes or no is needed'; end if;
  if v_type = 'date' and v_txt !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'a date (YYYY-MM-DD) is needed'; end if;
  execute format('select to_jsonb(x.%I) from pipeline.%I x where x.%I::text = $1', p_column, p_table, v_key) into v_before using p_row;
  execute format('update pipeline.%I set %I = $1::%s where %I::text = $2', p_table, p_column, v_type, v_key) using v_txt, p_row;
  if not found then raise exception 'row not found'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', 'change', p_table || '.' || p_column || ':' || p_row, jsonb_build_object('before', v_before, 'after', p_value, 'reason', btrim(p_reason)), auth.uid());
  return public.admin_policy_tables_read();
end $function$;
revoke all on function public.admin_policy_tables_write(text, text, text, jsonb, text) from public, anon;
grant execute on function public.admin_policy_tables_write(text, text, text, jsonb, text) to authenticated;

CREATE OR REPLACE FUNCTION public.admin_toolsets_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'toolsets', (select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'kind', t.kind, 'layers', t.layers, 'enforcement', t.enforcement, 'help', t.help,
        'updated_at', t.updated_at, 'reason', t.reason,
        'key_saved', (select p.vault_secret_id is not null from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'switched_on', (select p.enabled from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'plan', case when exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = t.key and s.key = 'plan_credits') then security.toolset_plan_status(t.key) end,
        'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                        'unit', s.unit, 'section', s.section, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.toolset_key = t.key)) order by t.sort), '[]'::jsonb)
      from pipeline.platform_toolsets t where t.key <> 'pipeline'),  -- v2.15.269: the register shows on Pipeline settings
    'openrouter', jsonb_build_object(
      'balance', (select jsonb_build_object('remaining_usd', o.remaining_usd, 'observed_at', o.observed_at, 'total_credits', o.payload->'total_credits', 'total_usage', o.payload->'total_usage')
                  from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
      -- v2.15.258 (bug 12/10-01): the AI uses that run now, with their daily guards and the credit floor (Layer 3 retired)
      'credit_floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
      'uses', (select coalesce(jsonb_agg(jsonb_build_object('use', g.use, 'label', g.label, 'spent_today', g.spent, 'guard', g.guard, 'calls', g.calls,
                    'allowed', security.ai_use_allowed_v1(g.use))), '[]'::jsonb) from security.ai_spend_today_v1() g),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select r.day, round(sum(r.usd), 4) usd, sum(r.calls) calls from (
                               select (x.at at time zone 'UTC')::date as day, sum(x.cost_usd) usd, count(*) calls from pipeline.scholarship_ai_extractions x where x.at > now() - interval '14 days' group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.uni_adapter_drafts x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.central_ai_queue x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (coalesce(x.decided_at, x.created_at) at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.coverage_ai_match x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1) r
                             group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $function$;

CREATE OR REPLACE FUNCTION security.automation_batch(p_command text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  -- v2.15.269: a job that reads its size from a setting shows that setting
  select coalesce((select (s.value #>> '{}')::int from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = substring(p_command from 'pipeline_num_v1\(''([^'']+)''')),
                  (select s.value::int from pipeline.scholarship_layer_settings s where s.key = substring(p_command from 'scholarship_setting\(''([^'']+)''')),
                  (substring(p_command from '"limit"\s*:\s*(\d+)'))::int, (substring(p_command from '\(\s*(\d+)\s*\)'))::int)
$function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.admin_pipeline_settings_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_fc record;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  select billing_config into v_fc from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  return jsonb_build_object(
    'can_change', security.current_role_rank() >= 6,
    'course_pages', jsonb_build_object(
      -- v2.15.269: job sizes are in the settings register (Pipeline settings › Job sizes)
      'matcher_prepare_universities', security.pipeline_num_v1('batch.ai_match_prepare_universities', null)::int,
      'matcher_prepare_courses', security.pipeline_num_v1('batch.ai_match_prepare_courses', null)::int,
      'matcher_items_per_minute', security.pipeline_num_v1('batch.ai_match', null)::int,
      'matcher_concurrency', security.pipeline_num_v1('concurrency.ai_match', null)::int,
      'search_per_minute', security.pipeline_num_v1('batch.link_search_worker', null)::int,
      'search_monthly_credit_cap', (select monthly_credit_cap from pipeline.course_link_search_settings limit 1),
      'queued', jsonb_build_object('matcher_ready', (select count(*) from pipeline.coverage_ai_match where state = 'ready'),
                                   'matcher_never_offered', (select count(*) from pipeline.coverage_ai_match where state = 'none'),
                                   'searches_queued', (select count(*) from pipeline.course_link_search where state = 'queued')),
      'priority_countries', (select coalesce(jsonb_agg(k.iso_alpha2 order by p.sort), '[]'::jsonb) from pipeline.priority_pins p join ref.countries k on k.id = p.target_id where p.kind = 'country')),
    'reading', jsonb_build_object(
      'read_batch_per_30s', security.pipeline_num_v1('batch.coverage_read', null)::int,
      'pages_waiting', (select count(*) from pipeline.coverage_course_pages where status = 'bound' and read_status is null)),
    'identity', (select jsonb_object_agg(k.iso_alpha2, jsonb_build_object('active', c.active, 'currency', c.currency_code, 'identities', c.identities, 'approved_ref', c.approved_ref))
                   from pipeline.coverage_admission_countries c join ref.countries k on k.id = c.country_id),
    -- v2.15.269: the Layer 3 block is removed (Layer 3 retired 12 Oct 2026)
    'budgets', jsonb_build_object(
      'firecrawl_monthly_limit', (v_fc.billing_config->>'monthly_vendor_units_limit')::int,
      'firecrawl_stop_at_remaining', (v_fc.billing_config->>'stop_at_vendor_units_remaining')::int,
      'firecrawl_used_this_month', (select coalesce(sum(units), 0) from pipeline.coverage_vendor_usage where at >= date_trunc('month', now())),
      'firecrawl_by_purpose', (select jsonb_object_agg(purpose, u) from (select purpose, sum(units) u from pipeline.coverage_vendor_usage where at >= date_trunc('month', now()) group by 1) z),
      'openrouter', (select jsonb_build_object('remaining_usd', remaining_usd, 'observed_at', observed_at) from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1)),
    'recent_changes', (select coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'area', area, 'action', action, 'target', target) order by created_at desc), '[]'::jsonb)
                         from (select * from pipeline.admin_control_events where area in ('settings', 'layer3', 'automations', 'course_link_search', 'requeue') order by created_at desc limit 20) e));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_pipeline_settings_write(p_key text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v int; v_n numeric; v_txt text; v_before jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  v_before := public.admin_pipeline_settings_read();
  case p_key
    -- v2.15.269: job sizes are settings in the register; the job reads them, it is not rewritten
    when 'course_pages.matcher_prepare_universities' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 500 then raise exception 'between 1 and 500'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.ai_match_prepare_universities';
    when 'course_pages.matcher_prepare_courses' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 5000 then raise exception 'between 1 and 5,000'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.ai_match_prepare_courses';
    when 'course_pages.matcher_items_per_minute' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 200 then raise exception 'between 1 and 200'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.ai_match';
    when 'course_pages.matcher_concurrency' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 24 then raise exception 'between 1 and 24'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'concurrency.ai_match';
    when 'course_pages.search_per_minute' then
      v := (p_value#>>'{}')::int; if v < 1 or v > 120 then raise exception 'between 1 and 120'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.link_search_worker';
    when 'course_pages.search_monthly_credit_cap' then
      perform public.admin_course_link_search_settings((p_value#>>'{}')::int);
    when 'reading.read_batch_per_30s' then
      v := (p_value#>>'{}')::int; if v < 10 or v > 200 then raise exception 'between 10 and 200'; end if;
      update pipeline.platform_toolset_settings set value = to_jsonb(v), reason = 'Pipeline settings', updated_by = auth.uid(), updated_at = now() where toolset_key = 'pipeline' and key = 'batch.coverage_read';
    -- v2.15.269: the Layer 3 settings are removed (Layer 3 retired 12 Oct 2026; its jobs no longer exist)
    when 'identity.attribute' then
      if not (p_value->>'attribute') in ('official_url', 'english', 'intakes', 'tuition') then raise exception 'attribute must be official_url, english, intakes or tuition'; end if;
      if exists (select 1 from jsonb_array_elements_text(p_value->'identities') x where x not in ('cricos_code', 'nzqa_code', 'exact_title', 'title_level', 'field_award', 'degree_name')) then raise exception 'unknown identity'; end if;
      update pipeline.coverage_admission_countries c
         set identities = jsonb_set(c.identities, array[p_value->>'attribute'], coalesce(p_value->'identities', '[]'::jsonb), true), updated_at = now(),
             approved_ref = c.approved_ref || format('; Settings page, Platform Admin %s (%s: %s)', to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), p_value->>'attribute', p_value->'identities')
        from ref.countries k where k.id = c.country_id and k.iso_alpha2 = p_value->>'country';
      if not found then raise exception 'country % not found', p_value->>'country'; end if;
    else raise exception 'unknown setting %', p_key;
  end case;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('settings', 'change', p_key, jsonb_build_object('value', p_value, 'before', v_before #> string_to_array(p_key, '.')), auth.uid());
  return public.admin_pipeline_settings_read();
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_read_record(p_course_id uuid, p_read_status text, p_http_status integer, p_fetched_via text, p_identity_basis text, p_storage_path text, p_sha256 text, p_candidates jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security'
AS $function$
declare v_row pipeline.coverage_course_pages%rowtype; v_ev uuid; v_src uuid;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select * into v_row from pipeline.coverage_course_pages where course_id=p_course_id;
  if v_row.course_id is null then raise exception 'course page not bound'; end if;
  -- night run: a page read and confirmed before keeps its reading when a later read fails for a passing reason
  if p_read_status in ('fetch_failed', 'blocked', 'needs_render', 'too_thin', 'not_html') and v_row.read_status = 'read' and v_row.identity_basis is not null and v_row.evidence_id is not null then
    update pipeline.coverage_course_pages set http_status = p_http_status, leased_until = null, next_read_at = case when p_read_status = 'needs_render' then date_trunc('month', now()) + interval '1 month 1 hour' else now() + make_interval(days => security.pipeline_num_v1('retry.course_page_http_failed_days', 7)::int) end where course_id = p_course_id; -- fixed: month roll-over for pages that need a browser
    return jsonb_build_object('evidence_id', null, 'kept_previous_read', true, 'failed_as', p_read_status);
  end if;
  if p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src:=security.coverage_sweep_source(v_row.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id=v_src and content_hash=p_sha256 and source_url=v_row.url limit 1;
    if v_ev is null then
      v_ev:=public.svc_coursefacts_register_evidence(v_src, v_row.url, p_storage_path, p_sha256, 'text/html',
        jsonb_build_object('layer',2,'kind','provider_course_page','worker','coverage-sweep','course_id',p_course_id,'identity_basis',p_identity_basis,'fetched_via',p_fetched_via,'gzip',true));
    end if;
  end if;
  update pipeline.coverage_course_pages set read_status=p_read_status, read_at=now(), http_status=p_http_status, fetched_via=p_fetched_via,
         identity_basis=p_identity_basis, evidence_id=coalesce(v_ev,evidence_id), candidates=p_candidates, leased_until=null,
         next_read_at=case when p_read_status in ('read','identity_mismatch') then now()+make_interval(days => coalesce((select a.read_cycle_days from pipeline.uni_adapters a where a.provider_id=v_row.provider_id), security.pipeline_num_v1('reread.course_page_default_days', 90)::int)) when p_read_status='needs_render' then date_trunc('month',now())+interval '1 month 1 hour' else now()+make_interval(hours => security.pipeline_num_v1('retry.course_page_failed_hours', 6)::int) end, -- fixed: month roll-over
         read_attempts=case when p_read_status='needs_render' then greatest(read_attempts-1,0) else read_attempts end,
         status=case when p_read_status='identity_mismatch' then 'mismatch' when status='ambiguous' and p_identity_basis='cricos_code' then 'bound' else status end,
         basis=case when status='ambiguous' and p_identity_basis='cricos_code' then 'cricos_code_on_page' else basis end
   where course_id=p_course_id;
  return jsonb_build_object('evidence_id',v_ev);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_discovery_record(p_provider_id uuid, p_status text, p_method text, p_url_count integer, p_urls jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_n int:=0;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.coverage_provider_urls(provider_id,url,title,tokens,title_tokens,source)
  select p_provider_id, left(e->>'url',1000), left(e->>'title',300), security.coverage_text_tokens(security.coverage_slug(e->>'url')),
         security.coverage_text_tokens(regexp_replace(coalesce(e->>'title',''),'\s[|–—]\s.*$','')), coalesce(p_method,'map')
    from jsonb_array_elements(coalesce(p_urls,'[]'::jsonb)) e where coalesce(e->>'url','')~'^https?://'
  on conflict (provider_id,url) do update set title=coalesce(excluded.title,pipeline.coverage_provider_urls.title), tokens=excluded.tokens, title_tokens=excluded.title_tokens, last_seen_at=now();
  get diagnostics v_n=row_count;
  update pipeline.coverage_provider_discovery set status=p_status, method=p_method, url_count=p_url_count, kept_count=v_n, last_error=left(p_error,500),
         leased_until=null, mapped_at=case when p_status='mapped' then now() else mapped_at end,
         next_due_at=case when p_status='mapped' then now()+make_interval(days => security.pipeline_num_v1('remap.site_days', 30)::int) when p_status='failed' then now()+make_interval(hours => security.pipeline_num_v1('retry.site_map_failed_hours', 6)::int) else null end, updated_at=now()
   where provider_id=p_provider_id;
  return jsonb_build_object('kept',v_n);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_site_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select d.provider_id from pipeline.coverage_provider_discovery d
     where d.status='no_website' and coalesce(d.site_searched_at,'-infinity')<now()-make_interval(days => security.pipeline_num_v1('retry.no_website_days', 30)::int) and coalesce(d.leased_until,'-infinity')<now()
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (d.requested_at is null), d.requested_at, (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc
     limit greatest(1,least(coalesce(p_limit,5),20)) for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes' from pick where d.provider_id=pick.provider_id returning d.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'name',coalesce(p.display_name,p.canonical_name),'trading',p.short_name,
           'cricos',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='cricos'),'country',security.coverage_country(u.provider_id),
           'dli',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='ircc_dli'))),'[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id=u.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_site_record(p_provider_id uuid, p_website text, p_evidence jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v_dom text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- v2.15.245: no credit to spend: searched again in a day; nothing else is recorded
  if coalesce(p_evidence->>'note', '') ilike '%budget%' then
    update pipeline.coverage_provider_discovery set leased_until=null, site_searched_at=now()-make_interval(days => greatest(0, security.pipeline_num_v1('retry.no_website_days', 30)::int - security.pipeline_num_v1('retry.website_after_budget_days', 1)::int)), site_evidence=p_evidence, updated_at=now() where provider_id=p_provider_id;
    return;
  end if;
  -- v2.15.232 (Fix 3): a course finder address entered by hand is kept; the search result is stored as evidence only
  if exists (select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p_provider_id and l.field='course_finder')
     or exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id=p_provider_id and d.site_source='manual') then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence, updated_at=now() where provider_id=p_provider_id;
    return;
  end if;
  -- v2.15.233 (Feature 1): a course directory or other third-party site is never recorded as the provider's site
  if nullif(p_website,'') is not null and security.third_party_host_v1(p_website) then
    update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, updated_at=now(),
           site_evidence=coalesce(p_evidence,'{}'::jsonb)||jsonb_build_object('refused', p_website, 'refused_why', 'third-party site, not the provider''s own')
     where provider_id=p_provider_id;
    return;
  end if;
  update pipeline.coverage_provider_discovery set site_searched_at=now(), leased_until=null, site_evidence=p_evidence,
         website=coalesce(nullif(p_website,''),website), site_source=case when nullif(p_website,'') is not null then coalesce('search_verified_'||nullif(p_evidence->>'basis',''),'search_verified_cricos_code') else site_source end,
         status=case when nullif(p_website,'') is not null then 'pending' else status end, attempts=case when nullif(p_website,'') is not null then 0 else attempts end,
         requested_at=null, updated_at=now()
   where provider_id=p_provider_id;
  -- v2.15.245 (Platform Admin, 11 Oct 2026): a website found and verified goes on the provider's record, with its follow-on work
  if nullif(p_website,'') is not null then perform security.provider_website_adopt_v1(p_provider_id, p_website); end if;
  -- Decision 220: a Canadian site gets the generic recipe for its own .ca domain, and its active courses with no
  -- candidate page are queued for the course-page search by title.
  if nullif(p_website,'') is not null and security.coverage_country(p_provider_id) = 'CA' then
    v_dom := lower(regexp_replace(substring(btrim(p_website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
    if v_dom ~ '^[a-z0-9.-]+\.ca$' then
      insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
      select p_provider_id, v_dom,
             jsonb_build_array(jsonb_build_object(
               're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                     || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
               'rep', '\&')),
             true, 'Generic recipe: any page on the provider''s own site; used only when the reader proves the page is the course''s (CA, Decision 220, 2 Oct 2026)', now()
       where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      select c.id, c.provider_id, 'title', 'queued', now()
        from catalogue.courses c
       where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
         and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
      on conflict (course_id) do nothing;
    end if;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_read_record(p_scholarship_id uuid, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_ev uuid; v_src uuid; v_pid uuid; v_url text; r jsonb; v_ai boolean := coalesce((select s.ai_admission from pipeline.scholarship_ai_extract_settings s where s.id=1),false) and exists (select 1 from pipeline.scholarship_ai_models m where m.status='active');
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, p.url into v_pid, v_url from scholarship.scholarships s join pipeline.scholarship_pages p on p.scholarship_id=s.id where s.id=p_scholarship_id;
  if p_storage_path is not null and p_read_status='read' then
    v_src:=security.coverage_sweep_source(v_pid);
    -- unchanged page: reuse its evidence; changed page: next capture version, superseding the previous one
    select e.id into v_ev from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id and e.content_hash=p_sha256 order by e.capture_version desc limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key,supersedes_evidence_id)
      select p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
             jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'),
             coalesce((select max(e.capture_version) from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id),0)+1,
             'scholarship:'||p_scholarship_id,
             (select e.id from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id order by e.capture_version desc limit 1)
      returning id into v_ev;
    end if;
  end if;
  update pipeline.scholarship_pages set requested_at=case when p_read_status='waiting_scraper' then requested_at end, read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, evidence_id=case when p_read_status='read' then coalesce(v_ev,evidence_id) else evidence_id end,
         -- v2.15.249: with AI admission on, an AI-read page keeps its AI facts; the rule-read facts are kept under 'rules'
         facts=case when p_read_status='read' then case when v_ai and facts->>'extracted_by'='ai' then facts || jsonb_build_object('rules', p_facts) else coalesce(p_facts,facts) end else facts end,
         name_check=case when p_facts ? 'name_check' then p_facts->'name_check' else name_check end,
         -- 11 Oct 2026: pages are read through the scraper only; one waiting for the scraper (no credit or service) is tried again
         -- within the hour and does not use up its attempts; a blocked page is tried again in 2 days
         next_read_at=case when p_read_status='read' then now()+make_interval(days => security.pipeline_num_v1('reread.scholarship_page_days', 90)::int)
                           when p_read_status='name_mismatch' then now()+make_interval(days => security.pipeline_num_v1('retry.scholarship_name_mismatch_days', 30)::int)
                           when p_read_status='blocked' then now()+make_interval(days => security.pipeline_num_v1('retry.scholarship_blocked_days', 2)::int)
                           when p_read_status='waiting_scraper' then now()+make_interval(hours => security.pipeline_num_v1('retry.scholarship_waiting_scraper_hours', 1)::int)
                           else now()+make_interval(hours => security.pipeline_num_v1('retry.scholarship_failed_hours', 6)::int) end,
         attempts=case when p_read_status='read' then 0 when p_read_status='waiting_scraper' then greatest(attempts-1,0) else attempts end
   where scholarship_id=p_scholarship_id;
  -- v2.15.249 (bugs 11/10-6): with AI admission on, the AI reads the page again and decides; the rules no longer withdraw or apply
  if p_read_status='read' and v_ai then
    insert into pipeline.scholarship_ai_queue(model_code,prompt_version,run_kind,scholarship_id,provider_id,url)
    select a.model_code,a.prompt_version,'reread',p_scholarship_id,v_pid,coalesce(p_final_url,v_url) from security.scholarship_ai_active_v1() a
     where not exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id=p_scholarship_id and q.state in ('queued','leased'));
    r:=jsonb_build_object('applied',false,'ai','queued');
  -- an admitted page that no longer meets the admission rules is withdrawn, not applied
  elsif p_read_status='read' and p_facts ? 'admission' and coalesce((p_facts->'admission'->>'admit')::boolean,true) is false
     and exists (select 1 from pipeline.scholarship_pages where scholarship_id=p_scholarship_id and url_source='admitted') then
    r:=security.scholarship_admission_withdraw_v1(p_scholarship_id, jsonb_build_object('reasons',p_facts->'admission'->'reasons','extractor',p_facts->>'extractor'));
  elsif p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;
  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried
  if p_read_status='name_mismatch' then
    update pipeline.scholarship_page_candidates c set match_basis='rejected_name_mismatch', matched_scholarship_id=null
      from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id and sp.url_source='discovered' and c.id=sp.candidate_id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
    select p_scholarship_id,'provider_page_rejected',jsonb_build_object('url',sp.url,'url_source',sp.url_source),p_facts->'name_check' from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id;
  end if;
  return coalesce(r,jsonb_build_object('applied',false));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_record(p_candidate_id bigint, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r jsonb; c pipeline.scholarship_page_candidates%rowtype; v_ev uuid; v_ai boolean := coalesce((select s.ai_admission from pipeline.scholarship_ai_extract_settings s where s.id=1),false) and exists (select 1 from pipeline.scholarship_ai_models m where m.status='active');
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if p_read_status='deferred' then -- out of time in this run: back to the queue unchanged
    update pipeline.scholarship_page_candidates set leased_until=null, attempts=greatest(0,attempts-1) where id=p_candidate_id;
    return jsonb_build_object('admitted',false,'deferred',true);
  end if;
  update pipeline.scholarship_page_candidates set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, storage_path=coalesce(p_storage_path,storage_path), content_hash=coalesce(p_sha256,content_hash), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status in ('read','robots_disallowed','gone') then now()+make_interval(days => security.pipeline_num_v1('reread.scholarship_candidate_days', 90)::int) else now()+make_interval(hours => security.pipeline_num_v1('retry.scholarship_candidate_failed_hours', 6)::int) end,
         admit_status=case when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true then 'rejected' else admit_status end,
         admit_reasons=case when not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) is not true
                            then array(select jsonb_array_elements_text(coalesce(p_facts->'admission'->'reasons','[]'))) else admit_reasons end
   where id=p_candidate_id;
  if not v_ai and p_read_status='read' and coalesce((p_facts->'admission'->>'admit')::boolean,false) then r:=security.scholarship_admit_from_provider_page_v1(p_candidate_id); end if;
  -- v2.15.249 (bugs 11/10-6): with AI admission on, the AI decides every page read (its copy is kept), not the rules
  if v_ai and p_read_status in ('read','too_thin') and p_storage_path is not null then
    insert into pipeline.scholarship_ai_queue(model_code,prompt_version,run_kind,candidate_id,provider_id,url)
    select a.model_code,a.prompt_version,'admit',p_candidate_id,(select x.provider_id from pipeline.scholarship_page_candidates x where x.id=p_candidate_id),coalesce(p_final_url,(select x.url from pipeline.scholarship_page_candidates x where x.id=p_candidate_id))
      from security.scholarship_ai_active_v1() a where not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id=p_candidate_id and q.state in ('queued','leased'));
    r:=jsonb_build_object('admitted',false,'ai','queued');
  end if;
  select * into c from pipeline.scholarship_page_candidates where id=p_candidate_id;
  -- v2.15.248 (Platform Admin bugs 11/10-5, Fix 2): a stored page that did not become a scholarship is kept as evidence of the decision
  if c.storage_path is not null and c.evidence_id is null and coalesce(c.admit_status,'')<>'admitted' then
    insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
    values (security.coverage_sweep_source(c.provider_id),'scholarship_candidate_page',coalesce(c.final_url,c.url),c.storage_path,c.content_hash,'application/gzip',
            jsonb_build_object('candidate_id',c.id,'provider_id',c.provider_id,'read_status',c.read_status,'decision',coalesce(c.admit_status,c.read_status),'reasons',to_jsonb(coalesce(c.admit_reasons,'{}'::text[])),'worker','coverage-sweep scholarship candidates'),1,'scholarship_candidate:'||c.id)
    returning id into v_ev;
    update pipeline.scholarship_page_candidates set evidence_id=v_ev where id=c.id;
  end if;
  -- (Fix 4) a page that lists scholarships is suggested as the provider's listing page, for a person to confirm
  if coalesce(c.admit_status,'')<>'admitted' and c.read_status in ('read','too_thin')
     and (coalesce(c.facts->>'h1','')||' '||coalesce(c.title,'')||' '||coalesce(c.facts->>'page_title','') ~* '(scholarships? (finder|search|list|directory)|grants and scholarships|find (a|your) scholarship|^\s*scholarships\s*$)'
          or coalesce(c.admit_reasons,'{}') && array['listing_page'] or c.url ~* '(scholarship-finder|/scholarships?/?$|/grants-scholarships/?$)') then
    insert into pipeline.scholarship_listing_pages(provider_id,url,url_norm,source,active,status)
    values (c.provider_id,coalesce(c.final_url,c.url),security.scholarship_url_norm(coalesce(c.final_url,c.url)),'suggested',false,'suggested')
    on conflict (provider_id,url_norm) do nothing;
  end if;
  return coalesce(r, jsonb_build_object('admitted',false));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_listing_record(p_id bigint, p_status text, p_http_status integer, p_items jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_items jsonb := case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end; v_hash text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select md5(coalesce(string_agg(lower(btrim(e->>'name')), '|' order by lower(btrim(e->>'name'))), '')) into v_hash from jsonb_array_elements(v_items) e;
  update pipeline.scholarship_listing_pages
     set status = case when p_status = 'read' then 'read' else 'failed' end, http_status = p_http_status, read_at = now(), error = left(p_error, 300),
         items = case when p_status = 'read' then v_items else items end, item_hash = case when p_status = 'read' then v_hash else item_hash end,
         next_read_at = case when p_status = 'read' then now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_listing_days', 7)::int) else now() + make_interval(days => security.pipeline_num_v1('retry.scholarship_listing_failed_days', 1)::int) end
   where id = p_id;
  return jsonb_build_object('ok', true, 'items', jsonb_array_length(v_items));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_record(p_queue_id bigint, p_answer jsonb, p_checks jsonb, p_verdict text, p_cost numeric, p_tokens_in integer, p_tokens_out integer, p_seconds numeric, p_error text, p_storage_path text, p_sha256 text, p_final_url text, p_rule_facts jsonb, p_retry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare q pipeline.scholarship_ai_queue%rowtype; v_id bigint; v_ev uuid; v_on boolean; r jsonb; v_why text; v_next text; v_prev record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.scholarship_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'no queue item'); end if;
  if p_retry then
    update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = greatest(attempts - 1, 0), next_try_at = now() + interval '30 minutes' where id = q.id;
    return jsonb_build_object('ok', true, 'retry', true);
  end if;
  -- v2.15.256: a value an earlier model in this chain proved stands when this model's value is not proven (its own proven value wins)
  if p_error is null and p_verdict = 'scholarship' and not coalesce((p_checks->>'value')::boolean, false)
     and coalesce(p_answer->'value'->>'kind', 'not_stated') not in ('not_stated', 'non_monetary') then
    select e.answer->'value' val, e.model_code into v_prev from pipeline.scholarship_ai_extractions e join pipeline.scholarship_ai_queue x on x.id = e.queue_id
     where coalesce(x.root_id, x.id) = coalesce(q.root_id, q.id) and x.id <> q.id and e.verdict = 'scholarship' and e.error is null
       and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1;
    if v_prev.val is not null then
      p_answer := jsonb_set(p_answer, '{value}', v_prev.val) || jsonb_build_object('value_from', v_prev.model_code);
      p_checks := p_checks || jsonb_build_object('value', true);
    end if;
  end if;
  -- a candidate page read live for the first time: its copy and read are recorded on the candidate, as the scheduled reader does
  if q.candidate_id is not null and p_storage_path is not null then
    update pipeline.scholarship_page_candidates set storage_path = p_storage_path, content_hash = p_sha256, final_url = coalesce(p_final_url, final_url), read_at = now(),
           read_status = coalesce(nullif(p_rule_facts->>'read_status', ''), 'read'), next_read_at = now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_ai_days', 90)::int), leased_until = null,
           facts = case when p_rule_facts ? 'facts' then p_rule_facts->'facts' else facts end
     where id = q.candidate_id;
  end if;
  if p_storage_path is not null then
    insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
    values (security.coverage_sweep_source(q.provider_id), 'scholarship_ai_page', coalesce(p_final_url, q.url), p_storage_path, p_sha256, 'application/gzip',
            jsonb_build_object('queue_id', q.id, 'candidate_id', q.candidate_id, 'scholarship_id', q.scholarship_id, 'model', q.model_code, 'worker', 'coverage-sweep scholarship_ai'), 1, 'scholarship_ai:' || q.id)
    returning id into v_ev;
    if q.candidate_id is not null then update pipeline.scholarship_page_candidates set evidence_id = coalesce(evidence_id, v_ev) where id = q.candidate_id; end if;
  end if;
  insert into pipeline.scholarship_ai_extractions(queue_id, model_code, model_identifier, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url,
         storage_path, content_hash, evidence_id, answer, checks, verdict, cost_usd, tokens_in, tokens_out, seconds, error)
  values (q.id, q.model_code, (select m.model_identifier from pipeline.scholarship_ai_models m where m.code = q.model_code), q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id,
          coalesce(p_final_url, q.url), coalesce(p_storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = q.candidate_id)), p_sha256,
          coalesce(v_ev, (select c.evidence_id from pipeline.scholarship_page_candidates c where c.id = q.candidate_id), (select sp.evidence_id from pipeline.scholarship_pages sp where sp.scholarship_id = q.scholarship_id)),
          p_answer, p_checks, p_verdict, p_cost, p_tokens_in, p_tokens_out, p_seconds, p_error)
  returning id into v_id;
  -- v2.15.250 (bugs 11/10-6 follow-up): an unsettled answer (failed reply, name not proven, or a stated fact not proven by its quote)
  -- goes to the next model in the chain, on the same stored copy; after the last model it goes to Layer 4 while AI admission is on
  v_why := case when q.run_kind in ('admit', 'reread') then security.scholarship_ai_unsettled_v1(p_answer, p_checks, p_verdict, p_error) end;
  -- v2.15.250 (23:50): an answer that would admit is confirmed by the next model while confirm_admissions is on
  if v_why is null and q.run_kind in ('admit', 'reread') and p_error is null and p_verdict = 'scholarship' and p_answer->>'audience' in ('international', 'both')
     and coalesce((p_checks->>'audience')::boolean, false) and coalesce(p_answer->>'offered', '') <> 'no'
     and coalesce((select s.confirm_admissions from pipeline.scholarship_ai_extract_settings s where s.id = 1), true)
     and security.scholarship_ai_next_model_v1(q.model_code) is not null then
    v_why := 'a second model confirms each admission';
  end if;
  v_next := case when v_why is not null then security.scholarship_ai_next_model_v1(q.model_code) end;
  if v_next is not null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url, step, storage_path, root_id)
    values (v_next, q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id, coalesce(p_final_url, q.url), q.step + 1,
            coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id));
    return jsonb_build_object('ok', true, 'extraction', v_id, 'escalated_to', v_next, 'why', v_why);
  end if;
  update pipeline.scholarship_ai_queue set state = case when p_error is null or attempts >= 3 then 'done' else 'queued' end, done_at = case when p_error is null or attempts >= 3 then now() end,
         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id where id = q.id;
  select ai_admission into v_on from pipeline.scholarship_ai_extract_settings where id = 1;
  if v_on and v_why is not null and (p_error is null or q.attempts >= 3) then r := security.scholarship_ai_review_open_v1(v_id, v_why);
  elsif p_error is null and v_on and q.run_kind in ('admit', 'reread') then r := security.scholarship_ai_apply_v1(v_id); end if;
  return jsonb_build_object('ok', true, 'extraction', v_id, 'applied', r);
end $function$;

CREATE OR REPLACE FUNCTION security.fc_search_stopped_v1()
 RETURNS TABLE(provider_id uuid, searches bigint, since timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with s as (
  with w as (select u.provider_id, greatest(now() - make_interval(days => security.fc_setting_num_v1('search_stop_window_days', 7)::int), coalesce(max(r.resumed_at), '-infinity'::timestamptz)) since
               from (select distinct x.provider_id from pipeline.coverage_vendor_usage x where x.purpose = 'course_link_search' and x.at > now() - make_interval(days => security.fc_setting_num_v1('search_stop_window_days', 7)::int)) u
               left join pipeline.firecrawl_search_resumes r on r.provider_id = u.provider_id group by u.provider_id)
  select w.provider_id, count(*) searches, w.since
    from w join pipeline.coverage_vendor_usage x on x.provider_id = w.provider_id and x.purpose = 'course_link_search' and x.at > w.since and x.at < now() - interval '1 hour' -- fixed: searches still in flight are not counted
   where not exists (select 1 from pipeline.coverage_course_pages pg where pg.provider_id = w.provider_id and pg.read_at > w.since and pg.status = 'bound' and pg.read_status = 'read')
   group by w.provider_id, w.since
  having count(*) >= security.fc_setting_num_v1('search_stop_after', 30))
  select s.provider_id, s.searches, s.since from s
  union all
  -- v2.15.265: held by the Platform Admin for an adapter check, until Search again
  select h.provider_id, 0::bigint, h.held_at from pipeline.firecrawl_search_holds h
   where not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at)
     and h.provider_id not in (select s2.provider_id from s s2)
$function$;

CREATE OR REPLACE FUNCTION security.provider_onboarding_step_v1(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o pipeline.provider_onboarding%rowtype; p catalogue.providers%rowtype; j pipeline.admin_jobs%rowtype; d pipeline.uni_adapter_drafts%rowtype;
        v_courses int; v_read int; v_need int; v_r jsonb; v_prop jsonb; v_adapter jsonb; v_q jsonb; v_rd jsonb; v_b jsonb; v_s record; v_central jsonb := '[]'::jsonb;
        v_age interval; v_central_n int := 0; v_en jsonb; v_aiq int; v_rev int; v_found int; v_pub int;
begin
  select * into o from pipeline.provider_onboarding where id = p_id for update skip locked;
  if o.id is null then return; end if;
  select * into p from catalogue.providers where id = o.provider_id;
  v_age := now() - coalesce(o.step_started_at, now());
  if p.id is null or p.lifecycle_status <> 'active' then
    update pipeline.provider_onboarding set status = 'cancelled', note = 'The university is no longer active.', finished_at = now(), updated_at = now() where id = o.id; return;
  end if;
  select count(*) into v_courses from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active';
  select count(*) into v_read from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_status = 'read';
  v_need := least(3, greatest(v_courses, 1));
  if o.job_id is not null then select * into j from pipeline.admin_jobs where id = o.job_id; end if;

  if o.status = 'queued' then
    update pipeline.provider_onboarding set status = 'website', started_at = coalesce(started_at, now()), step_started_at = now(), job_id = null, note = 'Finding the website, contacts and central pages.', updated_at = now() where id = o.id;

  elsif o.status = 'website' then
    if j.id is null then
      if nullif(p.website, '') is not null and exists (select 1 from pipeline.admin_jobs x where x.kind = 'provider_fill' and x.scope = o.provider_id::text and x.state = 'done' and x.finished_at > now() - make_interval(days => security.pipeline_num_v1('onboarding.provider_fill_valid_days', 30)::int)) then
        update pipeline.provider_onboarding set status = 'course_pages', step_started_at = now(), job_id = null, note = 'Website known; finding course pages.', updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set job_id = security.provider_onboarding_job_v1('provider_fill', o.provider_id, jsonb_build_object('provider_id', o.provider_id, 'scope', o.provider_id)),
               step_started_at = now(), note = 'Finding the website, contacts and central pages (Fill in from website).', updated_at = now() where id = o.id;
      end if;
    elsif j.state in ('done', 'failed', 'cancelled') then
      if nullif(p.website, '') is null then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'no_website', job_id = null,
               note = 'No website could be verified. Enter it in Layer 4 › Websites to find (or the Adapter builder); onboarding carries on by itself.', updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set status = 'course_pages', step_started_at = now(), job_id = null, result = result || jsonb_build_object('website', p.website), note = 'Website found; finding course pages.', updated_at = now() where id = o.id;
      end if;
    end if;

  elsif o.status in ('course_pages', 'waiting_courses') then
    if v_courses = 0 then
      update pipeline.provider_onboarding set status = 'waiting_courses', note = 'No active courses yet; onboarding carries on when its courses arrive from the register.', updated_at = now() where id = o.id;
    elsif v_read >= v_need and exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and not a.enabled) then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'adapter_off', note = 'An adapter exists but is switched off; open it in Layer 2 › Adapters (onboarding does not overwrite it).', updated_at = now() where id = o.id;
    elsif v_read >= v_need and exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled) then
      -- an adapter already exists (built by hand or earlier): apply it again and qualify, never overwrite its settings
      perform public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: apply the existing adapter again'));
      update pipeline.provider_onboarding set status = 'applying', step_started_at = now(), job_id = null, result = result || jsonb_build_object('pages_read', v_read, 'courses', v_courses, 'existing_adapter', true),
             note = 'An adapter already exists; applying it again before qualifying.', updated_at = now() where id = o.id;
    elsif v_read >= v_need then
      v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: capture sample pages'));
      update pipeline.provider_onboarding set status = 'capturing', step_started_at = now(), job_id = null, draft_id = (v_r->>'draft_id')::uuid,
             result = result || jsonb_build_object('pages_read', v_read, 'courses', v_courses, 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0) + 1), note = format('%s course pages read; capturing sample pages.', v_read), updated_at = now() where id = o.id;
    elsif j.id is null then
      -- v2.15.253 fix: a website recorded before generic recipes existed has none; add the generic one (any page on its own site)
      if not exists (select 1 from pipeline.course_link_recipes r where r.provider_id = o.provider_id and r.active) and nullif(p.website, '') is not null then
        insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
        select o.provider_id, x.dom, jsonb_build_array(jsonb_build_object(
                 're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(x.dom, '\.', '\\.', 'g') || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
                 'rep', '\&')), true,
               'Generic recipe: any page on the provider''s own site (onboarding, CF-247 v2.15.253); used only when the reader proves the page is the course''s', now()
          from (select lower(regexp_replace(substring(p.website from '^(?:https?://)?([^/:?#]+)'), '^www\.', '')) dom) x
         where x.dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        on conflict (provider_id) do update set search_domain = excluded.search_domain, patterns = excluded.patterns, active = true, notes = excluded.notes, updated_at = now()
         where not pipeline.course_link_recipes.active
           and (pipeline.course_link_recipes.notes like 'Generic recipe%' or pipeline.course_link_recipes.search_domain is distinct from excluded.search_domain);
      end if;
      -- v2.15.254: a recipe switched off for this same site is a person's decision; stop with a plain reason instead of an error
      if not exists (select 1 from pipeline.course_link_recipes r where r.provider_id = o.provider_id and r.active)
         and exists (select 1 from pipeline.course_link_recipes r where r.provider_id = o.provider_id) then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'recipe_off', job_id = null,
               note = 'Its course-page search was switched off by a person for this website (' || coalesce((select r.search_domain from pipeline.course_link_recipes r where r.provider_id = o.provider_id), '?') || '). Check the website in the Adapter builder (1.1); entering a different website replaces the search, then Retry.',
               updated_at = now() where id = o.id;
        return;
      end if;
      insert into pipeline.firecrawl_targets(provider_id, included, reason, set_by, set_at) values (o.provider_id, true, 'Onboarding: find and read its course pages', auth.uid(), now())
      on conflict (provider_id) do update set included = true, reason = excluded.reason, set_by = excluded.set_by, set_at = now();
      update pipeline.provider_onboarding set status = 'course_pages', job_id = security.provider_onboarding_job_v1('course_page_find', o.provider_id, jsonb_build_object('provider_id', o.provider_id, 'scope', o.provider_id,
               -- at most 300 courses in one task: the courses without a read page, largest sample of kinds first
               'course_ids', (select coalesce(jsonb_agg(c.id), '[]'::jsonb) from (select c.id from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active'
                               and not exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = c.id and pg.read_status = 'read') order by c.id limit security.pipeline_num_v1('onboarding.sample_courses', 300)::int) c))),
             step_started_at = now(), note = format('Searching for course pages (%s of %s needed read so far).', v_read, v_need), updated_at = now() where id = o.id;
    elsif j.state in ('done', 'failed', 'cancelled') and v_age > interval '90 minutes'
          -- v2.15.256: not while pages the search found are still waiting to be read (up to 6 hours);
          -- v2.15.260 (keep moving): nor when no page of it has been read for an hour; it carries on by itself when its pages are read
          and (v_age > make_interval(hours => security.pipeline_num_v1('onboarding.course_search_wait_hours', 6)::int) or not exists (select 1 from pipeline.course_link_search s where s.provider_id = o.provider_id and s.state in ('queued', 'sent', 'found'))
               or not exists (select 1 from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_at > now() - interval '60 minutes')) then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'too_few_pages', job_id = null,
             note = format('Only %s of %s course pages could be read (%s needed). The next university starts; this one carries on by itself once enough of its pages are read, or add pages in the Adapter builder (2.1).', v_read, v_courses, v_need), updated_at = now() where id = o.id;
    elsif j.state not in ('done', 'failed', 'cancelled') then
      update pipeline.provider_onboarding set note = format('Searching for course pages: %s of %s needed read so far.', v_read, v_need), updated_at = now() where id = o.id;
    else
      update pipeline.provider_onboarding set note = format('Search finished; waiting for pages to be read (%s of %s needed).', v_read, v_need), updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'capturing' then
    select * into d from pipeline.uni_adapter_drafts where id = o.draft_id;
    if d.status = 'captured' then
      if not exists (select 1 from jsonb_array_elements(coalesce(d.captures, '[]'::jsonb)) c where not (c ? 'error')) then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'capture_failed', note = 'None of the sample pages could be captured.', updated_at = now() where id = o.id;
      else
        v_b := security.adapter_builder_budget();
        if (v_b->>'used_usd')::numeric >= (v_b->>'limit_usd')::numeric or (v_b->>'proposals')::int >= (v_b->>'limit_proposals')::int then
          -- v2.15.260 (keep moving): the next university starts; this one carries on by itself when the allowance renews
          update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'ai_allowance', job_id = null,
                 note = 'The adapter AI allowance for today is used. The next university starts; this one carries on by itself when it renews (midnight, Melbourne time).', updated_at = now() where id = o.id;
        else
          perform public.admin_adapter_builder('propose', jsonb_build_object('provider_id', o.provider_id, 'draft_id', o.draft_id, 'marks', '[]'::jsonb,
                   'comments', 'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.'
                   || coalesce(' The current settings did not pass: ' || (select string_agg(e.key || ': ' || e.value, '; ' order by e.key) from jsonb_each_text(coalesce(o.result->'held', '{}'::jsonb)) e) || '. Widen the patterns so each field is read on most course pages.', ''),
                   'reason', 'Onboarding: propose the adapter'));
          update pipeline.provider_onboarding set status = 'proposing', attempts = 0, step_started_at = now(), note = format('The pinned model (%s) is proposing the settings.', coalesce(nullif(d.model, ''), v_b->>'model')), updated_at = now() where id = o.id;
        end if;
      end if;
    elsif d.status = 'error' or v_age > interval '30 minutes' then
      if o.attempts < 1 then
        v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: capture sample pages again'));
        update pipeline.provider_onboarding set attempts = attempts + 1, step_started_at = now(), draft_id = (v_r->>'draft_id')::uuid, note = 'Capturing the sample pages again.', updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'capture_failed', note = 'Capturing the sample pages did not finish (' || coalesce(d.status, 'no draft') || ').', updated_at = now() where id = o.id;
      end if;
    end if;

  elsif o.status = 'proposing' then
    select * into d from pipeline.uni_adapter_drafts where id = o.draft_id;
    v_prop := d.proposals -> -1;
    if d.status = 'proposed' and v_prop is not null then
      if (v_prop->>'kind' = 'error' or v_prop->'adapter' is null) and o.attempts < security.pipeline_num_v1('onboarding.proposal_attempts', 2) then
        perform public.admin_adapter_builder('propose', jsonb_build_object('provider_id', o.provider_id, 'draft_id', o.draft_id, 'marks', '[]'::jsonb,
                 'comments', 'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.', 'reason', 'Onboarding: propose the adapter again'));
        update pipeline.provider_onboarding set attempts = attempts + 1, step_started_at = now(), note = 'The proposal failed; asking the model again.', updated_at = now() where id = o.id;
      elsif v_prop->>'kind' = 'error' or v_prop->'adapter' is null then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'proposal_failed', note = 'The model could not propose settings: ' || left(coalesce(v_prop->>'error', 'no settings returned'), 300), updated_at = now() where id = o.id;
      else
        v_adapter := coalesce(security.uni_adapter_json(o.provider_id), '{}'::jsonb) - 'updated_at' - 'reason'
                     || jsonb_strip_nulls(jsonb_build_object('json_source', v_prop->'adapter'->'json_source'))
                     || jsonb_build_object('json_paths', coalesce(security.uni_adapter_json(o.provider_id)->'json_paths', '{}'::jsonb) || coalesce(v_prop->'adapter'->'json_paths', '{}'::jsonb),
                                           'patterns', coalesce(security.uni_adapter_json(o.provider_id)->'patterns', '{}'::jsonb) || coalesce(v_prop->'adapter'->'patterns', '{}'::jsonb),
                                           'pick', coalesce(security.uni_adapter_json(o.provider_id)->'pick', '{}'::jsonb) || coalesce(v_prop->'adapter'->'pick', '{}'::jsonb),
                                           'enabled', true);
        perform public.admin_uni_adapter_write('save', jsonb_build_object('provider_id', o.provider_id, 'adapter', v_adapter, 'reason', 'Onboarding: settings proposed by the pinned model'));
        perform public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: apply to the stored pages'));
        update pipeline.provider_onboarding set status = 'applying', step_started_at = now(), result = result || jsonb_build_object('proposal_cost', v_prop->'cost', 'model', v_prop->'model'),
               note = 'Saved (switched on, testing, nothing admitted) and applying to the stored pages.', updated_at = now() where id = o.id;
      end if;
    elsif (d.status = 'error' or (d.status = 'proposed' and v_prop->>'kind' = 'error') or (d.status = 'proposing' and v_age > interval '30 minutes')) and o.attempts < security.pipeline_num_v1('onboarding.proposal_attempts', 2) then
      -- a failed answer (for example no answer from the model), or none after 30 minutes (v2.15.254), is asked again, twice at most
      perform public.admin_adapter_builder('propose', jsonb_build_object('provider_id', o.provider_id, 'draft_id', o.draft_id, 'marks', '[]'::jsonb,
               'comments', 'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.', 'reason', 'Onboarding: propose the adapter again'));
      update pipeline.provider_onboarding set attempts = attempts + 1, step_started_at = now(), note = 'The proposal failed; asking the model again.', updated_at = now() where id = o.id;
    elsif d.status = 'error' or v_age > interval '30 minutes' then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'proposal_failed', note = 'The proposal did not finish: ' || left(coalesce(v_prop->>'error', d.status), 200), updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'applying' then
    if v_age > interval '90 minutes' or (v_age > interval '10 minutes' and not exists (select 1 from pipeline.uni_adapter_results r where r.provider_id = o.provider_id and r.at > now() - interval '5 minutes')) then
      update pipeline.provider_onboarding set status = 'qualifying', step_started_at = now(), note = 'Qualifying each field against the admit rule.', updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'qualifying' then
    v_q := security.adapter_qualify_one_v1(o.provider_id, coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5), coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9));
    v_rd := security.provider_onboarding_ready_v1(v_q);
    -- v2.15.255: nothing passes and fewer than 2 AI attempts in this onboarding: the AI proposes again (6, then 10 sample pages),
    -- told which fields did not pass; the proposal is merged over the current settings (an old adapter included)
    if jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) = 0 and coalesce((o.result->>'ai_attempts')::int, 0) < 2 and v_read >= v_need then
      v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', o.provider_id, 'samples', case when coalesce((o.result->>'ai_attempts')::int, 0) = 0 then 6 else 10 end,
               'reason', 'Onboarding: no field passes; the AI proposes again'));
      update pipeline.provider_onboarding set status = 'capturing', step_started_at = now(), job_id = null, draft_id = (v_r->>'draft_id')::uuid, attempts = 0,
             result = result || jsonb_build_object('qualify', v_q, 'ready', v_rd->'ready', 'held', v_rd->'held', 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0) + 1),
             note = format('No field passes yet; the AI proposes settings from %s sample pages (AI attempt %s of 2).', case when coalesce((o.result->>'ai_attempts')::int, 0) = 0 then 6 else 10 end, coalesce((o.result->>'ai_attempts')::int, 0) + 1),
             updated_at = now() where id = o.id;
      return;
    end if;
    -- central pages: the Firecrawl map's suggestions first, then the provider's stored links; approved by a person in the Adapter builder (1.3)
    for v_s in select distinct on (s.kind) s.kind, s.url from (
                 select f.value->>'kind' kind, f.value->>'url' url, 1 pri from pipeline.provider_central_search c
                   cross join lateral jsonb_array_elements(case jsonb_typeof(c.found) when 'array' then c.found else '[]'::jsonb end) f(value)
                  where c.provider_id = o.provider_id and f.value->>'kind' in ('intake_calendar', 'fee_schedule', 'english_policy') and f.value->>'url' is not null
                    and coalesce((f.value->>'score')::numeric, 0) >= 4
                 union all
                 select x.kind, u.url, 2 from pipeline.coverage_provider_urls u cross join lateral (select case
                   when u.url ~* '(key-?dates|academic-?calendar|semester-?dates|term-?dates|important-?dates|principal-?dates)' then 'intake_calendar'
                   when u.url ~* '(international.*(fee|tuition)|(fee|tuition).*international|fee-?schedule|tuition-?fees)' then 'fee_schedule'
                   when u.url ~* '(english-?language-?requirement|english-?requirement|english-?proficiency)' then 'english_policy' end kind) x
                  where u.provider_id = o.provider_id and x.kind is not null) s
               where not exists (select 1 from pipeline.provider_fact_sources fs where fs.provider_id = o.provider_id and fs.kind = s.kind)
               order by s.kind, s.pri, length(s.url) loop
      begin
        perform public.admin_provider_central_page('add', jsonb_build_object('provider_id', o.provider_id, 'kind', v_s.kind, 'url', v_s.url, 'reason', 'Onboarding: suggested central page'));
        v_central := v_central || jsonb_build_object('kind', v_s.kind, 'url', v_s.url);
      exception when others then null;
      end;
    end loop;
    -- v2.15.258 journey: qualifying ends at Admit (stage 4); scholarships are searched only after the courses are enriched (stage 6)
    if jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) = 0 then v_central_n := security.central_ai_enqueue_v1(o.provider_id); end if;
    update pipeline.provider_onboarding set status = case when jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) > 0 then 'waiting_admit' else 'stopped' end,
           stop_reason = case when jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) > 0 then null else 'nothing_ready' end,
           step_started_at = now(), job_id = null,
           result = result || jsonb_build_object('qualify', v_q, 'ready', v_rd->'ready', 'held', v_rd->'held', 'central_pages', v_central),
           note = case when jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) > 0
                       then 'Ready to admit: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_rd->'ready') x) || '. A Platform Admin admits on Layer 2 › Adapters; its courses are then enriched and its scholarships found.'
                       else format('Nothing passed after %s AI attempt(s); the Fields column shows why for each field.%s', coalesce((o.result->>'ai_attempts')::int, 0),
                                   case when v_central_n > 0 then ' The AI is reading its central pages (English policy, calendar) for a person to approve.' else '' end) end,
           updated_at = now() where id = o.id;

  elsif o.status = 'scholarships' and o.result->>'phase' = 'enrich' then
    -- v2.15.258 stage 5: the admitted adapter writes its values to the courses. First apply it to the stored pages once; when no value
    -- has changed for 10 minutes (and at least 20 minutes have passed), record what was written and move on to the scholarships
    if not (o.result ? 'enrich_from') then
      if exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled) then
        perform public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: admitted; write the admitted values to its courses'));
      end if;
      update pipeline.provider_onboarding set step_started_at = now(), result = result || jsonb_build_object('enrich_from', now()),
             note = 'Admitted; writing the admitted values to its courses.', updated_at = now() where id = o.id;
    elsif v_age > interval '20 minutes' and not exists (select 1 from pipeline.adapter_overwrite_changes c where c.provider_id = o.provider_id and c.at > now() - interval '10 minutes') then
      v_en := (select coalesce(jsonb_object_agg(t.field, t.n), '{}'::jsonb) from (select c.field, count(distinct c.course_id) n from pipeline.adapter_overwrite_changes c
                where c.provider_id = o.provider_id and c.at >= (o.result->>'enrich_from')::timestamptz group by 1) t);
      if o.result ? 'scholarships' then
        update pipeline.provider_onboarding set step_started_at = now(), job_id = null, result = result || jsonb_build_object('enriched', v_en, 'phase', 'scholarship_admit'),
               note = format('Courses enriched (%s). Its scholarships were found earlier; checking they are admitted.',
                             coalesce((select string_agg(e.key || ' on ' || e.value || ' courses', ', ' order by e.key) from jsonb_each_text(v_en) e), 'no value changed')),
               updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set step_started_at = now(), result = result || jsonb_build_object('enriched', v_en, 'phase', 'scholarship_search'),
               job_id = security.provider_onboarding_job_v1('scholarship_provider_scan', o.provider_id, jsonb_build_object('provider_ids', jsonb_build_array(o.provider_id), 'scope', o.provider_id)),
               note = format('Courses enriched (%s); finding scholarships (map, screen, read).',
                             coalesce((select string_agg(e.key || ' on ' || e.value || ' courses', ', ' order by e.key) from jsonb_each_text(v_en) e), 'no value changed')),
               updated_at = now() where id = o.id;
      end if;
    else
      update pipeline.provider_onboarding set note = format('Enriching its courses: %s values written since it was admitted.',
               (select count(*) from pipeline.adapter_overwrite_changes c where c.provider_id = o.provider_id and c.at >= (o.result->>'enrich_from')::timestamptz)),
             updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'scholarships' and o.result->>'phase' = 'scholarship_search' then
    -- v2.15.258 stage 6: the scholarship search for this university
    if j.id is null then
      update pipeline.provider_onboarding set job_id = security.provider_onboarding_job_v1('scholarship_provider_scan', o.provider_id, jsonb_build_object('provider_ids', jsonb_build_array(o.provider_id), 'scope', o.provider_id)),
             step_started_at = now(), note = 'Finding scholarships (map, screen, read).', updated_at = now() where id = o.id;
    elsif j.state in ('done', 'failed', 'cancelled') then
      update pipeline.provider_onboarding set job_id = null, step_started_at = now(), result = result || jsonb_build_object('scholarships', j.result, 'phase', 'scholarship_admit'),
             note = 'Scholarship search finished; the AI reads the pages and checks them before publishing.', updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'scholarships' and o.result->>'phase' = 'scholarship_admit' then
    -- v2.15.258 stage 7: done when no page waits for the AI or for a person (held pages), or after 7 days
    select count(*) into v_aiq from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state <> 'done';
    select count(*) into v_rev from pipeline.scholarship_ai_reviews r where r.provider_id = o.provider_id and r.status = 'pending';
    select count(*), count(*) filter (where s.publication_status = 'published') into v_found, v_pub
      from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute';
    if (v_age > interval '15 minutes' and v_aiq = 0 and v_rev = 0) or v_age > make_interval(days => security.pipeline_num_v1('onboarding.scholarship_admit_max_days', 7)::int) then
      update pipeline.provider_onboarding set status = 'done', finished_at = now(), job_id = null,
             result = result || jsonb_build_object('scholarship_admit', jsonb_build_object('found', v_found, 'published', v_pub, 'waiting_ai', v_aiq, 'waiting_person', v_rev)),
             note = format('Onboarding complete: %s scholarships found, %s published.%s', v_found, v_pub,
                           case when v_aiq + v_rev > 0 then format(' %s pages still wait for the AI or a person (Scholarships › Extraction).', v_aiq + v_rev) else '' end),
             updated_at = now() where id = o.id;
    else
      update pipeline.provider_onboarding set note = format('Admitting scholarships: %s found, %s published; %s pages waiting for the AI, %s held for a person (Scholarships › Extraction).', v_found, v_pub, v_aiq, v_rev),
             updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'scholarships' then
    -- v2.15.255: searched once in this onboarding already (a retry or a second AI attempt): finish without searching again
    if j.id is null and o.result ? 'scholarships' then j.state := 'done'; j.result := o.result->'scholarships'; end if;
    if j.id is null and j.state is null then
      update pipeline.provider_onboarding set job_id = security.provider_onboarding_job_v1('scholarship_provider_scan', o.provider_id, jsonb_build_object('provider_ids', jsonb_build_array(o.provider_id), 'scope', o.provider_id)),
             step_started_at = now(), note = 'Finding scholarships (map, screen, read).', updated_at = now() where id = o.id;
    elsif j.state in ('done', 'failed', 'cancelled') then
      -- v2.15.256: nothing ready: the university's central pages go to the AI, for a person to approve
      if jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) = 0 then v_central_n := security.central_ai_enqueue_v1(o.provider_id); end if;
      -- v2.15.255: nothing ready after the AI attempts is "Needs a person" (stopped, nothing_ready), not Ready to admit
      update pipeline.provider_onboarding set status = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'waiting_admit' else 'stopped' end,
             stop_reason = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then null else 'nothing_ready' end,
             job_id = null, result = result || jsonb_build_object('scholarships', j.result),
             note = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'Ready to admit: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(o.result->'ready') x) || '. A Platform Admin admits on Layer 2 › Adapters.'
                         else format('Nothing passed after %s AI attempt(s); the Fields column shows why for each field.%s', coalesce((o.result->>'ai_attempts')::int, 0),
                                     case when v_central_n > 0 then ' The AI is reading its central pages (English policy, calendar) for a person to approve.' else '' end) end,
             updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'waiting_admit' then
    -- v2.15.259: Admit automatically (switched on by a Platform Admin, with a reason): exactly the fields that passed the admit rule
    if coalesce((select s.auto_admit from pipeline.provider_onboarding_settings s where s.id = 1), false)
       and jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0
       and exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled and not coalesce(a.admit, false)) then
      perform public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', o.provider_id, 'admit', true, 'fields', o.result->'ready',
               'reason', 'Admitted automatically by onboarding (auto-admit switched on by a Platform Admin): fields that passed the admit rule: '
                         || (select string_agg(x, ', ') from jsonb_array_elements_text(o.result->'ready') x)));
      update pipeline.provider_onboarding set result = result || jsonb_build_object('auto_admitted', jsonb_build_object('at', now(), 'fields', o.result->'ready')),
             updated_at = now() where id = o.id;
    end if;
    if exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled and coalesce(a.admit, false)) then
      -- v2.15.258: admitted is stage 4 of 7; its courses are enriched next (stage 5), then its scholarships
      update pipeline.provider_onboarding set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
             result = (result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Admitted; its courses are enriched next.', updated_at = now() where id = o.id;
    else
      -- still waiting for a person: checked again in 10 minutes
      update pipeline.provider_onboarding set updated_at = now() where id = o.id;
    end if;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION security.provider_onboarding_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s pipeline.provider_onboarding_settings%rowtype; o record; v_active int; v_n int := 0; v_err int := 0; v_started int := 0; v_b jsonb;
begin
  select * into s from pipeline.provider_onboarding_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('skipped', 'onboarding is switched off'); end if;
  -- v2.15.260 (keep moving): enough course pages read since it stopped for too few: carry on
  update pipeline.provider_onboarding ob set status = 'course_pages', stop_reason = null, step_started_at = now(), job_id = null, note = 'Enough course pages read now; carrying on.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason = 'too_few_pages'
     and (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = ob.provider_id and pg.read_status = 'read')
         >= least(3, greatest((select count(*) from catalogue.courses c where c.provider_id = ob.provider_id and c.lifecycle_status = 'active'), 1));
  -- v2.15.260: the adapter AI allowance renewed: carry on (from its course pages, so the sample pages are captured again)
  v_b := security.adapter_builder_budget();
  if (v_b->>'used_usd')::numeric < (v_b->>'limit_usd')::numeric and (v_b->>'proposals')::int < (v_b->>'limit_proposals')::int then
    update pipeline.provider_onboarding ob set status = 'course_pages', stop_reason = null, step_started_at = now(), job_id = null, attempts = 0, note = 'The AI allowance renewed; carrying on.', updated_at = now()
     where ob.status = 'stopped' and ob.stop_reason = 'ai_allowance';
  end if;
  -- a missing website was entered: carry on
  update pipeline.provider_onboarding ob set status = 'website', stop_reason = null, step_started_at = now(), job_id = null, note = 'Website entered; carrying on.', updated_at = now()
    from catalogue.providers pv where pv.id = ob.provider_id and ob.status = 'stopped' and ob.stop_reason = 'no_website' and nullif(pv.website, '') is not null;
  -- v2.15.255: a university that needed a person and has since been admitted by hand is done
  -- v2.15.258: then its courses are enriched (stage 5) and its scholarships found, instead of finishing here
  update pipeline.provider_onboarding ob set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
         result = (ob.result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Admitted by a person; its courses are enriched next.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason in ('nothing_ready', 'approve_central')
     and exists (select 1 from pipeline.uni_adapters a where a.provider_id = ob.provider_id and a.enabled and coalesce(a.admit, false));
  -- v2.15.256: central pages read by the AI and decided by a person (at least one approved): done
  update pipeline.provider_onboarding ob set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
         result = (ob.result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Central pages approved by a person; its courses are enriched next.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason = 'approve_central'
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'proposed')
     and exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'approved' and pp.decided_at >= coalesce(ob.started_at, ob.created_at));
  -- v2.15.258: only the working stages count towards "at once"; Admit, Enrich and Admit scholarships wait
  select count(*) into v_active from pipeline.provider_onboarding
   where status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
      or (status = 'scholarships' and coalesce(result->>'phase', 'scholarship_search') = 'scholarship_search');
  for o in select id from pipeline.provider_onboarding where status = 'queued' order by priority desc, created_at limit greatest(coalesce(s.max_active, 0) - v_active, 0) loop
    update pipeline.provider_onboarding set status = 'website', started_at = now(), step_started_at = now(), note = 'Starting.', updated_at = now() where id = o.id;
    v_started := v_started + 1;
  end loop;
  for o in select ob.id, coalesce(ob.requested_by, s.run_as) run_as from pipeline.provider_onboarding ob
            where ob.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
               or (ob.status = 'scholarships' and coalesce(ob.result->>'phase', 'scholarship_search') = 'scholarship_search')
               -- v2.15.258: the waiting stages (Admit, Enrich, Admit scholarships) are checked every 10 minutes, after the working ones
               or ((ob.status = 'waiting_admit' or (ob.status = 'scholarships' and ob.result->>'phase' in ('enrich', 'scholarship_admit'))) and ob.updated_at < now() - make_interval(mins => security.pipeline_num_v1('onboarding.waiting_check_minutes', 10)::int))
               or (ob.status = 'waiting_courses' and ob.updated_at < now() - make_interval(hours => security.pipeline_num_v1('onboarding.waiting_courses_check_hours', 1)::int))
            order by case when ob.status = 'waiting_admit' or ob.status = 'waiting_courses' or ob.result->>'phase' in ('enrich', 'scholarship_admit') then 1 else 0 end, ob.updated_at
            limit security.pipeline_num_v1('onboarding.universities_per_minute', 250)::int loop
    begin
      perform set_config('request.jwt.claims', jsonb_build_object('sub', o.run_as::text, 'role', 'authenticated')::text, true);
      perform security.provider_onboarding_step_v1(o.id);
      v_n := v_n + 1;
    exception when others then
      -- v2.15.260: a used-up AI allowance or a missing website is a plain reason that carries on by itself, not an unexpected error
      update pipeline.provider_onboarding set status = 'stopped',
             stop_reason = case when sqlerrm ilike '%proposals for today are used%' or sqlerrm ilike '%allowance%' then 'ai_allowance'
                                when sqlerrm ilike '%no website is recorded%' then 'no_website' else 'error' end,
             note = left(case when sqlerrm ilike '%proposals for today are used%' or sqlerrm ilike '%allowance%' then 'The adapter AI allowance for today is used; carries on by itself when it renews (midnight, Melbourne time). '
                              when sqlerrm ilike '%no website is recorded%' then 'No website is recorded; enter it in the Adapter builder (1.1) or Layer 4 › Websites to find, and onboarding carries on by itself. '
                              else '' end || 'Stopped: ' || sqlerrm, 500), updated_at = now() where id = o.id;
      v_err := v_err + 1;
    end;
    perform set_config('request.jwt.claims', '', true);
  end loop;
  return jsonb_build_object('started', v_started, 'advanced', v_n, 'stopped_by_error', v_err);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_facts_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id, s.kind, r.search_domain
      from pipeline.provider_fact_search s join pipeline.course_link_recipes r on r.provider_id = s.provider_id and r.active
     where (s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < security.pipeline_num_v1('retry.provider_facts_attempts', 3)))
       and (s.kind <> 'fee_schedule' or security.tuition_chase_enabled(s.provider_id))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (s.kind <> 'fee_schedule'), s.queued_at, s.provider_id limit greatest(1, least(coalesce(p_limit, 20), 60))
     for update of s skip locked),
  upd as (
    update pipeline.provider_fact_search s set state = 'sent', sent_at = now(), attempts = s.attempts + 1,
           query = case p.kind when 'fee_schedule' then 'international student tuition fees site:' || p.search_domain
                               when 'english_policy' then 'English language requirements international students site:' || p.search_domain
                               else 'academic calendar key dates intakes site:' || p.search_domain end
      from pick p where s.provider_id = p.provider_id and s.kind = p.kind
    returning s.provider_id, s.kind, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'kind', kind, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_facts_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select f.id from pipeline.provider_fact_sources f
     where ((f.kind = 'fee_schedule' and security.tuition_chase_enabled(f.provider_id))
            or f.kind in ('english_policy', 'intake_calendar'))
       and (f.status = 'found' or (f.status = 'reading' and f.updated_at < now() - interval '20 minutes')) and f.attempts < security.pipeline_num_v1('retry.provider_facts_attempts', 3)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (f.linked_from is null), f.rank,
              (select count(*) from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active') desc, f.created_at limit greatest(1, least(coalesce(p_limit, 10), 30))
     for update skip locked),
  upd as (update pipeline.provider_fact_sources f set status = 'reading', attempts = f.attempts + 1, updated_at = now() from pick where f.id = pick.id
          returning f.id, f.provider_id, f.kind, f.url)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'kind', u.kind, 'url', u.url,
           'country', (select k.iso_alpha2 from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = u.provider_id),
           'currency', (select a.currency_code from catalogue.providers p join pipeline.coverage_admission_countries a on a.country_id = p.country_id where p.id = u.provider_id))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_cricos_peo_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.id, coalesce(p.display_name, p.canonical_name) name,
           (select min(upper(r.registration_code)) from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos') cricos
      from catalogue.providers p
     where p.lifecycle_status = 'active'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)  -- v2.15.237: paused while the provider is unpublished or archived
       and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = 'cricos' and r.registration_code ~* '^[0-9]{5}[A-Z]$')
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.provider_contact_checks k where k.provider_id = p.id and k.kind = 'regulatory_peo'
                         and (k.checked_at > now() - make_interval(days => security.pipeline_num_v1('recheck.cricos_contact_days', 180)::int) and k.outcome <> 'budget' or k.checked_at > now() - interval '1 hour')) -- fixed: a check in flight
     order by (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 4), 8))),
  lease as (insert into pipeline.provider_contact_checks(provider_id, kind, checked_at, outcome) select id, 'regulatory_peo', now(), 'leased' from pick
            on conflict (provider_id, kind) do update set checked_at = now(), outcome = 'leased' returning provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.name, 'cricos', p.cricos)), '[]'::jsonb) into v
    from pick p where p.id in (select provider_id from lease);
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.platform_notices_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w_or int := coalesce((security.toolset_setting('openrouter', 'notice_window_hours'))::text::int, 24);
  w_job int := coalesce((security.toolset_setting('scheduled_jobs', 'notice_window_hours'))::text::int, 24);
  w_edge int := coalesce((security.toolset_setting('edge_functions', 'notice_window_hours'))::text::int, 6);
  v_or_mode text := coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop');
  v jsonb := '[]'::jsonb;
begin
  -- v2.15.258 (bug 12/10-01): OpenRouter notices for the AI uses that run now (Layer 3 retired on 12 Oct 2026). Refused calls
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:refused:' || z.code, 'layer', 2, 'toolset', 'openrouter', 'kind', 'refused', 'severity', 'high',
      'title', case z.code when 'credit' then 'OpenRouter refused calls: out of credit'
                           when 'key_limit' then 'OpenRouter refused calls: the key''s own spending limit was reached'
                           when 'rate' then 'OpenRouter refused calls: rate limit'
                           else 'OpenRouter refused calls: key not accepted' end,
      'detail', format('%s AI calls in the last %s hours were refused; those pages are read again later.', z.n, w_or),
      'hint', case z.code when 'credit' then 'Top up the OpenRouter balance; the refused pages are read again by themselves.'
                          when 'key_limit' then 'The limit is set on the key at OpenRouter (Workspaces › Keys), not in StudySearch. Raise or clear it there.'
                          when 'rate' then 'Usually clears by itself; the pages are read again.'
                          else 'Check the OpenRouter key on Settings.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select case when r.e ilike '%key limit%' or r.e ilike '%weekly limit%' then 'key_limit' when r.e ~ 'HTTP 402' or r.e ilike '%credit%' then 'credit'
                      when r.e ~ 'HTTP 429' then 'rate' else 'key' end code, count(*) n, min(r.at) first_at, max(r.at) last_at
          from (select x.error e, x.at from pipeline.scholarship_ai_extractions x where x.at > now() - make_interval(hours => w_or) and x.error ~ 'HTTP (40[123]|429)'
                union all
                select q.error, coalesce(q.done_at, q.created_at) from pipeline.central_ai_queue q where q.created_at > now() - make_interval(hours => w_or) and q.error ~ 'HTTP (40[123]|429)') r
          group by 1) z), '[]'::jsonb);

  -- OpenRouter balance: below the warning level, below the credit floor, or not read recently (read by the openrouter-balance job)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'openrouter:2:low_balance', 'layer', 2, 'toolset', 'openrouter', 'kind', 'low_balance',
      'severity', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0) then 'high' else 'warning' end,
      'title', format('OpenRouter balance is US$%s', round(o.remaining_usd, 2)),
      'detail', case when o.remaining_usd < coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0)
                     then format('Below the credit floor of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'credit_floor_usd'),
                                 case v_or_mode when 'observe' then 'observe only, so it keeps running until OpenRouter refuses calls' else 'stop at limits, so the scholarship AI and central pages AI have stopped' end)
                     else format('Below the warning level of US$%s. AI is set to %s.', security.toolset_setting('openrouter', 'low_balance_warn_usd'),
                                 case v_or_mode when 'observe' then 'observe only' else 'stop at limits' end) end,
      'hint', 'Top up the OpenRouter account the platform''s key uses.',
      'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select * from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1) o
    where o.remaining_usd < greatest(coalesce((security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric, 0),
                                     coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0))
    union all
    select jsonb_build_object('key', 'openrouter:2:not_observed', 'layer', 2, 'toolset', 'openrouter', 'kind', 'not_observed', 'severity', 'warning',
      'title', 'OpenRouter balance has not been read recently',
      'detail', format('Last reading %s.', coalesce(to_char(o.observed_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), 'never')),
      'hint', 'The balance is read every 15 minutes by the scheduled job "Read the OpenRouter balance" (openrouter-balance); check it in Scheduled jobs.',
      'count', 1, 'first_at', o.observed_at, 'last_at', now())
    from (select max(observed_at) observed_at from pipeline.layer3_openrouter_observations where kind = 'credits') o
    where o.observed_at is null or o.observed_at < now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30))
  ) q), '[]'::jsonb);

  -- An AI use past its daily guard today (UTC day)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'openrouter:2:over_guard:' || g.use || ':' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'openrouter', 'kind', 'over_guard',
      'severity', case v_or_mode when 'observe' then 'info' else 'warning' end,
      'title', format('%s spent US$%s today, past its guard of US$%s', g.label, g.spent, g.guard),
      'detail', case v_or_mode when 'observe' then 'Observe only: it keeps running. This is recorded for the top-up review.'
                     else 'Stop at limits: it has stopped until the UTC day changes (adapter proposals stop at their own allowance; course-page matching is observed only).' end,
      'hint', 'Change the guard or the mode on Models & services › OpenRouter (AI models) › Daily guards.',
      'count', 1, 'first_at', now(), 'last_at', now()))
    from security.ai_spend_today_v1() g where g.guard > 0 and g.spent >= g.guard), '[]'::jsonb);

  -- Firecrawl balance, scholarship share, course-link search cap (Layer 2)
  v := v || coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('key', 'firecrawl:2:low_balance', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'low_balance', 'severity', 'warning',
      'title', format('Firecrawl has %s credits left this month', o.remaining_units),
      'detail', format('Below the warning level of %s. The period ends %s.', security.toolset_setting('firecrawl', 'low_balance_warn_units'), to_char(o.period_end at time zone 'Australia/Melbourne', 'DD Mon YYYY')),
      'hint', 'Work that needs Firecrawl stops at the reserve set on Scrapers & fetchers.', 'count', 1, 'first_at', o.observed_at, 'last_at', o.observed_at) x
    from (select v2.* from pipeline.vendor_credit_observations v2 join pipeline.layer2_acquisition_providers p on p.id = v2.provider_id and p.provider_key = 'firecrawl' order by v2.observed_at desc limit 1) o
    where o.remaining_units < coalesce((security.toolset_setting('firecrawl', 'low_balance_warn_units'))::text::numeric, 0)
    union all
    -- v2.15.262: the day's Firecrawl budget (a share, or the billed total) at 80% or more
    select jsonb_build_object('key', 'firecrawl:2:daily:' || b.grp || ':' || to_char(now() at time zone 'Australia/Melbourne', 'YYYY-MM-DD'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'daily_budget',
      'severity', case when b.used >= b.cap then 'high' else 'warning' end,
      'title', format('Firecrawl daily budget, %s: %s of %s credits used', b.label, round(b.used), round(b.cap)),
      'detail', case when b.used >= b.cap then 'Used up: this work waits until midnight, Melbourne time.' else 'At 80% or more; this work stops for the day when it is used up.' end,
      'hint', 'Raise the share under Daily budget if this work should carry on today.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select 'total' grp, 'billed today' label, (st->>'billed_today')::numeric used, (st->>'total')::numeric cap, (st->>'on')::boolean is_on from security.fc_budget_status_v1() st
          union all
          select g->>'group', g->>'label', (g->>'used')::numeric, (g->>'share')::numeric, (st->>'on')::boolean
            from security.fc_budget_status_v1() st, jsonb_array_elements(st->'groups') g) b
    where b.is_on and b.cap > 0 and b.used >= 0.8 * b.cap
    union all
    select jsonb_build_object('key', 'firecrawl:2:search_stopped', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_stopped', 'severity', 'warning',
      'title', format('Course-page search stopped for %s universit%s', s.n, case when s.n = 1 then 'y' else 'ies' end),
      'detail', format('No correct course page after %s searches. Usually the website on record is wrong or the site hides its course pages from search.', security.fc_setting_num_v1('search_stop_after', 30)),
      'hint', 'Check the website on record (correct it on the provider if it is wrong), then press Search again.', 'count', s.n, 'first_at', now(), 'last_at', now(), 'items', s.items)
    from (select count(*) n, jsonb_agg(jsonb_build_object('provider_id', f.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website,
                                                          'searches', f.searches) order by f.searches desc, p.canonical_name) items
            from security.fc_search_stopped_v1() f join catalogue.providers p on p.id = f.provider_id
           where f.searches > 0
             and not exists (select 1 from pipeline.firecrawl_search_holds h where h.provider_id = f.provider_id
                               and not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at))) s where s.n > 0
    union all
    -- v2.15.265: course search held for an adapter check, by name
    select jsonb_build_object('key', 'firecrawl:2:search_held', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'search_held', 'severity', 'warning',
      'title', format('Course-page search held for %s: %s', count(*), string_agg(coalesce(p.display_name, p.canonical_name), ', ' order by p.canonical_name)),
      'detail', string_agg(coalesce(p.display_name, p.canonical_name) || ': ' || h.reason, '; ' order by p.canonical_name),
      'hint', 'Check the university''s adapter and website, then press Search again.', 'count', count(*), 'first_at', min(h.held_at), 'last_at', now(),
      'items', jsonb_agg(jsonb_build_object('provider_id', h.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website, 'reason', h.reason) order by p.canonical_name))
    from pipeline.firecrawl_search_holds h join catalogue.providers p on p.id = h.provider_id
   where not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = h.provider_id and r.resumed_at > h.held_at)
  having count(*) > 0
    union all
    -- v2.15.265: Australian providers whose official website was searched for and not found
    select jsonb_build_object('key', 'firecrawl:2:no_official_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'no_official_site', 'severity', 'info',
      'title', format('%s Australian providers have no official website found', count(*)),
      'detail', 'Not in the CRICOS register, TEQSA or training.gov.au, and no site showing their CRICOS code. Course pages and scholarships are not searched for them.',
      'hint', 'Enter a website if you know it: the course-page search starts within minutes. Otherwise nothing to do.', 'count', count(*), 'first_at', min(d.site_searched_at), 'last_at', max(d.site_searched_at),
      'items', jsonb_agg(jsonb_build_object('provider_id', d.provider_id, 'name', coalesce(p.display_name, p.canonical_name)) order by p.canonical_name))
    from pipeline.coverage_provider_discovery d join catalogue.providers p on p.id = d.provider_id and p.lifecycle_status = 'active'
   where d.status = 'no_website' and d.site_searched_at is not null and nullif(btrim(p.website), '') is null and security.coverage_country(d.provider_id) = 'AU'
  having count(*) > 0
    union all
    -- v2.15.265: providers sharing one website (pathway colleges on their university's site): their searches read the other's pages
    select jsonb_build_object('key', 'firecrawl:2:shared_site', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'shared_site', 'severity', 'info',
      'title', format('%s providers share a website with another provider', sum(z.n)),
      'detail', 'Examples: ' || string_agg(z.host, ', ' order by z.n desc) filter (where z.rk <= 5),
      'hint', 'Usually a pathway college on its university''s site. Give the college its own website, or leave it: scholarships are not searched for providers with fewer than 30 courses.', 'count', sum(z.n), 'first_at', now(), 'last_at', now())
    from (select y.host, y.n, row_number() over (order by y.n desc, y.host) rk from (
            select security.fc_spend_host_v1(p.website) host, count(*) n from catalogue.providers p
             where p.lifecycle_status = 'active' and p.website ~* '^https?://' group by 1 having count(*) > 1) y where y.host is not null) z
  having count(*) > 0
    union all
    select jsonb_build_object('key', 'firecrawl:2:scholarship_share', 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Scholarship Firecrawl share: %s of %s credits used', s.used, s.cap),
      'detail', format('Fewer than the reserve of %s are left, so newly found scholarship pages that refuse a direct read are not read.', s.reserve),
      'hint', 'Raise the cap on Layer 2 › Scholarships if you want them read.', 'count', 1, 'first_at', now(), 'last_at', now())
    from (select (b->>'used')::numeric used, (b->>'cap')::numeric cap, (b->>'reserve')::numeric reserve
          from (select jsonb_build_object(
                  'used', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape')),
                  'cap', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_cap'),
                  'reserve', (select s2.value from pipeline.scholarship_layer_settings s2 where s2.key = 'firecrawl_reserve')) b) q) s
    where s.cap - s.used <= s.reserve
    union all
    select jsonb_build_object('key', 'firecrawl:2:course_link_cap:' || to_char(now(), 'YYYY-MM'), 'layer', 2, 'toolset', 'firecrawl', 'kind', 'cap_reached', 'severity', 'warning',
      'title', format('Course-link search used %s of its %s monthly credits', l.used, l.cap),
      'detail', 'Course-link search stops for the rest of the month.', 'hint', 'Change the monthly cap on Jobs › Priority.',
      'count', 1, 'first_at', now(), 'last_at', now())
    from (select (select monthly_credit_cap from pipeline.course_link_search_settings limit 1) cap,
                 (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now())) used) l
    where l.used >= l.cap
  ) q), '[]'::jsonb);

  -- Scheduled jobs that timed out or failed (the job's layer)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'scheduled_jobs:' || z.layer || ':' || z.kind || ':' || z.jobname, 'layer', z.layer, 'toolset', 'scheduled_jobs', 'kind', z.kind,
      'severity', case when z.n >= 5 then 'high' else 'warning' end,
      'title', case z.kind when 'timeout' then format('Job "%s" hit the database time limit %s times', z.jobname, z.n)
                           else format('Job "%s" failed %s times', z.jobname, z.n) end,
      'detail', format('In the last %s hours (%s runs in all). Last message: %s', w_job, z.runs, z.msg),
      'hint', case z.kind when 'timeout' then 'Lower the job''s batch size setting so each run finishes inside the limit.' else 'Usually clears by itself (for example a deadlock); if it repeats, the job needs a fix.' end,
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    -- (11 Oct 2026: the run history is read once, last 7 days; only the jobs that failed are ranked for "last three runs succeeded")
    from (with hist as materialized (select h.jobid, h.status, h.return_message, h.start_time, h.end_time
                                       from cron.job_run_details h where h.start_time > now() - interval '7 days'), -- fixed: run history read once, last 7 days
               fd as materialized (select * from hist where status = 'failed' and end_time > now() - make_interval(hours => w_job)),
               fj as materialized (select distinct jobid from fd),
               last3 as (select f.jobid, bool_and(t.status = 'succeeded') ok, count(*) c from fj f
                           cross join lateral (select x.status from hist x where x.jobid = f.jobid and x.status in ('succeeded', 'failed')
                                               order by x.start_time desc limit 3) t group by f.jobid),
               runs as (select x.jobid, count(*) n from hist x where x.jobid in (select jobid from fj)
                          and x.end_time > now() - make_interval(hours => w_job) group by x.jobid)
          select j.jobname, coalesce(l.layer, 2) layer,
                 case when d.return_message ilike '%statement timeout%' then 'timeout' else 'failed' end kind,
                 count(*) n, min(d.end_time) first_at, max(d.end_time) last_at, left(max(d.return_message), 140) msg,
                 max(coalesce(rn.n, 0)) runs
          from fd d join cron.job j on j.jobid = d.jobid left join pipeline.platform_job_layers l on l.jobname = j.jobname
          left join last3 l3 on l3.jobid = d.jobid left join runs rn on rn.jobid = d.jobid
          where not (coalesce(l3.ok, false) and coalesce(l3.c, 0) = 3)
          group by j.jobid, j.jobname, l.layer, 3
          having count(*) >= coalesce((security.toolset_setting('scheduled_jobs', 'min_failures'))::text::int, 1)) z), '[]'::jsonb);

  -- Edge function calls that timed out (platform)
  v := v || coalesce((select jsonb_agg(jsonb_build_object(
      'key', 'edge_functions:0:timeout', 'layer', 0, 'toolset', 'edge_functions', 'kind', 'timeout', 'severity', 'warning',
      'title', format('%s edge function calls timed out or hit the worker limit', z.n),
      'detail', format('In the last %s hours.', w_edge), 'hint', 'The worker runs too long per call; lower its per-run limit.',
      'count', z.n, 'first_at', z.first_at, 'last_at', z.last_at))
    from (select count(*) n, min(r.created) first_at, max(r.created) last_at from net._http_response r
          where r.created > now() - make_interval(hours => w_edge) and (r.timed_out or r.status_code in (504, 546))) z
    where z.n >= coalesce((security.toolset_setting('edge_functions', 'min_timeouts'))::text::int, 1)), '[]'::jsonb);

  -- v2.15.269: a running job with a number written into it (it should read a setting)
  v := v || coalesce((select jsonb_agg(jsonb_build_object('key', 'pipeline:0:fixed_value:' || c.jobname, 'layer', 0, 'toolset', 'pipeline', 'kind', 'fixed_value', 'severity', 'warning',
      'title', format('Job "%s" has a number written into it', c.jobname),
      'detail', 'Its size or limit should come from Pipeline settings, so it can be changed on screen.',
      'hint', 'Move the value to the settings register (Pipeline settings).', 'count', 1, 'first_at', now(), 'last_at', now()))
    from security.controls_check_v1() c), '[]'::jsonb);

  return v;
end $function$;

-- 1 The register rows (each default is today's value)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by) values
  ('pipeline', 'batch.coverage_admit', 'Admit official page and English', 'Courses admitted in each run.', 'number', to_jsonb(500), 10, 5000, 'courses a run', 100, 'Job sizes', 'coverage-admit (every 10 minutes)'),
  ('pipeline', 'batch.coverage_admit_intakes', 'Admit intakes', 'Courses admitted in each run.', 'number', to_jsonb(300), 10, 5000, 'courses a run', 110, 'Job sizes', 'coverage-admit-intakes (every 10 minutes)'),
  ('pipeline', 'batch.adapter_overwrite', 'Adapter values replace older ones', 'Values replaced in each run.', 'number', to_jsonb(200), 10, 5000, 'values a run', 120, 'Job sizes', 'adapter-overwrite (every 10 minutes)'),
  ('pipeline', 'batch.fee_period_settle', 'Settle fee periods from page wording', 'Fees settled in each run.', 'number', to_jsonb(500), 10, 5000, 'fees a run', 130, 'Job sizes', 'fee-period-settle (every 10 minutes)'),
  ('pipeline', 'batch.link_refresh', 'Refresh course links', 'Links checked in each run.', 'number', to_jsonb(500), 10, 5000, 'links a run', 140, 'Job sizes', 'link-refresh (every 10 minutes)'),
  ('pipeline', 'batch.provider_basis_rule_admit', 'Admit tuition under provider fee rules', 'Fees admitted in each run.', 'number', to_jsonb(200), 10, 5000, 'fees a run', 150, 'Job sizes', 'provider-basis-rule-admit (every 10 minutes)'),
  ('pipeline', 'batch.course_link_reverse', 'Match known course pages by CRICOS code', 'Universities matched each minute.', 'number', to_jsonb(30), 1, 500, 'universities a minute', 160, 'Job sizes', 'course-link-reverse (every minute)'),
  ('pipeline', 'batch.course_link_search_queue', 'Line up course-page searches', 'Courses lined up for a search each minute.', 'number', to_jsonb(20), 1, 500, 'courses a minute', 170, 'Job sizes', 'course-link-search (every minute)'),
  ('pipeline', 'batch.link_search_worker', 'Search for course pages', 'Firecrawl searches (2 credits each) each minute.', 'number', to_jsonb(120), 1, 120, 'searches a minute', 180, 'Job sizes', 'course-link-search-worker (every minute)'),
  ('pipeline', 'batch.coverage_bind', 'Match pages to courses', 'Universities matched in each run.', 'number', to_jsonb(30), 1, 500, 'universities a run', 190, 'Job sizes', 'coverage-bind (every 5 minutes)'),
  ('pipeline', 'batch.ai_match_prepare_universities', 'Prepare AI course-page matching: universities', 'Universities whose site maps are offered to the AI matcher in each run.', 'number', to_jsonb(200), 1, 500, 'universities a run', 200, 'Job sizes', 'coverage-ai-match-prepare (every 2 minutes)'),
  ('pipeline', 'batch.ai_match_prepare_courses', 'Prepare AI course-page matching: courses', 'Courses prepared in each run.', 'number', to_jsonb(1000), 1, 5000, 'courses a run', 210, 'Job sizes', 'coverage-ai-match-prepare (every 2 minutes)'),
  ('pipeline', 'batch.ai_match', 'AI course-page matching', 'Pages the AI matcher judges each minute.', 'number', to_jsonb(80), 1, 200, 'pages a minute', 220, 'Job sizes', 'coverage-ai-match (every minute)'),
  ('pipeline', 'concurrency.ai_match', 'AI course-page matching: calls at once', 'AI calls made at the same time.', 'number', to_jsonb(12), 1, 24, 'calls', 230, 'Job sizes', 'coverage-ai-match (every minute)'),
  ('pipeline', 'batch.coverage_read', 'Read course pages', 'Pages read in each run (both readers).', 'number', to_jsonb(60), 10, 200, 'pages every 30 seconds', 240, 'Job sizes', 'coverage-read, coverage-read-2 (every 30 seconds)'),
  ('pipeline', 'batch.coverage_discover', 'Discover course pages (first worker)', 'University sites mapped each minute.', 'number', to_jsonb(20), 1, 200, 'sites a minute', 250, 'Job sizes', 'coverage-discover (every minute)'),
  ('pipeline', 'batch.coverage_discover_2', 'Discover course pages (second worker)', 'University sites mapped each minute.', 'number', to_jsonb(8), 1, 200, 'sites a minute', 260, 'Job sizes', 'coverage-discover-2 (every minute)'),
  ('pipeline', 'batch.coverage_find_site', 'Find provider websites', 'Providers looked up in each run.', 'number', to_jsonb(5), 1, 50, 'providers a run', 270, 'Job sizes', 'coverage-find-site (every 3 minutes)'),
  ('pipeline', 'batch.coverage_reextract', 'Re-read saved pages', 'Saved pages read again each minute.', 'number', to_jsonb(200), 1, 2000, 'pages a minute', 280, 'Job sizes', 'coverage-reextract (every minute)'),
  ('pipeline', 'batch.coverage_reidentify', 'Identify course pages again', 'Pages identified again each minute.', 'number', to_jsonb(300), 1, 2000, 'pages a minute', 290, 'Job sizes', 'coverage-reidentify (every minute)'),
  ('pipeline', 'batch.central_find', 'Find central pages', 'Universities searched in each run.', 'number', to_jsonb(4), 1, 50, 'universities a run', 300, 'Job sizes', 'central-find (every 5 minutes)'),
  ('pipeline', 'batch.provider_facts_search', 'Fee schedules, English policies and calendars: searches', 'Searches in each run.', 'number', to_jsonb(12), 1, 100, 'searches a run', 310, 'Job sizes', 'provider-facts (every 10 minutes)'),
  ('pipeline', 'batch.provider_facts_read', 'Fee schedules, English policies and calendars: reads', 'Documents read in each run.', 'number', to_jsonb(20), 1, 200, 'documents a run', 320, 'Job sizes', 'provider-facts (every 10 minutes)'),
  ('pipeline', 'batch.provider_policy_refresh', 'Plan English policy refreshes', 'Policies planned in each run.', 'number', to_jsonb(12), 1, 200, 'policies a run', 330, 'Job sizes', 'provider-english-defaults (every 10 minutes)'),
  ('pipeline', 'batch.provider_contact_page', 'Find provider phone and email', 'Providers in each run.', 'number', to_jsonb(8), 1, 50, 'providers a run', 340, 'Job sizes', 'provider-contact-page (every 3 minutes)'),
  ('pipeline', 'batch.cricos_peo', 'Read CRICOS contacts', 'Providers each minute (8 at most).', 'number', to_jsonb(2), 1, 8, 'providers a minute', 350, 'Job sizes', 'cricos-peo (every minute)'),
  ('pipeline', 'batch.admin_jobs', 'Task manager tasks', 'Task items moved on each minute.', 'number', to_jsonb(10), 1, 200, 'items a minute', 360, 'Job sizes', 'admin-jobs (every minute)'),
  ('pipeline', 'batch.onboarding_snapshot', 'Onboarding figures', 'Universities counted in each refresh.', 'number', to_jsonb(100), 10, 2000, 'universities', 370, 'Job sizes', 'layer2-onboarding-snapshot (every 2 hours)'),
  ('pipeline', 'batch.layer1_run_driver', 'Register run driver', 'Register runs moved on each minute.', 'number', to_jsonb(3), 1, 20, 'runs a minute', 380, 'Job sizes', 'layer1-run-driver (every minute)'),
  ('pipeline', 'batch.layer1_regulatory_scheduler', 'Register refresh scheduler', 'Sources checked each hour.', 'number', to_jsonb(20), 1, 200, 'sources an hour', 390, 'Job sizes', 'coursefinder-layer1-regulatory-scheduler (hourly)'),
  ('pipeline', 'batch.refresh_scheduler', 'Refresh policies', 'Policies checked each hour.', 'number', to_jsonb(100), 1, 1000, 'policies an hour', 400, 'Job sizes', 'coursefinder-m2-3-refresh-intelligence-tick (hourly)'),
  ('pipeline', 'batch.evidence_link_index', 'Index evidence links', 'Items indexed in each run.', 'number', to_jsonb(200), 1, 2000, 'items a run', 410, 'Job sizes', 'evidence-link-index (every 10 minutes)'),
  ('pipeline', 'batch.evidence_dedupe', 'Remove duplicate evidence files', 'Files checked each day.', 'number', to_jsonb(100), 1, 2000, 'files a day', 420, 'Job sizes', 'evidence-storage-dedupe-daily (daily)'),
  ('pipeline', 'reread.course_page_default_days', 'Read course pages again after', 'Used when the universitys adapter sets no cycle of its own.', 'number', to_jsonb(90), 1, 365, 'days', 430, 'Re-read and retry', 'svc_coverage_read_record'),
  ('pipeline', 'retry.course_page_failed_hours', 'Try a failed course-page read again after', null, 'number', to_jsonb(6), 1, 168, 'hours', 440, 'Re-read and retry', 'svc_coverage_read_record'),
  ('pipeline', 'retry.course_page_http_failed_days', 'Try a course page that returned an error again after', null, 'number', to_jsonb(7), 1, 90, 'days', 450, 'Re-read and retry', 'svc_coverage_read_record'),
  ('pipeline', 'remap.site_days', 'Map a university site again after', null, 'number', to_jsonb(30), 1, 365, 'days', 460, 'Re-read and retry', 'svc_coverage_discovery_record'),
  ('pipeline', 'retry.site_map_failed_hours', 'Try a failed site map again after', null, 'number', to_jsonb(6), 1, 168, 'hours', 470, 'Re-read and retry', 'svc_coverage_discovery_record'),
  ('pipeline', 'retry.no_website_days', 'Look again for a provider with no website after', null, 'number', to_jsonb(30), 1, 365, 'days', 480, 'Re-read and retry', 'svc_coverage_site_next, svc_coverage_site_record'),
  ('pipeline', 'retry.website_after_budget_days', 'Look again when the search had no credit, after', null, 'number', to_jsonb(1), 1, 30, 'days', 490, 'Re-read and retry', 'svc_coverage_site_record'),
  ('pipeline', 'reread.scholarship_page_days', 'Read a scholarship page again after', 'Each found page. Published scholarships are also read again on their own cycle (Layer 2 › Scholarships).', 'number', to_jsonb(90), 1, 365, 'days', 500, 'Re-read and retry', 'svc_scholarship_read_record'),
  ('pipeline', 'retry.scholarship_name_mismatch_days', 'Read a page whose name did not match again after', null, 'number', to_jsonb(30), 1, 365, 'days', 510, 'Re-read and retry', 'svc_scholarship_read_record'),
  ('pipeline', 'retry.scholarship_blocked_days', 'Try a blocked scholarship page again after', null, 'number', to_jsonb(2), 1, 60, 'days', 520, 'Re-read and retry', 'svc_scholarship_read_record'),
  ('pipeline', 'retry.scholarship_waiting_scraper_hours', 'Try a page waiting for the scraper again after', null, 'number', to_jsonb(1), 1, 48, 'hours', 530, 'Re-read and retry', 'svc_scholarship_read_record'),
  ('pipeline', 'retry.scholarship_failed_hours', 'Try a failed scholarship page again after', null, 'number', to_jsonb(6), 1, 168, 'hours', 540, 'Re-read and retry', 'svc_scholarship_read_record'),
  ('pipeline', 'reread.scholarship_candidate_days', 'Check a possible scholarship page again after', null, 'number', to_jsonb(90), 1, 365, 'days', 550, 'Re-read and retry', 'svc_scholarship_candidate_record'),
  ('pipeline', 'retry.scholarship_candidate_failed_hours', 'Try a failed possible page again after', null, 'number', to_jsonb(6), 1, 168, 'hours', 560, 'Re-read and retry', 'svc_scholarship_candidate_record'),
  ('pipeline', 'reread.scholarship_listing_days', 'Read a scholarship listing page again after', null, 'number', to_jsonb(7), 1, 90, 'days', 570, 'Re-read and retry', 'svc_scholarship_listing_record'),
  ('pipeline', 'retry.scholarship_listing_failed_days', 'Try a failed listing page again after', null, 'number', to_jsonb(1), 1, 30, 'days', 580, 'Re-read and retry', 'svc_scholarship_listing_record'),
  ('pipeline', 'reread.scholarship_ai_days', 'Read a page with AI again after', null, 'number', to_jsonb(90), 1, 365, 'days', 590, 'Re-read and retry', 'svc_scholarship_ai_record'),
  ('pipeline', 'retry.provider_facts_attempts', 'Tries for a fee schedule, English policy or calendar', null, 'number', to_jsonb(3), 1, 10, 'tries', 600, 'Re-read and retry', 'svc_provider_facts_search_next, svc_provider_facts_read_next'),
  ('pipeline', 'recheck.cricos_contact_days', 'Check CRICOS contacts again after', null, 'number', to_jsonb(180), 7, 730, 'days', 610, 'Re-read and retry', 'svc_cricos_peo_next'),
  ('pipeline', 'onboarding.universities_per_minute', 'Universities moved on each minute', 'The onboarding job looks at up to this many universities each minute.', 'number', to_jsonb(250), 10, 1000, 'universities', 620, 'Onboarding', 'provider_onboarding_tick_v1'),
  ('pipeline', 'onboarding.waiting_check_minutes', 'Check universities waiting to admit or enrich every', null, 'number', to_jsonb(10), 1, 120, 'minutes', 630, 'Onboarding', 'provider_onboarding_tick_v1'),
  ('pipeline', 'onboarding.waiting_courses_check_hours', 'Check universities waiting for course pages every', null, 'number', to_jsonb(1), 1, 48, 'hours', 640, 'Onboarding', 'provider_onboarding_tick_v1'),
  ('pipeline', 'onboarding.provider_fill_valid_days', 'A universitys details count as fresh for', 'Details filled by Fill in details are not filled again within this time.', 'number', to_jsonb(30), 1, 365, 'days', 650, 'Onboarding', 'provider_onboarding_step_v1'),
  ('pipeline', 'onboarding.sample_courses', 'Courses searched for course pages at once', null, 'number', to_jsonb(300), 50, 2000, 'courses', 660, 'Onboarding', 'provider_onboarding_step_v1'),
  ('pipeline', 'onboarding.course_search_wait_hours', 'Wait for found course pages to be read for up to', null, 'number', to_jsonb(6), 1, 72, 'hours', 670, 'Onboarding', 'provider_onboarding_step_v1'),
  ('pipeline', 'onboarding.proposal_attempts', 'Adapter proposals before a person is asked', null, 'number', to_jsonb(2), 1, 5, 'tries', 680, 'Onboarding', 'provider_onboarding_step_v1'),
  ('pipeline', 'onboarding.scholarship_admit_max_days', 'Close the scholarship stage after at most', 'Even if pages still wait for the AI or a person.', 'number', to_jsonb(7), 1, 60, 'days', 690, 'Onboarding', 'provider_onboarding_step_v1')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set reason = 'CF-247 v2.15.269: moved from code (today''s value)', updated_at = now() where toolset_key = 'pipeline' and reason is null;

-- 4 Worker settings (Firecrawl, Find pages) and the search-stop window
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by) values
  ('firecrawl', 'map_limit_course_site', 'Site map: links read for course pages', 'Most links a site map returns when looking for course pages.', 'number', to_jsonb(30000), 100, 100000, 'links', 900, 'Find pages', 'worker: discover'),
  ('firecrawl', 'map_limit_central', 'Site map: links read for central pages', null, 'number', to_jsonb(5000), 100, 100000, 'links', 905, 'Find pages', 'worker: central_find'),
  ('firecrawl', 'map_limit_central_search', 'Site map search: links for a central page', null, 'number', to_jsonb(200), 10, 5000, 'links', 910, 'Find pages', 'worker: central_find'),
  ('firecrawl', 'map_limit_scholarships', 'Site map search: links for scholarship pages', null, 'number', to_jsonb(5000), 100, 100000, 'links', 915, 'Find pages', 'worker: scholarship_discover'),
  ('firecrawl', 'search_results_website', 'Search results: official website', null, 'number', to_jsonb(8), 1, 20, 'results', 920, 'Find pages', 'worker: find_site'),
  ('firecrawl', 'search_results_register', 'Search results: register page', null, 'number', to_jsonb(5), 1, 20, 'results', 925, 'Find pages', 'worker: find_site'),
  ('firecrawl', 'search_results_cricos', 'Search results: CRICOS code', null, 'number', to_jsonb(8), 1, 20, 'results', 930, 'Find pages', 'worker: find_site'),
  ('firecrawl', 'search_results_scholarship_search', 'Search results: scholarship search', null, 'number', to_jsonb(5), 1, 20, 'results', 935, 'Find pages', 'worker: scholarship search'),
  ('firecrawl', 'search_results_scholarship_discover', 'Search results: scholarship discovery', null, 'number', to_jsonb(6), 1, 20, 'results', 940, 'Find pages', 'worker: scholarship discovery'),
  ('firecrawl', 'search_stop_window_days', 'Count searches over the last', 'With "Stop searching a university after", the window the searches are counted in.', 'number', to_jsonb(7), 1, 60, 'days', 945, 'Daily budget', 'fc_search_stopped_v1')
on conflict (toolset_key, key) do nothing;
update pipeline.platform_toolset_settings set reason = 'CF-247 v2.15.269: moved from code (today''s value)', updated_at = now() where toolset_key = 'firecrawl' and reason is null and key in ('map_limit_course_site', 'map_limit_central', 'map_limit_central_search', 'map_limit_scholarships', 'search_results_website', 'search_results_register', 'search_results_cricos', 'search_results_scholarship_search', 'search_results_scholarship_discover', 'search_stop_window_days');
update pipeline.platform_toolset_settings set label = 'Proxy for every Firecrawl read', help = 'basic, auto, stealth or enhanced. Used by every Firecrawl read (course pages, scholarships, central pages, website finder, adapter samples) and manual runs.',
       used_by = 'worker: every Firecrawl read' where toolset_key = 'firecrawl' and key = 'read_proxy';

-- 2 Every job reads its size from the register
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'adapter-overwrite'), command := 'select security.adapter_overwrite_v1(security.pipeline_num_v1(''batch.adapter_overwrite'', 200)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'admin-jobs'), command := 'select security.admin_jobs_tick_v1(security.pipeline_num_v1(''batch.admin_jobs'', 10)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'course-link-reverse'), command := 'select security.course_link_reverse_tick_v1(security.pipeline_num_v1(''batch.course_link_reverse'', 30)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'course-link-search'), command := 'select security.course_link_search_tick_v1(security.pipeline_num_v1(''batch.course_link_search_queue'', 20)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coursefinder-layer1-regulatory-scheduler'), command := 'select security.layer1_regulatory_scheduler_tick_impl(now(), security.pipeline_num_v1(''batch.layer1_regulatory_scheduler'', 20)::int, true);');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coursefinder-m2-3-refresh-intelligence-tick'), command := 'select security.refresh_scheduler_tick_impl(now(), security.pipeline_num_v1(''batch.refresh_scheduler'', 100)::int);');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-admit'), command := 'select security.coverage_admission_apply_v1(security.pipeline_num_v1(''batch.coverage_admit'', 500)::int, ''coverage-sweep-v0.5.6'')');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-admit-intakes'), command := 'select security.coverage_admission_apply_v1(security.pipeline_num_v1(''batch.coverage_admit_intakes'', 300)::int, ''coverage-sweep-v0.5.6'', array[''intakes''])');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-ai-match-prepare'), command := 'select security.coverage_ai_match_prepare_v1(security.pipeline_num_v1(''batch.ai_match_prepare_universities'', 200)::int, security.pipeline_num_v1(''batch.ai_match_prepare_courses'', 1000)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-bind'), command := 'select security.coverage_bind_tick_v1(security.pipeline_num_v1(''batch.coverage_bind'', 30)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'fee-period-settle'), command := 'select security.fee_period_settle_v1(security.pipeline_num_v1(''batch.fee_period_settle'', 500)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'layer1-run-driver'), command := 'select security.layer1_run_driver_tick_v1(security.pipeline_num_v1(''batch.layer1_run_driver'', 3)::int);');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'layer2-onboarding-snapshot'), command := 'select security.layer2_onboarding_snapshot_refresh_v1(security.pipeline_num_v1(''batch.onboarding_snapshot'', 100)::int);');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'link-refresh'), command := 'select security.link_refresh_tick_v1(security.pipeline_num_v1(''batch.link_refresh'', 500)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'provider-basis-rule-admit'), command := 'select security.provider_basis_rule_admit_v1(true, security.pipeline_num_v1(''batch.provider_basis_rule_admit'', 200)::int)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'provider-english-defaults'), command := 'select security.provider_policy_refresh_plans_v1(security.pipeline_num_v1(''batch.provider_policy_refresh'', 12)::int); select security.provider_english_apply_all_v1();');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'central-find'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''central_find'', ''limit'', security.pipeline_num_v1(''batch.central_find'', 4)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'course-link-search-worker'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''link_search'', ''limit'', security.pipeline_num_v1(''batch.link_search_worker'', 120)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-ai-match'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''ai_match'', ''limit'', security.pipeline_num_v1(''batch.ai_match'', 80)::int, ''concurrency'', security.pipeline_num_v1(''concurrency.ai_match'', 12)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-discover'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''discover'', ''limit'', security.pipeline_num_v1(''batch.coverage_discover'', 20)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-discover-2'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''discover'', ''limit'', security.pipeline_num_v1(''batch.coverage_discover_2'', 8)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-find-site'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''find_site'', ''limit'', security.pipeline_num_v1(''batch.coverage_find_site'', 5)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-read'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''read'', ''limit'', security.pipeline_num_v1(''batch.coverage_read'', 60)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-read-2'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''read'', ''limit'', security.pipeline_num_v1(''batch.coverage_read'', 60)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-reextract'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''reextract'', ''limit'', security.pipeline_num_v1(''batch.coverage_reextract'', 200)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-reidentify'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''reidentify'', ''limit'', security.pipeline_num_v1(''batch.coverage_reidentify'', 300)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'cricos-peo'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''cricos_peo'', ''limit'', security.pipeline_num_v1(''batch.cricos_peo'', 2)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'evidence-link-index'), command := 'select pipeline.svc_pilot_submit_nonce(''evidence-link-index'', jsonb_build_object(''limit'', security.pipeline_num_v1(''batch.evidence_link_index'', 200)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'evidence-storage-dedupe-daily'), command := 'select pipeline.svc_pilot_submit_nonce(''evidence-storage-dedupe'', jsonb_build_object(''remove'', true, ''limit'', security.pipeline_num_v1(''batch.evidence_dedupe'', 100)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'provider-contact-page'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''contact_page'', ''limit'', security.pipeline_num_v1(''batch.provider_contact_page'', 8)::int))');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'provider-facts'), command := 'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''provider_facts'', ''search_limit'', security.pipeline_num_v1(''batch.provider_facts_search'', 12)::int, ''read_limit'', security.pipeline_num_v1(''batch.provider_facts_read'', 20)::int))');
update pipeline.automation_catalogue set batch_editable = true where jobname in ('adapter-overwrite', 'admin-jobs', 'course-link-reverse', 'course-link-search', 'coursefinder-layer1-regulatory-scheduler', 'coursefinder-m2-3-refresh-intelligence-tick', 'coverage-admit', 'coverage-admit-intakes', 'coverage-ai-match-prepare', 'coverage-bind', 'fee-period-settle', 'layer1-run-driver', 'layer2-onboarding-snapshot', 'link-refresh', 'provider-basis-rule-admit', 'provider-english-defaults', 'central-find', 'course-link-search-worker', 'coverage-ai-match', 'coverage-discover', 'coverage-discover-2', 'coverage-find-site', 'coverage-read', 'coverage-read-2', 'coverage-reextract', 'coverage-reidentify', 'cricos-peo', 'evidence-link-index', 'evidence-storage-dedupe-daily', 'provider-contact-page', 'provider-facts');

do $post$
declare v_expected jsonb := '{"public.admin_toolsets_read()": "c54f956cedc46cb6e18d8122d2d14c9b", "security.automation_batch(text)": "fe2d14f9d318226ac6b08b49cb41e888", "security.admin_automation_control_v1(text,text,jsonb)": "8d5a6f103e1ad22a6f4bbd2f15d6a5c5", "public.admin_pipeline_settings_read()": "6a192ef1a9dda96193847745663c3539", "public.admin_pipeline_settings_write(text,jsonb)": "47491f592951aaeada568c06411cd8be", "public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)": "e0437f036b88f3a7231e99d5245c6ffe", "public.svc_coverage_discovery_record(uuid,text,text,integer,jsonb,text)": "ff0454e1e31004ac00a0909e29aeed49", "public.svc_coverage_site_next(integer)": "bdac9ab932a167a469837bcb07abfa99", "public.svc_coverage_site_record(uuid,text,jsonb)": "aa8a856505ba213d7fd0ba2f0cbfa648", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "ece9139335e8e6832158353fa097d2e9", "public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)": "2bfb43c34e48aca7194ec8bb196c1662", "public.svc_scholarship_listing_record(bigint,text,integer,jsonb,text)": "a72f798fc8cdf221dc68dedb721dc161", "public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)": "b047f8d230f41aedd732901bf4a630a3", "security.fc_search_stopped_v1()": "672e614cafececb235a6e56c372e7c30", "security.provider_onboarding_step_v1(uuid)": "8597740642ce2470f793be575793e680", "security.provider_onboarding_tick_v1()": "924761ef08dd1dec8e0453bd096bbd3f", "public.svc_provider_facts_search_next(integer)": "14c68d372eb69d1487e5a887d4a81d20", "public.svc_provider_facts_read_next(integer)": "5125d17949c155b56bd2b3a3903e6479", "public.svc_cricos_peo_next(integer)": "9b7675ad956065b6ba793b5e744114ad", "security.platform_notices_v1()": "eb99486952e5e68ffa42e625f2376c92"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.269 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $check$
declare v_n int;
begin
  select count(*) into v_n from security.controls_check_v1();
  if v_n > 0 then raise exception 'v2.15.269 post-check: % running job(s) still have a number written into them', v_n; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline') <> 60 then raise exception 'v2.15.269 post-check: register rows'; end if;
end $check$;
