CREATE OR REPLACE FUNCTION security.course_entry_cost_v1()
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the measured average once 20 course reads have cost something; the setting until then
  select case when count(*) >= 20 then avg(f.cost_usd) else security.pipeline_num_v1('entry.course_read_cost_usd', 0.005) end  -- fixed: 20 reads before the average is trusted
    from pipeline.field_enrich_items f where f.field = 'entry_requirements' and coalesce(f.cost_usd, 0) > 0
$function$
