CREATE OR REPLACE FUNCTION public.scholarship_detail_extraction_context(p_job_id uuid, p_evidence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline'
AS $function$
declare
  v_job record;
  v_e record;
  v_candidate uuid;
  v_classification text;
  v_url text;
  v_eligible boolean:=false;
  v_normalized uuid;
begin
  if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
  select * into v_job from pipeline.jobs where id=p_job_id and domain='scholarship' and job_type='scholarship_scope_acquisition';
  if not found then return null; end if;
  select id,evidence_type,source_url,metadata into v_e from pipeline.evidence_artifacts where id=p_evidence_id;
  if not found then return null; end if;
  begin v_candidate:=nullif(v_job.payload->>'candidate_id','')::uuid; exception when others then v_candidate:=null; end;
  if v_candidate is not null then
    select classification,coalesce(nullif(detail_target_url,''),nullif(scholarship_url,'')) into v_classification,v_url
    from pipeline.layer2_scholarship_discovery_candidates where id=v_candidate;
  end if;
  v_eligible:=coalesce(v_classification,'')='detail_ready'
    and coalesce(v_url,v_e.source_url,'') !~* '/search\?'
    and coalesce(v_url,v_e.source_url,'') !~* '[?&](query|collection|form|num_ranks|f\.)=';
  select id into v_normalized
  from pipeline.evidence_artifacts
  where evidence_type='layer2_extraction_input'
    and metadata->>'source_evidence_id'=p_evidence_id::text
  order by created_at desc limit 1;
  return jsonb_build_object(
    'job_id',v_job.id,'candidate_id',v_candidate,'classification',v_classification,'eligible',v_eligible,
    'evidence_id',v_e.id,'evidence_type',v_e.evidence_type,'source_url',v_e.source_url,
    'attempt_id',v_e.metadata->>'attempt_id','existing_normalized_evidence_id',v_normalized,
    'reason',case when v_eligible then 'detail_ready' else 'candidate_not_current_detail_ready_or_filter_page' end
  );
end
$function$
