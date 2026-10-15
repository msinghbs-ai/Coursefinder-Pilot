CREATE OR REPLACE FUNCTION security.layer2_lineage_for_job(p_job_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
  select jsonb_build_object(
    'parent_run_id',coalesce(r.metadata->>'parent_run_id',r.id::text),
    'scope_wave_request_id',r.id,
    'batch_id',i.batch_id,
    'scope_type',r.scope_type,
    'scope_id',r.scope_id,
    'country_code',r.country_code,
    'route_mode',r.route_mode,
    'lineage_version','a26-v1'
  )
  from pipeline.layer2_run_items i
  join pipeline.layer2_scope_wave_items wi on wi.batch_id=i.batch_id and wi.course_id=i.entity_id
  join pipeline.layer2_scope_wave_requests r on r.id=wi.request_id
  where i.job_id=p_job_id
  order by wi.ordinal
  limit 1
$function$
