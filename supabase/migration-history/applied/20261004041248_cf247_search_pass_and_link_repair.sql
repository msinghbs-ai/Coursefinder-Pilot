-- CF-247 (4 Oct 2026, 16:00 AEDT). Decision 252, next steps 1 and 2. Platform Admin, 15:07: "Proceed".
--   Step 1. Serper as a second discovery pass. A search pass is a run the Platform Admin starts (with a reason) over the
--           courses the first search left without a page. Each page Serper finds on the provider's own site goes into
--           the existing identity check exactly like a page from the first search (basis serper_search). Nothing is
--           admitted by the pass: the reader decides. If the reader refuses the page, the next candidate is tried, then
--           the course is left as before. A page already confirmed, or a link entered by hand, is never replaced.
--   Step 2. Repair page addresses. The first search kept addresses without their query string, so script pages
--           (calendar.ualberta.ca/preview_program.php and the like) opened a blank page. The full address is taken back
--           from the stored search results and the page goes back to the reader. The picker now keeps the query string
--           of script pages. Bound pages that could not be read and do not look like course pages are offered to the
--           search pass for a better page (a setting).
-- Every repair and every page the pass binds is logged in pipeline.page_link_repairs. All limits are settings.
-- No text value in this file contains a semicolon.

create table if not exists pipeline.page_link_repairs (
  id bigserial primary key,
  course_id uuid not null,
  provider_id uuid,
  old_url text,
  new_url text not null,
  reason text not null,
  run_id uuid,
  at timestamptz not null default now()
);
create index if not exists page_link_repairs_course on pipeline.page_link_repairs(course_id);
alter table pipeline.page_link_repairs enable row level security;
revoke all on pipeline.page_link_repairs from anon, authenticated;

create table if not exists pipeline.search_pass_links (
  course_id uuid primary key,
  provider_id uuid,
  run_id uuid,
  candidates jsonb not null default '[]'::jsonb,
  cand_idx int not null default 1,
  bound_url text,
  refind boolean not null default false,
  state text not null default 'found' check (state in ('found', 'verified', 'none')),
  updated_at timestamptz not null default now()
);
alter table pipeline.search_pass_links enable row level security;
revoke all on pipeline.search_pass_links from anon, authenticated;

alter table pipeline.toolset_sample_runs add column if not exists applies boolean not null default false;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('serper', 'pass_cases_per_country', 'Courses per country in one pass', 'How many courses a search pass takes per country. Courses already searched by an earlier pass are skipped.', 'number', '1000', 1, 20000, 'courses', 10, 'Decision 252 step 1', 'Search pass'),
  ('serper', 'pass_credits_per_run', 'Credits one pass may use', 'A search pass stops when it has used this many credits. The key''s plan limits apply as well.', 'number', '2100', 1, 1000000, 'credits', 20, 'Decision 252 step 1', 'Search pass'),
  ('serper', 'pass_auto_continue', 'Carry on after each worker call', 'Yes: when a worker call reaches its time limit the pass starts the next call by itself until it is finished, at its credits or at the plan''s reserve. No: press Continue each time.', 'boolean', 'true', null, null, null, 30, 'Decision 252 step 1', 'Search pass'),
  ('serper', 'pass_refind_unreadable', 'Look again for pages that could not be read', 'Yes: courses whose page could not be read (needs a browser, blocked or failed) and whose address does not look like a course page are included, so a better page can be found.', 'boolean', 'true', null, null, null, 40, 'Decision 252 step 2', 'Search pass'),
  ('serper', 'course_like_url', 'What a course page address looks like', 'A pattern (regular expression, any case). Unreadable pages whose address matches it are left for rendering instead of being searched again.', 'text', '"/(course|courses|program|programs|programme|programmes|qualification|qualifications|study|degree|degrees|handbook)"', null, null, null, 50, 'Decision 252 step 2', 'Search pass')
on conflict (toolset_key, key) do nothing;

