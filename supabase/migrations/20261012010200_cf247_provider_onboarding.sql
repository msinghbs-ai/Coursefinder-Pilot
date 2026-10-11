-- CF-247 v2.15.253 (Platform Admin, 12 Oct 2026 09:35): "Build adapters for universities without an adapter. Once the provider is in, the
-- workflow should onboard it, which would create the adapter automatically and then run the scholarship adapter." Decisions: onboarding
-- stops for a person at Ready to admit (a passing check never switches anything on by itself); onboard all universities without an
-- adapter as soon as possible; central pages are attached and approved inside onboarding and the Adapter builder (Layer 4 › Attributes
-- retired); the 33 open flagged fees from the retired Layer 3 are closed and fee-rule results kept.
-- One onboarding per university runs the existing Adapter builder steps in order, as the Platform Admin who started it (or the run-as
-- setting for automatic starts): website (provider_fill task), course pages (course_page_find task, the university made a Firecrawl
-- target), capture 6 sample pages, the pinned model proposes the settings, save in testing and apply, qualify (strict ready rule), attach
-- central pages, find scholarships (scholarship_provider_scan task), then wait for a person to admit. A step that cannot continue stops
-- with a plain reason; a stop for a missing website resumes by itself once a website is entered.
-- Nothing is dropped or deleted.

create table if not exists pipeline.provider_onboarding_settings (
  id int primary key default 1 check (id = 1), enabled boolean not null default true, auto_start_new boolean not null default true,
  max_active int not null default 30 check (max_active between 0 and 200), run_as uuid, changed_by uuid, changed_at timestamptz, reason text);
