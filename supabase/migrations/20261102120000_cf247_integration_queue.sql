-- CF-247 Continuous Validation, Integration Feedback and Parallel Agent Execution (Platform Admin mandate 2 Nov 2026 16:58; admin
-- docs/platform/nz-enrichment-brief/2026-11-02-continuous-validation-integration-feedback-mandate-1658.md §3, §4 V3/V4, §5, §6, §7, §9, §13;
-- docs/platform/AGENT-OPERATING-MODEL.md "Integration Controller and operating modes").
-- Why: every observed failure, regression, missing dependency or unmet acceptance criterion must become a trackable remediation item that is
--   grouped by a deterministic fingerprint (no fresh duplicate for an unchanged problem), reopened as a regression when it recurs after closure,
--   and closed only on production verification evidence. Today failures live in Platform health issues (pipeline.platform_issues, which
--   auto-resolve and are not owned), queue-watch states, Admin documents and chat; nothing carries owner, root cause, fix, deployment and
--   verification together, and nothing records the operating mode.
-- What exists and is reused (nothing here is a second alerting or health system):
--   * Platform health (job platform-health, security.platform_health_check_v1) and the progress watchdog (job queue-watch,
--     security.queue_watch_run_v1, which opens Platform health issues itself): their output, the open rows of pipeline.platform_issues, is read
--     by the V4 job and fed into the queue by fingerprint. Neither function is edited; neither is run a second time.
--   * The deduplicated alert path (pipeline.platform_issues -> job platform-alerts, security.platform_alerts_evaluate_v1 -> pipeline.platform_alerts,
--     alerts.* settings, recovery notice): a P0 integration issue opens one Platform health issue (check key "integration:<fingerprint>",
--     critical) and resolves it when the condition clears or the issue closes. platform-alerts raises it once (dedupe key issue:raised, the
--     per-check quiet period), sends one recovery notice, and its existing reminder rule applies. The health check never auto-resolves these
--     rows: it resolves only check keys whose first part is a check it ran, and "integration" is not one of its checks (live definition read
--     2 Nov 2026 17:06, md5 25ff04344e2a940a3132e7ba709f98aa, section 5).
--   * pipeline.admin_control_events (audit of operating mode changes), pipeline.automation_catalogue (G1), pipeline.platform_toolset_settings
--     (G2), pipeline.component_register (housekeeping), security.current_role_rank (screen role check).
--   * AER Phase B (branch cf247-aer-phase-b, migration 20261102110000: pipeline.aer_gap_findings / aer_gap_root_causes / aer_gap_events) is not
--     duplicated or touched: an AER root cause links to at most one integration issue by reference (integration_issues.aer_root_cause_ref).
-- What:
--   1. pipeline.integration_issues (the queue; every §3 field), pipeline.integration_issue_events (history), pipeline.integration_operating_mode
--      (Mode 1 or 2, who set it; changed only through security.integration_mode_set_v1, audited in admin_control_events),
--      pipeline.integration_validate_state (per-check watermarks and last results), pipeline.integration_lease_watch (the lease tables V4
--      looks at, each with an index or under a few thousand rows), pipeline.integration_deploy_checks (V3 results).
--   2. security.integration_issue_upsert_v1 (by fingerprint: an unchanged problem updates last_observed_at and retry_count; a recurrence after
--      Closed reopens it as a regression), security.integration_issue_transition_v1 (the lifecycle; failed validation returns to In progress or
--      Triaged with new evidence), security.integration_issue_close_v1 (refuses without verification evidence), security.integration_mode_set_v1.
--   3. V4: security.integration_validate_v1, job integration-validate (created INACTIVE; the integrator switches it on after release), at :21
--      and :51 (clear of the admission minutes :x3/:x5/:x9, the :35-:42 jobs, :47-:48 and the :x6-:x8 read windows). Keyed checks only.
--   4. V3: security.integration_deploy_check_v1, called by the release controller after each deploy.
--   5. Screen: public.admin_integration_queue (PIM Admin and above; read only), Platform health › Integration queue.
--   6. One index beside pipeline.layer4_review_items (entity_id, field_code, status): the regeneration and duplicate checks look up a pending
--      item's decided siblings by key; the table (24,890 rows on 2 Nov 2026) had no index on entity_id.
-- Replaces: nothing (new queue; Platform health, queue-watch and platform-alerts are reused unchanged)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. No existing function is edited. Consumer API untouched (G3): no consumer function, table, column
-- or edge function changes; search.course_documents is only read.

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'integration.failed_runs_scan', 'Integration checks: scheduler runs looked through',
  'Failed job runs are found among this many of the newest scheduler runs (all jobs), only those newer than the last check, so the read stays small. Keep it above the runs of all jobs between two checks (about 1,200 in 30 minutes).',
  'number', to_jsonb(5000), 500, 50000, 'runs', 990, 'Integration queue', 'security.integration_validate_v1 (failed job runs); security.integration_deploy_check_v1 (errors since the deploy)',
  'CF-247 continuous validation mandate (Platform Admin 2 Nov 2026 16:58) §4 V3/V4'),
 ('pipeline', 'integration.lease_stale_minutes', 'Integration checks: a lease is stale after',
  'A work item still leased this long after its lease ended (in the lease tables listed for the integration checks) opens a stale-lease issue for its table.',
  'number', to_jsonb(60), 15, 1440, 'minutes', 991, 'Integration queue', 'security.integration_validate_v1 (stale leases)', 'CF-247 continuous validation mandate §4 V3 "queues and leases"'),
 ('pipeline', 'integration.draft_stuck_hours', 'Integration checks: an adapter draft is stuck after',
  'An adapter draft left in capturing or proposing for this long without a change opens a stuck-draft issue.',
  'number', to_jsonb(24), 1, 720, 'hours', 992, 'Integration queue', 'security.integration_validate_v1 (stuck drafts)', 'CF-247 continuous validation mandate §4 V4 "drafts stuck in capture/proposal"'),
 ('pipeline', 'integration.first_run_lookback_hours', 'Integration checks: first run looks back',
  'On its first run (no watermark yet) a windowed check (failed job runs, work for archived providers) looks back this far.',
  'number', to_jsonb(24), 1, 720, 'hours', 993, 'Integration queue', 'security.integration_validate_v1', 'CF-247 continuous validation mandate §4 V4 (incremental checks)'),
 ('pipeline', 'integration.entity_ids_max', 'Integration queue: entity ids kept per issue',
  'An issue keeps up to this many provider and course ids (the union of every observation); beyond it the issue is marked as having more.',
  'number', to_jsonb(500), 10, 5000, 'ids', 994, 'Integration queue', 'security.integration_issue_upsert_v1', 'CF-247 continuous validation mandate §3 (group repeats without concealing affected entities)'),
 ('pipeline', 'integration.l4_pending_max', 'Integration checks: Layer 4 pending items examined',
  'The Layer 4 duplicate, orphan, regeneration and course-url-fill checks examine at most this many pending items a run (newest first); a larger backlog is reported as partly checked.',
  'number', to_jsonb(5000), 500, 50000, 'items', 995, 'Integration queue', 'security.integration_validate_v1 (Layer 4 checks)', 'CF-247 continuous validation mandate §6'),
 ('pipeline', 'integration.inactive_courses_max', 'Integration checks: inactive courses examined',
  'The search leak check looks up the search document of at most this many courses that are not active a run.',
  'number', to_jsonb(20000), 1000, 200000, 'courses', 996, 'Integration queue', 'security.integration_validate_v1 (search leak)', 'CF-247 continuous validation mandate §7 (no retired records in active search)')
on conflict do nothing;

