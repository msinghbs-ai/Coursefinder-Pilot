-- CF-CHG-20260823-029
-- Preserve the M1 Evidence response contract while avoiding repeated expensive metric scans.
create or replace function security.admin_evidence_detail(p_evidence_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, security, pipeline, workflow, ref, auth, storage
as $$
declare
  v_rank integer:=0;
  v_result jsonb;
  v_observation_count bigint:=0;
  v_verification_at timestamptz;
  v_has_source_null boolean:=false;
  v_operational_status text;
  v_unresolved_conflict boolean:=false;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;

  v_observation_count:=security.admin_evidence_observation_count(p_evidence_id);
  v_verification_at:=security.admin_evidence_verification_at(p_evidence_id);
  v_has_source_null:=security.admin_evidence_has_source_null(p_evidence_id);
  v_operational_status:=security.admin_evidence_operational_status(p_evidence_id);
  v_unresolved_conflict:=security.admin_evidence_has_unresolved_conflict(p_evidence_id);

  select jsonb_build_object(
    'artifact',jsonb_build_object(
      'id',e.id,'evidence_type',e.evidence_type,
      'layer',security.admin_evidence_layer(e.storage_path,e.evidence_type,e.metadata,s.source_type),
      'source_url',e.source_url,'captured_at',e.captured_at,
      'snapshot_version',coalesce(e.metadata->>'snapshot_version',e.metadata->>'source_version',e.metadata->>'worker_version',e.metadata->>'version'),
      'content_hash',e.content_hash,'mime_type',e.mime_type,'valid_from',e.valid_from,'valid_to',e.valid_to,
      'verification_at',v_verification_at,
      'extraction_state',case when exists(select 1 from pipeline.claims cl where cl.evidence_id=e.id and lower(coalesce(cl.status,''))='rejected') and v_observation_count=0 then 'rejected' when v_observation_count>0 then 'extracted' else 'missing_extraction' end,
      'observation_count',v_observation_count,'has_source_null',v_has_source_null,'status',v_operational_status,
      'freshness_state',case when lower(coalesce(e.metadata->>'freshness_state',''))='stale' or lower(coalesce(e.metadata->>'stale','false'))='true' then 'stale' when e.valid_to is not null and e.valid_to<now() then 'expired' when e.valid_to is not null then 'current' else 'no_policy' end,
      'metadata',security.admin_redact_json(e.metadata)
    ),
    'source',case when s.id is null then null else jsonb_build_object('id',s.id,'label',s.label,'source_type',s.source_type,'authority_url',s.url,'status',s.status,'trust_rank',s.trust_rank,'country_code',co.iso_alpha2,'last_checked_at',s.last_checked_at,'last_success_at',s.last_success_at,'last_failure_at',s.last_failure_at,'metadata',security.admin_redact_json(s.metadata)) end,
    'job',case when j.id is null then null else jsonb_build_object('id',j.id,'job_type',j.job_type,'domain',j.domain,'status',j.status,'started_at',j.started_at,'completed_at',j.completed_at,'attempt_count',j.attempt_count) end,
    'storage',jsonb_build_object('available',o.id is not null,'size_bytes',case when jsonb_typeof(o.metadata->'size')='number' then o.metadata->'size' else null end,'content_type',coalesce(o.metadata->>'mimetype',e.mime_type),'object_created_at',o.created_at,'object_updated_at',o.updated_at,'preview_allowed',(o.id is not null and lower(coalesce(e.mime_type,'')) in ('application/pdf','image/png','image/jpeg','text/plain','application/json')),'download_allowed',(o.id is not null)),
    'supersession',jsonb_build_object('predecessor',case when prev.id is null then null else jsonb_build_object('id',prev.id,'captured_at',prev.captured_at,'content_hash',prev.content_hash) end,'successors',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'captured_at',n.captured_at,'content_hash',n.content_hash) order by n.captured_at) from pipeline.evidence_artifacts n where n.supersedes_evidence_id=e.id),'[]'::jsonb)),
    'claims',coalesce((select jsonb_agg(jsonb_build_object('id',cl.id,'entity_id',cl.entity_id,'field_code',cl.field_code,'value',security.admin_redact_json(cl.value_json),'layer',cl.layer,'confidence',cl.confidence,'status',cl.status,'created_at',cl.created_at) order by cl.created_at desc) from pipeline.claims cl where cl.evidence_id=e.id),'[]'::jsonb),
    'reviews',coalesce((select jsonb_agg(jsonb_build_object('id',rq.id,'entity_id',rq.entity_id,'domain',rq.domain,'field_code',rq.field_code,'priority',rq.priority,'status',rq.status,'created_at',rq.created_at,'updated_at',rq.updated_at,'closed_at',rq.closed_at) order by rq.created_at desc) from workflow.review_queue rq join pipeline.claims cl on cl.id=rq.candidate_claim_id where cl.evidence_id=e.id),'[]'::jsonb),
    'review_actions',coalesce((select jsonb_agg(jsonb_build_object('id',ra.id,'review_id',ra.review_id,'action',ra.action,'reason',ra.reason,'created_at',ra.created_at) order by ra.created_at desc) from workflow.review_actions ra where ra.evidence_id=e.id),'[]'::jsonb),
    'change_control_ids',case when jsonb_typeof(e.metadata->'change_control_ids')='array' then e.metadata->'change_control_ids' when e.metadata ? 'change_control_id' then jsonb_build_array(e.metadata->>'change_control_id') else '[]'::jsonb end,
    'unresolved_conflict',v_unresolved_conflict
  ) into v_result
  from pipeline.evidence_artifacts e
  left join pipeline.sources s on s.id=e.source_id
  left join ref.countries co on co.id=s.country_id
  left join pipeline.jobs j on j.id=e.job_id
  left join pipeline.evidence_artifacts prev on prev.id=e.supersedes_evidence_id
  left join storage.objects o on o.bucket_id='evidence' and o.name=e.storage_path
  where e.id=p_evidence_id;
  return coalesce(v_result,'{}'::jsonb);
end $$;
comment on function security.admin_evidence_detail(uuid) is 'M2.1 deployed UAT hardening: computes expensive Evidence metrics once per detail read while preserving the M1 Evidence response contract.';
