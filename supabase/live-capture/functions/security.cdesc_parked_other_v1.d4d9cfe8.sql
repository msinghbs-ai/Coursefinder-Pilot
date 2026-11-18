CREATE OR REPLACE FUNCTION security.cdesc_parked_other_v1(p_item uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the machine has declined this waiting item for good for a reason that is not a duplicate: it cannot be admitted, so it does not hold up a twin
  select exists (select 1 from pipeline.course_description_machine_admissions d where d.review_item_id = p_item and d.outcome = 'declined' and d.withdrawn_at is null and not d.transient and d.reason_code not like 'duplicate\_%')
$function$
