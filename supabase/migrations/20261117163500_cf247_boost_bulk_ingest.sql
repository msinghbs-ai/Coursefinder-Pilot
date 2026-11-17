-- CF-247 S1-Build (Platform Admin 17 Nov 2026 16:15): the Boost bulk ingestion lane worker-boost-bulk-ingest.
-- What it does, every 5 minutes inside the overnight window only: the edge function worker-boost-bulk-ingest reads the Boost result files
-- the Boost Worker wrote to Storage staging-boost/inbound/, loads their rows into pipeline.boost_inbound_staging (each file once, recorded in
-- pipeline.boost_ingest_files), and settles each loaded batch with security.boost_promote_v1 (admin repo sql/boost-ingestion/002).
-- Promotion admits only study_load answers from a (lane, provider, model) the Platform Admin has put in pipeline.boost_model_qualifications,
-- only where the course has none and no manual lock, without touching updated_at; every other row is kept as a shadow reading, proposed to its
-- lane's own rule, or refused. The qualification table is empty: until a Platform Admin adds a row, nothing reaches the catalogue.
-- When it runs (security.boost_ingest_gate_v1, every value a setting in section Boost):
--   boost.ingest_on is 1; Pipeline Maintenance Mode is off; Melbourne time is inside boost.ingest_window_start_minute to
--   boost.ingest_window_end_minute (01:05 to 04:50); not inside the blackout boost.ingest_blackout_start_epoch to boost.ingest_blackout_end_epoch
--   (Thu 19 Nov 2026 01:30 to 03:30 AEDT, the migration squash); housekeeping-daily is not running and started more than
--   boost.ingest_after_housekeeping_minutes ago; and, checked by the edge function before each file, no tick of PR 1 (rollup-scheduler),
--   PR 2 (admission-rule-runner a, b, c) or PR 3 (coverage-lane-dispatch a, b, c) holds its tick lock.
-- G1: the job is catalogued (area Boost) and registered. G2: window, blackout, sizes and the switch are settings; the job command has no number.
-- G3: no consumer API object is read for structure or changed (study_load is an API v3 column, written only where null, Decision 277).
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

