CREATE OR REPLACE FUNCTION security.layer4_review_context_impl(p_review_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'auth'
AS $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'review',to_jsonb(r),
    'evidence',jsonb_build_object(
      'id',e.id,'source_id',e.source_id,'source_url',e.source_url,'storage_path',e.storage_path,
      'content_hash',e.content_hash,'mime_type',e.mime_type,'captured_at',e.captured_at,
      'valid_from',e.valid_from,'valid_to',e.valid_to,'review_state',e.review_state,
      'retention_class',e.retention_class,'metadata',e.metadata
    ),
    'layer3',case when i.id is null then null else jsonb_build_object(
      'id',i.id,'profile_id',i.profile_id,'profile_code',p.code,'aggregator_provider',p.aggregator_provider,
      'configured_model',p.model_identifier,'response_model',i.aggregator_response_model,
      'prompt_profile_version',i.prompt_profile_version,'eligibility_reason',i.eligibility_reason,
      'revalidation_ref',i.revalidation_ref,'status',i.status,'candidate_value',i.candidate_value,
      'confidence',i.confidence,'rationale',i.rationale,'evidence_quotes',i.evidence_quotes,
      'validator_result',i.validator_result,'input_tokens',i.input_tokens,'output_tokens',i.output_tokens,
      'estimated_cost_usd',i.estimated_cost_usd,'interpretation_expires_at',i.interpretation_expires_at
    ) end,
    'history',coalesce((
      select jsonb_agg(to_jsonb(d) order by d.created_at)
      from pipeline.layer4_decisions d where d.review_item_id=r.id
    ),'[]'::jsonb)
  ) into v
  from pipeline.layer4_review_items r
  left join pipeline.evidence_artifacts e on e.id=r.evidence_id
  left join pipeline.layer3_interpretations i on i.id=r.layer3_interpretation_id
  left join pipeline.layer3_model_profiles p on p.id=i.profile_id
  where r.id=p_review_item_id;
  if v is null then raise exception 'review item not found'; end if;
  return v;
end $function$
