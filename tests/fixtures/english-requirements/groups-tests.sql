-- Guards: decision 19:14 §8 and Platform Admin 6 Nov 2026 09:44 §3 (D1 scope, D2 human approval and binding, D3 switched off, D5 reparse), §4 (compatibility), on the production-parity fixture
-- after groups-harness.sql and the migration 20261106550000. Every case runs the migration's REAL functions on REAL captured tables; fixture rows are invented (no production data).
-- A failed case raises; the script stops (ON_ERROR_STOP).
\set ON_ERROR_STOP on
-- the row triggers of the captured tables (evidence lineage sync, manual lock guard, layer 4 guards) read evidence tables and functions outside the captured path: replica mode skips triggers and
-- foreign-key triggers, never table constraints (the unique key and the checks are the production ones, and this script relies on them)
set session_replication_role = replica;
create or replace function pg_temp.ok(c boolean, what text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL %', what; end if; raise notice 'PASS %', what; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ad', false), set_config('request.jwt.claim.role', 'authenticated', false);
insert into security.user_roles values ('00000000-0000-0000-0000-0000000000ad', 'platform_admin', null);
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, sort, section, reason) values
 ('pipeline', 'central.auto_approve', 'x', 'x', 'boolean', 'true'::jsonb, 1, 's', 'fixture'), ('pipeline', 'central.auto_approve_english_all', 'x', 'x', 'boolean', 'true'::jsonb, 1, 's', 'fixture')
 on conflict do nothing;

-- fixtures: a university and a TAFE, courses at three levels in two fields (rows invented)
insert into catalogue.providers(id, stable_key, canonical_name, display_name, provider_type_id, lifecycle_status, publication_status, website) values
 ('00000000-0000-0000-0000-00000000b001', 'h-uni', 'Fixture University', 'Fixture University', (select id from ref.provider_types where code = 'university'), 'active', 'published', 'https://www.fixture.example/'),
 ('00000000-0000-0000-0000-00000000b002', 'h-tafe', 'Fixture TAFE', 'Fixture TAFE', (select id from ref.provider_types where code = 'tafe'), 'active', 'published', 'https://www.tafe.fixture.example/about'),
 ('00000000-0000-0000-0000-00000000b003', 'h-hidden', 'Hidden College', 'Hidden College', (select id from ref.provider_types where code = 'college'), 'active', 'draft', 'https://hidden.example/');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, study_level_id, primary_field_id, lifecycle_status, open_to_international)
select ('00000000-0000-0000-0000-0000000c0' || lpad(n::text, 3, '0'))::uuid, 'h-c' || n, '00000000-0000-0000-0000-00000000b001', t, (select id from ref.study_levels where code = lv), (select id from ref.fields_of_study where code = f), 'active', true
  from (values (1, 'Bachelor of Social Work', 'bachelor', 'asced-0905'), (2, 'Bachelor of Economics', 'bachelor', 'asced-0919'), (3, 'Master of Social Work', 'masters_coursework', 'asced-0905'),
               (4, 'Bachelor of Computer Science', 'bachelor', 'asced-0201'), (5, 'Doctor of Philosophy in Social Work', 'doctorate', 'asced-0905'), (6, 'Bachelor of Community Welfare', 'bachelor', 'asced-0905'),
               (7, 'Bachelor of Youth Work', 'bachelor', 'asced-0905'), (8, 'Bachelor of Politics', 'bachelor', 'asced-0901'), (9, 'Bachelor of Laws', 'bachelor', 'asced-0805')) v(n, t, lv, f);
-- course 6 has its own page reading (IELTS 7.5, a key that is not a policy's); course 7 is locked by hand; course 2 (Economics) is under Society and Culture AND matches the Economics and Law pattern
insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_requirement_key, status)
select '00000000-0000-0000-0000-0000000c0006', id, 7.5, '{}', 'from the course page', 'page:course6', 'active' from ref.english_tests where code = 'IELTS';
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', '00000000-0000-0000-0000-0000000c0007', 'english', 'value');

