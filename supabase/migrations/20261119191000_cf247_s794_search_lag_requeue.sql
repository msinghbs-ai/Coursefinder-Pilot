-- CF-247 s794 (Platform Admin 19 Nov 2026 23:15 AEDT handover, Part 2 item 2: "fix any non-API projection lags"; chat S1-Build).
-- Found (rolled-back live reads through GitHub Actions, 20 Nov 2026 00:00-00:10 AEDT, s792 assessment):
--   - 48 AU, NZ and CA courses hold an active intake, an active English requirement or an official link in the catalogue that their search
--     document (search.course_documents) does not show; the sampled documents were built at 07:45 AEDT on 19 Nov, before those rows arrived;
--   - nothing asked for them to be rebuilt: search.course_refresh_requests was empty, and catalogue.course_intakes and
--     catalogue.course_english_requirements have no trigger that asks for a refresh (the producer gap is a follow-up, not changed here).
-- What changes: one request a course in search.course_refresh_requests for exactly those courses; the existing job search-course-refresh
-- (security.search_course_refresh_drain_v1, every minute, batch.search_course_refresh 300) rebuilds them. No table, function, job or setting;
-- nothing is deleted; the consumer API is read the same way (only the 48 documents are rebuilt by the existing path).
-- Replaces: nothing. Retires: nothing.
-- G1: no job. G2: no setting. G3: untouched (75 functions, 48 tables).

with lag as (
  select distinct cd.course_id
    from search.course_documents cd join catalogue.courses c on c.id = cd.course_id
   where cd.country_code in ('AU', 'NZ', 'CA')
     and ((not coalesce(cd.has_intake, false) and exists (select 1 from catalogue.course_intakes i where i.course_id = cd.course_id and i.status = 'active'))
       or (not coalesce(cd.has_english, false) and exists (select 1 from catalogue.course_english_requirements e where e.course_id = cd.course_id and e.status = 'active'))
       or (cd.official_course_url is null and c.course_url is not null)))
insert into search.course_refresh_requests (course_id, requested_at, requested_by)
select l.course_id, now(), 's794_projection_lag'
  from lag l
 where not exists (select 1 from search.course_refresh_requests r where r.course_id = l.course_id and r.processed_at is null);

-- post-check: every lagging course is queued once, and nothing else was queued by this change
do $$
declare v_q int := (select count(*) from search.course_refresh_requests where requested_by = 's794_projection_lag' and processed_at is null);
begin
  if v_q = 0 then raise exception 'post-check: no lagging course was queued'; end if;
  if v_q > 500 then raise exception 'post-check: % courses queued, more than the measured lag (48); refusing', v_q; end if;
  perform set_config('cf.diag', format('queued %s courses for search-course-refresh', v_q), true);
end $$;
