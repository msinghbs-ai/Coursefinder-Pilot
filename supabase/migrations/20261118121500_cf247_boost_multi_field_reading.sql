-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08 decision 3, and 10:10: "staging extracted values unadmitted in staging-boost until each
-- field owner's approval rule is active"), with worker coverage-sweep v1.0.15 (boost-fields.ts, prompt boost-fields-v1).
-- What it does:
--   1. Route boost_fields_extract (Models & services, area Boost): one named model (qwen3-30b), US$2 and 6,000 calls a day. Its qualification
--      row lets the route run; it admits nothing.
--   2. Job boost-fields, every 2 minutes, when setting boost.fields_on is 1 and the Boost gate is open (squash blackout, Maintenance Mode and
--      housekeeping-daily still hold it): worker coverage-sweep mode boost_fields claims courses with a stored own course page that miss one
--      or more Boost gap fields: course_description (empty description), delivery_mode (empty), intakes (no course_intakes row), course_fees
--      (no course_fees row), aer_entry (no course_entry_requirements row). Courses are claimed in the order of the Boost priority matrix (the
--      18 boost.matrix.* settings: country weight by the category weight of each missing field); one model call per page asks for every
--      missing field. Lanes read: setting boost.fields_lanes.
--   3. The answers, each checked against the whole page by the worker, are written to Storage staging-boost/fields/<batch>.ndjson and to
--      pipeline.boost_field_candidates with promotion_state shadow and the field's owner. Nothing is admitted to the catalogue: each owner's
--      own rule (course descriptions: the source-grounded description rule; delivery mode; intakes; fees: the fee lane; entry requirements:
--      AER v2) decides, once the Platform Admin turns that rule on for Boost candidates.
--   4. Boost priority matrix: lanes delivery_mode (Course basics) and intakes (Intakes & deadlines) join boost.matrix.lane_categories.
--   5. Spend of each reading goes to the AI spend ledger (trigger ai_spend_capture on pipeline.boost_field_items).
-- G1: job boost-fields is catalogued. G2: sizes, switch, lanes, page text, answer length and parallel reads are settings; the job command holds
-- no number. G3: no consumer API object is read or changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '20261118111500') then raise exception 'migration 20261118111500 is not applied'; end if;
  if not exists (select 1 from pipeline.ai_model_catalogue where code = 'qwen3-30b' and status = 'allowed') then raise exception 'model qwen3-30b is not an allowed model in the catalogue'; end if;
  if exists (select 1 from pipeline.ai_service_routes where service_code = 'boost_fields_extract') then raise exception 'route boost_fields_extract already exists'; end if;
end $pre$;

-- 1. The route and its running qualification
insert into pipeline.ai_service_routes(service_code, label, area, field, lane, ledger_match, cascade, daily_usd_cap, daily_calls_cap, prompt_source, enabled, resolver,
                                       purpose_group, migration_state, previous_model, note, sort, reason)
values ('boost_fields_extract', 'Boost multi-field reading', 'Boost', null, 'boost_fields', null, array['qwen3-30b'], 2, 6000, 'worker code: boost-fields.ts (boost-fields-v1)', true, 'route',
        'reads', 'routed_single', null,
        'Boost reads each stored course page once for every gap field the course misses (description, delivery mode, intakes, tuition fee, entry requirements). Results are staged in shadow for each field owner''s own admission rule; nothing is admitted here.',
        162, 'S2 - BOOST 18 Nov 2026 (Platform Admin 07:08 decision 3 and 10:10): one pass per stored page, pinned to the central model as the Boost route')
on conflict (service_code) do nothing;

insert into pipeline.ai_route_qualifications(service_code, model_code, prompt_version, status, provisional, evidence, note)
select 'boost_fields_extract', 'qwen3-30b', 'boost-fields-v1', 'qualified', true,
       'Platform Admin decision 13 Nov 2026 19:09 (central model Qwen3 30B), 17 Nov 2026 22:05 (Boost routes pinned to named allowed models) and 18 Nov 2026 07:08 decision 3',
       'S2 - BOOST 18 Nov 2026: lets the route run. Every result is shadow; each field''s owner rule decides admission'
