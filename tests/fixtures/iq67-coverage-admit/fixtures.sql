-- CF-247 IQ-00067: after the migration. The batch goes on past the locked course; the locked rows are held with a named reason; a refused item
-- is held, rolled back on its own and not retried until admit.refused_recheck_hours; refusals a run are bounded; the lock rule is unchanged;
-- the root cause and remedies are registered through workstream A's contract. Scratch PostgreSQL only.
create function pg_temp.check(p_ok boolean, p_what text) returns void language plpgsql as $f$
begin if not coalesce(p_ok, false) then raise exception 'FAIL: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;
create table pg_temp.r(run int primary key, v jsonb);

-- run 1
insert into pg_temp.r select 1, security.coverage_admission_gated_v1('coverage-admit', 500, 'coverage-sweep-v0.5.6', array['official_url', 'english']);
select pg_temp.check((select v->>'written' = '1' and v->>'decided_by_rule' = '1' and v->>'layer4' = '1' from pg_temp.r where run = 1),
  'run 1 completes: C3 written, C2 decided by rule and applied, C5 raised to a person (result ' || (select v::text from pg_temp.r where run = 1) || ')');
select pg_temp.check((select v->>'held_manual_lock' = '2' and v->>'held_refused' = '2' and v->>'errors' = '2' and v->>'stopped_at_limit' = 'false' from pg_temp.r where run = 1),
  'run 1 holds the two locked rows (C1 page, C4 English) and the two refusals (C6 write, C7 page), and is not stopped');
select pg_temp.check(exists (select 1 from catalogue.course_links where course_id = '22222222-0000-4000-8000-000000000002' and url = 'https://uni.example.edu/courses/bachelor-x' and status = 'active' and is_primary)
  and (select course_url from catalogue.courses where id = '22222222-0000-4000-8000-000000000002') = 'https://uni.example.edu/courses/bachelor-x',
  'the batch continued past the locked course: C2''s rule decision applied its page');
select pg_temp.check((select count(*) from catalogue.course_links where course_id = '22222222-0000-4000-8000-000000000001') = 1
  and exists (select 1 from catalogue.course_links where course_id = '22222222-0000-4000-8000-000000000001' and status = 'active' and url like '%bachelor-nursing-science.html')
  and (select course_url from catalogue.courses where id = '22222222-0000-4000-8000-000000000001') like '%bachelor-nursing-science.html',
  'the locked course keeps the page set by hand (link and course record untouched)');
select pg_temp.check(not exists (select 1 from pipeline.layer4_review_items where entity_id in ('22222222-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000004')),
  'the locked course is never offered to apply: no Layer 4 item and no rule decision for C1 or C4');
select pg_temp.check(not exists (select 1 from pipeline.layer4_review_items where entity_id = '22222222-0000-4000-8000-000000000007')
  and not exists (select 1 from catalogue.course_links where course_id = '22222222-0000-4000-8000-000000000007' and url like '%a b'),
  'the refused rule decision rolled back on its own (C7: no approved item, no link), and nothing else rolled back with it');
select pg_temp.check(exists (select 1 from pipeline.layer4_review_items where entity_id = '22222222-0000-4000-8000-000000000005' and status = 'pending')
  and exists (select 1 from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id where i.entity_id = '22222222-0000-4000-8000-000000000002' and d.action = 'approve'),
  'C5 waits for a person; C2''s decision is recorded');
select pg_temp.check((select count(*) from fx.applied) = 1 and exists (select 1 from fx.applied where course_id = '22222222-0000-4000-8000-000000000003'),
  'C3 written; C4 (locked English) not written');
select pg_temp.check(exists (select 1 from pipeline.coverage_admission_holds where course_id = '22222222-0000-4000-8000-000000000001' and attribute = 'official_url'
    and reason = 'manual_lock' and plan_action = 'differs' and detail->'lock_fields' = '["course_url", "official_url"]' and seen_count = 1)
  and exists (select 1 from pipeline.coverage_admission_holds where course_id = '22222222-0000-4000-8000-000000000004' and attribute = 'english' and reason = 'manual_lock'),
  'held as manual_lock with the lock fields named: C1 official page, C4 English requirement');
select pg_temp.check(exists (select 1 from pipeline.coverage_admission_holds where course_id = '22222222-0000-4000-8000-000000000006' and reason = 'apply_refused'
    and plan_action = 'write' and detail->>'error' like 'fixture: the record writer refused%')
  and exists (select 1 from pipeline.coverage_admission_holds where course_id = '22222222-0000-4000-8000-000000000007' and reason = 'apply_refused'
    and plan_action = 'differs' and detail->>'error' = 'the link must be a full https:// web address' and detail->>'rule' like 'take:%'),
  'held as apply_refused with the refusal named: C6 write, C7 rule decision');
select pg_temp.check((select (last_result->>'written')::int = 1 and runs_done = 1 and last_full_at is not null from pipeline.job_input_marks where job_key = 'coverage-admit'),
  'the run committed: the job mark moved');
select pg_temp.check(exists (select 1 from pipeline.consumer_api_baselines where label like 'after coverage admission batch (2 courses%'),
  'the admitted courses (C2, C3) are refreshed and baselined as before');

-- run 2: the locked rows are held again (bounded: one row each, seen twice); the refusals wait; nothing is raised or decided twice
insert into pg_temp.r select 2, security.coverage_admission_gated_v1('coverage-admit', 500, 'coverage-sweep-v0.5.6', array['official_url', 'english']);
select pg_temp.check((select v->>'held_manual_lock' = '2' and v->>'refused_waiting' = '2' and v->>'errors' = '0' and v->>'decided_by_rule' = '0' and v->>'layer4' = '0' from pg_temp.r where run = 2),
  'run 2: locked rows held again, the two refused items wait (admit.refused_recheck_hours), no error, nothing raised twice (result ' || (select v::text from pg_temp.r where run = 2) || ')');
