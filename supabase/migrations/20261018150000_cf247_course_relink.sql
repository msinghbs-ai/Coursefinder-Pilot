-- CF-247 (18 Oct 2026). Relink the course pages the reader refused as another course's page (8,691 courses, read_status identity_mismatch).
-- Platform Admin 22:44 "Lets start on point 5"; choice "A+B, then D (Recommended)".
-- Measured 18 Oct: 182 refused pages are dead (not found); 1,449 are another course's page (only 12 of those other courses lack a page);
-- the rest are unrelated pages from search. 7,890 of the courses were already searched and nothing correct was found.
-- A Address pattern: 53 universities give every course an address built from its name (uts.edu.au/courses/{course-name}). The pattern is
--   learnt from the university's own verified pages (at least relink.pattern_min_pages pages and relink.pattern_min_share of them) and the
--   address is built for each course. About 943 courses.
-- B Stored address lists: an address on the university's stored lists whose last part is the course name. About 135 courses.
--   Plus: the refused page of another course whose title is exactly this course's title (about 12).
-- Each address is only a candidate. It is bound through the existing course-page search flow (pipeline.course_link_search, state found,
-- with the candidates in order) and read directly (no Firecrawl). The reader's identity check decides, exactly as for any page; a refused
-- or dead candidate moves to the next one and then to "none" (security.course_link_search_tick_v1, unchanged).
-- D Not on the university's site: a course with no candidate, or whose candidates were all refused, is recorded as absent. Nothing searches
--   it again automatically (asked-for searches still can: Find course pages in the Adapter builder); the builder lists it as "Not found on
--   the site", and it keeps its register data.
-- New: pipeline.course_relink, security.course_relink_provider_v1, security.course_relink_tick_v1, job course-relink (every 10 minutes),
-- settings batch.course_relink, relink.pattern_min_pages, relink.pattern_min_share.
-- Replaces: nothing
-- Retires: nothing (the job and its functions are marked retiring once every course is decided)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.course_relink', 'Courses relinked per run', 'Each run of the course-relink job builds candidate addresses for about this many courses whose page was refused, then binds the first one to be read.', 'number', '200', 20, 1000, 'courses', 317, 'CF-247 relink, 18 Oct 2026', 'Course pages', 'job course-relink'),
 ('pipeline', 'relink.pattern_min_pages', 'Address pattern: verified pages needed', 'A university''s address pattern ({course-name} in the address) is used only when at least this many of its verified course pages follow it.', 'number', '10', 3, 100, 'pages', 318, 'CF-247 relink, 18 Oct 2026', 'Course pages', 'security.course_relink_provider_v1'),
 ('pipeline', 'relink.pattern_min_share', 'Address pattern: share of verified pages', 'A university''s address pattern is used only when at least this share of its verified course pages follow it.', 'number', '0.5', 0.2, 1, 'share', 319, 'CF-247 relink, 18 Oct 2026', 'Course pages', 'security.course_relink_provider_v1')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.course_relink (
  course_id uuid primary key references catalogue.courses(id) on delete cascade,
  provider_id uuid not null,
  old_url text,
  candidates jsonb not null default '[]'::jsonb,
  sources jsonb not null default '[]'::jsonb,
  pattern text,
  state text not null check (state in ('trying', 'found', 'absent')),
  reason text,
  result_url text,
  started_at timestamptz not null default now(),
  decided_at timestamptz
);
comment on table pipeline.course_relink is 'CF-247 relink (18 Oct 2026): courses whose page was refused as another course''s page; candidate addresses from the university''s address pattern, its stored address lists or another course''s refused page; trying, found, or absent (not on the university''s site).';
create index if not exists course_relink_state_idx on pipeline.course_relink (state, provider_id);
alter table pipeline.course_relink enable row level security;

