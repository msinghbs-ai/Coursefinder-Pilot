-- Guards: Platform Admin 8 Nov 2026 14:06 (English gap recovery): one cause per active course without English, counts that add up, and the withdrawn-reading default
-- (setting english.default_after_withdrawn_reading, ships off) changes only the courses it is meant to. Runs on the English fixture after funnel-harness.sql and migrations 20261108120000 and 20261108121000.
-- Invented rows only. Isolated local PostgreSQL only.
\set ON_ERROR_STOP on
set session_replication_role = replica;
create or replace function pg_temp.ok(c boolean, what text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL %', what; end if; raise notice 'PASS %', what; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ad', false), set_config('request.jwt.claim.role', 'authenticated', false);

-- before: what the fixture already holds (earlier scenarios), so each assertion is a difference
create temp table f0 as select layer, cause_key, courses from security.english_gap_funnel_v1();
create or replace function pg_temp.d(p_layer text, p_cause text) returns bigint language sql as $$
  select coalesce((select courses from security.english_gap_funnel_v1() where layer = p_layer and cause_key = p_cause), 0) - coalesce((select courses from f0 where layer = p_layer and cause_key = p_cause), 0) $$;

-- P1 published, with an approved AI level default (undergraduate IELTS 6.5); P2 not published; P3 published without any central page
insert into catalogue.providers(id, stable_key, canonical_name, display_name, provider_type_id, lifecycle_status, publication_status, website) values
 ('00000000-0000-0000-0000-00000000ec01', 'g-p1', 'Gap P1', 'Gap P1', (select id from ref.provider_types where code = 'university'), 'active', 'published', 'https://p1.fixture.example/'),
 ('00000000-0000-0000-0000-00000000ec02', 'g-p2', 'Gap P2', 'Gap P2', (select id from ref.provider_types where code = 'university'), 'active', 'draft', 'https://p2.fixture.example/'),
 ('00000000-0000-0000-0000-00000000ec03', 'g-p3', 'Gap P3', 'Gap P3', (select id from ref.provider_types where code = 'university'), 'active', 'published', 'https://p3.fixture.example/');
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, study_level_id, lifecycle_status, open_to_international)
select ('00000000-0000-0000-0000-0000000ec' || lpad(n::text, 3, '0'))::uuid, 'g-c' || n, pv, t, (select id from ref.study_levels where code = lv), 'active', true
  from (values (1, '00000000-0000-0000-0000-00000000ec01'::uuid, 'Bachelor of Plain', 'bachelor'),            -- no row: the default is ready
               (2, '00000000-0000-0000-0000-00000000ec01', 'Bachelor of Same', 'bachelor'),                    -- only a withdrawn page reading, IELTS 6.5 = the default
               (3, '00000000-0000-0000-0000-00000000ec01', 'Bachelor of Other', 'bachelor'),                   -- only a withdrawn page reading, IELTS 7.0 <> the default
               (4, '00000000-0000-0000-0000-00000000ec01', 'Bachelor of Policy Withdrawn', 'bachelor'),        -- only a withdrawn row the policy itself wrote: keeps blocking
               (5, '00000000-0000-0000-0000-00000000ec01', 'Bachelor of Active', 'bachelor'),                  -- has an active row: not a gap
               (6, '00000000-0000-0000-0000-00000000ec01', 'Bachelor of Locked', 'bachelor'),                  -- locked by hand
               (7, '00000000-0000-0000-0000-00000000ec01', 'Diploma of Level Not Covered', 'diploma'),         -- the policy has no diploma default
               (8, '00000000-0000-0000-0000-00000000ec02', 'Bachelor of Hidden', 'bachelor'),                  -- provider not published
               (9, '00000000-0000-0000-0000-00000000ec03', 'Bachelor of Another Page', 'bachelor'),            -- its page is for another course
               (10, '00000000-0000-0000-0000-00000000ec03', 'Bachelor of Failed Read', 'bachelor')) v(n, pv, t, lv);  -- the English read failed
insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_requirement_key, status)
select c, t.id, s, '{}', 'fixture', k, st from ref.english_tests t, (values
  ('00000000-0000-0000-0000-0000000ec002'::uuid, 6.5, 'page:c2', 'withdrawn'), ('00000000-0000-0000-0000-0000000ec003', 7.0, 'page:c3', 'withdrawn'),
  ('00000000-0000-0000-0000-0000000ec004', 6.5, 'policy:p1:undergraduate', 'withdrawn'), ('00000000-0000-0000-0000-0000000ec005', 6.5, 'page:c5', 'active')) v(c, s, k, st)
 where t.code = 'IELTS';
insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', '00000000-0000-0000-0000-0000000ec006', 'english', 'value');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_status) values ('00000000-0000-0000-0000-0000000ec009', '00000000-0000-0000-0000-00000000ec03', 'https://p3.fixture.example/x', 'mismatch', 'read');
insert into pipeline.field_enrich_items(course_id, field, state) values ('00000000-0000-0000-0000-0000000ec010', 'english', 'failed');

insert into pipeline.evidence_artifacts(id, storage_path) values ('00000000-0000-0000-0000-00000000e0c1', 'layer2/AU/provider-facts/fixture/p1.md.gz');
insert into pipeline.provider_fact_sources(id, provider_id, kind, url, title, rank, found_via, status, evidence_id, content_hash)
values ('00000000-0000-0000-0000-00000000f0c9', '00000000-0000-0000-0000-00000000ec01', 'english_policy', 'https://p1.fixture.example/english', 't', 5, 'search', 'read', '00000000-0000-0000-0000-00000000e0c1', 'hash-c9');
select public.svc_provider_policy_record('00000000-0000-0000-0000-00000000f0c9', '{"parser":"ai:fixture-model","style":"level_default","defaults":{"undergraduate":[{"test_code":"IELTS","overall_score":6.5,"component_scores":{},"quote":"6.5"}]},"exceptions":[]}'::jsonb);
select security.policy_auto_approve_v1();
select pg_temp.ok((select status from pipeline.provider_policy_proposals where fact_source_id = '00000000-0000-0000-0000-00000000f0c9') = 'approved', 'the fixture default for P1 is approved');

