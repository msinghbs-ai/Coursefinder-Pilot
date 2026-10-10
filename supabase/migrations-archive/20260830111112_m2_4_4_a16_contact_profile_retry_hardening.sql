update pipeline.layer3_model_profiles
set retry_ceiling=2,
    max_output_tokens=900,
    last_validation_result=coalesce(last_validation_result,'{}'::jsonb)||jsonb_build_object(
      'state','contact_benchmark_retry_hardening',
      'validated',false,
      'reason','Bounded third attempt plus lower output ceiling after preserved malformed-output benchmark failures',
      'change_control_ref','CF-CHG-20260830-048'
    ),
    updated_at=now()
where code='openrouter-international-contact-v1';

comment on table pipeline.layer3_model_profiles is
'M2.4 Layer 3 model profiles. A16 international-contact profile uses retry_ceiling=2 only after immutable benchmark evidence showed malformed structured output; profile remains disabled until dedicated contact benchmark PASS.';