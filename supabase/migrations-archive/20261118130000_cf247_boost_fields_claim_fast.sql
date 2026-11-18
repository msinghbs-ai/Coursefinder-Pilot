-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 07:08 decision 3): the claim of the Boost multi-field reading, made fast enough for the worker.
-- What was wrong: security.boost_fields_claim_v1 of migration 20261118121500 worked out the gap fields of every active course of a country
-- (one function call per course) for each cell of the priority matrix. Called by the worker as service_role it ran past the API's statement
-- time-out on every run since 11:01 AEDT (HTTP 500 "canceling statement due to statement timeout"), so no page was read. The migration's own
-- post-check ran it as postgres, with no time-out, and passed.
-- What it does: the claim starts from the stored course pages (about 3,000, read through the index on evidence type), works out each one's
-- gap fields once per call in one query, and then takes them cell by cell in the order of the priority matrix as before. Same rules: own
-- page only (not a text stored for another course), active course, not read before, claim lease, every missing field asked in one call.
-- G1, G2, G3: unchanged.
-- Replaces: security.boost_fields_claim_v1 of migration 20261118121500 (same result, one pass)
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
declare v text;
begin
  v := md5(pg_get_functiondef('security.boost_fields_claim_v1(int)'::regprocedure));
  if v <> 'ca58e9b4cd2058fceb814806852fe6a6' then raise exception 'security.boost_fields_claim_v1 is not the definition this migration replaces (md5 %)', v; end if;
end $pre$;

create or replace function security.boost_fields_claim_v1(p_limit int)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare
  v_left int := least(greatest(coalesce(p_limit, 0), 0), 500);  -- fixed: bound on one call; the size is the setting batch.boost_fields
  v_batch text := 'bf-' || to_char(now() at time zone 'utc', 'YYYYMMDD"T"HH24MISS') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_lanes text[] := security.pipeline_list_v1('boost.fields_lanes');
  v_alias text[] := security.pipeline_list_v1('boost.matrix.country_aliases');
  v_items jsonb := '[]'::jsonb; v_got jsonb; r record;
