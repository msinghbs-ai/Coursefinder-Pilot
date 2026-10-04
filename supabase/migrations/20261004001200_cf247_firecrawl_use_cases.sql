-- CF-247 (4 Oct 2026, 16:30 AEDT). Decision 253: Firecrawl only, by use case, for target universities.
-- Platform Admin, 15:51: "I have invested heavily in growth plan of firecrawl and if we are hitting any product limits we
-- should reach out to their support. Use firecrawl and maintain result report that I can share with support team ...
-- Dont waste credit on australia small unis, rather target uni with international students only. FC has all features
-- from search, scrape, crawl in built. Use it but with use cases and keep setting ui based uni adapters for field mappings."
--
--   1. Target universities. A rule made of settings (countries, a name pattern, exclusions, the least number of active
--      courses per country, the international-student registers) picks the universities. The Platform Admin can add or
--      take out any provider by hand, with a reason. A setting (on) keeps every Firecrawl call of the coverage worker to
--      target universities, so credits are not spent on small providers.
--   2. Use cases. Read pages (pages that need a browser, refused a plain read or failed) and Find pages (a Firecrawl
--      search on the university's own site for courses without a confirmed page). Each run is started by the Platform
--      Admin with a reason, runs under its own credit allowance and carries on by itself each minute. Pages found go into
--      the existing identity check and the existing approved admission paths. Nothing new is admitted here.
--   3. Every Firecrawl call made by a run is logged with what was asked, what came back (HTTP status, error text, the
--      scrape id, credits used, proxy used, the page's own status) so a report can go to Firecrawl support.
--   4. The platform's Firecrawl allowance follows the balance Firecrawl itself reports (read every 15 minutes). The
--      monthly limit setting (100,000, the old plan) only applies when no recent reading exists. The limit is set to the
--      plan Firecrawl reports (500,000 credits, period 2 Oct to 2 Nov), as the Platform Admin stated at 15:51.
-- All limits are settings changed on Platform settings › Models & services › Toolsets and limits.
-- No text value in this file contains a semicolon.

create table if not exists pipeline.firecrawl_targets (
  provider_id uuid primary key,
  included boolean not null,
  reason text not null,
  set_by uuid,
  set_at timestamptz not null default now()
);
alter table pipeline.firecrawl_targets enable row level security;
revoke all on pipeline.firecrawl_targets from anon, authenticated;

create table if not exists pipeline.firecrawl_runs (
  id uuid primary key default gen_random_uuid(),
  use_case text not null check (use_case in ('read_page', 'find_page')),
  status text not null default 'running' check (status in ('running', 'done', 'stopped', 'stopped_credit_cap', 'stopped_plan_reserve')),
  settings jsonb not null default '{}'::jsonb,
  reason text not null,
  requested_by uuid,
  items int not null default 0,
  done int not null default 0,
  credits_cap numeric not null,
  credits_used numeric not null default 0,
  outcomes jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  last_call_at timestamptz,
  finished_at timestamptz
);
alter table pipeline.firecrawl_runs enable row level security;
revoke all on pipeline.firecrawl_runs from anon, authenticated;

create table if not exists pipeline.firecrawl_run_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null,
  course_id uuid,
  provider_id uuid,
  country text,
  url text,
  input jsonb not null default '{}'::jsonb,
  state text not null default 'queued' check (state in ('queued', 'leased', 'done')),
  leased_until timestamptz,
  outcome text,
  result jsonb,
  credits numeric,
  done_at timestamptz
);
create index if not exists firecrawl_run_items_run on pipeline.firecrawl_run_items(run_id, state);
create index if not exists firecrawl_run_items_course on pipeline.firecrawl_run_items(course_id);
alter table pipeline.firecrawl_run_items enable row level security;
revoke all on pipeline.firecrawl_run_items from anon, authenticated;

create table if not exists pipeline.firecrawl_calls (
  id bigserial primary key,
  at timestamptz not null default now(),
  run_id uuid,
  item_id uuid,
  use_case text not null,
  endpoint text not null,
  provider_id uuid,
  course_id uuid,
  url text,
  request jsonb not null default '{}'::jsonb,
  http int,
  success boolean not null default false,
  error text,
  scrape_id text,
  credits_used numeric,
  proxy_used text,
  page_status int,
  duration_ms int,
  outcome text,
  meta jsonb not null default '{}'::jsonb
);
create index if not exists firecrawl_calls_at on pipeline.firecrawl_calls(at);
create index if not exists firecrawl_calls_run on pipeline.firecrawl_calls(run_id);
alter table pipeline.firecrawl_calls enable row level security;
revoke all on pipeline.firecrawl_calls from anon, authenticated;

alter table pipeline.search_pass_links add column if not exists engine text not null default 'serper';

-- Settings (Platform Admin, UI). Sections are shown in this order on the Firecrawl panel.
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('firecrawl', 'target_countries', 'Countries', 'Countries whose universities are targets. Add a country code when it is onboarded.', 'list', '["AU","NZ","CA"]', null, null, null, 10, 'Decision 253', 'Target universities'),
  ('firecrawl', 'target_name_pattern', 'What a university is called', 'A pattern (regular expression, any case) the provider''s name must match.', 'text', '"(^|[^a-z])universit(y|ies)([^a-z]|$)"', null, null, null, 20, 'Decision 253', 'Target universities'),
  ('firecrawl', 'target_exclude_pattern', 'Names left out', 'A pattern (regular expression, any case). Providers whose name matches it are not targets (colleges, pathways, language centres and the like).', 'text', '"college|pathway|senior|language cent|divinity|theology"', null, null, null, 30, 'Decision 253', 'Target universities'),
  ('firecrawl', 'target_min_courses', 'Least active courses, by country', 'Country code and the least number of active courses, for example AU:100. Smaller universities are not targets. A country not listed has no minimum.', 'list', '["AU:100","NZ:100","CA:30"]', null, null, null, 40, 'Decision 253', 'Target universities'),
  ('firecrawl', 'target_registers', 'International-student registers', 'A target must be on one of these registers (or be marked as enrolling international students): cricos (Australia), nzqa (New Zealand), ircc_dli (Canada).', 'list', '["cricos","nzqa","ircc_dli"]', null, null, null, 50, 'Decision 253', 'Target universities'),
  ('firecrawl', 'target_only', 'Use Firecrawl only for target universities', 'Yes: every Firecrawl call of the coverage worker (discovery, search, page reading, scholarships) is made only for target universities. No: any provider.', 'boolean', 'true', null, null, null, 60, 'Decision 253', 'Target universities'),
  ('firecrawl', 'read_statuses', 'Pages to read', 'Pages in these states are read through Firecrawl: needs_render (needs a browser), blocked (refused a plain read), fetch_failed, too_thin.', 'list', '["needs_render","blocked","fetch_failed"]', null, null, null, 110, 'Decision 253', 'Read pages'),
  ('firecrawl', 'read_proxy', 'Proxy', 'basic, auto (basic first, then stealth when the site refuses), stealth or enhanced. Stealth and enhanced cost 4 more credits a page.', 'text', '"auto"', null, null, null, 120, 'Decision 253', 'Read pages'),
  ('firecrawl', 'read_wait_ms', 'Wait after the page loads', 'Time Firecrawl waits for scripts before taking the page. 0 for no wait.', 'number', '3000', 0, 30000, 'ms', 130, 'Decision 253', 'Read pages'),
  ('firecrawl', 'read_timeout_ms', 'Time allowed per page', 'Firecrawl stops a page after this long.', 'number', '60000', 10000, 120000, 'ms', 140, 'Decision 253', 'Read pages'),
  ('firecrawl', 'read_location', 'Read from the course''s country', 'Yes: Firecrawl reads the page as a visitor in the course''s country (some sites show international fees and intakes by location).', 'boolean', 'true', null, null, null, 150, 'Decision 253', 'Read pages'),
  ('firecrawl', 'read_credits_per_run', 'Credits one run may use', 'A Read pages run stops when it has used this many credits.', 'number', '15000', 1, 500000, 'credits', 160, 'Decision 253', 'Read pages'),
  ('firecrawl', 'find_query', 'Search wording', 'Words sent to Firecrawl search. {course}, {code}, {provider} and {domain} are filled in.', 'text', '"{course} site:{domain}"', null, null, null, 210, 'Decision 253', 'Find pages'),
  ('firecrawl', 'find_results', 'Results per search', 'How many results Firecrawl returns for each search (2 credits for every 10 results).', 'number', '5', 1, 20, 'results', 220, 'Decision 253', 'Find pages'),
  ('firecrawl', 'find_min_title_match', 'Title match needed', 'Share of the course title''s words that must be in a result''s title (0 to 1) before the page is offered to the identity check.', 'number', '0.6', 0, 1, null, 230, 'Decision 253', 'Find pages'),
  ('firecrawl', 'find_retry_refused', 'Search again where an earlier search was refused', 'Yes: courses whose earlier search results were all refused by the identity check are searched again.', 'boolean', 'false', null, null, null, 240, 'Decision 253', 'Find pages'),
  ('firecrawl', 'find_credits_per_run', 'Credits one run may use', 'A Find pages run stops when it has used this many credits.', 'number', '15000', 1, 500000, 'credits', 250, 'Decision 253', 'Find pages'),
  ('firecrawl', 'run_concurrency', 'Calls at the same time', 'How many Firecrawl calls one worker call makes at once. Keep it under the plan''s concurrency.', 'number', '12', 1, 50, 'calls', 310, 'Decision 253', 'Runs'),
  ('firecrawl', 'run_batch_per_call', 'Items per worker call', 'How many pages or courses one worker call takes. A worker call stops at its time limit and the next one carries on.', 'number', '40', 1, 200, 'items', 320, 'Decision 253', 'Runs'),
  ('firecrawl', 'run_auto_continue', 'Carry on every minute', 'Yes: an open run gets a new worker call every minute until it is finished, at its credits or at the plan''s reserve. No: runs only go when started or continued by hand.', 'boolean', 'true', null, null, null, 330, 'Decision 253', 'Runs')
on conflict (toolset_key, key) do nothing;

create or replace function security.firecrawl_setting(p_key text) returns jsonb
language sql stable security definer set search_path = '' as $f$
  select security.toolset_setting('firecrawl', p_key)
$f$;
revoke all on function security.firecrawl_setting(text) from public, anon, authenticated;

-- The target universities: the rule (settings) plus the Platform Admin's own additions and removals.
create or replace function security.firecrawl_targets_v1() returns table (provider_id uuid, country text, name text, courses int, rule_match boolean, included boolean, override_reason text, domain text)
language plpgsql stable security definer set search_path = '' as $f$
declare v_countries text[]; v_pat text; v_excl text; v_regs text[]; v_min jsonb := '{}'::jsonb; x text;
begin
  select coalesce(array_agg(upper(btrim(e))), '{}') into v_countries from jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_countries'), '[]'::jsonb)) e;
  v_pat := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
  v_excl := nullif(btrim(coalesce(security.firecrawl_setting('target_exclude_pattern') #>> '{}', '')), '');
  select coalesce(array_agg(lower(btrim(e))), '{}') into v_regs from jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_registers'), '[]'::jsonb)) e;
  for x in select jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_min_courses'), '[]'::jsonb)) loop
    if x ~ '^\s*[A-Za-z]{2}\s*:\s*[0-9]+\s*$' then v_min := v_min || jsonb_build_object(upper(btrim(split_part(x, ':', 1))), btrim(split_part(x, ':', 2))::int); end if;
  end loop;
  return query
  with cand as (
    select p.id, k.iso_alpha2 cc, coalesce(p.display_name, p.canonical_name) nm, p.website, p.enrols_international,
           (select count(*)::int from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') n,
           t.included ov, t.reason ovr
    from catalogue.providers p join ref.countries k on k.id = p.country_id
    left join pipeline.firecrawl_targets t on t.provider_id = p.id
    where t.provider_id is not null or (k.iso_alpha2 = any(v_countries) and coalesce(p.display_name, p.canonical_name) ~* v_pat)
  ), ruled as (
    select c.*, (c.cc = any(v_countries) and c.nm ~* v_pat and (v_excl is null or c.nm !~* v_excl)
                 and c.n >= coalesce((v_min->>c.cc)::int, 0)
                 and (c.enrols_international is true or exists (select 1 from catalogue.provider_registrations r where r.provider_id = c.id and lower(r.registration_scheme) = any(v_regs)))) rm
    from cand c
  )
  select r.id, r.cc, r.nm, r.n, r.rm, coalesce(r.ov, r.rm), r.ovr,
         coalesce(nullif(regexp_replace(lower(substring(r.website from '^(?:https?://)?([^/?#]+)')), '^www\.', ''), ''),
                  (select regexp_replace(lower(substring(pg.url from '^https?://([^/?#]+)')), '^www\.', '') h from pipeline.coverage_course_pages pg
                    where pg.provider_id = r.id and pg.status = 'bound' and pg.read_status = 'read' group by 1 order by count(*) desc limit 1))
  from ruled r;
end $f$;
revoke all on function security.firecrawl_targets_v1() from public, anon, authenticated;

-- For the worker: whether calls are kept to target universities, and which those are.
create or replace function public.svc_fc_targets() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object('target_only', coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true),
                            'ids', coalesce((select jsonb_agg(t.provider_id) from security.firecrawl_targets_v1() t where t.included), '[]'::jsonb));
end $f$;
revoke all on function public.svc_fc_targets() from public, anon, authenticated;
grant execute on function public.svc_fc_targets() to service_role;

-- What each use case would take now, for target universities only.
create or replace function security.firecrawl_backlog_v1(p_use_case text) returns table (course_id uuid, provider_id uuid, country text, url text, input jsonb)
language plpgsql stable security definer set search_path = '' as $f$
declare v_statuses text[]; v_retry boolean;
begin
  select coalesce(array_agg(e), '{}') into v_statuses from jsonb_array_elements_text(coalesce(security.firecrawl_setting('read_statuses'), '[]'::jsonb)) e;
  v_retry := coalesce((security.firecrawl_setting('find_retry_refused') #>> '{}')::boolean, false);
  if p_use_case = 'read_page' then
    return query
    select pg.course_id, pg.provider_id, t.country, pg.url,
           jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'page_status', pg.status, 'earlier_read', pg.read_status, 'earlier_http', pg.http_status)
    from security.firecrawl_targets_v1() t
    join pipeline.coverage_course_pages pg on pg.provider_id = t.provider_id
    join catalogue.courses c on c.id = pg.course_id
    where t.included and c.lifecycle_status = 'active' and pg.status in ('bound', 'ambiguous') and pg.read_status = any(v_statuses)
      and pg.url is not null and coalesce(pg.http_status, 0) not in (404, 410) and pg.evidence_id is null;
  elsif p_use_case = 'find_page' then
    return query
    select c.id, t.provider_id, t.country, null::text,
           jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'provider', t.name, 'domain', t.domain,
                              'earlier_url', pg.url, 'earlier_status', pg.status)
    from security.firecrawl_targets_v1() t
    join catalogue.courses c on c.provider_id = t.provider_id
    left join pipeline.coverage_course_pages pg on pg.course_id = c.id
    where t.included and t.domain is not null and c.lifecycle_status = 'active'
      and (pg.course_id is null or pg.status not in ('bound', 'ambiguous'))
      and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'official_url')
      and not exists (select 1 from pipeline.search_pass_links l where l.course_id = c.id and (l.state in ('found', 'verified') or (l.state = 'none' and not v_retry)));
  end if;
end $f$;
revoke all on function security.firecrawl_backlog_v1(text) from public, anon, authenticated;

-- The platform's Firecrawl allowance follows Firecrawl's own reported balance when a reading from the last 2 hours
-- exists (md5-guarded). Without a recent reading the monthly limit setting applies as before.
do $g$ declare v_oid oid := 'security.layer2_provider_budget_status(uuid,numeric)'::regprocedure; v_def text; o1 text; o2 text; c int;
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '21113f0647869a59432f922c5092da86' then raise exception 'layer2_provider_budget_status changed, not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o1 := $x$  v_remaining:=least(v_remaining, coalesce((select greatest(o.remaining_units$x$;
  o2 := $x$order by o.observed_at desc limit 1), v_remaining));$x$;
  c := (length(v_def) - length(replace(v_def, o1, ''))) / length(o1); if c <> 1 then raise exception 'budget snippet 1 found % times', c; end if;
  c := (length(v_def) - length(replace(v_def, o2, ''))) / length(o2); if c <> 1 then raise exception 'budget snippet 2 found % times', c; end if;
  v_def := replace(replace(v_def, o1, $x$  -- Decision 253: Firecrawl's own balance is the authority when read in the last 2 hours.
  v_remaining:=coalesce((select greatest(o.remaining_units$x$), o2, $x$order by o.observed_at desc limit 1), v_remaining);$x$);
  execute v_def;
end $g$;

-- The plan Firecrawl reports (Platform Admin, 15:51: Growth plan, about 490,000 credits left).
do $p$ declare v_before jsonb;
begin
  select billing_config into v_before from pipeline.layer2_acquisition_providers where provider_key = 'firecrawl';
  update pipeline.layer2_acquisition_providers set billing_config = billing_config || jsonb_build_object('monthly_vendor_units_limit', 500000, 'plan_tier', 'growth_500k', 'plan_note', 'Growth plan, 500,000 credits a month as reported by Firecrawl (period 2 Oct to 2 Nov 2026)', 'plan_confirmed_at', now(), 'entitlement_basis', 'vendor_reported_plan'), updated_at = now() where provider_key = 'firecrawl';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('toolsets', 'firecrawl_plan', 'firecrawl', jsonb_build_object('before', v_before->'monthly_vendor_units_limit', 'after', 500000, 'reason', 'Decision 253. Platform Admin 15:51 stated the Growth plan. Firecrawl reports 500,000 credits for 2 Oct to 2 Nov.'), null);
end $p$;

-- Pages found by a Firecrawl search are labelled as such when the next candidate is tried (md5-guarded).
do $g$ declare v_oid oid := 'security.search_pass_advance_v1()'::regprocedure; v_def text; o text; c int;
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '2400c446114c5d22deb8ee6719cbbfc1' then raise exception 'search_pass_advance_v1 changed, not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$set url = v_next, basis = 'serper_search', status$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'advance snippet found % times', c; end if;
  execute replace(v_def, o, $x$set url = v_next, basis = case when r.engine = 'firecrawl' then 'firecrawl_search' else 'serper_search' end, status$x$);
end $g$;

-- Start, stop or continue a run, and add or take out a target university (Platform Admin, with a reason).
create or replace function public.admin_firecrawl_write(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_uc text := p_args->>'use_case';
        v_run uuid; v_n int; v_settings jsonb; v_cap numeric; v_budget jsonb; v_pid uuid; v_inc boolean; v_r pipeline.firecrawl_runs%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'target' then
    v_pid := (p_args->>'provider_id')::uuid;
    if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
    if p_args->'included' is null or jsonb_typeof(p_args->'included') = 'null' then
      update pipeline.firecrawl_targets set included = (select t.rule_match from security.firecrawl_targets_v1() t where t.provider_id = v_pid), reason = 'back to the rule: ' || v_reason, set_by = auth.uid(), set_at = now() where provider_id = v_pid;
    else
      v_inc := (p_args->>'included')::boolean;
      insert into pipeline.firecrawl_targets(provider_id, included, reason, set_by, set_at) values (v_pid, v_inc, v_reason, auth.uid(), now())
        on conflict (provider_id) do update set included = excluded.included, reason = excluded.reason, set_by = excluded.set_by, set_at = now() where pipeline.firecrawl_targets.provider_id = excluded.provider_id;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_target', v_pid::text, jsonb_build_object('included', p_args->'included', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  elsif p_action = 'start' then
    if v_uc not in ('read_page', 'find_page') then raise exception 'use case must be read_page or find_page'; end if;
    if exists (select 1 from pipeline.firecrawl_runs r where r.use_case = v_uc and r.status = 'running') then raise exception 'a run of this use case is still open. Let it finish or stop it first'; end if;
    v_budget := security.layer2_provider_budget_status((select p.id from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl'), 1);
    if not coalesce((v_budget->>'allowed')::boolean, false) then raise exception 'Firecrawl is at its reserve. Check the plan on this page first'; end if;
    select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) into v_settings from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl';
    v_cap := (v_settings->>(case when v_uc = 'read_page' then 'read_credits_per_run' else 'find_credits_per_run' end))::numeric;
    insert into pipeline.firecrawl_runs(use_case, settings, reason, requested_by, credits_cap) values (v_uc, v_settings, v_reason, auth.uid(), v_cap) returning id into v_run;
    insert into pipeline.firecrawl_run_items(run_id, course_id, provider_id, country, url, input)
      select v_run, b.course_id, b.provider_id, b.country, b.url, b.input from (select distinct on (b0.course_id) b0.* from security.firecrawl_backlog_v1(v_uc) b0 order by b0.course_id) b
      order by b.provider_id, b.course_id;
    get diagnostics v_n = row_count;
    update pipeline.firecrawl_runs set items = v_n, status = case when v_n = 0 then 'done' else 'running' end, finished_at = case when v_n = 0 then now() end where id = v_run;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_run_start', v_uc, jsonb_build_object('run_id', v_run, 'items', v_n, 'credits_cap', v_cap, 'reason', v_reason), auth.uid());
    if v_n > 0 then perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', v_run)); end if;
    return jsonb_build_object('ok', true, 'run_id', v_run, 'items', v_n, 'credits_cap', v_cap);
  elsif p_action in ('stop', 'continue') then
    select * into v_r from pipeline.firecrawl_runs where id = (p_args->>'run_id')::uuid;
    if v_r.id is null then raise exception 'unknown run'; end if;
    if p_action = 'stop' then
      update pipeline.firecrawl_runs set status = 'stopped', finished_at = now() where id = v_r.id and status = 'running';
    else
      if v_r.status not in ('running', 'stopped_credit_cap', 'stopped_plan_reserve', 'stopped') then raise exception 'only an open or stopped run can be continued'; end if;
      if p_args ? 'add_credits' then update pipeline.firecrawl_runs set credits_cap = credits_cap + greatest((p_args->>'add_credits')::numeric, 0) where id = v_r.id; end if;
      update pipeline.firecrawl_runs set status = 'running', finished_at = null where id = v_r.id;
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', v_r.id));
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'firecrawl_run_' || p_action, v_r.id::text, jsonb_build_object('add_credits', p_args->'add_credits', 'reason', v_reason), auth.uid());
    return jsonb_build_object('ok', true);
  end if;
  raise exception 'unknown action';
end $f$;
revoke all on function public.admin_firecrawl_write(text, jsonb) from public, anon;
grant execute on function public.admin_firecrawl_write(text, jsonb) to authenticated;

-- The worker takes the next items of a run (leased for 5 minutes). Pages being read are leased on the page too, so the
-- regular reader does not read the same page at the same time.
create or replace function public.svc_fc_run_next(p_run_id uuid, p_limit int) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r pipeline.firecrawl_runs%rowtype; v_items jsonb; v_left int; v_budget jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_r from pipeline.firecrawl_runs where id = p_run_id for update;
  if v_r.id is null or v_r.status <> 'running' then return jsonb_build_object('run', to_jsonb(v_r) - 'settings', 'items', '[]'::jsonb); end if;
  if v_r.credits_used >= v_r.credits_cap then
    update pipeline.firecrawl_runs set status = 'stopped_credit_cap', finished_at = now() where id = v_r.id;
    return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'status', 'stopped_credit_cap'), 'items', '[]'::jsonb);
  end if;
  v_budget := security.layer2_provider_budget_status((select p.id from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl'), 5);
  if not coalesce((v_budget->>'allowed')::boolean, false) then
    update pipeline.firecrawl_runs set status = 'stopped_plan_reserve', finished_at = now() where id = v_r.id;
    return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'status', 'stopped_plan_reserve'), 'items', '[]'::jsonb);
  end if;
  if coalesce(p_limit, 0) <= 0 then
    return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'use_case', v_r.use_case, 'status', v_r.status, 'settings', v_r.settings, 'credits_left', v_r.credits_cap - v_r.credits_used), 'items', '[]'::jsonb);
  end if;
  with picked as (
    select i.id from pipeline.firecrawl_run_items i
    where i.run_id = v_r.id and (i.state = 'queued' or (i.state = 'leased' and i.leased_until < now()))
    order by i.state desc, i.provider_id, i.id limit greatest(1, least(coalesce(p_limit, 40), 200)) for update skip locked
  ), upd as (
    update pipeline.firecrawl_run_items i set state = 'leased', leased_until = now() + interval '5 minutes' from picked where i.id = picked.id
    returning i.id, i.course_id, i.provider_id, i.country, i.url, i.input, i.result
  )
  select coalesce(jsonb_agg(to_jsonb(upd)), '[]'::jsonb) into v_items from upd;
  if v_r.use_case = 'read_page' then
    update pipeline.coverage_course_pages pg set leased_until = now() + interval '5 minutes' where pg.course_id in (select (e->>'course_id')::uuid from jsonb_array_elements(v_items) e);
  end if;
  if jsonb_array_length(v_items) = 0 then
    select count(*) into v_left from pipeline.firecrawl_run_items i where i.run_id = v_r.id and i.state <> 'done';
    if v_left = 0 then update pipeline.firecrawl_runs set status = 'done', finished_at = now() where id = v_r.id; end if;
  end if;
  update pipeline.firecrawl_runs set last_call_at = now() where id = v_r.id;
  return jsonb_build_object('run', jsonb_build_object('id', v_r.id, 'use_case', v_r.use_case, 'status', v_r.status, 'settings', v_r.settings, 'credits_left', v_r.credits_cap - v_r.credits_used), 'items', v_items);
