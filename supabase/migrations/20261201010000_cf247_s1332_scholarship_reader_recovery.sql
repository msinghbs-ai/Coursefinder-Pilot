-- CF-247 s1332 (S2-Build; SS-Programme-Control 28 Nov 2026 07:22 AEDT, P0: "Recover existing scholarship reader exceptions. QUT listing 1429 remains failed
-- with waiting_scraper ... Continue the existing UQ College accordion reader work for candidate 22521, preserving its protected classification and eligibility
-- holds. No new reader framework, queue, scheduler or admission bypass.")
-- Found live (28 Nov 2026 07:30 to 08:10 AEDT, rolled-back reads only):
--   1. Candidate reading is stalled for every provider: each scholarship_discover call since 27 Nov 2026 20:00 AEDT failed with
--      "svc_scholarship_candidate_next: canceling statement due to statement timeout" (pipeline.mode_outcome_ledger, 500), so 2,073 due candidates (QUT 75,
--      never leased since 24 Nov) wait. Timed: the directory-site rule security.third_party_host_v1, asked once per page of the 600-page window, takes 6.6 s
--      of the 8 s limit; it depends only on the page's site host (security.site_host_v1), and the window holds about 40 hosts.
--   2. QUT listing 1429 (https://www.qut.edu.au/study/fees-and-scholarships/scholarships/browse): read 24 Nov through Firecrawl (pages 1 to 3, 30 items; the
--      direct copy gives no items), page 4 then refused, and every later first page refused with university_cap: QUT used its whole per-university
--      scholarship allowance (150 units in the rolling 30-day window, 12 to 24 Nov), so the paid read waits until mid-December (1,655 university_cap
--      refusals across providers in two days).
--   3. UQ College's scholarship page (candidate 22521, https://uqcollege.uq.edu.au/scholarships, now /apply/scholarships) is a hub of award blocks; it was
--      read once as one page (8 Oct, direct, HTTP 200) and rejected no_named_title. It is not a listing source, so the existing award-section readers
--      (s1035 headings, s1037 labels and tiers) never split it.
-- What this changes (existing mechanisms only):
--   1. public.svc_scholarship_candidate_next asks the directory-site rule once per distinct host of its window; the same pages pass (the rule reads only the
--      host), every other rule, order and limit is unchanged.
--   2. QUT is given one Claude-session on-demand Firecrawl request (security.on_demand_open_v1, operating model 3.3.2), scoped to the scholarships purpose
--      group and capped at 150 units (s903 cap: the request stops covering spend at its own recorded use), for the existing six-hour window; listing 1429
--      is read again now (status waiting, as s1043 retried Adelaide's waiting_scraper row). The scheduled listing and candidate lanes do the reads.
--   3. UQ College's scholarship hub is registered as a manual listing source and read now (as s1043 registered the Charles Darwin hub), so the existing
--      award-section readers split it into award candidates. Candidate 22521, the provider's type and every admission and eligibility rule are untouched:
--      each award candidate takes the normal read and admission route and its holds.
-- No new reader, queue, job, setting or admission path. Firecrawl within the monthly plan (ops_cost.fc_usd_per_credit 0); no model is called here.
-- G1: no job. G2: no value added (the window, retries and caps are existing settings; 150 is the request's own recorded cap, operating model 3.3.2).
-- G3: no consumer object changed (checked). Locks and active cron jobs checked unchanged. Nothing dropped or deleted.
-- Replaces: public.svc_scholarship_candidate_next (same function, per-host directory-site check).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and one function replacement

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_scholarship_candidate_next(integer)'::regprocedure)) <> 'dc4c9c4c765375d14801209c6f3d88ae' then
    raise exception 'guard: public.svc_scholarship_candidate_next is not the definition read on 28 Nov 2026';
  end if;
  if not exists (select 1 from pipeline.scholarship_listing_pages where id = 1429 and provider_id = '2c4f515c-c146-4e90-ba8a-294130aa1f40'
                 and url = 'https://www.qut.edu.au/study/fees-and-scholarships/scholarships/browse') then
    raise exception 'guard: QUT listing 1429 is not the row read on 28 Nov 2026';
  end if;
  if not exists (select 1 from pipeline.scholarship_page_candidates where id = 22521 and provider_id = '4d6daad6-d58d-43b3-ad22-9a5571aa4048') then
    raise exception 'guard: candidate 22521 is not UQ College''s';
  end if;
  if to_regprocedure('security.on_demand_scope_v1(uuid,text[])') is null or security.fc_purpose_group_v1('sch_scrape') <> 'scholarships' then
    raise exception 'guard: on-demand scoping or the scholarships purpose group is not as read on 28 Nov 2026';
  end if;
end $g$;
create temp table s1332_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs,
         (select md5(to_jsonb(c)::text) from pipeline.scholarship_page_candidates c where c.id = 22521) c22521;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_ok uuid[] := '{}'; v_p record; v_task uuid[];
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- CF-247 s1054: only a queued or running "Find scholarships" task puts its providers' candidates first (a request left from earlier no longer does)
  v_task := array(select distinct x::uuid from pipeline.admin_jobs j, jsonb_array_elements_text(coalesce(j.args->'providers', '[]'::jsonb)) x
                   where j.kind = 'scholarship_provider_scan' and j.state in ('queued', 'running'));
  -- CF-247 scholarship recovery F1: the skip rules run when candidates are recorded and hourly (security.scholarship_candidate_skip_v1).
  -- CF-247 s1054: the holds are checked once per provider that has a due candidate, before the window, so held providers never fill it
  for v_p in select distinct c.provider_id from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
              where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3 loop
    -- v2.15.237 unpublished; v2.15.271 search off. DR-15 (s1199, 26 Nov 2026): a paid Firecrawl hold (cap or eligibility) no longer holds the free read:
    -- the page is read directly first at no cost, and any paid scrape is still decided by public.svc_fc_spend (per-university cap, eligibility, shares)
    if not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = v_p.provider_id)
       and not security.provider_sch_search_off_v1(v_p.provider_id) then v_ok := v_ok || v_p.provider_id; end if;
  end loop;
  -- CF-247 s1332: the window keeps each page's site host, so the directory-site rule is asked once per host below (it depends on the host only)
  create temp table if not exists sch_cand_win_v3(id bigint, provider_id uuid, url text, requested boolean, tier int, priority int, found_at timestamptz, cc text, host text) on commit drop;
  truncate sch_cand_win_v3;
  insert into sch_cand_win_v3
  select z.id, z.provider_id, z.url, z.requested, z.tier, z.priority, z.found_at, z.cc, security.site_host_v1(z.url) from (
    select c.id, c.provider_id, c.url, c.provider_id = any (v_task) requested, coalesce(d.tier, 9) tier, d.priority, c.found_at, coalesce(co.iso_alpha2::text, '--') cc,
           -- CF-247 s1054: the window takes each country in turn, so one country's older backlog never fills it
           row_number() over (partition by coalesce(co.iso_alpha2::text, '--') order by (c.provider_id = any (v_task)) desc, coalesce(d.tier, 9), (d.priority not in (0,3)), c.found_at, c.id) crk
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
      join catalogue.providers p on p.id = c.provider_id left join ref.countries co on co.id = p.country_id
     where c.provider_id = any (v_ok) and c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3) z
   order by z.requested desc, z.crk, z.cc
   limit greatest(1, security.pipeline_num_v1('scholarship.candidate_pick_window', 600)::int);
  -- CF-247 s1332 (S2-Build, SS-Programme-Control 28 Nov 2026 07:22 AEDT): security.third_party_host_v1 reads only security.site_host_v1 of its address, so it is
  -- asked once per distinct host of the window (about 40) instead of once per page (600): the same pages pass. Asked per page it took 6.6 s of the call's
  -- 8 s statement limit, and every candidate run from 27 Nov 2026 20:00 AEDT was cancelled (mode_outcome_ledger: statement timeout).
  with hosts as (
    select w.host, security.third_party_host_v1(min(w.url)) directory_site from sch_cand_win_v3 w group by w.host),
  ranked0 as (
    select w.id, w.requested, w.tier, w.priority, w.cc, row_number() over (partition by w.provider_id order by (w.url ~* 'international') desc, w.found_at, w.id) rn
      from sch_cand_win_v3 w join hosts h on h.host is not distinct from w.host where not h.directory_site),
  ranked as (
    -- CF-247 s1054: within a country the providers take turns (rn), and the countries take turns (crk)
    select r0.*, row_number() over (partition by r0.requested, r0.cc order by r0.rn, r0.tier, (r0.priority not in (0,3)), r0.id) crk from ranked0 r0),
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by r.requested desc, r.crk, r.cc, c.id
     limit greatest(1,least(coalesce(p_limit,30), security.pipeline_num_v1('scholarship.candidates_max', 60)::int)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id  -- fixed: claim lease
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

comment on function public.svc_scholarship_candidate_next(integer) is 'CF-247 s1332: leases due scholarship candidate pages (DR-15 holds; country and provider turns); the directory-site rule is asked once per site host of the window.';

do $a$
declare v_qut uuid := '2c4f515c-c146-4e90-ba8a-294130aa1f40'; v_uqc uuid := '4d6daad6-d58d-43b3-ad22-9a5571aa4048';
        v_url text := 'https://uqcollege.uq.edu.au/apply/scholarships'; v_od jsonb; v_n int;
begin
  -- 2. QUT: one capped, scoped on-demand request for the scholarship reads, then listing 1429 read again from its first page
  v_od := security.on_demand_open_v1('claude_session',
            'CF-247 s1332 (S2-Build, SS-Programme-Control 28 Nov 2026 07:22 AEDT P0): QUT scholarship listing 1429 and its waiting candidates; the per-university allowance is used up',
            array[v_qut], jsonb_build_object('cap_firecrawl_units', 150, 'firecrawl_units', 150, 'openrouter_usd', 0, 'lanes', 'scholarship_listing, scholarship_discover candidates'),
            null, array['firecrawl']);
  perform security.on_demand_scope_v1((v_od->>'id')::uuid, array['scholarships']);
  update pipeline.scholarship_listing_pages set status = 'waiting', next_read_at = null where id = 1429 and status = 'failed';
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scholarship_coverage', 'read_now', v_qut::text, jsonb_build_object('listing', 1429, 'rows', v_n, 'on_demand', v_od->>'id',
          'reason', 'SS-Programme-Control 28 Nov 2026 07:22 AEDT: recover QUT listing 1429 (s1332)', 'migration', '20261201010000'), security.system_actor_id());
  -- 3. UQ College: the scholarship hub becomes a listing source, read now by the existing listing reader and its award-section readers
  insert into pipeline.scholarship_listing_pages(provider_id, url, url_norm, source, active, status, next_read_at, added_by)
  values (v_uqc, v_url, security.scholarship_url_norm(v_url), 'manual', true, 'waiting', null, security.system_actor_id())
  on conflict (provider_id, url_norm) do update set active = true, next_read_at = null,
     source = case when pipeline.scholarship_listing_pages.source = 'suggested' then 'manual' else pipeline.scholarship_listing_pages.source end,
     status = case when pipeline.scholarship_listing_pages.status in ('suggested', 'failed') then 'waiting' else pipeline.scholarship_listing_pages.status end;
  insert into pipeline.admin_control_events (area, action, target, detail, actor)
  values ('scholarship_coverage', 'add_listing', v_uqc::text, jsonb_build_object('url', v_url, 'candidate', 22521,
          'reason', 'SS-Programme-Control 28 Nov 2026 07:22 AEDT: UQ College award blocks through the s1035 and s1037 award-section readers; holds unchanged (s1332)', 'migration', '20261201010000'), security.system_actor_id());
end $a$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from s1332_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  if (select md5(to_jsonb(c)::text) from pipeline.scholarship_page_candidates c where c.id = 22521) is distinct from b.c22521 then raise exception 'post-check: candidate 22521 changed'; end if;
  if not exists (select 1 from pipeline.on_demand_requests r where r.state = 'open' and '2c4f515c-c146-4e90-ba8a-294130aa1f40' = any (r.provider_ids)
                 and r.purpose_groups = array['scholarships'] and r.toolsets = array['firecrawl'] and (r.estimate->>'cap_firecrawl_units')::int = 150) then
    raise exception 'post-check: the QUT on-demand request is not open, scoped and capped';
  end if;
  if security.on_demand_request_for_v2('2c4f515c-c146-4e90-ba8a-294130aa1f40', 'sch_scrape') is null or security.on_demand_request_for_v2('2c4f515c-c146-4e90-ba8a-294130aa1f40', 'map') is not null then
    raise exception 'post-check: the QUT request does not cover exactly the scholarship reads';
  end if;
  if not exists (select 1 from pipeline.scholarship_listing_pages where provider_id = '4d6daad6-d58d-43b3-ad22-9a5571aa4048' and url = 'https://uqcollege.uq.edu.au/apply/scholarships' and active and next_read_at is null) then
    raise exception 'post-check: the UQ College hub is not a listing source due now';
  end if;
end $p$;
