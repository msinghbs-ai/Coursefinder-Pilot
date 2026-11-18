CREATE OR REPLACE FUNCTION security.cdesc_norm_v1(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select btrim(regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', ' ', 'g'))
$function$