-- 2. tables ---------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.integration_issues (
  id bigserial primary key,
  issue_ref text generated always as ('IQ-' || lpad(id::text, 5, '0')) stored,
  fingerprint text not null unique check (length(btrim(fingerprint)) > 0),
  title text not null,
  layer text not null,
  subsystem text,
  provider_ids uuid[] not null default '{}',
  course_ids uuid[] not null default '{}',
  country_codes text[] not null default '{}',
  entities_truncated boolean not null default false,
  detected_at timestamptz not null default now(),
  failure text not null,
  expected text not null,
  detection_source text not null,
  validation_layer text not null default 'manual' check (validation_layer in ('V1', 'V2', 'V3', 'V4', 'manual')),
  evidence jsonb not null default '{}'::jsonb,
  evidence_refs text[] not null default '{}',
  root_cause_class text not null default 'unclassified' check (root_cause_class in ('unclassified', 'code_defect', 'data_drift', 'job_config',
    'lifecycle_leak', 'queue_or_lease', 'missing_dependency', 'governance_gap', 'external', 'budget', 'human_decision', 'deployment_drift')),
  severity text not null check (severity in ('P0', 'P1', 'P2')),
  impact text,
  workstream text not null check (workstream in ('A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10')),
  blocked_by bigint[] not null default '{}',
  depends_on text[] not null default '{}',
  fix_commit text,
  fix_migration text,
  deployed_version text,
  verification_outcome text check (verification_outcome in ('passed', 'failed', 'regressed')),
  verification_evidence jsonb,
  verified_at timestamptz,
  verified_by text,
  retry_count int not null default 0,
  last_observed_at timestamptz not null default now(),
  condition_cleared_at timestamptz,
  status text not null default 'detected' check (status in ('detected', 'triaged', 'assigned', 'in_progress', 'code_ready', 'integration_testing',
    'deployed', 'production_verification', 'closed', 'reopened')),
  assignee text,
  regression_count int not null default 0,
  reopened_at timestamptz,
  closed_at timestamptz,
  aer_root_cause_ref text,
  alert_check_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table pipeline.integration_issues is 'CF-247 continuous validation mandate (Platform Admin 2 Nov 2026 16:58) §3: the persistent integration feedback queue. One row per defect, grouped by a deterministic fingerprint (V4 checks, V3 deploy checks, Platform health and queue-watch issues, and items recorded by the Integration Controller). Repeats update last_observed_at and retry_count; a recurrence after Closed reopens the row as a regression; Closed needs production verification evidence (security.integration_issue_close_v1). aer_root_cause_ref links one AER Phase B root cause (pipeline.aer_gap_root_causes) by reference. Written only by the integration functions; read on Platform health › Integration queue (PIM Admin and above). Never read by the consumer API.';
create unique index if not exists integration_issues_aer_ref_uq on pipeline.integration_issues (aer_root_cause_ref) where aer_root_cause_ref is not null;
create index if not exists integration_issues_open_idx on pipeline.integration_issues (status, severity) where status <> 'closed';
create index if not exists integration_issues_observed_idx on pipeline.integration_issues (last_observed_at desc);
alter table pipeline.integration_issues enable row level security;
revoke all on pipeline.integration_issues from public, anon, authenticated;
revoke all on sequence pipeline.integration_issues_id_seq from public, anon, authenticated;

create table if not exists pipeline.integration_issue_events (
  id bigserial primary key,
  issue_id bigint not null references pipeline.integration_issues(id),
  at timestamptz not null default now(),
  kind text not null check (kind in ('detected', 'observed', 'not_observed', 'observed_again', 'escalated', 'status', 'reopened_regression',
    'closed', 'updated', 'alert_opened', 'alert_resolved')),
  from_status text,
  to_status text,
  actor text not null,
  note text,
  detail jsonb not null default '{}'::jsonb
);
comment on table pipeline.integration_issue_events is 'CF-247 continuous validation mandate §3/§5: the history of each integration issue (detected, material re-observations, condition cleared or back, status changes with their evidence, regression reopenings, closure with its verification, P0 alert opened and resolved). Written only by the integration functions; never read by the consumer API.';
create index if not exists integration_issue_events_issue_idx on pipeline.integration_issue_events (issue_id, at desc);
alter table pipeline.integration_issue_events enable row level security;
revoke all on pipeline.integration_issue_events from public, anon, authenticated;
revoke all on sequence pipeline.integration_issue_events_id_seq from public, anon, authenticated;

create table if not exists pipeline.integration_operating_mode (
  id int primary key default 1 check (id = 1),
  mode int not null check (mode in (1, 2)),
  set_by text not null,
  set_at timestamptz not null default now(),
  reason text not null
);
comment on table pipeline.integration_operating_mode is 'CF-247 mandate §13 and AGENT-OPERATING-MODEL.md: the current operating mode (1 Active Remediation, 2 Steady-State Monitoring) and who set it. One row. Changed only by the Integration Controller through security.integration_mode_set_v1 (a trigger refuses any other write), each change recorded in pipeline.admin_control_events (area integration, action operating_mode). Never read by the consumer API.';
alter table pipeline.integration_operating_mode enable row level security;
revoke all on pipeline.integration_operating_mode from public, anon, authenticated;
insert into pipeline.integration_operating_mode(id, mode, set_by, reason)
values (1, 1, 'Platform Admin (AGENT-OPERATING-MODEL.md, 2 Nov 2026 17:00)', 'CF-247 programme not yet accepted; SS-015 Gates C-E open')
on conflict (id) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'integration', 'operating_mode', 'pipeline.integration_operating_mode',
       jsonb_build_object('from', null, 'to', 1, 'set_by', 'Platform Admin (AGENT-OPERATING-MODEL.md, 2 Nov 2026 17:00)', 'reason', 'recorded when the queue was created (migration 20261102120000)'), null
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'integration' and e.action = 'operating_mode');

create or replace function security.integration_mode_guard_v1() returns trigger
language plpgsql set search_path to '' as $function$
begin
  if coalesce(current_setting('cf247.integration_mode_path', true), '') <> 'on' then
    raise exception 'the operating mode is changed only by the Integration Controller (security.integration_mode_set_v1)' using errcode = '42501';
  end if;
  return new;
end $function$;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'integration_mode_guard' and tgrelid = 'pipeline.integration_operating_mode'::regclass) then
    create trigger integration_mode_guard before update or delete on pipeline.integration_operating_mode
      for each row execute function security.integration_mode_guard_v1();
  end if;
end $t$;

create table if not exists pipeline.integration_validate_state (
  check_key text primary key,
  last_run_at timestamptz,
  watermark_id bigint,
  watermark_at timestamptz,
  last_found int,
  last_ms int,
  last_error text,
  detail jsonb not null default '{}'::jsonb
);
comment on table pipeline.integration_validate_state is 'CF-247 mandate §4 V4: per-check watermark (newest scheduler run or ledger row already looked at) and last result of job integration-validate (security.integration_validate_v1), so each run reads only what is new. Never read by the consumer API.';
alter table pipeline.integration_validate_state enable row level security;
revoke all on pipeline.integration_validate_state from public, anon, authenticated;

create table if not exists pipeline.integration_lease_watch (
  table_name text primary key,
  lease_column text not null,
  leased_predicate text not null,
  workstream text not null default 'A7',
  note text
);
comment on table pipeline.integration_lease_watch is 'CF-247 mandate §4 V3/V4: the work tables whose stale leases job integration-validate counts, each with the condition that means "still leased" there. Only tables with an index on their state or lease, or a few thousand rows, are listed (read 2 Nov 2026), so the check stays keyed. Never read by the consumer API.';
alter table pipeline.integration_lease_watch enable row level security;
revoke all on pipeline.integration_lease_watch from public, anon, authenticated;
insert into pipeline.integration_lease_watch(table_name, lease_column, leased_predicate, note) values
 ('pipeline.coverage_ai_match', 'leased_until', $p$state = 'leased'$p$, 'index (state, id)'),
 ('pipeline.field_enrich_items', 'leased_until', $p$state = 'leased'$p$, 'partial index on open states'),
 ('pipeline.scholarship_ai_queue', 'leased_until', $p$state = 'leased'$p$, 'partial index (state, next_try_at)'),
 ('pipeline.central_ai_queue', 'leased_until', $p$state = 'leased'$p$, 'index (state, id)'),
 ('pipeline.entry_matrix_runs', 'leased_until', $p$state in ('reading', 'leased')$p$, 'index (state, created_at)'),
 ('pipeline.provider_description_reads', 'leased_until', $p$state = 'reading'$p$, 'index (state, next_try_at)'),
 ('pipeline.layer1_run_queue', 'lease_until', $p$status = 'running'$p$, 'index (status, heartbeat_at)'),
 ('pipeline.fee_reader_queue', 'leased_until', $p$state = 'leased'$p$, 'about 5,400 rows'),
 ('pipeline.provider_central_search', 'leased_until', $p$state = 'leased'$p$, 'about 2,300 rows'),
 ('pipeline.source_find_runs', 'leased_until', $p$state = 'leased'$p$, 'about 480 rows')
on conflict (table_name) do nothing;

create table if not exists pipeline.integration_deploy_checks (
  id bigserial primary key,
  release text not null,
  checked_at timestamptz not null default now(),
  since timestamptz not null,
  ok boolean not null,
  result jsonb not null,
  issues text[] not null default '{}'
);
comment on table pipeline.integration_deploy_checks is 'CF-247 mandate §4 V3: one row per deployment check run by the release controller (security.integration_deploy_check_v1): migration md5 against the file, function md5s against the expected ones, scheduled job compatibility, failed runs and HTTP errors since the deploy, and the integration issues it opened or updated. Never read by the consumer API.';
alter table pipeline.integration_deploy_checks enable row level security;
revoke all on pipeline.integration_deploy_checks from public, anon, authenticated;
revoke all on sequence pipeline.integration_deploy_checks_id_seq from public, anon, authenticated;

-- the Layer 4 key lookup (new index beside the table; nothing else changes)
create index if not exists layer4_review_items_entity_field_iq_idx on pipeline.layer4_review_items (entity_id, field_code, status);

-- 3. queue functions ----------------------------------------------------------------------------------------------------------------------
create or replace function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate §3/§5: create or update an integration issue by its deterministic fingerprint. An unchanged problem updates last_observed_at
-- and retry_count only (no new row, no history line); new affected entities or a higher severity add one history line; a recurrence after
-- Closed reopens the same row as a regression. Severity is never lowered automatically.
declare v_fp text := btrim(coalesce(p->>'fingerprint', ''));
        v_max int := security.pipeline_num_v1('integration.entity_ids_max', 500)::int;
        v_sev text := coalesce(nullif(p->>'severity', ''), 'P2');
        v_prov uuid[] := coalesce((select array_agg(distinct x::uuid) from jsonb_array_elements_text(coalesce(p->'provider_ids', '[]'::jsonb)) x), '{}');
        v_course uuid[] := coalesce((select array_agg(distinct x::uuid) from jsonb_array_elements_text(coalesce(p->'course_ids', '[]'::jsonb)) x), '{}');
        v_cc text[] := coalesce((select array_agg(distinct upper(x)) from jsonb_array_elements_text(coalesce(p->'country_codes', '[]'::jsonb)) x), '{}');
        v_refs text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'evidence_refs', '[]'::jsonb)) x), '{}');
        v_deps text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'depends_on', '[]'::jsonb)) x), '{}');
        v_blk bigint[];
        r pipeline.integration_issues; v_new_prov uuid[]; v_new_course uuid[]; v_more boolean; v_action text; v_status text;
