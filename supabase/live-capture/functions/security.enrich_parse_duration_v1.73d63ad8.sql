CREATE OR REPLACE FUNCTION security.enrich_parse_duration_v1(p text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when m is null then null else jsonb_build_object('value', m[1]::numeric,
           'unit', case when m[3] ~* '^(year|yr)' then 'years' when m[3] ~* '^month' then 'months' when m[3] ~* '^week' then 'weeks'
                        when m[3] ~* '^(semester|trimester|term)' then 'semesters' end) end
    from (select regexp_match(coalesce(p, ''), '(\d+(?:\.\d+)?)\s*(-\s*\d+(?:\.\d+)?\s*|to\s*\d+(?:\.\d+)?\s*)?(years?|yrs?|months?|weeks?|semesters?|trimesters?|terms?)\M', 'i') m) x
$function$
