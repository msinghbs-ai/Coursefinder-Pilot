-- CF-247 AI spend control, phase 2: the route is the only place a model is chosen. Every AI service's reader asks security.ai_route_v1, so the
-- Models & services page never shows a route that is not enforced.
-- Platform Admin 13 Nov 2026 19:14: "GPT 4.1 mini is too expensive it has exhausted the AI credit. use other cheaper model and define the usage per
--   field in ui under Model and Services ... Model classified that can be used - Qwen3, Mimo, mistral small, Kimi K2, Gemini, LLama, deepseek and
--   then Service based Model with cascading, Then Recent usage, remove/retire all other older scripts"; 19:15: "Keep prompt respective for each
--   service as well"; 19:23: "stop the entry requirement or any other setting using GPT mini now. all settings corresponding to model using AI
--   model/prompt or services should be defined in Model & services".
-- Root cause this closes: GPT-4.1 mini was pinned in pipeline.central_ai_settings (12 Oct) and in the setting entry.matrix_model (26 Oct) by build
-- sessions, outside the Platform Admin's cascade. After this change a model can be named in one place only, and security.ai_route_guard_v1()
-- lists anything that names one elsewhere.
-- Needs migration 20261113380000 (phase 1) applied first.
-- 6 pipeline.scholarship_ai_models holds every allowed catalogue model (the scholarship queue's model_code has a foreign key to it), kept in step by
--   a trigger on the catalogue; the first model of the scholarship route is 'active' there and the others 'candidate' (a copy of the route, as the
--   chain is; it activates nothing by itself). Queued scholarship reads that name a model that is not allowed are re-pointed to the route's
--   first model (counted in a notice; nothing is deleted).
-- 7 public.admin_settings_register_read and public.admin_toolsets_read return home and home_group with each setting (additive keys).
-- 8 Round 4 (Platform Admin review 13 Nov 2026 22:10): every service has a migration_state (routed, routed_single, not_migrated) and a
--   routed_single service cannot be saved with more than one model; public.admin_ai_qualification_set_v1 records a qualification (Platform Admin,
--   audited; it switches nothing on); public.svc_ai_model_answered_v1 also keeps every model call attempt (pipeline.ai_invocations), removed
--   after retention.ai_invocations_days by the existing daily job (security.ledger_retention_v1); the page read is open to rank 3 (read-only,
--   no key details), says the mode and what would hold, and carries the scholarship reading configuration.
-- Locks this migration takes on tables that exist before it (no ACCESS EXCLUSIVE; it adds no column):
--   pipeline.scholarship_ai_extract_settings   SHARE ROW EXCLUSIVE (create trigger: writes wait for the commit, reads do not), then ROW EXCLUSIVE
--   pipeline.ai_model_catalogue                 SHARE ROW EXCLUSIVE (create trigger; the table is new in phase 1)
--   pipeline.ai_service_routes, pipeline.scholarship_ai_models, pipeline.scholarship_ai_queue (the few rows naming a model that is not allowed),
--   pipeline.central_ai_settings, pipeline.platform_toolset_settings (one new row, one used_by line), pipeline.component_register   ROW EXCLUSIVE
--   everything else is read (ACCESS SHARE). The 22 replaced functions take no table lock.
--
-- 1 The nine services that did not ask the route now do (each md5-guarded; worker-facing keys keep their names and types; `models` is new beside
--   them; each is held by its route's switch, its cap and the daily ceiling as phase 1 holds; a cap or the ceiling does not hold on-demand work):
--     fees                    public.svc_fee_ai_next
--     central pages           public.svc_central_ai_next (intake calendars and English policy pages each have their own route now)
--     provider description    public.svc_provider_description_next, svc_provider_description_reserve_v1, security.provider_description_selection_v1
--     scholarships            public.svc_scholarship_ai_next, svc_scholarship_ai_record, svc_scholarship_eligibility_next, svc_scholarship_recheck_next,
--                             security.scholarship_ai_active_v1, scholarship_ai_next_model_v1: the route's cascade is the chain ("unproven goes to
--                             the next model, then a person" is unchanged). pipeline.scholarship_ai_extract_settings.chain is kept as a copy of the
--                             route for the screens that still show it and can no longer be edited directly.
--     adapter proposals       security.adapter_builder_model_for_v1, adapter_builder_models_v1, adapter_builder_budget
--     entry requirements v2   security.aer_v2_shadow_hold_v1, public.svc_aer_v2_shadow_record: the model is the route's; the prompt version keeps
--                             its text and sha
--     course-page matching    public.svc_coverage_ai_match_next hands out the route's model and cascade (it was fixed in the worker)
--     page identity           a new route, page_identity (allowed models only)
--     security.ai_model_pinned_ok_v1: a model is pinned-ok when the catalogue lists it as allowed
--   pipeline.central_ai_settings.model_* is written only as a copy of the intake calendar route, for the screens that still show it; a direct
--   change (the old AI configuration card, public.admin_ai_config) is refused with a message pointing to Models & services.
-- 2 Every route has a daily US$ cap (required by the table since phase 1, where the five integrator seeds are stated); public.admin_ai_route_set_v1
--   refuses a save without one. page_identity is seeded 1, by the integrator, pending the Platform Admin's value.
-- 3 pipeline.field_enrich_items.model (column from 20261113379000): the model that answered each course field (public.svc_enrich_ai_record), so the
--   spend ledger carries the real model. public.svc_ai_model_answered_v1 lets the worker correct the ledger's model when a later model of the cascade answered.
-- 4 security.ai_route_guard_v1() (read-only): functions that name a model identifier, text settings that hold one, cascades naming a model that is
--   not allowed.
-- 5 public.admin_ai_overview_v1: every service carries enforced, its first model and its prompt; `legacy.layer3` reports the Layer 3 profiles
--   still switched on (Layer 3 was retired on 12 Oct 2026 and is not wired to the routes).
--
-- Live definitions this change replaces (md5 of pg_get_functiondef, read 13 Nov 2026 about 20:20 AEDT; before -> after):
--   public.svc_fee_ai_next(integer)  f18fa0ef8454803ef0990e42c2e653d7 -> bf6ec0c89a535508e83ba0ff1e38b6cf
--   public.svc_central_ai_next(integer)  c085a8253b6db65c55773dca02e620ac -> 255f8ff7108bb19a719630b72f576228
--   public.svc_provider_description_next(integer)  16d8baa4faf83ec9c6471d63774c2531 -> f7b463e1df56305e32404c73493781b6
--   public.svc_provider_description_reserve_v1(uuid,text,numeric,text)  10abae09be0f865d0eba4d45a6da6049 -> df2ef6b8fc11e845525f2f49f7a145d9
--   security.provider_description_selection_v1(jsonb)  55924745a938cd02dfdb52d2bff606fe -> fc03bf02372ce16efd9c12e5cea55ae0
--   public.svc_scholarship_ai_next(integer)  8b24b21a104963db0e2a9429ca03b627 -> b563f09b94dda390caac48f2c1e9a8a6
--   public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)  736fe3f1d0eb22407eb4d5c586df3bd5 -> cbcf286f7d5cdd916aee7bb34ca52bc4
--   public.svc_scholarship_eligibility_next(integer)  309668330f2c434ff7ef047b5941a0a3 -> c6d57cba0c9101d080e682599af32e9b
--   public.svc_scholarship_recheck_next(integer)  ccfaf9a9c6bbba4ce5fde64a3d7738af -> 5a0aba814bfda17a7da7ba8273fd1cb4
--   security.aer_v2_shadow_hold_v1()  b8d1f95c8a171c5346d2a4c88c9adbb3 -> 84dd6a5cb62b79e92d918f3314f579a9
--   public.svc_aer_v2_shadow_record(uuid,text,text,uuid,text,jsonb,jsonb,jsonb,numeric,text,text)  43cceaf0ca4e33f7dc9a724eb5b2f22a -> b9b470c621b36d072328a1b4ac7db1cf
--   public.svc_coverage_ai_match_next(integer)  5a8176270c18994ef3564a5f59a9ff60 -> 64129c1e8aa79984939c2d8781c60aab
--   public.svc_enrich_ai_record(jsonb)  bcbfc91ce997b1516d90b1320264fa12 -> bbd61b2798896f1e592577766ffaab02
--   public.admin_settings_register_read()  4fb9bae7b10132e965a39c9cc8d04b4b -> c3e4f273e08c7b348da6de1764205fc8
--   public.admin_toolsets_read()  c54f956cedc46cb6e18d8122d2d14c9b -> df2380c6d541db3756bcc88c5e62641a
--   security.ledger_retention_v1()  d9f7df569b5bd1a975fc13fee5ef0b55 -> 3c2e418e4cb7451d616efde45f2c9861
--   public.admin_provider_description_run_v1(text,jsonb)  74ea2ec5577cef7370c03327881d6cb8 -> 225892e00395b3c03a8532b47d4ccfbb
--   security.scholarship_ai_active_v1()  74a1d5993a35b209ffbaa177ee6eec13 -> 4984eaf9195e1e6da5007af84856faf4
--   security.scholarship_ai_next_model_v1(text)  e69e857eff40d3d2d1c1e03d981ee1cd -> 061cb6e6bfe5d85a6f747d0b96b15a5d
--   security.adapter_builder_model_for_v1(uuid)  eaf3a8ba8ba0d21e3f03795773ad12f3 -> 2aa0c60d8bd996394b3fa2674aa3b122
--   security.adapter_builder_models_v1()  2dca9fed779ceb5c4020d48f2b5451f9 -> 060d7488bc4ebd37e997611cf8cf04ea
--   security.adapter_builder_budget()  7871e4b5612d275ec05c2f3a8ee28181 -> ba9a37041952d16dac3934bd8603890b
--   security.ai_model_pinned_ok_v1(text)  c19ca34d9fafbebbe35c505f17974a22 -> 8640931456f763088b222e6a17028fed
--
-- Replaces: the model choice of pipeline.central_ai_settings.model_* (fees, central pages, provider descriptions), of
--   pipeline.scholarship_ai_extract_settings.chain, of the settings firecrawl.builder_model / builder_model_profile and pipeline.uni_adapter_models
--   (a provider's own model is kept only when the route's cascade names it), of pipeline.aer_prompt_versions.model, and of the worker constants
--   AI_MATCH_MODEL and PAGE_ID_MODELS, with pipeline.ai_service_routes.
-- Retires: nothing is dropped. The replaced columns and settings stay as copies or unread values; their used_by lines and the register say so.

do $guard$
declare r record;
begin
  if to_regprocedure('security.ai_route_v1(text)') is null then raise exception 'migration 20261113380000 (AI models and services, phase 1) must be applied before this change'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'pipeline' and table_name = 'field_enrich_items' and column_name = 'model') then
    raise exception 'migration 20261113379000 (the item model column) must be applied before this change';
  end if;
  for r in select * from (values
      ('public.svc_fee_ai_next(integer)', 'f18fa0ef8454803ef0990e42c2e653d7', 'bf6ec0c89a535508e83ba0ff1e38b6cf'),
      ('public.svc_central_ai_next(integer)', 'c085a8253b6db65c55773dca02e620ac', '255f8ff7108bb19a719630b72f576228'),
      ('public.svc_provider_description_next(integer)', '16d8baa4faf83ec9c6471d63774c2531', 'f7b463e1df56305e32404c73493781b6'),
      ('public.svc_provider_description_reserve_v1(uuid,text,numeric,text)', '10abae09be0f865d0eba4d45a6da6049', 'df2ef6b8fc11e845525f2f49f7a145d9'),
      ('security.provider_description_selection_v1(jsonb)', '55924745a938cd02dfdb52d2bff606fe', 'fc03bf02372ce16efd9c12e5cea55ae0'),
      ('public.svc_scholarship_ai_next(integer)', '8b24b21a104963db0e2a9429ca03b627', 'b563f09b94dda390caac48f2c1e9a8a6'),
      ('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)', '736fe3f1d0eb22407eb4d5c586df3bd5', 'cbcf286f7d5cdd916aee7bb34ca52bc4'),
      ('public.svc_scholarship_eligibility_next(integer)', '309668330f2c434ff7ef047b5941a0a3', 'c6d57cba0c9101d080e682599af32e9b'),
      ('public.svc_scholarship_recheck_next(integer)', 'ccfaf9a9c6bbba4ce5fde64a3d7738af', '5a0aba814bfda17a7da7ba8273fd1cb4'),
      ('security.aer_v2_shadow_hold_v1()', 'b8d1f95c8a171c5346d2a4c88c9adbb3', '84dd6a5cb62b79e92d918f3314f579a9'),
      ('public.svc_aer_v2_shadow_record(uuid,text,text,uuid,text,jsonb,jsonb,jsonb,numeric,text,text)', '43cceaf0ca4e33f7dc9a724eb5b2f22a', 'b9b470c621b36d072328a1b4ac7db1cf'),
      ('public.svc_coverage_ai_match_next(integer)', '5a8176270c18994ef3564a5f59a9ff60', '64129c1e8aa79984939c2d8781c60aab'),
      ('public.svc_enrich_ai_record(jsonb)', 'bcbfc91ce997b1516d90b1320264fa12', 'bbd61b2798896f1e592577766ffaab02'),
      ('public.admin_settings_register_read()', '4fb9bae7b10132e965a39c9cc8d04b4b', 'c3e4f273e08c7b348da6de1764205fc8'),
      ('public.admin_toolsets_read()', 'c54f956cedc46cb6e18d8122d2d14c9b', 'df2380c6d541db3756bcc88c5e62641a'),
      ('security.ledger_retention_v1()', 'd9f7df569b5bd1a975fc13fee5ef0b55', '3c2e418e4cb7451d616efde45f2c9861'),
      ('public.admin_provider_description_run_v1(text,jsonb)', '74ea2ec5577cef7370c03327881d6cb8', '225892e00395b3c03a8532b47d4ccfbb'),
      ('security.scholarship_ai_active_v1()', '74a1d5993a35b209ffbaa177ee6eec13', '4984eaf9195e1e6da5007af84856faf4'),
      ('security.scholarship_ai_next_model_v1(text)', 'e69e857eff40d3d2d1c1e03d981ee1cd', '061cb6e6bfe5d85a6f747d0b96b15a5d'),
      ('security.adapter_builder_model_for_v1(uuid)', 'eaf3a8ba8ba0d21e3f03795773ad12f3', '2aa0c60d8bd996394b3fa2674aa3b122'),
      ('security.adapter_builder_models_v1()', '2dca9fed779ceb5c4020d48f2b5451f9', '060d7488bc4ebd37e997611cf8cf04ea'),
      ('security.adapter_builder_budget()', '7871e4b5612d275ec05c2f3a8ee28181', 'ba9a37041952d16dac3934bd8603890b'),
      ('security.ai_model_pinned_ok_v1(text)', 'c19ca34d9fafbebbe35c505f17974a22', '8640931456f763088b222e6a17028fed')
      ) v(sig, before, after) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) not in (r.before, r.after) then
      raise exception 'live % differs from the definition this change replaces (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure));
    end if;
    raise notice '%: %', r.sig, case when md5(pg_get_functiondef(r.sig::regprocedure)) = r.after then 'unchanged' else 'applied' end;
  end loop;
end $guard$;

-- 1 helpers ----------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.ai_route_gate_v1(p_service text) returns jsonb
language sql stable security definer set search_path = '' as $function$
  -- the route as a reader needs it: security.ai_route_v1 with the providers of the open on-demand requests of the route's purpose group
  select security.ai_route_v1(p_service) || jsonb_build_object('on_demand_providers', to_jsonb(security.ai_on_demand_providers_v1(p_service)))
$function$;
create or replace function security.ai_route_open_v1(p_route jsonb, p_provider uuid) returns boolean
language sql immutable set search_path = '' as $function$
  -- may work of this provider be handed out? Yes when the route is not held, or when it is held by a cap or the ceiling only and the provider has
  -- an open on-demand request of the route's purpose group (operating model 3.3.2). Switched off, no allowed model and the account's credit
  -- floor hold everything, on-demand included.
  select not coalesce((p_route->>'held')::boolean, true)
      or (coalesce((p_route->>'on_demand_exempt')::boolean, false) and p_provider is not null and coalesce(p_route->'on_demand_providers' ? p_provider::text, false))
$function$;
revoke all on function security.ai_route_gate_v1(text), security.ai_route_open_v1(jsonb, uuid) from public, anon, authenticated;

-- 2 routes: every service is resolved by its route; the new page identity route; a cap on every route -----------------------------------------------
insert into pipeline.ai_service_routes (service_code, label, area, field, lane, ledger_match, cascade, daily_usd_cap, daily_calls_cap, prompt_source, resolver, note, sort, reason, purpose_group)
values ('page_identity', 'Page identity check', 'Matching and identity', null, 'page_identity', null, array['qwen3-30b', 'mimo-v2.6-pro', 'kimi-k2-0905'], 1, null,
        'worker code: cf247-page-identity-v1.0.2', 'route', 'Qualification only: the worker has no scheduled call for it.', 125, 'seed 13 Nov 2026 (phase 2)', 'course_search')
on conflict (service_code) do nothing;
-- the scholarship route is enforced from now on, so it starts as the chain is today (phase 1 seeded an unqualified second model on it)
update pipeline.ai_service_routes r
   set cascade = (select array_agg(c.code order by c.ord) from unnest(s.chain) with ordinality c(code, ord) join pipeline.ai_model_catalogue m on m.code = c.code and m.status = 'allowed'),
       reason = 'phase 2: the cascade is the scholarship chain', changed_at = now()
  from pipeline.scholarship_ai_extract_settings s
 where s.id = 1 and r.service_code = 'scholarship_extraction' and r.resolver <> 'route'
   and exists (select 1 from unnest(s.chain) c(code) join pipeline.ai_model_catalogue m on m.code = c.code and m.status = 'allowed');
update pipeline.ai_service_routes r set resolver = 'route',
       -- routed: the worker executes the cascade. routed_single: the call uses the first model only (no fallback yet). page_identity has no call.
       migration_state = case when r.service_code in ('course_description', 'course_entry_requirements', 'course_other_fields', 'fee_reader', 'calendar_reading', 'central_english_policy',
                                                     'course_matching', 'entry_requirements_v2_shadow', 'scholarship_extraction') then 'routed'
                              when r.service_code = 'page_identity' then 'not_migrated' else 'routed_single' end,
       -- what each service ran on before this release (live, 13 Nov 2026): GPT-4.1 mini through pipeline.central_ai_settings (until 19:09), the settings
       -- entry.matrix_model and ops.ai_diagnosis_model and the trial's prompt version; Qwen3 30B for the scholarship chain, the matcher and adapter proposals
       previous_model = case when r.service_code in ('scholarship_extraction', 'scholarship_eligibility', 'course_matching', 'adapter_builder') then 'qwen/qwen3-30b-a3b-instruct-2507'
                             when r.service_code = 'page_identity' then null else 'openai/gpt-4.1-mini' end,
       note = case r.service_code
         when 'course_description' then null when 'course_other_fields' then null
         when 'entry_requirements_v2_shadow' then 'The prompt version keeps its text and sha; the model is this route''s. The trial is switched off (aer.v2_shadow_on).'
         when 'scholarship_extraction' then 'The cascade is the escalation chain: an unproven fact goes to the next qualified model, then to a person. A technical failure retries the same model.'
         when 'scholarship_eligibility' then null
         when 'adapter_builder' then 'A provider''s own model (pipeline.uni_adapter_models) is used only when this cascade names it.'
         when 'course_matching' then null
         when 'provider_description' then null when 'calendar_reading' then null when 'central_english_policy' then null when 'fee_reader' then null
         else r.note end
 where r.resolver <> 'route' or r.migration_state = 'not_migrated';

