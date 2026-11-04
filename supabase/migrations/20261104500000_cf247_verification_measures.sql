-- CF-247 verification measures (Platform Admin direction 4 Nov 2026 10:00 AEDT, admin docs/platform/2026-11-04-autonomous-admission-throughput-direction-1000.md
-- §6, §7, §10, §11). Builds on first-run verification (20261104460000, v2.15.464).
--
-- Why (live, read-only, 4 Nov 2026 11:08-11:16 AEDT):
--   M1 §6: three released jobs sit at awaiting_first_run with "no output measure is named for this job": layer4-interventions (v2.15.463, run
--      1211874), layer4-readiness (v2.15.465, run 1213752) and first-run-verify itself (v2.15.464, run 1213213; its 09:32 check saw its own run still
--      running and settled at 10:02). A successful run alone must not verify them.
--   M2 §6: scholarship-coverage-classify returns duplicate_cases, report_errors and report_error_last; pg_cron keeps "1 row", so a repeat or a report
--      failure is invisible after the run.
--   M3 §10: security.integration_issue_upsert_v1 only raises a severity, so a governed downgrade (decision items 22: 25 policy-refused P1 coverage
--      issues) is undone by the next observation, and there is no governed way to change one.
--   M4 §7: states with no recovery condition: 104 failed field reads with no work item; 202 scholarship reads failed "no scraper credit after 3 tries"
--      (terminal, IQ-00129); 49 AER technical items parked with a blocker but no next time (IQ-00232). Nothing reports them as a class.
--   M5 §11: the progress reading has no per-pipeline table with the §11 columns, and its scholarship "eligible" (755) is providers that ever had a
--      candidate page, not the 2,560-provider coverage scope.
-- What:
--   1 pipeline.job_output_contracts: the output a job's run must produce when it is not a chain transition (layer4-interventions: created, reused,
--     resolved, returned to recovery, awaiting human input; layer4-readiness: checked, newly classified, technical-blocked, judgement-ready,
--     superseded; first-run-verify: transitions read, releases judged). security.progress_measure_v1 measures them (md5-guarded edit); the release
--     register names the contract (md5-guarded edit); the zero reason reads the contract's switches (md5-guarded edit). The three awaiting rows are
--     given their contract (records). Their zero is verified only when justified, as for every transition.
--   2 pipeline.scholarship_coverage_classify_runs: one row per classifier run (providers, cases, work reports, recoveries, duplicate_cases,
--     report_errors, report_error_last, the whole answer), written by the function itself in an isolated block (md5-guarded edit; a ledger failure
--     never fails the run). The job command is unchanged.
--   3 security.integration_issue_severity_v1: a governed severity change (either way) with the original and new severity, an evidence-based reason,
--     the decision authority, a history event and timestamp; fingerprint, status and history kept; never closes or recreates. The decision is kept on
--     the issue (severity_decided_at, severity_decided_by, severity_decision), and security.integration_issue_upsert_v1 (md5-guarded edit) no longer
--     raises a governed severity on a repeat observation; a person or this function can change it again.
--   4 security.recovery_condition_gaps_v1 (read only): every unresolved state without a recovery condition or an explicit authority blocker (work
--     items, open issues, release verifications; with p_deep the failed field reads and scholarship reads without a work item).
--   5 security.pipeline_progress_table_v1 (read only): the §11 table (eligible, processed, technically recovered, review-ready, human-decided,
--     admitted, published, blocked) for scholarships and AER, each cell with its basis; the scholarship scope (classifier coverage of the 2,560
--     in-scope providers, and what the narrower 755 was). Sections of security.self_sustainability_v1 (md5-guarded edit), so ops_report_v1 carries
--     them unchanged (518b5bf8).
-- Activation: everything here reads or records. No switch is added on or turned on; nothing admits, publishes, decides, spends or deletes.
-- md5 (before = live 4 Nov 2026 11:10 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/verification-measures/run.sh):
--   security.integration_issue_upsert_v1(jsonb,text)                                b0a1a64982680ae5d588c2d73b779e4e -> f9d7bf1a6dbe94ba97c34f10817f56c1
--   security.scholarship_coverage_classify_v1(uuid[])                               c072494c5e0082e2a8b58a06dfd94a00 -> 7cd322359de3c7f823df240452afc2a8
--   security.progress_measure_v1(text,timestamp with time zone)                     36447d3fd694efceaab38339fcd5ff12 -> 40c0c972abc353be8f6eee35c79750e9
--   security.progress_zero_reason_v1(text,jsonb)                                    9554405ed2ef504b3dfceb29acec165d -> 746d7baedb0a79dc0a6fbfead82f67c2
--   security.release_first_run_register_v1(text,jsonb,jsonb,timestamp with time zone,text) 22788bb62eb9fcccad30c414da3923c0 -> 1f0b3cf6d1d1eea550e83ff5b4e5e5fe
--   security.self_sustainability_v1(integer)                                        77c269232cdea05bafe2e46b51d5ac8f -> a91e9c8151cca09763cf755ab1da1f56
-- Called or read, not edited (live md5): security.ops_report_v1(integer) 518b5bf873549931a15d4173fef793d5 (its section calls self_sustainability_v1),
--   security.layer4_readiness_tick_v1() 06e5f4394b0c2831404fc7a766d669c4 and security.layer4_interventions_tick_v1() da2aaf0fd207edf4c36a55a8e2172424
--   (owned elsewhere: only their tables are read), security.integration_issue_transition_v1 3e8fc63663e5120c50f0859da97dd7a8.
-- Replaces: security.integration_issue_upsert_v1, security.scholarship_coverage_classify_v1, security.progress_measure_v1, security.progress_zero_reason_v1,
--   security.release_first_run_register_v1, security.self_sustainability_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. Consumer API untouched (G3): scholarship.scholarships and catalogue tables are only read.

