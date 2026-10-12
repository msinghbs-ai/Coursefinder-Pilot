-- CF-247 v2.15.258 (Platform Admin, 12 Oct 2026, bug 12/10-01): the onboarding journey in seven stages.
--   1 Provider in      a university is in the platform (Layer 1 register, another database, or our search) and queued
--   2 Prepare          website, contacts, central pages, course pages found and read
--   3 Create adapter   the pinned AI proposes the settings; they are applied to the stored pages and qualified
--   4 Admit            a Platform Admin admits the fields that pass (or approves central pages when nothing passes)
--   5 Enrich courses   the admitted adapter writes its values to the courses (plus approved central pages)
--   6 Scholarship adapter  the scholarship search (map, screen, read) starts only now
--   7 Admit scholarships   the AI reads and checks the pages; held pages are decided by a person; then Done
-- Before this change scholarships were searched before Admit. Statuses are unchanged (no constraint is dropped): stages 5 to 7
-- run under status 'scholarships' with result->>'phase' = enrich, scholarship_search or scholarship_admit. Rows already in
-- 'scholarships' without a phase finish as before. Applied through the db-apply-migration workflow; nothing is dropped.
-- Requires 20261012011400 (the admin_provider_onboarding guard expects its post-11400 definition).

do $guard$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "120ef69e34a2308c1684f46773261c44", "security.provider_onboarding_tick_v1()": "ddcaa4f4bedef103c9e07613ee70a080", "security.provider_onboarding_event_v1()": "bd95675d2dc3a01bc543cef9b6f8347f", "public.admin_provider_onboarding(text, jsonb)": "19e2f3bb5d42ebaeb48a4a0126c4f1d7"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- the stage a row is in (shown on Layer 2 › Onboarding)
create or replace function security.provider_onboarding_stage_v1(p_status text, p_stop_reason text, p_result jsonb)
 returns text language sql immutable set search_path to '' as $$
  select case
    when p_status = 'queued' then 'provider_in'
    when p_status in ('website', 'course_pages', 'waiting_courses') then 'prepare'
    when p_status in ('capturing', 'proposing', 'applying', 'qualifying') then 'create_adapter'
    when p_status = 'waiting_admit' then 'admit'
    when p_status = 'stopped' and p_stop_reason in ('no_website', 'too_few_pages', 'recipe_off') then 'prepare'
    when p_status = 'stopped' and p_stop_reason in ('nothing_ready', 'approve_central') then 'admit'
    when p_status = 'stopped' and p_stop_reason = 'error' and coalesce(p_result, '{}'::jsonb) ? 'phase' then
      case p_result->>'phase' when 'enrich' then 'enrich' when 'scholarship_search' then 'scholarship_adapter' else 'admit_scholarships' end
    when p_status = 'stopped' and p_stop_reason = 'error' and coalesce(p_result, '{}'::jsonb) ? 'qualify' then 'admit'
    when p_status = 'stopped' and p_stop_reason = 'error' and coalesce(p_result, '{}'::jsonb) ? 'pages_read' then 'create_adapter'
    when p_status = 'stopped' and p_stop_reason = 'error' then 'prepare'
    when p_status = 'stopped' then 'create_adapter'
    when p_status = 'scholarships' and p_result->>'phase' = 'enrich' then 'enrich'
    when p_status = 'scholarships' and p_result->>'phase' = 'scholarship_admit' then 'admit_scholarships'
    when p_status = 'scholarships' then 'scholarship_adapter'
    when p_status = 'done' then 'done'
    else p_status end
$$;
revoke all on function security.provider_onboarding_stage_v1(text, text, jsonb) from public;

