-- CF-247 AI spend control: one list of models, one route per AI service (cascade, daily caps, prompt source), usage by service and model.
-- Platform Admin 13 Nov 2026 19:14 AEDT: "GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the
--   usage per field in ui under Model and Services. UI is useless and grown organically. define proper and clear controls of OpenRouter key and
--   usage pane, Model classified that can be used - Qwen3, Mimo, mistral small, Kimi K2, Gemini, LLama, deepseek and then Service based Model
--   with cascading, Then Recent usage, remove/retire all other older scripts"
-- Platform Admin 13 Nov 2026 19:15 AEDT: "Keep prompt respective for each service as well"
-- Platform Admin 13 Nov 2026 19:23 AEDT: "stop the entry requirement or any other setting using GPT mini now. all settings corresponding to
--   model using AI model/prompt or services should be defined in Model & services. simply the settings UI as well and retire non used settings
--   developed unnecessary since the redesigned modules"
-- Backend only. The page (Models & services) is built from docs/platform/AI-MODELS-SERVICES-CONTRACT.md in a following change.
--
-- What this adds
--   pipeline.ai_model_catalogue   the one list of models: family, OpenRouter id, price, allowed or not allowed. GPT-4.1 mini, GPT-4.1, GPT-4.1 nano
--                                 and the Claude models are listed as not allowed, so history still resolves and no route can name them.
--   pipeline.ai_service_routes    one row per AI service: its spend lane (and how a shared lane is split), its cascade of 1 to 4 models, a daily
--                                 US$ cap and a daily calls cap (null = none), where its prompt is kept, and whether it is switched on.
--   security.ai_route_v1(service) what a reader asks: the allowed models in cascade order, the caps, today's spend (UTC day, as the existing AI
--                                 guards count it) and whether the service is held (switched off, no allowed model, the daily ceiling
--                                 budgets.ai_daily_ceiling_usd reached, or its own cap reached). A held route holds whatever the OpenRouter
--                                 toolset mode is: the mode was Observe only, so the ceiling of US$14 stopped nothing (US$37 on 12 Nov).
--                                 A cap or the ceiling (held_kind limit) does not hold a provider of an open on-demand request (operating model
--                                 3.3.2, Platform Admin 12 Nov 2026 21:07); switched off or no allowed model (held_kind off) holds everything.
--   pipeline.ai_spend_ledger      two new columns beside the old ones: service_code and model. Filled by the one writer,
--                                 security.ai_spend_capture_v1. service_code is also filled for the rows already there (so today's spend counts
--                                 from the first minute); model is filled going forward only.
--   pipeline.platform_toolset_settings  two new columns, home and home_group: a setting about an AI model, prompt, cap, switch or the OpenRouter
--                                 credit is marked home = 'models_services' with the service it belongs to. Nothing is hidden or removed.
--   public.admin_ai_overview_v1, admin_ai_model_set_v1, admin_ai_route_set_v1   the page's read and its two audited writes.
--
-- What this changes in existing functions (each md5-guarded; only the model and budget lines; every key the deployed worker reads keeps its name
-- and type; `models`, `routes` and `held` are new keys beside them)
--   public.svc_enrich_ai_next(integer)      e4bdf62857d011458e3293006a7e7426 -> 91b15e0d47ea762d391f3a937b49f72c
--   public.svc_entry_matrix_next(integer)   3eb6ca3bb909cda113e2c1ee79704a42 -> 93cc870630625dd8c2a215cae4cc1601
--   public.svc_ops_diagnosis_next(integer)  adc209ebf9196c613e3dd82fa76fed61 -> 8a2b8a50b0fd640365b3dab7a2d372aa
--   security.ai_spend_capture_v1()          5b78fa074a9480d4f127ecc4fe93dcf3 -> 13a35f446d15bc3ce06fe0d0e4725284
--
-- Stops GPT-4.1 mini: the course entry requirements read, entry matrices and the operations diagnosis are seeded qwen3-30b first, then
--   mistral-small-3.2. The scholarship chain loses gpt-4.1-mini as its second step (an unproven fact then goes to a person, as it does when the
--   chain ends). No switch is turned on by this change: entry.matrix_enabled, aer.*, ops.ai_diagnosis_on keep their values.
--
-- Replaces: the model choice of settings pipeline entry.matrix_model and ops.ai_diagnosis_model, and of pipeline.central_ai_settings.model_* for the
--   course field reader (public.svc_enrich_ai_next), with pipeline.ai_service_routes. The two settings stay and are no longer read.
--   pipeline.central_ai_settings.model_* is still read by the central pages, fee, calendar and provider description readers, so it is kept
--   equal to their routes by trigger (both directions) until those readers ask the route.
-- Retires: nothing is dropped. pipeline.component_register has no kind for a setting, so the two unread settings say so in their used_by line and
--   carry home = 'models_services'; pipeline.central_ai_settings stays active with a note.

do $guard$
declare r record;
begin
  for r in select * from (values
      ('public.svc_enrich_ai_next(integer)', 'e4bdf62857d011458e3293006a7e7426', '91b15e0d47ea762d391f3a937b49f72c'),
      ('public.svc_entry_matrix_next(integer)', '3eb6ca3bb909cda113e2c1ee79704a42', '93cc870630625dd8c2a215cae4cc1601'),
      ('public.svc_ops_diagnosis_next(integer)', 'adc209ebf9196c613e3dd82fa76fed61', '8a2b8a50b0fd640365b3dab7a2d372aa'),
      ('security.ai_spend_capture_v1()', '5b78fa074a9480d4f127ecc4fe93dcf3', '13a35f446d15bc3ce06fe0d0e4725284')) v(sig, before, after) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) not in (r.before, r.after) then
      raise exception 'live % differs from the definition this change replaces (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure));
    end if;
    raise notice '%: %', r.sig, case when md5(pg_get_functiondef(r.sig::regprocedure)) = r.after then 'unchanged' else 'applied' end;
  end loop;
end $guard$;

-- 1 the model list ------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.ai_model_catalogue (
  code text primary key,
  family text not null default 'other' check (family in ('qwen3', 'mimo', 'mistral_small', 'kimi_k2', 'gemini', 'llama', 'deepseek', 'other')),
  label text not null,
  model_identifier text not null unique,
  input_usd_per_mtok numeric,
  output_usd_per_mtok numeric,
  price_checked_at timestamptz,
  context_tokens integer,
  status text not null default 'not_allowed' check (status in ('allowed', 'not_allowed')),
  note text,
  sort integer not null default 100,
  reason text,
  changed_at timestamptz not null default now(),
  changed_by uuid);
comment on table pipeline.ai_model_catalogue is 'The one list of AI models the platform may use (Models & services): family, OpenRouter id, price per million tokens, allowed or not allowed. A service route (pipeline.ai_service_routes) can only name a model listed here as allowed. Platform Admin 13 Nov 2026.';
alter table pipeline.ai_model_catalogue enable row level security;
revoke all on pipeline.ai_model_catalogue from anon, authenticated;

create or replace function security.ai_model_family_trg() returns trigger language plpgsql set search_path = '' as $function$
begin
  -- the families the Platform Admin named (13 Nov 2026); any other value is stored as 'other'
  if new.family is null or new.family not in ('qwen3', 'mimo', 'mistral_small', 'kimi_k2', 'gemini', 'llama', 'deepseek') then new.family := 'other'; end if;
  return new;
end $function$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'ai_model_family' and tgrelid = 'pipeline.ai_model_catalogue'::regclass) then
    create trigger ai_model_family before insert or update of family on pipeline.ai_model_catalogue for each row execute function security.ai_model_family_trg();
  end if;
end $$;

