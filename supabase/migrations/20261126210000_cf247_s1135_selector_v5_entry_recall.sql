-- CF-247 s1135 (S1-Build / Integration Controller; Platform Admin 25 Nov 2026 12:01 AEDT, P0 AER preprocessing qualification: "Recover the five
-- genuine missed pathway and conditional admission statements through the existing meaningful-content selector ... Exclude the two incorrectly
-- classified uniform and placement cost requirements from the valid academic benchmark, with documented evidence").
-- Found live (rolled back, 25 Nov 2026 12:10 AEDT, recall check run s1130-entry-cohort-v4-2026-11-25, lean-sections-v4): all 152 earlier answer rows
-- are on their stored pages; 145 inside the selection. Of the 7 outside, 4 are genuine pathway or conditional admission statements ("You may also
-- be considered if you have", "Applicants may be admitted ... if they have previously successfully completed", "will be considered on the basis of
-- their work and life experience", "Provided you meet the required academic and work-ready criteria") and 3 are not academic entry requirements:
-- a uniform cost note, a placement cost note and a course description sentence ("The course features private tuition for voice and instrument
-- studies"); the benchmark excludes these 3.
-- What changes (live on deploy, worker v1.0.43): lean-sections-v5 (lean-sections.ts) treats pathway and conditional admission sentences as entry
-- requirement signals; no other field changes. This migration reseeds the existing recall check (job lean-sections-eval) under v5 with the same
-- 152 earlier rows and 64 accepted rows (the cohort page sizes are already measured under v4). No AI, no Firecrawl, nothing admitted.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged. No spending limit changed.
-- Replaces: lean-sections-v4 for every reader of the selector.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'lean_section_eval_cases_gold_source_check' and pg_get_constraintdef(oid) like '%ai_earlier%') then
    raise exception 'guard: the s1125 paste file has not widened the recall check labels';
  end if;
end $g$;
create temp table s1135_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1135_cron on commit drop as select count(*) n from cron.job where active;

do $seed$
declare v_run constant text := 's1135-entry-cohort-v5-2026-11-25'; v_from constant text := 's1130-entry-cohort-v4-2026-11-25'; v_a int;
begin
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
  select v_run, x.field, x.gold_source, x.source_ref, x.course_id, x.evidence_id, x.storage_path, x.gold
    from pipeline.lean_section_eval_cases x where x.run_label = v_from and x.gold_source in ('ai_earlier', 'aer_accepted')
  on conflict do nothing;
  get diagnostics v_a = row_count;
  if v_a > 400 then raise exception 's1135: % recall cases, more than planned (216)', v_a; end if;  -- fixed: the planned run's size
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'seed', 'pipeline.lean_section_eval_cases', jsonb_build_object('reason', 'P0 AER preprocessing qualification (Platform Admin 25 Nov 2026 12:01 AEDT): recall of lean-sections-v5',
          'by', 'migration 20261126210000 (CF-247 s1135)', 'run', v_run, 'from_run', v_from, 'cases', v_a,
          'excluded_from_benchmark', jsonb_build_array('uniform cost note', 'placement cost note', 'course description sentence (private tuition)')), null);
  raise notice 's1135: % cases', v_a;
end $seed$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1135_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1135_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
