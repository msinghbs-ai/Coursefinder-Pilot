CREATE OR REPLACE FUNCTION public.svc_ranking_applied_import_for_source(p_source_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'ranking'
AS $function$
  select jsonb_build_object('import_id',m.id,'content_hash',m.content_hash,'original_filename',m.original_filename,'edition_year',m.edition_year)
    from pipeline.sources s
    join ranking.systems sy on sy.code=s.metadata->>'ranking_system_code'
    join ranking.manual_imports m on m.system_id=sy.id and m.edition_year=(s.metadata->>'edition_year')::int and m.status='applied'
   where s.id=p_source_id
   order by m.updated_at desc limit 1
$function$
