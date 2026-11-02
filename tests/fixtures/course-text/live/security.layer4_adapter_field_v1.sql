CREATE OR REPLACE FUNCTION security.layer4_adapter_field_v1(p_field_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case p_field_code when 'course_intake' then 'intakes' when 'course_english' then 'english' when 'provider_current_tuition_validation' then 'fee' end
$function$
