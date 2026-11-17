-- CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 22:05 and 22:45): the Boost model benchmark. The same study load reading as Boost extraction
-- (worker boost.ts, prompt boost-study-load-v1), asked of each named candidate model for the same stored course pages, so the models can be
-- compared on verified rate, failures, tokens, cost and time before one is qualified for admission.
-- What it adds:
--   1. The route boost_extract_benchmark in Models & services: the three named allowed candidates (Qwen3 30B, Mistral Small 3.2, MiMo v2.6
--      Flash), each asked directly for every page (never as a fallback), with its own daily spend and call caps.
--   2. pipeline.boost_benchmark_items: one row per (run, stored page, model) with the answer, the check's verdict, tokens, cost and time.
--   3. A run is named by the setting boost.benchmark_label. When the label has no rows the next claim builds its cohort: up to
--      boost.benchmark_pages_per_country stored course pages of courses with no study load for each country of the Boost priority matrix.
--      Changing the label on Settings › Pipeline settings › Boost starts a new run.
--   4. Job boost-benchmark, every 2 minutes, only while the run named by the label has work left (and the switch is on, Maintenance Mode is
--      off and the squash blackout is not on): worker coverage-sweep mode boost_benchmark.
-- What it does not do: nothing is written to the catalogue, to Storage staging-boost or to pipeline.boost_inbound_staging, and no model is
-- qualified for admission (pipeline.boost_model_qualifications). The results stay in pipeline.boost_benchmark_items.
-- G1: job boost-benchmark is catalogued. G2: sizes are settings; the job command holds no number. G3: no consumer API object is read or changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('security.boost_lane_category_v1(text)') is null or to_regclass('pipeline.boost_extract_items') is null then
    raise exception 'the Boost matrix (20261117223000) or Boost extraction (20261117235000) is not there';
  end if;
  if (select count(*) from pipeline.ai_model_catalogue where code in ('qwen3-30b', 'mistral-small-3.2', 'mimo-v2.6-flash') and status = 'allowed') <> 3 then
    raise exception 'the three candidate models are not all allowed models in the catalogue';
  end if;
end $pre$;

-- 1. The route and its candidates
insert into pipeline.ai_service_routes(service_code, label, area, field, lane, ledger_match, cascade, daily_usd_cap, daily_calls_cap, prompt_source, enabled, resolver,
                                       purpose_group, migration_state, previous_model, note, sort, reason)
values ('boost_extract_benchmark', 'Boost extraction benchmark (study load)', 'Boost', null, 'boost_benchmark', null, array['qwen3-30b', 'mistral-small-3.2', 'mimo-v2.6-flash'], 1, 2000,
        'worker code: boost.ts (boost-study-load-v1)', true, 'route', 'reads', 'routed', null,
        'Benchmark only. Each model listed is asked directly for every page of a benchmark run (not as a fallback). Nothing it answers is staged or admitted; results are in pipeline.boost_benchmark_items.',
        161, 'S2 - BOOST 17 Nov 2026 (Platform Admin 22:05 and 22:45: benchmark Qwen3 30B, Mistral Small 3.2 and MiMo v2.6 Flash)')
on conflict (service_code) do nothing;

insert into pipeline.ai_route_qualifications(service_code, model_code, prompt_version, status, provisional, evidence, note)
select 'boost_extract_benchmark', m.code, 'boost-study-load-v1', 'qualified', true,
       'Platform Admin 17 Nov 2026 22:05 and 22:45: named benchmark candidate',
       'S2 - BOOST 17 Nov 2026: lets the benchmark ask this model. It qualifies nothing for admission and nothing for the route boost_extract'
  from pipeline.ai_model_catalogue m
 where m.code in ('qwen3-30b', 'mistral-small-3.2', 'mimo-v2.6-flash')
   and not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract_benchmark' and q.model_code = m.code);

