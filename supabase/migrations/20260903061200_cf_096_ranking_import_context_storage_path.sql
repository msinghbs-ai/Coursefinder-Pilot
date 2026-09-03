create or replace function public.svc_ranking_import_control_context(p_import_id uuid)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','ranking','pipeline'
as $$
 with x as (
   select mi.*,rs.code system_code,
          case rs.code
            when 'the_wur' then 'THE'
            when 'qs_wur' then 'QS'
            when 'arwu' then 'ARWU'
            else upper(rs.code)
          end source_system
   from ranking.manual_imports mi
   join ranking.systems rs on rs.id=mi.system_id
   where mi.id=p_import_id
 )
 select jsonb_build_object(
   'id',x.id,'system_id',x.system_id,'system_code',x.system_code,'edition_year',x.edition_year,
   'original_filename',x.original_filename,'mime_type',x.mime_type,'byte_size',x.byte_size,'status',x.status,
   'evidence_artifact_id',x.evidence_artifact_id,'storage_path',x.storage_path,'source_url',x.source_url,
   'methodology_url',x.methodology_url,'content_hash',x.content_hash,'validation_summary',x.validation_summary,
   'parse_summary',x.parse_summary,
   'source_id',(
     select s.id from pipeline.sources s
     where upper(coalesce(s.metadata->>'source_system',''))=x.source_system
     order by
       case when nullif(s.metadata->>'edition_year','')::integer=x.edition_year then 0
            when coalesce((s.metadata->>'multi_year_family')::boolean,false) then 1
            else 2 end,
       s.updated_at desc
     limit 1
   )
 )
 from x
$$;

revoke all on function public.svc_ranking_import_control_context(uuid) from public, anon, authenticated;
grant execute on function public.svc_ranking_import_control_context(uuid) to service_role;
