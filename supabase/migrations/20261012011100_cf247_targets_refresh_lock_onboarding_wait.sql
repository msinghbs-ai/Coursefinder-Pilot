-- CF-247 v2.15.256 (12 Oct 2026). Platform Admin, 13:06 status review; fixes 1 and 4 agreed.
-- 1. firecrawl-targets failed 14 times in 6 hours with "deadlock detected": the job and the workers (through svc_fc_targets when the
--    cache is over 5 minutes old) ran security.firecrawl_targets_refresh_v1 at the same time, each upserting the same ~1,000 rows
--    (11,331 calls, 3.8 s each). A refresh now runs only when no other refresh is running (transaction advisory lock); the others
--    return at once and use the cache, which is at most a minute old.
-- 4. Onboarding stopped universities with "too few course pages" 90 minutes after the course-page search finished even while
--    pages it had found were still waiting to be read (74 for the 15 stopped). It now waits while searches are queued, sent or
--    found but not yet read, up to 6 hours. Universities stopped this way with pages still pending carry on (no new search).
-- Guarded on the live definitions; nothing dropped.
do $guard$
declare v_expected jsonb := '{"security.firecrawl_targets_refresh_v1()": "d306720aae01dd3c1c8f3c01d6bb1ff7", "security.provider_onboarding_step_v1(uuid)": "edfcb42974f87751341d46b2abdfb07a"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

CREATE OR REPLACE FUNCTION security.firecrawl_targets_refresh_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n int;
begin
  -- v2.15.256: one refresh at a time (two at once deadlocked on the cache)
  if not pg_try_advisory_xact_lock(hashtext('cf247:firecrawl_targets_refresh')) then return 0; end if;
  insert into pipeline.firecrawl_target_cache(provider_id, included, refreshed_at, country, name, domain, rule_match, override_reason, courses)
    select t.provider_id, t.included, now(), t.country, t.name, t.domain, t.rule_match, t.override_reason, t.courses from security.firecrawl_targets_v1() t
  on conflict (provider_id) do update set included = excluded.included, refreshed_at = now(), country = excluded.country, name = excluded.name, domain = excluded.domain, rule_match = excluded.rule_match, override_reason = excluded.override_reason, courses = excluded.courses where pipeline.firecrawl_target_cache.provider_id = excluded.provider_id;
  get diagnostics n = row_count;
  update pipeline.firecrawl_target_cache set included = false, refreshed_at = now() where refreshed_at < now() - interval '30 seconds' and included;
  return n;
end $function$;

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
      -- v2.15.255: nothing ready after the AI attempts is "Needs a person" (stopped, nothing_ready), not Ready to admit
      update pipeline.provider_onboarding set status = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'waiting_admit' else 'stopped' end,
             stop_reason = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then null else 'nothing_ready' end,
             job_id = null, result = result || jsonb_build_object('scholarships', j.result),
             note = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'Ready to admit: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(o.result->'ready') x) || '. A Platform Admin admits on Layer 2 › Adapters.'
                         else format('Nothing passed after %s AI attempt(s); the Fields column shows why for each field.', coalesce((o.result->>'ai_attempts')::int, 0)) end,
             updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'waiting_admit' then
    if exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled and coalesce(a.admit, false)) then
      update pipeline.provider_onboarding set status = 'done', finished_at = now(), note = 'Admitted; onboarding complete.', updated_at = now() where id = o.id;
    end if;
  end if;
end $function$;

-- universities stopped as "too few course pages" while their found pages still wait to be read carry on, without a new search
update pipeline.provider_onboarding o set status = 'course_pages', stop_reason = null, step_started_at = now(), attempts = 0,
       job_id = (select j.id from pipeline.admin_jobs j where j.scope = o.provider_id::text and j.kind = 'course_page_find' order by j.created_at desc limit 1),
       note = 'Found course pages are still waiting to be read; carrying on (v2.15.256).', updated_at = now()
 where o.status = 'stopped' and o.stop_reason = 'too_few_pages'
   and exists (select 1 from pipeline.course_link_search s where s.provider_id = o.provider_id and s.state in ('queued', 'sent', 'found'));

do $post$
declare v_expected jsonb := '{"security.firecrawl_targets_refresh_v1()": "2d3661f1f5e90354e522a0885b9ca9bb", "security.provider_onboarding_step_v1(uuid)": "f97a0eed5b91bd10359e039b480a1492"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.256 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
