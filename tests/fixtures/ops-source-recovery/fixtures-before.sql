-- Today's defects on the live definitions (rolled back: the migration then runs on the seed as it is).
begin;
do $b$
declare r jsonb; v text;
begin
  r := security.source_proof_feed_v1();
  -- S1: one free relink a run (proof.feed_per_run 1 here); the other identity_mismatch courses are recorded as needing paid search
  select route into v from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000002';
  if v <> 'no_route' then raise exception 'before S1: course 2 is %, expected no_route', v; end if;
  -- S3: a page refused by the E16 check has no free route
  select route into v from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000003';
  if v <> 'no_route' then raise exception 'before S3: course 3 is %', v; end if;
  -- S4: a course known only by its absence record is not considered
  if exists (select 1 from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000012') then raise exception 'before S4'; end if;
  raise notice 'before: S1 course 2 recorded no_route (capacity), S3 identity_refused course 3 no_route, S4 absence-only course 12 never considered (routed %)', r->'routed';
  -- S6: course-relink offers course 13 its own refused page in another spelling
  perform security.course_relink_provider_v1('a1000000-0000-0000-0000-000000000001', 50);
  if not exists (select 1 from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000013' and candidates ? 'http://u1.example/study/ba-arts-studies-program') then
    raise exception 'before S6: expected course 13 to be offered its refused page'; end if;
  if exists (select 1 from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000003') then raise exception 'before S3: relink took identity_refused'; end if;
  raise notice 'before: S6 course 13 offered its own refused page (http, no www, no trailing slash); S3 course 3 not relinked';
end $b$;
rollback;
