CREATE OR REPLACE FUNCTION public.svc_coverage_read_record(p_course_id uuid, p_read_status text, p_http_status integer, p_fetched_via text, p_identity_basis text, p_storage_path text, p_sha256 text, p_candidates jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security'
AS $function$
declare v_row pipeline.coverage_course_pages%rowtype; v_ev uuid; v_src uuid;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select * into v_row from pipeline.coverage_course_pages where course_id=p_course_id;
  if v_row.course_id is null then raise exception 'course page not bound'; end if;
  -- night run: a page read and confirmed before keeps its reading when a later read fails for a passing reason
  if p_read_status in ('fetch_failed', 'blocked', 'needs_render', 'too_thin', 'not_html') and v_row.read_status = 'read' and v_row.identity_basis is not null and v_row.evidence_id is not null then
    update pipeline.coverage_course_pages set http_status = p_http_status, leased_until = null, next_read_at = case when p_read_status = 'needs_render' then date_trunc('month', now()) + interval '1 month 1 hour' else now() + interval '7 days' end where course_id = p_course_id;
    return jsonb_build_object('evidence_id', null, 'kept_previous_read', true, 'failed_as', p_read_status);
  end if;
  if p_storage_path is not null and p_sha256 ~ '^[0-9a-f]{64}$' then
    v_src:=security.coverage_sweep_source(v_row.provider_id);
    select id into v_ev from pipeline.evidence_artifacts where source_id=v_src and content_hash=p_sha256 and source_url=v_row.url limit 1;
    if v_ev is null then
      v_ev:=public.svc_coursefacts_register_evidence(v_src, v_row.url, p_storage_path, p_sha256, 'text/html',
        jsonb_build_object('layer',2,'kind','provider_course_page','worker','coverage-sweep','course_id',p_course_id,'identity_basis',p_identity_basis,'fetched_via',p_fetched_via,'gzip',true));
    end if;
  end if;
  update pipeline.coverage_course_pages set read_status=p_read_status, read_at=now(), http_status=p_http_status, fetched_via=p_fetched_via,
         identity_basis=p_identity_basis, evidence_id=coalesce(v_ev,evidence_id), candidates=p_candidates, leased_until=null,
         next_read_at=case when p_read_status in ('read','identity_mismatch') then now()+make_interval(days => coalesce((select a.read_cycle_days from pipeline.uni_adapters a where a.provider_id=v_row.provider_id), 90)) when p_read_status='needs_render' then date_trunc('month',now())+interval '1 month 1 hour' else now()+interval '6 hours' end,
         read_attempts=case when p_read_status='needs_render' then greatest(read_attempts-1,0) else read_attempts end,
         status=case when p_read_status='identity_mismatch' then 'mismatch' when status='ambiguous' and p_identity_basis='cricos_code' then 'bound' else status end,
         basis=case when status='ambiguous' and p_identity_basis='cricos_code' then 'cricos_code_on_page' else basis end
   where course_id=p_course_id;
  return jsonb_build_object('evidence_id',v_ev);
end $function$
