-- CF-247 (19 Oct 2026). Platform Admin 06:34 "Proceed with next steps together to finish them sooner"; choices:
--   University-calendar intake rule: "Undergraduate only (Recommended)".
--   Adelaide University: "Re-find on new site (Recommended)".
-- 1 Intakes from an approved academic calendar (Decision 241, colleges only until now) now also fill a university's undergraduate courses
--   (study levels in setting calendar.university_levels: bachelor, bachelor honours, associate degree, diploma, advanced diploma) that have
--   no intake, no lock and no pending Layer 4 item. Postgraduate and research courses are not filled from the calendar.
-- 2 Re-find a provider's course pages on its current website: pipeline.page_refind keeps each course's current page; an asked-for
--   course-page search runs on the provider's website; a page found there replaces the old one only once the reader accepts it is this
--   course's; if nothing passes, the old page is put back and read again. Started here for Adelaide University (pages on the pre-merger
--   adelaide.edu.au; website adelaideuni.edu.au). security.course_link_bind_v1 lets an open re-find replace a bound page;
--   security.course_relink_tick_v1 settles open re-finds every 10 minutes.
-- Guarded: every live definition is md5-checked, and every edit must apply exactly once.
-- Replaces: security.calendar_default_intakes_apply_v1 (universities' undergraduate courses included); security.course_link_bind_v1
--   (open re-find may replace a bound page); security.course_relink_tick_v1 (settles re-finds)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266); values go into the same tables as before.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'calendar.university_levels', 'University courses filled from the academic calendar', 'Study levels of a university''s courses whose intakes are filled from its approved academic calendar when the course page names none (Decision 241 extended 19 Oct 2026: undergraduate only).', 'list',
  '["bachelor", "bachelor_honours", "associate_degree", "diploma", "advanced_diploma"]'::jsonb, null, null, 'study levels', 320, 'CF-247, Platform Admin 19 Oct 2026 06:34 "Undergraduate only"', 'Enrichment', 'security.calendar_default_intakes_apply_v1')
on conflict (toolset_key, key) do nothing;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 calendar intakes: universities' undergraduate courses
select pg_temp.edit_once('security.calendar_default_intakes_apply_v1()', '9d39783597ebdedddf0e59dddec61bbb', array[
  array['select distinct x.provider_id, security.calendar_default_months(x.provider_id) months',
        'select distinct x.provider_id, security.calendar_default_months(x.provider_id) months, pv.canonical_name ~* ''\muniversity\M'' uni'],
  array[' and k.iso_alpha2 = ''AU'' and pv.canonical_name !~* ''\muniversity\M''),',
        ' and k.iso_alpha2 = ''AU''),'],
  array['select p.provider_id, p.months, s.evidence_id',
        'select p.provider_id, p.months, p.uni, s.evidence_id'],
  array['     where c.lifecycle_status = ''active''' || chr(10),
        '     where c.lifecycle_status = ''active''' || chr(10) ||
        '       -- 19 Oct 2026 (Platform Admin "Undergraduate only"): a university''s courses only at the study levels in calendar.university_levels' || chr(10) ||
        '       and (not cal.uni or exists (select 1 from ref.study_levels sl where sl.id = c.study_level_id and sl.code in (select jsonb_array_elements_text(s2.value) from pipeline.platform_toolset_settings s2 where s2.toolset_key = ''pipeline'' and s2.key = ''calendar.university_levels'')))' || chr(10)]
]);

-- 2 re-find on the current website
create table if not exists pipeline.page_refind (
  course_id uuid primary key references catalogue.courses(id) on delete cascade,
  provider_id uuid not null,
  old_url text not null,
  old_basis text,
  new_domain text not null,
  reason text not null,
  state text not null default 'open' check (state in ('open', 'replaced', 'kept_old')),
  result_url text,
  started_at timestamptz not null default now(),
  decided_at timestamptz
);
comment on table pipeline.page_refind is 'CF-247 (19 Oct 2026): course pages re-found on the provider''s current website; the old page is kept until a new one passes the reader''s identity check, and put back when none does.';
alter table pipeline.page_refind enable row level security;

CREATE OR REPLACE FUNCTION security.page_refind_start_v1(p_provider_id uuid, p_old_domain text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_dom text; v_n int;
begin
  select rc.search_domain into v_dom from pipeline.course_link_recipes rc where rc.provider_id = p_provider_id and rc.active;
  if v_dom is null or v_dom = lower(p_old_domain) then raise exception 'the provider''s course-page search must point at its current website first'; end if;
  insert into pipeline.page_refind(course_id, provider_id, old_url, old_basis, new_domain, reason)
  select g.course_id, g.provider_id, g.url, g.basis, v_dom, p_reason
    from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
   where g.provider_id = p_provider_id and g.status = 'bound' and g.read_status = 'read'
     and security.site_host_v1(g.url) = lower(p_old_domain)
  on conflict (course_id) do nothing;
  get diagnostics v_n = row_count;
  insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at, requested_at)
  select r.course_id, r.provider_id, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now(), now()
    from pipeline.page_refind r join catalogue.courses c on c.id = r.course_id where r.provider_id = p_provider_id and r.state = 'open'
  on conflict (course_id) do update set state = 'queued', stage = excluded.stage, attempts = 0, cand_idx = 0, candidates = null, results = null, bound_url = null,
         queued_at = now(), requested_at = now(), sent_at = null, done_at = null;
  return jsonb_build_object('courses', v_n, 'search_domain', v_dom);
