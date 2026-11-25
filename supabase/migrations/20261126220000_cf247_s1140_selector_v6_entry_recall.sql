-- CF-247 s1140 (S1-Build / Integration Controller; Platform Admin 25 Nov 2026 12:01 and 12:37 AEDT, P0 AER preprocessing qualification).
-- Found live (rolled back, 25 Nov 2026 12:55 AEDT): qualification run s1125-entry-qualify-2026-11-25 complete (332 of 332, US$0.28). DeepSeek V4 Flash read
-- every page (83 of 83 answers valid), took 46% fewer input tokens on the selected text (median 3,081 to 1,671), and dropped fewer unsupported
-- quotes (8 against 26), but the existing no-loss criterion is not met: 11 pages found fewer label rows on the selected text than on the whole page
-- (and 11 found more). The selection missed: an entry condition printed as a heading ("Graduate with an AUSTRALIAN DEGREE (AQF Level 9)", "You may also
-- be considered if you have:"), minimum ages, a weighted average mark, a coordinator's approval, "You must:" lines and creative submissions or
-- portfolios (recall run s1135-entry-cohort-v5-2026-11-25: 59 of 64 accepted rows inside v5).
-- What changes (live on deploy, worker v1.0.44): lean-sections-v6 (lean-sections.ts) selects those; no other field changes. This migration reseeds
-- the existing recall check under v6 with the 152 earlier rows, the 64 accepted rows and the 225 cohort pages. No AI, no Firecrawl, nothing admitted.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked). Locks and cron checked unchanged. No spending limit changed.
-- Replaces: lean-sections-v5 for every reader of the selector.
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
create temp table s1140_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1140_cron on commit drop as select count(*) n from cron.job where active;

do $seed$
declare v_run constant text := 's1140-entry-cohort-v6-2026-11-25'; v_from constant text := 's1130-entry-cohort-v4-2026-11-25'; v_a int;
begin
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
  select v_run, x.field, x.gold_source, x.source_ref, x.course_id, x.evidence_id, x.storage_path, x.gold
    from pipeline.lean_section_eval_cases x where x.run_label = v_from and x.gold_source in ('ai_earlier', 'aer_accepted', 'cohort_size')
  on conflict do nothing;
  get diagnostics v_a = row_count;
  if v_a > 600 then raise exception 's1140: % recall cases, more than planned (441)', v_a; end if;  -- fixed: the planned run's size
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_eval', 'seed', 'pipeline.lean_section_eval_cases', jsonb_build_object('reason', 'P0 AER preprocessing qualification (Platform Admin 25 Nov 2026 12:01 AEDT): recall of lean-sections-v6',
          'by', 'migration 20261126220000 (CF-247 s1140)', 'run', v_run, 'from_run', v_from, 'cases', v_a,
          'excluded_from_benchmark', jsonb_build_array('uniform cost note', 'placement cost note', 'course description sentence (private tuition)')), null);
  raise notice 's1140: % cases', v_a;
end $seed$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where active) <> (select n from s1140_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1140_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
