CREATE OR REPLACE FUNCTION security.place_presentable(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p is null then null
              when p ~ '[a-z]' or p !~ '[A-Z]' then btrim(p)
              else regexp_replace(initcap(btrim(p)),'\mMc([a-z])','Mc\1','g') end
$function$
