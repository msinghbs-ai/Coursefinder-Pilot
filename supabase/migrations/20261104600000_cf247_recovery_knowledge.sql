-- CF-247 recovery knowledge: autonomous recovery learns from outcomes (Platform Admin direction 4 Nov 2026 18:08 AEDT, admin
-- docs/platform/2026-11-04-autonomous-recovery-learning-direction-1808.md §1, §2, §3, §6, §7). Extends the operations controller's remedy catalogue
-- (pipeline.ops_remedies, pipeline.ops_remedy_runs), issue fingerprints and work continuity; no second controller.
--
-- Why (live, read-only, 4 Nov 2026 18:09-18:17 AEDT):
--   K1 The controller keeps no memory across issues: in 24 h it ran 20 auto remedies that verified nothing (record_capacity_profile 11 on
--      job_failed:course-relink, a code defect fixed by a release; fee_integrity_recheck 6 on IQ-00111; layer4_admission_recheck 3 on IQ-00116
--      before layer4_tuition_publication_repair, the remedy that worked, ran once at 06:24 and verified).
--   K2 Of 28 active auto remedies, most treat root causes whose detect rule is documentary (fn/sql keys outside the grammar), so the controller can
--      never diagnose them; the scholarship and source-recovery remedies are unreachable automatically.
--   K3 The AER held step re-reads the same stored copy with the same reader: 90 of 103 corrections refused overnight; 69 refused on an unchanged copy in 24 h.
--   K4 Nothing records which outcomes came from the platform and which from Claude engineering, the Platform Admin or a person in Layer 4.
-- What:
--   1 pipeline.ops_remedy_knowledge: one verified pattern per remedy and root cause (or lane pattern): fingerprints and trigger conditions, the
--     remedy, the authority it needs, who performs it, expected outcome, no-retry condition, reuse conditions, applications, verified and failed
--     outcomes, the consecutive-failure streak, cost, and automatic eligibility. pipeline.ops_remedy_outcomes: every outcome (controller runs
--     harvested by remedy run id; lanes and seeds recorded with their evidence), each with who performed it. pipeline.ops_remedy_blocks: a remedy
--     stopped for one fingerprint after learn.no_yield_max consecutive failures, lifted only when the issue's evidence changes (a release, a
--     deployed fix, a remediation state). pipeline.ops_learning_readings: the §7 baseline at release and hourly readings.
--   2 Recurrence: the controller still diagnoses and selects (unchanged). The learning step (job first-run-verify, md5-guarded edit) harvests
--     verified and failed runs, records effectiveness and cost, blocks an ineffective remedy for that fingerprint by exhausting its attempts on
--     the issue (the controller's own rule then routes it, with the evidence, to a release or a decision), and lifts the block when the evidence
--     changes. security.ops_authorise_v1 (md5-guarded edit) refuses a remedy that has lost automatic eligibility across its patterns
--     (learn.min_success_pct over at least learn.rate_min_outcomes outcomes). Eligibility is restored only by security.ops_learning_eligibility_set_v1
--     (a named authority and reason). Lanes outside the controller (the AER recovery selector) ask security.ops_learning_retry_check_v1 before
--     repeating an attempt on the same evidence signature and record with security.ops_learning_record_v1.
--   3 Seeds from real outcomes only: every live controller run (harvested), and the register's recorded outcomes: the classifier ON CONFLICT fix and
--     the relink isolation (Claude engineering), the IQ-00116 tuition repair (platform), the Course Link rules (Platform Admin authority, executed
--     item by item), the AER corrected re-reads on an unchanged copy and at the row limit (platform, ineffective).
--   4 §1 security.autonomy_audit_v1 and §7 security.ops_learning_report_v1 (read only), as sections of security.self_sustainability_v1 (md5-guarded
--     edit), so ops_report_v1 carries them unchanged.
-- Activation: learn.on 1 (records; harvest, readings), learn.gate_on 1 (it only refuses repeating a remedy that verified nothing: no spend, no data
--   change, no work removed; the issue stays routed with its evidence). Higher-reasoning diagnosis is unchanged (ops.ai_diagnosis_on stays 0).
--   Nothing here changes admission policy, code, spending ceilings, protected data, manual locks or Layer 4 decisions.
-- md5 (before = live 4 Nov 2026 18:10 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/recovery-knowledge/run.sh):
--   security.ops_authorise_v1(text)                  ae58963cd1298edeeacae406dc65b314 -> 9f4a124db50a835f23ccb475f8d935c8
--   security.first_run_verify_tick_v1()              9c078d17de8d699de2d932ad1eca8fb8 -> 9df7a97bd494ff3c5425925e419553a5
--   security.self_sustainability_v1(integer)         a91e9c8151cca09763cf755ab1da1f56 -> 1965a71983c841617d9e06d29fa363ec
-- Called or read, not edited (live md5): security.ops_report_v1(integer) 518b5bf873549931a15d4173fef793d5, security.ops_controller_tick_v1()
--   5dce3c4735eb6cd0594c0fdbb77b6486, security.integration_issue_upsert_v1(jsonb,text) f9d7bf1a6dbe94ba97c34f10817f56c1,
--   security.integration_issue_transition_v1(bigint,text,text,text,jsonb) 3e8fc63663e5120c50f0859da97dd7a8.
-- Replaces: security.ops_authorise_v1, security.first_run_verify_tick_v1, security.self_sustainability_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. Consumer API untouched (G3). No Firecrawl or AI spend.

do $guard$
begin
  if to_regclass('pipeline.ops_remedy_runs') is null or to_regclass('pipeline.release_job_verifications') is null or to_regclass('pipeline.job_output_contracts') is null then
    raise exception 'recovery knowledge needs workstream A (20261104010000), first-run verification (20261104460000) and verification measures (20261104520000) first';
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
                                 ('security.integration_issue_upsert_v1(jsonb,text)', 'f9d7bf1a6dbe94ba97c34f10817f56c1')) x(sig, m) loop
    if md5(pg_get_functiondef(v.sig::regprocedure)) <> v.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', v.sig, md5(pg_get_functiondef(v.sig::regprocedure));
    end if;
  end loop;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'learn.on', 'Recovery knowledge: learn from remedy outcomes',
  '1: every half hour the outcome of each verified or failed remedy run is recorded against its pattern (fingerprint, root cause, remedy), with cost, and the §7 reading is kept hourly. Records only. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1530, 'Direction 4 Nov 2026 18:08 §2-§3: ships on (records only)', 'First-run verification and progress', 'security.ops_learning_tick_v1'),
 ('pipeline', 'learn.gate_on', 'Recovery knowledge: stop repeating a remedy that verifies nothing',
  '1: a remedy that failed learn.no_yield_max times in a row on one fingerprint is not run again on it until its evidence changes, and a remedy below learn.min_success_pct overall loses automatic eligibility; the issue stays routed to a release or a decision with the evidence. It never runs anything. 0: record only.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1531, 'Direction 4 Nov 2026 18:08 §3 "must lose automatic retry eligibility"', 'First-run verification and progress',
  'security.ops_learning_gate_v1; security.ops_authorise_v1'),
 ('pipeline', 'learn.no_yield_max', 'Recovery knowledge: consecutive failed outcomes before a remedy stops on a fingerprint',
  'After this many verified failures in a row of one remedy on one fingerprint, it is not run again there until the evidence changes.',
  'number', to_jsonb(3), 1, 20, 'outcomes', 1532, 'Direction 4 Nov 2026 18:08 §3', 'First-run verification and progress', 'security.ops_learning_harvest_v1'),
 ('pipeline', 'learn.min_success_pct', 'Recovery knowledge: lowest success rate that keeps a remedy automatic',
  'A remedy whose verified share of its last learn.rate_min_outcomes or more outcomes, across all its patterns, is below this loses automatic eligibility.',
  'number', to_jsonb(20), 0, 100, 'percent', 1533, 'Direction 4 Nov 2026 18:08 §3', 'First-run verification and progress', 'security.ops_learning_harvest_v1'),
 ('pipeline', 'learn.rate_min_outcomes', 'Recovery knowledge: outcomes needed before a remedy''s rate is judged',
  'A remedy''s success rate is judged only once it has at least this many verified or failed outcomes.',
  'number', to_jsonb(6), 2, 100, 'outcomes', 1534, 'Direction 4 Nov 2026 18:08 §3', 'First-run verification and progress', 'security.ops_learning_harvest_v1'),
 ('pipeline', 'learn.not_remedy_fingerprints', 'Recovery knowledge: failures that are never remedy candidates',
  'Issues whose fingerprint matches one of these patterns are never learned from or stopped as remedy outcomes: their cause is an authority decision, not a defect the platform can repair (for example alerts held because their delivery destination was paused by the Platform Admin).',
  'list', '["%platform_alerts%", "%platform-alerts%", "%alert%deliver%", "%watchdog%"]'::jsonb, null, null, 'fingerprint patterns', 1536,
  'Integration Controller 4 Nov 2026: alert delivery paused by the Platform Admin is an authority blocker, not a remedy candidate', 'First-run verification and progress',
  'security.ops_learning_harvest_v1; security.ops_learning_gate_v1'),
 ('pipeline', 'learn.reading_minutes', 'Recovery knowledge: keep a §7 reading every',
  'The learning step keeps one reading of the §7 measures at most this often.',
  'number', to_jsonb(60), 15, 1440, 'minutes', 1535, 'Direction 4 Nov 2026 18:08 §7 "track whether Claude interventions decrease"', 'First-run verification and progress', 'security.ops_learning_tick_v1')
