-- CF-247 S666 (S2-BOOST-Discovery; Platform Admin 19 Nov 2026 08:18, addendum "Fix IQ-00029 Coverage-Discovery 8 s worker timeouts"): the two
-- picks the worker calls under its 8 s limit check their conditions lazily, in pick order, inside a time budget, so the call answers instead of
-- timing out. Two functions are replaced; each is replaced only from the definition read live on 19 Nov 2026 (pre-check below).
--   * public.svc_coverage_discovery_next(integer): the focus check (security.enrich_focus_v1, 10.7 ms a provider) ran over every due provider
--     (1,177 due, 7.8 s with nothing in focus) before the order and the limit; the 86 HTTP 500 "canceling statement due to statement timeout"
--     since 18 Nov 18:24 UTC (3 hours: 86 of 360 discover calls) are this function, not the stop gate. It now orders the due providers by
--     active courses first (an index-only count) and checks focus in that order until the run size is reached or the time budget is spent.
--   * public.svc_course_link_search_next(integer): the stop gate (9.7 ms a row), the site-list check (7.4 ms a row) and the provider-level
--     checks (focus, few pages, not checked, onboarding: about 17 ms a provider) ran over all 4,049 queued rows and 171 providers before the
--     order and the limit (measured 43 s, 8 s and 6 s). They now run in pick order, once per provider for the provider-level checks, until the
--     run size is reached or the time budget is spent. Only the order-defining facts (priority country, tier) stay eager. A university whose
--     search is stopped is skipped without calling the gate when no person's task can bypass it, which is exactly the gate's own answer. The
--     stop is read per provider (security.fc_search_stopped_for_v1, the gate's own fallback) instead of for every provider up front (2.3 s), and the
--     directory-site check (12 ms a provider) is made per provider when first reached. Tested in a rolled-back live run with the daily share open:
--     the old definition picked 40 in 17.7 s (a time-out under the 8 s limit); this one answers in 5.1 s with 17 of the same 40.
-- The picked set is the same as before for the same state: the same conditions, the same order, the first rows that pass; the leased rows are
-- still locked with skip locked and updated as before. The one difference: a call that spends its time budget returns the rows it has found.
-- The time budget counts from the start of the call and stays inside the worker's 8 s limit (-- fixed: API time-out).
-- No table, column, job or setting added; G3 75 functions / 48 tables (neither function is in the consumer API). Nothing dropped or deleted.
-- Replaces: the whole-queue evaluation inside public.svc_coverage_discovery_next and public.svc_course_link_search_next (the S657 provider
--   narrowing of 18 Nov stays; the pick still timed out at about 250 providers with a queued search).
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the two function replacements below

-- 0. Pre-check: both functions are replaced only from the definitions read live on 19 Nov 2026
do $pre$
begin
  if md5(pg_get_functiondef('public.svc_coverage_discovery_next(integer)'::regprocedure)) <> '13d8b126bbe2a2d76a11540e72a4e134' then
    raise exception 'pre-check: public.svc_coverage_discovery_next differs from the definition this change replaces';
  end if;
  if md5(pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure)) <> 'b9bb31d5c9aa4053b1afaebeab63d36b' then
    raise exception 'pre-check: public.svc_course_link_search_next differs from the definition this change replaces';
  end if;
end $pre$;

-- 1. Discovery pick: order first, focus check in order, inside the time budget
CREATE OR REPLACE FUNCTION public.svc_coverage_discovery_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline'
AS $function$
declare v jsonb; v_ids uuid[] := '{}'; v_lim int := greatest(1, least(coalesce(p_limit, 5), 20)); v_t0 timestamptz := clock_timestamp(); v_r record;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- 19 Nov 2026 (S666): the focus check is made in pick order, not over every due provider before the order and the limit
  for v_r in
    select d.provider_id from pipeline.coverage_provider_discovery d
     where (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active') desc, d.provider_id
  loop
    exit when cardinality(v_ids) >= v_lim;
    exit when clock_timestamp() - v_t0 > interval '5 seconds';  -- fixed: the call answers inside the worker's 8 s limit with the providers found so far
    if security.enrich_focus_v1(v_r.provider_id) then v_ids := v_ids || v_r.provider_id; end if;  -- CF-247 15 Oct: focus providers only (Waste rules)
  end loop;
  with pick as (
    select d.provider_id from pipeline.coverage_provider_discovery d
     where d.provider_id = any (v_ids)
       and (d.status='pending' or (d.status in ('mapped','failed') and d.next_due_at<=now())) and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
     for update skip locked),
  upd as (update pipeline.coverage_provider_discovery d set leased_until=now()+interval '10 minutes', attempts=d.attempts+1, updated_at=now()
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,
           'extra_domains',(select coalesce(jsonb_agg(x.domain order by x.domain),'[]'::jsonb) from pipeline.provider_extra_domains x where x.provider_id=u.provider_id and x.state='approved'),  -- SP-1
           'courses',(select count(*) from catalogue.courses c where c.provider_id=u.provider_id and c.lifecycle_status='active'))),'[]'::jsonb) into v from upd u;
  return v;
