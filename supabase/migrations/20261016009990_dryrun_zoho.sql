-- CF-247 (22 Oct 2026). Platform Admin 23:46: "Platform needs to independently read website. You are finding it for the platform and
-- reading it. I think adding new countries will have problems without you reading the website and courselinks. This is exactly where
-- we need to make the platform self sufficient. We should only be trying out what works and let platform execute it using toolset.
-- And leave all configurable and manageable from ui."
-- The course source finder does what was done by hand on 22 Oct (NZ, AU and CA course list pages, Université de Montréal):
-- 1 Worker mode source_find (job source-find) takes a university without a course source and:
--   a learns the address pattern of its course pages from the pages already found for it (the folder most of them share and their depth,
--      for example /study-with-us/levels-of-study/<3 parts> at RMIT); with too few pages found, the largest folder named like a course
--      folder (pipeline.source_find_paths kind folder_word: courses, programmes, programs, degrees, ...) in its site map;
--   b reads robots.txt and the site maps it names (or /sitemap.xml), following index files named like course files first;
--   c keeps a site map when enough of its addresses fit the pattern (source_find.min_links) and it holds enough of the pages already
--      found (source_find.min_recall);
--   d otherwise tries the course folder itself and the usual list addresses (pipeline.source_find_paths kind list_path) and keeps the
--      page with the most course links (the scraper only when the page is drawn by the browser, within the Firecrawl budget).
-- 2 public.svc_source_find_record keeps what was tried and why in pipeline.source_find_runs and adds the source:
--   a university with active courses gets a course list (pipeline.provider_course_lists, feeding the page matchers);
--   one with fewer active courses than source_find.programme_below gets a programme list (pipeline.programme_sources: courses are
--   created inactive and shown only after a person approves the list).
--   Nothing found: state none, with the reason, shown on the Work queues tab (queue source_find, Nothing left to try) and tried again
--   after source_find.retry_days.
-- 1e Platform Admin 23:53 "Can the providers course finder use the ai or firecrawl to fasten up the process ... we should toolset to maximise
--    and fasten the process": each site is first mapped with Firecrawl (one call, 1 credit, every address with its page title, sub-sites
--    included); a map that gives enough course addresses becomes the source (read_via map, read again by map). Site maps and list pages
--    are the fallbacks when the Firecrawl budget refuses or the map gives too few.
-- 3 Countries the finder works on: pipeline.source_find_countries (AU, NZ, CA). All of it is shown and changed on the Course sources screen.
-- Replaces: hand-found course list pages and programme sources (22 Oct 2026); those stay as the finder's test set.
-- read_via (map) on pipeline.provider_course_lists and pipeline.programme_sources; svc_course_list_next and svc_programme_source_next
--   return it (md5-guarded edits).
-- Retires: nothing

-- settings ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.source_find', 'Universities looked at per source finder run', 'Each run of the source-find job looks for the course source of this many universities.', 'number', to_jsonb(3), 1, 10, 'universities', 920, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'job source-find; coverage-sweep source_find'),
 ('pipeline', 'source_find.min_links', 'Course addresses a source must give', 'A site map or list page is kept only when at least this many of its addresses fit the course address pattern.', 'number', to_jsonb(20), 3, 500, 'addresses', 921, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'coverage-sweep source_find'),
 ('pipeline', 'source_find.min_recall', 'Known course pages a source must hold', 'A site map is kept only when it holds at least this share of the course pages already found for the university (when 3 or more are known).', 'number', to_jsonb(0.5), 0.1, 1, 'share', 922, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'coverage-sweep source_find'),
 ('pipeline', 'source_find.max_files', 'Site map files read per university', 'At most this many site map files are read for one university.', 'number', to_jsonb(25), 1, 100, 'files', 923, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'coverage-sweep source_find'),
 ('pipeline', 'source_find.max_locs', 'Site map addresses read per university', 'At most this many site map addresses are read for one university.', 'number', to_jsonb(60000), 1000, 500000, 'addresses', 924, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'coverage-sweep source_find'),
 ('pipeline', 'source_find.max_list_tries', 'List addresses tried per university', 'At most this many list page addresses are tried for one university when no site map fits.', 'number', to_jsonb(8), 1, 30, 'pages', 925, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'coverage-sweep source_find'),
 ('pipeline', 'source_find.retry_days', 'Source finder tries again after', 'A university where no course source was found is looked at again after this many days.', 'number', to_jsonb(14), 1, 180, 'days', 926, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'public.svc_source_find_record'),
 ('pipeline', 'source_find.page_share_below', 'Look for a source while course pages found are below', 'A university is looked at while the share of its active courses with a course page is below this.', 'number', to_jsonb(0.95), 0.1, 1, 'share', 927, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'public.svc_source_find_next'),
 ('pipeline', 'source_find.programme_below', 'Programme list when active courses are fewer than', 'A university with fewer active courses than this gets a programme list (courses created inactive, shown after approval) instead of a course list.', 'number', to_jsonb(1), 0, 1000, 'courses', 928, 'CF-247 22 Oct 2026 (course source finder)', 'Enrichment', 'public.svc_source_find_record')
