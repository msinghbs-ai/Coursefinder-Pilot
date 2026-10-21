-- CF-247 (22 Oct 2026). NZ data enrichment review, Platform Admin 07:22 "Review the data enrichment for nz and keep the stat how much of
-- toolset we used used successfully and failed before uni or courses were flagged. Find the gaps and resolution."; choice
-- "Quick wins: 1, 3, 6, 8". Review figures (NZ, live, 22 Oct): 149 providers used 6,432 course-search credits (32% of NZ search credits)
-- and never got a correct page; non-university providers whose site map kept 5 or fewer course-like pages got 11 correct search pages for
-- 4,738 credits. 307 NZ pages needed a browser and 141 were blocked; title-search pages are never rendered (12 Oct rule), so they wait for
-- the month roll-over. Address-pattern guesses: NZ 1 correct of 123 (AU 9 of 955, CA 10 of 343). 3,855 open flags across NZ providers,
-- page_not_found open at 198 of them. Two fee-reader records were refused ("unsupported Unicode escape sequence"; worker v0.36.0).
-- Changes:
--   1 Search where it can work: security.site_few_course_pages_v1 is true for a provider in search.site_check_countries (["NZ"]) whose site
--     map failed or kept search.min_site_course_pages (5) or fewer course-like pages, unless a search already found one of its pages.
--     security.course_search_off_v1 = that, or the provider is in search.skip_providers (now also NZIST 6683, Skills Group Training 7502,
--     Skills Update 9328, Te Rūnanga-o-Tūranganui-a-Kiwa 9646). public.svc_course_link_search_next skips those, except searches a person
--     asked for (Search again).
--   3 Pages that need a browser: in pages.render_countries (["NZ"]) a page read as needs_render or blocked is offered to the worker with
--     render_ok (Firecrawl, within the day's scrape share) and is tried again after retry.course_page_render_hours (24) instead of the month
--     roll-over; NZ pages waiting now are due now. Address-pattern guesses are made only in relink.url_pattern_countries (["AU","CA"]).
--   8 One flag per provider: security.enrichment_flags_refresh_v1 raises course_pages_not_listed on the provider when course search is off
--     for it, clears that provider's per-course page_not_found flags (kept, marked cleared) and raises no new ones; the provider flag clears
--     itself when search is on again.
-- Replaces: public.svc_course_link_search_next (site check); public.svc_coverage_read_next (render_ok); public.svc_coverage_read_record (retry of pages that need a browser); security.course_relink_provider_v1 (pattern countries); security.enrichment_flags_refresh_v1 (provider flag). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "f48156c1524387d6e0e8518527b51979",
                              "public.svc_coverage_read_next(integer)": "2e177089e3c930b4281c943b6b21047f",
                              "public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)": "537b2db7c6493b3e57a7fb9a737a09ca",
                              "security.course_relink_provider_v1(uuid,integer)": "f800ee85ffbc7ca764c06f12b8028887",
                              "security.enrichment_flags_refresh_v1()": "2044836d4d057d925e7499c2145da5f0"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then raise exception 'live % differs from the definition this change replaces', v_sig; end if;
  end loop;
end $guard$;

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

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'search.site_check_countries', 'Course-page search: check the site first in', 'In these countries a provider is searched only when its site map kept more than the minimum course-like pages (or a search already found one of its pages).', 'list', '["NZ"]'::jsonb, null, null, 'countries', 321,
  'CF-247, Platform Admin 22 Oct 2026 07:22, NZ review fix 1 (6,432 NZ search credits on providers with no correct page)', 'Course pages', 'security.site_few_course_pages_v1'),
 ('pipeline', 'search.min_site_course_pages', 'Course-page search: fewest course-like pages on the site map', 'A provider whose site map kept this many course-like pages or fewer (or whose map failed) is not searched in the check-first countries.', 'number', to_jsonb(5), 0, 100, 'pages', 322,
  'CF-247, Platform Admin 22 Oct 2026 07:22 (NZ: 11 correct search pages for 4,738 credits at 5 or fewer)', 'Course pages', 'security.site_few_course_pages_v1'),
 ('pipeline', 'pages.render_countries', 'Course pages: render pages that need a browser in', 'In these countries a course page that needed a browser or was blocked is read through Firecrawl (within the day''s scrape share), whatever search found it, and tried again after the render retry hours.', 'list', '["NZ"]'::jsonb, null, null, 'countries', 323,
  'CF-247, Platform Admin 22 Oct 2026 07:22, NZ review fix 3 (307 NZ pages need a browser, 141 blocked)', 'Course pages', 'public.svc_coverage_read_next, public.svc_coverage_read_record'),
 ('pipeline', 'retry.course_page_render_hours', 'Course page needing a browser: try again after', 'In the render countries, a page that still needed a browser is tried again after this many hours (elsewhere at the next month).', 'number', to_jsonb(24), 1, 720, 'hours', 445,
  'CF-247, Platform Admin 22 Oct 2026 07:22, NZ review fix 3', 'Re-read and retry', 'public.svc_coverage_read_record'),
 ('pipeline', 'relink.url_pattern_countries', 'Re-link: guess page addresses from the university''s address form in', 'Countries where a refused page is re-tried at an address built from the university''s usual address form. Results to 22 Oct: NZ 1 correct of 123, AU 9 of 955, CA 10 of 343.', 'list', '["AU","CA"]'::jsonb, null, null, 'countries', 324,
  'CF-247, Platform Admin 22 Oct 2026 07:22, NZ review fix 3 (NZ taken out)', 'Course pages', 'security.course_relink_provider_v1')