end $f$;
revoke all on function public.svc_fc_run_next(uuid, int) from public, anon, authenticated;
grant execute on function public.svc_fc_run_next(uuid, int) to service_role;

-- The worker records one item's outcome and the credits it used.
create or replace function public.svc_fc_run_record(p_item_id uuid, p_outcome text, p_result jsonb, p_credits numeric) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_i pipeline.firecrawl_run_items%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_i from pipeline.firecrawl_run_items where id = p_item_id for update;
  if v_i.id is null then return 'unknown'; end if;
  if v_i.state = 'done' then return 'already_done'; end if;
  if p_outcome = 'retry' then
    update pipeline.firecrawl_run_items set state = 'queued', leased_until = null, credits = coalesce(credits, 0) + coalesce(p_credits, 0), result = p_result where id = v_i.id;
  else
    update pipeline.firecrawl_run_items set state = 'done', leased_until = null, outcome = p_outcome, result = p_result, credits = coalesce(credits, 0) + coalesce(p_credits, 0), done_at = now() where id = v_i.id;
  end if;
  update pipeline.firecrawl_runs r set credits_used = r.credits_used + coalesce(p_credits, 0), done = r.done + case when p_outcome = 'retry' then 0 else 1 end, outcomes = case when p_outcome = 'retry' then r.outcomes else jsonb_set(r.outcomes, array[p_outcome], to_jsonb(coalesce((r.outcomes->>p_outcome)::int, 0) + 1)) end where r.id = v_i.run_id;
  update pipeline.coverage_course_pages set leased_until = null where course_id = v_i.course_id and leased_until is not null and v_i.url is not null;
  return 'ok';
