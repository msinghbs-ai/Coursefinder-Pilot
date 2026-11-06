-- Guards: Platform Admin 6 Nov 2026 09:44 §3 (do not infer English for an unrelated course; do not override an authoritative course-specific reading) and §4 (compatibility: manual locks, protected approvals) for English requirements.
-- UNSW's stored English page lists named courses inside a faculty cell ("Exceptions: - Bachelor of Education (Secondary) (Honours): 7.5 ..."). Runs after groups-tests.sql on the same database.
-- The proposal is the REAL v0.3.0 parser output on the verbatim stored page (pages/a1a0f40d-....md); the courses are invented rows, with real UNSW titles for the excepted courses.
\set ON_ERROR_STOP on
set session_replication_role = replica;
create or replace function pg_temp.ok(c boolean, what text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL %', what; end if; raise notice 'PASS %', what; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ad', false), set_config('request.jwt.claim.role', 'authenticated', false);
\set page `node tests/fixtures/english-requirements/groups.mjs parsed-page tests/fixtures/english-requirements/pages/a1a0f40d-001a-4df2-848e-0a49812a0ac8.md`

insert into catalogue.providers(id, stable_key, canonical_name, display_name, provider_type_id, lifecycle_status, publication_status, website) values
 ('00000000-0000-0000-0000-00000000b005', 'h-unsw', 'UNSW Fixture', 'UNSW Fixture', (select id from ref.provider_types where code = 'university'), 'active', 'published', 'https://www.unsw.fixture.example/');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, study_level_id, lifecycle_status, open_to_international)
select ('00000000-0000-0000-0000-0000000d0' || lpad(n::text, 3, '0'))::uuid, 'h-u' || n, '00000000-0000-0000-0000-00000000b005', t, (select id from ref.study_levels where code = lv), 'active', true
  from (values (1, 'Bachelor of Education (Secondary) (Honours)', 'bachelor'),         -- real title, an exception of Arts, Design & Architecture (IELTS 7.5)
               (2, 'Bachelor of Criminology & Criminal Justice', 'bachelor'),          -- real title, an exception of Law & Justice (IELTS 6.5, below the faculty 7.0)
               (3, 'Master of Teaching (Primary & Secondary)', 'masters_coursework'),  -- real title, an exception of Arts, Design & Architecture (IELTS 7.5)
               (4, 'Bachelor of Design', 'bachelor'),                                  -- a plain faculty course
               (5, 'Bachelor of Architecture', 'bachelor'),                            -- has its own page reading
               (6, 'Bachelor of Fine Arts', 'bachelor'),                               -- locked by hand
               (7, 'Master of Design', 'masters_coursework')) v(n, t, lv);
insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_requirement_key, status)
select '00000000-0000-0000-0000-0000000d0005', id, 8.0, '{}', 'from the course page', 'page:course-d5', 'active' from ref.english_tests where code = 'IELTS';
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', '00000000-0000-0000-0000-0000000d0006', 'english', 'value');

