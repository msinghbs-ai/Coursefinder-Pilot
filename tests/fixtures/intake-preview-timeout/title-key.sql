-- Authoritative production function snapshot, 4 Nov 2026; replaces the old fixture simplification only.
CREATE OR REPLACE FUNCTION security.course_title_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select btrim(regexp_replace(replace(lower(coalesce(p, '')), '&', ' and '), '[^a-z0-9]+', ' ', 'g'))
$function$;
