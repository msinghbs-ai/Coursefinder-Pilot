CREATE OR REPLACE FUNCTION security.apply_provider_fee_profiles_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue'
AS $function$
declare n int; b int;
begin
  with m as (
    select w.id, pf.rule_code, pf.resolved_basis
    from pipeline.layer3_work_items w
    join catalogue.courses c on c.id=w.entity_id
    join pipeline.provider_fee_profiles pf on pf.provider_id=c.provider_id and pf.active and pf.review_by>=current_date
    join pipeline.evidence_artifacts e on e.id=w.evidence_id
    join pipeline.layer3_interpretations i on i.id=w.interpretation_id
    where w.task_class='provider_current_tuition_validation'
      and w.status in ('pending','layer4_required')
      and w.candidate_context->'provider_current_tuition'->>'basis' in ('annual_or_indicative_requires_validation', pf.resolved_basis)
      and coalesce(w.candidate_context->'provider_current_tuition'->>'audience','')=pf.audience
      and e.source_url ~* pf.page_url_pattern
      and coalesce(i.evidence_quotes::text,'') !~* pf.exclusion_pattern
      and not (w.candidate_context ? 'provider_fee_rule'))
  update pipeline.layer3_work_items w
  set candidate_context = jsonb_set(jsonb_set(w.candidate_context,'{provider_current_tuition,basis}',to_jsonb(m.resolved_basis)),
                                    '{provider_current_tuition,basis_source}',to_jsonb('provider_fee_rule:'||m.rule_code))
                          || jsonb_build_object('provider_fee_rule',m.rule_code,'provider_fee_rule_applied_at',now()),
      updated_at=now()
  from m where w.id=m.id;
  get diagnostics n = row_count;
  update pipeline.layer3_work_items w
  set candidate_context = jsonb_set(w.candidate_context,'{provider_current_tuition,basis_source}',to_jsonb('provider_fee_rule:'||(w.candidate_context->>'provider_fee_rule'))),
      updated_at=now()
  where w.candidate_context ? 'provider_fee_rule'
    and not (w.candidate_context->'provider_current_tuition' ? 'basis_source')
    and w.status in ('pending','layer4_required');
  get diagnostics b = row_count;
  return jsonb_build_object('applied',n,'stamped',b);
end $function$