on conflict do nothing;

-- tables -----------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.source_find_countries (
  country_code text primary key,
  enabled boolean not null default true,
  reason text not null,
  updated_at timestamptz not null default now()
);
comment on table pipeline.source_find_countries is 'CF-247 22 Oct 2026: countries the course source finder works on (Course sources screen).';
insert into pipeline.source_find_countries(country_code, reason) values
 ('AU', 'Platform Admin 22 Oct 2026 23:46: platform finds course sources itself'),
 ('NZ', 'Platform Admin 22 Oct 2026 23:46: platform finds course sources itself'),
 ('CA', 'Platform Admin 22 Oct 2026 23:46: platform finds course sources itself')
on conflict do nothing;

create table if not exists pipeline.source_find_paths (
  id bigserial primary key,
  kind text not null check (kind in ('list_path', 'folder_word')),
  value text not null,
  sort int not null default 100,
  enabled boolean not null default true,
  unique (kind, value)
);
comment on table pipeline.source_find_paths is 'CF-247 22 Oct 2026: what the course source finder tries: list_path, list page addresses tried on a university''s site (in sort order); folder_word, words a course folder or course site map file is named with (when too few course pages are known to learn the pattern).';
insert into pipeline.source_find_paths(kind, value, sort) values
 ('list_path', '/courses', 10), ('list_path', '/programmes', 20), ('list_path', '/programs', 30), ('list_path', '/study', 40),
 ('list_path', '/find-a-course', 50), ('list_path', '/study/courses', 60), ('list_path', '/degrees', 70), ('list_path', '/qualifications', 80),
 ('list_path', '/study/find-a-course', 90), ('list_path', '/course-search', 100), ('list_path', '/programmes-detudes', 110),
 ('folder_word', 'courses?', 10), ('folder_word', 'programmes?', 20), ('folder_word', 'programs?', 30), ('folder_word', 'degrees?', 40),
 ('folder_word', 'qualifications?', 50), ('folder_word', 'study-options', 60), ('folder_word', 'majors', 70), ('folder_word', 'programme-search', 80)
on conflict do nothing;

create table if not exists pipeline.source_find_runs (
  provider_id uuid primary key references catalogue.providers(id),
  state text not null check (state in ('leased', 'found', 'none', 'failed', 'tested')),
  tried_at timestamptz, next_try_at timestamptz, leased_until timestamptz,
  attempts int not null default 0,
  known int, pattern text, pattern_basis text,
  chosen jsonb, tried jsonb not null default '[]'::jsonb,
  reason text, added text, worker text
);
comment on table pipeline.source_find_runs is 'CF-247 22 Oct 2026: the course source finder''s last look at each university: the pattern it learnt, every site map and list page it tried with its counts, what it chose and what it added (course list or programme list), or why nothing was found. state tested: a test run that added nothing.';

