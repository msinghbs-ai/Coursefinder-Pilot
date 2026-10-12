-- CF-247 v2.15.256 (12 Oct 2026). Platform Admin status review, fix 3: "onboarding fallback to the university's central pages".
-- Found: 53 universities need a person because their course pages do not state the field; most have central pages found already, but
-- the rule parser read nothing from them (fee schedules 58 no values, English policies and calendars 100 no values).
-- 1. A pinned model (GPT-4.1 mini, openai/gpt-4.1-mini, provider routing require_parameters) reads the stored English language policy and
--    academic calendar pages (worker v0.21.0, mode central_ai). Every score and month must be in a quote that is on the page. The result is
--    recorded as a proposal in the rule parser's shape (parser "ai:gpt-4.1-mini"): a person approves it in the Adapter builder (1.3) or
--    Providers › Onboarding › Approvals waiting. Nothing is applied by the AI. Approved English policies fill English for courses with none;
--    calendars turn a course page's "Semester 1" into a month. Fee schedules are not read by the AI (Australian fee schedules are matched
--    by CRICOS code; that stays with the rule parser).
-- 2. Onboarding: when nothing passes after the AI attempts, the university's central pages are queued for the AI. When a proposal is
--    ready the row shows "Approve central pages" (stop reason approve_central); once its proposals are decided and one was approved, the
--    university is done.
-- 3. Scheduled job central-ai (every 5 minutes, catalogued) sends queued pages to the worker. Queue: pipeline.central_ai_queue.
-- Guarded on the live definitions; nothing dropped.
do $guard$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "f97a0eed5b91bd10359e039b480a1492", "security.provider_onboarding_tick_v1()": "9ea953d2b80f465b83ba8e6cd97588bf"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create table if not exists pipeline.central_ai_settings (
  id int primary key default 1 check (id = 1), enabled boolean not null default true, model_code text not null, model_identifier text not null,
  calls_at_once int not null default 2 check (calls_at_once between 0 and 6), reason text, changed_by uuid, changed_at timestamptz not null default now());
alter table pipeline.central_ai_settings enable row level security;
revoke all on pipeline.central_ai_settings from public, anon, authenticated;
insert into pipeline.central_ai_settings(id, model_code, model_identifier, reason)
values (1, 'gpt-4.1-mini', 'openai/gpt-4.1-mini', 'Platform Admin 12 Oct 2026 status review, fix 3: pinned model for central pages; every result is approved by a person')
on conflict (id) do nothing;

create table if not exists pipeline.central_ai_queue (
  id bigserial primary key, fact_source_id uuid not null references pipeline.provider_fact_sources(id) on delete cascade,
  provider_id uuid not null, kind text not null check (kind in ('english_policy', 'intake_calendar')), content_hash text,
  state text not null default 'queued' check (state in ('queued', 'leased', 'done', 'failed')), attempts int not null default 0,
  leased_until timestamptz, created_at timestamptz not null default now(), done_at timestamptz, status text, cost_usd numeric, error text);
create unique index if not exists central_ai_queue_one_open on pipeline.central_ai_queue (fact_source_id) where state in ('queued', 'leased');
create index if not exists central_ai_queue_state_idx on pipeline.central_ai_queue (state, id);
alter table pipeline.central_ai_queue enable row level security;
revoke all on pipeline.central_ai_queue from public, anon, authenticated;

-- queue a university's stored English policy and calendar pages that have no proposal to decide and were not read by the AI at this copy
create or replace function security.central_ai_enqueue_v1(p_provider uuid) returns int language plpgsql security definer set search_path to '' as $f$
declare v_n int;
begin
  if not coalesce((select s.enabled from pipeline.central_ai_settings s where s.id = 1), false) then return 0; end if;
  insert into pipeline.central_ai_queue(fact_source_id, provider_id, kind, content_hash)
  select f.id, f.provider_id, f.kind, f.content_hash from pipeline.provider_fact_sources f
    join pipeline.evidence_artifacts e on e.id = f.evidence_id and e.storage_path is not null
   where f.provider_id = p_provider and f.kind in ('english_policy', 'intake_calendar') and f.status in ('read', 'parsed', 'no_values')
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.fact_source_id = f.id and pp.status in ('proposed', 'approved'))
     and not exists (select 1 from pipeline.central_ai_queue q where q.fact_source_id = f.id and (q.state in ('queued', 'leased') or q.content_hash is not distinct from f.content_hash))
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $f$;
revoke all on function security.central_ai_enqueue_v1(uuid) from public, anon, authenticated;

