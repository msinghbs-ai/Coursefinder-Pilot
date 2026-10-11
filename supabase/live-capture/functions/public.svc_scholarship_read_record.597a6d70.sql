CREATE OR REPLACE FUNCTION public.svc_scholarship_read_record(p_scholarship_id uuid, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_ev uuid; v_src uuid; v_pid uuid; v_url text; r jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, p.url into v_pid, v_url from scholarship.scholarships s join pipeline.scholarship_pages p on p.scholarship_id=s.id where s.id=p_scholarship_id;
  if p_storage_path is not null and p_read_status='read' then
    v_src:=security.coverage_sweep_source(v_pid);
    -- unchanged page: reuse its evidence; changed page: next capture version, superseding the previous one
    select e.id into v_ev from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id and e.content_hash=p_sha256 order by e.capture_version desc limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key,supersedes_evidence_id)
      select p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
             jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'),
             coalesce((select max(e.capture_version) from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id),0)+1,
             'scholarship:'||p_scholarship_id,
             (select e.id from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id order by e.capture_version desc limit 1)
      returning id into v_ev;
    end if;
  end if;
  update pipeline.scholarship_pages set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, evidence_id=case when p_read_status='read' then coalesce(v_ev,evidence_id) else evidence_id end,
         facts=case when p_read_status='read' then coalesce(p_facts,facts) else facts end,
         name_check=case when p_facts ? 'name_check' then p_facts->'name_check' else name_check end,
         next_read_at=case when p_read_status='read' then now()+interval '90 days' when p_read_status in ('robots_disallowed','blocked','name_mismatch') then now()+interval '30 days' else now()+interval '6 hours' end,
         attempts=case when p_read_status='read' then 0 else attempts end
   where scholarship_id=p_scholarship_id;
  -- an admitted page that no longer meets the admission rules is withdrawn, not applied
  if p_read_status='read' and p_facts ? 'admission' and coalesce((p_facts->'admission'->>'admit')::boolean,true) is false
     and exists (select 1 from pipeline.scholarship_pages where scholarship_id=p_scholarship_id and url_source='admitted') then
    r:=security.scholarship_admission_withdraw_v1(p_scholarship_id, jsonb_build_object('reasons',p_facts->'admission'->'reasons','extractor',p_facts->>'extractor'));
  elsif p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;
  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried
  if p_read_status='name_mismatch' then
    update pipeline.scholarship_page_candidates c set match_basis='rejected_name_mismatch', matched_scholarship_id=null
      from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id and sp.url_source='discovered' and c.id=sp.candidate_id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
    select p_scholarship_id,'provider_page_rejected',jsonb_build_object('url',sp.url,'url_source',sp.url_source),p_facts->'name_check' from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id;
  end if;
  return coalesce(r,jsonb_build_object('applied',false));
end $function$
