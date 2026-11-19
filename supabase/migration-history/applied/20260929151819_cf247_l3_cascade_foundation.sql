-- CF-CHG-20260915-247 Layer 3 cost-tiered cascade: FOUNDATION (Platform Admin direction 29 Sep 2026 20:38 IST:
-- "use openrouter model routing in layer 3, use cheapest one with 80% success rates and for failed one use higher cost
-- model and so on ... be cost effective using model when required"). NOTHING IS ACTIVATED HERE.
--  * pipeline.layer3_route_tiers: the ladder per task class (one pinned profile per tier, ordered by measured cost per
--    call; active only after the activation migration);
--  * pipeline.layer3_route_budget.route_mode: 'single' (today) or 'ladder' (set only by the activation migration);
--  * holdout results carry the cascade tier, the escalation reasons and whether the attempt was final (h2 end-to-end);
--  * interpretations carry the cascade tier and escalation reasons; an attempt that was escalated is recorded with the
--    new status 'escalated' (each tier's attempt is its own interpretation, with its own cost);
--  * hard US$6 cap on all cascade-era test spend (run labels c-...), enforced in the Edge function and, as a backstop,
--    by a trigger here;
--  * five further low-cost candidate models per task class (plus claude-haiku-4.5 and claude-sonnet-4.6 for tuition),
--    all DISABLED and PAUSED, pinned to one exact OpenRouter id each (catalogue read 29 Sep 2026 15:1x UTC):
--      google/gemini-2.5-flash-lite            US$0.10 / 0.40 per M tokens (in / out)
--      openai/gpt-4.1-nano                     US$0.10 / 0.40
--      mistralai/mistral-small-3.2-24b-instruct US$0.094 / 0.25 (already the old tuition incumbent; new for intake/English)
--      meta-llama/llama-4-maverick             US$0.1875 / 0.6525
--      qwen/qwen3-30b-a3b-instruct-2507        US$0.048 / 0.193 (the non-thinking release of qwen3-30b-a3b)
--      anthropic/claude-haiku-4.5 (tuition)    US$1 / 5    } OpenRouter lists no seed support for Anthropic models; the
--      anthropic/claude-sonnet-4.6 (tuition)   US$3 / 15   } tuition request omits seed for these two only
--                                                             (deterministic_validators.seed_supported=false).
--    Intake and English candidates run the unchanged frozen contracts (cf247-intake-validation-v1.2.0,
--    cf247-english-validation-v1.0.0); tuition candidates copy the live tuition profile's prompt, schema and validators.

create table if not exists pipeline.layer3_route_tiers (
  id uuid primary key default gen_random_uuid(),
  task_class text not null check (task_class in ('provider_intake_validation','provider_english_validation','provider_current_tuition_validation')),
  tier_no int not null check (tier_no between 1 and 6),
  profile_id uuid not null references pipeline.layer3_model_profiles(id),
  min_success numeric not null default 0.80 check (min_success > 0 and min_success <= 1),
  cost_per_call_usd numeric not null check (cost_per_call_usd >= 0),
  h1_success_rate numeric,
  h1_wrong_admitted int,
  h1_wrong_admitted_after_escalation int,
  is_final boolean not null default false,
  qualified_by jsonb not null default '{}'::jsonb,
  qualified_binding_hash text check (qualified_binding_hash is null or qualified_binding_hash ~ '^[0-9a-f]{64}$'),
  contract_version text not null default 'cf247-l3-cascade-v1.0.0',
  active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  change_control_ref text not null default 'CF-CHG-20260915-247',
  unique (task_class, contract_version, tier_no)
);
create unique index if not exists layer3_route_tiers_active_idx on pipeline.layer3_route_tiers(task_class, tier_no) where active;
alter table pipeline.layer3_route_tiers enable row level security;
revoke all on pipeline.layer3_route_tiers from public, anon, authenticated;
comment on table pipeline.layer3_route_tiers is 'CF-247 Layer 3 cascade ladder per task class (Platform Admin direction 29 Sep 2026 20:38 IST). Active rows are used only when layer3_route_budget.route_mode = ladder.';