end
$function$;

-- 2. Course link search pick: order-defining facts first, the gate, site list and provider-level checks in pick order, inside the time budget
CREATE OR REPLACE FUNCTION public.svc_course_link_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_person boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;
        v_daycap int := security.pipeline_num_v1('search.daily_picked_cap', 100)::int; v_room int;
        v_course_stop int := security.pipeline_num_v1('search.stop_per_course_after', 6)::int; v_on boolean; v_cap numeric; v_used numeric; v_lim int := greatest(1, least(coalesce(p_limit, 40), 200)); v jsonb;
        -- CF-247 operating model 3.3.2: providers of an open on-demand request covering course search (pass 1), the scheduled room (pass 2)
        v_od uuid[]; v_sched int; v_pass int; v_take int; v_part jsonb;
        -- 19 Nov 2026 (S666): the call's clock, the rows picked in order, and the provider-level checks made once per provider when first reached
        v_t0 timestamptz := clock_timestamp(); v_ids uuid[]; v_r record; v_pv jsonb; v_k text; v_focus boolean; v_few boolean; v_unch boolean; v_bulk boolean; v_stopped boolean;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select enabled, monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings where id = 1;
  select coalesce(sum(units), 0) into v_used from pipeline.coverage_vendor_usage where purpose = 'course_link_search' and at >= date_trunc('month', now());
  if not coalesce(v_on, false) or v_used + 2 * v_lim > v_cap then return '[]'::jsonb; end if;
  -- v2.15.262: inside the day's Firecrawl share for course search, and not for universities whose search has stopped
  -- 13 Nov 2026 (operating model 3.3.2): the share and the daily cap below hold the scheduled pick (pass 2) only; an open on-demand request's
  -- providers are picked first (pass 1) up to the run size
  v_od := array(select distinct x from pipeline.on_demand_requests r, unnest(r.provider_ids) x
                 where r.state = 'open' and r.expires_at > now() and 'firecrawl' = any (r.toolsets)
                   and (r.purpose_groups is null or security.fc_purpose_group_v1('course_link_search') = any (r.purpose_groups)));
  v_sched := greatest(0, least(v_lim, floor(security.fc_budget_left_v1('course_link_search') / 2)::int));
  if v_sched < 1 and cardinality(v_od) = 0 then return '[]'::jsonb; end if;
  -- R2 (C-Q1): the day's picked-courses cap (UTC day); a person's running Find course pages task is counted but not held
  select v_daycap - count(*) into v_room from pipeline.course_link_search where sent_at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC');
  if v_room > 0 then v_sched := least(v_sched, v_room); end if;
  v := '[]'::jsonb;
  for v_pass in 1 .. 2 loop
  v_take := case v_pass when 1 then case when cardinality(v_od) > 0 then v_lim else 0 end else least(v_sched, v_lim - jsonb_array_length(v)) end;
  continue when v_take < 1;
  v_ids := '{}'; v_pv := '{}'::jsonb;
  -- the rows in pick order, with the facts that define the order (priority country, tier) worked out once per provider
  for v_r in
    with prov as materialized (  -- materialized: worked out once, not folded back into every row
      select q.provider_id,
             coalesce(security.coverage_country(q.provider_id) in (select jsonb_array_elements_text(sp.value) from pipeline.platform_toolset_settings sp
                                                                    where sp.toolset_key = 'pipeline' and sp.key = 'search.priority_countries'), false) prio,
             security.fc_provider_tier_v1(q.provider_id) tier, rc.search_domain
        from (select d0.provider_id
                from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') d0
               -- 18 Nov 2026 (S657): only the providers this pass can take, and the plain checks first
               where (case when v_pass = 1 then d0.provider_id = any (v_od) else not (d0.provider_id = any (v_od)) end)
                 and not exists (select 1 from security.provider_hidden_v1 h0 where h0.provider_id = d0.provider_id)
                 and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true) or d0.provider_id = any (v_od)
                      or exists (select 1 from pipeline.firecrawl_target_cache tc0 where tc0.provider_id = d0.provider_id and tc0.included))
              offset 0) q
        join pipeline.course_link_recipes rc on rc.provider_id = q.provider_id and rc.active
       where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
         -- v2.15.255: while Firecrawl is for target universities only, take only their searches
         and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true) or q.provider_id = any (v_od)
              or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = q.provider_id and tc.included))
         -- 21 Oct 2026: providers with no course pages to find are not searched (search.skip_providers)
         and not exists (select 1 from catalogue.providers px, pipeline.platform_toolset_settings sk
                          where px.id = q.provider_id and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key))
    select s.course_id, s.provider_id, s.requested_at, pv.search_domain
      from pipeline.course_link_search s join prov pv on pv.provider_id = s.provider_id
      join catalogue.courses c on c.id = s.course_id
      left join pipeline.provider_priority pp on pp.provider_id = s.provider_id
     where s.state = 'queued'
       and (case when v_pass = 1 then s.provider_id = any (v_od) else not (s.provider_id = any (v_od)) end)
     -- v2.15.265: top-50, Australian 30+ courses, overseas, small providers; CRICOS-code searches first within each
     -- 21 Oct 2026 (Platform Admin "Keep 13,000, fix order only"): priority countries first (search.priority_countries)
     order by (s.requested_at is null), s.requested_at, pv.prio desc, pv.tier, (s.stage <> 'cricos'), coalesce(pp.rank, 100000),
              md5(s.course_id::text || to_char(now(), 'YYYYMMDDHH24MI'))
  loop
    exit when cardinality(v_ids) >= v_take;
    exit when clock_timestamp() - v_t0 > interval '5 seconds';  -- fixed: the call answers inside the worker's 8 s limit with the rows found so far
    -- the cheapest provider-level checks, once per provider, when first reached: a directory site (v2.15.265: never a search limited to one)
    -- and the university stop (the gate's own per-provider answer)
    v_k := v_r.provider_id::text;
    if not (v_pv ? v_k) then
      v_pv := v_pv || jsonb_build_object(v_k, jsonb_build_object(
        'third_party', security.third_party_host_v1('https://' || v_r.search_domain),
        'stopped', security.fc_search_stopped_for_v1(v_r.provider_id)));
    end if;
    if coalesce((v_pv -> v_k ->> 'third_party')::boolean, false) then continue; end if;
    v_stopped := coalesce((v_pv -> v_k ->> 'stopped')::boolean, false);
    -- R2: the daily cap (pass 2), unless a person's task covers the course
    if v_pass = 2 and not (v_room > 0 or (v_person and security.link_search_person_task_v1(v_r.provider_id, v_r.course_id))) then continue; end if;
    -- S1: the one stop gate (university stop with the person bypass, per-course stop). A stopped university with no person bypass is the gate's own answer
    if v_stopped and not v_person then continue; end if;
    if security.search_stop_gate_v1(v_r.provider_id, v_r.course_id, v_stopped) is not null then continue; end if;
    -- the other provider-level checks, once per provider, when a row of it passes the gate
    if not (v_pv -> v_k ? 'focus') then
      v_pv := jsonb_set(v_pv, array[v_k], (v_pv -> v_k) || jsonb_build_object(
        'focus', security.enrich_focus_v1(v_r.provider_id),
        'few', security.site_few_course_pages_v1(v_r.provider_id),
        'unchecked', security.site_not_checked_v1(v_r.provider_id),
        'bulk', exists (select 1 from pipeline.provider_onboarding o
                         where o.provider_id = v_r.provider_id and o.source in ('backfill', 'new_provider')
                           and not exists (select 1 from pipeline.firecrawl_search_resumes rs where rs.provider_id = v_r.provider_id and rs.resumed_at > o.created_at))));
    end if;
    v_focus := coalesce((v_pv -> v_k ->> 'focus')::boolean, false); v_few := coalesce((v_pv -> v_k ->> 'few')::boolean, false);
    v_unch := coalesce((v_pv -> v_k ->> 'unchecked')::boolean, false); v_bulk := coalesce((v_pv -> v_k ->> 'bulk')::boolean, false);
    -- CF-247 15 Oct: focus providers only; 18 Oct: a search a person asked for runs for any provider
    if v_pass = 2 and not (v_focus or v_r.requested_at is not null) then continue; end if;
    -- 22 Oct 2026 (NZ review fixes 1 and 2, Platform Admin 13:28 fix 1): unless a person asked: not where the site lists too few course
    -- pages, not before the site is checked, and for universities the site list first
    if v_r.requested_at is not null and (not v_bulk or (v_person and security.link_search_person_task_v1(v_r.provider_id, v_r.course_id))) then
      null;
    elsif v_few or v_unch then
      continue;
    elsif not security.site_list_match_done_v1(v_r.course_id, v_r.provider_id) then
      continue;
    end if;
    v_ids := v_ids || v_r.course_id;
  end loop;
  continue when cardinality(v_ids) = 0;
  with pick as (
    select s.course_id, s.provider_id, s.stage, c.course_code, c.canonical_title, rc.search_domain
      from pipeline.course_link_search s join catalogue.courses c on c.id = s.course_id
      join pipeline.course_link_recipes rc on rc.provider_id = s.provider_id and rc.active
     where s.state = 'queued' and s.course_id = any (v_ids)
       for update of s skip locked),
  upd as (
    update pipeline.course_link_search s set state = 'sent', sent_at = now(), req_id = null,
           query = case p.stage when 'cricos' then '"' || p.course_code || '" site:' || p.search_domain
                                else case when security.coverage_country(p.provider_id) = 'CA'
                                     then trim(regexp_replace(regexp_replace(regexp_replace(p.canonical_title, '\s*\([^)]*\)', ' ', 'g'), '\s+-\s+(UBCV|UBCO|Major|Honours|Open Learning)\M.*$', '', 'i'), '[:"]+', ' ', 'g')) || ' site:' || p.search_domain
                                     else '"' || replace(regexp_replace(p.canonical_title, '\s*\(\s*Level\s+\d{1,2}\s*\)\s*$', '', 'i'), '"', '') || '" site:' || p.search_domain end end
      from pick p where s.course_id = p.course_id
    returning s.course_id, s.provider_id, s.stage, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'provider_id', provider_id, 'stage', stage, 'query', query)), '[]'::jsonb) into v_part from upd;
  v := v || v_part;
  end loop;
  return v;
