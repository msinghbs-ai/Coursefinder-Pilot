begin isolation level repeatable read;
-- Lean AI Input Phase 1b step 1 recall matcher fix: rolled-back rehearsal of 20261114051500 (run b seed). Forced rollback: the final DO block always raises.
create temp table _rh_pre on commit drop as select
  (select count(*) from pipeline.platform_toolset_settings) settings_total,
  (select md5(string_agg(toolset_key||key||value::text, ',' order by toolset_key,key)) from pipeline.platform_toolset_settings) settings_md5,
  (select count(*) from cron.job) cron_jobs, (select count(*) from pipeline.field_enrich_items) enrich_rows,
  (select count(*) from pipeline.aer_labelled_rows_v1) labels,
  (select count(*) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14') a_total,
  (select count(*) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14' and state='done') a_done,
  (select count(*) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14' and state='failed') a_failed,
  (select count(*) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14' and state='pending') a_pending,
  (select md5(string_agg(id::text||state||coalesce(gold_in_selection::text,'')||coalesce(gold_in_lean::text,''), ',' order by id)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14' and state='done') a_done_md5,
  (select md5(string_agg(field||gold_source||source_ref, ',' order by field,gold_source,source_ref)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14') a_keys_md5;
-- begin migration
-- CF-247 Lean AI Input Phase 1b step 1, recall matcher fix (Platform Admin 14 Nov 2026 13:25, option A): worker coverage-sweep v0.91.0 mode
-- lean_sections_eval matches each labelled value against the blocks' words without their "[B<n> @<offset>]" labels (lean-sections.ts blockPlain),
-- so a quote that runs across adjacent blocks is found. Run phase1b-step1-2026-11-14 (worker v0.89.0) under-counted converted-page and selection
-- recall for such quotes; its done cases are kept as recorded (their page, current-reader and first-cut figures are exact), its unread cases are
-- closed as superseded, and the same 2,800 labelled cases are seeded again as run phase1b-step1b-2026-11-14 (same seed, same fixed hash order).
-- The new cases are held for 10 minutes so that only the v0.91.0 worker (deployed in the same release) reads them. No AI, no Firecrawl; nothing
-- admitted; no reader request, prompt, model, admission, budget or consumer API change. Nothing is dropped or deleted.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '3s';

update pipeline.lean_section_eval_cases
   set state = 'failed', leased_until = null, done_at = now(),
       error = 'superseded: recall matcher fixed in worker v0.91.0; the case is read again in run phase1b-step1b-2026-11-14'
 where run_label = 'phase1b-step1-2026-11-14' and state = 'pending';

select security.lean_sections_eval_seed_v1('phase1b-step1b-2026-11-14');

update pipeline.lean_section_eval_cases set leased_until = now() + interval '10 minutes'  -- fixed: the release window, so the v0.89.0 worker reads none of the new run
 where run_label = 'phase1b-step1b-2026-11-14' and state = 'pending';

do $c$
begin
  if (select count(*) from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1b-2026-11-14') <> (select count(*) from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1-2026-11-14') then
    raise exception 'post-check: run b holds the same cases as run a';
  end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1-2026-11-14' and state = 'pending') then raise exception 'post-check: run a has no unread case left'; end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1b-2026-11-14' and (state <> 'pending' or leased_until is null)) then raise exception 'post-check: run b is pending and held'; end if;
end $c$;

-- end of migration
do $rehearsal$
declare p record; r jsonb := '{}'; f text[] := '{}'; v jsonb; q text := current_query();
begin
  select * into p from _rh_pre;
  r := r || jsonb_build_object('X1_migration_md5', md5(substr(q, strpos(q, '-- begin migration') + length('-- begin migration') + 1, strpos(q, E'\n-- end of migration') - strpos(q, '-- begin migration') - length('-- begin migration'))),
       'pre', jsonb_build_object('a_total', p.a_total, 'a_done', p.a_done, 'a_failed', p.a_failed, 'a_pending', p.a_pending));
  -- run a: done cases kept exactly, unread cases closed as superseded, nothing removed
  if (select count(*) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14') <> p.a_total then f := f || 'A1 run a lost cases'; end if;
  if (select md5(string_agg(id::text||state||coalesce(gold_in_selection::text,'')||coalesce(gold_in_lean::text,''), ',' order by id)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14' and state='done') is distinct from p.a_done_md5 then f := f || 'A2 run a done cases changed'; end if;
  if (select count(*) from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14' and state='failed' and error like 'superseded: recall matcher fixed in worker v0.91.0%') <> p.a_pending then f := f || 'A3 superseded <> unread'; end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label='phase1b-step1-2026-11-14' and state='pending') then f := f || 'A4 run a pending left'; end if;
  -- run b: the same labelled cases, pending, held for the release window
  if (select md5(string_agg(field||gold_source||source_ref, ',' order by field,gold_source,source_ref)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1b-2026-11-14') is distinct from p.a_keys_md5 then f := f || 'B1 run b keys differ from run a'; end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label='phase1b-step1b-2026-11-14' and (state<>'pending' or leased_until is null or leased_until > now() + interval '10 minutes' or leased_until <= now())) then f := f || 'B2 run b not pending and held'; end if;
  r := r || jsonb_build_object('B_run_b', (select jsonb_object_agg(field, n) from (select field, count(*) n from pipeline.lean_section_eval_cases where run_label='phase1b-step1b-2026-11-14' group by field) z));
  -- the worker gets nothing during the release window
  if jsonb_array_length(public.svc_lean_sections_eval_next_v1(5)) <> 0 then f := f || 'W1 leased during the release window'; end if;
  v := security.lean_sections_eval_report_v1(null); r := r || jsonb_build_object('Q_report_run', v->'run', 'Q_ai_calls', v->'ai_calls');
  if (v->>'ai_calls')::int <> 0 then f := f || 'Q1 ai calls'; end if;
  -- regression: nothing else touched
  if (select count(*) from pipeline.platform_toolset_settings) <> p.settings_total or (select md5(string_agg(toolset_key||key||value::text, ',' order by toolset_key,key)) from pipeline.platform_toolset_settings) <> p.settings_md5 then f := f || 'N1 settings changed'; end if;
  if (select count(*) from cron.job) <> p.cron_jobs then f := f || 'N2 cron changed'; end if;
  if (select count(*) from pipeline.field_enrich_items) <> p.enrich_rows or (select count(*) from pipeline.aer_labelled_rows_v1) <> p.labels then f := f || 'N3 other data changed'; end if;
  r := jsonb_build_object('verdict', case when cardinality(f) = 0 then 'PASS' else 'FAIL' end, 'failed', to_jsonb(f), 'txid', txid_current(), 'at', now()) || r;
  raise exception 'REHEARSAL_RESULT %', r::text;
end $rehearsal$;