begin
  if v_fp = '' then raise exception 'an integration issue needs a fingerprint' using errcode = '22023'; end if;
  if v_sev not in ('P0', 'P1', 'P2') then raise exception 'severity must be P0, P1 or P2' using errcode = '22023'; end if;
  select coalesce(array_agg(i.id), '{}') into v_blk from pipeline.integration_issues i
   where i.fingerprint in (select jsonb_array_elements_text(coalesce(p->'blocked_by_fingerprints', '[]'::jsonb)));
  perform pg_advisory_xact_lock(hashtext('cf247:integration_issue:' || v_fp));  -- fixed: one writer per fingerprint
  select * into r from pipeline.integration_issues i where i.fingerprint = v_fp for update;
  if not found then
    v_status := coalesce(nullif(p->>'status', ''), 'detected');
    if v_status not in ('detected', 'triaged', 'assigned', 'in_progress') then raise exception 'a new issue starts as detected, triaged, assigned or in_progress' using errcode = '22023'; end if;
    insert into pipeline.integration_issues(fingerprint, title, layer, subsystem, provider_ids, course_ids, country_codes, entities_truncated, failure, expected,
           detection_source, validation_layer, evidence, evidence_refs, root_cause_class, severity, impact, workstream, blocked_by, depends_on, status, assignee,
           fix_commit, fix_migration, aer_root_cause_ref, detected_at, last_observed_at)
    values (v_fp, left(coalesce(p->>'title', v_fp), 300), coalesce(nullif(p->>'layer', ''), 'Platform'), p->>'subsystem',
           v_prov[1:v_max], v_course[1:v_max], v_cc, cardinality(v_prov) > v_max or cardinality(v_course) > v_max,
           coalesce(nullif(p->>'failure', ''), 'not stated'), coalesce(nullif(p->>'expected', ''), 'not stated'),
           coalesce(nullif(p->>'source', ''), p_actor), coalesce(nullif(p->>'validation_layer', ''), 'manual'), coalesce(p->'evidence', '{}'::jsonb), v_refs,
           coalesce(nullif(p->>'root_cause_class', ''), 'unclassified'), v_sev, p->>'impact', coalesce(nullif(p->>'workstream', ''), 'A10'), v_blk, v_deps,
           v_status, p->>'assignee', p->>'fix_commit', p->>'fix_migration', nullif(p->>'aer_root_cause_ref', ''),
           coalesce((p->>'detected_at')::timestamptz, now()), now())
    returning * into r;
    insert into pipeline.integration_issue_events(issue_id, kind, to_status, actor, note, detail)
    values (r.id, 'detected', r.status, p_actor, left(r.failure, 500), jsonb_build_object('severity', r.severity, 'workstream', r.workstream, 'source', r.detection_source,
            'providers', cardinality(v_prov), 'courses', cardinality(v_course), 'evidence', r.evidence));
    return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', 'created', 'status', r.status, 'severity', r.severity);
  end if;

  select coalesce(array_agg(x), '{}') into v_new_prov from unnest(v_prov) x where not x = any(r.provider_ids);
  select coalesce(array_agg(x), '{}') into v_new_course from unnest(v_course) x where not x = any(r.course_ids);
  v_more := r.entities_truncated or cardinality(r.provider_ids) + cardinality(v_new_prov) > v_max or cardinality(r.course_ids) + cardinality(v_new_course) > v_max;

  if r.status = 'closed' then
    -- §5: the same issue after closure reopens the original row as a regression
    update pipeline.integration_issues i set status = 'reopened', regression_count = i.regression_count + 1, reopened_at = now(), retry_count = i.retry_count + 1,
           last_observed_at = now(), condition_cleared_at = null, verification_outcome = 'regressed',
           severity = case when v_sev < i.severity then v_sev else i.severity end,
           provider_ids = (i.provider_ids || v_new_prov)[1:v_max], course_ids = (i.course_ids || v_new_course)[1:v_max], entities_truncated = v_more,
           country_codes = (select coalesce(array_agg(distinct c), '{}') from unnest(i.country_codes || v_cc) c),
           evidence = i.evidence || coalesce(p->'evidence', '{}'::jsonb), evidence_refs = (select coalesce(array_agg(distinct e), '{}') from unnest(i.evidence_refs || v_refs) e),
           updated_at = now()
     where i.id = r.id returning * into r;
    insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
    values (r.id, 'reopened_regression', 'closed', 'reopened', p_actor, left(coalesce(p->>'failure', r.failure), 500),
            jsonb_build_object('regression_count', r.regression_count, 'evidence', coalesce(p->'evidence', '{}'::jsonb), 'new_providers', cardinality(v_new_prov), 'new_courses', cardinality(v_new_course)));
    return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', 'reopened', 'status', r.status, 'severity', r.severity, 'regression_count', r.regression_count);
  end if;

  v_action := case when v_sev < r.severity then 'escalated' when cardinality(v_new_prov) + cardinality(v_new_course) > 0 then 'observed'
                   when r.condition_cleared_at is not null then 'observed_again' else 'unchanged' end;
  update pipeline.integration_issues i set retry_count = i.retry_count + 1, last_observed_at = now(), condition_cleared_at = null,
         severity = case when v_sev < i.severity then v_sev else i.severity end,
         provider_ids = (i.provider_ids || v_new_prov)[1:v_max], course_ids = (i.course_ids || v_new_course)[1:v_max], entities_truncated = v_more,
         country_codes = case when v_cc <@ i.country_codes then i.country_codes else (select coalesce(array_agg(distinct c), '{}') from unnest(i.country_codes || v_cc) c) end,
         evidence = case when v_action = 'unchanged' then i.evidence else i.evidence || coalesce(p->'evidence', '{}'::jsonb) end,
         updated_at = case when v_action = 'unchanged' then i.updated_at else now() end
   where i.id = r.id returning * into r;
  if v_action <> 'unchanged' then
    insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
    values (r.id, v_action, r.status, r.status, p_actor, null, jsonb_build_object('severity', r.severity, 'new_providers', cardinality(v_new_prov), 'new_courses', cardinality(v_new_course),
            'evidence', coalesce(p->'evidence', '{}'::jsonb)));
  end if;
  return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'action', v_action, 'status', r.status, 'severity', r.severity, 'retry_count', r.retry_count);
end $function$;
revoke all on function security.integration_issue_upsert_v1(jsonb, text) from public, anon, authenticated;
comment on function security.integration_issue_upsert_v1(jsonb, text) is 'CF-247 mandate §3/§5: create or update an integration issue by fingerprint; unchanged problems are not duplicated; a recurrence after Closed reopens as a regression';

create or replace function security.integration_issue_transition_v1(p_issue bigint, p_to text, p_actor text, p_note text default null, p_patch jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate §3 lifecycle: Detected -> Triaged -> Assigned -> In progress -> Code ready -> Integration testing -> Deployed -> Production
-- verification -> Closed (Closed only through security.integration_issue_close_v1). Failed validation returns the issue to In progress or Triaged
-- and must carry the new evidence (p_note). The Integration Controller path only (not granted to any client role).
declare r pipeline.integration_issues; v_from text;
        v_next jsonb := '{"detected": ["triaged", "assigned", "in_progress"], "triaged": ["assigned", "in_progress"], "assigned": ["in_progress", "triaged"],
                          "in_progress": ["code_ready", "triaged", "assigned"], "code_ready": ["integration_testing", "in_progress"],
                          "integration_testing": ["deployed", "in_progress", "triaged"], "deployed": ["production_verification", "in_progress", "triaged"],
                          "production_verification": ["in_progress", "triaged"], "reopened": ["triaged", "assigned", "in_progress"]}'::jsonb;
begin
  if coalesce(btrim(p_actor), '') = '' then raise exception 'name who is changing the issue' using errcode = '22023'; end if;
  select * into r from pipeline.integration_issues where id = p_issue for update;
  if not found then raise exception 'no integration issue %', p_issue using errcode = 'P0002'; end if;
  v_from := r.status;
  if p_to = 'closed' then raise exception 'an issue is closed only with verification evidence (security.integration_issue_close_v1)' using errcode = '22023'; end if;
  if p_to is not null and p_to <> v_from then
    if not coalesce(v_next->v_from ? p_to, false) then raise exception 'an issue cannot move from % to %', v_from, p_to using errcode = '22023'; end if;
    if p_to in ('in_progress', 'triaged') and v_from in ('code_ready', 'integration_testing', 'deployed', 'production_verification') and length(btrim(coalesce(p_note, ''))) < 10 then
      raise exception 'failed validation returns the issue with its new evidence: describe what failed' using errcode = '22023';
    end if;
  end if;
  if p_patch ? 'severity' and p_patch->>'severity' not in ('P0', 'P1', 'P2') then raise exception 'severity must be P0, P1 or P2' using errcode = '22023'; end if;
  update pipeline.integration_issues i set
    status = coalesce(nullif(p_to, ''), i.status),
    severity = coalesce(p_patch->>'severity', i.severity), workstream = coalesce(p_patch->>'workstream', i.workstream),
    root_cause_class = coalesce(p_patch->>'root_cause_class', i.root_cause_class), impact = coalesce(p_patch->>'impact', i.impact),
    assignee = coalesce(p_patch->>'assignee', i.assignee), fix_commit = coalesce(p_patch->>'fix_commit', i.fix_commit),
    fix_migration = coalesce(p_patch->>'fix_migration', i.fix_migration), deployed_version = coalesce(p_patch->>'deployed_version', i.deployed_version),
    aer_root_cause_ref = coalesce(nullif(p_patch->>'aer_root_cause_ref', ''), i.aer_root_cause_ref),
    blocked_by = case when p_patch ? 'blocked_by' then coalesce((select array_agg(x::bigint) from jsonb_array_elements_text(p_patch->'blocked_by') x), '{}') else i.blocked_by end,
    depends_on = case when p_patch ? 'depends_on' then coalesce((select array_agg(x) from jsonb_array_elements_text(p_patch->'depends_on') x), '{}') else i.depends_on end,
    evidence = i.evidence || coalesce(p_patch->'evidence', '{}'::jsonb),
    verification_outcome = case when p_to in ('in_progress', 'triaged') and v_from in ('integration_testing', 'deployed', 'production_verification') then 'failed' else i.verification_outcome end,
    updated_at = now()
   where i.id = p_issue returning * into r;
  insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
  values (r.id, case when r.status <> v_from then 'status' else 'updated' end, v_from, r.status, p_actor, p_note, coalesce(p_patch, '{}'::jsonb));
  return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'from', v_from, 'status', r.status);
