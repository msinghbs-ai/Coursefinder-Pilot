CREATE OR REPLACE FUNCTION pipeline.layer3_holdout_digest(p_gold_set text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pipeline', 'extensions'
AS $function$
  select encode(extensions.digest(coalesce(string_agg(concat_ws('|', c.case_key, c.course_id, c.evidence_id, c.text_sha256, c.gold::text, coalesce(c.evidence_excerpt,'~'), coalesce(c.candidate_context::text,'~')), E'\n' order by c.case_key),''),'sha256'),'hex')
    from pipeline.layer3_holdout_cases c where c.gold_set=p_gold_set
$function$
