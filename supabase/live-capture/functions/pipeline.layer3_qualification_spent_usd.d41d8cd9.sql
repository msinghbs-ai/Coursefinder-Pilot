CREATE OR REPLACE FUNCTION pipeline.layer3_qualification_spent_usd()
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
  select coalesce(sum(cost_usd),0) from pipeline.layer3_holdout_results
$function$
