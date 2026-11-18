-- CF-247 Lean AI Input Phase 1b step 1 (Platform Admin 14 Nov 2026 11:37, approving admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md
-- step 1: "build the deterministic section selector / header-preserving Markdown converter ... and run the offline recall validation (zero AI spend)").
-- The offline recall check of the section selector (worker coverage-sweep v0.89.0 mode lean_sections_eval, lean-sections.ts):
--   * labelled cases, independent of the AI reader: rows a person ACCEPTED in Layer 4 for academic entry requirements (pipeline.aer_labelled_rows_v1,
--     course pages, with the exact stored page the person judged) and values read by tested university adapters (pipeline.uni_adapter_results:
--     duration, campus, delivery mode, entry requirement, intakes, fee) on the course's stored page;
--   * each case records whether the value is on the page at all, inside the first enrich.page_chars characters the current reader is sent, in the
--     converted page (lean-blocks-v1) and in the selected sections (lean-sections-v1); the report gives recall per field and the beyond-the-cut set.
-- Stored copies only: no AI call, no Firecrawl, no live fetch. Nothing is admitted, no reader, prompt, model, budget or admission rule changes,
-- and no request of any AI read changes (the selector is not used by any reader). Negative (absence) labels are not part of step 1: the selector
-- never claims absence (a page with no selection is read whole), and any skip stays unapproved (design §4, F3).
-- G1: job lean-sections-eval is catalogued. G2: switch, batch and sample size are settings. G3: no consumer API object is read or changed.
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '3s';

create table if not exists pipeline.lean_section_eval_cases (
  id                 bigint generated always as identity primary key,
  run_label          text not null,
  field              text not null,
  gold_source        text not null check (gold_source in ('aer_accepted', 'adapter')),
  source_ref         text not null,
  course_id          uuid,
  evidence_id        uuid,
  storage_path       text not null,
  gold               jsonb not null,
  state              text not null default 'pending' check (state in ('pending', 'done', 'failed')),
  leased_until       timestamptz,
  created_at         timestamptz not null default now(),
  done_at            timestamptz,
  selector           text,
  converter          text,
  worker             text,
  page_chars         integer,
  cut_chars          integer,
  lean_chars         integer,
  lean_blocks        integer,
  gold_in_page       boolean,
  gold_in_current    boolean,
  gold_in_first_cut  boolean,
  gold_in_lean       boolean,
  gold_in_selection  boolean,
  no_selection       boolean,
  selected_blocks    integer,
  selected_chars     integer,
  block_ids          jsonb,
  error              text,
  unique (run_label, field, gold_source, source_ref)
);
comment on table pipeline.lean_section_eval_cases is 'CF-247 Lean AI Input Phase 1b step 1 (Platform Admin 14 Nov 2026 11:37; admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md §4): labelled cases for the offline recall check of the section selector (worker coverage-sweep v0.89.0 mode lean_sections_eval). Each case is a stored course page and a value taken from it independently of the AI reader (gold_source aer_accepted: a Layer 4 row a person accepted; adapter: a tested university adapter reading). The worker records whether the value is on the page, inside the first enrich.page_chars characters the current reader is sent, in the converted page (lean-blocks-v1) and in the selected sections (lean-sections-v1). Measurement only: nothing reads it to decide a value. Seeded by security.lean_sections_eval_seed_v1; report security.lean_sections_eval_report_v1.';
create index if not exists lean_section_eval_cases_pending_idx on pipeline.lean_section_eval_cases (state, id) where state = 'pending';
alter table pipeline.lean_section_eval_cases enable row level security;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'reading.lean_sections_eval_on', 'Lean AI input: run the section selector recall check',
  '1: job lean-sections-eval hands labelled stored pages to the worker until every case is read (no AI, no Firecrawl). 0: nothing runs.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 1443, 'Lean AI Input Phase 1b step 1, Platform Admin 14 Nov 2026 11:37 (offline recall validation, zero AI spend)', 'Enrich fields', 'security.lean_sections_eval_fire_v1 (job lean-sections-eval)'),
 ('pipeline', 'batch.lean_sections_eval', 'Lean AI input: labelled pages read per call',
  'How many labelled stored pages one worker call converts and checks.',
  'number', '120'::jsonb, 1, 200, 'pages', 1444, 'Lean AI Input Phase 1b step 1', 'Enrich fields', 'security.lean_sections_eval_fire_v1 (job lean-sections-eval; worker mode lean_sections_eval)'),
 ('pipeline', 'reading.lean_sections_eval_sample', 'Lean AI input: labelled cases per field and source',
  'How many labelled cases the seed takes for each field and label source (a fixed hash order, so a seed can be repeated).',
  'number', '400'::jsonb, 10, 5000, 'cases', 1445, 'Lean AI Input Phase 1b step 1', 'Enrich fields', 'security.lean_sections_eval_seed_v1')
