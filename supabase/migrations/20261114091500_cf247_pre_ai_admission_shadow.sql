-- CF-247 Pre-AI admission gate, shadow (Decision 278, Platform Admin 14 Nov 2026 16:10, D1-D4; admin docs/audits/studysearch-pre-ai-admission-gate-design.md
-- §5; builds on docs/platform/SHARED-SOURCE-TO-PUBLISHED-ENRICHMENT-DESIGN.md §11 F3/F4/F5/F6 and LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md §4).
-- Worker coverage-sweep v0.95.0, module admission-gate.ts (pre-ai-admission-v1), judges each scholarship_ai read before it is sent and records what it
-- WOULD do. This migration adds the table those decisions go to, the insert the worker calls, the lookup of fingerprints already answered, the gate's
-- settings, a read-only report, and lets the worker read the gate's settings. Nothing else:
--   * the gate ships off (admission.gate_on = 0) and every reason ships with enforcement off (admission.enforce.<reason> = 0): no read is skipped, no
--     request, prompt, model, value, admission rule, budget, Firecrawl acquisition or Layer 4 routing changes;
--   * a reason is switched on only by a later, separate migration naming the Platform Admin's approval and the measured false-negative rate
--     (report security.pre_ai_admission_report_v1 column would_reject_but_admitted must be 0 for that reason over the agreed window);
--   * D2: the scholarship keyword score (scholarship_low_signal) is measured only: it has no enforcement switch (eleven switches, not twelve) and the
--     worker never enforces it;
--   * beside pipeline.ai_input_observations (Lean AI Phase 1) and pipeline.ai_invocations (#1128), never into them: the three join on item and
--     fingerprint;
--   * public.svc_worker_settings_v1 also returns the pipeline keys admission.%: without this the worker never sees admission.gate_on or a switch
--     (found on live 14 Nov 2026: the function returns enrich.%, reading.% and scholarship.% only). Edited only from the definition it was read
--     from (md5 5ef1c297c311ea346d95d04b2d430c34).
-- G1: no new job (the worker writes rows during reads it already makes).  G2: every threshold, retention and switch is a setting (pipeline).
-- G3: no consumer API object is read or changed.
-- Replaces: public.svc_worker_settings_v1() (same name; one added line, guarded on the live definition, md5 5ef1c297c311ea346d95d04b2d430c34).
-- Retires: nothing.

set local lock_timeout = '3s';

create table if not exists pipeline.pre_ai_admission_decisions (
  id                    bigint generated always as identity primary key,
  decided_at            timestamptz not null default now(),
  gate                  text not null,                        -- pre-ai-admission-v1
  lane                  text not null check (lane in ('aer', 'scholarship', 'tuition_fees', 'course_overview', 'course_fields')),
  lane_item             text not null,                        -- the queue the item came from: field_enrich_items, scholarship_ai_queue, ...
  item_id               text not null,
  evidence_id           uuid,
  storage_path          text,
  decision              text not null check (decision in ('admit', 'reject', 'park')),  -- what happened (admit while shadow)
  would                 text not null check (would in ('admit', 'reject', 'park')),     -- what the gate would do with every reason enforced
  shadow                boolean not null,
  reason_codes          text[] not null default '{}',
  reasons               jsonb,
  sent_chars            integer,
  tokens_saved_estimate integer,                              -- chars/4, an estimate; real tokens are in ai_invocations
  input_sha256          text,
  fingerprint           text,
  signals               jsonb,
  worker                text
);
comment on table pipeline.pre_ai_admission_decisions is 'CF-247 pre-AI admission gate (admin docs/audits/studysearch-pre-ai-admission-gate-design.md): one row per AI read judged by worker module admission-gate.ts (pre-ai-admission-v1) before it is sent: the decision, what the gate would do with every reason enforced, the reason codes, the estimated tokens a rejection would save, the input hash and fingerprint. Shadow unless admission.enforce.<reason> is on. Kept admission.retention_days.';
create index if not exists pre_ai_admission_decisions_at_idx on pipeline.pre_ai_admission_decisions (decided_at);
create index if not exists pre_ai_admission_decisions_item_idx on pipeline.pre_ai_admission_decisions (lane_item, item_id);
create index if not exists pre_ai_admission_decisions_fp_idx on pipeline.pre_ai_admission_decisions (fingerprint);
alter table pipeline.pre_ai_admission_decisions enable row level security;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'admission.gate_on', 'Pre-AI admission: judge each AI read before it is sent',
  '1: each AI read is judged by the pre-AI admission gate and the decision is recorded (pipeline.pre_ai_admission_decisions). 0: nothing is judged or recorded. With every admission.enforce.* switch at 0 the reads are exactly as before.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1450, 'Pre-AI admission gate, shadow (audit 14 Nov 2026); on only with Platform Admin approval', 'Enrich fields', 'worker coverage-sweep mode scholarship_ai (v0.95.0); enrich_ai and aer_v2_shadow later, each a separate approval'),
 ('pipeline', 'admission.min_main_chars', 'Pre-AI admission: least main text for a page to be read',
  'A stored copy with less main text than this (navigation, header and footer removed) is judged thin. 300 is the direct reader''s own floor for a read page.',
  'number', '300'::jsonb, 50, 5000, 'characters', 1451, 'Pre-AI admission gate: thin-page rule', 'Enrich fields', 'worker admission-gate.ts thin_page'),
 ('pipeline', 'admission.scholarship_min_score', 'Pre-AI admission: least scholarship signals for a single-award read',
  'Six deterministic signals (award word in title, award word in text, a value, eligibility, how to apply, who may apply). Under this score the page is judged low-signal. Measured, not guessed: see the report before raising it.',
  'number', '2'::jsonb, 0, 6, 'signals', 1452, 'Pre-AI admission gate: scholarship score', 'Enrich fields', 'worker admission-gate.ts scholarship_low_signal'),
 ('pipeline', 'admission.retention_days', 'Pre-AI admission: keep decisions for',
  'Decisions older than this are removed by the insert itself, a batch at a time (admission.purge_batch).',
  'number', '30'::jsonb, 7, 365, 'days', 1453, 'Pre-AI admission gate: bounded history', 'Enrich fields', 'public.svc_pre_ai_admission_record_v1'),
 ('pipeline', 'admission.purge_batch', 'Pre-AI admission: decisions removed per insert, at most',
  'How many expired decisions one insert removes, so a removal never holds the worker.',
  'number', '2000'::jsonb, 100, 20000, 'rows', 1454, 'Pre-AI admission gate: bounded purge', 'Enrich fields', 'public.svc_pre_ai_admission_record_v1')
on conflict (toolset_key, key) do nothing;

-- one enforcement switch per enforceable reason, all off; switching one on is its own approved change. scholarship_low_signal has none (D2: measured only)
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
select 'pipeline', 'admission.enforce.' || r, 'Pre-AI admission: enforce ' || replace(r, '_', ' '),
       '1: a read judged ' || r || ' is not sent (it is recorded with this reason and its item settles as rejected_admission, or parks for reuse/split). 0: recorded only. Switch on only after the report shows no admitted value among this reason''s would-reject reads.',
       'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1460 + o, 'Pre-AI admission gate: off until measured (audit 14 Nov 2026)', 'Enrich fields', 'worker admission-gate.ts ' || r
from unnest(array['manifest_invalid','page_not_ok','soft_block','soft_not_found','thin_page','prompt_leak','over_budget_split','aer_no_signal',
                  'scholarship_listing','fees_no_amount','duplicate_input']) with ordinality as t(r, o)
on conflict (toolset_key, key) do nothing;

create or replace function public.svc_pre_ai_admission_record_v1(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
-- CF-247 pre-AI admission gate: the worker's decisions, kept as sent (one short insert), then a bounded removal of expired rows.
-- A row that does not fit is skipped, never raised: recording a decision must never fail a read.
declare v_n int := 0; v_gone int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('kept', 0); end if;
  insert into pipeline.pre_ai_admission_decisions (gate, lane, lane_item, item_id, evidence_id, storage_path, decision, would, shadow, reason_codes, reasons,
         sent_chars, tokens_saved_estimate, input_sha256, fingerprint, signals, worker)
  select left(x->>'gate', 40), x->>'lane', left(x->>'lane_item', 60), left(x->>'item_id', 80),
         case when x->>'evidence_id' ~ '^[0-9a-f-]{36}$' then (x->>'evidence_id')::uuid end, left(x->>'storage_path', 400),
         x->>'decision', x->>'would', coalesce((x->>'shadow')::boolean, true),
         coalesce(array(select left(e, 40) from jsonb_array_elements_text(coalesce(x->'reason_codes', '[]'::jsonb)) e), '{}'),
         x->'reasons', (x->>'sent_chars')::int, (x->>'tokens_saved_estimate')::int, left(x->>'input_sha256', 64), left(x->>'fingerprint', 64),
         x->'signals', left(x->>'worker', 60)
    from jsonb_array_elements(p_rows) x
   where x->>'lane' in ('aer', 'scholarship', 'tuition_fees', 'course_overview', 'course_fields')
     and x->>'decision' in ('admit', 'reject', 'park') and x->>'would' in ('admit', 'reject', 'park')
     and coalesce(x->>'item_id', '') <> '' and coalesce(x->>'gate', '') <> '';
  get diagnostics v_n = row_count;
  delete from pipeline.pre_ai_admission_decisions d
   where d.id in (select d2.id from pipeline.pre_ai_admission_decisions d2
                   where d2.decided_at < now() - make_interval(days => security.pipeline_num_v1('admission.retention_days', 30)::int)
                   order by d2.id limit security.pipeline_num_v1('admission.purge_batch', 2000)::int);
  get diagnostics v_gone = row_count;
  return jsonb_build_object('kept', v_n, 'expired_removed', v_gone);
end $function$;
revoke all on function public.svc_pre_ai_admission_record_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_pre_ai_admission_record_v1(jsonb) to service_role;

-- the fingerprints already answered (F4 content cache): a decision of this gate that admitted a read whose answer was recorded. The worker asks before a
-- paid read; duplicate_input is measured from it (shadow) and only parks when a park route exists (none yet in scholarship_ai).
create or replace function public.svc_pre_ai_admission_seen_v1(p_fingerprints text[]) returns text[]
language plpgsql stable security definer set search_path = '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((
    select array_agg(distinct d.fingerprint)
      from pipeline.pre_ai_admission_decisions d
     where d.fingerprint = any(p_fingerprints[1:50])  -- fixed: one worker call asks for its own reads only
       and d.decision = 'admit' and d.item_id ~ '^[0-9]+$'
       and case when d.lane_item = 'scholarship_ai_queue' then exists (
                  select 1 from pipeline.scholarship_ai_queue q join pipeline.scholarship_ai_extractions x on x.id = q.extraction_id
                   where q.id = d.item_id::bigint and x.error is null and x.answer is not null)
                when d.lane_item = 'field_enrich_items' then exists (
                  select 1 from pipeline.field_enrich_items e where e.id = d.item_id::bigint and e.state in ('filled', 'review'))
                else false end), '{}');