on conflict (toolset_key, key) do nothing;

-- 2. tables ---------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.ops_remedy_knowledge (
  code text primary key check (code ~ '^[a-z][a-z0-9_:]*$'),
  lane text not null check (lane in ('aer', 'course_link', 'scholarship', 'fees', 'platform')),
  title text not null,
  fingerprint_like text[] not null default '{}',
  root_cause text,
  remedy_code text references pipeline.ops_remedies(code),
  trigger_conditions jsonb not null default '{}'::jsonb,
  authority text not null check (authority in ('auto', 'release', 'admin', 'layer4_human')),
  performed_by text not null check (performed_by in ('platform', 'claude_engineering', 'platform_admin', 'layer4_human')),
  expected_outcome text not null,
  no_retry_condition text not null,
  reuse_conditions text not null,
  applied int not null default 0,
  verified int not null default 0,
  failed int not null default 0,
  no_yield_streak int not null default 0,
  cost_usd numeric not null default 0,
  credits numeric not null default 0,
  last_outcome_at timestamptz,
  auto_eligible boolean not null default true,
  eligibility_reason text,
  eligibility_changed_at timestamptz,
  eligibility_changed_by text,
  seeded_from text,
  created_at timestamptz not null default now());
comment on table pipeline.ops_remedy_knowledge is 'CF-247 (direction 4 Nov 2026 18:08 §2): the recovery knowledge base, beside the remedy catalogue (pipeline.ops_remedies). One pattern per remedy and root cause (code remedy:root_cause, kept by job first-run-verify from the controller''s runs) or per lane pattern: fingerprints and trigger conditions, the remedy, the authority it needs, who performs it (platform, Claude engineering, Platform Admin, a person in Layer 4), the expected outcome, when it must not be retried, when it may be reused, its applications, verified and failed outcomes, its consecutive-failure streak, cost, and whether it may run automatically. Eligibility is lost by the harvest (settings learn.*) and restored only by security.ops_learning_eligibility_set_v1. Never read by the consumer API.';
alter table pipeline.ops_remedy_knowledge enable row level security;
revoke all on pipeline.ops_remedy_knowledge from public, anon, authenticated;

create table if not exists pipeline.ops_remedy_outcomes (
  id bigserial primary key,
  knowledge_code text not null references pipeline.ops_remedy_knowledge(code),
  issue_id bigint references pipeline.integration_issues(id),
  fingerprint text,
  entity text,
  remedy_run_id bigint unique references pipeline.ops_remedy_runs(id),
  performed_by text not null check (performed_by in ('platform', 'claude_engineering', 'platform_admin', 'layer4_human')),
  applied_at timestamptz not null,
  expected text,
  observed jsonb not null default '{}'::jsonb,
  success boolean not null,
  stage_advanced boolean,
  applications int not null default 1,
  cost_usd numeric not null default 0,
  credits numeric not null default 0,
  evidence_signature text,
  evidence jsonb not null default '{}'::jsonb,
  seeded boolean not null default false,
  recorded_at timestamptz not null default now());
comment on table pipeline.ops_remedy_outcomes is 'CF-247 (direction 4 Nov 2026 18:08 §2-§3): every recorded remedy outcome: the pattern, issue and fingerprint, the entity and evidence signature (for lanes that must not repeat on unchanged evidence), the controller run it came from (unique), who performed it, expected and observed result, success, whether the stage advanced, applications (an aggregate seed counts several), cost and credits, and the evidence. Seeds are real recorded outcomes (seeded true, with their source). Never read by the consumer API.';
create index if not exists ops_remedy_outcomes_code_idx on pipeline.ops_remedy_outcomes (knowledge_code, applied_at desc);
create index if not exists ops_remedy_outcomes_fp_idx on pipeline.ops_remedy_outcomes (knowledge_code, fingerprint, applied_at desc);
create index if not exists ops_remedy_outcomes_sig_idx on pipeline.ops_remedy_outcomes (knowledge_code, entity, evidence_signature) where evidence_signature is not null;
alter table pipeline.ops_remedy_outcomes enable row level security;
revoke all on pipeline.ops_remedy_outcomes from public, anon, authenticated;
revoke all on sequence pipeline.ops_remedy_outcomes_id_seq from public, anon, authenticated;

create table if not exists pipeline.ops_remedy_blocks (
  id bigserial primary key,
  knowledge_code text not null references pipeline.ops_remedy_knowledge(code),
  fingerprint text not null,
  issue_id bigint references pipeline.integration_issues(id),
  blocked_at timestamptz not null default now(),
  reason text not null,
  signature text not null,
  prevented int not null default 0,
  lifted_at timestamptz,
  lift_reason text);
comment on table pipeline.ops_remedy_blocks is 'CF-247 (direction 4 Nov 2026 18:08 §3): a remedy stopped on one fingerprint after learn.no_yield_max consecutive failures: the evidence signature at the block (issue status, remediation state, fix and deployed version), how many repeats it prevented, and when and why it was lifted (the evidence changed). Never read by the consumer API.';
create unique index if not exists ops_remedy_blocks_open_uq on pipeline.ops_remedy_blocks (knowledge_code, fingerprint) where lifted_at is null;
alter table pipeline.ops_remedy_blocks enable row level security;
revoke all on pipeline.ops_remedy_blocks from public, anon, authenticated;
revoke all on sequence pipeline.ops_remedy_blocks_id_seq from public, anon, authenticated;

