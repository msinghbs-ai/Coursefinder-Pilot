-- CF-CHG-20260915-245
-- Dedicated provider-current-tuition validation profile. It is deliberately paused and benchmark-failed by default;
-- no Layer 3 execution is authorised until fee-specific provider/control benchmarks pass.
begin;
insert into pipeline.layer3_model_profiles(
  code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,
  prompt_profile_version,prompt_system,structured_output_schema,deterministic_validators,
  max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,
  fallback_profile_id,cost_ceiling_usd,enabled,paused,last_validation_result,quality_benchmark,
  change_control_ref,uat_ref,created_at,updated_at
)
select
  'openrouter-provider-tuition-validation-v1',p.aggregator_provider,p.base_url,p.model_identifier,p.secret_env_key,
  array['provider_current_tuition_validation']::text[],'cf245-provider-current-tuition-validation-v1',
  'Validate only the supplied first-party Evidence for provider-current international tuition. Return JSON only. Do not infer or annualise a fee unless the Evidence explicitly supports the amount, currency and basis. Distinguish annual/indicative tuition from loan caps, deposits, regulatory total-course fees, domestic fees and unrelated charges. If ambiguous, return candidate_value null and explain why. Never alter regulatory identity.',
  jsonb_build_object('type','object','required',jsonb_build_array('candidate_value','confidence','rationale','evidence_quotes'),'candidate_value',jsonb_build_object('type',jsonb_build_array('object','null'),'properties',jsonb_build_object('amount',jsonb_build_object('type','number'),'currency',jsonb_build_object('type','string'),'basis',jsonb_build_object('type','string'),'fee_year',jsonb_build_object('type',jsonb_build_array('integer','null')),'international_student',jsonb_build_object('type','boolean')))),
  jsonb_build_object('confidence_min',0,'confidence_max',1,'review_confidence_min',0.9,'amount_min',1,'amount_max',250000,'allowed_currencies',jsonb_build_array('AUD','NZD'),'allowed_basis',jsonb_build_array('annual','indicative_annual','per_year_explicit'),'international_student_required',true,'evidence_quote_required',true,'reject_terms',jsonb_build_array('loan cap','student contribution','commonwealth supported','deposit only','application fee')),
  least(p.max_input_tokens,12000),least(p.max_output_tokens,900),least(p.requests_per_minute,10),least(p.requests_per_day,25),1,least(p.timeout_ms,30000),null,0,true,true,
  jsonb_build_object('valid',true,'state','configured_but_paused_pending_fee_specific_benchmark','validated_at',now()),
  jsonb_build_object('pass',false,'state','benchmark_required','change_control_ref','CF-CHG-20260915-245'),
  'CF-CHG-20260915-245','CF-245-Gate-L3-fee-benchmark',now(),now()
from pipeline.layer3_model_profiles p where p.code='openrouter-free-router-v1'
on conflict(code) do update set
  allowed_task_classes=excluded.allowed_task_classes,prompt_profile_version=excluded.prompt_profile_version,prompt_system=excluded.prompt_system,
  structured_output_schema=excluded.structured_output_schema,deterministic_validators=excluded.deterministic_validators,
  requests_per_minute=excluded.requests_per_minute,requests_per_day=excluded.requests_per_day,retry_ceiling=excluded.retry_ceiling,
  timeout_ms=excluded.timeout_ms,cost_ceiling_usd=excluded.cost_ceiling_usd,enabled=true,paused=true,
  last_validation_result=excluded.last_validation_result,quality_benchmark=excluded.quality_benchmark,
  change_control_ref=excluded.change_control_ref,uat_ref=excluded.uat_ref,updated_at=now();
commit;