-- Step 2a: the picker keeps the query string of script pages (md5-guarded).
do $g$ declare v_oid oid := 'security.course_link_pick_v1(uuid,text[])'::regprocedure; v_def text; o text; c int;
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '12c2663ee54572ddde516881d2d5aa76' then raise exception 'course_link_pick_v1 changed, not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$u as (select regexp_replace(url, '[?#].*$', '') url, i$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'pick snippet found % times', c; end if;
  execute replace(v_def, o, $x$u as (select case when url ~* '\.(php|aspx?|cfm|jsp)\?' then regexp_replace(url, '#.*$', '') else regexp_replace(url, '[?#].*$', '') end url, i$x$);
end $g$;

-- Step 2b: one-off repair of addresses that lost their query string (from the stored search results).
do $r$ declare f record; n int := 0;
begin
  for f in select distinct on (pg.course_id) pg.course_id, pg.provider_id, pg.url old_url, pg.basis, regexp_replace(r.u, '#.*$', '') new_url
             from pipeline.coverage_course_pages pg
             join pipeline.course_link_search s on s.course_id = pg.course_id
             cross join lateral jsonb_array_elements_text(case when jsonb_typeof(s.results) = 'array' then s.results else '[]'::jsonb end) with ordinality r(u, ord)
            where pg.basis in ('title_search', 'cricos_search') and pg.url ~* '\.(php|aspx?|cfm|jsp)$'
              and pg.read_status is distinct from 'read' and r.u like pg.url || '?%' and r.u not like pg.url || '?utm%'
              and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = pg.course_id and k.field = 'official_url')
            order by pg.course_id, r.ord loop
    insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason) values (f.course_id, f.provider_id, f.old_url, f.new_url, 'query string restored from the stored search results (Decision 252 step 2)');
    perform security.course_link_bind_v1(f.course_id, f.provider_id, f.new_url, f.basis);
    update pipeline.course_link_search set bound_url = f.new_url where course_id = f.course_id and bound_url = f.old_url;
    n := n + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'page_link_repair', 'query strings restored', jsonb_build_object('pages', n, 'decision', 'Decision 252 step 2'), null);
end $r$;

