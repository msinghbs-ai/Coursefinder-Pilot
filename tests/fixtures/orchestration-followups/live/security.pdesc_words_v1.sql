CREATE OR REPLACE FUNCTION security.pdesc_words_v1(p text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct w), '{}'::text[]) from regexp_split_to_table(lower(coalesce(p, '')), '[^a-z0-9]+') w where length(w) >= 3
$function$