CREATE OR REPLACE FUNCTION security.provider_onboarding_step_v1(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o pipeline.provider_onboarding%rowtype; p catalogue.providers%rowtype; j pipeline.admin_jobs%rowtype; d pipeline.uni_adapter_drafts%rowtype;
        v_courses int; v_read int; v_need int; v_r jsonb; v_prop jsonb; v_adapter jsonb; v_q jsonb; v_rd jsonb; v_b jsonb; v_s record; v_central jsonb := '[]'::jsonb;
        v_age interval; v_central_n int := 0; v_en jsonb; v_aiq int; v_rev int; v_found int; v_pub int;
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
    -- v2.15.258 journey: qualifying ends at Admit (stage 4); scholarships are searched only after the courses are enriched (stage 6)
    if jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) = 0 then v_central_n := security.central_ai_enqueue_v1(o.provider_id); end if;
    update pipeline.provider_onboarding set status = case when jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) > 0 then 'waiting_admit' else 'stopped' end,
           stop_reason = case when jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) > 0 then null else 'nothing_ready' end,
           step_started_at = now(), job_id = null,
           result = result || jsonb_build_object('qualify', v_q, 'ready', v_rd->'ready', 'held', v_rd->'held', 'central_pages', v_central),
           note = case when jsonb_array_length(coalesce(v_rd->'ready', '[]'::jsonb)) > 0
                       then 'Ready to admit: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_rd->'ready') x) || '. A Platform Admin admits on Layer 2 › Adapters; its courses are then enriched and its scholarships found.'
                       else format('Nothing passed after %s AI attempt(s); the Fields column shows why for each field.%s', coalesce((o.result->>'ai_attempts')::int, 0),
                                   case when v_central_n > 0 then ' The AI is reading its central pages (English policy, calendar) for a person to approve.' else '' end) end,
           updated_at = now() where id = o.id;

  elsif o.status = 'scholarships' and o.result->>'phase' = 'enrich' then
    -- v2.15.258 stage 5: the admitted adapter writes its values to the courses. First apply it to the stored pages once; when no value
    -- has changed for 10 minutes (and at least 20 minutes have passed), record what was written and move on to the scholarships
    if not (o.result ? 'enrich_from') then
      if exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled) then
        perform public.admin_uni_adapter_write('apply', jsonb_build_object('provider_id', o.provider_id, 'reason', 'Onboarding: admitted; write the admitted values to its courses'));
      end if;
      update pipeline.provider_onboarding set step_started_at = now(), result = result || jsonb_build_object('enrich_from', now()),
             note = 'Admitted; writing the admitted values to its courses.', updated_at = now() where id = o.id;
    elsif v_age > interval '20 minutes' and not exists (select 1 from pipeline.adapter_overwrite_changes c where c.provider_id = o.provider_id and c.at > now() - interval '10 minutes') then
      v_en := (select coalesce(jsonb_object_agg(t.field, t.n), '{}'::jsonb) from (select c.field, count(distinct c.course_id) n from pipeline.adapter_overwrite_changes c
                where c.provider_id = o.provider_id and c.at >= (o.result->>'enrich_from')::timestamptz group by 1) t);
      if o.result ? 'scholarships' then
        update pipeline.provider_onboarding set step_started_at = now(), job_id = null, result = result || jsonb_build_object('enriched', v_en, 'phase', 'scholarship_admit'),
               note = format('Courses enriched (%s). Its scholarships were found earlier; checking they are admitted.',
                             coalesce((select string_agg(e.key || ' on ' || e.value || ' courses', ', ' order by e.key) from jsonb_each_text(v_en) e), 'no value changed')),
               updated_at = now() where id = o.id;
      else
        update pipeline.provider_onboarding set step_started_at = now(), result = result || jsonb_build_object('enriched', v_en, 'phase', 'scholarship_search'),
               job_id = security.provider_onboarding_job_v1('scholarship_provider_scan', o.provider_id, jsonb_build_object('provider_ids', jsonb_build_array(o.provider_id), 'scope', o.provider_id)),
               note = format('Courses enriched (%s); finding scholarships (map, screen, read).',
                             coalesce((select string_agg(e.key || ' on ' || e.value || ' courses', ', ' order by e.key) from jsonb_each_text(v_en) e), 'no value changed')),
               updated_at = now() where id = o.id;
      end if;
    else
      update pipeline.provider_onboarding set note = format('Enriching its courses: %s values written since it was admitted.',
               (select count(*) from pipeline.adapter_overwrite_changes c where c.provider_id = o.provider_id and c.at >= (o.result->>'enrich_from')::timestamptz)),
             updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'scholarships' and o.result->>'phase' = 'scholarship_search' then
    -- v2.15.258 stage 6: the scholarship search for this university
    if j.id is null then
      update pipeline.provider_onboarding set job_id = security.provider_onboarding_job_v1('scholarship_provider_scan', o.provider_id, jsonb_build_object('provider_ids', jsonb_build_array(o.provider_id), 'scope', o.provider_id)),
             step_started_at = now(), note = 'Finding scholarships (map, screen, read).', updated_at = now() where id = o.id;
    elsif j.state in ('done', 'failed', 'cancelled') then
      update pipeline.provider_onboarding set job_id = null, step_started_at = now(), result = result || jsonb_build_object('scholarships', j.result, 'phase', 'scholarship_admit'),
             note = 'Scholarship search finished; the AI reads the pages and checks them before publishing.', updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'scholarships' and o.result->>'phase' = 'scholarship_admit' then
    -- v2.15.258 stage 7: done when no page waits for the AI or for a person (held pages), or after 7 days
    select count(*) into v_aiq from pipeline.scholarship_ai_queue q where q.provider_id = o.provider_id and q.state <> 'done';
    select count(*) into v_rev from pipeline.scholarship_ai_reviews r where r.provider_id = o.provider_id and r.status = 'pending';
    select count(*), count(*) filter (where s.publication_status = 'published') into v_found, v_pub
      from scholarship.scholarships s where s.provider_id = o.provider_id and s.created_at >= coalesce(o.started_at, o.created_at) - interval '1 minute';
    if (v_age > interval '15 minutes' and v_aiq = 0 and v_rev = 0) or v_age > interval '7 days' then
      update pipeline.provider_onboarding set status = 'done', finished_at = now(), job_id = null,
             result = result || jsonb_build_object('scholarship_admit', jsonb_build_object('found', v_found, 'published', v_pub, 'waiting_ai', v_aiq, 'waiting_person', v_rev)),
             note = format('Onboarding complete: %s scholarships found, %s published.%s', v_found, v_pub,
                           case when v_aiq + v_rev > 0 then format(' %s pages still wait for the AI or a person (Scholarships › Extraction).', v_aiq + v_rev) else '' end),
             updated_at = now() where id = o.id;
    else
      update pipeline.provider_onboarding set note = format('Admitting scholarships: %s found, %s published; %s pages waiting for the AI, %s held for a person (Scholarships › Extraction).', v_found, v_pub, v_aiq, v_rev),
             updated_at = now() where id = o.id;
    end if;

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
      -- v2.15.258: admitted is stage 4 of 7; its courses are enriched next (stage 5), then its scholarships
      update pipeline.provider_onboarding set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
             result = (result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Admitted; its courses are enriched next.', updated_at = now() where id = o.id;
    else
      -- still waiting for a person: checked again in 10 minutes
      update pipeline.provider_onboarding set updated_at = now() where id = o.id;
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
  -- v2.15.258: then its courses are enriched (stage 5) and its scholarships found, instead of finishing here
  update pipeline.provider_onboarding ob set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
         result = (ob.result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Admitted by a person; its courses are enriched next.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason in ('nothing_ready', 'approve_central')
     and exists (select 1 from pipeline.uni_adapters a where a.provider_id = ob.provider_id and a.enabled and coalesce(a.admit, false));
  -- v2.15.256: central pages read by the AI and decided by a person (at least one approved): done
  update pipeline.provider_onboarding ob set status = 'scholarships', stop_reason = null, step_started_at = now(), job_id = null,
         result = (ob.result - 'enrich_from') || jsonb_build_object('phase', 'enrich', 'admitted_at', now()), note = 'Central pages approved by a person; its courses are enriched next.', updated_at = now()
   where ob.status = 'stopped' and ob.stop_reason = 'approve_central'
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'proposed')
     and exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = ob.provider_id and pp.status = 'approved' and pp.decided_at >= coalesce(ob.started_at, ob.created_at));
  -- v2.15.258: only the working stages count towards "at once"; Admit, Enrich and Admit scholarships wait
  select count(*) into v_active from pipeline.provider_onboarding
   where status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
      or (status = 'scholarships' and coalesce(result->>'phase', 'scholarship_search') = 'scholarship_search');
  for o in select id from pipeline.provider_onboarding where status = 'queued' order by priority desc, created_at limit greatest(coalesce(s.max_active, 0) - v_active, 0) loop
    update pipeline.provider_onboarding set status = 'website', started_at = now(), step_started_at = now(), note = 'Starting.', updated_at = now() where id = o.id;
    v_started := v_started + 1;
  end loop;
  for o in select ob.id, coalesce(ob.requested_by, s.run_as) run_as from pipeline.provider_onboarding ob
            where ob.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
               or (ob.status = 'scholarships' and coalesce(ob.result->>'phase', 'scholarship_search') = 'scholarship_search')
               -- v2.15.258: the waiting stages (Admit, Enrich, Admit scholarships) are checked every 10 minutes, after the working ones
               or ((ob.status = 'waiting_admit' or (ob.status = 'scholarships' and ob.result->>'phase' in ('enrich', 'scholarship_admit'))) and ob.updated_at < now() - interval '10 minutes')
               or (ob.status = 'waiting_courses' and ob.updated_at < now() - interval '1 hour')
            order by case when ob.status = 'waiting_admit' or ob.status = 'waiting_courses' or ob.result->>'phase' in ('enrich', 'scholarship_admit') then 1 else 0 end, ob.updated_at
            limit 250 loop
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