do $guard$
begin
  if to_regclass('pipeline.release_job_verifications') is null or to_regclass('pipeline.progress_transitions') is null then
    raise exception 'verification measures need first-run verification (20261104460000) first';
  end if;
  if to_regclass('pipeline.layer4_interventions') is null or to_regclass('pipeline.layer4_item_readiness') is null then
    raise exception 'verification measures need human-assisted recovery (20261104450000) and Layer 4 readiness (20261104120000) first';
  end if;
end $guard$;
create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

do $g$
declare v record;
begin
  for v in select * from (values ('security.integration_issue_transition_v1(bigint,text,text,text,jsonb)', '3e8fc63663e5120c50f0859da97dd7a8'),
                                 ('security.ops_report_v1(integer)', '518b5bf873549931a15d4173fef793d5')) x(sig, m) loop
    if md5(pg_get_functiondef(v.sig::regprocedure)) <> v.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', v.sig, md5(pg_get_functiondef(v.sig::regprocedure));
    end if;
  end loop;
end $g$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'recovery.severity_reason_min_chars', 'Governed severity: shortest reason accepted',
  'A severity change must give an evidence-based reason at least this long, besides its evidence and the authority that decided it.',
  'number', to_jsonb(30), 10, 500, 'characters', 1525, 'Direction 4 Nov 2026 10:00 §10 "evidence-based reason"', 'First-run verification and progress',
  'security.integration_issue_severity_v1'),
 ('pipeline', 'recovery.gap_sample', 'Recovery gaps: examples kept per class',
  'The recovery-condition report lists at most this many examples of each class (the counts are complete).',
  'number', to_jsonb(10), 1, 100, 'examples', 1526, 'Direction 4 Nov 2026 10:00 §7', 'First-run verification and progress', 'security.recovery_condition_gaps_v1')
on conflict (toolset_key, key) do nothing;

-- 2. output contracts for jobs that are not chain transitions (§6) -------------------------------------------------------------------------------
create table if not exists pipeline.job_output_contracts (
  jobname text primary key,
  measure_key text not null unique check (measure_key ~ '^[a-z][a-z0-9_]*$'),
  outputs text[] not null,
  switch_keys text[] not null default '{}',
  justified_zero text not null,
  notes text);
comment on table pipeline.job_output_contracts is 'CF-247 (direction 4 Nov 2026 10:00 §6): the measurable output of a scheduled job that is not a transition of the progress contract: the measure key security.progress_measure_v1 counts it with, the named outputs, the switches whose being off blocks it by authority, and when a zero is justified. First-run verification (pipeline.release_job_verifications) judges the job''s first run on it: a zero verifies only with a justified reason. Changed only by a release. Never read by the consumer API.';
alter table pipeline.job_output_contracts enable row level security;
revoke all on pipeline.job_output_contracts from public, anon, authenticated;
insert into pipeline.job_output_contracts(jobname, measure_key, outputs, switch_keys, justified_zero, notes) values
 ('layer4-interventions', 'l4_interventions', '{created,reused,resolved,returned_to_recovery,awaiting_human_input}', '{har.generate_aer_on,har.generate_sch_on}',
  'no case is waiting for a person and no intervention is open (no_eligible_work), or both generation switches are off (blocked_authority)',
  'Read from pipeline.layer4_interventions and pipeline.layer4_intervention_events; security.layer4_interventions_tick_v1 is not edited.'),
 ('layer4-readiness', 'l4_readiness', '{checked,newly_classified,technical_blocked,judgement_ready,superseded}', '{layer4.readiness_on}',
  'no Layer 4 item is pending (no_eligible_work), or layer4.readiness_on is 0 (blocked_authority)',
  'Read from pipeline.layer4_readiness_runs, pipeline.layer4_item_readiness and pipeline.layer4_supersessions; security.layer4_readiness_tick_v1 is not edited.'),
 ('first-run-verify', 'first_run_verify', '{transitions_read,releases_judged}', '{progress.on,frv.on}',
  'never zero while progress.on is 1: every run reads every transition',
  'Read from pipeline.progress_observations and pipeline.release_job_verifications.')
on conflict (jobname) do nothing;

