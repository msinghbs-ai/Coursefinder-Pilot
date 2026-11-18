-- CF-247 S2-BOOST-Discovery (Platform Admin 18 Nov 2026 16:54: clear Course page needed through Firecrawl discovery, at most 10 requests at a
-- time, binding official single-course pages by CRICOS or NZQA code and exact title).
-- What was read live (17:05 AEDT)
--   * Rule l4-page-needed-search-v1 has sent 600 Course page needed items back to the course-link search lane (state search_requested). Every
--     one of them is still queued with 0 attempts: today's Firecrawl share for finding course pages (firecrawl daily_share_course_search) was
--     used up before the rule's first run, so the scheduled pick takes nothing until the day rolls over, and then only inside the daily share
--     and the daily picked cap. The lane finished 21 searches in the last 8 hours; 3,445 searches wait in its queue.
--   * Adelaide University: 163 of the 600 are its 404 pages. 161 are addresses on adelaideuni.edu.au itself that the binder guessed from the
--     course title (basis url_pattern); 2 are on adelaide.edu.au, which is already an approved host of the provider. A domain alias would
--     change none of them; each needs the search by its CRICOS code that is now queued.
-- What it changes: one on-demand request (operating model 3.3.2; security.on_demand_open_v1, via claude_session, toolset firecrawl, scoped to the
-- course search purpose group) for the providers of the items the rule has sent to the lane, with its estimate. The lane's own on-demand pass
-- (public.svc_course_link_search_next, pass 1) then searches those providers' queued courses now, by CRICOS or NZQA code and then by title, at
-- most 10 searches at a time (the worker's fixed pool), and binds a page only with identity proof, exactly as a scheduled search does.
-- Scheduled work of the same providers in every other Firecrawl purpose group keeps its limits. The account's own limits (monthly plan, credit
-- reserve), hidden providers, directory sites, robots, the per-course stop and manual locks still apply.
-- No table, function, job or setting is created or changed. G3 untouched. Nothing is dropped or deleted.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

create temp table cf_s656 on commit drop as select null::jsonb r where false;

do $d$
declare v_prov uuid[]; v_sent int; v_q int; v_unit numeric; v_res jsonb; v_id uuid; v_left numeric;
        v_tag text := '[S656 course page search]';
begin
  if exists (select 1 from pipeline.on_demand_requests r where r.state = 'open' and r.expires_at > now() and r.reason like v_tag || '%') then
    raise notice 'an S656 on-demand request is already open; nothing opened'; return;
  end if;
  select array_agg(distinct n.provider_id), count(*) into v_prov, v_sent
    from pipeline.course_page_needed n
   where n.state = 'search_requested'
     and exists (select 1 from pipeline.course_link_search s where s.course_id = n.course_id and s.state = 'queued')
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = n.provider_id);
  if coalesce(cardinality(v_prov), 0) = 0 then raise notice 'no Course page needed search is queued; nothing opened'; return; end if;
  -- the on-demand pass takes every queued search of these providers, so the estimate counts them all
  select count(*) into v_q from pipeline.course_link_search s where s.state = 'queued' and s.provider_id = any (v_prov);
  select avg(c.credits_used) into v_unit from pipeline.firecrawl_calls c
   where c.use_case = 'link_search' and c.endpoint = 'search' and c.credits_used is not null and c.at > now() - interval '14 days';  -- fixed: the estimate's look-back
  if v_unit is null then raise exception 'no course page search is on record to estimate from'; end if;
  v_left := (security.on_demand_credit_left_v1()->>'firecrawl_left_on_plan')::numeric;
  if v_left is null or ceil(v_q * v_unit) > v_left then
    raise exception 'the estimate (% credits) is above the Firecrawl credit left on the plan (%)', ceil(v_q * v_unit), v_left;
  end if;
  v_res := security.on_demand_open_v1('claude_session',
    v_tag || ' Platform Admin 18 Nov 2026 16:54: search now for the official course pages of the Course page needed items sent to the course-link search lane by rule l4-page-needed-search-v1 (CRICOS or NZQA code, then title; identity proof before any bind)',
    v_prov,
    jsonb_build_object('course_page_needed_items', v_sent, 'providers', cardinality(v_prov), 'searches_queued', v_q,
                       'credits_per_search_avg', round(v_unit, 2), 'firecrawl_credits', ceil(v_q * v_unit),
                       'note', 'searches only; a found page is read inside the scheduled reading share'),
    null, '{firecrawl}');
  v_id := (v_res->>'id')::uuid;
  perform security.on_demand_scope_v1(v_id, '{course_search}');
  insert into cf_s656 values (v_res);
  raise notice 'S656 on-demand request: %', v_res;
end $d$;

-- post-checks
do $c$
declare v jsonb := (select r from cf_s656); v_r record;
begin
  if v is null then return; end if;
  select * into v_r from pipeline.on_demand_requests where id = (v->>'id')::uuid;
  if v_r.state <> 'open' or v_r.expires_at <= now() then raise exception 'post-check: the on-demand request is not open'; end if;
  if v_r.toolsets <> '{firecrawl}' then raise exception 'post-check: the request must cover Firecrawl only'; end if;
  if v_r.purpose_groups <> '{course_search}' then raise exception 'post-check: the request must be scoped to course search'; end if;
  if security.fc_purpose_group_v1('course_link_search') <> 'course_search' then raise exception 'post-check: course page search is no longer in group course_search'; end if;
  if exists (select 1 from unnest(v_r.provider_ids) x join security.provider_hidden_v1 h on h.provider_id = x) then raise exception 'post-check: a hidden provider is covered'; end if;
end $c$;
