-- CF-247 course link recipes (Platform Admin, 1 Oct 2026 00:39 AEST): "First find the further information from vtac
-- website for top 10 universities and create the same strategy and go ahead for firecrawl for further link fetching."
--
-- Finding: VTAC's "Further information" link for Monash is the university's own course page, built from the Monash course
-- code (https://www.monash.edu/study/course/B2029). VTAC's robots.txt disallows all automated access (User-agent: * /
-- Disallow: /), and VTAC lists only Victorian undergraduate entry, so VTAC is not crawled. The same result comes from the
-- universities' own sites: a Firecrawl search for the CRICOS code on the university's domain returns the course page or
-- its handbook entry, and each university has a stable address pattern for both.
--
-- 1. pipeline.course_link_recipes: per university, the domain to search and the ordered address patterns that count as
--    an official course page (marketing page first, handbook second). {year} in a replacement is the current year, so
--    an old handbook hit is moved to this year's edition. Editable data, not code.
-- 2. pipeline.course_link_search: one row per course being looked for. Stage 1 searches "<CRICOS>" on the domain;
--    stage 2 (no usable hit) searches the exact course title. Hits are bound to pipeline.coverage_course_pages with
--    basis cricos_search / title_search; the page reader then confirms identity (CRICOS code or exact title on the page)
--    before anything is admitted. A page that fails the check moves to the next candidate.
-- 3. security.course_link_search_tick_v1(batch): collects finished searches, binds, moves failures on, sends the next
--    batch. Stops at the monthly credit cap in pipeline.course_link_search_settings. Scheduled every minute.
-- 4. security.coverage_bind_v2 no longer overwrites or releases pages bound by the link search (md5-guarded edit).
-- Courses with no page after both stages stay state 'none' for the Layer 4 "Course page needed" queue (Decision 179).

create table if not exists pipeline.course_link_recipes (
  provider_id uuid primary key references catalogue.providers(id),
  search_domain text not null,
  patterns jsonb not null,
  active boolean not null default true,
  notes text,
  updated_at timestamptz not null default now(),
  updated_by uuid);
alter table pipeline.course_link_recipes enable row level security;
revoke all on pipeline.course_link_recipes from public, anon, authenticated;

create table if not exists pipeline.course_link_search_settings (
  id int primary key default 1 check (id=1),
  enabled boolean not null default true,
  monthly_credit_cap numeric not null default 15000,
  updated_at timestamptz not null default now(),
  updated_by uuid);
alter table pipeline.course_link_search_settings enable row level security;
revoke all on pipeline.course_link_search_settings from public, anon, authenticated;
insert into pipeline.course_link_search_settings(id) values (1) on conflict do nothing;

create table if not exists pipeline.course_link_search (
  course_id uuid primary key references catalogue.courses(id),
  provider_id uuid not null,
  stage text not null default 'cricos' check (stage in ('cricos','title')),
  state text not null default 'queued' check (state in ('queued','sent','found','none','error','verified')),
  query text,
  req_id bigint,
  attempts int not null default 0,
  results jsonb,
  candidates jsonb,
  cand_idx int not null default 0,
  bound_url text,
  queued_at timestamptz not null default now(),
  sent_at timestamptz,
  done_at timestamptz);
create index if not exists course_link_search_state_idx on pipeline.course_link_search(state, provider_id);
alter table pipeline.course_link_search enable row level security;
revoke all on pipeline.course_link_search from public, anon, authenticated;

insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, notes) values
 ('22657140-1cb0-4fa7-91df-90518ea8b35b','unsw.edu.au','[
   {"re":"^https?://(www\\.)?unsw\\.edu\\.au/study/(undergraduate|postgraduate)/([a-z0-9-]+)/?$","rep":"https://www.unsw.edu.au/study/\\2/\\3"},
   {"re":"^https?://(www\\.)?handbook\\.unsw\\.edu\\.au/(undergraduate|postgraduate|research)/programs/[0-9]{4}/([0-9]{4})$","rep":"https://www.handbook.unsw.edu.au/\\2/programs/{year}/\\3"}]','UNSW: study page, else handbook program'),
 ('68022bdf-43e8-44b3-ac14-e9eed9f71e83','sydney.edu.au','[
   {"re":"^https?://(www\\.)?sydney\\.edu\\.au/courses/courses/(uc|pc|pr)/([a-z0-9-]+)\\.html$","rep":"https://www.sydney.edu.au/courses/courses/\\2/\\3.html"}]','Sydney: courses page'),
 ('543b87b8-f0dd-4bc7-80d6-76252cfaabec','monash.edu','[
   {"re":"^https?://(www\\.)?monash\\.edu/study/course/([A-Za-z][0-9]{4})$","rep":"https://www.monash.edu/study/course/\\2?international=true"},
   {"re":"^https?://handbook\\.monash\\.edu/[^/]+/courses/([A-Za-z][0-9]{4})$","rep":"https://www.monash.edu/study/course/\\1?international=true"},
   {"re":"^https?://www3\\.monash\\.edu/pubs/.*/([A-Za-z][0-9]{4})\\.html$","rep":"https://www.monash.edu/study/course/\\1?international=true"}]','Monash: VTAC "Further information" pattern, /study/course/<code>, from the code in handbook or pubs results'),
 ('9d22a19e-c3f7-4012-b738-17bc0b481e7f','uts.edu.au','[
   {"re":"^https?://(www\\.)?uts\\.edu\\.au/courses/([a-z0-9-]+)/?$","rep":"https://www.uts.edu.au/courses/\\2"},
   {"re":"^https?://coursehandbook\\.uts\\.edu\\.au/course/[0-9]{4}/([A-Za-z][0-9]+)$","rep":"https://coursehandbook.uts.edu.au/course/{year}/\\1"}]','UTS: course page, else handbook'),
 ('8e1adb6c-e069-43db-9584-bd054255e702','rmit.edu.au','[
   {"re":"^https?://(www\\.)?rmit\\.edu\\.au/(study-with-us/levels-of-study/.+-[a-z]{1,3}[0-9]{3})(/.*)?$","rep":"https://www.rmit.edu.au/\\2"}]','RMIT: level-of-study page ending in the program code'),
 ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0','adelaideuni.edu.au','[
   {"re":"^https?://(www\\.)?adelaideuni\\.edu\\.au/study/degrees/([a-z0-9-]+)/?$","rep":"https://adelaideuni.edu.au/study/degrees/\\2/"}]','Adelaide University: degree page'),
 ('0a42da16-8df1-4439-a929-4dfdd04b6d83','flinders.edu.au','[
   {"re":"^https?://(www\\.)?flinders\\.edu\\.au/study/courses/([a-z0-9-]+)/?$","rep":"https://www.flinders.edu.au/study/courses/\\2"},
   {"re":"^https?://handbook\\.flinders\\.edu\\.au/courses/[0-9]{4}/([A-Za-z0-9]+)$","rep":"https://handbook.flinders.edu.au/courses/{year}/\\1"}]','Flinders: course page, else handbook'),
 ('188103a5-1aba-4f99-bd3e-0416659086d3','mq.edu.au','[
   {"re":"^https?://(www\\.)?mq\\.edu\\.au/study/find-a-course/courses/([a-z0-9-]+)/?$","rep":"https://www.mq.edu.au/study/find-a-course/courses/\\2"},
   {"re":"^https?://coursehandbook\\.mq\\.edu\\.au/[0-9]{4}/(courses|doubledegree)/([A-Za-z][0-9]+)$","rep":"https://coursehandbook.mq.edu.au/{year}/\\1/\\2"}]','Macquarie: course page, else handbook'),
 ('1822b40a-8b13-44dc-8c37-106ae31bb447','newcastle.edu.au','[
   {"re":"^https?://(www\\.)?newcastle\\.edu\\.au/degrees/([a-z0-9/-]+?)/?$","rep":"https://www.newcastle.edu.au/degrees/\\2"},
   {"re":"^https?://handbook\\.newcastle\\.edu\\.au/program/[0-9]{4}/([0-9]+)$","rep":"https://handbook.newcastle.edu.au/program/{year}/\\1"}]','Newcastle: degree page, else handbook program'),
 ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2','unimelb.edu.au','[
   {"re":"^https?://study\\.unimelb\\.edu\\.au/find/courses/(undergraduate|graduate|honours)/([a-z0-9-]+)/?$","rep":"https://study.unimelb.edu.au/find/courses/\\1/\\2/"},
   {"re":"^https?://handbook\\.unimelb\\.edu\\.au/[0-9]{4}/courses/([a-z0-9-]+)$","rep":"https://handbook.unimelb.edu.au/{year}/courses/\\1"}]','Melbourne: study site, else handbook')
on conflict (provider_id) do nothing;