create table if not exists pipeline.ops_learning_readings (
  id bigserial primary key,
  at timestamptz not null default now(),
  kind text not null check (kind in ('baseline', 'reading')),
  metrics jsonb not null);
comment on table pipeline.ops_learning_readings is 'CF-247 (direction 4 Nov 2026 18:08 §7): the §7 measures: the baseline taken when this release is applied, and a reading at most every learn.reading_minutes, so the trend of Claude interventions against verified recovery patterns can be shown. Never read by the consumer API.';
create index if not exists ops_learning_readings_at_idx on pipeline.ops_learning_readings (at desc);
alter table pipeline.ops_learning_readings enable row level security;
revoke all on pipeline.ops_learning_readings from public, anon, authenticated;
revoke all on sequence pipeline.ops_learning_readings_id_seq from public, anon, authenticated;

-- 3. functions --------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.ops_learning_signature_v1(p_issue bigint) returns text
language sql stable security definer set search_path to '' as $function$
-- what must change before a stopped remedy may be tried again on an issue: its status, remediation state, fix and deployed version
  select md5(concat_ws('|', i.status, i.remediation_status, i.fix_migration, i.fix_commit, i.deployed_version)) from pipeline.integration_issues i where i.id = p_issue
$function$;
revoke all on function security.ops_learning_signature_v1(bigint) from public, anon, authenticated;

create or replace function security.ops_learning_lane_v1(p_fingerprint text, p_remedy text) returns text
language sql immutable set search_path to '' as $function$
  select case when coalesce(p_fingerprint, '') ~ '(aer|entry_matrix|course_entry)' then 'aer'
              when coalesce(p_fingerprint, '') ~ '(official_course_url|course-relink|course_link|relink)' or coalesce(p_remedy, '') like 'rem\_%' then 'course_link'
              when coalesce(p_fingerprint, '') ~ 'scholarship' or coalesce(p_remedy, '') like 'sch\_%' then 'scholarship'
              when coalesce(p_fingerprint, '') ~ '(fee|tuition)' or coalesce(p_remedy, '') ~ '(fee|tuition)' then 'fees'
              else 'platform' end
$function$;
revoke all on function security.ops_learning_lane_v1(text, text) from public, anon, authenticated;

create or replace function security.ops_learning_refusal_v1(p_remedy text) returns text
language sql stable security definer set search_path to '' as $function$
-- Called by security.ops_authorise_v1: a remedy that has lost automatic eligibility in every pattern it has (and has patterns) is refused.
  select 'lost automatic eligibility (recovery knowledge): ' || coalesce(max(k.eligibility_reason), 'no verified result')
    from pipeline.ops_remedy_knowledge k
   where security.pipeline_num_v1('learn.gate_on', 1) >= 1 and k.remedy_code = p_remedy and k.performed_by = 'platform'
  having count(*) > 0 and bool_and(not k.auto_eligible)
$function$;
revoke all on function security.ops_learning_refusal_v1(text) from public, anon, authenticated;

create or replace function security.ops_learning_not_remedy_v1(p_fingerprint text) returns boolean
language sql stable security definer set search_path to '' as $function$
-- an issue whose cause is an authority decision (learn.not_remedy_fingerprints) is never a remedy candidate
  select coalesce(p_fingerprint, '') like any (coalesce((select array_agg(x) from jsonb_array_elements_text(security.toolset_setting('pipeline', 'learn.not_remedy_fingerprints')) x), '{}'))
$function$;
revoke all on function security.ops_learning_not_remedy_v1(text) from public, anon, authenticated;

