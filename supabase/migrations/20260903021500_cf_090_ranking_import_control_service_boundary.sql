begin;

create or replace function public.svc_ranking_import_control_context(p_import_id uuid)
returns jsonb
language sql
security definer
set search_path='pg_catalog','ranking','pipeline'
as $$
 with x as (
   select mi.*,rs.code system_code,
          case when rs.code='the_wur' then 'THE' else 'QS' end source_system
   from ranking.manual_imports mi
   join ranking.systems rs on rs.id=mi.system_id
   where mi.id=p_import_id
 )
 select jsonb_build_object(
   'id',x.id,
   'system_id',x.system_id,
   'system_code',x.system_code,
   'edition_year',x.edition_year,
   'original_filename',x.original_filename,
   'status',x.status,
   'evidence_artifact_id',x.evidence_artifact_id,
   'source_url',x.source_url,
   'methodology_url',x.methodology_url,
   'content_hash',x.content_hash,
   'source_id',(
     select s.id
     from pipeline.sources s
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

revoke all on function public.svc_ranking_import_control_context(uuid) from public,anon,authenticated;
grant execute on function public.svc_ranking_import_control_context(uuid) to service_role;

create or replace function public.svc_ranking_import_validation_update(
 p_import_id uuid,
 p_status text,
 p_validation_summary jsonb,
 p_parse_summary jsonb
)
returns boolean
language plpgsql
security definer
set search_path='pg_catalog','ranking'
as $$
begin
 if current_user not in ('service_role','postgres') then
   raise exception 'service role required' using errcode='42501';
 end if;
 if p_status not in ('uploaded','validated','parsed','reconciled','needs_review','applied','rejected') then
   raise exception 'invalid ranking import status' using errcode='22023';
 end if;
 update ranking.manual_imports
 set status=p_status,
     validation_summary=coalesce(p_validation_summary,'{}'::jsonb),
     parse_summary=coalesce(p_parse_summary,'{}'::jsonb),
     updated_at=now()
 where id=p_import_id;
 return found;
end
$$;

revoke all on function public.svc_ranking_import_validation_update(uuid,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.svc_ranking_import_validation_update(uuid,text,jsonb,jsonb) to service_role;

commit;
