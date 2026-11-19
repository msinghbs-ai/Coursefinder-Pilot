create or replace function public.svc_ranking_applied_import_for_source(p_source_id uuid)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline','ranking' as $f$
  select jsonb_build_object('import_id',m.id,'content_hash',m.content_hash,'original_filename',m.original_filename,'edition_year',m.edition_year)
    from pipeline.sources s
    join ranking.systems sy on sy.code=s.metadata->>'ranking_system_code'
    join ranking.manual_imports m on m.system_id=sy.id and m.edition_year=(s.metadata->>'edition_year')::int and m.status='applied'
   where s.id=p_source_id
   order by m.updated_at desc limit 1
$f$;
revoke all on function public.svc_ranking_applied_import_for_source(uuid) from public, anon, authenticated;
grant execute on function public.svc_ranking_applied_import_for_source(uuid) to service_role;
select public.svc_ranking_applied_import_for_source('a886e94f-bb68-4bfb-82a7-964b587f5067');