-- The courses a search pass takes: no page found by the first search, or (a setting) a page that could not be read and
-- does not look like a course page. Never a course whose page is confirmed or whose link was entered by hand.
create or replace function security.toolset_pass_backlog(p_country text) returns table (subject_key text, course_id uuid, provider_id uuid, input jsonb)
language sql stable security definer set search_path = '' as $f$
  select b.subject_key, b.course_id, b.provider_id, b.input
  from security.toolset_backlog('find_course_page', p_country) b
  where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = b.course_id and k.field = 'official_url')
  union all
  select 'course:' || c.id, c.id, p.id,
         jsonb_build_object('course', coalesce(c.display_title, c.canonical_title), 'code', c.course_code, 'provider', coalesce(p.display_name, p.canonical_name),
                            'domain', regexp_replace(lower(substring(p.website from '^(?:https?://)?([^/?#]+)')), '^www\.', ''), 'country', k.name,
                            'earlier_candidate', pg.url, 'earlier_status', pg.read_status, 'refind', true)
  from pipeline.coverage_course_pages pg join catalogue.courses c on c.id = pg.course_id join catalogue.providers p on p.id = pg.provider_id join ref.countries k on k.id = p.country_id
  where coalesce((security.toolset_setting('serper', 'pass_refind_unreadable') #>> '{}')::boolean, false)
    and k.iso_alpha2 = p_country and c.lifecycle_status = 'active' and p.website is not null
    and pg.status = 'bound' and pg.read_status in ('needs_render', 'blocked', 'fetch_failed') and pg.evidence_id is null
    and pg.url !~* coalesce(security.toolset_setting('serper', 'course_like_url') #>> '{}', '/course')
    and not exists (select 1 from pipeline.manual_locks k2 where k2.entity = 'course' and k2.entity_id = c.id and k2.field = 'official_url')
$f$;
revoke all on function security.toolset_pass_backlog(text) from public, anon, authenticated;

-- Start a search pass (Platform Admin, with a reason). The first worker call starts at once with a one-time run pass.
create or replace function public.admin_search_pass_start(p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_reason, '')); v_settings jsonb; v_countries text[];
        v_run uuid; v_cc text; v_n int; v_added int := 0; v_plan jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if not exists (select 1 from pipeline.layer2_acquisition_providers p where p.provider_key = 'serper' and p.vault_secret_id is not null) then
    raise exception 'save the Serper key on Platform settings › Environment & integrations first'; end if;
  v_plan := security.toolset_plan_status('serper');
  if (v_plan->>'at_reserve')::boolean then raise exception 'the Serper key''s plan is at its reserve. Replace the key or raise the plan limits first'; end if;
  if exists (select 1 from pipeline.toolset_sample_runs r where r.toolset_key = 'serper' and r.status in ('ready', 'running', 'paused_time_limit')) then
    raise exception 'a Serper run is still open. Finish or stop it first'; end if;
  select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) into v_settings from pipeline.platform_toolset_settings s where s.toolset_key = 'serper';
  v_settings := v_settings || jsonb_build_object('sample_credits_per_run', v_settings->'pass_credits_per_run');
  select array_agg(x) into v_countries from jsonb_array_elements_text(v_settings->'sample_countries') x;
  insert into pipeline.toolset_sample_runs(toolset_key, purpose, countries, settings, reason, requested_by, applies)
    values ('serper', 'find_course_page', coalesce(v_countries, '{}'), v_settings, v_reason, auth.uid(), true) returning id into v_run;
  foreach v_cc in array coalesce(v_countries, '{}') loop
    v_n := (v_settings->>'pass_cases_per_country')::int;
    insert into pipeline.toolset_sample_items(run_id, country, subject_key, course_id, provider_id, input)
    select v_run, v_cc, b.subject_key, b.course_id, b.provider_id, b.input
    from (select distinct on (b0.subject_key) b0.* from security.toolset_pass_backlog(v_cc) b0 order by b0.subject_key) b
    where not exists (select 1 from pipeline.toolset_sample_items i join pipeline.toolset_sample_runs r on r.id = i.run_id
                      where i.subject_key = b.subject_key and r.applies and i.status = 'done')
    order by md5(b.subject_key || v_run::text) limit v_n;
    get diagnostics v_n = row_count; v_added := v_added + v_n;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('toolsets', 'search_pass_start', 'serper', jsonb_build_object('run_id', v_run, 'courses', v_added, 'reason', v_reason), auth.uid());
  perform pipeline.svc_pilot_submit_nonce('toolset-runner', jsonb_build_object('action', 'run', 'run_id', v_run));
  return jsonb_build_object('ok', true, 'run_id', v_run, 'courses', v_added);
end $f$;
revoke all on function public.admin_search_pass_start(text) from public, anon;
grant execute on function public.admin_search_pass_start(text) to authenticated;

-- The worker sends a found page into the identity check (service role). Candidates are the provider-site results that
-- passed the title match, best first. A confirmed page or a link entered by hand is never replaced.
create or replace function public.svc_search_pass_bind(p_item_id uuid) returns text
language plpgsql security definer set search_path = '' as $f$
declare v_i pipeline.toolset_sample_items%rowtype; v_c jsonb; v_url text; v_pg pipeline.coverage_course_pages%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_i from pipeline.toolset_sample_items where id = p_item_id;
  if v_i.id is null or v_i.course_id is null then return 'no_course'; end if;
  if not exists (select 1 from pipeline.toolset_sample_runs r where r.id = v_i.run_id and r.applies) then return 'not_a_pass'; end if;
  v_c := coalesce(v_i.result->'candidates', '[]'::jsonb);
  if jsonb_array_length(v_c) = 0 then return 'no_candidate'; end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = v_i.course_id and k.field = 'official_url') then return 'entered_by_hand'; end if;
  select * into v_pg from pipeline.coverage_course_pages where course_id = v_i.course_id;
  if v_pg.course_id is not null and v_pg.status = 'bound' and (v_pg.read_status = 'read' or v_pg.identity_basis is not null) then return 'already_confirmed'; end if;
  v_url := v_c->>0;
  if v_pg.course_id is not null and v_pg.url = v_url and v_pg.status = 'mismatch' then
    if jsonb_array_length(v_c) < 2 then return 'already_refused'; end if;
    v_url := v_c->>1;
  end if;
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason, run_id)
    values (v_i.course_id, v_i.provider_id, v_pg.url, v_url, case when (v_i.input->>'refind')::boolean then 'search pass: better page for an unreadable one' else 'search pass: page found' end, v_i.run_id);
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (v_i.course_id, v_i.provider_id, v_url, 'serper_search', 'bound', now(), now(), 0)
  on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(), score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now() where pipeline.coverage_course_pages.status <> 'bound' or (pipeline.coverage_course_pages.read_status in ('needs_render', 'blocked', 'fetch_failed') and pipeline.coverage_course_pages.evidence_id is null);
  insert into pipeline.search_pass_links(course_id, provider_id, run_id, candidates, cand_idx, bound_url, refind, state, updated_at)
    values (v_i.course_id, v_i.provider_id, v_i.run_id, v_c, case when v_url = v_c->>0 then 1 else 2 end, v_url, coalesce((v_i.input->>'refind')::boolean, false), 'found', now())
  on conflict (course_id) do update set run_id = excluded.run_id, candidates = excluded.candidates, cand_idx = excluded.cand_idx, bound_url = excluded.bound_url, refind = excluded.refind, state = 'found', updated_at = now();
  return 'bound';
