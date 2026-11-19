-- CF-247 s799 (Platform Admin 20 Nov 2026 05:42 AEDT, chat S1-Build, item 3): the two claims that still time out under load, after s788 closed enrich_ai.
-- Read live 20 Nov 2026 06:40 AEDT (rolled back): svc_boost_extract_claim(40) 1,526 ms with nothing to hand out; svc_coverage_reidentify_next(100) 588 ms;
-- 3 and 2 HTTP 500 statement time-outs in the last 24 hours. Causes: the boost claim grouped every stored page text by content hash (20,855 rows) once per
-- country (six) to find shared provider pages, then looked up each course's latest page text through the general entity index; the reidentify claim
-- walked the page status index and sorted.
-- Fix (the s788 pattern: an index that matches the claim, and the claim states it): two partial indexes on stored page texts (by hash, and by course
-- and capture time), and one on the pages waiting to be re-identified (by course, the claim's order). The boost claim now checks "is this page shared
-- with another course" per candidate through the hash index; same rule, same output, same lease, same lock, same lanes and weights. The reidentify
-- claim is unchanged; its index now matches its filter and order.
-- The boost claim also keeps the s797 rule: a B7 rule value (source register, no evidence id) is still open to a reading.
-- Parity before writing (read live 20 Nov 2026 05:45 AEDT): head 20261120010000; merged after s797 (20261120070000), whose edit of the same function it keeps.
-- G3: no consumer object. No spend (claims only hand out work that was already due).
-- Replaces: the per-country content-hash grouping in security.boost_extract_claim_v1.
-- Retires: nothing.

create index if not exists evidence_artifacts_page_text_hash_idx on pipeline.evidence_artifacts (content_hash, entity_id)
  where evidence_type = 'provider_course_page_text' and storage_path is not null and content_hash is not null;
create index if not exists evidence_artifacts_page_text_entity_idx on pipeline.evidence_artifacts (entity_id, captured_at desc nulls last)
  where evidence_type = 'provider_course_page_text' and storage_path is not null;
create index if not exists coverage_course_pages_reidentify_idx on pipeline.coverage_course_pages (course_id)
  where status = 'mismatch' and read_status = 'identity_mismatch';

do $pre$
declare v_def text := replace(pg_get_functiondef('security.boost_extract_claim_v1(integer)'::regprocedure), chr(13), '');
begin
  if md5(v_def) <> 'a80ff8e9ce2989abe8f786b0748c9357' and v_def not like '%c.study_load_evidence_id is null))  -- s797%' then
    raise exception 'pre-check: security.boost_extract_claim_v1 changed since it was read (definition md5 %)', md5(v_def);
  end if;
end $pre$;

create or replace function security.boost_extract_claim_v1(p_limit integer)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_left int := least(greatest(coalesce(p_limit, 0), 0), 500);  -- fixed: bound on one call; the size is the setting batch.boost_extract
  v_batch text := 'bx-' || to_char(now() at time zone 'utc', 'YYYYMMDD"T"HH24MISS') || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
  v_cat text := security.boost_lane_category_v1('study_load');
  v_items jsonb := '[]'::jsonb; v_got jsonb; r record; v_codes text[];
begin
  if not ('study_load' = any (security.pipeline_list_v1('boost.extract_lanes'))) or v_cat is null or v_left = 0 then
    return jsonb_build_object('batch_id', v_batch, 'items', v_items);
  end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_extract_claim'));
  for r in select m.country_code, m.weight from security.boost_country_category_matrix_v1() m
            where m.enrichment_category = v_cat and m.weight > 0 order by m.priority_rank loop
    exit when v_left <= 0;
    v_codes := array[r.country_code] || array(select split_part(x, '=', 1) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x
                                              where split_part(x, '=', 2) = r.country_code);
    with cand as materialized (
      select c.id as entity_id, a.id as evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) as source_url, c.display_title
        from catalogue.courses c
        join catalogue.providers p on p.id = c.provider_id
        join ref.countries k on k.id = p.country_id and k.iso_alpha2 = any (v_codes)
        join lateral (select e.id, e.storage_path, e.source_url, e.content_hash from pipeline.evidence_artifacts e
                       where e.entity_id = c.id and e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
                       order by e.captured_at desc nulls last limit 1) a on true
       where c.lifecycle_status = 'active' and (c.study_load is null or (c.study_load_source = 'register' and c.study_load_evidence_id is null))  -- s797
         and not exists (select 1 from pipeline.boost_extract_items x where x.lane = 'study_load' and x.entity_id = c.id and x.evidence_id = a.id
                          and (x.state in ('verified', 'rejected', 'failed') or (x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes')))  -- fixed: claim lease
         -- a stored page whose text is also stored for another course is a general page of the provider, not this course's page: not read (s799: per page, by index)
         and not exists (select 1 from pipeline.evidence_artifacts h where h.content_hash = a.content_hash and h.evidence_type = 'provider_course_page_text'
                          and h.storage_path is not null and h.content_hash is not null and h.entity_id <> c.id)
         and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))
       limit v_left),
    ins as (
      insert into pipeline.boost_extract_items as t (item_key, lane, entity, entity_id, evidence_id, country_code, state, batch_id, claimed_at)
      select 'sl-' || d.entity_id || '-' || d.evidence_id, 'study_load', 'course', d.entity_id, d.evidence_id, r.country_code, 'claimed', v_batch, now() from cand d
      on conflict (item_key) do update set state = 'claimed', batch_id = excluded.batch_id, claimed_at = now(), done_at = null, result_path = null, note = null,
                                          cost = null, model_called = null
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

-- post-checks: the same work is handed out, and both claims answer in time (timed in a sub-block that is always rolled back: nothing stays claimed)
do $$
declare t timestamptz; ms1 int; ms2 int; ms1b int; n1 int; n2 int; v jsonb; v_rule text; v_o text;
begin
  select max(rule) into v_rule from pipeline.coverage_reidentify_done;
  begin
    t := clock_timestamp(); v := public.svc_boost_extract_claim(security.pipeline_num_v1('batch.boost_extract', 40)::int); ms1 := round(extract(epoch from clock_timestamp() - t) * 1000); n1 := jsonb_array_length(v->'items');
    t := clock_timestamp(); v := public.svc_boost_extract_claim(40); ms1b := round(extract(epoch from clock_timestamp() - t) * 1000);
    t := clock_timestamp(); v := public.svc_coverage_reidentify_next(100, v_rule); ms2 := round(extract(epoch from clock_timestamp() - t) * 1000); n2 := jsonb_array_length(v);
    raise exception 'cf-s799-undo';
  exception when raise_exception then if sqlerrm <> 'cf-s799-undo' then raise; end if;
  end;
  v_o := format('boost claim %s ms (%s items), again %s ms | reidentify(100, %s) %s ms (%s rows)', ms1, n1, ms1b, v_rule, ms2, n2);
  if ms1 > 1000 or ms2 > 1000 then raise exception 'post-check: a claim is still slow: %', v_o; end if;
  perform set_config('cf.diag', v_o, true);
end $$;