-- the three released jobs awaiting a measure get their contract (records only; judged on the next check)
update pipeline.release_job_verifications v set transition_key = c.measure_key,
       evidence = v.evidence || jsonb_build_object('output_contract', c.measure_key, 'contract_set_by', '20261104500000')
  from pipeline.job_output_contracts c
 where c.jobname = v.jobname and v.transition_key is null and v.status = 'awaiting_first_run';

-- 3. classifier run results (§6) -----------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.scholarship_coverage_classify_runs (
  id bigserial primary key,
  at timestamptz not null default now(),
  manual boolean not null,
  providers int,
  cases int,
  work_reports int,
  recoveries_succeeded int,
  recoveries_failed int,
  duplicate_cases int,
  report_errors int,
  report_error_last text,
  result jsonb not null);
comment on table pipeline.scholarship_coverage_classify_runs is 'CF-247 (direction 4 Nov 2026 10:00 §6): one row per run of security.scholarship_coverage_classify_v1 (scheduled, or manual when providers are given): providers and cases classified, work reports, recoveries verified, duplicate_cases (repeated listing addresses folded into one case) and report_errors with the last one, and the whole answer, which pg_cron discards. Written by the function in an isolated block. Never read by the consumer API.';
create index if not exists scholarship_coverage_classify_runs_at_idx on pipeline.scholarship_coverage_classify_runs (at desc);
alter table pipeline.scholarship_coverage_classify_runs enable row level security;
revoke all on pipeline.scholarship_coverage_classify_runs from public, anon, authenticated;
revoke all on sequence pipeline.scholarship_coverage_classify_runs_id_seq from public, anon, authenticated;

select pg_temp.edit_once('security.scholarship_coverage_classify_v1(uuid[])', 'c072494c5e0082e2a8b58a06dfd94a00', '7cd322359de3c7f823df240452afc2a8',
  array[array[$o$  return jsonb_build_object('ran', true, 'providers', v_n, 'cases', v_items,$o$,
              $n$  -- direction 4 Nov 2026 10:00 §6: the run's answer is kept (pg_cron discards it); a ledger write never fails the run
  begin
    insert into pipeline.scholarship_coverage_classify_runs(manual, providers, cases, work_reports, recoveries_succeeded, recoveries_failed, duplicate_cases, report_errors,
           report_error_last, result)
    values (p_providers is not null, v_n, v_items, v_reports, v_ok, v_fail, v_dup, v_rerr, v_rlast,
            jsonb_build_object('ran', true, 'providers', v_n, 'cases', v_items, 'work_reports', v_reports, 'recoveries_succeeded', v_ok, 'recoveries_failed', v_fail,
                               'duplicate_cases', v_dup, 'report_errors', v_rerr, 'report_error_last', v_rlast));
  exception when others then null;
  end;
  return jsonb_build_object('ran', true, 'providers', v_n, 'cases', v_items,$n$]], array[1]);

-- 4. governed issue severity (§10) ------------------------------------------------------------------------------------------------------------------
alter table pipeline.integration_issues add column if not exists severity_decided_at timestamptz;
alter table pipeline.integration_issues add column if not exists severity_decided_by text;
alter table pipeline.integration_issues add column if not exists severity_decision jsonb;
comment on column pipeline.integration_issues.severity_decided_at is 'CF-247 (direction 4 Nov 2026 10:00 §10): when the severity was last set by a governed decision (security.integration_issue_severity_v1); while set, a repeat observation does not raise it again (security.integration_issue_upsert_v1). severity_decided_by is the decision authority; severity_decision holds the original and new severity, the reason and the evidence. The history is in pipeline.integration_issue_events.';

create or replace function security.integration_issue_severity_v1(p_issue bigint, p_severity text, p_reason text, p_authority text, p_evidence jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 10:00 §10): change an open issue's severity (lower or higher) as a governed decision: the new severity, an evidence-based
-- reason (recovery.severity_reason_min_chars), the decision authority (who decided, and under which decision) and the evidence (a non-empty object).
-- The fingerprint, status and history are kept; one history event records from, to, reason, authority, evidence and time; the decision is kept on the
-- issue, so a repeat observation does not undo it. Never closes, reopens or recreates an issue. The Integration Controller path only.
declare r pipeline.integration_issues; v_min int := security.pipeline_num_v1('recovery.severity_reason_min_chars', 30)::int; v_dec jsonb;
begin
  if p_severity not in ('P0', 'P1', 'P2') then raise exception 'severity must be P0, P1 or P2' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_reason, ''))) < v_min then raise exception 'give an evidence-based reason of at least % characters', v_min using errcode = '22023'; end if;
  if length(btrim(coalesce(p_authority, ''))) < 5 then raise exception 'name the decision authority (who decided, and the decision)' using errcode = '22023'; end if;
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'object' or p_evidence = '{}'::jsonb then raise exception 'give the evidence (an object)' using errcode = '22023'; end if;
  select * into r from pipeline.integration_issues where id = p_issue for update;
  if not found then raise exception 'no integration issue %', p_issue using errcode = 'P0002'; end if;
  if r.status = 'closed' then raise exception '% is closed: a closed issue keeps its severity (reopen it through its own evidence first)', r.issue_ref using errcode = '22023'; end if;
  if r.severity = p_severity then return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'severity', r.severity, 'changed', false); end if;
  v_dec := jsonb_build_object('from', r.severity, 'to', p_severity, 'reason', btrim(p_reason), 'authority', btrim(p_authority), 'evidence', p_evidence, 'at', now(),
                              'direction', case when p_severity < r.severity then 'raised' else 'lowered' end);
  update pipeline.integration_issues set severity = p_severity, severity_decided_at = now(), severity_decided_by = btrim(p_authority), severity_decision = v_dec,
         evidence = evidence || jsonb_build_object('severity_decisions', coalesce(evidence->'severity_decisions', '[]'::jsonb) || jsonb_build_array(v_dec)), updated_at = now()
   where id = r.id;
  insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
  values (r.id, case when p_severity < r.severity then 'escalated' else 'updated' end, r.status, r.status, btrim(p_authority),
          'Severity ' || r.severity || ' -> ' || p_severity || ' (governed decision): ' || left(btrim(p_reason), 400), jsonb_build_object('severity_decision', v_dec));
  return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'from', r.severity, 'severity', p_severity, 'changed', true, 'status', r.status);
