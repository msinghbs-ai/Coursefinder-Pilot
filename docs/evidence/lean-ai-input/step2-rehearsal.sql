begin isolation level repeatable read;
-- Lean AI Input Phase 1b step 2 bundle: rolled-back rehearsal of 20261114071500. Forced rollback: the final DO block always raises.
create temp table _rh_pre on commit drop as select
  (select count(*) from pipeline.platform_toolset_settings) settings_total,
  (select md5(string_agg(toolset_key||key||value::text, ',' order by toolset_key,key)) from pipeline.platform_toolset_settings where not (toolset_key='pipeline' and key='batch.lean_sections_eval')) settings_md5_other,
  (select count(*) from cron.job) cron_jobs, (select count(*) from pipeline.field_enrich_items) enrich_rows, (select count(*) from pipeline.ai_input_observations) obs_rows,
  (select md5(pg_get_functiondef('public.svc_ai_input_observe_v1(jsonb)'::regprocedure))) obs_md5_before,
  (select md5(string_agg(id::text||state||coalesce(gold_in_selection::text,''), ',' order by id)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1b-2026-11-14') run_b_md5,
  (select md5(string_agg(field||gold_source||source_ref, ',' order by field,gold_source,source_ref)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1b-2026-11-14') run_b_keys;
-- begin migration
-- CF-247 Lean AI Input Phase 1b step 2, shadow selection (admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md §5.2; Platform Admin
-- 14 Nov 2026 14:32: bundle step 2 with the run b report, "recording the selector's output alongside current reads, still with zero AI prompt
-- changes or spend"). Worker coverage-sweep v0.92.0 (mode enrich_ai): every observed course-page read also records what the section selector
-- (lean-sections.ts lean-sections-v2 over aer-v2.ts lean-blocks-v1) would send for its field, beside what is sent: block count, characters, block
-- ids, whether it fell back to the whole page, the preflight on the selection and the selection's SHA-256. Nothing else:
--   * the request sent, prompt, model, skip, value, admission rule, budget, credit floor and Layer 4 routing are unchanged;
--   * no paid call is started to fill it: rows appear only when Enrich fields runs as it already would;
--   * the selection is not sent and decides nothing (switch-over is 1b-3 qualification and 1b-4 activation, separate approvals).
-- Adds nine columns beside the Phase 1 observation columns, five settings, the insert extended to keep them (same name, guarded on the live
-- definition), and a read-only report. G2: sizes, the shadow's page-size bound and the switch are settings; the worker's reading.input_observe_on
-- switch is now read as a switch (a 0 was read as the default 1).
-- The selector is lean-sections-v2 (wider entry-requirement headings from the run phase1b-step1b-2026-11-14 misses) and the offline check decodes
-- HTML entities in labels. Run phase1b-step1c-2026-11-14 re-checks the same 2,800 labelled cases with v2 (zero spend), held for the release window.
-- batch.lean_sections_eval goes from 120 to 40: batches of 120 fee pages exceeded the edge CPU-time limit on 14 Nov 2026; 40 ran cleanly.
-- G3: no consumer API object is read or changed.
-- Replaces: public.svc_ai_input_observe_v1(jsonb) (same name; replaced only from the definition it was written against, md5 3f6d4ed98c8055bdbd18adae4e09edf0).
-- Retires: nothing.

set local lock_timeout = '3s';

do $g$
begin
  if md5(pg_get_functiondef('public.svc_ai_input_observe_v1(jsonb)'::regprocedure)) <> '3f6d4ed98c8055bdbd18adae4e09edf0' then
    raise exception 'live public.svc_ai_input_observe_v1 differs from the definition this change replaces (md5 %)', md5(pg_get_functiondef('public.svc_ai_input_observe_v1(jsonb)'::regprocedure));
  end if;
end $g$;

alter table pipeline.ai_input_observations
  add column if not exists selector            text,
  add column if not exists sel_input           text,
  add column if not exists sel_blocks          integer,
  add column if not exists sel_chars           integer,
  add column if not exists sel_no_selection    boolean,
  add column if not exists sel_block_ids       text[],
  add column if not exists preflight_selection text check (preflight_selection in ('likely', 'unknown', 'no_signal', 'not_measured')),
  add column if not exists sel_sha256          text,
  add column if not exists sel_ms              integer;
comment on table pipeline.ai_input_observations is 'CF-247 Lean AI Input Phase 1 (Platform Admin 13 Nov 2026 22:51; admin docs/platform/LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md §4): one row per course-page AI read of the Enrich fields reader (worker coverage-sweep v0.87.0+, lean-input.ts lean-input-observation-v1): source text length, characters sent, whether and where the text was cut, the structured-text size (lean-md-v1), a high-recall preflight on the text sent and on the whole page (shadow: never used to skip a read), the sent-input SHA-256 and the content/prompt/model/schema fingerprint. Phase 1b step 2 (worker v0.92.0, 14 Nov 2026): the selector and sel_* columns record what the section selector (lean-sections-v2 over lean-blocks-v1) would send for the field, beside what is sent; it is not sent and decides nothing. Measurement only. Joined to pipeline.field_enrich_items by item_id and to pipeline.ai_invocations (#1128). Kept reading.input_observation_retention_days.';

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'reading.selection_shadow_on', 'Lean AI input: record what the section selector would send',
  '1: each observed course-page read also records the sections the selector would send for its field (blocks, characters, block ids, fallback to the whole page, preflight). Nothing is sent from it. 0: not recorded. Reads, values and admissions are the same either way.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 1443, 'Lean AI Input Phase 1b step 2 (shadow), Platform Admin 14 Nov 2026 14:32', 'Enrich fields', 'worker coverage-sweep v0.92.0 (mode enrich_ai)'),
 ('pipeline', 'reading.section_max_chars', 'Section selector: largest section taken whole',
  'A matching heading selects its whole section up to this size; a larger section keeps only its heading and the matching blocks with their neighbours.',
  'number', '8000'::jsonb, 1000, 40000, 'characters', 1444, 'Lean AI Input Phase 1b: selector size, as validated in the offline recall check', 'Enrich fields', 'worker coverage-sweep v0.92.0 (modes enrich_ai shadow, lean_sections_eval)'),
 ('pipeline', 'reading.section_neighbour_chars', 'Section selector: short note kept beside a value, at most',
  'A block next to a matching block is kept when it is at most this long (units, periods, "indicative", the student group).',
  'number', '240'::jsonb, 40, 2000, 'characters', 1445, 'Lean AI Input Phase 1b: selector size, as validated in the offline recall check', 'Enrich fields', 'worker coverage-sweep v0.92.0 (modes enrich_ai shadow, lean_sections_eval)'),
 ('pipeline', 'reading.section_intro_blocks', 'Section selector: opening blocks kept for a description',
  'For a course description the first blocks of the page are kept as well as the matching sections.',
  'number', '12'::jsonb, 1, 60, 'blocks', 1446, 'Lean AI Input Phase 1b: selector size, as validated in the offline recall check', 'Enrich fields', 'worker coverage-sweep v0.92.0 (modes enrich_ai shadow, lean_sections_eval)'),
 ('pipeline', 'reading.selection_shadow_max_chars', 'Lean AI input: largest page shadowed by the section selector',
  'A page whose structured text is longer than this is recorded as skipped instead of shadowed, so the shadow never adds unbounded CPU time to a paid read.',
  'number', '200000'::jsonb, 20000, 1000000, 'characters', 1447, 'Lean AI Input Phase 1b step 2: bound on the shadow''s CPU time inside a read', 'Enrich fields', 'worker coverage-sweep v0.92.0 (mode enrich_ai)')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings
   set value = '40'::jsonb, reason = 'Lean AI Input Phase 1b, 14 Nov 2026: batches of 120 fee pages exceeded the edge CPU-time limit; 40 ran cleanly'
 where toolset_key = 'pipeline' and key = 'batch.lean_sections_eval' and value = '120'::jsonb;

create or replace function public.svc_ai_input_observe_v1(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
-- CF-247 Lean AI Input Phase 1: the worker's input observations, kept as sent (one short insert), then a bounded removal of expired rows.
-- Phase 1b step 2 (worker v0.92.0): also the shadow selection (sel_*), when the worker sends it.
-- A row that does not fit is skipped, never raised: an observation must never fail a read.
declare v_n int := 0; v_gone int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('kept', 0); end if;
  insert into pipeline.ai_input_observations (contract, worker, read, field, item_id, course_id, storage_path, source_sha256, converter, source_chars,
         sent_chars, limit_chars, cut, cut_at, lean_chars, lean_tables, lean_table_rows, preflight_sent, preflight_full, prompt_key, model, schema_key,
         input_sha256, fingerprint, selector, sel_input, sel_blocks, sel_chars, sel_no_selection, sel_block_ids, preflight_selection, sel_sha256, sel_ms)
  select left(x->>'contract', 60), left(x->>'worker', 60), left(x->>'read', 40), left(x->>'field', 40), (x->>'item_id')::bigint,
         case when x->>'course_id' ~ '^[0-9a-f-]{36}$' then (x->>'course_id')::uuid end, left(x->>'storage_path', 400), left(x->>'source_sha256', 64),
         left(x->>'converter', 40), (x->>'source_chars')::int, (x->>'sent_chars')::int, (x->>'limit_chars')::int, coalesce((x->>'cut')::boolean, false),
         (x->>'cut_at')::int, (x->>'lean_chars')::int, (x->>'lean_tables')::int, (x->>'lean_table_rows')::int,
         case when x->>'preflight_sent' in ('likely', 'unknown', 'no_signal', 'not_measured') then x->>'preflight_sent' end,
         case when x->>'preflight_full' in ('likely', 'unknown', 'no_signal', 'not_measured') then x->>'preflight_full' end,
         left(x->>'prompt_key', 120), left(x->>'model', 120), left(x->>'schema_key', 120), left(x->>'input_sha256', 64), left(x->>'fingerprint', 64),
         left(x->>'selector', 60), left(x->>'sel_input', 40), (x->>'sel_blocks')::int, (x->>'sel_chars')::int, (x->>'sel_no_selection')::boolean,
         case when jsonb_typeof(x->'sel_block_ids') = 'array' then (select array_agg(left(e, 12)) from (select jsonb_array_elements_text(x->'sel_block_ids') e limit 400) z) end,  -- fixed: the recorded id list's length, a storage bound
         case when x->>'preflight_selection' in ('likely', 'unknown', 'no_signal', 'not_measured') then x->>'preflight_selection' end,
         left(x->>'sel_sha256', 64), (x->>'sel_ms')::int
    from jsonb_array_elements(p_rows) x
   where coalesce(x->>'read', '') <> '' and coalesce(x->>'field', '') <> '' and coalesce(x->>'contract', '') <> '';
  get diagnostics v_n = row_count;
  delete from pipeline.ai_input_observations o
   where o.id in (select o2.id from pipeline.ai_input_observations o2
                   where o2.observed_at < now() - make_interval(days => security.pipeline_num_v1('reading.input_observation_retention_days', 30)::int)
                   order by o2.id limit security.pipeline_num_v1('reading.input_observation_purge_batch', 2000)::int);
  get diagnostics v_gone = row_count;
  return jsonb_build_object('kept', v_n, 'expired_removed', v_gone);
end $function$;
revoke all on function public.svc_ai_input_observe_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_ai_input_observe_v1(jsonb) to service_role;

create or replace function security.ai_input_selection_report_v1(p_hours int default 24) returns table (
  read text, field text, reads bigint, with_selection bigint, whole_page_fallback bigint, skipped_size bigint, median_sent_chars int,
  median_selected_chars int, selected_share_of_sent numeric, cut_reads bigint, cut_but_signal_in_selection bigint, signal_lost_by_selection bigint,
  filled bigint, filled_but_selection_no_signal bigint, p95_shadow_ms int)
language sql stable security definer set search_path = '' as $function$
  -- CF-247 Lean AI Input Phase 1b step 2, read-only: per read and field over the last p_hours, what the section selector would have sent beside
  -- what was sent. signal_lost_by_selection = the whole page had a signal (likely or unknown) and the selection had none: must stay 0 before 1b-3.
  -- filled_but_selection_no_signal = the reader filled the field from the text it was sent while the selection showed no signal: reviewed by a
  -- person before any switch-over. A whole-page fallback counts as the structured page (as it would be sent). Outcomes come from
  -- pipeline.field_enrich_items.
  with o as (select * from pipeline.ai_input_observations a where a.observed_at > now() - make_interval(hours => greatest(1, p_hours)) and a.selector is not null),
  j as (select o.*, e.state, case when o.sel_no_selection then o.lean_chars else o.sel_chars end eff_chars
          from o left join pipeline.field_enrich_items e on e.id = o.item_id)
  select j.read, j.field, count(*), count(*) filter (where not j.sel_no_selection), count(*) filter (where j.sel_no_selection),
         count(*) filter (where j.selector like '%:skipped-size'),
         (percentile_disc(0.5) within group (order by j.sent_chars))::int, (percentile_disc(0.5) within group (order by j.eff_chars))::int,
         round(sum(j.eff_chars)::numeric / nullif(sum(j.sent_chars) filter (where j.eff_chars is not null), 0), 3),
         count(*) filter (where j.cut), count(*) filter (where j.cut and j.preflight_sent <> 'likely' and j.preflight_selection = 'likely'),
         count(*) filter (where j.preflight_full in ('likely', 'unknown') and j.preflight_selection = 'no_signal'),
         count(*) filter (where j.state = 'filled'), count(*) filter (where j.state in ('filled', 'review') and j.preflight_selection = 'no_signal'),
         (percentile_disc(0.95) within group (order by j.sel_ms))::int
    from j group by j.read, j.field order by count(*) desc
$function$;
revoke all on function security.ai_input_selection_report_v1(int) from public, anon, authenticated;

-- run c: the same labelled cases read with lean-sections-v2; held for the release window so only the v0.92.0 worker reads them
select security.lean_sections_eval_seed_v1('phase1b-step1c-2026-11-14');
update pipeline.lean_section_eval_cases set leased_until = now() + interval '10 minutes'  -- fixed: the release window, so the v0.91.0 worker reads none of the new run
 where run_label = 'phase1b-step1c-2026-11-14' and state = 'pending';

do $c$
declare v jsonb;
begin
  if (select count(*) from information_schema.columns where table_schema = 'pipeline' and table_name = 'ai_input_observations'
       and column_name in ('selector', 'sel_input', 'sel_blocks', 'sel_chars', 'sel_no_selection', 'sel_block_ids', 'preflight_selection', 'sel_sha256', 'sel_ms')) <> 9 then
    raise exception 'post-check: the nine shadow selection columns exist';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('reading.selection_shadow_on', 'reading.section_max_chars', 'reading.section_neighbour_chars', 'reading.section_intro_blocks', 'reading.selection_shadow_max_chars')) <> 5 then
    raise exception 'post-check: five settings';
  end if;
  if (select count(*) from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1c-2026-11-14') <> (select count(*) from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1b-2026-11-14') then
    raise exception 'post-check: run c holds the same cases as run b';
  end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1c-2026-11-14' and (state <> 'pending' or leased_until is null)) then raise exception 'post-check: run c is pending and held'; end if;
  v := public.svc_ai_input_observe_v1('[]'::jsonb);
  if (v->>'kept')::int <> 0 then raise exception 'post-check: an empty insert keeps nothing'; end if;
end $c$;
-- end of migration
do $rehearsal$
declare p record; r jsonb := '{}'; f text[] := '{}'; v jsonb; q text := current_query();
begin
  select * into p from _rh_pre;
  r := r || jsonb_build_object('X1_migration_md5', md5(substr(q, strpos(q, '-- begin migration') + length('-- begin migration') + 1, strpos(q, E'\n-- end of migration') - strpos(q, '-- begin migration') - length('-- begin migration') - 1)),
    'obs_md5_before', p.obs_md5_before, 'obs_md5_after', md5(pg_get_functiondef('public.svc_ai_input_observe_v1(jsonb)'::regprocedure)));
  if p.obs_md5_before <> '3f6d4ed98c8055bdbd18adae4e09edf0' then f := f || 'G1 guard md5'; end if;
  -- S: settings
  if (select count(*) from pipeline.platform_toolset_settings) <> p.settings_total + 5 then f := f || 'S1 settings +5'; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='batch.lean_sections_eval') <> '40'::jsonb then f := f || 'S2 batch 40'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key='pipeline' and key in ('reading.selection_shadow_on','reading.section_max_chars','reading.section_neighbour_chars','reading.section_intro_blocks','reading.selection_shadow_max_chars') and label is not null and unit is not null and used_by is not null and min_value is not null and max_value is not null) <> 5 then f := f || 'S3 settings complete'; end if;
  if (select md5(string_agg(toolset_key||key||value::text, ',' order by toolset_key,key)) from pipeline.platform_toolset_settings where not (toolset_key='pipeline' and key='batch.lean_sections_eval') and not (toolset_key='pipeline' and key in ('reading.selection_shadow_on','reading.section_max_chars','reading.section_neighbour_chars','reading.section_intro_blocks','reading.selection_shadow_max_chars'))) <> p.settings_md5_other then f := f || 'S4 other settings changed'; end if;
  r := r || jsonb_build_object('S_new', (select jsonb_object_agg(key, value) from pipeline.platform_toolset_settings where toolset_key='pipeline' and key in ('reading.selection_shadow_on','reading.section_max_chars','reading.section_neighbour_chars','reading.section_intro_blocks','reading.selection_shadow_max_chars','batch.lean_sections_eval')));
  -- O: the extended insert keeps a v0.92.0 row with its shadow and a v0.91.0 row without; bad rows skipped
  v := public.svc_ai_input_observe_v1(jsonb_build_array(
    jsonb_build_object('contract','lean-input-observation-v1','worker','rehearsal','read','course_entry','field','entry_requirements','item_id',0,'source_chars',30000,'sent_chars',30000,'cut',false,
      'preflight_sent','likely','preflight_full','likely','selector','lean-sections-v2','sel_input','lean-blocks-v1','sel_blocks',12,'sel_chars',4000,'sel_no_selection',false,
      'sel_block_ids', jsonb_build_array('B1','B7','B8'),'preflight_selection','likely','sel_sha256', repeat('a',64),'sel_ms',9),
    jsonb_build_object('contract','lean-input-observation-v1','worker','rehearsal','read','course_fields','field','duration','item_id',0,'source_chars',9000,'sent_chars',9000),
    jsonb_build_object('contract','lean-input-observation-v1','worker','rehearsal','read','course_fields','field','campus','selector','lean-sections-v2:skipped-size'),
    jsonb_build_object('worker','bad')));
  r := r || jsonb_build_object('O1_insert', v);
  if (v->>'kept')::int <> 3 then f := f || 'O1 kept <> 3'; end if;
  if not exists (select 1 from pipeline.ai_input_observations where worker='rehearsal' and field='entry_requirements' and sel_blocks=12 and sel_block_ids = array['B1','B7','B8'] and preflight_selection='likely' and sel_ms=9 and selector='lean-sections-v2') then f := f || 'O2 shadow row'; end if;
  if not exists (select 1 from pipeline.ai_input_observations where worker='rehearsal' and field='duration' and selector is null and sel_blocks is null) then f := f || 'O3 legacy row'; end if;
  select coalesce(jsonb_agg(to_jsonb(x)), '[]') into v from security.ai_input_selection_report_v1(1) x;
  r := r || jsonb_build_object('Q_report', v);
  if jsonb_array_length(v) <> 2 then f := f || 'Q1 report rows <> 2 (entry, campus skipped)'; end if;
  -- C: run c seeded with the same cases, held; run b untouched
  if (select md5(string_agg(field||gold_source||source_ref, ',' order by field,gold_source,source_ref)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1c-2026-11-14') is distinct from p.run_b_keys then f := f || 'C1 run c keys'; end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where run_label='phase1b-step1c-2026-11-14' and (state<>'pending' or leased_until is null or leased_until <= now())) then f := f || 'C2 run c held'; end if;
  if (select md5(string_agg(id::text||state||coalesce(gold_in_selection::text,''), ',' order by id)) from pipeline.lean_section_eval_cases where run_label='phase1b-step1b-2026-11-14') <> p.run_b_md5 then f := f || 'C3 run b changed'; end if;
  if jsonb_array_length(public.svc_lean_sections_eval_next_v1(5)) <> 0 then f := f || 'C4 leased in the release window'; end if;
  -- N: nothing else
  if (select count(*) from cron.job) <> p.cron_jobs then f := f || 'N1 cron'; end if;
  if (select count(*) from pipeline.field_enrich_items) <> p.enrich_rows then f := f || 'N2 enrich rows'; end if;
  r := jsonb_build_object('verdict', case when cardinality(f) = 0 then 'PASS' else 'FAIL' end, 'failed', to_jsonb(f), 'txid', txid_current(), 'at', now()) || r;
  raise exception 'REHEARSAL_RESULT %', r::text;
end $rehearsal$;