end $function$;

CREATE OR REPLACE FUNCTION security.page_refind_settle_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rep int; v_old int;
begin
  update pipeline.page_refind r set state = 'replaced', decided_at = now(), result_url = g.url
    from pipeline.coverage_course_pages g, pipeline.course_link_search s
   where r.state = 'open' and g.course_id = r.course_id and s.course_id = r.course_id and s.state = 'verified'
     and g.status = 'bound' and g.identity_basis is not null and security.site_host_v1(g.url) like '%' || r.new_domain;
  get diagnostics v_rep = row_count;
  -- nothing passed on the current website: the old page goes back and is read again
  with back as (
    update pipeline.page_refind r set state = 'kept_old', decided_at = now(), result_url = r.old_url
      from pipeline.course_link_search s where r.state = 'open' and s.course_id = r.course_id and s.state in ('none', 'error')
    returning r.course_id, r.old_url, r.old_basis)
  update pipeline.coverage_course_pages g set url = b.old_url, basis = b.old_basis, status = 'bound', bound_at = now(), read_status = null, read_at = null,
         http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null, leased_until = null, read_attempts = 0, next_read_at = now()
    from back b where g.course_id = b.course_id and g.url <> b.old_url;
  select count(*) into v_old from pipeline.page_refind where state = 'kept_old' and decided_at > now() - interval '1 minute';  -- fixed: this run only
  return jsonb_build_object('replaced', v_rep, 'kept_old', v_old);
end $function$;

revoke execute on function security.page_refind_start_v1(uuid, text, text), security.page_refind_settle_v1() from public, anon, authenticated;

select pg_temp.edit_once('security.course_link_bind_v1(uuid,uuid,text,text)', '9a8ddb7f000d5ccca6f2fc5311728bed', array[
  array['   where pipeline.coverage_course_pages.status <> ''bound'' or pipeline.coverage_course_pages.basis in (''cricos_search'',''title_search'');',
        '   where pipeline.coverage_course_pages.status <> ''bound'' or pipeline.coverage_course_pages.basis in (''cricos_search'',''title_search'')' || chr(10) ||
        '      or exists (select 1 from pipeline.page_refind r where r.course_id = pipeline.coverage_course_pages.course_id and r.state = ''open'');  -- 19 Oct 2026: an open re-find may replace a bound page']
]);

select pg_temp.edit_once('security.course_relink_tick_v1(integer)', '850b7cbf906bd92e5f3eaa80858c9661', array[
  array['  -- settle: a candidate the reader accepted, or every candidate refused' || chr(10),
        '  perform security.page_refind_settle_v1();  -- 19 Oct 2026: re-finds on a provider''s current website' || chr(10) ||
        '  -- settle: a candidate the reader accepted, or every candidate refused' || chr(10)]
]);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.page_refind', 'L2 read', 'Course pages re-found on a provider''s current website, old page kept until a new one passes', 'active', '20261019010000'),
 ('function', 'security.page_refind_start_v1', 'L2 read', 'Starts a re-find of a provider''s pages from an old domain', 'active', '20261019010000'),
 ('function', 'security.page_refind_settle_v1', 'L2 read', 'Settles re-finds: replaced, or old page put back', 'active', '20261019010000')
on conflict (kind, name) do nothing;

-- Adelaide University: pages on the pre-merger site
select security.page_refind_start_v1(p.id, 'adelaide.edu.au', 'Platform Admin 19 Oct 2026 06:34: "Re-find on new site" (pre-merger adelaide.edu.au pages; website adelaideuni.edu.au)')
  from catalogue.providers p where p.canonical_name = 'Adelaide University';

do $post$
begin
  if position('calendar.university_levels' in pg_get_functiondef('security.calendar_default_intakes_apply_v1()'::regprocedure)) = 0 then raise exception 'post-check: calendar rule'; end if;
  if position('pipeline.page_refind' in pg_get_functiondef('security.course_link_bind_v1(uuid,uuid,text,text)'::regprocedure)) = 0 then raise exception 'post-check: bind'; end if;
  if position('page_refind_settle_v1' in pg_get_functiondef('security.course_relink_tick_v1(integer)'::regprocedure)) = 0 then raise exception 'post-check: tick'; end if;
  if (select count(*) from pipeline.page_refind where state = 'open') < 200 then raise exception 'post-check: Adelaide re-find not started'; end if;
end $post$;
