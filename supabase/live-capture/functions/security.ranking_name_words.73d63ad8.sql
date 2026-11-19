CREATE OR REPLACE FUNCTION security.ranking_name_words(p text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(distinct w), '{}') from regexp_split_to_table(regexp_replace(translate(lower(split_part(coalesce(p, ''), '|', 1)), 'àáâãäåāçćčèéêëēěìíîïīñńòóôõöøōùúûüūýÿžšœæ’', 'aaaaaaaccceeeeeeiiiiinnooooooouuuuuyyzsoa'''), '[^a-z0-9]+', ' ', 'g'), '\s+') w
   where length(w) > 1 and w not in ('the','of','and','at','in','for','university','universit','universite','college','institute','institut','de','du','des','la','le','les','et','school','inc','ltd','limited','campus','including')
$function$