-- Prices and context sizes: OpenRouter models API (openrouter.ai/api/v1/models), read 13 Nov 2026. The identifiers below were each seen in that
-- list. A model that could not be verified would be seeded not_allowed with the note 'identifier not verified'; none needed it.
insert into pipeline.ai_model_catalogue (code, family, label, model_identifier, input_usd_per_mtok, output_usd_per_mtok, price_checked_at, context_tokens, status, note, sort, reason) values
  ('qwen3-30b', 'qwen3', 'Qwen3 30B A3B Instruct (2507)', 'qwen/qwen3-30b-a3b-instruct-2507', 0.10, 0.30, now(), 262144, 'allowed', 'In use: course fields, central pages, fees, scholarships, course-page matching, adapter proposals', 10, 'seed 13 Nov 2026'),
  ('qwen3-235b', 'qwen3', 'Qwen3 235B A22B (2507)', 'qwen/qwen3-235b-a22b-2507', 0.14, 0.80, now(), 262144, 'allowed', 'In use: Layer 3 tuition validation', 11, 'seed 13 Nov 2026'),
  ('mimo-v2.6-pro', 'mimo', 'MiMo v2.6 Pro', 'xiaomi/mimo-v2.6-pro', 0.435, 0.87, now(), 1050000, 'allowed', 'In use: Layer 3 English validation', 20, 'seed 13 Nov 2026'),
  ('mimo-v2.6-flash', 'mimo', 'MiMo v2.6 Flash', 'xiaomi/mimo-v2.6-flash', 0.14, 0.28, now(), 1050000, 'allowed', 'Not used yet; not qualified on any platform prompt', 21, 'seed 13 Nov 2026'),
  ('mistral-small-3.2', 'mistral_small', 'Mistral Small 3.2 24B', 'mistralai/mistral-small-3.2-24b-instruct', 0.10, 0.30, now(), 256000, 'allowed', 'Layer 3 candidate (not switched on); second in the cascades that were on GPT-4.1 mini', 30, 'seed 13 Nov 2026'),
  ('kimi-k2-0905', 'kimi_k2', 'Kimi K2 (0905)', 'moonshotai/kimi-k2-0905', 0.60, 2.50, now(), 262144, 'allowed', 'In use: Layer 3 intake validation. Costs more than GPT-4.1 mini per token', 40, 'seed 13 Nov 2026'),
  ('gemini-2.5-flash-lite', 'gemini', 'Gemini 2.5 Flash Lite', 'google/gemini-2.5-flash-lite', 0.10, 0.40, now(), 1048576, 'allowed', 'Layer 3 candidate (not switched on)', 50, 'seed 13 Nov 2026'),
  ('gemini-2.5-flash', 'gemini', 'Gemini 2.5 Flash', 'google/gemini-2.5-flash', 0.30, 2.50, now(), 1048576, 'allowed', 'Layer 3 profiles retired after their tests', 51, 'seed 13 Nov 2026'),
  ('llama-4-maverick', 'llama', 'Llama 4 Maverick', 'meta-llama/llama-4-maverick', 0.35, 1.00, now(), 524288, 'allowed', 'Layer 3 candidate (not switched on)', 60, 'seed 13 Nov 2026'),
  ('llama-4-scout', 'llama', 'Llama 4 Scout', 'meta-llama/llama-4-scout', 0.10, 0.30, now(), 1310720, 'allowed', 'Not used yet; not qualified on any platform prompt', 61, 'seed 13 Nov 2026'),
  ('deepseek-v3.2', 'deepseek', 'DeepSeek V3.2', 'deepseek/deepseek-v3.2', 0.26, 0.38, now(), 163840, 'allowed', 'Layer 3 profiles retired after their tests', 70, 'seed 13 Nov 2026'),
  ('deepseek-v4-flash', 'deepseek', 'DeepSeek V4 Flash', 'deepseek/deepseek-v4-flash', 0.09, 0.18, now(), 1048576, 'allowed', 'Not used yet; not qualified on any platform prompt', 71, 'seed 13 Nov 2026'),
  ('gpt-4.1-mini', 'openai', 'GPT-4.1 mini', 'openai/gpt-4.1-mini', 0.40, 1.60, now(), 1047576, 'not_allowed', 'Platform Admin 13 Nov 2026 19:14: too expensive, it exhausted the AI credit. Kept so history resolves', 900, 'Platform Admin 13 Nov 2026 19:14'),
  ('gpt-4.1', 'openai', 'GPT-4.1', 'openai/gpt-4.1', 2.00, 8.00, now(), 1047576, 'not_allowed', 'Not in the families the Platform Admin allows. Kept so history resolves', 901, 'Platform Admin 13 Nov 2026 19:14'),
  ('gpt-4.1-nano', 'openai', 'GPT-4.1 nano', 'openai/gpt-4.1-nano', 0.10, 0.40, now(), 1047576, 'not_allowed', 'Not in the families the Platform Admin allows. Kept so history resolves', 902, 'Platform Admin 13 Nov 2026 19:14'),
  ('claude-haiku-4.5', 'anthropic', 'Claude Haiku 4.5', 'anthropic/claude-haiku-4.5', 1.00, 5.00, now(), 200000, 'not_allowed', 'Not in the families the Platform Admin allows. Kept so history resolves', 910, 'Platform Admin 13 Nov 2026 19:14'),
  ('claude-sonnet-4.6', 'anthropic', 'Claude Sonnet 4.6', 'anthropic/claude-sonnet-4.6', 3.00, 15.00, now(), 1000000, 'not_allowed', 'Not in the families the Platform Admin allows. Still switched on in Layer 3 English validation (its own tiers). Kept so history resolves', 911, 'Platform Admin 13 Nov 2026 19:14')
on conflict (code) do nothing;

-- 2 the service routes --------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.ai_service_routes (
  service_code text primary key,
  label text not null,
  area text not null,
  field text,
  lane text not null,
  ledger_match jsonb,
  cascade text[] not null check (cardinality(cascade) between 1 and 4),
  daily_usd_cap numeric check (daily_usd_cap is null or daily_usd_cap >= 0),
  daily_calls_cap integer check (daily_calls_cap is null or daily_calls_cap >= 0),
  prompt_source text not null,
  enabled boolean not null default true,
  resolver text not null default 'route',
  note text,
  sort integer not null default 100,
  reason text,
  changed_at timestamptz not null default now(),
  changed_by uuid);
comment on table pipeline.ai_service_routes is 'One row per AI service (Models & services): its spend lane in pipeline.ai_spend_ledger (ledger_match splits a shared lane by source table or row value), its cascade of 1 to 4 models from pipeline.ai_model_catalogue, its daily US$ and calls caps (null = none), where its prompt is kept, and whether it is on. resolver = route: the reader asks security.ai_route_v1; anything else names where the model is still chosen until that reader is moved. Platform Admin 13 Nov 2026.';
alter table pipeline.ai_service_routes enable row level security;
revoke all on pipeline.ai_service_routes from anon, authenticated;