-- 1. Settings (section Boost)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'boost.quiet_window_start_hour', 'Boost promotion: quiet window starts (Melbourne hour)', 'Boost rows are promoted only from this hour (Melbourne time).',
   'number', to_jsonb(1), 0, 23, 'hour', 900, 'Boost', 'security.boost_promote_v1', 'CF-247 Boost, Platform Admin 16 Nov 2026 20:31 (01:00-05:00 AEDT)'),
  ('pipeline', 'boost.quiet_window_end_hour', 'Boost promotion: quiet window ends (Melbourne hour)', 'Boost rows are promoted only before this hour (Melbourne time).',
   'number', to_jsonb(5), 1, 24, 'hour', 901, 'Boost', 'security.boost_promote_v1', 'CF-247 Boost, Platform Admin 16 Nov 2026 20:31 (01:00-05:00 AEDT)'),
  ('pipeline', 'boost.promote_rows_per_run', 'Boost promotion: rows per run', 'Rows one promotion run settles, in one transaction.',
   'number', to_jsonb(1000), 1, 5000, 'rows', 902, 'Boost', 'security.boost_promote_v1', 'CF-247 Boost: 1,000 rows in one transaction under 5 s (test project, run 44019730363)'),
  ('pipeline', 'boost.ingest_on', 'Boost ingestion: on', 'Switches the job worker-boost-bulk-ingest on (1) or off (0). Off stops it at its next run.',
   'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 903, 'Boost', 'security.boost_ingest_gate_v1 (job worker-boost-bulk-ingest)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 16:15'),
  ('pipeline', 'boost.ingest_window_start_minute', 'Boost ingestion: window starts (Melbourne minute of the day)', 'The job runs only from this minute of the day, Melbourne time (65 is 01:05).',
   'number', to_jsonb(65), 0, 1439, 'minute of the day', 904, 'Boost', 'security.boost_ingest_gate_v1 (job worker-boost-bulk-ingest)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 16:15 (01:05-04:50 AEDT)'),
  ('pipeline', 'boost.ingest_window_end_minute', 'Boost ingestion: window ends (Melbourne minute of the day)', 'The job runs only before this minute of the day, Melbourne time (290 is 04:50).',
   'number', to_jsonb(290), 1, 1440, 'minute of the day', 905, 'Boost', 'security.boost_ingest_gate_v1 (job worker-boost-bulk-ingest)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 16:15 (01:05-04:50 AEDT)'),
  ('pipeline', 'boost.ingest_blackout_start_epoch', 'Boost ingestion: blackout starts (Unix time)', 'No ingestion from this moment (seconds since 1970, UTC). Set for the migration squash: Thu 19 Nov 2026 01:30 AEDT.',
   'number', to_jsonb(1795012200), 0, 4102444800, 'Unix seconds', 906, 'Boost', 'security.boost_ingest_gate_v1 (job worker-boost-bulk-ingest)', 'CF-247 S1-Build: migration squash Thu 19 Nov 2026 01:30-03:30 AEDT'),
  ('pipeline', 'boost.ingest_blackout_end_epoch', 'Boost ingestion: blackout ends (Unix time)', 'Ingestion may run again from this moment (seconds since 1970, UTC). Set for the migration squash: Thu 19 Nov 2026 03:30 AEDT.',
   'number', to_jsonb(1795019400), 0, 4102444800, 'Unix seconds', 907, 'Boost', 'security.boost_ingest_gate_v1 (job worker-boost-bulk-ingest)', 'CF-247 S1-Build: migration squash Thu 19 Nov 2026 01:30-03:30 AEDT'),
  ('pipeline', 'boost.ingest_after_housekeeping_minutes', 'Boost ingestion: quiet minutes after housekeeping starts', 'No ingestion while housekeeping-daily runs, nor for this many minutes after it starts.',
   'number', to_jsonb(20), 0, 240, 'minutes', 908, 'Boost', 'security.boost_ingest_gate_v1 (job worker-boost-bulk-ingest)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 16:15 (housekeeping-daily about 03:47 AEDT)'),
  ('pipeline', 'boost.ingest_files_per_run', 'Boost ingestion: files per run', 'Result files one run of worker-boost-bulk-ingest loads.',
   'number', to_jsonb(4), 1, 50, 'files', 909, 'Boost', 'worker-boost-bulk-ingest (through security.boost_ingest_gate_v1)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 16:15'),
  ('pipeline', 'boost.ingest_rows_per_call', 'Boost ingestion: rows per load call', 'Rows sent to the database in one call while a file is loaded.',
   'number', to_jsonb(500), 50, 2000, 'rows', 910, 'Boost', 'worker-boost-bulk-ingest (through security.boost_ingest_gate_v1)', 'CF-247 S1-Build, Platform Admin 17 Nov 2026 16:15')
on conflict (toolset_key, key) do nothing;

-- 2. The promotion function (admin repo sql/boost-ingestion/002, unchanged)
create or replace function security.boost_promote_v1(p_batch text, p_dry boolean default true, p_now timestamptz default now())
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_start int := security.pipeline_num_v1('boost.quiet_window_start_hour', 1)::int;
  v_end   int := security.pipeline_num_v1('boost.quiet_window_end_hour', 5)::int;
  v_rows  int := security.pipeline_num_v1('boost.promote_rows_per_run', 1000)::int;
  v_hour  int := extract(hour from (p_now at time zone 'Australia/Melbourne'))::int;
  v_out   jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and security.current_role_rank() < 6 then
    raise exception 'Platform Admin or service role required';
  end if;
  if not p_dry and not (v_hour >= v_start and v_hour < v_end) then
    raise exception 'outside the Boost quiet window (% to % Melbourne time; now %)', v_start, v_end, v_hour;
  end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_promote'));

  create temp table if not exists cf_boost_plan (id bigint primary key, lane text, entity_id uuid, evidence_id uuid, answer jsonb,
    state text, note text) on commit drop;
  truncate cf_boost_plan;

  insert into cf_boost_plan (id, lane, entity_id, evidence_id, answer, state, note)
  select s.id, s.lane, s.entity_id, s.evidence_id, s.answer,
    case
      when s.worker_status <> 'verified' then 'refused'
      when s.lane = 'aer_entry' then 'shadow'
      when q.model is null then 'shadow'
      when s.lane = 'study_load' and (c.study_load is not null
           or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.entity_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')))
        then 'refused'
      when s.lane = 'study_load' and s.answer->>'study_load' is null then 'refused'
      when s.lane = 'study_load' then 'admitted'
      else 'proposed' end,
    case
      when s.worker_status <> 'verified' then 'worker: ' || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(s.verdict->'problems') x), s.worker_status)
      when s.lane = 'aer_entry' then 'AER shadow reading (admitted only by the AER rule after qualification)'
      when q.model is null then 'model not qualified for this lane: ' || coalesce(s.provider, '?') || ' / ' || coalesce(s.model, '?')
      when s.lane = 'study_load' and c.study_load is not null then 'course already holds a study load'
      when s.lane = 'study_load' and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = s.entity_id
           and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')) then 'a manual lock holds this course''s study load'
      when s.lane = 'study_load' and s.answer->>'study_load' is null then 'page does not state a study load'
      when s.lane = 'study_load' then null
      when s.lane = 'provider_accreditations' then 'check against the body''s official list (D-3, PR C)'
      else 'for the lane''s own admission rule' end
  from pipeline.boost_inbound_staging s
  left join pipeline.boost_model_qualifications q on q.lane = s.lane and q.provider = s.provider and q.model = s.model
  left join catalogue.courses c on s.lane = 'study_load' and c.id = s.entity_id
  where s.batch_id = p_batch and s.promotion_state = 'staged'
  order by s.id
  limit v_rows;

  if not p_dry then
    -- study_load: only where null, one row per course (the earliest verified row of the batch), updated_at not touched
    update catalogue.courses c
       set study_load = p.answer->>'study_load', study_load_source = 'provider_page', study_load_evidence_id = p.evidence_id
      from (select distinct on (entity_id) * from cf_boost_plan where state = 'admitted' order by entity_id, id) p
     where c.id = p.entity_id and c.study_load is null;
    update pipeline.boost_inbound_staging s set promotion_state = p.state, promotion_note = p.note, promoted_at = p_now
      from cf_boost_plan p where s.id = p.id;
  end if;

  select jsonb_build_object('batch', p_batch, 'dry', p_dry, 'melbourne_hour', v_hour, 'window', jsonb_build_array(v_start, v_end),
           'rows', coalesce(sum(n), 0), 'by_state', coalesce(jsonb_object_agg(state, n) filter (where state is not null), '{}'::jsonb))
    into v_out
    from (select state, count(*) n from cf_boost_plan group by state) x;
  return v_out;
