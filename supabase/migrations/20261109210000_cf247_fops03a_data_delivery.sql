-- CF-247 F-OPS.03A (Platform Admin P0, 9 Nov 2026 21:28 Melbourne): "Operational progress visibility is not accepted. I should not have to rely on your chat messages to know whether
-- StudySearch is processing, admitting or publishing data." An always-visible, live Data Delivery summary at the TOP of the existing Layer 2/3 > Operations screen.
-- It reuses the lane funnel registry, readings and job history (20261108170000) and the Provider Catalogue facts (20261109200000, #956); there is no second dashboard,
-- no second scheduler and no new menu.
--
-- What:
--   1 pipeline.data_delivery_streams   one row per data stream (provider descriptions, intake dates, course descriptions, fees, English, entry requirements AER,
--                                      scholarships, discovery/official links): its lane, its primary jobs, the read-only SELECT of each measure (coverage, net gain
--                                      from ledger timestamps, Website/Zoho carriage), the lane stages that make up its queue and its holds, what is NOT measured and
--                                      why, and where the numbers drill down. A stream adds a measure by inserting a row (its own migration), never by editing a function.
--   2 pipeline.data_delivery_readings  the counted result of each measure with its time, duration and error (a snapshot, so the screen never runs the heavy SELECTs).
--   3 security.data_delivery_refresh_v1 (job data-delivery: the only writer; due check, single flight, per-run batch and time budget, records only),
--     security.data_delivery_v1 (ONE set-based, read-only read: per stream coverage n of N and %, 24 h and 7 d net admission gains (admitted minus withdrawn, from the
--     ledger timestamps of each stream), Website and Zoho state (matched / pending / missing / not applicable, or Not measured with the reason), queue, holds with the top
--     exact reasons, speed (items per hour over a stated window), last and next run of the primary jobs, a visible flag when a job ran green but admitted nothing,
--     and the automatic recovery status), small helper functions, and the action data_delivery of public.admin_layer23 (rank 3 and above, the same gate as Operations).
--   4 pdesc lane stages (waiting for the reader; held, by normalised cause) so the Provider description queue and holds are counted from the reader's own ledger.
--   5 settings (G2, toolset pipeline, section "Data delivery"): switch, count-again time, measures per run, run time budget, short and long net windows, stale time, the
--     screen's refresh interval, scheduler history span and the number of exact reasons shown. Job data-delivery (catalogued first).
-- Unknown is never zero: a measure that is not counted, could not be counted or has no ledger is returned as known=false with the reason, and the screen prints Unknown /
-- Not measured with that reason. The gaps are listed in the pull request as follow-ups; nothing is estimated.
-- Live definitions (read 9 Nov 2026, project fxcwkweaxjtknorudmwp; body md5 = pg_proc.prosrc):
--   public.admin_layer23(text,jsonb)  body b1d08c144078fce71ba2cd3762a00b0f  (edited here: one exact, md5-guarded text edit adding the action data_delivery)
-- Activation: ON (records only: it writes its own snapshot, spends no credit, calls no API, changes no catalogue value). data_delivery.on = 0 stops the refresh; the
--   screen then shows the last counted figures marked stale. A passing check never switches anything on by itself: no automation switch is touched.
-- Consumer API (G3): not touched. No public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, api.* object or consumer edge function is
--   created, altered, dropped or granted. The consumer feed tables (pipeline.website_sync_items, pipeline.zoho_sync_items) and the candidate functions
--   (security.website_sync_candidates_v1, security.zoho_sync_candidates_v1) are READ ONLY, exactly as the Provider Catalogue facts read them.
-- Replaces: nothing (the lane funnels and the Provider Catalogue facts stay; this reads them and puts one summary above them)
-- Retires: nothing
-- Nothing is dropped or deleted by this migration.

do $guard$
begin
  if to_regclass('pipeline.platform_toolset_settings') is null or to_regclass('pipeline.automation_catalogue') is null then
    raise exception 'data delivery needs the settings register and the automation catalogue first';
  end if;
  if to_regprocedure('security.pipeline_num_v1(text,numeric)') is null or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'data delivery needs security.pipeline_num_v1 and security.current_role_rank first';
  end if;
  if to_regclass('pipeline.lane_funnel_lanes') is null or to_regclass('pipeline.lane_funnel_stages') is null or to_regclass('pipeline.lane_funnel_readings') is null
     or to_regprocedure('security.lane_funnel_eval_v1(text,integer)') is null then
    raise exception 'data delivery needs the lane funnels (20261108170000) first';
  end if;
  if to_regprocedure('security.cron_next_run_v1(text,timestamp with time zone)') is null then raise exception 'data delivery needs security.cron_next_run_v1'; end if;
  if to_regprocedure('security.website_sync_candidates_v1(text)') is null or to_regprocedure('security.zoho_sync_candidates_v1(text)') is null then
    raise exception 'data delivery needs the feed candidate functions (read only)';
  end if;
  if to_regprocedure('public.admin_layer23(text,jsonb)') is null then raise exception 'data delivery needs public.admin_layer23'; end if;
end $guard$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'data_delivery.on', 'Data delivery: count every stream''s coverage, gains and Website/Zoho state',
  '1: job data-delivery counts, for each data stream, coverage, the gains of the short and long windows and the Website and Zoho state, and keeps the figures for the Data Delivery summary at the top of Layer 2/3 > Operations. 0: no new count; the summary shows the last figures marked stale. Records only: no credit, no API call, no change to any catalogue value.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1800, 'F-OPS.03A (Platform Admin 9 Nov 2026): live Data Delivery summary; ships on, records only', 'Data delivery', 'security.data_delivery_refresh_v1 (job data-delivery)'),
 ('pipeline', 'data_delivery.refresh_minutes', 'Data delivery: count each measure again after',
  'A measure is counted again when its last count is older than this. The job looks every minute; this keeps each measure to one count in this time.',
  'number', to_jsonb(10), 2, 240, 'minutes', 1801, 'F-OPS.03A', 'Data delivery', 'security.data_delivery_refresh_v1'),
 ('pipeline', 'data_delivery.measures_per_run', 'Data delivery: measures counted in one run',
  'At most this many due measures (oldest first) are counted in one run of the job, so no single run holds the database for long.',
  'number', to_jsonb(8), 1, 40, 'measures', 1802, 'F-OPS.03A', 'Data delivery', 'security.data_delivery_refresh_v1'),
 ('pipeline', 'data_delivery.run_budget_seconds', 'Data delivery: stop starting new counts in a run after',
  'A run counts due measures one after another and stops starting a new one once this much time has passed, so a run cannot grow without limit. A count that has already started is not interrupted (the database''s own statement time limit still applies); if it fails, the measure shows unknown with the error.',
  'number', to_jsonb(30), 5, 300, 'seconds', 1803, 'F-OPS.03A', 'Data delivery', 'security.data_delivery_refresh_v1'),
 ('pipeline', 'data_delivery.net_short_hours', 'Data delivery: short window for net gains and speed',
  'The first net-gain column (admitted minus withdrawn, from ledger timestamps), the job run counts, the green-with-nothing-admitted flag and the speed use this many hours. The column is headed with this value.',
  'number', to_jsonb(24), 1, 168, 'hours', 1804, 'F-OPS.03A: 24-hour net gain', 'Data delivery', 'security.data_delivery_refresh_v1; security.data_delivery_v1'),
 ('pipeline', 'data_delivery.net_long_hours', 'Data delivery: long window for net gains',
  'The second net-gain column uses this many hours (168 is seven days). Where a stream''s ledger is younger than the window, the column says so and shows the ledger start.',
  'number', to_jsonb(168), 24, 720, 'hours', 1805, 'F-OPS.03A: 7-day net gain', 'Data delivery', 'security.data_delivery_refresh_v1; security.data_delivery_v1'),
 ('pipeline', 'data_delivery.stale_after_minutes', 'Data delivery: a count is marked stale after',
  'A measure older than this shows a Stale chip with its age. Keep it above the count-again time.',
  'number', to_jsonb(30), 5, 1440, 'minutes', 1806, 'F-OPS.03A', 'Data delivery', 'security.data_delivery_v1'),
 ('pipeline', 'data_delivery.ui_refresh_seconds', 'Data delivery: the summary reloads itself every',
  'The Data Delivery summary asks for fresh figures this often while the tab is visible (it stops while the tab is hidden and reloads when it is shown again). The Refresh button reloads at once.',
  'number', to_jsonb(60), 15, 3600, 'seconds', 1807, 'F-OPS.03A: refresh automatically', 'Data delivery', 'Layer 2/3 > Operations > Data Delivery (security.data_delivery_v1)'),
 ('pipeline', 'data_delivery.run_history_hours', 'Data delivery: scheduler history read for the last-run columns',
  'The last run, last success and run counts of each stream''s primary jobs are read from this much scheduler history. A job with no run in it shows Unknown, not never.',
  'number', to_jsonb(48), 2, 336, 'hours', 1808, 'F-OPS.03A: last and next run', 'Data delivery', 'security.data_delivery_v1'),
 ('pipeline', 'data_delivery.reasons_shown', 'Data delivery: exact hold reasons shown per stream',
  'Each stream lists its largest hold reasons, by count, up to this many. The full breakdown is on the lane below.',
  'number', to_jsonb(3), 1, 10, 'reasons', 1809, 'F-OPS.03A: exact reasons', 'Data delivery', 'security.data_delivery_v1')
on conflict (toolset_key, key) do nothing;

-- 2. tables ----------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.data_delivery_streams (
  stream text primary key check (stream ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  sort integer not null,
  lane text not null references pipeline.lane_funnel_lanes(lane),
  unit text not null,
  what text,
  coverage_sql text,
  net_sql text,
  consumer_sql text,
  net_basis text,
  speed_basis text,
  primary_jobs text[] not null default '{}',
  queue_parts text[] not null default '{}',
  hold_parts text[] not null default '{}',
  not_measured jsonb not null default '{}'::jsonb,
  drill jsonb not null default '{}'::jsonb,
  added_in text);
comment on table pipeline.data_delivery_streams is 'CF-247 F-OPS.03A (Platform Admin 9 Nov 2026): one row per data stream shown in the Data Delivery summary at the top of Layer 2/3 > Operations. Holds the lane it belongs to (pipeline.lane_funnel_lanes), the primary jobs whose last and next run are shown, one read-only SELECT per measure (coverage: cc, n, total; net: cc, added, removed, processed, last_added_at, since with {window}; consumer: cc, expected and the Website and Zoho matched / pending / missing / not served counts), the lane stages that make up the queue and the holds (a part is a stage key, or stage:reason), what is not measured and why, and the drill-down targets. A null SELECT means the measure is not built: the screen says Not measured with the reason. Edited only by a migration. Read only by security.data_delivery_refresh_v1 and security.data_delivery_v1. Never read by the consumer API.';
alter table pipeline.data_delivery_streams enable row level security;
revoke all on pipeline.data_delivery_streams from public, anon, authenticated;

create table if not exists pipeline.data_delivery_readings (
  stream text not null references pipeline.data_delivery_streams(stream),
  measure text not null check (measure in ('coverage', 'net_short', 'net_long', 'consumer')),
  measured_at timestamptz not null default now(),
  rows jsonb,
  took_ms integer,
  error text,
  primary key (stream, measure));
comment on table pipeline.data_delivery_readings is 'CF-247 F-OPS.03A (Platform Admin 9 Nov 2026): the latest counted result of each measure of pipeline.data_delivery_streams (rows as counted per country), when it was counted, how long it took and its error. rows is null when the measure could not be counted (shown as Unknown, never 0). Written only by job data-delivery (security.data_delivery_refresh_v1). Never read by the consumer API.';
alter table pipeline.data_delivery_readings enable row level security;
revoke all on pipeline.data_delivery_readings from public, anon, authenticated;

-- 3. the refresh (job data-delivery): the only writer ---------------------------------------------------------------------------------------------------
create or replace function security.data_delivery_refresh_v1(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  m record; v_rows jsonb; v_t0 timestamptz; v_start timestamptz := clock_timestamp();
  v_every int := security.pipeline_num_v1('data_delivery.refresh_minutes', 10)::int;
  v_batch int := security.pipeline_num_v1('data_delivery.measures_per_run', 8)::int;
  v_budget int := security.pipeline_num_v1('data_delivery.run_budget_seconds', 30)::int;
  v_short int := security.pipeline_num_v1('data_delivery.net_short_hours', 24)::int;
  v_long int := security.pipeline_num_v1('data_delivery.net_long_hours', 168)::int;
  v_done int := 0; v_failed int := 0;
begin
  if security.pipeline_num_v1('data_delivery.on', 1) < 1 and not p_force then return jsonb_build_object('skipped', 'switched off (data_delivery.on)'); end if;
  if not pg_try_advisory_xact_lock(hashtext('data_delivery_refresh')) then return jsonb_build_object('skipped', 'another count is running'); end if;
  for m in
    select d.stream, d.measure, d.sql, d.hours from (
      select s.stream, k.measure,
             case k.measure when 'coverage' then s.coverage_sql when 'net_short' then s.net_sql when 'net_long' then s.net_sql else s.consumer_sql end as sql,
             case k.measure when 'net_long' then v_long else v_short end as hours, s.sort
        from pipeline.data_delivery_streams s cross join (values ('coverage'), ('net_short'), ('net_long'), ('consumer')) k(measure)) d
      left join pipeline.data_delivery_readings r on r.stream = d.stream and r.measure = d.measure
     where d.sql is not null and (p_force or r.measured_at is null or r.error is not null and r.measured_at < now() - make_interval(mins => 1)  -- fixed: a failed count is retried after a minute
                                  or r.measured_at < now() - make_interval(mins => v_every))
     order by r.measured_at nulls first, d.sort, d.measure
     limit v_batch
  loop
    v_t0 := clock_timestamp();
    begin
      v_rows := security.lane_funnel_eval_v1(m.sql, m.hours);
      insert into pipeline.data_delivery_readings as r(stream, measure, measured_at, rows, took_ms, error)
        values (m.stream, m.measure, clock_timestamp(), v_rows, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int, null)
        on conflict (stream, measure) do update set measured_at = excluded.measured_at, rows = excluded.rows, took_ms = excluded.took_ms, error = null;
      v_done := v_done + 1;
    exception when others then
      insert into pipeline.data_delivery_readings as r(stream, measure, measured_at, rows, took_ms, error)
        values (m.stream, m.measure, clock_timestamp(), null, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int, left(sqlerrm, 300))
        on conflict (stream, measure) do update set measured_at = excluded.measured_at, rows = null, took_ms = excluded.took_ms, error = excluded.error;
      v_failed := v_failed + 1;
    end;
    exit when clock_timestamp() - v_start > make_interval(secs => v_budget);  -- the run stops starting new counts once its budget is spent; the rest stay due for the next run
  end loop;
  return jsonb_build_object('counted', v_done, 'failed', v_failed);
end $function$;
revoke all on function security.data_delivery_refresh_v1(boolean) from public, anon, authenticated;

-- 4. helpers for the read (no table is written; they only shape cached figures) --------------------------------------------------------------------------
create or replace function security.data_delivery_meta_v1(p_reading jsonb, p_stale int)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('measured_at', p_reading->>'measured_at', 'took_ms', p_reading->'took_ms',
    'age_minutes', round(extract(epoch from now() - (p_reading->>'measured_at')::timestamptz) / 60),
    'stale', (p_reading->>'measured_at')::timestamptz < now() - make_interval(mins => p_stale))
$$;
revoke all on function security.data_delivery_meta_v1(jsonb, int) from public, anon, authenticated;

create or replace function security.data_delivery_net_v1(p_reading jsonb, p_hours int, p_stale int)
returns jsonb language sql stable set search_path = '' as $$
  select case
    when p_reading is null then jsonb_build_object('known', false, 'window_hours', p_hours, 'reason', 'Not counted yet (the first count runs within minutes of release)')
    when p_reading->>'error' is not null then jsonb_build_object('known', false, 'window_hours', p_hours, 'reason', 'Could not be counted: ' || (p_reading->>'error')) || security.data_delivery_meta_v1(p_reading, p_stale)
    else (select jsonb_build_object('known', true, 'window_hours', p_hours, 'added', coalesce(sum(x.added), 0),
              'removed', case when bool_and(x.removed is not null) then sum(x.removed) end,
              'removed_known', coalesce(bool_and(x.removed is not null), false),
              'net', case when bool_and(x.removed is not null) then coalesce(sum(x.added), 0) - sum(x.removed) end,
              'processed', case when bool_and(x.processed is not null) then sum(x.processed) end,
              'last_added_at', max(x.last_added_at), 'since', min(x.since),
              'partial', min(x.since) is null or min(x.since) > now() - make_interval(hours => p_hours))
            || security.data_delivery_meta_v1(p_reading, p_stale)
          from jsonb_to_recordset(p_reading->'rows') as x(cc text, added bigint, removed bigint, processed bigint, last_added_at timestamptz, since timestamptz)) end
$$;
revoke all on function security.data_delivery_net_v1(jsonb, int, int) from public, anon, authenticated;

create or replace function security.data_delivery_consumer_v1(p_reading jsonb, p_side text, p_stale int, p_reason text)
returns jsonb language sql stable set search_path = '' as $$
  select case
    when p_reading is null then jsonb_build_object('known', false, 'reason', coalesce(p_reason, 'Not measured for this stream'))
    when p_reading->>'error' is not null then jsonb_build_object('known', false, 'reason', 'Could not be counted: ' || (p_reading->>'error')) || security.data_delivery_meta_v1(p_reading, p_stale)
    else (select case when coalesce(bool_and(case p_side when 'w' then x.w_matched else x.z_matched end is not null), false)
            then jsonb_build_object('known', true, 'expected', sum(x.expected),
                   'matched', sum(case p_side when 'w' then x.w_matched else x.z_matched end), 'pending', sum(case p_side when 'w' then x.w_pending else x.z_pending end),
                   'missing', sum(case p_side when 'w' then x.w_missing else x.z_missing end), 'not_applicable', sum(case p_side when 'w' then x.w_not_served else x.z_not_served end))
                 || security.data_delivery_meta_v1(p_reading, p_stale)
            else jsonb_build_object('known', false, 'reason', coalesce(p_reason, 'Not measured for this stream')) end
          from jsonb_to_recordset(p_reading->'rows') as x(cc text, expected bigint, w_matched bigint, w_pending bigint, w_missing bigint, w_not_served bigint,
                                                           z_matched bigint, z_pending bigint, z_missing bigint, z_not_served bigint)) end
$$;
revoke all on function security.data_delivery_consumer_v1(jsonb, text, int, text) from public, anon, authenticated;

-- queue and holds: the lane stages named by the stream (a part is a stage key, or stage:reason), read from the progress contract or the lane funnel readings
create or replace function security.data_delivery_parts_v1(p_lane text, p_parts text[], p_stale int, p_top int)
returns jsonb language sql stable set search_path = '' as $$
  with u as (
    select x.ord, split_part(x.spec, ':', 1) as sk, nullif(split_part(x.spec, ':', 2), '') as rsn from unnest(p_parts) with ordinality x(spec, ord)),
  p as (
    select u.ord, u.rsn, st.key, st.title, st.kind, r.reasons, r.oldest_at, coalesce(t.measured_at, r.measured_at) as at, coalesce(t.measure_error, r.error) as err,
           case when st.transition_key is not null then case when t.measure_error is null then t.input_eligible end else r.n end as stage_n
      from u join pipeline.lane_funnel_stages st on st.lane = p_lane and st.key = u.sk
      left join pipeline.progress_transitions t on t.key = st.transition_key
      left join pipeline.lane_funnel_readings r on r.lane = st.lane and r.stage_key = st.key),
  q as (
    select p.*, case when p.rsn is null then p.stage_n when p.stage_n is null and p.reasons is null then null
                     else coalesce((select sum((e->>'n')::numeric) from jsonb_array_elements(coalesce(p.reasons, '[]'::jsonb)) e where e->>'reason' = p.rsn), 0) end as n
      from p),
  rs as (
    select e->>'reason' as reason, (e->>'n')::numeric as n, q.title as stage, e->>'oldest' as oldest_at
      from q cross join lateral jsonb_array_elements(q.reasons) e where q.rsn is null and q.kind in ('held', 'blocked') and q.reasons is not null and (e->>'n')::numeric > 0
    union all
    select coalesce(q.rsn, q.title), q.n, q.title, q.oldest_at::text from q
     where q.n > 0 and (q.rsn is not null or q.reasons is null or q.kind not in ('held', 'blocked')))
  select jsonb_build_object('known', coalesce(bool_or(q.n is not null), false), 'n', sum(q.n), 'partial', coalesce(bool_or(q.n is null), false),
      'parts', coalesce(jsonb_agg(jsonb_build_object('stage', q.key, 'title', case when q.rsn is null then q.title else q.title || ': ' || q.rsn end, 'kind', q.kind, 'n', q.n,
               'oldest_at', q.oldest_at, 'measured_at', q.at, 'stale', coalesce(q.at < now() - make_interval(mins => p_stale), false), 'error', q.err) order by q.ord), '[]'::jsonb),
      'reasons', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.reason, 'n', z.n, 'stage', z.stage, 'oldest_at', z.oldest_at) order by z.n desc, z.reason), '[]'::jsonb)
                    from (select * from rs order by n desc, reason limit greatest(coalesce(p_top, 0), 0)) z))
    from q
