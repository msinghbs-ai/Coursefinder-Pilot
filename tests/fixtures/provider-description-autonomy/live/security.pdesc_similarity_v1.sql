CREATE OR REPLACE FUNCTION security.pdesc_similarity_v1(a text, b text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  with x as (select security.pdesc_words_v1(a) wa, security.pdesc_words_v1(b) wb)
  select case when cardinality(x.wa) = 0 or cardinality(x.wb) = 0 then 0
              else round((select count(*) from unnest(x.wa) w where w = any (x.wb))::numeric
                         / (select count(*) from (select unnest(x.wa) union select unnest(x.wb)) u), 4) end
    from x
$function$

