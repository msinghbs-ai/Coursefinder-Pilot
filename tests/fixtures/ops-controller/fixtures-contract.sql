-- CF-247 P0 workstream A: the shared contract (part 1 of 20261104010000) on isolated fixtures. Every case raises an exception when it fails.
\set ON_ERROR_STOP 1
create or replace function fx.refused(p_sql text, p_like text) returns void language plpgsql as $f$
begin
  begin execute p_sql; exception when others then
    if sqlerrm not like p_like then raise exception 'refused with the wrong reason: % (expected %)', sqlerrm, p_like; end if;
    return;
  end;
  raise exception 'not refused: %', p_sql;
end $f$;
create or replace function fx.ok(p_cond boolean, p_case text) returns void language plpgsql as $f$
begin if not coalesce(p_cond, false) then raise exception 'FAILED: %', p_case; end if; raise notice 'ok: %', p_case; end $f$;

-- C1 the names other workstreams code against
select fx.ok(to_regclass('pipeline.ops_root_causes') is not null and to_regclass('pipeline.ops_remedies') is not null and to_regclass('pipeline.ops_remedy_runs') is not null
  and to_regclass('pipeline.ops_outcome_codes') is not null, 'C1 the four contract tables exist');
select fx.ok((select array_agg(column_name::text order by ordinal_position) from information_schema.columns where table_schema = 'pipeline' and table_name = 'ops_remedies')
  = array['code', 'title', 'treats', 'authority', 'action_fn', 'verify_fn', 'max_attempts_key', 'cooldown_key', 'active', 'notes'], 'C1 ops_remedies has exactly the contract columns');
select fx.ok((select array_agg(column_name::text order by ordinal_position) from information_schema.columns where table_schema = 'pipeline' and table_name = 'ops_root_causes')
  = array['code', 'class', 'title', 'description', 'detect', 'created_at'], 'C1 ops_root_causes has exactly the contract columns');
select fx.ok((select array_agg(column_name::text order by ordinal_position) from information_schema.columns where table_schema = 'pipeline' and table_name = 'ops_remedy_runs')
  = array['id', 'issue_id', 'remedy_code', 'started_at', 'finished_at', 'before', 'after', 'result', 'evidence'], 'C1 ops_remedy_runs has exactly the contract columns');
select fx.ok((select array_agg(code order by code) from pipeline.ops_outcome_codes) = array['blocked_evidence', 'blocked_policy', 'deferred_dependency', 'failed_remediation',
  'failed_retryable', 'not_needed', 'succeeded_no_movement', 'succeeded_with_result'] and (select array_agg(code) from pipeline.ops_outcome_codes where counts_as_movement) = array['succeeded_with_result'],
  'C1 the eight outcome codes; only succeeded_with_result counts as movement');
select fx.ok((select count(*) from information_schema.columns where table_schema = 'pipeline' and table_name = 'integration_issues'
  and column_name in ('correlation_key', 'diagnosis', 'remedy_code', 'remedy_attempts', 'next_action_at')) = 5, 'C1 the five new integration issue columns');
select fx.ok(to_regprocedure('security.ops_root_cause_register_v1(text,jsonb)') is not null and to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is not null
  and to_regprocedure('security.job_outcome_set_v1(uuid,text,jsonb)') is not null, 'C1 the three contract functions exist with their signatures');

-- C2 job outcome beside the state (backwards compatible)
insert into pipeline.admin_jobs(id, kind, state) values ('00000000-0000-4000-8000-0000000000a1', 'course_page_find', 'cancelled');
select security.job_outcome_set_v1('00000000-0000-4000-8000-0000000000a1', 'not_needed', '{"reason": "no eligible work"}');
select fx.ok((select outcome = 'not_needed' and state = 'cancelled' and outcome_detail->>'reason' = 'no eligible work' from pipeline.admin_jobs where id = '00000000-0000-4000-8000-0000000000a1'),
  'C2 not needed is a real outcome; the state is unchanged');
select fx.refused($$select security.job_outcome_set_v1('00000000-0000-4000-8000-0000000000a1', 'done_ok', '{}')$$, 'unknown job outcome%');
select fx.refused($$select security.job_outcome_set_v1('00000000-0000-4000-8000-0000000000ff', 'not_needed', '{}')$$, 'no job%');
select fx.refused($$update pipeline.admin_jobs set outcome = 'whatever' where id = '00000000-0000-4000-8000-0000000000a1'$$, '%foreign key%');
select fx.refused($$update pipeline.admin_jobs set state = 'not_needed' where id = '00000000-0000-4000-8000-0000000000a1'$$, '%admin_jobs_state_check%');
select fx.ok(true, 'C2 an unknown outcome, a missing job and a direct bad outcome are refused; the state check is unchanged');

-- C3 registers: upsert by code, refusals
select security.ops_root_cause_register_v1('fx_cause', '{"class": "transient", "title": "Fixture cause", "detect": {"priority": 500}}');
select security.ops_root_cause_register_v1('fx_cause', '{"class": "data", "title": "Fixture cause, replaced", "detect": {"priority": 501}}');
select fx.ok((select class = 'data' and title like '%replaced' and (detect->>'priority')::int = 501 from pipeline.ops_root_causes where code = 'fx_cause')
  and (select count(*) from pipeline.ops_root_causes where code = 'fx_cause') = 1, 'C3 a root cause is replaced by code, not duplicated');
