CREATE OR REPLACE FUNCTION security.cdesc_prompt_version_v1()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select 'cdesc-source-grounded-v3'::text  -- fixed: the code identity of the released course description prompt (course-text.ts CDESC_PROMPT_VERSION), not an operational value
$function$
