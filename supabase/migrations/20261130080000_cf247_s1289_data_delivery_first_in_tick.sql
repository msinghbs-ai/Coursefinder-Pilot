-- CF-247 s1289 (S1-Build; SS-Programme-Control 27 Nov 2026 06:46 AEDT, "Production reliability and consumer integrity", items 3 and 4, read-back of s1287).
-- Read live 27 Nov 2026 06:48 AEDT (rolled-back read-back): data-delivery (security.data_delivery_refresh_v1, the Data Delivery screen's background counts; not a
-- consumer API object) has not run since 01:59 AEDT: 11 runs and 341 deferrals since 00:52, against 325 runs and 29 deferrals over the same span before.
-- Cause: one run at 01:15 AEDT took 103.5 s, so its estimate (the 14-day longest run, rollup.keep_days) is above rollup.tick_finish_by_seconds (100). A
-- target estimated past the finish time runs only as the first target of a tick, and admin-read-snapshots is always first in the every-minute priority 10
-- group, so data-delivery would stay starved until that run leaves the 14-day window (the s1287 mechanism; s1287 did not set the estimate).
-- Change (data only, as s1287): data-delivery moves to priority 9, ahead of the every-minute group and behind the starved targets s1287 placed at 3 to 5, so it
-- runs first in every minute where none of them is due (about two minutes in three) and they keep their slots. The dispatcher function is not changed.
-- G1: no job. G2: priority is the target's own schedule data (fixed). G3: 75/48 checked. Locks checked. Nothing dropped or deleted.
-- Replaces: the priority of rollup target data-delivery (10). Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the target update

create temp table s1289_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before;
create temp table s1289_cron on commit drop as select jobid from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'data-delivery' and rollup_group = 'A' and priority = 10 and mode = 'live' and enabled) then
    raise exception 'guard: data-delivery is not the live priority 10 target read on 27 Nov 2026';
  end if;
  if exists (select 1 from pipeline.rollup_targets where rollup_group = 'A' and enabled and priority between 6 and 9) then raise exception 'guard: another target already holds priority 6 to 9'; end if;
end $g$;

update pipeline.rollup_targets
   set priority = 9,  -- fixed: the target's order in its group, as its own schedule (ahead of the every-minute group, behind priorities 3 to 5)
       updated_at = now(),
       note = coalesce(note, '') || ' | 27 Nov 2026 (20261130080000, s1289): priority 9; a 103.5 s run put its 14-day estimate past the tick finish time, so as the second target of every tick it never ran'
 where target_code = 'data-delivery' and rollup_group = 'A';

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1289_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: active cron jobs above 140'; end if;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'data-delivery' and priority = 9 and mode = 'live' and enabled) then raise exception 'post-check: data-delivery is not priority 9'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1289_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