create or replace function public.svc_central_ai_next(p_limit integer) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v jsonb; s pipeline.central_ai_settings%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into s from pipeline.central_ai_settings where id = 1;
  if not coalesce(s.enabled, false) then return '[]'::jsonb; end if;
  with pick as (select q.id from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                 order by q.id limit greatest(1, least(coalesce(p_limit, 6), 10)) for update skip locked),
  upd as (update pipeline.central_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'id', u.fact_source_id, 'kind', u.kind, 'url', f.url, 'provider', coalesce(p.display_name, p.canonical_name),
           'storage_path', e.storage_path, 'model', s.model_identifier, 'model_code', s.model_code)), '[]'::jsonb) into v
    from upd u join pipeline.provider_fact_sources f on f.id = u.fact_source_id join pipeline.evidence_artifacts e on e.id = f.evidence_id
    join catalogue.providers p on p.id = u.provider_id;
  return v;
end $f$;
revoke all on function public.svc_central_ai_next(integer) from public, anon, authenticated;
grant execute on function public.svc_central_ai_next(integer) to service_role;

-- record the AI's reading as a proposal (the rule parser's shape) through svc_provider_policy_record; nothing is applied here
create or replace function public.svc_central_ai_record(p_queue_id bigint, p_parsed jsonb, p_cost numeric, p_error text) returns jsonb language plpgsql security definer set search_path to '' as $f$
declare q pipeline.central_ai_queue%rowtype; r jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into q from pipeline.central_ai_queue where id = p_queue_id for update;
  if q.id is null then return jsonb_build_object('ok', false); end if;
  if p_error is not null then
    update pipeline.central_ai_queue set state = case when p_error = 'time budget' then 'queued' when attempts >= 3 then 'failed' else 'queued' end,
           attempts = case when p_error = 'time budget' then greatest(attempts - 1, 0) else attempts end, leased_until = null, error = left(p_error, 400), cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0)
     where id = q.id;
    return jsonb_build_object('ok', true, 'status', 'error');
  end if;
  r := public.svc_provider_policy_record(q.fact_source_id, p_parsed);
  update pipeline.central_ai_queue set state = 'done', done_at = now(), leased_until = null, status = r->>'status', cost_usd = coalesce(cost_usd, 0) + coalesce(p_cost, 0), error = null where id = q.id;
  if r->>'status' = 'proposed' then
    update pipeline.provider_onboarding o set stop_reason = 'approve_central', updated_at = now(),
           note = 'The AI read its central pages; approve or reject them in the Adapter builder (1.3) or Providers › Onboarding › Approvals waiting.'
     where o.provider_id = q.provider_id and o.status = 'stopped' and o.stop_reason = 'nothing_ready';
  end if;
  return jsonb_build_object('ok', true, 'status', r->>'status');
end $f$;
revoke all on function public.svc_central_ai_record(bigint, jsonb, numeric, text) from public, anon, authenticated;
grant execute on function public.svc_central_ai_record(bigint, jsonb, numeric, text) to service_role;

