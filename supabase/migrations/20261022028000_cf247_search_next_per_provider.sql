-- CF-247 (22 Oct 2026). Platform Admin 18:26 (Scheduled jobs, "Workers sending back errors"): "Why is the coverage sweep job failing".
-- Found: since 14:30 Melbourne every run of the course page search worker ended with "svc_course_link_search_next: canceling statement due
-- to statement timeout" (236 so far; last search sent 14:53, 4,041 waiting). The search gates added this morning (20261022019000 and
-- 20261022020000) call provider-level checks (a person asked, the site lists too few course pages, the site is not checked yet, focus
-- provider, country, tier) once for every queued row, about 4,000 rows each run, which passes the 8-second limit.
-- Change: the same rules, worked out once per provider (a few hundred) and joined to the rows; the one per-course check (the site list
-- placed the course) runs only for rows that still need it. Nothing else changes: same order, same limits, same gates.
-- Also two indexes for the checks that run before every pick (monthly and daily course-search credits, searches stopped per provider):
-- usage by purpose and time, and title-search pages by provider and bind time.
-- Replaces: public.svc_course_link_search_next (pick step only, per-provider checks). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $edit$
declare v_def text := pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure); v_a int; v_b int; v_new text;
begin
  if md5(v_def) <> 'd74f17bdf20b971b584291ef20f637c4' then raise exception 'live public.svc_course_link_search_next differs from the definition this change edits'; end if;
  v_a := strpos(v_def, '  with pick as (');
  v_b := strpos(v_def, '     for update of s skip locked),');
  if v_a = 0 or v_b = 0 or v_b < v_a then raise exception 'pick step not found'; end if;
  v_new := $n$  -- 22 Oct 2026 (Platform Admin 18:26): provider-level checks once per provider, not once per queued row (the run timed out)
  with prov as materialized (  -- materialized: worked out once, not folded back into every row
    select q.provider_id,
           security.enrich_focus_v1(q.provider_id) focus,
           security.site_few_course_pages_v1(q.provider_id) few,
           security.site_not_checked_v1(q.provider_id) unchecked,
           exists (select 1 from pipeline.provider_onboarding o
                    where o.provider_id = q.provider_id and o.source in ('backfill', 'new_provider')
                      and not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = q.provider_id and r.resumed_at > o.created_at)) bulk,
           coalesce(security.coverage_country(q.provider_id) in (select jsonb_array_elements_text(sp.value) from pipeline.platform_toolset_settings sp
                                                                  where sp.toolset_key = 'pipeline' and sp.key = 'search.priority_countries'), false) prio,
           security.fc_provider_tier_v1(q.provider_id) tier, rc.search_domain
      from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') q
      join pipeline.course_link_recipes rc on rc.provider_id = q.provider_id and rc.active
     where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
       and q.provider_id <> all (v_stopped)
       -- v2.15.255: while Firecrawl is for target universities only, take only their searches
       and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
            or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = q.provider_id and tc.included))
       -- v2.15.265: never a search limited to a directory site
       and not security.third_party_host_v1('https://' || rc.search_domain)
       -- 21 Oct 2026: providers with no course pages to find are not searched (search.skip_providers)
       and not exists (select 1 from catalogue.providers px, pipeline.platform_toolset_settings sk
                        where px.id = q.provider_id and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key)),
  pick as (
    select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, pv.search_domain
      from pipeline.course_link_search s join prov pv on pv.provider_id = s.provider_id
      join catalogue.courses c on c.id = s.course_id
      left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
     where s.state = 'queued'
       and (pv.focus or s.requested_at is not null)  -- CF-247 15 Oct: focus providers only; 18 Oct: a search a person asked for runs for any provider
       -- 22 Oct 2026 (NZ review fixes 1 and 2, Platform Admin 13:28 fix 1): unless a person asked: not where the site lists too few course
       -- pages, not before the site is checked, and for universities the site list first
       and case when s.requested_at is not null and not pv.bulk then true
                when pv.few or pv.unchecked then false
                else security.site_list_match_done_v1(s.course_id, s.provider_id) end
     -- v2.15.265: top-50, Australian 30+ courses, overseas, small providers; CRICOS-code searches first within each
     -- 21 Oct 2026 (Platform Admin "Keep 13,000, fix order only"): priority countries first (search.priority_countries)
     order by (s.requested_at is null), s.requested_at, pv.prio desc, pv.tier, (s.stage <> 'cricos'), coalesce(pp.rank, 100000),
              md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
     limit v_lim
$n$;
  v_def := left(v_def, v_a - 1) || v_new || substr(v_def, v_b);
  execute v_def;
end $edit$;

create index if not exists coverage_vendor_usage_purpose_at_idx on pipeline.coverage_vendor_usage (purpose, at, provider_id);
create index if not exists coverage_course_pages_title_search_bound_idx on pipeline.coverage_course_pages (provider_id, bound_at desc)
  where basis = 'title_search' and read_at is not null;
analyze pipeline.coverage_vendor_usage;
analyze pipeline.coverage_course_pages;