end $function$;
revoke all on function security.integration_issue_transition_v1(bigint, text, text, text, jsonb) from public, anon, authenticated;

create or replace function security.integration_issue_close_v1(p_issue bigint, p_actor text, p_verification jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate §3/§5 step 13: an issue closes only after its original failed production condition has been verified. Refused unless the
-- verification says passed, names what was checked (evidence, at least a sentence) and when or where (checked_at or a reference).
declare r pipeline.integration_issues; v_from text;
begin
  if coalesce(btrim(p_actor), '') = '' then raise exception 'name who verified the fix' using errcode = '22023'; end if;
  if p_verification is null or jsonb_typeof(p_verification) <> 'object' or coalesce(p_verification->>'outcome', '') <> 'passed'
     or length(btrim(coalesce(p_verification->>'evidence', ''))) < 20
     or (coalesce(p_verification->>'checked_at', '') = '' and coalesce(p_verification->>'reference', '') = '') then
    raise exception 'closing needs production verification evidence: outcome passed, what was checked (evidence) and when or where (checked_at or reference)' using errcode = '22023';
  end if;
  select * into r from pipeline.integration_issues where id = p_issue for update;
  if not found then raise exception 'no integration issue %', p_issue using errcode = 'P0002'; end if;
  if r.status = 'closed' then return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'status', 'closed', 'already', true); end if;
  v_from := r.status;
  update pipeline.integration_issues i set status = 'closed', closed_at = now(), verification_outcome = 'passed', verification_evidence = p_verification,
         verified_at = coalesce((p_verification->>'checked_at')::timestamptz, now()), verified_by = p_actor, updated_at = now()
   where i.id = p_issue returning * into r;
  insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note, detail)
  values (r.id, 'closed', v_from, 'closed', p_actor, left(p_verification->>'evidence', 500), p_verification);
  -- a P0 alert issue still open on Platform health closes with it (platform-alerts sends the one recovery notice)
  if r.alert_check_key is not null then
    update pipeline.platform_issues set resolved_at = now() where check_key = r.alert_check_key and resolved_at is null;
    if found then insert into pipeline.integration_issue_events(issue_id, kind, actor, note) values (r.id, 'alert_resolved', p_actor, 'closed'); end if;
  end if;
  return jsonb_build_object('id', r.id, 'issue_ref', r.issue_ref, 'status', 'closed', 'from', v_from);