-- 3 the worker can correct the ledger's model when a later model of the cascade answered ---------------------------------------------------------
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'retention.ai_invocations_days', 'AI call attempts: kept for', 'Rows of pipeline.ai_invocations (one per model call attempt) older than this are removed by the daily ledger-retention job.',
        'number', to_jsonb(90), 14, 365, 'days', 781, 'Platform Admin review 13 Nov 2026: per-invocation trace', 'Platform upkeep', 'job ledger-retention (security.ledger_retention_v1)')
on conflict (toolset_key, key) do nothing;
insert into pipeline.ai_route_qualifications (service_code, model_code, prompt_version, status, note)
values ('page_identity', 'qwen3-30b', 'cf247-page-identity-v1.0.2', 'pending', 'Qualification only; no scheduled call.')
on conflict (service_code, model_code) do nothing;

create or replace function public.svc_ai_model_answered_v1(p_source text, p_source_id text, p_model text, p_attempts jsonb default null, p_worker text default null) returns integer
language plpgsql security definer set search_path = '' as $function$
-- The worker reports what its model calls did.
--   p_attempts: one object per call attempt {service, model, attempt_no, outcome answered|failed, failure_kind, input_tokens, output_tokens, cost,
--   source, source_id}: kept in pipeline.ai_invocations (which model was asked, whether it answered, when and why a fallback happened).
--   p_source, p_source_id, p_model: when a later model of the cascade answered, the latest ledger row of that source row is corrected to it.
declare n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_attempts) = 'array' then
    insert into pipeline.ai_invocations (service_code, model, attempt_no, outcome, failure_kind, input_tokens, output_tokens, cost_usd, source, source_id, worker)
    select nullif(x->>'service', ''), x->>'model', coalesce((x->>'attempt_no')::int, 1), case when x->>'outcome' = 'answered' then 'answered' else 'failed' end,
           case when x->>'failure_kind' in ('http', 'timeout', 'empty', 'cut', 'non_json', 'refused') then x->>'failure_kind' end,
           (x->>'input_tokens')::int, (x->>'output_tokens')::int, (x->>'cost')::numeric, nullif(x->>'source', ''), nullif(x->>'source_id', ''), left(p_worker, 60)
      from jsonb_array_elements(p_attempts) x where nullif(x->>'model', '') is not null;
    get diagnostics n = row_count;
  end if;
  if p_model is not null and p_source is not null and exists (select 1 from pipeline.ai_model_catalogue m where m.model_identifier = p_model) then
    update pipeline.ai_spend_ledger l set model = p_model
     where l.id = (select max(x.id) from pipeline.ai_spend_ledger x where x.source = p_source and x.source_id = p_source_id and x.at > now() - interval '15 minutes')  -- fixed: the record of the same worker call
       and l.model is distinct from p_model;
    if p_attempts is null then get diagnostics n = row_count; end if;
  end if;
  return n;
