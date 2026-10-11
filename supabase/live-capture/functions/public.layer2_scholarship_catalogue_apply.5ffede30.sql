CREATE OR REPLACE FUNCTION public.layer2_scholarship_catalogue_apply(p_evidence_id uuid, p_links jsonb DEFAULT '[]'::jsonb, p_status text DEFAULT 'captured'::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue'
AS $function$
declare
  v_ctx jsonb;
  v_link jsonb;
  v_inserted integer:=0;
  v_total integer:=0;
  v_duplicates integer:=0;
  v_parent_candidate uuid;
  v_run uuid;
begin
  v_ctx:=public.layer2_scholarship_extraction_context(p_evidence_id);
  if v_ctx is null or v_ctx='null'::jsonb then raise exception 'evidence_not_found' using errcode='P0002'; end if;
  if v_ctx->>'evidence_type'<>'layer2_extraction_input' then raise exception 'layer2_extraction_input_required' using errcode='23514'; end if;
  if p_status not in('captured','complete','partial','needs_review','failed') then raise exception 'invalid_catalogue_status' using errcode='23514'; end if;

  for v_link in select value from jsonb_array_elements(coalesce(p_links,'[]'::jsonb))
  loop
    v_total:=v_total+1;
    insert into pipeline.layer2_scholarship_discovery_candidates(
      source_id,evidence_id,source_profile_version_id,scholarship_url,observed_title,status
    ) values(
      (v_ctx->>'source_id')::uuid,
      p_evidence_id,
      nullif(v_ctx->>'source_profile_version_id','')::uuid,
      v_link->>'url',
      nullif(v_link->>'title',''),
      'discovered'
    )
    on conflict(evidence_id,scholarship_url) do nothing;
    if found then v_inserted:=v_inserted+1; else v_duplicates:=v_duplicates+1; end if;
  end loop;

  insert into pipeline.scholarship_catalogue_runs(
    source_id,evidence_id,source_profile_version_id,provider_id,content_hash,
    discovered_count,unique_candidate_count,duplicate_count,status,metadata
  ) values(
    (v_ctx->>'source_id')::uuid,
    p_evidence_id,
    nullif(v_ctx->>'source_profile_version_id','')::uuid,
    nullif(v_ctx->>'provider_id','')::uuid,
    v_ctx->>'content_hash',
    v_total,v_inserted,v_duplicates,p_status,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'source_url',v_ctx->>'source_url',
      'source_label',v_ctx->>'source_label',
      'change_control_ref','CF-CHG-20260903-083'
    )
  )
  on conflict(source_id,evidence_id) do update set
    discovered_count=excluded.discovered_count,
    unique_candidate_count=excluded.unique_candidate_count,
    duplicate_count=excluded.duplicate_count,
    status=excluded.status,
    metadata=excluded.metadata,
    observed_at=now()
  returning id into v_run;

  begin
    v_parent_candidate:=nullif(v_ctx->'source_metadata'->>'candidate_id','')::uuid;
  exception when others then v_parent_candidate:=null; end;

  if v_parent_candidate is not null then
    update pipeline.layer2_scholarship_discovery_candidates
    set status='acquired'
    where id=v_parent_candidate and status='discovered';
  end if;

  return jsonb_build_object(
    'run_id',v_run,
    'provider_id',v_ctx->>'provider_id',
    'source_id',v_ctx->>'source_id',
    'discovered_count',v_total,
    'inserted_count',v_inserted,
    'duplicate_count',v_duplicates,
    'status',p_status
  );
end $function$