end $function$;
revoke all on function security.integration_issue_close_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.integration_mode_set_v1(p_mode int, p_controller text, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate §13: only the Integration Controller changes the operating mode (this function is not granted to any client role). Mode 2 is
-- entered only on declared acceptance, so it is refused while any P0 or P1 integration issue is open (§11 completion gate, item 9).
declare v_old int; v_open int;
begin
  if p_mode not in (1, 2) then raise exception 'the operating mode is 1 (Active Remediation) or 2 (Steady-State Monitoring)' using errcode = '22023'; end if;
  if length(btrim(coalesce(p_controller, ''))) < 3 or length(btrim(coalesce(p_reason, ''))) < 10 then
    raise exception 'name the Integration Controller and give the reason (kept in the audit log)' using errcode = '22023';
  end if;
  select mode into v_old from pipeline.integration_operating_mode where id = 1 for update;
  if p_mode = 2 then
    select count(*) into v_open from pipeline.integration_issues where status <> 'closed' and severity in ('P0', 'P1');
    if v_open > 0 then raise exception 'Mode 2 needs programme acceptance: % P0/P1 integration issue(s) are still open', v_open using errcode = '22023'; end if;
  end if;
  perform set_config('cf247.integration_mode_path', 'on', true);
  insert into pipeline.integration_operating_mode as m(id, mode, set_by, set_at, reason) values (1, p_mode, p_controller, now(), p_reason)
  on conflict (id) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = excluded.set_at, reason = excluded.reason;
  perform set_config('cf247.integration_mode_path', '', true);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('integration', 'operating_mode', 'pipeline.integration_operating_mode', jsonb_build_object('from', v_old, 'to', p_mode, 'set_by', p_controller, 'reason', p_reason), null);
  return jsonb_build_object('from', v_old, 'mode', p_mode, 'set_by', p_controller);
end $function$;
revoke all on function security.integration_mode_set_v1(int, text, text) from public, anon, authenticated;

-- P0 alerts through the existing deduplicated path: one Platform health issue per P0 fingerprint while its condition is observed
create or replace function security.integration_alert_sync_v1(p_issue bigint, p_observed boolean, p_actor text default 'integration-validate') returns void
language plpgsql security definer set search_path to '' as $function$
declare r pipeline.integration_issues; v_key text;
begin
  select * into r from pipeline.integration_issues where id = p_issue;
  if not found then return; end if;
  v_key := 'integration:' || left(r.fingerprint, 200);
  if p_observed and r.severity = 'P0' and r.status <> 'closed' then
    insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
    values (v_key, 'critical', 'integration', left(r.issue_ref || ' ' || r.title, 300),
            jsonb_build_object('issue', r.issue_ref, 'fingerprint', r.fingerprint, 'workstream', r.workstream, 'next_step', left(r.expected, 300),
                               'resolve', 'Platform health › Integration queue'))
    on conflict (check_key) where resolved_at is null do update set last_seen = now(), occurrences = i.occurrences + 1;
    if r.alert_check_key is null then
      update pipeline.integration_issues set alert_check_key = v_key where id = r.id;
      insert into pipeline.integration_issue_events(issue_id, kind, actor, note) values (r.id, 'alert_opened', p_actor, v_key);
    end if;
  elsif r.alert_check_key is not null then
    update pipeline.platform_issues set resolved_at = now() where check_key = r.alert_check_key and resolved_at is null;
    if found then insert into pipeline.integration_issue_events(issue_id, kind, actor, note) values (r.id, 'alert_resolved', p_actor, 'condition no longer observed'); end if;
  end if;
end $function$;
revoke all on function security.integration_alert_sync_v1(bigint, boolean, text) from public, anon, authenticated;

-- the pending Layer 4 items the checks examine: newest first, bounded (index status, created_at)
create or replace function security.integration_l4_pending_v1(p_max int) returns table(id uuid, entity_type text, entity_id uuid, field_code text, proposed_value jsonb, created_at timestamptz)
language sql stable security definer set search_path to '' as $function$
  select i.id, i.entity_type, i.entity_id, i.field_code, i.proposed_value, i.created_at from pipeline.layer4_review_items i
   where i.status = 'pending' order by i.created_at desc limit p_max
$function$;
revoke all on function security.integration_l4_pending_v1(int) from public, anon, authenticated;

-- 4. V4: continuous production validation ------------------------------------------------------------------------------------------------
create or replace function security.integration_validate_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate §4 V4, §6, §7 (job integration-validate). Keyed, incremental checks only; each finding feeds the queue by fingerprint. A check
-- that ran and no longer sees a fingerprint marks its open issue "condition cleared" (the issue still closes only with verification).
declare v_t0 timestamptz := clock_timestamp(); v_ok text[] := '{}'; v_seen text[] := '{}'; v_out jsonb := '{}'::jsonb; v_err jsonb := '{}'::jsonb;
        v_scan int := security.pipeline_num_v1('integration.failed_runs_scan', 5000)::int;
        v_back interval := make_interval(hours => security.pipeline_num_v1('integration.first_run_lookback_hours', 24)::int);
        v_lease interval := make_interval(mins => security.pipeline_num_v1('integration.lease_stale_minutes', 60)::int);
        v_draft interval := make_interval(hours => security.pipeline_num_v1('integration.draft_stuck_hours', 24)::int);
        v_l4max int := security.pipeline_num_v1('integration.l4_pending_max', 5000)::int;
        v_inmax int := security.pipeline_num_v1('integration.inactive_courses_max', 20000)::int;
        s pipeline.integration_validate_state; r record; v_n bigint; v_m bigint; v_id bigint; v_ts timestamptz; v_res jsonb; v_num numeric; v_num2 numeric;
        v_pend int := 0; v_trunc boolean := false; v_res2 jsonb;
begin
  -- 0. Platform health and queue-watch output: their open issues (not this queue's own P0 rows) ----------------------------------------
  begin
    v_n := 0;
    for r in select p.check_key, p.severity, p.area, p.title, p.detail, p.first_seen from pipeline.platform_issues p
              where p.resolved_at is null and p.severity in ('critical', 'warning') and p.check_key not like 'integration:%' loop
      v_res := security.integration_issue_upsert_v1(jsonb_build_object(
        'fingerprint', case when r.check_key like 'cron:failed:%' then 'job_failed:' || substr(r.check_key, 13) else 'health:' || r.check_key end,
        'title', r.title, 'layer', case when r.area in ('scheduled jobs', 'edge functions') then 'Scheduling' when r.area = 'search/API' then 'Search/API'
                                        when r.area in ('coverage sweep', 'scholarships') then 'Layer 2' else 'Platform' end,
        'subsystem', r.area, 'failure', r.title, 'expected', coalesce(r.detail->>'next_step', 'The Platform health check passes'),
        'source', case when r.check_key like 'queue_watch%' then 'queue-watch' else 'platform-health' end, 'validation_layer', 'V4',
        'evidence', jsonb_build_object('platform_issue', r.check_key, 'first_seen', r.first_seen, 'detail', r.detail),
        'severity', case r.severity when 'critical' then 'P1' else 'P2' end, 'root_cause_class', 'unclassified',
        'workstream', case when r.check_key like 'queue_watch%' or r.area in ('scheduled jobs', 'edge functions') then 'A7' when r.area = 'search/API' then 'A8'
                           when r.area in ('coverage sweep', 'scholarships') then 'A2' else 'A9' end), 'integration-validate');
      v_seen := v_seen || (case when r.check_key like 'cron:failed:%' then 'job_failed:' || substr(r.check_key, 13) else 'health:' || r.check_key end);
      v_n := v_n + 1;
    end loop;
    v_ok := v_ok || 'health'::text; v_out := v_out || jsonb_build_object('health', v_n);
  exception when others then v_err := v_err || jsonb_build_object('health', left(sqlerrm, 300));
  end;

  -- 1. failed job runs, newer than the last run looked at (newest runs only) ------------------------------------------------------------
  begin
    select * into s from pipeline.integration_validate_state where check_key = 'job_failed';
    v_m := null; v_n := 0;
    for r in with d as (select x.runid, x.jobid, x.status, x.start_time, x.return_message from cron.job_run_details x order by x.runid desc limit v_scan)
             select j.jobname, count(*) n, max(d.runid) last_runid, max(d.start_time) last_at, (array_agg(left(d.return_message, 300) order by d.runid desc))[1] msg
               from d join cron.job j on j.jobid = d.jobid
              where d.status = 'failed' and d.runid > coalesce(s.watermark_id, 0) and (s.watermark_id is not null or d.start_time >= now() - v_back)
              group by j.jobname loop
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'job_failed:' || r.jobname,
        'title', 'Scheduled job ' || r.jobname || ' has failed runs', 'layer', 'Scheduling', 'subsystem', 'cron', 'failure', r.n || ' failed run(s) of ' || r.jobname || ', the last at ' || r.last_at || ': ' || coalesce(r.msg, 'no message'),
        'expected', 'Every run of an active scheduled job succeeds (target T1: 0 failed runs a day)', 'source', 'integration-validate', 'validation_layer', 'V4',
        'evidence', jsonb_build_object('failed_runs', r.n, 'last_runid', r.last_runid, 'last_at', r.last_at, 'message', r.msg), 'severity', 'P1',
        'root_cause_class', 'unclassified', 'workstream', 'A7'), 'integration-validate');
      v_seen := v_seen || ('job_failed:' || r.jobname); v_n := v_n + 1;
    end loop;
    select max(x.runid) into v_m from (select runid from cron.job_run_details order by runid desc limit 1) x;
    insert into pipeline.integration_validate_state as t(check_key, last_run_at, watermark_id, last_found) values ('job_failed', now(), v_m, v_n)
    on conflict (check_key) do update set last_run_at = now(), watermark_id = coalesce(excluded.watermark_id, t.watermark_id), last_found = excluded.last_found, last_error = null;
    v_ok := v_ok || 'job_failed'::text; v_out := v_out || jsonb_build_object('job_failed', v_n);
  exception when others then v_err := v_err || jsonb_build_object('job_failed', left(sqlerrm, 300));
  end;

  -- 2. stale leases in the watched work tables ------------------------------------------------------------------------------------------
  begin
    v_n := 0;
    for r in select w.* from pipeline.integration_lease_watch w loop
      begin
        execute format('select count(*), min(%1$I) from %2$s where %3$s and %1$I < now() - $1', r.lease_column, r.table_name, r.leased_predicate) into v_m, v_ts using v_lease;
      exception when others then
        v_err := v_err || jsonb_build_object('stale_lease:' || r.table_name, left(sqlerrm, 200)); v_m := 0;
        v_seen := v_seen || ('stale_lease:' || r.table_name);  -- not read: its open issue is not taken as cleared
      end;
      if v_m > 0 then
        perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'stale_lease:' || r.table_name,
          'title', 'Stale leases in ' || r.table_name, 'layer', 'Scheduling', 'subsystem', r.table_name,
          'failure', v_m || ' item(s) still leased more than ' || security.pipeline_num_v1('integration.lease_stale_minutes', 60) || ' minutes after the lease ended (oldest lease end ' || v_ts || ')',
          'expected', 'An expired lease is reclaimed by the next claim or released', 'source', 'integration-validate', 'validation_layer', 'V4',
          'evidence', jsonb_build_object('items', v_m, 'oldest_lease_end', v_ts, 'predicate', r.leased_predicate), 'severity', 'P1', 'root_cause_class', 'queue_or_lease',
          'workstream', r.workstream), 'integration-validate');
        v_seen := v_seen || ('stale_lease:' || r.table_name); v_n := v_n + 1;
      end if;
    end loop;
    v_ok := v_ok || 'stale_lease'::text; v_out := v_out || jsonb_build_object('stale_lease', v_n);
  exception when others then v_err := v_err || jsonb_build_object('stale_lease', left(sqlerrm, 300));
  end;

  -- 3. adapter drafts stuck in capture or proposal ----------------------------------------------------------------------------------
  begin
    v_n := 0;
    for r in select d.status, count(*) n, array_agg(distinct d.provider_id) prov, min(d.updated_at) oldest
               from pipeline.uni_adapter_drafts d where d.status in ('capturing', 'proposing') and d.updated_at < now() - v_draft group by d.status loop
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'draft_stuck:' || r.status,
        'title', 'Adapter drafts stuck in ' || r.status, 'layer', 'Adapters', 'subsystem', 'pipeline.uni_adapter_drafts',
        'failure', r.n || ' draft(s) in ' || r.status || ' unchanged since ' || r.oldest, 'expected', 'A draft moves on from ' || r.status || ' (captured, proposed or error) within '
          || security.pipeline_num_v1('integration.draft_stuck_hours', 24) || ' hours',
        'source', 'integration-validate', 'validation_layer', 'V4', 'provider_ids', to_jsonb(r.prov), 'evidence', jsonb_build_object('drafts', r.n, 'oldest_update', r.oldest),
        'severity', 'P2', 'root_cause_class', 'queue_or_lease', 'workstream', 'A3'), 'integration-validate');
      v_seen := v_seen || ('draft_stuck:' || r.status); v_n := v_n + 1;
    end loop;
    v_ok := v_ok || 'draft_stuck'::text; v_out := v_out || jsonb_build_object('draft_stuck', v_n);
  exception when others then v_err := v_err || jsonb_build_object('draft_stuck', left(sqlerrm, 300));
  end;

  -- 4-6, 9. Layer 4: pending items (newest first, bounded) -----------------------------------------------------------------------------
  begin
    select count(*) into v_pend from security.integration_l4_pending_v1(v_l4max);
    v_trunc := v_pend >= v_l4max;
    -- duplicates: more than one pending item for the same entity and field
    v_n := 0;
    for r in select p.field_code, count(*) groups, sum(p.n) items, array_agg(p.entity_id) ents, bool_or(p.entity_type = 'course') is_course
               from (select entity_type, entity_id, field_code, count(*) n from security.integration_l4_pending_v1(v_l4max) group by 1, 2, 3 having count(*) > 1) p group by p.field_code loop
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'l4_duplicate:' || r.field_code,
        'title', 'Duplicate pending Layer 4 items (' || r.field_code || ')', 'layer', 'Layer 4', 'subsystem', 'pipeline.layer4_review_items',
        'failure', r.items || ' pending items in ' || r.groups || ' group(s) share the same entity and field', 'expected', 'At most one pending item per entity and field',
        'source', 'integration-validate', 'validation_layer', 'V4', 'course_ids', case when r.is_course then to_jsonb(r.ents) else '[]'::jsonb end,
        'provider_ids', case when r.is_course then '[]'::jsonb else to_jsonb(r.ents) end,
        'evidence', jsonb_build_object('groups', r.groups, 'items', r.items, 'pending_examined', v_pend, 'partly_checked', v_trunc), 'severity', 'P1', 'root_cause_class', 'code_defect', 'workstream', 'A4'), 'integration-validate');
      v_seen := v_seen || ('l4_duplicate:' || r.field_code); v_n := v_n + 1;
    end loop;
    v_out := v_out || jsonb_build_object('l4_duplicate', v_n);
    -- orphans: the entity is gone, not active, or belongs to an archived provider
    v_n := 0;
    for r in select p.field_code, count(*) n, array_agg(p.entity_id) filter (where p.entity_type = 'course') courses,
                    array_agg(coalesce(c.provider_id, p.entity_id)) filter (where pr.id is not null or p.entity_type = 'provider') provs
               from security.integration_l4_pending_v1(v_l4max) p
               left join catalogue.courses c on p.entity_type = 'course' and c.id = p.entity_id
               left join catalogue.providers pr on pr.id = case when p.entity_type = 'course' then c.provider_id when p.entity_type = 'provider' then p.entity_id end
              where (p.entity_type = 'course' and (c.id is null or c.lifecycle_status is distinct from 'active' or pr.lifecycle_status is distinct from 'active'))
                 or (p.entity_type = 'provider' and (pr.id is null or pr.lifecycle_status is distinct from 'active'))
              group by p.field_code loop
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'l4_orphan:' || r.field_code,
        'title', 'Orphan pending Layer 4 items (' || r.field_code || ')', 'layer', 'Layer 4', 'subsystem', 'pipeline.layer4_review_items',
        'failure', r.n || ' pending item(s) whose course or provider is missing, not active or archived', 'expected', 'Retirement supersedes the pending items of retired entities (§6, §7)',
        'source', 'integration-validate', 'validation_layer', 'V4', 'course_ids', coalesce(to_jsonb(r.courses), '[]'::jsonb), 'provider_ids', coalesce(to_jsonb(r.provs), '[]'::jsonb),
        'evidence', jsonb_build_object('items', r.n, 'pending_examined', v_pend, 'partly_checked', v_trunc), 'severity', 'P1', 'root_cause_class', 'lifecycle_leak', 'workstream', 'A5'), 'integration-validate');
      v_seen := v_seen || ('l4_orphan:' || r.field_code); v_n := v_n + 1;
    end loop;
    v_out := v_out || jsonb_build_object('l4_orphan', v_n);
    -- regenerated: a pending item proposing what was already decided for the same entity and field (keyed by the new index)
    v_n := 0;
    for r in select p.field_code, count(*) n, array_agg(p.entity_id) ents, bool_or(p.entity_type = 'course') is_course
               from security.integration_l4_pending_v1(v_l4max) p
              where exists (select 1 from pipeline.layer4_review_items d where d.entity_id = p.entity_id and d.field_code = p.field_code and d.status <> 'pending'
                              and d.decided_at is not null and d.decided_at < p.created_at and d.proposed_value is not distinct from p.proposed_value)
              group by p.field_code loop
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'l4_regenerated:' || r.field_code,
        'title', 'Layer 4 items regenerated after a decision (' || r.field_code || ')', 'layer', 'Layer 4', 'subsystem', 'pipeline.layer4_review_items',
        'failure', r.n || ' pending item(s) propose the same value for the same entity and field as an item already decided',
        'expected', 'A decided proposal is not raised again (Decision 263); fix the generator, not the reviews (§10)',
        'source', 'integration-validate', 'validation_layer', 'V4', 'course_ids', case when r.is_course then to_jsonb(r.ents) else '[]'::jsonb end,
        'provider_ids', case when r.is_course then '[]'::jsonb else to_jsonb(r.ents) end,
        'evidence', jsonb_build_object('items', r.n, 'pending_examined', v_pend, 'partly_checked', v_trunc), 'severity', 'P1', 'root_cause_class', 'code_defect', 'workstream', 'A4'), 'integration-validate');
      v_seen := v_seen || ('l4_regenerated:' || r.field_code); v_n := v_n + 1;
    end loop;
    v_out := v_out || jsonb_build_object('l4_regenerated', v_n);
    v_ok := v_ok || array['l4_duplicate', 'l4_orphan', 'l4_regenerated']::text[];
  exception when others then v_err := v_err || jsonb_build_object('layer4', left(sqlerrm, 300));
  end;
  v_out := v_out || jsonb_build_object('pending_examined', v_pend);

  -- 9. (own block) course-url-fill against pending official_course_url items
  begin
    with p as (select q.entity_id, min(q.created_at) first_pending from security.integration_l4_pending_v1(v_l4max) q
                where q.field_code = 'official_course_url' and q.entity_type = 'course' group by q.entity_id)
    select count(*), coalesce(jsonb_agg(f.course_id), '[]'::jsonb), max(f.filled_at) into v_m, v_res, v_ts
      from p join pipeline.course_url_fills f on f.course_id = p.entity_id and f.retracted_at is null and f.filled_at > p.first_pending;
    if v_m > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'course_url_fill:pending_official_course_url',
        'title', 'course-url-fill wrote course_url while an official_course_url Layer 4 item was pending', 'layer', 'Catalogue', 'subsystem', 'security.course_url_fill_v1 (job course-url-fill)',
        'failure', v_m || ' course(s) whose course_url was filled after a pending official_course_url item was raised for them (last fill ' || v_ts || ')',
        'expected', 'course-url-fill skips (or reports) a course with a pending official_course_url item; Layer 4 decides the page',
        'source', 'integration-validate', 'validation_layer', 'V4', 'course_ids', v_res,
        'evidence', jsonb_build_object('courses', v_m, 'last_fill', v_ts, 'found_live', '2 Nov 2026 16:07-16:47, housekeeping disposition §6 (H05 drift)'),
        'evidence_refs', jsonb_build_array('admin docs/platform/nz-enrichment-brief/2026-11-02-housekeeping-disposition.md §6'),
        'severity', 'P1', 'root_cause_class', 'code_defect', 'workstream', 'A2'), 'integration-validate');
      v_seen := v_seen || 'course_url_fill:pending_official_course_url'::text;
    end if;
    v_ok := v_ok || 'course_url_fill'::text; v_out := v_out || jsonb_build_object('course_url_fill', v_m);
  exception when others then v_err := v_err || jsonb_build_object('course_url_fill', left(sqlerrm, 300));
  end;

  -- 7. work (Firecrawl spend) for archived providers, since the last ledger row looked at ------------------------------------------------
  begin
    select * into s from pipeline.integration_validate_state where check_key = 'archived_provider_work';
    select count(*), coalesce(sum(u.units), 0), coalesce(jsonb_agg(distinct u.provider_id), '[]'::jsonb), max(u.id), max(u.at)
      into v_m, v_num, v_res, v_id, v_ts
      from catalogue.providers pr
      join pipeline.coverage_vendor_usage u on u.provider_id = pr.id and u.at >= coalesce(s.watermark_at, now() - v_back) and u.id > coalesce(s.watermark_id, 0)
     where pr.lifecycle_status is distinct from 'active';
    if v_m > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'archived_provider_work:firecrawl',
        'title', 'Firecrawl spent on archived providers', 'layer', 'Layer 2', 'subsystem', 'pipeline.coverage_vendor_usage',
        'failure', v_m || ' Firecrawl call(s), ' || v_num || ' credit(s), for archived providers since the last check',
        'expected', 'No discovery, scraping or reading for an archived provider (§7)', 'source', 'integration-validate', 'validation_layer', 'V4', 'provider_ids', v_res,
        'evidence', jsonb_build_object('calls', v_m, 'credits', v_num, 'last_at', v_ts), 'severity', 'P1', 'root_cause_class', 'lifecycle_leak', 'workstream', 'A5'), 'integration-validate');
      v_seen := v_seen || 'archived_provider_work:firecrawl'::text;
    end if;
    insert into pipeline.integration_validate_state as t(check_key, last_run_at, watermark_id, watermark_at, last_found)
    values ('archived_provider_work', now(), coalesce(v_id, s.watermark_id, (select max(id) from pipeline.coverage_vendor_usage)), now(), v_m)
    on conflict (check_key) do update set last_run_at = now(), watermark_id = excluded.watermark_id, watermark_at = excluded.watermark_at, last_found = excluded.last_found, last_error = null;
    v_ok := v_ok || 'archived_provider_work'::text; v_out := v_out || jsonb_build_object('archived_provider_work', v_m);
  exception when others then v_err := v_err || jsonb_build_object('archived_provider_work', left(sqlerrm, 300));
  end;

  -- 8. archived providers and inactive courses visible in search (the documents the website and Zoho read) --------------------------------
  begin
    select count(*), coalesce(jsonb_agg(distinct d.provider_id), '[]'::jsonb), coalesce(jsonb_agg(d.course_id), '[]'::jsonb)
      into v_m, v_res, v_res2
      from catalogue.providers pr join search.course_documents d on d.provider_id = pr.id and d.publication_status = 'published'
     where pr.lifecycle_status is distinct from 'active';
    if v_m > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'search_leak:archived_provider',
        'title', 'Archived providers'' courses are published in search', 'layer', 'Search/API', 'subsystem', 'search.course_documents',
        'failure', v_m || ' published search document(s) belong to archived providers', 'expected', 'No active consumer search record for an archived provider (§7)',
        'source', 'integration-validate', 'validation_layer', 'V4', 'provider_ids', v_res, 'course_ids', v_res2, 'evidence', jsonb_build_object('documents', v_m),
        'severity', 'P0', 'root_cause_class', 'lifecycle_leak', 'workstream', 'A5'), 'integration-validate');
      v_seen := v_seen || 'search_leak:archived_provider'::text;
    end if;
    v_out := v_out || jsonb_build_object('search_leak_archived_provider', v_m);
    select count(*), coalesce(jsonb_agg(d.course_id), '[]'::jsonb), coalesce(jsonb_agg(distinct d.provider_id), '[]'::jsonb) into v_m, v_res, v_res2
      from (select c.id from catalogue.courses c where c.lifecycle_status is distinct from 'active' limit v_inmax) c
      join search.course_documents d on d.course_id = c.id and d.publication_status = 'published';
    if v_m > 0 then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'search_leak:inactive_course',
        'title', 'Courses that are not active are published in search', 'layer', 'Search/API', 'subsystem', 'search.course_documents',
        'failure', v_m || ' published search document(s) belong to courses that are not active', 'expected', 'Retired or inactive courses leave search at the next refresh',
        'source', 'integration-validate', 'validation_layer', 'V4', 'course_ids', v_res, 'provider_ids', v_res2, 'evidence', jsonb_build_object('documents', v_m),
        'severity', 'P0', 'root_cause_class', 'lifecycle_leak', 'workstream', 'A8'), 'integration-validate');
      v_seen := v_seen || 'search_leak:inactive_course'::text;
    end if;
    v_ok := v_ok || 'search_leak'::text; v_out := v_out || jsonb_build_object('search_leak_inactive_course', v_m);
  exception when others then v_err := v_err || jsonb_build_object('search_leak', left(sqlerrm, 300));
  end;

  -- 10. unexpected Firecrawl or AI spend: today's ledgers against the settings ---------------------------------------------------------
  begin
    v_num := security.fc_billed_today_v1();
    if coalesce((security.toolset_setting('firecrawl', 'daily_budget_on') #>> '{}')::boolean, false)
       and v_num > security.fc_setting_num_v1('daily_budget_total', 25000) then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'spend:firecrawl_day',
        'title', 'Firecrawl spend above the daily budget', 'layer', 'Platform', 'subsystem', 'pipeline.coverage_vendor_usage',
        'failure', v_num || ' credits billed today against a daily budget of ' || security.fc_setting_num_v1('daily_budget_total', 25000),
        'expected', 'Billed credits stay within the daily budget while it is on', 'source', 'integration-validate', 'validation_layer', 'V4',
        'evidence', jsonb_build_object('billed_today', v_num, 'budget', security.fc_setting_num_v1('daily_budget_total', 25000)), 'severity', 'P1', 'root_cause_class', 'budget', 'workstream', 'A7'), 'integration-validate');
      v_seen := v_seen || 'spend:firecrawl_day'::text;
    end if;
    select coalesce(sum(t.spent), 0) into v_num2 from security.ai_spend_today_v1() t;
    if v_num2 > security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then
      perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'spend:ai_day',
        'title', 'AI spend above the daily ceiling', 'layer', 'Platform', 'subsystem', 'pipeline.ai_spend_ledger',
        'failure', 'US$' || round(v_num2, 2) || ' spent today against a ceiling of US$' || security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14),
        'expected', 'AI spend stays within budgets.ai_daily_ceiling_usd', 'source', 'integration-validate', 'validation_layer', 'V4',
        'evidence', jsonb_build_object('spent_today_usd', v_num2, 'ceiling_usd', security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14)), 'severity', 'P1', 'root_cause_class', 'budget', 'workstream', 'A7'), 'integration-validate');
      v_seen := v_seen || 'spend:ai_day'::text;
    end if;
    v_ok := v_ok || 'spend'::text; v_out := v_out || jsonb_build_object('firecrawl_today', v_num, 'ai_today_usd', v_num2);
  exception when others then v_err := v_err || jsonb_build_object('spend', left(sqlerrm, 300));
  end;

  -- 11. condition cleared / alerts: open issues of the checks that ran ---------------------------------------------------------------
  for r in select i.id, i.fingerprint, i.condition_cleared_at, i.status from pipeline.integration_issues i
            where i.status <> 'closed' and split_part(i.fingerprint, ':', 1) = any (v_ok) loop
    if r.fingerprint = any (v_seen) then
      perform security.integration_alert_sync_v1(r.id, true);
    else
      if r.condition_cleared_at is null then
        update pipeline.integration_issues set condition_cleared_at = now() where id = r.id;
        insert into pipeline.integration_issue_events(issue_id, kind, from_status, to_status, actor, note)
        values (r.id, 'not_observed', r.status, r.status, 'integration-validate', 'condition no longer observed; close after production verification');
      end if;
      perform security.integration_alert_sync_v1(r.id, false);
    end if;
  end loop;

  v_out := v_out || jsonb_build_object('ran', to_jsonb(v_ok), 'errors', v_err, 'observed', cardinality(v_seen), 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  insert into pipeline.integration_validate_state as t(check_key, last_run_at, last_found, last_ms, last_error, detail)
  values ('run', now(), cardinality(v_seen), round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int, nullif(v_err::text, '{}'), v_out)
  on conflict (check_key) do update set last_run_at = now(), last_found = excluded.last_found, last_ms = excluded.last_ms, last_error = excluded.last_error, detail = excluded.detail;
  return v_out;
end $function$;
revoke all on function security.integration_validate_v1() from public, anon, authenticated;
comment on function security.integration_validate_v1() is 'CF-247 mandate §4 V4 (job integration-validate): Platform health and queue-watch output, failed job runs, stale leases, stuck adapter drafts, Layer 4 duplicates, orphans and regenerations, course-url-fill against pending official_course_url items, work for archived providers, archived or inactive records in search, spend against settings; each feeds the integration queue by fingerprint; P0 through the existing platform-alerts path';

-- 5. V3: deployment validation, called by the release controller after each deploy -------------------------------------------------------
create or replace function security.integration_deploy_check_v1(p_release text, p_migrations jsonb, p_functions jsonb default '{}'::jsonb,
                                                               p_since timestamptz default null, p_jobs text[] default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate §4 V3. p_migrations: [{"version": "20261102120000", "md5": "<md5 of the migration file>"}, ...]; the applied statements are
-- compared with the file (the statements of a migration applied whole are the file text, so their md5 is the file's md5; the md5 of the file with
-- carriage returns and trailing newlines removed is accepted too). p_functions:
-- {"schema.name(argtypes)": "<expected md5 of pg_get_functiondef>"}. Job compatibility: every function an active job's command calls exists
-- (p_jobs limits the jobs looked at). Errors since the deploy (p_since): failed scheduler runs among the newest runs and failed HTTP calls.
-- Each mismatch opens or updates an integration issue by fingerprint (V3, workstream A8 or A7). The result is kept in
-- pipeline.integration_deploy_checks. Reads only; the Integration Controller path only.
declare v_since timestamptz := coalesce(p_since, now() - interval '30 minutes');  -- fixed: default window when the caller gives no deploy time
        v_scan int := security.pipeline_num_v1('integration.failed_runs_scan', 5000)::int;
        m record; f record; j record; v_live text; v_norm text; v_mig jsonb := '[]'::jsonb; v_fn jsonb := '[]'::jsonb; v_jobs jsonb := '[]'::jsonb;
        v_fail jsonb; v_http int := 0; v_ok boolean := true; v_issues text[] := '{}'; v_res jsonb; v_missing text[]; v_n int;
begin
  if coalesce(btrim(p_release), '') = '' then raise exception 'name the release' using errcode = '22023'; end if;
  -- migrations: applied, and the applied text is the file
  for m in select x->>'version' version, x->>'md5' md5 from jsonb_array_elements(coalesce(p_migrations, '[]'::jsonb)) x loop
    -- the raw text, and the text with carriage returns and trailing newlines removed (SS-015 Gate A F7: 11 versions differ only in those)
    select md5(array_to_string(s.statements, '')), md5(rtrim(replace(array_to_string(s.statements, ''), E'\r', ''), E'\n')) into v_live, v_norm
      from supabase_migrations.schema_migrations s where s.version = m.version;
    v_mig := v_mig || jsonb_build_object('version', m.version, 'expected', m.md5, 'live', v_live, 'live_normalised', v_norm,
                                         'ok', v_live is not null and m.md5 in (v_live, v_norm));
    if v_live is null or m.md5 not in (v_live, v_norm) then
      v_ok := false;
      v_res := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'v3_migration:' || m.version,
        'title', 'Migration ' || m.version || ' ' || case when v_live is null then 'is not applied' else 'differs from its file' end, 'layer', 'Release',
        'subsystem', 'supabase_migrations.schema_migrations', 'failure', case when v_live is null then 'not in the applied migrations' else 'applied md5 ' || v_live || ', file md5 ' || m.md5 end,
        'expected', 'The deployed migration is the reviewed file, byte for byte', 'source', 'release ' || p_release, 'validation_layer', 'V3',
        'evidence', jsonb_build_object('release', p_release, 'version', m.version, 'expected', m.md5, 'live', v_live), 'severity', 'P1',
        'root_cause_class', 'deployment_drift', 'workstream', 'A8'), 'release controller');
      v_issues := v_issues || (v_res->>'issue_ref');
    end if;
  end loop;
  -- functions: live definition md5 against the expected one
  for f in select e.key sig, e.value #>> '{}' md5 from jsonb_each(coalesce(p_functions, '{}'::jsonb)) e loop
    v_live := null;
    begin v_live := md5(pg_get_functiondef(f.sig::regprocedure)); exception when others then v_live := null; end;
    v_fn := v_fn || jsonb_build_object('function', f.sig, 'expected', f.md5, 'live', v_live, 'ok', v_live is not null and v_live = f.md5);
    if v_live is null or v_live <> f.md5 then
      v_ok := false;
      v_res := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'v3_function:' || f.sig,
        'title', 'Function ' || f.sig || ' ' || case when v_live is null then 'is missing' else 'differs from the release' end, 'layer', 'Release', 'subsystem', f.sig,
        'failure', case when v_live is null then 'not found live' else 'live md5 ' || v_live || ', expected ' || f.md5 end,
        'expected', 'The live definition is the one the release built and tested', 'source', 'release ' || p_release, 'validation_layer', 'V3',
        'evidence', jsonb_build_object('release', p_release, 'expected', f.md5, 'live', v_live), 'severity', 'P1', 'root_cause_class', 'deployment_drift', 'workstream', 'A8'), 'release controller');
      v_issues := v_issues || (v_res->>'issue_ref');
    end if;
  end loop;
  -- scheduled job compatibility: every function a job calls exists (by schema and name)
  for j in select c.jobname, c.command from cron.job c where c.active and (p_jobs is null or c.jobname = any (p_jobs)) loop
    select coalesce(array_agg(distinct x[1] || '.' || x[2]), '{}') into v_missing
      from regexp_matches(j.command, '([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(', 'g') x
     where x[1] not in ('cron', 'net', 'pg_catalog', 'extensions', 'vault')
       and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = x[1] and p.proname = x[2]);
    if cardinality(v_missing) > 0 then
      v_ok := false;
      v_jobs := v_jobs || jsonb_build_object('job', j.jobname, 'missing', to_jsonb(v_missing));
      v_res := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'v3_job:' || j.jobname,
        'title', 'Scheduled job ' || j.jobname || ' calls a function that does not exist', 'layer', 'Scheduling', 'subsystem', 'cron',
        'failure', 'missing: ' || array_to_string(v_missing, ', '), 'expected', 'Every active job calls functions that exist after the deploy',
        'source', 'release ' || p_release, 'validation_layer', 'V3', 'evidence', jsonb_build_object('release', p_release, 'missing', to_jsonb(v_missing)),
        'severity', 'P1', 'root_cause_class', 'deployment_drift', 'workstream', 'A7'), 'release controller');
      v_issues := v_issues || (v_res->>'issue_ref');
    end if;
  end loop;
  -- errors since the deploy
  select coalesce(jsonb_object_agg(x.jobname, x.n), '{}'::jsonb) into v_fail
    from (select c.jobname, count(*) n from (select d.jobid, d.status, d.start_time from cron.job_run_details d order by d.runid desc limit v_scan) d
            join cron.job c on c.jobid = d.jobid where d.status = 'failed' and d.start_time >= v_since group by c.jobname) x;
  begin
    execute 'select count(*) from net._http_response h where h.created >= $1 and (h.status_code >= 500 or h.timed_out or h.error_msg is not null)' into v_http using v_since;
  exception when others then v_http := null;
  end;
  select coalesce(sum(e.value::int), 0) into v_n from jsonb_each_text(v_fail) e;
  if v_n > 0 or coalesce(v_http, 0) > 0 then
    v_ok := false;
    v_res := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'v3_errors:' || p_release,
      'title', 'Errors after release ' || p_release, 'layer', 'Release', 'subsystem', 'cron and pg_net',
      'failure', v_n || ' failed scheduler run(s) and ' || coalesce(v_http::text, 'unknown') || ' failed HTTP call(s) since ' || v_since,
      'expected', 'No new failures after a deploy', 'source', 'release ' || p_release, 'validation_layer', 'V3',
      'evidence', jsonb_build_object('release', p_release, 'since', v_since, 'failed_runs', v_fail, 'http_errors', v_http), 'severity', 'P2',
      'root_cause_class', 'unclassified', 'workstream', 'A7'), 'release controller');
    v_issues := v_issues || (v_res->>'issue_ref');
  end if;
  v_res := jsonb_build_object('release', p_release, 'ok', v_ok, 'since', v_since, 'migrations', v_mig, 'functions', v_fn, 'jobs_incompatible', v_jobs,
                              'failed_runs', v_fail, 'http_errors', v_http, 'issues', to_jsonb(v_issues));
  insert into pipeline.integration_deploy_checks(release, since, ok, result, issues) values (p_release, v_since, v_ok, v_res, v_issues);
  return v_res;
