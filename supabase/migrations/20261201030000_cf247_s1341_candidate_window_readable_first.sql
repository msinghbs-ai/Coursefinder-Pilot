-- CF-247 s1341 (S2-Build; SS-Programme-Control instruction PC-20261128-0931-S2-Build, 28 Nov 2026: "Trace 29/30 capped leases and quantify actual eligible
-- versus cap-blocked; prefer existing per-host defer/retry or selector capability within authority ... no setting change without approval").
-- Traced live (28 Nov 2026 09:55 to 10:20 AEDT, rolled-back reads):
--   * 1,959 candidate pages are due. 1,742 (23 providers: AU 687, CA 1,055) belong to providers whose paid read is refused (security.fc_sch_held_v1:
--     20 by the per-university cap, 3 by the spend rule). 217 (5 providers) are readable either way: RMIT 191, UQ College 16, three others 10.
--   * In the last two hours no candidate was read directly; 8 were read through Firecrawl (6 of them QUT's, through its on-demand request). Each call
--     leases 30, and 29 come back waiting_scraper: the paid-held pages' direct copies are not usable evidence.
--   * Why the readable pages never get a turn: the window takes each country's oldest pages first (s1054), the paid-held pages are older, and the
--     one-hour waiting-for-scraper retry (DR-15) returns them every hour, so the 600-page window is refilled with them before RMIT's 191 (attempts 0,
--     due, no refusal, no Firecrawl call since 25 Nov) or UQ College's 16 are reached.
-- Change (the existing selector, within authority; no setting changed): the picker keeps every rule and order it has, and puts first the pages of
-- providers whose page can be read either way. A provider whose paid read is refused and no open on-demand request covers still gets its free
-- direct read (DR-15) as soon as the readable pages are leased. One security.fc_sch_held_v1 call per due provider (about 28, the s981 cheap order).
-- G1: no job. G2: no value (retry.scholarship_waiting_scraper_hours stays 1; a change to it is the Platform Admin's). G3: 75/48 checked. Locks and
-- active cron jobs checked unchanged. Nothing dropped or deleted. $0.
-- Replaces: public.svc_scholarship_candidate_next (same function, readable pages first).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and one function replacement

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_scholarship_candidate_next(integer)'::regprocedure)) <> '470411a97f69be25315d921c5c257052' then
    raise exception 'guard: public.svc_scholarship_candidate_next is not the s1332 definition';
  end if;
end $g$;
create temp table s1341_base on commit drop as select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_ok uuid[] := '{}'; v_p record; v_task uuid[]; v_paid uuid[] := '{}';
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
       and not security.provider_sch_search_off_v1(v_p.provider_id) then
      v_ok := v_ok || v_p.provider_id;
      -- CF-247 s1341 (S2-Build, PC-20261128-0931-S2-Build): a provider whose paid read is refused (its per-university cap or the scholarship spend rule,
      -- security.fc_sch_held_v1) and no open on-demand request covers is still pickable for its free direct read (DR-15), but after every provider
      -- whose page can be read either way: with the one-hour waiting-for-scraper retry its older pages filled the whole window (28 Nov 2026 09:55 AEDT:
      -- 1,742 such pages at 23 providers took 29 of every 30 leases; 217 readable pages, 191 of them RMIT's, never reached the window)
      if security.fc_sch_held_v1(v_p.provider_id, true) and security.on_demand_request_for_v2(v_p.provider_id, 'sch_scrape') is null then v_paid := v_paid || v_p.provider_id; end if;
    end if;
  end loop;
  -- CF-247 s1332: the window keeps each page's site host, so the directory-site rule is asked once per host below (it depends on the host only)
  create temp table if not exists sch_cand_win_v4(id bigint, provider_id uuid, url text, requested boolean, tier int, priority int, found_at timestamptz, cc text, host text, paid_held boolean) on commit drop;
  truncate sch_cand_win_v4;
  insert into sch_cand_win_v4
  select z.id, z.provider_id, z.url, z.requested, z.tier, z.priority, z.found_at, z.cc, security.site_host_v1(z.url), z.paid_held from (
    select c.id, c.provider_id, c.url, c.provider_id = any (v_task) requested, coalesce(d.tier, 9) tier, d.priority, c.found_at, coalesce(co.iso_alpha2::text, '--') cc, c.provider_id = any (v_paid) paid_held,
           -- CF-247 s1054: the window takes each country in turn, so one country's older backlog never fills it
           row_number() over (partition by coalesce(co.iso_alpha2::text, '--') order by (c.provider_id = any (v_task)) desc, coalesce(d.tier, 9), (d.priority not in (0,3)), c.found_at, c.id) crk
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
      join catalogue.providers p on p.id = c.provider_id left join ref.countries co on co.id = p.country_id
     where c.provider_id = any (v_ok) and c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3) z
   order by z.requested desc, z.paid_held, z.crk, z.cc  -- s1341: pages readable either way first
   limit greatest(1, security.pipeline_num_v1('scholarship.candidate_pick_window', 600)::int);
  -- CF-247 s1332 (S2-Build, SS-Programme-Control 28 Nov 2026 07:22 AEDT): security.third_party_host_v1 reads only security.site_host_v1 of its address, so it is
  -- asked once per distinct host of the window (about 40) instead of once per page (600): the same pages pass. Asked per page it took 6.6 s of the call's
  -- 8 s statement limit, and every candidate run from 27 Nov 2026 20:00 AEDT was cancelled (mode_outcome_ledger: statement timeout).
  with hosts as (
    select w.host, security.third_party_host_v1(min(w.url)) directory_site from sch_cand_win_v4 w group by w.host),
  ranked0 as (
    select w.id, w.requested, w.tier, w.priority, w.cc, w.paid_held, row_number() over (partition by w.provider_id order by (w.url ~* 'international') desc, w.found_at, w.id) rn
      from sch_cand_win_v4 w join hosts h on h.host is not distinct from w.host where not h.directory_site),
  ranked as (
    -- CF-247 s1054: within a country the providers take turns (rn), and the countries take turns (crk)
    select r0.*, row_number() over (partition by r0.requested, r0.cc order by r0.rn, r0.tier, (r0.priority not in (0,3)), r0.id) crk from ranked0 r0),
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by r.requested desc, r.paid_held, r.crk, r.cc, c.id
     limit greatest(1,least(coalesce(p_limit,30), security.pipeline_num_v1('scholarship.candidates_max', 60)::int)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id  -- fixed: claim lease
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;

comment on function public.svc_scholarship_candidate_next(integer) is 'CF-247 s1341: leases due scholarship candidate pages (DR-15 holds; country and provider turns; directory-site rule once per host, s1332); pages of providers whose paid read is refused and not covered on demand come after the pages readable either way.';

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from s1341_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  if security.pipeline_num_v1('retry.scholarship_waiting_scraper_hours', 1) <> 1 then raise exception 'post-check: the retry setting is not as read'; end if;
end $p$;
