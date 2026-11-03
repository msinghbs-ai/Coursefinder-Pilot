CREATE OR REPLACE FUNCTION security.pdesc_has_term_v1(p_text text, p_term text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select nullif(btrim(regexp_replace(lower(coalesce(p_term, '')), '[^a-z0-9#%]+', ' ', 'g')), '') is not null
     and position(' ' || btrim(regexp_replace(lower(coalesce(p_term, '')), '[^a-z0-9#%]+', ' ', 'g')) || ' '
                  in ' ' || regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9#%]+', ' ', 'g') || ' ') > 0
$function$