end $f$;
revoke all on function public.svc_search_pass_bind(uuid) from public, anon, authenticated;
grant execute on function public.svc_search_pass_bind(uuid) to service_role;

-- After the reader: a confirmed page is verified, a refused or unreadable one moves to the next candidate or is left.
create or replace function security.search_pass_advance_v1() returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare r record; v_next text; n_ver int := 0; n_next int := 0; n_none int := 0;
begin
  update pipeline.search_pass_links l set state = 'verified', updated_at = now() from pipeline.coverage_course_pages p where l.state = 'found' and p.course_id = l.course_id and p.url = l.bound_url and p.status = 'bound' and p.identity_basis is not null;
  get diagnostics n_ver = row_count;
  for r in select l.*, p.status pstatus from pipeline.search_pass_links l join pipeline.coverage_course_pages p on p.course_id = l.course_id and p.url = l.bound_url
            where l.state = 'found' and (p.status = 'mismatch' or (p.read_status in ('fetch_failed', 'blocked', 'robots_disallowed') and (p.read_attempts >= 2 or p.http_status in (404, 410)))) loop
    if r.cand_idx < jsonb_array_length(r.candidates) then
      v_next := r.candidates->>r.cand_idx;
      insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason, run_id) values (r.course_id, r.provider_id, r.bound_url, v_next, 'search pass: next candidate after the reader refused the page', r.run_id);
      update pipeline.coverage_course_pages set url = v_next, basis = 'serper_search', status = 'bound', bound_at = now(), read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, read_attempts = 0, next_read_at = now(), leased_until = null where course_id = r.course_id and url = r.bound_url;
      update pipeline.search_pass_links set cand_idx = cand_idx + 1, bound_url = v_next, updated_at = now() where course_id = r.course_id;
      n_next := n_next + 1;
    else
      update pipeline.search_pass_links set state = 'none', updated_at = now() where course_id = r.course_id;
      n_none := n_none + 1;
    end if;
  end loop;
  return jsonb_build_object('verified', n_ver, 'next_candidate', n_next, 'none', n_none);
end $f$;
revoke all on function security.search_pass_advance_v1() from public, anon, authenticated;