$$;
revoke all on function security.data_delivery_parts_v1(text, text[], int, int) from public, anon, authenticated;

-- 5. the read: ONE set-based, read-only function (no per-row calls into other readers; one scheduler-history scan for all primary jobs) -------------------
create or replace function security.data_delivery_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
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
  v_hint text; v_oldest timestamptz; v_newest timestamptz; v_errors int; v_rd jsonb; v_job jsonb;
begin
  -- one scan of the scheduler history for every primary job of every stream, and for the refresh job itself (one pass, grouped by job: measured 83 ms live against 516 ms for a per-job lookup)
  with want as (
    select c.jobid, c.jobname, c.active, c.schedule from cron.job c
     where c.jobname = 'data-delivery' or c.jobname in (select unnest(x.primary_jobs) from pipeline.data_delivery_streams x)),
  h as (
    select d.jobid, max(d.start_time) as last_start, (array_agg(d.end_time order by d.start_time desc))[1] as last_end, (array_agg(d.status order by d.start_time desc))[1] as last_status,
           (array_agg(left(d.return_message, 240) order by d.start_time desc))[1] as last_message, max(d.start_time) filter (where d.status = 'succeeded') as last_success,
           count(*) filter (where d.start_time > now() - make_interval(hours => v_short)) as runs,
           count(*) filter (where d.start_time > now() - make_interval(hours => v_short) and d.status = 'failed') as failed,
           count(*) filter (where d.start_time > now() - make_interval(hours => v_short) and d.status = 'succeeded') as succeeded,
           bool_or(d.status in ('running', 'starting')) as running
      from cron.job_run_details d where d.jobid in (select jobid from want) and d.start_time > now() - make_interval(hours => greatest(v_hist, v_short)) group by d.jobid)
  select coalesce(jsonb_object_agg(w.jobname, jsonb_build_object('active', w.active, 'schedule', w.schedule, 'next_run', case when w.active then security.cron_next_run_v1(w.schedule, now()) end,
      'last_start', h.last_start, 'last_end', h.last_end, 'last_status', h.last_status, 'last_message', h.last_message, 'last_success', h.last_success,
      'runs', coalesce(h.runs, 0), 'failed', coalesce(h.failed, 0), 'succeeded', coalesce(h.succeeded, 0), 'running', coalesce(h.running, false))), '{}'::jsonb)
    into v_runs from want w left join h on h.jobid = w.jobid;

  for s in select d.*, l.switch_keys, l.issue_refs, l.title as lane_title from pipeline.data_delivery_streams d join pipeline.lane_funnel_lanes l on l.lane = d.lane order by d.sort, d.stream loop
    select coalesce(jsonb_object_agg(r.measure, jsonb_build_object('rows', r.rows, 'measured_at', r.measured_at, 'took_ms', r.took_ms, 'error', r.error)), '{}'::jsonb)
      into v_r from pipeline.data_delivery_readings r where r.stream = s.stream;
    -- coverage: n of N, and the country split
    v_cov := case
      when v_r->'coverage' is null then jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'coverage', 'Not counted yet (the first count runs within minutes of release)'))
      when v_r->'coverage'->>'error' is not null then jsonb_build_object('known', false, 'reason', 'Could not be counted: ' || (v_r->'coverage'->>'error')) || security.data_delivery_meta_v1(v_r->'coverage', v_stale)
      else (select jsonb_build_object('known', true, 'n', coalesce(sum(x.n), 0), 'total', case when coalesce(bool_and(x.total is not null), false) then sum(x.total) end,
                'total_reason', case when not coalesce(bool_and(x.total is not null), false) then coalesce(s.not_measured->>'coverage_total', 'The total is not measured') end,
                'pct', case when coalesce(bool_and(x.total is not null), false) and sum(x.total) > 0 then round(100.0 * sum(x.n) / sum(x.total), 1) end,
                'by_country', coalesce(jsonb_agg(jsonb_build_object('cc', x.cc, 'n', x.n, 'total', x.total) order by x.cc), '[]'::jsonb))
              || security.data_delivery_meta_v1(v_r->'coverage', v_stale)
              from jsonb_to_recordset(v_r->'coverage'->'rows') as x(cc text, n bigint, total bigint)) end;
    v_ns := security.data_delivery_net_v1(v_r->'net_short', v_short, v_stale);
    v_nl := security.data_delivery_net_v1(v_r->'net_long', v_long, v_stale);
    if (v_ns->>'known')::boolean and not (v_ns->>'removed_known')::boolean then v_ns := v_ns || jsonb_build_object('removed_reason', coalesce(s.not_measured->>'net_removed', 'Removals are not recorded for this stream')); end if;
    if (v_nl->>'known')::boolean and not (v_nl->>'removed_known')::boolean then v_nl := v_nl || jsonb_build_object('removed_reason', coalesce(s.not_measured->>'net_removed', 'Removals are not recorded for this stream')); end if;
    v_w := security.data_delivery_consumer_v1(v_r->'consumer', 'w', v_stale, s.not_measured->>'website');
    v_z := security.data_delivery_consumer_v1(v_r->'consumer', 'z', v_stale, s.not_measured->>'zoho');
    v_q := case when cardinality(s.queue_parts) = 0 then jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'queue', 'No queue is recorded for this stream'))
                else security.data_delivery_parts_v1(s.lane, s.queue_parts, v_stale, 0) end;
    v_h := case when cardinality(s.hold_parts) = 0 then jsonb_build_object('known', false, 'reason', coalesce(s.not_measured->>'holds', 'No holds are recorded for this stream'))
                else security.data_delivery_parts_v1(s.lane, s.hold_parts, v_stale, v_top) end;
    if cardinality(s.hold_parts) > 0 and s.not_measured ? 'holds_by_cause' then v_h := v_h || jsonb_build_object('causes_reason', s.not_measured->>'holds_by_cause'); end if;
    -- speed: items per hour over the stated window (the ledger span when the ledger is younger than the window)
    if not (v_ns->>'known')::boolean then
      v_speed := jsonb_build_object('known', false, 'reason', v_ns->>'reason');
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
             'history_hours', v_hist, 'known', count(*) filter (where x->>'last_start' is not null) > 0,
             'reason', case when count(*) = 0 then 'No primary job is named for this stream'
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
    v_rec := jsonb_build_object(
      'state', case when v_off or (v_total > 0 and v_active = 0) then 'off' when v_last_status = 'failed' then 'failing' when v_open > 0 and v_remedy_ok > 0 then 'recovering'
                    when v_open > 0 then 'needs_attention' when v_total = 0 then 'unknown' else 'healthy' end,
      'text', case when v_off then 'A switch for this stream is off, so nothing retries until it is switched on'
                   when v_total > 0 and v_active = 0 then 'No primary job is active, so nothing retries'
                   when v_last_status = 'failed' then 'The last run failed; the job retries at its next scheduled run' || coalesce(' (' || to_char((v_job_sum->>'next_run_at')::timestamptz at time zone 'Australia/Melbourne', 'DD Mon HH24:MI') || ' Melbourne)', '')
                   when v_open > 0 and v_remedy_ok > 0 then v_open || ' open issue(s); automatic remedies acted ' || v_remedy_ok || ' time(s) in the window'
                   when v_open > 0 then v_open || ' open issue(s) and no automatic remedy has acted in the window'
                   when v_total = 0 then 'No primary job is named, so recovery is not measured'
                   else 'No open issues; the scheduled job retries on its next run' end,
      'open_issues', v_open, 'issue_refs', v_issue_refs, 'remedy_acted', v_remedy_ok, 'remedy_refused', v_remedy_bad, 'last_remedy_at', v_remedy_last,
      'window_hours', v_short);
    -- a green job that admitted nothing (or whose admissions cannot be counted) is flagged
    v_ok := coalesce((v_job_sum->>'succeeded')::int, 0); v_bad := coalesce((v_job_sum->>'failed')::int, 0);
    v_hint := coalesce(v_h->'reasons'->0->>'reason', case when (v_q->>'known')::boolean and coalesce((v_q->>'n')::numeric, 0) = 0 then 'nothing is waiting' end);
    v_flags := '[]'::jsonb;
    if v_ok > 0 and (v_ns->>'known')::boolean and coalesce((v_ns->>'added')::numeric, 0) = 0 then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'green_no_admission', 'severity', 'warn',
        'text', 'Ran OK ' || v_ok || ' time(s) in ' || v_short || ' h, admitted nothing' || coalesce(' (' || v_hint || ')', '')));
    elsif v_ok > 0 and not (v_ns->>'known')::boolean then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'green_admission_unknown', 'severity', 'warn',
        'text', 'Ran OK ' || v_ok || ' time(s) in ' || v_short || ' h; what it admitted is unknown (' || coalesce(v_ns->>'reason', 'not counted') || ')'));
    end if;
    if v_bad > 0 then v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'job_failing', 'severity', 'bad', 'text', v_bad || ' failed run(s) in ' || v_short || ' h')); end if;
    if (v_cov->>'known')::boolean is not true or (v_ns->>'known')::boolean is not true then
      v_flags := v_flags || jsonb_build_array(jsonb_build_object('code', 'measure_unknown', 'severity', 'info', 'text', 'A headline measure could not be counted; see the reason in the cell'));
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'stream', s.stream, 'title', s.title, 'unit', s.unit, 'what', s.what, 'lane', s.lane, 'net_basis', s.net_basis, 'drill', s.drill,
      'coverage', v_cov, 'net_short', v_ns, 'net_long', v_nl, 'website', v_w, 'zoho', v_z, 'queue', v_q, 'holds', v_h, 'speed', v_speed,
      'jobs', v_job_sum || jsonb_build_object('list', v_jobs), 'recovery', v_rec, 'flags', v_flags,
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
end $function$;
revoke all on function security.data_delivery_v1() from public, anon, authenticated;

