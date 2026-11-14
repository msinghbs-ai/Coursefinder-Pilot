-- Phase 2 rows, loaded into both databases before the migrations.
insert into pipeline.layer3_model_profiles (code, model_identifier, allowed_task_classes, enabled, paused, retired_at) values
  ('openrouter-intake-l3c-qwen3-30b-a3b-2507-v1', 'qwen/qwen3-30b-a3b-instruct-2507', '{provider_intake_validation}', true, false, null),
  ('openrouter-intake-l3c-kimi-k2-0905-v1', 'moonshotai/kimi-k2-0905', '{provider_intake_validation}', true, false, null),
  ('openrouter-intake-l3r-claude-haiku-4-5-v1', 'anthropic/claude-haiku-4.5', '{provider_intake_validation}', true, false, null),
  ('openrouter-english-l3r-claude-sonnet-4-6-v1', 'anthropic/claude-sonnet-4.6', '{provider_english_validation}', true, false, null);
insert into pipeline.layer3_route_tiers select id, 'provider_intake_validation', 1, true from pipeline.layer3_model_profiles where code = 'openrouter-intake-l3c-qwen3-30b-a3b-2507-v1';
insert into pipeline.layer3_interpretations (created_at) values ('2026-10-11 21:55:27+00');
insert into pipeline.uni_adapter_models (provider_id, profile_code, reason) values ('00000000-0000-0000-0000-00000000b001', 'openrouter-intake-l3r-claude-haiku-4-5-v1', 'a person chose Claude for this provider');
insert into pipeline.evidence_artifacts values ('00000000-0000-0000-0000-00000000e002', 'c/calendar.html', 'text/html');
insert into pipeline.provider_fact_sources values ('00000000-0000-0000-0000-00000000f101', 'https://fixture.example/calendar', '00000000-0000-0000-0000-00000000e002');
update pipeline.central_ai_queue set fact_source_id = '00000000-0000-0000-0000-00000000f101';
insert into pipeline.coverage_ai_match (course_id, provider_id, state, candidates) values ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000b001', 'ready', '[{"url": "https://fixture.example/c1"}]');
-- a function that names a model outside the routes, as the guard must report it
create function public.fx_pins_a_model() returns text language sql as $$ select coalesce(null, 'openai/gpt-4.1-mini') $$;
create function public.fx_allowed_default() returns text language sql as $$ select coalesce(null, 'qwen/qwen3-30b-a3b-instruct-2507') $$;