end $f$;
revoke all on function public.svc_fc_run_record(uuid, text, jsonb, numeric) from public, anon, authenticated;
grant execute on function public.svc_fc_run_record(uuid, text, jsonb, numeric) to service_role;

-- Every Firecrawl call a run makes (service role). Kept for the support report.
create or replace function public.svc_fc_call_log(p jsonb) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.firecrawl_calls(run_id, item_id, use_case, endpoint, provider_id, course_id, url, request, http, success, error, scrape_id, credits_used, proxy_used, page_status, duration_ms, outcome, meta)
  values ((p->>'run_id')::uuid, (p->>'item_id')::uuid, coalesce(p->>'use_case', 'unknown'), coalesce(p->>'endpoint', 'unknown'), (p->>'provider_id')::uuid, (p->>'course_id')::uuid,
          left(p->>'url', 2000), coalesce(p->'request', '{}'::jsonb), (p->>'http')::int, coalesce((p->>'success')::boolean, false), left(p->>'error', 1000), left(p->>'scrape_id', 200),
          (p->>'credits_used')::numeric, left(p->>'proxy_used', 40), (p->>'page_status')::int, (p->>'duration_ms')::int, left(p->>'outcome', 60), coalesce(p->'meta', '{}'::jsonb));
end $f$;
revoke all on function public.svc_fc_call_log(jsonb) from public, anon, authenticated;
grant execute on function public.svc_fc_call_log(jsonb) to service_role;

