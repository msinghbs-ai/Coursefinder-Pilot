-- CF-247 scholarship sweep: re-reads failed on the evidence uniqueness rule (evidence_group_key + capture_version),
-- so the first batch was never re-read. An unchanged page now reuses its evidence; a changed page becomes the next
-- capture version and supersedes the previous one. Leases cleared and all pages re-read.
do $patch$
declare v text; o text; n text;
begin
  v:=pg_get_functiondef('public.svc_scholarship_read_record(uuid,text,int,text,text,text,text,jsonb)'::regprocedure);
  o:=$o$    insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
    values (p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
            jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'), 1, 'scholarship:'||p_scholarship_id)
    returning id into v_ev;$o$;
  n:=$n$    -- unchanged page: reuse its evidence; changed page: next capture version, superseding the previous one
    select e.id into v_ev from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id and e.content_hash=p_sha256 order by e.capture_version desc limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key,supersedes_evidence_id)
      select p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
             jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'),
             coalesce((select max(e.capture_version) from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id),0)+1,
             'scholarship:'||p_scholarship_id,
             (select e.id from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id order by e.capture_version desc limit 1)
      returning id into v_ev;
    end if;$n$;
  if position(o in v)=0 then raise exception 'evidence anchor not found'; end if;
  execute replace(v,o,n);
end $patch$;
update pipeline.scholarship_pages set leased_until=null, attempts=0, next_read_at=now();