end $function$;
revoke all on function public.svc_pre_ai_admission_seen_v1(text[]) from public, anon, authenticated;
grant execute on function public.svc_pre_ai_admission_seen_v1(text[]) to service_role;

-- the worker reads the gate's settings (admission.gate_on, the floors and the switches) through svc_worker_settings_v1
create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;
select pg_temp.edit_once('public.svc_worker_settings_v1()', '5ef1c297c311ea346d95d04b2d430c34', array[
  array[$o$or (s.toolset_key = 'pipeline' and s.key like 'scholarship.%'));  -- CF-247 scholarship recovery F10: scholarship worker sizes and waits$o$,
        $n$or (s.toolset_key = 'pipeline' and s.key like 'scholarship.%')  -- CF-247 scholarship recovery F10: scholarship worker sizes and waits
              or (s.toolset_key = 'pipeline' and s.key like 'admission.%'));  -- CF-247 pre-AI admission gate (Decision 278): its switch, floors and enforcement switches$n$]]);

create or replace function security.pre_ai_admission_report_v1(p_hours int default 168) returns table (
  lane text, reason text, judged bigint, would_reject bigint, would_reject_share numeric, tokens_saved_estimate bigint,
  would_reject_but_admitted bigint, would_reject_but_spent_usd numeric)
