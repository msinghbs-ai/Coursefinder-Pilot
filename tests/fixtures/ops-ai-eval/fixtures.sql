-- CF-247 P0 workstream E fixtures: every case of migration 20261104070000 on the seed (seed.sql). Each check raises on failure and prints
-- "ok: ..." on success. The fixture acts as the Platform Admin only where it says so (a setting changed with a reason). No AI call is made:
-- the worker's answers are recorded answers (fx.answers below).
grant usage on schema fx to service_role;  -- the fixture's own helpers (fx.ok, fx.fails) are callable while acting as the worker role
create or replace function fx.ok(p boolean, p_msg text) returns void language plpgsql as $$
begin if p is not true then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok: %', p_msg; end $$;
-- runs p_sql (optionally on the AI path, or while an ops remedy runs) and expects an error matching p_pattern
create or replace function fx.fails(p_sql text, p_pattern text, p_msg text, p_path text default null) returns void language plpgsql as $$
declare v_err text;
begin
  begin
    if p_path = 'ai' then perform set_config('cf247.ai_eval_path', 'on', true); elsif p_path = 'remedy' then perform set_config('cf247.ops_remedy', 'on', true);
    elsif p_path = 'release' then perform set_config('cf247.release', '20261104070000', true);
    elsif p_path = 'release+ai' then perform set_config('cf247.release', '20261104070000', true); perform set_config('cf247.ai_eval_path', 'on', true);
    elsif p_path = 'release+remedy' then perform set_config('cf247.release', '20261104070000', true); perform set_config('cf247.ops_remedy', 'on', true); end if;
    execute p_sql;
  exception when others then v_err := sqlerrm; end;
  perform set_config('cf247.ai_eval_path', '', true); perform set_config('cf247.ops_remedy', '', true); perform set_config('cf247.release', '', true);
  if v_err is null then raise exception 'FAILED (no error): %', p_msg; end if;
  if v_err not like p_pattern then raise exception 'FAILED (wrong error "%"): %', v_err, p_msg; end if;
  raise notice 'ok (refused: %): %', left(v_err, 90), p_msg;
end $$;
create or replace function fx.pid(p_code text) returns bigint language sql as $$ select id from pipeline.ai_improvement_proposals where code = p_code $$;
create or replace function fx.vid(p_code text, p_version text) returns bigint language sql as $$ select id from pipeline.ai_instruction_versions where code = p_code and version = p_version $$;
create or replace function fx.ex(p_family text, p_entity uuid) returns bigint language sql as $$ select id from pipeline.ai_eval_examples where family = p_family and entity_id = p_entity and tier = 'person' order by id limit 1 $$;
-- recorded answers for the page_identity set (examples for c1 accept, c2 reject, c3 correct, c9 no page)
create or replace function fx.answers(p_kind text) returns jsonb language sql as $$
  select jsonb_build_object('worker', 'fixture recorded answers', 'answers', jsonb_agg(a)) from (
    select jsonb_build_object('example_id', fx.ex('page_identity', fx.u('c1')), 'verdict', case when p_kind = 'B' then 'no_value' else 'accept' end, 'value', '"https://u.edu/c1"'::jsonb, 'tokens_in', 900, 'tokens_out', 40,
                              'cost_usd', case when p_kind = 'B' then 0.002 else 0.001 end) a
    union all select jsonb_build_object('example_id', fx.ex('page_identity', fx.u('c2')), 'verdict', case when p_kind = 'base' then 'accept' else 'no_value' end,
                              'value', case when p_kind = 'base' then '"https://dir.example.com/c2"'::jsonb end, 'tokens_in', 900, 'tokens_out', 40, 'cost_usd', case when p_kind = 'B' then 0.002 else 0.001 end)
    union all select jsonb_build_object('example_id', fx.ex('page_identity', fx.u('c3')), 'verdict', 'accept',
                              'value', case when p_kind = 'base' then '"http://u.edu/handbook/c3"'::jsonb else '"https://u.edu/c3/"'::jsonb end, 'tokens_in', 900, 'tokens_out', 40, 'cost_usd', case when p_kind = 'B' then 0.002 else 0.001 end)
    union all select jsonb_build_object('example_id', fx.ex('page_identity', fx.u('c9')), 'verdict', 'no_value', 'value', null, 'tokens_in', 900, 'tokens_out', 40, 'cost_usd', case when p_kind = 'B' then 0.002 else 0.001 end)) z $$;

-- 1. the migration: registers, baselines, proposals, root causes, remedies, job ---------------------------------------------------------------
select fx.ok((select count(*) from pipeline.ai_instruction_versions where status = 'current') = 9, 'nine live baselines registered as current (worker constants, scholarship prompt v2, rule and schema baselines)');
select fx.ok((select bool_and(security.ai_model_pinned_ok_v1(model_identifier)) from pipeline.ai_instruction_versions where kind = 'prompt'), 'every prompt version names one pinned, listed model');
select fx.ok((select body_md5 from pipeline.ai_instruction_versions where code = 'scholarship-page' and status = 'current') = md5('v2 text'), 'the scholarship baseline is the md5 of the active database prompt (version 2)');
select fx.ok((select count(*) from pipeline.ai_improvement_proposals where status = 'proposed' and authority = 'release' and production_evidence ? 'measured_at' and production_evidence ? 'counts'
              and length(problem_observed) > 100 and length(risks) > 50 and baseline_version_id is not null and candidate_version_id is not null) = 3, 'three seeded proposals with evidence, baseline and candidate, on the release path');