where not exists (select 1 from pipeline.ai_route_qualifications q where q.service_code = 'boost_fields_extract' and q.model_code = 'qwen3-30b');

-- 2. Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'boost.fields_on', 'Boost multi-field reading: on (1) or off (0)',
  'Whether job boost-fields reads stored course pages for the Boost gap fields. Off stops the reading at once; what is staged is kept.',
  'number', to_jsonb(1), 0, 1, 'switch', 960, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 3 and 10:10', 'Boost', 'security.boost_fields_gate_v1 (job boost-fields)'),
 ('pipeline', 'boost.fields_lanes', 'Boost multi-field reading: fields read',
  'The gap fields asked for in one pass per stored page. Any of: course_description, delivery_mode, intakes, course_fees, aer_entry.',
  'list', '["course_description", "delivery_mode", "intakes", "course_fees", "aer_entry"]'::jsonb, 0, null, 'lanes', 961, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 3', 'Boost', 'security.boost_fields_claim_v1'),
 ('pipeline', 'batch.boost_fields', 'Boost multi-field reading: pages a run',
  'How many stored course pages one run of job boost-fields claims and reads.',
  'number', to_jsonb(20), 1, 200, 'pages', 962, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 3', 'Boost', 'job boost-fields'),
 ('pipeline', 'reading.boost_fields_section_chars', 'Boost multi-field reading: page text sent to the model',
  'At most this many characters of each stored page are sent: the start of the page (for the overview) and the parts around each asked field''s words. The answer is always checked against the whole page.',
  'number', to_jsonb(8000), 1000, 30000, 'characters', 963, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 3', 'Boost', 'worker coverage-sweep boost_fields (boost-fields.ts)'),
 ('pipeline', 'reading.boost_fields_parallel', 'Boost multi-field reading: pages read at the same time',
  'How many stored pages one run reads at the same time. Each page is still one call to the one routed model.',
  'number', to_jsonb(4), 1, 8, 'pages', 964, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 3', 'Boost', 'worker coverage-sweep boost_fields (boost-fields.ts)'),
 ('pipeline', 'reading.answer_tokens.boost_fields', 'AI answer length: Boost multi-field reading',
  'The longest answer the Boost multi-field reading may give. A cut answer is recorded as failed with its reason; the cost is recorded.',
  'number', to_jsonb(900), 200, 3000, 'tokens', 943, 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 3', 'AI answer limits', 'worker coverage-sweep boost_fields')
on conflict (toolset_key, key) do nothing;

-- 4. Priority matrix: the two new lanes
update pipeline.platform_toolset_settings
   set value = value || '["delivery_mode=course_basics", "intakes=intakes_deadlines"]'::jsonb, updated_at = now(),
       reason = 'CF-247 Boost, Platform Admin 18 Nov 2026 07:08 decision 3: delivery mode under Course basics, intakes under Intakes & deadlines, for the multi-field reading order'
 where toolset_key = 'pipeline' and key = 'boost.matrix.lane_categories' and not (value @> '["delivery_mode=course_basics"]'::jsonb);

-- 3. Tables
create table if not exists pipeline.boost_field_items (
  item_key     text primary key,
  entity_id    uuid not null references catalogue.courses(id),
  evidence_id  uuid not null,
  country_code text,
  category     text,
  lanes        text[] not null,
  state        text not null check (state in ('claimed', 'read', 'no_signal', 'failed', 'released')),
  batch_id     text not null,
  claimed_at   timestamptz not null default now(),
  done_at      timestamptz,
  cost         numeric,
  model_called boolean,
  result_path  text,
  note         text
);
create index if not exists boost_field_items_entity on pipeline.boost_field_items (entity_id, evidence_id);
comment on table pipeline.boost_field_items is 'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 3): stored course pages claimed by the Boost multi-field reading, with the gap fields asked, the outcome, the cost and the result file in Storage staging-boost/fields.';
alter table pipeline.boost_field_items enable row level security;

create table if not exists pipeline.boost_field_candidates (
  id              bigserial primary key,
  batch_id        text not null,
  item_key        text not null,
  course_id       uuid not null references catalogue.courses(id),
  evidence_id     uuid,
  lane            text not null check (lane in ('course_description', 'delivery_mode', 'intakes', 'course_fees', 'aer_entry')),
  status          text not null check (status in ('verified', 'rejected', 'not_stated')),
  value           jsonb,
  quote           text,
  problems        jsonb not null default '[]'::jsonb,
  provider        text,
  model           text,
  prompt_version  text not null,
  owner           text not null,
  promotion_state text not null default 'shadow' check (promotion_state in ('shadow', 'proposed', 'admitted', 'refused')),
  promotion_note  text,
  created_at      timestamptz not null default now(),
  unique (batch_id, item_key, lane)
);
create index if not exists boost_field_candidates_course_lane on pipeline.boost_field_candidates (course_id, lane);
comment on table pipeline.boost_field_candidates is 'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 3 and 10:10): one row per (stored page, gap field) read by the Boost multi-field reading, with the value, the quote, the page check''s outcome and the field''s owner. Shadow until that owner''s own admission rule takes Boost candidates; nothing here is in the catalogue.';
alter table pipeline.boost_field_candidates enable row level security;

do $t$
begin
  if not exists (select 1 from pg_trigger where tgrelid = 'pipeline.boost_field_items'::regclass and tgname = 'ai_spend_capture') then
    create trigger ai_spend_capture after insert or update of cost on pipeline.boost_field_items
      for each row execute function security.ai_spend_capture_v1('boost_fields', 'delta', '{cost}');
  end if;
end $t$;

-- 5. Gate, route, claim, outcome, progress
create or replace function security.boost_fields_gate_v1(p_now timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare g jsonb;
begin
  if security.pipeline_num_v1('boost.fields_on', 0) < 1 then return jsonb_build_object('ok', false, 'reason', 'Boost multi-field reading is switched off'); end if;
  g := security.boost_ingest_gate_v1(true, p_now);
  if not coalesce((g->>'ok')::boolean, false) then return jsonb_build_object('ok', false, 'reason', coalesce(g->>'reason', 'gate closed')); end if;
  return jsonb_build_object('ok', true, 'melbourne_minute', g->'melbourne_minute');
end $function$;
revoke all on function security.boost_fields_gate_v1(timestamptz) from public, anon, authenticated;
grant execute on function security.boost_fields_gate_v1(timestamptz) to service_role;
comment on function security.boost_fields_gate_v1(timestamptz) is 'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 3): whether the Boost multi-field reading may run now: the switch boost.fields_on, then the Boost gate (squash blackout, Maintenance Mode, housekeeping-daily).';

create or replace function public.svc_boost_fields_gate()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_fields_gate_v1(now());
end $function$;
comment on function public.svc_boost_fields_gate() is 'CF-247 Boost: the gate of the Boost multi-field reading, read by worker coverage-sweep mode boost_fields.';

create or replace function public.svc_boost_fields_route_v1()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.ai_route_v1('boost_fields_extract');
end $function$;
comment on function public.svc_boost_fields_route_v1() is 'CF-247 Boost: the route of the Boost multi-field reading (model, caps, hold), read by worker coverage-sweep mode boost_fields.';

-- the gap fields of a course, among the lanes read
create or replace function security.boost_fields_missing_v1(p_course uuid)
returns text[] language sql stable security definer set search_path to '' as $function$
  select coalesce(array_agg(l order by l), '{}') from unnest(security.pipeline_list_v1('boost.fields_lanes')) l
   where (l = 'course_description' and exists (select 1 from catalogue.courses c where c.id = p_course and nullif(btrim(coalesce(c.description, '')), '') is null)
          and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course and k.field = 'description'))
      or (l = 'delivery_mode' and exists (select 1 from catalogue.courses c where c.id = p_course and c.delivery_mode is null)
          and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = p_course and k.field = 'delivery_mode'))
      or (l = 'intakes' and not exists (select 1 from catalogue.course_intakes i where i.course_id = p_course))
      or (l = 'course_fees' and not exists (select 1 from catalogue.course_fees f where f.course_id = p_course))
      or (l = 'aer_entry' and not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = p_course))
$function$;
revoke all on function security.boost_fields_missing_v1(uuid) from public, anon, authenticated;
comment on function security.boost_fields_missing_v1(uuid) is 'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 3): the Boost gap fields a course misses, among setting boost.fields_lanes; a field held by a manual lock is not a gap.';

create or replace function security.boost_fields_claim_v1(p_limit int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_left int := least(greatest(coalesce(p_limit, 0), 0), 500);  -- fixed: bound on one call; the size is the setting batch.boost_fields
  v_batch text := 'bf-' || to_char(now() at time zone 'utc', 'YYYYMMDD"T"HH24MISS') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_items jsonb := '[]'::jsonb; v_got jsonb; r record;
begin
  if v_left = 0 or cardinality(security.pipeline_list_v1('boost.fields_lanes')) = 0 then return jsonb_build_object('batch_id', v_batch, 'items', v_items); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_fields_claim'));
  -- matrix order: each (country, category) cell by priority, for the categories of the lanes read
  for r in select m.country_code, m.enrichment_category, m.weight, array_agg(split_part(a, '=', 1)) as cell_lanes
             from security.boost_country_category_matrix_v1() m
             join unnest(security.pipeline_list_v1('boost.matrix.lane_categories')) a on split_part(a, '=', 2) = m.enrichment_category
            where m.weight > 0 and split_part(a, '=', 1) = any (security.pipeline_list_v1('boost.fields_lanes'))
            group by m.country_code, m.enrichment_category, m.weight, m.priority_rank
            order by m.priority_rank loop
    exit when v_left <= 0;
    with shared as (
      select e.content_hash from pipeline.evidence_artifacts e
       where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null and e.content_hash is not null
       group by e.content_hash having count(distinct e.entity_id) > 1),
    cand as (
      select c.id as entity_id, a.id as evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) as source_url, c.display_title, security.boost_fields_missing_v1(c.id) as lanes
        from catalogue.courses c
        join catalogue.providers p on p.id = c.provider_id
        join ref.countries k on k.id = p.country_id
        join lateral (select e.id, e.storage_path, e.source_url, e.content_hash from pipeline.evidence_artifacts e
                       where e.entity_id = c.id and e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
                       order by e.captured_at desc nulls last limit 1) a on true
       where c.lifecycle_status = 'active'
         and (k.iso_alpha2 = r.country_code
              or k.iso_alpha2 in (select split_part(x, '=', 1) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x where split_part(x, '=', 2) = r.country_code))
         and not exists (select 1 from shared h where h.content_hash = a.content_hash)
         and not exists (select 1 from pipeline.boost_field_items x where x.entity_id = c.id and x.evidence_id = a.id
                          and (x.state in ('read', 'no_signal', 'failed') or (x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes')))  -- fixed: claim lease
       ),
    pick as (select * from cand where lanes && r.cell_lanes limit v_left),
    ins as (
      insert into pipeline.boost_field_items as t (item_key, entity_id, evidence_id, country_code, category, lanes, state, batch_id, claimed_at)
      select 'bf-' || d.entity_id || '-' || d.evidence_id, d.entity_id, d.evidence_id, r.country_code, r.enrichment_category, d.lanes, 'claimed', v_batch, now() from pick d
      on conflict (item_key) do update set state = 'claimed', batch_id = excluded.batch_id, lanes = excluded.lanes, country_code = excluded.country_code, category = excluded.category,
                                          claimed_at = now(), done_at = null, result_path = null, note = null, cost = null, model_called = null
      returning t.item_key, t.entity_id, t.evidence_id)
    select coalesce(jsonb_agg(jsonb_build_object('item_key', i.item_key, 'entity', 'course', 'entity_id', i.entity_id, 'evidence_id', i.evidence_id, 'lanes', to_jsonb(d.lanes),
             'storage_path', d.storage_path, 'source_url', d.source_url, 'country_code', r.country_code, 'category', r.enrichment_category, 'weight', r.weight,
             'context', jsonb_build_object('title', d.display_title))), '[]'::jsonb)
      into v_got from ins i join pick d on d.entity_id = i.entity_id and d.evidence_id = i.evidence_id;
    v_items := v_items || v_got;
    v_left := v_left - jsonb_array_length(v_got);
  end loop;
  return jsonb_build_object('batch_id', v_batch, 'items', v_items);
end $function$;
revoke all on function security.boost_fields_claim_v1(int) from public, anon, authenticated;
comment on function security.boost_fields_claim_v1(int) is
  'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 3): claims up to p_limit active courses whose own stored course page has not been read for their gap fields, cell by cell in the order of the Boost priority matrix (country weight by the category of a missing field), with every missing field of the course to ask in one call.';

create or replace function public.svc_boost_fields_claim(p_limit int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.boost_fields_claim_v1(p_limit);
end $function$;
comment on function public.svc_boost_fields_claim(int) is 'CF-247 Boost: claims the next courses for the Boost multi-field reading (security.boost_fields_claim_v1), called by worker coverage-sweep mode boost_fields.';

create or replace function public.svc_boost_fields_done(p_batch text, p_items jsonb, p_path text, p_model text, p_prompt_version text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_n int; v_c int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with j as (select x->>'item_key' as item_key, x->>'status' as status, (x->>'model_called')::boolean as model_called, nullif(x->>'cost', '')::numeric as cost, x->>'note' as note
               from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x where x->>'status' in ('read', 'no_signal', 'failed', 'released')),
  upd as (update pipeline.boost_field_items t
             set state = j.status, model_called = j.model_called, cost = j.cost, note = left(j.note, 300), done_at = now(),
                 result_path = case when j.status = 'released' then null else p_path end
            from j where t.item_key = j.item_key and t.batch_id = p_batch and t.state = 'claimed'
          returning t.item_key)
  select count(*) into v_n from upd;
  insert into pipeline.boost_field_candidates (batch_id, item_key, course_id, evidence_id, lane, status, value, quote, problems, provider, model, prompt_version, owner)
  select p_batch, t.item_key, t.entity_id, t.evidence_id, f->>'lane', f->>'status', f->'value', left(f->>'quote', 4000), coalesce(f->'problems', '[]'::jsonb),
         case when (x->>'model_called')::boolean then 'openrouter' end, case when (x->>'model_called')::boolean then p_model end, coalesce(p_prompt_version, '?'),
         case f->>'lane' when 'course_description' then 'Course descriptions: the source-grounded description rule'
                         when 'delivery_mode' then 'Course basics: delivery mode'
                         when 'intakes' then 'Intakes (S2-Intakes)'
                         when 'course_fees' then 'Fees: the fee lane''s admission rules'
                         when 'aer_entry' then 'Entry requirements: AER v2' end
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x
    join pipeline.boost_field_items t on t.item_key = x->>'item_key' and t.batch_id = p_batch
    cross join lateral jsonb_array_elements(coalesce(x->'fields', '[]'::jsonb)) f
   where x->>'status' in ('read', 'no_signal') and f->>'lane' in ('course_description', 'delivery_mode', 'intakes', 'course_fees', 'aer_entry')
     and f->>'status' in ('verified', 'rejected', 'not_stated')
  on conflict (batch_id, item_key, lane) do nothing;
  get diagnostics v_c = row_count;
  return jsonb_build_object('batch', p_batch, 'settled', v_n, 'candidates', v_c);
end $function$;
comment on function public.svc_boost_fields_done(text, jsonb, text, text, text) is 'CF-247 Boost: records the outcome of each page of a Boost multi-field batch and stages its field answers in pipeline.boost_field_candidates (shadow), called by worker coverage-sweep mode boost_fields.';

create or replace function security.boost_fields_progress_v1()
returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object(
    'pages_by_state', (select coalesce(jsonb_object_agg(s.state, s.n), '{}'::jsonb) from (select state, count(*) n from pipeline.boost_field_items group by state) s),
    'fields', (select coalesce(jsonb_object_agg(s.lane, s.by_status), '{}'::jsonb) from (select lane, jsonb_object_agg(status, n) by_status from (select lane, status, count(*) n from pipeline.boost_field_candidates group by 1, 2) z group by lane) s),
    'model_calls', (select count(*) from pipeline.boost_field_items where model_called),
    'cost_usd', (select coalesce(sum(cost), 0) from pipeline.boost_field_items),
    'admitted', (select count(*) from pipeline.boost_field_candidates where promotion_state <> 'shadow'),
    'last_done_at', (select max(done_at) from pipeline.boost_field_items))
$function$;
revoke all on function security.boost_fields_progress_v1() from public, anon, authenticated;
grant execute on function security.boost_fields_progress_v1() to service_role;
comment on function security.boost_fields_progress_v1() is 'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 3): pages read by the Boost multi-field reading by outcome, field answers by field and check outcome, model calls, cost, and how many left shadow.';

revoke all on function public.svc_boost_fields_gate() from public, anon, authenticated;
revoke all on function public.svc_boost_fields_route_v1() from public, anon, authenticated;
revoke all on function public.svc_boost_fields_claim(int) from public, anon, authenticated;
revoke all on function public.svc_boost_fields_done(text, jsonb, text, text, text) from public, anon, authenticated;
grant execute on function public.svc_boost_fields_gate() to service_role;
grant execute on function public.svc_boost_fields_route_v1() to service_role;
grant execute on function public.svc_boost_fields_claim(int) to service_role;
grant execute on function public.svc_boost_fields_done(text, jsonb, text, text, text) to service_role;

-- 6. The job (G1)
insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('boost-fields', 'Boost', 22, 'Boost multi-field reading',
  'Every 2 minutes, all day, when setting boost.fields_on is 1 (Settings > Pipeline settings > Boost), not during the migration squash blackout and not beside housekeeping-daily: worker coverage-sweep reads each stored course page once for every Boost gap field the course misses (description, delivery mode, intakes, tuition fee, entry requirements), in the order of the Boost priority matrix, through the Models & services route Boost multi-field reading. Results go to Storage staging-boost/fields and pipeline.boost_field_candidates in shadow; each field owner''s rule decides admission.',
  6, false)
on conflict (jobname) do nothing;

select cron.schedule('boost-fields', '*/2 * * * *',
  'select pipeline.svc_pilot_submit_nonce(''coverage-sweep'', jsonb_build_object(''mode'', ''boost_fields'', ''limit'', security.pipeline_num_v1(''batch.boost_fields'', 20)::int)) where (security.boost_fields_gate_v1()->>''ok'')::boolean')
where not exists (select 1 from cron.job where jobname = 'boost-fields');

-- 7. The register
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'boost-fields', 'Layer 2', 'Boost', 'Boost multi-field reading: every gap field of a stored course page in one call', 'active', '{}', '20261118121500'),
  ('table', 'pipeline.boost_field_items', 'Layer 2', 'Boost', 'Stored pages claimed by the Boost multi-field reading, with outcome and result file', 'active', '{}', '20261118121500'),
  ('table', 'pipeline.boost_field_candidates', 'Layer 2', 'Boost', 'Boost field answers per page and field, shadow until the owner rule decides', 'active', '{}', '20261118121500'),
  ('function', 'security.boost_fields_gate_v1', 'Layer 2', 'Boost', 'Whether the Boost multi-field reading may run now', 'active', '{}', '20261118121500'),
  ('function', 'security.boost_fields_missing_v1', 'Layer 2', 'Boost', 'The Boost gap fields a course misses', 'active', '{}', '20261118121500'),
  ('function', 'security.boost_fields_claim_v1', 'Layer 2', 'Boost', 'Claims the next pages for the Boost multi-field reading in matrix order', 'active', '{}', '20261118121500'),
  ('function', 'security.boost_fields_progress_v1', 'Layer 2', 'Boost', 'Boost multi-field reading counts', 'active', '{}', '20261118121500'),
  ('function', 'public.svc_boost_fields_gate', 'Layer 2', 'Boost', 'Worker call: the Boost multi-field gate', 'active', '{}', '20261118121500'),
  ('function', 'public.svc_boost_fields_route_v1', 'Layer 2', 'Boost', 'Worker call: the Boost multi-field route', 'active', '{}', '20261118121500'),
  ('function', 'public.svc_boost_fields_claim', 'Layer 2', 'Boost', 'Worker call: claim pages for the Boost multi-field reading', 'active', '{}', '20261118121500'),
  ('function', 'public.svc_boost_fields_done', 'Layer 2', 'Boost', 'Worker call: outcome and field answers of a Boost multi-field batch', 'active', '{}', '20261118121500')
on conflict do nothing;

-- 8. Post-checks (a claim is tried and released inside this transaction)
do $c$
declare v_route jsonb := security.ai_route_v1('boost_fields_extract'); v_claim jsonb; v_again jsonb; v_item jsonb; v_done jsonb; v_cmd text;
begin
  if v_route->>'model' is distinct from (select model_identifier from pipeline.ai_model_catalogue where code = 'qwen3-30b') then raise exception 'post-check: the route does not hand out the pinned model: %', v_route; end if;
  if (select cardinality(cascade) from pipeline.ai_service_routes where service_code = 'boost_fields_extract') <> 1 then raise exception 'post-check: the route is not pinned to one model'; end if;
  if (security.boost_fields_gate_v1('2026-11-19 01:45+11')->>'ok')::boolean then raise exception 'post-check: the gate is open inside the squash blackout'; end if;
  select command into v_cmd from cron.job where jobname = 'boost-fields' and active;
  if v_cmd is null or v_cmd !~ 'boost_fields_gate_v1\(\)' or v_cmd ~ '''limit'', [0-9]' then raise exception 'post-check: the job is missing, inactive or holds a number: %', v_cmd; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'boost-fields') then raise exception 'post-check: the job is not catalogued'; end if;
  if not (select relrowsecurity from pg_class where oid = 'pipeline.boost_field_candidates'::regclass) or not (select relrowsecurity from pg_class where oid = 'pipeline.boost_field_items'::regclass) then
    raise exception 'post-check: row-level security is off';
  end if;
  if security.boost_lane_category_v1('delivery_mode') is distinct from 'course_basics' or security.boost_lane_category_v1('intakes') is distinct from 'intakes_deadlines' then raise exception 'post-check: the new lanes are not in the matrix'; end if;
  v_claim := security.boost_fields_claim_v1(3);
  v_again := security.boost_fields_claim_v1(3);
  if jsonb_array_length(v_claim->'items') > 0 then
    v_item := v_claim->'items'->0;
    if v_item->>'storage_path' is null or jsonb_array_length(v_item->'lanes') = 0
       or not (select (v_item->'lanes') @> to_jsonb(security.boost_fields_missing_v1((v_item->>'entity_id')::uuid)) and to_jsonb(security.boost_fields_missing_v1((v_item->>'entity_id')::uuid)) @> (v_item->'lanes')) then
      raise exception 'post-check: a claimed item does not carry the course''s gap fields: %', v_item;
    end if;
    if exists (select 1 from jsonb_array_elements(v_again->'items') x, jsonb_array_elements(v_claim->'items') y where x->>'item_key' = y->>'item_key') then raise exception 'post-check: a page was claimed twice'; end if;
    v_done := public.svc_boost_fields_done(v_claim->>'batch_id',
      (select jsonb_agg(jsonb_build_object('item_key', x->>'item_key', 'status', 'released', 'note', 'post-check of migration 20261118121500')) from jsonb_array_elements(v_claim->'items') x), null, null, 'boost-fields-v1');
    if (v_done->>'settled')::int <> jsonb_array_length(v_claim->'items') then raise exception 'post-check: the outcome was not recorded: %', v_done; end if;
    if jsonb_array_length(v_again->'items') > 0 then
      perform public.svc_boost_fields_done(v_again->>'batch_id',
        (select jsonb_agg(jsonb_build_object('item_key', x->>'item_key', 'status', 'released', 'note', 'post-check of migration 20261118121500')) from jsonb_array_elements(v_again->'items') x), null, null, 'boost-fields-v1');
    end if;
  end if;
  if exists (select 1 from pipeline.boost_field_items where state = 'claimed') then raise exception 'post-check: a page is still claimed'; end if;
  if exists (select 1 from pipeline.boost_field_candidates) then raise exception 'post-check: a candidate was staged by this check'; end if;
  if exists (select 1 from pipeline.boost_model_qualifications where lane <> 'study_load') then raise exception 'post-check: a model is qualified for admission on a field lane; this change qualifies none'; end if;
  if has_function_privilege('anon', 'public.svc_boost_fields_claim(int)', 'execute') or has_function_privilege('authenticated', 'public.svc_boost_fields_done(text, jsonb, text, text, text)', 'execute')
     or has_function_privilege('authenticated', 'security.boost_fields_claim_v1(int)', 'execute') then
    raise exception 'post-check: a Boost multi-field function is open to anon or authenticated';
  end if;
end $c$;