create or replace function security.ops_learning_harvest_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 18:08 §2-§3): every controller run that verified or failed becomes an outcome of its pattern (remedy:root_cause),
-- once (by run id). Counters, the consecutive-failure streak and the last outcome are kept. learn.no_yield_max failures in a row on one fingerprint
-- open a block for that fingerprint (lifted only when the issue's evidence changes). A remedy whose verified share of its last learn.rate_min_outcomes
-- outcomes is below learn.min_success_pct loses automatic eligibility in all its platform patterns, and that is raised once as an issue. Records only.
declare r record; m pipeline.ops_remedies; i pipeline.integration_issues; v_rc text; v_code text; v_ok boolean; v_streak int; v_n int := 0; v_b int := 0; v_lost int := 0;
        v_max int := security.pipeline_num_v1('learn.no_yield_max', 3)::int; v_min_n int := security.pipeline_num_v1('learn.rate_min_outcomes', 6)::int;
        v_pct numeric := security.pipeline_num_v1('learn.min_success_pct', 20); x record;
begin
  for r in select u.* from pipeline.ops_remedy_runs u where u.result in ('verified', 'verify_failed')
              and not exists (select 1 from pipeline.ops_remedy_outcomes o where o.remedy_run_id = u.id)
            order by u.id limit security.pipeline_num_v1('recovery.issues_per_run', 200)::int loop
    select * into m from pipeline.ops_remedies where code = r.remedy_code;
    select * into i from pipeline.integration_issues where id = r.issue_id;
    continue when security.ops_learning_not_remedy_v1(i.fingerprint);
    v_rc := coalesce(r.evidence->'diagnosis'->>'root_cause', i.diagnosis->>'root_cause', 'unclassified');
    v_code := r.remedy_code || ':' || v_rc; v_ok := r.result = 'verified';
    insert into pipeline.ops_remedy_knowledge(code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
           no_retry_condition, reuse_conditions, seeded_from)
    values (v_code, security.ops_learning_lane_v1(i.fingerprint, r.remedy_code), m.title || ' (for ' || v_rc || ')', array[i.fingerprint], v_rc, r.remedy_code,
            coalesce((select c.detect from pipeline.ops_root_causes c where c.code = v_rc), '{}'::jsonb), m.authority, 'platform',
            coalesce(m.title, r.remedy_code) || ': verified by ' || coalesce(m.verify_fn::text, 'its check') || ' on a later controller run',
            'learn.no_yield_max verified failures in a row on one fingerprint, until that issue''s evidence changes; or a success rate below learn.min_success_pct',
            'the controller diagnoses ' || v_rc || ', the remedy is active and authorised (' || m.authority || '), and no block is open for the fingerprint',
            'ops_remedy_runs (harvested)')
    on conflict (code) do update set fingerprint_like = case when i.fingerprint = any (pipeline.ops_remedy_knowledge.fingerprint_like) then pipeline.ops_remedy_knowledge.fingerprint_like
                                                              else pipeline.ops_remedy_knowledge.fingerprint_like || i.fingerprint end;
    insert into pipeline.ops_remedy_outcomes(knowledge_code, issue_id, fingerprint, remedy_run_id, performed_by, applied_at, expected, observed, success, stage_advanced, evidence)
    values (v_code, r.issue_id, i.fingerprint, r.id, 'platform', coalesce(r.finished_at, r.started_at), m.title,
            coalesce(r.after, '{}'::jsonb), v_ok, case when v_ok then coalesce((r.after->'verify'->>'condition_cleared')::boolean, true) else false end,
            jsonb_build_object('run', r.id, 'verify', r.evidence->'verify', 'issue', i.issue_ref));
    update pipeline.ops_remedy_knowledge k set applied = k.applied + 1, verified = k.verified + case when v_ok then 1 else 0 end, failed = k.failed + case when v_ok then 0 else 1 end,
           no_yield_streak = case when v_ok then 0 else k.no_yield_streak + 1 end, last_outcome_at = greatest(k.last_outcome_at, coalesce(r.finished_at, r.started_at))
     where k.code = v_code;
    if not v_ok and i.fingerprint is not null then
      select count(*) into v_streak from pipeline.ops_remedy_outcomes o
       where o.knowledge_code = v_code and o.fingerprint = i.fingerprint and not o.success
         and o.applied_at > coalesce((select max(s.applied_at) from pipeline.ops_remedy_outcomes s where s.knowledge_code = v_code and s.fingerprint = i.fingerprint and s.success), '-infinity');
      if v_streak >= v_max and not exists (select 1 from pipeline.ops_remedy_blocks b where b.knowledge_code = v_code and b.fingerprint = i.fingerprint and b.lifted_at is null) then
        insert into pipeline.ops_remedy_blocks(knowledge_code, fingerprint, issue_id, reason, signature)
        values (v_code, i.fingerprint, i.id, r.remedy_code || ' verified nothing ' || v_streak || ' times in a row on ' || i.fingerprint, security.ops_learning_signature_v1(i.id));
        v_b := v_b + 1;
      end if;
    end if;
    v_n := v_n + 1;
  end loop;
  -- remedy-level eligibility (platform patterns of the controller's remedies)
  for x in select k.remedy_code, count(*) n, count(*) filter (where o.success) ok
             from (select distinct k1.remedy_code from pipeline.ops_remedy_knowledge k1
                    where k1.performed_by = 'platform' and k1.remedy_code is not null and k1.auto_eligible) k
             join lateral (select o.success from pipeline.ops_remedy_outcomes o join pipeline.ops_remedy_knowledge k2 on k2.code = o.knowledge_code
                            where k2.remedy_code = k.remedy_code and k2.performed_by = 'platform' order by o.applied_at desc limit v_min_n) o on true
            group by k.remedy_code loop
    if x.n >= v_min_n and 100.0 * x.ok / x.n < v_pct then
      update pipeline.ops_remedy_knowledge set auto_eligible = false, eligibility_changed_at = now(), eligibility_changed_by = 'recovery knowledge (job first-run-verify)',
             eligibility_reason = x.ok || ' of its last ' || x.n || ' outcomes verified (below ' || v_pct || '%)'
       where remedy_code = x.remedy_code and performed_by = 'platform' and auto_eligible;
      if found then
        v_lost := v_lost + 1;
        perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'remedy_ineffective:' || x.remedy_code,
          'title', 'Remedy ' || x.remedy_code || ' lost automatic eligibility: ' || x.ok || ' of its last ' || x.n || ' outcomes verified', 'layer', 'Platform', 'subsystem', 'recovery knowledge',
          'failure', 'The remedy repeatedly produced no verified result; it is no longer run automatically.',
          'expected', 'A remedy that works, or a release, or a decision to restore it (security.ops_learning_eligibility_set_v1)',
          'source', 'first-run-verify (recovery knowledge)', 'validation_layer', 'V4', 'severity', 'P2', 'root_cause_class', 'unclassified', 'workstream', 'A7', 'assignee', 'engineering',
          'evidence', jsonb_build_object('remedy', x.remedy_code, 'outcomes', x.n, 'verified', x.ok)), 'first-run-verify');
      end if;
    end if;
  end loop;
  return jsonb_build_object('harvested', v_n, 'blocks_opened', v_b, 'remedies_lost_eligibility', v_lost);
end $function$;
revoke all on function security.ops_learning_harvest_v1() from public, anon, authenticated;

create or replace function security.ops_learning_gate_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 18:08 §3 steps 2 and 6): each open block is lifted when its issue closed or its evidence changed; otherwise, while
-- learn.gate_on is 1 and the controller plans the stopped remedy for the issue, its attempts are set to the remedy's maximum, so the controller's
-- own rule routes the issue (to a release or a decision, with the evidence) instead of running it again. One history line per prevention.
declare b pipeline.ops_remedy_blocks; i pipeline.integration_issues; k pipeline.ops_remedy_knowledge; m pipeline.ops_remedies; v_max int; v_lift int := 0; v_prev int := 0;
begin
  for b in select * from pipeline.ops_remedy_blocks where lifted_at is null order by id loop
    select * into i from pipeline.integration_issues where fingerprint = b.fingerprint;
    if i.id is null or i.status = 'closed' then
      update pipeline.ops_remedy_blocks set lifted_at = now(), lift_reason = 'issue closed or gone' where id = b.id; v_lift := v_lift + 1; continue;
    end if;
    if security.ops_learning_not_remedy_v1(b.fingerprint) then
      update pipeline.ops_remedy_blocks set lifted_at = now(), lift_reason = 'not a remedy candidate: an authority blocker (learn.not_remedy_fingerprints)' where id = b.id; v_lift := v_lift + 1; continue;
    end if;
    if security.ops_learning_signature_v1(i.id) is distinct from b.signature then
      update pipeline.ops_remedy_blocks set lifted_at = now(), lift_reason = 'evidence changed: status ' || i.status || ', remediation ' || coalesce(i.remediation_status, 'none')
             || coalesce(', fix ' || i.fix_migration, '') || coalesce(', deployed ' || i.deployed_version, '') where id = b.id;
      v_lift := v_lift + 1; continue;
    end if;
    continue when security.pipeline_num_v1('learn.gate_on', 1) < 1;
    select * into k from pipeline.ops_remedy_knowledge where code = b.knowledge_code;
    select * into m from pipeline.ops_remedies where code = k.remedy_code;
    continue when m.code is null or coalesce(i.ops_plan->>'proposed', '') <> m.code;
    v_max := security.pipeline_num_v1(coalesce(m.max_attempts_key, 'ops.max_attempts'), 3)::int;
    continue when i.remedy_code = m.code and i.remedy_attempts >= v_max;
    update pipeline.integration_issues set remedy_code = m.code, remedy_attempts = v_max, next_action_at = least(coalesce(next_action_at, now()), now()) where id = i.id;
    update pipeline.ops_remedy_blocks set prevented = prevented + 1 where id = b.id;
    perform security.integration_issue_transition_v1(i.id, null, 'first-run-verify',
      'Recovery knowledge: ' || m.code || ' is not run again on this fingerprint (' || b.reason || '); it is retried only when the issue''s evidence changes (a fix, a release or a remediation step)',
      jsonb_build_object('evidence', jsonb_build_object('recovery_knowledge_block', jsonb_build_object('pattern', b.knowledge_code, 'blocked_at', b.blocked_at, 'reason', b.reason))));
    v_prev := v_prev + 1;
  end loop;
  return jsonb_build_object('lifted', v_lift, 'prevented', v_prev);
end $function$;
revoke all on function security.ops_learning_gate_v1() from public, anon, authenticated;

