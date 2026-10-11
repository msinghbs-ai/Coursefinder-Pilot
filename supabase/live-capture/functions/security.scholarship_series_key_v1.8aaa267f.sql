CREATE OR REPLACE FUNCTION security.scholarship_series_key_v1(p_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select btrim(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p_name, '')),
           '^\s*(\d{4}\s*[-:]\s*)?((semester|sem|trimester|term|intake)\s*\d+\s*[-:]?\s*)?(\d{4}\s*[-:]\s*)?', ''),
           '\s*\((a?\$|aud)?\s*[\d,.]+\s*k?\)\s*$', ''), '\s+', ' ', 'g'))
$function$
