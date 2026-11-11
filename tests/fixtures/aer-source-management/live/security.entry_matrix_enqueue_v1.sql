CREATE OR REPLACE FUNCTION security.entry_matrix_enqueue_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  insert into pipeline.entry_matrix_runs(provider_id, source_id, content_hash)
  select s.provider_id, s.id, coalesce(s.content_hash, s.evidence_id::text)
    from pipeline.entry_matrix_sources s
   where s.status = 'read' and s.evidence_id is not null and security.entry_matrix_enabled_v1(s.provider_id)
  on conflict (source_id, content_hash) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$