-- Seeds: the model each service uses today; a service on GPT-4.1 mini gets qwen3-30b first, then mistral-small-3.2. Caps come from the existing
-- per-lane settings where one exists (read here, not written as numbers); a lane shared by several services gives its guard to none of them
-- when the split has no setting of its own (null = no cap; the daily ceiling still holds every route).
insert into pipeline.ai_service_routes (service_code, label, area, field, lane, ledger_match, cascade, daily_usd_cap, daily_calls_cap, prompt_source, resolver, note, sort, reason)
select v.service_code, v.label, v.area, v.field, v.lane, v.ledger_match::jsonb, v.cascade, v.usd, v.calls, v.prompt_source, v.resolver, v.note, v.sort, 'seed 13 Nov 2026 (Platform Admin 19:14)'
from (select coalesce((select m.code from pipeline.central_ai_settings c join pipeline.ai_model_catalogue m on m.model_identifier = c.model_identifier and m.status = 'allowed' where c.id = 1), 'qwen3-30b') central,
             coalesce((select m.code from pipeline.ai_model_catalogue m where m.status = 'allowed' and m.model_identifier = (select s.value #>> '{}' from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'builder_model')), 'qwen3-30b') builder) d
cross join lateral (values
  ('course_description', 'Course description', 'Course fields', 'course_description', 'enrich_fields', '{"where": {"field": ["description"]}}',
     array[d.central], null::numeric, null::int, 'worker code: cdesc-source-grounded-v1', 'route',
     'The deployed worker reads one model for the description and the other course fields: while both flow it is this route''s first model.', 10),
  ('course_entry_requirements', 'Course entry requirements', 'Course fields', 'course_entry_requirements', 'enrich_fields', '{"where": {"field": ["entry_requirements"]}}',
     array['qwen3-30b', 'mistral-small-3.2'], null, null, 'worker code: course-entry-v1', 'route',
     'Was GPT-4.1 mini (setting entry.matrix_model). qwen3-30b has not been qualified on this prompt.', 20),
  ('course_other_fields', 'Other course fields (deadline, intakes, duration, campus, delivery, English)', 'Course fields', 'course_other_fields', 'enrich_fields',
     '{"where_not": {"field": ["description", "entry_requirements"]}}',
     array[d.central], null, null, 'worker code: course-fields-v1 (deadline: course-text-v2)', 'route',
     'The deployed worker reads one model for the description and the other course fields: this route''s model is used when the description route is held.', 30),
  ('entry_matrices', 'Entry requirement matrices (provider pages)', 'Entry requirements', null, 'entry_matrix', '{"source": ["entry_matrix_runs"]}',
     array['qwen3-30b', 'mistral-small-3.2'], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_entry_matrix'), null,
     'worker code: entry-matrix-v0.1.4', 'route', 'Was GPT-4.1 mini (setting entry.matrix_model). qwen3-30b has not been qualified on this prompt.', 40),
  ('entry_requirements_v2_shadow', 'Entry requirements v2 (shadow trial)', 'Entry requirements', null, 'entry_matrix', '{"source": ["aer_v2_shadow_results"]}',
     array['qwen3-30b', 'mistral-small-3.2'], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'aer.v2_shadow_daily_usd'), null,
     'pipeline.aer_prompt_versions', 'pipeline.aer_prompt_versions', 'The model is pinned on the prompt version (GPT-4.1 mini on aer-v2-course-v1). The trial is switched off (aer.v2_shadow_on).', 50),
  ('scholarship_extraction', 'Scholarship pages', 'Scholarships', null, 'scholarship_ai', '{"source": ["scholarship_ai_extractions", "scholarship_ai_reviews"]}',
     array['qwen3-30b', 'mistral-small-3.2'], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_scholarship_ai'), null,
     'pipeline.scholarship_ai_prompts', 'pipeline.scholarship_ai_extract_settings', 'The reader follows its own chain (Scholarships › AI reading). GPT-4.1 mini is taken out of that chain by this change.', 60),
  ('scholarship_eligibility', 'Scholarship eligibility', 'Scholarships', null, 'scholarship_ai', '{"source": ["scholarship_eligibility_reads"]}',
     array['qwen3-30b'], null, null, 'worker code: eligibility.ts', 'pipeline.scholarship_ai_extract_settings', 'Uses the first model of the scholarship chain.', 70),
  ('provider_description', 'Provider description', 'Providers', null, 'provider_description', null,
     array[d.central], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_provider_description'), null,
     'pipeline.provider_description_prompts', 'pipeline.central_ai_settings', 'Shares one model with the other central readers until its reader asks the route.', 80),
  ('calendar_reading', 'Intake calendars (central pages)', 'Central pages', null, 'central_ai', '{"where": {"kind": ["intake_calendar"]}}',
     array[d.central], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_central_ai'), null,
     'worker code: calendar-v2.4', 'pipeline.central_ai_settings', 'Shares one model with the other central readers until its reader asks the route.', 90),
  ('central_english_policy', 'English policy pages (central pages)', 'Central pages', null, 'central_ai', '{"where_not": {"kind": ["intake_calendar"]}}',
     array[d.central], null, null, 'worker code: provider-policy-v0.3.1', 'pipeline.central_ai_settings', 'Shares one model with the other central readers until its reader asks the route.', 100),
  ('fee_reader', 'Fees', 'Fees', null, 'fee_ai', null,
     array[d.central], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_fee_ai'), null,
     'worker code: fees.ts', 'pipeline.central_ai_settings', 'Shares one model with the other central readers until its reader asks the route.', 110),
  ('course_matching', 'Course-page matching', 'Course pages', null, 'course_match', null,
     array['qwen3-30b'], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_course_match'), null,
     'worker code: ai-match-v0.10.0', 'worker code', 'qwen/qwen3-30b-a3b-instruct-2507 is fixed in the worker (AI_MATCH_MODEL).', 120),
  ('adapter_builder', 'Adapter proposals', 'Adapters', null, 'adapter_builder', null,
     array[d.builder], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'builder_ai_daily_usd'),
     (select (s.value #>> '{}')::int from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'builder_proposals_per_day'),
     'worker code: builder.ts', 'firecrawl.builder_model', 'The model is the setting firecrawl.builder_model (a provider may have its own in pipeline.uni_adapter_models).', 130),
  ('ops_diagnosis', 'Operations diagnosis', 'Operations', null, 'ops_diagnose', null,
     array['qwen3-30b', 'mistral-small-3.2'], (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'ops.ai_diagnosis_usd_per_day'),
     (select (s.value #>> '{}')::int from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'ops.ai_requests_per_day'),
     'function public.svc_ops_diagnosis_next: ops-diagnose-v1', 'route', 'Was GPT-4.1 mini (setting ops.ai_diagnosis_model). Switched off (ops.ai_diagnosis_on).', 140)
) v(service_code, label, area, field, lane, ledger_match, cascade, usd, calls, prompt_source, resolver, note, sort)
on conflict (service_code) do nothing;

-- 3 the ledger: service and model beside the lane ---------------------------------------------------------------------------------------------
alter table pipeline.ai_spend_ledger add column if not exists service_code text;
alter table pipeline.ai_spend_ledger add column if not exists model text;
create index if not exists ai_spend_ledger_service_at_idx on pipeline.ai_spend_ledger (service_code, at);

-- 4 functions ------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.ai_ledger_service_v1(p_lane text, p_source text, p_row jsonb) returns text
language sql stable security definer set search_path = '' as $function$
  -- the service a cost belongs to: the lane, then ledger_match (source: the table that recorded it; where / where_not: values of that row)
  select r.service_code from pipeline.ai_service_routes r
   where r.lane = p_lane
     and (r.ledger_match is null or (
           (not (r.ledger_match ? 'source') or coalesce(r.ledger_match->'source' ? p_source, false))
       and not exists (select 1 from jsonb_each(coalesce(r.ledger_match->'where', '{}'::jsonb)) w where not coalesce(w.value ? (p_row->>w.key), false))
       and not exists (select 1 from jsonb_each(coalesce(r.ledger_match->'where_not', '{}'::jsonb)) w where coalesce(w.value ? (p_row->>w.key), false))))
   order by (r.ledger_match is null), r.sort, r.service_code limit 1
$function$;

create or replace function security.ai_route_v1(p_service text) returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
-- What a reader asks before it hands out AI work for a service. Held routes hand out nothing; what is already claimed finishes and records its cost.
declare r pipeline.ai_service_routes%rowtype; v_models jsonb; v_usd numeric; v_calls bigint; v_all numeric; v_ceiling numeric; v_reason text;
        v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';  -- fixed: the UTC day the AI guards count (security.ai_spend_today_v1)
begin
  select * into r from pipeline.ai_service_routes where service_code = p_service;
  if not found then
    return jsonb_build_object('service', p_service, 'models', '[]'::jsonb, 'model', null, 'cap', jsonb_build_object('usd', null, 'calls', null),
                              'spent_today', jsonb_build_object('usd', 0, 'calls', 0), 'held', true, 'held_kind', 'off', 'held_reason', 'unknown service: ' || coalesce(p_service, ''));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('code', m.code, 'model_identifier', m.model_identifier) order by c.ord), '[]'::jsonb) into v_models
    from unnest(r.cascade) with ordinality c(code, ord) join pipeline.ai_model_catalogue m on m.code = c.code and m.status = 'allowed';
  select coalesce(sum(l.cost_usd), 0), coalesce(sum(l.calls), 0) into v_usd, v_calls from pipeline.ai_spend_ledger l where l.at >= v_day and l.service_code = r.service_code;
  select coalesce(sum(l.cost_usd), 0) into v_all from pipeline.ai_spend_ledger l where l.at >= v_day;
  v_ceiling := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14);
  v_reason := case
    when not r.enabled then 'switched off (Models & services)'
    when jsonb_array_length(v_models) = 0 then 'no allowed model in the cascade'
    when v_ceiling > 0 and v_all >= v_ceiling then format('daily ceiling: US$%s spent today (UTC) across all AI services, ceiling US$%s (budgets.ai_daily_ceiling_usd)', round(v_all, 2), v_ceiling)
    when r.daily_usd_cap is not null and v_usd >= r.daily_usd_cap then format('service cap: US$%s spent today (UTC), cap US$%s', round(v_usd, 2), r.daily_usd_cap)
    when r.daily_calls_cap is not null and v_calls >= r.daily_calls_cap then format('service cap: %s calls today (UTC), cap %s', v_calls, r.daily_calls_cap)
  end;
  return jsonb_build_object('service', r.service_code, 'models', v_models, 'model', v_models#>>'{0,model_identifier}',
                            'cap', jsonb_build_object('usd', r.daily_usd_cap, 'calls', r.daily_calls_cap),
                            'spent_today', jsonb_build_object('usd', round(v_usd, 4), 'calls', v_calls),
                            'held', v_reason is not null,
                            -- off: switched off or no allowed model (holds everything). limit: the ceiling or a cap (holds scheduled work; on-demand work
                            -- is not held by limits, Platform Admin 12 Nov 2026 21:07, operating model 3.3.2)
                            'held_kind', case when v_reason is null then null when not r.enabled or jsonb_array_length(v_models) = 0 then 'off' else 'limit' end,
                            'held_reason', v_reason);
end $function$;

create or replace function security.ai_on_demand_providers_v1() returns uuid[]
language sql stable security definer set search_path = '' as $function$
  -- the providers of the on-demand requests open now for AI work (pipeline.on_demand_requests): their work is not held by a cap or the ceiling
  select coalesce(array_agg(distinct p.id), '{}'::uuid[]) from pipeline.on_demand_requests r cross join lateral unnest(r.provider_ids) p(id)
   where r.state = 'open' and r.expires_at > now() and 'openrouter' = any (r.toolsets)
$function$;

create or replace function security.ai_service_model_v1(p_service text) returns text
language sql stable security definer set search_path = '' as $function$
  -- the model in effect for a service today: from its route, or from the place its reader still reads (resolver)
  select case r.resolver
    when 'route' then (select m.model_identifier from unnest(r.cascade) with ordinality c(code, ord) join pipeline.ai_model_catalogue m on m.code = c.code and m.status = 'allowed' order by c.ord limit 1)
    when 'pipeline.central_ai_settings' then (select c.model_identifier from pipeline.central_ai_settings c where c.id = 1)
    when 'pipeline.scholarship_ai_extract_settings' then (select m.model_identifier from pipeline.scholarship_ai_extract_settings s join pipeline.scholarship_ai_models m on m.code = s.chain[1] where s.id = 1)
    when 'firecrawl.builder_model' then (select s.value #>> '{}' from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'builder_model')
    when 'pipeline.aer_prompt_versions' then (select v.model from pipeline.aer_prompt_versions v where v.status <> 'retired' order by v.created_at desc limit 1)
  end
  from pipeline.ai_service_routes r where r.service_code = p_service
$function$;

create or replace function security.ai_enrich_routes_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
-- The routes of the course field reader (lane enrich_fields) for public.svc_enrich_ai_next: each route as security.ai_route_v1 gives it, and
-- which fields are held. A route matched by where.field holds those fields; the route matched by where_not.field holds every other field
-- (rest). off_*: held for everything (switched off, no allowed model). limit_*: held by a cap or the ceiling (not for on-demand providers).
-- top: the route whose model the deployed worker uses for the description and the other fields (the first that is not switched off).
declare r record; v_rt jsonb; v_routes jsonb := '{}'::jsonb; v_held jsonb := '{}'::jsonb; v_off jsonb := '[]'::jsonb; v_lim jsonb := '[]'::jsonb; v_except jsonb := '[]'::jsonb;
        v_off_rest boolean := false; v_lim_rest boolean := false; v_top jsonb; v_top_free jsonb; v_f jsonb;
begin
  for r in select * from pipeline.ai_service_routes x where x.lane = 'enrich_fields' order by x.sort, x.service_code loop
    v_rt := security.ai_route_v1(r.service_code);
    v_routes := v_routes || jsonb_build_object(r.service_code, v_rt);
    v_f := r.ledger_match #> '{where,field}';
    if v_f is null then v_except := coalesce(r.ledger_match #> '{where_not,field}', '[]'::jsonb); end if;
    if (v_rt->>'held')::boolean then
      v_held := v_held || jsonb_build_object(r.service_code, v_rt->>'held_reason');
      if v_rt->>'held_kind' = 'off' then
        if v_f is not null then v_off := v_off || v_f; else v_off_rest := true; end if;
      else
        if v_f is not null then v_lim := v_lim || v_f; else v_lim_rest := true; end if;
      end if;
    elsif v_top_free is null and r.service_code <> 'course_entry_requirements' then v_top_free := v_rt;
    end if;
    if v_top is null and r.service_code <> 'course_entry_requirements' and coalesce(v_rt->>'held_kind', '') <> 'off' then v_top := v_rt; end if;
  end loop;
  return jsonb_build_object('routes', v_routes, 'held', v_held, 'off_fields', v_off, 'off_rest', v_off_rest, 'limit_fields', v_lim, 'limit_rest', v_lim_rest,
                            'rest_except', v_except, 'on_demand_providers', to_jsonb(security.ai_on_demand_providers_v1()),
                            'top', coalesce(v_top_free, v_top, v_routes->'course_description', '{}'::jsonb));
end $function$;

revoke all on function security.ai_ledger_service_v1(text, text, jsonb), security.ai_route_v1(text), security.ai_service_model_v1(text), security.ai_enrich_routes_v1(), security.ai_on_demand_providers_v1(), security.ai_model_family_trg() from public, anon, authenticated;

-- 5 the four guarded edits -------------------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.svc_enrich_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_lim int := greatest(1, least(coalesce(p_limit, 10), 40));
        -- 13 Nov 2026 (Platform Admin 19:14): the model and the budget of each field group come from its route (pipeline.ai_service_routes)
        v_r jsonb; v_top jsonb; v_off text[]; v_capf text[]; v_not text[]; v_off_rest boolean; v_cap_rest boolean; v_od uuid[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  v_r := security.ai_enrich_routes_v1();
  v_top := v_r->'top';
  v_off := array(select jsonb_array_elements_text(v_r->'off_fields')); v_capf := array(select jsonb_array_elements_text(v_r->'limit_fields'));
  v_not := array(select jsonb_array_elements_text(v_r->'rest_except'));
  v_off_rest := coalesce((v_r->>'off_rest')::boolean, false); v_cap_rest := coalesce((v_r->>'limit_rest')::boolean, false);
  v_od := array(select jsonb_array_elements_text(v_r->'on_demand_providers'))::uuid[];
  -- 22 Oct 2026 (Platform Admin 11:42): items of unpublished providers in automatic tasks (standing gap queue, automatic plans) are settled
  -- without the AI; the gap queue asks for them again once the provider is published (reason 'provider unpublished'). A task a person started runs.
  update pipeline.field_enrich_items e set state = 'skipped', reason = 'provider unpublished', leased_until = null, updated_at = now()
    from pipeline.admin_jobs j
   where j.id = e.job_id and e.state = 'ai' and (coalesce((j.args->>'standing')::boolean, false) or j.args->>'plan_mode' = 'auto')
     and exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id);
  with pick0 as (select e.id, e.job_id, e.course_id from pipeline.field_enrich_items e
                 where (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
                   and not (e.field = any(v_off)) and not (v_off_rest and not (e.field = any(v_not)))
                   and (e.provider_id = any(v_od) or (not (e.field = any(v_capf)) and not (v_cap_rest and not (e.field = any(v_not)))))  -- a held route hands out no work for its fields (a cap or the ceiling does not hold an on-demand provider)
                 order by e.job_id, (e.course_id is null), e.course_id, e.id limit v_lim for update skip locked),  -- a course's fields together
  -- CF-247 Release B (§6 priority 2): with enrich.multi_field_on, the rest of each leased course's due stored-page items of the same task too
  pick1 as (select e.id from pipeline.field_enrich_items e
             where security.pipeline_num_v1('enrich.multi_field_on', 1) >= 1 and e.source = 'ai_stored' and e.course_id is not null
               and (e.job_id, e.course_id) in (select p0.job_id, p0.course_id from pick0 p0 where p0.course_id is not null)
               and (e.state = 'ai' or (e.state = 'leased' and e.leased_until < now())) and e.attempts < 3
               and not (e.field = any(v_off)) and not (v_off_rest and not (e.field = any(v_not)))
                   and (e.provider_id = any(v_od) or (not (e.field = any(v_capf)) and not (v_cap_rest and not (e.field = any(v_not)))))
             for update skip locked),
  pick as (select p0.id from pick0 p0 union select p1.id from pick1 p1),
  upd as (update pipeline.field_enrich_items e set state = 'leased', leased_until = now() + make_interval(mins => 4), attempts = e.attempts + 1, updated_at = now()
            from pick where e.id = pick.id returning e.*)
  select jsonb_build_object('model', coalesce(v_top->>'model', ''), 'model_code', coalesce(v_top#>>'{models,0,code}', ''),
    'models', coalesce(v_top->'models', '[]'::jsonb), 'routes', v_r->'routes', 'held', v_r->'held',
    'pages', coalesce((select jsonb_agg(g.x) from (
                         select jsonb_build_object('course_id', u.course_id, 'storage_path', min(u.storage_path), 'title', min(c.canonical_title), 'provider', min(coalesce(p.display_name, p.canonical_name)),
                                  'items', jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field,
                                    'hint', case when u.reason = 'the quote is not on the page' then 'last time the quote given for this field was not found on the page' end))) x
                           from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id
                          where u.source = 'ai_stored' and u.course_id is not null group by u.course_id) g), '[]'::jsonb),
    'titles', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'field', u.field, 'title', c.canonical_title, 'level', sl.name, 'provider', coalesce(p.display_name, p.canonical_name)))
                        from upd u join catalogue.courses c on c.id = u.course_id join catalogue.providers p on p.id = u.provider_id left join ref.study_levels sl on sl.id = c.study_level_id
                       where u.source = 'ai_title'), '[]'::jsonb),
    'campus_lists', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'names', (select coalesce(jsonb_agg(jsonb_build_object('text', q, 'pages', n) order by n desc), '[]'::jsonb)
                                     from (select c.quote q, count(*) n from pipeline.field_enrich_items c where c.job_id = u.job_id and c.provider_id = u.provider_id and c.field = 'campus' and c.quote is not null group by c.quote order by 2 desc limit 80) z)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'campus_list'), '[]'::jsonb),
    'regions', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider', coalesce(p.display_name, p.canonical_name), 'country', k.name,
                         'cities', (select coalesce(jsonb_agg(distinct btrim(c2.city)), '[]'::jsonb) from catalogue.campuses c2
                                     where c2.provider_id = u.provider_id and c2.status = 'active' and c2.subdivision_id is null and nullif(btrim(c2.city), '') is not null),
                         'regions', (select coalesce(jsonb_agg(s2.name order by s2.name), '[]'::jsonb) from ref.subdivisions s2 where s2.country_id = p.country_id)))
                        from upd u join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id where u.field = 'campus_region'), '[]'::jsonb),
    'addresses', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'storage_path', u.storage_path,
                         'website', case when u.source = 'scraper' then p.website end, 'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id)))
                        from upd u join catalogue.providers p on p.id = u.provider_id where u.field = 'provider_address'), '[]'::jsonb),
    'entry', jsonb_build_object('model', coalesce(v_r#>>'{routes,course_entry_requirements,model}', ''), 'models', coalesce(v_r#>'{routes,course_entry_requirements,models}', '[]'::jsonb),
                                'page_chars', security.pipeline_num_v1('entry.course_page_chars', 100000)::int),  -- CF-247 Track C Step B: the entry model, from its route
    'fields', (select jsonb_agg(jsonb_build_object('code', f.code, 'name', f.name) order by f.code) from ref.fields_of_study f where f.code ~ '^asced-\d{4}$' and f.code !~ '00$'),
    'levels', (select jsonb_agg(jsonb_build_object('code', l.short_code, 'name', l.name) order by l.sort_order) from ref.study_levels l where l.short_code is not null))
    into v;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_entry_matrix_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_route jsonb := security.ai_route_v1('entry_matrices'); v_model text := v_route->>'model';  -- 13 Nov 2026: the route (pipeline.ai_service_routes)
        v_od uuid[] := security.ai_on_demand_providers_v1();
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 or not security.ai_use_allowed_v1('entry_matrix') then return '[]'::jsonb; end if;
  -- the route: switched off or no allowed model holds everything; a cap or the daily ceiling holds all but on-demand providers
  if v_model is null or v_route->>'held_kind' = 'off' or (coalesce((v_route->>'held')::boolean, true) and cardinality(v_od) = 0) then return '[]'::jsonb; end if;
  with pick as (select r.id from pipeline.entry_matrix_runs r
                 where (r.state = 'queued' or (r.state = 'leased' and r.leased_until < now()))
                   and r.attempts < security.pipeline_num_v1('entry.matrix_attempts', 3)
                   and security.entry_matrix_enabled_v1(r.provider_id)
                   and (not (v_route->>'held')::boolean or r.provider_id = any(v_od))
                 order by r.created_at limit greatest(1, least(coalesce(p_limit, 4), 20)) for update skip locked),
  upd as (update pipeline.entry_matrix_runs r set state = 'leased', leased_until = now() + interval '5 minutes',  -- fixed: lease timer
                 attempts = r.attempts + 1, model_code = v_model, updated_at = now() from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('run_id', u.id, 'source_id', u.source_id, 'provider_id', u.provider_id,
           'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'url', s.url, 'storage_path', e.storage_path, 'mime', e.mime_type,
           'model', v_model, 'model_code', split_part(v_model, '/', 2), 'models', v_route->'models',
           'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int,
           'max_tokens', security.pipeline_num_v1('entry.matrix_max_tokens', 8000)::int,
           'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,
           'slice_concurrency', security.pipeline_num_v1('entry.matrix_slice_concurrency', 1)::int,
           'pdf_max_pages', security.pipeline_num_v1('entry.pdf_max_pages', 40)::int,
           'completeness_required', security.entry_completeness_required_v1(u.provider_id))), '[]'::jsonb) into v
    from upd u join pipeline.entry_matrix_sources s on s.id = u.source_id join pipeline.evidence_artifacts e on e.id = s.evidence_id
    join catalogue.providers p on p.id = u.provider_id left join ref.countries k on k.id = p.country_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_ops_diagnosis_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Hands queued AI diagnosis requests to the worker while ops.ai_diagnosis_on is 1, within ops.ai_requests_per_day and while today's AI spend is
