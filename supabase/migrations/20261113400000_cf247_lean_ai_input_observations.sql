-- CF-247 Lean AI Input, Phase 1 (Platform Admin 13 Nov 2026 22:51 "StudySearch — Lean AI Input and Evidence Optimisation"; admin
-- docs/platform/SHARED-SOURCE-TO-PUBLISHED-ENRICHMENT-DESIGN.md §11 and docs/platform/LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md §4).
-- Observe first, change nothing that admits. Worker coverage-sweep v0.87.0 (mode enrich_ai) records, for every course-page read, what the
-- reader was sent and what it was not sent: the source text length, the characters sent, whether and where the text was cut, a high-recall
-- preflight on the text sent and on the whole page, the sent-input SHA-256 and a content/prompt/model/schema fingerprint (lean-input.ts).
-- This migration adds the table they go to, the insert the worker calls, two settings and a read-only report. Nothing else:
--   * no request, prompt, model, skip, value, admission rule, budget, credit floor, Firecrawl acquisition or Layer 4 routing changes;
--   * the preflight is shadow: recorded, never used to skip a read;
--   * beside #1128 (pipeline.ai_invocations: model, attempt, tokens, cost per call), never into it: the two join on the field item.
-- G2: retention, purge batch and the on/off switch are settings (pipeline toolset), read at run time.
-- G3: no consumer API object is read or changed.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '3s';

create table if not exists pipeline.ai_input_observations (
  id              bigint generated always as identity primary key,
  observed_at     timestamptz not null default now(),
  contract        text not null,
  worker          text,
  read            text not null,
  field           text not null,
  item_id         bigint,
  course_id       uuid,
  storage_path    text,
  source_sha256   text,
  converter       text,
  source_chars    integer,
  sent_chars      integer,
  limit_chars     integer,
  cut             boolean not null default false,
  cut_at          integer,
  lean_chars      integer,
  lean_tables     integer,
  lean_table_rows integer,
  preflight_sent  text check (preflight_sent in ('likely', 'unknown', 'no_signal', 'not_measured')),
  preflight_full  text check (preflight_full in ('likely', 'unknown', 'no_signal', 'not_measured')),
  prompt_key      text,
  model           text,
  schema_key      text,
  input_sha256    text,
  fingerprint     text
);
comment on table pipeline.ai_input_observations is 'CF-247 Lean AI Input Phase 1 (Platform Admin 13 Nov 2026 22:51; admin docs/platform/LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md §4): one row per course-page AI read of the Enrich fields reader (worker coverage-sweep v0.87.0, lean-input.ts lean-input-observation-v1): source text length, characters sent, whether and where the text was cut (a description, deadline or course-fields read sends at most enrich.page_chars; an entry read longer than its page size is held, sent 0), the structured-text size (lean-md-v1: headings, table rows with their headers), a high-recall preflight on the text sent and on the whole page (shadow: never used to skip a read), the sent-input SHA-256 and the content/prompt/model/schema fingerprint. Measurement only: nothing reads it to decide a value. Joined to pipeline.field_enrich_items by item_id for outcomes and to pipeline.ai_invocations (#1128) for tokens and cost. Kept reading.input_observation_retention_days.';
create index if not exists ai_input_observations_at_idx on pipeline.ai_input_observations (observed_at);
create index if not exists ai_input_observations_item_idx on pipeline.ai_input_observations (item_id);
create index if not exists ai_input_observations_fp_idx on pipeline.ai_input_observations (fingerprint);
alter table pipeline.ai_input_observations enable row level security;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'reading.input_observe_on', 'Lean AI input: observe what each AI read is sent',
  '1: every course-page read of Enrich fields records its source length, what was sent, whether the text was cut, a shadow preflight and the input fingerprint (pipeline.ai_input_observations). 0: nothing is recorded. Reads, values and admissions are the same either way.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 1440, 'Lean AI Input Phase 1, Platform Admin 13 Nov 2026 22:51 (measure actual AI inputs first)', 'Enrich fields', 'worker coverage-sweep v0.87.0 (mode enrich_ai)'),
 ('pipeline', 'reading.input_observation_retention_days', 'Lean AI input: keep observations for',
  'Observations older than this are removed by the insert itself, a batch at a time (reading.input_observation_purge_batch).',
  'number', '30'::jsonb, 7, 365, 'days', 1441, 'Lean AI Input Phase 1: bounded measurement history', 'Enrich fields', 'public.svc_ai_input_observe_v1'),
 ('pipeline', 'reading.input_observation_purge_batch', 'Lean AI input: observations removed per insert, at most',
  'How many expired observations one insert removes, so a removal never holds the worker.',
  'number', '2000'::jsonb, 100, 20000, 'rows', 1442, 'Lean AI Input Phase 1: bounded purge', 'Enrich fields', 'public.svc_ai_input_observe_v1')