end $function$;
revoke all on function security.integration_deploy_check_v1(text, jsonb, jsonb, timestamptz, text[]) from public, anon, authenticated;
comment on function security.integration_deploy_check_v1(text, jsonb, jsonb, timestamptz, text[]) is 'CF-247 mandate §4 V3: after each deploy the release controller records migration md5 against the file, function md5s, job compatibility and errors since the deploy; mismatches open integration issues';

-- 6. the screen: Platform health › Integration queue (PIM Admin and above; read only) ---------------------------------------------------
create or replace function public.admin_integration_queue(p_action text default 'summary', p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_rank int := security.current_role_rank(); v_id bigint; v_scope text := coalesce(nullif(p_args->>'scope', ''), 'open');
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'PIM Admin role or above required' using errcode = '42501'; end if;
  if p_action = 'summary' then
    return jsonb_build_object(
      'mode', (select jsonb_build_object('mode', m.mode, 'set_by', m.set_by, 'set_at', m.set_at, 'reason', m.reason) from pipeline.integration_operating_mode m where m.id = 1),
      'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from pipeline.integration_issues group by 1) x),
      'by_severity', (select coalesce(jsonb_object_agg(severity, n), '{}'::jsonb) from (select severity, count(*) n from pipeline.integration_issues where status <> 'closed' group by 1) x),
      'by_workstream', (select coalesce(jsonb_object_agg(workstream, n), '{}'::jsonb) from (select workstream, count(*) n from pipeline.integration_issues where status <> 'closed' group by 1) x),
      'reopened', (select count(*) from pipeline.integration_issues where regression_count > 0 and status <> 'closed'),
      'regressions_total', (select coalesce(sum(regression_count), 0) from pipeline.integration_issues),
      'last_check', (select jsonb_build_object('at', s.last_run_at, 'found', s.last_found, 'ms', s.last_ms, 'errors', s.last_error) from pipeline.integration_validate_state s where s.check_key = 'run'),
      'job_active', coalesce((select j.active from cron.job j where j.jobname = 'integration-validate'), false),
      'last_deploy_check', (select jsonb_build_object('release', d.release, 'at', d.checked_at, 'ok', d.ok, 'issues', d.issues) from pipeline.integration_deploy_checks d order by d.id desc limit 1),
      'issues', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'ref', i.issue_ref, 'fingerprint', i.fingerprint, 'title', i.title, 'layer', i.layer,
                   'severity', i.severity, 'status', i.status, 'workstream', i.workstream, 'root_cause', i.root_cause_class, 'source', i.detection_source,
                   'validation_layer', i.validation_layer, 'detected_at', i.detected_at, 'last_observed_at', i.last_observed_at, 'retry_count', i.retry_count,
                   'regressions', i.regression_count, 'cleared_at', i.condition_cleared_at, 'providers', cardinality(i.provider_ids), 'courses', cardinality(i.course_ids),
                   'countries', i.country_codes, 'more_entities', i.entities_truncated, 'blocked_by', i.blocked_by, 'depends_on', i.depends_on,
                   'fix_commit', i.fix_commit, 'fix_migration', i.fix_migration, 'deployed_version', i.deployed_version, 'verification', i.verification_outcome,
                   'aer_root_cause_ref', i.aer_root_cause_ref) order by case i.severity when 'P0' then 0 when 'P1' then 1 else 2 end, i.last_observed_at desc), '[]'::jsonb)
                   from (select * from pipeline.integration_issues x
                          where (v_scope = 'all' or (v_scope = 'open' and x.status <> 'closed') or (v_scope = 'closed' and x.status = 'closed') or (v_scope = 'reopened' and x.regression_count > 0))
                          order by x.last_observed_at desc limit 500) i));  -- fixed: screen list length
  elsif p_action = 'issue' then
    v_id := (p_args->>'id')::bigint;
    return (select jsonb_build_object('issue', to_jsonb(i), 'events',
              (select coalesce(jsonb_agg(to_jsonb(e) order by e.at desc, e.id desc), '[]'::jsonb) from (select * from pipeline.integration_issue_events e where e.issue_id = i.id order by e.at desc, e.id desc limit 200) e))  -- fixed: screen list length
              from pipeline.integration_issues i where i.id = v_id);
  end if;
  raise exception 'unknown action' using errcode = '22023';
