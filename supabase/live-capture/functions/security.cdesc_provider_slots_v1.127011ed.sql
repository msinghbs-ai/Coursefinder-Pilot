CREATE OR REPLACE FUNCTION security.cdesc_provider_slots_v1(p_provider uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the places a provider still has for first descriptions waiting in Layer 4: enrich.course_description_pending_max less the waiting items the machine has NOT declined for good under the current policy (those wait for a person and take no place a reading could use)
  select security.pipeline_num_v1('enrich.course_description_pending_max', 10)::int - count(*)::int
    from pipeline.layer4_review_items q join catalogue.courses c on c.id = q.entity_id
   where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending' and c.provider_id = p_provider
     and not exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = q.id and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient
                        and d.policy_stamp = security.course_description_machine_policy_stamp_v1())
$function$