-- service functions ------------------------------------------------------------------------------------------------------------------
create or replace function public.svc_source_find_next(p_limit integer default 3, p_provider_ids uuid[] default null)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v jsonb; v_share numeric := security.pipeline_num_v1('source_find.page_share_below', 0.95);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  create temp table if not exists _sf_pick(provider_id uuid) on commit drop; truncate _sf_pick;
  if p_provider_ids is not null then
    insert into _sf_pick select unnest(p_provider_ids) limit 20;  -- fixed: a test run looks at a handful of universities
  else
    insert into _sf_pick
    with cand as (
      select p.id, (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') active,
             (select count(*) from catalogue.courses c join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.status = 'bound' and pg.read_status = 'read'
               where c.provider_id = p.id and c.lifecycle_status = 'active') paged,
             (select count(*) from catalogue.courses c where c.provider_id = p.id) all_courses
        from catalogue.providers p
       where p.enrols_international is true and coalesce(p.lifecycle_status, 'active') = 'active' and p.website is not null
         and security.coverage_country(p.id) in (select x.country_code from pipeline.source_find_countries x where x.enabled)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
         and not exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p.id and l.status <> 'stopped')
         and not exists (select 1 from pipeline.programme_sources s where s.provider_id = p.id and s.status <> 'stopped')
         and not exists (select 1 from pipeline.source_find_runs r where r.provider_id = p.id
                           and (r.state in ('found', 'tested') or coalesce(r.next_try_at, now()) > now() or coalesce(r.leased_until, '-infinity') > now())))
    select c.id from cand c
     where c.all_courses > 0 and (c.active = 0 or c.paged::numeric / c.active < v_share)
     order by (c.active - c.paged) desc, c.all_courses desc
     limit greatest(1, least(coalesce(p_limit, 3), 10));  -- fixed: per-call safety cap; the run size is batch.source_find
  end if;
  insert into pipeline.source_find_runs as r (provider_id, state, leased_until, attempts)
  select provider_id, 'leased', now() + interval '10 minutes', 1 from _sf_pick  -- fixed: lease for one call
  on conflict (provider_id) do update set state = 'leased', leased_until = excluded.leased_until, attempts = r.attempts + 1;
  select jsonb_build_object(
    'items', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', p.id, 'name', p.display_name, 'website', p.website,
                'known', (select coalesce(jsonb_agg(u), '[]'::jsonb) from (
                           select distinct pg.url u from pipeline.coverage_course_pages pg where pg.provider_id = p.id and pg.status = 'bound' and pg.read_status = 'read' and pg.url is not null
                           union select distinct c.course_url from catalogue.courses c where c.provider_id = p.id and c.course_url ~* '^https?://' and c.lifecycle_status = 'active'
                           limit 400) k))), '[]'::jsonb)  -- fixed: a sample of known course pages is enough to learn the pattern
                from _sf_pick x join catalogue.providers p on p.id = x.provider_id),
    'list_paths', (select coalesce(jsonb_agg(s.value order by s.sort), '[]'::jsonb) from pipeline.source_find_paths s where s.kind = 'list_path' and s.enabled),
    'folder_words', (select coalesce(jsonb_agg(s.value order by s.sort), '[]'::jsonb) from pipeline.source_find_paths s where s.kind = 'folder_word' and s.enabled),
    'settings', jsonb_build_object('min_links', security.pipeline_num_v1('source_find.min_links', 20), 'min_recall', security.pipeline_num_v1('source_find.min_recall', 0.5),
                'max_files', security.pipeline_num_v1('source_find.max_files', 25), 'max_locs', security.pipeline_num_v1('source_find.max_locs', 60000),
                'max_list_tries', security.pipeline_num_v1('source_find.max_list_tries', 8)))
    into v;
  return v;
end $function$;
revoke all on function public.svc_source_find_next(integer, uuid[]) from public, anon, authenticated;
grant execute on function public.svc_source_find_next(integer, uuid[]) to service_role;