-- 1 the setting is off: nothing about the withdrawn readings changes
select pg_temp.ok(security.pipeline_num_v1('english.default_after_withdrawn_reading', 0) = 0, 'english.default_after_withdrawn_reading ships off');
select pg_temp.ok(pg_temp.d('primary', 'default_ready_to_apply') = 1, 'off: only the plain course is ready to apply');
select pg_temp.ok(pg_temp.d('primary', 'default_blocked_by_withdrawn_reading') = 3, 'off: the three courses with only withdrawn rows are blocked');
select pg_temp.ok(pg_temp.d('primary', 'withdrawn_reading_differs_from_default') = 0, 'off: no course is reported as differing');
select pg_temp.ok(pg_temp.d('primary', 'manual_lock') = 1, 'the locked course is reported as a manual lock');
select pg_temp.ok(pg_temp.d('primary', 'policy_held:no_default_for_level') + pg_temp.d('primary', 'policy_held:level_not_covered') = 1, 'the diploma is held by the policy, with its reason');
select pg_temp.ok(pg_temp.d('primary', 'provider_not_published') = 1, 'the course of an unpublished provider is reported as such');
select pg_temp.ok(pg_temp.d('primary', 'page_for_another_course') = 1, 'a page bound to another course is reported');
select pg_temp.ok(pg_temp.d('primary', 'english_read_failed_not_retried') = 1, 'a failed English read is reported (the requeue is a recorded decision, not run)');
select pg_temp.ok((select sum(courses) from security.english_gap_funnel_v1() where layer = 'primary') = (select count(*) from catalogue.courses c where c.lifecycle_status = 'active' and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active')),
  'the primary layer adds up to the active courses without English (one cause per course)');
select pg_temp.ok((select sum(courses) from security.english_gap_funnel_v1() where layer = 'rule') = (select sum(courses) from security.english_gap_funnel_v1() where layer = 'page'), 'the rule and page layers each add up to the same total');
select pg_temp.ok(not has_function_privilege('anon', 'security.english_gap_funnel_v1()', 'execute') and not has_function_privilege('authenticated', 'security.english_gap_funnel_v1()', 'execute'), 'the security function is not callable by anon or authenticated');
select pg_temp.ok(not has_function_privilege('anon', 'public.admin_english_gap_funnel()', 'execute') and has_function_privilege('authenticated', 'public.admin_english_gap_funnel()', 'execute'), 'the Admin read is granted to signed-in users only');

-- 2 the admin read: a Curator and above only
select pg_temp.ok((public.admin_english_gap_funnel()->>'without_english')::int = (select sum(courses) from security.english_gap_funnel_v1() where layer = 'primary'), 'the Admin read states the same total as the funnel (Platform Admin)');
do $$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
  begin perform public.admin_english_gap_funnel(); raise exception 'FAIL a user with no role read the funnel'; exception when sqlstate '42501' then perform pg_temp.ok(true, 'a user with no role cannot read the funnel'); end;
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ad', false);
end $$;

-- 3 the plan, setting off then on
create temp table plan_off as select x.course_id, x.outcome from pipeline.provider_policy_proposals p, lateral security.provider_english_plan_v1(p.id) x where p.provider_id = '00000000-0000-0000-0000-00000000ec01' and p.status = 'approved';
select pg_temp.ok((select outcome from plan_off where course_id = '00000000-0000-0000-0000-0000000ec002') = 'other_value', 'off: a withdrawn page reading still blocks the default (as live)');
update pipeline.platform_toolset_settings set value = '1'::jsonb where toolset_key = 'pipeline' and key = 'english.default_after_withdrawn_reading';
create temp table plan_on as select x.course_id, x.outcome from pipeline.provider_policy_proposals p, lateral security.provider_english_plan_v1(p.id) x where p.provider_id = '00000000-0000-0000-0000-00000000ec01' and p.status = 'approved';
select pg_temp.ok((select outcome from plan_on where course_id = '00000000-0000-0000-0000-0000000ec002') = 'write', 'on: a withdrawn page reading with the same score as the default no longer blocks it');
select pg_temp.ok((select outcome from plan_on where course_id = '00000000-0000-0000-0000-0000000ec003') = 'differs', 'on: a withdrawn page reading at another score is held and shown as differing, not written');
select pg_temp.ok((select outcome from plan_on where course_id = '00000000-0000-0000-0000-0000000ec004') = 'other_value', 'on: a withdrawn row the policy itself wrote keeps blocking (no rewrite of a withdrawal)');
select pg_temp.ok((select outcome from plan_on where course_id = '00000000-0000-0000-0000-0000000ec006') = 'set_by_hand', 'on: a locked course is still left alone');
select pg_temp.ok((select count(*) from plan_off o join plan_on n using (course_id) where o.outcome is distinct from n.outcome) = 2, 'on: exactly the two withdrawn page readings change outcome');
select pg_temp.ok(pg_temp.d('primary', 'default_ready_to_apply') = 2 and pg_temp.d('primary', 'withdrawn_reading_differs_from_default') = 1 and pg_temp.d('primary', 'default_blocked_by_withdrawn_reading') = 1, 'on: the funnel moves one course to ready, one to differing, and keeps one blocked');
select pg_temp.ok((select count(*) from catalogue.course_english_requirements where course_id in ('00000000-0000-0000-0000-0000000ec002', '00000000-0000-0000-0000-0000000ec003', '00000000-0000-0000-0000-0000000ec004') and status = 'active') = 0, 'planning wrote nothing');
update pipeline.platform_toolset_settings set value = '0'::jsonb where toolset_key = 'pipeline' and key = 'english.default_after_withdrawn_reading';
select pg_temp.ok((select count(*) from pipeline.provider_policy_proposals p, lateral security.provider_english_plan_v1(p.id) x where p.provider_id = '00000000-0000-0000-0000-00000000ec01' and p.status = 'approved' and x.outcome = 'write') = 1, 'off again: back to the live outcomes');
