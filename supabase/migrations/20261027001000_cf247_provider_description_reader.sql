-- CF-247 AU completion week, step 5 (Platform Admin 26 Oct 2026 17:01: "Description reader: build started tonight"; lands Wednesday with
-- the Wollongong acceptance test: <= 400 chars, no superlatives, evidence quote, sourced from uow.edu.au/about/). Spec: admin
-- docs/platform/ui-audit/2026-10-25-consolidated-visibility-and-data.md Part E; record: 2026-10-26-au-completion-week.md.
-- Where reality differs from the spec (doc-as-code):
--   - the about page is not a new kind in pipeline.provider_fact_sources (its kind check would have to be dropped and re-made; migrations
--     drop nothing). It has its own table, pipeline.provider_descriptions, one row per reading;
--   - provenance (source address, as-at, model, run, quote, AI-consolidated) is held in that table, not in new columns on
--     catalogue.providers, so the consumer API's tables keep their shape (G3). The website reads `description` as today.
-- 1 pipeline.provider_descriptions: each reading of a provider's about page: address, stored copy, model, the text proposed, the exact
--   source sentences, the checks (length, words not allowed, every quote found on the stored page) and the outcome.
-- 2 security.provider_description_enqueue_v1(): providers in description.countries and description.provider_types with a website, no
--   description and no manual lock, not hidden, not read within description.refresh_days unless the stored page changed.
-- 3 public.svc_provider_description_next / _record (worker mode provider_description, coverage-sweep): the worker reads the about page
--   (stored copy first; direct, robots respected; Firecrawl only when the site refuses a direct read), asks the pinned model
--   (description.model; no "auto" routing) for a short factual description with its source sentences, and records it. The record
--   function re-checks every rule; a reading that breaks one is refused with the reason.
-- 4 Apply: only while description.enabled is 1, and never over a person's text (manual lock). Until then every reading waits for a person
--   (Layer 4-style review on the provider screen comes with the worker release). A passing check never switches anything on.
-- 5 AI spend: use 'provider_description' with its own daily guard (openrouter.guard_provider_description, US$1), added to
--   security.ai_spend_today_v1 (md5-guarded).
-- 6 Job provider-description (catalogued; every 10 minutes) is created inactive.
-- Replaces: nothing (security.ai_spend_today_v1 edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'description.enabled', 'Provider descriptions: write to the catalogue', '1: a reading that passes every check is written as the provider''s description (never over a person''s text). 0: readings wait for a person. Stays 0 until 5 descriptions are checked by hand against their about pages.', 'number', '0'::jsonb, 0, 1, 'on/off', 960, 'Provider descriptions', 'public.svc_provider_description_record', 'CF-247 AU week step 5 (Part E spec): off until 5 hand-verified'),
 ('pipeline', 'description.provider_max_chars', 'Provider descriptions: longest', 'A description longer than this is refused.', 'number', '400'::jsonb, 200, 800, 'characters', 961, 'Provider descriptions', 'public.svc_provider_description_next, public.svc_provider_description_record', 'CF-247 Part E spec (400)'),
 ('pipeline', 'description.about_paths', 'Provider descriptions: about page addresses', 'Paths tried on the provider''s website, in order, after links titled About on its home page.', 'list', '["/about/", "/about", "/about-us/", "/about-us"]'::jsonb, null, null, 'paths', 962, 'Provider descriptions', 'public.svc_provider_description_next', 'CF-247 Part E spec'),
 ('pipeline', 'description.model', 'Provider descriptions: model', 'The one pinned model that writes descriptions (no automatic routing across models).', 'text', '"openai/gpt-4.1-mini"'::jsonb, null, null, 'model', 963, 'Provider descriptions', 'public.svc_provider_description_next', 'CF-247 Part E spec: pinned, individually qualified (same model as central pages)'),
 ('pipeline', 'description.countries', 'Provider descriptions: countries', 'Countries whose providers get a description.', 'list', '["AU"]'::jsonb, null, null, 'countries', 964, 'Provider descriptions', 'security.provider_description_enqueue_v1', 'CF-247 Part E spec: AU first'),
 ('pipeline', 'description.provider_types', 'Provider descriptions: provider types', 'Provider types read, in this order of priority.', 'list', '["university"]'::jsonb, null, null, 'types', 965, 'Provider descriptions', 'security.provider_description_enqueue_v1', 'CF-247 Part E spec: AU''s universities first'),
 ('pipeline', 'description.banned_words', 'Provider descriptions: words not allowed', 'Superlatives and marketing words: a description containing any of them is refused, even when the page uses them.', 'list', '["leading", "world-leading", "world-class", "best", "top", "premier", "excellence", "excellent", "outstanding", "renowned", "prestigious", "finest", "greatest", "unrivalled", "unparalleled", "unique", "cutting-edge", "vibrant", "exceptional", "world-renowned", "number one", "#1"]'::jsonb, null, null, 'words', 966, 'Provider descriptions', 'public.svc_provider_description_record', 'CF-247 Part E spec: no superlatives at all'),
 ('pipeline', 'description.refresh_days', 'Provider descriptions: read again after', 'A provider is read again after this many days only when its stored about page changed.', 'number', '90'::jsonb, 7, 365, 'days', 967, 'Provider descriptions', 'security.provider_description_enqueue_v1', 'CF-247 Part E spec: never a blind re-read'),
 ('pipeline', 'batch.provider_description', 'Provider descriptions: providers a run', 'Providers read in one worker call.', 'number', '10'::jsonb, 1, 50, 'providers', 968, 'Provider descriptions', 'job provider-description', 'CF-247 Part E spec'),
 ('openrouter', 'guard_provider_description', 'Daily guard: provider descriptions with AI', 'Provider descriptions stop for the day when their AI spend reaches this (UTC day), inside the overall credit floor.', 'number', '1'::jsonb, 0, 50, 'US$ a day', 50, 'Daily guards', 'security.ai_use_allowed_v1(''provider_description'')', 'CF-247 AU week step 5')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.provider_descriptions (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  state text not null default 'queued' check (state in ('queued', 'leased', 'done', 'failed')),
  leased_until timestamptz,
  attempts int not null default 0,
  about_url text,
  storage_path text,
  content_hash text,
  model text,
  description text,
  quotes jsonb not null default '[]'::jsonb,
  checks jsonb not null default '{}'::jsonb,
  outcome text check (outcome in ('proposed', 'refused', 'no_page', 'applied', 'approved', 'rejected')),
  reason text,
  cost_usd numeric,
  error text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  decided_by uuid,
  decided_at timestamptz
);
create index if not exists provider_descriptions_provider on pipeline.provider_descriptions(provider_id, created_at desc);
comment on table pipeline.provider_descriptions is 'CF-247 AU week step 5 (Part E): each reading of a provider''s about page for its description: address, stored copy, pinned model, the text proposed, its exact source sentences, the checks and the outcome; the provenance of catalogue.providers.description';