-- under budgets.ai_daily_ceiling_usd. Each comes with the pinned model and the context it may quote.
declare v jsonb; v_today int; v_room int; v_ref text; v_tz text := 'Australia/Melbourne';  -- fixed: the platform's reporting time zone
        v_route jsonb := security.ai_route_v1('ops_diagnosis');  -- 13 Nov 2026: the model and the service cap come from the route
begin
  if security.pipeline_num_v1('ops.ai_diagnosis_on', 0) < 1 then return jsonb_build_object('items', '[]'::jsonb, 'held', 'ops.ai_diagnosis_on is 0'); end if;
  if coalesce((v_route->>'held')::boolean, true) then return jsonb_build_object('items', '[]'::jsonb, 'held', coalesce(v_route->>'held_reason', 'the route is held')); end if;
  if (select coalesce(sum(t.spent), 0) from security.ai_spend_today_v1() t) >= security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'daily AI ceiling reached');
  end if;
  -- the lane's spend must count in the daily ceiling (security.ai_spend_today_v1 lists the lanes it sums)
  if not exists (select 1 from security.ai_spend_today_v1() t where t.use = 'ops_diagnose') then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'the ops_diagnose lane is not counted in the daily AI ceiling yet (security.ai_spend_today_v1)');
  end if;
  v_ref := security.ai_use_refusal_v1('ops_diagnose');  -- the existing guard: credit floor, daily ceiling, lane guard (stop mode)
  if v_ref is not null then return jsonb_build_object('items', '[]'::jsonb, 'held', v_ref); end if;
  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'ops_diagnose' and l.at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))  -- fixed: the UTC day the AI guards count
     >= security.pipeline_num_v1('ops.ai_diagnosis_usd_per_day', 0.5) then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'ops.ai_diagnosis_usd_per_day reached');
  end if;
  select count(*) into v_today from pipeline.ops_ai_diagnosis_requests q where q.state in ('leased', 'answered') and (q.requested_at at time zone v_tz)::date = (now() at time zone v_tz)::date;
  v_room := greatest(least(coalesce(p_limit, 1), security.pipeline_num_v1('ops.ai_requests_per_day', 20)::int - v_today), 0);
  with c as (select q.id from pipeline.ops_ai_diagnosis_requests q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())
              order by q.requested_at limit v_room for update skip locked)
  update pipeline.ops_ai_diagnosis_requests q set state = 'leased', leased_until = now() + interval '10 minutes',  -- fixed: lease timer
         model = v_route->>'model'
    from c where q.id = c.id;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'model', q.model, 'models', v_route->'models', 'lease_until', q.leased_until, 'contract', 'ops-diagnose-v1', 'context', q.context,
           'instructions', 'You diagnose one StudySearch integration issue from the context only. Choose exactly one root_cause from the codes in context.root_causes. '
                           || 'Give confidence from 0 to 1. Give evidence as short quotes copied exactly, character for character, from text values in the context (not paraphrased). '
                           || 'Do not propose actions, settings or code changes. Answer with one JSON object that matches response_schema and nothing else.',
           'response_schema', jsonb_build_object('type', 'object', 'required', jsonb_build_array('root_cause', 'confidence', 'evidence'), 'additionalProperties', false,
             'properties', jsonb_build_object(
               'root_cause', jsonb_build_object('type', 'string', 'enum', (select jsonb_agg(c.code order by c.code) from pipeline.ops_root_causes c)),
               'confidence', jsonb_build_object('type', 'number', 'minimum', 0, 'maximum', 1),
               'evidence', jsonb_build_object('type', 'array', 'minItems', 1, 'items', jsonb_build_object('type', 'string')),
               'reasoning', jsonb_build_object('type', 'string'))))), '[]'::jsonb) into v
    from pipeline.ops_ai_diagnosis_requests q where q.state = 'leased' and q.leased_until > now();
  return jsonb_build_object('items', v, 'contract', 'ops-diagnose-v1');
