-- CF-247 v2.15.255 (12 Oct 2026). Platform Admin, 11:15: "Will this create the adapter automatically, start the scholarships as well,
-- and can I monitor the journey from the UI?" Live check: 35 of 38 universities at Ready to admit had nothing to admit (27 had an old
-- adapter that onboarding applied again without asking the AI), and New scholarships showed 0 because pages were still with the AI.
-- Decisions: the AI proposes over an old adapter that passes no field; nothing ready means one more AI attempt with more sample pages,
-- then "Needs a person"; an expandable journey per university with live scholarship results.
-- 1. Qualifying: when no field passes and fewer than 2 AI attempts were made in this onboarding, the AI proposes again (6 sample pages,
--    then 10), told which fields did not pass and why; the proposal is merged over the current settings, saved in testing, applied and
--    qualified again. Admitting stays a person's step; a passing check never admits.
-- 2. Nothing ready after that: the row stops with reason nothing_ready, shown as "Needs a person" (not Ready to admit). The scholarship
--    search still runs once; a retry does not search again.
-- 3. Journey: pipeline.provider_onboarding_events records each step change (trigger); admin_provider_onboarding('journey') returns the
--    steps, the tasks, the AI drafts and the scholarships found with their state; each row shows live scholarship counts.
-- 4. Adapter builder 'start' takes an optional number of sample pages (1 to 10).
-- 5. The 35 universities at Ready to admit with nothing ready are sent back to qualifying (no scholarship search again).
-- Guarded: live definitions must match the snapshots this change was written from. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "333443c31185a6aa5daa96436b5dc2bf", "security.provider_onboarding_tick_v1()": "00ad2b365e981d102e9035104e53079b", "public.admin_adapter_builder(text, jsonb)": "08bcda47fabc0afc42e47f410face7ea", "public.admin_provider_onboarding(text, jsonb)": "af45e243263d4a0fdf33761379544067", "public.admin_waiting_read()": "8eae4aa1f362db6398c5bfb88eec1794"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create table if not exists pipeline.provider_onboarding_events (
  id bigserial primary key, onboarding_id uuid not null references pipeline.provider_onboarding(id) on delete cascade,
  at timestamptz not null default now(), status text, stop_reason text, note text, job_id uuid, draft_id uuid);
create index if not exists provider_onboarding_events_idx on pipeline.provider_onboarding_events (onboarding_id, at);
alter table pipeline.provider_onboarding_events enable row level security;
revoke all on pipeline.provider_onboarding_events from public, anon, authenticated;
create index if not exists scholarship_ai_queue_provider_queued_idx on pipeline.scholarship_ai_queue (provider_id) where state = 'queued';
create index if not exists scholarships_provider_created_idx on scholarship.scholarships (provider_id, created_at);

create or replace function security.provider_onboarding_event_v1() returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status or old.stop_reason is distinct from new.stop_reason
     or old.job_id is distinct from new.job_id or old.draft_id is distinct from new.draft_id then
    insert into pipeline.provider_onboarding_events(onboarding_id, status, stop_reason, note, job_id, draft_id)
    values (new.id, new.status, new.stop_reason, new.note, new.job_id, new.draft_id);
  end if;
  return new;
end $f$;
revoke all on function security.provider_onboarding_event_v1() from public, anon, authenticated;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'provider_onboarding_events_log' and tgrelid = 'pipeline.provider_onboarding'::regclass) then
    create trigger provider_onboarding_events_log after insert or update on pipeline.provider_onboarding
      for each row execute function security.provider_onboarding_event_v1();
  end if;
end $t$;

