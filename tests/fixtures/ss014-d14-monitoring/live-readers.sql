CREATE OR REPLACE FUNCTION public.svc_coverage_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with due as (
    select p.course_id, p.provider_id, p.status st, coalesce(pp.rank,100000) prank, coalesce(cp.sort,1000000) csort, row_number() over (partition by p.provider_id order by (p.status<>'bound'), p.next_read_at) rk
      from pipeline.coverage_course_pages p left join pipeline.provider_priority pp on pp.provider_id=p.provider_id left join pipeline.course_priority cp on cp.course_id=p.course_id
     where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)),  -- v2.15.237: paused while the provider is unpublished or archived
  pick as (select course_id from due where rk<=20 order by csort, least(prank,101), (st<>'bound'), rk, random() limit greatest(1,least(coalesce(p_limit,20),200))),
  upd as (update pipeline.coverage_course_pages p set leased_until=now()+interval '10 minutes', read_attempts=p.read_attempts+1
            from pick where p.course_id=pick.course_id and coalesce(p.leased_until,'-infinity')<now()  -- W30: re-checked on the locked row; one claim per page
            returning p.course_id, p.provider_id, p.url, p.status, p.basis, p.read_status)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'provider_id',u.provider_id,'url',u.url,'title',c.canonical_title,'code',c.course_code,'country',security.coverage_country(u.provider_id),'status',u.status,'basis',u.basis,'render_ok',(u.read_status in ('needs_render','blocked') and security.render_country_v1(u.provider_id)),'manual',coalesce(u.basis='manual',false),'direct_only',exists (select 1 from pipeline.page_reread_pilot rr where rr.course_id=u.course_id and rr.outcome_at is null),'rendered_before',(exists (select 1 from pipeline.coverage_course_pages q where q.course_id=u.course_id and q.fetched_via='firecrawl') or exists (select 1 from pipeline.page_link_repairs x where x.course_id=u.course_id and x.reason like 'university adapter: international view read%')),'priority',coalesce((select pp.rank<=100 from pipeline.provider_priority pp where pp.provider_id=u.provider_id),false) or exists (select 1 from pipeline.course_priority cp where cp.course_id=u.course_id))),'[]'::jsonb)
    into v from upd u join catalogue.courses c on c.id=u.course_id;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.svc_course_link_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_person boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;
        v_daycap int := security.pipeline_num_v1('search.daily_picked_cap', 100)::int; v_room int;
        v_course_stop int := security.pipeline_num_v1('search.stop_per_course_after', 6)::int; v_on boolean; v_cap numeric; v_used numeric; v_lim int := greatest(1, least(coalesce(p_limit, 40), 200)); v jsonb; v_stopped uuid[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if not coalesce(v_on, false) or v_used + 2 * v_lim > v_cap then return '[]'::jsonb; end if;
  -- v2.15.262: inside the day's Firecrawl share for course search, and not for universities whose search has stopped
  v_lim := least(v_lim, floor(security.fc_budget_left_v1('course_link_search') / 2)::int);
  if v_lim < 1 then return '[]'::jsonb; end if;
  -- R2 (C-Q1): the day's picked-courses cap (UTC day); a person's running Find course pages task is counted but not held
  select v_daycap - count(*) into v_room from pipeline.course_link_search where sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC');
  if v_room > 0 then v_lim := least(v_lim, v_room); end if;
  v_stopped := array(select x.provider_id from security.fc_search_stopped_v1() x);
  -- 22 Oct 2026 (Platform Admin 18:26): provider-level checks once per provider, not once per queued row (the run timed out)
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
           security.fc_provider_tier_v1(q.provider_id) tier, rc.search_domain,
           (q.provider_id = any (v_stopped)) stopped  -- 24 Oct 2026 (hotfix D2): kept as a flag; the row check below decides
      from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') q
      join pipeline.course_link_recipes rc on rc.provider_id = q.provider_id and rc.active
     where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
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
       and security.search_stop_gate_v1(s.provider_id, s.course_id, pv.stopped) is null  -- S1: the one stop gate (university stop with the person bypass, per-course stop)
       and (v_room > 0 or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))  -- R2: the daily cap
       and (pv.focus or s.requested_at is not null)  -- CF-247 15 Oct: focus providers only; 18 Oct: a search a person asked for runs for any provider
       -- 22 Oct 2026 (NZ review fixes 1 and 2, Platform Admin 13:28 fix 1): unless a person asked: not where the site lists too few course
       -- pages, not before the site is checked, and for universities the site list first
       and case when s.requested_at is not null and (not pv.bulk or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id))) then true
                when pv.few or pv.unchecked then false
                else security.site_list_match_done_v1(s.course_id, s.provider_id) end
     -- v2.15.265: top-50, Australian 30+ courses, overseas, small providers; CRICOS-code searches first within each
     -- 21 Oct 2026 (Platform Admin "Keep 13,000, fix order only"): priority countries first (search.priority_countries)
     order by (s.requested_at is null), s.requested_at, pv.prio desc, pv.tier, (s.stage <> 'cricos'), coalesce(pp.rank, 100000),
              md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
     limit v_lim
     for update of s skip locked),
  upd as (
    update pipeline.course_link_search s set state = 'sent', sent_at = now(), req_id = null,
           query = case p.stage when 'cricos' then '"' || p.course_code || '" site:' || p.search_domain
                                else case when security.coverage_country(p.provider_id) = 'CA'
                                     then trim(regexp_replace(regexp_replace(regexp_replace(p.canonical_title, '\s*\([^)]*\)', ' ', 'g'), '\s+-\s+(UBCV|UBCO|Major|Honours|Open Learning)\M.*$', '', 'i'), '[:"]+', ' ', 'g')) || ' site:' || p.search_domain
                                     else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end end
      from pick p where s.course_id = p.course_id
    returning s.course_id, s.provider_id, s.stage, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'provider_id', provider_id, 'stage', stage, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$
;