end $function$;
revoke all on function public.svc_ai_model_answered_v1(text, text, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.svc_ai_model_answered_v1(text, text, text, jsonb, text) to service_role;

-- 4 the guarded edits (live text with the model and budget lines changed) ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.svc_fee_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := '[]'::jsonb; q record; v_rt jsonb := security.ai_route_gate_v1('fee_reader');  -- 13 Nov 2026: the model and the budget come from the route
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  for q in
    update pipeline.fee_reader_queue x set state = 'leased', leased_until = now() + interval '4 minutes', attempts = attempts + 1  -- fixed: lease longer than one worker call
     where x.id in (select y.id from pipeline.fee_reader_queue y
                     where (y.state = 'queued' or (y.state = 'leased' and y.leased_until < now())) and y.attempts < 3  -- fixed: three tries
                       and security.ai_route_open_v1(v_rt, y.provider_id)
                       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = y.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
                     order by y.priority desc, y.created_at limit greatest(1, least(coalesce(p_limit, 3), security.pipeline_num_v1('fees.pages_per_run', 10)::int)) for update skip locked)
    returning x.*
  loop
    v := v || (
      select jsonb_build_object(
        'queue_id', q.id, 'source_id', coalesce(f.id, q.fact_source_id), 'url', coalesce(f.url, ce.source_url, cg.url), 'storage_path', coalesce(e.storage_path, ce.storage_path),
        -- CF-247 23 Oct 2026: a course's own page; the worker reads the stored page as text and the course list is that one course
        'course_page', q.course_id is not null,
        'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2,
        'profile', (select to_jsonb(cp) - 'reason' - 'updated_by' - 'updated_at' from pipeline.fee_country_profiles cp where cp.country_code = k.iso_alpha2),
        'model', v_rt->>'model', 'model_code', v_rt#>>'{models,0,code}', 'models', v_rt->'models',
        'page_chars', security.pipeline_num_v1('fees.page_chars', 40000)::int,
        'notes', case when q.course_id is null then (select r.notes from pipeline.fee_reader_recipes r where r.provider_id = q.provider_id) end,
        'findings', coalesce((select jsonb_agg(jsonb_build_object('kind', z.kind, 'detail', z.detail, 'times', z.times) order by z.last_seen desc)
                                from (select * from pipeline.fee_reader_findings x where x.provider_id = q.provider_id and x.resolved_at is null
                                      order by x.last_seen desc limit security.pipeline_num_v1('fees.findings_in_prompt', 10)::int) z), '[]'::jsonb),
        'courses', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'title', c.canonical_title, 'level', sl.code) order by c.canonical_title)
                               from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id
                              where c.provider_id = q.provider_id and c.lifecycle_status = 'active' and (q.course_id is null or c.id = q.course_id)), '[]'::jsonb))
        from catalogue.providers p join ref.countries k on k.id = p.country_id
        left join pipeline.provider_fact_sources f on f.id = q.fact_source_id and q.course_id is null
        left join pipeline.evidence_artifacts e on e.id = f.evidence_id
        left join pipeline.coverage_course_pages cg on cg.course_id = q.course_id
        left join pipeline.evidence_artifacts ce on ce.id = q.evidence_id
       where p.id = q.provider_id and (q.course_id is not null or f.id is not null));
  end loop;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_central_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; s pipeline.central_ai_settings%rowtype;
        -- 13 Nov 2026: each kind of central page has its own route (model, cap, switch); the settings row keeps the lane switch and calls at once
        v_cal jsonb := security.ai_route_gate_v1('calendar_reading'); v_pol jsonb := security.ai_route_gate_v1('central_english_policy');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into s from pipeline.central_ai_settings where id = 1;
  if not coalesce(s.enabled, false) then return '[]'::jsonb; end if;
  with pick as (select q.id from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                   and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
                   and security.ai_route_open_v1(case when q.kind = 'intake_calendar' then v_cal else v_pol end, q.provider_id)
                 order by q.id limit greatest(1, least(coalesce(p_limit, 6), 10)) for update skip locked),
  upd as (update pipeline.central_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'id', u.fact_source_id, 'kind', u.kind, 'url', f.url, 'provider', coalesce(p.display_name, p.canonical_name),
           'storage_path', e.storage_path, 'notes', case when u.kind = 'intake_calendar' then security.calendar_reader_notes_v1(u.provider_id) end, 'model', (case when u.kind = 'intake_calendar' then v_cal else v_pol end)->>'model',
           'model_code', (case when u.kind = 'intake_calendar' then v_cal else v_pol end)#>>'{models,0,code}', 'models', (case when u.kind = 'intake_calendar' then v_cal else v_pol end)->'models')), '[]'::jsonb) into v
    from upd u join pipeline.provider_fact_sources f on f.id = u.fact_source_id join pipeline.evidence_artifacts e on e.id = f.evidence_id
    join catalogue.providers p on p.id = u.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_description_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
declare v jsonb; v_rt jsonb := security.ai_route_v1('provider_description'); v_model text; v_pending int; v_spent numeric; v_fc_used int; v_mach boolean := security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1; v_cap numeric; v_afford numeric; v_od boolean; v_over boolean := false; v_pv text := security.provider_description_prompt_active_v1()->>'version'; /* 20261112010000: on demand, over a lane limit, the active prompt version */ v_fc_res int; v_fc_left int; v_ws text[]; v_stored jsonb; v_reoffer uuid[]; v_tries numeric := security.pipeline_num_v1('pdesc.tries', 3); v_acq boolean := security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1; -- the two settings the pick tests on every due read, read once
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('idle', true, 'reason', 'off', 'items', '[]'::jsonb); end if;
  -- Validation 5 Nov 2026: a worker leases only through public.svc_provider_description_lease_v1 or _cohort_next, which declare the
  -- reservation protocol. A worker from before this release (it calls this function directly and never reserves) gets no item, so it cannot
  -- make an unreserved paid AI call against this database.
  if coalesce(auth.role(), '') = 'service_role' and coalesce(current_setting('cf.pdesc_worker_protocol', true), '') <> 'provider-description-reserve-v1' then
    return jsonb_build_object('idle', true, 'reason', 'worker_protocol_required', 'items', '[]'::jsonb);
  end if;
  -- fixed: serialize reservation of review slots across all reader callers; no waiting behind another worker.
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb); end if;
  v_cap := case when v_mach then security.pipeline_num_v1('pdesc.concurrency_max', 12) else security.pipeline_num_v1('pdesc.pending_max', 10) end;
  select (case when v_mach then 0 else (select count(*) from pipeline.layer4_review_items i where i.field_code='provider_description' and i.status='pending') end)
       + (select count(*) from pipeline.provider_description_reads r where r.state='reading' and r.leased_until>=now()) into v_pending;
  if v_pending >= v_cap then return jsonb_build_object('idle', true, 'reason', 'review_full', 'items', '[]'::jsonb); end if;
  v_model := v_rt->>'model';  -- 13 Nov 2026: the route (pipeline.ai_service_routes)
  if nullif(btrim(v_model), '') is null then return jsonb_build_object('idle', true, 'reason', 'no_model', 'items', '[]'::jsonb); end if;
  -- the shared AI rule (credit floor, daily ceiling, lane guard; v2.15.404): nothing new is claimed while AI use is refused
  if not security.ai_use_allowed_v1(case when security.pdesc_on_demand_due_v1() then 'provider_description_on_demand' else 'provider_description' end) then return jsonb_build_object('idle', true, 'reason', 'ai_refused', 'items', '[]'::jsonb); end if; /* 20261112010000 */
  -- the pilot's hard ceilings: total AI spend of this lane in the shared ledger, and total Firecrawl reads of this reader
  select coalesce(sum(l.cost_usd), 0) into v_spent from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening';
  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r
   where r.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int); -- 20261110250000: an allowance a window, not a lifetime count
  -- 20261112010000: a read an operator asked for (checks.on_demand) is not held by the lane limits; while one is due, this call takes on-demand reads only
  v_od := security.pdesc_on_demand_due_v1();
  if v_od then v_over := true; end if;
  if coalesce((v_rt->>'held')::boolean, true) and not (coalesce((v_rt->>'on_demand_exempt')::boolean, false) and v_od) then return jsonb_build_object('idle', true, 'reason', 'route_held', 'detail', v_rt->>'held_reason', 'items', '[]'::jsonb); end if;
  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) and not v_od then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
  if v_mach then
    -- automatic mode: no more reads in progress than the AI spend still available covers, at the dearer of the set cost and the observed cost of a read
    v_afford := floor((security.pipeline_num_v1('pdesc.ai_usd_max', 1) - v_spent - coalesce((select sum(x.reserved_usd) from pipeline.provider_description_reads x where x.state = 'reading'), 0))
                      / greatest(security.pipeline_num_v1('pdesc.read_cost_floor_usd', 0.003), coalesce((select sum(x.cost_usd) / nullif(count(*) filter (where x.ai_calls > 0), 0) from pipeline.provider_description_reads x), 0)))
                - (select count(*) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now());
    if v_afford < 1 and not v_od then return jsonb_build_object('idle', true, 'reason', 'ai_spend_committed', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
    if v_od then v_afford := null; end if;
  end if;
  -- QA N4: Firecrawl reads held by worker calls still in flight are not available again; with automatic admission on, this call is granted at most pdesc.firecrawl_per_call of what the ceiling still allows after them
  v_fc_res := coalesce((select sum(coalesce((x.checks->>'firecrawl_reserved')::int, 0)) from pipeline.provider_description_reads x where x.state = 'reading' and x.leased_until >= now()), 0);
  v_fc_left := case when v_mach then least(greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used - v_fc_res), security.pipeline_num_v1('pdesc.firecrawl_per_call', 5)::int)
                    else greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used) end;
  if v_od then v_fc_left := security.pipeline_num_v1('pdesc.firecrawl_per_call', 5)::int; end if; -- 20261112010000: on demand, the per-call share only (spent as purpose provider_description_on_demand)
  if v_mach then
    -- QA N6/N7/N11: a provider the automatic rule must not describe now (locked, earlier rejection, withdrawn, cleared by hand, open finding, unusable name, already described) is held here, before any AI call
    update pipeline.provider_description_reads r set state='held',rule='machine_declined_'||(b.blk->>'rule'),reason=left(b.blk->>'reason',400),leased_until=null,updated_at=now() -- fixed: the stored reason shows its first 400 characters
      from (select x.id,security.provider_description_machine_blocked_v1(x.provider_id) blk from pipeline.provider_description_reads x where (x.state='queued' and x.next_try_at<=now()) or (x.state='reading' and x.leased_until<now())) b
     where r.id=b.id and b.blk is not null;
  end if;
  -- one pass (9 Nov 2026, lease statement time-out): the stored About copy of each provider with open work is found ONCE here and read from v_stored below; it was found up to three times per queued row.
  -- Only a provider with a copy at an About address can have one (security.pdesc_about_like_patterns_v1 is the first step of security.provider_description_stored_v1), so the others are not asked.
  v_ws := security.pdesc_about_like_patterns_v1();
  select coalesce(jsonb_object_agg(z.pid, to_jsonb(z.sid)), '{}'::jsonb) into v_stored from (
    select x.provider_id::text pid, security.provider_description_stored_v1(x.provider_id) sid
      from (select distinct o.provider_id from pipeline.provider_description_reads o where (o.state='queued' or (o.state='reading' and o.leased_until<now()))
               and exists (select 1 from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id=s.id where s.provider_id=o.provider_id and lower(a.source_url) like any (v_ws))
             offset 0) x) z -- offset 0 is an optimisation fence: without it the planner moves the not-null test below the DISTINCT and asks stored_v1 for every open read
   where z.sid is not null;
  -- identity hold (10 Nov 2026): due queued reads are tested for the provider identity, the ones tested longest ago first (each tested read is marked checks.identity_checked_at, so the same oldest reads are not tested on every call). The stored About copy is read from v_stored (found once, above).
  -- Only wrong_host (a provider with no website gives this too) and provider_host_conflict hold the read, with the identity rule and reason and the mark checks.identity_hold: the selection offers such a read again as soon as the provider passes (website or host corrected).
  -- Any other outcome (provider_inactive, a lifecycle hold, an open identity finding) leaves the read queued as before. wrong_host is taken by the register-fact tier; provider_host_conflict waits for a person. Not for a Run Now cohort (the job guard holds those).
  if v_mach and nullif(current_setting('cf.pdesc_cohort',true),'') is null and security.pipeline_num_v1('batch.provider_description', 3) >= 1 then
    update pipeline.provider_description_reads r set state=case when h.hold then 'held' else r.state end, rule=case when h.hold then h.idr else r.rule end, reason=case when h.hold then left(h.why,400) else r.reason end, -- fixed: the stored reason shows its first 400 characters
           leased_until=case when h.hold then null else r.leased_until end, updated_at=case when h.hold then now() else r.updated_at end,
           checks=coalesce(r.checks,'{}'::jsonb)||jsonb_build_object('identity_checked_at',now())||case when h.hold then jsonb_build_object('identity_hold',true) else '{}'::jsonb end
      from (select o.id, i.v->>'rule' idr, i.v->>'reason' why, (not coalesce((i.v->>'ok')::boolean,false) and i.v->>'rule' in ('wrong_host','provider_host_conflict')) hold
              from (select x.id, x.provider_id, pp.website from pipeline.provider_description_reads x join catalogue.providers pp on pp.id=x.provider_id and pp.lifecycle_status='active' and pp.publication_status='published'
                     where x.state='queued' and x.next_try_at<=now() order by (x.checks->>'identity_checked_at') nulls first, x.next_try_at, x.id limit security.pipeline_num_v1('batch.provider_description', 3)::int) o
              cross join lateral (select security.provider_description_identity_v1(o.provider_id, coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>o.provider_id::text)::uuid), o.website)) v offset 0) i) h
     where r.id=h.id and r.state='queued';
  end if;
  -- identity re-offer (9 Nov 2026): a provider whose latest finished read was held on an identity rule (pdesc.identity_reeval_rules) by another reader than the one running now (security.pdesc_reader_behaviour_v1) is not held or skipped on recovery knowledge:
  -- that knowledge recorded the earlier reader's failure. Found once here from the latest finished read of each provider. A failure of any other kind, or of the current reader, keeps its memory.
  v_reoffer := array(select l.provider_id from (select distinct on (o.provider_id) o.provider_id, o.state, o.rule, o.checks from pipeline.provider_description_reads o
                        where o.state not in ('queued', 'reading') order by o.provider_id, o.created_at desc) l
                      where l.state = 'held' and coalesce(security.toolset_setting('pipeline', 'pdesc.identity_reeval_rules'), '[]'::jsonb) ? l.rule
                        and coalesce(l.checks->'identity'->>'reader_behavior_version', '') is distinct from coalesce(security.pdesc_reader_behaviour_v1(), ''));
  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure',reason='The same stored evidence already failed; changed approved evidence or an authorised correction is needed before another AI call.',leased_until=null,updated_at=now()
  where r.id in (select x.id from pipeline.provider_description_reads x join pipeline.evidence_artifacts a on a.id=(v_stored->>x.provider_id::text)::uuid
    where x.state='queued' and not (x.provider_id = any(v_reoffer)) and not security.pdesc_on_demand_live_v1(x.checks) and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',x.provider_id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),v_model,coalesce(v_pv,x.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true)
    order by x.next_try_at,x.id limit security.pipeline_num_v1('batch.provider_description',3)::int);
  with act as materialized (select pz.country_id,count(*) n from pipeline.provider_description_reads o join catalogue.providers pz on pz.id=o.provider_id
                              where v_mach and o.state in ('reading','proposed','admitted','held') and o.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.rate_window_hours', 3)::int) group by pz.country_id),
  pick as (select l.id from (
             -- lazy pick (9 Nov 2026, lease and record time-outs): the cheap tests and the order are worked out for every due read (inner query), then the dear per-provider tests
             -- (scope, recovery memory, identity, hidden) run only on the reads taken in that order until the limit is reached. The same reads in the same order as before; the whole queue is no longer tested on every call.
             select c.id from (
               select r.id, r.provider_id, r.prompt_version, r.checks from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < v_tries
                   and (not v_over or security.pdesc_on_demand_live_v1(r.checks))
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))) or (v_mach and security.provider_description_basic_profile_v1(r.provider_id) is not null))
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when v_acq then true else (v_stored->>r.provider_id::text) is not null end
                 order by security.pdesc_on_demand_live_v1(r.checks) desc, case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 offset 0) c -- offset 0 is an optimisation fence: the dear tests below are not moved under the sort, so they stop with the limit
              where security.provider_description_scope_v1(c.provider_id)
                and (c.provider_id = any(v_reoffer) or security.pdesc_on_demand_live_v1(c.checks) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',c.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>c.provider_id::text)::uuid),v_model,coalesce(v_pv,c.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
                and exists(select 1 from catalogue.providers p where p.id=c.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
                and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=c.provider_id)) o
           -- the row lock, as before: skip a read another call holds; the due test is repeated on the locked row, as the lock of the old single query re-tested it
           cross join lateral (select q.id from pipeline.provider_description_reads q where q.id = o.id
                                  and ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'reading' and q.leased_until < now()))
                                  and q.tries < v_tries
                                for update skip locked) l
           limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))),
  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1, prompt_version = coalesce(v_pv, r.prompt_version), checks=coalesce(r.checks,'{}'::jsonb)||jsonb_build_object('description_at_lease',(select p.description from catalogue.providers p where p.id=r.provider_id),'identity_snapshot',security.provider_description_identity_snapshot_v1(r.provider_id),'firecrawl_reserved',case when v_mach and r.id=(select pk.id from pick pk order by pk.id limit 1) then v_fc_left else 0 end),
                 leased_until = now() + interval '20 minutes',  -- fixed: claim timer (a lost worker call is taken again)
                 updated_at = now()
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'on_demand', security.pdesc_on_demand_live_v1(u.checks), 'provider', coalesce(p.display_name, p.canonical_name),
           'website', p.website, 'country', k.iso_alpha2, 'identity_names',jsonb_build_array(p.canonical_name,p.display_name), 'provider_type',(select t.code from ref.provider_types t where t.id=p.provider_type_id), 'hosts', to_jsonb(security.provider_hosts_v1(u.provider_id)),
           'stored', (select jsonb_build_object('evidence_id', a.id, 'storage_path', a.storage_path, 'url', a.source_url, 'captured_at', coalesce(a.captured_at, a.created_at),'content_hash',coalesce(a.content_hash,a.id::text))
                        from pipeline.evidence_artifacts a where a.id = st.stored_id),
           -- About pages the central page finder suggested (page type about_page, central.ts), on the provider's own hosts, best first
           -- IQ-00055: the page rule once per suggestion (a lateral), for the filter and the order
           'candidates', (select coalesce(jsonb_agg(z.url order by (z.pg->>'main_host')::boolean desc, z.score desc, length(z.url)), '[]'::jsonb) from (
                            select y.url, y.score, g.pg from (
                              select distinct e->>'url' url, coalesce((e->>'score')::numeric, 0) score
                                from pipeline.provider_central_search cs, jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e
                               where cs.provider_id = u.provider_id and e->>'kind' = 'about_page' and e->>'url' ~* '^https?://'
                                 and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)) y
                              cross join lateral (select security.provider_description_page_v1(u.provider_id, y.url) pg offset 0) g
                             where (g.pg->>'ok')::boolean) z))), '[]'::jsonb)
    into v
    -- IQ-00055: the stored copy once per claimed row
    from upd u cross join lateral (select case when nullif(current_setting('cf.pdesc_cohort',true),'') is not null then (select m.evidence_id from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=u.id) else (v_stored->>u.provider_id::text)::uuid end stored_id offset 0) st
         join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;
  return jsonb_build_object('model', v_model, 'models', v_rt->'models', 'prompt', security.provider_description_prompt_active_v1(),
    'acquire_direct', security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 and coalesce((select c.selection->>'mode' from pipeline.provider_description_cohorts c where c.id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid),'approved')='approved',
    'acquire_firecrawl', security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1 and coalesce((select c.selection->>'mode' from pipeline.provider_description_cohorts c where c.id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid),'approved')='approved',
    'firecrawl_left', v_fc_left,
    'page_chars', security.pipeline_num_v1('pdesc.page_chars', 16000)::int,'verbatim_span_max_chars',security.pipeline_num_v1('pdesc.verbatim_span_max_chars',120)::int,
    'min_quote_chars', security.pipeline_num_v1('pdesc.min_quote_chars', 20)::int,
    'about_patterns', coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb),
    -- pilot 2 Nov 2026 16:16: the page rule's lists, for the home page's links (security.provider_description_page_v1 decides the same way)
    'page_rule', jsonb_build_object('about_prefixes', coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb),
                                    'refused_path_words', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_path_words'), '[]'::jsonb),
                                    'refused_host_labels', coalesce(security.toolset_setting('pipeline', 'pdesc.refused_host_labels'), '[]'::jsonb),
                                    'about_max_segments', security.pipeline_num_v1('pdesc.about_max_segments', 2)::int),
    -- pilot 2 Nov 2026 16:16 (CDU held at 916 characters): the model is told the limits the validation applies
    'length', jsonb_build_object('min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2)::int, 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5)::int,
                                 'min_chars', security.pipeline_num_v1('pdesc.min_chars', 150)::int, 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)::int),
    'items', v);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_description_reserve_v1(p_item uuid, p_model text, p_max_cost numeric, p_source_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.provider_description_reads%rowtype; v_model text; v_spent numeric; v_today numeric; v_reserved numeric; v_cap numeric; v_daily numeric; v_source_hash text;
begin
 if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtext('cf247 provider description spend')); -- fixed: serialize reservations across reader calls.
 select * into r from pipeline.provider_description_reads where id=p_item for update;
 if r.id is null or r.state<>'reading' or r.leased_until<=now() then return jsonb_build_object('ok',false,'reason','no_active_read_lease'); end if;
 select x->>'model_identifier' into v_model from jsonb_array_elements(security.ai_route_v1('provider_description')->'models') x where x->>'model_identifier' = p_model;  -- a model of the route's cascade
 if p_model is distinct from v_model or p_max_cost is null or p_max_cost<=0 then return jsonb_build_object('ok',false,'reason','invalid_pinned_model_price_quote'); end if;
 v_source_hash:=coalesce(nullif(p_source_hash,''),(select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=security.provider_description_stored_v1(r.provider_id)));
 if v_source_hash is null then return jsonb_build_object('ok',false,'reason','no_source_version_before_ai'); end if;
 if exists(select 1 from pipeline.provider_description_reads rejected where rejected.provider_id=r.provider_id and rejected.state='rejected' and rejected.content_hash=v_source_hash) then return jsonb_build_object('ok',false,'reason','unchanged_rejected_evidence'); end if;
 if not security.pdesc_on_demand_live_v1(r.checks) and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,security.provider_description_signature_v1(v_source_hash,p_model,coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) then return jsonb_build_object('ok',false,'reason','recovery_knowledge_unchanged_failure'); end if;
 if r.checks->'identity_snapshot' is not null and r.checks->'identity_snapshot' is distinct from security.provider_description_identity_snapshot_v1(r.provider_id) then return jsonb_build_object('ok',false,'reason','identity_changed_after_lease'); end if;
 if r.reserved_usd>0 then return jsonb_build_object('ok',false,'reason','existing_cost_reservation_uncertain','ai_calls',r.ai_calls,'reserved_usd',r.reserved_usd); end if;
 if security.pipeline_num_v1('pdesc.enabled',0)<1 or not security.ai_use_allowed_v1(case when security.pdesc_on_demand_live_v1(r.checks) then 'provider_description_on_demand' else 'provider_description' end) then /* 20261112010000 */ return jsonb_build_object('ok',false,'reason','ai_refused'); end if;
 select coalesce(sum(cost_usd),0),coalesce(sum(cost_usd) filter(where at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),0) into v_spent,v_today from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening';
 select coalesce(sum(reserved_usd),0) into v_reserved from pipeline.provider_description_reads where reserved_usd>0 and id<>r.id;
 v_cap:=security.pipeline_num_v1('pdesc.ai_usd_max',1);
 v_daily:=coalesce((security.toolset_setting('openrouter','guard_provider_description')#>>'{}')::numeric,1);
 if v_spent+v_reserved+p_max_cost>v_cap and not security.pdesc_on_demand_live_v1(r.checks) then /* 20261112010000: on demand is not held by the lane ceiling */ return jsonb_build_object('ok',false,'reason','ai_ceiling','remaining_usd',greatest(0,v_cap-v_spent-v_reserved)); end if;
 if v_today+v_reserved+p_max_cost>v_daily and not security.pdesc_on_demand_live_v1(r.checks) then /* 20261112010000: nor by the lane daily guard */ return jsonb_build_object('ok',false,'reason','ai_daily_guard','remaining_usd',greatest(0,v_daily-v_today-v_reserved)); end if;
 update pipeline.provider_description_reads set reserved_usd=p_max_cost where id=r.id;
 return jsonb_build_object('ok',true,'reserved_usd',p_max_cost,'remaining_usd',greatest(0,v_cap-v_spent-v_reserved-p_max_cost));
end $function$;

CREATE OR REPLACE FUNCTION security.provider_description_selection_v1(p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_size int := coalesce((p_args->>'size')::int,security.pipeline_num_v1('batch.provider_description',3)::int);
 v_max int := case when security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then security.pipeline_num_v1('pdesc.queue_cap',60)::int else least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int end;
 v_cc text := upper(nullif(btrim(p_args->>'country'),'')); v_type text := nullif(btrim(coalesce(p_args->>'provider_type',p_args->>'type')),'');
 v_provider uuid := nullif(p_args->>'provider_id','')::uuid; v_filter text := coalesce(nullif(coalesce(p_args->>'description_state',p_args->>'filter'),''),'missing');
 v_mode text := coalesce(nullif(p_args->>'mode',''),'stored'); v_rows jsonb; v_scanned jsonb; v_pat text[]:=security.pdesc_about_like_patterns_v1(); v_cur text:=security.pdesc_reader_behaviour_v1(); v_idr jsonb:=coalesce(security.toolset_setting('pipeline','pdesc.identity_reeval_rules'),'[]'::jsonb);
 -- upgrade mode (pdesc.registry_upgrade_on, argument upgrade): the list is the providers that hold a register-fact profile, not the providers with no description
 v_upg boolean := security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and coalesce((p_args->>'upgrade')::boolean,false);
 -- QA B2: with prefilter (automatic mode only; the default there for the missing-description list of every caller, and always for the reader) the stored page and identity are worked out for a bounded slice of the providers that can still be read, not for the whole catalogue
 v_pre boolean := security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and coalesce((p_args->>'prefilter')::boolean,v_filter='missing' and v_provider is null);
 v_slice int := least(security.pipeline_num_v1('pdesc.scan_max',150)::int, greatest(coalesce((p_args->>'size')::int,security.pipeline_num_v1('batch.provider_description',3)::int),1)*security.pipeline_num_v1('pdesc.scan_factor',3)::int);
begin
 if v_size < 1 or v_size > v_max then raise exception 'cohort size must be between 1 and %',v_max using errcode='22023'; end if;
 if v_mode not in ('stored','approved') then raise exception 'unsupported processing mode' using errcode='22023'; end if;
 if v_mode='approved' and security.pipeline_num_v1('pdesc.acquire_direct',0)<1 then raise exception 'acquisition has not been authorised' using errcode='42501'; end if;
 if v_filter not in ('missing','stale','failed','all') then raise exception 'unsupported description selection' using errcode='22023'; end if;
 with pre as materialized (
  select q.id from (select p.id,coalesce(m.scanned_at,'-infinity'::timestamptz) sc,(select count(*) from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') ac,coalesce(p.display_name,p.canonical_name) nm
   from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id left join pipeline.provider_description_scan_marks m on m.provider_id=p.id
   where v_pre and (v_cc is null or k.iso_alpha2=v_cc) and (v_type is null or t.code=v_type) and (v_provider is null or p.id=v_provider)
    and security.provider_description_scope_v1(p.id) and case when v_upg then security.provider_description_basic_profile_v1(p.id) is not null else nullif(btrim(p.description),'') is null end and p.publication_status='published'
    and not exists(select 1 from pipeline.provider_description_reads x where x.provider_id=p.id and x.state in ('queued','reading','proposed'))
    and (not v_upg or ((nullif(btrim(p.website),'') is not null or security.provider_description_stored_candidate_v1(p.id,v_pat))))
    and (v_mode<>'stored' or security.provider_description_stored_candidate_v1(p.id,v_pat))
   order by sc,ac desc,nm limit v_slice) q
 ), candidates as materialized (
 select p.*,k.iso_alpha2::text cc,t.code typ,
  (select count(*) from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') active_course_count,
  security.provider_description_stored_v1(p.id) stored_id
 from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id
 where (v_cc is null or k.iso_alpha2=v_cc) and (v_type is null or t.code=v_type) and (v_provider is null or p.id=v_provider)
  -- Scope is governed by the existing policy. The UI selector can narrow it, never widen it.
  and security.provider_description_scope_v1(p.id)
  and (not v_pre or p.id in (select pre.id from pre))
 ), rows as (
 select p.*,r.id last_read_id,r.state read_state,r.rule read_rule,r.reason read_reason,r.proposal,r.checks,r.review_item_id,(select li.created_at from pipeline.layer4_review_items li where li.id=r.review_item_id) review_created_at,r.model,r.cost_usd,r.tries,r.updated_at read_updated_at,r.last_verified_at read_last_verified_at,
 a.source_url,a.id evidence_id,coalesce(a.captured_at,a.created_at) source_captured_at,coalesce(a.content_hash,a.id::text) source_hash,
 case
  when v_pre and security.provider_description_machine_blocked_v1(p.id) is not null then 'machine_'||(security.provider_description_machine_blocked_v1(p.id)->>'rule')
  when p.lifecycle_status<>'active' then 'provider_inactive'
  when p.publication_status<>'published' or exists(select 1 from security.provider_hidden_v1 h where h.provider_id=p.id) then 'provider_not_published'
  when exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=p.id and l.field in ('description','p_description','all')) then 'manual_lock'
  when nullif(btrim(p.description),'') is not null and security.provider_description_approved_lineage_v1(p.id,p.description) is null then 'manual_description'
  when nullif(btrim(p.description),'') is not null and (select z.proposal->>'description' from pipeline.provider_description_reads z where z.provider_id=p.id and z.state in ('admitted','verified') order by coalesce(z.last_verified_at,z.updated_at) desc,z.id desc limit 1) is distinct from p.description then 'manual_description_changed'
  when r.state in ('queued','reading','proposed') then 'existing_work'
  when r.state='dead_letter' then 'dead_letter_requires_retry'
  when coalesce(r.reserved_usd,0)>0 then 'cost_reservation_uncertain'
  when r.state='held' and r.rule='review_full' then 'review_capacity_parked'
  when r.state='held' and r.rule in ('source_identity_proof_missing','ai_ceiling','ai_daily_guard','ai_refused','model_pricing_unavailable','invalid_model_pricing','unrecognised_pricing_component','ai_budget_refused','existing_cost_reservation_uncertain') then 'policy_retry_parked'
  when r.state in ('held','rejected') and r.content_hash is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and not (r.state='held' and coalesce(v_idr ? r.rule, false) and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) and not (r.state='held' and r.rule='recovery_knowledge_unchanged_failure' and coalesce(r.ai_calls,0)=0 and coalesce(r.reserved_usd,0)=0 and a.id is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',p.id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),(select security.ai_route_v1('provider_description')->>'model'),coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) and not exists(select 1 from pipeline.provider_description_reads z where z.provider_id=p.id and z.state='rejected' and z.content_hash=coalesce(a.content_hash,a.id::text))) then 'unchanged_unsuitable_evidence'
  when r.state in ('held','rejected') and r.updated_at>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int)
   and not (r.updated_at<=now()-make_interval(mins=>security.pipeline_num_v1('pdesc.retry_minutes',360)::int) and a.id is not null
            and coalesce(a.content_hash,a.id::text) is distinct from r.content_hash
            and (r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) and not (r.state='held' and coalesce(v_idr ? r.rule, false) and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) and not (r.state='held' and coalesce(r.checks ? 'identity_hold',false) and coalesce((security.provider_description_identity_v1(p.id,coalesce(a.source_url,p.website))->>'ok')::boolean,false)) and not (r.state='held' and r.rule='recovery_knowledge_unchanged_failure' and coalesce(r.ai_calls,0)=0 and coalesce(r.reserved_usd,0)=0 and a.id is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',p.id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),(select security.ai_route_v1('provider_description')->>'model'),coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) and not exists(select 1 from pipeline.provider_description_reads z where z.provider_id=p.id and z.state='rejected' and z.content_hash=coalesce(a.content_hash,a.id::text))) then 'retry_wait'
  when r.state in ('admitted','verified') and r.proposal->'sentences' is not null and a.id is not null
   and security.provider_description_validate_v1(p.id,r.source_url,r.source_captured_at,jsonb_build_object('about_page',true,'sentences',r.proposal->'sentences'))->>'outcome' not in ('propose','verified')
   then case when coalesce(a.content_hash,a.id::text) is distinct from r.content_hash then 'invalid_description' else 'invalid_description_unchanged_evidence' end
  when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is not null and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) and not (v_upg and security.provider_description_basic_profile_v1(p.id) is not null) then 'description_current'
  when a.id is not null and not (security.provider_description_identity_v1(p.id,a.source_url)->>'ok')::boolean then security.provider_description_identity_v1(p.id,a.source_url)->>'rule'
  when a.id is not null and not coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',p.id::text,security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),(select security.ai_route_v1('provider_description')->>'model'),coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true) and not (r.state='held' and coalesce(v_idr ? r.rule, false) and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'recovery_knowledge_unchanged_failure'
  when v_mode='stored' and a.id is null then 'no_verified_stored_source'
  when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is null then 'description_lost'
  else 'eligible' end eligibility_reason
 from candidates p left join lateral(select x.* from pipeline.provider_description_reads x where x.provider_id=p.id order by x.created_at desc,x.id desc limit 1) r on true
 left join pipeline.evidence_artifacts a on a.id=p.stored_id
 ), shaped as (
 select jsonb_build_object('provider_id',rows.id,'provider',coalesce(display_name,canonical_name),'name',coalesce(display_name,canonical_name),'stable_key',stable_key,
 'registration',coalesce((select jsonb_agg(jsonb_build_object('registration_id',pr.id,'scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status,'valid_to',pr.valid_to,'checked_at',pr.checked_at,'source_id',pr.source_id,'evidence_id',pr.evidence_id) order by pr.registration_scheme,pr.registration_code) from catalogue.provider_registrations pr where pr.provider_id=rows.id),'[]'::jsonb),'country',cc,'type',typ,'lifecycle_status',lifecycle_status,'publication_status',publication_status,
 'active_course_count',active_course_count,'current_description',description,'proposed_description',proposal->>'description','sentences',proposal->'sentences','checks',checks,
 'source_url',source_url,'evidence_id',evidence_id,'source_hash',source_hash,'source_captured_at',source_captured_at,'source_age_days',extract(epoch from (now()-source_captured_at))/86400,
 'evidence_version',source_hash,'approval_status',case when read_state='proposed' then 'pending' else read_state end,'manual_locked',eligibility_reason='manual_lock','last_read_id',last_read_id,'state',coalesce(read_state,'missing'),'rule',read_rule,'reason',read_reason,'review_item_id',review_item_id,'review_created_at',review_created_at,
 'model',coalesce(model,(select security.ai_route_v1('provider_description')->>'model')),'cost_usd',cost_usd,'tries',tries,
 'eligible',eligibility_reason in ('eligible','invalid_description','description_lost'),'eligibility_reason',eligibility_reason,'required_approval','Individual human Layer 4 decision','last_verified_at',read_last_verified_at) row,
 eligibility_reason,active_course_count,coalesce(display_name,canonical_name) nm
 from rows where v_filter='all' or (v_filter='missing' and nullif(btrim(description),'') is null)
 or (v_filter='stale' and nullif(btrim(description),'') is not null)
 or (v_filter='failed' and read_state in ('held','dead_letter','rejected'))
 ) select coalesce(jsonb_agg(row order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm),'[]'::jsonb),(select coalesce(jsonb_agg(z.row->>'provider_id'),'[]'::jsonb) from shaped z where z.eligibility_reason not in ('eligible','invalid_description','description_lost')) into v_rows,v_scanned
 from (select * from shaped order by eligibility_reason in ('eligible','invalid_description','description_lost') desc,active_course_count desc,nm limit v_size) b;
 return jsonb_build_object('providers',v_rows,'selected',(select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),
 'eligible',(select count(*) from jsonb_array_elements(v_rows) x where (x->>'eligible')::boolean),'bounded',true,'size',v_size,'scanned',case when v_pre then v_scanned end,'as_at',now(),
 'exclusions',(select coalesce(jsonb_agg(jsonb_build_object('provider_id',x->>'provider_id','reason',x->>'eligibility_reason')),'[]') from jsonb_array_elements(v_rows) x where not (x->>'eligible')::boolean));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_rt jsonb := security.ai_route_gate_v1('scholarship_extraction'); v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int; v_win bigint[]; v_tp text[]; v_off uuid[];
        v_scan int := security.pipeline_num_v1('batch.sch_ai_pick_scan', 60)::int;
        -- CF-247 P0 mandate 3 Nov 2026 §6: while the scholarship Firecrawl lane is held, only items with a stored copy are taken
        v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- CF-247 F-SCH 13 Nov 2026: one bounded window of the next items, in the picker's order and filters; only these are checked and leased
  -- (the due items are put in order first and the per-item checks run only until the window is full: offset 0 keeps them out of the sort)
  select array_agg(w.id) into v_win from (
    select o.id from (select q.id, q.provider_id, q.run_kind from pipeline.scholarship_ai_queue q
                       where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                       order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id offset 0) o
     where (o.provider_id is null or o.run_kind in ('test', 'qualify') or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = o.provider_id))
       and (v_paid or security.scholarship_ai_has_copy_v1(o.id))
     limit greatest(20, least(v_scan, 2000))) w;
  -- the same two checks, once per distinct site and provider in the window (one row each), not once per item: 67 ms for 200 items, was 1.1 s per item check
  select array_agg(h.host) into v_tp from (select distinct on (security.site_host_v1(w.url)) security.site_host_v1(w.url) host, w.url
                                              from pipeline.scholarship_ai_queue w where w.id = any(v_win)) h
   where h.host is not null and security.third_party_host_v1(h.url);
  select array_agg(p.provider_id) into v_off from (select distinct w.provider_id from pipeline.scholarship_ai_queue w where w.id = any(v_win) and w.provider_id is not null) p
   where security.provider_sch_search_off_v1(p.provider_id);
  -- v2.15.271 (Platform Admin, 14 Oct 2026): pages on a directory site, and providers whose scholarship search is Off, are closed, not read
  update pipeline.scholarship_ai_queue q
     set state = 'failed', done_at = now(), leased_until = null,
         skip_reason = case when security.third_party_host_v1(q.url) then 'directory site' else 'scholarship search off for this provider' end
   where q.id = any(v_win) and q.state in ('queued', 'leased')  -- F-SCH 13 Nov 2026: the window only (was every due item: 27 s at 8,981)
     and (security.site_host_v1(q.url) = any(v_tp) or q.provider_id = any(v_off));
  -- CF-247 15 Oct (waste rules): a queued candidate whose page was stored within the reuse time takes that copy, so it is not read again
  update pipeline.scholarship_page_candidates c set storage_path = x.storage_path, content_hash = x.content_hash, evidence_id = coalesce(c.evidence_id, x.evidence_id)
    from (select distinct on (q.candidate_id) q.candidate_id, e.storage_path, e.content_hash, e.evidence_id
            from pipeline.scholarship_ai_queue q
            join pipeline.scholarship_ai_extractions e on e.url = q.url and e.storage_path is not null and e.error is null and e.at > now() - make_interval(hours => v_reuse)
           where q.state = 'queued' and q.next_try_at <= now() and q.candidate_id is not null and not q.fresh_read  -- CF-247 4 Nov 2026: an approved fresh read takes no copy
           order by q.candidate_id, e.at desc) x
   where c.id = x.candidate_id and c.storage_path is null and v_reuse > 0;
  with pick as (
    select q.id from pipeline.scholarship_ai_queue q
     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3 and q.id = any(v_win)  -- F-SCH 13 Nov 2026: only from the checked window
       and (q.provider_id is null or q.run_kind in ('test', 'qualify') or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id))  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
       -- 13 Nov 2026: the route's switch, cap and the daily ceiling (a test or qualification run a person started is not held by a limit); a model that is not allowed waits
       and (security.ai_route_open_v1(v_rt, q.provider_id) or (q.run_kind in ('test', 'qualify') and coalesce((v_rt->>'on_demand_exempt')::boolean, false)))
       and exists (select 1 from pipeline.ai_model_catalogue am where am.code = q.model_code and am.status = 'allowed')
       and (v_paid or security.scholarship_ai_has_copy_v1(q.id))  -- the others wait, with no try used (they were refused and closed after 3 tries)
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id
     limit greatest(1, least(coalesce(p_limit, 8), 20)) for update skip locked),
  upd as (update pipeline.scholarship_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'model_code', u.model_code, 'model', m.model_identifier, 'prompt_version', u.prompt_version,
           'prompt', (select p.text from pipeline.scholarship_ai_prompts p where p.version = u.prompt_version), 'run_kind', u.run_kind, 'url', u.url, 'recovery', u.recovery,
           'scholarship_name', (select s.name from scholarship.scholarships s where s.id = u.scholarship_id),
           'candidate_id', u.candidate_id, 'scholarship_id', u.scholarship_id, 'provider_id', u.provider_id, 'country', case when u.provider_id is not null then security.coverage_country(u.provider_id) end,  -- v2.15.256
           'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = u.provider_id),
           'currency', case when u.provider_id is not null then scholarship.provider_currency(u.provider_id) else 'AUD' end,
           'storage_path', case when u.fresh_read then null else coalesce(u.storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = u.candidate_id),
                                    (select e.storage_path from pipeline.scholarship_pages sp join pipeline.evidence_artifacts e on e.id = sp.evidence_id where sp.scholarship_id = u.scholarship_id),
                                    (select e.storage_path from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id where s.id = u.scholarship_id),
                                    -- CF-247 15 Oct (waste rules): a copy of the same page stored within the reuse time
                                    (select x.storage_path from pipeline.scholarship_ai_extractions x where x.url = u.url and x.storage_path is not null and x.error is null and x.at > now() - make_interval(hours => v_reuse) order by x.at desc limit 1)) end)), '[]'::jsonb)
    into v from upd u join pipeline.ai_model_catalogue m on m.code = u.model_code;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_record(p_queue_id bigint, p_answer jsonb, p_checks jsonb, p_verdict text, p_cost numeric, p_tokens_in integer, p_tokens_out integer, p_seconds numeric, p_error text, p_storage_path text, p_sha256 text, p_final_url text, p_rule_facts jsonb, p_retry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare q pipeline.scholarship_ai_queue%rowtype; v_id bigint; v_ev uuid; v_on boolean; r jsonb; v_why text; v_next text; v_prev record;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.scholarship_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false, 'reason', 'no queue item'); end if;
  if p_retry then
    -- CF-247 7 Nov 2026: a read refused for credits, the university cap or the run's time is not the page failing. It gives its try back and waits
    -- (retry.sch_ai_wait_minutes); it is closed only when it has waited longer than sch_ai.wait_max_days. Before this it was closed "after 3 tries" (202 items).
    update pipeline.scholarship_ai_queue set attempts = greatest(attempts - 1, 0), leased_until = null,
           state = case when q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then 'failed' else 'queued' end,
           done_at = case when q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then now() end,
           skip_reason = case when q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then 'no scraper credit within the waiting time' end,
           next_try_at = now() + make_interval(mins => security.pipeline_num_v1('retry.sch_ai_wait_minutes', 30)::int) where id = q.id;
    -- an approved single read that has waited longer than the waiting time ends its request
    if q.read_request_id is not null and q.created_at < now() - make_interval(days => security.pipeline_num_v1('sch_ai.wait_max_days', 14)::int) then
      update pipeline.scholarship_read_requests set state = 'refused', finished_at = now(), outcome = jsonb_build_object('why', 'no scraper credit within the waiting time')
       where id = q.read_request_id and state = 'queued';
    end if;
    return jsonb_build_object('ok', true, 'retry', true);
  end if;
  -- v2.15.256: a value an earlier model in this chain proved stands when this model's value is not proven (its own proven value wins)
  if p_error is null and p_verdict = 'scholarship' and not coalesce((p_checks->>'value')::boolean, false)
     and coalesce(p_answer->'value'->>'kind', 'not_stated') not in ('not_stated', 'non_monetary') then
    select e.answer->'value' val, e.model_code into v_prev from pipeline.scholarship_ai_extractions e join pipeline.scholarship_ai_queue x on x.id = e.queue_id
     where coalesce(x.root_id, x.id) = coalesce(q.root_id, q.id) and x.id <> q.id and e.verdict = 'scholarship' and e.error is null
       and coalesce((e.checks->>'value')::boolean, false) order by e.id desc limit 1;
    if v_prev.val is not null then
      p_answer := jsonb_set(p_answer, '{value}', v_prev.val) || jsonb_build_object('value_from', v_prev.model_code);
      p_checks := p_checks || jsonb_build_object('value', true);
    end if;
  end if;
  -- a candidate page read live for the first time: its copy and read are recorded on the candidate, as the scheduled reader does
  if q.candidate_id is not null and p_storage_path is not null then
    update pipeline.scholarship_page_candidates set storage_path = p_storage_path, content_hash = p_sha256, final_url = coalesce(p_final_url, final_url), read_at = now(),
           read_status = coalesce(nullif(p_rule_facts->>'read_status', ''), 'read'), next_read_at = now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_ai_days', 90)::int), leased_until = null,
           facts = case when p_rule_facts ? 'facts' then p_rule_facts->'facts' else facts end
     where id = q.candidate_id;
  end if;
  if p_storage_path is not null then
    insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
    values (security.coverage_sweep_source(q.provider_id), 'scholarship_ai_page', coalesce(p_final_url, q.url), p_storage_path, p_sha256, 'application/gzip',
            jsonb_build_object('queue_id', q.id, 'candidate_id', q.candidate_id, 'scholarship_id', q.scholarship_id, 'model', q.model_code, 'worker', 'coverage-sweep scholarship_ai'), 1, 'scholarship_ai:' || q.id)
    returning id into v_ev;
    if q.candidate_id is not null then update pipeline.scholarship_page_candidates set evidence_id = coalesce(evidence_id, v_ev) where id = q.candidate_id; end if;
  end if;
  insert into pipeline.scholarship_ai_extractions(queue_id, model_code, model_identifier, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url,
         storage_path, content_hash, evidence_id, answer, checks, verdict, cost_usd, tokens_in, tokens_out, seconds, error)
  values (q.id, q.model_code, (select m.model_identifier from pipeline.ai_model_catalogue m where m.code = q.model_code), q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id,
          coalesce(p_final_url, q.url), coalesce(p_storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = q.candidate_id)), p_sha256,
          coalesce(v_ev, (select c.evidence_id from pipeline.scholarship_page_candidates c where c.id = q.candidate_id), (select sp.evidence_id from pipeline.scholarship_pages sp where sp.scholarship_id = q.scholarship_id)),
          p_answer, p_checks, p_verdict, p_cost, p_tokens_in, p_tokens_out, p_seconds, p_error)
  returning id into v_id;
  -- v2.15.250 (bugs 11/10-6 follow-up): an unsettled answer (failed reply, name not proven, or a stated fact not proven by its quote)
  -- goes to the next model in the chain, on the same stored copy; after the last model it goes to Layer 4 while AI admission is on
  -- CF-247 4 Nov 2026: an approved single read whose page could not be read ends here (one read; no retry, no other model)
  if q.read_request_id is not null and p_error is not null and p_storage_path is null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    r := security.scholarship_read_request_close_v1(q.read_request_id, v_id, 'read_failed', 'Approved read: the page could not be read (' || left(p_error, 200) || ')');
    return jsonb_build_object('ok', true, 'extraction', v_id, 'request', r);
  end if;
  v_why := case when q.run_kind in ('admit', 'reread') then security.scholarship_ai_unsettled_v1(p_answer, p_checks, p_verdict, p_error) end;
  -- v2.15.250 (23:50): an answer that would admit is confirmed by the next model while confirm_admissions is on
  if v_why is null and q.run_kind in ('admit', 'reread') and p_error is null and p_verdict = 'scholarship' and p_answer->>'audience' in ('international', 'both')
     and coalesce((p_checks->>'audience')::boolean, false) and coalesce(p_answer->>'offered', '') <> 'no'
     and coalesce((select s.confirm_admissions from pipeline.scholarship_ai_extract_settings s where s.id = 1), true)
     and security.scholarship_ai_next_model_v1(q.model_code) is not null then
    v_why := 'a second model confirms each admission';
  end if;
  v_next := case when v_why is not null then security.scholarship_ai_next_model_v1(q.model_code) end;
  if v_next is not null then
    update pipeline.scholarship_ai_queue set state = 'done', done_at = now(), leased_until = null, extraction_id = v_id where id = q.id;
    insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, sample_id, candidate_id, scholarship_id, provider_id, url, step, storage_path, root_id, fresh_read, read_request_id)
    values (v_next, q.prompt_version, q.run_kind, q.job_id, q.sample_id, q.candidate_id, q.scholarship_id, q.provider_id, coalesce(p_final_url, q.url), q.step + 1,
            coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id), q.fresh_read and coalesce(p_storage_path, q.storage_path) is null, q.read_request_id);
    return jsonb_build_object('ok', true, 'extraction', v_id, 'escalated_to', v_next, 'why', v_why);
  end if;
  update pipeline.scholarship_ai_queue set state = case when p_error is null or attempts >= 3 then 'done' else 'queued' end, done_at = case when p_error is null or attempts >= 3 then now() end,
         leased_until = null, next_try_at = now() + interval '10 minutes', extraction_id = v_id where id = q.id;
  -- CF-247 4 Nov 2026: an approved single read never admits or publishes; its answer goes to the held item in Layer 4, where the decision stays
  if q.read_request_id is not null then
    if p_error is null or q.attempts >= 3 then
      r := security.scholarship_read_request_close_v1(q.read_request_id, v_id, case when p_error is null then 'read' else 'read_failed' end,
             coalesce(v_why, 'Approved read: answer recorded; the decision stays in Layer 4'));
    end if;
    return jsonb_build_object('ok', true, 'extraction', v_id, 'request', r);
  end if;
  select ai_admission into v_on from pipeline.scholarship_ai_extract_settings where id = 1;
  -- F-SCH redesign (12 Nov 2026, directive §5 and §9): after the last model, a stated fact its quote does not prove is dropped (unknown) and the
  -- proven remainder goes through the governed admission path; a technical failure stays on the extraction for the coverage classifier and recoveries.
  -- Neither is a Layer 4 review. A detail read (run_kind detail) only fills empty canonical fields.
  if v_on and v_why is not null and p_error is null and q.run_kind = 'admit' then
    update pipeline.scholarship_ai_extractions set answer = security.scholarship_ai_strip_unproven_v1(answer, checks) where id = v_id;
    r := coalesce(security.scholarship_ai_apply_v1(v_id), '{}'::jsonb) || jsonb_build_object('unproven_dropped', v_why);
  elsif v_on and v_why is not null and p_error is null and q.run_kind = 'reread' then
    -- a re-read that does not prove a stated fact again never withdraws on that ground: the record keeps its admitted facts and their evidence
    r := jsonb_build_object('unproven_kept', v_why) || case when coalesce(q.prompt_version, 0) >= 3 then jsonb_build_object('detail', security.scholarship_detail_apply_v1(v_id)) else '{}'::jsonb end;
    update pipeline.scholarship_ai_extractions set applied = r || jsonb_build_object('at', now()) where id = v_id;
  elsif v_on and v_why is not null and p_error is not null and q.attempts >= 3 then r := jsonb_build_object('technical_failure', left(p_error, 200));
  elsif p_error is null and v_on and q.run_kind in ('admit', 'reread') then r := security.scholarship_ai_apply_v1(v_id);
  elsif p_error is null and q.run_kind = 'detail' then
    r := security.scholarship_detail_apply_v1(v_id);
    update pipeline.scholarship_ai_extractions set applied = coalesce(r, '{}'::jsonb) || jsonb_build_object('at', now()) where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'extraction', v_id, 'applied', r);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_eligibility_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- F-SCH.01: leases due reads for worker mode scholarship_eligibility with the pinned first model of the scholarship chain (the same model as the
-- re-check reader); held while sch_elig.on is 0 or the AI guards refuse (credit floor, daily ceiling, lane guard scholarship_ai).
declare v jsonb; v_model text; v_why text; v_rt jsonb := security.ai_route_gate_v1('scholarship_eligibility');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if security.pipeline_num_v1('sch_elig.on', 0) < 1 then return jsonb_build_object('items', '[]'::jsonb, 'held', 'sch_elig.on is 0'); end if;
  v_why := security.ai_use_refusal_v1('scholarship_ai');
  if v_why is not null then return jsonb_build_object('items', '[]'::jsonb, 'held', v_why); end if;
  v_model := v_rt->>'model';  -- 13 Nov 2026: the route (pipeline.ai_service_routes)
  if v_model is null then return jsonb_build_object('items', '[]'::jsonb, 'held', coalesce(v_rt->>'held_reason', 'no allowed model in the cascade')); end if;
  if (v_rt->>'held')::boolean and not (coalesce((v_rt->>'on_demand_exempt')::boolean, false) and jsonb_array_length(v_rt->'on_demand_providers') > 0) then return jsonb_build_object('items', '[]'::jsonb, 'held', v_rt->>'held_reason'); end if;
  with pick as (
    select e.candidate_id from pipeline.scholarship_eligibility_reads e
     where ((e.state = 'queued' and coalesce(e.next_try_at, '-infinity') <= now()) or (e.state = 'leased' and e.leased_until < now()))
       and security.ai_route_open_v1(v_rt, e.provider_id)
     order by e.queued_at, e.candidate_id limit greatest(1, least(coalesce(p_limit, 10), 40))  -- fixed: the worker's upper bound per call
     for update skip locked),
  upd as (update pipeline.scholarship_eligibility_reads e set state = 'leased', leased_until = now() + interval '15 minutes', tries = e.tries + 1, updated_at = now()  -- fixed: lease timer
            from pick where e.candidate_id = pick.candidate_id returning e.candidate_id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'url', coalesce(c.final_url, c.url), 'storage_path', c.storage_path, 'provider_id', c.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = c.provider_id),
           'country', security.coverage_country(c.provider_id),
           'name', coalesce(nullif(btrim(c.facts->'admission'->>'name'), ''), nullif(btrim(c.facts->'ai'->>'name'), ''), c.title, ''),
           'model', v_model, 'models', v_rt->'models',
           'link_follow', security.pipeline_num_v1('sch_elig.link_follow_on', 1) >= 1,
           'links_max', security.pipeline_num_v1('sch_elig.links_max', 1)::int)), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_page_candidates c on c.id = u.candidate_id;
  return jsonb_build_object('items', v);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_recheck_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_model text; v_rt jsonb := security.ai_route_gate_v1('scholarship_extraction');
        -- CF-247 P0 mandate 3 Nov 2026 §6: while the scholarship Firecrawl lane is held, only reviews with a stored copy are re-checked
        v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  v_model := v_rt->>'model';  -- 13 Nov 2026: the route (pipeline.ai_service_routes)
  if v_model is null then return '[]'::jsonb; end if;
  with pick as (
    select r.id from pipeline.scholarship_ai_reviews r
     where r.status = 'pending'
       and (r.recheck->>'state' = 'queued' or (r.recheck->>'state' = 'leased' and (r.recheck->>'leased_until')::timestamptz < now()))
       and (r.provider_id is null or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id))  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
       and security.ai_route_open_v1(v_rt, r.provider_id)
       and (v_paid or r.storage_path is not null)  -- the others wait (a refused read was recorded as "the page could not be read again")
     order by r.id limit greatest(1, least(coalesce(p_limit, 12), 40)) for update skip locked),
  upd as (update pipeline.scholarship_ai_reviews r set recheck = r.recheck || jsonb_build_object('state', 'leased', 'leased_until', now() + interval '10 minutes',  -- fixed: lease timer
                                                                                         'tries', coalesce((r.recheck->>'tries')::int, 0) + 1)
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'url', u.url, 'storage_path', u.storage_path, 'provider_id', u.provider_id, 'reason', u.reason, 'model', v_model, 'models', v_rt->'models',
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = u.provider_id),
           'country', security.coverage_country(u.provider_id),
           'name', (select e.answer->>'name' from pipeline.scholarship_ai_extractions e where e.id = u.extraction_ids[array_upper(u.extraction_ids, 1)]))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION security.aer_v2_shadow_hold_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v record; v_rt jsonb := security.ai_route_v1('entry_requirements_v2_shadow'); v_spent numeric; v_today numeric; v_budget numeric := security.pipeline_num_v1('aer.v2_shadow_budget_usd', 20);
        v_daily numeric := security.pipeline_num_v1('aer.v2_shadow_daily_usd', 3);
