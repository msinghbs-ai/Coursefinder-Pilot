begin;

create or replace function public.svc_ranking_import_control_context(p_import_id uuid)
returns jsonb
language sql
security definer
set search_path='pg_catalog','ranking'
as $$
 select jsonb_build_object(
   'id',mi.id,
   'system_id',mi.system_id,
   'system_code',rs.code,
   'edition_year',mi.edition_year,
   'original_filename',mi.original_filename,
   'status',mi.status,
   'evidence_artifact_id',mi.evidence_artifact_id,
   'source_url',mi.source_url,
   'methodology_url',mi.methodology_url,
   'content_hash',mi.content_hash
 )
 from ranking.manual_imports mi
 join ranking.systems rs on rs.id=mi.system_id
 where mi.id=p_import_id
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