alter table pipeline.layer3_route_budget add column if not exists route_mode text not null default 'single';
do $c$ begin
  if not exists (select 1 from pg_constraint where conname='layer3_route_budget_route_mode_check') then
    alter table pipeline.layer3_route_budget add constraint layer3_route_budget_route_mode_check check (route_mode in ('single','ladder'));
  end if;
end $c$;

alter table pipeline.layer3_holdout_results
  add column if not exists cascade_tier_no int,
  add column if not exists escalation_reasons text[] not null default '{}',
  add column if not exists cascade_final boolean;

alter table pipeline.layer3_interpretations
  add column if not exists cascade_tier_no int,
  add column if not exists escalation_reasons text[];
alter table pipeline.layer3_interpretations drop constraint layer3_interpretations_status_check;
alter table pipeline.layer3_interpretations add constraint layer3_interpretations_status_check
  check (status = any (array['reserved','calling','validated','rejected_validation','provider_error','cancelled','no_candidate','escalated']));

-- cascade-era test spend (all run labels c-...): hard US$6 cap
create or replace function pipeline.layer3_cascade_test_spent_usd() returns numeric language sql stable set search_path to 'pg_catalog','pipeline' as $f$
  select coalesce(sum(cost_usd),0) from pipeline.layer3_holdout_results where run_label like 'c-%'
$f$;
revoke all on function pipeline.layer3_cascade_test_spent_usd() from public, anon, authenticated;
create or replace function pipeline.layer3_cascade_test_cap_guard() returns trigger language plpgsql set search_path to 'pg_catalog','pipeline' as $f$
begin
  if new.run_label like 'c-%' and pipeline.layer3_cascade_test_spent_usd() >= 6.0 then
    raise exception 'cascade test spend cap US$6 reached (spent %)', pipeline.layer3_cascade_test_spent_usd();
  end if;
  return new;
end $f$;
drop trigger if exists layer3_cascade_test_cap on pipeline.layer3_holdout_results;
create trigger layer3_cascade_test_cap before insert on pipeline.layer3_holdout_results for each row execute function pipeline.layer3_cascade_test_cap_guard();

create or replace function public.layer3_cascade_test_spent_service() returns numeric language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  perform public.layer3_routing_service_guard();
  return pipeline.layer3_cascade_test_spent_usd();
end $f$;

-- stored holdout results of a gold set (offline replay reads these; no model call)
create or replace function public.layer3_holdout_results_service(p_gold_set text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  perform public.layer3_routing_service_guard();
  return coalesce((select jsonb_agg(jsonb_build_object('run_label',r.run_label,'case_id',r.case_id,'case_key',c.case_key,'profile_id',r.profile_id,'profile_code',p.code,
      'configured_model',r.configured_model,'returned_model',r.returned_model,'outcome',r.outcome,'admitted',r.admitted,'answer',r.answer,'errors',r.errors,
      'cost_usd',r.cost_usd,'external_calls',r.external_calls,'cascade_tier_no',r.cascade_tier_no,'escalation_reasons',r.escalation_reasons,'cascade_final',r.cascade_final)
      order by r.run_label, c.case_key)
    from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id join pipeline.layer3_model_profiles p on p.id=r.profile_id
   where c.gold_set=p_gold_set),'[]'::jsonb);
end $f$;

-- one cascade attempt on a holdout case (h2 end-to-end run)
create or replace function public.layer3_cascade_result_record_service(p_run_label text, p_case_id uuid, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  perform public.layer3_routing_service_guard();
  if p_run_label !~ '^c-' then raise exception 'cascade run labels start with c-'; end if;
  insert into pipeline.layer3_holdout_results(run_label,case_id,profile_id,task_class,configured_model,returned_model,outcome,admitted,answer,errors,text_matches_gold,excerpt_in_text,
    cost_usd,input_tokens,output_tokens,latency_ms,external_calls,cascade_tier_no,escalation_reasons,cascade_final)
  values (p_run_label,p_case_id,(p_result->>'profile_id')::uuid,p_result->>'task_class',p_result->>'configured_model',p_result->>'returned_model',p_result->>'outcome',
    p_result->'admitted',p_result->'answer',coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'errors') x),'{}'),
    (p_result->>'text_matches_gold')::boolean,(p_result->>'excerpt_in_text')::boolean,greatest(coalesce((p_result->>'cost_usd')::numeric,0),0),
    coalesce((p_result->>'input_tokens')::int,0),coalesce((p_result->>'output_tokens')::int,0),(p_result->>'latency_ms')::int,coalesce((p_result->>'external_calls')::int,0),
    (p_result->>'cascade_tier_no')::int,coalesce((select array_agg(x) from jsonb_array_elements_text(p_result->'escalation_reasons') x),'{}'),(p_result->>'cascade_final')::boolean)
  on conflict (run_label,case_id) do nothing;
  return jsonb_build_object('ok',true,'cascade_test_spent_usd',pipeline.layer3_cascade_test_spent_usd());