on conflict (toolset_key, key) do nothing;

-- the labelled cases, independent of the AI reader; a fixed hash order makes the sample repeatable
create or replace function security.lean_sections_eval_seed_v1(p_run text) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_n int := 0; v_k int; v_per int := greatest(1, security.pipeline_num_v1('reading.lean_sections_eval_sample', 400)::int);
begin
  -- (1) entry requirements a person accepted in Layer 4, on the very stored page the person judged
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
  select p_run, 'entry_requirements', 'aer_accepted', l.row_id::text, l.course_id, l.evidence_id, e.storage_path,
         jsonb_build_array(left(l.quote, 160))  -- fixed: the compared opening of a long quote (a quote may be cut by the reader's own limit)
    from pipeline.aer_labelled_rows_v1 l join pipeline.evidence_artifacts e on e.id = l.evidence_id
   where l.source_kind = 'course_page' and l.label = 'accepted' and length(security.aer_flat_v1(l.quote)) >= 12 and e.storage_path ~ '\.html'  -- fixed: a quote too short to identify is not a label
   order by md5(l.row_id::text) limit v_per
  on conflict do nothing;
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  -- (2) values read by tested university adapters, on the course's bound stored page
  with r as (select distinct on (x.course_id) x.id, x.course_id, x.fields from pipeline.uni_adapter_results x order by x.course_id, x.at desc),
  g as (select r.id, r.course_id, p.evidence_id, e.storage_path, f.field, f.gold
          from r join pipeline.coverage_course_pages p on p.course_id = r.course_id join pipeline.evidence_artifacts e on e.id = p.evidence_id
          cross join lateral (values
            ('duration', case when length(r.fields->'extra'->>'duration') >= 3 then jsonb_build_array(r.fields->'extra'->>'duration') end),
            ('campus', case when length(r.fields->'extra'->>'campus') >= 3 then jsonb_build_array(r.fields->'extra'->>'campus') end),
            ('delivery', case when length(r.fields->'extra'->>'mode') >= 3 then jsonb_build_array(r.fields->'extra'->>'mode') end),
            ('entry_requirements', case when length(r.fields->'extra'->>'entry_requirement') >= 20 then jsonb_build_array(left(r.fields->'extra'->>'entry_requirement', 120)) end),  -- fixed: the compared opening of a long reading
            ('intakes', case when r.fields->>'intakes_by' = 'adapter' and jsonb_typeof(r.fields->'intakes') = 'array' and jsonb_array_length(r.fields->'intakes') > 0 then r.fields->'intakes' end),
            ('fees', case when jsonb_typeof(r.fields->'fee') = 'number' and (r.fields->>'fee')::numeric >= 1000 then jsonb_build_array(round((r.fields->>'fee')::numeric)::bigint::text) end)  -- fixed: an amount below this is not a yearly tuition fee
          ) f(field, gold)
         where f.gold is not null and e.storage_path ~ '\.html'),
  s as (select g.*, row_number() over (partition by g.field order by md5(g.id::text || g.field)) rn from g)
  insert into pipeline.lean_section_eval_cases (run_label, field, gold_source, source_ref, course_id, evidence_id, storage_path, gold)
  select p_run, s.field, 'adapter', s.id::text, s.course_id, s.evidence_id, s.storage_path, s.gold from s where s.rn <= v_per
  on conflict do nothing;
  get diagnostics v_k = row_count; v_n := v_n + v_k;
  return jsonb_build_object('run', p_run, 'added', v_n, 'per_field_and_source', v_per);
end $function$;
comment on function security.lean_sections_eval_seed_v1(text) is 'CF-247 Lean AI Input Phase 1b step 1: adds the labelled cases of one run (Layer 4 accepted entry-requirement rows on their judged page; tested adapter readings on the bound page), reading.lean_sections_eval_sample per field and source in a fixed hash order. Inserts only.';
revoke all on function security.lean_sections_eval_seed_v1(text) from public, anon, authenticated;

create or replace function public.svc_lean_sections_eval_next_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('reading.lean_sections_eval_on', 0) < 1 then return '[]'::jsonb; end if;
  with pick as (select c.id from pipeline.lean_section_eval_cases c
                 where c.state = 'pending' and (c.leased_until is null or c.leased_until < now())
                 order by c.id limit greatest(1, least(coalesce(p_limit, 1), 200)) for update skip locked),  -- fixed: the setting batch.lean_sections_eval's upper bound
  upd as (update pipeline.lean_section_eval_cases c set leased_until = now() + interval '5 minutes' from pick where c.id = pick.id  -- fixed: lease, longer than one worker call
          returning c.id, c.field, c.storage_path, c.gold)
  select coalesce(jsonb_agg(jsonb_build_object('case_id', upd.id, 'field', upd.field, 'storage_path', upd.storage_path, 'gold', upd.gold) order by upd.id), '[]'::jsonb) into v from upd;
  return v;
end $function$;
comment on function public.svc_lean_sections_eval_next_v1(int) is 'CF-247 Lean AI Input Phase 1b step 1 (worker mode lean_sections_eval): leases pending labelled cases (stored page path, field, gold value) while reading.lean_sections_eval_on is 1.';
revoke all on function public.svc_lean_sections_eval_next_v1(int) from public, anon, authenticated;
grant execute on function public.svc_lean_sections_eval_next_v1(int) to service_role;

create or replace function public.svc_lean_sections_eval_record_v1(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_rows) <> 'array' then return jsonb_build_object('recorded', 0); end if;
  update pipeline.lean_section_eval_cases c set
     state = case when x->>'error' is null then 'done' else 'failed' end, leased_until = null, done_at = now(),
     selector = left(x->>'selector', 40), converter = left(x->>'converter', 40), worker = left(x->>'worker', 60),
     page_chars = (x->>'page_chars')::int, cut_chars = (x->>'cut_chars')::int, lean_chars = (x->>'lean_chars')::int, lean_blocks = (x->>'lean_blocks')::int,
     gold_in_page = (x->>'gold_in_page')::boolean, gold_in_current = (x->>'gold_in_current')::boolean, gold_in_first_cut = (x->>'gold_in_first_cut')::boolean,
     gold_in_lean = (x->>'gold_in_lean')::boolean, gold_in_selection = (x->>'gold_in_selection')::boolean, no_selection = (x->>'no_selection')::boolean,
     selected_blocks = (x->>'selected_blocks')::int, selected_chars = (x->>'selected_chars')::int,
     block_ids = case when jsonb_typeof(x->'block_ids') = 'array' then x->'block_ids' end, error = left(x->>'error', 300)
    from jsonb_array_elements(p_rows) x
   where c.id = (x->>'case_id')::bigint and c.state = 'pending';
  get diagnostics v_n = row_count;
  return jsonb_build_object('recorded', v_n);
end $function$;
comment on function public.svc_lean_sections_eval_record_v1(jsonb) is 'CF-247 Lean AI Input Phase 1b step 1 (worker mode lean_sections_eval): records each labelled case''s result (value on the page, in the first cut, in the converted page, in the selected sections; sizes; block ids).';
revoke all on function public.svc_lean_sections_eval_record_v1(jsonb) from public, anon, authenticated;
grant execute on function public.svc_lean_sections_eval_record_v1(jsonb) to service_role;

create or replace function security.lean_sections_eval_fire_v1() returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_due int; v_open int;
begin
  if security.pipeline_num_v1('reading.lean_sections_eval_on', 0) < 1 then return jsonb_build_object('on', false); end if;
  select count(*) into v_due from pipeline.lean_section_eval_cases c where c.state = 'pending' and (c.leased_until is null or c.leased_until < now());
  if v_due = 0 then return jsonb_build_object('on', true, 'due', 0, 'note', 'every labelled case is read'); end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'lean_sections_eval' and l.created_at > now() - interval '4 minutes'  -- fixed: fire guard
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  if v_open > 0 then return jsonb_build_object('on', true, 'open', v_open); end if;
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'lean_sections_eval', 'limit', security.pipeline_num_v1('batch.lean_sections_eval', 120)::int));
  return jsonb_build_object('on', true, 'due', v_due, 'sent', 1);
