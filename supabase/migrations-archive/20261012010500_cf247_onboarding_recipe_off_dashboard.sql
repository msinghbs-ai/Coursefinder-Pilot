-- CF-247 v2.15.254 (12 Oct 2026). Two follow-ups to automatic onboarding (v2.15.253).
-- 1. A course-page search recipe that was switched off because it was built from another domain (Humber College: built from
--    guelphhumber.ca) blocked onboarding with a misleading "no website" error. When the switched-off recipe searches a different
--    domain from the website now recorded, it no longer describes this university's site, so it is replaced by the generic recipe
--    for the recorded website. A switched-off recipe for the same domain is left alone and onboarding stops with a plain reason
--    (recipe_off) for a person to decide.
-- 2. Dashboard "Waiting for you": Flagged values and Fee rules were retired in v2.15.253, so their rows go; Scholarships ready to
--    publish links to Scholarships > Coverage; two onboarding rows are added (universities ready to admit, onboarding stopped).
-- Guarded: the live definitions must match the snapshots this change was written from. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "d8e866d233c91758087a8ca65365eaea", "public.admin_waiting_read()": "586b7e0a36395d2d10216bf4d3433a86"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

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
             result = result || jsonb_build_object('pages_read', v_read, 'courses', v_courses), note = format('%s course pages read; capturing sample pages.', v_read), updated_at = now() where id = o.id;
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
                   'comments', 'Propose settings that read international intakes (months), IELTS overall, the international annual fee and delivery from these course pages.', 'reason', 'Onboarding: propose the adapter'));
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
    elsif (d.status = 'error' or (d.status = 'proposed' and v_prop->>'kind' = 'error')) and o.attempts < 2 then
      -- a failed answer (for example no answer from the model) is asked again, twice at most
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
    if j.id is null then
      update pipeline.provider_onboarding set job_id = security.provider_onboarding_job_v1('scholarship_provider_scan', o.provider_id, jsonb_build_object('provider_ids', jsonb_build_array(o.provider_id), 'scope', o.provider_id)),
             step_started_at = now(), note = 'Finding scholarships (map, screen, read).', updated_at = now() where id = o.id;
    elsif j.state in ('done', 'failed', 'cancelled') then
      update pipeline.provider_onboarding set status = 'waiting_admit', job_id = null, result = result || jsonb_build_object('scholarships', j.result),
             note = case when jsonb_array_length(coalesce(o.result->'ready', '[]'::jsonb)) > 0 then 'Ready to admit: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(o.result->'ready') x) || '. A Platform Admin admits on Layer 2 › Adapters.'
                         else 'Built and testing; no field is ready to admit yet (see why). Approve its central pages in the Adapter builder (1.3) so values can be checked.' end,
             updated_at = now() where id = o.id;
    end if;

  elsif o.status = 'waiting_admit' then
    if exists (select 1 from pipeline.uni_adapters a where a.provider_id = o.provider_id and a.enabled and coalesce(a.admit, false)) then
      update pipeline.provider_onboarding set status = 'done', finished_at = now(), note = 'Admitted; onboarding complete.', updated_at = now() where id = o.id;
    end if;
  end if;
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
    v_rows := v_rows || jsonb_build_object('key','onboarding_stopped','label','Onboarding stopped for a person','count',v_n,'oldest',v_old,'href','#providers?tab=onboarding','min',3);
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

-- Humber College (the one university stopped this way) carries on at the next tick.
update pipeline.provider_onboarding set status = 'website', stop_reason = null, attempts = 0, job_id = null, step_started_at = now(), note = 'Retried after the v2.15.254 recipe fix.', updated_at = now()
 where status = 'stopped' and stop_reason = 'error' and note like 'Stopped: no website is recorded for this provider yet%';

do $post$
declare v_expected jsonb := '{"security.provider_onboarding_step_v1(uuid)": "33530dae0626d1ad5ec434ef0e0953e9", "public.admin_waiting_read()": "8eae4aa1f362db6398c5bfb88eec1794"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'v2.15.254 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