create or replace function security.central_ai_fire_v1() returns int language plpgsql security definer set search_path to '' as $f$
declare v_open int; v_max int; v_due int; v_sent int := 0;
begin
  select calls_at_once into v_max from pipeline.central_ai_settings where id = 1 and enabled;
  select count(*) into v_due from pipeline.central_ai_queue q where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3;
  if v_due = 0 or coalesce(v_max, 0) = 0 then return 0; end if;
  select count(*) into v_open from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = 'central_ai' and l.created_at > now() - interval '3 minutes'
     and not exists (select 1 from net._http_response r where r.id = l.request_id);
  while v_open + v_sent < v_max and v_sent * 6 < v_due loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'central_ai', 'limit', 6));
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $f$;
revoke all on function security.central_ai_fire_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('central-ai', 'Course pages', 6, 'Read central pages with AI',
        'Sends queued English language policy and academic calendar pages to the pinned model (GPT-4.1 mini); each score and month must be quoted from the page. Results are proposals a person approves in the Adapter builder (1.3); nothing is applied by the AI.', 6, false)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'central-ai') then perform cron.schedule('central-ai', '*/5 * * * *', 'select security.central_ai_fire_v1()'); end if;
end $c$;

CREATE OR REPLACE FUNCTION security.provider_onboarding_step_v1(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o pipeline.provider_onboarding%rowtype; p catalogue.providers%rowtype; j pipeline.admin_jobs%rowtype; d pipeline.uni_adapter_drafts%rowtype;
        v_courses int; v_read int; v_need int; v_r jsonb; v_prop jsonb; v_adapter jsonb; v_q jsonb; v_rd jsonb; v_b jsonb; v_s record; v_central jsonb := '[]'::jsonb;
        v_age interval; v_central_n int := 0;
begin
  select * into o from pipeline.provider_onboarding where id = p_id for update skip locked;
  if o.id is null then return; end if;
  select * into p from catalogue.providers where id = o.provider_id;
  v_age := now() - coalesce(o.step_started_at, now());
  if p.id is null or p.lifecycle_status <> 'active' then
    update pipeline.provider_onboarding set status = 'cancelled', note = 'The university is no longer active.', finished_at = now(), updated_at = now() where id = o.id; return;
  end if;
  select count(*) into v_courses from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active';
  select count(*) into v_read from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_status = 'read';
  v_need := least(3, greatest(v_courses, 1));
  if o.job_id is not null then select * into j from pipeline.admin_jobs where id = o.job_id; end if;

  if o.status = 'queued' then
    update pipeline.provider_onboarding set status = 'website', started_at = coalesce(started_at, now()), step_started_at = now(), job_id = null, note = 'Finding the website, contacts and central pages.', updated_at = now() where id = o.id;

  elsif o.status = 'website' then
    if j.id is null then
      if nullif(p.website, '') is not null and exists (select 1 from pipeline.admin_jobs x where x.kind = 'provider_fill' and x.scope = o.provider_id::text and x.state = 'done' and x.finished_at > now() - interval '30 days') then
        update pipeline.provider_onboarding set status = 'course_pages', step_started_at = now(), job_id = null, note = 'Website known; finding course pages.', updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set job_id = security.provider_onboarding_job_v1('provider_fill', o.provider_id, jsonb_build_object('provider_id', o.provider_id, 'scope', o.provider_id)),
               step_started_at = now(), note = 'Finding the website, contacts and central pages (Fill in from website).', updated_at = now() where id = o.id;
      end if;
    elsif j.state in ('done', 'failed', 'cancelled') then
      if nullif(p.website, '') is null then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'no_website', job_id = null,
               note = 'No website could be verified. Enter it in Layer 4 › Websites to find (or the Adapter builder); onboarding carries on by itself.', updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set status = 'course_pages', step_started_at = now(), job_id = null, result = result || jsonb_build_object('website', p.website), note = 'Website found; finding course pages.', updated_at = now() where id = o.id;
      end if;
    end if;

  elsif o.status in ('course_pages', 'waiting_courses') then
    if v_courses = 0 then
      update pipeline.provider_onboarding set status = 'waiting_courses', note = 'No active courses yet; onboarding carries on when its courses arrive from the register.', updated_at = now() where id = o.id;
    elsif v_read >= v_need and exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and not a.enabled) then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'adapter_off', note = 'An adapter exists but is switched off; open it in Layer 2 › Adapters (onboarding does not overwrite it).', updated_at = now() where id = o.id;
    elsif v_read >= v_need and exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled) then
      -- an adapter already exists (built by hand or earlier): apply it again and qualify, never overwrite its settings
      perform public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: apply the existing adapter again'));
      update pipeline.provider_onboarding set status = 'applying', step_started_at = now(), job_id = null, result = result || jsonb_build_object('pages_read', v_read, 'courses', v_courses, 'existing_adapter', true),
             note = 'An adapter already exists; applying it again before qualifying.', updated_at = now() where id = o.id;
    elsif v_read >= v_need then
      v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: capture sample pages'));
      update pipeline.provider_onboarding set status = 'capturing', step_started_at = now(), job_id = null, draft_id = (v_r->>'draft_id')::uuid,
             result = result || jsonb_build_object('pages_read', v_read, 'courses', v_courses, 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0) + 1), note = format('%s course pages read; capturing sample pages.', v_read), updated_at = now() where id = o.id;
    elsif j.id is null then
      -- v2.15.253 fix: a website recorded before generic recipes existed has none; add the generic one (any page on its own site)
      if not exists (select 1 from pipeline.course_link_recipes r where r.provider_id = o.provider_id and r.active) and nullif(p.website, '') is not null then
        insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
        select o.provider_id, x.dom, jsonb_build_array(jsonb_build_object(
                 're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(x.dom, '\.', '\\.', 'g') || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
                 'rep', '\&')), true,
               'Generic recipe: any page on the provider''s own site (onboarding, CF-247 v2.15.253); used only when the reader proves the page is the course''s', now()
          from (select lower(regexp_replace(substring(p.website from '^(?:https?://)?([^/:?#]+)'), '^www\.', '')) dom) x
         where x.dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        on conflict (provider_id) do update set search_domain = excluded.search_domain, patterns = excluded.patterns, active = true, notes = excluded.notes, updated_at = now()
         where not pipeline.course_link_recipes.active
           and (pipeline.course_link_recipes.notes like 'Generic recipe%' or pipeline.course_link_recipes.search_domain is distinct from excluded.search_domain);
      end if;
      -- v2.15.254: a recipe switched off for this same site is a person's decision; stop with a plain reason instead of an error
      if not exists (select 1 from pipeline.course_link_recipes r where r.provider_id = o.provider_id and r.active)
         and exists (select 1 from pipeline.course_link_recipes r where r.provider_id = o.provider_id) then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'recipe_off', job_id = null,
               note = 'Its course-page search was switched off by a person for this website (' || coalesce((select r.search_domain from pipeline.course_link_recipes r where r.provider_id = o.provider_id), '?') || '). Check the website in the Adapter builder (1.1); entering a different website replaces the search, then Retry.',
               updated_at = now() where id = o.id;
        return;
      end if;
      insert into pipeline.firecrawl_targets(provider_id, included, reason, set_by, set_at) values (o.provider_id, true, 'Onboarding: find and read its course pages', auth.uid(), now())
      on conflict (provider_id) do update set included = true, reason = excluded.reason, set_by = excluded.set_by, set_at = now();
      update pipeline.provider_onboarding set status = 'course_pages', job_id = security.provider_onboarding_job_v1('course_page_find', o.provider_id, jsonb_build_object('provider_id', o.provider_id, 'scope', o.provider_id,
               -- at most 300 courses in one task: the courses without a read page, largest sample of kinds first
               'course_ids', (select coalesce(jsonb_agg(c.id), '[]'::jsonb) from (select c.id from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active'
                               and not exists (select 1 from pipeline.coverage_course_pages pg where pg.course_id = c.id and pg.read_status = 'read') order by c.id limit 300) c))),
             step_started_at = now(), note = format('Searching for course pages (%s of %s needed read so far).', v_read, v_need), updated_at = now() where id = o.id;
    elsif j.state in ('done', 'failed', 'cancelled') and v_age > interval '90 minutes'
          -- v2.15.256: not while pages the search found are still waiting to be read (up to 6 hours)
          and (v_age > interval '6 hours' or not exists (select 1 from pipeline.course_link_search s where s.provider_id = o.provider_id and s.state in ('queued', 'sent', 'found'))) then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'too_few_pages', job_id = null,
             note = format('Only %s of %s course pages could be read (%s needed). Add pages by hand in the Adapter builder (2.1), then Retry.', v_read, v_courses, v_need), updated_at = now() where id = o.id;
    elsif j.state not in ('done', 'failed', 'cancelled') then
      update pipeline.provider_onboarding set note = format('Searching for course pages: %s of %s needed read so far.', v_read, v_need), updated_at = now() where id = o.id;
    else
      update pipeline.provider_onboarding set note = format('Search finished; waiting for pages to be read (%s of %s needed).', v_read, v_need), updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'capturing' then
    select * into d from pipeline.uni_adapter_drafts where id = o.draft_id;
    if d.status = 'captured' then
      if not exists (select 1 from jsonb_array_elements(coalesce(d.captures, '[]'::jsonb)) c where not (c ? 'error')) then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'capture_failed', note = 'None of the sample pages could be captured.', updated_at = now() where id = o.id;
      else
        v_b := security.adapter_builder_budget();
        if (v_b->>'used_usd')::numeric >= (v_b->>'limit_usd')::numeric or (v_b->>'proposals')::int >= (v_b->>'limit_proposals')::int then
          update pipeline.provider_onboarding set note = 'Waiting for the AI allowance (it renews at midnight, Melbourne time).', updated_at = now() where id = o.id;
        else
          perform public.admin_adapter_builder('propose', jsonb_build_object('provider_id', o.provider_id, 'draft_id', o.draft_id, 'marks', '[]'::jsonb,
                   'comments', 'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.'
                   || coalesce(' The current settings did not pass: ' || (select string_agg(e.key || ': ' || e.value, '; ' order by e.key) from jsonb_each_text(coalesce(o.result->'held', '{}'::jsonb)) e) || '. Widen the patterns so each field is read on most course pages.', ''),
                   'reason', 'Onboarding: propose the adapter'));
          update pipeline.provider_onboarding set status = 'proposing', attempts = 0, step_started_at = now(), note = format('The pinned model (%s) is proposing the settings.', coalesce(nullif(d.model, ''), v_b->>'model')), updated_at = now() where id = o.id;
        end if;
      end if;
    elsif d.status = 'error' or v_age > interval '30 minutes' then
      if o.attempts < 1 then
        v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: capture sample pages again'));
        update pipeline.provider_onboarding set attempts = attempts + 1, step_started_at = now(), draft_id = (v_r->>'draft_id')::uuid, note = 'Capturing the sample pages again.', updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'capture_failed', note = 'Capturing the sample pages did not finish (' || coalesce(d.status, 'no draft') || ').', updated_at = now() where id = o.id;
      end if;
    end if;

  elsif o.status = 'proposing' then
    select * into d from pipeline.uni_adapter_drafts where id = o.draft_id;
    v_prop := d.proposals -> -1;
    if d.status = 'proposed' and v_prop is not null then
      if (v_prop->>'kind' = 'error' or v_prop->'adapter' is null) and o.attempts < 2 then
        perform public.admin_adapter_builder('propose', jsonb_build_object('provider_id', o.provider_id, 'draft_id', o.draft_id, 'marks', '[]'::jsonb,
                 'comments', 'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.', 'reason', 'Onboarding: propose the adapter again'));
        update pipeline.provider_onboarding set attempts = attempts + 1, step_started_at = now(), note = 'The proposal failed; asking the model again.', updated_at = now() where id = o.id;
      elsif v_prop->>'kind' = 'error' or v_prop->'adapter' is null then
        update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'proposal_failed', note = 'The model could not propose settings: ' || left(coalesce(v_prop->>'error', 'no settings returned'), 300), updated_at = now() where id = o.id;
      else
        v_adapter := coalesce(security.uni_adapter_json(o.provider_id), '{}'::jsonb) - 'updated_at' - 'reason'
                     || jsonb_strip_nulls(jsonb_build_object('json_source', v_prop->'adapter'->'json_source'))
                     || jsonb_build_object('json_paths', coalesce(security.uni_adapter_json(o.provider_id)->'json_paths', '{}'::jsonb) || coalesce(v_prop->'adapter'->'json_paths', '{}'::jsonb),
                                           'patterns', coalesce(security.uni_adapter_json(o.provider_id)->'patterns', '{}'::jsonb) || coalesce(v_prop->'adapter'->'patterns', '{}'::jsonb),
                                           'pick', coalesce(security.uni_adapter_json(o.provider_id)->'pick', '{}'::jsonb) || coalesce(v_prop->'adapter'->'pick', '{}'::jsonb),
                                           'enabled', true);
        perform public.admin_uni_adapter_write('save', jsonb_build_object('provider_id', o.provider_id, 'adapter', v_adapter, 'reason', 'Onboarding: settings proposed by the pinned model'));
        perform public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: apply to the stored pages'));
        update pipeline.provider_onboarding set status = 'applying', step_started_at = now(), result = result || jsonb_build_object('proposal_cost', v_prop->'cost', 'model', v_prop->'model'),
               note = 'Saved (switched on, testing, nothing admitted) and applying to the stored pages.', updated_at = now() where id = o.id;
      end if;
    elsif (d.status = 'error' or (d.status = 'proposed' and v_prop->>'kind' = 'error') or (d.status = 'proposing' and v_age > interval '30 minutes')) and o.attempts < 2 then
      -- a failed answer (for example no answer from the model), or none after 30 minutes (v2.15.254), is asked again, twice at most
      perform public.admin_adapter_builder('propose', jsonb_build_object('provider_id', o.provider_id, 'draft_id', o.draft_id, 'marks', '[]'::jsonb,
               'comments', 'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.', 'reason', 'Onboarding: propose the adapter again'));
      update pipeline.provider_onboarding set attempts = attempts + 1, step_started_at = now(), note = 'The proposal failed; asking the model again.', updated_at = now() where id = o.id;
    elsif d.status = 'error' or v_age > interval '30 minutes' then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'proposal_failed', note = 'The proposal did not finish: ' || left(coalesce(v_prop->>'error', d.status), 200), updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'applying' then
    if v_age > interval '90 minutes' or (v_age > interval '10 minutes' and not exists (select 1 from pipeline.uni_adapter_results r where r.provider_id = o.provider_id and r.at > now() - interval '5 minutes')) then
      update pipeline.provider_onboarding set status = 'qualifying', step_started_at = now(), note = 'Qualifying each field against the admit rule.', updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'qualifying' then
    v_q := security.adapter_qualify_one_v1(o.provider_id, coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5), coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9));
    v_rd := security.provider_onboarding_ready_v1(v_q);
    -- v2.15.255: nothing passes and fewer than 2 AI attempts in this onboarding: the AI proposes again (6, then 10 sample pages),
    -- told which fields did not pass; the proposal is merged over the current settings (an old adapter included)
    if jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) = 0 and coalesce((o.result->>'ai_attempts')::int, 0) < 2 and v_read >= v_need then
      v_r := public.admin_adapter_builder('start', jsonb_build_object('provider_id', o.provider_id, 'samples', case when coalesce((o.result->>'ai_attempts')::int, 0) = 0 then 6 else 10 end,
               'reason', 'Onboarding: no field passes; the AI proposes again'));
      update pipeline.provider_onboarding set status = 'capturing', step_started_at = now(), job_id = null, draft_id = (v_r->>'draft_id')::uuid, attempts = 0,
             result = result || jsonb_build_object('qualify', v_q, 'ready', v_rd->'ready', 'held', v_rd->'held', 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0) + 1),
             note = format('No field passes yet; the AI proposes settings from %s sample pages (AI attempt %s of 2).', case when coalesce((o.result->>'ai_attempts')::int, 0) = 0 then 6 else 10 end, coalesce((o.result->>'ai_attempts')::int, 0) + 1),
             updated_at = now() where id = o.id;
      return;
    end if;
    -- central pages: the Firecrawl map's suggestions first, then the provider's stored links; approved by a person in the Adapter builder (1.3)
    for v_s in select distinct on (s.kind) s.kind, s.url from (
                 select f.value->>'kind' kind, f.value->>'url' url, 1 pri from pipeline.provider_central_search c
                   cross join lateral jsonb_array_elements(case jsonb_typeof(c.found) when 'array' then c.found else '[]'::jsonb end) f(value)
                  where c.provider_id = o.provider_id and f.value->>'kind' in ('intake_calendar', 'fee_schedule', 'english_policy') and f.value->>'url' is not null
                    and coalesce((f.value->>'score')::numeric, 0) >= 4
                 union all
                 select x.kind, u.url, 2 from pipeline.coverage_provider_urls u cross join lateral (select case
                   when u.url ~* '(key-?dates|academic-?calendar|semester-?dates|term-?dates|important-?dates|principal-?dates)' then 'intake_calendar'
                   when u.url ~* '(international.*(fee|tuition)|(fee|tuition).*international|fee-?schedule|tuition-?fees)' then 'fee_schedule'
                   when u.url ~* '(english-?language-?requirement|english-?requirement|english-?proficiency)' then 'english_policy' end kind) x
                  where u.provider_id = o.provider_id and x.kind is not null) s
               where not exists (select 1 from pipeline.provider_fact_sources fs where fs.provider_id = o.provider_id and fs.kind = s.kind)
               order by s.kind, s.pri, length(s.url) loop
      begin
        perform public.admin_provider_central_page('add', jsonb_build_object('provider_id', o.provider_id, 'kind', v_s.kind, 'url', v_s.url, 'reason', 'Onboarding: suggested central page'));
        v_central := v_central || jsonb_build_object('kind', v_s.kind, 'url', v_s.url);
      exception when others then null;
      end;
    end loop;
    update pipeline.provider_onboarding set status = 'scholarships', step_started_at = now(), job_id = null,
           result = result || jsonb_build_object('qualify', v_q, 'ready', v_rd->'ready', 'held', v_rd->'held', 'central_pages', v_central),
           note = 'Qualified; finding scholarships.', updated_at = now() where id = o.id;

  elsif o.status = 'scholarships' then
    -- v2.15.255: searched once in this onboarding already (a retry or a second AI attempt): finish without searching again
    if j.id is null and o.result ? 'scholarships' then j.state := 'done'; j.result := o.result->'scholarships'; end if;
    if j.id is null and j.state is null then
      update pipeline.provider_onboarding set job_id = security.provider_onboarding_job_v1('scholarship_provider_scan', o.provider_id, jsonb_build_object('provider_ids', jsonb_build_array(o.provider_id), 'scope', o.provider_id)),
             step_started_at = now(), note = 'Finding scholarships (map, screen, read).', updated_at = now() where id = o.id;
    elsif j.state in ('done', 'failed', 'cancelled') then
      -- v2.15.256: nothing ready: the university's central pages go to the AI, for a person to approve
      if jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) = 0 then v_central_n := security.central_ai_enqueue_v1(o.provider_id); end if;
      -- v2.15.255: nothing ready after the AI attempts is "Needs a person" (stopped, nothing_ready), not Ready to admit
      update pipeline.provider_onboarding set status = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'waiting_admit' else 'stopped' end,
             stop_reason = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then null else 'nothing_ready' end,
             job_id = null, result = result || jsonb_build_object('scholarships', j.result),
             note = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'Ready to admit: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(o.result->'ready') x) || '. A Platform Admin admits on Layer 2 › Adapters.'
                         else format('Nothing passed after %s AI attempt(s); the Fields column shows why for each field.%s', coalesce((o.result->>'ai_attempts')::int, 0),
                                     case when v_central_n > 0 then ' The AI is reading its central pages (English policy, calendar) for a person to approve.' else '' end) end,
             updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'waiting_admit' then
    if exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled and coalesce(a.admit, false)) then
      update pipeline.provider_onboarding set status = 'done', finished_at = now(), note = 'Admitted; onboarding complete.', updated_at = now() where id = o.id;
    end if;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION security.provider_onboarding_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s pipeline.provider_onboarding_settings%rowtype; o record; v_active int; v_n int := 0; v_err int := 0; v_started int := 0;
