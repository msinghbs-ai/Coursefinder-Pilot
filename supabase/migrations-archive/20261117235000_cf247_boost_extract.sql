-- CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 21:18 decision 1, and 22:05): Boost extraction through the coverage-sweep worker and the
-- Models & services route, so cost recording, the allowed-model check and model health stay in one place. No separate worker holds a key.
-- What it adds:
--   1. The route boost_extract in Models & services (pipeline.ai_service_routes): one pinned model, the central model Qwen3 30B, with a daily
--      spend cap and a daily call cap. Its qualification is provisional: it lets the route run, and what the route produces is shadow only.
--   2. pipeline.boost_extract_items: one row per (lane, course, stored page) the worker has claimed, so a page is read once.
--   3. The worker's calls: svc_boost_extract_gate (the switch boost.extract_on and the overnight gate of migration 20261117163500),
--      svc_boost_extract_route_v1, svc_boost_extract_claim (courses with no study load that have a stored course page, in the order of the
--      Boost priority matrix) and svc_boost_extract_done.
--   4. Job boost-extract, every 5 minutes, only when the gate allows (01:05 to 04:50 Melbourne, not in the squash blackout, not beside
--      housekeeping-daily): it calls worker coverage-sweep mode boost_extract, which writes result files to Storage staging-boost/inbound.
--      worker-boost-bulk-ingest (unchanged) loads and settles them.
--   5. Settings: the switch, the courses per run, the lanes, the answer length and the page text sent.
-- What it does not do: it qualifies no model for admission (pipeline.boost_model_qualifications stays empty, so every row is shadow or
-- refused and nothing is written to the catalogue), and it changes neither security.boost_promote_v1, the gate nor worker-boost-bulk-ingest.
-- Lane: study_load only. The other Boost lanes are not read by this worker yet.
-- G1: job boost-extract is catalogued. G2: sizes are settings; the job command holds no number. G3: no consumer API object is read or changed.
-- Replaces: the plan to deploy the Cloudflare Worker cf-boost-extractor with its own AI keys (admin docs/platform/CF-WORKER-BOOST-AND-PROD-LAUNCH.md §1 to §8; never deployed)
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('security.boost_ingest_gate_v1(boolean,timestamptz)') is null or to_regprocedure('security.boost_lane_category_v1(text)') is null
     or to_regprocedure('security.ai_route_v1(text)') is null then
    raise exception 'the Boost gate (20261117163500), the Boost matrix (20261117223000) or the AI route function is not there';
  end if;
  if not exists (select 1 from pipeline.ai_model_catalogue where code = 'qwen3-30b' and status = 'allowed') then
    raise exception 'model qwen3-30b is not an allowed model in the catalogue';
  end if;
end $pre$;

-- 1. The route (Models & services) and its provisional qualification
insert into pipeline.ai_service_routes(service_code, label, area, field, lane, ledger_match, cascade, daily_usd_cap, daily_calls_cap, prompt_source, enabled, resolver,
                                       purpose_group, migration_state, previous_model, note, sort, reason)
values ('boost_extract', 'Boost extraction (study load)', 'Boost', null, 'boost_extract', null, array['qwen3-30b'], 1, 1500, 'worker code: boost.ts (boost-study-load-v1)', true, 'route',
        'reads', 'routed_single', null,
        'Boost reads stored course pages overnight for courses with no study load. Results are shadow only until the Platform Admin qualifies a model for the lane (pipeline.boost_model_qualifications).',
        160, 'S2 - BOOST 17 Nov 2026 (Platform Admin 21:18 decision 1 and 22:05: through coverage-sweep and Models & services, pinned to a named allowed model); central model per Platform Admin decision 13 Nov 2026 19:09')
on conflict (service_code) do nothing;

