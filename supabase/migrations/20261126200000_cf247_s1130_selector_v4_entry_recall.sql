-- CF-247 s1130 (S1-Build / Integration Controller; Platform Admin 25 Nov 2026 08:16 AEDT, P0 AER preprocessing, Admin #1063: "Validate academic
-- requirement recall, qualifications, scores, audiences, conditions, tables and footnotes ... Do not treat historical AI answers as unquestionable
-- ground truth; verify against source evidence").
-- Found live (rolled back, 25 Nov 2026 11:20 AEDT, recall check run s1125-entry-cohort-2026-11-25, lean-sections-v3): of the 152 earlier answer
-- rows, 80 read at 10:55 AEDT were all on their stored page, and 71 were inside the selection. The 9 outside were condition sentences that print
-- neither "entry" nor "requirement": Working with Children, Police and NDIS checks, "involved in some form of high-level music making", and two
-- rows that are not entry requirements at all (uniform and placement costs: the earlier answer was wrong there). The qualification run lost two
-- Layer 4 accepted rows the same way ("designed exclusively for professionals with 2+ years of work experience", "Graduate with an AUSTRALIAN
-- DEGREE (AQF Level 9)").
-- What changes (live on deploy, worker v1.0.42): lean-sections-v4 (lean-sections.ts) treats such entry condition sentences as entry requirement
-- signals and makes a selection holding one likely; no other field changes. This migration seeds the existing recall check (job
-- lean-sections-eval, already running) with the same labels under v4: the 152 earlier rows (ai_earlier), the rows a person accepted on the 30
-- qualification pages (aer_accepted) and the 225 cohort pages for their sizes (cohort_size). No AI, no Firecrawl, nothing admitted.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged. No spending limit changed.
-- Replaces: lean-sections-v3 for every reader of the selector.
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
create temp table s1130_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1130_cron on commit drop as select count(*) n from cron.job where active;

do $seed$
declare v_run constant text := 's1130-entry-cohort-v4-2026-11-25'; v_from constant text := 's1125-entry-cohort-2026-11-25'; v_a int; v_b int; v_c int;
begin
  -- the same earlier rows and cohort pages as the v3 run
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
  select v_run, x.field, x.gold_source, x.source_ref, x.course_id, x.evidence_id, x.storage_path, x.gold
    from pipeline.lean_section_eval_cases x where x.run_label = v_from
  on conflict do nothing;
  get diagnostics v_a = row_count;
  -- the rows a person accepted on the 30 Layer 4 qualification pages, one case each
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
  select distinct on (g->>'row_id') v_run, 'entry_requirements', 'aer_accepted', g->>'row_id', c.course_id, c.evidence_id, c.storage_path, jsonb_build_array(left(g->>'quote', 160))  -- fixed: the compared opening of a long quote (the existing seed's rule)
    from pipeline.lean_qualify_cases c cross join lateral jsonb_array_elements(c.gold) g
   where c.run_label = 's1125-entry-qualify-2026-11-25' and c.gold_source = 'aer_accepted' and length(security.aer_flat_v1(g->>'quote')) >= 12
  on conflict do nothing;
  get diagnostics v_b = row_count;
  select count(*) into v_c from pipeline.lean_section_eval_cases where run_label = v_run;
  if v_c > 1000 then raise exception 's1130: % recall cases, more than planned', v_c; end if;  -- fixed: the planned run's size
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'seed', 'pipeline.lean_section_eval_cases', jsonb_build_object('reason', 'P0 AER preprocessing regression (Platform Admin 25 Nov 2026 08:16 AEDT, Admin #1063): recall of lean-sections-v4',
          'by', 'migration 20261126200000 (CF-247 s1130)', 'run', v_run, 'from_run', v_from, 'copied', v_a, 'accepted_rows', v_b, 'cases', v_c), null);
  raise notice 's1130: % cases (% copied, % accepted rows)', v_c, v_a, v_b;
end $seed$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1130_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1130_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