-- 2 queue ----------------------------------------------------------------------------------------------------------------------------
create or replace function security.provider_description_enqueue_v1()
returns int language plpgsql security definer set search_path = '' as $f$
declare v int;
begin
  insert into pipeline.provider_descriptions(provider_id)
  select p.id
    from catalogue.providers p
    join ref.countries k on k.id = p.country_id
    left join ref.provider_types t on t.id = p.provider_type_id
   where k.iso_alpha2 in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'description.countries'), '[]'::jsonb)))
     and coalesce(t.code, 'other') in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'description.provider_types'), '[]'::jsonb)))
     and p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is not null and nullif(btrim(p.description), '') is null
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
     and not exists (select 1 from pipeline.manual_locks m where m.entity = 'provider' and m.entity_id = p.id and m.field = 'description')
     and not exists (select 1 from pipeline.provider_descriptions d where d.provider_id = p.id
                      and (d.state in ('queued', 'leased')
                           or d.created_at > now() - make_interval(days => security.pipeline_num_v1('description.refresh_days', 90)::int)))
  limit security.pipeline_num_v1('batch.provider_description', 10)::int;
  get diagnostics v = row_count;
  return v;
end $f$;
comment on function security.provider_description_enqueue_v1() is 'CF-247 AU week step 5: queues providers in scope with a website, no description and no manual lock, not read within description.refresh_days';
revoke all on function security.provider_description_enqueue_v1() from public, anon, authenticated;

-- 3 worker interface -----------------------------------------------------------------------------------------------------------------
create or replace function public.svc_provider_description_next(p_limit int)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  if not security.ai_use_allowed_v1('provider_description') then return '[]'::jsonb; end if;
  with c as (
    select d.id from pipeline.provider_descriptions d
     where d.state = 'queued' or (d.state = 'leased' and d.leased_until < now())
     order by d.created_at limit greatest(1, least(p_limit, 50))  -- fixed: the setting's upper bound (batch.provider_description)
     for update skip locked),
  u as (
    update pipeline.provider_descriptions d set state = 'leased', leased_until = now() + interval '5 minutes', attempts = d.attempts + 1  -- fixed: lease
      from c where d.id = c.id returning d.*)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id, 'provider_id', u.provider_id, 'provider', coalesce(nullif(p.display_name, ''), p.canonical_name), 'website', p.website,
           'country', k.iso_alpha2, 'about_paths', security.toolset_setting('pipeline', 'description.about_paths'),
           'model', security.toolset_setting('pipeline', 'description.model') #>> '{}',
           'max_chars', security.pipeline_num_v1('description.provider_max_chars', 400)::int,
           'banned_words', security.toolset_setting('pipeline', 'description.banned_words'))), '[]'::jsonb)
    into v
    from u join catalogue.providers p on p.id = u.provider_id join ref.countries k on k.id = p.country_id;
  return v;
