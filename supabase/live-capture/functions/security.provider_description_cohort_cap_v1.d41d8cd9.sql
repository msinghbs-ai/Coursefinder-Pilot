CREATE OR REPLACE FUNCTION security.provider_description_cohort_cap_v1()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the one cap on a cohort: the screen's limit (capabilities.max_size) and the server's Run Now check are this same number
  select least(security.pipeline_num_v1('pdesc.queue_per_run', 10), security.pipeline_num_v1('pdesc.pending_max', 10), security.pipeline_num_v1('run_now.pilot_cap', 20), security.pipeline_num_v1('pdesc.queue_cap', 60))::int
$function$