select fx.refused($$select security.ops_root_cause_register_v1('fx_bad', '{"class": "weather", "title": "x y z"}')$$, '%class must be%');
create function fx.act_ok(p_issue bigint) returns jsonb language sql as $f$ select jsonb_build_object('ok', true, 'changed', false, 'evidence', jsonb_build_object('issue', p_issue)) $f$;
create function fx.verify_ok(p_issue bigint) returns jsonb language sql as $f$ select jsonb_build_object('passed', true, 'measure', '{}'::jsonb, 'evidence', '{}'::jsonb) $f$;
create function fx.act_wrong(p_issue int) returns jsonb language sql as $f$ select '{}'::jsonb $f$;
create function fx.act_sneaky(p_issue bigint) returns jsonb language plpgsql as $f$ begin perform set_config('cf247.ops_remedy', 'off', true); return '{}'::jsonb; end $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, kind, value, min_value, max_value) values ('pipeline', 'fx.attempts', 'number', '2', 1, 5) on conflict do nothing;
select security.ops_remedy_register_v1('fx_remedy', '{"title": "Fixture remedy", "treats": ["fx_cause"], "authority": "auto", "action_fn": "fx.act_ok(bigint)", "verify_fn": "fx.verify_ok(bigint)", "max_attempts_key": "fx.attempts"}');
select fx.ok((select authority = 'auto' and action_fn = 'fx.act_ok(bigint)'::regprocedure and verify_fn = 'fx.verify_ok(bigint)'::regprocedure and treats = array['fx_cause'] and active
  from pipeline.ops_remedies where code = 'fx_remedy'), 'C3 a remedy registers with its functions');
select fx.refused($$select security.ops_remedy_register_v1('fx_r2', '{"title": "Missing fn", "treats": ["fx_cause"], "authority": "auto", "action_fn": "fx.nothing_here(bigint)", "verify_fn": "fx.verify_ok(bigint)"}')$$, '%does not exist%');
select fx.refused($$select security.ops_remedy_register_v1('fx_r2', '{"title": "Wrong args", "treats": ["fx_cause"], "authority": "auto", "action_fn": "fx.act_wrong(integer)", "verify_fn": "fx.verify_ok(bigint)"}')$$, '%(p_issue bigint) returning jsonb%');
select fx.refused($$select security.ops_remedy_register_v1('fx_r2', '{"title": "No verify", "treats": ["fx_cause"], "authority": "auto", "action_fn": "fx.act_ok(bigint)"}')$$, '%needs an action and a verification%');
select fx.refused($$select security.ops_remedy_register_v1('fx_r2', '{"title": "Unknown cause", "treats": ["nope"], "authority": "auto", "action_fn": "fx.act_ok(bigint)", "verify_fn": "fx.verify_ok(bigint)"}')$$, '%unknown root cause%');
select fx.refused($$select security.ops_remedy_register_v1('fx_r2', '{"title": "Bad key", "treats": ["fx_cause"], "authority": "auto", "action_fn": "fx.act_ok(bigint)", "verify_fn": "fx.verify_ok(bigint)", "cooldown_key": "fx.nope"}')$$, '%does not exist%');
select fx.refused($$select security.ops_remedy_register_v1('fx_r2', '{"title": "Sneaky", "treats": ["fx_cause"], "authority": "auto", "action_fn": "fx.act_sneaky(bigint)", "verify_fn": "fx.verify_ok(bigint)"}')$$, '%authority boundary%');
select fx.refused($$select security.ops_remedy_register_v1('fx_r2', '{"title": "Bad authority", "treats": ["fx_cause"], "authority": "self"}')$$, '%authority must be%');
select security.ops_remedy_register_v1('fx_release', '{"title": "Fixed in a release", "treats": ["fx_cause"], "authority": "release"}');
select fx.ok((select action_fn is null and authority = 'release' from pipeline.ops_remedies where code = 'fx_release'), 'C3 a release remedy needs no function; refusals hold');

-- C4 the authority boundary on the registers: a call made while a remedy runs is refused
do $d$ begin
  perform set_config('cf247.ops_remedy', 'on', true);
  begin perform security.ops_remedy_register_v1('fx_r3', '{"title": "From a remedy", "treats": ["fx_cause"], "authority": "release"}'); raise exception 'not refused';
  exception when insufficient_privilege then null; end;
  begin perform security.ops_root_cause_register_v1('fx_c3', '{"class": "data", "title": "From a remedy"}'); raise exception 'not refused';
  exception when insufficient_privilege then null; end;
  perform set_config('cf247.ops_remedy', '', true);
end $d$;
select fx.ok(not exists (select 1 from pipeline.ops_remedies where code = 'fx_r3') and not exists (select 1 from pipeline.ops_root_causes where code = 'fx_c3'),
  'C4 a remedy cannot register remedies or root causes');

-- clean the fixture rows so later fixtures start from the shipped registers
delete from pipeline.ops_remedies where code like 'fx\_%'; delete from pipeline.ops_root_causes where code like 'fx\_%';
delete from pipeline.admin_jobs where id = '00000000-0000-4000-8000-0000000000a1';
