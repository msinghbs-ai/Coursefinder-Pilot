-- HELD (not a migration): equivalence of the Operations reads before and after 20261110020000 (Operations load speed). READ ONLY on live data: nothing in a schema other than pg_temp is
-- created, written or changed (the old function texts and the result rows live in this session's temporary schema and vanish with it). Run it with the Platform Admin SQL editor AFTER the migration is
-- applied and the lane-funnel job has run once. It stops at the start if the migration is not there. The last statement returns one table (n, check, result, ms_old, ms_new, detail).
-- What it proves, on live data:
--   1 lane_funnel_v1(null) and lane_funnel_v1('<each lane>'): the old function (this file holds its production text, md5 cd8ecc118783da99f50c6fbd035cd3c1) and the new one give the same JSON apart from the
--     documented additions (job_history, history_known) and the cache-derived job fields (running, runs, failed, succeeded, last_start, last_end, last_status, last_message, last_success) and the clock
--     (at, next_run). Everything else must be identical. A cache-derived field may differ only where it is explained by the summary's age: a run started after the summary was made, or only the window's
--     counts sliding (same last attempt and same state). Anything else is reported as UNEXPLAINED and fails the check.
--   2 intake_progress_repeats_v1 (production md5 3f4a208ca8e0252eb17a1e21e73f80ca) and process_results_recovery_v1 (0bb7a5bd32ba384bf341214c9a5a9c3c): identical JSON (the recovery measurement
--     ignores measured_at / window_since, which are the time it was read).
--   3 the Layer 2/3 operations inbox: layer4_inbox_items_v1() and layer4_inbox_items_v2(null, null, null, false) give the same multiset of (kind, provider_id), which is all admin_layer23('operations') uses.
--   4 timings: each old and new read, three times each, clock_timestamp() around the call; the lane funnel old read is the slow one (4.5 to 20 s on 10 Nov 2026) and may stop at the limit of an SQL editor.
-- Cache-derived fields are not expected to be byte-identical: the lane funnel read now shows the summary kept by job lane-funnel (at most lane_funnel.job_runs_refresh_seconds old when the job is running).
create temp table eq_out(n int generated always as identity, chk text, result text, ms_old numeric, ms_new numeric, detail text);

CREATE OR REPLACE FUNCTION pg_temp.old_lane_funnel_v1(p_lane text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $old_body$
declare
  l record; v_out jsonb := '[]'::jsonb; v_lane jsonb; v_jobs jsonb; v_sw jsonb; v_set jsonb; v_stages jsonb; v_issues jsonb; v_budget jsonb;
  v_win int := security.pipeline_num_v1('lane_funnel.gain_window_hours', 24)::int;
  v_hist int := security.pipeline_num_v1('lane_funnel.run_history_hours', 48)::int;
  v_stale int := security.pipeline_num_v1('lane_funnel.stale_after_minutes', 45)::int;
  v_max int := security.pipeline_num_v1('lane_funnel.settings_shown_max', 60)::int;
  v_fc jsonb := security.fc_budget_status_v1();
  v_active int; v_jobs_n int; v_failing int; v_green int; v_eligible numeric; v_transfer numeric; v_transfer_known boolean; v_published numeric;
  v_verdict text; v_off_switch boolean; v_unknown_switch boolean;
begin
  for l in select * from pipeline.lane_funnel_lanes x where p_lane is null or x.lane = p_lane order by x.sort, x.lane loop
    -- jobs: schedule, state, next run, last attempt and result over the scheduler history, first-run verification of the newest release
    select coalesce(jsonb_agg(jb order by jb->>'job'), '[]'::jsonb) into v_jobs from (
      select jsonb_build_object('job', j.jobname, 'label', a.label, 'schedule', c.schedule, 'active', c.active, 'scheduled', c.jobid is not null, 'control_rank', coalesce(a.control_rank, 6),
          'next_run', case when c.jobid is not null and c.active then security.cron_next_run_v1(c.schedule, now()) end,
          'running', coalesce(g.running, false), 'runs', coalesce(g.runs, 0), 'failed', coalesce(g.failed, 0), 'succeeded', coalesce(g.succeeded, 0),
          'last_start', r.start_time, 'last_end', r.end_time, 'last_status', r.status, 'last_message', left(r.return_message, 240),
          'last_success', g.last_success,
          'first_run', (select jsonb_build_object('release', v.release, 'status', v.status, 'first_run_status', v.first_run_status, 'first_run_at', v.first_run_at,
                                                  'expected_first_run', v.expected_first_run, 'actual_output', v.actual_output, 'reason', left(v.status_reason, 200))
                          from pipeline.release_job_verifications v where v.jobname = j.jobname order by v.registered_at desc limit 1)) jb
        from unnest(l.jobs) j(jobname)
        left join pipeline.automation_catalogue a on a.jobname = j.jobname
        left join cron.job c on c.jobname = j.jobname
        left join lateral (select d.start_time, d.end_time, d.status, d.return_message from cron.job_run_details d
                            where d.jobid = c.jobid and d.start_time > now() - make_interval(hours => v_hist) order by d.start_time desc limit 1) r on true
        left join lateral (select count(*) filter (where d.start_time > now() - make_interval(hours => v_win)) runs,
                                  count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'failed') failed,
                                  count(*) filter (where d.start_time > now() - make_interval(hours => v_win) and d.status = 'succeeded') succeeded,
                                  bool_or(d.status in ('running', 'starting')) running, max(d.start_time) filter (where d.status = 'succeeded') last_success
                             from cron.job_run_details d where d.jobid = c.jobid and d.start_time > now() - make_interval(hours => v_hist)) g on true) q;
    select count(*) filter (where (x->>'active')::boolean), count(*), count(*) filter (where (x->>'failed')::int > 0),
           count(*) filter (where (x->>'active')::boolean and (x->>'succeeded')::int > 0 and (x->>'failed')::int = 0)
      into v_active, v_jobs_n, v_failing, v_green from jsonb_array_elements(v_jobs) x;
    -- switches: a pipeline setting that is 1 / true is on, 0 / false is off, a missing setting is unknown
    select coalesce(jsonb_agg(jsonb_build_object('key', k.key, 'label', s.label, 'value', s.value, 'on', case when s.key is null then null else (s.value #>> '{}') in ('1', 'true') end) order by k.ord), '[]'::jsonb)
      into v_sw from unnest(l.switch_keys) with ordinality k(key, ord) left join pipeline.platform_toolset_settings s on s.toolset_key = 'pipeline' and s.key = k.key;
    select bool_or(x->'on' = 'false'::jsonb), bool_or(x->'on' = 'null'::jsonb) into v_off_switch, v_unknown_switch from jsonb_array_elements(v_sw) x;
    select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'unit', s.unit, 'min', s.min_value, 'max', s.max_value, 'section', s.section,
                                                 'used_by', s.used_by, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb) into v_set
      from (select x.* from pipeline.platform_toolset_settings x where x.toolset_key = 'pipeline'
              and exists (select 1 from unnest(l.setting_prefixes) p where left(x.key, length(p)) = p) order by x.sort, x.key limit v_max) s;
    -- stages
    select coalesce(jsonb_agg(sg order by (sg->>'step')::int), '[]'::jsonb) into v_stages from (
      select jsonb_build_object('step', st.step, 'key', st.key, 'title', st.title, 'kind', st.kind, 'what', st.what, 'drill', st.drill,
          'source', case when st.transition_key is not null then 'progress contract' else 'counted' end,
          'n', case when t.key is not null then t.input_eligible else r.n end,
          'oldest_at', case when t.key is not null then null else r.oldest_at end,
          'gain', case when t.key is not null then case st.kind when 'admitted' then t.output_admitted when 'published' then t.output_published else t.output_created end else r.gain end,
          'processed', case when t.key is not null then t.input_processed end,
          'created', case when t.key is not null then t.output_created end,
          'reasons', case when t.key is not null then nullif(jsonb_strip_nulls(jsonb_build_object('rejected', t.rejected_reasons, 'parked', t.parked_next_actions)), '{}'::jsonb) else r.reasons end,
          'zero_reason', t.zero_reason, 'zero_detail', t.zero_detail, 'stalled', coalesce(t.stalled, false), 'last_advanced_at', t.last_advanced_at,
          'window_start', t.window_start,
          'measured_at', case when t.key is not null then t.measured_at else r.measured_at end,
          'stale', coalesce(case when t.key is not null then t.measured_at else r.measured_at end < now() - make_interval(mins => v_stale), false),
          'error', case when t.key is not null then t.measure_error else r.error end,
          'took_ms', r.took_ms,
          'n_prev', (select h.n from pipeline.lane_funnel_history h where h.lane = st.lane and h.stage_key = st.key and h.measured_at <= now() - make_interval(hours => v_win)
                      order by h.measured_at desc limit 1)) sg
        from pipeline.lane_funnel_stages st
        left join pipeline.progress_transitions t on t.key = st.transition_key
        left join pipeline.lane_funnel_readings r on r.lane = st.lane and r.stage_key = st.key
       where st.lane = l.lane) q;
    -- verdict: a green job, a stage transfer and published data are three different things
    select sum((x->>'n')::numeric) filter (where x->>'kind' in ('eligible', 'queued', 'review_ready')),
           sum((x->>'gain')::numeric) filter (where x->>'kind' = 'admitted'), bool_or(x->>'gain' is not null) filter (where x->>'kind' = 'admitted'),
           sum((x->>'gain')::numeric) filter (where x->>'kind' = 'published')
      into v_eligible, v_transfer, v_transfer_known, v_published from jsonb_array_elements(v_stages) x;
    v_verdict := case
      when v_jobs_n = 0 and not exists (select 1 from jsonb_array_elements(v_sw) x) then 'unknown'
      when coalesce(v_off_switch, false) or (v_jobs_n > 0 and v_active = 0) then 'off'
      when v_failing > 0 then 'failing'
      when exists (select 1 from jsonb_array_elements(v_stages) x where (x->>'stalled')::boolean) then 'stalled'
      when coalesce(v_transfer, 0) > 0 or coalesce(v_published, 0) > 0 then 'transferring'
      when v_green > 0 and coalesce(v_eligible, 0) > 0 and coalesce(v_transfer_known, false) then 'green_no_transfer'
      when v_green > 0 and not coalesce(v_transfer_known, false) and coalesce(v_published, 0) = 0 then 'green_transfer_unknown'
      else 'idle' end;
    select coalesce(jsonb_agg(jsonb_build_object('ref', i.issue_ref, 'title', i.title, 'status', i.status, 'severity', i.severity) order by i.issue_ref), '[]'::jsonb) into v_issues
      from pipeline.integration_issues i where i.issue_ref = any(l.issue_refs);
    v_budget := case when l.budget_group is null then null else (
      select jsonb_build_object('group', l.budget_group, 'label', g->>'label', 'share_today', (g->>'share')::numeric, 'used_today', (g->>'used')::numeric, 'refused_today', (g->>'refused')::numeric,
                                'credits_window', coalesce((select sum(u.units) from pipeline.coverage_vendor_usage u where u.at > now() - make_interval(hours => v_win) and security.fc_purpose_group_v1(u.purpose) = l.budget_group), 0),
                                'unit', 'credits', 'shared', 'the group is shared by every lane that reads with it')
        from jsonb_array_elements(v_fc->'groups') g where g->>'group' = l.budget_group) end;
    v_lane := jsonb_build_object('lane', l.lane, 'title', l.title, 'what', l.what, 'screen', l.screen, 'review_kinds', to_jsonb(l.review_kinds), 'verdict', v_verdict,
      'jobs', v_jobs, 'jobs_active', v_active, 'jobs_total', v_jobs_n, 'jobs_failing', v_failing, 'jobs_green', v_green, 'switches', v_sw, 'settings', v_set, 'stages', v_stages, 'issues', v_issues,
      'budget', v_budget, 'transfer_24h', v_transfer, 'published_24h', v_published);
    v_out := v_out || jsonb_build_array(v_lane);
  end loop;
  return jsonb_build_object('at', now(), 'window_hours', v_win, 'lanes', v_out,
    'meaning', jsonb_build_object('green_job', 'the scheduler reports the job as succeeded; it says nothing about data',
      'stage_transfer', 'items that moved into the admitted stage in the window (a new value held in the catalogue)',
      'published', 'items that reached the consumer-visible stage in the window'));
end $old_body$;

CREATE OR REPLACE FUNCTION pg_temp.old_intake_progress_repeats_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $old_body$
  -- Platform Admin 5 Nov 2026 22:46: each deterministic refusal of the last day that repeats the same failure class of the same intake row is classified
  -- from existing records only, in this order:
  --   excluded_source_update   the calendar set, calendar document, approved reading, periods, evidence year or course page wording differ between the two decisions;
  --   excluded_reader_revision the reader or rule differ, or a release that changed an intake or calendar function was deployed between them
  --                            (pipeline.integration_deploy_checks.result->functions);
  --   excluded_setting_change  an intake_dates.* or run_now.* setting was changed between them: the Settings audit (pipeline.admin_control_events)
  --                            or, for a change written without an audit row, the setting's last-changed time (platform_toolset_settings.updated_at);
  --   unverified_repeat        the inputs of the later decision cannot be established and the earlier one shows no difference (no calendar set, page
  --                            wording or rule on both), or a release between them does not record the functions it changed; a gap on only one
  --                            of the two decisions is a difference and counts as a source update (also never raised);
  --   confirmed                otherwise: evidence, reader and settings demonstrably unchanged.
  with ev as (select e.intake_id, e.run_at, e.failure_class, e.calendar_set, e.calendar_evidence_id, e.proposal_id, e.periods, e.evidence_year, e.page_quote, e.reader, e.rule,
                     p.run_at p_at, p.calendar_set p_set, p.calendar_evidence_id p_doc, p.proposal_id p_prop, p.periods p_periods, p.evidence_year p_year, p.page_quote p_quote,
                     p.reader p_reader, p.rule p_rule, p.next_revisit_at p_revisit
                from pipeline.course_intake_date_events e
                cross join lateral (select x.* from pipeline.course_intake_date_events x
                                     where x.intake_id = e.intake_id and x.run_at < e.run_at and x.failure_class = e.failure_class order by x.run_at desc limit 1) p
               where e.run_at >= now() - make_interval(days => 1) and e.deterministic and e.outcome = 'skipped'),  -- fixed: the one-day check named by decision 16:36 §6
  st as (select a.created_at at from pipeline.admin_control_events a
          where a.area in ('toolsets', 'settings') and a.action in ('setting', 'change') and a.target ~ '^(pipeline\.)?(intake_dates|run_now)\.'
            and a.created_at >= (select min(ev.p_at) from ev)
         -- a change written without an audit row (for example by a release) is still seen through the setting's own last-changed time
         union all
         select s.updated_at from pipeline.platform_toolset_settings s
          where s.toolset_key = 'pipeline' and s.key ~ '^(intake_dates|run_now)\.' and s.updated_at >= (select min(ev.p_at) from ev)),
  rel as (select r.since at, exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.result->'functions') = 'array' then r.result->'functions' else '[]'::jsonb end) f
                                      where f->>'function' ~ '^security\.(intake_|calendar_)') intake_fn,
                 coalesce(jsonb_typeof(r.result->'functions') = 'array', false) known
            from pipeline.integration_deploy_checks r where r.since >= (select min(ev.p_at) from ev)),
  k as (select ev.*, case
          when ev.calendar_set is distinct from ev.p_set or ev.calendar_evidence_id is distinct from ev.p_doc or ev.proposal_id is distinct from ev.p_prop
               or ev.periods is distinct from ev.p_periods or ev.evidence_year is distinct from ev.p_year or ev.page_quote is distinct from ev.p_quote then 'excluded_source_update'
          when ev.reader is distinct from ev.p_reader or ev.rule is distinct from ev.p_rule
               or exists (select 1 from rel where rel.at > ev.p_at and rel.at < ev.run_at and rel.intake_fn) then 'excluded_reader_revision'
          when exists (select 1 from st where st.at > ev.p_at and st.at < ev.run_at) then 'excluded_setting_change'
          -- F-INT 9 Nov 2026: the earlier decision set a revisit time and this look is on or after it: a scheduled look, not an unchanged repeat
          when ev.p_revisit is not null and ev.run_at >= ev.p_revisit then 'excluded_scheduled_revisit'
          when ev.calendar_set is null or ev.page_quote is null or ev.rule is null
               or exists (select 1 from rel where rel.at > ev.p_at and rel.at < ev.run_at and not rel.known) then 'unverified_repeat'
          else 'confirmed' end status from ev)
  select jsonb_build_object(
    'confirmed', (select count(distinct k.intake_id) from k where k.status = 'confirmed'),
    'excluded_source_update', (select count(distinct k.intake_id) from k where k.status = 'excluded_source_update'),
    'excluded_reader_revision', (select count(distinct k.intake_id) from k where k.status = 'excluded_reader_revision'),
    'excluded_setting_change', (select count(distinct k.intake_id) from k where k.status = 'excluded_setting_change'),
    'excluded_scheduled_revisit', (select count(distinct k.intake_id) from k where k.status = 'excluded_scheduled_revisit'),
    'unverified_repeat', (select count(distinct k.intake_id) from k where k.status = 'unverified_repeat'),
    'examples', (select coalesce(jsonb_agg(jsonb_build_object('status', z.status, 'intake_id', z.intake_id, 'class', z.failure_class, 'decided', z.run_at, 'earlier', z.p_at)), '[]'::jsonb)
                   from (select distinct on (k.status) k.* from k order by k.status, k.run_at desc) z))
$old_body$;

CREATE OR REPLACE FUNCTION pg_temp.old_process_results_recovery_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $old_body$
  with u as (select (e->>'id')::uuid id, e->>'name' name from jsonb_array_elements(security.intake_ui_scopes_v1()) e),
  w as (select now() - make_interval(days => security.pipeline_num_v1('process_results.window_days', 7)::int) since),
  ev as (select e.* from pipeline.course_intake_date_events e, w where e.run_at >= w.since and e.provider_id in (select id from u)),
  d as (select d.* from pipeline.course_intake_dates d where d.provider_id in (select id from u))
  select jsonb_build_object(
    'measured_at', now(), 'window_since', (select since from w),
    'admitted', (select coalesce(jsonb_agg(x order by x->>'university', x->>'year'), '[]'::jsonb) from (
       select jsonb_build_object('university', u.name, 'source_type', 'approved calendar', 'rule', ev.rule, 'year', coalesce((ev.after_value->>'year')::int, (ev.before_value->>'year')::int),
                'precision', ev.start_precision, 'admitted', count(*), 'with_start_date', count(*) filter (where ev.after_value->>'start_date' is not null),
                'with_deadline', count(*) filter (where ev.after_value->>'application_deadline' is not null),
                'published', count(*) filter (where ev.publication_state = 'published'), 'publication_failed', count(*) filter (where ev.publication_state = 'consumer_publication_failed'),
                'provider_not_published', count(*) filter (where ev.publication_state in ('provider_not_published', 'course_not_in_consumer_source')), 'not_checked', count(*) filter (where ev.publication_state is null)) x
         from ev join u on u.id = ev.provider_id where ev.outcome = 'filled'
        group by u.name, ev.rule, coalesce((ev.after_value->>'year')::int, (ev.before_value->>'year')::int), ev.start_precision) z),
    'classes', (select coalesce(jsonb_agg(x order by (x->>'rows')::int desc), '[]'::jsonb) from (
       select jsonb_build_object('university', u.name, 'class', coalesce(d.failure_class, case when d.next_action = 'complete' then 'complete' else 'not_classified_yet' end),
                'deterministic', bool_and(d.deterministic), 'rows', count(*), 'reason', min(d.reason), 'next_revisit_at', min(d.next_revisit_at), 'revisit_trigger', min(d.revisit_trigger)) x
         from d join u on u.id = d.provider_id
        group by u.name, coalesce(d.failure_class, case when d.next_action = 'complete' then 'complete' else 'not_classified_yet' end)) z),
    'refresh', jsonb_build_object(
       'budget', security.pipeline_num_v1('central.calendar_refresh_credit_budget', 40),
       'credits_counted', (select coalesce(sum(greatest(q.credit_estimate, coalesce(q.credits_used, 0))), 0) from pipeline.calendar_refresh_requests q),
       'credits_used', (select coalesce(sum(q.credits_used), 0) from pipeline.calendar_refresh_requests q),
       'requests', (select coalesce(jsonb_agg(jsonb_build_object('university', u.name, 'url', q.url, 'requested_at', q.requested_at, 'reason', q.reason, 'status', q.status,
                       'credits_used', q.credits_used, 'yield', q.yield, 'next_year_starts', q.next_year_starts) order by q.requested_at desc), '[]'::jsonb)
                      from pipeline.calendar_refresh_requests q join u on u.id = q.provider_id)),
    'reader', (select coalesce(jsonb_agg(jsonb_build_object('reader', s.reader_version, 'state', s.state, 'documents', s.n) order by s.reader_version nulls first, s.state), '[]'::jsonb)
                 from (select reader_version, state, count(*) n from pipeline.calendar_reread_state group by 1, 2) s),
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'last_run', (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid),
                       'last_status', (select r.status from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1))), '[]'::jsonb)
               from cron.job j where j.jobname in ('calendar-reread', 'central-ai', 'provider-facts', 'intake-dates-apply', 'process-results')))