end $function$;

CREATE OR REPLACE FUNCTION security.ai_spend_capture_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Decision 5 E-7 (2 Nov 2026): records the AI cost a row gains. tg_argv: lane, how ('delta' = the increase of an accumulated cost;
-- 'decision' = the cost of each decision of a leased item, as svc_coverage_ai_match_record overwrites it), the path of the cost in the row.
declare v_new jsonb := to_jsonb(new); v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end; v_path text[] := tg_argv[2]::text[];
        v_add numeric; v_svc text; v_model text;
begin
  if tg_argv[1] = 'decision' then
    if tg_op = 'UPDATE' and not (v_old->>'state' = 'leased' and v_new->>'state' <> 'leased'
                                 and (v_new->>'decided_at') is distinct from (v_old->>'decided_at')) then return null; end if;
    v_add := coalesce((v_new #>> v_path)::numeric, 0);
  else
    v_add := coalesce((v_new #>> v_path)::numeric, 0) - coalesce((v_old #>> v_path)::numeric, 0);
  end if;
  if v_add > 0 then
    -- 13 Nov 2026: the service and the model beside the lane (usage by service and model). The model is the row's own when it has one,
    -- else the model in effect for the service; a failure here never stops the cost being recorded.
    begin
      v_svc := security.ai_ledger_service_v1(tg_argv[0], tg_table_name, v_new);
      v_model := coalesce(nullif(v_new->>'model', ''), nullif(v_new->>'model_identifier', ''), nullif(v_new->>'model_code', ''), security.ai_service_model_v1(v_svc));
    exception when others then v_svc := null; v_model := null;
    end;
    insert into pipeline.ai_spend_ledger(lane, source, source_id, cost_usd, service_code, model) values (tg_argv[0], tg_table_name, v_new->>'id', v_add, v_svc, v_model);
  end if;
  return null;
end $function$;

-- 7 pipeline.central_ai_settings.model_* stays equal to the routes that still read it ------------------------------------------------------------
create or replace function security.ai_central_sync_v1() returns void
language plpgsql security definer set search_path = '' as $function$
declare m record;
begin
  select c.code, c.model_identifier into m
    from pipeline.ai_service_routes r cross join lateral unnest(r.cascade) with ordinality x(code, ord)
    join pipeline.ai_model_catalogue c on c.code = x.code and c.status = 'allowed'
   where r.resolver = 'pipeline.central_ai_settings' order by r.sort, x.ord limit 1;
  if m.code is null then return; end if;  -- no allowed model: the central model is left as it is and the routes show as held
  update pipeline.central_ai_settings s set model_code = m.code, model_identifier = m.model_identifier, changed_at = now(),
         reason = 'Models & services: the central readers route' where s.id = 1 and s.model_identifier is distinct from m.model_identifier;
end $function$;

create or replace function security.ai_route_central_trg() returns trigger
language plpgsql security definer set search_path = '' as $function$
begin
  -- the central readers (central pages, calendars, fees, provider descriptions) still read one model: their routes keep one cascade
  if pg_trigger_depth() > 1 or new.resolver <> 'pipeline.central_ai_settings' then return null; end if;
  update pipeline.ai_service_routes r set cascade = new.cascade, changed_at = now(), changed_by = new.changed_by, reason = new.reason
   where r.resolver = 'pipeline.central_ai_settings' and r.service_code <> new.service_code and r.cascade is distinct from new.cascade;
  perform security.ai_central_sync_v1();
  return null;
end $function$;

create or replace function security.ai_central_settings_trg() returns trigger
language plpgsql security definer set search_path = '' as $function$
declare v_code text;
begin
  if new.model_identifier is not distinct from old.model_identifier then return new; end if;
  select m.code into v_code from pipeline.ai_model_catalogue m where m.model_identifier = new.model_identifier and m.status = 'allowed';
  if v_code is null then
    raise exception 'model % is not an allowed model (Models & services › Models)', new.model_identifier using errcode = '23514';
  end if;
  if pg_trigger_depth() = 1 then  -- changed on the old AI configuration card: the routes follow
    update pipeline.ai_service_routes r set cascade = (array[v_code] || array_remove(r.cascade, v_code))[1:4], changed_at = now(), changed_by = new.changed_by,  -- fixed: a cascade holds 4 models at most (table check)
           reason = coalesce(new.reason, 'central model changed')
     where r.resolver = 'pipeline.central_ai_settings' and r.cascade[1] is distinct from v_code;
  end if;
  return new;
end $function$;

create or replace function security.ai_model_status_trg() returns trigger
language plpgsql security definer set search_path = '' as $function$
begin
  if new.status is distinct from old.status then perform security.ai_central_sync_v1(); end if;
  return null;
end $function$;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'ai_route_central' and tgrelid = 'pipeline.ai_service_routes'::regclass) then
    create trigger ai_route_central after insert or update of cascade on pipeline.ai_service_routes for each row execute function security.ai_route_central_trg();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'ai_central_settings_allowed' and tgrelid = 'pipeline.central_ai_settings'::regclass) then
    create trigger ai_central_settings_allowed before update of model_identifier, model_code on pipeline.central_ai_settings for each row execute function security.ai_central_settings_trg();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'ai_model_status' and tgrelid = 'pipeline.ai_model_catalogue'::regclass) then
    create trigger ai_model_status after update of status on pipeline.ai_model_catalogue for each row execute function security.ai_model_status_trg();
  end if;
end $$;
revoke all on function security.ai_central_sync_v1(), security.ai_route_central_trg(), security.ai_central_settings_trg(), security.ai_model_status_trg() from public, anon, authenticated;

-- 8 the page: one read, two audited writes --------------------------------------------------------------------------------------------------------
create or replace function public.admin_ai_overview_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank();
        v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';  -- fixed: the UTC day the AI guards count
        v_bal record;
begin
  if auth.uid() is null or v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
  select o.remaining_usd, o.observed_at, o.payload into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  return jsonb_build_object(
    'can_control', v_rank >= 5,
    'day_start', v_day,
    'openrouter', jsonb_build_object(
      -- the key is an edge function secret (OPENROUTER_API_KEY); the database never holds it. A balance read inside the stale window proves it works.
      'key_present', coalesce(v_bal.observed_at > now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30)), false),
      'key_secret_name', 'OPENROUTER_API_KEY',
      'mode', (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'),
      'balance_usd', round(v_bal.remaining_usd, 2), 'balance_observed_at', v_bal.observed_at,
      'total_credits_usd', (coalesce(v_bal.payload->>'total_credits', v_bal.payload#>>'{data,total_credits}'))::numeric,
      'floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
      'low_warn_usd', (security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric,
      'daily_ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
      'spent_today_usd', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.at >= v_day),
      'settings', (select coalesce(jsonb_agg(jsonb_build_object('toolset', s.toolset_key, 'key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'kind', s.kind,
                            'min', s.min_value, 'max', s.max_value, 'unit', s.unit) order by s.toolset_key, s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.home = 'models_services' and s.home_group = 'openrouter')),
    'models', (select coalesce(jsonb_agg(jsonb_build_object('code', m.code, 'family', m.family, 'label', m.label, 'model_identifier', m.model_identifier,
                 'input_usd_per_mtok', m.input_usd_per_mtok, 'output_usd_per_mtok', m.output_usd_per_mtok, 'price_checked_at', m.price_checked_at,
                 'context_tokens', m.context_tokens, 'status', m.status, 'note', m.note, 'reason', m.reason, 'changed_at', m.changed_at,
                 'used_by', (select coalesce(jsonb_agg(r.service_code order by r.sort), '[]'::jsonb) from pipeline.ai_service_routes r where m.code = any(r.cascade)))
               order by m.status <> 'allowed', m.sort, m.code), '[]'::jsonb) from pipeline.ai_model_catalogue m),
    'services', (select coalesce(jsonb_agg(x.j order by x.sort, x.service_code), '[]'::jsonb) from (
       select r.sort, r.service_code, jsonb_build_object('service_code', r.service_code, 'label', r.label, 'area', r.area, 'field', r.field, 'lane', r.lane,
                'ledger_match', r.ledger_match, 'cascade', to_jsonb(r.cascade),
                'cascade_detail', (select coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'label', m.label, 'model_identifier', m.model_identifier, 'status', coalesce(m.status, 'unknown')) order by c.ord), '[]'::jsonb)
                                     from unnest(r.cascade) with ordinality c(code, ord) left join pipeline.ai_model_catalogue m on m.code = c.code),
                'daily_usd_cap', r.daily_usd_cap, 'daily_calls_cap', r.daily_calls_cap, 'enabled', r.enabled,
                'resolver', r.resolver, 'wired', r.resolver = 'route', 'model_in_effect', security.ai_service_model_v1(r.service_code),
                'note', r.note, 'reason', r.reason, 'changed_at', r.changed_at, 'changed_by', (select u.email from auth.users u where u.id = r.changed_by),
                'models', rt.j->'models', 'spent_today', rt.j->'spent_today', 'held', rt.j->'held', 'held_kind', rt.j->'held_kind', 'held_reason', rt.j->'held_reason',
                'prompt', case
                  when r.prompt_source = 'pipeline.provider_description_prompts' then (select jsonb_build_object('source', r.prompt_source, 'version', p.version::text, 'text', left(p.system_prompt, 4000))  -- fixed: the page shows the first 4000 characters
                          from pipeline.provider_description_prompts p where p.status = 'active' order by p.version desc limit 1)
                  when r.prompt_source = 'pipeline.scholarship_ai_prompts' then (select jsonb_build_object('source', r.prompt_source, 'version', p.version::text, 'text', left(p.text, 4000))  -- fixed: as above
                          from pipeline.scholarship_ai_prompts p where p.active order by p.version desc limit 1)
                  when r.prompt_source = 'pipeline.aer_prompt_versions' then (select jsonb_build_object('source', r.prompt_source, 'version', p.version, 'text', left(p.system_text, 4000))  -- fixed: as above
                          from pipeline.aer_prompt_versions p where p.status <> 'retired' order by p.created_at desc limit 1)
                  else jsonb_build_object('source', split_part(r.prompt_source, ': ', 1), 'version', nullif(split_part(r.prompt_source, ': ', 2), ''), 'text', null) end,
                'settings', (select coalesce(jsonb_agg(jsonb_build_object('toolset', s.toolset_key, 'key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'kind', s.kind,
                               'min', s.min_value, 'max', s.max_value, 'unit', s.unit) order by s.toolset_key, s.sort, s.key), '[]'::jsonb)
                               from pipeline.platform_toolset_settings s where s.home = 'models_services' and s.home_group = r.service_code)) j
         from pipeline.ai_service_routes r cross join lateral (select security.ai_route_v1(r.service_code) j) rt) x),
    'legacy_controls', jsonb_build_object(
      'central_ai_settings', (select jsonb_build_object('enabled', c.enabled, 'calls_at_once', c.calls_at_once, 'model_code', c.model_code, 'model_identifier', c.model_identifier,
                                 'reason', c.reason, 'changed_at', c.changed_at, 'write', 'public.admin_ai_config') from pipeline.central_ai_settings c where c.id = 1),
      'scholarship_chain', (select jsonb_build_object('chain', to_jsonb(s.chain), 'reason', s.reason, 'changed_at', s.changed_at, 'write', 'public.admin_scholarship_ai')
                              from pipeline.scholarship_ai_extract_settings s where s.id = 1)),
    'usage', jsonb_build_object(
      'by_day_14d', (select coalesce(jsonb_agg(jsonb_build_object('day', u.d, 'service_code', u.svc, 'lane', u.lane, 'model', u.model, 'usd', u.usd, 'calls', u.calls) order by u.d desc, u.usd desc), '[]'::jsonb)
                       from (select (l.at at time zone 'UTC')::date d, l.service_code svc, l.lane, l.model, round(sum(l.cost_usd), 4) usd, sum(l.calls) calls
                               from pipeline.ai_spend_ledger l where l.at >= v_day - interval '13 days'  -- fixed: the page's 14-day usage window
                              group by 1, 2, 3, 4) u),
      'by_hour_24h', (select coalesce(jsonb_agg(jsonb_build_object('hour', u.h, 'service_code', u.svc, 'lane', u.lane, 'model', u.model, 'usd', u.usd, 'calls', u.calls) order by u.h desc, u.usd desc), '[]'::jsonb)
                        from (select date_trunc('hour', l.at) h, l.service_code svc, l.lane, l.model, round(sum(l.cost_usd), 4) usd, sum(l.calls) calls
                                from pipeline.ai_spend_ledger l where l.at >= date_trunc('hour', now()) - interval '23 hours'  -- fixed: the page's 24-hour usage window
                               group by 1, 2, 3, 4) u)),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'detail', e.detail, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
                 from (select * from pipeline.admin_control_events where area = 'ai_models' order by created_at desc limit 20) e left join auth.users u on u.id = e.actor));