end $function$;
revoke all on function public.admin_integration_queue(text, jsonb) from public, anon;
grant execute on function public.admin_integration_queue(text, jsonb) to authenticated;

-- 7. the job (G1: catalogued first; created INACTIVE, the integrator switches it on after release) ----------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('integration-validate', 'Platform upkeep', 16, 'Integration checks (V4)',
  'At :21 and :51 (clear of the admission minutes :x3, :x5, :x9, the :35-:42 jobs and :47-:48): reads the open Platform health and work-queue issues and runs keyed checks (failed job runs since the last check, stale leases, adapter drafts stuck in capture or proposal, duplicate, orphan or regenerated Layer 4 items, course-url-fill writing a course_url while an official_course_url item is pending, Firecrawl spent on archived providers, archived or inactive records published in search, spend against the settings). Each finding opens or updates one integration issue by fingerprint (no duplicates; a recurrence after closure reopens it as a regression). P0 findings go through the existing alert outbox (platform-alerts), once per change. Settings integration.*. Off until the integrator switches it on after release.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'integration-validate') then
    perform cron.schedule('integration-validate', '21,51 * * * *', $j$select security.integration_validate_v1()$j$);
  end if;
  perform cron.alter_job((select jobid from cron.job where jobname = 'integration-validate'), active := false);
end $c$;

-- 8. component register ------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.integration_issues', 'Platform', 'CF-247 continuous validation: the integration feedback queue (by fingerprint)', 'active', '{}', '20261102120000'),
 ('table', 'pipeline.integration_issue_events', 'Platform', 'CF-247 continuous validation: integration issue history', 'active', '{}', '20261102120000'),
 ('table', 'pipeline.integration_operating_mode', 'Platform', 'CF-247 §13: operating mode (1 or 2) and who set it', 'active', '{}', '20261102120000'),
 ('table', 'pipeline.integration_validate_state', 'Platform', 'CF-247 V4: per-check watermarks and last results', 'active', '{}', '20261102120000'),
 ('table', 'pipeline.integration_lease_watch', 'Platform', 'CF-247 V4: lease tables the stale-lease check reads', 'active', '{}', '20261102120000'),
 ('table', 'pipeline.integration_deploy_checks', 'Platform', 'CF-247 V3: deployment check results', 'active', '{}', '20261102120000'),
 ('job', 'integration-validate', 'Platform', 'CF-247 V4: continuous production checks feeding the integration queue', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_issue_upsert_v1', 'Platform', 'CF-247 §3: create or update an integration issue by fingerprint; regression reopening', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_issue_transition_v1', 'Platform', 'CF-247 §3: integration issue lifecycle', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_issue_close_v1', 'Platform', 'CF-247 §5: close only with production verification evidence', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_mode_set_v1', 'Platform', 'CF-247 §13: operating mode change by the Integration Controller', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_mode_guard_v1', 'Platform', 'CF-247 §13: refuses operating mode writes outside the controller path', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_alert_sync_v1', 'Platform', 'CF-247: P0 integration issues through the existing platform-alerts path', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_l4_pending_v1', 'Platform', 'CF-247 V4: the pending Layer 4 items the checks examine', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_validate_v1', 'Platform', 'CF-247 V4: job integration-validate', 'active', '{}', '20261102120000'),
 ('function', 'security.integration_deploy_check_v1', 'Platform', 'CF-247 V3: deployment check for the release controller', 'active', '{}', '20261102120000'),
 ('function', 'public.admin_integration_queue', 'Platform', 'CF-247: Platform health › Integration queue (PIM Admin and above)', 'active', '{}', '20261102120000')
on conflict do nothing;
