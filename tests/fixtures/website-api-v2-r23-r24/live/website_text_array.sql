CREATE OR REPLACE FUNCTION api.website_text_array(p jsonb)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select case jsonb_typeof(p)
    when 'array' then nullif(array(select btrim(x) from jsonb_array_elements_text(p) x where btrim(x)<>''), '{}')
    when 'string' then case when btrim(p #>> '{}')<>'' then array[btrim(p #>> '{}')] end
  end $function$