-- A page found by a Firecrawl search goes into the identity check like any found page. A confirmed page or a link
-- entered by hand is never replaced. Every change is logged in pipeline.page_link_repairs.
create or replace function public.svc_fc_find_bind(p_item_id uuid, p_candidates jsonb) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_i pipeline.firecrawl_run_items%rowtype; v_c jsonb := coalesce(p_candidates, '[]'::jsonb); v_url text; v_pg pipeline.coverage_course_pages%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_i from pipeline.firecrawl_run_items where id = p_item_id;
  if v_i.id is null or v_i.course_id is null then return 'no_course'; end if;
  if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) = 0 then return 'no_candidate'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = v_i.course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = v_i.course_id;
  if v_pg.course_id is not null and v_pg.status in ('bound', 'ambiguous') then return 'page_already_bound'; end if;
  v_url := v_c->>0;
  if v_pg.course_id is not null and v_pg.url = v_url then
    if jsonb_array_length(v_c) < 2 then return 'already_refused'; end if;
    v_url := v_c->>1;
  end if;
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason, run_id)
    values (v_i.course_id, v_i.provider_id, v_pg.url, v_url, 'firecrawl search: page found', v_i.run_id);
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (v_i.course_id, v_i.provider_id, v_url, 'firecrawl_search', 'bound', now(), now(), 0)
  on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(), score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now() where pipeline.coverage_course_pages.status not in ('bound', 'ambiguous');
  insert into pipeline.search_pass_links(course_id, provider_id, run_id, candidates, cand_idx, bound_url, refind, state, updated_at, engine)
    values (v_i.course_id, v_i.provider_id, v_i.run_id, v_c, case when v_url = v_c->>0 then 1 else 2 end, v_url, false, 'found', now(), 'firecrawl')
  on conflict (course_id) do update set run_id = excluded.run_id, candidates = excluded.candidates, cand_idx = excluded.cand_idx, bound_url = excluded.bound_url, refind = false, state = 'found', updated_at = now(), engine = 'firecrawl' where pipeline.search_pass_links.course_id = excluded.course_id;
  return 'bound';