$old_body$;

do $eq$
declare
  v_a jsonb; v_b jsonb; v_t timestamptz; v_ms_o numeric; v_ms_n numeric; v_i int; v_lane text; v_bad int; v_diff int; v_exp int;
  v_cache constant text[] := array['running','runs','failed','succeeded','last_start','last_end','last_status','last_message','last_success'];
  v_drop constant text[] := array['history_known','next_run'];
  v_meas timestamptz;
begin
  if position('job_history' in pg_get_functiondef('security.lane_funnel_v1(text)'::regprocedure)) = 0 then
    raise exception 'migration 20261110020000 is not applied: run this after it';
  end if;
  select r.measured_at into v_meas from pipeline.lane_funnel_job_runs r where r.singleton;

  -- 1 lane funnel: all lanes, then each lane on its own
  for v_lane in select null union all select x.lane from pipeline.lane_funnel_lanes x order by 1 nulls first loop
    v_t := clock_timestamp(); v_a := pg_temp.old_lane_funnel_v1(v_lane); v_ms_o := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_t := clock_timestamp(); v_b := security.lane_funnel_v1(v_lane);    v_ms_n := extract(epoch from clock_timestamp() - v_t) * 1000;
    -- the same lanes, stages, switches, settings, budget, issues and job identity; only the cache-derived job fields may differ
    with oj as (select l->>'lane' lane, j from jsonb_array_elements(v_a->'lanes') l, jsonb_array_elements(l->'jobs') j),
         nj as (select l->>'lane' lane, j from jsonb_array_elements(v_b->'lanes') l, jsonb_array_elements(l->'jobs') j),
         pair as (select o.lane, o.j oldj, n.j newj from oj o full join nj n on n.lane = o.lane and n.j->>'job' = o.j->>'job'),
         strip as (select lane, (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(oldj) e(k, v) where k <> all(v_cache || v_drop)) o_rest,
                          (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(newj) e(k, v) where k <> all(v_cache || v_drop)) n_rest,
                          (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(oldj) e(k, v) where k = any(v_cache)) o_c,
                          (select coalesce(jsonb_object_agg(k, v), '{}') from jsonb_each(newj) e(k, v) where k = any(v_cache)) n_c from pair)
    select count(*) filter (where o_rest is distinct from n_rest),
           count(*) filter (where o_c is distinct from n_c),
           count(*) filter (where o_c is distinct from n_c
              and (  (o_c->>'last_start')::timestamptz > coalesce(v_meas, '-infinity')                                   -- a run started after the summary was made
                  or (o_c->'last_start' = n_c->'last_start' and o_c->'last_status' = n_c->'last_status' and o_c->'running' = n_c->'running'))) -- only the window's counts slid
      into v_bad, v_diff, v_exp from strip;
    insert into eq_out(chk, result, ms_old, ms_new, detail) values
      ('lane funnel ' || coalesce(v_lane, '(all lanes)') || ': everything except the cache-derived job fields',
       case when v_bad = 0 and (v_a - 'at' - 'lanes') = (v_b - 'at' - 'lanes' - 'job_history')
              and (select jsonb_agg(l - 'jobs' order by l->>'lane') from jsonb_array_elements(v_a->'lanes') l) is not distinct from (select jsonb_agg(l - 'jobs' order by l->>'lane') from jsonb_array_elements(v_b->'lanes') l)
            then 'SAME' else 'DIFFERENT' end, round(v_ms_o, 1), round(v_ms_n, 1),
       'jobs whose identity fields differ: ' || v_bad || '; jobs whose cache-derived fields differ: ' || v_diff || ', of which explained by the summary age: ' || v_exp ||
       case when v_diff > v_exp then ' (UNEXPLAINED ' || (v_diff - v_exp) || ')' else '' end);
    if v_diff > v_exp then update eq_out set result = 'UNEXPLAINED' where n = (select max(n) from eq_out); end if;
  end loop;
  -- the job_history block names its own age
  insert into eq_out(chk, result, detail) select 'lane funnel: job_history', case when (v_b->'job_history'->>'known')::boolean then 'KNOWN' else 'UNKNOWN' end,
    'age ' || coalesce(v_b->'job_history'->>'age_seconds', '?') || ' s, stale ' || coalesce(v_b->'job_history'->>'stale', '?') || ', error ' || coalesce(v_b->'job_history'->>'error', 'none');

  -- 2 the intake status repeat check and the process results recovery measurement
  v_t := clock_timestamp(); v_a := pg_temp.old_intake_progress_repeats_v1(); v_ms_o := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp(); v_b := security.intake_progress_repeats_v1();    v_ms_n := extract(epoch from clock_timestamp() - v_t) * 1000;
  insert into eq_out(chk, result, ms_old, ms_new, detail) values ('intake status: repeat check', case when v_a = v_b then 'SAME' else 'DIFFERENT' end, round(v_ms_o, 1), round(v_ms_n, 1), left(v_b::text, 120));
  v_t := clock_timestamp(); v_a := pg_temp.old_process_results_recovery_v1(); v_ms_o := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp(); v_b := security.process_results_recovery_v1();    v_ms_n := extract(epoch from clock_timestamp() - v_t) * 1000;
  insert into eq_out(chk, result, ms_old, ms_new, detail) values ('process results: recovery measurement',
    case when (v_a - 'measured_at' - 'window_since' - 'jobs') = (v_b - 'measured_at' - 'window_since' - 'jobs')
          and (select jsonb_agg(x order by x->>'job') from jsonb_array_elements(v_a->'jobs') x) is not distinct from (select jsonb_agg(x order by x->>'job') from jsonb_array_elements(v_b->'jobs') x)
         then 'SAME' else 'DIFFERENT' end, round(v_ms_o, 1), round(v_ms_n, 1), 'five jobs by name, last run over the whole history');

  -- 3 the Layer 2/3 operations inbox: kind and provider only
  v_t := clock_timestamp(); select count(*) into v_i from security.layer4_inbox_items_v1() i; v_ms_o := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp(); select count(*) into v_bad from security.layer4_inbox_items_v2(null, null, null, false) i; v_ms_n := extract(epoch from clock_timestamp() - v_t) * 1000;
  select count(*) into v_diff from ((select i.kind, i.provider_id from security.layer4_inbox_items_v1() i except all select i.kind, i.provider_id from security.layer4_inbox_items_v2(null, null, null, false) i)
                                    union all (select i.kind, i.provider_id from security.layer4_inbox_items_v2(null, null, null, false) i except all select i.kind, i.provider_id from security.layer4_inbox_items_v1() i)) z;
  insert into eq_out(chk, result, ms_old, ms_new, detail) values ('Layer 2/3 operations inbox: kind and provider', case when v_diff = 0 and v_i = v_bad then 'SAME' else 'DIFFERENT' end, round(v_ms_o, 1), round(v_ms_n, 1), v_i || ' items, ' || v_diff || ' differ');

  -- 4 repeated timings (warm)
  for v_i in 1 .. 3 loop
    v_t := clock_timestamp(); v_a := pg_temp.old_lane_funnel_v1(null); v_ms_o := extract(epoch from clock_timestamp() - v_t) * 1000;
    v_t := clock_timestamp(); v_b := security.lane_funnel_v1(null);    v_ms_n := extract(epoch from clock_timestamp() - v_t) * 1000;
    insert into eq_out(chk, result, ms_old, ms_new, detail) values ('lane funnel (all lanes), timing ' || v_i, 'TIMED', round(v_ms_o, 1), round(v_ms_n, 1), '');
  end loop;
end $eq$;

select n, chk, result, ms_old, ms_new, detail from eq_out order by n;
