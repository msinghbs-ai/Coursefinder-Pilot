begin isolation level repeatable read;
-- Lean AI Input Phase 1b-3 bundle: rolled-back rehearsal of 20261114091500. Forced rollback: the final DO block always raises. No worker is called.
create temp table _rh_pre on commit drop as select
  (select count(*) from pipeline.platform_toolset_settings) settings_total,
  (select md5(string_agg(toolset_key||key||value::text, ',' order by toolset_key,key)) from pipeline.platform_toolset_settings) settings_md5,
  (select count(*) from cron.job) cron_jobs, (select count(*) from pipeline.field_enrich_items) enrich_rows, (select count(*) from pipeline.fee_reader_queue) fee_rows,
  (select count(*) from pipeline.lean_section_eval_cases) eval_rows, (select count(*) from pipeline.ai_invocations) invocations;
-- begin migration
-- CF-247 Lean AI Input Phase 1b-3, qualification of the selected input for fees and intakes (Platform Admin 14 Nov 2026 17:20: "Approve the
-- Phase 1b-3 Fees & Intakes qualification plan with the hard US$2.00 ceiling (against stored pages only, nothing admitted)"; admin
-- docs/platform/LEAN-AI-INPUT-PHASE1B-3-QUALIFICATION-PLAN-FEES-INTAKES.md). Worker coverage-sweep v0.94.0, mode lean_qualify (lean-qualify.ts):
--   * each labelled stored page is read twice on its service's pinned route (fees: fee_reader; intakes: course_other_fields), with today's input
--     (baseline) and with the lean-sections-v3 selected [B#] blocks (candidate); same instructions and context in both arms, the candidate adds
--     one line saying the text comes as blocks (candidate prompt versions fee-reader+blocks-v1, course-intakes+blocks-v1, active nowhere);
--   * positives: run phase1b-step1d-2026-11-14 cases whose label is in the reader's text (fees 257, intakes 228); negatives (up to
--     reading.lean_qualify_negatives per field): course pages the fee reader read and found no fee row on, and course pages the Enrich reader
--     said do not state the intakes (kept only when the whole page shows no start-date signal);
--   * answers go to pipeline.lean_qualify_cases only: nothing is admitted, published, proposed or sent to Layer 4, and no value table is written;
--   * spend: the database hands out no case once the run's recorded cost reaches reading.lean_qualify_ceiling_usd (US$2.00), nor while a route
--     is held (credit floor); stored copies only, no Firecrawl; the job ships off (reading.lean_qualify_on 0) and is switched on only after the
--     on-demand request is opened (security.on_demand_open_v1);
--   * a pass switches nothing on: activation (1b-4) is a separate per-service setting the Platform Admin changes.
-- The same release ships lean-sections-v3 (entry score lines are signals; the offline recall check and the shadow use it).
-- G1: job lean-qualify catalogued. G2: switch, batch, ceiling and negatives are settings. G3: no consumer API object is read or changed.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '3s';