insert into pipeline.evidence_artifacts(id, storage_path) values ('00000000-0000-0000-0000-00000000e0b1', 'layer2/AU/provider-facts/fixture/unsw.md.gz');
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, evidence_id, content_hash)
values ('00000000-0000-0000-0000-00000000f0c1', '00000000-0000-0000-0000-00000000b005', 'english_policy', 'https://www.unsw.edu.au/study/how-to-apply/english-language-requirements', 't', 5, 'search', 'read', '00000000-0000-0000-0000-00000000e0b1', '1896907dc286e70309f8fcd4c0369fa6b99edcead772d817712f364cfd2ba36d');
select pg_temp.ok((public.svc_provider_policy_record('00000000-0000-0000-0000-00000000f0c1', :'page'::jsonb)->>'status') = 'proposed', 'the real UNSW page reading is filed as a proposal (course groups), never as a default');
select pg_temp.ok((select style = 'course_groups' and proposal->'defaults' = '{}'::jsonb from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0c1'), 'it carries groups and no university default');
select public.admin_provider_policy_decide((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0c1'), 'approve', 'fixture approval');
-- a person binds the Arts, Design & Architecture groups to the design and education courses by title (the exception courses are reached by the pattern too, on purpose)
select public.admin_provider_english_groups_set_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0c1'),
  '[{"group_name":"Arts, Design & Architecture","level":"undergraduate","title_regex":"^Bachelor of (Education|Design|Architecture|Fine Arts)"},
    {"group_name":"Arts, Design & Architecture","level":"postgraduate","title_regex":"^Master of (Teaching|Design)"},
    {"group_name":"Law & Justice","level":"undergraduate","title_regex":"^Bachelor of Criminology"}]'::jsonb, 'fixture binding of the real UNSW groups');

create temp table uplan as select * from security.provider_english_plan_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0c1'));
select pg_temp.ok((select plan||'/'||outcome from uplan where course_id = '00000000-0000-0000-0000-0000000d0004') = 'group/write', 'a plain faculty course (Bachelor of Design) takes the faculty score');
select pg_temp.ok((select plan||'/'||outcome from uplan where course_id = '00000000-0000-0000-0000-0000000d0007') = 'group/write', 'a plain postgraduate faculty course (Master of Design) takes the faculty score');
select pg_temp.ok((select plan from uplan where course_id = '00000000-0000-0000-0000-0000000d0001') <> 'group', 'Bachelor of Education (Secondary) (Honours), an exception the page lists, is not given the faculty score');
select pg_temp.ok((select plan from uplan where course_id = '00000000-0000-0000-0000-0000000d0002') <> 'group', 'Bachelor of Criminology & Criminal Justice, an exception the page lists, is not given the Law & Justice score');
select pg_temp.ok((select plan from uplan where course_id = '00000000-0000-0000-0000-0000000d0003') <> 'group', 'Master of Teaching (Primary & Secondary), an exception the page lists, is not given the faculty score');
select pg_temp.ok((select outcome from uplan where course_id = '00000000-0000-0000-0000-0000000d0005') in ('differs', 'agrees', 'other_value'), 'a course with its own page reading keeps it (outcome ' || coalesce((select outcome from uplan where course_id = '00000000-0000-0000-0000-0000000d0005'), '') || ')');
select pg_temp.ok((select outcome from uplan where course_id = '00000000-0000-0000-0000-0000000d0006') = 'set_by_hand', 'a course locked by hand is left alone');
select pg_temp.ok((select count(*) from uplan where plan = 'group' and course_id in ('00000000-0000-0000-0000-0000000d0001', '00000000-0000-0000-0000-0000000d0002', '00000000-0000-0000-0000-0000000d0003')) = 0, 'no excepted course is planned as a group');
select pg_temp.ok((select count(*) from uplan where outcome = 'write' and course_id in ('00000000-0000-0000-0000-0000000d0002', '00000000-0000-0000-0000-0000000d0003', '00000000-0000-0000-0000-0000000d0005', '00000000-0000-0000-0000-0000000d0006')) = 0, 'no excepted-and-held, own-reading or locked course is planned to be written');

select security.provider_english_apply_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0c1'));
select pg_temp.ok((select count(distinct course_id) from catalogue.course_english_requirements where course_id in ('00000000-0000-0000-0000-0000000d0004', '00000000-0000-0000-0000-0000000d0007') and status = 'active' and notes like 'English requirement for the course group%') = 2
  and (select count(*) from catalogue.course_english_requirements where course_id in ('00000000-0000-0000-0000-0000000d0004', '00000000-0000-0000-0000-0000000d0007') and status = 'active') = 8, 'the plain faculty courses were written (IELTS, TOEFL iBT, PTE, Cambridge), with the group named');
select pg_temp.ok((select overall_score from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000d0004' and source_requirement_key like '%:ielts') = 6.5, 'Bachelor of Design takes IELTS 6.5 from Arts, Design & Architecture');
select pg_temp.ok((select overall_score from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000d0001' and source_requirement_key like '%:ielts') = 7.5 and (select count(*) from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000d0001') = 1, 'Bachelor of Education (Secondary) (Honours) holds the 7.5 the page names for it, never the faculty 6.5'); 
select pg_temp.ok((select count(*) from catalogue.course_english_requirements where course_id in ('00000000-0000-0000-0000-0000000d0001', '00000000-0000-0000-0000-0000000d0002', '00000000-0000-0000-0000-0000000d0003') and notes like 'English requirement for the course group%') = 0, 'no excepted course holds a faculty-group row');
select pg_temp.ok((select overall_score from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000d0005') = 8.0 and (select count(*) from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000d0005') = 1, 'the course page reading (8.0) is untouched and no second row was added');
select pg_temp.ok((select count(*) from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000d0006') = 0, 'the locked course got no row');
\echo english exception scenarios: passed
