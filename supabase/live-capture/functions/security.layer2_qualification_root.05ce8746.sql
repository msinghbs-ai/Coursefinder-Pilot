CREATE OR REPLACE FUNCTION security.layer2_qualification_root(p_run_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
  with recursive chain(id,depth) as (
    select p_run_id,0
    union all
    select p.id,chain.depth+1
    from chain
    join pipeline.layer2_scale_qualification_runs p
      on nullif(p.result_summary->>'next_qualification_run_id','')::uuid=chain.id
    where chain.depth<100
  )
  select id from chain order by depth desc limit 1
$function$