-- Run inside the existing course-link-search job (every minute), so no new scheduled job is added (md5-guarded).
do $g$ declare v_oid oid := 'security.course_link_search_tick_v1(integer)'::regprocedure; v_def text; o text; c int;
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from '17cbb1540acdcdd9f01cd9a73e7ac79b' then raise exception 'course_link_search_tick_v1 changed, not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$  -- 3. Send the next batch, inside the monthly credit cap.$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'tick snippet found % times', c; end if;
  execute replace(v_def, o, $x$  -- 2c. Decision 252: pages from the Serper search pass, after the reader.
  perform security.search_pass_advance_v1();

$x$ || o);
end $g$;

-- The worker learns whether a run is a search pass (md5-guarded), and can carry on by itself after a time limit.
do $g$ declare v_oid oid := 'public.svc_toolset_sample_next(uuid,integer)'::regprocedure; v_def text; o text; c int;
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from 'eaac20b00a5b42d145ba5604ac084577' then raise exception 'svc_toolset_sample_next changed, not replacing'; end if;
  v_def := pg_get_functiondef(v_oid);
  o := $x$'purpose', v_r.purpose, 'settings', v_r.settings, 'plan', v_plan,$x$;
  c := (length(v_def) - length(replace(v_def, o, ''))) / length(o); if c <> 1 then raise exception 'next snippet found % times', c; end if;
  execute replace(v_def, o, $x$'purpose', v_r.purpose, 'applies', v_r.applies, 'settings', v_r.settings, 'plan', v_plan,$x$);
end $g$;

create or replace function public.svc_toolset_sample_continue(p_run_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r pipeline.toolset_sample_runs%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_r from pipeline.toolset_sample_runs where id = p_run_id;
  if v_r.id is null or not v_r.applies or v_r.status <> 'paused_time_limit' then return jsonb_build_object('continued', false); end if;
  if not coalesce((security.toolset_setting(v_r.toolset_key, 'pass_auto_continue') #>> '{}')::boolean, false) then return jsonb_build_object('continued', false, 'why', 'carry on is switched off'); end if;
  return jsonb_build_object('continued', true, 'request', pipeline.svc_pilot_submit_nonce('toolset-runner', jsonb_build_object('action', 'run', 'run_id', p_run_id)));
end $f$;
revoke all on function public.svc_toolset_sample_continue(uuid) from public, anon, authenticated;
grant execute on function public.svc_toolset_sample_continue(uuid) to service_role;

-- What the search pass and the repairs did (Toolsets and limits screen).
create or replace function public.admin_search_pass_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'status', r.status, 'status_note', r.status_note, 'credits_used', r.credits_used, 'created_at', r.created_at, 'reason', r.reason,
               'courses', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id), 'done', (select count(*) from pipeline.toolset_sample_items i where i.run_id = r.id and i.status = 'done')) order by r.created_at desc), '[]'::jsonb)
             from pipeline.toolset_sample_runs r where r.applies),
    'links', (select coalesce(jsonb_agg(jsonb_build_object('country', z.cc, 'refind', z.refind, 'state', z.state, 'n', z.n)), '[]'::jsonb)
              from (select k.iso_alpha2 cc, l.refind, l.state, count(*) n from pipeline.search_pass_links l join catalogue.providers p on p.id = l.provider_id join ref.countries k on k.id = p.country_id group by 1, 2, 3) z),
    'reading', (select coalesce(jsonb_agg(jsonb_build_object('read_status', z.rs, 'n', z.n)), '[]'::jsonb)
                from (select coalesce(p.read_status, 'waiting') rs, count(*) n from pipeline.search_pass_links l join pipeline.coverage_course_pages p on p.course_id = l.course_id and p.url = l.bound_url where l.state = 'found' group by 1) z),
    'repairs', (select coalesce(jsonb_agg(jsonb_build_object('reason', z.reason, 'n', z.n, 'last_at', z.last_at)), '[]'::jsonb)
                from (select reason, count(*) n, max(at) last_at from pipeline.page_link_repairs group by 1) z));
end $f$;
revoke all on function public.admin_search_pass_read() from public, anon;
grant execute on function public.admin_search_pass_read() to authenticated;
