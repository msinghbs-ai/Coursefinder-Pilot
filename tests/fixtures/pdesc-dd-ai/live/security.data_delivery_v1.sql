CREATE OR REPLACE FUNCTION security.data_delivery_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s record; v_out jsonb := '[]'::jsonb;
  v_short int := security.pipeline_num_v1('data_delivery.net_short_hours', 24)::int;
  v_long int := security.pipeline_num_v1('data_delivery.net_long_hours', 168)::int;
  v_stale int := security.pipeline_num_v1('data_delivery.stale_after_minutes', 30)::int;
  v_hist int := security.pipeline_num_v1('data_delivery.run_history_hours', 48)::int;
  v_top int := security.pipeline_num_v1('data_delivery.reasons_shown', 3)::int;
  v_ui int := security.pipeline_num_v1('data_delivery.ui_refresh_seconds', 60)::int;
  v_runs jsonb; v_r jsonb; v_cov jsonb; v_ns jsonb; v_nl jsonb; v_w jsonb; v_z jsonb; v_q jsonb; v_h jsonb; v_speed jsonb; v_jobs jsonb; v_job_sum jsonb; v_flags jsonb; v_rec jsonb;
  v_hrs numeric; v_ok int; v_bad int; v_last_status text; v_open int; v_remedy_ok int; v_remedy_bad int; v_remedy_last timestamptz; v_issue_refs jsonb; v_off boolean; v_active int; v_total int;
  v_hint text; v_qtxt text; v_hc jsonb; v_hc_at timestamptz; v_hc_err text; v_hc_failed timestamptz; v_hc_ok boolean; v_stalled boolean; v_paused text; v_every int := security.pipeline_num_v1('data_delivery.refresh_minutes', 10)::int; v_oldest timestamptz; v_newest timestamptz; v_errors int; v_rd jsonb; v_job jsonb;