end $function$;
revoke all on function security.boost_promote_v1(text, boolean, timestamptz) from public, anon, authenticated;
comment on function security.boost_promote_v1(text, boolean, timestamptz) is
  'CF-247 Boost: settles staged Boost rows of one batch in one transaction (quiet window, settings boost.*). Admits only study_load from qualified models '
  'where the course has none and no manual lock; proposes the other lanes to their own rules; keeps AER and unqualified models as shadow readings.';

-- 3. The file ledger
create table if not exists pipeline.boost_ingest_files (
  path       text primary key,
  status     text not null default 'loading' check (status in ('loading', 'loaded', 'failed')),
  lines      int,
  loaded     int,
  batches    text[] not null default '{}',
  promoted   jsonb,
  error      text,
  claimed_at timestamptz not null default now(),
  done_at    timestamptz
);
comment on table pipeline.boost_ingest_files is 'CF-247 Boost (Platform Admin 17 Nov 2026 16:15): one row per result file of Storage staging-boost/inbound/ that worker-boost-bulk-ingest claimed, with what it loaded and how each batch was settled. A file is loaded once; a failed file stays failed until a person clears its row.';
alter table pipeline.boost_ingest_files enable row level security;
revoke all on pipeline.boost_ingest_files from anon, authenticated;

