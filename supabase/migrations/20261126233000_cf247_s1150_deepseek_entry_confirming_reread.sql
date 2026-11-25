-- CF-247 s1150 (S1-Build / Release Controller; Platform Admin 25 Nov 2026 14:36 AEDT, Decision 1: "Run the single confirming re-read of
-- DeepSeek V4 Flash on the 83 benchmark pages using the live v1.0.44 selector (s1140)", about US$0.07).
-- Found live (rolled back, 25 Nov 2026 14:40 AEDT): qualification run s1125-entry-qualify-2026-11-25 is complete (332 of 332 cases, US$0.284).
-- DeepSeek V4 Flash met every criterion except no-loss: on 11 of its 83 pages the sections-first read found fewer label rows than the whole-page
-- read, all of them rows outside the lean-sections-v3/v4 selection. Selector lean-sections-v6 (s1140, worker v1.0.44) now holds 148 of the 152
-- earlier rows (the 4 outside: 3 that are not entry requirements, and one) and 62 of the 64 rows a person accepted.
-- What this does: seeds the existing qualification harness (job lean-qualify, pipeline.lean_qualify_cases, worker mode lean_qualify) with the
-- same 83 DeepSeek V4 Flash pages and labels under a new run label, so each page is read once more as a whole page and once as its selected
-- sections, under v6. The picker hands out the newest run first, under the entry route's key and balance holds and the existing per-run ceiling
-- reading.lean_qualify_ceiling_usd (US$2). Nothing is admitted, no route or qualification is changed, nothing is switched on.
-- G1: no job (the existing lean-qualify job reads it). G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged.
-- Replaces: nothing (the s1125 run stays as recorded; this is its confirming re-read).
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if exists (select 1 from pipeline.lean_qualify_cases where run_label = 's1125-entry-qualify-2026-11-25' and state = 'pending') then
    raise exception 'guard: the s1125 qualification run is not complete';
  end if;
end $g$;
create temp table s1150_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1150_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1150_route on commit drop as select enabled, daily_usd_cap, cascade from pipeline.ai_service_routes where service_code = 'course_entry_requirements';

do $seed$
declare v_run constant text := 's1150-entry-qualify-deepseek-v6-2026-11-25'; v_from constant text := 's1125-entry-qualify-2026-11-25';
  v_model constant text := 'deepseek-v4-flash'; v_n int;
begin
  insert into pipeline.lean_qualify_cases (run_label, field, kind, source_ref, course_id, evidence_id, storage_path, gold, model_code, gold_source)
  select v_run, x.field, x.kind, x.source_ref, x.course_id, x.evidence_id, x.storage_path, x.gold, x.model_code, x.gold_source
    from pipeline.lean_qualify_cases x
   where x.run_label = v_from and x.field = 'entry_requirements' and x.model_code = v_model
  on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n <> 83 then raise exception 's1150: % DeepSeek V4 Flash pages, not the 83 benchmark pages', v_n; end if;  -- fixed: the benchmark's size
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'seed', 'pipeline.lean_qualify_cases', jsonb_build_object(
          'reason', 'Confirming re-read of DeepSeek V4 Flash on the 83 benchmark pages under lean-sections-v6 (Platform Admin 25 Nov 2026 14:36 AEDT, Decision 1)',
          'by', 'migration 20261126233000 (CF-247 s1150)', 'run', v_run, 'from_run', v_from, 'model', v_model, 'cases', v_n, 'estimate_usd', 0.07), null);
  raise notice 's1150: % cases seeded', v_n;
end $seed$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1150_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1150_locks) then raise exception 'post-check: manual locks changed'; end if;
  if exists (select 1 from pipeline.ai_service_routes r, s1150_route b where r.service_code = 'course_entry_requirements'
              and (r.enabled is distinct from b.enabled or r.daily_usd_cap is distinct from b.daily_usd_cap or r.cascade is distinct from b.cascade)) then
    raise exception 'post-check: the course entry route changed';
  end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