end $function$;

create or replace function public.admin_ai_model_set_v1(p_code text, p_status text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare v_before text; v_reason text := btrim(coalesce(p_reason, ''));
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_status is null or p_status not in ('allowed', 'not_allowed') then raise exception 'status must be allowed or not_allowed'; end if;
  select m.status into v_before from pipeline.ai_model_catalogue m where m.code = p_code for update;
  if v_before is null then raise exception 'model % is not in the list', p_code; end if;
  update pipeline.ai_model_catalogue set status = p_status, reason = v_reason, changed_at = now(), changed_by = auth.uid() where code = p_code;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'model_status', p_code, jsonb_build_object('before', v_before, 'after', p_status, 'reason', v_reason,
            'services', (select coalesce(jsonb_agg(r.service_code order by r.sort), '[]'::jsonb) from pipeline.ai_service_routes r where p_code = any(r.cascade))), auth.uid());
  return public.admin_ai_overview_v1();
end $function$;

create or replace function public.admin_ai_route_set_v1(p_service text, p_cascade text[], p_daily_usd_cap numeric, p_daily_calls_cap integer, p_enabled boolean, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $function$
-- Saves a service route whole: the cascade, both caps (null = no cap) and the switch (null keeps it). Every change is logged with its reason.
declare r pipeline.ai_service_routes%rowtype; v_reason text := btrim(coalesce(p_reason, '')); v_bad text;
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into r from pipeline.ai_service_routes where service_code = p_service for update;
  if not found then raise exception 'service % is not in the list', p_service; end if;
  if p_cascade is null or cardinality(p_cascade) = 0 then raise exception 'the cascade is empty: name at least one allowed model'; end if;
  if cardinality(p_cascade) > 4 then raise exception 'a cascade holds 4 models at most'; end if;  -- fixed: the table check
  if (select count(distinct c) from unnest(p_cascade) c) <> cardinality(p_cascade) then raise exception 'the cascade names a model twice'; end if;
  select string_agg(c.code, ', ') into v_bad from unnest(p_cascade) c(code) where not exists (select 1 from pipeline.ai_model_catalogue m where m.code = c.code);
  if v_bad is not null then raise exception 'unknown model in the cascade: %', v_bad; end if;
  select string_agg(c.code, ', ') into v_bad from unnest(p_cascade) c(code) join pipeline.ai_model_catalogue m on m.code = c.code and m.status <> 'allowed';
  if v_bad is not null then raise exception 'not an allowed model: % (Models & services › Models)', v_bad; end if;
  if p_daily_usd_cap < 0 or p_daily_calls_cap < 0 then raise exception 'a cap cannot be negative (leave it empty for no cap)'; end if;
  update pipeline.ai_service_routes set cascade = p_cascade, daily_usd_cap = p_daily_usd_cap, daily_calls_cap = p_daily_calls_cap, enabled = coalesce(p_enabled, enabled),
         reason = v_reason, changed_at = now(), changed_by = auth.uid() where service_code = p_service;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_set', p_service, jsonb_build_object(
            'before', jsonb_build_object('cascade', to_jsonb(r.cascade), 'daily_usd_cap', r.daily_usd_cap, 'daily_calls_cap', r.daily_calls_cap, 'enabled', r.enabled),
            'after', jsonb_build_object('cascade', to_jsonb(p_cascade), 'daily_usd_cap', p_daily_usd_cap, 'daily_calls_cap', p_daily_calls_cap, 'enabled', coalesce(p_enabled, r.enabled)),
            'resolver', r.resolver, 'reason', v_reason), auth.uid());
  return public.admin_ai_overview_v1();
