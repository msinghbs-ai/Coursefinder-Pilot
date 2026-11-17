-- CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 22:48: "Do not wait for the 01:05 AEDT scheduled window ... adjusting or bypassing the
-- 01:05-04:50 AEDT window gate for manual/on-demand runs while keeping Thursday's 01:15-03:30 AEDT squash lock intact").
-- What it does:
--   1. Setting boost.on_demand_until_epoch (Settings > Pipeline settings > Boost): until that time Boost extraction, Boost ingestion and Boost
--      promotion run outside the overnight window. It is set here to Wed 18 Nov 2026 01:05 Melbourne time, when the overnight window opens, so
--      Boost runs from this deploy until 04:50 without a gap. 0, or a time that has passed, means the window applies as before.
--   2. security.boost_ingest_gate_v1 (also the gate of job boost-extract, through security.boost_extract_gate_v1): the window check is skipped
--      while on demand. Its other checks are unchanged and still apply: the switch, Pipeline Maintenance Mode, the migration squash blackout,
--      housekeeping-daily and the dispatcher locks.
--   3. security.boost_promote_v1: the quiet-window check is skipped while on demand, and promotion is now also refused inside the migration
--      squash blackout whatever the window says. Nothing else in it changes (one admitted row per course; only where the course has no
--      study load; updated_at not touched).
-- It qualifies no model: until a model is qualified every row stays shadow. Both functions are replaced only if the live definitions are the
-- ones this change was written against.
-- G1: no new job. G2: the time is a setting. G3: no consumer API object is read or changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $g$
begin
  if md5(pg_get_functiondef('security.boost_ingest_gate_v1(boolean,timestamptz)'::regprocedure)) <> '9406870cde770d5e5b3be383a99aafd9' then
    raise exception 'security.boost_ingest_gate_v1 is not the definition of migration 20261117163500; re-read it before replacing';
  end if;
  if md5(pg_get_functiondef('security.boost_promote_v1(text,boolean,timestamptz)'::regprocedure)) <> 'c9239d35c718c69eff127c54a647594c' then
    raise exception 'security.boost_promote_v1 is not the definition of migration 20261117223000; re-read it before replacing';
  end if;
end $g$;

-- 1. The setting and its reader
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'boost.on_demand_until_epoch', 'Boost: run on demand until (Unix time, seconds)',
  'Until this time Boost extraction, ingestion and promotion run outside the overnight window. 0, or a time that has passed, means the overnight window applies. The migration squash blackout, Maintenance Mode and housekeeping-daily still hold Boost while on demand.',
  'number', to_jsonb(1794924300), 0, 4102444800, 'Unix seconds', 955, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:48 (on demand until the overnight window opens, Wed 18 Nov 2026 01:05 Melbourne)', 'Boost',
  'security.boost_on_demand_v1 (security.boost_ingest_gate_v1, security.boost_promote_v1)')
on conflict (toolset_key, key) do nothing;

create or replace function security.boost_on_demand_v1(p_now timestamptz default now())
returns boolean language sql stable security definer set search_path to '' as $function$
  select extract(epoch from p_now) < security.pipeline_num_v1('boost.on_demand_until_epoch', 0)
$function$;
revoke all on function security.boost_on_demand_v1(timestamptz) from public, anon, authenticated;
grant execute on function security.boost_on_demand_v1(timestamptz) to service_role;
comment on function security.boost_on_demand_v1(timestamptz) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 22:48): true while Boost runs on demand, that is before the time in setting boost.on_demand_until_epoch. The overnight window of the Boost gate and the quiet window of Boost promotion do not apply while it is true.';

-- 2. The gate
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
  -- on demand (setting boost.on_demand_until_epoch, Platform Admin 17 Nov 2026 22:48): until that time the overnight window does not apply; the
  -- squash blackout, Maintenance Mode, housekeeping-daily and the dispatcher locks below still do
  if not (v_min >= v_from and v_min < v_to) and not security.boost_on_demand_v1(p_now) then
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

