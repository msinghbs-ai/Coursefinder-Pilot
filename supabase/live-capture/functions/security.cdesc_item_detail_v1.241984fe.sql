CREATE OR REPLACE FUNCTION security.cdesc_item_detail_v1(p_course_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('course_id', c.id, 'field', 'description', 'catalogue_chars', length(btrim(coalesce(c.description, ''))),
           'item', case when e.id is null then null else jsonb_build_object('id', e.id, 'state', e.state, 'reason', e.reason, 'attempts', e.attempts, 'source', e.source,
                      'evidence_id', e.evidence_id, 'storage_path', e.storage_path, 'reading_chars', length(btrim(coalesce(e.value->>'text', ''))), 'at', e.updated_at) end) order by c.id), '[]'::jsonb)
    from catalogue.courses c
    left join lateral (select x.id, x.state, x.reason, x.attempts, x.source, x.evidence_id, x.storage_path, x.value, x.updated_at from pipeline.field_enrich_items x
                        where x.course_id = c.id and x.field = 'description' order by x.id desc limit 1) e on true
   where c.id = any (p_course_ids)
$function$