CREATE OR REPLACE FUNCTION security.provider_onboarding_step_v1(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o pipeline.provider_onboarding%rowtype; p catalogue.providers%rowtype; j pipeline.admin_jobs%rowtype; d pipeline.uni_adapter_drafts%rowtype;
        v_courses int; v_read int; v_need int; v_r jsonb; v_prop jsonb; v_adapter jsonb; v_q jsonb; v_rd jsonb; v_b jsonb; v_s record; v_central jsonb := '[]'::jsonb;
        v_age interval;
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
    elsif j.state in ('done', 'failed', 'cancelled') and v_age > interval '90 minutes' then
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
      -- v2.15.255: nothing ready after the AI attempts is "Needs a person" (stopped, nothing_ready), not Ready to admit
      update pipeline.provider_onboarding set status = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'waiting_admit' else 'stopped' end,
             stop_reason = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then null else 'nothing_ready' end,
             job_id = null, result = result || jsonb_build_object('scholarships', j.result),
             note = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'Ready to admit: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(o.result->'ready') x) || '. A Platform Admin admits on Layer 2 › Adapters.'
                         else format('Nothing is ready to admit after %s AI attempt(s): %s. Mark values on the sample pages in the Adapter builder or approve its central pages (1.3), then Retry.',
                                     coalesce((o.result->>'ai_attempts')::int, 0), coalesce((select string_agg(e.key || ': ' || e.value, '; ' order by e.key) from jsonb_each_text(coalesce(o.result->'held', '{}'::jsonb)) e), 'no field read')) end,
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
   where ob.status = 'stopped' and ob.stop_reason = 'nothing_ready'
     and exists (select 1 from pipeline.uni_adapters a where a.provider_id = ob.provider_id and a.enabled and coalesce(a.admit, false));
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

CREATE OR REPLACE FUNCTION public.admin_adapter_builder(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        v_id uuid; v_d pipeline.uni_adapter_drafts%rowtype; v_n int; v_b jsonb; v_samples jsonb; v_m jsonb; v_s jsonb; v_cid uuid; v_code text; v_host text; v_dom text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  if p_action = 'read' then
    return jsonb_build_object('budget', security.adapter_builder_budget(), 'can_manage', v_rank >= 6,
      'model', security.adapter_builder_model_for_v1(v_pid), 'models', case when v_rank >= 6 then security.adapter_builder_models_v1() else '[]'::jsonb end,
      'max_samples', 10,
      -- v2.15.232 (Feature 2): the provider's courses, to attach a course page entered by hand as a sample
      'courses', case when v_rank >= 6 then coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'course', coalesce(c.display_title, c.canonical_title),
                   'code', (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = c.id and lower(cr.scheme) = 'cricos' limit 1)) order by coalesce(c.display_title, c.canonical_title))
                   from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active'), '[]'::jsonb) else '[]'::jsonb end,
      'website', (select p.website from catalogue.providers p where p.id = v_pid),
      'pages', case when v_rank >= 6 then coalesce((select jsonb_agg(jsonb_build_object('course', x.title, 'code', x.code, 'url', x.url, 'read', x.read_status = 'read') order by x.title) from (
                 select distinct on (pg.url) coalesce(c.display_title, c.canonical_title) title, pg.url, pg.read_status,
                        (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code
                   from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
                  where pg.provider_id = v_pid and pg.url is not null limit 600) x), '[]'::jsonb) else '[]'::jsonb end,
      'drafts', coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from (select * from pipeline.uni_adapter_drafts where provider_id = v_pid order by created_at desc limit 3) d), '[]'::jsonb));
  end if;
  if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'model' then
    if not exists (select 1 from catalogue.providers where id = v_pid) then raise exception 'unknown provider'; end if;
    v_code := nullif(btrim(coalesce(p_args->>'profile_code', '')), '');
    if v_code is null then
      delete from pipeline.uni_adapter_models where provider_id = v_pid;
    else
      if not exists (select 1 from jsonb_array_elements(security.adapter_builder_models_v1()) x where x->>'code' = v_code) then
        raise exception 'that model is not enabled and qualified for intake work (Models & services)';
      end if;
      insert into pipeline.uni_adapter_models(provider_id, profile_code, set_by, reason) values (v_pid, v_code, auth.uid(), v_reason)
        on conflict (provider_id) do update set profile_code = excluded.profile_code, set_by = excluded.set_by, set_at = now(), reason = excluded.reason;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_model', v_pid::text, jsonb_build_object('profile_code', v_code, 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true, 'model', security.adapter_builder_model_for_v1(v_pid));
  end if;
  if p_action = 'start' then
    v_n := least(greatest(coalesce(nullif(p_args->>'samples', '')::int, (security.firecrawl_setting('builder_samples') #>> '{}')::int, 6), 1), 10);  -- v2.15.255: optional number of samples
    select coalesce(jsonb_agg(jsonb_build_object('course_id', x.course_id, 'course', x.title, 'code', x.code, 'url', x.url, 'kind', x.kind) order by x.kr, x.kind), '[]'::jsonb) into v_samples from (
      select q.*, row_number() over (partition by q.kind order by random()) kr from (
        select distinct on (pg.url) pg.course_id, coalesce(c.display_title, c.canonical_title) title, (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1) code, pg.url,
               case when coalesce(c.display_title, c.canonical_title) ~* '/|, bachelor|and bachelor|double' then 'double'
                    when coalesce(c.display_title, c.canonical_title) ~* 'master|graduate|doctor|postgrad' then 'postgraduate'
                    when coalesce(c.display_title, c.canonical_title) ~* 'certificate|diploma' then 'certificate or diploma'
                    else 'undergraduate' end kind
          from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status in ('active', 'inactive')
         where pg.provider_id = v_pid and pg.read_status = 'read' and pg.url is not null) q
      order by kr, kind limit v_n) x;
    if jsonb_array_length(coalesce(v_samples, '[]'::jsonb)) = 0 then raise exception 'no confirmed course page for this university yet - find pages first'; end if;
    insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, v_samples, v_reason, auth.uid()) returning id into v_id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_start', v_pid::text, jsonb_build_object('draft_id', v_id, 'samples', v_samples, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  -- v2.15.232 (Feature 2): a course page entered by hand. It must be on the provider's own website; it is saved as the course's
  -- official page (entered by hand, locked) through admin_course_edit, then added as a sample exactly as add_sample does.
  if p_action = 'add_page' then
    v_cid := nullif(p_args->>'course_id', '')::uuid;
    select c.provider_id into v_pid from catalogue.courses c where c.id = v_cid;
    if v_pid is null then raise exception 'pick one of this provider''s courses'; end if;
    if nullif(p_args->>'provider_id', '') is not null and v_pid <> (p_args->>'provider_id')::uuid then raise exception 'that course belongs to another provider'; end if;
    v_code := btrim(coalesce(p_args->>'url', ''));
    if v_code !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    v_host := lower(regexp_replace(substring(v_code from '^https?://([^/:?#]+)'), '^www\.', ''));
    select lower(regexp_replace(substring(coalesce(p.website, '') from '^(?:https?://)?([^/:?#]+)'), '^www\.', '')) into v_dom from catalogue.providers p where p.id = v_pid;
    if coalesce(v_dom, '') = '' then raise exception 'record the provider''s own website first (step 1), then add its course pages'; end if;
    if not (v_host = v_dom or v_host like '%.' || v_dom) then raise exception 'this page is not on the provider''s own website (%)', v_dom; end if;
    perform public.admin_course_edit(v_cid, 'set_official_url', jsonb_build_object('url', v_code, 'reason', v_reason));
    return public.admin_adapter_builder('add_sample', jsonb_build_object('course_id', v_cid, 'reason', v_reason));
  end if;
  if p_action = 'add_sample' then
    v_cid := nullif(p_args->>'course_id', '')::uuid;
    select jsonb_build_object('course_id', pg.course_id, 'course', coalesce(c.display_title, c.canonical_title),
             'code', (select cr.registration_code from catalogue.course_registrations cr where cr.course_id = pg.course_id and lower(cr.scheme) = 'cricos' limit 1),
             'url', pg.url, 'kind', 'chosen'), pg.provider_id
      into v_s, v_pid
      from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id
     where pg.url is not null and (pg.course_id = v_cid or (v_cid is null and pg.provider_id = v_pid and pg.url = nullif(p_args->>'url', '')))
     order by (pg.read_status = 'read') desc limit 1;
    if v_s is null then raise exception 'this course has no stored page to sample'; end if;
    select * into v_d from pipeline.uni_adapter_drafts where provider_id = v_pid order by created_at desc limit 1;
    if v_d.id is not null and v_d.status in ('capturing', 'proposing') then raise exception 'the current samples are still being captured or proposed; try again in a minute'; end if;
    if v_d.id is null then
      insert into pipeline.uni_adapter_drafts(provider_id, samples, reason, created_by) values (v_pid, jsonb_build_array(v_s), v_reason, auth.uid()) returning id into v_id;
    else
      if exists (select 1 from jsonb_array_elements(v_d.samples) x where x->>'url' = v_s->>'url') then raise exception 'this page is already a sample'; end if;
      if jsonb_array_length(v_d.samples) >= 10 then raise exception 'a draft holds at most 10 samples: capture new samples to start again'; end if;
      update pipeline.uni_adapter_drafts set samples = samples || jsonb_build_array(v_s), status = 'capturing', updated_at = now() where id = v_d.id;
      v_id := v_d.id;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_add_sample', v_pid::text, jsonb_build_object('draft_id', v_id, 'sample', v_s, 'reason', v_reason), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_capture', 'draft_id', v_id));
    return jsonb_build_object('ok', true, 'draft_id', v_id);
  end if;
  select * into v_d from pipeline.uni_adapter_drafts where id = (p_args->>'draft_id')::uuid;
  if v_d.id is null then raise exception 'unknown draft'; end if;
  if p_action = 'marks' then
    if jsonb_typeof(coalesce(p_args->'marks', '[]'::jsonb)) <> 'array' then raise exception 'marks must be a list'; end if;
    update pipeline.uni_adapter_drafts set marks = coalesce(p_args->'marks', '[]'::jsonb), comments = left(coalesce(p_args->>'comments', ''), 4000), updated_at = now() where id = v_d.id;
    return jsonb_build_object('ok', true);
  elsif p_action = 'propose' then
    if jsonb_array_length(v_d.captures) = 0 then raise exception 'capture the sample pages first'; end if;
    v_b := security.adapter_builder_budget();
    if (v_b->>'used_usd')::numeric >= (v_b->>'limit_usd')::numeric then raise exception 'the AI allowance for today is used (US$ % of %). It is a setting under Adapter builder', v_b->>'used_usd', v_b->>'limit_usd'; end if;
    if (v_b->>'proposals')::int >= (v_b->>'limit_proposals')::int then raise exception 'the proposals for today are used (% of %). It is a setting under Adapter builder', v_b->>'proposals', v_b->>'limit_proposals'; end if;
    v_m := security.adapter_builder_model_for_v1(v_d.provider_id);
    update pipeline.uni_adapter_drafts set status = 'proposing', marks = coalesce(p_args->'marks', marks), comments = coalesce(left(p_args->>'comments', 4000), comments), model = v_m->>'model', model_profile = v_m->>'code', updated_at = now() where id = v_d.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'adapter_builder_propose', v_d.provider_id::text, jsonb_build_object('draft_id', v_d.id, 'budget', v_b, 'model', v_m), auth.uid());
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'adapter_propose', 'draft_id', v_d.id));
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_onboarding(p_action text DEFAULT 'read'::text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_ids uuid[]; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  -- v2.15.255: one university's journey: steps, tasks, AI drafts, and the scholarships found with their state
  if p_action = 'journey' then
    return (select jsonb_build_object('id', o.id, 'status', o.status, 'stop_reason', o.stop_reason, 'started_at', o.started_at, 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0),
      'qualify', o.result->'qualify', 'held', o.result->'held', 'ready', o.result->'ready', 'central_pages', o.result->'central_pages', 'scholarship_search', o.result->'scholarships',
      'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'status', e.status, 'stop_reason', e.stop_reason, 'note', e.note) order by e.at), '[]'::jsonb)
                   from pipeline.provider_onboarding_events e where e.onboarding_id = o.id),
      'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'title', j.title, 'state', j.state, 'created_at', j.created_at, 'finished_at', j.finished_at,
                   'note', left(coalesce(j.result->>'note', j.error, ''), 300)) order by j.created_at), '[]'::jsonb)
                  from pipeline.admin_jobs j where j.scope = o.provider_id::text and j.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'drafts', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'status', d.status, 'created_at', d.created_at, 'updated_at', d.updated_at, 'samples', jsonb_array_length(coalesce(d.samples, '[]'::jsonb)),
                   'proposals', jsonb_array_length(coalesce(d.proposals, '[]'::jsonb)), 'model', d.model, 'cost_usd', d.cost_usd, 'reason', d.reason) order by d.created_at), '[]'::jsonb)
                  from pipeline.uni_adapter_drafts d where d.provider_id = o.provider_id and d.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'scholarships', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'publication_status', s.publication_status, 'lifecycle_status', s.lifecycle_status,
                   'created_at', s.created_at, 'url', s.source_url) order by s.created_at desc), '[]'::jsonb)
                  from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
      'ai_waiting', (select count(*) from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state = 'queued'),
      'ai_read', (select coalesce(jsonb_object_agg(t.v, t.n), '{}'::jsonb) from (select coalesce(x.verdict, 'failed') v, count(*) n from pipeline.scholarship_ai_extractions x
                   where x.provider_id = o.provider_id and x.at >= coalesce(o.started_at, o.created_at) group by 1) t))
      from pipeline.provider_onboarding o where o.id = nullif(p_args->>'id', '')::uuid);
  end if;
  if p_action <> 'read' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if p_action = 'start' then
      v_ids := case when p_args->>'scope' = 'no_adapter' then array(
                 select pr.id from catalogue.providers pr
                  where pr.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
                    and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                    and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false)))
               else array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x) end;
      if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'choose universities'; end if;
      insert into pipeline.provider_onboarding(provider_id, source, requested_by, reason, priority)
      select i, case when p_args->>'scope' = 'no_adapter' then 'backfill' else 'manual' end, auth.uid(), v_reason,
             case when p_args->>'scope' = 'no_adapter' then (select least(count(*), 99999)::int from catalogue.courses c where c.provider_id = i and c.lifecycle_status = 'active') else 200000 end
        from unnest(v_ids) i
      on conflict do nothing;
      get diagnostics v_n = row_count;
    elsif p_action = 'stop' then
      update pipeline.provider_onboarding set status = 'cancelled', note = 'Stopped by a person: ' || v_reason, finished_at = now(), updated_at = now()
       where id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)) x)) and status not in ('done', 'cancelled');
      get diagnostics v_n = row_count;
    elsif p_action = 'retry' then
      update pipeline.provider_onboarding set status = case when stop_reason in ('capture_failed', 'proposal_failed') then 'course_pages' else 'website' end,
             stop_reason = null, attempts = 0, job_id = null, step_started_at = now(), note = 'Retried by a person: ' || v_reason, requested_by = auth.uid(), updated_at = now()
       where id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'ids', '[]'::jsonb)) x)) and status = 'stopped';
      get diagnostics v_n = row_count;
    elsif p_action = 'settings' then
      update pipeline.provider_onboarding_settings set enabled = coalesce((p_args->>'enabled')::boolean, enabled), auto_start_new = coalesce((p_args->>'auto_start_new')::boolean, auto_start_new),
             max_active = coalesce((p_args->>'max_active')::int, max_active), run_as = case when (p_args->>'run_as_me')::boolean then auth.uid() else run_as end,
             changed_by = auth.uid(), changed_at = now(), reason = v_reason where id = 1;
      v_n := 1;
    else raise exception 'unknown action';
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('onboarding', p_action, coalesce(p_args->>'scope', ''), p_args || jsonb_build_object('count', v_n), auth.uid());
  end if;
  return jsonb_build_object(
    'can_manage', v_rank >= 6,
    'settings', (select to_jsonb(s) - 'id' from pipeline.provider_onboarding_settings s where s.id = 1),
    'counts', (select coalesce(jsonb_object_agg(t.status, t.n), '{}'::jsonb) from (select status, count(*) n from pipeline.provider_onboarding group by 1) t),
    'stops', (select coalesce(jsonb_object_agg(t.r, t.n), '{}'::jsonb) from (select stop_reason r, count(*) n from pipeline.provider_onboarding where status = 'stopped' group by 1) t),
    'without_adapter', (select count(*) from catalogue.providers pr where pr.lifecycle_status = 'active'
                          and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                          and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false))),
    'approvals_waiting', (select count(*) from pipeline.provider_fact_sources fs where fs.decision is null and fs.status = 'parsed' and fs.kind = 'fee_schedule')
                         + (select count(*) from pipeline.provider_policy_proposals pp where pp.status = 'proposed'),
    'rows', (select coalesce(jsonb_agg(x order by x->>'sort'), '[]'::jsonb) from (
       select jsonb_build_object('sort', lpad((case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end)::text, 2, '0') || to_char(o.updated_at, 'YYYYMMDDHH24MISS'),
              'id', o.id, 'provider_id', o.provider_id, 'name', coalesce(nullif(pr.display_name, ''), pr.canonical_name), 'country', (select k.iso_alpha2 from ref.countries k where k.id = pr.country_id),
              'website', pr.website, 'status', o.status, 'stop_reason', o.stop_reason, 'note', o.note, 'source', o.source, 'job_id', o.job_id,
              'ready', o.result->'ready', 'held', o.result->'held', 'central_pages', o.result->'central_pages', 'scholarships', o.result->'scholarships'->'new_scholarships', 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0),
              'scholarships_live', jsonb_build_object('found', (select count(*) from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute'),
                 'published', (select count(*) from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute' and s.publication_status = 'published'),
                 'waiting_ai', (select count(*) from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state = 'queued'),
                 'searched', o.result ? 'scholarships'),
              'courses', (select count(*) from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active'),
              'pages_read', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_status = 'read'),
              'started_at', o.started_at, 'step_started_at', o.step_started_at, 'updated_at', o.updated_at, 'finished_at', o.finished_at, 'created_at', o.created_at) x
         from pipeline.provider_onboarding o join catalogue.providers pr on pr.id = o.provider_id
        where (p_args->>'status' is null or o.status = p_args->>'status' or (p_args->>'status' = 'active' and o.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships')))
          and (p_args->>'q' is null or coalesce(pr.display_name, pr.canonical_name) ilike '%' || (p_args->>'q') || '%')
        order by case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end, o.updated_at desc
        limit least(greatest(coalesce((p_args->>'limit')::int, 200), 1), 500)) t));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_waiting_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_rows jsonb := '[]'::jsonb; v_n bigint; v_old timestamptz;
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.layer4_review_items where status = 'pending';
    v_rows := v_rows || jsonb_build_object('key','review','label','Review items to decide','count',v_n,'oldest',v_old,'href','#layer-4-review','min',3);
  exception when others then null; end;
  -- v2.15.254: Flagged values and Fee rules were retired (v2.15.253); onboarding waits on a person instead
  begin
    select count(*), min(updated_at) into v_n, v_old from pipeline.provider_onboarding where status = 'waiting_admit';
    v_rows := v_rows || jsonb_build_object('key','onboarding_admit','label','Universities ready to admit','count',v_n,'oldest',v_old,'href','#providers?tab=onboarding','min',3);
  exception when others then null; end;
  begin
    select count(*), min(updated_at) into v_n, v_old from pipeline.provider_onboarding where status = 'stopped';
    v_rows := v_rows || jsonb_build_object('key','onboarding_stopped','label','Onboarding stopped or needs a person','count',v_n,'oldest',v_old,'href','#providers?tab=onboarding','min',3);
  exception when others then null; end;
  begin
    select count(distinct c.scholarship_id), min(c.created_at) into v_n, v_old from scholarship.course_mapping_candidates c where c.status = 'needs_review';
    v_rows := v_rows || jsonb_build_object('key','scholarship_links','label','Scholarships to link to courses','count',v_n,'oldest',v_old,'href','#scholarships?tab=links','min',4);
  exception when others then null; end;
  begin
    select count(*) into v_n from security.scholarship_publishability_v1() x join scholarship.scholarships s on s.id = x.scholarship_id
     where x.publishable and coalesce(s.publication_status, '') <> 'published';
    v_rows := v_rows || jsonb_build_object('key','scholarships_ready','label','Scholarships ready to publish','count',v_n,'oldest',null,'href','#scholarships?tab=coverage','min',5);
  exception when others then null; end;
  begin
    select count(*) into v_n from pipeline.important_links where retired_at is null and enabled and health_status = 'degraded';
    v_rows := v_rows || jsonb_build_object('key','reference','label','Reference sites not reachable','count',v_n,'oldest',null,'href','#reference-data?tab=links','min',3);
  exception when others then null; end;
  begin
    select count(*), min(coalesce(starts_on, starts_at::date))::timestamptz into v_n, v_old from pipeline.important_dates
     where status = 'active' and coalesce(starts_on, starts_at::date) between current_date and current_date + warning_window;
    v_rows := v_rows || jsonb_build_object('key','dates','label','Key dates coming up','count',v_n,'oldest',v_old,'href','#reference-data?tab=dates','min',3);
  exception when others then null; end;
  begin
    select count(*), min(created_at) into v_n, v_old from pipeline.jobs where status = 'failed' and created_at > now() - interval '24 hours';
    v_rows := v_rows || jsonb_build_object('key','failed_jobs','label','Jobs that failed in the last 24 hours','count',v_n,'oldest',v_old,'href','#scheduled-jobs?tab=jobs','min',4);
  exception when others then null; end;
  begin
    select count(distinct d.jobid), min(d.start_time) into v_n, v_old from cron.job_run_details d where d.status = 'failed' and d.start_time > now() - interval '24 hours';
    v_rows := v_rows || jsonb_build_object('key','failed_automations','label','Automations that failed in the last 24 hours','count',v_n,'oldest',v_old,'href','#scheduled-jobs','min',4);
  exception when others then null; end;
  return jsonb_build_object('rank', v_rank, 'generated_at', now(),
    'rows', (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(v_rows) r where (r->>'min')::int <= v_rank));
end $function$;

-- the journey starts with each university's current step (earlier steps are shown from its tasks and AI drafts)
insert into pipeline.provider_onboarding_events(onboarding_id, at, status, stop_reason, note, job_id, draft_id)
select o.id, coalesce(o.step_started_at, o.updated_at), o.status, o.stop_reason, o.note, o.job_id, o.draft_id from pipeline.provider_onboarding o
 where o.status <> 'queued' and not exists (select 1 from pipeline.provider_onboarding_events e where e.onboarding_id = o.id);

-- Ready to admit with nothing ready: back to qualifying (the AI proposes; no second scholarship search). An old adapter counts as no AI
-- attempt yet; an AI-built one as one.
update pipeline.provider_onboarding set status = 'qualifying', step_started_at = now(), job_id = null, attempts = 0,
       result = result || jsonb_build_object('ai_attempts', case when coalesce((result->>'existing_adapter')::boolean, false) then 0 else 1 end),
       note = 'Nothing was ready to admit; qualifying again so the AI can propose (v2.15.255).', updated_at = now()
 where status = 'waiting_admit' and jsonb_array_length(coalesce(result->'ready', '[]'::jsonb)) = 0;

do $post$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "d5cf2004d4d7eecb9f0d09fa17f405b4", "security.provider_onboarding_tick_v1()": "9ea953d2b80f465b83ba8e6cd97588bf", "public.admin_adapter_builder(text, jsonb)": "23c611e79c25ab1663f65fcea709b202", "public.admin_provider_onboarding(text, jsonb)": "9f609f60fe7b79fb39c312abbb0bb3cf", "public.admin_waiting_read()": "7e1ed8ba5e92d1a85b3993fd38201617"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.255 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
