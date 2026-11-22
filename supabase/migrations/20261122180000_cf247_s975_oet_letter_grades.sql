-- CF-247 s975 (session S1-API-Frontend-Delivery, consolidated batch Part 3; Platform Admin 22 Nov 2026 14:22 AEDT): REQ-34 OET letter grades.
-- The 256 active OET requirements (Flinders University's English language policy, Decision 227) hold OET scores (overall 300, and 300 in
-- each sub-test listed) but no letter grade, so the Zoho API v3 columns oet_grade and oet_subtest_grades were empty. OET reports each score
-- with a letter grade on one published scale (A 450-500, B 350-440, C+ 300-340, C 200-290, D 100-190, E 0-90; OET, as reproduced in the GMC
-- tribunal circular on OET changes). This fills score_grade from the overall score and subtest_grades from each sub-test score on that scale.
-- Deterministic, from the stored values only ($0: no page read, no AI). Only empty grades are filled; a course whose English is locked by a
-- person is left alone. Live on deploy.
-- Consumer API untouched (G3 checked before and after; values only, no column or function changed). G1: no new job. G2: no operational
-- value (the scale is the test's published reference data, applied once here). Locks unchanged.
-- Parity: live head 20261122170000 (s973) read 22 Nov 2026 17:00 AEDT; this file is numbered above it.
-- Replaces: nothing (OET grades were never filled).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s975_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s975_cron on commit drop as select count(*) n from cron.job where active;

-- OET's published score-to-grade scale (reference data)
create temp table s975_oet_scale (grade text, low numeric, high numeric) on commit drop;
insert into s975_oet_scale values ('A', 450, 500), ('B', 350, 449), ('C+', 300, 349), ('C', 200, 299), ('D', 100, 199), ('E', 0, 99);

create temp table s975_done (n int) on commit drop;
do $u$
declare v_n int;
begin
  with oet as (
    select r.id, r.overall_score, r.component_scores
      from catalogue.course_english_requirements r
      join ref.english_tests t on t.id = r.english_test_id
     where upper(t.code) = 'OET' and r.status = 'active' and r.score_grade is null
       and r.overall_score between 0 and 500
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.field = 'english' and l.entity_id::text = r.course_id::text)
  ), graded as (
    select o.id,
           (select s.grade from s975_oet_scale s where o.overall_score between s.low and s.high) grade,
           (select jsonb_object_agg(c.key, s.grade order by c.key)
              from jsonb_each(coalesce(o.component_scores, '{}'::jsonb)) c
              join s975_oet_scale s on jsonb_typeof(c.value) = 'number' and (c.value)::numeric between s.low and s.high) subtests
      from oet o
  )
  update catalogue.course_english_requirements r
     set score_grade = g.grade,
         subtest_grades = coalesce(r.subtest_grades, g.subtests)
    from graded g
   where r.id = g.id and g.grade is not null;
  get diagnostics v_n = row_count;
  insert into s975_done values (v_n);
end $u$;

do $c$
declare v_api jsonb := security.consumer_api_check_v1(); v_left int;
begin
  select count(*) into v_left from catalogue.course_english_requirements r join ref.english_tests t on t.id = r.english_test_id
   where upper(t.code) = 'OET' and r.status = 'active' and r.score_grade is null and r.overall_score between 0 and 500
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.field = 'english' and l.entity_id::text = r.course_id::text);
  if v_left <> 0 then raise exception 'post-check: % OET requirements still have no letter grade', v_left; end if;
  raise notice 's975: % OET requirements graded', (select n from s975_done);
  if (select count(*) from cron.job where active) <> (select n from s975_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s975_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
