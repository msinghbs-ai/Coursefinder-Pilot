CREATE OR REPLACE FUNCTION public.svc_fc_extract_cases(p_task_class text, p_offset integer, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('case_id', c.id, 'task_class', c.task_class, 'url', c.source_url, 'gold', c.gold) order by c.case_key), '[]'::jsonb) into v
    from (select * from pipeline.layer3_holdout_cases where task_class = p_task_class order by case_key offset greatest(0, coalesce(p_offset, 0)) limit greatest(1, least(coalesce(p_limit, 50), 100))) c;
  return v;
end $function$