-- Ordered, de-duplicated official candidates from a list of search result addresses.
create or replace function security.course_link_pick_v1(p_provider_id uuid, p_urls text[])
returns text[] language sql stable set search_path = '' as $$
  with pat as (select ord, e->>'re' re, replace(e->>'rep','{year}',extract(year from now())::int::text) rep
                 from pipeline.course_link_recipes r, jsonb_array_elements(r.patterns) with ordinality x(e, ord)
                where r.provider_id = p_provider_id and r.active),
       u as (select regexp_replace(url, '[?#].*$', '') url, i from unnest(p_urls) with ordinality y(url, i) where url is not null),
       m as (select pat.ord, u.i, regexp_replace(u.url, pat.re, pat.rep) cand from pat join u on u.url ~ pat.re),
       d as (select cand, min(ord*1000+i) k from m group by cand)
  select coalesce(array_agg(cand order by k), '{}') from d
$$;
revoke all on function security.course_link_pick_v1(uuid, text[]) from public, anon, authenticated;

-- Queue courses of providers with an active recipe that have no confirmed page.
create or replace function security.course_link_search_enqueue_v1(p_provider_id uuid default null)
returns int language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  insert into pipeline.course_link_search(course_id, provider_id)
  select c.id, c.provider_id
    from catalogue.courses c join pipeline.course_link_recipes r on r.provider_id = c.provider_id and r.active
    left join pipeline.coverage_course_pages p on p.course_id = c.id
   where c.lifecycle_status = 'active' and c.course_code ~ '^[0-9]{6}[0-9A-Z]$'
     and (p_provider_id is null or c.provider_id = p_provider_id)
     and (p.course_id is null or p.status = 'mismatch' or (p.status = 'ambiguous' and p.read_status is not null))
  on conflict (course_id) do nothing;
  get diagnostics v = row_count;
  return v;
end $$;
revoke all on function security.course_link_search_enqueue_v1(uuid) from public, anon, authenticated;

create or replace function security.course_link_bind_v1(p_course_id uuid, p_provider_id uuid, p_url text, p_basis text)
returns void language sql security definer set search_path = '' as $$
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
  values (p_course_id, p_provider_id, p_url, p_basis, 'bound', now(), now(), 0)
  on conflict (course_id) do update set url = excluded.url, basis = excluded.basis, status = 'bound', bound_at = now(),
         score = null, runner_up = null, read_status = null, read_at = null, http_status = null, fetched_via = null,
         identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now()
   where pipeline.coverage_course_pages.status <> 'bound' or pipeline.coverage_course_pages.basis in ('cricos_search','title_search');
$$;
revoke all on function security.course_link_bind_v1(uuid, uuid, text, text) from public, anon, authenticated;

create or replace function security.course_link_search_tick_v1(p_batch int default 40)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; v_urls text[]; v_c text[]; v_cap numeric; v_on boolean; v_used numeric; v_key text; v_dom text;
        n_harvest int := 0; n_found int := 0; n_moved int := 0; n_sent int := 0; v_next text;
