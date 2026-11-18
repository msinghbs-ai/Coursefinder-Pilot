CREATE OR REPLACE FUNCTION security.aer_quote_has_value_v1(p_quote text, p_grade text, p_value numeric)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- the published minimum is in the quote as a whole token: the grade text when the row has one, otherwise the value (70, 3.3; never 170 or 3.35)
  select case when nullif(btrim(coalesce(p_grade, '')), '') is not null
              then coalesce(p_quote, '') ~* ('(^|[^0-9A-Za-z.])' || regexp_replace(btrim(p_grade), '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '($|[^0-9A-Za-z])')
              when p_value is not null
              then coalesce(p_quote, '') ~ ('(^|[^0-9.])' || replace(trim_scale(p_value)::text, '.', '\.') || '($|[^0-9])')
              else false end
$function$