end $f$;

-- the ladder of a task class (all tiers of the given contract version, with each tier's profile)
create or replace function public.layer3_cascade_ladder_service(p_task_class text, p_contract_version text default 'cf247-l3-cascade-v1.0.0')
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
begin
  perform public.layer3_routing_service_guard();
  return jsonb_build_object('task_class',p_task_class,'contract_version',p_contract_version,
    'route_mode',(select route_mode from pipeline.layer3_route_budget where task_class=p_task_class),
    'tiers',coalesce((select jsonb_agg(jsonb_build_object('tier_no',t.tier_no,'active',t.active,'is_final',t.is_final,'cost_per_call_usd',t.cost_per_call_usd,
        'qualified_binding_hash',t.qualified_binding_hash,
        'profile',jsonb_build_object('id',p.id,'code',p.code,'model_identifier',p.model_identifier,'base_url',p.base_url,'secret_env_key',p.secret_env_key,
          'enabled',p.enabled,'paused',p.paused,'retired_at',p.retired_at,'allowed_task_classes',p.allowed_task_classes,'prompt_profile_version',p.prompt_profile_version,
          'prompt_system',p.prompt_system,'structured_output_schema',p.structured_output_schema,'deterministic_validators',p.deterministic_validators,
          'max_input_tokens',p.max_input_tokens,'max_output_tokens',p.max_output_tokens,'timeout_ms',p.timeout_ms,'retry_ceiling',p.retry_ceiling,
          'cost_ceiling_usd',p.cost_ceiling_usd,'requests_per_minute',p.requests_per_minute,'requests_per_day',p.requests_per_day)) order by t.tier_no)
      from pipeline.layer3_route_tiers t join pipeline.layer3_model_profiles p on p.id=t.profile_id
     where t.task_class=p_task_class and t.contract_version=p_contract_version),'[]'::jsonb));
end $f$;

do $g$ declare fn text;
begin
  foreach fn in array array['layer3_cascade_test_spent_service()','layer3_holdout_results_service(text)','layer3_cascade_result_record_service(text,uuid,jsonb)',
    'layer3_cascade_ladder_service(text,text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', fn);
    execute format('grant execute on function public.%s to service_role', fn);
  end loop;
end $g$;

-- candidate profiles for intake and English (unchanged frozen contracts), DISABLED and PAUSED
with m(slug, model, out_tokens) as (values
  ('gemini-2-5-flash-lite','google/gemini-2.5-flash-lite',4000),
  ('gpt-4-1-nano','openai/gpt-4.1-nano',1200),
  ('mistral-small-3-2','mistralai/mistral-small-3.2-24b-instruct',1200),
  ('llama-4-maverick','meta-llama/llama-4-maverick',1200),
  ('qwen3-30b-a3b-2507','qwen/qwen3-30b-a3b-instruct-2507',1200)),
t(task, short, version) as (values
  ('provider_intake_validation','intake','cf247-intake-validation-v1.2.0'),
  ('provider_english_validation','english','cf247-english-validation-v1.0.0'))
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-'||t.short||'-l3c-'||m.slug||'-v1','openrouter','https://openrouter.ai/api/v1',m.model,'OPENROUTER_API_KEY',array[t.task],t.version,
       'Contract '||t.version||' (layer3-model-routing, _shared/cf247-model-routing.ts); contract fingerprint '||f.fingerprint,
       jsonb_build_object('contract',t.version,'strict_json_schema',true),
       jsonb_build_object('contract',t.version,'contract_fingerprint',f.fingerprint,'quote_check','verbatim, whitespace-insensitive','returned_model_must_equal_pinned',true),
       12000,m.out_tokens,30,6000,1,60000,0.05,false,true,
       jsonb_build_object('state','pending_cascade_candidate_test','validated',false),
       jsonb_build_object('pass',false,'state','pending_cascade_candidate_test'),
       'CF-CHG-20260915-247','CF-247-layer3-cascade'
  from m cross join t join pipeline.layer3_task_contract_freezes f on f.task_class=t.task and f.contract_version=t.version
 where not exists (select 1 from pipeline.layer3_model_profiles x where x.code='openrouter-'||t.short||'-l3c-'||m.slug||'-v1');

-- tuition candidates: exact copies of the live tuition profile except the model (and seed_supported=false for the two
-- Anthropic models, whose request omits seed)
with m(slug, model, out_tokens, seed_ok, ceiling) as (values
  ('gemini-2-5-flash-lite','google/gemini-2.5-flash-lite',3000,true,0.05),
  ('gpt-4-1-nano','openai/gpt-4.1-nano',900,true,0.05),
  ('llama-4-maverick','meta-llama/llama-4-maverick',900,true,0.05),
  ('qwen3-30b-a3b-2507','qwen/qwen3-30b-a3b-instruct-2507',900,true,0.05),
  ('claude-haiku-4-5','anthropic/claude-haiku-4.5',900,false,0.10),
  ('claude-sonnet-4-6','anthropic/claude-sonnet-4.6',900,false,0.10))
insert into pipeline.layer3_model_profiles(code,aggregator_provider,base_url,model_identifier,secret_env_key,allowed_task_classes,prompt_profile_version,prompt_system,
  structured_output_schema,deterministic_validators,max_input_tokens,max_output_tokens,requests_per_minute,requests_per_day,retry_ceiling,timeout_ms,cost_ceiling_usd,
  enabled,paused,last_validation_result,quality_benchmark,change_control_ref,uat_ref)
select 'openrouter-tuition-l3c-'||m.slug||'-v1',s.aggregator_provider,s.base_url,m.model,s.secret_env_key,s.allowed_task_classes,
       'cf247-provider-current-tuition-validation-v2-numeric-confidence-'||m.slug||'-l3c',s.prompt_system,s.structured_output_schema,
       case when m.seed_ok then s.deterministic_validators else s.deterministic_validators||jsonb_build_object('seed_supported',false) end,
       s.max_input_tokens,m.out_tokens,s.requests_per_minute,s.requests_per_day,s.retry_ceiling,s.timeout_ms,m.ceiling,false,true,
       jsonb_build_object('state','pending_cascade_candidate_test','validated',false),
       jsonb_build_object('pass',false,'state','pending_cascade_candidate_test'),
       s.change_control_ref,'CF-247-layer3-cascade'
  from pipeline.layer3_model_profiles s cross join m
 where s.code='openrouter-tuition-l3r-qwen3-235b-2507-v1'
   and not exists (select 1 from pipeline.layer3_model_profiles x where x.code='openrouter-tuition-l3c-'||m.slug||'-v1');

do $v$
begin
  if (select count(*) from pipeline.layer3_model_profiles where code like 'openrouter-%-l3c-%' and not enabled and paused)<>16 then
    raise exception 'expected 16 disabled, paused cascade candidate profiles';
  end if;
  if exists (select 1 from pipeline.layer3_route_budget where route_mode<>'single') then raise exception 'nothing may be in ladder mode yet'; end if;
end $v$;