end $f$;
revoke all on function public.svc_fc_find_bind(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.svc_fc_find_bind(uuid, jsonb) to service_role;

-- Each minute: an open run with "carry on" gets a worker call. Expired leases go back to the queue.
create or replace function security.firecrawl_runs_tick_v1() returns int
language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0;
begin
  update pipeline.firecrawl_run_items set state = 'queued', leased_until = null where state = 'leased' and leased_until < now() - interval '1 minute';
  if not coalesce((security.firecrawl_setting('run_auto_continue') #>> '{}')::boolean, true) then return 0; end if;
  for r in select id from pipeline.firecrawl_runs where status = 'running' order by created_at loop
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'fc_run', 'run_id', r.id));
    n := n + 1;
  end loop;
  return n;
end $f$;
revoke all on function security.firecrawl_runs_tick_v1() from public, anon, authenticated;
select cron.schedule('firecrawl-runs', '* * * * *', 'select security.firecrawl_runs_tick_v1()');
insert into pipeline.platform_job_layers(jobname, layer, updated_at) values ('firecrawl-runs', 2, now()) on conflict (jobname) do nothing;

-- The Firecrawl panel: plan and balance, target universities with what each has now, runs, and spend.
create or replace function public.admin_firecrawl_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_fc uuid; v_obs record; v_out jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  select p.id into v_fc from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl';
  select o.* into v_obs from pipeline.vendor_credit_observations o where o.provider_id = v_fc order by o.observed_at desc limit 1;
  with t as (select * from security.firecrawl_targets_v1()),
  c as (
    select t.provider_id, count(*) courses,
           count(*) filter (where pg.status = 'bound' and pg.read_status = 'read' and pg.identity_basis is not null) confirmed,
           count(*) filter (where pg.status in ('bound', 'ambiguous') and pg.read_status in ('needs_render', 'blocked', 'fetch_failed', 'too_thin', 'robots_disallowed')) unreadable,
           count(*) filter (where pg.course_id is null or pg.status not in ('bound', 'ambiguous')) no_page,
           count(*) filter (where exists (select 1 from catalogue.course_intakes i where i.course_id = cc.id)) intakes,
           count(*) filter (where exists (select 1 from catalogue.course_english_requirements e where e.course_id = cc.id)) english,
           count(*) filter (where exists (select 1 from catalogue.course_fees f join pipeline.sources s on s.id = f.source_id where f.course_id = cc.id and coalesce(f.audience, '') ~* 'int' and s.source_type <> 'dataset')) web_fee,
           count(*) filter (where exists (select 1 from catalogue.course_fees f where f.course_id = cc.id and coalesce(f.audience, '') ~* 'int')) any_fee
    from t join catalogue.courses cc on cc.provider_id = t.provider_id and cc.lifecycle_status = 'active'
    left join pipeline.coverage_course_pages pg on pg.course_id = cc.id
    group by t.provider_id
  )
  select jsonb_build_object(
    'can_manage', coalesce(v_rank, 0) >= 6,
    'plan', jsonb_build_object('budget', security.layer2_provider_budget_status(v_fc, 1), 'vendor', case when v_obs.provider_id is null then null else jsonb_build_object('observed_at', v_obs.observed_at, 'plan_credits', v_obs.plan_units, 'remaining', v_obs.remaining_units, 'period_start', v_obs.raw->>'billing_period_start', 'period_end', v_obs.period_end) end),
    'targets', coalesce((select jsonb_agg(jsonb_build_object('provider_id', t.provider_id, 'country', t.country, 'name', t.name, 'domain', t.domain, 'rule_match', t.rule_match, 'included', t.included, 'override_reason', t.override_reason,
                 'courses', coalesce(c.courses, 0), 'confirmed', coalesce(c.confirmed, 0), 'unreadable', coalesce(c.unreadable, 0), 'no_page', coalesce(c.no_page, 0), 'intakes', coalesce(c.intakes, 0), 'english', coalesce(c.english, 0), 'web_fee', coalesce(c.web_fee, 0), 'any_fee', coalesce(c.any_fee, 0))
               order by t.included desc, t.country, coalesce(c.courses, 0) desc) from t left join c on c.provider_id = t.provider_id), '[]'::jsonb),
    'backlog', jsonb_build_object('read_page', (select count(*) from security.firecrawl_backlog_v1('read_page')), 'find_page', (select count(*) from security.firecrawl_backlog_v1('find_page'))),
    'runs', coalesce((select jsonb_agg(to_jsonb(r) - 'settings' order by r.created_at desc) from (select * from pipeline.firecrawl_runs order by created_at desc limit 12) r), '[]'::jsonb),
    'spend', coalesce((select jsonb_agg(jsonb_build_object('purpose', s.purpose, 'target', s.target, 'units', s.units) order by s.units desc) from (
               select u.purpose, (u.provider_id in (select provider_id from security.firecrawl_targets_v1() where included)) target, sum(u.units) units
               from pipeline.coverage_vendor_usage u where u.acquisition_provider_id = v_fc and u.at >= coalesce((v_obs.raw->>'billing_period_start')::timestamptz, date_trunc('month', now()))
               group by 1, 2) s), '[]'::jsonb)
  ) into v_out;
  return v_out;
end $f$;
revoke all on function public.admin_firecrawl_read() from public, anon;
grant execute on function public.admin_firecrawl_read() to authenticated;

-- The Firecrawl support report: every logged call since a time, by result, by site and by error, with scrape ids.
create or replace function public.admin_firecrawl_report(p_since timestamptz) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_since timestamptz := coalesce(p_since, now() - interval '7 days'); v_fc uuid; v_obs record;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  select p.id into v_fc from pipeline.layer2_acquisition_providers p where p.provider_key = 'firecrawl';
  select o.* into v_obs from pipeline.vendor_credit_observations o where o.provider_id = v_fc order by o.observed_at desc limit 1;
  return jsonb_build_object(
    'since', v_since, 'generated_at', now(),
    'account', case when v_obs.provider_id is null then null else jsonb_build_object('plan_credits', v_obs.plan_units, 'remaining', v_obs.remaining_units, 'period_start', v_obs.raw->>'billing_period_start', 'period_end', v_obs.period_end, 'observed_at', v_obs.observed_at) end,
    'totals', (select jsonb_build_object('calls', count(*), 'succeeded', count(*) filter (where success), 'failed', count(*) filter (where not success), 'credits', coalesce(sum(credits_used), 0),
                 'api_errors', count(*) filter (where http is null or http >= 400), 'timeouts', count(*) filter (where outcome = 'timeout' or error ~* 'timed? ?out'),
                 'rate_limited', count(*) filter (where http = 429), 'stealth_used', count(*) filter (where proxy_used ~* 'stealth|enhanced'), 'median_ms', percentile_disc(0.5) within group (order by duration_ms))
               from pipeline.firecrawl_calls where at >= v_since),
    'by_endpoint', coalesce((select jsonb_agg(x order by x->>'endpoint') from (select jsonb_build_object('endpoint', endpoint, 'use_case', use_case, 'calls', count(*), 'succeeded', count(*) filter (where success), 'credits', coalesce(sum(credits_used), 0)) x
               from pipeline.firecrawl_calls where at >= v_since group by endpoint, use_case) q), '[]'::jsonb),
    'by_outcome', coalesce((select jsonb_object_agg(coalesce(outcome, 'unknown'), n) from (select outcome, count(*) n from pipeline.firecrawl_calls where at >= v_since group by 1) q), '{}'::jsonb),
    'by_site', coalesce((select jsonb_agg(x order by (x->>'failed')::int desc, (x->>'calls')::int desc) from (
        select jsonb_build_object('site', h, 'calls', count(*), 'failed', count(*) filter (where not success),
               'page_statuses', (select jsonb_object_agg(coalesce(s2.ps::text, 'none'), s2.n) from (select page_status ps, count(*) n from pipeline.firecrawl_calls k2 where k2.at >= v_since and regexp_replace(lower(substring(k2.url from '^https?://([^/?#]+)')), '^www\.', '') = q.h group by 1) s2),
               'errors', (select jsonb_agg(distinct left(k3.error, 160)) from pipeline.firecrawl_calls k3 where k3.at >= v_since and k3.error is not null and regexp_replace(lower(substring(k3.url from '^https?://([^/?#]+)')), '^www\.', '') = q.h),
               'proxies', (select jsonb_agg(distinct k4.proxy_used) from pipeline.firecrawl_calls k4 where k4.at >= v_since and k4.proxy_used is not null and regexp_replace(lower(substring(k4.url from '^https?://([^/?#]+)')), '^www\.', '') = q.h),
               'samples', (select jsonb_agg(jsonb_build_object('url', k5.url, 'scrape_id', k5.scrape_id, 'http', k5.http, 'page_status', k5.page_status, 'error', left(k5.error, 200), 'at', k5.at)) from (
                   select * from pipeline.firecrawl_calls k5 where k5.at >= v_since and not k5.success and regexp_replace(lower(substring(k5.url from '^https?://([^/?#]+)')), '^www\.', '') = q.h order by k5.at desc limit 5) k5)) x
        from (select regexp_replace(lower(substring(url from '^https?://([^/?#]+)')), '^www\.', '') h, success from pipeline.firecrawl_calls where at >= v_since and endpoint = 'scrape' and url ~ '^https?://') q
        group by h having count(*) filter (where not success) > 0) z), '[]'::jsonb),
    'errors', coalesce((select jsonb_agg(x order by (x->>'calls')::int desc) from (
        select jsonb_build_object('error', e, 'calls', count(*), 'first_at', min(at), 'last_at', max(at), 'sample_scrape_id', (array_agg(scrape_id order by at desc) filter (where scrape_id is not null))[1], 'sample_url', (array_agg(url order by at desc))[1]) x
        from (select coalesce(left(error, 200), 'HTTP ' || coalesce(http::text, 'none') || ', page status ' || coalesce(page_status::text, 'none')) e, at, scrape_id, url from pipeline.firecrawl_calls where at >= v_since and not success) q group by e) z), '[]'::jsonb)
  );
end $f$;
revoke all on function public.admin_firecrawl_report(timestamptz) from public, anon;
grant execute on function public.admin_firecrawl_report(timestamptz) to authenticated;