end $function$;
revoke all on function security.integration_issue_severity_v1(bigint, text, text, text, jsonb) from public, anon, authenticated;
comment on function security.integration_issue_severity_v1(bigint, text, text, text, jsonb) is 'CF-247 direction 4 Nov 2026 10:00 §10: governed severity change with reason, authority, evidence and a history event; never closes or recreates';

select pg_temp.edit_once('security.integration_issue_upsert_v1(jsonb,text)', 'b0a1a64982680ae5d588c2d73b779e4e', 'f9d7bf1a6dbe94ba97c34f10817f56c1',
  array[array[$o$severity = case when v_sev < i.severity then v_sev else i.severity end,$o$,
              $n$severity = case when v_sev < i.severity and i.severity_decided_at is null then v_sev else i.severity end,$n$],
        array[$o$v_action := case when v_sev < r.severity then 'escalated'$o$,
              $n$v_action := case when v_sev < r.severity and r.severity_decided_at is null then 'escalated'$n$]], array[2, 1]);

-- 5. the output measures (§6) and the scholarship scope (§11), in the one measure function --------------------------------------------------------
select pg_temp.edit_once('security.progress_measure_v1(text,timestamp with time zone)', '36447d3fd694efceaab38339fcd5ff12', '40c0c972abc353be8f6eee35c79750e9',
  array[array[$o$      'eligible', (select count(distinct c.provider_id) from pipeline.scholarship_page_candidates c),$o$,
              $n$      'eligible', (select count(*) from pipeline.coverage_provider_reconciliation l where l.domain = 'scholarship' and l.disposition not in ('not_applicable', 'out_of_scope')),
      'providers_with_candidates', (select count(distinct c.provider_id) from pipeline.scholarship_page_candidates c),
      'providers_classified', (select count(*) from pipeline.scholarship_coverage_providers),$n$],
        array[$o$'basis', 'eligible: providers with any scholarship candidate; created:$o$,
              $n$'basis', 'eligible: in-scope providers of the scholarship coverage ledger (coverage_provider_reconciliation, not applicable and out of scope excluded); providers_with_candidates: providers with any candidate page ever found (the 755 read on 4 Nov, a subset, not an eligibility count); created:$n$],
        array[$o$  else
    raise exception 'no progress measure for transition %', p_key using errcode = '22023';$o$,
              $n$  -- job output contracts (pipeline.job_output_contracts; direction 4 Nov 2026 10:00 §6): created is the run's measurable output
  when 'l4_interventions' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_interventions i where i.status in ('ai_pending', 'awaiting_input', 'resuming') or i.created_at >= p_since),
      'interventions_created', (select count(*) from pipeline.layer4_interventions i where i.created_at >= p_since),
      'reused', (select count(*) from pipeline.layer4_interventions i where i.created_at < p_since and i.last_seen_at >= p_since),
      'resolved', (select count(*) from pipeline.layer4_interventions i where i.status in ('resolved', 'auto_resolved', 'not_published') and coalesce(i.verified_at, i.updated_at) >= p_since),
      'returned_to_recovery', (select count(*) from pipeline.layer4_interventions i where i.status = 'returned_technical' and i.updated_at >= p_since),
      'awaiting_human_input', (select count(*) from pipeline.layer4_interventions i where i.status = 'awaiting_input'),
      'processed', (select count(*) from pipeline.layer4_interventions i where i.updated_at >= p_since or i.last_seen_at >= p_since),
      'created', (select count(*) from pipeline.layer4_interventions i where i.created_at >= p_since or i.last_seen_at >= p_since
                    or (i.status in ('resolved', 'auto_resolved', 'not_published', 'returned_technical') and coalesce(i.verified_at, i.updated_at) >= p_since)),
      'downstream', (select count(*) from pipeline.layer4_interventions i where i.status = 'resuming'),
      'human_decided', (select count(*) from pipeline.layer4_intervention_events e where e.at >= p_since and e.actor is not null),
      'last_output_at', (select max(greatest(i.created_at, i.last_seen_at)) from pipeline.layer4_interventions i),
      'basis', 'created: interventions created, reused (repeat or changed evidence), resolved or returned to recovery since the run; awaiting_human_input: open now') into v;
  when 'l4_readiness' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending'),
      'processed', (select count(*) from pipeline.layer4_readiness_runs r where r.at >= p_since),
      'checked', (select coalesce(sum((r.result->>'classified')::numeric), 0) from pipeline.layer4_readiness_runs r where r.at >= p_since),
      'created', (select coalesce(sum((r.result->>'classified')::numeric), 0) from pipeline.layer4_readiness_runs r where r.at >= p_since),
      'newly_classified', (select count(*) from pipeline.layer4_item_readiness x where x.classified_at >= p_since and x.item_created_at >= p_since),
      'technical_blocked', (select count(*) from pipeline.layer4_item_readiness x where x.classified_at >= p_since and x.readiness = 'technical_blocked'),
      'judgement_ready', (select count(*) from pipeline.layer4_item_readiness x where x.classified_at >= p_since and x.readiness = 'judgement_ready'),
      'superseded', (select count(*) from pipeline.layer4_supersessions s where s.at >= p_since and s.reversed_at is null),
      'downstream', (select count(*) from pipeline.layer4_item_readiness x where x.readiness = 'judgement_ready'),
      'last_output_at', (select max(r.at) from pipeline.layer4_readiness_runs r where coalesce((r.result->>'classified')::numeric, 0) > 0),
      'basis', 'checked: items classified by the runs since (layer4_readiness_runs); newly classified: items that arrived since; technical-blocked and judgement-ready: classified since; superseded: settled without a person') into v;
  when 'first_run_verify' then
    select jsonb_build_object(
      'eligible', (select count(*) from pipeline.progress_transitions),
      'processed', (select count(*) from pipeline.progress_observations o where o.measured_at >= p_since),
      'created', (select count(*) from pipeline.progress_observations o where o.measured_at >= p_since),
      'transitions_read', (select count(*) from pipeline.progress_observations o where o.measured_at >= p_since),
      'releases_judged', (select count(*) from pipeline.release_job_verifications r where r.checked_at >= p_since),
      'last_output_at', (select max(o.measured_at) from pipeline.progress_observations o),
      'basis', 'transitions read (progress_observations) and release jobs judged since the run') into v;
  else
    raise exception 'no progress measure for transition %', p_key using errcode = '22023';$n$]], array[1, 1, 1]);