create or replace function public.svc_source_find_record(p_provider_id uuid, p_result jsonb, p_test boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_ch jsonb := p_result->'chosen'; v_active int; v_added text; v_state text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select count(*) into v_active from catalogue.courses c where c.provider_id = p_provider_id and c.lifecycle_status = 'active';
  if jsonb_typeof(v_ch) = 'object' and v_ch->>'url' ~* '^https?://' then
    v_state := case when p_test then 'tested' else 'found' end;
    if not p_test then
      if v_active < security.pipeline_num_v1('source_find.programme_below', 1) then
        insert into pipeline.programme_sources(provider_id, url, kind, url_pattern, child_pattern, read_via, reason)
        values (p_provider_id, v_ch->>'url', case when v_ch->>'kind' = 'list' then 'list' else 'sitemap' end, coalesce(v_ch->>'link_pattern', p_result->>'pattern'), v_ch->>'child_pattern',
                case when v_ch->>'kind' = 'map' then 'map' end,
                'Found by the course source finder (' || coalesce(v_ch->>'matches', '?') || ' programme addresses)')
        on conflict (provider_id, url) do nothing;
        v_added := 'programme_list';
      else
        insert into pipeline.provider_course_lists(provider_id, url, reason, added_by, link_pattern, child_pattern, read_via)
        values (p_provider_id, v_ch->>'url', 'Found by the course source finder (' || coalesce(v_ch->>'matches', '?') || ' course addresses)', null,
                case when v_ch->>'kind' in ('sitemap', 'map') then coalesce(v_ch->>'link_pattern', p_result->>'pattern') end, case when v_ch->>'kind' = 'sitemap' then v_ch->>'child_pattern' end,
                case when v_ch->>'kind' = 'map' then 'map' end)
        on conflict (provider_id, url) do nothing;
        v_added := 'course_list';
      end if;
    end if;
  else
    v_state := case when p_result->>'error' is not null then 'failed' else 'none' end;
  end if;
  insert into pipeline.source_find_runs as r (provider_id, state, tried_at, next_try_at, leased_until, known, pattern, pattern_basis, chosen, tried, reason, added, worker)
  values (p_provider_id, v_state, now(),
          case when v_state in ('none', 'failed') then now() + make_interval(days => security.pipeline_num_v1('source_find.retry_days', 14)::int) end, null,
          (p_result->>'known')::int, left(p_result->>'pattern', 500), p_result->>'pattern_basis', v_ch, coalesce(p_result->'tried', '[]'::jsonb),
          left(coalesce(p_result->>'reason', p_result->>'error'), 500), v_added, p_result->>'worker')
  on conflict (provider_id) do update set state = excluded.state, tried_at = excluded.tried_at, next_try_at = excluded.next_try_at, leased_until = null,
         known = excluded.known, pattern = excluded.pattern, pattern_basis = excluded.pattern_basis, chosen = excluded.chosen, tried = excluded.tried,
         reason = excluded.reason, added = excluded.added, worker = excluded.worker;
  return jsonb_build_object('state', v_state, 'added', v_added);
end $function$;
revoke all on function public.svc_source_find_record(uuid, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.svc_source_find_record(uuid, jsonb, boolean) to service_role;

-- read by Firecrawl map ----------------------------------------------------------------------------------------------------------------
alter table pipeline.provider_course_lists add column if not exists read_via text;
alter table pipeline.programme_sources add column if not exists read_via text;
comment on column pipeline.provider_course_lists.read_via is 'CF-247 22 Oct 2026: map = the site is listed by a Firecrawl map of url (1 credit) and the addresses fitting link_pattern are kept; null = read as a page or site map.';
comment on column pipeline.programme_sources.read_via is 'CF-247 22 Oct 2026: map = the site is listed by a Firecrawl map of url (1 credit) and the addresses fitting url_pattern are kept; null = read by kind.';
do $do$
declare v_def text := pg_get_functiondef('public.svc_course_list_next'::regproc);
  v_old text := $o$'link_pattern', u.link_pattern, 'child_pattern', u.child_pattern)$o$;
  v_new text := $n$'link_pattern', u.link_pattern, 'child_pattern', u.child_pattern, 'read_via', u.read_via)$n$;
begin
  if md5(v_def) <> 'c5ae4d50b84cd36ea5eca5936aa4cf48' then raise exception 'public.svc_course_list_next is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'course list next: expected one link_pattern'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;
do $do$
declare v_def text := pg_get_functiondef('public.svc_programme_source_next'::regproc);
  v_old text := $o$'child_pattern', u.child_pattern, $o$;
  v_new text := $n$'child_pattern', u.child_pattern, 'read_via', u.read_via, $n$;
begin
  if md5(v_def) <> '14f671b5c9aa6da5d2fbb4d03e9b06b4' then raise exception 'public.svc_programme_source_next is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'programme source next: expected one child_pattern'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