create or replace function security.ops_learning_retry_check_v1(p_code text, p_entity text, p_signature text) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 18:08 §3, §4): for a lane that repeats an attempt outside the controller (the AER recovery selector, Course Link rules):
-- may this pattern be tried on this entity with this evidence signature (stored copy, reader and settings)? Refused when the pattern lost automatic
-- eligibility, or when the same entity and signature already failed; allowed when the signature changed.
  select case when k.code is null then jsonb_build_object('allowed', true, 'reason', 'no recorded pattern')
              when not k.auto_eligible and k.authority = 'auto' and exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = k.code and o.entity = p_entity
                                                                          and o.evidence_signature = p_signature and not o.success)
                then jsonb_build_object('allowed', false, 'reason', 'the same evidence already failed, and the pattern lost automatic eligibility: ' || coalesce(k.eligibility_reason, ''))
              when exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = k.code and o.entity = p_entity and o.evidence_signature = p_signature and not o.success)
                then jsonb_build_object('allowed', false, 'reason', 'the same evidence already failed for this item: ' || k.no_retry_condition)
              when not k.auto_eligible and k.authority <> 'auto'
                then jsonb_build_object('allowed', false, 'reason', 'needs ' || k.authority || ' authority: ' || coalesce(k.eligibility_reason, k.reuse_conditions))
              else jsonb_build_object('allowed', true, 'reason', 'evidence changed or never tried') end
    from (select 1) d left join pipeline.ops_remedy_knowledge k on k.code = p_code
$function$;
revoke all on function security.ops_learning_retry_check_v1(text, text, text) from public, anon, authenticated;

create or replace function security.ops_learning_record_v1(p jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- A lane records an outcome of a known pattern: code, entity, evidence_signature, performed_by, success, stage_advanced, observed, cost_usd, credits.
declare v_ok boolean := coalesce((p->>'success')::boolean, false); v_id bigint;
begin
  if not exists (select 1 from pipeline.ops_remedy_knowledge where code = p->>'code') then raise exception 'no recovery pattern %', p->>'code' using errcode = '22023'; end if;
  insert into pipeline.ops_remedy_outcomes(knowledge_code, issue_id, fingerprint, entity, performed_by, applied_at, expected, observed, success, stage_advanced, cost_usd, credits, evidence_signature, evidence)
  values (p->>'code', (p->>'issue_id')::bigint, p->>'fingerprint', p->>'entity', coalesce(p->>'performed_by', 'platform'), coalesce((p->>'applied_at')::timestamptz, now()), p->>'expected',
          coalesce(p->'observed', '{}'::jsonb), v_ok, (p->>'stage_advanced')::boolean, coalesce((p->>'cost_usd')::numeric, 0), coalesce((p->>'credits')::numeric, 0), p->>'evidence_signature',
          coalesce(p->'evidence', '{}'::jsonb))
  returning id into v_id;
  update pipeline.ops_remedy_knowledge k set applied = k.applied + 1, verified = k.verified + case when v_ok then 1 else 0 end, failed = k.failed + case when v_ok then 0 else 1 end,
         no_yield_streak = case when v_ok then 0 else k.no_yield_streak + 1 end, last_outcome_at = greatest(k.last_outcome_at, now()),
         cost_usd = k.cost_usd + coalesce((p->>'cost_usd')::numeric, 0), credits = k.credits + coalesce((p->>'credits')::numeric, 0)
   where k.code = p->>'code';
  return jsonb_build_object('outcome', v_id);
end $function$;
revoke all on function security.ops_learning_record_v1(jsonb) from public, anon, authenticated;

create or replace function security.ops_learning_eligibility_set_v1(p_code text, p_eligible boolean, p_reason text, p_authority text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Governed change of a pattern's automatic eligibility (the only way to restore it): an evidence-based reason and the decision authority.
declare v_min int := security.pipeline_num_v1('recovery.severity_reason_min_chars', 30)::int; k pipeline.ops_remedy_knowledge;
begin
  if length(btrim(coalesce(p_reason, ''))) < v_min then raise exception 'give an evidence-based reason of at least % characters', v_min using errcode = '22023'; end if;
  if length(btrim(coalesce(p_authority, ''))) < 5 then raise exception 'name the decision authority' using errcode = '22023'; end if;
  update pipeline.ops_remedy_knowledge set auto_eligible = p_eligible, eligibility_reason = btrim(p_reason), eligibility_changed_at = now(), eligibility_changed_by = btrim(p_authority),
         no_yield_streak = case when p_eligible then 0 else no_yield_streak end
   where code = p_code returning * into k;
  if k.code is null then raise exception 'no recovery pattern %', p_code using errcode = 'P0002'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ops', 'remedy_eligibility', 'pipeline.ops_remedy_knowledge', jsonb_build_object('code', p_code, 'eligible', p_eligible, 'reason', p_reason, 'authority', p_authority), null);
  return jsonb_build_object('code', k.code, 'auto_eligible', k.auto_eligible);
end $function$;
revoke all on function security.ops_learning_eligibility_set_v1(text, boolean, text, text) from public, anon, authenticated;

-- 4. §1 and §7, read only -----------------------------------------------------------------------------------------------------------------------------
create or replace function security.autonomy_audit_v1(p_hours int default 24) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 18:08 §1): outcomes of the last p_hours by who achieved them. A release or a fix built by Claude counts as Claude
-- engineering, never as a platform remedy; the controller's bookkeeping (linking duplicates, confirming a cleared condition, re-closing a stale
-- reopening) is shown apart from remedies that changed data. Reads only.
declare s timestamptz := now() - make_interval(hours => p_hours); v_book text[] := array['supersede_into_owner', 'confirm_condition_cleared', 'reclose_stale_reopen']; v_prog jsonb;
begin
  begin v_prog := security.pipeline_progress_table_v1(p_hours); exception when others then v_prog := jsonb_build_object('error', left(sqlerrm, 200)); end;
  return jsonb_build_object('window_hours', p_hours, 'since', s, 'categories', jsonb_build_array(
    jsonb_build_object('category', 'detected_automatically', 'value', (select count(*) from pipeline.integration_issues i where i.detected_at >= s and i.validation_layer <> 'manual'),
      'detail', jsonb_build_object('raised_by_hand', (select count(*) from pipeline.integration_issues i where i.detected_at >= s and i.validation_layer = 'manual'))),
    jsonb_build_object('category', 'diagnosed_automatically', 'value', (select count(*) from pipeline.integration_issues i where (i.diagnosis->>'at')::timestamptz >= s
                                                                         and coalesce(i.diagnosis->>'root_cause', 'unclassified') <> 'unclassified'),
      'detail', jsonb_build_object('unclassified', (select count(*) from pipeline.integration_issues i where (i.diagnosis->>'at')::timestamptz >= s
                                                     and coalesce(i.diagnosis->>'root_cause', 'unclassified') = 'unclassified'))),
    jsonb_build_object('category', 'remedied_automatically', 'value', (select count(*) from pipeline.ops_remedy_runs r join pipeline.ops_remedies m on m.code = r.remedy_code
                                                                        where r.started_at >= s and m.authority = 'auto' and r.remedy_code <> all (v_book) and r.result in ('acted', 'verified', 'verify_failed')),
      'detail', jsonb_build_object('bookkeeping_runs', (select count(*) from pipeline.ops_remedy_runs r where r.started_at >= s and r.remedy_code = any (v_book)),
                                   'by_remedy', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb) from (select r.remedy_code || '/' || r.result k, count(*) n from pipeline.ops_remedy_runs r
                                                  where r.started_at >= s and r.remedy_code <> all (v_book) group by 1) z))),
    jsonb_build_object('category', 'verified_automatically', 'value', (select count(*) from pipeline.ops_remedy_runs r where r.started_at >= s and r.result = 'verified' and r.remedy_code <> all (v_book)),
      'detail', jsonb_build_object('closed_by_controller', (select count(*) from pipeline.integration_issue_events e where e.at >= s and e.kind = 'closed' and e.actor in ('ops-controller', 'first-run-verify')),
                                   'bookkeeping_verified', (select count(*) from pipeline.ops_remedy_runs r where r.started_at >= s and r.result = 'verified' and r.remedy_code = any (v_book)))),
    jsonb_build_object('category', 'claude_engineering', 'value', (select count(distinct x.release) from security.ops_releases_v1() x where x.at >= s and x.source = 'migration'),
      'detail', jsonb_build_object('basis', 'migrations applied (releases built by Claude)',
        'issue_steps_by_integration_controller', (select count(*) from pipeline.integration_issue_events e where e.at >= s and e.kind in ('status', 'closed')
                                                   and (e.actor ilike '%integration%controller%' or e.actor ilike 'claude%')))),
    jsonb_build_object('category', 'platform_admin_authority', 'value', (select count(*) from pipeline.admin_control_events c where c.created_at >= s
                                                                          and (c.actor is not null or (c.area = 'layer4' and c.action like 'rule\_%'))),
      'detail', jsonb_build_object('basis', 'pastes, decisions and approved rule runs recorded in admin_control_events',
        'open_awaiting_decision', (select count(*) from pipeline.integration_issues i where i.status <> 'closed' and i.superseded_by is null and i.ops_state = 'needs_decision'))),
    jsonb_build_object('category', 'layer4_human_decision', 'value', (select count(*) from pipeline.layer4_decisions d where d.created_at >= s and d.actor_id is not null)
                                                                     + (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= s and r.decided_by is not null),
      'detail', jsonb_build_object('layer4', (select coalesce(jsonb_object_agg(z.a, z.n), '{}'::jsonb) from (select d.action a, count(*) n from pipeline.layer4_decisions d
                                               where d.created_at >= s and d.actor_id is not null group by 1) z),
                                   'scholarship_reviews', (select count(*) from pipeline.scholarship_ai_reviews r where r.decided_at >= s and r.decided_by is not null)))),
    'results', v_prog - 'scholarship_scope');
