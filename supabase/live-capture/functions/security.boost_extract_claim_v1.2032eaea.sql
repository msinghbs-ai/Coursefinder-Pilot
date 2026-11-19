CREATE OR REPLACE FUNCTION security.boost_extract_claim_v1(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    with shared as (
      select e.content_hash from pipeline.evidence_artifacts e
       where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null and e.content_hash is not null
       group by e.content_hash having count(distinct e.entity_id) > 1),
    cand as (
      select c.id as entity_id, a.id as evidence_id, a.storage_path, coalesce(a.source_url, c.course_url) as source_url, c.display_title
        from catalogue.courses c
        join catalogue.providers p on p.id = c.provider_id
        join ref.countries k on k.id = p.country_id
        join lateral (select e.id, e.storage_path, e.source_url, e.content_hash from pipeline.evidence_artifacts e
                       where e.entity_id = c.id and e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
                       order by e.captured_at desc nulls last limit 1) a on true
       where c.lifecycle_status = 'active' and c.study_load is null
         and (k.iso_alpha2 = r.country_code
              or k.iso_alpha2 in (select split_part(x, '=', 1) from unnest(security.pipeline_list_v1('boost.matrix.country_aliases')) x where split_part(x, '=', 2) = r.country_code))
         -- a stored page whose text is also stored for another course is a general page of the provider, not this course's page: not read
         and not exists (select 1 from shared h where h.content_hash = a.content_hash)
         and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))
         and not exists (select 1 from pipeline.boost_extract_items x where x.lane = 'study_load' and x.entity_id = c.id and x.evidence_id = a.id
                          and (x.state in ('verified', 'rejected', 'failed') or (x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes')))  -- fixed: claim lease
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
end $function$
