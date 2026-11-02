CREATE OR REPLACE FUNCTION public.svc_nz_cop_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('path', z.storage_path, 'captured_at', z.captured_at) order by z.part)
    from (select x.* from (
            select distinct on (substring(e.storage_path from '-offset-([0-9]+)-')) substring(e.storage_path from '-offset-([0-9]+)-')::int part, e.storage_path, e.captured_at
              from pipeline.evidence_artifacts e join pipeline.sources s on s.id = e.source_id
             where s.url like 'https://www.nzqa.govt.nz/providers/%' and e.storage_path like 'regulatory/NZ/nzqa/%-offset-%'
               and e.captured_at > (select max(e2.captured_at) from pipeline.evidence_artifacts e2 where e2.source_id = e.source_id and e2.storage_path like 'regulatory/NZ/nzqa/%-offset-%')
                                   - make_interval(days => security.pipeline_num_v1('nz.cop_window_days', 3)::int)
             order by substring(e.storage_path from '-offset-([0-9]+)-'), e.captured_at desc) x
          where not exists (select 1 from pipeline.nz_cop_reads r where r.path = x.storage_path and r.error is null and r.reader = 'v2')  -- fixed: the current reader
          order by x.part limit greatest(1, least(coalesce(p_limit, 3), 10))) z), '[]'::jsonb);  -- fixed: bounds of one call
end $function$
