CREATE OR REPLACE FUNCTION security.pdesc_support_v1(p_sentence text, p_quote text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  with s as (select distinct left(w, 5) w from regexp_split_to_table(lower(coalesce(p_sentence, '')), '[^a-z0-9]+') w
              where length(w) >= 4 and w not in ('that', 'this', 'with', 'from', 'into', 'their', 'there', 'which', 'where', 'what', 'have', 'also', 'such', 'they', 'them', 'than', 'more', 'most', 'other', 'offers', 'offer', 'provides', 'provide')),
       q as (select distinct left(w, 5) w from regexp_split_to_table(lower(coalesce(p_quote, '')), '[^a-z0-9]+') w where length(w) >= 4)
  select case when (select count(*) from s) = 0 then 1 else round((select count(*) from s where s.w in (select w from q))::numeric / (select count(*) from s), 4) end
$function$
