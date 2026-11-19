CREATE OR REPLACE FUNCTION security.course_description_sample_pool_v1()
 RETURNS TABLE(item_id uuid, country text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- every course description item a person has decided or can decide now (not superseded, not stale), with its provider's country
  select r.id, k.iso_alpha2::text
    from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
    join catalogue.providers pv on pv.id = c.provider_id join ref.countries k on k.id = pv.country_id
   where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and r.status <> 'superseded'
     and (r.status <> 'pending' or r.id in (select q.item_id from security.course_description_reconcile_v1(null, true, security.pipeline_num_v1('enrich.course_description_report_max', 500)::int) q where q.class = 'ready'))
$function$