begin
  select x.version, x.system_text, x.system_sha256, x.model, x.quote_max_chars into v
    from pipeline.aer_prompt_versions x where x.purpose = 'course_page' and x.status = 'trial' order by x.created_at desc limit 1;
  select coalesce(sum(r.cost_usd), 0),
         coalesce(sum(r.cost_usd) filter (where r.created_at >= date_trunc('day', now() at time zone 'utc') at time zone 'utc'), 0)  -- fixed: the UTC day, as the AI ledger counts it
    into v_spent, v_today from pipeline.aer_v2_shadow_results r;
  return jsonb_build_object(
    'held', case when security.pipeline_num_v1('aer.v2_shadow_on', 0) < 1 then 'switched off (aer.v2_shadow_on)'
                 when v.version is null then 'no trial prompt version'
                 when coalesce((v_rt->>'held')::boolean, true) then coalesce(v_rt->>'held_reason', 'the route is held')  -- 13 Nov 2026: the route's switch, cap and the daily ceiling
                 when v_spent >= v_budget then format('trial budget reached: US$%s of US$%s (aer.v2_shadow_budget_usd)', round(v_spent, 4), v_budget)
                 when v_today >= v_daily then format('daily share reached: US$%s of US$%s today (aer.v2_shadow_daily_usd)', round(v_today, 4), v_daily) end,
    'version', case when v.version is not null then jsonb_build_object('version', v.version, 'system_text', v.system_text, 'system_sha256', v.system_sha256,
                                                                        'model', v_rt->>'model', 'models', v_rt->'models', 'quote_max_chars', v.quote_max_chars) end,  -- the model is the route's; the prompt text and its sha are the version's
    'budget', jsonb_build_object('usd', v_budget, 'spent', v_spent, 'daily_usd', v_daily, 'today', v_today));