end $f$;
revoke all on function public.svc_provider_description_next(int) from public, anon, authenticated;
grant execute on function public.svc_provider_description_next(int) to service_role;

-- The record re-checks every rule; the worker's own checks are not trusted alone.
create or replace function public.svc_provider_description_record(p_id uuid, p_result jsonb, p_cost numeric, p_error text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare d pipeline.provider_descriptions; v_text text := btrim(coalesce(p_result->>'description', '')); v_max int := security.pipeline_num_v1('description.provider_max_chars', 400)::int;
        v_bad text[]; v_quotes jsonb := coalesce(p_result->'quotes', '[]'::jsonb); v_out text; v_why text; v_locked boolean; v_checks jsonb;
begin
  select * into d from pipeline.provider_descriptions where id = p_id for update;
  if d.id is null then raise exception 'reading not found'; end if;
  if p_error is not null then
    update pipeline.provider_descriptions set state = case when d.attempts >= 3 then 'failed' else 'queued' end, leased_until = null, error = left(p_error, 400), cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0)  -- fixed: three attempts
     where id = p_id;
    return jsonb_build_object('status', 'error');
  end if;
  if nullif(p_result->>'about_url', '') is null then
    update pipeline.provider_descriptions set state = 'done', outcome = 'no_page', reason = coalesce(p_result->>'why', 'no about page found'), read_at = now(), cost_usd = coalesce(p_cost, 0) where id = p_id;
    return jsonb_build_object('status', 'no_page');
  end if;
  select array_agg(w) into v_bad from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'description.banned_words'), '[]'::jsonb)) w
   where v_text ~* ('(^|[^[:alnum:]])' || regexp_replace(w, '([^[:alnum:] ])', '\\\1', 'g') || '($|[^[:alnum:]])');
  v_checks := jsonb_build_object('chars', length(v_text), 'max_chars', v_max, 'banned_found', to_jsonb(coalesce(v_bad, '{}')),
                                 'quotes', jsonb_array_length(v_quotes), 'quotes_on_page', coalesce(p_result->'quotes_on_page', 'false'::jsonb));
  v_why := case when v_text = '' then 'no description returned'
                when length(v_text) > v_max then format('%s characters, more than %s', length(v_text), v_max)
                when cardinality(coalesce(v_bad, '{}')) > 0 then 'words not allowed: ' || array_to_string(v_bad, ', ')
                when jsonb_array_length(v_quotes) = 0 then 'no source sentence quoted'
                when coalesce((p_result->>'quotes_on_page')::boolean, false) is not true then 'a quoted sentence is not on the stored page' end;
  select exists (select 1 from pipeline.manual_locks m where m.entity = 'provider' and m.entity_id = d.provider_id and m.field = 'description') into v_locked;
  v_out := case when v_why is not null then 'refused'
                when security.pipeline_num_v1('description.enabled', 0) >= 1 and not v_locked
                     and exists (select 1 from catalogue.providers p where p.id = d.provider_id and nullif(btrim(p.description), '') is null) then 'applied'
                else 'proposed' end;
  update pipeline.provider_descriptions
     set state = 'done', leased_until = null, about_url = p_result->>'about_url', storage_path = p_result->>'storage_path', content_hash = p_result->>'content_hash',
         model = p_result->>'model', description = nullif(v_text, ''), quotes = v_quotes, checks = v_checks, outcome = v_out, reason = v_why,
         cost_usd = coalesce(p_cost, 0), read_at = now(), error = null
   where id = p_id;
  if v_out = 'applied' then
    update catalogue.providers set description = v_text, updated_at = now() where id = d.provider_id and nullif(btrim(description), '') is null;
  end if;
  return jsonb_build_object('status', v_out, 'reason', v_why);
end $f$;
revoke all on function public.svc_provider_description_record(uuid, jsonb, numeric, text) from public, anon, authenticated;
grant execute on function public.svc_provider_description_record(uuid, jsonb, numeric, text) to service_role;
