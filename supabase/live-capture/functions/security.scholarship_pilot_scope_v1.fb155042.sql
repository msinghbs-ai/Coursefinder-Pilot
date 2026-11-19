CREATE OR REPLACE FUNCTION security.scholarship_pilot_scope_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select not security.scholarship_flag_v1('scholarship.pilot_only', true) or security.scholarship_pilot_member_v1(p_provider_id)
$function$