select fx.ok((select (production_evidence#>>'{counts,held_intake_not_matched}')::int = 178 from pipeline.ai_improvement_proposals where code = 'ai-p1-deadline-verbatim'), 'P1 carries the measured deadline holds');
select fx.ok((select count(*) from pipeline.ops_root_causes where code in ('ai_quote_not_verbatim', 'ai_page_identity_mismatch', 'ai_instruction_regression')) = 3, 'three root causes registered in workstream A''s register');
select fx.ok((select authority = 'auto' and action_fn = 'security.ai_remedy_canary_rollback_v1(bigint)'::regprocedure and verify_fn is not null from pipeline.ops_remedies where code = 'ai_canary_rollback')
         and (select authority = 'release' and action_fn is null from pipeline.ops_remedies where code = 'ai_improvement_proposal'), 'remedies registered: ai_canary_rollback (auto: stops a canary) and ai_improvement_proposal (release)');
select fx.ok((select command = 'select security.ai_eval_tick_v1()' and schedule = '7 * * * *' from cron.job where jobname = 'ai-eval') and exists (select 1 from pipeline.automation_catalogue where jobname = 'ai-eval'),
             'job ai-eval at minute 7, catalogued, no number in its command');
select fx.ok((select count(*) from pipeline.ai_auto_tunable_settings) = 4, 'the allow-list holds the four batch sizes that have a live minimum and maximum');

-- 2. datasets: trusted only, incremental, deduplicated -------------------------------------------------------------------------------------
select fx.ok((security.ai_eval_tick_v1()->'examples'->>'l4_decision')::int = 4, 'first run: four Layer 4 decisions by a person with a reason');
select fx.ok((select (security.ai_eval_counts_v1()->'page_identity'->>'active')::int = 4 and (security.ai_eval_counts_v1()->'page_identity'->>'person')::int = 4), 'page identity: approve, reject, rule edit, a person''s removal (4)');
select fx.ok((select count(*) from pipeline.ai_eval_examples where entity_id = fx.u('c1') and family = 'page_identity') = 1, 'the manual edit that repeats Layer 4 decision e1 adds no second label');
select fx.ok((select (c->'course_fields'->>'active')::int = 3 and (c->'course_fields'->>'person')::int = 1 and (c->'course_fields'->>'inactive')::int = 1 from security.ai_eval_counts_v1() c),
             'course fields: one person decision, two quote-checked readings; the reading a person contradicted is inactive');
select fx.ok((select (c->'deadline'->>'verified_quote')::int = 1 and (c->'deadline'->>'person')::int = 0 and (c->'entry_requirements'->>'active')::int = 1
                 and (c->'provider_course_matching'->>'active')::int = 3 and (c->'scholarship_classification'->>'active')::int = 2 and (c->'course_description'->>'active')::int = 0
                from security.ai_eval_counts_v1() c), 'deadline 1 (quote only), entry 1, provider and course matching 3 (website edit, lock, match case), scholarships 2, descriptions 0');
select fx.ok(not exists (select 1 from pipeline.ai_eval_examples where source_ref in ('layer4_decisions:' || fx.u('e5'), 'layer4_decisions:' || fx.u('e6'), 'layer4_decisions:' || fx.u('e7'))),
             'not ground truth: a decision by a non-person, a return to Layer 2, a decision without a reason');
select fx.ok(not exists (select 1 from pipeline.ai_eval_examples where entity_id in (fx.u('c10'), fx.u('b3'), fx.u('c5'), fx.u('53'), fx.u('54'))) and not exists (select 1 from pipeline.ai_eval_examples where entity_id = fx.u('c3') and field = 'intakes')
         and not exists (select 1 from pipeline.ai_eval_examples where entity_id = fx.u('c6') and source_ref in (select 'field_enrich_items:' || id from pipeline.field_enrich_items where source in ('register', 'ai_stored'))),
             'not ground truth: an edit or lock by a non-person, a reading with no quote, a reading under review, an AI campus reading, an undecided or superseded scholarship');
select fx.ok((select count(*) from pipeline.ai_eval_examples where source_kind = 'match_case') = 1, 'one match case: the matcher''s list for c1 labelled by the page a person chose (c9 has only a no-page label)');
select fx.ok((select sum(v::int) from jsonb_each_text(security.ai_eval_tick_v1()->'examples') e(k, v)) = 0, 'second run adds nothing (incremental)');

-- 3. ground truth is enforced in data -----------------------------------------------------------------------------------------------------
select fx.fails($$insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, field, label, expected) values ('deadline', 'l4_decision', 'person', 'person', 'x:1', 'k1', 'course', 'deadline', 'accept', '"x"')$$,
                '%no person decided it%', 'a person-tier example with no person is refused');
select fx.fails($$insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, field, label, expected) values ('deadline', 'quote_evidence', 'verified_quote', 'quote_check', 'x:2', 'k2', 'course', 'deadline', 'accept', '"x"')$$,
                '%no quote on a stored page%', 'a reading without a quote on a stored page is refused');
select fx.fails($$insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, field, label, expected, decided_by) values ('deadline', 'ai_output', 'person', 'person', 'x:3', 'k3', 'course', 'deadline', 'accept', '"x"', fx.u('a1'))$$,
                '%violates check constraint%', 'unreviewed AI output is not a source kind');