end $function$;

CREATE OR REPLACE FUNCTION public.svc_aer_v2_shadow_record(p_course_id uuid, p_prompt_version text, p_model text, p_evidence_id uuid, p_content_hash text, p_records jsonb, p_checks jsonb, p_seen_not_mapped jsonb, p_cost_usd numeric, p_error text, p_worker text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_model text; v_prov uuid; v_pass int; v_fail int; v_id bigint;
        v_checks jsonb := case when jsonb_typeof(p_checks) = 'array' then p_checks else '[]'::jsonb end;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.aer_prompt_versions x where x.version = p_prompt_version) then raise exception 'unknown AER prompt version %', p_prompt_version; end if;
  select x->>'model_identifier' into v_model from jsonb_array_elements(security.ai_route_v1('entry_requirements_v2_shadow')->'models') x where x->>'model_identifier' = p_model;
  if p_model is distinct from v_model then raise exception 'model % is not a model of the route entry_requirements_v2_shadow', p_model; end if;  -- pinned: only a model of the route's cascade is kept
  select c.provider_id into v_prov from catalogue.courses c where c.id = p_course_id;
  if v_prov is null then raise exception 'course % not found', p_course_id; end if;
  select count(*) filter (where coalesce((x->>'pass')::boolean, false)), count(*) filter (where not coalesce((x->>'pass')::boolean, false))
    into v_pass, v_fail from jsonb_array_elements(v_checks) x;
  -- shadow only: the result is kept here and nowhere else (no catalogue table, no Layer 4 item)
  insert into pipeline.aer_v2_shadow_results(prompt_version, model, course_id, provider_id, evidence_id, content_hash, records, checks, seen_not_mapped, passed, failed, cost_usd, error, worker)
  values (p_prompt_version, p_model, p_course_id, v_prov, p_evidence_id, p_content_hash,
          case when jsonb_typeof(p_records) = 'array' then p_records else '[]'::jsonb end, v_checks,
          case when jsonb_typeof(p_seen_not_mapped) = 'array' then p_seen_not_mapped else '[]'::jsonb end,
          v_pass, v_fail, greatest(coalesce(p_cost_usd, 0), 0), left(p_error, 400), left(p_worker, 40))  -- fixed: column display lengths
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'passed', v_pass, 'failed', v_fail);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_coverage_ai_match_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb; v_rt jsonb := security.ai_route_gate_v1('course_matching');  -- 13 Nov 2026: the model and the budget come from the route
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if; if not security.ai_use_allowed_v1('course_match') then return '[]'::jsonb; end if;  -- Decision 5 E-7 (2 Nov 2026): nothing new is claimed while AI use is refused
  with pick as (
    select q.id from pipeline.coverage_ai_match q
      left join pipeline.course_priority cp on cp.course_id = q.course_id
      left join pipeline.provider_priority pp on pp.provider_id = q.provider_id
     where (q.state = 'ready' or (q.state = 'leased' and q.leased_until < now()))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and security.ai_route_open_v1(v_rt, q.provider_id)
     order by (q.state = 'leased'), coalesce(cp.sort, 1000000), coalesce(pp.rank, 100000), q.id
     limit greatest(1, least(coalesce(p_limit, 20), 80)) for update of q skip locked),
  upd as (update pipeline.coverage_ai_match q set state = 'leased', leased_until = now() + interval '10 minutes' from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'course_id', u.course_id, 'provider_id', u.provider_id, 'title', co.canonical_title,
           'code', case when co.course_code ~ '^[0-9a-f]{8}-' then null else co.course_code end,
           'level', (select sl.name from ref.study_levels sl where sl.id = co.study_level_id),
           'provider', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(u.provider_id),
           'candidates', u.candidates, 'model', v_rt->>'model', 'models', v_rt->'models')), '[]'::jsonb)
    into v from upd u join catalogue.courses co on co.id = u.course_id join catalogue.providers pr on pr.id = u.provider_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_enrich_ai_record(p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; i pipeline.field_enrich_items%rowtype; v_val jsonb; v_out jsonb := '{}'::jsonb; v_k text; v_ev uuid;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    select * into i from pipeline.field_enrich_items where id = (r->>'item_id')::bigint for update;
    if i.id is null then continue; end if;
    -- CF-247 Release B (D3): the reader version recorded with an absence (pipeline.course_field_absence.reader_version)
    perform set_config('cf247.reader_version', left(coalesce(nullif(concat_ws(' ', nullif(r->>'worker', ''), nullif(r->>'prompt_version', ''), nullif(r->>'model', '')), ''),
                                                                'enrich_ai ' || coalesce(i.source, '') || ' ' || coalesce(security.ai_service_model_v1(security.ai_ledger_service_v1('enrich_fields', 'field_enrich_items', jsonb_build_object('field', i.field))), '')), 200), true);
    v_ev := i.evidence_id;
    if r->>'storage_path' is not null then
      insert into pipeline.evidence_artifacts(source_id, evidence_type, source_url, storage_path, content_hash, mime_type, metadata, capture_version, evidence_group_key)
      values (security.coverage_sweep_source(i.provider_id), 'enrich_home_page', r->>'url', r->>'storage_path', r->>'sha256', 'application/gzip',
              jsonb_build_object('item_id', i.id, 'provider_id', i.provider_id, 'worker', 'coverage-sweep enrich_ai'), 1, 'enrich:' || i.id)
      returning id into v_ev;
    end if;
    update pipeline.field_enrich_items set cost_usd = coalesce(cost_usd, 0) + coalesce((r->>'cost')::numeric, 0), model = coalesce(nullif(r->>'model', ''), model), evidence_id = v_ev,
           storage_path = coalesce(r->>'storage_path', storage_path), leased_until = null, updated_at = now() where id = i.id;
    if r->>'retry' = 'true' then
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'reason', 300) where id = i.id;
      v_k := 'retry';
    elsif r->>'error' is not null then
      update pipeline.field_enrich_items set state = case when attempts >= 3 then 'failed' else 'ai' end, reason = left(r->>'error', 300) where id = i.id;
      v_k := 'error';
    elsif i.field = 'campus' then
      if nullif(btrim(r->'value'->>'campus'), '') is not null then
        update pipeline.field_enrich_items set state = 'waiting', quote = left(r->'value'->>'campus', 300) where id = i.id; v_k := 'campus_named';
      else
        if security.enrich_fallback_v1(i.id) then v_k := 'provider_fact';  -- 22 Oct 2026 (fix 4): the provider's only campus
        else update pipeline.field_enrich_items set state = 'skipped', reason = 'the page names no campus' where id = i.id; v_k := 'not_stated'; end if;
      end if;
    elsif i.field = 'entry_requirements' then
      -- CF-247 Track C Step B (28 Oct 2026): course academic entry requirements, proposed for a person (B1)
      v_k := security.enrich_entry_record_v1(i.id, r);
    elsif i.field in ('description', 'deadline') then
      -- CF-247 Workstream C (3 Nov 2026): course description and application deadline from the stored course page
      v_k := security.enrich_course_text_record_v1(i.id, r);
    elsif i.field = 'campus_list' then
      update pipeline.field_enrich_items set value = jsonb_build_object('campuses', coalesce(r->'value'->'campuses', '[]'::jsonb)), quote = left(r->>'quote', 300) where id = i.id;
      v_k := 'campus_list'; perform security.enrich_campus_list_apply_v1(i.id);
    else
      v_val := case i.field
        when 'duration' then security.enrich_parse_duration_v1(r->>'quote')
        when 'delivery' then (select jsonb_build_object('mode', r->'value'->>'mode') where r->'value'->>'mode' in ('on_campus', 'online', 'blended', 'on_campus_and_online'))
        when 'level' then (select jsonb_build_object('level_id', l.id) from ref.study_levels l where l.short_code = r->'value'->>'level')
        when 'field_of_study' then (select jsonb_build_object('field_id', f.id) from ref.fields_of_study f where f.code = r->'value'->>'field' and f.code ~ '^asced-\d{4}$')
        when 'international' then (select jsonb_build_object('open', (r->'value'->>'open')::boolean) where r->'value'->>'open' in ('true', 'false'))
        when 'provider_address' then (select r->'value' where nullif(btrim(r->'value'->>'street'), '') is not null)
        when 'english' then security.enrich_parse_english_v1(r->'value'->>'text', r->>'quote')
        when 'intakes' then coalesce(security.enrich_parse_intakes_v1(r->'value'->>'text', r->>'quote'),
                                     security.enrich_parse_intake_periods_v1(i.provider_id, r->'value'->>'text', r->>'quote'))  -- 23 Oct 2026: semesters from the approved calendar
        when 'campus_region' then (select r->'value' where jsonb_array_length(coalesce(r->'value'->'cities', '[]'::jsonb)) > 0)
        when 'campus' then null end;
      if v_val is null then
        if security.enrich_fallback_v1(i.id) then v_k := 'provider_fact';  -- 22 Oct 2026 (fix 4): a provider-level or registered fact
        else
        update pipeline.field_enrich_items set state = 'skipped', reason = coalesce(nullif(r->>'reason', ''), 'the page does not state it') where id = i.id;
        v_k := 'not_stated';
        end if;
      else
        update pipeline.field_enrich_items set value = v_val, quote = left(coalesce(r->>'quote', i.quote), 300) where id = i.id;
        v_k := security.enrich_apply_v1(i.id);
      end if;
    end if;
    v_out := v_out || jsonb_build_object(v_k, coalesce((v_out->>v_k)::int, 0) + 1);
  end loop;
  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_settings_register_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'sections', (select coalesce(jsonb_agg(jsonb_build_object('section', z.section, 'settings', z.settings) order by z.first_sort), '[]'::jsonb)
                   from (select s.section, min(s.sort) first_sort,
                                jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                                          'unit', s.unit, 'home', s.home, 'home_group', s.home_group, 'used_by', s.used_by, 'reason', s.reason, 'updated_at', s.updated_at,
                                          'control_class', s.control_class,
                                          'replaced_by', (select r.replaced_by from pipeline.component_register r where r.name = s.toolset_key || '.' || s.key and r.status = 'retiring' limit 1)) order by s.sort, s.key) settings
                           from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' group by s.section) z),
    'check', (select coalesce(jsonb_agg(jsonb_build_object('job', c.jobname, 'detail', c.detail)), '[]'::jsonb) from security.controls_check_v1() c),
    'jobs', (select count(*) from cron.job where active));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_toolsets_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'toolsets', (select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'kind', t.kind, 'layers', t.layers, 'enforcement', t.enforcement, 'help', t.help,
        'updated_at', t.updated_at, 'reason', t.reason,
        'key_saved', (select p.vault_secret_id is not null from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'switched_on', (select p.enabled from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'plan', case when exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = t.key and s.key = 'plan_credits') then security.toolset_plan_status(t.key) end,
        'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                        'unit', s.unit, 'home', s.home, 'home_group', s.home_group, 'section', s.section, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.toolset_key = t.key)) order by t.sort), '[]'::jsonb)
      from pipeline.platform_toolsets t where t.key <> 'pipeline'),  -- v2.15.269: the register shows on Pipeline settings
    'openrouter', jsonb_build_object(
      'balance', (select jsonb_build_object('remaining_usd', o.remaining_usd, 'observed_at', o.observed_at, 'total_credits', o.payload->'total_credits', 'total_usage', o.payload->'total_usage')
                  from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
      -- v2.15.258 (bug 12/10-01): the AI uses that run now, with their daily guards and the credit floor (Layer 3 retired)
      'credit_floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
      'uses', (select coalesce(jsonb_agg(jsonb_build_object('use', g.use, 'label', g.label, 'spent_today', g.spent, 'guard', g.guard, 'calls', g.calls,
                    'allowed', security.ai_use_allowed_v1(g.use))), '[]'::jsonb) from security.ai_spend_today_v1() g),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select r.day, round(sum(r.usd), 4) usd, sum(r.calls) calls from (
                               select (x.at at time zone 'UTC')::date as day, sum(x.cost_usd) usd, count(*) calls from pipeline.scholarship_ai_extractions x where x.at > now() - interval '14 days' group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.uni_adapter_drafts x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.central_ai_queue x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (coalesce(x.decided_at, x.created_at) at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.coverage_ai_match x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1) r
                             group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $function$;

CREATE OR REPLACE FUNCTION security.ledger_retention_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n_ledger int; n_zy int; n_h int; n_ui int; n_ai int;
begin
  delete from pipeline.mode_outcome_ledger where run_at < now() - make_interval(days => security.pipeline_num_v1('retention.mode_outcome_ledger_days', 90)::int);
  get diagnostics n_ledger = row_count;
  delete from pipeline.zero_yield_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.zero_yield_snapshots_days', 90)::int);
  get diagnostics n_zy = row_count;
  delete from pipeline.health_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.health_snapshots_days', 90)::int);
  get diagnostics n_h = row_count;
  delete from pipeline.ui_error_log where at < now() - make_interval(days => security.pipeline_num_v1('retention.ui_error_log_days', 90)::int);
  get diagnostics n_ui = row_count;
  delete from pipeline.ai_invocations where at < now() - make_interval(days => security.pipeline_num_v1('retention.ai_invocations_days', 90)::int);
  get diagnostics n_ai = row_count;
  return jsonb_build_object('mode_outcome_ledger', n_ledger, 'zero_yield_snapshots', n_zy, 'health_snapshots', n_h, 'ui_error_log', n_ui, 'ai_invocations', n_ai);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_description_run_v1(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_rank int:=security.current_role_rank(); c pipeline.provider_description_cohorts%rowtype;
 v_res jsonb; v_preview jsonb; v_fresh jsonb; x jsonb; v_id uuid; v_reason text:=btrim(coalesce(p_args->>'reason','')); v_n int:=0; v_run uuid; v_why text;
 v_mode text; v_args jsonb; v_ids uuid[]; v_history jsonb; v_rule text; v_diagnosis jsonb; v_context jsonb; v_issue bigint; v_ai_request bigint; v_ai_model text; v_ai_why text; v_job pipeline.automation_catalogue%rowtype; v_dispatch_error text; v_dispatch_sqlstate text;
begin
 if v_actor is null or v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
 select * into v_job from pipeline.automation_catalogue where jobname='provider-description-read';
 if p_action='verify' and v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
 if p_action='capabilities' then
 return jsonb_build_object('contract','provider-description-run-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
 'can_explain',v_rank>=coalesce(v_job.control_rank,6),'can_diagnose',security.pipeline_num_v1('ops.ai_diagnosis_on',0)>=1 and security.ai_use_allowed_v1('ops_diagnose') and nullif(security.ai_route_v1('ops_diagnosis')->>'model','') is not null,'ai_diagnosis_reason','AI assistance requires the existing approved Operations diagnosis switch, model and spending guards plus an existing open issue linked to this exact provider and evidence. Explain evidence always uses stored checks.',
 'countries',coalesce((select jsonb_agg(jsonb_build_object('code',k.iso_alpha2,'label',coalesce(to_jsonb(k)->>'name',to_jsonb(k)->>'country_name',k.iso_alpha2::text),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.countries'),'[]')?k.iso_alpha2::text)) from ref.countries k where k.iso_alpha2 in ('AU','NZ','CA')),'[]'),
 'provider_types',coalesce((select jsonb_agg(jsonb_build_object('code',t.code,'label',coalesce(to_jsonb(t)->>'label',to_jsonb(t)->>'name',t.code),'enabled',coalesce(security.toolset_setting('pipeline','pdesc.provider_types'),'[]')?t.code)) from ref.provider_types t),'[]'),
 'providers',coalesce((select jsonb_agg(jsonb_build_object('provider_id',p.id,'name',coalesce(p.display_name,p.canonical_name),'country',k.iso_alpha2,'type',t.code) order by coalesce(p.display_name,p.canonical_name)) from catalogue.providers p join ref.countries k on k.id=p.country_id left join ref.provider_types t on t.id=p.provider_type_id where security.provider_description_scope_v1(p.id)),'[]'),
 'min_size',1,'max_size',security.provider_description_cohort_cap_v1(),'default_size',security.pipeline_num_v1('batch.provider_description',3)::int,
 'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
 'model',(select security.ai_route_v1('provider_description')->>'model'),'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,
 'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
 'policy',jsonb_build_object('countries',security.toolset_setting('pipeline','pdesc.countries'),'types',security.toolset_setting('pipeline','pdesc.provider_types'),'provider_keys',security.toolset_setting('pipeline','pdesc.provider_keys'),'ai_usd_max',security.pipeline_num_v1('pdesc.ai_usd_max',1),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'reserved_usd',(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads),'remaining_usd',greatest(0,security.pipeline_num_v1('pdesc.ai_usd_max',1)-(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')-(select coalesce(sum(reserved_usd),0) from pipeline.provider_description_reads)),'actual_ai_calls',(select coalesce(sum(ai_calls),0) from pipeline.provider_description_reads),'recorded_billable_calls',(select coalesce(sum(calls),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'recorded_cost_usd',(select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening'),'ai_call_counter_scope','reported model calls since provider-description-autonomy instrumentation; ledger calls are separate recorded billable calls','budget_period','lifetime pilot','required_approval','Individual human Layer 4 decision'));
 elsif p_action='preview' then
 v_args:=p_args||jsonb_build_object('mode',coalesce(nullif(p_args->>'mode',''),'stored'));
 -- Fill fields (Provider Catalogue and Provider Detail): the screen names what it wants to do; the governed selection gets the same description state it always had.
 if nullif(p_args->>'fill_mode','') is not null then
  if p_args->>'fill_mode' not in ('missing','upgrade_basic') then raise exception 'unsupported fill mode' using errcode='22023'; end if;
  v_args:=v_args||jsonb_build_object('description_state',case p_args->>'fill_mode' when 'upgrade_basic' then 'stale' else 'missing' end,'upgrade',p_args->>'fill_mode'='upgrade_basic');
 end if;
 v_res:=security.provider_description_selection_multi_v1(v_args);
 insert into pipeline.provider_description_cohorts(requested_by,selection,snapshot,expires_at)
 values(v_actor,v_args,v_res,now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int)) returning id into v_id;
 return v_res||jsonb_build_object('token',v_id,'preview_token',v_id,'expires_at',now()+make_interval(mins=>security.pipeline_num_v1('pdesc.ui_preview_minutes',10)::int));
 elsif p_action='prepare' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot prepare this job' using errcode='42501'; end if;
 if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason is shorter than the governed minimum' using errcode='22023'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'preview_token','')::uuid and requested_by=v_actor for update;
 if c.id is null then raise exception 'unknown owned preview' using errcode='42501'; end if;
 if c.state in ('prepared','started') then return security.provider_description_run_result_v1(c.id); end if;
 if c.expires_at<now() then raise exception 'preview expired; preview again' using errcode='22023'; end if;
 v_fresh:=security.provider_description_selection_multi_v1(c.selection);
 for x in select * from jsonb_array_elements(c.snapshot->'providers') where (value->>'eligible')::boolean loop
  if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where f->>'provider_id'=x->>'provider_id' and (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description' and f->>'last_read_id' is not distinct from x->>'last_read_id') then raise exception 'preview changed; preview again' using errcode='22023'; end if;
  v_n:=v_n+1;
  insert into pipeline.provider_description_cohort_members(cohort_id,provider_id,evidence_id,pick,snapshot) values(c.id,(x->>'provider_id')::uuid,(x->>'evidence_id')::uuid,v_n,x);
 end loop;
 if v_n=0 then raise exception 'no eligible provider with approved evidence in this preview' using errcode='22023'; end if;
 update pipeline.provider_description_cohorts set state='prepared',reason=v_reason,prepared_at=now() where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','cohort_prepare',c.id::text,jsonb_build_object('selected',v_n,'reason',v_reason,'selection',c.selection),v_actor);
 return security.provider_description_run_result_v1(c.id);
 elsif p_action='run' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot start this job' using errcode='42501'; end if;
 select * into c from pipeline.provider_description_cohorts where id=nullif(p_args->>'cohort_id','')::uuid and requested_by=v_actor for update;
 if c.id is null or c.state='preview' then raise exception 'unknown owned fixed cohort' using errcode='42501'; end if;
 if c.run_id is not null then return security.provider_description_run_result_v1(c.id)||jsonb_build_object('repeat',true); end if;
 if (select count(*) from pipeline.provider_description_cohort_members where cohort_id=c.id)>security.provider_description_cohort_cap_v1() then
   raise exception 'current_cap_changed: the fixed cohort exceeds the current governed cap; prepare a new cohort' using errcode='22023';
 end if;
 -- Same task kind, catalogue permission, pause/spend/review rules and provider-description job. Never a second scheduler.
 v_why:=case when not coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read' then 'job_not_allowlisted'
 when v_job.jobname is null then 'job_not_catalogued'
 when not exists(select 1 from cron.job where jobname='provider-description-read' and active) then 'job_paused'
 when security.pipeline_num_v1('pdesc.enabled',0)<1 then 'reader_off'
 when not security.ai_use_allowed_v1('provider_description') then 'ai_refused'
 when (select coalesce(sum(cost_usd),0) from pipeline.ai_spend_ledger where lane='provider_description' and source<>'opening')>=security.pipeline_num_v1('pdesc.ai_usd_max',1) then 'ai_ceiling'
 when (select count(*) from pipeline.layer4_review_items where field_code='provider_description' and status='pending')>=security.pipeline_num_v1('pdesc.pending_max',10) then 'review_full' end;
 -- Policy/capacity holds are durable: the fixed cohort stays recoverable and the existing scheduled job resumes it.
 for x in select m.snapshot from pipeline.provider_description_cohort_members m where m.cohort_id=c.id order by m.pick loop
   v_fresh:=security.provider_description_selection_v1(c.selection||jsonb_build_object('provider_id',x->>'provider_id','size',1));
   if not exists(select 1 from jsonb_array_elements(v_fresh->'providers') f where (f->>'eligible')::boolean and f->>'evidence_id' is not distinct from x->>'evidence_id' and f->>'source_hash' is not distinct from x->>'source_hash' and f->>'current_description' is not distinct from x->>'current_description') then
     update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('eligibility_reason','selection_changed_before_run','eligible',false) where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid; continue;
   end if;
   insert into pipeline.provider_description_reads(provider_id) values((x->>'provider_id')::uuid) on conflict do nothing returning id into v_id;
   if v_id is null then select id into v_id from pipeline.provider_description_reads where provider_id=(x->>'provider_id')::uuid and state in ('queued','reading','proposed') order by created_at desc limit 1; end if;
   update pipeline.provider_description_cohort_members set read_id=v_id where cohort_id=c.id and provider_id=(x->>'provider_id')::uuid;
   v_n:=v_n+1; v_id:=null;
 end loop;
 update pipeline.provider_description_cohorts set state='started' where id=c.id;
 if v_why is null and v_n>0 then
   perform set_config('cf.pdesc_run_now',c.id::text,true);
   begin
     v_res:=security.provider_description_fire_v1();
   exception when others then
     -- OTHERS deliberately excludes query cancellation: the caller's statement/lock limits remain authoritative.
     get stacked diagnostics v_dispatch_error=message_text,v_dispatch_sqlstate=returned_sqlstate;
     v_res:=jsonb_build_object('sent',0,'parked',true,'reason','reader_dispatch_failed','error',v_dispatch_error,'sqlstate',v_dispatch_sqlstate,'retry_strategy','existing provider-description-read schedule resumes this saved queued cohort');
   end;
 else v_res:=jsonb_build_object('sent',0,'parked',true,'reason',coalesce(v_why,'selection_changed_before_run')); end if;
 insert into pipeline.admin_jobs(kind,lane,state,title,args,result,error,requested_by,reason,started_at,finished_at,scope,outcome)
 values('job_run_now','run_now',case when v_dispatch_error is not null then 'failed' when v_why is null then 'done' else 'cancelled' end,'Provider descriptions: bounded Run Now',jsonb_build_object('job','provider-description-read','cohort_id',c.id,'idempotency_key',c.request_key),v_res||jsonb_build_object('selected',v_n,'admitted',0,'publication_measured_separately',true),v_dispatch_error,v_actor,c.reason,now(),clock_timestamp(),'cohort:'||c.id,case when v_dispatch_error is not null then 'failed_retryable' when v_why is not null then 'blocked_policy' else 'succeeded_no_movement' end) returning id into v_run;
 update pipeline.provider_description_cohorts set run_id=v_run where id=c.id;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','run_now','provider-description-read',jsonb_build_object('cohort_id',c.id,'run_id',v_run,'dispatch',v_res,'reason',c.reason),v_actor);
 return security.provider_description_run_result_v1(c.id)||jsonb_build_object('dispatch',v_res);
  elsif p_action='fill_caps' then
 -- Fill fields: what the panel needs to know before it asks anything. No provider list (capabilities carries every provider in scope; the panel does not need it).
 return jsonb_build_object('contract','provider-description-fill-v1','can_run',v_rank>=coalesce(v_job.control_rank,6),'control_rank',coalesce(v_job.control_rank,6),'reason_min_chars',security.pipeline_num_v1('pdesc.reason_min_chars',5)::int,
  'min_size',1,'max_size',security.provider_description_cohort_cap_v1(),
  'cap',jsonb_build_object('queue_per_run',security.pipeline_num_v1('pdesc.queue_per_run',10),'pending_max',security.pipeline_num_v1('pdesc.pending_max',10),'pilot_cap',security.pipeline_num_v1('run_now.pilot_cap',20),'queue_cap',security.pipeline_num_v1('pdesc.queue_cap',60),'effective',security.provider_description_cohort_cap_v1()),
  'enabled',security.pipeline_num_v1('pdesc.enabled',0)>=1,'job_active',coalesce((select active from cron.job where jobname='provider-description-read'),false),
  'run_now_allowed',coalesce(security.toolset_setting('pipeline','run_now.jobs'),'[]'::jsonb)?'provider-description-read',
  'poll_seconds',greatest(30,security.pipeline_num_v1('pdesc.every_minutes',60)::int*15) /* fixed: a quarter of the reader's own window (minutes x 60 / 4), never faster than twice a minute */,'status_max',security.provider_description_cohort_cap_v1(),
  'modes',jsonb_build_array(jsonb_build_object('id','stored','label','Stored official evidence + approved AI','allowed',true),jsonb_build_object('id','approved','label','Existing authorised acquisition + approved AI','allowed',security.pipeline_num_v1('pdesc.acquire_direct',0)>=1)),
  'fill_modes',jsonb_build_array('missing','upgrade_basic','preview_only','verify_publication'),
  'upgrade_basic_on',security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1,
  'quality_classes',to_jsonb(security.provider_description_quality_classes_v1()));
 elsif p_action in ('provider_status','provider_publication') then
 -- Fill fields, read only: the state of up to the governed number of providers, and the task that last included each. Needs no saved cohort, so it works after the browser was closed.
 select coalesce(array_agg(distinct (e)::uuid),array[]::uuid[]) into v_ids from jsonb_array_elements_text(case when jsonb_typeof(p_args->'provider_ids')='array' then p_args->'provider_ids' else '[]'::jsonb end) e;
 if cardinality(v_ids)=0 or cardinality(v_ids)>security.provider_description_cohort_cap_v1() then raise exception 'name between 1 and % providers',security.provider_description_cohort_cap_v1() using errcode='22023'; end if;
 if p_action='provider_publication' then
  if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot verify this job publication' using errcode='42501'; end if;
  v_res:=security.provider_description_publication_read_v1(v_ids);
  insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify_provider_publication',array_to_string(v_ids,','),jsonb_build_object('providers',cardinality(v_ids),'as_at',now(),'reason','Operator requested actual catalogue and consumer read-back from Fill fields'),v_actor);
  return v_res;
 end if;
 return security.provider_description_fill_status_v1(v_ids,coalesce((p_args->>'feeds')::boolean,false),v_actor);
 elsif p_action='quality_counts' then
 return security.provider_description_quality_counts_v1();
 elsif p_action='quality_refresh' then
 if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot refresh the quality snapshot' using errcode='42501'; end if;
 select array_agg(distinct (e)::uuid) into v_ids from jsonb_array_elements_text(case when jsonb_typeof(p_args->'provider_ids')='array' then p_args->'provider_ids' else '[]'::jsonb end) e;
 return security.provider_description_quality_refresh_v1(v_ids);
 elsif p_action in ('saved','verify','diagnose') then
 if p_action='diagnose' and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor;
 elsif nullif(p_args->>'cohort_id','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'cohort_id')::uuid and requested_by=v_actor;
 else select * into c from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc,id desc limit 1; end if;
 if p_action='diagnose' then
   if v_rank<coalesce(v_job.control_rank,6) then raise exception 'your role cannot diagnose this job' using errcode='42501'; end if;
   if length(v_reason)<security.pipeline_num_v1('pdesc.reason_min_chars',5) then raise exception 'audit reason required'; end if;
   if c.id is null and nullif(p_args->>'preview_token','') is not null then select * into c from pipeline.provider_description_cohorts where id=(p_args->>'preview_token')::uuid and requested_by=v_actor; end if;
   if c.id is null then raise exception 'owned saved evidence required' using errcode='42501'; end if;
   select coalesce(r.rule,m.snapshot->>'eligibility_reason'),coalesce(r.reason,m.snapshot->>'reason') into v_rule,v_why from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid;
   if v_rule is null then select x->>'eligibility_reason',x->>'reason' into v_rule,v_why from jsonb_array_elements(c.snapshot->'providers') x where x->>'provider_id'=p_args->>'provider_id'; end if;
   if v_rule is null then raise exception 'provider is not in owned saved evidence' using errcode='42501'; end if;
   v_diagnosis:=jsonb_build_object('method','stored_checks','rule',v_rule,'explanation',coalesce(v_why,case v_rule when 'no_verified_stored_source' then 'A current official About/Overview page stored against this exact provider is needed.' when 'unchanged_unsuitable_evidence' then 'The same evidence previously failed or was rejected. A changed approved source is needed before another AI read.' when 'review_full' then 'The validated proposal is parked until Layer 4 capacity becomes available; no further AI read is needed.' else 'Inspect the official source, identity references and validation checks. Only the existing human Layer 4 decision can authorise admission.' end),'ai_used',false,'cost_usd',0,'ai_reason','Provider-description AI diagnostics have no approved existing route.','at',now());
   -- AI is advice through the existing Operations lane only, bound to an already recorded issue and the exact stored source.
   select coalesce((select m.snapshot||jsonb_build_object('evidence_id',coalesce(r.evidence_id,m.evidence_id),'source_hash',coalesce(r.content_hash,m.snapshot->>'source_hash'),'checks',r.checks,'sentences',r.proposal->'sentences') from pipeline.provider_description_cohort_members m left join pipeline.provider_description_reads r on r.id=m.read_id where m.cohort_id=c.id and m.provider_id=(p_args->>'provider_id')::uuid),
     (select z from jsonb_array_elements(c.snapshot->'providers') z where z->>'provider_id'=p_args->>'provider_id')) into v_context;
   v_ai_model:=nullif(security.ai_route_v1('ops_diagnosis')->>'model','');
   v_ai_why:=case when security.pipeline_num_v1('ops.ai_diagnosis_on',0)<1 then 'ops.ai_diagnosis_on is 0'
      when v_ai_model is null then 'no approved Operations diagnosis model'
      when not security.ai_use_allowed_v1('ops_diagnose') then 'existing Operations AI spending guard refuses assistance'
      when nullif(v_context->>'evidence_id','') is null then 'no exact stored evidence reference for an existing issue' end;
   if v_ai_why is null then
    select i.id into v_issue from pipeline.integration_issues i where i.status not in ('closed','superseded') and (p_args->>'provider_id')::uuid=any(i.provider_ids)
      and jsonb_path_exists(i.evidence,'$.**.evidence_id ? (@ == $id)',jsonb_build_object('id',v_context->>'evidence_id')) order by i.id desc limit 1;
    if v_issue is null then v_ai_why:='no existing open integration issue links this exact provider and stored evidence'; end if;
   end if;
   if v_ai_why is null then
    perform pg_advisory_xact_lock(hashtext('cf247 pdesc diagnosis '||v_issue::text)); -- fixed: duplicate request suppression for the existing issue/evidence.
    select q.id into v_ai_request from pipeline.ops_ai_diagnosis_requests q where q.issue_id=v_issue and q.context->>'provider_description_evidence_id'=v_context->>'evidence_id' and q.state in ('queued','leased','answered','refused') order by q.id desc limit 1;
    if v_ai_request is null then
     insert into pipeline.ops_ai_diagnosis_requests(issue_id,context,model,note)
     values(v_issue,jsonb_build_object('issue',v_issue,'provider_id',p_args->>'provider_id','provider_description_evidence_id',v_context->>'evidence_id','evidence',v_context,'question','Explain why this official source or claim is unsuitable and which evidence is missing. Advice only; do not authorise a description or change any setting.',
       'deterministic',v_diagnosis,'root_causes',(select jsonb_agg(jsonb_build_object('code',rc.code,'class',rc.class,'title',rc.title,'description',rc.description)) from pipeline.ops_root_causes rc)),v_ai_model,'Provider description evidence explanation; advice through existing Operations diagnosis') returning id into v_ai_request;
    end if;
    v_diagnosis:=v_diagnosis||jsonb_build_object('request_id',v_ai_request,'request_status','queued','integration_issue_id',v_issue,'model',v_ai_model,'ai_reason','Queued through the existing Operations diagnosis worker; no approval or settings authority.');
   else v_diagnosis:=v_diagnosis||jsonb_build_object('ai_reason',v_ai_why); end if;
   update pipeline.provider_description_cohort_members set snapshot=snapshot||jsonb_build_object('diagnosis',v_diagnosis) where cohort_id=c.id and provider_id=(p_args->>'provider_id')::uuid;
   update pipeline.provider_description_cohorts set snapshot=jsonb_set(snapshot,'{providers}',(select jsonb_agg(case when z->>'provider_id'=p_args->>'provider_id' then z||jsonb_build_object('diagnosis',v_diagnosis) else z end) from jsonb_array_elements(snapshot->'providers') z)) where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','explain_evidence',c.id::text,jsonb_build_object('provider_id',p_args->>'provider_id','reason',v_reason,'diagnosis',v_diagnosis),v_actor);
   return v_diagnosis;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('cohort_id',h.id,'state',h.state,'created_at',h.created_at,'reason',h.reason,'run_id',h.run_id) order by h.created_at desc),'[]') into v_history from (select * from pipeline.provider_description_cohorts where requested_by=v_actor order by created_at desc limit security.pipeline_num_v1('pdesc.queue_per_run',10)::int) h;
 if c.state='preview' then
   v_preview:=jsonb_set(c.snapshot,'{providers}',coalesce((select jsonb_agg(z||case when z->'diagnosis'->>'request_id' is not null then jsonb_build_object('diagnosis',(z->'diagnosis')||coalesce((select jsonb_build_object('request_status',q.state,'ai_used',q.state='answered','explanation',coalesce(q.answer->>'reasoning',z->'diagnosis'->>'explanation'),'answer',q.answer,'model',q.model,'cost_usd',q.cost_usd,'answered_at',q.answered_at) from pipeline.ops_ai_diagnosis_requests q where q.id=(z->'diagnosis'->>'request_id')::bigint),'{}'::jsonb)) else '{}'::jsonb end) from jsonb_array_elements(c.snapshot->'providers') z),'[]'::jsonb));
   return jsonb_build_object('preview',v_preview||jsonb_build_object('token',c.id,'expires_at',c.expires_at),'scope',c.selection,'history',v_history);
 end if;
 if c.id is null then return jsonb_build_object('history',v_history,'providers','[]'::jsonb,'runs','[]'::jsonb); end if;
 v_res:=security.provider_description_run_result_v1(c.id);
 if p_action='verify' then
   update pipeline.provider_description_cohorts set verified_at=now(),verification=v_res-'last_verification' where id=c.id;
   insert into pipeline.admin_control_events(area,action,target,detail,actor) values('provider_descriptions','verify',c.id::text,jsonb_build_object('totals',v_res->'totals','as_at',now(),'reason','Operator requested actual catalogue and consumer read-back'),v_actor);
 end if;
 return v_res||jsonb_build_object('history',v_history);
 end if;
 raise exception 'unknown provider-description action %',p_action using errcode='22023';
end $function$;

-- 5 functions rewritten whole (short; md5-guarded above) ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION security.scholarship_ai_active_v1()
 RETURNS TABLE(model_code text, model_identifier text, prompt_version integer, ai_admission boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 13 Nov 2026: the first allowed model of the route scholarship_extraction reads first (it was the first of the old chain)
  select m.x->>'code', m.x->>'model_identifier', (select p.version from pipeline.scholarship_ai_prompts p where p.active order by p.version desc limit 1), s.ai_admission
    from pipeline.scholarship_ai_extract_settings s
    left join lateral (select t.x from jsonb_array_elements(security.ai_route_v1('scholarship_extraction')->'models') with ordinality t(x, o) order by t.o limit 1) m on true
   where s.id = 1
$function$;
CREATE OR REPLACE FUNCTION security.scholarship_ai_next_model_v1(p_code text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 13 Nov 2026: the next allowed model after p_code in the route's cascade; none (a person decides) after the last, or when p_code is not in it
  with c as (select t.x->>'code' code, t.o from jsonb_array_elements(security.ai_route_v1('scholarship_extraction')->'models') with ordinality t(x, o))
  select n.code from c n where n.o > (select c.o from c where c.code = p_code) order by n.o limit 1
$function$;
CREATE OR REPLACE FUNCTION security.adapter_builder_model_for_v1(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 13 Nov 2026: the model is the route adapter_builder's. A provider's own choice is kept only when the route's cascade names its model.
  -- code is the Layer 3 profile that holds the OpenRouter credential for that model (the builder's profile first).
  with rt as (select security.ai_route_v1('adapter_builder') j),
  own as (select m.code, m.model_identifier, a.set_at, a.reason
            from pipeline.uni_adapter_models a join pipeline.layer3_model_profiles m on m.code = a.profile_code, rt
           where a.provider_id = p_provider_id and m.enabled and not m.paused and m.retired_at is null
             and exists (select 1 from jsonb_array_elements(rt.j->'models') x where x->>'model_identifier' = m.model_identifier))
  select coalesce(
    (select jsonb_build_object('code', o.code, 'model', o.model_identifier, 'chosen', true, 'set_at', o.set_at, 'reason', o.reason) from own o),
    (select jsonb_build_object('code', (select p.code from pipeline.layer3_model_profiles p where p.model_identifier = rt.j->>'model' and p.retired_at is null
                                          order by (p.code = security.firecrawl_setting('builder_model_profile') #>> '{}') desc, p.enabled desc, p.code limit 1),
                               'model', rt.j->>'model', 'chosen', false) from rt))
$function$;
CREATE OR REPLACE FUNCTION security.adapter_builder_models_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 13 Nov 2026: only the models of the route adapter_builder's cascade can be chosen for a provider
  select coalesce(jsonb_agg(jsonb_build_object('code', m.code, 'model', m.model_identifier, 'max_output_tokens', m.max_output_tokens) order by m.model_identifier), '[]'::jsonb)
    from pipeline.layer3_model_profiles m
   where m.enabled and not m.paused and m.retired_at is null and m.aggregator_provider = 'openrouter'
     and 'provider_intake_validation' = any(m.allowed_task_classes)
     and exists (select 1 from jsonb_array_elements(security.ai_route_v1('adapter_builder')->'models') x where x->>'model_identifier' = m.model_identifier)
$function$;
CREATE OR REPLACE FUNCTION security.adapter_builder_budget()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 13 Nov 2026: the allowance, the proposals a day and the model are the route adapter_builder's (they were the settings builder_ai_daily_usd,
  -- builder_proposals_per_day and builder_model). A held route leaves no allowance.
  with today as (select (now() at time zone 'Australia/Melbourne')::date d), rt as (select security.ai_route_v1('adapter_builder') j),
  rounds as (select (p->>'cost')::numeric cost from pipeline.uni_adapter_drafts dr cross join lateral jsonb_array_elements(dr.proposals) p, today
             where ((p->>'at')::timestamptz at time zone 'Australia/Melbourne')::date = today.d)
  select jsonb_build_object('used_usd', coalesce((select sum(cost) from rounds), 0), 'proposals', (select count(*) from rounds),
                            'limit_usd', case when (rt.j->>'held')::boolean then 0 else (rt.j#>>'{cap,usd}')::numeric end,
                            'limit_proposals', case when (rt.j->>'held')::boolean then 0 else coalesce((rt.j#>>'{cap,calls}')::int, coalesce((security.firecrawl_setting('builder_proposals_per_day') #>> '{}')::int, 30)) end,
                            'model', rt.j->>'model', 'held', rt.j->>'held_reason') from rt
$function$;
CREATE OR REPLACE FUNCTION security.ai_model_pinned_ok_v1(p_model text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- 13 Nov 2026: a pinned model is one named model (never a router) that the catalogue lists as allowed
  select coalesce(p_model, '') ~ '^[a-z0-9][a-z0-9._-]*/[a-zA-Z0-9][a-zA-Z0-9._:-]*$'
     and p_model !~* '(^openrouter/|(^|[/:._-])auto([/:._-]|$)|router)'
     and exists (select 1 from pipeline.ai_model_catalogue m where m.model_identifier = p_model and m.status = 'allowed')
$function$;

-- 6 the copies: central_ai_settings.model_* and the scholarship chain follow their routes and cannot be set directly ---------------------------------
create or replace function security.ai_service_model_v1(p_service text) returns text
language sql stable security definer set search_path = '' as $function$
  -- the model in effect for a service: the first allowed model of its route's cascade
  select (select m.model_identifier from unnest(r.cascade) with ordinality c(code, ord) join pipeline.ai_model_catalogue m on m.code = c.code and m.status = 'allowed' order by c.ord limit 1)
    from pipeline.ai_service_routes r where r.service_code = p_service
$function$;
create or replace function security.ai_central_sync_v1() returns void
language plpgsql security definer set search_path = '' as $function$
declare m record; v_chain text[];
begin
  -- display copies only: nothing chooses a model from them any more
  perform set_config('cf247.ai_route_sync', 'on', true);
  select x->>'code' code, x->>'model_identifier' model_identifier into m from jsonb_array_elements(security.ai_route_v1('calendar_reading')->'models') with ordinality t(x, o) order by o limit 1;
  if m.code is not null then
    update pipeline.central_ai_settings s set model_code = m.code, model_identifier = m.model_identifier, changed_at = now(),
           reason = 'copy of the intake calendar route (Models & services)' where s.id = 1 and s.model_identifier is distinct from m.model_identifier;
  end if;
  select array_agg(x->>'code' order by o) into v_chain from jsonb_array_elements(security.ai_route_v1('scholarship_extraction')->'models') with ordinality t(x, o);
  if v_chain is not null then
    update pipeline.scholarship_ai_extract_settings s set chain = v_chain, changed_at = now(), reason = 'copy of the scholarship route (Models & services)'
     where s.id = 1 and s.chain is distinct from v_chain;
  end if;
  -- pipeline.scholarship_ai_models: every allowed model has a row (scholarship_ai_queue.model_code refers to it); the first model of the
  -- scholarship route is 'active' and the others 'candidate'. A copy of the route: it switches nothing on (AI admission has its own switch).
  insert into pipeline.scholarship_ai_models (code, label, model_identifier, status, sort)
  select c.code, c.label, c.model_identifier, 'candidate', c.sort from pipeline.ai_model_catalogue c
   where c.status = 'allowed' and not exists (select 1 from pipeline.scholarship_ai_models x where x.code = c.code);
  if v_chain is not null then
    update pipeline.scholarship_ai_models x set status = 'candidate' where x.status = 'active' and x.code <> v_chain[1];
    update pipeline.scholarship_ai_models x set status = 'active', activated_at = now(), reason = 'first model of the scholarship route (Models & services)'
     where x.code = v_chain[1] and x.status <> 'active';
  end if;
  perform set_config('cf247.ai_route_sync', 'off', true);
end $function$;
create or replace function security.ai_route_central_trg() returns trigger
language plpgsql security definer set search_path = '' as $function$
begin
  if new.service_code in ('calendar_reading', 'scholarship_extraction') then perform security.ai_central_sync_v1(); end if;
  return null;
end $function$;
create or replace function security.ai_central_settings_trg() returns trigger
language plpgsql security definer set search_path = '' as $function$
begin
  if coalesce(current_setting('cf247.ai_route_sync', true), '') <> 'on' and (to_jsonb(new)->>'model_identifier' is distinct from to_jsonb(old)->>'model_identifier' or to_jsonb(new)->'chain' is distinct from to_jsonb(old)->'chain') then
    raise exception 'the model is chosen on Models & services (each service has its own route); it can no longer be set here' using errcode = '23514';
  end if;
  return new;
end $function$;
create or replace function security.ai_model_status_trg() returns trigger
language plpgsql security definer set search_path = '' as $function$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then perform security.ai_central_sync_v1(); end if;
  return null;
end $function$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'ai_model_added' and tgrelid = 'pipeline.ai_model_catalogue'::regclass) then
    create trigger ai_model_added after insert on pipeline.ai_model_catalogue for each row execute function security.ai_model_status_trg();
  end if;
end $$;
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'ai_scholarship_chain_copy' and tgrelid = 'pipeline.scholarship_ai_extract_settings'::regclass) then
    create trigger ai_scholarship_chain_copy before update of chain on pipeline.scholarship_ai_extract_settings for each row execute function security.ai_central_settings_trg();
  end if;
end $$;
select security.ai_central_sync_v1();
-- queued scholarship reads that name a model that is not allowed any more would wait for ever: they go to the route's first model
do $$
declare n int; v_first text := security.ai_route_v1('scholarship_extraction')#>>'{models,0,code}';
begin
  if v_first is null then raise notice 'scholarship queue: no allowed model on the route; nothing re-pointed'; return; end if;
  update pipeline.scholarship_ai_queue q set model_code = v_first
   where q.state in ('queued', 'leased') and not exists (select 1 from pipeline.ai_model_catalogue m where m.code = q.model_code and m.status = 'allowed');
  get diagnostics n = row_count;
  raise notice 'scholarship queue: % queued read(s) naming a model that is not allowed re-pointed to %', n, v_first;
  if n > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('ai_models', 'scholarship_queue_repointed', 'pipeline.scholarship_ai_queue', jsonb_build_object('rows', n, 'to', v_first, 'migration', '20261113390000', 'reason', 'Platform Admin 13 Nov 2026 19:23'), null);
  end if;
end $$;

-- 7 the guard: where a model is named outside the routes -------------------------------------------------------------------------------------------------
create or replace function security.ai_route_guard_v1() returns jsonb
language sql stable security definer set search_path = '' as $function$
  -- Read-only. functions: a function of public, security or pipeline whose source holds a quoted model identifier (a vendor of the catalogue),
  -- unless it is the last argument of a call (a coalesce default) and the catalogue allows it. settings: a text setting whose value is a model
  -- identifier. cascades: a route naming a model that is not allowed or not listed.
  with vendors as (select string_agg(distinct split_part(m.model_identifier, '/', 1), '|') v from pipeline.ai_model_catalogue m),
  lit as (
    select n.nspname || '.' || p.proname fn, x.m[1] id, p.prosrc ~ (',\s*''' || replace(x.m[1], '.', '\.') || '''\s*\)') as_default
      from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace, vendors,
           lateral regexp_matches(p.prosrc, '''((?:' || vendors.v || ')/[A-Za-z0-9][A-Za-z0-9._:-]*)''', 'g') x(m)
     where n.nspname in ('public', 'security', 'pipeline') and p.prokind = 'f' and p.proname <> 'ai_route_guard_v1'),
  f as (select l.fn, l.id, coalesce(m.status, 'not listed') status from lit l left join pipeline.ai_model_catalogue m on m.model_identifier = l.id
         where not (l.as_default and coalesce(m.status, '') = 'allowed') group by 1, 2, 3),
  s as (select s.toolset_key || '.' || s.key setting, s.value #>> '{}' id,
               coalesce((select m.status from pipeline.ai_model_catalogue m where m.model_identifier = s.value #>> '{}'), 'not listed') status
          from pipeline.platform_toolset_settings s, vendors where s.kind = 'text' and (s.value #>> '{}') ~ ('^(' || vendors.v || ')/[A-Za-z0-9]')),
  c as (select r.service_code, x.code, coalesce(m.status, 'not listed') status from pipeline.ai_service_routes r cross join lateral unnest(r.cascade) x(code)
          left join pipeline.ai_model_catalogue m on m.code = x.code where coalesce(m.status, '') <> 'allowed')
  select jsonb_build_object(
    'functions', (select coalesce(jsonb_agg(jsonb_build_object('function', f.fn, 'model', f.id, 'status', f.status) order by f.status <> 'not_allowed', f.fn, f.id), '[]'::jsonb) from f),
    'settings', (select coalesce(jsonb_agg(jsonb_build_object('setting', s.setting, 'model', s.id, 'status', s.status) order by s.setting), '[]'::jsonb)
                   from s),
    'cascades', (select coalesce(jsonb_agg(jsonb_build_object('service', c.service_code, 'model', c.code, 'status', c.status) order by c.service_code), '[]'::jsonb) from c),
    'not_allowed_named', (select count(*) from f where f.status = 'not_allowed') + (select count(*) from s where s.status = 'not_allowed') + (select count(*) from c))
$function$;
revoke all on function security.ai_route_guard_v1() from public, anon, authenticated;

create or replace function security.ai_settings_not_read_v1() returns table(toolset_key text, key text, replaced_by text)
language sql immutable set search_path = '' as $function$
  -- settings the routes replaced: kept with their values, read by nothing for the model any more (shown read-only on Models & services)
  values ('pipeline', 'entry.matrix_model', 'routes entry_matrices and course_entry_requirements'), ('pipeline', 'ops.ai_diagnosis_model', 'route ops_diagnosis'),
         ('firecrawl', 'builder_model', 'route adapter_builder')
$function$;
revoke all on function security.ai_settings_not_read_v1() from public, anon, authenticated;

-- 8 the page read: every service is enforced; the Layer 3 profiles still switched on are reported, not wired ------------------------------------------
create or replace function public.admin_ai_overview_v1() returns jsonb
language plpgsql stable security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank();
        v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';  -- fixed: the UTC day the AI guards count
        v_bal record;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;  -- rank 3 reads (no key details)
  select o.remaining_usd, o.observed_at, o.payload into v_bal from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1;
  return jsonb_build_object(
    'can_control', v_rank >= 5, 'can_admin', v_rank >= 6, 'rank', v_rank,
    -- the daily ceiling and the service caps follow this mode (Observe only: reported, nothing stopped); the balance checks, the switch and
    -- qualification hold in both
    'mode', case when security.toolset_enforced('openrouter') then 'stop' else 'observe' end,
    'ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
    'caps_total_usd', (select coalesce(sum(r.daily_usd_cap), 0) from pipeline.ai_service_routes r where r.enabled),
    'caps_exceed_ceiling', (select coalesce(sum(r.daily_usd_cap), 0) from pipeline.ai_service_routes r where r.enabled) > security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
    'day_start', v_day,
    'openrouter', jsonb_build_object(
      -- the key is an edge function secret (OPENROUTER_API_KEY); the database never holds it. A balance read inside the stale window proves it works.
      'key_present', coalesce(v_bal.observed_at > now() - make_interval(mins => coalesce((security.toolset_setting('openrouter', 'balance_stale_minutes'))::text::int, 30)), false),
      'key_secret_name', 'OPENROUTER_API_KEY',
      'key', case when v_rank < 4 then jsonb_build_object('present', v_bal.observed_at is not null) else jsonb_build_object('present', v_bal.observed_at is not null, 'secret', 'OPENROUTER_API_KEY', 'shared_by_profiles', (select count(*) from pipeline.layer3_model_profiles p where p.secret_env_key = 'OPENROUTER_API_KEY'),
                                'profile_id', (select p.id from pipeline.layer3_model_profiles p where p.code = (security.toolset_setting('firecrawl', 'builder_model_profile') #>> '{}')),
                                'profile_code', security.toolset_setting('firecrawl', 'builder_model_profile') #>> '{}') end,
      'balance_max_age_minutes', coalesce((security.toolset_setting('openrouter', 'balance_max_age_minutes'))::text::numeric, 90),
      'balance_known', v_bal.remaining_usd is not null,
      'balance_note', case when v_bal.remaining_usd is null then 'No OpenRouter balance reading: every AI service is held until one is recorded.' end,
      'mode', (select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'),
      'balance_usd', round(v_bal.remaining_usd, 2), 'balance_observed_at', v_bal.observed_at,
      'total_credits_usd', (coalesce(v_bal.payload->>'total_credits', v_bal.payload#>>'{data,total_credits}'))::numeric,
      'floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
      'low_warn_usd', (security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric,
      'daily_ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
      'spent_today_usd', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.at >= v_day),
      'settings', (select coalesce(jsonb_agg(jsonb_build_object('toolset', s.toolset_key, 'key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'kind', s.kind,
                               'not_read', exists (select 1 from security.ai_settings_not_read_v1() nr where nr.toolset_key = s.toolset_key and nr.key = s.key),
                               'read_only', exists (select 1 from security.ai_settings_not_read_v1() nr where nr.toolset_key = s.toolset_key and nr.key = s.key),
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
                'resolver', r.resolver, 'wired', r.resolver = 'route', 'enforced', r.resolver = 'route', 'model', rt.j->>'model', 'model_in_effect', security.ai_service_model_v1(r.service_code),
                'note', r.note, 'reason', r.reason, 'changed_at', r.changed_at, 'changed_by', (select u.email from auth.users u where u.id = r.changed_by),
                'models', rt.j->'models', 'spent_today', rt.j->'spent_today', 'held', rt.j->'held', 'held_kind', rt.j->'held_kind', 'held_reason', rt.j->'held_reason', 'would_hold_now', rt.j->'would_hold', 'would_hold_kind', rt.j->'would_hold_kind', 'would_hold_reason', rt.j->'would_hold_reason',
                'enforcing', rt.j->'enforcing', 'migration_state', r.migration_state, 'skipped', rt.j->'skipped',
                'qualification', (select coalesce(jsonb_agg(jsonb_build_object('code', q.model_code, 'qualified', q.status = 'qualified', 'status', q.status, 'provisional', q.provisional,
                                      'prompt_version', q.prompt_version, 'evidence', q.evidence, 'at', q.qualified_at, 'by', q.qualified_by, 'note', q.note) order by q.model_code), '[]'::jsonb)
                                    from pipeline.ai_route_qualifications q where q.service_code = r.service_code),
                'previous_model', r.previous_model,
                'last_call', (select jsonb_build_object('at', i.at, 'model', i.model, 'outcome', i.outcome, 'error', i.failure_kind, 'attempt_no', i.attempt_no)
                                from pipeline.ai_invocations i where i.service_code = r.service_code order by i.at desc, i.id desc limit 1),
                -- held: nothing is handed out. failing: the last call failed. fallback: the last answer came from a later model of the cascade.
                -- ok: the last call was answered by the first model asked. no_calls: no call is on record yet.
                'recovery_state', case when coalesce((rt.j->>'held')::boolean, false) then 'held'
                                       else coalesce((select case when i.outcome = 'failed' then 'failing' when i.attempt_no > 1 then 'fallback' else 'ok' end
                                                        from pipeline.ai_invocations i where i.service_code = r.service_code order by i.at desc, i.id desc limit 1), 'no_calls') end,
                'config', case when r.service_code = 'scholarship_extraction' then (select jsonb_build_object('write', 'public.admin_scholarship_ai', 'ai_admission', s.ai_admission,
                                      'prompts', (select coalesce(jsonb_agg(jsonb_build_object('version', p.version, 'current', p.active, 'text', p.text, 'sha256', encode(sha256(convert_to(p.text, 'UTF8')), 'hex')) order by p.version desc), '[]'::jsonb)
                                                    from pipeline.scholarship_ai_prompts p)) from pipeline.scholarship_ai_extract_settings s where s.id = 1) end,
                'on_demand_exempt', rt.j->'on_demand_exempt', 'purpose_group', r.purpose_group,
                'prompt', case
                  when r.prompt_source = 'pipeline.provider_description_prompts' then (select jsonb_build_object('source', r.prompt_source, 'version', p.version::text, 'text', p.system_prompt, 'text_ref', null, 'sha256', encode(sha256(convert_to(p.system_prompt, 'UTF8')), 'hex'))
                          from pipeline.provider_description_prompts p where p.status = 'active' order by p.version desc limit 1)
                  when r.prompt_source = 'pipeline.scholarship_ai_prompts' then (select jsonb_build_object('source', r.prompt_source, 'version', p.version::text, 'text', p.text, 'text_ref', null, 'sha256', encode(sha256(convert_to(p.text, 'UTF8')), 'hex'))
                          from pipeline.scholarship_ai_prompts p where p.active order by p.version desc limit 1)
                  when r.prompt_source = 'pipeline.aer_prompt_versions' then (select jsonb_build_object('source', r.prompt_source, 'version', p.version, 'text', p.system_text, 'text_ref', null, 'sha256', encode(sha256(convert_to(p.system_text, 'UTF8')), 'hex'))
                          from pipeline.aer_prompt_versions p where p.status <> 'retired' order by p.created_at desc limit 1)
                  else jsonb_build_object('source', split_part(r.prompt_source, ': ', 1), 'version', nullif(split_part(r.prompt_source, ': ', 2), ''), 'text', null,
                                          'text_ref', 'ai-prompts.json#' || r.service_code, 'sha256', null) end,  -- the full text and its sha are in the generated file (scripts/ai-prompts-export.mjs)
                'settings', (select coalesce(jsonb_agg(jsonb_build_object('toolset', s.toolset_key, 'key', s.key, 'label', s.label, 'help', s.help, 'value', s.value, 'kind', s.kind,
                               'not_read', exists (select 1 from security.ai_settings_not_read_v1() nr where nr.toolset_key = s.toolset_key and nr.key = s.key),
                               'read_only', exists (select 1 from security.ai_settings_not_read_v1() nr where nr.toolset_key = s.toolset_key and nr.key = s.key),
                               'min', s.min_value, 'max', s.max_value, 'unit', s.unit) order by s.toolset_key, s.sort, s.key), '[]'::jsonb)
                               from pipeline.platform_toolset_settings s where s.home = 'models_services' and s.home_group = r.service_code)) j
         from pipeline.ai_service_routes r cross join lateral (select security.ai_route_v1(r.service_code) j) rt) x),
    'legacy_controls', jsonb_build_object(
      'central_ai_settings', (select jsonb_build_object('enabled', c.enabled, 'calls_at_once', c.calls_at_once, 'model_code', c.model_code, 'model_identifier', c.model_identifier,
                                 'reason', c.reason, 'changed_at', c.changed_at, 'write', null, 'copy_of', 'route calendar_reading') from pipeline.central_ai_settings c where c.id = 1),
      'scholarship_chain', (select jsonb_build_object('chain', to_jsonb(s.chain), 'reason', s.reason, 'changed_at', s.changed_at, 'write', null, 'copy_of', 'route scholarship_extraction')
                              from pipeline.scholarship_ai_extract_settings s where s.id = 1)),
    'legacy', jsonb_build_object('layer3', jsonb_build_object(
      'note', 'Layer 3 was retired on 12 Oct 2026 and is not wired to the routes. A profile listed here is switched on in its own table; in_active_tier says whether a Layer 3 step would still use it.',
      'last_call_at', (select max(i.created_at) from pipeline.layer3_interpretations i),
      'jobs', (select coalesce(jsonb_agg(j.jobname order by j.jobname), '[]'::jsonb) from cron.job j where j.active and j.command ~* 'layer3'),
      'profiles_switched_on', (select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'model_identifier', p.model_identifier, 'tasks', to_jsonb(p.allowed_task_classes),
                                  'in_active_tier', exists (select 1 from pipeline.layer3_route_tiers t where t.profile_id = p.id and t.active),
                                  'catalogue_status', coalesce((select m.status from pipeline.ai_model_catalogue m where m.model_identifier = p.model_identifier), 'not listed')) order by p.code), '[]'::jsonb)
                                 from pipeline.layer3_model_profiles p where p.enabled and not p.paused and p.retired_at is null))),
    'guard', security.ai_route_guard_v1()->'not_allowed_named',
    'usage', jsonb_build_object(
      'by_model_24h', (select coalesce(jsonb_agg(to_jsonb(u) order by u.service_code, u.attempts desc), '[]'::jsonb)
                         from (select i.service_code, i.model, count(*) attempts, count(*) filter (where i.outcome = 'answered') answered, count(*) filter (where i.outcome = 'failed') failures,
                                      count(*) filter (where i.attempt_no > 1) fallbacks, coalesce(sum(i.input_tokens), 0) tokens_in, coalesce(sum(i.output_tokens), 0) tokens_out,
                                      round(coalesce(sum(i.cost_usd), 0), 4) usd, null::text evidence_href
                                 from pipeline.ai_invocations i where i.at >= now() - interval '24 hours'  -- fixed: the page's 24-hour usage window
                                group by 1, 2) u),
      'fallbacks_24h', (select coalesce(jsonb_agg(to_jsonb(f) order by f.at desc), '[]'::jsonb)
                          from (select i.at, i.service_code, i.model, i.attempt_no, i.failure_kind from pipeline.ai_invocations i
                                 where i.outcome = 'failed' and i.at >= now() - interval '24 hours' order by i.at desc limit 100) f),  -- fixed: the page's 24-hour window and its last 100 failed attempts
      'by_day_14d', (select coalesce(jsonb_agg(jsonb_build_object('day', u.d, 'service_code', u.svc, 'lane', u.lane, 'model', u.model, 'usd', u.usd, 'calls', u.calls) order by u.d desc, u.usd desc), '[]'::jsonb)
                       from (select (l.at at time zone 'UTC')::date d, l.service_code svc, l.lane, l.model, round(sum(l.cost_usd), 4) usd, sum(l.calls) calls
                               from pipeline.ai_spend_ledger l where l.at >= v_day - interval '13 days'  -- fixed: the page's 14-day usage window
                              group by 1, 2, 3, 4) u),
      'by_hour_24h', (select coalesce(jsonb_agg(jsonb_build_object('hour', u.h, 'service_code', u.svc, 'lane', u.lane, 'model', u.model, 'usd', u.usd, 'calls', u.calls) order by u.h desc, u.usd desc), '[]'::jsonb)
                        from (select date_trunc('hour', l.at) h, l.service_code svc, l.lane, l.model, round(sum(l.cost_usd), 4) usd, sum(l.calls) calls
                                from pipeline.ai_spend_ledger l where l.at >= date_trunc('hour', now()) - interval '23 hours'  -- fixed: the page's 24-hour usage window
                               group by 1, 2, 3, 4) u)),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'detail', e.detail, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
                 from (select * from pipeline.admin_control_events where area = 'ai_models' order by created_at desc limit 20) e  -- fixed: the page shows the last 20 changes
                 left join auth.users u on u.id = e.actor));
end $function$;
create or replace function public.admin_ai_route_set_v1(p_service text, p_cascade text[], p_daily_usd_cap numeric, p_daily_calls_cap integer, p_enabled boolean, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $function$
-- Saves a service route whole: the cascade, the daily US$ cap (required), the calls cap (null = none) and the switch (null keeps it). Logged with its reason.
declare r pipeline.ai_service_routes%rowtype; v_reason text := btrim(coalesce(p_reason, '')); v_bad text;
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into r from pipeline.ai_service_routes where service_code = p_service for update;
  if not found then raise exception 'service % is not in the list', p_service; end if;
  if p_cascade is null or cardinality(p_cascade) = 0 then raise exception 'the cascade is empty: name at least one allowed model'; end if;
  if cardinality(p_cascade) > 4 then raise exception 'a cascade holds 4 models at most'; end if;  -- fixed: the table check
  if r.migration_state <> 'routed' and cardinality(p_cascade) > 1 then raise exception 'this service uses one model: a fallback is not available for it yet'; end if;
  if (select count(distinct c) from unnest(p_cascade) c) <> cardinality(p_cascade) then raise exception 'the cascade names a model twice'; end if;
  select string_agg(c.code, ', ') into v_bad from unnest(p_cascade) c(code) where not exists (select 1 from pipeline.ai_model_catalogue m where m.code = c.code);
  if v_bad is not null then raise exception 'unknown model in the cascade: %', v_bad; end if;
  select string_agg(c.code, ', ') into v_bad from unnest(p_cascade) c(code) join pipeline.ai_model_catalogue m on m.code = c.code and m.status <> 'allowed';
  if v_bad is not null then raise exception 'not an allowed model: % (Models & services › Models)', v_bad; end if;
  if p_daily_usd_cap is null then raise exception 'give a daily US$ cap (every service has one)'; end if;
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

create or replace function public.admin_ai_qualification_set_v1(p_service text, p_code text, p_evidence text, p_reason text, p_status text default 'qualified') returns jsonb
language plpgsql security definer set search_path = '' as $function$
-- Records whether a model is qualified for a service, with the evidence. Platform Admin only; logged. It switches nothing on: a qualified model is
-- handed out only if the route's cascade names it and the route is on.
declare v_reason text := btrim(coalesce(p_reason, '')); v_before jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_status is null or p_status not in ('qualified', 'unqualified', 'pending') then raise exception 'status must be qualified, unqualified or pending'; end if;
  if not exists (select 1 from pipeline.ai_service_routes r where r.service_code = p_service) then raise exception 'service % is not in the list', p_service; end if;
  if not exists (select 1 from pipeline.ai_model_catalogue m where m.code = p_code) then raise exception 'model % is not in the list', p_code; end if;
  if p_status = 'qualified' and length(btrim(coalesce(p_evidence, ''))) < 10 then raise exception 'say what the qualification rests on (the evidence)'; end if;
  select to_jsonb(q) into v_before from pipeline.ai_route_qualifications q where q.service_code = p_service and q.model_code = p_code;
  insert into pipeline.ai_route_qualifications (service_code, model_code, status, provisional, evidence, qualified_at, qualified_by, note, changed_at)
  values (p_service, p_code, p_status, false, nullif(btrim(coalesce(p_evidence, '')), ''), case when p_status = 'qualified' then now() end, case when p_status = 'qualified' then auth.uid() end, v_reason, now())
  on conflict (service_code, model_code) do update set status = excluded.status, provisional = false, evidence = coalesce(excluded.evidence, pipeline.ai_route_qualifications.evidence),
        qualified_at = excluded.qualified_at, qualified_by = excluded.qualified_by, note = excluded.note, changed_at = now();
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'route_qualification', p_service || ' / ' || p_code, jsonb_build_object('before', v_before - 'evidence_detail', 'after', p_status, 'evidence', p_evidence, 'reason', v_reason), auth.uid());
  return public.admin_ai_overview_v1();
end $function$;
revoke all on function public.admin_ai_qualification_set_v1(text, text, text, text, text) from public, anon;
grant execute on function public.admin_ai_qualification_set_v1(text, text, text, text, text) to authenticated, service_role;

-- 9 the register and the settings that are now copies ------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings s
   set used_by = 'not read for the model since migration 20261113390000 (13 Nov 2026): the adapter proposals model is the route adapter_builder (Models & services). Was: ' || coalesce(s.used_by, '')
 where s.toolset_key = 'firecrawl' and s.key = 'builder_model' and coalesce(s.used_by, '') not like 'not read for the model since migration 20261113390000%';
update pipeline.component_register set note = 'model_code and model_identifier are a copy of the intake calendar route (pipeline.ai_service_routes) for the screens that still show them (20261113390000); no reader chooses a model from them. enabled and calls_at_once are still set here.', updated_at = now()
 where kind = 'table' and name = 'pipeline.central_ai_settings';
update pipeline.component_register set note = 'The model columns are no longer read (20261113390000): scholarship reading takes its models from pipeline.ai_service_routes through pipeline.ai_model_catalogue.', updated_at = now()
 where kind = 'table' and name = 'pipeline.scholarship_ai_models';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, replaced_by, introduced_in, retire_after)
values ('function', 'public.admin_ai_config(text,jsonb)', 'Platform', 'Models & services', 'Old AI configuration card: central model and switch', 'retiring', '{}',
        'public.admin_ai_route_set_v1 (Models & services); its central_model action is refused by trigger since 20261113390000', '20261113390000 (marked retiring)',
        current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int)
on conflict (kind, name) do update set status = 'retiring', replaced_by = excluded.replaced_by, retire_after = excluded.retire_after, updated_at = now();

do $post$
declare v text;
begin
  select string_agg(r.service_code, ', ') into v from pipeline.ai_service_routes r where r.resolver <> 'route';
  if v is not null then raise exception 'post-check: a service is not resolved by its route: %', v; end if;
  -- nothing that runs today may stop for want of a qualification: the services that were running before this change still resolve to a model
  select string_agg(r.service_code, ', ') into v from pipeline.ai_service_routes r
   where r.service_code in ('course_description', 'course_other_fields', 'fee_reader', 'calendar_reading', 'central_english_policy', 'provider_description',
                            'scholarship_extraction', 'scholarship_eligibility', 'course_matching', 'adapter_builder')
     and security.ai_route_v1(r.service_code)->>'model' is null;
  if v is not null then raise exception 'post-check: a service that runs today has no qualified model: %', v; end if;
  if (security.ai_route_guard_v1()->'cascades') <> '[]'::jsonb then raise exception 'post-check: a cascade names a model that is not allowed'; end if;
  select string_agg(c.code, ', ') into v from pipeline.ai_model_catalogue c where c.status = 'allowed' and not exists (select 1 from pipeline.scholarship_ai_models x where x.code = c.code);
  if v is not null then raise exception 'post-check: an allowed model has no row in pipeline.scholarship_ai_models: %', v; end if;
end $post$;
