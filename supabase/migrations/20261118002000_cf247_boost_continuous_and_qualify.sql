-- CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 22:50, directive "Remove artificial locks and run Boost continuously now", items 1 to 3; and
-- 22:48 item 2).
-- What it does:
--   1. Boost runs all day. The overnight window of the Boost gate and the quiet window of Boost promotion are opened to the whole day by their
--      settings (boost.ingest_window_start_minute 0, boost.ingest_window_end_minute 1440, boost.quiet_window_start_hour 0,
--      boost.quiet_window_end_hour 24). No function changes. What still holds Boost: the switches, Pipeline Maintenance Mode, the migration
--      squash blackout, housekeeping-daily and the dispatcher locks.
--   2. The squash blackout starts at the migration freeze: Thu 19 Nov 2026 01:15 Melbourne (was 01:30); it ends 03:30 as before.
--   3. Qwen3 30B is qualified for the study_load lane (pipeline.boost_model_qualifications): from now security.boost_promote_v1 admits its
--      verified, stated study loads where the course has none. A course that holds a study load, a manual lock, an unverified answer and a
--      "not stated" answer are refused as before; updated_at is not touched. Rows of this model already staged as shadow are settled again.
--   4. Throughput: job boost-extract runs every minute with 40 courses a run (it was every 5 minutes with 20), job worker-boost-bulk-ingest every
--      2 minutes with up to 10 files a run, and the route boost_extract may spend US$3 and make 5,000 calls a day (was US$1 and 1,500).
-- What it does not do: it does not send refused rows to Layer 4, and it reads no lane other than study_load (both are in the admin current state
-- as open decisions). No function is created or replaced.
-- G1: no new job. G2: every value changed is a setting or the route's own cap; the job commands hold no number. G3: no consumer API object is
-- changed (catalogue.courses.study_load is filled only where it is empty).
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('security.boost_on_demand_v1(timestamptz)') is null then raise exception 'migration 20261118000100 (promotion held in the squash blackout) is not applied'; end if;
  if not exists (select 1 from pipeline.ai_model_catalogue where code = 'qwen3-30b' and status = 'allowed' and model_identifier = 'qwen/qwen3-30b-a3b-instruct-2507') then
    raise exception 'qwen3-30b is not the allowed model qwen/qwen3-30b-a3b-instruct-2507';
  end if;
  if (select cascade from pipeline.ai_service_routes where service_code = 'boost_extract') is distinct from array['qwen3-30b'] then
    raise exception 'the route boost_extract is not pinned to qwen3-30b';
  end if;
end $pre$;

-- 1. and 2. All day, and the blackout from the freeze
update pipeline.platform_toolset_settings s set value = v.value, reason = 'CF-247 Boost, Platform Admin 17 Nov 2026 22:50: Boost runs all day; only the squash blackout and housekeeping-daily hold it', updated_at = now()
  from (values ('boost.ingest_window_start_minute', to_jsonb(0)), ('boost.ingest_window_end_minute', to_jsonb(1440)),
               ('boost.quiet_window_start_hour', to_jsonb(0)), ('boost.quiet_window_end_hour', to_jsonb(24))) v(key, value)
 where s.toolset_key = 'pipeline' and s.key = v.key;
update pipeline.platform_toolset_settings set value = to_jsonb(1795011300), updated_at = now(),
       reason = 'CF-247 Boost, Platform Admin 17 Nov 2026 22:50: the squash lock is the migration freeze, Thu 19 Nov 2026 01:15 to 03:30 Melbourne'
 where toolset_key = 'pipeline' and key = 'boost.ingest_blackout_start_epoch';

update pipeline.automation_catalogue set description =
  'Every 2 minutes, all day (Platform Admin 17 Nov 2026 22:50), not during the migration squash blackout, not while housekeeping-daily runs or just after it starts, and only when no PR 1, PR 2 or PR 3 tick holds its lock: loads the Boost result files from Storage staging-boost/inbound (each once) and settles them. Only qualified models are admitted, study load only, where the course has none.'
 where jobname = 'worker-boost-bulk-ingest';
update pipeline.automation_catalogue set description =
  'Every minute, all day (Platform Admin 17 Nov 2026 22:50), only when Boost extraction is switched on, not during the migration squash blackout and not beside housekeeping-daily: worker coverage-sweep reads stored course pages of courses with no study load, in the order of the Boost priority matrix, through the Models & services route Boost extraction, and writes result files to Storage staging-boost/inbound. A qualified model''s verified study loads are admitted where the course has none.'
 where jobname = 'boost-extract';

-- 4. Throughput
update pipeline.platform_toolset_settings s set value = v.value, reason = 'CF-247 Boost, Platform Admin 17 Nov 2026 22:50: clear the stored-page queue tonight', updated_at = now()
  from (values ('batch.boost_extract', to_jsonb(40)), ('boost.ingest_files_per_run', to_jsonb(10))) v(key, value)
 where s.toolset_key = 'pipeline' and s.key = v.key;
update pipeline.ai_service_routes set daily_usd_cap = 3, daily_calls_cap = 5000, changed_at = now(),
       reason = 'S2 - BOOST 17 Nov 2026 (Platform Admin 22:50: raise the daily cap so the stored-page queue clears tonight); pinned to qwen3-30b as before'
 where service_code = 'boost_extract';
select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), schedule := '* * * * *');
select cron.alter_job((select jobid from cron.job where jobname = 'worker-boost-bulk-ingest'), schedule := '*/2 * * * *');