begin
  -- a count is marked stale only after at least two count-again times, so a setting cannot make every figure permanently Stale
  v_stale := greatest(v_stale, 2 * v_every);  -- fixed: a safety floor of twice the count-again time, not an operating value
  -- the scheduler history comes from the cache written by job data-delivery (no scan of the scheduler's run history here); the job rows themselves (active, schedule) are read live, they are few
  select r.runs, r.measured_at, r.error, r.failed_at into v_hc, v_hc_at, v_hc_err, v_hc_failed from pipeline.data_delivery_job_runs r where r.singleton;
  select coalesce(jsonb_object_agg(w.jobname, jsonb_build_object('runs', 0, 'failed', 0, 'succeeded', 0, 'running', false) || coalesce(v_hc->w.jobname, '{}'::jsonb)
      || jsonb_build_object('active', w.active, 'schedule', w.schedule, 'next_run', case when w.active then security.cron_next_run_v1(w.schedule, now()) end)), '{}'::jsonb)
    into v_runs from cron.job w
   where w.jobname = 'data-delivery' or w.jobname in (select unnest(x.primary_jobs) from pipeline.data_delivery_streams x);
  v_hc_ok := coalesce(jsonb_typeof(v_hc) = 'object', false);

  for s in select d.*, l.switch_keys, l.issue_refs, l.title as lane_title from pipeline.data_delivery_streams d join pipeline.lane_funnel_lanes l on l.lane = d.lane order by d.sort, d.stream loop
    select coalesce(jsonb_object_agg(r.measure, jsonb_build_object('rows', r.rows, 'measured_at', r.measured_at, 'took_ms', r.took_ms, 'error', r.error, 'failed_at', r.failed_at)), '{}'::jsonb)
      into v_r from pipeline.data_delivery_readings r where r.stream = s.stream;
    -- coverage: n of N, and the country split
    v_cov := case
      when v_r->'coverage' is null then jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'coverage', 'Not counted yet (the first count runs within minutes of release)'))
      when jsonb_typeof(v_r->'coverage'->'rows') is distinct from 'array' then jsonb_build_object('known', false, 'reason', 'Could not be counted: ' || coalesce(v_r->'coverage'->>'error', 'no result')) || security.data_delivery_meta_v1(v_r->'coverage', v_stale)
      else (select jsonb_build_object('known', true, 'n', coalesce(sum(x.n), 0), 'total', case when coalesce(bool_and(x.total is not null), false) then sum(x.total) end,
                'total_reason', case when not coalesce(bool_and(x.total is not null), false) then coalesce(s.not_measured->>'coverage_total', 'The total is not measured') end,
                'pct', case when coalesce(bool_and(x.total is not null), false) and sum(x.total) > 0 then round(100.0 * sum(x.n) / sum(x.total), 1) end,
                'by_country', coalesce(jsonb_agg(jsonb_build_object('cc', x.cc, 'n', x.n, 'total', x.total) order by x.cc), '[]'::jsonb))
              || security.data_delivery_meta_v1(v_r->'coverage', v_stale)
              from jsonb_to_recordset(v_r->'coverage'->'rows') as x(cc text, n bigint, total bigint)) end;
    -- a stream with no net SELECT has no dated admission ledger: its admitted count is unknown (never 0), with the reason
    v_ns := case when s.net_sql is null then jsonb_build_object('known', false, 'window_hours', v_short, 'reason', coalesce(s.not_measured->>'net', 'Admissions are not counted for this stream'))
                 else security.data_delivery_net_v1(v_r->'net_short', v_short, v_stale, s.not_measured->>'net_empty') end;
    v_nl := case when s.net_sql is null then jsonb_build_object('known', false, 'window_hours', v_long, 'reason', coalesce(s.not_measured->>'net', 'Admissions are not counted for this stream'))
                 else security.data_delivery_net_v1(v_r->'net_long', v_long, v_stale, s.not_measured->>'net_empty') end;
    if (v_ns->>'known')::boolean and not (v_ns->>'removed_known')::boolean then v_ns := v_ns || jsonb_build_object('removed_reason', coalesce(s.not_measured->>'net_removed', 'Removals are not recorded for this stream')); end if;
    if (v_nl->>'known')::boolean and not (v_nl->>'removed_known')::boolean then v_nl := v_nl || jsonb_build_object('removed_reason', coalesce(s.not_measured->>'net_removed', 'Removals are not recorded for this stream')); end if;
    v_w := security.data_delivery_consumer_v1(v_r->'consumer', 'w', v_stale, s.not_measured->>'website');
    v_z := security.data_delivery_consumer_v1(v_r->'consumer', 'z', v_stale, s.not_measured->>'zoho');
    if (v_w->>'known')::boolean and s.not_measured ? 'website_pending' then v_w := v_w || jsonb_build_object('pending_reason', s.not_measured->>'website_pending'); end if;
    if (v_z->>'known')::boolean and s.not_measured ? 'zoho_pending' then v_z := v_z || jsonb_build_object('pending_reason', s.not_measured->>'zoho_pending'); end if;
    v_q := case when cardinality(s.queue_parts) = 0 then jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'queue', 'No queue is recorded for this stream'))
                else security.data_delivery_parts_v1(s.lane, s.queue_parts, v_stale, 0) end;
    v_h := case when cardinality(s.hold_parts) = 0 then jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'holds', 'No holds are recorded for this stream'))
                else security.data_delivery_parts_v1(s.lane, s.hold_parts, v_stale, v_top) end;
    if cardinality(s.hold_parts) > 0 and s.not_measured ? 'holds_by_cause' then v_h := v_h || jsonb_build_object('causes_reason', s.not_measured->>'holds_by_cause'); end if;
    -- speed: items per hour over the stated window (the ledger span when the ledger is younger than the window)
    if not (v_ns->>'known')::boolean then
      v_speed := jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'speed', v_ns->>'reason'));
    elsif v_ns->>'processed' is null then
      v_speed := jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'speed', 'Processing speed is not recorded for this stream'));
    else
      v_hrs := case when (v_ns->>'partial')::boolean and v_ns->>'since' is not null then greatest(extract(epoch from now() - (v_ns->>'since')::timestamptz) / 3600.0, 1) else v_short end;  -- fixed: at least one hour, so a young ledger is not divided by zero
      v_speed := jsonb_build_object('known', true, 'processed', (v_ns->>'processed')::numeric, 'window_hours', round(v_hrs, 1), 'per_hour', round((v_ns->>'processed')::numeric / v_hrs, 1), 'basis', s.speed_basis);
    end if;
    -- primary jobs: last and next run
    select coalesce(jsonb_agg(coalesce(v_runs->j.jobname, '{}'::jsonb) || jsonb_build_object('job', j.jobname, 'scheduled', v_runs ? j.jobname) order by j.ord), '[]'::jsonb)
      into v_jobs from unnest(s.primary_jobs) with ordinality j(jobname, ord);
    select jsonb_build_object('last_run_at', max((x->>'last_start')::timestamptz), 'next_run_at', min((x->>'next_run')::timestamptz) filter (where (x->>'active')::boolean),
             'runs', coalesce(sum((x->>'runs')::int), 0), 'succeeded', coalesce(sum((x->>'succeeded')::int), 0), 'failed', coalesce(sum((x->>'failed')::int), 0),
             'last_status', (array_agg(x->>'last_status' order by (x->>'last_start')::timestamptz desc nulls last))[1],
             'last_message', (array_agg(x->>'last_message' order by (x->>'last_start')::timestamptz desc nulls last))[1],
             'active', count(*) filter (where (x->>'active')::boolean), 'total', count(*),
             'history_hours', v_hist, 'known', v_hc_ok and count(*) filter (where x->>'last_start' is not null) > 0,
             'history_measured_at', v_hc_at, 'history_error', v_hc_err,
             'history_stale', v_hc_at is null or v_hc_at < now() - make_interval(mins => v_stale) or v_hc_err is not null,
             'reason', case when count(*) = 0 then 'No primary job is named for this stream'
                            when not v_hc_ok then 'The run history is not counted yet (the first count runs within minutes of release)' || coalesce(': ' || v_hc_err, '')
                            when count(*) filter (where x->>'last_start' is not null) = 0 then 'No run of ' || string_agg(x->>'job', ', ') || ' in the last ' || v_hist || ' hours of scheduler history' end)
      into v_job_sum from jsonb_array_elements(v_jobs) x;
    -- recovery: lane switch, open issues of the lane, automatic remedy runs in the short window
    select coalesce(bool_or((st.value #>> '{}') in ('0', 'false')), false) into v_off from unnest(s.switch_keys) k(key)
      join pipeline.platform_toolset_settings st on st.toolset_key = 'pipeline' and st.key = k.key;
    select count(*) filter (where i.status <> 'closed'), coalesce(jsonb_agg(i.issue_ref order by i.issue_ref) filter (where i.status <> 'closed'), '[]'::jsonb)
      into v_open, v_issue_refs from pipeline.integration_issues i where i.issue_ref = any(s.issue_refs);
    select count(*) filter (where rr.result in ('acted', 'verified')), count(*) filter (where rr.result in ('refused_authority', 'verify_failed')), max(rr.started_at)
      into v_remedy_ok, v_remedy_bad, v_remedy_last
      from pipeline.ops_remedy_runs rr join pipeline.integration_issues i on i.id = rr.issue_id
     where i.issue_ref = any(s.issue_refs) and rr.started_at > now() - make_interval(hours => v_short);
    v_active := coalesce((v_job_sum->>'active')::int, 0); v_total := coalesce((v_job_sum->>'total')::int, 0);
    v_last_status := v_job_sum->>'last_status';
    v_ok := coalesce((v_job_sum->>'succeeded')::int, 0); v_bad := coalesce((v_job_sum->>'failed')::int, 0);
    v_hint := v_h->'reasons'->0->>'reason';
    v_qtxt := case when (v_q->>'known')::boolean is not true then 'queue not counted'
                   when coalesce((v_q->>'n')::numeric, 0) = 0 then 'queue empty, nothing is waiting'
                   else (case when (v_q->>'partial')::boolean then 'at least ' else '' end) || (v_q->>'n') || ' waiting' end;
    -- a primary job that is paused or not scheduled is named: a stream must not read healthy while one of its jobs does not run
    select string_agg(x->>'job' || case when (x->>'scheduled')::boolean then ' is paused' else ' is not scheduled' end, '; ' order by x->>'job') into v_paused
      from jsonb_array_elements(v_jobs) x where not coalesce((x->>'active')::boolean, false);
    -- a stalled stream: its job ran OK in the window, the admitted count is known and 0, and something is waiting (or the queue is not counted)
    v_stalled := v_ok > 0 and coalesce((v_ns->>'admitted_known')::boolean, false) and coalesce((v_ns->>'added')::numeric, 0) = 0
                 and not ((v_q->>'known')::boolean and coalesce((v_q->>'n')::numeric, 0) = 0);
    v_rec := jsonb_build_object(
      'state', case when v_off then 'off' when v_paused is not null then 'paused' when v_last_status = 'failed' then 'failing' when v_open > 0 and v_remedy_ok > 0 then 'recovering'
                    when v_open > 0 then 'needs_attention' when v_total = 0 then 'unknown' when v_stalled then 'stalled' else 'healthy' end,
      'text', case when v_off then 'A switch for this stream is off, so nothing retries until it is switched on'
                   when v_paused is not null then 'Paused: ' || v_paused || ', so that work does not run until it is switched on'
                   when v_last_status = 'failed' then 'The last run failed; the job retries at its next scheduled run' || coalesce(' (' || to_char((v_job_sum->>'next_run_at')::timestamptz at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || ' Melbourne)', '')
                   when v_open > 0 and v_remedy_ok > 0 then v_open || ' open issue(s); automatic remedies acted ' || v_remedy_ok || ' time(s) in the window'
                   when v_open > 0 then v_open || ' open issue(s) and no automatic remedy has acted in the window'
                   when v_total = 0 then 'No primary job is named, so recovery is not measured'
                   when v_stalled then 'Stalled: the job ran OK ' || v_ok || ' time(s) in ' || v_short || ' h but admitted nothing (' || v_qtxt || '); it retries on schedule, and nothing is changing'
                   else 'No open issues; the scheduled job retries on its next run' end,
      'open_issues', v_open, 'issue_refs', v_issue_refs, 'remedy_acted', v_remedy_ok, 'remedy_refused', v_remedy_bad, 'last_remedy_at', v_remedy_last,
      'window_hours', v_short);
    -- a green job that admitted nothing (or whose admissions cannot be counted) is flagged
    v_flags := '[]'::jsonb;
    if v_ok > 0 and coalesce((v_ns->>'admitted_known')::boolean, false) and coalesce((v_ns->>'added')::numeric, 0) = 0 then
      -- a green job that admitted nothing is always shown; it reads as information, not an alarm, when nothing was waiting
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'green_no_admission',
        'severity', case when (v_q->>'known')::boolean and coalesce((v_q->>'n')::numeric, 0) = 0 then 'info' else 'warn' end,
        'queue_empty', (v_q->>'known')::boolean and coalesce((v_q->>'n')::numeric, 0) = 0,
        'text', 'Ran OK ' || v_ok || ' time(s) in ' || v_short || ' h, admitted nothing; ' || v_qtxt || coalesce('; top hold: ' || v_hint, '')));
    elsif v_ok > 0 and not coalesce((v_ns->>'admitted_known')::boolean, false) then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'green_admission_unknown', 'severity', 'warn',
        'text', 'Ran OK ' || v_ok || ' time(s) in ' || v_short || ' h; what it admitted is unknown (' || coalesce(v_ns->>'admitted_reason', v_ns->>'reason', 'not counted') || '); ' || v_qtxt));
    end if;
    if v_bad > 0 then v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'job_failing', 'severity', 'bad', 'text', v_bad || ' failed run(s) in ' || v_short || ' h')); end if;
    if (v_cov->>'known')::boolean is not true or (v_ns->>'known')::boolean is not true or not coalesce((v_ns->>'admitted_known')::boolean, false) then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'measure_unknown', 'severity', 'info', 'text', 'A headline measure could not be counted; see the reason in the cell'));
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'stream', s.stream, 'title', s.title, 'unit', s.unit, 'net_unit', coalesce(s.net_unit, s.unit), 'consumer_unit', coalesce(s.consumer_unit, s.unit), 'what', s.what, 'lane', s.lane, 'net_basis', s.net_basis, 'drill', s.drill,
      'coverage', v_cov, 'net_short', v_ns, 'net_long', v_nl, 'website', v_w, 'zoho', v_z, 'queue', v_q, 'holds', v_h, 'speed', v_speed,
      'jobs', v_job_sum || jsonb_build_object('list', v_jobs), 'recovery', v_rec, 'flags', v_flags,
      'stages', case when s.stream = 'cdesc' then security.data_delivery_cdesc_stages_v1() end,
      'stale', coalesce((v_cov->>'stale')::boolean, false) or coalesce((v_ns->>'stale')::boolean, false) or coalesce((v_w->>'stale')::boolean, false)));
  end loop;
  select min(r.measured_at), max(r.measured_at), count(*) filter (where r.error is not null) into v_oldest, v_newest, v_errors from pipeline.data_delivery_readings r;
  v_job := coalesce(v_runs->'data-delivery', jsonb_build_object('scheduled', false));
  return jsonb_build_object('at', now(), 'timezone', 'Australia/Melbourne', 'ui_refresh_seconds', v_ui, 'stale_after_minutes', v_stale,
    'windows', jsonb_build_object('short_hours', v_short, 'long_hours', v_long),
    'snapshot', jsonb_build_object('oldest_measured_at', v_oldest, 'newest_measured_at', v_newest, 'failed_measures', coalesce(v_errors, 0), 'job', v_job),
    'provider_filters_available', to_regprocedure('security.admin_providers_page_v3(jsonb)') is not null,
    'streams', v_out,
    'meaning', jsonb_build_object('net', 'admitted minus withdrawn, from the stream''s own ledger timestamps in the window',
      'unknown', 'Unknown or Not measured means the figure is not counted here; it is never shown as 0',
      'green', 'a job the scheduler reports as succeeded says nothing about data; the flag shows when it admitted nothing'));
end $function$