end $function$;
revoke all on function security.autonomy_audit_v1(integer) from public, anon, authenticated;

create or replace function security.ops_learning_metrics_v1(p_hours int default 24) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- the seven §7 measures over the last p_hours
  with a as (select security.autonomy_audit_v1(p_hours) j)
  select jsonb_build_object(
    'automatically_diagnosed', (select (x->>'value')::int from a, jsonb_array_elements(a.j->'categories') x where x->>'category' = 'diagnosed_automatically'),
    'automatically_recovered', (select count(*) from pipeline.ops_remedy_outcomes o where o.performed_by = 'platform' and o.success and not o.seeded and o.applied_at >= now() - make_interval(hours => p_hours)
                                  and o.knowledge_code not like 'supersede\_into\_owner:%' and o.knowledge_code not like 'confirm\_condition\_cleared:%' and o.knowledge_code not like 'reclose\_stale\_reopen:%'),
    'repeated_ineffective_prevented', (select coalesce(sum(b.prevented), 0) from pipeline.ops_remedy_blocks b)
                                      + (select count(*) from pipeline.ops_remedy_runs r where r.result = 'refused_authority' and r.evidence->'authorise'->>'reason' like 'lost automatic eligibility%'),
    'claude_interventions', (select (x->>'value')::int + coalesce((x->'detail'->>'issue_steps_by_integration_controller')::int, 0) from a, jsonb_array_elements(a.j->'categories') x
                              where x->>'category' = 'claude_engineering'),
    'human_only_decisions', (select (x->>'value')::int from a, jsonb_array_elements(a.j->'categories') x where x->>'category' = 'layer4_human_decision'),
    'records_admitted', (select coalesce(sum((p->'admitted'->>'value')::int), 0) from a, jsonb_array_elements(a.j->'results'->'pipelines') p),
    'consumer_published', (select coalesce(sum((p->'published'->>'value')::int), 0) from a, jsonb_array_elements(a.j->'results'->'pipelines') p),
    'verified_patterns', (select count(*) from pipeline.ops_remedy_knowledge k where k.verified > 0 and k.auto_eligible and k.authority = 'auto'))
$function$;
revoke all on function security.ops_learning_metrics_v1(integer) from public, anon, authenticated;

create or replace function security.ops_learning_report_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 (direction 4 Nov 2026 18:08 §7): metric, baseline (at release), current (last 24 h) and the verified outcome; and the trend of Claude
-- interventions against verified recovery patterns from the hourly readings. Reads only.
declare b jsonb; c jsonb; v_rows jsonb := '[]'::jsonb; k text; v_better boolean;
begin
  select r.metrics into b from pipeline.ops_learning_readings r where r.kind = 'baseline' order by r.id limit 1;
  c := security.ops_learning_metrics_v1(24);
  foreach k in array array['automatically_diagnosed', 'automatically_recovered', 'repeated_ineffective_prevented', 'claude_interventions', 'human_only_decisions', 'records_admitted', 'consumer_published'] loop
    v_better := case when k in ('claude_interventions') then (c->>k)::numeric < (b->>k)::numeric else (c->>k)::numeric > (b->>k)::numeric end;
    v_rows := v_rows || jsonb_build_object('metric', k, 'baseline', b->k, 'current', c->k,
      'verified_outcome', case when b is null then 'no baseline' when (c->>k) is null then 'not measured' when (c->>k)::numeric = (b->>k)::numeric then 'unchanged'
                               when v_better then 'improved' else 'worse' end);
  end loop;
  return jsonb_build_object('table', v_rows, 'baseline_at', (select min(r.at) from pipeline.ops_learning_readings r where r.kind = 'baseline'),
    'trend', (select coalesce(jsonb_agg(jsonb_build_object('at', z.at, 'claude_interventions', z.metrics->'claude_interventions', 'verified_patterns', z.metrics->'verified_patterns',
                                                         'automatically_recovered', z.metrics->'automatically_recovered') order by z.at), '[]'::jsonb)
                from (select r.at, r.metrics from pipeline.ops_learning_readings r order by r.at desc limit 48) z),
    'patterns', (select jsonb_build_object('total', count(*), 'auto_eligible', count(*) filter (where k2.auto_eligible), 'lost_eligibility', count(*) filter (where not k2.auto_eligible),
                                           'open_blocks', (select count(*) from pipeline.ops_remedy_blocks b2 where b2.lifted_at is null)) from pipeline.ops_remedy_knowledge k2),
    'authority_blockers', (select coalesce(jsonb_agg(z.b), '[]'::jsonb) from (
        select jsonb_build_object('blocker', 'alerts not delivered: destination paused by the Platform Admin', 'authority', 'Platform Admin',
          'detail', 'pipeline.platform_alerts waiting for delivery; their destination (the Work queue alerts scheduled task) was paused by the Platform Admin on 3 Nov 2026 18:21 AEDT, so no platform alert reaches the Platform Admin. Not a remedy candidate: only resuming the destination clears it.',
          'waiting', count(*), 'oldest', min(a.created_at)) b
          from pipeline.platform_alerts a where a.status in ('held', 'pending', 'failed') having count(*) > 0
        union all
        select jsonb_build_object('blocker', 'issues awaiting a Platform Admin decision', 'authority', 'Platform Admin', 'waiting', count(*),
                                  'oldest', min(i.detected_at)) from pipeline.integration_issues i
         where i.status <> 'closed' and i.superseded_by is null and i.ops_state = 'needs_decision' having count(*) > 0) z),
    'note', 'Not self-sustaining because rules are deployed: improved means the platform itself recovered and advanced records (direction 18:08 §7).');
