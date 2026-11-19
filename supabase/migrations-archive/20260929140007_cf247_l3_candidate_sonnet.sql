-- CF-CHG-20260915-247 Layer 3 model routing: a sixth, Sonnet-class candidate for intake and English only.
-- The first five candidates (gpt-4.1-mini, gemini-2.5-flash, qwen3-235b-a22b-2507, deepseek-v3.2, claude-haiku-4.5) all
-- missed the unchanged bar on the frozen intake and English holdouts (best: 12/13 intake, 18/19 English, zero
-- wrong-admitted values). anthropic/claude-sonnet-4.6 (US$3 / 15 per M tokens, strict JSON schema, no seed) is added under
-- the same frozen contracts, DISABLED and PAUSED, to be qualified on the same frozen holdouts. It cannot run the tuition
-- contract (the live interpreter sends a seed with require_parameters).
with t(task, short, version) as (values
  ('provider_intake_validation','intake','cf247-intake-validation-v1.2.0'),
  ('provider_english_validation','english','cf247-english-validation-v1.0.0'))
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-'||t.short||'-l3r-claude-sonnet-4-6-v1','openrouter','https://openrouter.ai/api/v1','anthropic/claude-sonnet-4.6','OPENROUTER_API_KEY',array[t.task],t.version,
       'Contract '||t.version||' (layer3-model-routing, _shared/cf247-model-routing.ts); contract fingerprint '||f.fingerprint,
       jsonb_build_object('contract',t.version,'strict_json_schema',true),
       jsonb_build_object('contract',t.version,'contract_fingerprint',f.fingerprint,'quote_check','verbatim, whitespace-insensitive','returned_model_must_equal_pinned',true),
       12000,1200,30,6000,1,60000,0.10,false,true,
       jsonb_build_object('state','pending_holdout_qualification','validated',false),
       jsonb_build_object('pass',false,'state','pending_holdout_qualification'),
       'CF-CHG-20260915-247','CF-247-layer3-model-routing'
  from t join pipeline.layer3_task_contract_freezes f on f.task_class=t.task and f.contract_version=t.version
 where not exists (select 1 from pipeline.layer3_model_profiles x where x.code='openrouter-'||t.short||'-l3r-claude-sonnet-4-6-v1');