on conflict (toolset_key, key) do nothing;

-- fix 1: four more providers whose programmes have no course pages to find (NZIST, Skills Group Training, Skills Update, Te Rūnanga-o-Tūranganui-a-Kiwa)
update pipeline.platform_toolset_settings s
   set value = (select jsonb_agg(distinct x) from jsonb_array_elements_text(s.value || '["provider:nzqa:6683","provider:nzqa:7502","provider:nzqa:9328","provider:nzqa:9646"]'::jsonb) x),
       reason = 'CF-247, Platform Admin 22 Oct 2026 07:22, NZ review fix 1 (NZIST 432, Skills Group 508, Skills Update 220, Te Rūnanga 260 credits, no correct page)'
 where s.toolset_key = 'pipeline' and s.key = 'search.skip_providers';

create or replace function security.site_few_course_pages_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  -- CF-247 22 Oct 2026 (NZ review fix 1): the provider's own site lists too few course pages for a search to find them
  select coalesce(security.coverage_country(p_provider) in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                                                            where s.toolset_key = 'pipeline' and s.key = 'search.site_check_countries'), false)
     and exists (select 1 from pipeline.coverage_provider_discovery d
                  where d.provider_id = p_provider
                    and (d.status = 'failed' or (d.status = 'mapped' and coalesce(d.kept_count, 0) <= security.pipeline_num_v1('search.min_site_course_pages', 5))))
     and not exists (select 1 from pipeline.coverage_course_pages g
                      where g.provider_id = p_provider and g.status = 'bound' and g.read_status = 'read'
                        and g.basis in ('title_search', 'firecrawl_search', 'serper_search'))
$$;
comment on function security.site_few_course_pages_v1(uuid) is 'CF-247 22 Oct 2026: true when a provider in search.site_check_countries has a failed site map or one that kept search.min_site_course_pages or fewer course-like pages, and no search has found one of its pages.';

create or replace function security.course_search_off_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from catalogue.providers px, pipeline.platform_toolset_settings sk
                  where px.id = p_provider and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key)
      or security.site_few_course_pages_v1(p_provider)
$$;
comment on function security.course_search_off_v1(uuid) is 'CF-247 22 Oct 2026: course-page search is off for the provider (search.skip_providers, or its site lists too few course pages); a search a person asks for still runs.';

create or replace function security.render_country_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(security.coverage_country(p_provider) in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                                                            where s.toolset_key = 'pipeline' and s.key = 'pages.render_countries'), false)
$$;
comment on function security.render_country_v1(uuid) is 'CF-247 22 Oct 2026: the provider is in a country listed in pages.render_countries (pages that need a browser are rendered).';

revoke all on function security.site_few_course_pages_v1(uuid), security.course_search_off_v1(uuid), security.render_country_v1(uuid) from public;

select pg_temp.edit_once('public.svc_course_link_search_next(integer)', 'f48156c1524387d6e0e8518527b51979', array[
  [$o$                        where px.id = s.provider_id and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key)$o$,
   $n$                        where px.id = s.provider_id and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key)
       -- 22 Oct 2026 (NZ review fix 1): not where the provider's own site lists too few course pages, unless a person asked
       and (s.requested_at is not null or not security.site_few_course_pages_v1(s.provider_id))$n$]]);

