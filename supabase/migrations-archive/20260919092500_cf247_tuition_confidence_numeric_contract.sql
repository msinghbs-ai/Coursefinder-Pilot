-- CF-CHG-20260915-247
-- Forward-only correction: make the already-required confidence field explicitly numeric [0,1].
-- This does not convert qualitative confidence, relax review_confidence_min, or alter Evidence/candidate authority.
begin;
update pipeline.layer3_model_profiles
set structured_output_schema = jsonb_set(
      structured_output_schema,
      '{properties}',
      coalesce(structured_output_schema->'properties','{}'::jsonb)
        || jsonb_build_object('confidence',jsonb_build_object('type','number','minimum',0,'maximum',1)),
      true
    ),
    prompt_system = prompt_system || E'\nThe confidence field MUST be a JSON number from 0 through 1 inclusive. Do not return qualitative confidence labels such as low, medium, or high.',
    prompt_profile_version = 'cf247-provider-current-tuition-validation-v2-numeric-confidence',
    updated_at = now()
where code='openrouter-provider-tuition-validation-v1'
  and change_control_ref in ('CF-CHG-20260915-245','CF-CHG-20260915-247');
commit;
