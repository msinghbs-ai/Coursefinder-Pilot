CREATE OR REPLACE FUNCTION security.coverage_norm_url(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  select rtrim(regexp_replace(regexp_replace(lower(coalesce(p,'')),'^https?://(www\.)?',''),'[?#].*$',''),'/')
$function$