insert into pipeline.ai_route_qualifications(service_code, model_code, prompt_version, status, provisional, evidence, note)
select 'boost_extract', 'qwen3-30b', 'boost-study-load-v1', 'qualified', true,
       'Platform Admin decision 13 Nov 2026 19:09 (central model set to Qwen3 30B) and 17 Nov 2026 22:05 (Boost route pinned to named allowed models); benchmark against Mistral Small 3.2 and MiMo v2.6 Flash pending',
       'S2 - BOOST 17 Nov 2026: lets the route run. Output is shadow only: admission needs a row in pipeline.boost_model_qualifications, which is a separate step'
where not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract' and q.model_code = 'qwen3-30b');

-- 2. Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'boost.extract_on', 'Boost extraction: on (1) or off (0)',
  'Whether job boost-extract reads stored course pages with AI inside the overnight window. Off stops the reading at once; rows already staged are still settled by worker-boost-bulk-ingest.',
  'number', to_jsonb(1), 0, 1, 'switch', 950, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:05', 'Boost', 'security.boost_extract_gate_v1 (job boost-extract)'),
 ('pipeline', 'batch.boost_extract', 'Boost extraction: courses per run',
  'How many courses job boost-extract claims in one run (every 5 minutes inside the overnight window). A run stops early when its time is used; the courses left go back to the queue.',
  'number', to_jsonb(20), 1, 200, 'courses', 951, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:05', 'Boost', 'job boost-extract'),
 ('pipeline', 'boost.extract_lanes', 'Boost extraction: lanes read',
  'The Boost lanes the worker reads. Only study_load is built; another lane named here is ignored until its reading is built.',
  'list', '["study_load"]'::jsonb, 0, null, 'lanes', 952, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:05', 'Boost', 'security.boost_extract_claim_v1'),
 ('pipeline', 'reading.boost_extract_section_chars', 'Boost extraction: page text sent to the model',
  'The most page text sent for one course: the parts of the stored page around the words full-time and part-time. The answer is still checked against the whole page.',
  'number', to_jsonb(6000), 1000, 40000, 'characters', 953, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:05', 'Boost', 'worker coverage-sweep boost_extract'),
 ('pipeline', 'reading.answer_tokens.boost_extract', 'AI answer length: Boost extraction',
  'The longest answer the Boost study load reading may give. A cut answer is recorded as failed with its reason; the cost is recorded.',
  'number', to_jsonb(300), 100, 2000, 'tokens', 942, 'CF-247 Boost, Platform Admin 17 Nov 2026 22:05', 'AI answer limits', 'worker coverage-sweep boost_extract')
on conflict (toolset_key, key) do nothing;

-- 3. The claim ledger
create table if not exists pipeline.boost_extract_items (
  item_key     text primary key,
  lane         text not null,
  entity       text not null check (entity in ('course', 'provider')),
  entity_id    uuid not null,
  evidence_id  uuid not null,
  country_code text,
  state        text not null check (state in ('claimed', 'verified', 'rejected', 'failed', 'released')),
  batch_id     text,
  result_path  text,
  model_called boolean,
  cost         numeric,
  note         text,
  claimed_at   timestamptz not null default now(),
  done_at      timestamptz,
  unique (lane, entity_id, evidence_id)
);
create index if not exists boost_extract_items_state_idx on pipeline.boost_extract_items (state, claimed_at);
create index if not exists boost_extract_items_entity_idx on pipeline.boost_extract_items (entity_id, lane);
comment on table pipeline.boost_extract_items is 'CF-247 Boost (Platform Admin 17 Nov 2026 22:05): one row per (lane, course, stored page) that worker coverage-sweep mode boost_extract has claimed, with its outcome, batch and result file. A page is read once; a newer stored page of the same course is a new row. Read by security.boost_extract_claim_v1 and security.boost_extract_progress_v1.';
alter table pipeline.boost_extract_items enable row level security;
revoke all on pipeline.boost_extract_items from anon, authenticated;

-- 4. The gate: the switch, then the overnight gate of the ingest job (window, squash blackout, housekeeping, dispatcher locks)
create or replace function security.boost_extract_gate_v1(p_check_locks boolean default true, p_now timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare g jsonb;
begin
  if security.pipeline_num_v1('boost.extract_on', 0) < 1 then return jsonb_build_object('ok', false, 'reason', 'Boost extraction is switched off'); end if;
  g := security.boost_ingest_gate_v1(p_check_locks, p_now);
  if not coalesce((g->>'ok')::boolean, false) then return jsonb_build_object('ok', false, 'reason', coalesce(g->>'reason', 'gate closed')); end if;
  return jsonb_build_object('ok', true, 'melbourne_minute', g->'melbourne_minute');
end $function$;
revoke all on function security.boost_extract_gate_v1(boolean, timestamptz) from public, anon, authenticated;
grant execute on function security.boost_extract_gate_v1(boolean, timestamptz) to service_role;
comment on function security.boost_extract_gate_v1(boolean, timestamptz) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 22:05): whether Boost extraction may run now: the switch boost.extract_on, then security.boost_ingest_gate_v1 (overnight window, squash blackout, housekeeping-daily, dispatcher locks).';

create or replace function public.svc_boost_extract_gate()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_extract_gate_v1(true);
end $function$;
comment on function public.svc_boost_extract_gate() is 'CF-247 Boost: the gate of Boost extraction (security.boost_extract_gate_v1 with the dispatcher locks), read by worker coverage-sweep mode boost_extract.';

create or replace function public.svc_boost_extract_route_v1()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.ai_route_v1('boost_extract');
end $function$;
comment on function public.svc_boost_extract_route_v1() is 'CF-247 Boost: the route of Boost extraction (model, caps, hold), read by worker coverage-sweep mode boost_extract.';

-- 5. The claim: courses with no study load and a stored course page, in the order of the Boost priority matrix
create or replace function security.boost_extract_claim_v1(p_limit int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_left int := least(greatest(coalesce(p_limit, 0), 0), 500);  -- fixed: bound on one call; the size is the setting batch.boost_extract
  v_batch text := 'bx-' || to_char(now() at time zone 'utc', 'YYYYMMDD"T"HH24MISS') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_cat text := security.boost_lane_category_v1('study_load');
  v_items jsonb := '[]'::jsonb; v_got jsonb; r record;
begin
  if not ('study_load' = any (security.pipeline_list_v1('boost.extract_lanes'))) or v_cat is null or v_left = 0 then
    return jsonb_build_object('batch_id', v_batch, 'items', v_items);
  end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_extract_claim'));
  for r in select m.country_code, m.weight from security.boost_country_category_matrix_v1() m
            where m.enrichment_category = v_cat and m.weight > 0 order by m.priority_rank loop
    exit when v_left <= 0;
    with cand as (
      select c.id as entity_id, a.id as evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) as source_url, c.display_title
        from catalogue.courses c
        join catalogue.providers p on p.id = c.provider_id
        join ref.countries k on k.id = p.country_id
        join lateral (select e.id, e.storage_path, e.source_url from pipeline.evidence_artifacts e
                       where e.entity_id = c.id and e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
                       order by e.captured_at desc nulls last limit 1) a on true
       where c.lifecycle_status = 'active' and c.study_load is null
         and (k.iso_alpha2 = r.country_code
              or k.iso_alpha2 in (select split_part(x, '=', 1) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x where split_part(x, '=', 2) = r.country_code))
         and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))
         and not exists (select 1 from pipeline.boost_extract_items x where x.lane = 'study_load' and x.entity_id = c.id and x.evidence_id = a.id
                          and (x.state in ('verified', 'rejected', 'failed') or (x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes')))  -- fixed: claim lease
       limit v_left),
    ins as (
      insert into pipeline.boost_extract_items as t (item_key, lane, entity, entity_id, evidence_id, country_code, state, batch_id, claimed_at)
      select 'sl-' || d.entity_id || '-' || d.evidence_id, 'study_load', 'course', d.entity_id, d.evidence_id, r.country_code, 'claimed', v_batch, now() from cand d
      on conflict (item_key) do update set state = 'claimed', batch_id = excluded.batch_id, claimed_at = now(), done_at = null, result_path = null, note = null
      returning t.item_key, t.entity_id, t.evidence_id)
    select coalesce(jsonb_agg(jsonb_build_object('item_key', i.item_key, 'lane', 'study_load', 'entity', 'course', 'entity_id', i.entity_id, 'evidence_id', i.evidence_id,
             'storage_path', d.storage_path, 'source_url', d.source_url, 'country_code', r.country_code, 'weight', r.weight,
             'context', jsonb_build_object('title', d.display_title))), '[]'::jsonb)
      into v_got from ins i join cand d on d.entity_id = i.entity_id and d.evidence_id = i.evidence_id;
    v_items := v_items || v_got;
    v_left := v_left - jsonb_array_length(v_got);
  end loop;
  return jsonb_build_object('batch_id', v_batch, 'items', v_items);
end $function$;
revoke all on function security.boost_extract_claim_v1(int) from public, anon, authenticated;
comment on function security.boost_extract_claim_v1(int) is
  'CF-247 Boost (Platform Admin 17 Nov 2026 22:05): claims up to p_limit active courses with no study load that have a stored course page not yet read, country by country in the order of the Boost priority matrix for the lane''s category, and returns them with a new batch id. A claim not settled within its lease is claimed again.';

create or replace function public.svc_boost_extract_claim(p_limit int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_extract_claim_v1(p_limit);
end $function$;
comment on function public.svc_boost_extract_claim(int) is 'CF-247 Boost: claims the next courses for Boost extraction (security.boost_extract_claim_v1), called by worker coverage-sweep mode boost_extract.';

-- 6. The outcome of a claimed batch
create or replace function public.svc_boost_extract_done(p_batch text, p_items jsonb, p_path text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_n int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with j as (select x->>'item_key' as item_key, x->>'status' as status, (x->>'model_called')::boolean as model_called, nullif(x->>'cost', '')::numeric as cost, x->>'note' as note
               from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x where x->>'status' in ('verified', 'rejected', 'failed', 'released')),
  upd as (update pipeline.boost_extract_items t
             set state = j.status, model_called = j.model_called, cost = j.cost, note = left(j.note, 300), done_at = now(),
                 result_path = case when j.status = 'released' then null else p_path end
            from j where t.item_key = j.item_key and t.batch_id = p_batch and t.state = 'claimed'
          returning t.state)
  select count(*) into v_n from upd;
  return jsonb_build_object('batch', p_batch, 'settled', v_n);
end $function$;
comment on function public.svc_boost_extract_done(text, jsonb, text) is 'CF-247 Boost: records the outcome of each course of a claimed batch (verified, rejected, failed, or released to be read again) and the result file, called by worker coverage-sweep mode boost_extract.';

-- 7. Progress, for the experiments and the current-state index
create or replace function security.boost_extract_progress_v1()
returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object(
    'by_state', (select coalesce(jsonb_object_agg(s.state, s.n), '{}'::jsonb) from (select state, count(*) n from pipeline.boost_extract_items group by state) s),
    'by_country', (select coalesce(jsonb_object_agg(s.country_code, s.n), '{}'::jsonb) from (select coalesce(country_code, '?') country_code, count(*) n from pipeline.boost_extract_items where state <> 'released' group by 1) s),
    'model_calls', (select count(*) from pipeline.boost_extract_items where model_called),
    'cost_usd', (select coalesce(sum(cost), 0) from pipeline.boost_extract_items),
    'batches', (select count(distinct batch_id) from pipeline.boost_extract_items where state <> 'released'),
    'last_done_at', (select max(done_at) from pipeline.boost_extract_items))
$function$;
revoke all on function security.boost_extract_progress_v1() from public, anon, authenticated;
grant execute on function security.boost_extract_progress_v1() to service_role;
comment on function security.boost_extract_progress_v1() is 'CF-247 Boost (Platform Admin 17 Nov 2026 22:05): counts of Boost extraction items by outcome and country, the model calls made and their cost.';

revoke all on function public.svc_boost_extract_gate() from public, anon, authenticated;
revoke all on function public.svc_boost_extract_route_v1() from public, anon, authenticated;
revoke all on function public.svc_boost_extract_claim(int) from public, anon, authenticated;
revoke all on function public.svc_boost_extract_done(text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_boost_extract_gate() to service_role;
grant execute on function public.svc_boost_extract_route_v1() to service_role;
grant execute on function public.svc_boost_extract_claim(int) to service_role;
grant execute on function public.svc_boost_extract_done(text, jsonb, text) to service_role;

-- 8. The job (G1): every 5 minutes, two minutes after worker-boost-bulk-ingest, only when the gate allows
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('boost-extract', 'Boost', 20, 'Boost extraction (overnight)',
  'Every 5 minutes, only when Boost extraction is switched on and inside the overnight window on Settings > Pipeline settings > Boost (01:05 to 04:50 Melbourne), not during the migration squash blackout and not beside housekeeping-daily: worker coverage-sweep reads stored course pages of courses with no study load, in the order of the Boost priority matrix, through the Models & services route Boost extraction, and writes result files to Storage staging-boost/inbound. Results are shadow only until a model is qualified.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('boost-extract', '2-59/5 * * * *',
  'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''boost_extract'', ''limit'', security.pipeline_num_v1(''batch.boost_extract'', 20)::int)) where (security.boost_extract_gate_v1(false)->>''ok'')::boolean')
where not exists (select 1 from cron.job where jobname = 'boost-extract');

-- 9. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'boost-extract', 'Layer 2', 'Boost', 'Boost extraction: stored course pages read overnight through the Models & services route', 'active', '{}', '20261117235000'),
  ('table', 'pipeline.boost_extract_items', 'Layer 2', 'Boost', 'Courses claimed by Boost extraction, with outcome and result file', 'active', '{}', '20261117235000'),
  ('function', 'security.boost_extract_gate_v1', 'Layer 2', 'Boost', 'Whether Boost extraction may run now', 'active', '{}', '20261117235000'),
  ('function', 'security.boost_extract_claim_v1', 'Layer 2', 'Boost', 'Claims the next courses for Boost extraction in matrix order', 'active', '{}', '20261117235000'),
  ('function', 'security.boost_extract_progress_v1', 'Layer 2', 'Boost', 'Boost extraction counts by outcome and country', 'active', '{}', '20261117235000'),
  ('function', 'public.svc_boost_extract_gate', 'Layer 2', 'Boost', 'Worker call: the Boost extraction gate', 'active', '{}', '20261117235000'),
  ('function', 'public.svc_boost_extract_route_v1', 'Layer 2', 'Boost', 'Worker call: the Boost extraction route', 'active', '{}', '20261117235000'),
  ('function', 'public.svc_boost_extract_claim', 'Layer 2', 'Boost', 'Worker call: claim courses for Boost extraction', 'active', '{}', '20261117235000'),
  ('function', 'public.svc_boost_extract_done', 'Layer 2', 'Boost', 'Worker call: outcome of a Boost extraction batch', 'active', '{}', '20261117235000')
on conflict do nothing;

-- 10. Post-checks (the claim is tried and released inside this transaction)
do $c$
declare v_route jsonb := security.ai_route_v1('boost_extract'); v_claim jsonb; v_again jsonb; v_item jsonb; v_done jsonb; v_cmd text;
begin
  if v_route->>'model' is distinct from (select model_identifier from pipeline.ai_model_catalogue where code = 'qwen3-30b') then
    raise exception 'post-check: the route does not hand out the pinned model: %', v_route;
  end if;
  if (select cardinality(cascade) from pipeline.ai_service_routes where service_code = 'boost_extract') <> 1 then raise exception 'post-check: the route is not pinned to one model'; end if;
  if (security.boost_extract_gate_v1(false, '2026-11-18 12:00+11')->>'ok')::boolean then raise exception 'post-check: the gate is open at midday'; end if;
  if security.boost_extract_gate_v1(false, '2026-11-18 01:10+11')->>'reason' in ('outside the window', 'Boost extraction is switched off') then
    raise exception 'post-check: the gate is closed by the window or the switch at 01:10 on Wednesday: %', security.boost_extract_gate_v1(false, '2026-11-18 01:10+11');
  end if;
  if (security.boost_extract_gate_v1(false, '2026-11-19 01:45+11')->>'ok')::boolean then raise exception 'post-check: the gate is open inside the squash blackout'; end if;
  select command into v_cmd from cron.job where jobname = 'boost-extract' and active;
  if v_cmd is null or v_cmd !~ 'boost_extract_gate_v1\(false\)' or v_cmd ~ '''limit'', [0-9]' then raise exception 'post-check: the job is missing, inactive or holds a number: %', v_cmd; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'boost-extract') then raise exception 'post-check: the job is not catalogued'; end if;
  if not (select relrowsecurity from pg_class where oid = 'pipeline.boost_extract_items'::regclass) then raise exception 'post-check: row-level security is off'; end if;
  -- the claim returns courses with no study load and a stored page, and a second claim does not return the same course; both claims are then
  -- released (state released: read again by the job), so nothing stays claimed by this check
  v_claim := security.boost_extract_claim_v1(3);
  v_again := security.boost_extract_claim_v1(3);
  if jsonb_array_length(v_claim->'items') > 0 then
    v_item := v_claim->'items'->0;
    if v_item->>'storage_path' is null or v_item->>'lane' <> 'study_load'
       or exists (select 1 from catalogue.courses c where c.id = (v_item->>'entity_id')::uuid and c.study_load is not null) then
      raise exception 'post-check: a claimed item is not a course with no study load and a stored page: %', v_item;
    end if;
    if exists (select 1 from jsonb_array_elements(v_again->'items') x, jsonb_array_elements(v_claim->'items') y where x->>'item_key' = y->>'item_key') then
      raise exception 'post-check: a course was claimed twice';
    end if;
    v_done := public.svc_boost_extract_done(v_claim->>'batch_id',
      (select jsonb_agg(jsonb_build_object('item_key', x->>'item_key', 'status', 'released', 'note', 'post-check of migration 20261117235000')) from jsonb_array_elements(v_claim->'items') x), null);
    if (v_done->>'settled')::int <> jsonb_array_length(v_claim->'items') then raise exception 'post-check: the outcome was not recorded: %', v_done; end if;
    if jsonb_array_length(v_again->'items') > 0 then
      perform public.svc_boost_extract_done(v_again->>'batch_id',
        (select jsonb_agg(jsonb_build_object('item_key', x->>'item_key', 'status', 'released', 'note', 'post-check of migration 20261117235000')) from jsonb_array_elements(v_again->'items') x), null);
    end if;
  end if;
  if exists (select 1 from pipeline.boost_extract_items where state = 'claimed') then raise exception 'post-check: a course is still claimed'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications) then raise exception 'post-check: no model may be qualified for admission by this change'; end if;
  if has_function_privilege('anon', 'public.svc_boost_extract_claim(int)', 'execute') or has_function_privilege('authenticated', 'public.svc_boost_extract_done(text, jsonb, text)', 'execute')
     or has_function_privilege('authenticated', 'security.boost_extract_claim_v1(int)', 'execute') then
    raise exception 'post-check: a Boost extraction function is open to anon or authenticated';
  end if;
end $c$;