CREATE OR REPLACE FUNCTION security.provider_onboarding_event_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status or old.stop_reason is distinct from new.stop_reason
     or old.job_id is distinct from new.job_id or old.draft_id is distinct from new.draft_id
     or old.result->>'phase' is distinct from new.result->>'phase' then
    -- v2.15.258: stages 5 to 7 run under status 'scholarships'; the event records the phase (enrich, scholarship_search, scholarship_admit)
    insert into pipeline.provider_onboarding_events(onboarding_id, status, stop_reason, note, job_id, draft_id)
    values (new.id, case when new.status = 'scholarships' and new.result ? 'phase' then new.result->>'phase' else new.status end,
            new.stop_reason, new.note, new.job_id, new.draft_id);
  end if;
  return new;
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
    return (select jsonb_build_object('id', o.id, 'status', o.status, 'stop_reason', o.stop_reason, 'started_at', o.started_at,
      'stage', security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result), 'phase', o.result->>'phase', 'source', o.source,
      'admitted_at', o.result->'admitted_at', 'enriched', o.result->'enriched', 'scholarship_admit', o.result->'scholarship_admit', 'finished_at', o.finished_at, 'ai_attempts', coalesce((o.result->>'ai_attempts')::int, 0),
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
    -- v2.15.258: rows by journey stage (1 Provider in ... 7 Admit scholarships, then Done)
    'stages', (select coalesce(jsonb_object_agg(t.stage, t.n), '{}'::jsonb) from (select security.provider_onboarding_stage_v1(status, stop_reason, result) stage, count(*) n
                 from pipeline.provider_onboarding group by 1) t),
    'stops', (select coalesce(jsonb_object_agg(t.r, t.n), '{}'::jsonb) from (select stop_reason r, count(*) n from pipeline.provider_onboarding where status = 'stopped' group by 1) t),
    'without_adapter', (select count(*) from catalogue.providers pr where pr.lifecycle_status = 'active'
                          and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                          and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false))),
    -- v2.15.258: universities without an admitting adapter that are not in onboarding yet (what "Onboard all" would add), and the pace
    'not_queued', (select count(*) from catalogue.providers pr where pr.lifecycle_status = 'active'
                     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
                     and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
                     and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false))
                     and not exists (select 1 from pipeline.provider_onboarding o where o.provider_id = pr.id and o.status not in ('done', 'cancelled'))),
    'pace', (select jsonb_build_object('finished_last_hour', count(distinct e.onboarding_id) filter (where e.at > now() - interval '1 hour'),
                                       'finished_last_6_hours', count(distinct e.onboarding_id))
               from pipeline.provider_onboarding_events e where e.at > now() - interval '6 hours' and e.status in ('waiting_admit', 'stopped', 'done')),
    'approvals_waiting', (select count(*) from pipeline.provider_fact_sources fs where fs.decision is null and fs.status = 'parsed' and fs.kind = 'fee_schedule')
                         + (select count(*) from pipeline.provider_policy_proposals pp where pp.status = 'proposed'),
    'rows', (select coalesce(jsonb_agg(x order by x->>'sort'), '[]'::jsonb) from (
       select jsonb_build_object('sort', lpad((case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end)::text, 2, '0') || to_char(o.updated_at, 'YYYYMMDDHH24MISS'),
              'id', o.id, 'provider_id', o.provider_id, 'name', coalesce(nullif(pr.display_name, ''), pr.canonical_name), 'country', (select k.iso_alpha2 from ref.countries k where k.id = pr.country_id),
              'website', pr.website, 'status', o.status, 'stop_reason', o.stop_reason,
              'stage', security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result), 'phase', o.result->>'phase', 'enriched', o.result->'enriched',
              'in_register', pr.canonical_source_id is not null, 'note', o.note, 'source', o.source, 'job_id', o.job_id,
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
          and (p_args->>'stage' is null or security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) = p_args->>'stage')
          and (p_args->>'q' is null or coalesce(pr.display_name, pr.canonical_name) ilike '%' || (p_args->>'q') || '%')
        order by case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end, o.updated_at desc
        limit least(greatest(coalesce((p_args->>'limit')::int, 200), 1), 500)) t));
end $function$;

do $post$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "2b150881c41af0855216024b83bef4cf", "security.provider_onboarding_tick_v1()": "03edc0d82409c7fbd66b4353a63b0fe8", "security.provider_onboarding_event_v1()": "a3e685cd09066c9c828699d45e01952c", "public.admin_provider_onboarding(text, jsonb)": "a0d8837318978aa53fdb23c51a08dad4"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.258 journey post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