select fx.fails($$update pipeline.ai_eval_examples set label = 'reject' where source_ref = 'layer4_decisions:' || fx.u('e1')$$, '%kept as recorded%', 'an example''s label cannot be rewritten');

-- 4. pinned models only ------------------------------------------------------------------------------------------------------------------
select fx.fails($$select security.ai_instruction_register_v1('{"family": "page_identity", "code": "page-identity", "kind": "prompt", "version": "r1", "status": "candidate", "model": "openrouter/auto", "body": "x"}')$$,
                '%one pinned, listed model%', 'openrouter/auto is refused');
select fx.fails($$select security.ai_instruction_register_v1('{"family": "page_identity", "code": "page-identity", "kind": "prompt", "version": "r2", "status": "candidate", "model": "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free", "body": "x"}')$$,
                '%one pinned, listed model%', 'a model whose only profile is retired is refused');
select fx.fails($$select security.ai_instruction_register_v1('{"family": "page_identity", "code": "page-identity", "kind": "prompt", "version": "r3", "status": "candidate", "model": "acme/unqualified-1", "body": "x"}')$$,
                '%one pinned, listed model%', 'a model no register lists is refused');
select fx.fails($$select security.ai_instruction_register_v1('{"family": "page_identity", "code": "page-identity", "kind": "prompt", "version": "r4", "status": "current", "model": "qwen/qwen3-30b-a3b-instruct-2507", "body": "x"}')$$,
                '%cannot make a version current%', 'the AI cannot make a version current', 'ai');

-- 5. offline regression evaluation on recorded answers -----------------------------------------------------------------------------------
update pipeline.platform_toolset_settings set value = '3', reason = 'fixture: Platform Admin lowers the person-decision minimum for a four-example set' where key = 'ai_eval.min_person_examples';
select fx.ok((security.ai_eval_set_freeze_v1('page_identity')->>'person')::int = 4, 'page identity set v1 frozen: 4 examples, all decided by a person');
select security.ai_instruction_register_v1(jsonb_build_object('family', 'page_identity', 'code', 'page-identity', 'kind', 'prompt', 'version', 'fx-' || v, 'status', 'candidate',
       'model', 'qwen/qwen3-30b-a3b-instruct-2507', 'body', 'fixture candidate ' || v)) from unnest(array['a', 'b', 'c', 'd']) v;
select fx.fails($$select security.ai_instruction_register_v1('{"family": "page_identity", "code": "page-identity", "kind": "prompt", "version": "fx-a", "status": "candidate", "model": "qwen/qwen3-30b-a3b-instruct-2507", "body": "other text"}')$$,
                '%already registered with other content%', 'a version is never rewritten');
create or replace function fx.submit(p_code text, p_version text, p_set bigint) returns jsonb language sql as $$
  select security.ai_proposal_submit_v1(jsonb_build_object('code', p_code, 'family', 'page_identity', 'change_class', 'prompt', 'authority', 'auto', 'proposed_by', 'platform_ai',
    'title', 'fixture ' || p_code, 'problem_observed', 'wrong pages chosen', 'current_method', 'page identity v1.0.2', 'proposed_change', 'candidate ' || p_version,
    'production_evidence', '{"measured_at": "2026-11-03T16:00+11:00", "counts": {"rejected": 448}}'::jsonb, 'expected_benefit', 'fewer wrong pages', 'risks', 'fixture risk',
    'baseline_version_id', fx.vid('page-identity', 'cf247-page-identity-v1.0.2'), 'candidate_version_id', fx.vid('page-identity', p_version), 'eval_set_id', p_set,
    'acceptance_criteria_extra', '{"max_fp_rate_rise_pts": 50, "note": "fixture"}'::jsonb)) $$;
select fx.ok((fx.submit('fx-a', 'fx-a', (select id from pipeline.ai_eval_sets where family = 'page_identity'))->>'authority') = 'release', 'the AI asked for auto authority on a prompt change and got release (the boundary table decides)');
select fx.ok((select (acceptance_criteria->>'max_fp_rate_rise_pts')::numeric = 0 and acceptance_criteria->>'note' = 'fixture' from pipeline.ai_improvement_proposals where code = 'fx-a'),
             'extra criteria add measures but cannot loosen one in force (false-positive rise stays 0)');