CREATE OR REPLACE FUNCTION security.course_relink_provider_v1(p_provider_id uuid, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tpl text; v_n int := 0; v_good int := 0; v_try int := 0; v_absent int := 0; r record; v_c text[]; v_s text[];
begin
  -- the university's address pattern, learnt from its own verified pages
  with g as (select lower(g.url) u, regexp_replace(regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') slug
               from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id
              where g.provider_id = p_provider_id and g.status = 'bound' and g.read_status = 'read' and g.identity_basis is not null)
  select t.tpl, t.n, (select count(*) from g) into v_tpl, v_n, v_good
    from (select replace(u, slug, '{slug}') tpl, count(*) n from g where length(slug) > 5 and strpos(u, slug) > 0 group by 1 order by 2 desc limit 1) t;
  if v_n < security.pipeline_num_v1('relink.pattern_min_pages', 10) or v_good = 0 or v_n::numeric / v_good < security.pipeline_num_v1('relink.pattern_min_share', 0.5) then
    v_tpl := null;
  end if;
  for r in
    select p.course_id, p.url old_url, regexp_replace(regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') slug,
           regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g') nt
      from pipeline.coverage_course_pages p join catalogue.courses c on c.id = p.course_id and c.lifecycle_status = 'active'
     where p.provider_id = p_provider_id and p.read_status = 'identity_mismatch'
       and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id)
     order by p.course_id
     limit greatest(1, p_limit)
  loop
    select array_agg(z.url order by z.rk), array_agg(z.src order by z.rk) into v_c, v_s from (
      select distinct on (lower(q.url)) q.url, q.src, q.rk from (
        -- another course's refused page whose title is exactly this course's title
        select o.url, 'page_swap' src, 1 rk from pipeline.coverage_course_pages o
         where o.provider_id = p_provider_id and o.course_id <> r.course_id and o.read_status = 'identity_mismatch' and length(r.nt) > 8
           and r.nt in (regexp_replace(regexp_replace(lower(coalesce(o.candidates->>'h1', '')), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'),
                        regexp_replace(regexp_replace(split_part(split_part(split_part(lower(coalesce(o.candidates->>'page_title', '')), ' | ', 1), ' – ', 1), ' - ', 1), '&#?[a-z0-9]+;', ' ', 'g'), '[^a-z0-9]+', '', 'g'))
        union all
        select replace(v_tpl, '{slug}', r.slug), 'url_pattern', 2 where v_tpl is not null and length(r.slug) > 5
        union all
        select l.url, 'url_list', 3 from (
          select pu.url from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
          union select dl.url from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) l
         where length(r.slug) > 10 and regexp_replace(substring(lower(l.url) from '/([^/?#]+)/?(?:[?#].*)?$'), '\.html?$', '') = r.slug) q
      where lower(q.url) <> lower(r.old_url)
        and not exists (select 1 from pipeline.course_page_blocks b where b.course_id = r.course_id and b.url = q.url)
      order by lower(q.url), q.rk) z;
    if coalesce(cardinality(v_c), 0) = 0 then
      insert into pipeline.course_relink(course_id, provider_id, old_url, pattern, state, reason, decided_at)
      values (r.course_id, p_provider_id, r.old_url, v_tpl, 'absent', 'no address from the university''s address pattern or stored lists', now());
      update pipeline.course_link_search set state = 'none', done_at = coalesce(done_at, now()) where course_id = r.course_id and state = 'queued' and requested_at is null;
      v_absent := v_absent + 1;
    else
      v_c := v_c[1:3]; v_s := v_s[1:3];  -- fixed: at most three candidates a course
      insert into pipeline.course_relink(course_id, provider_id, old_url, candidates, sources, pattern, state)
      values (r.course_id, p_provider_id, r.old_url, to_jsonb(v_c), to_jsonb(v_s), v_tpl, 'trying');
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, candidates, cand_idx, bound_url, queued_at, done_at)
      values (r.course_id, p_provider_id, 'title', 'found', to_jsonb(v_c), 1, v_c[1], now(), null)
      on conflict (course_id) do update set stage = 'title', state = 'found', candidates = excluded.candidates, cand_idx = 1, bound_url = excluded.bound_url,
             results = null, attempts = 0, done_at = null;
      perform security.course_link_bind_v1(r.course_id, p_provider_id, v_c[1], v_s[1]);
      v_try := v_try + 1;
    end if;
  end loop;
  return jsonb_build_object('pattern', v_tpl, 'trying', v_try, 'absent', v_absent);
end $function$;

CREATE OR REPLACE FUNCTION security.course_relink_tick_v1(p_batch integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_left int := greatest(1, coalesce(p_batch, 200)); v_pid uuid; v_r jsonb; v_found int; v_absent int; v_prov int := 0;
begin
  -- settle: a candidate the reader accepted, or every candidate refused
  update pipeline.course_relink x set state = 'found', decided_at = now(), result_url = s.bound_url, reason = 'the reader confirmed the page'
    from pipeline.course_link_search s where x.state = 'trying' and s.course_id = x.course_id and s.state = 'verified';
  get diagnostics v_found = row_count;
  update pipeline.course_relink x set state = 'absent', decided_at = now(), reason = 'every candidate address was refused by the reader or did not answer'
    from pipeline.course_link_search s where x.state = 'trying' and s.course_id = x.course_id and s.state in ('none', 'error');
  get diagnostics v_absent = row_count;
  -- next universities with refused pages not yet relinked
  for v_pid in select p.provider_id from pipeline.coverage_course_pages p
                where p.read_status = 'identity_mismatch' and not exists (select 1 from pipeline.course_relink x where x.course_id = p.course_id)
                  and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
                group by 1 order by count(*) desc loop
    exit when v_left <= 0;
    v_r := security.course_relink_provider_v1(v_pid, v_left);
    v_left := v_left - (v_r->>'trying')::int - (v_r->>'absent')::int;
    v_prov := v_prov + 1;
  end loop;
  return jsonb_build_object('found', v_found, 'absent', v_absent, 'providers', v_prov);
end $function$;

revoke execute on function security.course_relink_provider_v1(uuid, integer), security.course_relink_tick_v1(integer) from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('course-relink', 'Course pages', 48, 'Relink refused course pages', 'Every 10 minutes: for courses whose page was refused as another course''s page, builds candidate addresses (the university''s address pattern, its stored lists) and binds them to be read and checked; records a course as not on the site when none passes.', 4, true)
on conflict (jobname) do nothing;
select cron.schedule('course-relink', '4-59/10 * * * *', $$select security.course_relink_tick_v1(security.pipeline_num_v1('batch.course_relink', 200)::int)$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.course_relink', 'L2 read', 'Relink of refused course pages: candidates, outcome, absent courses', 'active', '20261018150000'),
 ('job', 'course-relink', 'L2 read', 'Relinks refused course pages every 10 minutes', 'active', '20261018150000'),
 ('function', 'security.course_relink_provider_v1', 'L2 read', 'Candidate addresses for one university''s refused course pages', 'active', '20261018150000'),
 ('function', 'security.course_relink_tick_v1', 'L2 read', 'Settles relink outcomes and starts the next batch', 'active', '20261018150000')
on conflict (kind, name) do nothing;

do $post$
begin
  if not exists (select 1 from cron.job where jobname = 'course-relink') then raise exception 'relink post-check: job'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where key in ('batch.course_relink', 'relink.pattern_min_pages', 'relink.pattern_min_share')) <> 3 then raise exception 'relink post-check: settings'; end if;
end $post$;
