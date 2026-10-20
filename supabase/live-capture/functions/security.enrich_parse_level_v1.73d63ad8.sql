CREATE OR REPLACE FUNCTION security.enrich_parse_level_v1(p text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select sl.id from ref.study_levels sl
   where sl.short_code = (case when p is null or length(p) > 60 then null
                               when p ~* '(ph\.?d|doctor)' then 'DR'
                               when p ~* 'master' then 'MA'
                               when p ~* 'graduate diploma|post-?graduate diploma' then 'GD'
                               when p ~* 'graduate certificate|post-?graduate certificate' then 'GC'
                               when p ~* 'honours' then 'BH'
                               when p ~* 'bachelor|baccalaur|degree' then 'BA'
                               when p ~* 'associate' then 'AS'
                               when p ~* 'advanced diploma' then 'AD'
                               when p ~* 'diploma|dipl[oô]me' then 'DP'
                               when p ~* 'certificate|certificat' then 'CT' end)
   limit 1
$function$
