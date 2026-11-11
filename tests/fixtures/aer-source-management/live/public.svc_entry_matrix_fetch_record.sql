CREATE OR REPLACE FUNCTION public.svc_entry_matrix_fetch_record(p_source_id uuid, p_status text, p_via text, p_http integer, p_storage_path text, p_sha256 text, p_mime text, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s pipeline.entry_matrix_sources%rowtype; v_src uuid; v_ev uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into s from pipeline.entry_matrix_sources where id = p_source_id for update;
  if s.id is null then raise exception 'source not found'; end if;
  if p_status = 'read' and p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src := security.coverage_sweep_source(s.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id = v_src and content_hash = p_sha256 and source_url = s.url limit 1;
    if v_ev is null then
      v_ev := public.svc_coursefacts_register_evidence(v_src, s.url, p_storage_path, p_sha256, coalesce(p_mime, 'text/html'),
                jsonb_build_object('layer', 2, 'kind', 'provider_entry_requirements', 'worker', 'coverage-sweep', 'entry_matrix_source_id', s.id, 'read_via', p_via));
    end if;
    update pipeline.entry_matrix_sources set status = 'read', read_via = p_via, http_status = p_http, evidence_id = v_ev, content_hash = p_sha256,
           read_at = now(), error = null, updated_at = now() where id = s.id;
    return jsonb_build_object('status', 'read', 'evidence_id', v_ev);
  end if;
  -- 29 Oct 2026: a Firecrawl budget refusal is not the page failing; it waits for the next read without using one of its tries
  update pipeline.entry_matrix_sources set
         attempts = case when p_error in ('credits_refused', 'credits_reserve', 'no_firecrawl_key') then greatest(attempts - 1, 0) else attempts end,
         status = case when p_status = 'robots_disallowed' then 'robots_disallowed'
                       when p_error in ('credits_refused', 'credits_reserve', 'no_firecrawl_key') then 'found'
                       when attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) then 'failed' else 'found' end,
         http_status = p_http, error = left(coalesce(p_error, p_status), 400), updated_at = now()
   where id = s.id;
  return jsonb_build_object('status', p_status);
end $function$