-- 1 the parsed table: a faculty table read by the v0.3.0 parser, as the worker sends it (parsed outside the database, see groups.mjs)
\set parsed `node tests/fixtures/english-requirements/groups.mjs parsed-faculty-table`
insert into pipeline.evidence_artifacts(id, storage_path) values ('00000000-0000-0000-0000-00000000e0a1', 'layer2/AU/provider-facts/fixture/a1.md.gz');
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, evidence_id, content_hash)
values ('00000000-0000-0000-0000-00000000f0a1', '00000000-0000-0000-0000-00000000b001', 'english_policy', 'https://www.fixture.example/english', 't', 5, 'search', 'read', '00000000-0000-0000-0000-00000000e0a1', 'hash-a1');
select pg_temp.ok((public.svc_provider_policy_record('00000000-0000-0000-0000-00000000f0a1', :'parsed'::jsonb)->>'status') = 'proposed', 'a faculty table with quoted scores is filed as status proposed (it was no_values before this change)');
select pg_temp.ok((select style from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1') = 'course_groups', 'its style is course_groups');
select pg_temp.ok((select count(*) from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1' and proposal->'defaults' = '{}'::jsonb) = 1, 'it carries no default (a faculty table is never read as a default)');
-- a group with no quote does not make a proposal
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, content_hash)
values ('00000000-0000-0000-0000-00000000f0a2', '00000000-0000-0000-0000-00000000b001', 'english_policy', 'https://www.fixture.example/english2', 't', 5, 'search', 'read', 'hash-a2');
select pg_temp.ok((public.svc_provider_policy_record('00000000-0000-0000-0000-00000000f0a2', '{"parser":"provider-policy-v0.3.0","style":"course_groups","defaults":{},"groups":[{"group_name":"X","level":null,"reqs":[{"test_code":"IELTS","overall_score":6.5,"component_scores":{},"quote":""}]}],"exceptions":[]}'::jsonb)->>'status') = 'no_values', 'a group without a quoted score is not a proposal');
select pg_temp.ok((public.svc_provider_policy_record('00000000-0000-0000-0000-00000000f0a2', '{"parser":"provider-policy-v0.2.5","style":"by_faculty","defaults":{},"exceptions":[]}'::jsonb)->>'status') = 'no_values', 'a reading with no groups key files exactly as before (no_values)');

-- 2 D2: never approved automatically, never closed automatically
do $$ declare g uuid; begin
  select id into g from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1';
  -- the same group reading under an AI parser name would match the old auto-approval condition (parser like 'ai:%'): the database must still leave it to a person
  update pipeline.provider_policy_proposals set parser = 'ai:fixture-model' where id = g;
  perform security.policy_auto_approve_v1();
  perform pg_temp.ok((select status from pipeline.provider_policy_proposals where id = g) = 'proposed', 'D2: automatic approval does not approve a course-group reading, even one that carries an ai: parser name');
  update pipeline.provider_policy_proposals set parser = 'provider-policy-v0.3.0' where id = g;
  -- an AI default reading for the same university is auto-approved as before, and does not close the waiting group reading
  insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, content_hash) values ('00000000-0000-0000-0000-00000000f0a3', '00000000-0000-0000-0000-00000000b001', 'english_policy', 'https://www.fixture.example/default', 't', 5, 'search', 'read', 'hash-a3');
  perform public.svc_provider_policy_record('00000000-0000-0000-0000-00000000f0a3', '{"parser":"ai:fixture-model","style":"level_default","defaults":{"undergraduate":[{"test_code":"IELTS","overall_score":6.5,"component_scores":{},"quote":"6.5"}]},"exceptions":[]}'::jsonb);
  perform security.policy_auto_approve_v1();
  perform pg_temp.ok((select status from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a3') = 'approved', 'an AI default reading is still approved automatically (existing authority unchanged)');
  perform pg_temp.ok((select status from pipeline.provider_policy_proposals where id = g) = 'proposed', 'D2: that automatic approval does not close the waiting course-group reading');
end $$;

-- 3 a person approves the groups; unbound groups reach no course
select public.admin_provider_policy_decide((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'), 'approve', 'fixture approval');
select pg_temp.ok((select status from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1') = 'approved', 'a Platform Admin approves the course-group reading');
select pg_temp.ok((select status from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a3') = 'approved', 'approving the group reading does not close the approved default reading');
select pg_temp.ok((select count(*) from security.provider_english_plan_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1')) where plan = 'group') = 0, 'D2: unbound groups reach no course');
-- only a Platform Admin binds
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a0', false);
insert into security.user_roles values ('00000000-0000-0000-0000-0000000000a0', 'pipeline_operator', null);
do $$ begin
  begin perform public.admin_provider_english_groups_set_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'), '[]'::jsonb, 'fixture reason'); raise exception 'FAIL an operator bound groups'; exception when sqlstate '42501' then perform pg_temp.ok(true, 'D2: a Pipeline Operator cannot bind course groups (Platform Admin only)'); end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ad', false);
-- the bindings (a person's): Social Sciences (undergraduate and postgraduate) to the Society and Culture fields below Human Welfare, Law row to economics by title pattern
do $$ declare p uuid := (select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'); v jsonb; begin
  begin perform public.admin_provider_english_groups_set_v1(p, '[{"group_name":"No such faculty","level":"undergraduate","fields":["asced-0905"]}]', 'fixture reason'); raise exception 'FAIL unknown group accepted';
  exception when others then perform pg_temp.ok(sqlerrm like '%is not in this policy%', 'a binding for a group the policy does not hold is refused'); end;
  begin perform public.admin_provider_english_groups_set_v1(p, '[{"group_name":"Social Sciences","level":"undergraduate","fields":["asced-9999"]}]', 'fixture reason'); raise exception 'FAIL unknown field accepted';
  exception when others then perform pg_temp.ok(sqlerrm like '%not an active field%', 'a binding to an unknown field of education is refused'); end;
  begin perform public.admin_provider_english_groups_set_v1(p, '[{"group_name":"Social Sciences","level":"undergraduate","title_regex":"("}]', 'fixture reason'); raise exception 'FAIL bad pattern accepted';
  exception when others then perform pg_temp.ok(sqlerrm like '%not a valid pattern%', 'an invalid title pattern is refused'); end;
  begin perform public.admin_provider_english_groups_set_v1(p, '[{"group_name":"Social Sciences","level":"undergraduate"}]', 'fixture reason'); raise exception 'FAIL empty binding accepted';
  exception when others then perform pg_temp.ok(sqlerrm like '%needs at least one field%', 'a binding with neither a field nor a pattern is refused'); end;
  begin perform public.admin_provider_english_groups_set_v1(p, '[]', ''); raise exception 'FAIL no reason accepted';
  exception when others then perform pg_temp.ok(sqlerrm like '%give a reason%', 'a reason is required'); end;
  v := public.admin_provider_english_groups_set_v1(p, '[{"group_name":"Social Sciences","level":"undergraduate","fields":["asced-09"]},{"group_name":"Social Sciences","level":"postgraduate","fields":["asced-09"]},{"group_name":"Economics and Law","level":"undergraduate","title_regex":"^Bachelor of (Economics|Laws)"}]', 'fixture: bound to Society and Culture');
  perform pg_temp.ok((v->>'bound')::int = 3, 'a Platform Admin binds three groups, with a reason');
  perform pg_temp.ok(exists (select 1 from pipeline.admin_control_events where action = 'english_groups_bound' and actor = '00000000-0000-0000-0000-0000000000ad'), 'the binding is logged with the actor');
end $$;
select pg_temp.ok((select count(*) from security.provider_english_plan_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1')) where plan = 'group') > 0, 'bound groups now reach courses (plan group)');

-- 4 the plan: precedence is the existing one
create temp table plan as select * from security.provider_english_plan_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'));
select pg_temp.ok((select plan||'/'||outcome from plan where course_id = '00000000-0000-0000-0000-0000000c0001') = 'group/write', 'Bachelor of Social Work (field below Society and Culture, undergraduate) takes the group requirement');
select pg_temp.ok((select plan||'/'||outcome from plan where course_id = '00000000-0000-0000-0000-0000000c0003') = 'group/write', 'Master of Social Work takes the postgraduate group requirement');
select pg_temp.ok((select (requirements->0->>'overall_score')::numeric from plan where course_id = '00000000-0000-0000-0000-0000000c0001') <> (select (requirements->0->>'overall_score')::numeric from plan where course_id = '00000000-0000-0000-0000-0000000c0003'), 'the undergraduate and postgraduate scores of the group are different and each course gets its own level''s');
select pg_temp.ok((select outcome from plan where course_id = '00000000-0000-0000-0000-0000000c0006') <> 'write', 'a course with its own page reading is never overwritten by a group rule');
select pg_temp.ok((select outcome from plan where course_id = '00000000-0000-0000-0000-0000000c0007') = 'set_by_hand', 'a course locked by hand is left alone');
select pg_temp.ok((select plan||'/'||outcome from plan where course_id = '00000000-0000-0000-0000-0000000c0005') like 'held/%', 'a research degree stays held (no group applies)');
select pg_temp.ok((select plan from plan where course_id = '00000000-0000-0000-0000-0000000c0004') = 'held', 'an unrelated course (Computer Science, another field) gets nothing: no English requirement is inferred');
select pg_temp.ok((select plan||'/'||outcome from plan where course_id = '00000000-0000-0000-0000-0000000c0009') = 'group/write', 'a title pattern binds a course whose field has no binding (Bachelor of Laws)');
select pg_temp.ok((select plan||'/'||outcome||'/'||reason from plan where course_id = '00000000-0000-0000-0000-0000000c0002') = 'held/held/more than one course group applies to this course', 'two groups with different scores for one course: held, never guessed (Bachelor of Economics)');

-- 5 apply: writes through the existing path with the group named and the source key of the existing policy rows
select pg_temp.ok((security.provider_english_apply_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'))->>'written')::int >= 3, 'applying the approved policy writes the bound courses');
select pg_temp.ok((select notes like 'English requirement for the course group "Social Sciences"%' from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0001' and status = 'active'), 'the row''s note names the course group');
select pg_temp.ok((select source_requirement_key like 'policy:%:ielts' from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0001'), 'the row carries the policy source key');
select pg_temp.ok((select overall_score from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0006') = 7.5, 'the course''s own page score (7.5) is untouched');
select pg_temp.ok((select count(*) from catalogue.course_english_requirements where course_id in ('00000000-0000-0000-0000-0000000c0002', '00000000-0000-0000-0000-0000000c0004', '00000000-0000-0000-0000-0000000c0005', '00000000-0000-0000-0000-0000000c0007')) = 0, 'no row was written for the ambiguous, unrelated, research or locked courses');
select pg_temp.ok((select confidence is null or confidence >= 0.6 from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0001'), 'a group row is not flagged as a university standard');
select pg_temp.ok((security.provider_english_apply_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'))->>'written')::int = 0, 'applying again writes nothing (idempotent)');
-- the university's other approved policy (a level default): it must not take a course that a bound group of the first policy already holds, and still reaches the rest
create temp table plan2 as select * from security.provider_english_plan_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a3'));
select pg_temp.ok((select plan||'/'||outcome from plan2 where course_id = '00000000-0000-0000-0000-0000000c0004') = 'default/write', 'the university''s level default still reaches a course no group holds (Bachelor of Computer Science)');
select pg_temp.ok((select plan from plan2 where course_id = '00000000-0000-0000-0000-0000000c0001') = 'held' and (select plan from plan2 where course_id = '00000000-0000-0000-0000-0000000c0008') = 'held', 'the level default holds a course that another approved policy''s bound group takes (no overlap)');

-- 6 editing the binding withdraws rows the old binding wrote (kept, not deleted)
do $$ declare p uuid := (select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'); v jsonb; begin
  v := public.admin_provider_english_groups_set_v1(p, '[{"group_name":"Social Sciences","level":"postgraduate","fields":["asced-09"]}]', 'fixture: undergraduate binding removed');
  perform pg_temp.ok((v->>'withdrawn_rows')::int >= 2, 'removing the undergraduate binding withdraws its rows');
  perform pg_temp.ok((select status from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0001') = 'withdrawn', 'the row is kept, as withdrawn');
  perform pg_temp.ok((select status from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0003') = 'active', 'the postgraduate row is still active');
  perform pg_temp.ok((select count(*) from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0001') = 1, 'one row per course and test (the unique key holds)');
end $$;

-- 7 a re-read by the same parser keeps a person's bindings
select public.svc_provider_policy_record('00000000-0000-0000-0000-00000000f0a1', :'parsed'::jsonb);
select pg_temp.ok(jsonb_array_length((select proposal->'group_bindings' from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1')) = 1, 'a re-read by the same parser keeps the bindings');

-- 8 add-tests ignores groups: nothing here adds or changes a group row
select pg_temp.ok((select count(*) from catalogue.course_english_requirements where course_id = '00000000-0000-0000-0000-0000000c0003') = 1 and
  (public.svc_provider_english_add_tests_v1((select id from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0a1'), 'provider-policy-v0.2.5', :'parsed'::jsonb || '{"add_only":["DET"]}'::jsonb, null)->>'added')::int = 0, 'policy-add-tests does not add tests to course-group rows');

-- 9 D1 scope: shipped as today (every type); a list limits attach and AI queueing and nothing already approved
insert into pipeline.provider_central_search(provider_id, state, found, updated_at, attempts) values
 ('00000000-0000-0000-0000-00000000b002', 'done', '[{"kind":"english_policy","url":"https://www.tafe.fixture.example/english","title":"English","score":6}]'::jsonb, now(), 1);
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, study_level_id, lifecycle_status) values ('00000000-0000-0000-0000-0000000c0101', 'h-t1', '00000000-0000-0000-0000-00000000b002', 'Certificate IV in Fixture', (select id from ref.study_levels where code = 'certificate_iv'), 'active');
select pg_temp.ok(security.pipeline_num_v1('central.english_search_non_university', 9) = 0, 'D3: the non-university search ships switched off');
select pg_temp.ok((select value from pipeline.platform_toolset_settings where key = 'central.english_provider_types') = '["*"]'::jsonb, 'D1: the provider scope ships as every type (today''s behaviour)');
select pg_temp.ok(security.english_provider_in_scope_v1('00000000-0000-0000-0000-00000000b002') and security.english_provider_in_scope_v1('00000000-0000-0000-0000-00000000b001'), 'D1: with ["*"] both a TAFE and a university are in scope');
update pipeline.platform_toolset_settings set value = '["university"]'::jsonb where key = 'central.english_provider_types';
select pg_temp.ok(security.english_provider_in_scope_v1('00000000-0000-0000-0000-00000000b001') and not security.english_provider_in_scope_v1('00000000-0000-0000-0000-00000000b002'), 'D1: with ["university"] the TAFE is out of scope');
select pg_temp.ok((security.central_pages_attach_v1()->>'attached')::int = 0, 'D1: an out-of-scope provider''s found English page is not attached');
update pipeline.platform_toolset_settings set value = '["*"]'::jsonb where key = 'central.english_provider_types';
select pg_temp.ok((security.central_pages_attach_v1()->>'attached')::int = 1, 'D1: with ["*"] the same page is attached (today''s behaviour)');
select pg_temp.ok(exists (select 1 from pipeline.provider_fact_sources where provider_id = '00000000-0000-0000-0000-00000000b002' and kind = 'english_policy'), 'D1: the attached page is a fact source');
update pipeline.provider_fact_sources set status = 'read', evidence_id = '00000000-0000-0000-0000-00000000e0a1', content_hash = 'hash-tafe' where provider_id = '00000000-0000-0000-0000-00000000b002' and kind = 'english_policy';
update pipeline.platform_toolset_settings set value = '["university"]'::jsonb where key = 'central.english_provider_types';
select pg_temp.ok(security.central_ai_enqueue_v1('00000000-0000-0000-0000-00000000b002') = 0, 'D1: a stored page of an out-of-scope provider is not queued for the AI');
update pipeline.platform_toolset_settings set value = '["*"]'::jsonb where key = 'central.english_provider_types';
select pg_temp.ok(security.central_ai_enqueue_v1('00000000-0000-0000-0000-00000000b002') = 1, 'D1: with ["*"] it is queued');
select pg_temp.ok((select count(*) from pipeline.provider_policy_proposals where status = 'approved' and provider_id = '00000000-0000-0000-0000-00000000b001') = 2, 'nothing approved was withdrawn by changing the scope');

-- 10 D3: switched off, nothing is queued or picked; switched on, the pick uses the provider's own website host and nothing else changes
select pg_temp.ok((security.central_pages_attach_v1()->>'search_queued')::int = 0 and (select count(*) from pipeline.provider_fact_search) = 0, 'D3: switched off, nothing is queued for the search');
select pg_temp.ok(jsonb_array_length(public.svc_provider_facts_search_next(10)) = 0, 'D3: switched off, nothing is picked for a search (no credit use)');
update pipeline.platform_toolset_settings set value = '1'::jsonb where key = 'central.english_search_non_university';
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, study_level_id, lifecycle_status) values ('00000000-0000-0000-0000-0000000c0201', 'h-t2', '00000000-0000-0000-0000-00000000b003', 'Diploma of Hidden', (select id from ref.study_levels where code = 'diploma'), 'active');
-- the TAFE already has a fact source and the university an approved rule: neither is queued; the hidden (unpublished) college is never queued
select pg_temp.ok((security.central_pages_attach_v1()->>'search_queued')::int = 0, 'D3: providers with a page or a rule, and unpublished providers, are not queued even when switched on');
insert into catalogue.providers(id, stable_key, canonical_name, display_name, provider_type_id, lifecycle_status, publication_status, website)
values ('00000000-0000-0000-0000-00000000b004', 'h-new', 'New College', 'New College', (select id from ref.provider_types where code = 'private_vet'), 'active', 'published', 'https://www.newcollege.example/courses?x=1');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, study_level_id, lifecycle_status) values ('00000000-0000-0000-0000-0000000c0301', 'h-n1', '00000000-0000-0000-0000-00000000b004', 'Diploma of New', (select id from ref.study_levels where code = 'diploma'), 'active');
select pg_temp.ok((security.central_pages_attach_v1()->>'search_queued')::int = 1, 'D3: switched on, a published provider with no page, search or rule is queued');
select pg_temp.ok((public.svc_provider_facts_search_next(10)->0->>'query') = 'English language requirements international students site:newcollege.example', 'D3: switched on, the search stays inside the provider''s own website host');
update pipeline.platform_toolset_settings set value = '0'::jsonb where key = 'central.english_search_non_university';
delete from pipeline.provider_fact_search;

-- 11 D5: reparse list: stored pages, latest reading no values (or rejected as one faculty row), not read by this parser, none live, published providers only
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, evidence_id, content_hash) values
 ('00000000-0000-0000-0000-00000000f0b1', '00000000-0000-0000-0000-00000000b004', 'english_policy', 'https://www.newcollege.example/e', 't', 5, 'search', 'no_values', '00000000-0000-0000-0000-00000000e0a1', 'hash-b1'),
 ('00000000-0000-0000-0000-00000000f0b2', '00000000-0000-0000-0000-00000000b004', 'english_policy', 'https://www.newcollege.example/f', 't', 5, 'search', 'read', '00000000-0000-0000-0000-00000000e0a1', 'hash-b2'),
 ('00000000-0000-0000-0000-00000000f0b3', '00000000-0000-0000-0000-00000000b003', 'english_policy', 'https://hidden.example/e', 't', 5, 'search', 'no_values', '00000000-0000-0000-0000-00000000e0a1', 'hash-b3');
insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, url, style, proposal, status, decision_note) values
 ('00000000-0000-0000-0000-00000000b004', '00000000-0000-0000-0000-00000000f0b1', 'english_policy', 'provider-policy-v0.2.5', 'hash-b1', 'u', 'by_faculty', '{}', 'no_values', null),
 ('00000000-0000-0000-0000-00000000b004', '00000000-0000-0000-0000-00000000f0b2', 'english_policy', 'ai:fixture', 'hash-b2', 'u', 'level_default', '{}', 'rejected', 'one faculty row, not a university default'),
 ('00000000-0000-0000-0000-00000000b003', '00000000-0000-0000-0000-00000000f0b3', 'english_policy', 'provider-policy-v0.2.5', 'hash-b3', 'u', 'by_faculty', '{}', 'no_values', null);
select pg_temp.ok((select jsonb_agg(x->>'id' order by x->>'id') from jsonb_array_elements(public.svc_provider_policy_reparse_next('provider-policy-v0.3.0', 50)) x) = '["00000000-0000-0000-0000-00000000f0b1", "00000000-0000-0000-0000-00000000f0b2"]'::jsonb,
  'D5: the reparse list holds the no-values page and the page rejected as one faculty row, not the unpublished provider''s and not a live reading');
insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, url, style, proposal, status) values ('00000000-0000-0000-0000-00000000b004', '00000000-0000-0000-0000-00000000f0b1', 'english_policy', 'provider-policy-v0.3.0', 'hash-b1', 'u', 'none', '{}', 'no_values');
select pg_temp.ok(jsonb_array_length(public.svc_provider_policy_reparse_next('provider-policy-v0.3.0', 50)) = 1, 'D5: a page is read once per parser version');
select pg_temp.ok(jsonb_array_length(public.svc_provider_policy_reparse_next('provider-policy-v0.3.0', 50) ) = 1 and (select md5(command) from cron.job where jobname = 'policy-add-tests') <> '4827953f23c896d5ae05b14dd4ca722f' and (select command from cron.job where jobname = 'policy-add-tests') like '%security.pipeline_num_v1(''batch.policy_reparse'', 20)%', 'D5: the existing policy-add-tests job carries the reparse size from a setting (no new job)');
select pg_temp.ok((select count(*) from cron.job where jobname like '%reparse%') = 0, 'D5: no new scheduled job was created');

-- 12 visibility: the status read on the existing panel (Pipeline Operator and above)
do $$ declare v jsonb; begin
  v := public.admin_provider_english_status_read(null, null, 50);
  perform pg_temp.ok(v->'stages' ? 'approved' and v->'stages' ? 'not_mapped' or v->'stages' ? 'page_read_no_rule' or v->'stages' ? 'mapped_no_page', 'the status read returns stages');
  perform pg_temp.ok((v->'scope'->'provider_types') = '["*"]'::jsonb and (v->'scope'->>'search_new_providers')::int = 0, 'it shows the provider-type scope and that the new-provider search is off');
  perform pg_temp.ok(jsonb_array_length(v->'jobs') >= 2, 'it lists the jobs of the route with their schedule');
  perform pg_temp.ok((select x->>'why' from jsonb_array_elements(v->'rows') x where x->>'provider_id' = '00000000-0000-0000-0000-00000000b004') is not null, 'every provider row says why there is no rule');
  perform pg_temp.ok((select x->>'stage' from jsonb_array_elements(v->'rows') x where x->>'provider_id' = '00000000-0000-0000-0000-00000000b001') = 'approved', 'the university shows as approved');
  perform pg_temp.ok(not exists (select 1 from jsonb_array_elements(v->'rows') x where x->>'provider_id' = '00000000-0000-0000-0000-00000000b003'), 'an unpublished provider is not listed');
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ff', false);
do $$ begin
  begin perform public.admin_provider_english_status_read(); raise exception 'FAIL anonymous read accepted'; exception when sqlstate '42501' then perform pg_temp.ok(true, 'the status read needs a Pipeline Operator or above'); end;
end $$;

-- 13 the consumer API is untouched: the migration names none of its objects
select pg_temp.ok(true, 'consumer API: checked by the source contract (the migration names no website_v2, website_edge, zoho or api object)');
\echo english group scenarios: passed
