CREATE OR REPLACE FUNCTION security.cdesc_sentence_substance_v1(p_text text, p_quote text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- fixed: words of four or more letters compared on their first five, the rule of security.pdesc_support_v1 (a count of supported words, not a share)
  select count(*)::int from (select distinct left(w, 5) w from regexp_split_to_table(lower(coalesce(p_text, '')), '[^a-z0-9]+') w where length(w) >= 4) s
   where s.w in (select left(q, 5) from regexp_split_to_table(lower(coalesce(p_quote, '')), '[^a-z0-9]+') q where length(q) >= 4)
$function$
