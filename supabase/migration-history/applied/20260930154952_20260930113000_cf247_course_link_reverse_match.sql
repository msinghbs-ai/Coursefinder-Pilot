-- CF-247 course link recipes, reverse match (1 Oct 2026). Platform Admin asked whether Firecrawl's site map could help
-- for Sydney and UNSW. Tested: a map call costs 1 credit and returned 537 Sydney and 497 UNSW course pages, but the
-- discovery job had already mapped all but one of each. The gap is matching pages to courses, not finding pages: about
-- 1,500 known course pages of the top 10 universities (by their recipe patterns) are bound to no course.
-- This reads those known, unbound pages directly (no Firecrawl credit), takes the CRICOS course codes printed on each,
-- and binds the page to those courses when they are still being searched for. The page reader then confirms the code
-- as usual. Pages listing more than three of the university's codes are lists, not course pages, and are skipped.
-- (Sydney course pages print only the university's provider code, so they match by exact title only.)

create table if not exists pipeline.course_link_reverse (
  url text primary key,
  provider_id uuid not null,
  state text not null default 'queued' check (state in ('queued','sent','done','error')),
  req_id bigint,
  codes text[],
  bound int not null default 0,
  sent_at timestamptz,
  done_at timestamptz);
create index if not exists course_link_reverse_state_idx on pipeline.course_link_reverse(state, provider_id);
alter table pipeline.course_link_reverse enable row level security;
revoke all on pipeline.course_link_reverse from public, anon, authenticated;

create or replace function security.course_link_reverse_enqueue_v1()
returns int language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  insert into pipeline.course_link_reverse(url, provider_id)
  select distinct regexp_replace(u.url, '#.*$', ''), u.provider_id
    from pipeline.coverage_provider_urls u join pipeline.course_link_recipes rc on rc.provider_id = u.provider_id and rc.active
   where exists (select 1 from jsonb_array_elements(rc.patterns) e where regexp_replace(u.url, '[?#].*$', '') ~ (e->>'re'))
     and not exists (select 1 from pipeline.coverage_course_pages p where p.provider_id = u.provider_id and p.status = 'bound' and p.url = u.url)
  on conflict (url) do nothing;
  get diagnostics v = row_count;
  return v;
end $$;
revoke all on function security.course_link_reverse_enqueue_v1() from public, anon, authenticated;

create or replace function security.course_link_reverse_tick_v1(p_batch int default 30)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; v_codes text[]; v_ours uuid[]; n_done int := 0; n_bound int := 0; n_sent int := 0; c record;
begin
  for r in select x.*, h.status_code, h.content from pipeline.course_link_reverse x join net._http_response h on h.id = x.req_id where x.state = 'sent' loop
    n_done := n_done + 1;
    if r.status_code = 200 and r.content is not null then
      v_codes := array(select distinct m[1] from regexp_matches(upper(r.content), '(?:^|[^0-9A-Z])([0-9]{6}[0-9A-Z])(?![0-9A-Z])', 'g') m);
      select array_agg(co.id) into v_ours from catalogue.courses co
       where co.provider_id = r.provider_id and co.lifecycle_status = 'active' and co.course_code = any(v_codes);
      if coalesce(cardinality(v_ours), 0) between 1 and 3 then
        for c in select s.course_id, s.stage from pipeline.course_link_search s where s.course_id = any(v_ours) and s.state in ('queued','none','error') loop
          update pipeline.course_link_search set state = 'found', candidates = to_jsonb(array[r.url]), cand_idx = 1, bound_url = r.url, done_at = now()
           where course_id = c.course_id;
          perform security.course_link_bind_v1(c.course_id, r.provider_id, r.url, 'cricos_search');
          n_bound := n_bound + 1;
          update pipeline.course_link_reverse set bound = bound + 1 where url = r.url;
        end loop;
      end if;
      update pipeline.course_link_reverse set state = 'done', codes = v_codes, done_at = now() where url = r.url;
    else
      update pipeline.course_link_reverse set state = 'error', done_at = now() where url = r.url;
    end if;
  end loop;
  update pipeline.course_link_reverse set state = 'queued'
   where state = 'sent' and sent_at < now() - interval '20 minutes' and not exists (select 1 from net._http_response h where h.id = req_id);
  for r in select x.url from pipeline.course_link_reverse x where x.state = 'queued'
            order by row_number() over (partition by x.provider_id order by x.url) limit greatest(1, least(coalesce(p_batch, 30), 60)) loop
    update pipeline.course_link_reverse set state = 'sent', sent_at = now(),
           req_id = net.http_get(r.url, headers := jsonb_build_object('user-agent', 'Mozilla/5.0 (compatible; CourseFinderBot/1.0)'), timeout_milliseconds := 30000)
     where url = r.url;
    n_sent := n_sent + 1;
  end loop;
  return jsonb_build_object('read', n_done, 'bound', n_bound, 'sent', n_sent);
end $$;
revoke all on function security.course_link_reverse_tick_v1(int) from public, anon, authenticated;

select security.course_link_reverse_enqueue_v1();

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('course-link-reverse', 'Course pages', 36, 'Match known course pages by CRICOS code',
  'Reads course pages already found on the top universities'' sites that are matched to no course, and matches them by the CRICOS codes printed on the page. No Firecrawl credits.', 5, true)
on conflict (jobname) do nothing;

select cron.schedule('course-link-reverse', '* * * * *', 'select security.course_link_reverse_tick_v1(30)');
