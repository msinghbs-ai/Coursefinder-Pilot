-- CF-247 s1328 (S1-Build; SS-Programme-Control 28 Nov 2026 07:05 AEDT, item 3: "Resolve the repeated zero-yield course-admission pass using the
-- existing DR-19 diagnostic process. Verify eligibility before changing code"; Standing Mandate 21 Nov 2026: a verified fix ships live).
-- Found live 28 Nov 2026 (read only; DR-19 security.record_journey_v1 on Layer 4 items 4ef82ae5 and 5608bcee, then rolled-back probes):
--   * eligible: 2 pending course entry first reads wait for the course pass (aer-course-partial-v1), ANU 070333K and Alphacrucis 080056K
--     (DOT batch 07), both stopped by aer-machine-v1 at the completeness gate (gate_incomplete, 06:48);
--   * the pass's filter reads each pending item's latest machine decision from pipeline.aer_machine_admissions (about 19,400 rows), which has
--     no index on review_item_id outside the shadow and admitted partial indexes: about 67 ms an item over 956 pending items, so the first row
--     arrives after the pass's 15 s fire guard and the pass looks at nothing (course_looked_at 0 on every tick for nine hours); the same reads
--     take the whole rule to 109 s and past the runner's 120 s statement time-out (runs due 06:59 and 07:14 not recorded).
--   * with this index (rolled back): the pass's query 285 ms, eligible 2; the rule admits both (course_rows_admitted 2, course_items_admitted 2).
-- The change: one index. No function, rule, check, ledger, setting or job changes; the rule's decisions are unchanged.
-- G1: no job. G2: no value. G3: a pipeline table the consumer API does not read; 75/48 checked. Locks, Layer 4 decisions and cron checked.
-- $0. Nothing dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the index build

create temp table s1328_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before, (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) as decided_before;

do $e$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
end $e$;

create index if not exists aer_machine_admissions_item_created_idx
  on pipeline.aer_machine_admissions (review_item_id, created_at desc);

comment on index pipeline.aer_machine_admissions_item_created_idx is
  'CF-247 s1328: latest machine decision per Layer 4 item (aer-partial-admit course pass and source-proof pass filters).';

do $e$
declare v jsonb := security.consumer_api_check_v1(); g record;
begin
  select * into g from s1328_guard;
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'post-check: consumer API baseline changed: %', v;
  end if;
  if (select count(*) from cron.job where active) <> g.cron_before then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> g.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> g.decided_before then
    raise exception 'post-check: Layer 4 decisions changed';
  end if;
end $e$;
