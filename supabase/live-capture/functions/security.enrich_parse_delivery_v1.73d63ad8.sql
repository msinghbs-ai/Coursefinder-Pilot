CREATE OR REPLACE FUNCTION security.enrich_parse_delivery_v1(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p is null or btrim(p) = '' then null
              when p ~* '(blended|hybrid)' then 'blended'
              when p ~* '(on[- ]?campus|in[- ]person|face[- ]to[- ]face|campus)' and p ~* '(online|distance)' then 'on_campus_and_online'
              when p ~* '(100\s*%\s*online|fully online|online only|online$|^online|distance)' then 'online'
              when p ~* '(on[- ]?campus|in[- ]person|face[- ]to[- ]face)' then 'on_campus'
              else null end
$function$
