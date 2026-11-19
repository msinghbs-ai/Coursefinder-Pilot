CREATE OR REPLACE FUNCTION security.ranking_name_key(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select regexp_replace(regexp_replace(regexp_replace(translate(lower(split_part(coalesce(p, ''), '|', 1)), 'àáâãäåāçćčèéêëēěìíîïīñńòóôõöøōùúûüūýÿžšœæ’', 'aaaaaaaccceeeeeeiiiiinnooooooouuuuuyyzsoa'''), '\([^)]*\)', '', 'g'), '^\s*the\s+', ''), '[^a-z0-9]+', '', 'g')
$function$