-- 3. The qualification, and the rows already staged as shadow for this model
create temp table cf_boost_before on commit drop as
  select (select count(*) from catalogue.courses where study_load is not null) as held,
         (select count(*) from catalogue.courses where study_load is not null and study_load_source is distinct from 'provider_page') as held_other;

insert into pipeline.boost_model_qualifications (lane, provider, model, qualified_by, qualified_at, reason)
select 'study_load', 'openrouter', 'qwen/qwen3-30b-a3b-instruct-2507', null, now(),
       'Platform Admin 17 Nov 2026 22:50 ("Mark Qwen3 30B qualified now"): the central model, pinned on the route boost_extract, prompt boost-study-load-v1. Admission: verified answers only (value allowed, quote on the stored page, quote states the load), only where the course has no study load.'
where not exists (select 1 from pipeline.boost_model_qualifications q where q.lane = 'study_load' and q.provider = 'openrouter' and q.model = 'qwen/qwen3-30b-a3b-instruct-2507');

update pipeline.boost_inbound_staging s set promotion_state = 'staged', promotion_note = null, promoted_at = null
 where s.lane = 'study_load' and s.provider = 'openrouter' and s.model = 'qwen/qwen3-30b-a3b-instruct-2507'
   and s.promotion_state = 'shadow' and s.worker_status = 'verified' and s.batch_id like 'bx-%';

do $settle$
declare b text; v jsonb; v_rows int := 0;
begin
  for b in select distinct s.batch_id from pipeline.boost_inbound_staging s where s.promotion_state = 'staged' and s.batch_id like 'bx-%' order by 1 loop
    v := security.boost_promote_v1(b, false, now());
    v_rows := v_rows + coalesce((v->>'rows')::int, 0);
  end loop;
  raise notice 'settled % row(s) staged before the qualification', v_rows;
end $settle$;

-- 5. Post-checks
do $c$
declare v_before record; v_now_held int; v_filled int;
begin
  select * into v_before from cf_boost_before;
  if security.boost_ingest_gate_v1(false, '2026-11-18 12:00+11')->>'reason' in ('outside the window') or security.boost_extract_gate_v1(false, '2026-11-18 15:30+11')->>'reason' in ('outside the window') then
    raise exception 'post-check: a Boost gate is still closed by the window at midday';
  end if;
  if (security.boost_ingest_gate_v1(false, '2026-11-19 01:20+11')->>'ok')::boolean or (security.boost_extract_gate_v1(false, '2026-11-19 03:29+11')->>'ok')::boolean then
    raise exception 'post-check: a Boost gate is open inside the squash lock (Thu 01:15 to 03:30)';
  end if;
  begin
    perform security.boost_promote_v1('post-check-no-such-batch', false, '2026-11-19 01:20+11');
    raise exception 'post-check: promotion ran inside the squash lock';
  exception when others then if sqlerrm not like 'migration squash blackout%' then raise; end if;
  end;
  if (security.boost_promote_v1('post-check-no-such-batch', false, '2026-11-18 12:00+11')->>'rows')::int <> 0 then raise exception 'post-check: promotion at midday did not run cleanly'; end if;
  if (select count(*) from pipeline.boost_model_qualifications) <> 1
     or not exists (select 1 from pipeline.boost_model_qualifications where lane = 'study_load' and provider = 'openrouter' and model = 'qwen/qwen3-30b-a3b-instruct-2507') then
    raise exception 'post-check: the qualification is not exactly Qwen3 30B for study_load';
  end if;
  -- the non-overwrite rule: no course that held a study load changed, and every course filled is one an admitted row names, with the value it states
  select count(*) into v_now_held from catalogue.courses where study_load is not null;
  select count(distinct s.entity_id) into v_filled from pipeline.boost_inbound_staging s join catalogue.courses c on c.id = s.entity_id
   where s.promotion_state = 'admitted' and s.batch_id like 'bx-%' and c.study_load = s.answer->>'study_load' and c.study_load_source = 'provider_page';
  if (select count(*) from catalogue.courses where study_load is not null and study_load_source is distinct from 'provider_page') <> v_before.held_other then
    raise exception 'post-check: a study load that did not come from Boost changed';
  end if;
  if v_now_held - v_before.held > v_filled then raise exception 'post-check: % course(s) gained a study load but only % are named by an admitted row', v_now_held - v_before.held, v_filled; end if;
  if exists (select 1 from pipeline.boost_inbound_staging s where s.promotion_state = 'admitted' and (s.worker_status <> 'verified' or s.answer->>'study_load' is null)) then
    raise exception 'post-check: an unverified or empty answer was admitted';
  end if;
  if (select schedule from cron.job where jobname = 'boost-extract') <> '* * * * *' or (select schedule from cron.job where jobname = 'worker-boost-bulk-ingest') <> '*/2 * * * *' then
    raise exception 'post-check: the job schedules are not as set';
  end if;
  if exists (select 1 from cron.job where jobname in ('boost-extract', 'worker-boost-bulk-ingest') and (not active or command ~ '''limit'', [0-9]')) then
    raise exception 'post-check: a Boost job is inactive or holds a number';
  end if;
  if (select array[daily_usd_cap, daily_calls_cap] from pipeline.ai_service_routes where service_code = 'boost_extract') <> array[3, 5000]::numeric[] then raise exception 'post-check: the route caps are not as set'; end if;
end $c$;
