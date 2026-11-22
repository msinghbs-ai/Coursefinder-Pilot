CREATE OR REPLACE FUNCTION security.platform_health_consolidated_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_stale interval := make_interval(mins => security.pipeline_num_v1('health.dispatcher_stale_minutes', 5)::int);
        v_l4warn int := security.pipeline_num_v1('health.layer4_pending_warn', 6000)::int;
        v_l4days int := security.pipeline_num_v1('health.layer4_oldest_warn_days', 45)::int;
        v_found jsonb := '[]'::jsonb; v_det jsonb := '{}'::jsonb; v_x jsonb; v_t timestamptz; v_n int; v_m int; v_ts timestamptz; r record;
        v_keys constant text[] := array['dispatchers', 'boost', 'layer4_backlog', 'guardrails'];
begin
  -- Dispatchers: each dispatcher cron job runs and succeeds; live targets that fail or are held open
  v_t := clock_timestamp(); v_x := '[]'::jsonb;
  for r in select c.jobname, c.active,
                  (select d.status from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) last_status,
                  (select max(d.start_time) from (select d2.start_time from cron.job_run_details d2 where d2.jobid = c.jobid and d2.status = 'succeeded' order by d2.runid desc limit 1) d) last_ok
             from cron.job c where c.jobname ~ '^(rollup-scheduler|coverage-lane-dispatch(-[bc])?|admission-rule-runner(-[bc])?)$' order by c.jobname loop
    v_x := v_x || jsonb_build_object('job', r.jobname, 'active', r.active, 'last_status', r.last_status, 'last_ok', r.last_ok);
    if not r.active or r.last_ok is null or r.last_ok < now() - v_stale then
      v_found := v_found || security.platform_health_issue_v1('dispatchers:' || r.jobname, 'critical', 'scheduled jobs',
        'Dispatcher ' || r.jobname || case when not r.active then ' is switched off' else ' has not run successfully since ' || coalesce(to_char(r.last_ok at time zone 'Australia/Sydney', 'DD Mon HH24:MI'), 'it started') end,
        jsonb_build_object('job', r.jobname, 'active', r.active, 'last_ok', r.last_ok, 'last_status', r.last_status));
    end if;
  end loop;
  select count(*) filter (where t.last_status = 'failed'), count(*) filter (where t.mode = 'shadow') into v_n, v_m from pipeline.rollup_targets t where t.enabled;
  if v_n > 0 then
    v_found := v_found || security.platform_health_issue_v1('dispatchers:rollup_targets', 'warning', 'scheduled jobs',
      v_n || ' rollup-scheduler target(s) failed on their last run: ' || (select string_agg(t.target_code, ', ' order by t.target_code) from pipeline.rollup_targets t where t.enabled and t.last_status = 'failed'),
      jsonb_build_object('failed', (select jsonb_agg(jsonb_build_object('target', t.target_code, 'error', left(t.last_error, 200), 'at', t.last_finished_at)) from pipeline.rollup_targets t where t.enabled and t.last_status = 'failed')));
  end if;
  v_det := v_det || jsonb_build_object('dispatchers', jsonb_build_object('jobs', v_x,
    'rollup_targets', jsonb_build_object('enabled', (select count(*) from pipeline.rollup_targets t where t.enabled), 'failed', v_n, 'shadow', v_m),
    'coverage_lanes', (select jsonb_build_object('enabled', count(*), 'live', count(*) filter (where f.mode = 'live'), 'held_open', count(*) filter (where f.open_until > now()),
                              'failing', count(*) filter (where f.consecutive_failures > 0)) from pipeline.field_execution_registry f where f.enabled),
    'admission_rules', (select jsonb_build_object('enabled', count(*), 'live', count(*) filter (where a.mode = 'live'), 'held_open', count(*) filter (where a.open_until > now()),
                               'failing', count(*) filter (where a.consecutive_failures > 0)) from pipeline.admission_rules a where a.enabled),
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  select count(*) into v_n from pipeline.field_execution_registry f where f.enabled and f.mode = 'live' and f.open_until > now();
  if v_n > 0 then
    v_found := v_found || security.platform_health_issue_v1('dispatchers:coverage_lanes', 'warning', 'scheduled jobs',
      v_n || ' coverage-lane-dispatch lane(s) are held after repeated failures: ' || (select string_agg(f.lane_code, ', ' order by f.lane_code) from pipeline.field_execution_registry f where f.enabled and f.mode = 'live' and f.open_until > now()),
      jsonb_build_object('lanes', (select jsonb_agg(jsonb_build_object('lane', f.lane_code, 'until', f.open_until, 'error', left(f.last_error, 200))) from pipeline.field_execution_registry f where f.enabled and f.mode = 'live' and f.open_until > now())));
  end if;

  -- Boost: switches, the Layer 4 admission cap, staging, qualified models and spend (last 24 hours)
  v_t := clock_timestamp();
  select count(*) into v_n from pipeline.boost_study_load_reviews b where b.status = 'open';
  v_det := v_det || jsonb_build_object('boost', jsonb_build_object(
    'switches', jsonb_build_object('ingest', security.pipeline_num_v1('boost.ingest_on', 0) >= 1, 'extract', security.pipeline_num_v1('boost.extract_on', 0) >= 1,
                                   'fields', security.pipeline_num_v1('boost.fields_on', 0) >= 1, 'benchmark', security.pipeline_num_v1('boost.benchmark_on', 0) >= 1),
    'layer4_open', v_n, 'layer4_open_max', security.pipeline_num_v1('boost.layer4_open_max', 400)::int,
    'staging', (select coalesce(jsonb_object_agg(z.promotion_state, z.n), '{}'::jsonb) from (select s.promotion_state, count(*) n from pipeline.boost_inbound_staging s group by 1) z),
    'qualified', (select coalesce(jsonb_agg(jsonb_build_object('lane', q.lane, 'model', q.model, 'at', q.qualified_at)), '[]'::jsonb) from pipeline.boost_model_qualifications q),
    'spend_24h_usd', (select coalesce(jsonb_object_agg(z.lane, z.usd), '{}'::jsonb) from (select l.lane, round(sum(l.cost_usd), 4) usd from pipeline.ai_spend_ledger l where l.at > now() - interval '1 day' and l.lane like 'boost%' group by 1) z),  -- fixed: the 24-hour window this report states
    'ai_daily_ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
    'ai_refusal', security.ai_use_refusal_v1('enrich_fields'),
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  for r in select c.jobname, (select d.status from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) st,
                  (select left(d.return_message, 200) from cron.job_run_details d where d.jobid = c.jobid order by d.runid desc limit 1) msg
             from cron.job c where c.active and c.jobname ~ '^(boost-|worker-boost-)' loop
    if r.st = 'failed' then
      v_found := v_found || security.platform_health_issue_v1('boost:' || r.jobname, 'warning', 'boost', 'Boost job ' || r.jobname || ' failed on its last run', jsonb_build_object('job', r.jobname, 'error', r.msg));
    end if;
  end loop;

  -- Layer 4 backlog: waiting items, the oldest, and the last 24 hours in and out
  v_t := clock_timestamp();
  select count(*), min(i.created_at) into v_n, v_ts from pipeline.layer4_review_items i where i.status = 'pending';
  v_det := v_det || jsonb_build_object('layer4_backlog', jsonb_build_object('pending', v_n, 'oldest', v_ts, 'warn_at', v_l4warn, 'oldest_warn_days', v_l4days,
    'created_24h', (select count(*) from pipeline.layer4_review_items i where i.created_at > now() - interval '1 day'),  -- fixed: the 24-hour window this report states
    'decided_24h', (select count(*) from pipeline.layer4_decisions d where d.created_at > now() - interval '1 day'),     -- fixed: as above
    'by_field', (select coalesce(jsonb_object_agg(z.field_code, z.n), '{}'::jsonb) from (select i.field_code, count(*) n from pipeline.layer4_review_items i where i.status = 'pending' group by 1 order by 2 desc limit 12) z),
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  if v_n >= v_l4warn then
    v_found := v_found || security.platform_health_issue_v1('layer4_backlog:pending', 'warning', 'Layer 4', v_n || ' items wait in Layer 4 review (warning at ' || v_l4warn || ')', jsonb_build_object('pending', v_n));
  end if;
  if v_ts < now() - make_interval(days => v_l4days) then
    v_found := v_found || security.platform_health_issue_v1('layer4_backlog:oldest', 'warning', 'Layer 4', 'The oldest Layer 4 item has waited since ' || to_char(v_ts at time zone 'Australia/Sydney', 'DD Mon YYYY'), jsonb_build_object('oldest', v_ts));
  end if;

  -- Guardrails: G1 (every running job catalogued) and G3 (consumer API matches its baseline)
  v_t := clock_timestamp();
  select count(*) into v_n from cron.job c where c.active and not exists (select 1 from pipeline.automation_catalogue a where a.jobname = c.jobname);
  select count(*) into v_m from pipeline.enrichment_flags f where f.entity = 'api' and f.entity_key = 'consumer' and f.reason_code = 'consumer_api_drift' and f.state = 'raised';
  v_det := v_det || jsonb_build_object('guardrails', jsonb_build_object(
    'g1_uncatalogued_jobs', v_n,
    'g1_uncatalogued', (select coalesce(jsonb_agg(c.jobname order by c.jobname), '[]'::jsonb) from cron.job c where c.active and not exists (select 1 from pipeline.automation_catalogue a where a.jobname = c.jobname)),
    'g3_functions', (select count(*) from security.consumer_api_functions_v1()), 'g3_relations', (select count(*) from security.consumer_api_relations_v1()),
    'g3_baseline_functions', (select count(*) from pipeline.consumer_api_baseline b where b.kind = 'function'),
    'g3_baseline_relations', (select count(*) from pipeline.consumer_api_baseline b where b.kind = 'relation'),
    'g3_drift_flag', v_m > 0,
    'ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)));
  if v_n > 0 then
    v_found := v_found || security.platform_health_issue_v1('guardrails:g1', 'warning', 'scheduled jobs', v_n || ' running scheduled job(s) are not in the automation catalogue (G1)', v_det->'guardrails');
  end if;
  if v_m > 0 then
    v_found := v_found || security.platform_health_issue_v1('guardrails:g3', 'critical', 'search/API', 'The consumer API differs from its baseline (G3, Decision 266)', v_det->'guardrails');
  end if;

  -- record: issues (dedup on check_key), resolve what cleared, store the four checks
  for r in select distinct on (x.check_key) x.check_key, x.severity, x.area, x.title, x.detail
             from jsonb_to_recordset(v_found) x(check_key text, severity text, area text, title text, detail jsonb)
            order by x.check_key, case x.severity when 'critical' then 1 when 'warning' then 2 else 3 end loop
    insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
    values (r.check_key, r.severity, r.area, left(r.title, 300), coalesce(r.detail, '{}'::jsonb))
    on conflict (check_key) where resolved_at is null do update set severity = excluded.severity, area = excluded.area, title = excluded.title,
      detail = excluded.detail, last_seen = now(), occurrences = i.occurrences + 1;
  end loop;
  update pipeline.platform_issues i set resolved_at = now()
   where i.resolved_at is null and split_part(i.check_key, ':', 1) = any (v_keys)
     and not exists (select 1 from jsonb_array_elements(v_found) f where f->>'check_key' = i.check_key);
  insert into pipeline.platform_health_checks as c (key, area, label, status, detail, checked_at, duration_ms, cadence_minutes, slow, sort_order)
  select k.key, k.area, k.label,
         coalesce((select case min(case f->>'severity' when 'critical' then 1 when 'warning' then 2 else 3 end) when 1 then 'critical' when 2 then 'warning' else 'ok' end
                     from jsonb_array_elements(v_found) f where split_part(f->>'check_key', ':', 1) = k.key), 'ok'),
         v_det->k.key, now(), (v_det->k.key->>'ms')::int, 10, false, k.sort  -- fixed: the cadence of target platform-health-consolidated
    from (values ('dispatchers', 'scheduled jobs', 'Dispatchers run: rollup-scheduler, coverage-lane-dispatch, admission-rule-runner', 15),
                 ('boost', 'boost', 'Boost admission and spend: switches, Layer 4 cap, staging, qualified models', 175),
                 ('layer4_backlog', 'Layer 4', 'Layer 4 review backlog: waiting, oldest, in and out', 65),
                 ('guardrails', 'governance', 'Guardrails: G1 every job catalogued, G3 consumer API unchanged', 5)) k(key, area, label, sort)
  on conflict (key) do update set area = excluded.area, label = excluded.label, status = excluded.status, detail = excluded.detail,
    checked_at = excluded.checked_at, duration_ms = excluded.duration_ms, cadence_minutes = excluded.cadence_minutes, sort_order = excluded.sort_order;
  return jsonb_build_object('issues', jsonb_array_length(v_found), 'checks', v_det);
end $function$