end $function$;

revoke all on function public.admin_ai_overview_v1(), public.admin_ai_model_set_v1(text, text, text), public.admin_ai_route_set_v1(text, text[], numeric, integer, boolean, text) from public, anon;
grant execute on function public.admin_ai_overview_v1(), public.admin_ai_model_set_v1(text, text, text), public.admin_ai_route_set_v1(text, text[], numeric, integer, boolean, text) to authenticated, service_role;

-- 9 data ------------------------------------------------------------------------------------------------------------------------------------------
-- 9a GPT-4.1 mini leaves the scholarship chain (Platform Admin 19:23: "stop ... any other setting using GPT mini now"). With no next model an
--    unproven fact goes to a person, as it does today when the chain ends. Nothing is switched on or off.
with ch as (
  update pipeline.scholarship_ai_extract_settings s set chain = array_remove(s.chain, 'gpt-4.1-mini'), changed_at = now(),
         reason = 'Platform Admin 13 Nov 2026 19:23: GPT-4.1 mini is not used any more (migration 20261113380000)'
   where s.id = 1 and 'gpt-4.1-mini' = any(s.chain) and cardinality(array_remove(s.chain, 'gpt-4.1-mini')) >= 1
  returning s.chain)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'ai_models', 'scholarship_chain', 'pipeline.scholarship_ai_extract_settings',
       jsonb_build_object('after', to_jsonb(ch.chain), 'removed', 'gpt-4.1-mini', 'reason', 'Platform Admin 13 Nov 2026 19:23', 'migration', '20261113380000'), null from ch;

