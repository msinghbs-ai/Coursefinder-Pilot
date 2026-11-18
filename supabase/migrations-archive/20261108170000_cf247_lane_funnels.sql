-- CF-247 OPS/UI lane H (Platform Admin mandate 8 Nov 2026, "visible control and progress in the existing StudySearch Admin UI"; directive 8 Nov 2026 14:06 Melbourne):
-- one generic, data-driven lane funnel for every autonomous domain, and a Firecrawl acceptance read. Both are SELECT-only reads for the EXISTING screens
-- (Layer 2/3 > Operations and Services & limits > Firecrawl); no new menu, no second dashboard, no second scheduler.
--
-- Why (live, read-only, 8 Nov 2026): an operator could not see, for intakes, fees, English, course and provider descriptions, entry requirements (AER),
-- scholarships, discovery and P0 integrity, in one place and in the same words: is it on, when is it next due, how many items sit at each stage, what moved in
-- 24 hours, how old the oldest waiting item is, what the last attempt did, why items are held, what it costs, where to drill down, and whether a person has to
-- decide. A green job (the scheduler's "succeeded") was shown as if it were a stage transfer. Only intake, AER and scholarships had stage counts, and those
-- sat in three different screens (pipeline.progress_transitions is read by first-run-verify only).
--
-- What:
--   1 pipeline.lane_funnel_lanes     one row per lane: title, the jobs behind it, the settings that switch it and the settings it is governed by (by key
--                                    prefix), the Firecrawl budget group, Layer 4 review kinds, issue references (internal), the existing screen.
--   2 pipeline.lane_funnel_stages    the stages of each lane, in order, each a kind (eligible, queued, in_flight, blocked, held, review_ready, human_review,
--                                    admitted, published, withdrawn, resolved, failed) with EITHER a transition of the existing progress contract
--                                    (pipeline.progress_transitions, read live) OR one read-only SELECT (count_sql returning n, oldest, gain and, for held causes,
--                                    one row per reason). A lane adds its stages by inserting rows (its own migration), never by editing a function.
--   3 pipeline.lane_funnel_readings / lane_funnel_history   the counted figures of the SELECT stages (snapshot: the screen never runs the counting SELECTs),
--                                    with their time, how long they took and the error, if any. A stage that could not be counted shows UNKNOWN, never 0.
--   4 security.lane_funnel_eval_v1 (STABLE: the database itself refuses any write inside a stage SELECT; one SELECT, no semicolon, no write keywords),
--     security.lane_funnel_refresh_v1 (job lane-funnel: the only writer; due check, single flight, per-stage time limit, records only),
--     security.lane_funnel_v1 (read: lane header, jobs with next run / last run / first-run verification, switches, settings with range and last change,
--     Firecrawl credits of the lane's group, issues, stages with count / oldest / 24 h gain / change on 24 h ago / held causes, and a verdict that keeps a green
--     job, a stage transfer and published data apart), public.admin_lane_funnel_v1 (rank 3 and above).
--   5 security.firecrawl_acceptance_v1 / public.admin_firecrawl_acceptance_v1 (rank 3 and above): allowance, live remaining, last sync, usage by lane group and
--     purpose, the reserved floor, daily spend against shares (today and the last days). Credits, never money. It reads the Controller's Firecrawl functions
--     (security.fc_*) and edits none of them.
--   6 settings (G2, toolset pipeline, section "Lane funnels"): switch, refresh time, per-stage time limit, window, stale time, history spacing and keep days,
--     settings shown, run-history span, Firecrawl days. Job lane-funnel (catalogued first).
-- Activation: ON (records only: it writes its own cache, spends no credit and calls no API). lane_funnel.on = 0 stops the refresh; the screen then shows the
--   last counted figures marked stale.
-- Pause / resume / run now stay the existing audited control (public.admin_automation_control, pipeline.admin_control_events); nothing here adds a control.
-- Replaces: nothing (the per-lane figures were on three screens and the progress contract; this reads them, it does not replace them)
-- Retires: nothing
-- Nothing is dropped or deleted by this migration. Consumer API untouched (G3): no public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*,
-- svc_website_settings_v1, api.* object or edge function is read, edited or granted; the stage SELECTs read internal tables and catalogue tables read-only.

do $guard$
begin
  if to_regclass('pipeline.platform_toolset_settings') is null or to_regclass('pipeline.automation_catalogue') is null then
    raise exception 'lane funnels need the settings register and the automation catalogue first';
  end if;
  if to_regprocedure('security.pipeline_num_v1(text,numeric)') is null or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'lane funnels need security.pipeline_num_v1 and security.current_role_rank first';
  end if;
end $guard$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'lane_funnel.on', 'Lane funnels: count every lane''s stages',
  '1: job lane-funnel counts the stages of each autonomous lane (intakes, fees, English, descriptions, entry requirements, scholarships, discovery, integrity) from the existing tables and keeps the figures for Layer 2/3 > Operations. 0: no new count; the screen shows the last figures marked stale. Records only: no credit, no API call, no change to any catalogue value.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1700, 'Mandate 8 Nov 2026 (OPS/UI): visible funnel for every lane; ships on, records only', 'Lane funnels', 'security.lane_funnel_refresh_v1 (job lane-funnel)'),
 ('pipeline', 'lane_funnel.refresh_minutes', 'Lane funnels: count each stage again after',
  'A stage is counted again when its last count is older than this. The job looks every minute; this keeps each stage to one count in this time.',
  'number', to_jsonb(15), 1, 240, 'minutes', 1701, 'Mandate 8 Nov 2026 (OPS/UI)', 'Lane funnels', 'security.lane_funnel_refresh_v1'),
 ('pipeline', 'lane_funnel.stage_timeout_seconds', 'Lane funnels: longest time allowed to count one stage',
  'A stage that takes longer is stopped and shown as unknown with the reason, so one slow count cannot hold the database.',
  'number', to_jsonb(20), 1, 120, 'seconds', 1702, 'Mandate 8 Nov 2026 (OPS/UI)', 'Lane funnels', 'security.lane_funnel_refresh_v1'),
 ('pipeline', 'lane_funnel.gain_window_hours', 'Lane funnels: gains are counted over the last',
  'The 24-hour gain column and the job run counts use this many hours. The first-run and progress observer has its own window (progress.window_hours).',
  'number', to_jsonb(24), 1, 168, 'hours', 1703, 'Mandate 8 Nov 2026 (OPS/UI): last 24 h net gains', 'Lane funnels', 'security.lane_funnel_eval_v1; security.lane_funnel_v1'),
 ('pipeline', 'lane_funnel.stale_after_minutes', 'Lane funnels: a count is marked stale after',
  'A stage figure older than this shows a Stale chip with its age. Keep it above the count-again time.',
  'number', to_jsonb(45), 5, 1440, 'minutes', 1704, 'Mandate 8 Nov 2026 (OPS/UI)', 'Lane funnels', 'security.lane_funnel_v1'),
 ('pipeline', 'lane_funnel.history_minutes', 'Lane funnels: keep a trend point every',
  'One point per stage is kept this often, to show the change on 24 hours ago.',
  'number', to_jsonb(60), 5, 1440, 'minutes', 1705, 'Mandate 8 Nov 2026 (OPS/UI): trend', 'Lane funnels', 'security.lane_funnel_refresh_v1'),
 ('pipeline', 'lane_funnel.keep_days', 'Lane funnels: keep trend points for',
  'Older trend points are removed by the job (the figures they came from are untouched).',
  'number', to_jsonb(30), 2, 365, 'days', 1706, 'Mandate 8 Nov 2026 (OPS/UI)', 'Lane funnels', 'security.lane_funnel_refresh_v1'),
 ('pipeline', 'lane_funnel.settings_shown_max', 'Lane funnels: settings listed for a lane',
  'Each lane lists the settings that govern it (by key prefix), up to this many, with value, range, unit, what uses it and the last change.',
  'number', to_jsonb(60), 5, 200, 'settings', 1707, 'Mandate 8 Nov 2026 (OPS/UI): labelled live settings', 'Lane funnels', 'security.lane_funnel_v1'),
 ('pipeline', 'lane_funnel.run_history_hours', 'Lane funnels: scheduler history read for the last-run columns',
  'The last attempt, last success and run counts of a lane''s jobs are read from this much scheduler history.',
  'number', to_jsonb(48), 2, 336, 'hours', 1708, 'Mandate 8 Nov 2026 (OPS/UI): last attempt and result', 'Lane funnels', 'security.lane_funnel_v1'),
 ('pipeline', 'lane_funnel.firecrawl_days', 'Firecrawl acceptance: daily spend shown for the last',
  'Settings > Services & limits > Firecrawl shows each day''s credits by group against the daily shares for this many Melbourne days.',
  'number', to_jsonb(7), 1, 31, 'days', 1709, 'Mandate 8 Nov 2026 section 3: daily spend distribution', 'Lane funnels', 'security.firecrawl_acceptance_v1')
on conflict (toolset_key, key) do nothing;

-- 2. tables ----------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.lane_funnel_lanes (
  lane text primary key check (lane ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  sort integer not null,
  what text,
  jobs text[] not null default '{}',
  switch_keys text[] not null default '{}',
  setting_prefixes text[] not null default '{}',
  budget_group text check (budget_group is null or budget_group in ('course_search', 'reads', 'scholarships', 'central', 'other')),
  review_kinds text[] not null default '{}',
  issue_refs text[] not null default '{}',
  screen text,
  process_record text,
  added_in text);
comment on table pipeline.lane_funnel_lanes is 'CF-247 OPS/UI (mandate 8 Nov 2026): one row per autonomous lane shown on Layer 2/3 > Operations (intakes, fees, English, course and provider descriptions, entry requirements, scholarships, discovery, integrity): its title, the scheduled jobs behind it, the settings that switch it, the settings that govern it (by key prefix), the Firecrawl budget group, the Layer 4 review kinds that wait on a person, internal issue references and the existing screen where it is worked. Read by security.lane_funnel_v1; edited only by a migration. Never read by the consumer API.';
alter table pipeline.lane_funnel_lanes enable row level security;
revoke all on pipeline.lane_funnel_lanes from public, anon, authenticated;

create table if not exists pipeline.lane_funnel_stages (
  lane text not null references pipeline.lane_funnel_lanes(lane),
  step integer not null,
  key text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  kind text not null check (kind in ('eligible', 'queued', 'in_flight', 'blocked', 'held', 'review_ready', 'human_review', 'admitted', 'published', 'withdrawn', 'resolved', 'failed')),
  what text,
  transition_key text,
  count_sql text,
  drill text,
  primary key (lane, key),
  unique (lane, step),
  check (transition_key is not null or count_sql is not null));
comment on table pipeline.lane_funnel_stages is 'CF-247 OPS/UI (mandate 8 Nov 2026): the stages of each lane, in order. A stage is either a transition of the existing progress contract (transition_key, read live from pipeline.progress_transitions) or one read-only SELECT (count_sql) returning n (items at the stage now), oldest (timestamp of the oldest waiting item) and gain (items that arrived in the last {window}); a held stage returns one row per cause with a reason column. {window} is replaced by the gain window setting. The SELECT must be a single statement with no write keyword and fully schema-qualified; it runs only in job lane-funnel, never when a screen opens. Kind says what the figure means (a green job is not a transfer: only admitted and published count as movement). Edited only by a migration. Never read by the consumer API.';
alter table pipeline.lane_funnel_stages enable row level security;
revoke all on pipeline.lane_funnel_stages from public, anon, authenticated;

create table if not exists pipeline.lane_funnel_readings (
  lane text not null,
  stage_key text not null,
  measured_at timestamptz not null default now(),
  n numeric,
  oldest_at timestamptz,
  gain numeric,
  reasons jsonb,
  took_ms integer,
  error text,
  primary key (lane, stage_key));
comment on table pipeline.lane_funnel_readings is 'CF-247 OPS/UI (mandate 8 Nov 2026): the latest counted figure of each SELECT stage of pipeline.lane_funnel_stages (items now, oldest waiting, gain in the window, held causes), when it was counted, how long it took and its error. n is null when the stage could not be counted (shown as unknown, never 0). Written only by job lane-funnel (security.lane_funnel_refresh_v1). Never read by the consumer API.';
alter table pipeline.lane_funnel_readings enable row level security;
revoke all on pipeline.lane_funnel_readings from public, anon, authenticated;

create table if not exists pipeline.lane_funnel_history (
  lane text not null,
  stage_key text not null,
  measured_at timestamptz not null,
  n numeric,
  gain numeric,
  primary key (lane, stage_key, measured_at));
comment on table pipeline.lane_funnel_history is 'CF-247 OPS/UI (mandate 8 Nov 2026): one point per stage every lane_funnel.history_minutes (items now and gain), so the screen can show the change on 24 hours ago. Written and trimmed (lane_funnel.keep_days) only by job lane-funnel. Never read by the consumer API.';
alter table pipeline.lane_funnel_history enable row level security;
revoke all on pipeline.lane_funnel_history from public, anon, authenticated;

-- 3. the stage evaluator: one read-only SELECT ------------------------------------------------------------------------------------------------------
create or replace function security.lane_funnel_eval_v1(p_sql text, p_window_hours integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_sql text; v_rows jsonb;
begin
  -- STABLE: a write inside the statement (even in a CTE) is refused by the database itself; the checks below refuse it earlier, in words
  v_sql := replace(btrim(coalesce(p_sql, ''), E' \n\t\r;'), '{window}', format('make_interval(hours => %s)', greatest(coalesce(p_window_hours, 1), 1)));  -- fixed: at least one hour
  if v_sql !~* '^\s*(select|with)\s' or position(';' in v_sql) > 0
     or v_sql ~* '\m(insert|update|delete|truncate|drop|alter|create|grant|revoke|copy|call|execute|pg_sleep|set_config|dblink|lo_import)\M' then
    raise exception 'lane funnel: a stage must be one read-only SELECT (no semicolon, no write keyword)';
  end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (%s) t', v_sql) into v_rows;
  return v_rows;
end $function$;
revoke all on function security.lane_funnel_eval_v1(text, integer) from public, anon, authenticated;

-- 4. the refresh (job lane-funnel): the only writer ---------------------------------------------------------------------------------------------------
create or replace function security.lane_funnel_refresh_v1(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  s record; v_rows jsonb; v_t0 timestamptz; v_prev text := current_setting('statement_timeout');
  v_every int := security.pipeline_num_v1('lane_funnel.refresh_minutes', 15)::int;
  v_win int := security.pipeline_num_v1('lane_funnel.gain_window_hours', 24)::int;
  v_to int := security.pipeline_num_v1('lane_funnel.stage_timeout_seconds', 20)::int;
  v_hist int := security.pipeline_num_v1('lane_funnel.history_minutes', 60)::int;
  v_keep int := security.pipeline_num_v1('lane_funnel.keep_days', 30)::int;
  v_done int := 0; v_failed int := 0; v_n numeric; v_old timestamptz; v_gain numeric; v_reasons jsonb;
begin
  if security.pipeline_num_v1('lane_funnel.on', 1) < 1 and not p_force then return jsonb_build_object('skipped', 'switched off (lane_funnel.on)'); end if;
  if not pg_try_advisory_xact_lock(hashtext('lane_funnel_refresh')) then return jsonb_build_object('skipped', 'another count is running'); end if;
  perform set_config('statement_timeout', (v_to * 1000)::text, true);  -- fixed: the setting is in seconds, the database wants milliseconds
  for s in select st.lane, st.key, st.count_sql from pipeline.lane_funnel_stages st where st.count_sql is not null order by st.lane, st.step loop
    if not p_force and exists (select 1 from pipeline.lane_funnel_readings r where r.lane = s.lane and r.stage_key = s.key and r.error is null
                                  and r.measured_at > now() - make_interval(mins => v_every)) then continue; end if;
    v_t0 := clock_timestamp();
    begin
      v_rows := security.lane_funnel_eval_v1(s.count_sql, v_win);
      if jsonb_array_length(v_rows) = 0 then v_n := 0; v_old := null; v_gain := null; v_reasons := null;
      elsif v_rows->0 ? 'reason' then
        select coalesce(sum((x->>'n')::numeric), 0), min((x->>'oldest')::timestamptz), sum((x->>'gain')::numeric) into v_n, v_old, v_gain from jsonb_array_elements(v_rows) x;
        v_reasons := v_rows;
      else
        v_n := (v_rows->0->>'n')::numeric; v_old := (v_rows->0->>'oldest')::timestamptz; v_gain := (v_rows->0->>'gain')::numeric; v_reasons := null;
      end if;
      insert into pipeline.lane_funnel_readings as r(lane, stage_key, measured_at, n, oldest_at, gain, reasons, took_ms, error)
        values (s.lane, s.key, clock_timestamp(), v_n, v_old, v_gain, v_reasons, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int, null)
        on conflict (lane, stage_key) do update set measured_at = excluded.measured_at, n = excluded.n, oldest_at = excluded.oldest_at, gain = excluded.gain,
          reasons = excluded.reasons, took_ms = excluded.took_ms, error = null;
      v_done := v_done + 1;
    exception when others then
      insert into pipeline.lane_funnel_readings as r(lane, stage_key, measured_at, n, oldest_at, gain, reasons, took_ms, error)
        values (s.lane, s.key, clock_timestamp(), null, null, null, null, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int, left(sqlerrm, 300))
        on conflict (lane, stage_key) do update set measured_at = excluded.measured_at, n = null, oldest_at = null, gain = null, reasons = null, took_ms = excluded.took_ms, error = excluded.error;
      v_failed := v_failed + 1;
    end;
  end loop;
  insert into pipeline.lane_funnel_history(lane, stage_key, measured_at, n, gain)
    select r.lane, r.stage_key, r.measured_at, r.n, r.gain from pipeline.lane_funnel_readings r
     where r.n is not null and not exists (select 1 from pipeline.lane_funnel_history h where h.lane = r.lane and h.stage_key = r.stage_key and h.measured_at > now() - make_interval(mins => v_hist))
    on conflict do nothing;
  delete from pipeline.lane_funnel_history where measured_at < now() - make_interval(days => v_keep);
  perform set_config('statement_timeout', v_prev, true);
  return jsonb_build_object('counted', v_done, 'failed', v_failed);
end $function$;
revoke all on function security.lane_funnel_refresh_v1(boolean) from public, anon, authenticated;

-- 5. the read ----------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.lane_funnel_v1(p_lane text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
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
end $function$;
revoke all on function security.lane_funnel_v1(text) from public, anon, authenticated;

create or replace function public.admin_lane_funnel_v1(p_lane text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Operations read permission required' using errcode = '42501'; end if;
  return security.lane_funnel_v1(p_lane);
end $function$;
revoke all on function public.admin_lane_funnel_v1(text) from public, anon;
grant execute on function public.admin_lane_funnel_v1(text) to authenticated;

-- 6. Firecrawl acceptance (read only; credits, never money) -------------------------------------------------------------------------------------------
create or replace function security.firecrawl_acceptance_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  p pipeline.layer2_acquisition_providers%rowtype; o pipeline.vendor_credit_observations%rowtype; v_est numeric; v_room numeric; v_floor numeric; v_status jsonb;
  v_win int := security.pipeline_num_v1('lane_funnel.gain_window_hours', 24)::int;
  v_days int := security.pipeline_num_v1('lane_funnel.firecrawl_days', 7)::int;
  v_job jsonb; v_groups jsonb; v_hist jsonb; v_purposes jsonb; v_groupuse jsonb; v_period_start timestamptz;
begin
  select * into p from pipeline.layer2_acquisition_providers x where x.provider_key = 'firecrawl';
  if p.id is not null then
    select * into o from pipeline.vendor_credit_observations x where x.provider_id = p.id order by x.observed_at desc limit 1;
  end if;
  v_est := security.fc_vendor_estimate_v1();
  v_room := security.fc_priority_room_v1();
  v_floor := security.fc_setting_num_v1('priority_floor_course_search', 0);
  v_status := security.fc_budget_status_v1();
  v_period_start := nullif(o.raw->>'billing_period_start', '')::timestamptz;
  select jsonb_build_object('job', 'firecrawl-credit', 'schedule', c.schedule, 'active', c.active,
      'next_run', case when c.active then security.cron_next_run_v1(c.schedule, now()) end,
      'last_start', r.start_time, 'last_status', r.status, 'last_message', left(r.return_message, 240))
    into v_job from cron.job c
    left join lateral (select d.start_time, d.status, d.return_message from cron.job_run_details d where d.jobid = c.jobid order by d.start_time desc limit 1) r on true
   where c.jobname = 'firecrawl-credit';
  -- the daily share left per group is the Controller's own function (security.fc_budget_left_v1), asked with one purpose of each group
  select coalesce(jsonb_agg(g || jsonb_build_object('left', security.fc_budget_left_v1(case g->>'group' when 'course_search' then 'course_link_search' when 'reads' then 'scrape'
                       when 'scholarships' then 'sch_scrape' when 'central' then 'central_map' else 'other_purpose' end)) order by ord), '[]'::jsonb) into v_groups  -- fixed: one purpose of each group, to ask the budget function
    from jsonb_array_elements(v_status->'groups') with ordinality t(g, ord);
  select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'group', d.grp, 'credits', d.units) order by d.day desc, d.grp), '[]'::jsonb) into v_hist from (
    select (u.at at time zone 'Australia/Melbourne')::date as day, security.fc_purpose_group_v1(u.purpose) as grp, sum(u.units) as units
      from pipeline.coverage_vendor_usage u where u.at >= security.fc_day_start_v1() - make_interval(days => v_days - 1) and u.on_demand_run is null group by 1, 2) d;
  select coalesce(jsonb_agg(jsonb_build_object('group', x.grp, 'credits_window', x.w, 'credits_period', x.pr, 'on_demand_window', x.od) order by x.grp), '[]'::jsonb) into v_groupuse from (
    select security.fc_purpose_group_v1(u.purpose) grp, sum(u.units) filter (where u.at > now() - make_interval(hours => v_win)) w,
           sum(u.units) filter (where v_period_start is not null and u.at >= v_period_start) pr, sum(u.units) filter (where u.at > now() - make_interval(hours => v_win) and u.on_demand_run is not null) od
      from pipeline.coverage_vendor_usage u where u.at > coalesce(v_period_start, now() - make_interval(hours => v_win)) - make_interval(hours => v_win) group by 1) x;
  select coalesce(jsonb_agg(jsonb_build_object('purpose', x.purpose, 'group', x.grp, 'credits_window', x.units, 'calls_window', x.n, 'last_at', x.last_at) order by x.units desc), '[]'::jsonb) into v_purposes from (
    select u.purpose, security.fc_purpose_group_v1(u.purpose) grp, sum(u.units) units, count(*) n, max(u.at) last_at
      from pipeline.coverage_vendor_usage u where u.at > now() - make_interval(hours => v_win) group by 1, 2) x;
  return jsonb_build_object('at', now(), 'unit', 'credits', 'note', 'Credits are counted by the platform; the vendor bill is not shown here and credits are not money.',
    'allowance', jsonb_build_object('plan_credits', o.plan_units, 'monthly_limit_credits', nullif(p.billing_config->>'monthly_vendor_units_limit', '')::numeric,
        'stop_at_remaining_credits', nullif(p.billing_config->>'stop_at_vendor_units_remaining', '')::numeric, 'plan_tier', p.billing_config->>'plan_tier',
        'period_start', v_period_start, 'period_end', o.period_end),
    'vendor', jsonb_build_object('remaining_credits', o.remaining_units, 'read_at', o.observed_at, 'age_minutes', case when o.observed_at is not null then round(extract(epoch from now() - o.observed_at) / 60) end,
        'fresh', v_est is not null, 'estimated_now_credits', v_est, 'used_since_reading_credits', case when v_est is not null then greatest(o.remaining_units - v_est, 0) end,
        'above_plan', case when o.remaining_units is not null and o.plan_units is not null then o.remaining_units > o.plan_units end),
    'sync', coalesce(v_job, jsonb_build_object('job', 'firecrawl-credit', 'scheduled', false)),
    'floor', jsonb_build_object('setting', 'firecrawl / priority_floor_course_search', 'credits', v_floor, 'applies', v_room is not null, 'room_credits', v_room,
        'under_floor', case when v_room is not null then v_room < 0 end, 'switched_off', v_floor <= 0),
    'daily', jsonb_build_object('budget_on', v_status->'on', 'total_credits', v_status->'total', 'billed_today', v_status->'billed_today', 'used_today', v_status->'used_today',
        'day_start', v_status->'day_start', 'groups', v_groups, 'days', v_hist, 'days_shown', v_days),
    'usage', jsonb_build_object('window_hours', v_win, 'by_group', v_groupuse, 'by_purpose', v_purposes));
end $function$;
revoke all on function security.firecrawl_acceptance_v1() from public, anon, authenticated;

create or replace function public.admin_firecrawl_acceptance_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Operations read permission required' using errcode = '42501'; end if;
  return security.firecrawl_acceptance_v1();
end $function$;
revoke all on function public.admin_firecrawl_acceptance_v1() from public, anon;
grant execute on function public.admin_firecrawl_acceptance_v1() to authenticated;

-- 7. the lanes and their stages (read from the live schema, 8 Nov 2026; a lane's own migration adds or refines rows) -----------------------------------
insert into pipeline.lane_funnel_lanes(lane, title, sort, what, jobs, switch_keys, setting_prefixes, budget_group, review_kinds, issue_refs, screen, process_record, added_in) values
 ('p0', 'P0 and release integrity', 10, 'Open P0 issues, releases whose scheduled jobs have not yet proved their first run, and the consumer API guard.',
  array['consumer-api-guard', 'first-run-verify', 'integration-validate', 'ops-controller'], '{}', array['frv.', 'recovery.'], null, '{}', array['IQ-00313'], 'Platform health > Integration queue', 'docs/platform/AGENT-OPERATING-MODEL.md', '20261108170000'),
 ('int', 'Intake dates and deadlines', 20, 'Course page and first-party calendar evidence to exact start dates and application deadlines, then Website and Zoho.',
  array['intake-dates-apply', 'calendar-reread', 'process-results', 'coverage-admit-intakes', 'provider-calendar-intakes', 'provider-calendar-defaults'], array['intake_dates.apply_enabled', 'progress.intake_chain_on'],
  array['intake_dates.', 'intake_progress.', 'calendar.', 'process_results.'], 'central', '{}', array['IQ-00313', 'IQ-00111'], 'Layer 2/3 > Operations > Process results', 'docs/platform/processes/intake-dates.md', '20261108170000'),
 ('fee', 'Tuition and other fees', 30, 'Fee schedules and course pages read into fee rows, checked, admitted and held as active course fees.',
  array['fee-reader', 'fee-period-settle', 'provider-fee-profiles-apply', 'provider-basis-rule-admit', 'fee-wording-rules', 'provider-facts', 'provider-fee-ranges-refresh', 'scholarship-fee-alignment', 'l4-rule-fee-year-align', 'fee-plausibility-guard'], array['fees.course_pages', 'fees.identity_gate_on'],
  array['fees.'], 'central', array['provider_current_tuition', 'provider_current_tuition_validation', 'fee_check'], array['IQ-00111', 'IQ-00020'], 'Layer 2/3 > Enrich fields > Fee reader', null, '20261108170000'),
 ('eng', 'English entry requirements', 40, 'University English policies and course pages to course English rows, with review where a person must decide.',
  array['central-attach', 'policy-add-tests', 'provider-english-defaults', 'policy-auto-approve', 'coverage-admit', 'companion-read'], array['central.auto_approve_english_all'],
  array['central.english', 'central.auto_approve_english', 'batch.english'], 'central', array['course_english'], '{}', 'Layer 2/3 > Enrich fields', null, '20261108170000'),
 ('cdesc', 'Course descriptions', 50, 'Source-backed course description proposals, human review in Layer 4, admission and publication.',
  array['field-gap-queue', 'enrich-plan-run', 'layer4-readiness', 'course-description-stale-retire', 'coverage-admit'], array['enrich.course_description_review_first', 'enrich.course_description_promote_held_on'], array['enrich.course_description', 'enrich.course_text', 'layer4.'], 'reads', array['course_description_first_read'], '{}', 'Layer 4 > Inbox', null, '20261108170000'),
 ('pdesc', 'Provider descriptions', 60, 'Official About pages to provider descriptions, checked against their evidence, reviewed by a person, then published.',
  array['provider-description-read'], array['pdesc.enabled', 'pdesc.acquire_direct', 'pdesc.acquire_firecrawl'], array['pdesc.', 'batch.provider_description'], 'central', array['provider_description'], '{}', 'Layer 2/3 > Operations > Provider description Run & Validate', null, '20261108170000'),
 ('aer', 'Academic entry requirements (AER)', 70, 'Official sources to read rows, review-ready packets, human decision, active entry rows and Website publication.',
  array['aer-scheduled-read', 'entry-matrix-read', 'aer-replay', 'aer-source-stored-find', 'aer-outcome-register', 'aer-reconcile', 'layer4-readiness'], array['aer.replay_on', 'aer.source_stored_find_on', 'aer.e13_recover_on'],
  array['aer.', 'layer4.', 'entry.max_rows', 'reading.'], 'reads', array['aer_review', 'course_entry_first_read', 'entry_matrix_first_run'], '{}', 'Layer 4 > Inbox (Entry requirements)', null, '20261108170000'),
 ('sch', 'Scholarships', 80, 'Coverage cases to found listings, read pages, eligibility, review, admission and publication with the right audience.',
  array['scholarship-coverage-classify', 'scholarship-coverage-recover', 'scholarship-listing', 'scholarship-discover', 'scholarship-read', 'scholarship-ai-extract', 'scholarship-auto-publish'],
  array['sch_cov.classify_on', 'sch_cov.recover_register_pages_on', 'sch_cov.recover_stored_reads_on', 'sch_cov.recover_listings_on'], array['sch_cov.', 'sch_ai.'], 'scholarships', array['held_scholarship'], '{}', 'Layer 2/3 > Scholarships', null, '20261108170000'),
 ('disc', 'Discovery, provider lifecycle and links', 90, 'Provider websites, course pages and official course links, ranking sources, and the reasons rankings are not yet published.',
  array['source-find', 'coverage-find-site', 'course-link-search-worker', 'course-link-search', 'course-link-reverse', 'link-refresh', 'ranking-link', 'ranking-edition-check', 'provider-identity-check', 'course-url-fill'],
  '{}', array['ranking.', 'layer4.page_needed'], 'course_search', array['official_course_url'], array['IQ-00061', 'IQ-00072'], 'Layer 2/3 > Course sources', null, '20261108170000')
on conflict (lane) do nothing;

insert into pipeline.lane_funnel_stages(lane, step, key, title, kind, what, transition_key, count_sql, drill) values
 -- P0 and release integrity
 ('p0', 10, 'open_p0', 'Open P0 issues', 'blocked', 'P0 issues not yet closed, by status (deployed and awaiting production verification count as open).', null,
  $q$select status as reason, count(*) as n, min(detected_at) as oldest from pipeline.integration_issues where severity = 'P0' and status <> 'closed' group by status$q$, 'health/integration'),
 ('p0', 20, 'releases_unproven', 'Releases whose job has not proved its first run', 'blocked', 'Release jobs awaiting their first scheduled run or whose first run failed.', null,
  $q$select status as reason, count(*) as n, min(registered_at) as oldest from pipeline.release_job_verifications where status in ('awaiting_first_run', 'failed_first_run') group by status$q$, 'health/integration'),
 ('p0', 30, 'p0_closed', 'P0 issues closed', 'resolved', 'P0 issues closed (gain: closed in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where closed_at > now() - {window}) as gain from pipeline.integration_issues where severity = 'P0' and status = 'closed'$q$, 'health/integration'),
 ('p0', 40, 'releases_verified', 'Releases operationally verified', 'published', 'Release jobs whose first scheduled run completed and produced the expected output (gain: verified in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where verified_at > now() - {window}) as gain from pipeline.release_job_verifications where status = 'operationally_verified'$q$, 'health/integration'),
 -- intake dates (the existing progress contract, plus the held causes of the last window)
 ('int', 10, 'selected', 'Selected and evaluated', 'eligible', 'Intake rows eligible and evaluated against evidence in the window.', 'intake_selection', null, 'layer2/operations'),
 ('int', 20, 'held', 'Held, by cause', 'held', 'Decisions in the window that did not admit a value, by cause (a held row is not lost: it is looked at again when its evidence changes).', null,
  $q$select coalesce(failure_class, outcome) as reason, count(*) as n, min(run_at) as oldest from pipeline.course_intake_date_events where run_at > now() - {window} and outcome <> 'filled' group by 1$q$, 'layer2/operations'),
 ('int', 30, 'admitted', 'Admitted to the catalogue', 'admitted', 'Start dates and deadlines admitted with evidence (gain: created in the window).', 'intake_admission', null, 'layer2/operations'),
 ('int', 40, 'published', 'Checked in the Website source', 'published', 'Admitted values found in the Website stored source (publication check passed).', 'intake_publication', null, 'layer2/operations'),
 -- fees
 ('fee', 10, 'sources', 'Fee sources found', 'eligible', 'Fee schedule documents found for providers, by state.', null,
  $q$select status as reason, count(*) as n, min(created_at) as oldest, count(*) filter (where created_at > now() - {window}) as gain from pipeline.provider_fact_sources where kind = 'fee_schedule' group by status$q$, 'layer2/enrich'),
 ('fee', 20, 'queued', 'Waiting for the fee reader', 'queued', 'Fee reader queue items not yet done or failed.', null,
  $q$select count(*) as n, min(created_at) as oldest, null::bigint as gain from pipeline.fee_reader_queue where state not in ('done', 'failed')$q$, 'layer2/enrich'),
 ('fee', 30, 'read', 'Fee rows read', 'in_flight', 'Fee rows the reader extracted from pages (gain: read in the window).', null,
  $q$select count(*) as n, min(created_at) as oldest, count(*) filter (where created_at > now() - {window}) as gain from pipeline.fee_reader_rows$q$, 'layer2/enrich'),
 ('fee', 40, 'held', 'Fee rows not admitted, by cause', 'held', 'Fee rows set aside by the reader''s checks, by outcome (domestic, not yearly, no matching course, conflict, same as held).', null,
  $q$select outcome as reason, count(*) as n, min(created_at) as oldest, count(*) filter (where created_at > now() - {window}) as gain from pipeline.fee_reader_rows where outcome not in ('admitted', 'replaced') group by outcome$q$, 'layer2/enrich'),
 ('fee', 50, 'human', 'Waiting for a person (tuition)', 'human_review', 'Layer 4 tuition items pending a decision (gain: decided in the window).', null,
  $q$select count(*) filter (where status = 'pending') as n, min(created_at) filter (where status = 'pending') as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code in ('provider_current_tuition', 'provider_current_tuition_validation')$q$, 'layer4/inbox'),
 ('fee', 55, 'readiness', 'Pending items, by readiness', 'review_ready', 'Pending tuition items by readiness (judgement ready means a person can decide now).', null,
  $q$select readiness as reason, count(*) as n, min(item_created_at) as oldest, null::bigint as gain from pipeline.layer4_item_readiness where item_status = 'pending' and field_code in ('provider_current_tuition', 'provider_current_tuition_validation') group by readiness$q$, 'layer4/inbox'),
 ('fee', 60, 'admitted', 'Fee rows admitted or replaced', 'admitted', 'Fee rows the reader admitted or that replaced an older value (gain: read in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where created_at > now() - {window}) as gain from pipeline.fee_reader_rows where outcome in ('admitted', 'replaced')$q$, 'layer2/enrich'),
 ('fee', 70, 'active', 'Active course fees', 'published', 'Active fee rows in the catalogue, read by Website and Zoho (gain: created in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where created_at > now() - {window}) as gain from catalogue.course_fees where status = 'active'$q$, 'courses'),
 ('fee', 80, 'withdrawn', 'Fee rows withdrawn', 'withdrawn', 'Fee rows made inactive (gain: changed in the window). A correction or withdrawal is shown beside new gains.', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where updated_at > now() - {window}) as gain from catalogue.course_fees where status = 'inactive'$q$, 'courses'),
 -- English
 ('eng', 10, 'no_english', 'Active courses with no active English rule', 'eligible', 'Active courses holding no active English requirement row (the gap).', null,
  $q$select count(*) as n, null::timestamptz as oldest, null::bigint as gain from catalogue.courses c where c.lifecycle_status = 'active' and not exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and e.status = 'active')$q$, 'layer2/enrich'),
 ('eng', 20, 'sources', 'English policy documents, by state', 'in_flight', 'Provider English policy documents found, read or failed.', null,
  $q$select status as reason, count(*) as n, min(created_at) as oldest, count(*) filter (where created_at > now() - {window}) as gain from pipeline.provider_fact_sources where kind = 'english_policy' group by status$q$, 'layer2/enrich'),
 ('eng', 30, 'human', 'Waiting for a person (course English)', 'human_review', 'Layer 4 course English items pending a decision (gain: decided in the window).', null,
  $q$select count(*) filter (where status = 'pending') as n, min(created_at) filter (where status = 'pending') as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code = 'course_english'$q$, 'layer4/inbox'),
 ('eng', 35, 'readiness', 'Pending items, by readiness', 'review_ready', 'Pending course English items by readiness.', null,
  $q$select readiness as reason, count(*) as n, min(item_created_at) as oldest, null::bigint as gain from pipeline.layer4_item_readiness where item_status = 'pending' and field_code in ('course_english') group by readiness$q$, 'layer4/inbox'),
 ('eng', 40, 'active', 'Active course English rows', 'published', 'Active English requirement rows (gain: verified in the window, which includes older rows checked again).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where last_verified_at > now() - {window}) as gain from catalogue.course_english_requirements where status = 'active'$q$, 'courses'),
 ('eng', 50, 'withdrawn', 'Course English rows withdrawn', 'withdrawn', 'English rows withdrawn (a correction, shown beside gains).', null,
  $q$select count(*) as n, null::timestamptz as oldest, null::bigint as gain from catalogue.course_english_requirements where status = 'withdrawn'$q$, 'courses'),
 -- course descriptions
 ('cdesc', 10, 'no_description', 'Active courses with no description', 'eligible', 'Active courses holding no description (the gap).', null,
  $q$select count(*) as n, null::timestamptz as oldest, null::bigint as gain from catalogue.courses where lifecycle_status = 'active' and coalesce(btrim(description), '') = ''$q$, 'layer4/inbox'),
 ('cdesc', 20, 'human', 'Waiting for a person (first read)', 'human_review', 'Layer 4 course description items pending a decision (gain: decided in the window). A person decides; nothing here approves.', null,
  $q$select count(*) filter (where status = 'pending') as n, min(created_at) filter (where status = 'pending') as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code = 'course_description_first_read'$q$, 'layer4/inbox'),
 ('cdesc', 25, 'readiness', 'Pending items, by readiness', 'review_ready', 'Pending course description items by readiness: the review capacity a person has to meet.', null,
  $q$select readiness as reason, count(*) as n, min(item_created_at) as oldest, null::bigint as gain from pipeline.layer4_item_readiness where item_status = 'pending' and field_code in ('course_description_first_read') group by readiness$q$, 'layer4/inbox'),
 ('cdesc', 30, 'admitted', 'Approved by a person', 'admitted', 'Description items approved or approved with an edit (gain: decided in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code = 'course_description_first_read' and status in ('approved', 'edited_approved')$q$, 'layer4/inbox'),
 ('cdesc', 40, 'held_rejected', 'Rejected or returned, by decision', 'held', 'Description items a person rejected or returned.', null,
  $q$select status as reason, count(*) as n, null::timestamptz as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code = 'course_description_first_read' and status in ('rejected', 'returned_layer2', 'returned_layer3') group by status$q$, 'layer4/inbox'),
 ('cdesc', 35, 'held_first_admission', 'Held: first admission behind the provider cap', 'held', 'Description proposals the reader held because the provider already has the most first readings waiting for a person (they join the review when room opens). From the Course descriptions lane report, 8 Nov 2026.', null,
  $q$select count(*) as n, min(updated_at) as oldest, count(*) filter (where updated_at > now() - {window}) as gain from pipeline.field_enrich_items where field = 'description' and state = 'skipped' and reason like 'held_first_admission:%'$q$, 'layer2/enrich'),
 ('cdesc', 37, 'held_by_check', 'Held by a check, by rule', 'held', 'Description proposals the reader set aside because a check failed (unsupported claim, length, sentence count, quote not on the page and so on).', null,
  $q$select btrim(split_part(reason, ':', 2)) as reason, count(*) as n, min(updated_at) as oldest, count(*) filter (where updated_at > now() - {window}) as gain from pipeline.field_enrich_items where field = 'description' and state = 'skipped' and reason like 'held:%' group by 1$q$, 'layer2/enrich'),
 ('cdesc', 50, 'published', 'Active courses holding a description', 'published', 'Active courses with a description in the catalogue (gain: rows changed in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where updated_at > now() - {window}) as gain from catalogue.courses where lifecycle_status = 'active' and coalesce(btrim(description), '') <> ''$q$, 'courses'),
 -- provider descriptions
 ('pdesc', 10, 'no_description', 'Active providers with no description', 'eligible', 'Active providers holding no description (the gap).', null,
  $q$select count(*) as n, null::timestamptz as oldest, null::bigint as gain from catalogue.providers where lifecycle_status = 'active' and coalesce(btrim(description), '') = ''$q$, 'layer2/enrich'),
 ('pdesc', 20, 'human', 'Waiting for a person', 'human_review', 'Layer 4 provider description items pending a decision (gain: decided in the window).', null,
  $q$select count(*) filter (where status = 'pending') as n, min(created_at) filter (where status = 'pending') as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code = 'provider_description'$q$, 'layer4/inbox'),
 ('pdesc', 25, 'readiness', 'Pending items, by readiness', 'review_ready', 'Pending provider description items by readiness.', null,
  $q$select readiness as reason, count(*) as n, min(item_created_at) as oldest, null::bigint as gain from pipeline.layer4_item_readiness where item_status = 'pending' and field_code in ('provider_description') group by readiness$q$, 'layer4/inbox'),
 ('pdesc', 30, 'admitted', 'Approved by a person', 'admitted', 'Provider descriptions approved or approved with an edit (gain: decided in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code = 'provider_description' and status in ('approved', 'edited_approved')$q$, 'layer4/inbox'),
 ('pdesc', 40, 'published', 'Active providers holding a description', 'published', 'Active providers with a description (gain: rows changed in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where updated_at > now() - {window}) as gain from catalogue.providers where lifecycle_status = 'active' and coalesce(btrim(description), '') <> ''$q$, 'providers/providers'),
 -- AER (the existing progress contract, readiness classes and active rows)
 ('aer', 10, 'discovery', 'Source discovery', 'eligible', 'Courses with no entry-requirement source yet, and sources found in the window.', 'aer_source_discovery', null, 'entry/sources'),
 ('aer', 20, 'extraction', 'Extraction', 'in_flight', 'Entry-requirement pages read into proposed rows.', 'aer_extraction', null, 'entry/sources'),
 ('aer', 30, 'completeness', 'Completeness validation', 'in_flight', 'Reads checked for completeness before review.', 'aer_completeness', null, 'entry/sources'),
 ('aer', 40, 'technical', 'Technical correction', 'in_flight', 'Reads corrected by the technical route.', 'aer_technical_correction', null, 'entry/sources'),
 ('aer', 50, 'readiness', 'Pending items, by readiness', 'review_ready', 'Pending entry-requirement items by readiness: judgement ready (a person can decide), technical blocked, resolvable. Technical holds are not review capacity.', null,
  $q$select readiness as reason, count(*) as n, min(item_created_at) as oldest, null::bigint as gain from pipeline.layer4_item_readiness where item_status = 'pending' and field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') group by readiness$q$, 'layer4/inbox?kind=aer_review'),
 ('aer', 60, 'layer4', 'Layer 4 review', 'human_review', 'Items waiting for a person (no AI approval).', 'aer_layer4_review', null, 'layer4/inbox?kind=aer_review'),
 ('aer', 70, 'active', 'Active entry records', 'admitted', 'Entry rows admitted after review.', 'aer_active_records', null, 'entry/matrix'),
 ('aer', 80, 'publication', 'Consumer publication', 'published', 'Active rows confirmed in the consumer source.', 'aer_publication', null, 'entry/matrix'),
 ('aer', 90, 'active_rows', 'Active course entry rows in the catalogue', 'published', 'Rows in the catalogue now (gain: updated in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where updated_at > now() - {window}) as gain from catalogue.course_entry_requirements where status = 'active'$q$, 'entry/course'),
 -- scholarships (the existing progress contract)
 ('sch', 10, 'classification', 'Coverage classification', 'eligible', 'Coverage cases classified.', 'sch_classification', null, 'layer2/scholarships'),
 ('sch', 20, 'cases', 'Coverage cases, by state', 'eligible', 'Cases in each coverage state (found, watched, signed off, missing and the rest).', null,
  $q$select state as reason, count(*) as n, min(state_since) as oldest, count(*) filter (where state_since > now() - {window}) as gain from pipeline.scholarship_coverage_items where present group by state$q$, 'scholarships/coverage'),
 ('sch', 30, 'recovery', 'Source recovery', 'in_flight', 'Missing sources recovered from stored records.', 'sch_source_recovery', null, 'scholarships/coverage'),
 ('sch', 40, 'listing', 'Listing traversal', 'in_flight', 'Listing pages followed.', 'sch_listing_traversal', null, 'layer2/scholarships'),
 ('sch', 50, 'matching', 'Candidate matching', 'in_flight', 'Candidates matched to providers.', 'sch_candidate_matching', null, 'layer2/scholarships'),
 ('sch', 60, 'reading', 'Reading', 'in_flight', 'Scholarship pages read.', 'sch_reading', null, 'layer2/scholarships'),
 ('sch', 70, 'eligibility', 'Eligibility validation', 'in_flight', 'Read pages validated as scholarships with the right audience.', 'sch_eligibility', null, 'layer2/scholarships'),
 ('sch', 80, 'layer4', 'Layer 4 where required', 'human_review', 'Held for a person.', 'sch_layer4', null, 'layer4/inbox?kind=held_scholarship'),
 ('sch', 90, 'admission', 'Admission', 'admitted', 'Scholarships admitted.', 'sch_admission', null, 'scholarships/list'),
 ('sch', 100, 'publication', 'Publication', 'published', 'Scholarships published.', 'sch_publication', null, 'scholarships/list'),
 -- discovery, links, rankings
 ('disc', 10, 'search', 'Course link search, by state', 'queued', 'Course link searches: queued, found, verified, none.', null,
  $q$select state as reason, count(*) as n, null::timestamptz as oldest, null::bigint as gain from pipeline.course_link_search group by state$q$, 'layer2/sources'),
 ('disc', 20, 'human', 'Waiting for a person (official course link)', 'human_review', 'Layer 4 official course link items pending a decision (gain: decided in the window).', null,
  $q$select count(*) filter (where status = 'pending') as n, min(created_at) filter (where status = 'pending') as oldest, count(*) filter (where decided_at > now() - {window}) as gain from pipeline.layer4_review_items where field_code = 'official_course_url'$q$, 'layer4/inbox?kind=course_link'),
 ('disc', 25, 'readiness', 'Pending items, by readiness', 'review_ready', 'Pending official course link items by readiness: judgement ready, resolvable, technical blocked.', null,
  $q$select readiness as reason, count(*) as n, min(item_created_at) as oldest, null::bigint as gain from pipeline.layer4_item_readiness where item_status = 'pending' and field_code in ('official_course_url') group by readiness$q$, 'layer4/inbox?kind=course_link'),
 ('disc', 30, 'links', 'Course links held', 'published', 'Course links in the catalogue (gain: created in the window).', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where created_at > now() - {window}) as gain from catalogue.course_links$q$, 'courses'),
 ('disc', 40, 'rankings', 'Published provider rankings', 'published', 'Provider ranking rows in the catalogue. Zero here is a measured zero; the reason (no approved import, display switch off) is on Rankings and statistics.', null,
  $q$select count(*) as n, null::timestamptz as oldest, count(*) filter (where verified_at > now() - {window}) as gain from catalogue.provider_rankings$q$, 'rankings/datasets')
on conflict (lane, key) do nothing;

-- 8. job lane-funnel (G1: catalogued first), register ---------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('lane-funnel', 'Reports', 62, 'Lane funnels: count the stages of every lane',
  'Each minute: counts the stages of each autonomous lane (intakes, fees, English, descriptions, entry requirements, scholarships, discovery, integrity) whose last count is older than Pipeline settings > Lane funnels > count each stage again after, one stage at a time within a time limit, and keeps the figures for Layer 2/3 > Operations. Records only: no credit, no API call, no change to any catalogue value. A stage that cannot be counted shows unknown.',
  5, false, null)
on conflict (jobname) do nothing;

do $sched$
begin
  if to_regnamespace('cron') is not null then
    perform cron.schedule('lane-funnel', '* * * * *', 'select security.lane_funnel_refresh_v1()');
  end if;
end $sched$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'lane-funnel', 'Platform', 'Reports', 'OPS/UI: counts the stages of every autonomous lane for Layer 2/3 > Operations (records only)', 'active', '{}', '20261108170000'),
 ('table', 'pipeline.lane_funnel_lanes', 'Platform', 'Reports', 'OPS/UI: the lanes shown on Operations, their jobs, switches, settings prefixes and budget group', 'active', '{}', '20261108170000'),
 ('table', 'pipeline.lane_funnel_stages', 'Platform', 'Reports', 'OPS/UI: the stages of each lane (a progress transition or one read-only SELECT)', 'active', '{}', '20261108170000'),
 ('table', 'pipeline.lane_funnel_readings', 'Platform', 'Reports', 'OPS/UI: the latest counted figure of each SELECT stage', 'active', '{}', '20261108170000'),
 ('table', 'pipeline.lane_funnel_history', 'Platform', 'Reports', 'OPS/UI: trend points of each stage', 'active', '{}', '20261108170000')
on conflict do nothing;

-- 9. first count now (the job repeats it) and post-check ----------------------------------------------------------------------------------------------
do $post$
declare v_lanes int; v_stages int; v_unsafe int;
begin
  select count(*) into v_lanes from pipeline.lane_funnel_lanes;
  select count(*) into v_stages from pipeline.lane_funnel_stages;
  if v_lanes < 9 or v_stages < 40 then raise exception 'lane funnels post-check: % lanes, % stages', v_lanes, v_stages; end if;
  -- every SELECT stage passes the evaluator's own gate (a keyword or a semicolon in a stage is refused before the first count)
  select count(*) into v_unsafe from pipeline.lane_funnel_stages s
   where s.count_sql is not null and (s.count_sql !~* '^\s*(select|with)\s' or position(';' in s.count_sql) > 0
         or s.count_sql ~* '\m(insert|update|delete|truncate|drop|alter|create|grant|revoke|copy|call|execute|pg_sleep|set_config|dblink|lo_import)\M');
  if v_unsafe > 0 then raise exception 'lane funnels post-check: % stage(s) are not a single read-only SELECT', v_unsafe; end if;
  if to_regnamespace('cron') is not null and not exists (select 1 from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname = 'lane-funnel') then
    raise exception 'lane funnels post-check: job lane-funnel is not scheduled and catalogued';
  end if;
  raise notice 'lane funnels: % lanes, % stages', v_lanes, v_stages;
end $post$;
