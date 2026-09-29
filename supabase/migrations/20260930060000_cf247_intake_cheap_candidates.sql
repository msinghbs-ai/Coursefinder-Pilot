-- CF-247 Layer 3 without Sonnet (Platform Admin, 30 Sep 2026 01:31 IST): "let not use sonnet its burning money ... get the
-- maximum data admitted with cheaper model". Sonnet was switched off in both cascades through the logged admin control
-- (Intakes: Qwen3 30B -> Claude Haiku 4.5; English: Qwen3 30B -> Mistral Small 3.2). This adds four cheaper candidates
-- for the intake cascade, each an exact copy of the intake Qwen3 30B candidate except the model and output allowance
-- (reasoning models need room to think). They start disabled and paused and must pass the frozen holdout l3r-intake-h1
-- (>= 80% right, 0 wrong admitted) before they can be added to a cascade. OpenRouter prices on 30 Sep 2026 (US$ per
-- million tokens in/out): gpt-oss-120b 0.037/0.17, qwen3-235b-2507 0.0875/0.35, qwen3-next-80b 0.10/1.10,
-- deepseek-v3.2-exp 0.27/0.41; Claude Haiku 4.5 is 1/5.
with m(slug, model, out_tokens) as (values
  ('gpt-oss-120b','openai/gpt-oss-120b',4000),
  ('qwen3-235b-2507','qwen/qwen3-235b-a22b-2507',1200),
  ('qwen3-next-80b','qwen/qwen3-next-80b-a3b-instruct',1200),
  ('deepseek-v3-2-exp','deepseek/deepseek-v3.2-exp',4000))
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-intake-l3c-'||m.slug||'-v1',s.aggregator_provider,s.base_url,m.model,s.secret_env_key,s.allowed_task_classes,s.prompt_profile_version,s.prompt_system,
       s.structured_output_schema,s.deterministic_validators,s.max_input_tokens,m.out_tokens,s.requests_per_minute,s.requests_per_day,s.retry_ceiling,s.timeout_ms,s.cost_ceiling_usd,
       false,true,jsonb_build_object('state','pending_cascade_candidate_test','validated',false),jsonb_build_object('pass',false,'state','pending_cascade_candidate_test'),
       s.change_control_ref,'CF-247-layer3-cheap-cascade'
  from pipeline.layer3_model_profiles s cross join m
 where s.code='openrouter-intake-l3c-qwen3-30b-a3b-2507-v1'
   and not exists (select 1 from pipeline.layer3_model_profiles x where x.code='openrouter-intake-l3c-'||m.slug||'-v1');

do $v$ begin
  if (select count(*) from pipeline.layer3_model_profiles where code in ('openrouter-intake-l3c-gpt-oss-120b-v1','openrouter-intake-l3c-qwen3-235b-2507-v1',
      'openrouter-intake-l3c-qwen3-next-80b-v1','openrouter-intake-l3c-deepseek-v3-2-exp-v1') and not enabled and paused)<>4 then
    raise exception 'expected 4 disabled, paused intake candidates';
  end if;
end $v$;