alter table pipeline.provider_onboarding_settings enable row level security;
insert into pipeline.provider_onboarding_settings(id, run_as, reason) values (1, '63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'Platform Admin, 12 Oct 2026: onboard as soon as possible')
on conflict (id) do nothing;

create table if not exists pipeline.provider_onboarding (
  id uuid primary key default gen_random_uuid(), provider_id uuid not null references catalogue.providers(id) on delete cascade,
  status text not null default 'queued' check (status in ('queued', 'website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying',
                                                          'scholarships', 'waiting_admit', 'waiting_courses', 'stopped', 'done', 'cancelled')),
  step_started_at timestamptz, started_at timestamptz, job_id uuid, draft_id uuid, attempts int not null default 0,
  stop_reason text, note text, result jsonb not null default '{}'::jsonb, priority int not null default 0,
  requested_by uuid, reason text, source text not null default 'manual' check (source in ('manual', 'new_provider', 'backfill')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), finished_at timestamptz);
create unique index if not exists provider_onboarding_one_open on pipeline.provider_onboarding (provider_id) where status not in ('done', 'cancelled');
create index if not exists provider_onboarding_status_idx on pipeline.provider_onboarding (status, priority desc, created_at);
alter table pipeline.provider_onboarding enable row level security;

-- the AI allowance for proposals: onboarding hundreds of universities needs more than the hand-built daily 60
update pipeline.platform_toolset_settings set value = to_jsonb(400) where toolset_key = 'firecrawl' and key = 'builder_proposals_per_day' and (value #>> '{}')::numeric < 400;
update pipeline.platform_toolset_settings set value = to_jsonb(5) where toolset_key = 'firecrawl' and key = 'builder_ai_daily_usd' and (value #>> '{}')::numeric < 5;

-- Start an admin task as the impersonated user, or return the one already open for that kind and university
create or replace function security.provider_onboarding_job_v1(p_kind text, p_provider uuid, p_args jsonb)
returns uuid language plpgsql security definer set search_path to '' as $f$
declare v_id uuid;
begin
  select j.id into v_id from pipeline.admin_jobs j
   where j.kind = p_kind and j.state in ('queued', 'running', 'paused')
     and (j.scope = p_provider::text or j.args->>'provider_id' = p_provider::text or j.args->'provider_ids' ? p_provider::text)
   order by j.created_at desc limit 1;
  if v_id is not null then return v_id; end if;
  perform public.admin_jobs('start', jsonb_build_object('kind', p_kind, 'args', p_args, 'from', 'Onboarding'));
  select j.id into v_id from pipeline.admin_jobs j where j.kind = p_kind and j.requested_by = auth.uid() order by j.created_at desc limit 1;
  return v_id;
end $f$;
revoke all on function security.provider_onboarding_job_v1(text, uuid, jsonb) from public, anon, authenticated;

-- Fields ready to admit (the Adapter builder's strict rule): passes the admit rule, read on 5+ pages, agrees with held values on 90%+ of 3+ courses
create or replace function security.provider_onboarding_ready_v1(p_q jsonb)
returns jsonb language sql immutable set search_path to '' as $f$
  select jsonb_build_object(
    'ready', coalesce(jsonb_agg(f.k) filter (where f.why is null), '[]'::jsonb),
    'held', coalesce(jsonb_object_agg(f.k, f.why) filter (where f.why is not null), '{}'::jsonb))
  from (select k, case
          when not coalesce((x->>'pass')::boolean, false) then coalesce(x->>'why', 'does not pass')
          when coalesce((x->>'read')::int, 0) < 5 then 'read on fewer than 5 pages'
          when coalesce((x->>'agree')::int, 0) < 3 or x->>'agree_share' is null then 'not enough held values to check against (needs 3 agreeing courses)'
          when (x->>'agree_share')::numeric < 0.9 then 'agrees on under 90% of checked courses' end why
        from jsonb_each(coalesce(p_q->'fields', '{}'::jsonb)) e(k, x) where k in ('intakes', 'english', 'fee', 'delivery')) f
$f$;

-- One step for one onboarding (called by the tick under the impersonated user)
create or replace function security.provider_onboarding_step_v1(p_id uuid)
returns void language plpgsql security definer set search_path to '' as $f$
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
      insert into pipeline.firecrawl_targets(provider_id, included, reason, set_by, set_at) values (o.provider_id, true, 'Onboarding: find and read its course pages', auth.uid(), now())
      on conflict (provider_id) do update set included = true, reason = excluded.reason, set_by = excluded.set_by, set_at = now();
      update pipeline.provider_onboarding set status = 'course_pages', job_id = security.provider_onboarding_job_v1('course_page_find', o.provider_id, jsonb_build_object('provider_id', o.provider_id, 'scope', o.provider_id)),
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
          update pipeline.provider_onboarding set status = 'proposing', step_started_at = now(), note = format('The pinned model (%s) is proposing the settings.', d.model), updated_at = now() where id = o.id;
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
      if v_prop->>'kind' = 'error' or v_prop->'adapter' is null then
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
    elsif d.status = 'error' or v_age > interval '30 minutes' then
      update pipeline.provider_onboarding set status = 'stopped', stop_reason = 'proposal_failed', note = 'The proposal did not finish.', updated_at = now() where id = o.id;
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
end $f$;
revoke all on function security.provider_onboarding_step_v1(uuid) from public, anon, authenticated;

-- Every minute: resume stops that can carry on, start queued onboardings up to the limit, advance the active ones
create or replace function security.provider_onboarding_tick_v1()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare s pipeline.provider_onboarding_settings%rowtype; o record; v_active int; v_n int := 0; v_err int := 0; v_started int := 0;
begin
  select * into s from pipeline.provider_onboarding_settings where id = 1;
  if not coalesce(s.enabled, false) then return jsonb_build_object('skipped', 'onboarding is switched off'); end if;
  -- a missing website was entered: carry on
  update pipeline.provider_onboarding o set status = 'website', stop_reason = null, step_started_at = now(), job_id = null, note = 'Website entered; carrying on.', updated_at = now()
    from catalogue.providers p where p.id = o.provider_id and o.status = 'stopped' and o.stop_reason = 'no_website' and nullif(p.website, '') is not null;
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
end $f$;
revoke all on function security.provider_onboarding_tick_v1() from public, anon, authenticated;

-- A university added (from a register or by hand) is onboarded automatically
create or replace function security.provider_onboarding_new_tg()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if new.lifecycle_status = 'active' and coalesce((select s.auto_start_new from pipeline.provider_onboarding_settings s where s.id = 1), false) then
    insert into pipeline.provider_onboarding(provider_id, source, reason, priority) values (new.id, 'new_provider', 'Added to the catalogue', 100)
    on conflict do nothing;
  end if;
  return new;
end $f$;
create or replace trigger providers_onboarding_new after insert on catalogue.providers for each row execute function security.provider_onboarding_new_tg();

-- Read and control (Providers › Onboarding)
create or replace function public.admin_provider_onboarding(p_action text default 'read', p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_ids uuid[]; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
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
              'ready', o.result->'ready', 'held', o.result->'held', 'central_pages', o.result->'central_pages', 'scholarships', o.result->'scholarships'->'new_scholarships',
              'courses', (select count(*) from catalogue.courses c where c.provider_id = o.provider_id and c.lifecycle_status = 'active'),
              'pages_read', (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = o.provider_id and pg.read_status = 'read'),
              'started_at', o.started_at, 'step_started_at', o.step_started_at, 'updated_at', o.updated_at, 'finished_at', o.finished_at, 'created_at', o.created_at) x
         from pipeline.provider_onboarding o join catalogue.providers pr on pr.id = o.provider_id
        where (p_args->>'status' is null or o.status = p_args->>'status' or (p_args->>'status' = 'active' and o.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships')))
          and (p_args->>'q' is null or coalesce(pr.display_name, pr.canonical_name) ilike '%' || (p_args->>'q') || '%')
        order by case o.status when 'stopped' then 1 when 'waiting_admit' then 2 else 3 end, o.updated_at desc
        limit least(greatest(coalesce((p_args->>'limit')::int, 200), 1), 500)) t));
end $f$;
revoke all on function public.admin_provider_onboarding(text, jsonb) from public, anon;
grant execute on function public.admin_provider_onboarding(text, jsonb) to authenticated;

-- Credit and limit warnings for the banner on every page (Firecrawl, OpenRouter, the adapter AI allowance, scholarship and course-link caps)
create or replace function public.admin_credit_notices()
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v jsonb := '[]'::jsonb; fc record; orr record; b jsonb; v_sch jsonb; v_cap numeric; v_used numeric;
begin
  if auth.uid() is null or security.current_role_rank() < 3 then return '[]'::jsonb; end if;
  select remaining_units, plan_units, observed_at, period_end into fc from pipeline.vendor_credit_observations order by observed_at desc limit 1;
  if fc.remaining_units is not null then
    if fc.remaining_units <= 0 then v := v || jsonb_build_object('level', 'critical', 'tool', 'Firecrawl', 'text', 'Firecrawl credits have run out; page reads and searches wait until the plan renews or is topped up.');
    elsif fc.remaining_units < greatest(coalesce((security.firecrawl_setting('low_balance_warn_units') #>> '{}')::numeric, 10000), 1) then
      v := v || jsonb_build_object('level', 'warning', 'tool', 'Firecrawl', 'text', format('Firecrawl credits are low: %s left (renews %s).', fc.remaining_units, to_char(fc.period_end at time zone 'Australia/Melbourne', 'DD Mon')));
    end if;
  end if;
  select remaining_usd, observed_at into orr from pipeline.layer3_openrouter_observations where kind = 'credits' order by observed_at desc limit 1;
  if orr.remaining_usd is not null then
    if orr.remaining_usd <= 0 then v := v || jsonb_build_object('level', 'critical', 'tool', 'OpenRouter', 'text', 'OpenRouter credit has run out: every AI call (scholarship reading, adapter proposals) fails until the key''s limit is raised.');
    elsif orr.remaining_usd < 10 then v := v || jsonb_build_object('level', 'warning', 'tool', 'OpenRouter', 'text', format('OpenRouter credit is low: US$%s left on the key.', round(orr.remaining_usd, 2)));
    end if;
  end if;
  b := security.adapter_builder_budget();
  if (b->>'used_usd')::numeric >= (b->>'limit_usd')::numeric or (b->>'proposals')::int >= (b->>'limit_proposals')::int then
    v := v || jsonb_build_object('level', 'warning', 'tool', 'Adapter AI allowance', 'text', format('Today''s adapter AI allowance is used (%s of %s proposals, US$%s of US$%s); onboarding waits until midnight, Melbourne time.', b->>'proposals', b->>'limit_proposals', round((b->>'used_usd')::numeric, 2), b->>'limit_usd'));
  end if;
  select s.value into v_cap from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap';
  select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape');
  if v_cap is not null and v_used >= v_cap * 0.9 then
    v := v || jsonb_build_object('level', case when v_used >= v_cap then 'critical' else 'warning' end, 'tool', 'Scholarship credits',
                                 'text', format('Scholarship scraper credits: %s of the %s cap used%s.', v_used, v_cap, case when v_used >= v_cap then '; scholarship pages wait. Raise the cap on Scholarships › Coverage › Settings' else '' end));
  end if;
  return v;
end $f$;
revoke all on function public.admin_credit_notices() from public, anon;
grant execute on function public.admin_credit_notices() to authenticated;

-- Standing rule G1: the scheduled job is catalogued (it shows in Scheduled jobs and Task manager)
select cron.schedule('provider-onboarding', '* * * * *', 'select security.provider_onboarding_tick_v1()') where not exists (select 1 from cron.job where jobname = 'provider-onboarding');
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank)
values ('provider-onboarding', 'Course pages', 5, 'Onboard universities', 'Runs each university''s onboarding a step at a time: website, course pages, sample pages, the model''s proposal, save and apply, qualify, central pages, scholarships; stops at Ready to admit for a person.', 6)
on conflict (jobname) do nothing;

-- The open flagged fees from the retired Layer 3 are closed; the fees stay as they are and the adapter reads them again
update pipeline.data_flags set status = 'confirmed', resolved_at = now(),
       resolution = jsonb_build_object('action', 'closed', 'note', 'Layer 3 retired (12 Oct 2026); the fee is kept and the university adapter reads it again'),
       change_control_ref = coalesce(change_control_ref || '; ', '') || 'CF-247 v2.15.253: closed, Layer 3 retired'
 where status = 'open';

-- Onboard every university without an admitting adapter, largest first (Platform Admin, 12 Oct 2026: as soon as possible)
insert into pipeline.provider_onboarding(provider_id, source, requested_by, reason, priority)
select pr.id, 'backfill', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', 'Platform Admin, 12 Oct 2026: build adapters for universities without one',
       (select count(*)::int from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
  from catalogue.providers pr
 where pr.lifecycle_status = 'active' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
   and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
   and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = pr.id and a.enabled and coalesce(a.admit, false))
on conflict do nothing;