-- the zero reason reads a job contract's switches and job when the key is not a chain transition
select pg_temp.edit_once('security.progress_zero_reason_v1(text,jsonb)', '9554405ed2ef504b3dfceb29acec165d', '746d7baedb0a79dc0a6fbfead82f67c2',
  array[array[$o$  select * into t from pipeline.progress_transitions where key = p_key;$o$,
              $n$  select * into t from pipeline.progress_transitions where key = p_key;
  if t.key is null then  -- a job output contract (pipeline.job_output_contracts)
    select c.measure_key, array[c.jobname], c.switch_keys into t.key, t.producer_jobs, t.switch_keys from pipeline.job_output_contracts c where c.measure_key = p_key;
  end if;$n$]], array[1]);

-- a release names a job's contract when it registers it
select pg_temp.edit_once('security.release_first_run_register_v1(text,jsonb,jsonb,timestamp with time zone,text)', '22788bb62eb9fcccad30c414da3923c0', '1f0b3cf6d1d1eea550e83ff5b4e5e5fe',
  array[array[$o$    v_tr := coalesce(v_spec->>'transition', (select t.key$o$,
              $n$    v_tr := coalesce(v_spec->>'transition', (select c.measure_key from pipeline.job_output_contracts c where c.jobname = j.name), (select t.key$n$]], array[1]);

-- 6. no state means "failed indefinitely" (§7), read only -------------------------------------------------------------------------------------------
create or replace function security.recovery_condition_gaps_v1(p_deep boolean default false) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 10:00 §7 "no persistent state may mean simply failed indefinitely without a recovery condition or explicit authority
-- blocker"): every unresolved state with neither. Classes: work items with no next time, no blocker, no escalation and no review (lane markers
-- excluded); work items with a blocker but no next time and no escalation; open canonical issues with no next action, no checkpoint and no blocker;
-- release verifications failed or past their deadline with no issue. With p_deep (a full read of two large tables; for the :x6-:x8 slots): failed
-- field reads with no work item, and scholarship reads failed for a reason other than a directory site with no work item. Counts are complete;
-- examples are limited to recovery.gap_sample. Reads only.
declare v_n int := security.pipeline_num_v1('recovery.gap_sample', 10)::int; v_dead int := security.pipeline_num_v1('frv.verify_deadline_hours', 24)::int; v jsonb;
begin
  v := jsonb_build_object(
    'work_items_no_condition', jsonb_build_object(
      'count', (select count(*) from pipeline.work_items w where w.stage not in ('done') and w.entity <> '*lane' and w.next_eligible_at is null
                  and w.unresolved_blocker is null and w.escalation is null and w.review_ref is null),
      'examples', (select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'lane', z.lane, 'stage', z.stage, 'entity', z.entity)), '[]'::jsonb) from (select w.id, w.lane, w.stage, w.entity
                     from pipeline.work_items w where w.stage not in ('done') and w.entity <> '*lane' and w.next_eligible_at is null and w.unresolved_blocker is null
                      and w.escalation is null and w.review_ref is null order by w.id limit v_n) z)),
    'work_items_blocked_no_next_no_escalation', jsonb_build_object(
      'count', (select count(*) from pipeline.work_items w where w.stage not in ('done') and w.entity <> '*lane' and w.next_eligible_at is null
                  and w.unresolved_blocker is not null and w.escalation is null and w.review_ref is null),
      'by_lane', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select w.lane || '/' || coalesce(w.failure_class, '?') k, count(*) n from pipeline.work_items w
                    where w.stage not in ('done') and w.entity <> '*lane' and w.next_eligible_at is null and w.unresolved_blocker is not null and w.escalation is null
                      and w.review_ref is null group by 1) z)),
    'work_items_parked_escalated_no_next', jsonb_build_object(
      'count', (select count(*) from pipeline.work_items w where w.stage in ('parked', 'quarantined') and w.entity <> '*lane' and w.next_eligible_at is null and w.escalation is not null),
      'by_authority', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select w.lane || '/' || coalesce(w.escalation->>'as', '?') || '/IQ-' || lpad(coalesce(w.escalation->>'issue_id', '0'), 5, '0') k,
                         count(*) n from pipeline.work_items w where w.stage in ('parked', 'quarantined') and w.entity <> '*lane' and w.next_eligible_at is null
                          and w.escalation is not null group by 1) z),
      'note', 'held by an explicit blocker escalated to an issue: a recovery condition exists (the issue), but no next automatic time'),
    'issues_no_next_action', jsonb_build_object(
      'count', (select count(*) from pipeline.integration_issues i where i.status <> 'closed' and i.superseded_by is null and i.next_action_at is null
                  and i.remediation_checkpoint_at is null and i.blocker is null),
      'examples', (select coalesce(jsonb_agg(z.issue_ref), '[]'::jsonb) from (select i.issue_ref from pipeline.integration_issues i where i.status <> 'closed' and i.superseded_by is null
                     and i.next_action_at is null and i.remediation_checkpoint_at is null and i.blocker is null order by i.id limit v_n) z)),
    'release_jobs_unowned', jsonb_build_object(
      'count', (select count(*) from pipeline.release_job_verifications r where r.issue_id is null
                  and (r.status = 'failed_first_run' or (r.status = 'awaiting_first_run' and r.deployed_at < now() - make_interval(hours => v_dead))))),
    'deep', p_deep);
  if p_deep then
    v := v || jsonb_build_object(
      'field_reads_failed_no_work_item', jsonb_build_object(
        'count', (select count(*) from pipeline.field_enrich_items f where f.state = 'failed'
                    and not exists (select 1 from pipeline.work_items w where w.lane = 'ai_extraction' and w.entity = f.course_id::text || ':' || f.field)),
        'by_reason', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select coalesce(left(f.reason, 50), 'not stated') r, count(*) n from pipeline.field_enrich_items f
                        where f.state = 'failed' and not exists (select 1 from pipeline.work_items w where w.lane = 'ai_extraction' and w.entity = f.course_id::text || ':' || f.field)
                        group by 1 order by 2 desc limit v_n) z)),
      'scholarship_reads_failed', jsonb_build_object(
        'by_reason', (select coalesce(jsonb_object_agg(z.r, z.n), '{}'::jsonb) from (select coalesce(q.skip_reason, 'not stated') r, count(*) n from pipeline.scholarship_ai_queue q
                        where q.state = 'failed' group by 1 order by 2 desc limit v_n) z),
        'note', 'directory site is a correct exclusion (IQ-00132); any other reason is terminal with no work item'));
  end if;
  return v;