create table if not exists pipeline.lean_qualify_cases (
  id            bigint generated always as identity primary key,
  created_at    timestamptz not null default now(),
  run_label     text not null,
  field         text not null check (field in ('fees', 'intakes')),
  kind          text not null check (kind in ('positive', 'negative')),
  source_ref    text not null,
  course_id     uuid,
  evidence_id   uuid,
  storage_path  text not null,
  gold          jsonb not null default '[]'::jsonb,
  state         text not null default 'pending' check (state in ('pending', 'done', 'failed', 'skipped')),
  leased_until  timestamptz,
  attempts      integer not null default 0,
  result        jsonb,
  cost_usd      numeric not null default 0,
  done_at       timestamptz,
  error         text,
  unique (run_label, field, kind, source_ref)
);
comment on table pipeline.lean_qualify_cases is 'CF-247 Lean AI Input Phase 1b-3 (Platform Admin 14 Nov 2026 17:20; admin docs/platform/LEAN-AI-INPUT-PHASE1B-3-QUALIFICATION-PLAN-FEES-INTAKES.md): fees and intakes qualification cases (positives with their independent label, negatives) and, per case, the baseline and candidate answers of worker mode lean_qualify with their checks, tokens and cost. Qualification only: nothing here is admitted or read by any reader; a pass switches nothing on.';
create index if not exists lean_qualify_cases_pending_idx on pipeline.lean_qualify_cases (state, id) where state = 'pending';
alter table pipeline.lean_qualify_cases enable row level security;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'reading.lean_qualify_on', 'Lean AI input: fees and intakes qualification run',
  '1: the qualification job hands stored labelled pages to worker mode lean_qualify, each read twice (today''s input and the selected blocks) on the pinned route; answers are recorded, nothing is admitted. 0: nothing runs. Switched on only with an open on-demand request.',
  'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1448, 'Lean AI Input Phase 1b-3, Platform Admin 14 Nov 2026 17:20 (ships off)', 'Enrich fields', 'job lean-qualify; public.svc_lean_qualify_next_v1'),
 ('pipeline', 'batch.lean_qualify', 'Lean AI input: qualification pages per worker call',
  'How many labelled pages one worker call reads (two AI reads each).',
  'number', '6'::jsonb, 1, 20, 'pages', 1449, 'Lean AI Input Phase 1b-3: two reads a page inside one worker call''s time budget', 'Enrich fields', 'security.lean_qualify_fire_v1'),
 ('pipeline', 'reading.lean_qualify_ceiling_usd', 'Lean AI input: qualification spend ceiling',
  'No qualification page is handed out once the run''s recorded AI cost reaches this amount.',
  'number', '2'::jsonb, 0, 5, 'US$', 1450, 'Lean AI Input Phase 1b-3: hard ceiling approved by the Platform Admin, 14 Nov 2026 17:20', 'Enrich fields', 'public.svc_lean_qualify_next_v1'),
 ('pipeline', 'reading.lean_qualify_negatives', 'Lean AI input: qualification negatives per field',
  'How many pages with no labelled value are added per field to measure false values.',
  'number', '100'::jsonb, 0, 400, 'pages', 1451, 'Lean AI Input Phase 1b-3 plan section 2', 'Enrich fields', 'security.lean_qualify_seed_v1')
on conflict (toolset_key, key) do nothing;

create or replace function security.lean_qualify_seed_v1(p_run text) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_n int := 0; v_k int; v_neg int := greatest(0, security.pipeline_num_v1('reading.lean_qualify_negatives', 100)::int);
begin
  -- positives: run phase1b-step1d-2026-11-14 cases whose label is in the reader's own text
  insert into pipeline.lean_qualify_cases (run_label, field, kind, source_ref, course_id, evidence_id, storage_path, gold)
  select p_run, x.field, 'positive', x.source_ref, x.course_id, x.evidence_id, x.storage_path, x.gold
    from pipeline.lean_section_eval_cases x
   where x.run_label = 'phase1b-step1d-2026-11-14' and x.field in ('fees', 'intakes') and x.state = 'done' and x.gold_in_current
  on conflict do nothing;
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  -- fee negatives: course pages the fee reader read with an AI call and found no fee row on
  insert into pipeline.lean_qualify_cases (run_label, field, kind, source_ref, course_id, evidence_id, storage_path)
  select p_run, 'fees', 'negative', 'fee_reader_queue:' || q.id, q.course_id, q.evidence_id, e.storage_path
    from pipeline.fee_reader_queue q join pipeline.evidence_artifacts e on e.id = q.evidence_id
   where q.state = 'done' and q.rows_found = 0 and q.course_id is not null and coalesce(q.cost_usd, 0) > 0 and e.storage_path ~ '\.html'
     and not exists (select 1 from pipeline.lean_qualify_cases z where z.run_label = p_run and z.field = 'fees' and z.course_id = q.course_id)
   order by md5(q.id::text) limit v_neg
  on conflict do nothing;
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  -- intakes negatives: course pages the Enrich reader said do not state the intakes (the worker keeps only pages with no start-date signal)
  insert into pipeline.lean_qualify_cases (run_label, field, kind, source_ref, course_id, evidence_id, storage_path)
  select p_run, 'intakes', 'negative', 'field_enrich_items:' || i.id, i.course_id, i.evidence_id, i.storage_path
    from pipeline.field_enrich_items i
   where i.field = 'intakes' and i.state = 'skipped' and i.reason = 'the page does not state it' and i.storage_path ~ '\.html'
     and not exists (select 1 from pipeline.lean_qualify_cases z where z.run_label = p_run and z.field = 'intakes' and z.course_id = i.course_id)
   order by md5(i.id::text) limit v_neg
  on conflict do nothing;
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  return jsonb_build_object('run', p_run, 'added', v_n);
end $function$;
comment on function security.lean_qualify_seed_v1(text) is 'CF-247 Lean AI Input Phase 1b-3: adds one run''s qualification cases (run phase1b-step1d-2026-11-14 positives for fees and intakes; up to reading.lean_qualify_negatives negatives per field in a fixed hash order). Inserts only.';
revoke all on function security.lean_qualify_seed_v1(text) from public, anon, authenticated;