language sql stable security definer set search_path = '' as $function$
  -- CF-247 pre-AI admission gate, read-only: per lane and reason over the last p_hours, how many reads the reason would have stopped, the tokens
  -- that would have saved, and the false-negative measure: would_reject_but_admitted counts reads the reason would have stopped whose answer was
  -- admitted anyway (scholarship verdict 'scholarship'; an enrichment item filled or sent to review). It must be 0 before admission.enforce.<reason>
  -- is proposed. would_reject_but_spent_usd is what those reads actually cost.
  with d as (select * from pipeline.pre_ai_admission_decisions a where a.decided_at > now() - make_interval(hours => greatest(1, p_hours))),
  r as (select d.*, unnest(case when cardinality(d.reason_codes) = 0 then array['(none)'] else d.reason_codes end) code from d),
  o as (
    select r.*,
           case when r.lane_item = 'scholarship_ai_queue' then (select x.verdict = 'scholarship' from pipeline.scholarship_ai_queue q
                     join pipeline.scholarship_ai_extractions x on x.id = q.extraction_id where q.id::text = r.item_id)
                when r.lane_item = 'field_enrich_items' then (select e.state in ('filled', 'review') from pipeline.field_enrich_items e where e.id::text = r.item_id)
           end admitted,
           case when r.lane_item = 'scholarship_ai_queue' then (select x.cost_usd from pipeline.scholarship_ai_queue q
                     join pipeline.scholarship_ai_extractions x on x.id = q.extraction_id where q.id::text = r.item_id)
                when r.lane_item = 'field_enrich_items' then (select e.cost_usd from pipeline.field_enrich_items e where e.id::text = r.item_id)
           end spent
      from r)
  select o.lane, o.code, count(*), count(*) filter (where o.would <> 'admit'), round(avg((o.would <> 'admit')::int)::numeric, 3),
         sum(o.tokens_saved_estimate)::bigint, count(*) filter (where o.would <> 'admit' and o.admitted is true),
         round(sum(o.spent) filter (where o.would <> 'admit'), 4)
    from o group by o.lane, o.code order by count(*) desc
$function$;
revoke all on function security.pre_ai_admission_report_v1(int) from public, anon, authenticated;
grant execute on function security.pre_ai_admission_report_v1(int) to service_role;

do $c$
begin
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'admission.gate_on' and value = '0'::jsonb) then
    raise exception 'post-check: the gate ships off';
  end if;
  if exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'admission.enforce.%' and value <> '0'::jsonb) then
    raise exception 'post-check: every enforcement switch ships off';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'admission.enforce.%') <> 11 then
    raise exception 'post-check: one enforcement switch per enforceable reason (eleven)';
  end if;
  if exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'admission.enforce.scholarship_low_signal') then
    raise exception 'post-check: the scholarship score is measured only (Decision 278 D2)';
  end if;
  if position('admission.%' in pg_get_functiondef('public.svc_worker_settings_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: the worker reads the gate settings';
  end if;
end $c$;