end $function$;
revoke all on function security.ops_learning_report_v1() from public, anon, authenticated;

create or replace function security.ops_learning_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- the learning step of job first-run-verify: harvest, gate, and a reading at most every learn.reading_minutes
declare v jsonb := '{}'::jsonb;
begin
  if security.pipeline_num_v1('learn.on', 1) < 1 then return jsonb_build_object('off', true); end if;
  v := v || jsonb_build_object('harvest', security.ops_learning_harvest_v1());
  v := v || jsonb_build_object('gate', security.ops_learning_gate_v1());
  if not exists (select 1 from pipeline.ops_learning_readings r where r.at > now() - make_interval(mins => security.pipeline_num_v1('learn.reading_minutes', 60)::int)) then
    insert into pipeline.ops_learning_readings(kind, metrics) values ('reading', security.ops_learning_metrics_v1(24));
    v := v || jsonb_build_object('reading', true);
  end if;
  return v;
end $function$;
revoke all on function security.ops_learning_tick_v1() from public, anon, authenticated;

-- 5. the controller's Authorise step refuses a remedy that lost automatic eligibility; the learning step runs in job first-run-verify; the report ---------
select pg_temp.edit_once('security.ops_authorise_v1(text)', 'ae58963cd1298edeeacae406dc65b314', '9f4a124db50a835f23ccb475f8d935c8',
  array[array[$o$when not m.active then 'remedy switched off' when m.action_fn is null$o$,
              $n$when not m.active then 'remedy switched off' when security.ops_learning_refusal_v1(m.code) is not null then security.ops_learning_refusal_v1(m.code) when m.action_fn is null$n$]],
  array[1]);

select pg_temp.edit_once('security.first_run_verify_tick_v1()', '9c078d17de8d699de2d932ad1eca8fb8', '9df7a97bd494ff3c5425925e419553a5',
  array[array[$o$  v := v || jsonb_build_object('route', v_r);$o$,
              $n$  v := v || jsonb_build_object('route', v_r);
  -- recovery knowledge (direction 4 Nov 2026 18:08 §2-§3): outcomes, blocks and readings, isolated
  begin v_r := security.ops_learning_tick_v1(); exception when others then v_r := jsonb_build_object('error', left(sqlerrm, 300)); end;
  v := v || jsonb_build_object('learn', v_r);$n$]], array[1]);

select pg_temp.edit_once('security.self_sustainability_v1(integer)', 'a91e9c8151cca09763cf755ab1da1f56', '1965a71983c841617d9e06d29fa363ec',
  array[array[$o$  exception when others then v_out := v_out || jsonb_build_object('recovery_gaps', jsonb_build_object('error', left(sqlerrm, 200))); end;$o$,
              $n$  exception when others then v_out := v_out || jsonb_build_object('recovery_gaps', jsonb_build_object('error', left(sqlerrm, 200))); end;
  -- direction 4 Nov 2026 18:08 §1 and §7: who achieved the outcomes, and the recovery-learning table with its baseline (each isolated)
  begin v_out := v_out || jsonb_build_object('autonomy', security.autonomy_audit_v1(p_window_hours) - 'results');
  exception when others then v_out := v_out || jsonb_build_object('autonomy', jsonb_build_object('error', left(sqlerrm, 200))); end;
  begin v_out := v_out || jsonb_build_object('recovery_learning', security.ops_learning_report_v1());
  exception when others then v_out := v_out || jsonb_build_object('recovery_learning', jsonb_build_object('error', left(sqlerrm, 200))); end;$n$]], array[1]);

-- 6. seeds from real outcomes (direction §2: "seed the history from real outcomes") -------------------------------------------------------------------
-- 6.1 every controller run already verified or failed (live ops_remedy_runs), harvested by run id
select security.ops_learning_harvest_v1();
select security.ops_learning_harvest_v1();  -- fixed: a second pass covers more than one batch of history; later runs are harvested by the job

