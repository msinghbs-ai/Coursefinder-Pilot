CREATE OR REPLACE FUNCTION security.course_description_trusted_v1(p_provider uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with n as (select greatest(1, security.pipeline_num_v1('enrich.course_description_review_first', 5)::int) k),
  d as (select r.status from pipeline.layer4_review_items r join catalogue.courses c on c.id = r.entity_id
         where r.entity_type = 'course' and r.field_code = 'course_description_first_read' and c.provider_id = p_provider and not exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = r.id and md.layer2_state->>'actor_kind' = 'machine')
           and r.status in ('approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
         order by r.decided_at desc nulls last limit (select k from n))
  select count(*) = (select k from n) and bool_and(d.status in ('approved', 'edited_approved')) from d
$function$
