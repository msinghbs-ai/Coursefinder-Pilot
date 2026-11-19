CREATE OR REPLACE FUNCTION public.svc_ranking_import_recovery_context(p_import_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
declare
  v jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service role required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'id',mi.id,
    'system_code',s.code,
    'edition_year',mi.edition_year,
    'status',mi.status,
    'content_hash',mi.content_hash,
    'evidence_artifact_id',mi.evidence_artifact_id,
    'storage_path',mi.storage_path,
    'original_filename',mi.original_filename
  ) into v
  from ranking.manual_imports mi
  join ranking.systems s on s.id=mi.system_id
  where mi.id=p_import_id;
  if v is null then raise exception 'ranking import not found' using errcode='P0002'; end if;
  return v;
end
$function$