-- 6.2 outcomes recorded in the execution register and the investigations, with who achieved them
insert into pipeline.ops_remedy_knowledge(code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome,
       no_retry_condition, reuse_conditions, auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
select * from (values
 ('sch_classify_duplicate_key', 'scholarship', 'Classifier insert met one key twice (repeated listing address): fold to one case per key',
  array['job_failed:scholarship-coverage-classify'], 'first_run_sql_defect', 'engineering_remediation',
  '{"error_class": "sql_cardinality", "pattern": "%cannot affect row a second time%"}'::jsonb, 'release', 'claude_engineering',
  'one case per (provider, item key); the scheduled run completes', 'the failing definition is never re-run unchanged: the fault is in code',
  'the same error class on a job is routed as owned engineering work (security.recovery_route_engineering_v1); never retried automatically', false,
  'a code defect: fixed by a release, not by the platform', now(), 'seed', 'execution register 4 Nov 07:35; v2.15.461 (IQ-00241); run 1211430'),
 ('course_relink_time_budget', 'course_link', 'course-relink statement time-out: isolate each university within a time budget',
  array['job_failed:course-relink'], 'timeout_under_load', 'fix_in_release',
  '{"error_class": "time_budget", "pattern": "%canceling statement due to statement timeout%"}'::jsonb, 'release', 'claude_engineering',
  'every scheduled run succeeds; universities settle in work items', 'recording a load profile again verifies nothing (8 failed in a row on this fingerprint)',
  'a repeated time-out on a job is routed as owned engineering work after ops.permanent_after_runs failures', false,
  'a code defect: fixed by a release, not by the platform', now(), 'seed', 'execution register 3 Nov 23:20; v2.15.445 (IQ-00074)'),
 ('course_link_approved_rules', 'course_link', 'Approved Course Link rules executed item by item (canberra_no_year, sfu_no_term, adelaide_keep_held)',
  array[]::text[], null, null,
  '{"rules": ["canberra_no_year", "sfu_no_term", "adelaide_keep_held"], "identity_basis": {"AU": "CRICOS code", "CA": "field and award"}}'::jsonb, 'admin', 'platform_admin',
  'each item decided by its approved rule; links changed verified on Website API v2, Zoho and Wix',
  'a stored copy whose identity basis is title only; a provider outside the rule''s approved scope',
  'only the same rule, for the same provider scope, on an exact identity basis; a new provider or rule needs Platform Admin approval', false,
  'Platform Admin authority per rule and provider scope', now(), 'seed', 'decision pack 3 Nov 21:50 items 1-2; register 4 Nov 03:00; morning measures §3.2'),
 ('aer_corrected_reread_same_copy', 'aer', 'AER held step: corrected re-read of the same stored copy with the same reader',
  array[]::text[], null, null,
  '{"step": "aer_schedule_held_v1", "signature": "stored copy content hash + reader version + entry settings"}'::jsonb, 'auto', 'platform',
  'the held read is replaced by a complete read',
  'the same stored copy, reader version and settings: the deterministic reader returns the same result',
  'only when the copy, the reader or the settings changed since the failed read (the AER recovery selector asks security.ops_learning_retry_check_v1)', false,
  '10 of 100 closed corrections replaced the held read (about 10%); 90 refused on the same copy', now(), 'recovery knowledge seed',
  'admin docs/platform/2026-11-04-aer-throughput-investigation.md §1 and §10 (overnight 3-4 Nov; 69 refused on an unchanged copy in 24 h)'),
 ('aer_reread_row_limit', 'aer', 'AER re-read of a read cut at the row limit',
  array[]::text[], null, null, '{"hold": "row_limit", "setting": "entry.max_rows_by_provider"}'::jsonb, 'admin', 'platform',
  'every printed requirement kept', 'any re-read under the same row limit: it is cut at the same boundary',
  'only after the Platform Admin sets a per-university row boundary, or the source is mapped as a matrix source', false,
  'no re-read can release a row-limit hold (162 held; 15 corrected reads refused at the row limit)', now(), 'recovery knowledge seed',
  'admin docs/platform/2026-11-04-aer-throughput-investigation.md §1, §2, §10')
) v(code, lane, title, fingerprint_like, root_cause, remedy_code, trigger_conditions, authority, performed_by, expected_outcome, no_retry_condition, reuse_conditions,
    auto_eligible, eligibility_reason, eligibility_changed_at, eligibility_changed_by, seeded_from)
where (v.remedy_code is null or exists (select 1 from pipeline.ops_remedies m where m.code = v.remedy_code))
  and (v.root_cause is null or exists (select 1 from pipeline.ops_root_causes c where c.code = v.root_cause))
on conflict (code) do nothing;

insert into pipeline.ops_remedy_outcomes(knowledge_code, fingerprint, performed_by, applied_at, expected, observed, success, stage_advanced, applications, evidence, seeded)
select v.* from (values
 ('sch_classify_duplicate_key', 'job_failed:scholarship-coverage-classify', 'claude_engineering', '2026-11-04 08:29:00+11'::timestamptz, 'one case per key',
  '{"release": "v2.15.461", "run": 1211430, "providers": 40, "cases": 4577, "seconds": 32}'::jsonb, true, true, 1,
  '{"failed_runs_before": [1208143, 1209768], "issues": ["IQ-00239", "IQ-00241"]}'::jsonb, true),
 ('course_relink_time_budget', 'job_failed:course-relink', 'claude_engineering', '2026-11-03 22:54:00+11'::timestamptz, 'every run succeeds',
  '{"release": "v2.15.445", "runs_ok_after": 67, "failed_before": 32}'::jsonb, true, true, 1, '{"issue": "IQ-00074"}'::jsonb, true),
 ('course_link_approved_rules', null, 'platform_admin', '2026-11-04 03:00:00+11'::timestamptz, 'items decided by approved rules',
  '{"decided": 338, "canberra_no_year": 97, "sfu_no_term": 58, "adelaide_keep_held": 183, "links_changed": 155, "consumer_verified": 155}'::jsonb, true, true, 338,
  '{"failures_fixed_by_releases": ["v2.15.448 own run tables (IQ-00161)", "v2.15.451 time budget", "v2.15.453 https target (IQ-00189)"]}'::jsonb, true),
 ('aer_corrected_reread_same_copy', null, 'platform', '2026-11-04 05:20:00+11'::timestamptz, 'held read replaced', '{"replaced": 10}'::jsonb, true, true, 10,
  '{"window": "3-4 Nov overnight"}'::jsonb, true),
 ('aer_corrected_reread_same_copy', null, 'platform', '2026-11-04 05:20:00+11'::timestamptz, 'held read replaced',
  '{"refused": 90, "dropped_minimums": 63, "row_limit": 15, "refused_unchanged_copy_24h": 69}'::jsonb, false, false, 90, '{"window": "3-4 Nov overnight"}'::jsonb, true),
 ('aer_reread_row_limit', null, 'platform', '2026-11-04 12:00:00+11'::timestamptz, 'every printed requirement kept', '{"refused_at_row_limit": 15, "row_limit_holds": 162}'::jsonb,
  false, false, 15, '{}'::jsonb, true)
) v(knowledge_code, fingerprint, performed_by, applied_at, expected, observed, success, stage_advanced, applications, evidence, seeded)
where exists (select 1 from pipeline.ops_remedy_knowledge k where k.code = v.knowledge_code)
  and not exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = v.knowledge_code and o.seeded and o.observed = v.observed);
update pipeline.ops_remedy_knowledge k set applied = coalesce(s.apps, 0), verified = coalesce(s.ok, 0), failed = coalesce(s.bad, 0), last_outcome_at = s.last
  from (select o.knowledge_code, sum(o.applications) apps, sum(o.applications) filter (where o.success) ok, sum(o.applications) filter (where not o.success) bad, max(o.applied_at) last
          from pipeline.ops_remedy_outcomes o where o.seeded group by 1) s
 where k.code = s.knowledge_code;

-- 6.3 the §7 baseline, at release
insert into pipeline.ops_learning_readings(kind, metrics)
select 'baseline', security.ops_learning_metrics_v1(24) where not exists (select 1 from pipeline.ops_learning_readings where kind = 'baseline');

-- 7. register (housekeeping) and post-check ------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.ops_remedy_knowledge', 'Platform', 'Platform upkeep', 'Recovery knowledge: verified remedy patterns and eligibility', 'active', '{}', '20261104600000'),
 ('table', 'pipeline.ops_remedy_outcomes', 'Platform', 'Platform upkeep', 'Recovery knowledge: every remedy outcome and who achieved it', 'active', '{}', '20261104600000'),
 ('table', 'pipeline.ops_remedy_blocks', 'Platform', 'Platform upkeep', 'Recovery knowledge: remedies stopped per fingerprint', 'active', '{}', '20261104600000'),
 ('table', 'pipeline.ops_learning_readings', 'Platform', 'Platform upkeep', 'Recovery knowledge: §7 baseline and readings', 'active', '{}', '20261104600000'),
 ('function', 'security.ops_learning_tick_v1', 'Platform', 'Platform upkeep', 'Learning step of job first-run-verify', 'active', '{}', '20261104600000'),
 ('function', 'security.autonomy_audit_v1', 'Platform', 'Platform upkeep', 'Who achieved the outcomes (§1)', 'active', '{}', '20261104600000'),
 ('function', 'security.ops_learning_report_v1', 'Platform', 'Platform upkeep', 'Recovery-learning table with baseline (§7)', 'active', '{}', '20261104600000')
on conflict do nothing;

do $$
declare v record;
begin
  for v in select * from (values ('security.ops_authorise_v1(text)', '9f4a124db50a835f23ccb475f8d935c8'), ('security.first_run_verify_tick_v1()', '9df7a97bd494ff3c5425925e419553a5'),
                                 ('security.self_sustainability_v1(integer)', '1965a71983c841617d9e06d29fa363ec'), ('security.ops_report_v1(integer)', '518b5bf873549931a15d4173fef793d5')) x(sig, m) loop
    if md5(pg_get_functiondef(v.sig::regprocedure)) <> v.m then raise exception 'post-check: %', v.sig; end if;
  end loop;
  if (select count(*) from pipeline.ops_learning_readings where kind = 'baseline') <> 1 then raise exception 'post-check: one baseline'; end if;
end $$;