-- 4. The gate
create or replace function security.boost_ingest_gate_v1(p_check_locks boolean default true, p_now timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v_min  int := (extract(hour from (p_now at time zone 'Australia/Melbourne')) * 60 + extract(minute from (p_now at time zone 'Australia/Melbourne')))::int;
  v_from int := security.pipeline_num_v1('boost.ingest_window_start_minute', 65)::int;
  v_to   int := security.pipeline_num_v1('boost.ingest_window_end_minute', 290)::int;
  v_bs   numeric := security.pipeline_num_v1('boost.ingest_blackout_start_epoch', 1795012200);
  v_be   numeric := security.pipeline_num_v1('boost.ingest_blackout_end_epoch', 1795019400);
  v_hk   int := security.pipeline_num_v1('boost.ingest_after_housekeeping_minutes', 20)::int;
  v_hk_start timestamptz; v_hk_running boolean;
  v_held text[];
  v_settings jsonb := jsonb_build_object('files_per_run', security.pipeline_num_v1('boost.ingest_files_per_run', 4)::int,
                                         'rows_per_call', security.pipeline_num_v1('boost.ingest_rows_per_call', 500)::int);
begin
  if security.pipeline_num_v1('boost.ingest_on', 1) < 1 then return jsonb_build_object('ok', false, 'reason', 'switched off (boost.ingest_on)'); end if;
  if security.maintenance_hold_v1() then return jsonb_build_object('ok', false, 'reason', 'Pipeline Maintenance Mode'); end if;
  if not (v_min >= v_from and v_min < v_to) then
    return jsonb_build_object('ok', false, 'reason', 'outside the window', 'melbourne_minute', v_min, 'window', jsonb_build_array(v_from, v_to));
  end if;
  if extract(epoch from p_now) >= v_bs and extract(epoch from p_now) < v_be then
    return jsonb_build_object('ok', false, 'reason', 'blackout (migration squash)');
  end if;
  select max(d.start_time), bool_or(d.status = 'running') into v_hk_start, v_hk_running
    from cron.job_run_details d join cron.job j on j.jobid = d.jobid
   where j.jobname = 'housekeeping-daily' and d.start_time > p_now - interval '1 day';  -- fixed: the look-back for the daily job's last start
  if coalesce(v_hk_running, false) or (v_hk_start is not null and v_hk_start > p_now - make_interval(mins => v_hk)) then
    return jsonb_build_object('ok', false, 'reason', 'housekeeping-daily running or just started', 'housekeeping_started', v_hk_start);
  end if;
  if p_check_locks then
    -- the tick locks of PR 1, PR 2 and PR 3 (session advisory locks taken by their ticks)
    select array_agg(k.name) into v_held
      from (values ('rollup-scheduler', 'cf247:rollup_tick'),
                   ('admission-rule-runner', 'cf247:admission_tick:a'), ('admission-rule-runner-b', 'cf247:admission_tick:b'), ('admission-rule-runner-c', 'cf247:admission_tick:c'),
                   ('coverage-lane-dispatch', 'cf247:coverage_lane_tick:a'), ('coverage-lane-dispatch-b', 'cf247:coverage_lane_tick:b'), ('coverage-lane-dispatch-c', 'cf247:coverage_lane_tick:c')) k(name, lock_key)
     where exists (select 1 from pg_catalog.pg_locks l
                    where l.locktype = 'advisory' and l.granted and l.objsubid = 1
                      and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext(k.lock_key)::bigint);
    if v_held is not null then return jsonb_build_object('ok', false, 'reason', 'a dispatcher tick is running', 'held', to_jsonb(v_held), 'settings', v_settings); end if;
  end if;
  return jsonb_build_object('ok', true, 'melbourne_minute', v_min, 'settings', v_settings);
end $function$;
revoke all on function security.boost_ingest_gate_v1(boolean, timestamptz) from public, anon, authenticated;
comment on function security.boost_ingest_gate_v1(boolean, timestamptz) is 'CF-247 Boost (Platform Admin 17 Nov 2026 16:15): whether worker-boost-bulk-ingest may run now: switch, Maintenance Mode, the Melbourne window, the squash blackout, housekeeping-daily, and (p_check_locks) the PR 1, PR 2 and PR 3 tick locks. Returns the run settings.';

-- 5. Service-role calls of the edge function
create or replace function public.svc_boost_ingest_gate()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_ingest_gate_v1(true);
end $function$;

create or replace function public.svc_boost_ingest_claim(p_paths text[])
returns text[] language plpgsql security definer set search_path to '' as $function$
declare v text[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- only the files this call claims: new ones, and a claim left 'loading' by a run that stopped (taken again after an hour)
  with stale as (update pipeline.boost_ingest_files set claimed_at = now()
                  where path = any (p_paths) and status = 'loading' and claimed_at < now() - interval '1 hour'  -- fixed: stale-claim timer
                  returning path),
       ins as (insert into pipeline.boost_ingest_files (path) select x from unnest(p_paths) x on conflict (path) do nothing returning path)
  select coalesce(array_agg(path order by path), '{}') into v from (select path from stale union select path from ins) z;
  return v;
end $function$;

create or replace function public.svc_boost_inbound_load(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_lines int; v_loaded int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select count(*) into v_lines from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb));
  with ins as (
    insert into pipeline.boost_inbound_staging (batch_id, item_key, lane, entity, entity_id, evidence_id, source_url, provider, model, prompt_id, prompt_version,
      prompt_sha256, selector, answer, verdict, worker_status, attempts, worker_at)
    select j->>'batch_id', j->>'item_key', j->>'lane', j->>'entity', (j->>'entity_id')::uuid, nullif(j->>'evidence_id', '')::uuid, j->>'source_url',
           j->>'provider', j->>'model', j->>'prompt_id', j->>'prompt_version', j->>'prompt_sha256', j->>'selector', j->'answer', j->'verdict', j->>'status',
           coalesce(j->'attempts', '[]'::jsonb), (j->>'at')::timestamptz
      from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) j where j->>'kind' = 'result'
    on conflict (batch_id, item_key) do nothing
    returning 1)
  select count(*) into v_loaded from ins;
  return jsonb_build_object('lines', v_lines, 'loaded', v_loaded);