end $function$;
comment on function security.lean_sections_eval_fire_v1() is 'CF-247 Lean AI Input Phase 1b step 1 (job lean-sections-eval): calls worker mode lean_sections_eval while reading.lean_sections_eval_on is 1 and labelled cases are unread; no AI, no Firecrawl; does nothing when every case is read.';
revoke all on function security.lean_sections_eval_fire_v1() from public, anon, authenticated;

create or replace function security.lean_sections_eval_report_v1(p_run text default null) returns jsonb
language sql stable security definer set search_path = '' as $function$
  -- recall of the section selector on independent labels: of the cases whose value is on the stored page, the share held by the selected sections;
  -- beside it the share held by the first enrich.page_chars characters the current reader is sent, and the beyond-the-cut set (on the page, not in the cut)
  with r as (select coalesce(p_run, (select c.run_label from pipeline.lean_section_eval_cases c order by c.id desc limit 1)) run),
  c as (select x.* from pipeline.lean_section_eval_cases x join r on r.run = x.run_label),
  f as (select c.field, c.gold_source,
               count(*) cases, count(*) filter (where c.state = 'done') read, count(*) filter (where c.state = 'failed') failed,
               count(*) filter (where c.gold_in_page) on_page,
               count(*) filter (where c.gold_in_page and c.gold_in_selection) held_by_selection,
               count(*) filter (where c.gold_in_page and c.gold_in_first_cut) held_by_current_cut,
               count(*) filter (where c.gold_in_page and c.gold_in_lean) held_by_converted_page,
               count(*) filter (where c.gold_in_page and not coalesce(c.gold_in_first_cut, false)) beyond_cut,
               count(*) filter (where c.gold_in_page and not coalesce(c.gold_in_first_cut, false) and c.gold_in_selection) beyond_cut_held_by_selection,
               count(*) filter (where c.no_selection) no_selection,
               (percentile_disc(0.5) within group (order by least(c.page_chars, c.cut_chars)) filter (where c.state = 'done'))::int median_current_sent_chars,
               (percentile_disc(0.5) within group (order by c.page_chars) filter (where c.state = 'done'))::int median_page_chars,
               (percentile_disc(0.5) within group (order by c.selected_chars) filter (where c.state = 'done'))::int median_selected_chars,
               (percentile_disc(0.95) within group (order by c.selected_chars) filter (where c.state = 'done'))::int p95_selected_chars,
               (array_agg(c.id order by c.id) filter (where c.gold_in_page and not coalesce(c.gold_in_selection, false)))[1:20] missed_case_ids  -- fixed: examples shown
          from c group by c.field, c.gold_source)
  select jsonb_build_object('run', (select r.run from r), 'selector', (select max(c.selector) from c), 'converter', (select max(c.converter) from c),
    'ai_calls', 0, 'firecrawl_credits', 0,
    'fields', coalesce((select jsonb_agg(jsonb_build_object('field', f.field, 'labels', f.gold_source, 'cases', f.cases, 'read', f.read, 'failed', f.failed,
        'on_page', f.on_page, 'selection_recall', case when f.on_page > 0 then round(f.held_by_selection::numeric / f.on_page, 4) end,
        'current_cut_recall', case when f.on_page > 0 then round(f.held_by_current_cut::numeric / f.on_page, 4) end,
        'converted_page_recall', case when f.on_page > 0 then round(f.held_by_converted_page::numeric / f.on_page, 4) end,
        'beyond_cut', f.beyond_cut, 'beyond_cut_held_by_selection', f.beyond_cut_held_by_selection, 'no_selection', f.no_selection,
        'median_page_chars', f.median_page_chars, 'median_current_sent_chars', f.median_current_sent_chars,
        'median_selected_chars', f.median_selected_chars, 'p95_selected_chars', f.p95_selected_chars, 'missed_case_ids', to_jsonb(f.missed_case_ids))
        order by f.field, f.gold_source) from f), '[]'::jsonb))