end $function$;
revoke all on function security.recovery_condition_gaps_v1(boolean) from public, anon, authenticated;
comment on function security.recovery_condition_gaps_v1(boolean) is 'CF-247 direction 4 Nov 2026 10:00 §7: unresolved states with no recovery condition or authority blocker (read only)';

-- 7. the §11 table, read only -------------------------------------------------------------------------------------------------------------------------
create or replace function security.pipeline_progress_table_v1(p_window_hours int default 24) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 10:00 §11): verified progress by pipeline: eligible, processed, technically recovered, review-ready, human-decided,
-- admitted, published, blocked; each cell {value, basis}. Movement is counted over p_window_hours; eligible, review-ready and blocked are as now. Also
-- the scholarship scope: classifier coverage of the in-scope providers and what the narrower provider count was. Reads only.
declare s timestamptz := now() - make_interval(hours => p_window_hours); v_aer text[] := array['course_entry_first_read', 'entry_matrix_first_run'];
        v_rec_off boolean := security.pipeline_num_v1('sch_cov.recover_register_pages_on', 0) < 1 and security.pipeline_num_v1('sch_cov.recover_stored_reads_on', 0) < 1
                             and security.pipeline_num_v1('sch_cov.recover_listings_on', 0) < 1;
        v_scope int; v_classified int; v_cand int;
