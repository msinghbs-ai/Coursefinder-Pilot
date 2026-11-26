-- CF-247 s1292 (S1-Build; SS-Programme-Control 27 Nov 2026 10:05 AEDT, "Standing Autonomous Learning and Continuous Improvement";
-- Agent Operating Model v1.29 and Master Plan §6.8, coursefinder-admin #1266).
-- Extends the existing recovery knowledge (20261104600000, pipeline.ops_remedy_knowledge / ops_remedy_outcomes / ops_remedy_blocks, the learning step
-- of first-run-verify, security.ops_learning_record_v1 and security.ops_learning_retry_check_v1). No new table, scheduler, queue, reader or spend.
-- Read live 27 Nov 2026 10:10 AEDT: 15 patterns; 72 active remedies (27 automatic); 82 issues closed in 7 days, all with a remedy code; the
-- controller verified 138 automatic confirm_condition_cleared runs in 7 days and refused the ineffective record_capacity_profile 243 times. None of
-- the engineering lessons of 26 and 27 Nov (scheduler, AER semantics and supply, consumer correction, feedback register, release gate, catalogue
-- tracing) was held as knowledge, and nothing in the Admin UI showed the knowledge.
-- What it changes:
--   1. Eight lessons are held as patterns (seeded_from names the release or incident). Each records its actual favourable and adverse outcomes through
--      security.ops_learning_record_v1, once per evidence signature, so a second run of this file records nothing again. Every new pattern is
--      release, admin or Layer 4 authority with auto_eligible false: the platform consults them (ops_learning_retry_check_v1) and never applies them by
--      itself; only registered automatic remedies run automatically (unchanged).
--   2. public.admin_ops_learning_v1() (Platform Admin only, read only): the existing learning report (security.ops_learning_report_v1), every pattern
--      with recorded, verified and failed outcomes and whether it is automatic, the last seven days of outcomes by who performed them, the active
--      no-yield blocks and the last automatic recoveries the controller verified. Shown under Platform health > Technical details.
-- G1: no job. G2: no new value (the window is the existing learn settings; 7 days and 10 rows are display bounds, marked fixed). G3: 75/48 checked.
-- Locks checked. Nothing dropped or deleted.
-- Replaces: nothing. Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the knowledge writes

create temp table s1292_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before;
create temp table s1292_cron on commit drop as select jobid from cron.job;

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'guard: consumer API baseline is not 75/48 with no drift: %', v; end if;
  if to_regprocedure('security.ops_learning_record_v1(jsonb)') is null or to_regprocedure('security.ops_learning_retry_check_v1(text,text,text)') is null then raise exception 'guard: the recovery knowledge functions are missing'; end if;
  if (select count(*) from pipeline.ops_remedies where code in ('fix_in_release', 'engineering_remediation') and active) <> 2 then raise exception 'guard: the release remedies are not registered'; end if;
end $g$;

insert into pipeline.ops_remedy_knowledge (code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
  no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
values
  ('rollup_tick:longest_run_estimate_starvation', 'platform', 'Rollup target deferred tick after tick: one slow run sets its estimate for 14 days',
   array['rollup:deferred:%'], 'estimate_from_longest_run', 'fix_in_release', '{"signal": "deferred share of a rollup target over 30% while it ran successfully before", "check": "pipeline.rollup_runs deferred vs succeeded; estimate vs tick finish time"}'::jsonb,
   'release', 'claude_engineering', 'the target runs in its due ticks again; protected targets, admin snapshots and Data Delivery keep their minute',
   'do not promote priorities or raise the tick budget or finish time for a starved target: since s1290 the estimate is the 95th percentile plus a margin; investigate the target''s own run time',
   'a target deferred while its runs succeed: read its estimate (rollup.estimate_*) and its starvation order before any change',
   false, 'engineering pattern (release authority): fixed in the scheduler (s1290); priority promotion was a partial, recurring workaround', now(), 'S1-Build (s1292)', 's1287 #1711, s1289 #1712, s1290 #1713 (D10)'),
  ('aer_semantic:instruction_age_duration_as_requirement', 'aer', 'AER row of the wrong kind: an application instruction, an age, a duration or a pathway read as an academic requirement',
   array['aer:semantic:%'], 'semantic_misclassification', 'fix_in_release', '{"signal": "prior_qualification or minimum_grade row whose wording is an instruction, an age, a course length or a possible route"}'::jsonb,
   'release', 'claude_engineering', 'the row is kept with the provider''s words as a general note; no score or requirement is inferred; consumer readback matches',
   'do not re-extract the same stored copy with the same reader and prompt: reclassify through the governed AER correction, then read back the consumers',
   'compare the row''s wording with its kind before admission or projection; D9 excludes duration and pathway wording from course_general',
   false, 'engineering pattern: s1280 and s1284 corrected 2,103 rows; one recurrence on 115246M (27 Nov 08:14) is open with S2-AER', now(), 'S1-Build (s1292)', 's1280, s1284, D9 #1709, course 115246M'),
  ('aer_refusal:refusal_not_no_value', 'aer', 'An account, key or route refusal recorded as "no value" and counted as an extraction attempt',
   array['aer:refusal:%'], 'refusal_counted_as_absence', 'fix_in_release', '{"signal": "AI route switched off, key refused or credit floor reached on an AER read"}'::jsonb,
   'release', 'claude_engineering', 'the item waits and resumes by the existing recovery policy once eligible; no attempt is spent and no absence is recorded',
   'do not retry a refused read with paid calls until the refusal has cleared; never record a refusal as a missing value',
   'classify the failed stage first: refusal, no value on the page, or identity hold',
   false, 'engineering pattern: retry window and refusal policy fixed in s1274, s1277 and s1282', now(), 'S1-Build (s1292)', 'DR-19, s1274, s1277 #1690, s1282 #1698'),
  ('aer_supply:producer_registered_no_eligible_work', 'aer', 'A registered producer and a successful scheduler run, but no eligible work reaches the reader',
   array['aer:supply:%'], 'eligibility_not_supply', 'fix_in_release', '{"signal": "aer_schedule_runs with course_reads 0 for consecutive cycles while coverage gaps remain"}'::jsonb,
   'release', 'claude_engineering', 'the eligible pool and the reason it is empty are known (genuine empty, stale coverage, absent producer, hold, redo limit)',
   'do not clear holds or shorten redo intervals to raise throughput; do not count reclassified coverage as new admissions',
   'before reporting zero reads, read security.aer_schedule_courses_v1(n, true) and the planner hand-off',
   false, 'engineering pattern: on 27 Nov the eligible backlog was 0 and no automatic plan held an academic entry read; redo interval until about 3 Dec', now(), 'S1-Build (s1292)', 's1176c #1707, s1274, morning check 27 Nov'),
  ('consumer_projection:frozen_correction_needs_notice', 'platform', 'A correction that changes what the Website or Zoho reads: approval and developer notice first',
   array['consumer:%'], 'consumer_contract_change', null, '{"signal": "a migration that changes values or rules served by website_v2/v3, zoho_v2 or their shared payloads"}'::jsonb,
   'admin', 'platform_admin', 'released only after the Platform Admin approval line and the confirmed Wix and Zoho notice; independent consumer readback after release',
   'never activate a held consumer correction before the notice is confirmed, whatever the rehearsal shows',
   'D9: country-specific evidence first, no inferred equivalence, contextual wording excluded',
   false, 'protected: Platform Admin decision and developer notice (D9 approved 27 Nov with safeguards; notice outstanding)', now(), 'S1-Build (s1292)', 'D9 #1709, coursefinder-admin #1263'),
  ('feedback_register:positional_sparse_write', 'platform', 'A batched positional sheet write with placeholder rows lands entries in the wrong rows',
   array['delivery:sheet_write:%'], 'positional_write_shift', 'fix_in_release', '{"signal": "a values update whose updated row count is smaller than the rows sent"}'::jsonb,
   'release', 'claude_engineering', 'each record written by its stable tracking ID, one exact row per write, and read back',
   'never send a sparse batch with whole-row placeholders; never claim exact restoration without the original evidence',
   'compare the updated range and row count with the rows intended; read the affected rows back before reporting',
   false, 'procedure pattern for agents: incident 27 Nov 09:30 (rows 98-108 and 70), repaired and read back', now(), 'S1-Build (s1292)', 'Feedback register incident 27 Nov'),
  ('release_gate:required_check_list_split', 'platform', 'Merge gate never completes: a required check name holds the list separator',
   array['release:auto_merge:%'], 'separator_in_check_name', 'fix_in_release', '{"signal": "auto-merge waits with every required check green"}'::jsonb,
   'release', 'claude_engineering', 'the gate counts every named check and merges once all are green',
   'do not rerun blanket CI or raise timeouts: compare the required names with the check-run names',
   'when a gate waits with all checks green, print the missing-check list it computes',
   false, 'engineering pattern: comma split failed on 26 Nov; split on '';'' (#1706, admin #1254)', now(), 'S1-Build (s1292)', 's1285 #1706, coursefinder-admin #1254'),
  ('catalogue:absent_vs_projection_or_specialisation', 'platform', 'A course reported absent is present, searched by another name, or held only as a specialisation',
   array['catalogue:absent:%'], 'search_or_specialisation_mismatch', null, '{"signal": "a feedback report that a named course is not in the Portal"}'::jsonb,
   'layer4_human', 'layer4_human', 'the trace (register, catalogue, identity, eligibility, publication, search projection, Portal) names the real gap or proves presence',
   'do not create a course or a duplicate from the feedback text; do not build a frontend workaround for a data gap',
   'run the Portal search with title, provider and code; read the specialisations and the stored page before any catalogue change',
   false, 'diagnosis pattern: CDU Doctor of Pharmacy present (code search gap), WSU MHS present (specialisation not captured), CDU OT three registrations, Kaplan suburbs', now(), 'S1-Build (s1292)', 'Feedback 3-6 traces 27 Nov')
on conflict (code) do nothing;

-- the actual outcomes, once per evidence signature (a second run records nothing again)
do $o$
declare r record;
begin
  for r in select * from (values
    ('rollup_tick:longest_run_estimate_starvation', 's1287:pilot#1711', 'rollup:ops-cost-guard', true, true, '{"ops_cost_guard_runs": {"before_14h": 2, "after_14h": 6}, "deferrals_before": 283}'),
    ('rollup_tick:longest_run_estimate_starvation', 's1287:data-delivery-starved', 'rollup:data-delivery', false, false, '{"data_delivery": "no run 01:59 to 07:04 AEDT, 341 deferrals: a 103.5 s run moved its estimate past the finish time; priority promotion did not protect it"}'),
    ('rollup_tick:longest_run_estimate_starvation', 's1289:pilot#1712', 'rollup:data-delivery', true, true, '{"data_delivery_runs": "ran 07:07 and 07:09 after priority 9"}'),
    ('rollup_tick:longest_run_estimate_starvation', 's1290:pilot#1713', 'rollup:scheduler', true, true, '{"first_28_min": {"data_delivery": "28/0 (before 12/15)", "course_field_readiness": "7/4 (before 0/24)", "admin_snapshots": "28/0"}, "longest_tick_s": 63}'),
    ('aer_semantic:instruction_age_duration_as_requirement', 's1280:equivalent-route-audience', 'aer:rows', true, true, '{"rows_corrected": 701}'),
    ('aer_semantic:instruction_age_duration_as_requirement', 's1284:age-as-score', 'aer:rows', true, true, '{"rows_corrected": 1402, "courses": 1365}'),
    ('aer_semantic:instruction_age_duration_as_requirement', 'enrich_ai:gpt-4.1-mini:course-entry-v1:115246M:2026-11-26T21:14Z', 'course:115246M', false, false, '{"row": "Applicants should submit certified transcripts ... stored as prior_qualification", "owner": "S2-AER"}'),
    ('aer_refusal:refusal_not_no_value', 's1277-s1282:retry-route-refusal', 'aer:schedule', true, true, '{"result": "refused reads wait and resume; no extraction attempt spent"}'),
    ('aer_supply:producer_registered_no_eligible_work', 'morning-check:2026-11-27', 'aer:schedule', false, false, '{"cycles_23_13_to_09_13": "0 reads except 08:13 (1 course)", "eligible_backlog": 0, "automatic_plans_with_entry_reads": 0}'),
    ('feedback_register:positional_sparse_write', 'feedback-register:2026-11-27T09:30', 'sheet:feedback-register', false, false, '{"rows_shifted": "98-108 and 70", "cause": "whole-row placeholders dropped by the values update"}'),
    ('feedback_register:positional_sparse_write', 'feedback-register:2026-11-27T09:45-repair', 'sheet:feedback-register', true, true, '{"rows_restored_and_read_back": 35, "unrecoverable_note": "FB-6.C02-04, marked reconstructed"}'),
    ('release_gate:required_check_list_split', 's1285:comma-split', 'release:pilot-auto-merge', false, false, '{"blocked": "Pilot #1706 waited 40 min with every required check green"}'),
    ('release_gate:required_check_list_split', 's1285:semicolon-split', 'release:pilot-auto-merge', true, true, '{"merged": "Pilot #1706 069e0666; main Deployed UAT 45835518048 passed"}'),
    ('catalogue:absent_vs_projection_or_specialisation', 'feedback-traces:2026-11-27', 'feedback:FB-6.C05-01,FB-6.C03-01,FB-4A.7-01,FB-5.3-25,FB-5.3-30', true, false, '{"present": ["CDU 111117H", "WSU 064020M", "KBS 34 courses"], "gaps": ["provider-code search", "WSU specialisation not captured"]}')
  ) v(code, sig, entity, ok, adv, obs) loop
    if not exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = r.code and o.evidence_signature = r.sig) then
      perform security.ops_learning_record_v1(jsonb_build_object('code', r.code, 'entity', r.entity, 'evidence_signature', r.sig, 'performed_by', 'claude_engineering',
        'success', r.ok, 'stage_advanced', r.adv, 'observed', r.obs::jsonb, 'expected', 'see pattern expected_outcome', 'evidence', jsonb_build_object('source', 'S1-Build s1292', 'signature', r.sig)));
    end if;
  end loop;
end $o$;

create or replace function public.admin_ops_learning_v1()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
-- CF-247 s1292: what the platform has learned, for Platform health > Technical details > Recovery knowledge (read only).
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;  -- fixed: who reads
  return jsonb_build_object(
    'as_of', now(),
    'report', security.ops_learning_report_v1(),
    'patterns', coalesce((select jsonb_agg(jsonb_build_object('code', k.code, 'lane', k.lane, 'title', k.title, 'authority', k.authority, 'automatic', k.auto_eligible,
        'recorded', k.applied, 'verified', k.verified, 'failed', k.failed, 'no_yield_streak', k.no_yield_streak, 'last_outcome_at', k.last_outcome_at,
        'no_retry', k.no_retry_condition, 'eligibility_reason', k.eligibility_reason, 'seeded_from', k.seeded_from) order by k.auto_eligible desc, k.lane, k.code)
        from pipeline.ops_remedy_knowledge k), '[]'::jsonb),
    'outcomes_7d', coalesce((select jsonb_agg(jsonb_build_object('code', z.code, 'performed_by', z.pb, 'outcomes', z.n, 'successful', z.ok, 'stage_advanced', z.adv) order by z.n desc)
        from (select o.knowledge_code code, o.performed_by pb, count(*) n, count(*) filter (where o.success) ok, count(*) filter (where o.stage_advanced) adv
                from pipeline.ops_remedy_outcomes o where o.recorded_at > now() - interval '7 days' group by 1, 2) z), '[]'::jsonb),  -- fixed: the screen's seven-day window
    'blocks', coalesce((select jsonb_agg(jsonb_build_object('code', b.knowledge_code, 'fingerprint', b.fingerprint, 'reason', b.reason, 'prevented', b.prevented, 'blocked_at', b.blocked_at) order by b.blocked_at desc)
        from pipeline.ops_remedy_blocks b where b.lifted_at is null), '[]'::jsonb),
    'recoveries', coalesce((select jsonb_agg(jsonb_build_object('run', r.id, 'remedy', r.remedy_code, 'result', r.result, 'at', r.started_at, 'issue', i.issue_ref, 'fingerprint', i.fingerprint,
        'regressions', i.regression_count, 'status', i.status, 'verified_by', i.verified_by) order by r.started_at desc)
        from (select * from pipeline.ops_remedy_runs x where x.result = 'verified' order by x.started_at desc limit 10) r  -- fixed: the screen shows the last ten
        left join pipeline.integration_issues i on i.id = r.issue_id), '[]'::jsonb));
end $function$;
revoke all on function public.admin_ops_learning_v1() from public, anon;
grant execute on function public.admin_ops_learning_v1() to authenticated, service_role;

do $c$
declare v jsonb := security.consumer_api_check_v1(); r jsonb;
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.ops_remedy_knowledge where seeded_from is not null and eligibility_changed_by = 'S1-Build (s1292)') <> 8 then raise exception 'post-check: the eight lessons are not held'; end if;
  if exists (select 1 from pipeline.ops_remedy_knowledge where eligibility_changed_by = 'S1-Build (s1292)' and auto_eligible) then raise exception 'post-check: a new lesson became automatic'; end if;
  if (select count(*) from pipeline.ops_remedy_outcomes where evidence ->> 'source' = 'S1-Build s1292') <> 14 then raise exception 'post-check: the fourteen outcomes are not recorded once each'; end if;
  -- an unchanged ineffective attempt is refused, and a protected correction stays held
  r := security.ops_learning_retry_check_v1('aer_semantic:instruction_age_duration_as_requirement', 'course:115246M', 'enrich_ai:gpt-4.1-mini:course-entry-v1:115246M:2026-11-26T21:14Z');
  if (r->>'allowed')::boolean then raise exception 'post-check: the unchanged failed read is not refused: %', r; end if;
  r := security.ops_learning_retry_check_v1('consumer_projection:frozen_correction_needs_notice', 'consumer:D9', 'pilot#1709');
  if (r->>'allowed')::boolean then raise exception 'post-check: the held consumer correction is not held: %', r; end if;
  if exists (select 1 from cron.job j where not exists (select 1 from s1292_cron b where b.jobid = j.jobid)) then raise exception 'post-check: a cron job was created'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1292_guard) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