-- Course sources screen --------------------------------------------------------------------------------------------------------------
create or replace function public.admin_course_sources(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_rank int := security.current_role_rank(); v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := nullif(btrim(p_args->>'reason'), ''); v_n int;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'list' then
    return jsonb_build_object(
      'countries', (select coalesce(jsonb_agg(to_jsonb(c) order by c.country_code), '[]'::jsonb) from pipeline.source_find_countries c),
      'paths', (select coalesce(jsonb_agg(to_jsonb(s) order by s.kind, s.sort), '[]'::jsonb) from pipeline.source_find_paths s),
      'providers', (select coalesce(jsonb_agg(z order by z->>'country', z->>'name'), '[]'::jsonb) from (
         select jsonb_build_object('provider_id', p.id, 'name', p.display_name, 'country', security.coverage_country(p.id), 'website', p.website,
                  'finder', (select to_jsonb(r) - 'provider_id' from pipeline.source_find_runs r where r.provider_id = p.id),
                  'lists', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'status', l.status, 'links', l.links_found, 'new', l.links_new, 'read_at', l.read_at,
                              'via', l.fetched_via, 'pattern', l.link_pattern, 'read_via', l.read_via, 'by_finder', l.reason like 'Found by the course source finder%')), '[]'::jsonb) from pipeline.provider_course_lists l where l.provider_id = p.id),
                  'programmes', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'url', s.url, 'kind', s.kind, 'status', s.status, 'found', s.found, 'pattern', s.url_pattern, 'read_via', s.read_via,
                              'approved_at', s.approved_at, 'states', (select coalesce(jsonb_object_agg(q.state, q.n), '{}'::jsonb) from (select c.state, count(*) n from pipeline.programme_candidates c where c.programme_source_id = s.id group by 1) q))), '[]'::jsonb)
                              from pipeline.programme_sources s where s.provider_id = p.id)) z
           from catalogue.providers p
          where exists (select 1 from pipeline.source_find_runs r where r.provider_id = p.id)
             or exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p.id)
             or exists (select 1 from pipeline.programme_sources s where s.provider_id = p.id)) x(z)));
  end if;
  if v_rank < 4 then raise exception 'Pipeline operator role or above required' using errcode = '42501'; end if;
  if v_reason is null then raise exception 'A reason is required'; end if;
  if p_action = 'find_again' then
    update pipeline.source_find_runs set next_try_at = now(), state = case when state in ('found', 'tested') then 'none' else state end where provider_id = v_pid;
    insert into pipeline.source_find_runs(provider_id, state, next_try_at) values (v_pid, 'none', now()) on conflict (provider_id) do nothing;
  elsif p_action = 'stop_list' then
    update pipeline.provider_course_lists set status = 'stopped', next_read_at = 'infinity', updated_at = now() where id = (p_args->>'id')::uuid;
  elsif p_action = 'stop_programme' then
    update pipeline.programme_sources set status = 'stopped', next_read_at = 'infinity', updated_at = now() where id = (p_args->>'id')::bigint;
  elsif p_action = 'add_list' then
    insert into pipeline.provider_course_lists(provider_id, url, reason, added_by, link_pattern, child_pattern, read_via)
    values (v_pid, p_args->>'url', v_reason, auth.uid(), nullif(p_args->>'link_pattern', ''), nullif(p_args->>'child_pattern', ''), nullif(p_args->>'read_via', ''))
    on conflict (provider_id, url) do update set status = 'due', next_read_at = now(), link_pattern = excluded.link_pattern, child_pattern = excluded.child_pattern, read_via = excluded.read_via, updated_at = now();
  elsif p_action = 'add_programme' then
    insert into pipeline.programme_sources(provider_id, url, kind, url_pattern, child_pattern, read_via, reason, added_by)
    values (v_pid, p_args->>'url', coalesce(nullif(p_args->>'kind', ''), 'sitemap'), p_args->>'url_pattern', nullif(p_args->>'child_pattern', ''), nullif(p_args->>'read_via', ''), v_reason, auth.uid())
    on conflict (provider_id, url) do update set status = 'due', next_read_at = now(), url_pattern = excluded.url_pattern, child_pattern = excluded.child_pattern, read_via = excluded.read_via, updated_at = now();
  elsif p_action = 'approve_programme' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    update pipeline.programme_sources set approved_at = now(), approved_by = auth.uid(), approved_reason = v_reason, updated_at = now() where provider_id = v_pid and approved_at is null;
  elsif p_action = 'country' then
    insert into pipeline.source_find_countries(country_code, enabled, reason) values (upper(p_args->>'country'), coalesce((p_args->>'enabled')::boolean, true), v_reason)
    on conflict (country_code) do update set enabled = excluded.enabled, reason = excluded.reason, updated_at = now();
  elsif p_action = 'path' then
    insert into pipeline.source_find_paths(kind, value, sort, enabled) values (p_args->>'kind', p_args->>'value', coalesce((p_args->>'sort')::int, 100), coalesce((p_args->>'enabled')::boolean, true))
    on conflict (kind, value) do update set enabled = excluded.enabled, sort = excluded.sort;
  else
    raise exception 'unknown action %', p_action;
  end if;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor) values ('course_sources', p_action, coalesce(v_pid::text, p_args->>'id', p_args->>'country', p_args->>'value'), p_args, auth.uid());
  return jsonb_build_object('ok', true, 'rows', v_n);