-- 3. Promotion
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
  -- on demand (setting boost.on_demand_until_epoch, Platform Admin 17 Nov 2026 22:48): until that time the quiet window does not apply
  if not p_dry and not (v_hour >= v_start and v_hour < v_end) and not security.boost_on_demand_v1(p_now) then
    raise exception 'outside the Boost quiet window (% to % Melbourne time; now %)', v_start, v_end, v_hour;
  end if;
  -- the migration squash blackout holds promotion whatever the window or an on-demand run says
  if not p_dry and extract(epoch from p_now) >= security.pipeline_num_v1('boost.ingest_blackout_start_epoch', 0)
     and extract(epoch from p_now) < security.pipeline_num_v1('boost.ingest_blackout_end_epoch', 0) then
    raise exception 'migration squash blackout: Boost promotion is held';
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

  -- one admitted row per course and lane: the earliest of the batch; later rows for the same course are refused, so the admitted count is the
  -- number of courses filled (Platform Admin 17 Nov 2026 21:18)
  update cf_boost_plan p
     set state = 'refused', note = 'an earlier row of this batch fills this course''s study load'
   where p.state = 'admitted'
     and exists (select 1 from cf_boost_plan f where f.state = 'admitted' and f.lane = p.lane and f.entity_id = p.entity_id and f.id < p.id);

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

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.boost_on_demand_v1', 'Layer 2', 'Boost', 'Whether Boost runs on demand (outside the overnight window) now', 'active', '{}', '20261118000100')
on conflict do nothing;

-- 4. Post-checks
do $c$
declare v_until timestamptz := to_timestamp(security.pipeline_num_v1('boost.on_demand_until_epoch', 0));
begin
  if v_until <> '2026-11-18 01:05+11'::timestamptz then raise exception 'post-check: on demand does not end when the overnight window opens: %', v_until; end if;
  if not security.boost_on_demand_v1('2026-11-18 00:30+11') or security.boost_on_demand_v1('2026-11-18 01:05+11') or security.boost_on_demand_v1('2026-11-18 12:00+11') then
    raise exception 'post-check: on demand is not true before 01:05 and false from then on';
  end if;
  -- on demand: the window no longer closes the gate before 01:05; without it, midday is still outside the window
  if security.boost_ingest_gate_v1(false, '2026-11-18 00:30+11')->>'reason' = 'outside the window' then raise exception 'post-check: the gate still closes on the window while on demand'; end if;
  if security.boost_ingest_gate_v1(false, '2026-11-18 12:00+11')->>'reason' is distinct from 'outside the window'
     and security.boost_ingest_gate_v1(false, '2026-11-18 12:00+11')->>'reason' is distinct from 'Pipeline Maintenance Mode' then
    raise exception 'post-check: the gate is open at midday after on demand has ended: %', security.boost_ingest_gate_v1(false, '2026-11-18 12:00+11');
  end if;
  if (security.boost_ingest_gate_v1(false, '2026-11-19 01:45+11')->>'ok')::boolean or (security.boost_extract_gate_v1(false, '2026-11-19 01:45+11')->>'ok')::boolean then
    raise exception 'post-check: a Boost gate is open inside the squash blackout';
  end if;
  -- promotion: a real run is refused inside the squash blackout and outside the window once on demand has ended; a dry run is always allowed
  begin
    perform security.boost_promote_v1('post-check-no-such-batch', false, '2026-11-19 01:45+11');
    raise exception 'post-check: promotion ran inside the squash blackout';
  exception when others then if sqlerrm not like 'migration squash blackout%' then raise; end if;
  end;
  begin
    perform security.boost_promote_v1('post-check-no-such-batch', false, '2026-11-18 12:00+11');
    raise exception 'post-check: promotion ran outside the window after on demand ended';
  exception when others then if sqlerrm not like 'outside the Boost quiet window%' then raise; end if;
  end;
  if (security.boost_promote_v1('post-check-no-such-batch', false, '2026-11-18 00:30+11')->>'rows')::int <> 0 then raise exception 'post-check: promotion on demand did not run cleanly'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified by this change'; end if;
end $c$;