begin
  select count(*) into v_scope from pipeline.coverage_provider_reconciliation l where l.domain = 'scholarship' and l.disposition not in ('not_applicable', 'out_of_scope');
  select count(*) into v_classified from pipeline.scholarship_coverage_providers p
   where exists (select 1 from pipeline.coverage_provider_reconciliation l where l.provider_id = p.provider_id and l.domain = 'scholarship' and l.disposition not in ('not_applicable', 'out_of_scope'));
  select count(distinct c.provider_id) into v_cand from pipeline.scholarship_page_candidates c;
  return jsonb_build_object('window_hours', p_window_hours, 'since', s, 'pipelines', jsonb_build_array(
    jsonb_build_object('pipeline', 'scholarships',
      'eligible', jsonb_build_object('value', (select count(*) from pipeline.scholarship_coverage_items i join pipeline.scholarship_coverage_state_codes k on k.code = i.state where i.present and not k.resolved),
                                     'basis', 'unresolved coverage cases of the classified providers'),
      'processed', jsonb_build_object('value', (select count(*) from pipeline.scholarship_admission_log a where a.at >= s), 'basis', 'admission decisions taken on read pages'),
      'technically_recovered', jsonb_build_object('value', (select count(*) from pipeline.scholarship_coverage_recoveries r where r.outcome = 'succeeded' and r.outcome_at >= s)
                                                         + (select count(*) from pipeline.layer4_interventions i where i.lane like 'sch%' and i.status in ('resolved', 'auto_resolved') and coalesce(i.verified_at, i.updated_at) >= s),
                                                  'basis', 'coverage recoveries whose case moved, and scholarship interventions resolved'),
      'review_ready', jsonb_build_object('value', (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending')
                                                + (select count(*) from pipeline.layer4_interventions i where i.lane like 'sch%' and i.status = 'awaiting_input'),
                                         'basis', 'AI reviews held for a person, and scholarship interventions awaiting input'),
      'human_decided', jsonb_build_object('value', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= s and r.decided_by is not null)
                                                 + (select count(*) from pipeline.layer4_intervention_events e join pipeline.layer4_interventions i on i.id = e.intervention_id
                                                     where i.lane like 'sch%' and e.at >= s and e.actor is not null),
                                          'basis', 'AI reviews decided by a person, and reviewer actions on scholarship interventions'),
      'admitted', jsonb_build_object('value', (select count(*) from scholarship.scholarships x where x.created_at >= s and x.lifecycle_status = 'active'), 'basis', 'active catalogue scholarships created'),
      'published', jsonb_build_object('value', (select count(*) from scholarship.scholarships x where x.lifecycle_status = 'active' and x.publication_status = 'published' and x.updated_at >= s),
                                      'basis', 'active scholarships published and changed in the window; consumer read-back is a separate check'),
      'blocked', jsonb_build_object('value', (select count(*) from pipeline.scholarship_coverage_items i where i.present and (i.state = 'ownership_conflict'
                                                 or (v_rec_off and i.state in ('rejected_incorrectly', 'source_found_unread', 'traversal_incomplete')))),
                                    'basis', 'ownership conflicts (Platform Admin), and recoverable cases while every sch_cov.recover_* switch is off (authority)')),
    jsonb_build_object('pipeline', 'aer',
      'eligible', jsonb_build_object('value', (select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = any (v_aer)), 'basis', 'AER items waiting in Layer 4 (course first read, matrix first run)'),
      'processed', jsonb_build_object('value', coalesce((select sum(r.course_reads) from pipeline.aer_schedule_runs r where r.ran_at >= s), 0)
                                             + (select count(*) from pipeline.entry_matrix_runs m where m.created_at >= s), 'basis', 'scheduled course reads and matrix runs'),
      'technically_recovered', jsonb_build_object('value', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.recovered_at >= s)
                                                         + (select count(*) from pipeline.layer4_interventions i where i.lane like 'aer%' and i.status in ('resolved', 'auto_resolved') and coalesce(i.verified_at, i.updated_at) >= s),
                                                  'basis', 'AER technical work items recovered, and AER interventions resolved'),
      'review_ready', jsonb_build_object('value', (select count(*) from pipeline.layer4_item_readiness x where x.readiness = 'judgement_ready' and x.field_code = any (v_aer)),
                                         'basis', 'AER Layer 4 items classified judgement-ready'),
      'human_decided', jsonb_build_object('value', (select count(*) from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id
                                                     where d.created_at >= s and d.actor_id is not null and i.field_code = any (v_aer)), 'basis', 'Layer 4 decisions by a person on AER items'),
      'admitted', jsonb_build_object('value', (select count(*) from catalogue.course_entry_requirements c where c.status = 'active' and c.updated_at >= s), 'basis', 'course entry rows made active'),
      'published', jsonb_build_object('value', (select count(*) from catalogue.course_entry_requirements c join catalogue.courses k on k.id = c.course_id join catalogue.providers p on p.id = k.provider_id
                                                 where c.status = 'active' and c.updated_at >= s and p.publication_status = 'published'),
                                      'basis', 'active entry rows of published providers; consumer read-back is a separate check'),
      'blocked', jsonb_build_object('value', (select count(*) from pipeline.layer4_item_readiness x where x.readiness = 'technical_blocked' and x.field_code = any (v_aer))
                                           + (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.stage = 'parked'),
                                    'basis', 'AER items technical-blocked in Layer 4, and AER technical work parked',
                                    'providers_without_source', (select count(distinct g.provider_id) from pipeline.aer_gap_findings g where g.state = 'open' and g.root_cause = 'no_source')))),
    'scholarship_scope', jsonb_build_object('in_scope_providers', v_scope, 'classified', v_classified, 'not_yet_classified', v_scope - v_classified,
      'providers_with_candidates', v_cand,
      'meaning', 'in scope: providers of the scholarship coverage ledger (pipeline.coverage_provider_reconciliation, domain scholarship) except not applicable and out of scope. providers_with_candidates (755 on 4 Nov) counts providers with at least one candidate page ever found, of any status: a subset of the scope, not an eligibility count; it was the progress reading''s eligible measure until 20261104500000.'));