create or replace function public.svc_lean_qualify_next_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v jsonb; v_run text; v_spent numeric; v_fee jsonb := security.ai_route_v1('fee_reader'); v_int jsonb := security.ai_route_v1('course_other_fields');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('reading.lean_qualify_on', 0) < 1 then return '[]'::jsonb; end if;
  select c.run_label into v_run from pipeline.lean_qualify_cases c where c.state = 'pending' order by c.id limit 1;
  if v_run is null then return '[]'::jsonb; end if;
  -- the hard ceiling: nothing more is handed out once the run's recorded cost reaches it
  select coalesce(sum(c.cost_usd), 0) into v_spent from pipeline.lean_qualify_cases c where c.run_label = v_run;
  if v_spent >= security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0) then return '[]'::jsonb; end if;
  with pick as (select c.id from pipeline.lean_qualify_cases c
                 where c.run_label = v_run and c.state = 'pending' and (c.leased_until is null or c.leased_until < now()) and c.attempts < 2  -- fixed: two tries
                   and ((c.field = 'fees' and coalesce((v_fee->>'held')::boolean, true) = false and v_fee->>'model' is not null)
                     or (c.field = 'intakes' and coalesce((v_int->>'held')::boolean, true) = false and v_int->>'model' is not null))
                 order by c.id limit greatest(1, least(coalesce(p_limit, 1), 20)) for update skip locked),  -- fixed: the setting batch.lean_qualify's upper bound
  upd as (update pipeline.lean_qualify_cases c set leased_until = now() + interval '5 minutes', attempts = c.attempts + 1 from pick where c.id = pick.id  -- fixed: lease, longer than one worker call
          returning c.*)
  select coalesce(jsonb_agg(jsonb_build_object('case_id', u.id, 'field', u.field, 'kind', u.kind, 'storage_path', u.storage_path, 'gold', u.gold,
           'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'title', co.canonical_title, 'url', e.source_url,
           'profile', case when u.field = 'fees' then (select to_jsonb(cp) - 'reason' - 'updated_by' - 'updated_at' from pipeline.fee_country_profiles cp where cp.country_code = k.iso_alpha2) end,
           'courses', case when u.field = 'fees' and co.id is not null then jsonb_build_array(jsonb_build_object('id', co.id, 'title', co.canonical_title, 'level', sl.code)) else '[]'::jsonb end,
           'page_chars', security.pipeline_num_v1('fees.page_chars', 40000)::int,
           'model', case when u.field = 'fees' then v_fee->>'model' else v_int->>'model' end,
           'models', case when u.field = 'fees' then v_fee->'models' else v_int->'models' end) order by u.id), '[]'::jsonb) into v
    from upd u left join catalogue.courses co on co.id = u.course_id left join ref.study_levels sl on sl.id = co.study_level_id
    left join catalogue.providers p on p.id = co.provider_id left join ref.countries k on k.id = p.country_id
    left join pipeline.evidence_artifacts e on e.id = u.evidence_id;
  return v;
end $function$;
comment on function public.svc_lean_qualify_next_v1(int) is 'CF-247 Lean AI Input Phase 1b-3 (worker mode lean_qualify): leases pending qualification pages with their label, course context and the service''s pinned route, while reading.lean_qualify_on is 1, the run''s recorded cost is below reading.lean_qualify_ceiling_usd and the route is not held.';
revoke all on function public.svc_lean_qualify_next_v1(int) from public, anon, authenticated;
grant execute on function public.svc_lean_qualify_next_v1(int) to service_role;

