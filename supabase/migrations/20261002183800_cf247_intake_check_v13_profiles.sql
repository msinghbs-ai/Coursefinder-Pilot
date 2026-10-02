-- CF-247 (Decision 229, 2 Oct 2026). Platform Admin, 19:21: "4 go ahead" (intake check v1.3.0 as a new contract).
-- Two candidate profiles for the v1.3.0 intake contract (layer3-model-routing chooses the contract by
-- prompt_profile_version). They are copies of the two qualified intake models (Qwen3 30B, cascade step 1; Claude Haiku
-- 4.5, step 2), each pinned to its single named model, created PAUSED and not placed in the cascade. Qualification on
-- the frozen holdout l3r-intake-h1 runs against them; switching either on is a separate step for the Platform Admin.
-- The v1.2.0 profiles are not changed.
insert into pipeline.layer3_model_profiles(code, aggregator_provider, base_url, model_identifier, secret_env_key, allowed_task_classes,
  prompt_profile_version, prompt_system, structured_output_schema, deterministic_validators, max_input_tokens, max_output_tokens,
  requests_per_minute, requests_per_day, retry_ceiling, timeout_ms, cost_ceiling_usd, enabled, paused, change_control_ref)
select x.new_code, p.aggregator_provider, p.base_url, p.model_identifier, p.secret_env_key, p.allowed_task_classes,
       'cf247-intake-validation-v1.3.0', 'Contract cf247-intake-validation-v1.3.0 (prompt and validators in supabase/functions/_shared/cf247-intake-validation-v13.ts)',
       p.structured_output_schema, p.deterministic_validators, p.max_input_tokens, p.max_output_tokens,
       p.requests_per_minute, p.requests_per_day, p.retry_ceiling, p.timeout_ms, p.cost_ceiling_usd, true, true, 'CF-CHG-20260915-247; Decision 229'
  from pipeline.layer3_model_profiles p
  join (values ('openrouter-intake-l3c-qwen3-30b-a3b-2507-v1', 'openrouter-intake-v13-qwen3-30b-a3b-2507-v1'),
               ('openrouter-intake-l3r-claude-haiku-4-5-v1', 'openrouter-intake-v13-claude-haiku-4-5-v1')) x(old_code, new_code) on x.old_code = p.code
 where not exists (select 1 from pipeline.layer3_model_profiles e where e.code = x.new_code);