select pg_temp.edit_once('public.svc_coverage_read_next(integer)', '2e177089e3c930b4281c943b6b21047f', array[
  [$o$returning p.course_id, p.provider_id, p.url, p.status, p.basis)$o$,
   $n$returning p.course_id, p.provider_id, p.url, p.status, p.basis, p.read_status)$n$],
  [$o$'basis',u.basis,$o$,
   $n$'basis',u.basis,'render_ok',(u.read_status in ('needs_render','blocked') and security.render_country_v1(u.provider_id)),$n$]]);

select pg_temp.edit_once('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)', '537b2db7c6493b3e57a7fb9a737a09ca', array[
  [$o$when p_read_status='needs_render' then date_trunc('month',now())+interval '1 month 1 hour' else$o$,
   $n$when p_read_status='needs_render' and security.render_country_v1(v_row.provider_id) then now()+make_interval(hours => security.pipeline_num_v1('retry.course_page_render_hours', 24)::int) when p_read_status='needs_render' then date_trunc('month',now())+interval '1 month 1 hour' else$n$]]);

select pg_temp.edit_once('security.course_relink_provider_v1(uuid,integer)', 'f800ee85ffbc7ca764c06f12b8028887', array[
  [$o$          from jsonb_array_elements(v_forms) with ordinality fm(form, ord) where length(r.slug) > 5$o$,
   $n$          from jsonb_array_elements(v_forms) with ordinality fm(form, ord) where length(r.slug) > 5
           -- 22 Oct 2026 (NZ review fix 3): address guesses only in relink.url_pattern_countries
           and security.coverage_country(p_provider_id) in (select jsonb_array_elements_text(sx.value) from pipeline.platform_toolset_settings sx
                                                             where sx.toolset_key = 'pipeline' and sx.key = 'relink.url_pattern_countries')$n$]]);

select pg_temp.edit_once('security.enrichment_flags_refresh_v1()', '2044836d4d057d925e7499c2145da5f0', array[
  [$o$v_on boolean := security.pipeline_num_v1('enrich.focus_top_n', 50) > 0;$o$,
   $n$v_on boolean := security.pipeline_num_v1('enrich.focus_top_n', 50) > 0; v_off int := 0;$n$],
  [$o$   where not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = q.course_id and p.status = 'bound')
   group by q.course_id$o$,
   $n$   where not exists (select 1 from pipeline.coverage_course_pages p where p.course_id = q.course_id and p.status = 'bound')
     and not security.course_search_off_v1(q.provider_id)  -- 22 Oct 2026 (NZ review fix 8): the provider flag covers these
   group by q.course_id$n$],
  [$o$  return jsonb_build_object('outside_focus', v_tail, 'page_not_found', v_nf);$o$,
   $n$  -- 22 Oct 2026 (NZ review fix 8): one flag on the provider when course search is off for it, instead of one per course
  insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
  select 'provider', p.id::text, p.id, 'course_page', 'course_pages_not_listed',
         'Course pages are not searched: the provider''s own site lists too few course pages, or its programmes have none (Pipeline settings › Course pages). Add pages by hand or use Search again.', 'waste-guard'
    from catalogue.providers p
   where exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
     and security.course_search_off_v1(p.id)
  on conflict (entity, entity_key, field, reason_code) do update set cleared_at = null where pipeline.enrichment_flags.cleared_at is not null;
  get diagnostics v_off = row_count;
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'course_pages_not_listed' and f.cleared_at is null and not security.course_search_off_v1(f.provider_id);
  update pipeline.enrichment_flags f set cleared_at = now()
   where f.reason_code = 'page_not_found' and f.entity = 'course' and f.cleared_at is null and security.course_search_off_v1(f.provider_id);
  return jsonb_build_object('outside_focus', v_tail, 'page_not_found', v_nf, 'course_pages_not_listed', v_off);$n$]]);

-- fix 3: pages in the render countries that needed a browser or were blocked are due now (a direct read first; Firecrawl when needed)
update pipeline.coverage_course_pages g set next_read_at = now(), read_attempts = 0
 where g.status = 'bound' and g.read_status in ('needs_render', 'blocked') and security.render_country_v1(g.provider_id)
   and coalesce(g.leased_until, '-infinity') < now();

select security.enrichment_flags_refresh_v1();