create or replace function public.svc_lean_qualify_record_v1(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows) <> 'array' then return jsonb_build_object('recorded', 0); end if;
  update pipeline.lean_qualify_cases c set
     state = case when x->>'error' = 'time budget' then 'pending' when x->>'error' is not null then 'failed' when (x->>'not_negative')::boolean then 'skipped' else 'done' end,
     leased_until = null, done_at = case when x->>'error' = 'time budget' then null else now() end, result = x - 'case_id', error = left(x->>'error', 300),
     cost_usd = c.cost_usd + coalesce((x#>>'{arms,baseline,cost}')::numeric, 0) + coalesce((x#>>'{arms,candidate,cost}')::numeric, 0)
    from jsonb_array_elements(p_rows) x
   where c.id = (x->>'case_id')::bigint and c.state = 'pending';
  get diagnostics v_n = row_count;
  return jsonb_build_object('recorded', v_n);
end $function$;
comment on function public.svc_lean_qualify_record_v1(jsonb) is 'CF-247 Lean AI Input Phase 1b-3 (worker mode lean_qualify): records each page''s baseline and candidate answers with their checks and cost; a page out of time goes back to pending; writes nothing else.';
revoke all on function public.svc_lean_qualify_record_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_lean_qualify_record_v1(jsonb) to service_role;

create or replace function security.lean_qualify_fire_v1() returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_due int; v_open int;
begin
  if security.pipeline_num_v1('reading.lean_qualify_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  select count(*) into v_due from pipeline.lean_qualify_cases c where c.state = 'pending' and (c.leased_until is null or c.leased_until < now()) and c.attempts < 2;  -- fixed: two tries
  if v_due = 0 then return jsonb_build_object('on', true, 'due', 0, 'note', 'every qualification page is read'); end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'lean_qualify' and l.created_at > now() - interval '3 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  if v_open >= 2 then return jsonb_build_object('on', true, 'open', v_open); end if;  -- fixed: at most two worker calls at once
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'lean_qualify', 'limit', security.pipeline_num_v1('batch.lean_qualify', 6)::int));
  return jsonb_build_object('on', true, 'due', v_due, 'sent', 1);
end $function$;
comment on function security.lean_qualify_fire_v1() is 'CF-247 Lean AI Input Phase 1b-3 (job lean-qualify): calls worker mode lean_qualify while reading.lean_qualify_on is 1 and qualification pages are unread; the ceiling and route holds are enforced by public.svc_lean_qualify_next_v1.';
revoke all on function security.lean_qualify_fire_v1() from public, anon, authenticated;

create or replace function security.lean_qualify_report_v1(p_run text default null) returns jsonb
language sql stable security definer set search_path = '' as $function$
  -- per field and kind: pages, reads, cost, the label found by each arm, losses and gains, false values on negatives, quote and answer
  -- checks, input tokens; and the plan's acceptance criteria (section 4) per field
  with r as (select coalesce(p_run, (select c.run_label from pipeline.lean_qualify_cases c order by c.id desc limit 1)) run),
  c as (select x.*, (x.result#>>'{arms,baseline,found}')::boolean bf, (x.result#>>'{arms,candidate,found}')::boolean cf,
               coalesce((x.result#>>'{arms,baseline,values}')::int, 0) bv, coalesce((x.result#>>'{arms,candidate,values}')::int, 0) cv,
               (x.result#>>'{arms,baseline,schema_ok}')::boolean bs, (x.result#>>'{arms,candidate,schema_ok}')::boolean cs,
               (x.result#>>'{arms,candidate,quote_ok}')::boolean cq, (x.result#>>'{arms,baseline,input_tokens}')::int bt, (x.result#>>'{arms,candidate,input_tokens}')::int ct,
               x.result#>>'{arms,baseline,skipped}' bsk, x.result#>>'{arms,candidate,skipped}' csk
          from pipeline.lean_qualify_cases x join r on r.run = x.run_label),
  f as (select c.field, c.kind, count(*) pages, count(*) filter (where c.state = 'done') read, count(*) filter (where c.state = 'failed') failed,
               count(*) filter (where c.state = 'skipped') not_clean_negative, count(*) filter (where c.state = 'pending') pending, round(sum(c.cost_usd), 4) cost_usd,
               count(*) filter (where c.bf) base_found, count(*) filter (where c.cf) cand_found,
               count(*) filter (where c.bf and not coalesce(c.cf, false)) lost, count(*) filter (where c.cf and not coalesce(c.bf, false)) won,
               count(*) filter (where c.state = 'done' and c.bv > 0) base_values, count(*) filter (where c.state = 'done' and c.cv > 0) cand_values,
               count(*) filter (where c.state = 'done' and c.csk is null) cand_reads, count(*) filter (where c.state = 'done' and c.csk is null and c.cs) cand_schema_ok,
               count(*) filter (where c.state = 'done' and c.cv > 0) cand_with_value, count(*) filter (where c.state = 'done' and c.cv > 0 and c.cq) cand_quote_ok,
               (percentile_disc(0.5) within group (order by c.bt) filter (where c.bt is not null))::int median_base_tokens,
               (percentile_disc(0.5) within group (order by c.ct) filter (where c.ct is not null))::int median_cand_tokens
          from c group by c.field, c.kind)
  select jsonb_build_object('run', (select r.run from r), 'ceiling_usd', security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0),
    'cost_usd', (select round(coalesce(sum(c.cost_usd), 0), 4) from c), 'admitted', 0,
    'groups', coalesce((select jsonb_agg(to_jsonb(f) order by f.field, f.kind) from f), '[]'::jsonb),
    'criteria', coalesce((select jsonb_agg(jsonb_build_object('field', p.field,
        'no_loss', p.lost = 0, 'no_new_false_values', coalesce(n.cand_values, 0) <= coalesce(n.base_values, 0),
        'quotes_in_text', p.cand_with_value = p.cand_quote_ok,
        'answers_valid_99', case when p.cand_reads > 0 then round(p.cand_schema_ok::numeric / p.cand_reads, 4) >= 0.99 end,
        'fewer_tokens', p.median_cand_tokens < p.median_base_tokens, 'all_read', p.pending = 0 and coalesce(n.pending, 0) = 0)) from f p left join f n on n.field = p.field and n.kind = 'negative' where p.kind = 'positive'), '[]'::jsonb))
$function$;
comment on function security.lean_qualify_report_v1(text) is 'CF-247 Lean AI Input Phase 1b-3: the fees and intakes qualification result per field and kind (labels found by each arm, losses, gains, false values on negatives, quote and answer checks, tokens, cost) and the plan''s acceptance criteria. Read-only.';
revoke all on function security.lean_qualify_report_v1(text) from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('lean-qualify', 'Course pages', 43, 'Lean AI input: fees and intakes qualification',
  'Every minute: while reading.lean_qualify_on is 1 and qualification pages are unread, calls worker mode lean_qualify (batch.lean_qualify pages a call) to read each labelled stored page twice on the pinned route (today''s input and the selected blocks). Stops at reading.lean_qualify_ceiling_usd. Stored copies only; nothing admitted. Ships off.',
  6, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'lean-qualify') then
    perform cron.schedule('lean-qualify', '* * * * *', 'select security.lean_qualify_fire_v1()');
  end if;
end $j$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'lean-qualify', 'Layer 2', 'Enrich fields', 'Lean AI Input Phase 1b-3: fees and intakes qualification of the selected input on stored pages (ships off, US$2.00 ceiling, nothing admitted)', 'active', '{}', '20261114091500'),
 ('table', 'pipeline.lean_qualify_cases', 'Layer 2', 'Enrich fields', 'Fees and intakes qualification cases and both arms'' answers', 'active', '{}', '20261114091500')
on conflict do nothing;

select security.lean_qualify_seed_v1('phase1b-3-fees-intakes-2026-11-14');

do $c$
begin
  if security.pipeline_num_v1('reading.lean_qualify_on', 1) <> 0 then raise exception 'post-check: the qualification ships off'; end if;
  if (select count(*) from pipeline.lean_qualify_cases where run_label = 'phase1b-3-fees-intakes-2026-11-14' and kind = 'positive') = 0 then raise exception 'post-check: positives seeded'; end if;
  if not exists (select 1 from cron.job where jobname = 'lean-qualify') or not exists (select 1 from pipeline.automation_catalogue where jobname = 'lean-qualify') then
    raise exception 'post-check: job lean-qualify scheduled and catalogued';
  end if;
  if jsonb_array_length(public.svc_lean_qualify_next_v1(6)) <> 0 then raise exception 'post-check: nothing is handed out while the switch is off'; end if;
end $c$;
-- end of migration
do $rehearsal$
declare p record; r jsonb := '{}'; f text[] := '{}'; v jsonb; q text := current_query(); c1 bigint; c2 bigint;
begin
  select * into p from _rh_pre;
  r := r || jsonb_build_object('X1_migration_md5', md5(substr(q, strpos(q, '-- begin migration') + length('-- begin migration') + 1, strpos(q, E'\n-- end of migration') - strpos(q, '-- begin migration') - length('-- begin migration') - 1)));
  -- S: settings
  if (select count(*) from pipeline.platform_toolset_settings) <> p.settings_total + 4 then f := f || 'S1 settings +4'; end if;
  if security.pipeline_num_v1('reading.lean_qualify_on', 9) <> 0 or security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 9) <> 2 then f := f || 'S2 off and US$2'; end if;
  -- C: seeded cases
  r := r || jsonb_build_object('C_seed', (select jsonb_object_agg(field || ':' || kind, n) from (select field, kind, count(*) n from pipeline.lean_qualify_cases group by 1,2) z));
  if (select count(*) from pipeline.lean_qualify_cases where kind = 'positive' and field = 'fees') <> 257 or (select count(*) from pipeline.lean_qualify_cases where kind = 'positive' and field = 'intakes') <> 228 then f := f || 'C1 positives 257/228'; end if;
  if (select count(*) from pipeline.lean_qualify_cases where kind = 'negative' and field = 'fees') not between 1 and 100 or (select count(*) from pipeline.lean_qualify_cases where kind = 'negative' and field = 'intakes') not between 1 and 100 then f := f || 'C2 negatives'; end if;
  -- N: off hands out nothing
  if jsonb_array_length(public.svc_lean_qualify_next_v1(6)) <> 0 then f := f || 'N1 off'; end if;
  v := security.lean_qualify_fire_v1(); if (v->>'on')::boolean then f := f || 'N2 fire while off'; end if;
  -- L: on (inside this transaction only) hands out pages with their context and the pinned route
  update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'reading.lean_qualify_on';
  v := public.svc_lean_qualify_next_v1(6);
  r := r || jsonb_build_object('L_sample', (v->0) - 'gold' - 'profile' - 'courses', 'L_n', jsonb_array_length(v));
  if jsonb_array_length(v) <> 6 then f := f || 'L1 six handed out'; end if;
  if exists (select 1 from jsonb_array_elements(v) x where x->>'model' is null or jsonb_typeof(x->'models') <> 'array' or x->>'provider' is null or x->>'storage_path' is null or x->>'title' is null) then f := f || 'L2 context'; end if;
  if exists (select 1 from jsonb_array_elements(v) x where x->>'field' = 'fees' and (x->'profile' is null or jsonb_array_length(x->'courses') <> 1)) then f := f || 'L3 fee context'; end if;
  c1 := (v->0->>'case_id')::bigint; c2 := (v->1->>'case_id')::bigint;
  -- R: record keeps both arms and adds their cost; a page out of time goes back to pending
  v := public.svc_lean_qualify_record_v1(jsonb_build_array(
    jsonb_build_object('case_id', c1, 'arms', jsonb_build_object('baseline', jsonb_build_object('found', true, 'cost', 0.0007, 'schema_ok', true, 'values', 1), 'candidate', jsonb_build_object('found', true, 'cost', 0.0004, 'schema_ok', true, 'values', 1, 'quote_ok', true))),
    jsonb_build_object('case_id', c2, 'error', 'time budget')));
  if (v->>'recorded')::int <> 2 then f := f || 'R1 recorded 2'; end if;
  if (select state || ':' || cost_usd from pipeline.lean_qualify_cases where id = c1) <> 'done:0.0011' then f := f || 'R2 done with cost'; end if;
  if (select state from pipeline.lean_qualify_cases where id = c2) <> 'pending' then f := f || 'R3 time budget back to pending'; end if;
  -- K: the ceiling: once the run's cost reaches it, nothing more is handed out
  update pipeline.platform_toolset_settings set value = '0.001'::jsonb where toolset_key = 'pipeline' and key = 'reading.lean_qualify_ceiling_usd';
  if jsonb_array_length(public.svc_lean_qualify_next_v1(6)) <> 0 then f := f || 'K1 ceiling'; end if;
  v := security.lean_qualify_report_v1(null); r := r || jsonb_build_object('Q_report', v->'criteria', 'Q_cost', v->'cost_usd', 'Q_admitted', v->'admitted');
  if (v->>'admitted')::int <> 0 or (v->>'cost_usd')::numeric <> 0.0011 then f := f || 'Q1 report'; end if;
  -- J/N: job catalogued; nothing else touched
  if (select count(*) from cron.job) <> p.cron_jobs + 1 or not exists (select 1 from pipeline.automation_catalogue where jobname = 'lean-qualify') then f := f || 'J1 job'; end if;
  if (select count(*) from pipeline.field_enrich_items) <> p.enrich_rows or (select count(*) from pipeline.fee_reader_queue) <> p.fee_rows or (select count(*) from pipeline.lean_section_eval_cases) <> p.eval_rows or (select count(*) from pipeline.ai_invocations) <> p.invocations then f := f || 'N3 other data changed'; end if;
  r := jsonb_build_object('verdict', case when cardinality(f) = 0 then 'PASS' else 'FAIL' end, 'failed', to_jsonb(f), 'txid', txid_current(), 'at', now()) || r;
  raise exception 'REHEARSAL_RESULT %', r::text;
end $rehearsal$;