begin
  select * into s from pipeline.provider_onboarding_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('skipped', 'onboarding is switched off'); end if;
  -- a missing website was entered: carry on
  update pipeline.provider_onboarding ob set status = 'website', stop_reason = null, step_started_at = now(), job_id = null, note = 'Website entered; carrying on.', updated_at = now()
    from catalogue.providers pv where pv.id = ob.provider_id and ob.status = 'stopped' and ob.stop_reason = 'no_website' and nullif(pv.website, '') is not null;
  -- v2.15.255: a university that needed a person and has since been admitted by hand is done
  update pipeline.provider_onboarding ob set status = 'done', stop_reason = null, finished_at = now(), note = 'Admitted by a person; onboarding complete.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason in ('nothing_ready', 'approve_central')
     and exists (select 1 from pipeline.uni_adapters a where a.provider_id = ob.provider_id and a.enabled and coalesce(a.admit, false));
  -- v2.15.256: central pages read by the AI and decided by a person (at least one approved): done
  update pipeline.provider_onboarding ob set status = 'done', stop_reason = null, finished_at = now(), note = 'Central pages approved by a person; onboarding complete.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason = 'approve_central'
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'proposed')
     and exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'approved' and pp.decided_at >= coalesce(ob.started_at, ob.created_at));
  select count(*) into v_active from pipeline.provider_onboarding where status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships');
  for o in select id from pipeline.provider_onboarding where status = 'queued' order by priority desc, created_at limit greatest(coalesce(s.max_active, 0) - v_active, 0) loop
    update pipeline.provider_onboarding set status = 'website', started_at = now(), step_started_at = now(), note = 'Starting.', updated_at = now() where id = o.id;
    v_started := v_started + 1;
  end loop;
  for o in select ob.id, coalesce(ob.requested_by, s.run_as) run_as from pipeline.provider_onboarding ob
            where ob.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships', 'waiting_admit')
               or (ob.status = 'waiting_courses' and ob.updated_at < now() - interval '1 hour')
            order by ob.updated_at limit 120 loop
    begin
      perform set_config('request.jwt.claims', jsonb_build_object('sub', o.run_as::text, 'role', 'authenticated')::text, true);
      perform security.provider_onboarding_step_v1(o.id);
      v_n := v_n + 1;
    exception when others then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'error', note = left('Stopped: ' || sqlerrm, 500), updated_at = now() where id = o.id;
      v_err := v_err + 1;
    end;
    perform set_config('request.jwt.claims', '', true);
  end loop;
  return jsonb_build_object('started', v_started, 'advanced', v_n, 'stopped_by_error', v_err);
end $function$;

-- the universities that need a person now: their central pages go to the AI
do $e$ declare r record; v int := 0; begin
  for r in select provider_id from pipeline.provider_onboarding where status = 'stopped' and stop_reason = 'nothing_ready' loop
    v := v + security.central_ai_enqueue_v1(r.provider_id);
  end loop;
  raise notice 'central pages queued: %', v;
end $e$;

do $post$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "120ef69e34a2308c1684f46773261c44", "security.provider_onboarding_tick_v1()": "ddcaa4f4bedef103c9e07613ee70a080"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.256 central AI post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
