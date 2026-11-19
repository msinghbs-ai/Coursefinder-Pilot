-- CF-CHG-20260915-247 Layer 3 model routing (Platform Admin direction 29 Sep 2026 18:30 IST): candidate profiles.
-- One profile per task class per candidate model, each pinned to one exact OpenRouter model id (never a router or
-- "auto" model), all created DISABLED and PAUSED. Chosen from the OpenRouter catalogue read on 29 Sep 2026 (13:2x UTC):
-- models that take a strict JSON schema (structured_outputs) and temperature; for tuition also seed, because the live
-- tuition interpreter's request (unchanged) sends one with require_parameters.
--   openai/gpt-4.1-mini          US$0.40 / 1.60 per M tokens (in / out)
--   google/gemini-2.5-flash      US$0.30 / 2.50
--   qwen/qwen3-235b-a22b-2507    US$0.0875 / 0.35
--   deepseek/deepseek-v3.2       US$0.28 / 0.42
--   anthropic/claude-haiku-4.5   US$1.00 / 5.00 (intake and English only: no seed, so it cannot run the tuition contract)
-- The intake and English prompts, schemas and validators live in code (contracts frozen 29 Sep 2026 13:31 UTC in
-- pipeline.layer3_task_contract_freezes); prompt_system here only names the contract. Tuition candidates copy the live
-- tuition profile's prompt, schema and validators exactly (only the model and version label differ), so a pass binds to
-- the unchanged live interpreter. Nothing here is enabled, unpaused or scheduled.

with m(slug, model, out_tokens) as (values
  ('gpt-4-1-mini','openai/gpt-4.1-mini',1200),
  ('gemini-2-5-flash','google/gemini-2.5-flash',4000),
  ('qwen3-235b-2507','qwen/qwen3-235b-a22b-2507',1200),
  ('deepseek-v3-2','deepseek/deepseek-v3.2',1500),
  ('claude-haiku-4-5','anthropic/claude-haiku-4.5',1200)),
t(task, short, version, fp) as (values
  ('provider_intake_validation','intake','cf247-intake-validation-v1.2.0',(select fingerprint from pipeline.layer3_task_contract_freezes where task_class='provider_intake_validation' and contract_version='cf247-intake-validation-v1.2.0')),
  ('provider_english_validation','english','cf247-english-validation-v1.0.0',(select fingerprint from pipeline.layer3_task_contract_freezes where task_class='provider_english_validation' and contract_version='cf247-english-validation-v1.0.0')))
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-'||t.short||'-l3r-'||m.slug||'-v1','openrouter','https://openrouter.ai/api/v1',m.model,'OPENROUTER_API_KEY',array[t.task],t.version,
       'Contract '||t.version||' (layer3-model-routing, _shared/cf247-model-routing.ts); contract fingerprint '||t.fp,
       jsonb_build_object('contract',t.version,'strict_json_schema',true),
       jsonb_build_object('contract',t.version,'contract_fingerprint',t.fp,'quote_check','verbatim, whitespace-insensitive','returned_model_must_equal_pinned',true),
       12000,m.out_tokens,30,6000,1,60000,0.05,false,true,
       jsonb_build_object('state','pending_holdout_qualification','validated',false),
       jsonb_build_object('pass',false,'state','pending_holdout_qualification'),
       'CF-CHG-20260915-247','CF-247-layer3-model-routing'
  from m cross join t
 where t.fp is not null
   and not exists (select 1 from pipeline.layer3_model_profiles x where x.code='openrouter-'||t.short||'-l3r-'||m.slug||'-v1');

-- tuition candidates: exact copies of the live tuition profile except the model (and a larger output allowance for the
-- thinking model gemini-2.5-flash, whose reasoning tokens count against max_tokens)
with m(slug, model, out_tokens) as (values
  ('gpt-4-1-mini','openai/gpt-4.1-mini',900),
  ('gemini-2-5-flash','google/gemini-2.5-flash',3000),
  ('qwen3-235b-2507','qwen/qwen3-235b-a22b-2507',900),
  ('deepseek-v3-2','deepseek/deepseek-v3.2',900))
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-tuition-l3r-'||m.slug||'-v1',s.aggregator_provider,s.base_url,m.model,s.secret_env_key,s.allowed_task_classes,
       'cf247-provider-current-tuition-validation-v2-numeric-confidence-'||m.slug||'-l3r',s.prompt_system,s.structured_output_schema,s.deterministic_validators,
       s.max_input_tokens,m.out_tokens,s.requests_per_minute,s.requests_per_day,s.retry_ceiling,s.timeout_ms,s.cost_ceiling_usd,false,true,
       jsonb_build_object('state','pending_holdout_qualification','validated',false),
       jsonb_build_object('pass',false,'state','pending_holdout_qualification'),
       s.change_control_ref,'CF-247-layer3-model-routing'
  from pipeline.layer3_model_profiles s cross join m
 where s.code='openrouter-provider-tuition-validation-mistral-small-3-2-v1'
   and not exists (select 1 from pipeline.layer3_model_profiles x where x.code='openrouter-tuition-l3r-'||m.slug||'-v1');
