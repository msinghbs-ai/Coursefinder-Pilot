-- CF-247 s1290 (S1-Build; Platform Admin decision D10, 27 Nov 2026: "Approve permanent fix", record coursefinder-admin #1207 comment 7203709925;
-- SS-Programme-Control 27 Nov 2026 08:28 AEDT).
-- security.rollup_tick_v1() existed only live (no migration held it). This file holds it in full, so the repository now carries the procedure. Captured live
-- 27 Nov 2026 08:40 AEDT: 2,795 characters, md5(pg_get_functiondef) 36a8d4f314788d4a292bac677b568858 (copy and replay in admin
-- docs/platform/2026-11-27-rollup-tick-v1-capture.md).
-- Problem: each target's estimate is its longest successful run in rollup.keep_days (14). One slow run holds a target out of every tick it is not first in
-- for 14 days (17,090 deferrals in 14 days; data-delivery starved from 01:59 to 07:04 on 27 Nov by one 103.5 s run).
-- Replay of the 61,944 successful runs held (14 days, 33 live targets): the 95th percentile plus 25% keeps every estimate under the 100 s finish time
-- (today five are 85 to 115 s); 0.5 to 2.4% of runs exceed it, and such a run only makes that one tick longer, as a first target already can.
-- The change (two parts, nothing else in the procedure changes):
--   1. Estimate: with at least rollup.estimate_min_runs successful runs, the rollup.estimate_percentile run time plus rollup.estimate_margin_percent, never
--      above the longest run; with fewer runs, the longest run, else expected_ms (the conservative estimate, as before).
--   2. Order: targets at or below rollup.protected_priority_max (the protected targets: the cost guard, the daily overview, the coverage build) keep running
--      first, in priority order. Next come targets due for longer than rollup.starved_after_minutes without running (starved), then the rest in priority order.
--      A starved target is still held by the 60 s budget and the 100 s finish rule when it is not first, so within a few minutes it runs first (bounded wait).
-- Kept: the 60 s tick budget, the 100 s finish rule, the one advisory tick lock (no overlapping ticks), the due-minute record before a live run, the commit
-- after each target, catch-up, shadow targets, the target priorities. No job, scheduler or cron row is created. The settings are new rows in the existing
-- Rollup scheduler section (G2). G3: 75/48 checked. Locks checked. Nothing dropped or deleted.
-- Rollback: rollup.estimate_min_runs at its maximum (500) and rollup.protected_priority_max 0 with rollup.starved_after_minutes 180 give back the old
-- estimate for every target and near-old order; or forward-fix by migration.
-- Replaces: security.rollup_tick_v1() (md5 36a8d4f3, live only). Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the procedure replace

create temp table s1290_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before;
create temp table s1290_cron on commit drop as select jobid from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if md5(pg_get_functiondef('security.rollup_tick_v1()'::regprocedure)) <> '36a8d4f314788d4a292bac677b568858' then raise exception 'guard: security.rollup_tick_v1 is not the procedure captured on 27 Nov 2026'; end if;
end $g$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values
  ('pipeline', 'rollup.estimate_percentile', 'Rollup estimate: run-time percentile',
   'Each target''s time estimate is this percentile of its successful runs in the history window (rollup.keep_days), plus the margin below. Used to decide whether the target still fits in the tick.',
   'number', to_jsonb(95), 50, 99, 'percent', 1825, 'Rollup scheduler', 'security.rollup_tick_v1 (rollup-scheduler)', 'CF-247 s1290 (Platform Admin D10, 27 Nov 2026)'),
  ('pipeline', 'rollup.estimate_margin_percent', 'Rollup estimate: safety margin',
   'Added to the percentile run time; the estimate is never above the target''s longest run.',
   'number', to_jsonb(25), 0, 100, 'percent', 1826, 'Rollup scheduler', 'security.rollup_tick_v1 (rollup-scheduler)', 'CF-247 s1290 (Platform Admin D10, 27 Nov 2026)'),
  ('pipeline', 'rollup.estimate_min_runs', 'Rollup estimate: runs needed for the percentile',
   'A target with fewer successful runs in the window is estimated by its longest run (or its expected time when it has none): the conservative estimate.',
   'number', to_jsonb(20), 1, 500, 'runs', 1827, 'Rollup scheduler', 'security.rollup_tick_v1 (rollup-scheduler)', 'CF-247 s1290 (Platform Admin D10, 27 Nov 2026)'),
  ('pipeline', 'rollup.starved_after_minutes', 'Rollup order: starved after',
   'A target due for longer than this without running goes ahead of the other unprotected targets in the next tick (it still keeps to the tick budget and finish time).',
   'number', to_jsonb(30), 5, 180, 'minutes', 1828, 'Rollup scheduler', 'security.rollup_tick_v1 (rollup-scheduler)', 'CF-247 s1290 (Platform Admin D10, 27 Nov 2026)'),
  ('pipeline', 'rollup.protected_priority_max', 'Rollup order: protected priorities',
   'Targets at or below this priority always run first in their due ticks, ahead of starved targets (the cost guard, the daily overview, the coverage build).',
   'number', to_jsonb(5), 0, 100, 'priority', 1829, 'Rollup scheduler', 'security.rollup_tick_v1 (rollup-scheduler)', 'CF-247 s1290 (Platform Admin D10, 27 Nov 2026)')
