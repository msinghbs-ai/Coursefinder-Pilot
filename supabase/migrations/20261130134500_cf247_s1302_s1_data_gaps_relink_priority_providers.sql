-- CF-247 s1302 (S1-Data-Gaps; SS-Programme-Control 27 Nov 2026 12:00 AEDT, International Course Source Integrity, Admin #1271, S1-DG-5 option A):
-- send the priority providers' parked course pages to the existing course relink route, so a dead or weakly proved official page is found again and
-- proved by the platform's own identity rule (the exact CRICOS code in Australia) before any binding changes.
-- Found live (27 Nov 2026, read through the rolled-back rehearsal, no interactive SQL):
--   Swinburne University of Technology: 411 active courses; 165 bound pages are fetch_failed with HTTP 404 (dead addresses, not a refusal); 176 courses are
--   parked in pipeline.source_proof_requests as held / no_route. Western Sydney University: 35 bound pages 404 (retired year handbook paths), 38 held / no_route.
--   Charles Darwin University: 9 held / no_route (10 identity_mismatch, 11 page_refused, 17 exhausted are NOT touched). Kaplan Business School: 4 held /
--   no_route (5 courses already relinked three times with relink_absent are NOT touched; no unchanged futile retry).
--   Course relink is the route those requests wait for (s1196: "held for want of a route: relink is that route now"), and nothing queued them.
-- What this does: moves exactly those held / no_route requests, at the four providers, to route relink, state queued, with the reason in detail.
--   Course relink (security.course_relink_tick_v1, job course-relink) then works them through its existing time budget and settings, reads pages plainly
--   (no model), takes no candidate on a retired host, and changes a binding only when the reader proves the exact course. A page locked by hand is left alone.
-- Not done here: audience proof (S1-Build worker verification, design #1271 phase B). A successor page is proved for identity, not audience; the 33
--   international-tagged links with a domestic path are not requeued (their pages read fine; they wait for audience verification). Toi Ohomai (NZ) stays with
--   its territorial owner. No link, value, lock, cron job or setting is changed by this file. No new job, queue or table.
-- G1: no job. G2: no new value. G3: no consumer object changed (checked before and after). Locks and cron checked unchanged. Spend: US$0.
-- Replaces: nothing (data only). Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check and one counted update

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

create temp table s1302_guard on commit drop as
select (select count(*) from cron.job) cron_before,
       (select count(*) from pipeline.manual_locks) locks_before,
       (select count(*) from catalogue.course_links) links_before,
       (select count(*) from catalogue.course_links where link_type = 'official_course' and status = 'active') official_before,
       (select count(*) from pipeline.coverage_course_pages) pages_before,
       (select count(*) from pipeline.source_proof_requests) requests_before;

-- the cohort: held for want of a route, at the four priority providers, for courses that are still active (the same test s1196 used)
create temp table s1302_due on commit drop as
select s.course_id, s.provider_id
  from pipeline.source_proof_requests s
  join catalogue.courses c on c.id = s.course_id and c.lifecycle_status = 'active'
 where s.state = 'held' and s.route = 'no_route'
   and s.provider_id in ('349da14b-66b1-4c57-9dfd-6f9c36412432'::uuid,   -- Swinburne University of Technology
                         '1719c3ba-1ddf-483e-935e-c750124ba99c'::uuid,   -- Western Sydney University
                         '6f5cb7f7-7c70-4c06-970f-f368c3a786e2'::uuid,   -- Charles Darwin University
                         '5fac5555-18f9-4bc7-91e4-e1466f8e33e3'::uuid);  -- Kaplan Business School Pty Ltd

do $c$
declare v_n int := (select count(*) from s1302_due);
begin
  if v_n < 150 or v_n > 300 then raise exception 's1302: % parked courses at the four providers, not the 227 measured', v_n; end if;  -- fixed: the measured cohort's size (176 + 38 + 9 + 4) with room for movement since
end $c$;

do $m$
declare v_q int; v_reason text := 'S1-DG-5 (SS-Programme-Control 27 Nov 2026 12:00): dead or weakly proved official pages found again by course relink; identity proved by the exact CRICOS code; audience proof is S1-Build phase B';
begin
  update pipeline.source_proof_requests s
     set route = 'relink', state = 'queued', attempts = 0, requested_at = now(), settled_at = null, outcome = null,
         detail = jsonb_build_object('reason', v_reason, 'by', 'migration CF-247 s1302', 'previous', jsonb_build_object('route', s.route, 'state', s.state))
   where s.course_id in (select course_id from s1302_due) and s.state = 'held' and s.route = 'no_route';
  get diagnostics v_q = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('coverage', 'priority_provider_relink', 'pipeline.source_proof_requests',
          jsonb_build_object('reason', v_reason, 'by', 'migration CF-247 s1302', 'queued', v_q,
                             'by_provider', (select jsonb_object_agg(provider_id::text, n) from (select provider_id, count(*) n from s1302_due group by 1) z)), null);
end $m$;

do $p$
declare v jsonb := security.consumer_api_check_v1(); b record; v_left int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  select * into b from s1302_guard;
  if (select count(*) from cron.job) <> b.cron_before then raise exception 'post-check: the number of cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from catalogue.course_links) <> b.links_before then raise exception 'post-check: course links changed'; end if;
  if (select count(*) from catalogue.course_links where link_type = 'official_course' and status = 'active') <> b.official_before then raise exception 'post-check: official links changed'; end if;
  if (select count(*) from pipeline.coverage_course_pages) <> b.pages_before then raise exception 'post-check: course pages changed'; end if;
  if (select count(*) from pipeline.source_proof_requests) <> b.requests_before then raise exception 'post-check: a request was added or removed'; end if;
  select count(*) into v_left from pipeline.source_proof_requests s join s1302_due d on d.course_id = s.course_id where s.state = 'held' and s.route = 'no_route';
  if v_left <> 0 then raise exception 'post-check: % cohort requests are still held for want of a route', v_left; end if;
  if (select count(*) from pipeline.source_proof_requests s join s1302_due d on d.course_id = s.course_id where s.route = 'relink' and s.state = 'queued') <> (select count(*) from s1302_due) then
    raise exception 'post-check: not every cohort request is queued for relink';
  end if;
end $p$;