end $function$;
revoke all on function security.pipeline_progress_table_v1(integer) from public, anon, authenticated;
comment on function security.pipeline_progress_table_v1(integer) is 'CF-247 direction 4 Nov 2026 10:00 §11: verified progress by pipeline (read only)';

select pg_temp.edit_once('security.self_sustainability_v1(integer)', '77c269232cdea05bafe2e46b51d5ac8f', 'a91e9c8151cca09763cf755ab1da1f56',
  array[array[$o$    'transitions', v_tr);$o$,
              $n$    'transitions', v_tr);
  -- direction 4 Nov 2026 10:00 §7 and §11: the per-pipeline table and the states with no recovery condition (each isolated)
  begin v_out := v_out || security.pipeline_progress_table_v1(p_window_hours) - 'window_hours' - 'since';
  exception when others then v_out := v_out || jsonb_build_object('pipelines', jsonb_build_object('error', left(sqlerrm, 200))); end;
  begin v_out := v_out || jsonb_build_object('recovery_gaps', security.recovery_condition_gaps_v1(false));
  exception when others then v_out := v_out || jsonb_build_object('recovery_gaps', jsonb_build_object('error', left(sqlerrm, 200))); end;$n$]], array[1]);

-- 8. register (housekeeping) and post-check ----------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.job_output_contracts', 'Platform', 'Platform upkeep', 'Measurable output of scheduled jobs outside the progress chains', 'active', '{}', '20261104500000'),
 ('table', 'pipeline.scholarship_coverage_classify_runs', 'Layer 2', 'Scholarships', 'Each scholarship classifier run''s answer', 'active', '{}', '20261104500000'),
 ('function', 'security.integration_issue_severity_v1', 'Platform', 'Platform upkeep', 'Governed issue severity change', 'active', '{}', '20261104500000'),
 ('function', 'security.recovery_condition_gaps_v1', 'Platform', 'Platform upkeep', 'States with no recovery condition or authority blocker', 'active', '{}', '20261104500000'),
 ('function', 'security.pipeline_progress_table_v1', 'Platform', 'Platform upkeep', 'Verified progress by pipeline (§11)', 'active', '{}', '20261104500000')
on conflict do nothing;

do $$
declare v record;
begin
  for v in select * from (values ('security.integration_issue_upsert_v1(jsonb,text)', 'f9d7bf1a6dbe94ba97c34f10817f56c1'),
                                 ('security.scholarship_coverage_classify_v1(uuid[])', '7cd322359de3c7f823df240452afc2a8'),
                                 ('security.progress_measure_v1(text,timestamp with time zone)', '40c0c972abc353be8f6eee35c79750e9'),
                                 ('security.progress_zero_reason_v1(text,jsonb)', '746d7baedb0a79dc0a6fbfead82f67c2'),
                                 ('security.release_first_run_register_v1(text,jsonb,jsonb,timestamp with time zone,text)', '1f0b3cf6d1d1eea550e83ff5b4e5e5fe'),
                                 ('security.self_sustainability_v1(integer)', 'a91e9c8151cca09763cf755ab1da1f56'),
                                 ('security.ops_report_v1(integer)', '518b5bf873549931a15d4173fef793d5')) x(sig, m) loop
    if md5(pg_get_functiondef(v.sig::regprocedure)) <> v.m then raise exception 'post-check: %', v.sig; end if;
  end loop;
  if (select count(*) from pipeline.job_output_contracts) <> 3 then raise exception 'post-check: three output contracts'; end if;
end $$;