$function$;
comment on function security.lean_sections_eval_report_v1(text) is 'CF-247 Lean AI Input Phase 1b step 1: selector recall on independent labels per field and label source, against the current reader''s first-cut recall; the beyond-the-cut set; sizes; missed case ids. Read-only.';
revoke all on function security.lean_sections_eval_report_v1(text) from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('lean-sections-eval', 'Course pages', 42, 'Lean AI input: section selector recall check',
  'Every 5 minutes: while reading.lean_sections_eval_on is 1 and labelled cases are unread, calls worker mode lean_sections_eval (batch.lean_sections_eval pages a call) to check the section selector on stored pages against values a person accepted or a tested adapter read. No AI, no Firecrawl; nothing admitted. Does nothing once every case is read.',
  6, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'lean-sections-eval') then
    perform cron.schedule('lean-sections-eval', '*/5 * * * *', 'select security.lean_sections_eval_fire_v1()');
  end if;
end $j$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'lean-sections-eval', 'Layer 2', 'Enrich fields', 'Lean AI Input Phase 1b step 1: offline recall check of the section selector on independent labels (no AI, no Firecrawl)', 'active', '{}', '20261114031500'),
 ('table', 'pipeline.lean_section_eval_cases', 'Layer 2', 'Enrich fields', 'Labelled cases and results of the section selector recall check', 'active', '{}', '20261114031500')
on conflict do nothing;

-- the first run's labelled cases
select security.lean_sections_eval_seed_v1('phase1b-step1-2026-11-14');

do $c$
begin
  if not exists (select 1 from cron.job where jobname = 'lean-sections-eval') or not exists (select 1 from pipeline.automation_catalogue where jobname = 'lean-sections-eval') then
    raise exception 'post-check: job lean-sections-eval scheduled and catalogued';
  end if;
  if (select count(*) from pipeline.lean_section_eval_cases where run_label = 'phase1b-step1-2026-11-14') = 0 then raise exception 'post-check: the first run has labelled cases'; end if;
  if exists (select 1 from pipeline.lean_section_eval_cases where gold_source not in ('aer_accepted', 'adapter')) then raise exception 'post-check: labels come only from people or tested adapters'; end if;
end $c$;