on conflict do nothing;

CREATE OR REPLACE PROCEDURE security.rollup_tick_v1()
 LANGUAGE plpgsql
AS $procedure$
declare v_t0 timestamptz := clock_timestamp(); v_tick timestamptz := date_trunc('minute', now()); v_budget int; v_finish int; v_keep int; v_back int;
        v_pct numeric; v_margin numeric; v_min_runs int; v_starve int; v_protect int;
        v_r record; v_el numeric; v_n int := 0;
begin
  if security.pipeline_num_v1('rollup.scheduler_on', 0) < 1 then return; end if;
  if not pg_try_advisory_lock(hashtext('cf247:rollup_tick')) then return; end if;  -- fixed: the one tick lock (a tick still running keeps the next one out)
  v_budget := security.pipeline_num_v1('rollup.tick_budget_seconds', 60)::int;
  v_finish := security.pipeline_num_v1('rollup.tick_finish_by_seconds', 100)::int;
  v_keep := security.pipeline_num_v1('rollup.keep_days', 14)::int;
  v_back := security.pipeline_num_v1('rollup.catch_up_minutes', 180)::int;
  v_pct := security.pipeline_num_v1('rollup.estimate_percentile', 95);  -- s1290
  v_margin := security.pipeline_num_v1('rollup.estimate_margin_percent', 25);
  v_min_runs := security.pipeline_num_v1('rollup.estimate_min_runs', 20)::int;
  v_starve := security.pipeline_num_v1('rollup.starved_after_minutes', 30)::int;
  v_protect := security.pipeline_num_v1('rollup.protected_priority_max', 5)::int;
  for v_r in
    select t.target_code, t.mode, d.due_at, d.n,
           case when t.mode = 'shadow' then 0
                when coalesce(e.runs, 0) < v_min_runs then coalesce(e.max_ms, t.expected_ms, 0)  -- s1290: too few runs, the conservative estimate
                else least(e.max_ms, e.p_ms * (1 + v_margin / 100.0)) end exp_ms
      from pipeline.rollup_targets t
      cross join lateral (
        select max(m) due_at, min(m) first_due, count(*) n
          from generate_series(greatest(coalesce(t.last_due_at + interval '1 minute', v_tick), v_tick - make_interval(mins => v_back)), v_tick, interval '1 minute') m
         where security.cron_matches_v1(t.schedule, m)) d
      left join lateral (
        select max(x.ms) max_ms, count(*) runs, percentile_cont(v_pct / 100.0) within group (order by x.ms) p_ms from pipeline.rollup_runs x
         where x.target_code = t.target_code and x.status = 'succeeded' and x.started_at > now() - make_interval(days => v_keep)) e on true
     where t.enabled and d.due_at is not null
     order by case when t.priority <= v_protect then 0 when d.first_due < v_tick - make_interval(mins => v_starve) then 1 else 2 end,  -- s1290: protected, then starved
              t.priority, d.due_at, t.target_code
  loop
    v_el := extract(epoch from clock_timestamp() - v_t0);
    if v_n > 0 and (v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish) then
      if v_r.mode = 'live' then
        insert into pipeline.rollup_runs(tick_at, target_code, mode, due_at, due_minutes, status)
        values (v_tick, v_r.target_code, 'live', v_r.due_at, v_r.n::int, 'deferred');
        commit;
      end if;
      continue;  -- stays due for the next tick
    end if;
    if v_r.mode = 'live' then  -- PR 1 fix (16 Nov 2026): the due minute is recorded before a live target runs, so a run cut off by the statement limit is not taken again before its next due minute
      update pipeline.rollup_targets set last_due_at = v_r.due_at, updated_at = now() where target_code = v_r.target_code;
      commit;
    end if;
    perform security.rollup_run_target_v1(v_r.target_code, v_tick, v_r.due_at, v_r.n::int);
    v_n := v_n + 1;
    commit;
  end loop;
  -- the run history is trimmed by housekeeping-daily (security.rollup_runs_trim_v1), not inside the tick
  perform pg_advisory_unlock(hashtext('cf247:rollup_tick'));  -- fixed: the one tick lock
end $procedure$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); d text := pg_get_functiondef('security.rollup_tick_v1()'::regprocedure);
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if position('pg_try_advisory_lock(hashtext(''cf247:rollup_tick''))' in d) = 0 or position('v_el > v_budget or v_el + v_r.exp_ms / 1000.0 > v_finish' in d) = 0
     or position('percentile_cont(v_pct / 100.0)' in d) = 0 then raise exception 'post-check: the procedure is not the s1290 text'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('rollup.estimate_percentile', 'rollup.estimate_margin_percent',
        'rollup.estimate_min_runs', 'rollup.starved_after_minutes', 'rollup.protected_priority_max')) <> 5 then raise exception 'post-check: a setting is missing'; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1290_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: active cron jobs above 140'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1290_guard) then raise exception 'post-check: manual locks changed'; end if;
  raise notice 's1290: rollup_tick_v1 md5 now %', md5(d);
end $c$;