end $function$;

create or replace function public.svc_boost_ingest_done(p_path text, p_lines int, p_loaded int, p_batches text[], p_promoted jsonb, p_error text)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.boost_ingest_files
     set status = case when p_error is null then 'loaded' else 'failed' end, lines = p_lines, loaded = p_loaded,
         batches = coalesce(p_batches, '{}'), promoted = p_promoted, error = p_error, done_at = now()
   where path = p_path;
end $function$;

create or replace function public.svc_boost_promote(p_batch text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_promote_v1(p_batch, false);
end $function$;

revoke all on function public.svc_boost_ingest_gate(), public.svc_boost_ingest_claim(text[]), public.svc_boost_inbound_load(jsonb),
  public.svc_boost_ingest_done(text, int, int, text[], jsonb, text), public.svc_boost_promote(text) from public, anon, authenticated;
grant execute on function public.svc_boost_ingest_gate(), public.svc_boost_ingest_claim(text[]), public.svc_boost_inbound_load(jsonb),
  public.svc_boost_ingest_done(text, int, int, text[], jsonb, text), public.svc_boost_promote(text) to service_role;

-- 6. The job (G1): every 5 minutes; it calls the edge function only when the gate (without the tick locks, which the function waits for) allows
insert into pipeline.pilot_nonce_functions (function_name, note)
select 'worker-boost-bulk-ingest', 'CF-247 Boost bulk ingestion (Platform Admin 17 Nov 2026 16:15): loads staging-boost/inbound result files and settles them'
where not exists (select 1 from pipeline.pilot_nonce_functions where function_name = 'worker-boost-bulk-ingest');

insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('worker-boost-bulk-ingest', 'Boost', 10, 'Boost bulk ingestion (overnight)',
  'Every 5 minutes, only inside the overnight window on Settings > Pipeline settings > Boost (01:05 to 04:50 Melbourne), not during the migration squash blackout, not while housekeeping-daily runs or just after it starts, and only when no PR 1, PR 2 or PR 3 tick holds its lock: loads the Boost result files from Storage staging-boost/inbound (each once) and settles them. Only qualified models are admitted, study load only, where the course has none.', 6, false)
on conflict (jobname) do nothing;

select cron.schedule('worker-boost-bulk-ingest', '*/5 * * * *',
  'select pipeline.svc_pilot_submit_nonce(''worker-boost-bulk-ingest'', jsonb_build_object(''mode'', ''boost_ingest'')) where (security.boost_ingest_gate_v1(false)->>''ok'')::boolean')
where not exists (select 1 from cron.job where jobname = 'worker-boost-bulk-ingest');

-- 7. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'worker-boost-bulk-ingest', 'Layer 2', 'Boost', 'Overnight Boost bulk ingestion: loads staging-boost/inbound result files and settles them', 'active', '{}', '20261117163500'),
  ('edge_function', 'worker-boost-bulk-ingest', 'Layer 2', 'Boost', 'Reads staging-boost/inbound result files, loads them and settles each batch', 'active', '{}', '20261117163500'),
  ('table', 'pipeline.boost_ingest_files', 'Layer 2', 'Boost', 'Boost result files loaded by worker-boost-bulk-ingest', 'active', '{}', '20261117163500'),
  ('function', 'security.boost_promote_v1', 'Layer 2', 'Boost', 'Settles staged Boost rows of one batch (qualified study load only)', 'active', '{}', '20261117163500'),
  ('function', 'security.boost_ingest_gate_v1', 'Layer 2', 'Boost', 'Whether Boost ingestion may run now', 'active', '{}', '20261117163500')
on conflict do nothing;

-- 8. Post-checks
do $c$
begin
  if not exists (select 1 from cron.job where jobname = 'worker-boost-bulk-ingest' and active and command like '%boost_ingest_gate_v1(false)%') then raise exception 'post-check: the job is not as designed'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'worker-boost-bulk-ingest') then raise exception 'post-check: the job is not catalogued'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'boost.%') < 11 then raise exception 'post-check: Boost settings missing'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'; end if;
  if not (select relrowsecurity from pg_class where oid = 'pipeline.boost_ingest_files'::regclass) then raise exception 'post-check: row-level security is off'; end if;
  if has_function_privilege('anon', 'public.svc_boost_inbound_load(jsonb)', 'execute') or has_function_privilege('authenticated', 'public.svc_boost_promote(text)', 'execute') then
    raise exception 'post-check: a Boost service function is open to anon or authenticated';
  end if;
end $c$;