begin
  if v_left = 0 or cardinality(v_lanes) = 0 then return jsonb_build_object('batch_id', v_batch, 'items', v_items); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_fields_claim'));
  -- every stored own course page not yet read, with the course's gap fields, worked out once
  create temp table if not exists cf_bf_cand (entity_id uuid primary key, evidence_id uuid, storage_path text, source_url text, title text, cc text, lanes text[], taken boolean) on commit drop;
  truncate cf_bf_cand;
  insert into cf_bf_cand
  with pages as (
    select distinct on (e.entity_id) e.entity_id, e.id, e.storage_path, e.source_url, e.content_hash
      from pipeline.evidence_artifacts e
     where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
     order by e.entity_id, e.captured_at desc nulls last),
  shared as (select p.content_hash from pages p where p.content_hash is not null group by p.content_hash having count(*) > 1),
  base as (
    select c.id as entity_id, a.id as evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) as source_url, c.display_title as title,
           coalesce((select split_part(x, '=', 2) from unnest(v_alias) x where split_part(x, '=', 1) = k.iso_alpha2 limit 1), k.iso_alpha2) as cc,
           array_remove(array[
             case when 'course_description' = any (v_lanes) and nullif(btrim(coalesce(c.description, '')), '') is null
                   and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'description') then 'course_description' end,
             case when 'delivery_mode' = any (v_lanes) and c.delivery_mode is null
                   and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field = 'delivery_mode') then 'delivery_mode' end,
             case when 'intakes' = any (v_lanes) and not exists (select 1 from catalogue.course_intakes i where i.course_id = c.id) then 'intakes' end,
             case when 'course_fees' = any (v_lanes) and not exists (select 1 from catalogue.course_fees f where f.course_id = c.id) then 'course_fees' end,
             case when 'aer_entry' = any (v_lanes) and not exists (select 1 from catalogue.course_entry_requirements q where q.course_id = c.id) then 'aer_entry' end], null) as lanes
      from pages a
      join catalogue.courses c on c.id = a.entity_id and c.lifecycle_status = 'active'
      join catalogue.providers p on p.id = c.provider_id
      join ref.countries k on k.id = p.country_id
     where not exists (select 1 from shared h where h.content_hash = a.content_hash)
       and not exists (select 1 from pipeline.boost_field_items x where x.entity_id = c.id and x.evidence_id = a.id
                        and (x.state in ('read', 'no_signal', 'failed') or (x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes'))))  -- fixed: claim lease
  select b.entity_id, b.evidence_id, b.storage_path, b.source_url, b.title, b.cc, b.lanes, false from base b where cardinality(b.lanes) > 0;
  -- matrix order: each (country, category) cell by priority, for the categories of the lanes read
  for r in select m.country_code, m.enrichment_category, m.weight, array_agg(split_part(a, '=', 1)) as cell_lanes
             from security.boost_country_category_matrix_v1() m
             join unnest(security.pipeline_list_v1('boost.matrix.lane_categories')) a on split_part(a, '=', 2) = m.enrichment_category
            where m.weight > 0 and split_part(a, '=', 1) = any (v_lanes)
            group by m.country_code, m.enrichment_category, m.weight, m.priority_rank
            order by m.priority_rank loop
    exit when v_left <= 0;
    with pick as (
      update cf_bf_cand d set taken = true
       where d.entity_id in (select z.entity_id from cf_bf_cand z where not z.taken and z.cc = r.country_code and z.lanes && r.cell_lanes order by z.entity_id limit v_left)
      returning d.*),
    ins as (
      insert into pipeline.boost_field_items as t (item_key, entity_id, evidence_id, country_code, category, lanes, state, batch_id, claimed_at)
      select 'bf-' || d.entity_id || '-' || d.evidence_id, d.entity_id, d.evidence_id, r.country_code, r.enrichment_category, d.lanes, 'claimed', v_batch, now() from pick d
      on conflict (item_key) do update set state = 'claimed', batch_id = excluded.batch_id, lanes = excluded.lanes, country_code = excluded.country_code, category = excluded.category,
                                          claimed_at = now(), done_at = null, result_path = null, note = null, cost = null, model_called = null
      returning t.item_key, t.entity_id)
    select coalesce(jsonb_agg(jsonb_build_object('item_key', i.item_key, 'entity', 'course', 'entity_id', d.entity_id, 'evidence_id', d.evidence_id, 'lanes', to_jsonb(d.lanes),
             'storage_path', d.storage_path, 'source_url', d.source_url, 'country_code', r.country_code, 'category', r.enrichment_category, 'weight', r.weight,
             'context', jsonb_build_object('title', d.title))), '[]'::jsonb)
      into v_got from ins i join pick d on d.entity_id = i.entity_id;
    v_items := v_items || v_got;
    v_left := v_left - jsonb_array_length(v_got);
  end loop;
  return jsonb_build_object('batch_id', v_batch, 'items', v_items);
end $function$;
revoke all on function security.boost_fields_claim_v1(int) from public, anon, authenticated;
comment on function security.boost_fields_claim_v1(int) is
  'CF-247 Boost (Platform Admin 18 Nov 2026 07:08 decision 3): claims up to p_limit active courses whose own stored course page has not been read for their gap fields, cell by cell in the order of the Boost priority matrix (country weight by the category of a missing field), with every missing field of the course to ask in one call. Starts from the stored pages; gap fields worked out once per call (migration 20261118130000).';

-- Post-checks: the claim answers under the API's time limit, as the worker's role sees it, and carries each course's gap fields
do $c$
declare v_t0 timestamptz := clock_timestamp(); v_claim jsonb; v_ms numeric; v_item jsonb;
begin
  set local statement_timeout = '8s';  -- fixed: the API's statement time-out, which the old claim ran past
  v_claim := security.boost_fields_claim_v1(20);
  v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
  if v_ms > 5000 then raise exception 'post-check: the claim took % ms', round(v_ms); end if;
  for v_item in select x from jsonb_array_elements(v_claim->'items') x loop
    if not ((v_item->'lanes') @> to_jsonb(security.boost_fields_missing_v1((v_item->>'entity_id')::uuid)) and to_jsonb(security.boost_fields_missing_v1((v_item->>'entity_id')::uuid)) @> (v_item->'lanes')) then
      raise exception 'post-check: a claimed item does not carry the course''s gap fields: %', v_item;
    end if;
  end loop;
  if jsonb_array_length(v_claim->'items') > 0 then
    perform public.svc_boost_fields_done(v_claim->>'batch_id',
      (select jsonb_agg(jsonb_build_object('item_key', x->>'item_key', 'status', 'released', 'note', 'post-check of migration 20261118130000')) from jsonb_array_elements(v_claim->'items') x), null, null, 'boost-fields-v1');
  end if;
  if exists (select 1 from pipeline.boost_field_items where state = 'claimed' and batch_id = v_claim->>'batch_id') then raise exception 'post-check: a page is still claimed'; end if;
  raise notice 'boost_fields claim: % items in % ms', jsonb_array_length(v_claim->'items'), round(v_ms);
end $c$;