-- 6. the Operations action: one exact, md5-guarded text edit of public.admin_layer23 (a second run finds it applied and changes nothing) -----------------
create or replace function pg_temp.edit_one(p_sig text, p_before text, p_after text, p_old text, p_new text) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_one('public.admin_layer23(text,jsonb)', 'b1d08c144078fce71ba2cd3762a00b0f', '4c99a80f6899cda0d836dcc4196534de',
$old$  if p_action = 'universities_page' then$old$,
$new$  if p_action = 'data_delivery' then
    -- CF-247 F-OPS.03A (Platform Admin 9 Nov 2026): the Data Delivery summary at the top of Layer 2/3 > Operations. One read, same rank as the screen (3 and above, checked above).
    return security.data_delivery_v1();
  end if;
  if p_action = 'universities_page' then$new$);

-- 7. pdesc lane stages: the Provider description queue and holds, counted from the reader's own ledger ------------------------------------------------------------
insert into pipeline.lane_funnel_stages(lane, step, key, title, kind, what, transition_key, count_sql, drill) values
 ('pdesc', 15, 'queued', 'Waiting for the reader', 'queued', 'Providers whose latest description read is queued and not yet taken (gain: queued or re-queued in the window).', null,
  $q$select count(*) as n, min(updated_at) as oldest, count(*) filter (where updated_at > now() - {window}) as gain from pipeline.provider_description_reads where state = 'queued'$q$, 'layer2/operations'),
 ('pdesc', 17, 'held', 'Held, by cause', 'held', 'Providers whose latest description read is held, by normalised cause (digits become N and the wording after a colon or semicolon is dropped; the exact text is on the provider).', null,
  $q$select left(regexp_replace(split_part(split_part(coalesce(nullif(btrim(reason), ''), 'no reason recorded'), ':', 1), chr(59), 1), '[0-9]+', 'N', 'g'), 120) as reason, count(*) as n, min(updated_at) as oldest, count(*) filter (where updated_at > now() - {window}) as gain from pipeline.provider_description_reads where state = 'held' group by 1 order by 2 desc limit 40$q$, 'layer2/operations')
