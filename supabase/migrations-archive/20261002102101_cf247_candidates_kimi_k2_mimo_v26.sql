-- CF-247 (2 Oct 2026). Platform Admin, 20:18: "Qualify kimi-k2-0905 and mimo-v2.6-pro as alternative and cascade in
-- models." Four candidate profiles, each pinned to one named OpenRouter model (both listed in the OpenRouter catalogue
-- with structured outputs): Moonshot Kimi K2 (0905) and Xiaomi MiMo v2.6 Pro, for the intake and the English task.
-- They are copies of the qualified Qwen3 30B profile for each task (same contract, same limits), created PAUSED and not
-- placed in any cascade. Qualification runs on the frozen holdouts l3r-intake-h1 and l3r-english-h1; switching any of
-- them on, or adding one to a cascade, is a separate step for the Platform Admin. MiMo v2.6 Pro is a reasoning model,
-- so its output allowance is 4000 tokens like the other reasoning candidates. No existing profile is changed.
insert into pipeline.layer3_model_profiles(code, aggregator_provider, base_url, model_identifier, secret_env_key, allowed_task_classes,
  prompt_profile_version, prompt_system, structured_output_schema, deterministic_validators, max_input_tokens, max_output_tokens,
  requests_per_minute, requests_per_day, retry_ceiling, timeout_ms, cost_ceiling_usd, enabled, paused, change_control_ref)
select x.new_code, p.aggregator_provider, p.base_url, x.model, p.secret_env_key, p.allowed_task_classes,
       p.prompt_profile_version, p.prompt_system, p.structured_output_schema, p.deterministic_validators, p.max_input_tokens, x.max_out,
       p.requests_per_minute, p.requests_per_day, p.retry_ceiling, p.timeout_ms, p.cost_ceiling_usd, false, true, 'CF-CHG-20260915-247; candidates Kimi K2 0905 and MiMo v2.6 Pro'
  from pipeline.layer3_model_profiles p
  join (values
    ('openrouter-intake-l3c-qwen3-30b-a3b-2507-v1',  'openrouter-intake-l3c-kimi-k2-0905-v1',  'moonshotai/kimi-k2-0905', 1200),
    ('openrouter-intake-l3c-qwen3-30b-a3b-2507-v1',  'openrouter-intake-l3c-mimo-v2-6-pro-v1', 'xiaomi/mimo-v2.6-pro',    4000),
    ('openrouter-english-l3c-qwen3-30b-a3b-2507-v1', 'openrouter-english-l3c-kimi-k2-0905-v1', 'moonshotai/kimi-k2-0905', 1200),
    ('openrouter-english-l3c-qwen3-30b-a3b-2507-v1', 'openrouter-english-l3c-mimo-v2-6-pro-v1','xiaomi/mimo-v2.6-pro',    4000)
  ) x(old_code, new_code, model, max_out) on x.old_code = p.code
 where not exists (select 1 from pipeline.layer3_model_profiles e where e.code = x.new_code);
