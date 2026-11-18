-- CF-247 S2-BOOST-Discovery (Platform Admin handover mandate Thu 19 Nov 2026 07:39, decision 3, s659): the course pages the course-link
-- search found, whose read never finished, are released so the page reader reads them. No search credit is used.
-- What was read live (19 Nov 2026 07:39 AEDT, SELECT only): 11 pages the searches of the Course page needed window (18 Nov 2026) found
-- (UVic 8, Seafood Training Services 2, PBRS 1) have no read result, no identity proof and no stored reading. Each was claimed by the reader
-- three times with no result recorded; the last lease ended 18 Nov 18:11 AEDT. The reader (public.svc_coverage_read_next) takes only pages
-- with fewer than its cap of attempts, so a page that used all its attempts without a result is never taken again.
-- 95 more binder rows are in the same state (85 of them found by older searches, mostly UVic); they are outside this decision and stay as they are.
-- This releases exactly those pages, the same first step as public.admin_course_read_now: next_read_at now, attempts reset, lease cleared.
-- It does not call security.course_page_rebind_v1 and does not touch a page that has a read result or a proof (the 55 ANU and La Trobe
-- pages, proved by CRICOS code, stay as they are, Platform Admin 19 Nov 07:39 decision 2). The reader queue was empty at the time (0 eligible),
-- so no priority entry is made. Reading uses a direct fetch first; a page that needs rendering is read inside the reading share, not the
-- course-search share.
-- Data update only; no table, function, job or setting is added (G3 75/48). Idempotent: with nothing left to release it does nothing.
-- Numbered 20261119085000: above the highest migration on main (20261119082000) and clear of open PRs (084000 #1344, 083300 #1352).
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';
set local statement_timeout = '60s';  -- fixed: one small data update

do $s659$
declare v_ids uuid[]; v_n int; v_done int; v_eligible int;
begin
  -- the reader's own conditions must still be these (a page past its attempts is not eligible)
  if (select prosrc from pg_proc where oid = 'public.svc_coverage_read_next(integer)'::regprocedure) not like '%p.read_attempts<3%' then
    raise exception 'guard: the reader no longer limits a page by its attempts';
  end if;

  v_ids := array(
    select p.course_id
      from pipeline.coverage_course_pages p
      join pipeline.course_link_search s on s.course_id = p.course_id and s.provider_id = p.provider_id and s.state = 'found' and s.bound_url = p.url
       -- only pages found by the searches of the Course page needed window (S656 on-demand request), not the older found pages
       and s.done_at >= (select min(r.opened_at) from pipeline.on_demand_requests r where r.reason like '[S656 course page search]%')
     where p.status = 'bound' and p.read_status is null and p.read_at is null and p.identity_basis is null and p.evidence_id is null and p.candidates is null
       and p.read_attempts > 0 and coalesce(p.next_read_at, p.bound_at) <= now() and coalesce(p.leased_until, '-infinity') < now()
       and not exists (select 1 from security.coverage_read_eligible_v1() e where e.course_id = p.course_id)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = p.course_id and l.field in ('official_url', 'course_url')));
  v_n := coalesce(cardinality(v_ids), 0);
  if v_n = 0 then raise notice 'S659: no found page is waiting unread past its attempts; nothing to release'; return; end if;

  update pipeline.coverage_course_pages p
     set next_read_at = now(), read_attempts = 0, leased_until = null
   where p.course_id = any (v_ids) and p.status = 'bound' and p.read_status is null and p.identity_basis is null and p.candidates is null;
  get diagnostics v_done = row_count;
  if v_done <> v_n then raise exception 'post-check: % pages selected, % released', v_n, v_done; end if;

  select count(*) into v_eligible from security.coverage_read_eligible_v1() e where e.course_id = any (v_ids);
  if v_eligible <> v_n then raise exception 'post-check: % pages released but % are eligible for the reader', v_n, v_eligible; end if;

  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'read_released', 'found pages unread past their attempts (s659)',
          jsonb_build_object('released', v_n, 'course_ids', to_jsonb(v_ids),
                             'approval', 'Platform Admin 19 Nov 2026 07:39, S2-BOOST-Discovery handover decision 3',
                             'search_credits', 0), null);
  raise notice 'S659: % found pages released to the reader, all eligible; no search credit used', v_n;
end $s659$;