end
$function$;

-- 3. Post-checks: both functions carry the time budget, nothing leaked into the consumer API
do $post$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
  if pg_get_functiondef('public.svc_coverage_discovery_next(integer)'::regprocedure) not like '%clock_timestamp() - v_t0 > interval ''5 seconds''%' then
    raise exception 'post-check: the discovery pick does not carry its time budget';
  end if;
  if pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure) not like '%clock_timestamp() - v_t0 > interval ''5 seconds''%'
     or pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure) not like '%security.search_stop_gate_v1(v_r.provider_id, v_r.course_id, v_stopped)%' then
    raise exception 'post-check: the course search pick does not carry its time budget and the stop gate';
  end if;
  if not has_function_privilege('service_role', 'public.svc_coverage_discovery_next(integer)', 'execute')
     or not has_function_privilege('service_role', 'public.svc_course_link_search_next(integer)', 'execute') then
    raise exception 'post-check: service_role lost execute on a pick';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'pick_time_budget', 'discovery and course search picks check lazily inside a time budget (s666)',
          jsonb_build_object('functions', jsonb_build_array('public.svc_coverage_discovery_next', 'public.svc_course_link_search_next'),
                             'approval', 'Platform Admin 19 Nov 2026 08:18 (IQ-00029)'), null);
end $post$;