select pg_temp.check((select count(*) from pipeline.coverage_admission_holds) = 4
  and (select seen_count from pipeline.coverage_admission_holds where course_id = '22222222-0000-4000-8000-000000000001') = 2
  and (select seen_count from pipeline.coverage_admission_holds where course_id = '22222222-0000-4000-8000-000000000006') = 1,
  'holds stay one row a course, field and proposal (C1 seen twice; C6 not retried)');

-- the refusals a run are bounded by admit.item_error_limit
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'admit.item_error_limit';
insert into fx.plan(course_id, provider_id, provider_cricos, course_cricos, evidence_id, content_hash, page_url, attribute, action, proposed, current)
select ('22222222-0000-4000-8000-00000000000' || n)::uuid, '11111111-0000-4000-8000-000000000000', 'P1', 'C' || n, gen_random_uuid(), 'h' || n,
       'https://uni.example.edu/c' || n, 'official_url', 'write', jsonb_build_object('course_url', 'https://uni.example.edu/c' || n), null from generate_series(8, 9) n;
insert into fx.refuse values ('22222222-0000-4000-8000-000000000008'), ('22222222-0000-4000-8000-000000000009');
insert into pg_temp.r select 3, security.coverage_admission_gated_v1('coverage-admit', 500, 'coverage-sweep-v0.5.6', array['official_url', 'english']);
select pg_temp.check((select v->>'held_refused' = '1' and v->>'errors' = '1' and v->>'stopped_at_limit' = 'true' from pg_temp.r where run = 3),
  'with admit.item_error_limit 1 the run stops after one refusal, holds it, and still commits (result ' || (select v::text from pg_temp.r where run = 3) || ')');
select pg_temp.check((select runs_done = 3 and last_result->>'more' = 'true' from pipeline.job_input_marks where job_key = 'coverage-admit'),
  'run 3 committed and is marked "more", so the next run is not skipped for no new input');
update pipeline.platform_toolset_settings set value = '25' where toolset_key = 'pipeline' and key = 'admit.item_error_limit';

-- the lock rule is unchanged: a person approving the locked course's page is still refused by the link apply
do $$
declare v_item uuid; v_err text;
begin
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, status)
  values ('course', '22222222-0000-4000-8000-000000000001', 'official_course_url', '{"course_url": "https://www.auckland.ac.nz/en/study/x"}', 'pending') returning id into v_item;
  begin
    perform security.layer4_course_link_apply_impl(gen_random_uuid(), v_item, '{}'::jsonb, 'fixture');
  exception when raise_exception then v_err := sqlerrm;
  end;
  perform pg_temp.check(v_err like 'this course''s page was set by hand on the course record%', 'the lock rule is unchanged: approving the locked course''s page is still refused');
  raise exception 'rollback' using errcode = 'P0001', hint = 'fixture';
exception when others then
  if sqlerrm like 'FAIL%' then raise; end if;
end $$;

-- root cause and remedies through workstream A's contract
select pg_temp.check(exists (select 1 from pipeline.ops_root_causes where code = 'lock_conflict_in_batch' and class = 'rule' and detect->>'message_like' = '%set by hand on the course record%'),
  'root cause lock_conflict_in_batch registered (class rule, detect names the job error)');
select pg_temp.check(exists (select 1 from pipeline.ops_remedies where code = 'coverage_admit_lock_hold' and authority = 'release' and treats = array['lock_conflict_in_batch'])
  and exists (select 1 from pipeline.ops_remedies where code = 'coverage_admit_recheck' and authority = 'auto' and active
    and action_fn = 'security.coverage_admit_recheck_v1(bigint)'::regprocedure and verify_fn = 'security.coverage_admit_recheck_verify_v1(bigint)'::regprocedure
    and max_attempts_key = 'admit.remedy_max_attempts' and cooldown_key = 'admit.remedy_cooldown_minutes'),
  'remedies registered: coverage_admit_lock_hold (release) and coverage_admit_recheck (auto, action and verification, bounded by settings)');
insert into pipeline.integration_issues(fingerprint, title, layer, failure, expected, detection_source, severity, workstream)
values ('iq67-fixture', 'coverage-admit fails every run', 'Layer 2', 'one raise aborts the batch', 'the batch completes', 'fixture', 'P1', 'A1');
insert into pg_temp.r select 10, security.coverage_admit_recheck_v1((select id from pipeline.integration_issues where fingerprint = 'iq67-fixture'));
insert into pipeline.ops_remedy_runs(issue_id, remedy_code, result) select id, 'coverage_admit_recheck', 'acted' from pipeline.integration_issues where fingerprint = 'iq67-fixture';
select pg_temp.check((select v->>'ok' = 'true' and v->>'changed' = '1' from pg_temp.r where run = 10) and (select last_full_at is null from pipeline.job_input_marks where job_key = 'coverage-admit'),
  'remedy action: the next coverage-admit run is a full pass');
select pg_temp.check(not (security.coverage_admit_recheck_verify_v1((select id from pipeline.integration_issues where fingerprint = 'iq67-fixture'))->>'passed')::boolean,
  'remedy verification fails until a full run commits');
insert into pg_temp.r select 4, security.coverage_admission_gated_v1('coverage-admit', 500, 'coverage-sweep-v0.5.6', array['official_url', 'english']);
select pg_temp.check((security.coverage_admit_recheck_verify_v1((select id from pipeline.integration_issues where fingerprint = 'iq67-fixture'))->>'passed')::boolean,
  'remedy verification passes once a full run committed after the action');