end $function$;
revoke all on function public.admin_course_sources(text, jsonb) from public, anon;
grant execute on function public.admin_course_sources(text, jsonb) to authenticated;

-- watchdog, job ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.queue_watch(key, label, area, purpose, jobnames, tools, pending_sql, progress_sql, done_sql, failed_sql, exhausted_sql, exhausted_label, fix_at, sort) values
('source_find', 'Course source finder', 'Enrichment', 'Finds each university''s own course site map or list page by itself (no person needed).',
 '{source-find}', '{}',
 $q$select count(*) from catalogue.providers p where p.enrols_international is true and coalesce(p.lifecycle_status, 'active') = 'active' and p.website is not null and security.coverage_country(p.id) in (select x.country_code from pipeline.source_find_countries x where x.enabled) and exists (select 1 from catalogue.courses c where c.provider_id = p.id) and not exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p.id and l.status <> 'stopped') and not exists (select 1 from pipeline.programme_sources s where s.provider_id = p.id and s.status <> 'stopped') and not exists (select 1 from pipeline.source_find_runs r where r.provider_id = p.id and (r.state in ('found', 'tested') or coalesce(r.next_try_at, now()) > now()))$q$,
 $q$select max(tried_at) from pipeline.source_find_runs$q$,
 $q$select count(*) from pipeline.source_find_runs where tried_at >= $1 and state in ('found', 'none', 'tested')$q$,
 $q$select count(*) from pipeline.source_find_runs where tried_at >= $1 and state = 'failed'$q$,
 $q$select count(*) from pipeline.source_find_runs where state = 'none'$q$,
 'Universities where no course source was found (Course sources screen)', '#layer-2-discovery?tab=sources', 170)
on conflict (key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('source-find', 'Enrichment', 55, 'Course source finder', 'Every 20 minutes while universities wait: learns the address pattern of a university''s course pages and finds its own course site map or list page (robots.txt, site maps, the usual list addresses in pipeline.source_find_paths); adds it as a course list, or as a programme list (inactive until approved) for a university with no active courses; or records why nothing was found. Run size batch.source_find.', 4, true, 'pages')
on conflict (jobname) do nothing;

select cron.schedule('source-find', '16-59/20 * * * *',
  $c$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'source_find', 'limit', security.pipeline_num_v1('batch.source_find', 3)::int)) where exists (select 1 from pipeline.queue_watch_state s where s.key = 'source_find' and s.pending > 0) or not exists (select 1 from pipeline.queue_watch_state s where s.key = 'source_find')$c$);
-- off until its test run against the hand-found sources is checked (a passing check never switches anything on by itself)
select cron.alter_job((select jobid from cron.job where jobname = 'source-find'), active := false);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.source_find_countries', 'Layer 1', 'Countries the course source finder works on', 'active', '{}', '20261022044000'),
 ('table', 'pipeline.source_find_paths', 'Layer 1', 'List addresses and folder words the source finder tries', 'active', '{}', '20261022044000'),
 ('table', 'pipeline.source_find_runs', 'Layer 1', 'The source finder''s last look at each university', 'active', '{}', '20261022044000'),
 ('function', 'public.svc_source_find_next', 'Layer 1', 'Universities due for the source finder', 'active', '{}', '20261022044000'),
 ('function', 'public.svc_source_find_record', 'Layer 1', 'Records what the source finder tried and adds the source', 'active', '{}', '20261022044000'),
 ('function', 'public.admin_course_sources', 'Platform', 'Course sources screen', 'active', '{}', '20261022044000'),
 ('job', 'source-find', 'Layer 1', 'Course source finder', 'active', '{}', '20261022044000')
on conflict (kind, name) do nothing;

select 'course source finder ready' ok;

do $t$ declare v jsonb; begin
  v := public.svc_source_find_next(3, null);
  raise exception 'DRYRUN OK %', jsonb_build_object('picked', (select jsonb_agg(x->>'name') from jsonb_array_elements(v->'items') x),
    'known', (select jsonb_agg(jsonb_array_length(x->'known')) from jsonb_array_elements(v->'items') x), 'paths', jsonb_array_length(v->'list_paths'), 'settings', v->'settings',
    'job_active', (select active from cron.job where jobname = 'source-find'), 'list_fn_ok', (select count(*) from pipeline.queue_watch where key = 'source_find')); end $t$;