begin
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;

  -- 1. Collect finished searches.
  for r in select s.*, h.status_code, h.content from pipeline.course_link_search s join net._http_response h on h.id = s.req_id
            where s.state = 'sent' loop
    n_harvest := n_harvest + 1;
    if r.status_code = 200 and left(r.content, 1) = '{' then
      perform public.svc_coverage_usage(2, 'course_link_search', r.provider_id, r.query);
      v_urls := array(select e->>'url' from jsonb_array_elements(coalesce((r.content::jsonb)->'data', '[]'::jsonb)) e);
      v_c := security.course_link_pick_v1(r.provider_id, v_urls);
      if cardinality(v_c) > 0 then
        update pipeline.course_link_search set state = 'found', results = to_jsonb(v_urls), candidates = to_jsonb(v_c), cand_idx = 1,
               bound_url = v_c[1], done_at = now() where course_id = r.course_id;
        perform security.course_link_bind_v1(r.course_id, r.provider_id, v_c[1], case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
        n_found := n_found + 1;
      elsif r.stage = 'cricos' then
        update pipeline.course_link_search set stage = 'title', state = 'queued', results = to_jsonb(v_urls), attempts = 0 where course_id = r.course_id;
      else
        update pipeline.course_link_search set state = 'none', results = to_jsonb(v_urls), done_at = now() where course_id = r.course_id;
      end if;
    else
      update pipeline.course_link_search set attempts = attempts + 1, state = case when attempts + 1 >= 3 then 'error' else 'queued' end,
             results = jsonb_build_object('http_status', r.status_code, 'body', left(r.content, 300)) where course_id = r.course_id;
    end if;
  end loop;
  -- searches with no response after 20 minutes are sent again
  update pipeline.course_link_search set state = 'queued', attempts = attempts + 1
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);

  -- 2. Pages the reader could not confirm move to the next candidate, then to the title search.
  for r in select s.*, p.status pstatus, p.read_status, p.read_attempts from pipeline.course_link_search s
             join pipeline.coverage_course_pages p on p.course_id = s.course_id and p.url = s.bound_url
            where s.state = 'found' and (p.status = 'mismatch' or (p.read_status in ('fetch_failed','blocked','robots_disallowed') and p.read_attempts >= 2)) loop
    if r.cand_idx < jsonb_array_length(r.candidates) then
      v_next := r.candidates->>r.cand_idx;
      update pipeline.course_link_search set cand_idx = cand_idx + 1, bound_url = v_next where course_id = r.course_id;
      perform security.course_link_bind_v1(r.course_id, r.provider_id, v_next, case r.stage when 'cricos' then 'cricos_search' else 'title_search' end);
    elsif r.stage = 'cricos' then
      update pipeline.course_link_search set stage = 'title', state = 'queued', attempts = 0, done_at = null where course_id = r.course_id;
    else
      update pipeline.course_link_search set state = 'none', done_at = now() where course_id = r.course_id;
    end if;
    n_moved := n_moved + 1;
  end loop;
  update pipeline.course_link_search s set state = 'verified' from pipeline.coverage_course_pages p
   where s.state = 'found' and p.course_id = s.course_id and p.url = s.bound_url and p.status = 'bound' and p.identity_basis is not null;

  -- 3. Send the next batch, inside the monthly credit cap.
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if v_on and v_used + 2 * p_batch <= v_cap then
    v_key := public.svc_coverage_firecrawl()->>'secret';
    if v_key is not null then
      for r in select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
                 from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
                 join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
                 left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
                where s.state = 'queued' order by (s.stage <> 'cricos'), coalesce(pp.rank, 100000), md5(s.course_id::text)
                limit greatest(1, least(coalesce(p_batch, 40), 100)) loop
        v_dom := case r.stage when 'cricos' then '"' || r.course_code || '" site:' || r.search_domain
                                         else '"' || replace(r.canonical_title, '"', '') || '" site:' || r.search_domain end;
        update pipeline.course_link_search set state = 'sent', sent_at = now(), query = v_dom,
               req_id = net.http_post(url := 'https://api.firecrawl.dev/v1/search',
                          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
                          body := jsonb_build_object('query', v_dom, 'limit', 5), timeout_milliseconds := 60000)
         where course_id = r.course_id;
        n_sent := n_sent + 1;
      end loop;
    end if;
  end if;
  return jsonb_build_object('collected', n_harvest, 'found', n_found, 'moved_on', n_moved, 'sent', n_sent, 'credits_this_month', v_used, 'cap', v_cap);
end $$;
revoke all on function security.course_link_search_tick_v1(int) from public, anon, authenticated;

-- Pages bound by the link search are left alone by the discovery matcher (md5-guarded in-place edit).
do $$
declare v_src text; v_def text; v_old1 text; v_new1 text; v_old2 text; v_new2 text;
begin
  select prosrc, pg_get_functiondef(oid) into v_src, v_def from pg_proc where oid = 'security.coverage_bind_v2(uuid)'::regprocedure;
  if md5(v_src) <> 'af9c56e33ca2edaca284d52ed003657f' then raise exception 'coverage_bind_v2 changed (md5 %)', md5(v_src); end if;
  v_old1 := $x$   where pipeline.coverage_course_pages.status not in ('mismatch') or pipeline.coverage_course_pages.url is distinct from excluded.url;$x$;
  v_new1 := $x$   where (pipeline.coverage_course_pages.status not in ('mismatch') or pipeline.coverage_course_pages.url is distinct from excluded.url)
     and coalesce(pipeline.coverage_course_pages.basis,'') not in ('cricos_search','title_search');$x$;
  v_old2 := $x$   where p.provider_id=p_provider_id and p.status='bound'
     and not exists$x$;
  v_new2 := $x$   where p.provider_id=p_provider_id and p.status='bound' and coalesce(p.basis,'') not in ('cricos_search','title_search')
     and not exists$x$;
  if position(v_old1 in v_def) = 0 or position(v_old2 in v_def) = 0 then raise exception 'coverage_bind_v2 anchor not found'; end if;
  execute replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
end $$;

select security.course_link_search_enqueue_v1();

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('course-link-search', 'Course pages', 35, 'Find course pages by CRICOS code',
  'Searches each university''s own site for the CRICOS code (then the exact course title) and matches the result to the university''s course page pattern. The page reader confirms the code on the page.', 5, true)
on conflict (jobname) do nothing;

select cron.schedule('course-link-search', '* * * * *', 'select security.course_link_search_tick_v1(40)');
