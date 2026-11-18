-- CF-247 AER v1.1 tooling (Platform Admin 27 Oct 2026 05:46: D5 and D4 tests "must use the stored source pages"). Record: admin
-- docs/platform/aer-v1.1-build-log.md (27 Oct 05:50 decision). Read-only.
-- public.svc_entry_matrix_inspect_paths(source ids): the stored copy (evidence storage path, mime type, content hash) of at most 12
-- entry-matrix sources, for the worker's read-only mode entry_inspect. Service role only. Reads; writes nothing.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched.

create or replace function public.svc_entry_matrix_inspect_paths(p_source_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'url', s.url, 'storage_path', e.storage_path, 'mime', e.mime_type, 'content_hash', s.content_hash) order by s.url), '[]'::jsonb)
            from pipeline.entry_matrix_sources s left join pipeline.evidence_artifacts e on e.id = s.evidence_id
           where s.id = any(p_source_ids[1:12]));  -- fixed: diagnostic batch cap
end $$;
revoke all on function public.svc_entry_matrix_inspect_paths(uuid[]) from public, anon, authenticated;
grant execute on function public.svc_entry_matrix_inspect_paths(uuid[]) to service_role;
comment on function public.svc_entry_matrix_inspect_paths(uuid[]) is 'CF-247 AER v1.1 tooling: stored-copy paths of up to 12 entry-matrix sources for the read-only worker mode entry_inspect (service role).';
