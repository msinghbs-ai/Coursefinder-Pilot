CREATE OR REPLACE FUNCTION pipeline.layer3_cascade_test_spent_usd()
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
  select coalesce(sum(cost_usd),0) from pipeline.layer3_holdout_results where run_label like 'c-%'
$function$