-- 2. Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'boost.benchmark_on', 'Boost benchmark: on (1) or off (0)',
  'Whether job boost-benchmark works through the benchmark run named below. Off stops it at once; what is done is kept.',
  'number', to_jsonb(1), 0, 1, 'switch', 960, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:45', 'Boost', 'security.boost_benchmark_gate_v1 (job boost-benchmark)'),
 ('pipeline', 'boost.benchmark_label', 'Boost benchmark: run label',
  'The name of the benchmark run. A label with no results yet starts a new run: its pages are chosen on the next job run. Lower-case letters, digits and hyphens.',
  'text', to_jsonb('bench-1'::text), null, null, 'label', 961, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:45', 'Boost', 'security.boost_benchmark_claim_v1'),
 ('pipeline', 'boost.benchmark_pages_per_country', 'Boost benchmark: stored pages per country',
  'The most stored course pages a benchmark run takes for each country of the Boost priority matrix. Every page is asked of every candidate model.',
  'number', to_jsonb(200), 1, 1000, 'pages', 962, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:45', 'Boost', 'security.boost_benchmark_claim_v1'),
 ('pipeline', 'batch.boost_benchmark', 'Boost benchmark: pages per run',
  'How many pages job boost-benchmark takes in one run (every 2 minutes while a benchmark has work left). Each page is one call to each candidate model.',
  'number', to_jsonb(8), 1, 50, 'pages', 963, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:45', 'Boost', 'job boost-benchmark')
on conflict (toolset_key, key) do nothing;

-- 3. The results
create table if not exists pipeline.boost_benchmark_items (
  id               bigint generated always as identity primary key,
  run_label        text not null,
  item_key         text not null,
  entity_id        uuid not null,
  evidence_id      uuid not null,
  storage_path     text not null,
  source_url       text,
  title            text,
  country_code     text not null,
  model_code       text not null,
  model_identifier text not null,
  state            text not null default 'queued' check (state in ('queued', 'claimed', 'verified', 'rejected', 'failed', 'no_signal')),
  selector         text,
  answer           jsonb,
  verdict          jsonb,
  input_tokens     int,
  output_tokens    int,
  cost             numeric,
  ms               int,
  note             text,
  claimed_at       timestamptz,
  done_at          timestamptz,
  created_at       timestamptz not null default now(),
  unique (run_label, item_key, model_code)
);
create index if not exists boost_benchmark_items_work_idx on pipeline.boost_benchmark_items (run_label, state, id);
comment on table pipeline.boost_benchmark_items is 'CF-247 Boost (Platform Admin 17 Nov 2026 22:45): one row per (benchmark run, stored course page, candidate model): the model''s study load answer, the verdict of the page check, tokens, cost and time. Written by worker coverage-sweep mode boost_benchmark. Nothing here is staged or admitted.';
alter table pipeline.boost_benchmark_items enable row level security;
revoke all on pipeline.boost_benchmark_items from anon, authenticated;

-- 4. The gate: the switch, Maintenance Mode, the squash blackout, and work left for the run named by the label
create or replace function security.boost_benchmark_gate_v1(p_now timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare
  v_label text := security.toolset_setting('pipeline', 'boost.benchmark_label') #>> '{}';
  v_bs numeric := security.pipeline_num_v1('boost.ingest_blackout_start_epoch', 0);
  v_be numeric := security.pipeline_num_v1('boost.ingest_blackout_end_epoch', 0);
begin
  if security.pipeline_num_v1('boost.benchmark_on', 0) < 1 then return jsonb_build_object('ok', false, 'reason', 'the Boost benchmark is switched off'); end if;
  if security.maintenance_hold_v1() then return jsonb_build_object('ok', false, 'reason', 'Pipeline Maintenance Mode'); end if;
  if extract(epoch from p_now) >= v_bs and extract(epoch from p_now) < v_be then return jsonb_build_object('ok', false, 'reason', 'blackout (migration squash)'); end if;
  if coalesce(v_label, '') !~ '^[a-z0-9-]{3,40}$' then return jsonb_build_object('ok', false, 'reason', 'the run label is not lower-case letters, digits and hyphens'); end if;
  if exists (select 1 from pipeline.boost_benchmark_items i where i.run_label = v_label)
     and not exists (select 1 from pipeline.boost_benchmark_items i where i.run_label = v_label
                      and (i.state = 'queued' or (i.state = 'claimed' and i.claimed_at < p_now - interval '10 minutes'))) then  -- fixed: claim lease
    return jsonb_build_object('ok', false, 'reason', 'nothing left to do', 'label', v_label);
  end if;
  return jsonb_build_object('ok', true, 'label', v_label);
end $function$;
revoke all on function security.boost_benchmark_gate_v1(timestamptz) from public, anon, authenticated;
grant execute on function security.boost_benchmark_gate_v1(timestamptz) to service_role;
comment on function security.boost_benchmark_gate_v1(timestamptz) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 22:45): whether the Boost benchmark may run now: the switch boost.benchmark_on, Maintenance Mode off, not in the squash blackout, and the run named by boost.benchmark_label is new or has work left.';

-- 5. The claim: builds the cohort of a new label, then hands out the next pages with their candidate models
create or replace function security.boost_benchmark_claim_v1(p_pages int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_label text := security.toolset_setting('pipeline', 'boost.benchmark_label') #>> '{}';
  v_per int := security.pipeline_num_v1('boost.benchmark_pages_per_country', 200)::int;
  v_pages int := least(greatest(coalesce(p_pages, 0), 0), 50);  -- fixed: bound on one call; the size is the setting batch.boost_benchmark
  v_cat text := security.boost_lane_category_v1('study_load');
  v_out jsonb; r record;
begin
  if coalesce(v_label, '') !~ '^[a-z0-9-]{3,40}$' or v_pages = 0 or v_cat is null then return jsonb_build_object('label', v_label, 'pages', '[]'::jsonb); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_benchmark_claim'));
  if not exists (select 1 from pipeline.boost_benchmark_items i where i.run_label = v_label) then
    for r in select m.country_code from security.boost_country_category_matrix_v1() m where m.enrichment_category = v_cat and m.weight > 0 order by m.priority_rank loop
      insert into pipeline.boost_benchmark_items (run_label, item_key, entity_id, evidence_id, storage_path, source_url, title, country_code, model_code, model_identifier)
      select v_label, 'sl-' || d.entity_id || '-' || d.evidence_id, d.entity_id, d.evidence_id, d.storage_path, d.source_url, d.display_title, r.country_code, x.code, x.model_identifier
        from (select c.id as entity_id, a.id as evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) as source_url, c.display_title
                from catalogue.courses c
                join catalogue.providers p on p.id = c.provider_id
                join ref.countries k on k.id = p.country_id
                join lateral (select e.id, e.storage_path, e.source_url from pipeline.evidence_artifacts e
                               where e.entity_id = c.id and e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
                               order by e.captured_at desc nulls last limit 1) a on true
               where c.lifecycle_status = 'active' and c.study_load is null
                 and (k.iso_alpha2 = r.country_code
                      or k.iso_alpha2 in (select split_part(y, '=', 1) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) y where split_part(y, '=', 2) = r.country_code))
               order by md5(c.id::text)
               limit v_per) d
        cross join lateral (select t->>'code' as code, t->>'model_identifier' as model_identifier
                              from jsonb_array_elements(security.ai_route_v1('boost_extract_benchmark')->'models') t) x
      on conflict (run_label, item_key, model_code) do nothing;
    end loop;
  end if;
  with pages as (
    select i.item_key from pipeline.boost_benchmark_items i
     where i.run_label = v_label and (i.state = 'queued' or (i.state = 'claimed' and i.claimed_at < now() - interval '10 minutes'))  -- fixed: claim lease
     group by i.item_key order by min(i.id) limit v_pages),
  upd as (
    update pipeline.boost_benchmark_items i set state = 'claimed', claimed_at = now()
      from pages g where i.run_label = v_label and i.item_key = g.item_key and i.state in ('queued', 'claimed')
    returning i.id, i.item_key, i.storage_path, i.title, i.country_code, i.model_code, i.model_identifier)
  select coalesce(jsonb_agg(pg), '[]'::jsonb) into v_out from (
    select jsonb_build_object('item_key', u.item_key, 'storage_path', min(u.storage_path), 'title', min(u.title), 'country_code', min(u.country_code),
             'rows', jsonb_agg(jsonb_build_object('id', u.id, 'model_code', u.model_code, 'model', u.model_identifier) order by u.model_code)) as pg
      from upd u group by u.item_key) z;
  return jsonb_build_object('label', v_label, 'pages', v_out);
end $function$;
revoke all on function security.boost_benchmark_claim_v1(int) from public, anon, authenticated;
comment on function security.boost_benchmark_claim_v1(int) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 22:45): for the run named by boost.benchmark_label: builds its cohort when the label is new (stored course pages of courses with no study load, per country of the Boost priority matrix, one row per candidate model of the route boost_extract_benchmark), then claims the next pages and returns them with their models.';

create or replace function public.svc_boost_benchmark_gate()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_benchmark_gate_v1();
end $function$;
comment on function public.svc_boost_benchmark_gate() is 'CF-247 Boost: the gate of the Boost benchmark (security.boost_benchmark_gate_v1), read by worker coverage-sweep mode boost_benchmark.';

create or replace function public.svc_boost_benchmark_route_v1()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.ai_route_v1('boost_extract_benchmark');
end $function$;
comment on function public.svc_boost_benchmark_route_v1() is 'CF-247 Boost: the route of the Boost benchmark (candidate models, caps, hold), read by worker coverage-sweep mode boost_benchmark.';

create or replace function public.svc_boost_benchmark_claim(p_pages int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_benchmark_claim_v1(p_pages);
end $function$;
comment on function public.svc_boost_benchmark_claim(int) is 'CF-247 Boost: claims the next benchmark pages (security.boost_benchmark_claim_v1), called by worker coverage-sweep mode boost_benchmark.';

-- 6. The outcome of claimed rows; a row given back (state queued) is asked again
create or replace function public.svc_boost_benchmark_done(p_items jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with j as (select (x->>'id')::bigint as id, x->>'state' as state, x->>'selector' as selector, x->'answer' as answer, x->'verdict' as verdict,
                    nullif(x->>'input_tokens', '')::int as input_tokens, nullif(x->>'output_tokens', '')::int as output_tokens,
                    nullif(x->>'cost', '')::numeric as cost, nullif(x->>'ms', '')::int as ms, x->>'note' as note
               from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x where x->>'state' in ('queued', 'verified', 'rejected', 'failed', 'no_signal')),
  upd as (update pipeline.boost_benchmark_items t
             set state = j.state, selector = j.selector, answer = case when j.state = 'queued' then null else j.answer end,
                 verdict = case when j.state = 'queued' then null else j.verdict end, input_tokens = j.input_tokens, output_tokens = j.output_tokens,
                 cost = j.cost, ms = j.ms, note = left(j.note, 300), done_at = case when j.state = 'queued' then null else now() end,
                 claimed_at = case when j.state = 'queued' then null else t.claimed_at end
            from j where t.id = j.id and t.state = 'claimed'
          returning 1)
  select count(*) into v_n from upd;
  return jsonb_build_object('settled', v_n);
end $function$;
comment on function public.svc_boost_benchmark_done(jsonb) is 'CF-247 Boost: records the outcome of claimed benchmark rows (verified, rejected, failed, no_signal, or queued to be asked again), called by worker coverage-sweep mode boost_benchmark.';

-- 7. The report of a run, per country and model
create or replace function security.boost_benchmark_report_v1(p_label text)
returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('label', p_label,
    'rows', (select count(*) from pipeline.boost_benchmark_items where run_label = p_label),
    'left', (select count(*) from pipeline.boost_benchmark_items where run_label = p_label and state in ('queued', 'claimed')),
    'by_model', (select coalesce(jsonb_agg(to_jsonb(x) order by x.country_code, x.model_code), '[]'::jsonb) from (
       select i.country_code, i.model_code, count(*) as pages,
              count(*) filter (where i.state in ('verified', 'rejected', 'failed')) as model_calls,
              count(*) filter (where i.state = 'verified' and i.answer->>'study_load' is not null) as verified_with_value,
              count(*) filter (where i.state = 'verified' and i.answer->>'study_load' is null) as verified_not_stated,
              count(*) filter (where i.state = 'rejected') as rejected, count(*) filter (where i.state = 'failed') as failed,
              count(*) filter (where i.state = 'no_signal') as no_signal,
              sum(i.input_tokens) as input_tokens, sum(i.output_tokens) as output_tokens, round(coalesce(sum(i.cost), 0), 6) as cost_usd,
              round((percentile_cont(0.5) within group (order by i.ms) filter (where i.ms is not null))::numeric) as median_ms
         from pipeline.boost_benchmark_items i where i.run_label = p_label group by 1, 2) x))
$function$;
revoke all on function security.boost_benchmark_report_v1(text) from public, anon, authenticated;
grant execute on function security.boost_benchmark_report_v1(text) to service_role;
comment on function security.boost_benchmark_report_v1(text) is 'CF-247 Boost (Platform Admin 17 Nov 2026 22:45): a benchmark run per country and model: pages, model calls, verified with a value, verified as not stated, rejected, failed, pages with no study word, tokens, cost and the median time of a call.';

revoke all on function public.svc_boost_benchmark_gate() from public, anon, authenticated;
revoke all on function public.svc_boost_benchmark_route_v1() from public, anon, authenticated;
revoke all on function public.svc_boost_benchmark_claim(int) from public, anon, authenticated;
revoke all on function public.svc_boost_benchmark_done(jsonb) from public, anon, authenticated;
grant execute on function public.svc_boost_benchmark_gate() to service_role;
grant execute on function public.svc_boost_benchmark_route_v1() to service_role;
grant execute on function public.svc_boost_benchmark_claim(int) to service_role;
grant execute on function public.svc_boost_benchmark_done(jsonb) to service_role;

-- 8. The job (G1): every 2 minutes, only while the gate allows
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('boost-benchmark', 'Boost', 30, 'Boost model benchmark',
  'Every 2 minutes, only while the benchmark run named on Settings > Pipeline settings > Boost has pages left, the benchmark is switched on, Pipeline Maintenance Mode is off and the migration squash blackout is not on: worker coverage-sweep asks each candidate model of the Models & services route Boost extraction benchmark for the study load of the same stored course pages and records the answers, tokens, cost and time. Nothing is staged or admitted.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('boost-benchmark', '1-59/2 * * * *',
  'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''boost_benchmark'', ''limit'', security.pipeline_num_v1(''batch.boost_benchmark'', 8)::int)) where (security.boost_benchmark_gate_v1()->>''ok'')::boolean')
where not exists (select 1 from cron.job where jobname = 'boost-benchmark');

-- 9. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'boost-benchmark', 'Layer 2', 'Boost', 'Boost model benchmark: candidate models asked for the same stored pages', 'active', '{}', '20261118020000'),
  ('table', 'pipeline.boost_benchmark_items', 'Layer 2', 'Boost', 'Boost benchmark results per run, page and model', 'active', '{}', '20261118020000'),
  ('function', 'security.boost_benchmark_gate_v1', 'Layer 2', 'Boost', 'Whether the Boost benchmark may run now', 'active', '{}', '20261118020000'),
  ('function', 'security.boost_benchmark_claim_v1', 'Layer 2', 'Boost', 'Builds a benchmark run''s cohort and claims its next pages', 'active', '{}', '20261118020000'),
  ('function', 'security.boost_benchmark_report_v1', 'Layer 2', 'Boost', 'A benchmark run per country and model', 'active', '{}', '20261118020000'),
  ('function', 'public.svc_boost_benchmark_gate', 'Layer 2', 'Boost', 'Worker call: the Boost benchmark gate', 'active', '{}', '20261118020000'),
  ('function', 'public.svc_boost_benchmark_route_v1', 'Layer 2', 'Boost', 'Worker call: the Boost benchmark route', 'active', '{}', '20261118020000'),
  ('function', 'public.svc_boost_benchmark_claim', 'Layer 2', 'Boost', 'Worker call: claim benchmark pages', 'active', '{}', '20261118020000'),
  ('function', 'public.svc_boost_benchmark_done', 'Layer 2', 'Boost', 'Worker call: outcome of benchmark rows', 'active', '{}', '20261118020000')
on conflict do nothing;

-- 10. Post-checks. The cohort is not built here: the job's first run builds it, so a dry run and the deploy leave the table empty.
do $c$
declare v_route jsonb := security.ai_route_v1('boost_extract_benchmark'); v_cmd text;
begin
  if jsonb_array_length(v_route->'models') <> 3 then raise exception 'post-check: the route does not hand out the three candidates: %', v_route->'models'; end if;
  if security.ai_route_v1('boost_extract')->'models' <> jsonb_build_array(jsonb_build_object('code', 'qwen3-30b', 'model_identifier', (select model_identifier from pipeline.ai_model_catalogue where code = 'qwen3-30b'))) then
    raise exception 'post-check: the route boost_extract is no longer pinned to one model';
  end if;
  if not (security.boost_benchmark_gate_v1('2026-11-18 00:30+11')->>'ok')::boolean and security.boost_benchmark_gate_v1('2026-11-18 00:30+11')->>'reason' <> 'Pipeline Maintenance Mode' then
    raise exception 'post-check: the gate is closed for a new label: %', security.boost_benchmark_gate_v1('2026-11-18 00:30+11');
  end if;
  if (security.boost_benchmark_gate_v1('2026-11-19 01:45+11')->>'ok')::boolean then raise exception 'post-check: the gate is open inside the squash blackout'; end if;
  select command into v_cmd from cron.job where jobname = 'boost-benchmark' and active;
  if v_cmd is null or v_cmd !~ 'boost_benchmark_gate_v1\(\)' or v_cmd ~ '''limit'', [0-9]' then raise exception 'post-check: the job is missing, inactive or holds a number: %', v_cmd; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'boost-benchmark') then raise exception 'post-check: the job is not catalogued'; end if;
  if not (select relrowsecurity from pg_class where oid = 'pipeline.boost_benchmark_items'::regclass) then raise exception 'post-check: row-level security is off'; end if;
  if exists (select 1 from pipeline.boost_benchmark_items) then raise exception 'post-check: the benchmark table is not empty'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified for admission by this change'; end if;
  if has_function_privilege('anon', 'public.svc_boost_benchmark_claim(int)', 'execute') or has_function_privilege('authenticated', 'public.svc_boost_benchmark_done(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'security.boost_benchmark_claim_v1(int)', 'execute') then
    raise exception 'post-check: a Boost benchmark function is open to anon or authenticated';
  end if;
end $c$;
