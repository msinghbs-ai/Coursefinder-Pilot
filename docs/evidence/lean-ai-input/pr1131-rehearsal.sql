begin isolation level repeatable read;
-- PR #1131 rolled-back rehearsal (Platform Admin approval 14 Nov 2026 10:42 AEDT). Forced rollback: the final DO block always raises.
create temp table _rh_pre on commit drop as select
  (select count(*) from pipeline.platform_toolset_settings) settings_total,
  (select md5(string_agg(toolset_key||key||value::text, ',' order by toolset_key,key)) from pipeline.platform_toolset_settings where key not like 'reading.input_observ%') settings_md5_other,
  (select count(*) from pipeline.field_enrich_items) enrich_rows,
  (select md5(string_agg(id::text||state||coalesce(updated_at::text,''), ',' order by id)) from pipeline.field_enrich_items where id > (select max(id)-5000 from pipeline.field_enrich_items)) enrich_tail_md5,
  (select count(*) from pg_tables where schemaname='pipeline') pipeline_tables;
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

-- idempotence: the same file again in the same transaction
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


do $rehearsal$
declare r jsonb := '{}'; f text[] := '{}'; v jsonb; v2 jsonb; v_item bigint; v_old bigint; p record; n int; t0 timestamptz;
begin
  select * into p from _rh_pre;
  -- X integrity: the migration text executed is byte-identical to the PR file (md5 df7a7055cfc8ab2940ab74eaf49614d8)
  declare q text := current_query(); a int; b int; begin
    a := strpos(q, '-- CF-247 Lean AI Input, Phase 1 (Platform Admin'); b := strpos(q, E'\n-- idempotence: the same file again');
    r := r || jsonb_build_object('X1_migration_md5', md5(substr(q, a, b - a)));
    if md5(substr(q, a, b - a)) <> 'df7a7055cfc8ab2940ab74eaf49614d8' then f := f || 'X1 executed migration text differs from PR file'; end if;
  end;
  -- S schema
  select count(*) into n from information_schema.columns where table_schema='pipeline' and table_name='ai_input_observations';
  r := r || jsonb_build_object('S1_columns', n); if n <> 26 then f := f || 'S1 columns<>26'; end if;
  select count(*) into n from pg_indexes where schemaname='pipeline' and tablename='ai_input_observations';
  r := r || jsonb_build_object('S2_indexes', n); if n <> 4 then f := f || 'S2 indexes<>4 (pk+3)'; end if;
  if not (select relrowsecurity from pg_class where oid='pipeline.ai_input_observations'::regclass) then f := f || 'S3 RLS off'; end if;
  if obj_description('pipeline.ai_input_observations'::regclass) not like 'CF-247 Lean AI Input Phase 1%' then f := f || 'S4 comment'; end if;
  select count(*) into n from pg_policies where schemaname='pipeline' and tablename='ai_input_observations';
  r := r || jsonb_build_object('S5_policies', n); if n <> 0 then f := f || 'S5 unexpected policy'; end if;
  -- P permissions
  r := r || jsonb_build_object('P_acl', jsonb_build_object(
    'observe_anon', has_function_privilege('anon','public.svc_ai_input_observe_v1(jsonb)','execute'),
    'observe_authenticated', has_function_privilege('authenticated','public.svc_ai_input_observe_v1(jsonb)','execute'),
    'observe_service_role', has_function_privilege('service_role','public.svc_ai_input_observe_v1(jsonb)','execute'),
    'report_anon', has_function_privilege('anon','security.ai_input_observation_report_v1(int)','execute'),
    'report_authenticated', has_function_privilege('authenticated','security.ai_input_observation_report_v1(int)','execute'),
    'table_select_anon', has_table_privilege('anon','pipeline.ai_input_observations','select'),
    'table_select_authenticated', has_table_privilege('authenticated','pipeline.ai_input_observations','select'),
    'observe_secdef', (select prosecdef from pg_proc where oid='public.svc_ai_input_observe_v1(jsonb)'::regprocedure),
    'observe_search_path', (select proconfig from pg_proc where oid='public.svc_ai_input_observe_v1(jsonb)'::regprocedure),
    'report_secdef', (select prosecdef from pg_proc where oid='security.ai_input_observation_report_v1(int)'::regprocedure)));
  if has_function_privilege('anon','public.svc_ai_input_observe_v1(jsonb)','execute') or has_function_privilege('authenticated','public.svc_ai_input_observe_v1(jsonb)','execute') then f := f || 'P1 observe callable by anon/authenticated'; end if;
  if not has_function_privilege('service_role','public.svc_ai_input_observe_v1(jsonb)','execute') then f := f || 'P2 service_role cannot observe'; end if;
  if has_function_privilege('anon','security.ai_input_observation_report_v1(int)','execute') or has_function_privilege('authenticated','security.ai_input_observation_report_v1(int)','execute') then f := f || 'P3 report callable by anon/authenticated'; end if;
  -- P4 the function's own role gate: a caller that is neither postgres nor service_role is refused
  begin
    set local role authenticated;
    perform public.svc_ai_input_observe_v1('[]'::jsonb);
    f := f || 'P4 authenticated was not refused';
  exception when others then r := r || jsonb_build_object('P4_authenticated_refused', sqlerrm);
  end;
  reset role;
  -- G settings
  r := r || jsonb_build_object('G_settings', (select jsonb_object_agg(key, jsonb_build_object('value', value, 'min', min_value, 'max', max_value, 'unit', unit, 'label', label is not null, 'used_by', used_by))
     from pipeline.platform_toolset_settings where toolset_key='pipeline' and key like 'reading.input_observ%'));
  select count(*) into n from pipeline.platform_toolset_settings where toolset_key='pipeline' and key in ('reading.input_observe_on','reading.input_observation_retention_days','reading.input_observation_purge_batch')
     and label is not null and unit is not null and used_by is not null and min_value is not null and max_value is not null;
  if n <> 3 then f := f || 'G1 settings incomplete'; end if;
  -- I idempotence (the file was applied twice)
  if (select count(*) from pipeline.platform_toolset_settings) <> p.settings_total + 3 then f := f || 'I1 settings added <> 3 after two applies'; end if;
  if (select count(*) from pg_tables where schemaname='pipeline') <> p.pipeline_tables + 1 then f := f || 'I2 tables added <> 1'; end if;
  if (select md5(string_agg(toolset_key||key||value::text, ',' order by toolset_key,key)) from pipeline.platform_toolset_settings where key not like 'reading.input_observ%') <> p.settings_md5_other then f := f || 'I3 another setting changed'; end if;
  -- W writer and input validation
  select id into v_item from pipeline.field_enrich_items where field='deadline' and state='filled' order by id desc limit 1;
  v := public.svc_ai_input_observe_v1(jsonb_build_array(
    jsonb_build_object('contract','lean-input-observation-v1','worker','rehearsal','read','course_deadline','field','deadline','item_id',1,'source_chars',30000,'sent_chars',24000,'limit_chars',24000,'cut',true,'cut_at',24000,'preflight_sent','no_signal','preflight_full','likely','fingerprint','fpA','input_sha256','a','course_id','not-a-uuid','worker_extra',repeat('x',500)),
    jsonb_build_object('contract','lean-input-observation-v1','worker',repeat('w',200),'read','course_deadline','field','deadline','item_id',v_item,'source_chars',1000,'sent_chars',1000,'cut',false,'preflight_sent','bogus','preflight_full','no_signal','fingerprint','fpA'),
    jsonb_build_object('contract','c','read','','field','x'),
    jsonb_build_object('read','course_fields','field','english')));
  r := r || jsonb_build_object('W1_first_call', v);
  if (v->>'kept')::int <> 2 then f := f || 'W1 kept<>2 (two valid, two rejected)'; end if;
  if (select preflight_sent from pipeline.ai_input_observations where item_id=v_item and contract='lean-input-observation-v1') is not null then f := f || 'W2 bad preflight not nulled'; end if;
  if (select course_id from pipeline.ai_input_observations where item_id=1 and contract='lean-input-observation-v1') is not null then f := f || 'W3 bad uuid not nulled'; end if;
  if (select length(worker) from pipeline.ai_input_observations where item_id=v_item and contract='lean-input-observation-v1') <> 60 then f := f || 'W4 worker not capped at 60'; end if;
  v := public.svc_ai_input_observe_v1('[]'::jsonb); r := r || jsonb_build_object('W5_empty', v); if (v->>'kept')::int <> 0 then f := f || 'W5 empty'; end if;
  begin v := public.svc_ai_input_observe_v1('{}'::jsonb); r := r || jsonb_build_object('W6_non_array', v);
  exception when others then f := f || ('W6 non-array input raised: ' || sqlerrm); end;
  begin v := public.svc_ai_input_observe_v1(null); r := r || jsonb_build_object('W7_null', v);
  exception when others then f := f || ('W7 null input raised: ' || sqlerrm); end;
  -- W8 a malformed number raises (the worker catches it; a failure to observe never fails a read)
  begin v := public.svc_ai_input_observe_v1('[{"contract":"c","read":"r","field":"f","source_chars":"abc"}]'::jsonb); r := r || jsonb_build_object('W8_bad_number', v);
  exception when others then r := r || jsonb_build_object('W8_bad_number_raises', sqlerrm); end;
  -- R bounded retention
  insert into pipeline.ai_input_observations (observed_at, contract, read, field) select now() - interval '40 days', 'lean-input-observation-v1', 'course_fields', 'retention-probe' from generate_series(1,3);
  update pipeline.platform_toolset_settings set value = '2'::jsonb where toolset_key='pipeline' and key='reading.input_observation_purge_batch';  -- in-transaction only, to prove the batch bound
  v := public.svc_ai_input_observe_v1(jsonb_build_array(jsonb_build_object('contract','lean-input-observation-v1','worker','rehearsal','read','course_fields','field','english','item_id',2)));
  select count(*) into n from pipeline.ai_input_observations where field='retention-probe';
  r := r || jsonb_build_object('R1_first_purge', v, 'R1_expired_left', n);
  if (v->>'expired_removed')::int <> 2 or n <> 1 then f := f || 'R1 purge not bounded to batch 2'; end if;
  v := public.svc_ai_input_observe_v1(jsonb_build_array(jsonb_build_object('contract','lean-input-observation-v1','worker','rehearsal','read','course_fields','field','english','item_id',3)));
  select count(*) into n from pipeline.ai_input_observations where field='retention-probe';
  r := r || jsonb_build_object('R2_second_purge', v, 'R2_expired_left', n);
  if n <> 0 then f := f || 'R2 expired rows remain'; end if;
  if exists (select 1 from pipeline.ai_input_observations where worker='rehearsal' and field='english' and item_id in (2,3)) is not true then f := f || 'R3 fresh rows purged'; end if;
  -- Q report
  r := r || jsonb_build_object('Q_report', (select jsonb_agg(to_jsonb(t)) from security.ai_input_observation_report_v1(1) t));
  if not exists (select 1 from security.ai_input_observation_report_v1(1) t where t.read='course_deadline' and t.field='deadline' and t.reads=2 and t.cut_reads=1
                 and t.signal_only_beyond_cut=1 and t.no_signal_but_filled=1 and t.repeated_fingerprints=1) then f := f || 'Q1 report figures'; end if;
  -- N regression: no canonical or reader data touched
  if (select count(*) from pipeline.field_enrich_items) <> p.enrich_rows then f := f || 'N1 field_enrich_items count changed'; end if;
  if (select md5(string_agg(id::text||state||coalesce(updated_at::text,''), ',' order by id)) from pipeline.field_enrich_items where id > (select max(id)-5000 from pipeline.field_enrich_items)) <> p.enrich_tail_md5 then f := f || 'N2 field_enrich_items rows changed'; end if;
  r := r || jsonb_build_object('D_def_md5', jsonb_build_object('observe', md5(pg_get_functiondef('public.svc_ai_input_observe_v1(jsonb)'::regprocedure)), 'report', md5(pg_get_functiondef('security.ai_input_observation_report_v1(int)'::regprocedure))));
  r := jsonb_build_object('verdict', case when cardinality(f) = 0 then 'PASS' else 'FAIL' end, 'failed', to_jsonb(f), 'txid', txid_current(), 'at', now()) || r;
  raise exception 'REHEARSAL_RESULT %', r::text;
end $rehearsal$;
