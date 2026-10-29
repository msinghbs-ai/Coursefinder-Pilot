-- CF-247 decision W30 (Workstream 2, enrichment reliability incident; hourly health report 23:20 AEDT 29 Oct 2026: "course source finder
-- failed on every call", "adapter capture failed", "one course-list read took 115 seconds"). Evidence: lane G handback (read-only, 29-30 Oct).
-- Three database defects proven live; each is corrected here with an md5-guarded edit of the live definition. Nothing else changes.
--   1. Course source finder (job source-find, worker mode source_find): public.svc_source_find_next timed out at the 8-second API limit on
--      12 of 18 calls 18:16-23:56 AEDT and on 80 of 143 calls in 48 h ("svc_source_find_next: canceling statement due to statement
--      timeout"). Its candidate scan ran three correlated counts per provider and the hidden-provider view once per provider
--      (1.2 million buffers, 2.8 s with the database idle, past 8 s under load). The same scan now works each set out once
--      (excluded providers, eligible providers, course counts grouped by provider): 45 thousand buffers, 0.3 s, and the same 748
--      candidates in the same order (checked live, read-only). Picking, leasing, the returned shape and every setting are unchanged.
--   2. Course page reads (jobs coverage-read and coverage-read-2, both every 30 seconds, worker mode read): public.svc_coverage_read_next
--      chose its pages without locking them, so two calls a second apart both leased the same page (read_attempts went up by 2, one
--      read_at) and Firecrawl was paid twice: 767 of 3,083 scrape credits in 7 days were a second fetch of the same address within
--      5 seconds. The lease update now re-checks the lease on the locked row (the claim pattern of svc_scholarship_candidate_next), so a
--      page is claimed by exactly one call; the other call simply gets fewer pages.
--   3. Onboarding jobs: security.provider_onboarding_job_v1 found the job it had just started as "the newest job of this kind started by
--      this user"; the onboarding tick starts several universities' jobs in one transaction as the same user, so each university could
--      track another's job (live: 2 of the 3 onboarding rows that hold a job track another university's course_page_find job; the three
--      jobs started at 22:57 are all tracked by one university's row). The lookup now also requires the job to be for this university.
-- Not changed here (reported for decision, not coded around): edge runtime failures (BOOT_ERROR, 502, 546 WORKER_RESOURCE_LIMIT,
-- SUPABASE_EDGE_RUNTIME_SERVICE_DEGRADED) that stopped the 23:10 adapter capture before the worker started; the course-list read time
-- (110-second worker budget plus an in-flight Firecrawl scrape of up to 60 seconds, recorded in full; pg_net stops waiting at 120 s).
-- Replaces: public.svc_source_find_next, public.svc_coverage_read_next, security.provider_onboarding_job_v1 (same names, md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job, table, setting or status value. Consumer API untouched (G3).

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1. The source finder's candidate scan, worked out once per set instead of once per provider (same candidates, same order).
select pg_temp.edit_n('public.svc_source_find_next(integer,uuid[])', '57a32d94f5c70321a207a39683260a64', array[
  array[$o$    insert into _sf_pick
    with cand as (
      select p.id, (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') active,
             (select count(*) from catalogue.courses c join pipeline.coverage_course_pages pg on pg.course_id = c.id and pg.status = 'bound' and pg.read_status = 'read'
               where c.provider_id = p.id and c.lifecycle_status = 'active') paged,
             (select count(*) from catalogue.courses c where c.provider_id = p.id) all_courses
        from catalogue.providers p
       where p.enrols_international is true and coalesce(p.lifecycle_status, 'active') = 'active' and p.website is not null
         and security.coverage_country(p.id) in (select x.country_code from pipeline.source_find_countries x where x.enabled)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
         and not exists (select 1 from pipeline.provider_course_lists l where l.provider_id = p.id and l.status <> 'stopped')
         and not exists (select 1 from pipeline.programme_sources s where s.provider_id = p.id and s.status <> 'stopped')
         and not exists (select 1 from pipeline.source_find_runs r where r.provider_id = p.id
                           and (r.state in ('found', 'tested') or coalesce(r.next_try_at, now()) > now() or coalesce(r.leased_until, '-infinity') > now())))
    select c.id from cand c$o$,
        $n$    insert into _sf_pick
    -- W30 (30 Oct 2026): each set is worked out once (it was three counts and the hidden-provider view per provider, past the 8-second limit)
    with excl as materialized (
      select h.provider_id from security.provider_hidden_v1 h
      union select l.provider_id from pipeline.provider_course_lists l where l.status <> 'stopped'
      union select s.provider_id from pipeline.programme_sources s where s.status <> 'stopped'
      union select r.provider_id from pipeline.source_find_runs r
             where r.state in ('found', 'tested') or coalesce(r.next_try_at, now()) > now() or coalesce(r.leased_until, '-infinity') > now()),
    prov as materialized (
      select p.id from catalogue.providers p join ref.countries k on k.id = p.country_id
       where p.enrols_international is true and coalesce(p.lifecycle_status, 'active') = 'active' and p.website is not null
         and k.iso_alpha2::text in (select x.country_code from pipeline.source_find_countries x where x.enabled)
         and not exists (select 1 from excl e where e.provider_id = p.id)),
    cand as materialized (
      select c.provider_id id, count(*) all_courses, count(*) filter (where c.lifecycle_status = 'active') active,
             count(*) filter (where c.lifecycle_status = 'active' and exists (select 1 from pipeline.coverage_course_pages pg
                                                                            where pg.course_id = c.id and pg.status = 'bound' and pg.read_status = 'read')) paged
        from catalogue.courses c join prov on prov.id = c.provider_id group by c.provider_id)
    select c.id from cand c$n$],
  array[$o$     order by (c.active - c.paged) desc, c.all_courses desc
     limit greatest(0,$o$,
        $n$     order by (c.active - c.paged) desc, c.all_courses desc, c.id
     limit greatest(0,$n$]], array[1, 1]);

-- 2. One claim per course page: the lease is re-checked on the locked row, so a second read call never takes a page another call holds.
select pg_temp.edit_n('public.svc_coverage_read_next(integer)', 'a8bfed7cfbf67741b8891ffadadf73e5', array[
  array[$o$from pick where p.course_id=pick.course_id returning p.course_id, p.provider_id, p.url$o$,
        $n$from pick where p.course_id=pick.course_id and coalesce(p.leased_until,'-infinity')<now()  -- W30: re-checked on the locked row; one claim per page
            returning p.course_id, p.provider_id, p.url$n$]], array[1]);

-- 3. An onboarding step tracks its own university's job, never the newest job another university started in the same tick.
select pg_temp.edit_n('security.provider_onboarding_job_v1(text,uuid,jsonb)', 'ab742e1eb06da68fa0d795229e505737', array[
  array[$o$where j.kind = p_kind and j.requested_by = auth.uid() order by j.created_at desc limit 1;$o$,
        $n$where j.kind = p_kind and j.requested_by = auth.uid()
     and (j.scope = p_provider::text or j.args->>'provider_id' = p_provider::text or j.args->'provider_ids' ? p_provider::text)  -- W30: this university's job
   order by j.created_at desc limit 1;$n$]], array[1]);

-- post-check: the three definitions carry the corrections
do $g$ begin
  if pg_get_functiondef('public.svc_source_find_next(integer,uuid[])'::regprocedure) ~ 'security\.coverage_country\(p\.id\)' then
    raise exception 'W30 post-check: svc_source_find_next still works out the country once per provider'; end if;
  if pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure) !~ 'pick\.course_id and coalesce\(p\.leased_until' then
    raise exception 'W30 post-check: svc_coverage_read_next does not re-check the lease'; end if;
  if pg_get_functiondef('security.provider_onboarding_job_v1(text,uuid,jsonb)'::regprocedure) !~ 'W30: this university''s job' then
    raise exception 'W30 post-check: provider_onboarding_job_v1 lookup is not scoped to the university'; end if;
end $g$;

select 'W30: source finder scan, one claim per course page, onboarding job per university' ok;
