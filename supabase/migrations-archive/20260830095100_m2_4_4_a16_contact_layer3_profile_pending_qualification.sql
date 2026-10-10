
insert into pipeline.layer3_model_profiles(
  code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,
  prompt_profile_version,prompt_system,structured_output_schema,deterministic_validators,
  max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,
  fallback_profile_id,cost_ceiling_usd,enabled,paused,last_validation_result,quality_benchmark,
  change_control_ref,uat_ref
)
select
  'openrouter-international-contact-v1',
  p.aggregator_provider,p.base_url,p.model_identifier,p.secret_env_key,
  array['international_contact']::text[],
  'm2.4.4-a16-contact-v1',
  'Interpret only supplied first-party university Layer 2 Evidence for international-student/admissions contact channels. Return JSON only. candidate_value must be an object with disposition, international_students_url, contact_team_url, general_email, contacts. A contact, email, phone, territory or URL may appear only when explicitly supported by the supplied Evidence. Do not infer or manufacture missing contact details. If the Evidence has no qualifying contact, return an explicit not_publicly_published or not_found_in_qualified_evidence disposition.',
  jsonb_build_object(
    'type','object',
    'required',jsonb_build_array('candidate_value','confidence','rationale','evidence_quotes'),
    'properties',jsonb_build_object(
      'candidate_value',jsonb_build_object('type',jsonb_build_array('object','null')),
      'confidence',jsonb_build_object('type','number','minimum',0,'maximum',1),
      'rationale',jsonb_build_object('type','string'),
      'evidence_quotes',jsonb_build_object('type','array','items',jsonb_build_object('type','string'))
    ),
    'additionalProperties',false
  ),
  jsonb_build_object(
    'max_quotes',4,'confidence_min',0,'confidence_max',1,'max_quote_chars',600,
    'max_rationale_chars',1600,'candidate_required',true,'max_contacts',12,
    'contact_values_must_be_evidence_bound',true,'no_manufactured_contacts',true,
    'review_confidence_min',0.8
  ),
  p.max_input_tokens,p.max_output_tokens,
  least(p.requests_per_minute,8),least(p.requests_per_day,120),
  p.retry_ceiling,p.timeout_ms,null,p.cost_ceiling_usd,
  false,false,
  jsonb_build_object('status','pending_contact_specific_qualification','qualified',false),
  jsonb_build_object(
    'pass',false,
    'status','pending_contact_specific_qualification',
    'summary','A16 contact task profile must pass dedicated first-party contact/no-contact/anti-hallucination benchmark before execution.'
  ),
  'CF-CHG-20260830-048',
  'M2.4.4-A16-contact-qualification'
from pipeline.layer3_model_profiles p
where p.code='openrouter-free-router-v1'
on conflict(code) do update
set allowed_task_classes=excluded.allowed_task_classes,
    prompt_profile_version=excluded.prompt_profile_version,
    prompt_system=excluded.prompt_system,
    structured_output_schema=excluded.structured_output_schema,
    deterministic_validators=excluded.deterministic_validators,
    enabled=false,
    paused=false,
    last_validation_result=excluded.last_validation_result,
    quality_benchmark=excluded.quality_benchmark,
    change_control_ref=excluded.change_control_ref,
    uat_ref=excluded.uat_ref,
    updated_at=now();

comment on function public.layer3_reserve_interpretation_service(uuid,uuid,text,uuid,text,uuid,jsonb,text) is
'M2.4.3 governed reservation. A16 contact profiles remain non-executable until their task-specific quality_benchmark.pass=true; no unrelated benchmark may qualify international_contact.';