select security.ai_eval_run_open_v1(fx.pid('fx-a'), 'baseline'), security.ai_eval_run_open_v1(fx.pid('fx-a'), 'candidate');
select fx.ok((select status from pipeline.ai_improvement_proposals where code = 'fx-a') = 'evaluating', 'opening the runs moves the proposal to evaluating');
set role service_role;
select fx.ok((public.svc_ai_eval_run_next_v1()->>'run') is null, 'the worker gets no run while ai_eval.offline_runs_on is 0 (answering spends)');
reset role;
update pipeline.platform_toolset_settings set value = '1', reason = 'fixture: Platform Admin lets the worker answer' where key = 'ai_eval.offline_runs_on';
set role service_role;
select fx.ok((select jsonb_array_length(r->'examples') = 4 and r#>>'{version,model}' = 'qwen/qwen3-30b-a3b-instruct-2507' from public.svc_ai_eval_run_next_v1() r), 'the worker leases a run: 4 examples and the pinned model');
reset role;
-- the worker's recorded answers (the fixture records them through the same function the worker calls)
select public.svc_ai_eval_answer_record_v1((select id from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-a') and arm = 'baseline'), fx.answers('base'));
select public.svc_ai_eval_answer_record_v1((select id from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-a') and arm = 'candidate'), fx.answers('A'));
update pipeline.platform_toolset_settings set value = '0', reason = 'fixture: back to the shipped value' where key = 'ai_eval.offline_runs_on';
select security.ai_eval_tick_v1();
select fx.ok((select metrics->>'accuracy_pct' = '50.00' and (metrics->>'false_positives')::int = 2 and (metrics->>'false_negatives')::int = 0 and metrics->>'coverage_pct' = '100.00'
                 and (metrics->>'cost_usd')::numeric = 0.004 and (metrics->>'tokens_in')::int = 3600 from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-a') and arm = 'baseline'),
             'baseline scored: accuracy 50%, 2 false positives (the directory page given, the handbook page given), coverage 100%, US$0.004, 3,600 tokens in');
select fx.ok((select metrics->>'accuracy_pct' = '100.00' and (metrics->>'false_positives')::int = 0 and metrics#>>'{person,accuracy_pct}' = '100.00' from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-a') and arm = 'candidate'),
             'candidate scored: accuracy 100%, no false positives (a trailing slash and http/https are the same address)');
select fx.ok((select (actual_results#>>'{offline,passed}')::boolean and status = 'evaluating' and actual_results#>>'{offline,verdict}' = 'passed offline' from pipeline.ai_improvement_proposals where code = 'fx-a'),
             'fx-a passed offline: +50 points accuracy, no regression on the seven criteria; it stays evaluating (canary is a separate step)');

-- a regression is rejected and enters the ledger; the same change is refused afterwards
select fx.submit('fx-b', 'fx-b', (select id from pipeline.ai_eval_sets where family = 'page_identity'));
select security.ai_eval_run_open_v1(fx.pid('fx-b'), 'baseline'), security.ai_eval_run_open_v1(fx.pid('fx-b'), 'candidate');
select public.svc_ai_eval_answer_record_v1((select id from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-b') and arm = 'baseline'), fx.answers('base'));
select public.svc_ai_eval_answer_record_v1((select id from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-b') and arm = 'candidate'), fx.answers('B'));
select security.ai_eval_tick_v1();
select fx.ok((select status = 'rejected' and actual_results#>'{offline,regressions}' = '["cost", "coverage"]'::jsonb from pipeline.ai_improvement_proposals where code = 'fx-b'),
             'fx-b rejected: accuracy +25 points but coverage -50 points and cost +100%');
select fx.ok((select outcome = 'rejected' and proposal_id = fx.pid('fx-b') from pipeline.ai_rejected_proposals where fingerprint = (select fingerprint from pipeline.ai_improvement_proposals where code = 'fx-b')), 'fx-b is in the rejected-proposal ledger');
select fx.ok((fx.submit('fx-b2', 'fx-b', (select id from pipeline.ai_eval_sets where family = 'page_identity'))->>'refused') = 'rejected before', 'the same change under a new code is refused: rejected before');
select fx.fails($$insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence, expected_benefit, risks, acceptance_criteria, fingerprint, proposed_by)
                  select 'fx-b3', family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence, expected_benefit, risks, '{}', fingerprint, 'platform_ai' from pipeline.ai_improvement_proposals where code = 'fx-b'$$,
                '%is not proposed again%', 'a direct insert of the rejected change is refused too');
select fx.ok((select count(*) from pipeline.ai_proposal_events where proposal_id = fx.pid('fx-b')) = 3, 'fx-b history kept: proposed, evaluating, rejected');

-- quote-checked readings alone never judge a change; source integrity is measured
select security.ai_eval_set_freeze_v1('deadline');
select security.ai_instruction_register_v1(jsonb_build_object('family', 'deadline', 'code', 'course-text', 'kind', 'prompt', 'version', 'fx-e', 'status', 'candidate', 'model', 'openai/gpt-4.1-mini', 'body', 'fixture deadline candidate'));
select security.ai_proposal_submit_v1(jsonb_build_object('code', 'fx-e', 'family', 'deadline', 'change_class', 'prompt', 'proposed_by', 'platform_ai', 'title', 'fixture e', 'problem_observed', 'held deadlines',
  'current_method', 'course-text-v1', 'proposed_change', 'fx-e', 'production_evidence', '{"measured_at": "2026-11-03T16:00+11:00", "counts": {"held": 413}}'::jsonb, 'expected_benefit', 'more deadlines', 'risks', 'fixture',
  'baseline_version_id', fx.vid('course-text', 'course-text-v1'), 'candidate_version_id', fx.vid('course-text', 'fx-e'), 'eval_set_id', (select id from pipeline.ai_eval_sets where family = 'deadline')));
select security.ai_eval_run_open_v1(fx.pid('fx-e'), 'baseline'), security.ai_eval_run_open_v1(fx.pid('fx-e'), 'candidate');
select public.svc_ai_eval_answer_record_v1((select id from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-e') and arm = a), jsonb_build_object('answers', jsonb_build_array(jsonb_build_object(
         'example_id', (select id from pipeline.ai_eval_examples where family = 'deadline'), 'verdict', 'accept', 'value', '{"date": "2027-01-15"}'::jsonb, 'quote', 'Applications close 15 January 2027',
         'quote_on_page', a = 'baseline', 'tokens_in', 5000, 'tokens_out', 120, 'cost_usd', 0.003)))) from unnest(array['baseline', 'candidate']) a;
select security.ai_eval_tick_v1();
select fx.ok((select metrics->>'source_integrity_pct' = '0.00' from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-e') and arm = 'candidate')
         and (select metrics->>'source_integrity_pct' = '100.00' from pipeline.ai_eval_runs where proposal_id = fx.pid('fx-e') and arm = 'baseline'), 'source integrity measured: the candidate''s quote is not on the page (0%), the baseline''s is (100%)');
select fx.ok((select status = 'evaluating' and actual_results#>>'{offline,verdict}' = 'not enough decisions by a person to judge' from pipeline.ai_improvement_proposals where code = 'fx-e'),
             'a set of quote-checked readings only (0 person decisions) never judges a change: it stays evaluating');

-- 6. canary ------------------------------------------------------------------------------------------------------------------------------
select fx.ok((select r->>'why' = 'canary off' and not (r->>'canary')::boolean and (r->>'version_id')::bigint = fx.vid('page-identity', 'cf247-page-identity-v1.0.2')
                from security.ai_canary_pick_v1('page-identity', 'course:x') r), 'with ai_eval.canary_on 0 every item gets the current version');
select fx.ok((security.ai_proposal_advance_v1(fx.pid('fx-a'), 'canary', 'passed offline')->>'refused') = 'canary routing is off (ai_eval.canary_on)', 'a canary cannot start while canary routing is off');
update pipeline.platform_toolset_settings set value = (case key when 'ai_eval.canary_on' then '1' when 'ai_eval.canary_share_pct' then '20' else '5' end)::jsonb, reason = 'fixture: Platform Admin switches canary routing on'
 where key in ('ai_eval.canary_on', 'ai_eval.canary_share_pct', 'ai_eval.canary_min_judged');
select fx.ok((security.ai_proposal_advance_v1(fx.pid('fx-b'), 'canary', 'try')->>'refused') = 'not passed offline', 'a rejected change never reaches canary');
select fx.ok((security.ai_proposal_advance_v1(fx.pid('fx-a'), 'canary', 'passed offline')->>'status') = 'canary', 'fx-a in canary');
select security.ai_canary_pick_v1('page-identity', 'course:k' || g, 'page_identity', md5('k' || g)::uuid) from generate_series(1, 200) g;
select fx.ok((select count(*) filter (where arm = 'candidate') between 20 and 50 and count(*) = 200 from pipeline.ai_canary_assignments where proposal_id = fx.pid('fx-a')),
             'a bounded share of 200 live items goes to the candidate (20% share, at most 50 a day): ' || (select count(*) filter (where arm = 'candidate') from pipeline.ai_canary_assignments where proposal_id = fx.pid('fx-a')));
select fx.ok((select bool_and((security.ai_canary_pick_v1('page-identity', item_key)->>'canary')::boolean = (arm = 'candidate')) from pipeline.ai_canary_assignments where proposal_id = fx.pid('fx-a')),
             'an item always gets the same version');
select public.svc_ai_canary_answer_record_v1('fx-a', item_key, jsonb_build_object('verdict', 'accept', 'value', to_jsonb(case when arm = 'candidate' then 'https://u.edu/' else 'https://dir.example.com/' end || substr(item_key, 8)),
       'quote_on_page', true, 'cost_usd', 0.001, 'tokens_in', 900, 'tokens_out', 40)) from pipeline.ai_canary_assignments where proposal_id = fx.pid('fx-a');
select fx.ok((security.ai_canary_judge_v1(fx.pid('fx-a'))->>'verdict') = 'canary running', 'no person has decided a canary item yet: the canary keeps running');
-- later, people decide those courses in Layer 4
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) select md5('ri-k' || g)::uuid, 'course', md5('k' || g)::uuid, 'official_course_url', 'approved' from generate_series(1, 200) g;
insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, proposed_value, created_at)
select md5('ri-k' || g)::uuid, 'approve', fx.u('a2'), 'The provider''s own course page', jsonb_build_object('course_url', 'https://u.edu/k' || g), clock_timestamp() + interval '1 second' from generate_series(1, 200) g;
select security.ai_eval_tick_v1();
select fx.ok((select (actual_results#>>'{canary,passed}')::boolean and (actual_results#>>'{canary,candidate,accuracy_pct}') = '100.00' and (actual_results#>>'{canary,current,accuracy_pct}') = '0.00'
                 and status = 'canary' from pipeline.ai_improvement_proposals where code = 'fx-a'), 'fx-a canary judged on later decisions by a person: candidate 100%, current 0%; passed, still canary');
-- a quote-checked reading made after a canary answer is never used to judge it (it may be the canary's own output)
insert into pipeline.ai_canary_assignments(proposal_id, item_key, family, entity_id, arm, version_id, verdict, value, answered_at)
values (fx.pid('ai-p1-deadline-verbatim'), 'course:q1:deadline', 'deadline', fx.u('c8'), 'candidate', fx.vid('course-text', 'course-text-v2-candidate'), 'accept', '{"date": "2027-03-01"}', now() - interval '1 hour');
insert into pipeline.field_enrich_items(course_id, provider_id, field, state, source, value, quote, storage_path, updated_at)
values (fx.u('c8'), fx.u('b2'), 'deadline', 'filled', 'ai_stored', '{"date": "2027-03-01"}', 'Applications close 1 March 2027', 'evidence/c8.txt', now());
select security.ai_eval_dataset_refresh_v1();
select fx.ok((select r->>'verdict' = 'canary running' and (r->>'judged')::int = 0 from security.ai_canary_judge_v1(fx.pid('ai-p1-deadline-verbatim')) r), 'a later quote-checked reading judges nothing: 0 judged');

-- 7. acceptance is the release path; rollback keeps the previous version ------------------------------------------------------------------
select fx.fails($$select security.ai_proposal_advance_v1(fx.pid('fx-a'), 'accepted', 'the AI accepts its own prompt')$$, '%accepted only through the release path%', 'the AI cannot accept its own prompt change');
select fx.fails($$select security.ai_proposal_record_release_v1(fx.pid('fx-a'), '20261105000000', 'platform_ai')$$, '%cannot accept its own%', 'the release function is refused on the AI path', 'ai');
select fx.fails($$select security.ai_proposal_record_release_v1(fx.pid('fx-e'), '20261105000000', 'Platform Admin')$$, '%no passed evaluation%', 'a change without a passed evaluation cannot be released');
select fx.ok((security.ai_proposal_record_release_v1(fx.pid('fx-a'), '20261105000000', 'Platform Admin')->>'status') = 'accepted', 'released by the release path: fx-a accepted');
select fx.ok((select status from pipeline.ai_instruction_versions where id = fx.vid('page-identity', 'fx-a')) = 'current'
         and (select status from pipeline.ai_instruction_versions where id = fx.vid('page-identity', 'cf247-page-identity-v1.0.2')) = 'previous', 'the candidate is current and the old version kept as previous');
select fx.ok((security.ai_proposal_rollback_v1(fx.pid('fx-a'), 'post-release monitoring found a regression')->>'status') = 'rolled_back', 'fx-a rolled back after release');
select fx.ok((select status from pipeline.ai_instruction_versions where id = fx.vid('page-identity', 'cf247-page-identity-v1.0.2')) = 'current'
         and (select status from pipeline.ai_instruction_versions where id = fx.vid('page-identity', 'fx-a')) = 'rolled_back'
         and exists (select 1 from pipeline.ai_rejected_proposals where proposal_id = fx.pid('fx-a') and outcome = 'rolled_back'), 'the previous version is current again; fx-a is in the ledger as rolled back');
select fx.ok((fx.submit('fx-a2', 'fx-a', (select id from pipeline.ai_eval_sets where family = 'page_identity'))->>'refused') = 'rejected before', 'a rolled-back change is not proposed again');

-- 8. a failing canary is rolled back automatically; the controller's remedy stops a canary --------------------------------------------------
create or replace function fx.offline_pass(p_code text) returns void language sql as $$
  select fx.submit(p_code, p_code, (select id from pipeline.ai_eval_sets where family = 'page_identity'));
  select security.ai_eval_run_open_v1(fx.pid(p_code), 'baseline'), security.ai_eval_run_open_v1(fx.pid(p_code), 'candidate');
  select public.svc_ai_eval_answer_record_v1((select id from pipeline.ai_eval_runs where proposal_id = fx.pid(p_code) and arm = 'baseline'), fx.answers('base'));
  select public.svc_ai_eval_answer_record_v1((select id from pipeline.ai_eval_runs where proposal_id = fx.pid(p_code) and arm = 'candidate'), fx.answers('A'));
  select security.ai_eval_tick_v1();
  select security.ai_proposal_advance_v1(fx.pid(p_code), 'canary', 'passed offline');
$$;
select fx.offline_pass('fx-d');
select security.ai_canary_pick_v1('page-identity', 'course:n' || g, 'page_identity', md5('n' || g)::uuid) from generate_series(1, 200) g;
select public.svc_ai_canary_answer_record_v1('fx-d', item_key, jsonb_build_object('verdict', 'accept', 'value', to_jsonb(case when arm = 'candidate' then 'https://dir.example.com/' else 'https://u.edu/' end || substr(item_key, 8)),
       'quote_on_page', true, 'cost_usd', 0.001)) from pipeline.ai_canary_assignments where proposal_id = fx.pid('fx-d');
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status) select md5('ri-n' || g)::uuid, 'course', md5('n' || g)::uuid, 'official_course_url', 'approved' from generate_series(1, 200) g;
insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, proposed_value, created_at)
select md5('ri-n' || g)::uuid, 'approve', fx.u('a2'), 'The provider''s own course page', jsonb_build_object('course_url', 'https://u.edu/n' || g), clock_timestamp() + interval '1 second' from generate_series(1, 200) g;
select security.ai_eval_tick_v1();
select fx.ok((select status = 'rolled_back' and status_reason like 'canary failed: regression in%' from pipeline.ai_improvement_proposals where code = 'fx-d')
         and exists (select 1 from pipeline.ai_rejected_proposals where proposal_id = fx.pid('fx-d') and outcome = 'rolled_back'), 'fx-d canary did worse on later decisions by a person: rolled back automatically and put in the ledger');
select fx.offline_pass('fx-c');
select fx.ok((select status from pipeline.ai_improvement_proposals where code = 'fx-c') = 'canary', 'fx-c in canary');
insert into pipeline.integration_issues(id, fingerprint, title, diagnosis) values (900, 'ai:fx-c', 'canary fx-c regressing', '{"root_cause": "ai_instruction_regression", "confidence": 0.9, "evidence": [{"proposal": "fx-c"}], "method": "fixture"}');
do $$ begin
  perform set_config('cf247.ops_remedy', 'on', true);   -- as the controller runs an auto remedy
  perform fx.ok((security.ai_remedy_canary_rollback_v1(900)->>'changed')::boolean, 'remedy ai_canary_rollback stops the canary');
  perform set_config('cf247.ops_remedy', '', true);
end $$;
select fx.ok((select status from pipeline.ai_improvement_proposals where code = 'fx-c') = 'rolled_back' and (security.ai_remedy_canary_verify_v1(900)->>'passed')::boolean, 'fx-c rolled back by the remedy; its verification passes');

-- 9. operational adjustments inside guardrails ---------------------------------------------------------------------------------------------
create or replace function fx.op(p_code text, p_toolset text, p_key text, p_value numeric, p_extra jsonb default '{}') returns jsonb language sql as $$
  select security.ai_proposal_submit_v1(jsonb_build_object('code', p_code, 'family', 'course_fields', 'change_class', 'operational_adjustment', 'proposed_by', 'platform_ai',
    'title', 'tune ' || p_key, 'problem_observed', 'time-outs', 'current_method', 'fixed batch', 'proposed_change', p_key || ' to ' || p_value,
    'production_evidence', '{"measured_at": "2026-11-03T16:00+11:00", "counts": {"timeouts": 3}}'::jsonb, 'expected_benefit', 'fewer time-outs', 'risks', 'slower throughput',
    'target_setting', jsonb_build_object('toolset', p_toolset, 'key', p_key, 'value', p_value) || p_extra)) $$;
select fx.fails($$select fx.op('op-x1', 'openrouter', 'guard_enrich_fields', 30)$$, '%not a setting the AI may tune%', 'a spending guard is not tunable');
select fx.fails($$select fx.op('op-x2', 'pipeline', 'ai_eval.canary_on', 1)$$, '%not a setting the AI may tune%', 'the AI''s own switches are not tunable');
select fx.fails($$select fx.op('op-x3', 'pipeline', 'batch.enrich_fields', 6000)$$, '%outside its range%', 'a value above the setting''s maximum is refused');
select fx.fails($$select fx.op('op-x4', 'pipeline', 'batch.enrich_fields', 2000)$$, '%at most 25 percent%', 'a step beyond ai_eval.auto_step_max_pct is refused');
select fx.fails($$select fx.op('op-x5', 'pipeline', 'batch.enrich_fields', 1400, '{"max_value": 9000}')$$, '%minimum and maximum are not changed%', 'a setting''s ceiling is never part of a proposal');
select fx.ok((fx.op('op-1', 'pipeline', 'batch.enrich_fields', 1400)->>'authority') = 'auto', 'batch.enrich_fields 1,200 to 1,400: inside range and step, authority auto');
select fx.ok((security.ai_proposal_advance_v1(fx.pid('op-1'), 'canary', 'trial')->>'refused') = 'automatic acceptance is off (ai_eval.auto_accept_on)', 'with ai_eval.auto_accept_on 0 nothing is tried');
select fx.ok((select value #>> '{}' from pipeline.platform_toolset_settings where key = 'batch.enrich_fields') = '1200', 'the setting is unchanged');
update pipeline.platform_toolset_settings set value = '1', reason = 'fixture: Platform Admin allows automatic operational adjustments' where key = 'ai_eval.auto_accept_on';
select fx.ok((security.ai_proposal_advance_v1(fx.pid('op-1'), 'canary', 'trial')->>'status') = 'canary', 'trial started');
select fx.ok((select value #>> '{}' from pipeline.platform_toolset_settings where key = 'batch.enrich_fields') = '1400' and (select applied->>'before' from pipeline.ai_improvement_proposals where code = 'op-1') = '1200',
             'trial: batch.enrich_fields is 1,400, the previous value (1,200) kept with the proposal');
select fx.ok((security.ai_proposal_advance_v1(fx.pid('op-1'), 'accepted', 'measured')->>'refused') = 'measured before and after results are needed', 'acceptance needs measured results');
select fx.ok((security.ai_proposal_advance_v1(fx.pid('op-1'), 'accepted', 'measured', '{"before": {"accuracy_pct": 90, "coverage_pct": 80, "fp_rate_pts": 0, "error_rate_pts": 5, "cost_usd": 10, "source_integrity_pct": 100},
               "after": {"accuracy_pct": 92, "coverage_pct": 85, "fp_rate_pts": 0, "error_rate_pts": 3, "cost_usd": 10, "source_integrity_pct": 100}}')->>'status') = 'accepted', 'measured benefit, no regression: accepted automatically');
select fx.op('op-2', 'pipeline', 'enrich.ai_items_per_call', 36);
select security.ai_proposal_advance_v1(fx.pid('op-2'), 'canary', 'trial');
select fx.ok((select value #>> '{}' from pipeline.platform_toolset_settings where key = 'enrich.ai_items_per_call') = '36', 'trial: enrich.ai_items_per_call 30 to 36');
select fx.ok((security.ai_proposal_advance_v1(fx.pid('op-2'), 'accepted', 'measured', '{"before": {"accuracy_pct": 90, "coverage_pct": 80, "fp_rate_pts": 0, "error_rate_pts": 2, "cost_usd": 10, "source_integrity_pct": 100},
               "after": {"accuracy_pct": 90, "coverage_pct": 83, "fp_rate_pts": 0, "error_rate_pts": 7, "cost_usd": 10, "source_integrity_pct": 100}}')->>'status') = 'rolled_back', 'more time-outs (error rate +5 points): rolled back');
select fx.ok((select value #>> '{}' from pipeline.platform_toolset_settings where key = 'enrich.ai_items_per_call') = '30', 'enrich.ai_items_per_call put back to 30');
select fx.ok((fx.op('op-2b', 'pipeline', 'enrich.ai_items_per_call', 36)->>'refused') = 'rejected before', 'the failed adjustment is not proposed again');
select fx.ok((select count(*) from pipeline.admin_control_events where area = 'ai_eval') = 3, 'every trial and put-back is in the control events (2 trials, 1 put-back)');

-- 10. the AI cannot change its approval boundaries ------------------------------------------------------------------------------------------
select fx.fails($$update pipeline.ai_approval_boundaries set authority = 'auto' where change_class = 'prompt'$$, '%only in a release migration%', 'boundaries change only in a release');
select fx.fails($$update pipeline.ai_approval_boundaries set authority = 'auto' where change_class = 'prompt'$$, '%cannot change its approval boundaries%', 'not on the AI path, even inside a release', 'release+ai');
select fx.fails($$update pipeline.ai_approval_boundaries set authority = 'auto' where change_class = 'admission_rule'$$, '%cannot change its approval boundaries%', 'not while an ops remedy runs', 'release+remedy');
select fx.fails($$insert into pipeline.ai_auto_tunable_settings values ('pipeline', 'ai_eval.auto_accept_on', 'x')$$, '%not an operational setting%', 'the allow-list never takes the AI''s own switches', 'release');
select fx.fails($$insert into pipeline.ai_auto_tunable_settings values ('openrouter', 'guard_enrich_fields', 'x')$$, '%not an operational setting%', 'the allow-list never takes a spending guard', 'release');
select fx.fails($$insert into pipeline.ai_auto_tunable_settings values ('pipeline', 'batch.coverage_read', 'x')$$, '%cannot change its approval boundaries%', 'the AI cannot extend its allow-list', 'release+ai');
select fx.fails($$update pipeline.ai_improvement_proposals set authority = 'auto' where code = 'ai-p1-deadline-verbatim'$$, '%kept as submitted%', 'a proposal''s authority cannot be changed');
select fx.fails($$update pipeline.ai_improvement_proposals set production_evidence = '{}' where code = 'ai-p2-not-stated-sections'$$, '%kept as submitted%', 'a proposal''s evidence cannot be rewritten');
select fx.fails($$update pipeline.ai_improvement_proposals set acceptance_criteria = acceptance_criteria || '{"max_fp_rate_rise_pts": 50}' where code = 'fx-e'$$, '%fixed once evaluation starts%', 'criteria are fixed once evaluation starts');
select fx.fails($$insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence, expected_benefit, risks, acceptance_criteria, fingerprint, proposed_by)
                  values ('fx-z', 'deadline', 'admission_rule', 'auto', 't', 'p', 'c', 'x', '{}', 'b', 'r', '{}', 'fz', 'platform_ai')$$, '%change of class admission_rule has authority release, not auto%', 'an admission rule change cannot claim auto authority');
select fx.ok((select security.ai_proposal_submit_v1('{"code": "fx-bound", "family": "deadline", "change_class": "approval_boundary", "proposed_by": "platform_ai", "title": "widen auto", "problem_observed": "slow",
               "current_method": "release", "proposed_change": "make prompts auto", "production_evidence": {"measured_at": "now", "counts": {}}, "expected_benefit": "faster", "risks": "unsafe", "change": "prompt: auto"}')->>'authority') = 'admin',
             'an AI proposal to widen its boundaries is recorded with authority admin (the Platform Admin decides)');
update pipeline.ai_improvement_proposals set status = 'evaluating', status_reason = 'fixture: under evaluation' where code = 'fx-bound';
select fx.fails($$select security.ai_proposal_advance_v1(fx.pid('fx-bound'), 'accepted', 'self-approve')$$, '%accepted only through the admin path%', 'and it cannot accept it');
set role service_role;
select fx.fails($$update pipeline.ai_approval_boundaries set authority = 'auto'$$, '%permission denied%', 'the worker role has no write on the boundaries');
select fx.fails($$update pipeline.ai_improvement_proposals set status = 'accepted'$$, '%permission denied%', 'the worker role has no write on proposals');
select fx.fails($$select count(*) from pipeline.ai_eval_examples$$, '%permission denied%', 'the worker role reads no tables directly');
select fx.ok((public.svc_ai_instruction_pick_v1('course-text', 'course:z')->>'version') = 'course-text-v1', 'the worker role picks a version through its function');
reset role;
select fx.ok((select authority from pipeline.ai_approval_boundaries where change_class = 'prompt') = 'release' and (select count(*) from pipeline.ai_auto_tunable_settings) = 4, 'boundaries and allow-list unchanged after every attempt');
select fx.ok((select count(*) from pipeline.ai_proposal_events e join pipeline.ai_improvement_proposals p on p.id = e.proposal_id where e.to_status = 'accepted' and p.authority <> 'auto' and e.by_path = 'ai') = 0,
             'no non-operational change was ever accepted on the AI path');
select fx.ok(true, 'counts after the fixture: ' || security.ai_eval_counts_v1()::text);