-- 9a2 the central model leaves a model that is not allowed (it was qwen3-30b when this was written, so this changes nothing then)
select security.ai_central_sync_v1();

-- 9b the rows already in the ledger get their service (not their model), so today's spend counts against each route from the first minute
update pipeline.ai_spend_ledger l
   set service_code = security.ai_ledger_service_v1(l.lane, l.source, case
         when l.source = 'field_enrich_items' and l.source_id ~ '^\d+$' then coalesce((select jsonb_build_object('field', e.field) from pipeline.field_enrich_items e where e.id = l.source_id::bigint), '{}'::jsonb)
         when l.source = 'central_ai_queue' and l.source_id ~ '^\d+$' then coalesce((select jsonb_build_object('kind', q.kind) from pipeline.central_ai_queue q where q.id = l.source_id::bigint), '{}'::jsonb)
         else '{}'::jsonb end)
 where l.service_code is null;

-- 9c the settings that belong to Models & services: two columns beside (taken last, so the lock on the settings table is short), then the marks
alter table pipeline.platform_toolset_settings add column if not exists home text;
alter table pipeline.platform_toolset_settings add column if not exists home_group text;
comment on column pipeline.platform_toolset_settings.home is 'The screen a setting belongs to when it is not the Settings register: models_services = shown and edited on Models & services (13 Nov 2026). Null = Settings.';
comment on column pipeline.platform_toolset_settings.home_group is 'With home = models_services: the service (pipeline.ai_service_routes.service_code) the setting belongs to, or openrouter for the key, credit and ceiling.';
-- marked, not moved: the Settings register still lists them until the page change
with m(toolset, pat, grp) as (values
  ('openrouter', '.', 'openrouter'),
  ('pipeline', '^budgets\.ai_', 'openrouter'),
  ('pipeline', '^targets\.ai_credit_min_usd$', 'openrouter'),
  ('firecrawl', '^builder_(model|model_profile|ai_daily_usd|proposals_per_day)$', 'adapter_builder'),
  ('pipeline', '^reading\.answer_tokens\.adapter_proposal', 'adapter_builder'),
  ('pipeline', '^entry\.matrix_(model|enabled|max_tokens|slice_chars|slice_concurrency|attempts|max_rows_per_page)$', 'entry_matrices'),
  ('pipeline', '^enrich\.course_entry_', 'course_entry_requirements'),
  ('pipeline', '^entry\.course_(page_chars|read_cost_usd)$', 'course_entry_requirements'),
  ('pipeline', '^(enrich\.course_text_items_per_day|reading\.answer_tokens\.course_text)$', 'course_description'),
  ('pipeline', '^enrich\.(ai_calls_at_once|ai_items_per_call|ai_pages_at_once)$', 'course_other_fields'),
  ('pipeline', '^reading\.answer_tokens\.(course_fields|course_titles|campus_lists|campus_regions|provider_address)$', 'course_other_fields'),
  ('pipeline', '^aer\.v2_shadow_(on|budget_usd|daily_usd)$', 'entry_requirements_v2_shadow'),
  ('pipeline', '^reading\.aer_v2_(max_tokens|page_chars|concurrency)$', 'entry_requirements_v2_shadow'),
  ('pipeline', '^pdesc\.(ai_usd_max|enabled|read_cost_floor_usd|prompt_.*)$', 'provider_description'),
  ('pipeline', '^reading\.answer_tokens\.provider_description$', 'provider_description'),
  ('pipeline', '^(ops|har)\.ai_', 'ops_diagnosis'),
  ('pipeline', '^reading\.answer_tokens\.ops_diagnosis$', 'ops_diagnosis'),
  ('pipeline', '^reading\.answer_tokens\.scholarship_(page|recheck)$', 'scholarship_extraction'),
  ('pipeline', '^(reread\.scholarship_ai_days|retry\.sch_ai_wait_minutes|sch_ai\.wait_max_days|batch\.sch_ai_pick_scan|batch\.scholarship_recheck)$', 'scholarship_extraction'),
  ('pipeline', '^reading\.answer_tokens\.central_page$', 'central_english_policy'),
  ('pipeline', '^reading\.calendar_(answer_tokens|max_slices|slice_chars)$', 'calendar_reading'),
  ('pipeline', '^(reading\.answer_tokens\.fee_page|fees\.findings_in_prompt)$', 'fee_reader'),
  ('pipeline', '^(reading\.answer_tokens\.course_page_match|batch\.ai_match|concurrency\.ai_match|ai_match\.min_candidates)$', 'course_matching'))
update pipeline.platform_toolset_settings s set home = 'models_services', home_group = m.grp
  from m where s.toolset_key = m.toolset and s.key ~ m.pat and (s.home is distinct from 'models_services' or s.home_group is distinct from m.grp);

-- 9d the two model settings are no longer read (kept; their values are not changed)
update pipeline.platform_toolset_settings s
   set used_by = 'not read since migration 20261113380000 (13 Nov 2026): the model is chosen on Models & services (pipeline.ai_service_routes, service ' || v.svc || '). Was: ' || coalesce(s.used_by, '')
  from (values ('entry.matrix_model', 'entry_matrices and course_entry_requirements'), ('ops.ai_diagnosis_model', 'ops_diagnosis')) v(key, svc)
 where s.toolset_key = 'pipeline' and s.key = v.key and coalesce(s.used_by, '') not like 'not read since migration 20261113380000%';

-- 9e the register: the new tables, and the note on the table whose model columns now follow the routes
insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, replaced_by, introduced_in, retire_after) values
  ('table', 'pipeline.ai_model_catalogue', 'Platform', 'Models & services', 'The one list of AI models: family, OpenRouter id, price, allowed or not', 'active', '{}', null, '20261113380000', null),
  ('table', 'pipeline.ai_service_routes', 'Platform', 'Models & services', 'One route per AI service: cascade, daily caps, prompt source, switch',
     'active', array['setting pipeline entry.matrix_model', 'setting pipeline ops.ai_diagnosis_model'], null, '20261113380000', null)
on conflict (kind, name) do update set purpose = excluded.purpose, replaces = excluded.replaces, introduced_in = excluded.introduced_in, updated_at = now();
update pipeline.component_register set note = 'model_code and model_identifier follow the central readers'' routes in pipeline.ai_service_routes by trigger (20261113380000); the course field reader no longer reads them. enabled and calls_at_once are still set here.', updated_at = now()
 where kind = 'table' and name = 'pipeline.central_ai_settings';

-- 10 post-check -----------------------------------------------------------------------------------------------------------------------------------
do $post$
declare v text;
begin
  select string_agg(r.service_code || ':' || c.code, ', ') into v from pipeline.ai_service_routes r cross join lateral unnest(r.cascade) c(code)
   where not exists (select 1 from pipeline.ai_model_catalogue m where m.code = c.code and m.status = 'allowed');
  if v is not null then raise exception 'post-check: a seeded cascade names a model that is not allowed: %', v; end if;
  if exists (select 1 from pipeline.ai_service_routes r where r.resolver = 'route' and security.ai_route_v1(r.service_code)->>'model' is null) then
    raise exception 'post-check: a wired route resolves to no model';
  end if;
  select string_agg(distinct m.model_identifier, ', ') into v from pipeline.ai_service_routes r cross join lateral unnest(r.cascade) c(code)
    join pipeline.ai_model_catalogue m on m.code = c.code where m.model_identifier ~ '^(openai|anthropic)/';
  if v is not null then raise exception 'post-check: a route names %', v; end if;
  if exists (select 1 from pipeline.central_ai_settings c where c.id = 1 and not exists (select 1 from pipeline.ai_model_catalogue m where m.model_identifier = c.model_identifier and m.status = 'allowed')) then
    raise notice 'pipeline.central_ai_settings holds a model that is not allowed; the central routes show it as the model in effect';
  end if;
end $post$;