on conflict (lane, key) do nothing;

-- 8. the streams (read from the live schema, 9 Nov 2026) -----------------------------------------------------------------------------------------------------
insert into pipeline.data_delivery_streams(stream, title, sort, lane, unit, what, coverage_sql, net_sql, consumer_sql, net_basis, speed_basis, primary_jobs, queue_parts, hold_parts, not_measured, drill, added_in) values
('pdesc', 'Provider descriptions', 10, 'pdesc', 'providers', 'Official About pages to provider descriptions, checked, reviewed and published to the Website and Zoho.', $q$select co.iso_alpha2::text as cc, count(*) filter (where nullif(btrim(p.description), '') is not null) as n, count(*) as total from catalogue.providers p join ref.countries co on co.id = p.country_id where p.lifecycle_status = 'active' group by 1$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), e as (select m.provider_id, 1 as a, 0 as r from pipeline.provider_description_machine_admissions m where m.outcome = 'admitted' and m.created_at > now() - {window} union all select m.provider_id, 0, 1 from pipeline.provider_description_machine_admissions m where m.outcome = 'admitted' and m.withdrawn_at > now() - {window} union all select ri.entity_id, 1, 0 from pipeline.layer4_review_items ri where ri.field_code = 'provider_description' and ri.status in ('approved', 'edited_approved') and ri.decided_at > now() - {window} and not exists (select 1 from pipeline.provider_description_machine_admissions m where m.review_item_id = ri.id)), g as (select co.iso_alpha2::text as cc, sum(e.a) as added, sum(e.r) as removed from e join catalogue.providers p on p.id = e.provider_id join ref.countries co on co.id = p.country_id group by 1), pr as (select co.iso_alpha2::text as cc, count(*) as processed from pipeline.provider_description_reads r join catalogue.providers p on p.id = r.provider_id join ref.countries co on co.id = p.country_id where r.updated_at > now() - {window} and r.state in ('admitted', 'proposed', 'held', 'rejected', 'verified', 'dead_letter') group by 1) select cty.cc, coalesce(g.added, 0) as added, coalesce(g.removed, 0) as removed, coalesce(pr.processed, 0) as processed, (select max(created_at) from pipeline.provider_description_machine_admissions where outcome = 'admitted') as last_added_at, (select min(created_at) from pipeline.provider_description_machine_admissions) as since from cty left join g on g.cc = cty.cc left join pr on pr.cc = cty.cc$q$, $q$with pv as (select p.id, p.stable_key, co.iso_alpha2::text as cc, nullif(btrim(p.description), '') as d from catalogue.providers p join ref.countries co on co.id = p.country_id where p.lifecycle_status = 'active'), wf as (select i.item_key, nullif(btrim(i.item->>'description'), '') as d from pipeline.website_sync_items i where i.entity = 'provider' and i.removed_at is null), zf as (select i.item_key, nullif(btrim(i.item->>'description'), '') as d from pipeline.zoho_sync_items i where i.entity = 'provider' and i.removed_at is null), wc as (select x.ref_id from security.website_sync_candidates_v1('provider') x where x.ref_id is not null), zc as (select x.ref_id from security.zoho_sync_candidates_v1('provider') x where x.ref_id is not null) select pv.cc, count(*) as expected, count(*) filter (where wf.item_key is not null and wf.d = pv.d) as w_matched, count(*) filter (where wf.item_key is not null and wf.d is distinct from pv.d) as w_pending, count(*) filter (where wf.item_key is null and wc.ref_id is not null) as w_missing, count(*) filter (where wf.item_key is null and wc.ref_id is null) as w_not_served, count(*) filter (where zf.item_key is not null and zf.d = pv.d) as z_matched, count(*) filter (where zf.item_key is not null and zf.d is distinct from pv.d) as z_pending, count(*) filter (where zf.item_key is null and zc.ref_id is not null) as z_missing, count(*) filter (where zf.item_key is null and zc.ref_id is null) as z_not_served from pv left join wf on wf.item_key = pv.stable_key left join zf on zf.item_key = pv.stable_key left join wc on wc.ref_id = pv.id left join zc on zc.ref_id = pv.id where pv.d is not null group by 1$q$, 'Machine admissions (created, withdrawn) and Layer 4 approvals not made by the machine route, by their timestamps', 'reads that reached a verdict (admitted, proposed, held, rejected, verified, dead letter)', array['provider-description-read']::text[], array['queued']::text[], array['held', 'human']::text[], '{}'::jsonb, '{"screen": "providers", "filled": {"description": "filled"}, "missing": {"description": "missing"}, "website": {"key": "website"}, "zoho": {"key": "zoho"}, "needs_provider_filters": true, "note": null}'::jsonb, '20261109210000'),
 ('int', 'Intake dates and deadlines', 20, 'int', 'intake rows', 'Course page and calendar evidence to exact start dates, then the Website and Zoho.', $q$select co.iso_alpha2::text as cc, count(*) filter (where i.start_date is not null) as n, count(*) as total from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where i.status = 'active' and c.lifecycle_status = 'active' group by 1$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), g as (select co.iso_alpha2::text as cc, count(*) filter (where e.outcome = 'filled') as added, count(*) filter (where e.outcome = 'withdrawn') as removed, count(*) as processed from pipeline.course_intake_date_events e join catalogue.providers p on p.id = e.provider_id join ref.countries co on co.id = p.country_id where e.run_at > now() - {window} group by 1) select cty.cc, coalesce(g.added, 0) as added, coalesce(g.removed, 0) as removed, coalesce(g.processed, 0) as processed, (select max(run_at) from pipeline.course_intake_date_events where outcome = 'filled') as last_added_at, (select min(run_at) from pipeline.course_intake_date_events) as since from cty left join g on g.cc = cty.cc$q$, $q$with ct as (select c.id, c.stable_key, co.iso_alpha2::text as cc from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' and exists (select 1 from catalogue.course_intakes f where f.course_id = c.id and f.status = 'active' and f.start_date is not null)), wf as (select i.item_key, coalesce((case when jsonb_typeof(i.item->'intakes') = 'array' then exists (select 1 from jsonb_array_elements(i.item->'intakes') y where y->>'start_date' is not null) else false end), false) as car from pipeline.website_sync_items i where i.entity = 'course' and i.removed_at is null), wc as (select x.ref_id from security.website_sync_candidates_v1('course') x where x.ref_id is not null), zf as (select i.item_key, coalesce((case when jsonb_typeof(i.item->'intakes') = 'array' then exists (select 1 from jsonb_array_elements(i.item->'intakes') y where y->>'start_date' is not null) else false end), false) as car from pipeline.zoho_sync_items i where i.entity = 'course' and i.removed_at is null), zc as (select x.ref_id from security.zoho_sync_candidates_v1('course') x where x.ref_id is not null) select ct.cc, count(*) as expected, count(*) filter (where wf.item_key is not null and wf.car) as w_matched, count(*) filter (where wf.item_key is not null and not wf.car) as w_pending, count(*) filter (where wf.item_key is null and wc.ref_id is not null) as w_missing, count(*) filter (where wf.item_key is null and wc.ref_id is null) as w_not_served, count(*) filter (where zf.item_key is not null and zf.car) as z_matched, count(*) filter (where zf.item_key is not null and not zf.car) as z_pending, count(*) filter (where zf.item_key is null and zc.ref_id is not null) as z_missing, count(*) filter (where zf.item_key is null and zc.ref_id is null) as z_not_served from ct left join wf on wf.item_key = ct.stable_key left join wc on wc.ref_id = ct.id left join zf on zf.item_key = ct.stable_key left join zc on zc.ref_id = ct.id group by 1$q$, 'Intake date events (filled, withdrawn) by run time', 'intake decisions in the window (filled, withdrawn and held)', array['intake-dates-apply']::text[], array['selected']::text[], array['held']::text[], '{}'::jsonb, '{"screen": "courses", "filled": {"hasIntake": "true"}, "missing": {"hasIntake": "false"}, "website": null, "zoho": null, "note": "The Course Catalogue filters on whether a course has an intake. It has no Website or Zoho state filter, so the pending and missing counts are shown but their courses are not listed (follow-up gap)."}'::jsonb, '20261109210000'),
 ('cdesc', 'Course descriptions', 30, 'cdesc', 'courses', 'Source-backed course description proposals, human review in Layer 4, admission and publication.', $q$select co.iso_alpha2::text as cc, count(*) filter (where nullif(btrim(c.description), '') is not null) as n, count(*) as total from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' group by 1$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), g as (select co.iso_alpha2::text as cc, count(*) as added from pipeline.layer4_review_items ri join catalogue.courses c on c.id = ri.entity_id join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where ri.field_code = 'course_description_first_read' and ri.status in ('approved', 'edited_approved') and ri.decided_at > now() - {window} group by 1) select cty.cc, coalesce(g.added, 0) as added, null::bigint as removed, (select count(*) from pipeline.field_enrich_items fe join catalogue.providers p2 on p2.id = fe.provider_id join ref.countries c2 on c2.id = p2.country_id where fe.field = 'description' and fe.updated_at > now() - {window} and c2.iso_alpha2::text = cty.cc) as processed, (select max(decided_at) from pipeline.layer4_review_items where field_code = 'course_description_first_read' and status in ('approved', 'edited_approved')) as last_added_at, (select min(decided_at) from pipeline.layer4_review_items where field_code = 'course_description_first_read' and decided_at is not null) as since from cty left join g on g.cc = cty.cc$q$, null, 'Layer 4 approvals of the first reading, by decision time', 'description reader items updated in the window', array['enrich-plan-run']::text[], '{}'::text[], array['held_first_admission', 'held_by_check', 'held_rejected', 'human']::text[], '{"net_removed": "A course description that is edited or cleared leaves no ledger event, so removals are not counted.", "queue": "The description reader keeps no waiting state (field_enrich_items has no queued state), so its queue is not counted.", "website": "Whether the course description reaches the Website and Zoho course feed items is not compared yet (no feed field check is built for it). Follow-up gap.", "zoho": "Whether the course description reaches the Website and Zoho course feed items is not compared yet (no feed field check is built for it). Follow-up gap."}'::jsonb, '{"screen": "courses", "filled": null, "missing": null, "website": null, "zoho": null, "note": "The Course Catalogue has no description filter yet, so the filled and missing courses cannot be listed (follow-up gap)."}'::jsonb, '20261109210000'),
 ('fee', 'Tuition and other fees', 40, 'fee', 'courses', 'Fee schedules and course pages read into fee rows, checked and admitted as active course fees.', $q$select co.iso_alpha2::text as cc, count(*) filter (where exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.status = 'active')) as n, count(*) as total from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' group by 1$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), g as (select co.iso_alpha2::text as cc, count(*) filter (where f.created_at > now() - {window}) as added, count(*) filter (where f.status <> 'active' and f.updated_at > now() - {window}) as removed from catalogue.course_fees f join catalogue.courses c on c.id = f.course_id join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where f.created_at > now() - {window} or f.updated_at > now() - {window} group by 1) select cty.cc, coalesce(g.added, 0) as added, coalesce(g.removed, 0) as removed, (select count(*) from pipeline.fee_reader_rows r join catalogue.providers p2 on p2.id = r.provider_id join ref.countries c2 on c2.id = p2.country_id where r.created_at > now() - {window} and c2.iso_alpha2::text = cty.cc) as processed, (select max(created_at) from catalogue.course_fees) as last_added_at, (select min(created_at) from catalogue.course_fees) as since from cty left join g on g.cc = cty.cc$q$, $q$with ct as (select c.id, c.stable_key, co.iso_alpha2::text as cc from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' and exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.status = 'active')), wf as (select i.item_key, coalesce((coalesce(i.item->'tuition', 'null'::jsonb) <> 'null'::jsonb), false) as car from pipeline.website_sync_items i where i.entity = 'course' and i.removed_at is null), wc as (select x.ref_id from security.website_sync_candidates_v1('course') x where x.ref_id is not null), zf as (select i.item_key, coalesce((coalesce(i.item->'tuition', 'null'::jsonb) <> 'null'::jsonb), false) as car from pipeline.zoho_sync_items i where i.entity = 'course' and i.removed_at is null), zc as (select x.ref_id from security.zoho_sync_candidates_v1('course') x where x.ref_id is not null) select ct.cc, count(*) as expected, count(*) filter (where wf.item_key is not null and wf.car) as w_matched, count(*) filter (where wf.item_key is not null and not wf.car) as w_pending, count(*) filter (where wf.item_key is null and wc.ref_id is not null) as w_missing, count(*) filter (where wf.item_key is null and wc.ref_id is null) as w_not_served, count(*) filter (where zf.item_key is not null and zf.car) as z_matched, count(*) filter (where zf.item_key is not null and not zf.car) as z_pending, count(*) filter (where zf.item_key is null and zc.ref_id is not null) as z_missing, count(*) filter (where zf.item_key is null and zc.ref_id is null) as z_not_served from ct left join wf on wf.item_key = ct.stable_key left join wc on wc.ref_id = ct.id left join zf on zf.item_key = ct.stable_key left join zc on zc.ref_id = ct.id group by 1$q$, 'Fee rows created, less fee rows that are no longer active and whose record changed in the window (there is no withdrawal time, so a withdrawn row edited later can be counted again; the removed figure is an upper bound)', 'fee rows the reader read in the window', array['fee-reader']::text[], array['queued']::text[], array['held', 'human']::text[], '{}'::jsonb, '{"screen": "courses", "filled": {"hasFee": "true"}, "missing": {"hasFee": "false"}, "website": null, "zoho": null, "note": "The Course Catalogue has no Website or Zoho state filter, so pending and missing courses are counted but not listed (follow-up gap)."}'::jsonb, '20261109210000'),
 ('eng', 'English entry requirements', 50, 'eng', 'courses', 'University English policies and course pages to course English rows.', $q$select co.iso_alpha2::text as cc, count(*) filter (where exists (select 1 from catalogue.course_english_requirements f where f.course_id = c.id and f.status = 'active')) as n, count(*) as total from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' group by 1$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), g as (select co.iso_alpha2::text as cc, count(*) as added from pipeline.layer4_review_items ri join catalogue.courses c on c.id = ri.entity_id join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where ri.field_code = 'course_english' and ri.status in ('approved', 'edited_approved') and ri.decided_at > now() - {window} group by 1) select cty.cc, coalesce(g.added, 0) as added, null::bigint as removed, null::bigint as processed, (select max(decided_at) from pipeline.layer4_review_items where field_code = 'course_english' and status in ('approved', 'edited_approved')) as last_added_at, (select min(decided_at) from pipeline.layer4_review_items where field_code = 'course_english' and decided_at is not null) as since from cty left join g on g.cc = cty.cc$q$, $q$with ct as (select c.id, c.stable_key, co.iso_alpha2::text as cc from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' and exists (select 1 from catalogue.course_english_requirements f where f.course_id = c.id and f.status = 'active')), wf as (select i.item_key, coalesce((case when jsonb_typeof(i.item->'english_requirements') = 'array' then jsonb_array_length(i.item->'english_requirements') > 0 else false end), false) as car from pipeline.website_sync_items i where i.entity = 'course' and i.removed_at is null), wc as (select x.ref_id from security.website_sync_candidates_v1('course') x where x.ref_id is not null), zf as (select i.item_key, coalesce((case when jsonb_typeof(i.item->'english_requirements') = 'array' then jsonb_array_length(i.item->'english_requirements') > 0 else false end), false) as car from pipeline.zoho_sync_items i where i.entity = 'course' and i.removed_at is null), zc as (select x.ref_id from security.zoho_sync_candidates_v1('course') x where x.ref_id is not null) select ct.cc, count(*) as expected, count(*) filter (where wf.item_key is not null and wf.car) as w_matched, count(*) filter (where wf.item_key is not null and not wf.car) as w_pending, count(*) filter (where wf.item_key is null and wc.ref_id is not null) as w_missing, count(*) filter (where wf.item_key is null and wc.ref_id is null) as w_not_served, count(*) filter (where zf.item_key is not null and zf.car) as z_matched, count(*) filter (where zf.item_key is not null and not zf.car) as z_pending, count(*) filter (where zf.item_key is null and zc.ref_id is not null) as z_missing, count(*) filter (where zf.item_key is null and zc.ref_id is null) as z_not_served from ct left join wf on wf.item_key = ct.stable_key left join wc on wc.ref_id = ct.id left join zf on zf.item_key = ct.stable_key left join zc on zc.ref_id = ct.id group by 1$q$, 'Layer 4 approvals of course English, by decision time', null, array['central-attach']::text[], '{}'::text[], array['human']::text[], '{"net_removed": "A withdrawn English row has no withdrawal time, so removals are not counted.", "speed": "English reads have no timestamped ledger, so items per hour cannot be counted.", "queue": "There is no English reader queue stage, so the queue is not counted.", "holds_by_cause": "English holds are not recorded by cause; only items waiting for a person are counted."}'::jsonb, '{"screen": "courses", "filled": {"hasEnglish": "true"}, "missing": {"hasEnglish": "false"}, "website": null, "zoho": null, "note": "The Course Catalogue has no Website or Zoho state filter, so pending and missing courses are counted but not listed (follow-up gap)."}'::jsonb, '20261109210000'),
 ('aer', 'Academic entry requirements (AER)', 60, 'aer', 'courses', 'Official sources to read rows, review, active entry rows and Website publication.', $q$with r as (select co.iso_alpha2::text as cc, count(*) as nrows from catalogue.course_entry_requirements e join catalogue.courses c on c.id = e.course_id join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where e.status = 'active' and c.lifecycle_status = 'active' group by 1), cv as (select co.iso_alpha2::text as cc, count(*) filter (where exists (select 1 from catalogue.course_entry_requirements f where f.course_id = c.id and f.status = 'active')) as n, count(*) as total from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' group by 1) select cv.cc, cv.n, cv.total, r.nrows as extra from cv left join r on r.cc = cv.cc$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), g as (select co.iso_alpha2::text as cc, count(*) filter (where e.status = 'active' and e.created_at > now() - {window}) as added, count(*) filter (where e.status = 'inactive' and e.updated_at > now() - {window}) as removed from catalogue.course_entry_requirements e join catalogue.courses c on c.id = e.course_id join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where e.created_at > now() - {window} or e.updated_at > now() - {window} group by 1) select cty.cc, coalesce(g.added, 0) as added, coalesce(g.removed, 0) as removed, null::bigint as processed, (select max(created_at) from catalogue.course_entry_requirements where status = 'active') as last_added_at, (select min(created_at) from catalogue.course_entry_requirements) as since from cty left join g on g.cc = cty.cc$q$, null, 'Active entry rows created, less inactive entry rows whose record changed in the window (there is no withdrawal time, so the removed figure is an upper bound)', null, array['aer-scheduled-read']::text[], array['extraction']::text[], array['technical', 'layer4']::text[], '{"speed": "Entry requirement reads have no processed-items ledger, so items per hour cannot be counted.", "website": "The Website comparison for entry requirements is not built yet. Follow-up gap.", "zoho": "The Zoho comparison for entry requirements is not built yet. Follow-up gap."}'::jsonb, '{"screen": "entry", "filled": null, "missing": null, "website": null, "zoho": null, "note": "Entry requirements are worked in Entry requirements; the Course Catalogue has no entry requirement filter."}'::jsonb, '20261109210000'),
 ('sch', 'Scholarships', 70, 'sch', 'scholarships', 'Coverage to found listings, read pages, review, admission and publication.', $q$select co.iso_alpha2::text as cc, count(*) as n, null::bigint as total from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id join ref.countries co on co.id = p.country_id where s.lifecycle_status = 'active' and s.publication_status = 'published' group by 1$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), g as (select co.iso_alpha2::text as cc, count(*) filter (where l.action = 'admitted') as added, count(*) filter (where l.action = 'withdrawn') as removed, count(*) as processed from pipeline.scholarship_admission_log l join catalogue.providers p on p.id = l.provider_id join ref.countries co on co.id = p.country_id where l.at > now() - {window} group by 1) select cty.cc, coalesce(g.added, 0) as added, coalesce(g.removed, 0) as removed, coalesce(g.processed, 0) as processed, (select max(at) from pipeline.scholarship_admission_log where action = 'admitted') as last_added_at, (select min(at) from pipeline.scholarship_admission_log) as since from cty left join g on g.cc = cty.cc$q$, $q$with ct as (select s.id, s.stable_key, co.iso_alpha2::text as cc from scholarship.scholarships s join catalogue.providers p on p.id = s.provider_id join ref.countries co on co.id = p.country_id where s.lifecycle_status = 'active' and s.publication_status = 'published'), wf as (select i.item_key from pipeline.website_sync_items i where i.entity = 'scholarship' and i.removed_at is null), wc as (select x.ref_id from security.website_sync_candidates_v1('scholarship') x where x.ref_id is not null) select ct.cc, count(*) as expected, count(*) filter (where wf.item_key is not null) as w_matched, 0::bigint as w_pending, count(*) filter (where wf.item_key is null and wc.ref_id is not null) as w_missing, count(*) filter (where wf.item_key is null and wc.ref_id is null) as w_not_served, null::bigint as z_matched, null::bigint as z_pending, null::bigint as z_missing, null::bigint as z_not_served from ct left join wf on wf.item_key = ct.stable_key left join wc on wc.ref_id = ct.id group by 1$q$, 'Scholarship admission log (admitted, withdrawn) by time', 'scholarship admission decisions in the window', array['scholarship-read', 'scholarship-auto-publish']::text[], array['reading']::text[], array['layer4']::text[], '{"coverage_total": "The number of scholarships that should be published is not defined, so there is no total or percentage.", "zoho": "The Zoho scholarship comparison is not built yet. Follow-up gap."}'::jsonb, '{"screen": "scholarships", "filled": {}, "missing": null, "website": null, "zoho": null, "note": "The Scholarship list shows the published scholarships."}'::jsonb, '20261109210000'),
 ('disc', 'Discovery and official course links', 80, 'disc', 'courses', 'Course link search and review to the official course address, then the Website and Zoho.', $q$select co.iso_alpha2::text as cc, count(*) filter (where exists (select 1 from catalogue.course_links f where f.course_id = c.id and f.status = 'active' and f.link_type = 'official_course')) as n, count(*) as total from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' group by 1$q$, $q$with cty as (select co.iso_alpha2::text as cc from ref.countries co where exists (select 1 from catalogue.providers p where p.country_id = co.id and p.lifecycle_status = 'active')), g as (select co.iso_alpha2::text as cc, count(*) filter (where l.status = 'active' and l.created_at > now() - {window}) as added, count(*) filter (where l.status in ('inactive', 'deprecated') and l.updated_at > now() - {window}) as removed from catalogue.course_links l join catalogue.courses c on c.id = l.course_id join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where l.link_type = 'official_course' and (l.created_at > now() - {window} or l.updated_at > now() - {window}) group by 1) select cty.cc, coalesce(g.added, 0) as added, coalesce(g.removed, 0) as removed, null::bigint as processed, (select max(created_at) from catalogue.course_links where link_type = 'official_course' and status = 'active') as last_added_at, (select min(created_at) from catalogue.course_links where link_type = 'official_course') as since from cty left join g on g.cc = cty.cc$q$, $q$with ct as (select c.id, c.stable_key, co.iso_alpha2::text as cc from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id where c.lifecycle_status = 'active' and exists (select 1 from catalogue.course_links f where f.course_id = c.id and f.status = 'active' and f.link_type = 'official_course')), wf as (select i.item_key, coalesce((coalesce(i.item->'official_url', 'null'::jsonb) <> 'null'::jsonb), false) as car from pipeline.website_sync_items i where i.entity = 'course' and i.removed_at is null), wc as (select x.ref_id from security.website_sync_candidates_v1('course') x where x.ref_id is not null), zf as (select i.item_key, coalesce((coalesce(i.item->'official_url', 'null'::jsonb) <> 'null'::jsonb), false) as car from pipeline.zoho_sync_items i where i.entity = 'course' and i.removed_at is null), zc as (select x.ref_id from security.zoho_sync_candidates_v1('course') x where x.ref_id is not null) select ct.cc, count(*) as expected, count(*) filter (where wf.item_key is not null and wf.car) as w_matched, count(*) filter (where wf.item_key is not null and not wf.car) as w_pending, count(*) filter (where wf.item_key is null and wc.ref_id is not null) as w_missing, count(*) filter (where wf.item_key is null and wc.ref_id is null) as w_not_served, count(*) filter (where zf.item_key is not null and zf.car) as z_matched, count(*) filter (where zf.item_key is not null and not zf.car) as z_pending, count(*) filter (where zf.item_key is null and zc.ref_id is not null) as z_missing, count(*) filter (where zf.item_key is null and zc.ref_id is null) as z_not_served from ct left join wf on wf.item_key = ct.stable_key left join wc on wc.ref_id = ct.id left join zf on zf.item_key = ct.stable_key left join zc on zc.ref_id = ct.id group by 1$q$, 'Official course links created, less links that are inactive or deprecated and whose record changed in the window (there is no withdrawal time, so the removed figure is an upper bound)', null, array['course-link-search-worker']::text[], array['search:queued']::text[], array['search:none', 'human']::text[], '{"speed": "Course link search keeps no timestamped ledger, so items per hour cannot be counted."}'::jsonb, '{"screen": "courses", "filled": null, "missing": null, "website": null, "zoho": null, "note": "The Course Catalogue has no official link filter yet (follow-up gap)."}'::jsonb, '20261109210000')
on conflict (stream) do nothing;

-- 9. job data-delivery (G1: catalogued first), register ----------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('data-delivery', 'Reports', 63, 'Data Delivery: count coverage, gains and Website/Zoho state of every data stream',
  'Each minute: counts, for each data stream (provider descriptions, intake dates, course descriptions, fees, English, entry requirements, scholarships, discovery), the measures whose last count is older than Pipeline settings > Data delivery > count each measure again after, a few at a time within a time budget, and keeps the figures for the Data Delivery summary at the top of Layer 2/3 > Operations. Records only: no credit, no API call, no change to any catalogue value. A measure that cannot be counted shows unknown.',
  5, false, null)
on conflict (jobname) do nothing;

do $sched$
begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('data-delivery', '* * * * *', 'select security.data_delivery_refresh_v1()');
  end if;
end $sched$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'data-delivery', 'Platform', 'Reports', 'F-OPS.03A: counts coverage, gains and Website/Zoho state of every data stream for the Data Delivery summary on Operations (records only)', 'active', '{}', '20261109210000'),
 ('table', 'pipeline.data_delivery_streams', 'Platform', 'Reports', 'F-OPS.03A: the data streams of the Data Delivery summary, their measures, queue and hold stages, gaps and drill-downs', 'active', '{}', '20261109210000'),
 ('table', 'pipeline.data_delivery_readings', 'Platform', 'Reports', 'F-OPS.03A: the latest counted result of each measure of each stream', 'active', '{}', '20261109210000'),
 ('function', 'security.data_delivery_refresh_v1', 'Platform', 'Reports', 'F-OPS.03A: the only writer of the Data Delivery snapshot (job data-delivery)', 'active', '{}', '20261109210000'),
 ('function', 'security.data_delivery_v1', 'Platform', 'Reports', 'F-OPS.03A: the one read behind the Data Delivery summary (admin_layer23 action data_delivery)', 'active', '{}', '20261109210000')
on conflict do nothing;

-- 10. post-check -------------------------------------------------------------------------------------------------------------------------------------------
do $post$
declare v_streams int; v_unsafe int;
begin
  select count(*) into v_streams from pipeline.data_delivery_streams;
  if v_streams < 8 then raise exception 'data delivery post-check: % streams', v_streams; end if;
  -- every measure SELECT passes the evaluator's own gate (a keyword or a semicolon is refused before the first count)
  select count(*) into v_unsafe from pipeline.data_delivery_streams s, lateral (values (s.coverage_sql), (s.net_sql), (s.consumer_sql)) q(t)
   where q.t is not null and (q.t !~* '^\s*(select|with)\s' or position(';' in q.t) > 0
         or q.t ~* '\m(insert|update|delete|truncate|drop|alter|create|grant|revoke|copy|call|execute|pg_sleep|set_config|dblink|lo_import)\M');
  select v_unsafe + count(*) into v_unsafe from pipeline.lane_funnel_stages s
   where s.lane = 'pdesc' and s.key in ('queued', 'held') and (s.count_sql !~* '^\s*(select|with)\s' or position(';' in s.count_sql) > 0
         or s.count_sql ~* '\m(insert|update|delete|truncate|drop|alter|create|grant|revoke|copy|call|execute|pg_sleep|set_config|dblink|lo_import)\M');
  if v_unsafe > 0 then raise exception 'data delivery post-check: % measure(s) are not a single read-only SELECT', v_unsafe; end if;
  if position('security.data_delivery_v1()' in pg_get_functiondef('public.admin_layer23(text,jsonb)'::regprocedure)) = 0 then raise exception 'data delivery post-check: admin_layer23 has no data_delivery action'; end if;
  if (select count(*) from pipeline.lane_funnel_stages where lane = 'pdesc' and key in ('queued', 'held')) <> 2 then raise exception 'data delivery post-check: the pdesc queue and held stages are missing'; end if;
  if to_regnamespace('cron') is not null and not exists (select 1 from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname = 'data-delivery') then
    raise exception 'data delivery post-check: job data-delivery is not scheduled and catalogued';
  end if;
  raise notice 'data delivery: % streams', v_streams;
end $post$;
