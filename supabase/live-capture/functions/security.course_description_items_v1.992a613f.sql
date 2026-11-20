CREATE OR REPLACE FUNCTION security.course_description_items_v1(p_provider uuid DEFAULT NULL::uuid, p_offset integer DEFAULT 0, p_sample boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with r as (
    select q.* from security.course_description_reconcile_v1(p_provider, p_provider is not null, security.pipeline_num_v1('enrich.course_description_report_max', 500)::int) q
     where q.class = 'ready' and (not coalesce(p_sample, false) or q.item_id in (select s.item_id from security.course_description_sample_ids_v1() s))),
  pg as (select r.* from r order by r.created_at, r.item_id limit security.pipeline_num_v1('layer4.inbox_page_size', 25)::int offset greatest(coalesce(p_offset, 0), 0))
  select jsonb_build_object(
    'total', (select count(*) from r),
    'offset', greatest(coalesce(p_offset, 0), 0), 'limit', security.pipeline_num_v1('layer4.inbox_page_size', 25)::int,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'kind', 'provider_description', 'ref', pg.item_id::text, 'provider_id', pg.provider_id, 'provider', coalesce(pv.display_name, pv.canonical_name), 'subject', pg.course_title,
        'why', coalesce(nullif(i.escalation_reason, ''), 'Needs a decision'), 'created_at', pg.created_at, 'ready', true,
        'detail', jsonb_strip_nulls(jsonb_build_object('field_code', i.field_code, 'course_id', pg.course_id, 'course_code', c.course_code,
                    'code_label', case when pg.country = 'AU' then 'CRICOS' else 'Course code' end,
                    'before', i.before_value, 'proposed', i.proposed_value, 'evidence_id', i.evidence_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                    'reask', pg.reask, 'in_sample', pg.item_id in (select s.item_id from security.course_description_sample_ids_v1() s),
                    -- the stored reading checked again now, so a card says when its rules have moved since it was proposed
                    'rules_now', case when pg.rechecked then jsonb_build_object('ok', true) else
                                  (select jsonb_build_object('ok', coalesce((z.v->>'ok')::boolean, false), 'rule', z.v->>'rule', 'reason', z.v->>'reason')
                                     from (select security.course_description_check_v1(pg.course_id, e.value) v) z) end)))
        order by pg.created_at, pg.item_id)
      from pg join pipeline.layer4_review_items i on i.id = pg.item_id
      join catalogue.courses c on c.id = pg.course_id
      left join catalogue.providers pv on pv.id = pg.provider_id
      left join pipeline.field_enrich_items e on e.id = pg.enrich_item
      left join pipeline.evidence_artifacts ev on ev.id = i.evidence_id), '[]'::jsonb))
$function$
