-- CF-247 (21 Oct 2026). Job queue review, Platform Admin 21:36 "Review the job queue"; choice "Keep 13,000, fix order only".
-- Found: course-page search used its whole daily share (13,000 credits) on 21 Oct; title searches bound 2,487 pages of which 39 were
-- confirmed and 1,426 were the wrong page (19 Oct: 34 of 424). The money did not follow "New Zealand first": the largest spenders were
-- Newcastle, Adelaide, Sydney and Monash, and 924 credits went to NZIST Work-Based Learning, whose apprenticeship programmes have no
-- course pages. The stop rule (no correct page in 30 searches) never stops a university that has one correct page among hundreds.
-- Changes (share unchanged):
--   1 Order: public.svc_course_link_search_next takes searches of providers in search.priority_countries (["NZ"]) first, after the ones a
--     person asked for.
--   2 Waste: security.fc_search_stopped_v1 also stops a university when its last search.wrong_in_row_stop (20) title-search pages that were
--     read were all the wrong page (or not a course page); it shows as stopped like the others and resumes with Search again.
--   3 Providers that have no course pages to find are listed in search.skip_providers (stable keys; NZIST Work-Based Learning,
--     provider:nzqa:6044) and are not searched.
-- Replaces: public.svc_course_link_search_next (order, skip list); security.fc_search_stopped_v1 (wrong-in-a-row rule). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"public.svc_course_link_search_next(integer)": "af38ae8afef28360fdb78671db46a14b",
                              "security.fc_search_stopped_v1()": "672e614cafececb235a6e56c372e7c30"}'::jsonb;
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
 ('pipeline', 'search.priority_countries', 'Course-page search: countries first', 'Searches for providers in these countries are taken first (after searches a person asked for).', 'list', '["NZ"]'::jsonb, null, null, 'countries', 317,
  'CF-247, Platform Admin 21 Oct 2026 21:36 "Keep 13,000, fix order only"', 'Course pages', 'svc_course_link_search_next'),
 ('pipeline', 'search.wrong_in_row_stop', 'Course-page search: stop after wrong pages in a row', 'A university''s course-page search stops (until Search again) when this many of its latest title-search pages that were read were all the wrong page.', 'number', to_jsonb(20), 5, 200, 'pages', 319,
  'CF-247, Platform Admin 21 Oct 2026 21:36 (1,426 wrong pages for 39 correct on 21 Oct)', 'Course pages', 'security.fc_search_stopped_v1'),
 ('pipeline', 'search.skip_providers', 'Course-page search: providers never searched', 'Stable keys of providers with no course pages to find (for example work-based learning).', 'list', '["provider:nzqa:6044"]'::jsonb, null, null, 'providers', 320,
  'CF-247, Platform Admin 21 Oct 2026 21:36 (924 credits on NZIST Work-Based Learning on 21 Oct)', 'Course pages', 'svc_course_link_search_next')
on conflict (toolset_key, key) do nothing;

select pg_temp.edit_once('public.svc_course_link_search_next(integer)', 'af38ae8afef28360fdb78671db46a14b', array[
  [$o$       and not security.third_party_host_v1('https://' || rc.search_domain)$o$,
   $n$       and not security.third_party_host_v1('https://' || rc.search_domain)
       -- 21 Oct 2026: providers with no course pages to find are not searched (search.skip_providers)
       and not exists (select 1 from catalogue.providers px, pipeline.platform_toolset_settings sk
                        where px.id = s.provider_id and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key)$n$],
  [$o$     order by (s.requested_at is null), s.requested_at, security.fc_provider_tier_v1(s.provider_id),$o$,
   $n$     -- 21 Oct 2026 (Platform Admin "Keep 13,000, fix order only"): priority countries first (search.priority_countries)
     order by (s.requested_at is null), s.requested_at,
              (security.coverage_country(s.provider_id) in (select jsonb_array_elements_text(sp.value) from pipeline.platform_toolset_settings sp where sp.toolset_key = 'pipeline' and sp.key = 'search.priority_countries')) desc,
              security.fc_provider_tier_v1(s.provider_id),$n$]]);

select pg_temp.edit_once('security.fc_search_stopped_v1()', '672e614cafececb235a6e56c372e7c30', array[
  [$o$  union all
  -- v2.15.265: held by the Platform Admin for an adapter check, until Search again$o$,
   $n$  union all
  -- 21 Oct 2026: the latest search.wrong_in_row_stop title-search pages that were read were all the wrong page (until Search again)
  select z.provider_id, z.n, z.since from (
    select y.provider_id, count(*) n, min(y.bound_at) since, count(*) filter (where y.status = 'bound' and y.read_status = 'read') good
      from (select pg.provider_id, pg.status, pg.read_status, pg.bound_at,
                   row_number() over (partition by pg.provider_id order by pg.bound_at desc) rn
              from pipeline.coverage_course_pages pg
             where pg.basis = 'title_search' and pg.read_at is not null
               and pg.bound_at > now() - make_interval(days => security.fc_setting_num_v1('search_stop_window_days', 7)::int)
               and pg.bound_at > coalesce((select max(r.resumed_at) from pipeline.firecrawl_search_resumes r where r.provider_id = pg.provider_id), '-infinity'::timestamptz)) y
     where y.rn <= security.pipeline_num_v1('search.wrong_in_row_stop', 20)::int
     group by y.provider_id) z
   where z.n >= security.pipeline_num_v1('search.wrong_in_row_stop', 20)::int and z.good = 0
     and z.provider_id not in (select s2.provider_id from s s2)
  union all
  -- v2.15.265: held by the Platform Admin for an adapter check, until Search again$n$]]);