on conflict (toolset_key, key) do nothing;

create or replace function public.svc_ai_input_observe_v1(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
-- CF-247 Lean AI Input Phase 1: the worker's input observations, kept as sent (one short insert), then a bounded removal of expired rows.
-- A row that does not fit is skipped, never raised: an observation must never fail a read.
declare v_n int := 0; v_gone int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('kept', 0); end if;
  insert into pipeline.ai_input_observations (contract, worker, read, field, item_id, course_id, storage_path, source_sha256, converter, source_chars,
         sent_chars, limit_chars, cut, cut_at, lean_chars, lean_tables, lean_table_rows, preflight_sent, preflight_full, prompt_key, model, schema_key,
         input_sha256, fingerprint)
  select left(x->>'contract', 60), left(x->>'worker', 60), left(x->>'read', 40), left(x->>'field', 40), (x->>'item_id')::bigint,
         case when x->>'course_id' ~ '^[0-9a-f-]{36}$' then (x->>'course_id')::uuid end, left(x->>'storage_path', 400), left(x->>'source_sha256', 64),
         left(x->>'converter', 40), (x->>'source_chars')::int, (x->>'sent_chars')::int, (x->>'limit_chars')::int, coalesce((x->>'cut')::boolean, false),
         (x->>'cut_at')::int, (x->>'lean_chars')::int, (x->>'lean_tables')::int, (x->>'lean_table_rows')::int,
         case when x->>'preflight_sent' in ('likely', 'unknown', 'no_signal', 'not_measured') then x->>'preflight_sent' end,
         case when x->>'preflight_full' in ('likely', 'unknown', 'no_signal', 'not_measured') then x->>'preflight_full' end,
         left(x->>'prompt_key', 120), left(x->>'model', 120), left(x->>'schema_key', 120), left(x->>'input_sha256', 64), left(x->>'fingerprint', 64)
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

create or replace function security.ai_input_observation_report_v1(p_hours int default 24) returns table (
  read text, field text, reads bigint, cut_reads bigint, cut_share numeric, median_source_chars int, p95_source_chars int, median_sent_chars int,
  tables_seen bigint, preflight_sent_no_signal bigint, preflight_full_no_signal bigint, signal_only_beyond_cut bigint,
  outcome_filled bigint, outcome_not_stated bigint, no_signal_but_filled bigint, repeated_fingerprints bigint)
language sql stable security definer set search_path = '' as $function$
  -- CF-247 Lean AI Input Phase 1, read-only: per read and field over the last p_hours, how often the text was cut, how often the field was
  -- signalled only beyond the cut (a possible false negative of the cut), how the shadow preflight compares with the reader's own outcome
  -- (no_signal_but_filled = the preflight would have been wrong: must stay 0 before any skip is proposed) and how many reads repeated an
  -- input already read (same fingerprint: change-based re-reading candidates). Outcomes come from pipeline.field_enrich_items.
  with o as (select * from pipeline.ai_input_observations a where a.observed_at > now() - make_interval(hours => greatest(1, p_hours))),
  j as (select o.*, e.state, e.reason from o left join pipeline.field_enrich_items e on e.id = o.item_id)
  select j.read, j.field, count(*), count(*) filter (where j.cut), round(avg(j.cut::int)::numeric, 3),
         (percentile_disc(0.5) within group (order by j.source_chars))::int, (percentile_disc(0.95) within group (order by j.source_chars))::int,
         (percentile_disc(0.5) within group (order by j.sent_chars))::int,
         count(*) filter (where j.lean_tables > 0),
         count(*) filter (where j.preflight_sent = 'no_signal'), count(*) filter (where j.preflight_full = 'no_signal'),
         count(*) filter (where j.cut and j.preflight_sent <> 'likely' and j.preflight_full = 'likely'),
         count(*) filter (where j.state = 'filled'), count(*) filter (where j.reason = 'the page does not state it'),
         count(*) filter (where j.preflight_full = 'no_signal' and j.state in ('filled', 'review')),
         count(j.fingerprint) - count(distinct j.fingerprint)
    from j group by j.read, j.field order by count(*) desc
$function$;
revoke all on function security.ai_input_observation_report_v1(int) from public, anon, authenticated;
