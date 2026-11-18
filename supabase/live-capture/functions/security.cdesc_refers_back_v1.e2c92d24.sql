CREATE OR REPLACE FUNCTION security.cdesc_refers_back_v1(p_text text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- fixed: a structural test of the grammar: the sentence opens by pointing back (security.cdesc_points_back_v1) or refers to something earlier inside it
  select security.cdesc_points_back_v1(p_text) or security.cdesc_refers_within_v1(p_text)
$function$
