-- CF-247 human-assisted recovery (Platform Admin design decision 4 Nov 2026 06:30, amending SS-018, SS-019 and SS-021; admin
-- docs/platform/nz-enrichment-brief/2026-11-04-human-assisted-recovery-design-decision-0630.md). Lands after workstream A's contract
-- (20261104010000), work continuity (20261104170000), the AER missing-university inventory (20261104090000), the Layer 4 course-link change
-- (20261104260000) and scholarship coverage (20261104390000).
--
-- Why (live, read-only, 4 Nov 2026 06:31-07:10 AEDT; morning measures 2026-11-04-morning-validation-measures.md):
--   * ACU, CQU, Deakin and JCU have no AER matrix source. The inventory holds what free discovery found (ACU and CQU: a named document whose URL
--     could not be verified; Deakin: the site refused the read; JCU: a JavaScript selector), but nothing asks a person for the one fact missing.
--   * CDU's course reads ran 6 times overnight with 0 rows; 49 aer_technical work items are parked with no next time; 1,424 eligible providers
--     have no AER source at all. Every one waits for Claude or ChatGPT to repair records by hand.
--   * Scholarship coverage (v2.15.460) classifies source_not_discovered, international_unresolved and ownership_conflict cases, but a reviewer has
--     no control that supplies the missing fact and resumes the work.
-- What (one central capability; the decision's §1-§9):
--   1 One intervention contract: pipeline.layer4_interventions, one row per (lane, entity, missing_fact), linked to its work item
--     (pipeline.work_items through security.work_item_report_v1: stage awaiting_review, no lease, no next attempt). It holds the status, the
--     required human input, the prefilled evidence (official links, stored copies, quotes, prior attempts, conflicts, AI analysis with confidence
--     and uncertainty), the recommended action, the actions allowed per role and the resume target. pipeline.layer4_intervention_classes holds
--     each failure class (lane, the fact it asks for, the actions it allows with the rank each needs, its handler, whether it is interpretative);
--     every time bound of a class is a setting har.<class>.* (G2). An unchanged failure never makes a new item (fingerprint; repeat only counted);
--     a changed one updates the same item; a failure that returns after closing reopens the same item.
--   2 A Layer 4 kind, "Human input needed" (intervention), for the existing Inbox, built to the Inbox paging contract as this change's own
--     functions (the Inbox functions and screen belong to the Inbox performance change, cf247-l4-inbox-perf, Coordinator 06:53):
--     security.layer4_intervention_kind_v1 (label and choices), _inbox_counts_v1 (counts only), _inbox_page_v1 (a keyset page of compact rows,
--     no evidence) and _inbox_detail_v1 (the decision's four sections for one card, read when opened), and _inbox_decide_v1 (the route). The eleven actions of §2 go through one server function, security.layer4_intervention_resolve_v1(id, action,
--     payload): role and per-item action checks, the class's validator (identity, official host, provenance, field rules, ownership), an audit
--     row for every action (pipeline.layer4_intervention_events, and the Inbox's admin_control_events row). A URL or document is never approval
--     to publish: it becomes a source or candidate value that the existing reader, Layer 3 and Layer 4 admission checks still decide.
--   3 Automatic resumption: pipeline.layer4_intervention_handlers, one per lane (validate_fn, resume_fn, verify_fn). Valid input marks the
--     dependency resolved, schedules the next operation (the existing reader picks it up; a stored copy is reused before any read), and the
--     job closes the intervention on the verified result, or reopens the same item with a specific new request; the linked integration issue is
--     closed or reopened on that result. Insufficient input updates the same item with what is still missing.
--   4 One targeted stronger-model step for interpretative classes only (har.ai_escalate_on, ships 0): a request on the existing ops_diagnose
--     worker lane (pipeline.ops_ai_diagnosis_requests; its spend capture, ops.ai_diagnosis_usd_per_day, security.ai_use_refusal_v1 and the daily
--     ceiling), pinned to har.ai_escalation_model; its proposals are checked against official evidence (a URL must be on the provider's own site
--     and already seen in stored evidence; a value must carry a quote) before they are offered, and never decide.
--   5 AER first (lanes aer_source and aer_course), then scholarship coverage (lane sch_coverage): job layer4-interventions
--     (security.layer4_interventions_tick_v1) raises interventions from what is held (the source inventory, discovery and reader outcomes, parked
--     aer_technical work items, scholarship coverage states), bounded and fair (batch.har_generate a run, har.generate_per_provider_max per
--     provider, har.open_max_per_lane open items a lane); it never touches the AER Layer 4 limit (aer.schedule_layer4_max): interventions are not
--     layer4_review_items.
--   6 Time bounds per class (har.<class>.max_attempts, escalate_after_hours, recheck_hours, deadline_hours, assigned_to); while waiting for a
--     person an item holds no lease, spends nothing, blocks nothing else and is never counted as admitted.
--   6b AER reads held by E13 or D-R3 (Platform Admin decision 4 Nov 2026 06:58 §1, §3; Inbox paging contract §2a, mode extend on aer_review):
--     security.layer4_aer_recovery_kind_v1/_detail_v1/_decide_v1: Re-read from stored evidence (the existing corrected read, D-R2, or the
--     matrix re-read), Request official evidence (one aer_read_evidence intervention per recovery case), Ask AI to analyse (behind
--     har.ai_escalate_on), Open human input (aer_read_rows_missing: rows checked against the dropped quotations); every action recorded in
--     pipeline.layer4_aer_recovery_actions, once per unchanged problem; valid input restarts the corrected read by itself. The gates still
--     refuse approval of an incomplete read.
--   7 Metrics (§9): security.layer4_intervention_report_v1(), a section of security.ops_report_v1 (md5-guarded edit). No new dashboard.
-- Activation:
--   ON (records, asks a person, and resumes only on a person's input within the existing readers' caps): har.on, har.generate_aer_on,
--     har.generate_sch_on, har.resume_on.
--   OFF: har.ai_escalate_on (AI spend; also needs ops.ai_diagnosis_on). Nothing here admits a value, decides a Layer 4 review item, publishes,
--     or changes a cap, a budget, a manual lock or the consumer API.
-- Settings (G2): har.* and batch.har_generate (Settings > Pipeline settings, "Human-assisted recovery").
-- md5 (before = live, read 4 Nov 2026 06:31 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/human-assisted-recovery/run.sh):
--   security.ops_report_v1(integer)           5a1e21cc42f8f54cbf0d9f3f7fe81c71 -> 3ba694dc078995d88a983e8e92b2f425
-- Called, not edited (live md5 4 Nov 2026 06:31): security.work_item_report_v1(text,text,text,text,jsonb) 6a15318c0ecd6644b32f1883463c542e,
--   security.integration_issue_upsert_v1(jsonb,text) b0a1a64982680ae5d588c2d73b779e4e, security.integration_issue_close_v1(bigint,text,jsonb),
--   security.url_on_provider_sites(text,uuid), security.third_party_host_v1(text), security.layer4_stored_copy_v1(text),
--   security.ai_use_refusal_v1(text), security.current_role_rank().
-- Replaces: security.ops_report_v1 (same name; md5-guarded edit: one report section)
-- Retires: nothing (record-by-record repair by Claude or ChatGPT is replaced by this route; no database object is retired)
-- Nothing is dropped or deleted. Consumer API untouched (G3). No Firecrawl or AI spend by this migration.

-- 0 the contracts this change builds on, and the definitions it edits or calls, as read live ---------------------------------------------------
do $g$
declare r record;
begin
  if to_regclass('pipeline.ops_remedies') is null or to_regclass('pipeline.work_items') is null or to_regclass('pipeline.aer_source_inventory') is null
     or to_regclass('pipeline.scholarship_coverage_items') is null or to_regclass('pipeline.course_page_needed') is null then
    raise exception 'needs workstream A''s contract (20261104010000), work continuity (20261104170000), the AER inventory (20261104090000), the Layer 4 course-link change (20261104260000) and scholarship coverage (20261104390000) first';
  end if;
  for r in select * from (values ('security.work_item_report_v1(text,text,text,text,jsonb)', '6a15318c0ecd6644b32f1883463c542e')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  -- called through their interfaces only (their bodies may change under their owners)
  for r in select * from (values ('security.integration_issue_upsert_v1(jsonb,text)'), ('security.integration_issue_close_v1(bigint,text,jsonb)'),
                                 ('security.url_on_provider_sites(text,uuid)'), ('security.third_party_host_v1(text)'), ('security.layer4_stored_copy_v1(text)'),
                                 ('security.ai_use_refusal_v1(text)'), ('security.current_role_rank()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'live % is missing', r.sig; end if;
  end loop;
end $g$;

-- an edit applied once, only from the definition it was written against (the 20261103050000 helper)
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

-- 1 settings (G2; Settings > Pipeline settings, section Human-assisted recovery) -------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'har.on', 'Human-assisted recovery: record and resolve interventions',
  'On (1): failures the platform cannot recover are raised once as Layer 4 interventions ("Human input needed"), a reviewer''s input is validated and audited, and the job checks the result. Off (0): nothing is raised; existing items stay as they are.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1500, 'Human-assisted recovery', 'security.layer4_intervention_raise_v1; security.layer4_intervention_resolve_v1; security.layer4_interventions_tick_v1 (job layer4-interventions)',
  'Platform Admin design decision 4 Nov 2026 06:30 §1-§3: ships on (it records and asks a person; it admits nothing)'),
 ('pipeline', 'har.generate_aer_on', 'Human-assisted recovery: raise AER interventions',
  'On (1): the job raises an intervention for each university whose entry-requirement source or read could not be recovered automatically (source inventory, reader outcomes, parked AER work). Off (0): no new AER intervention.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1501, 'Human-assisted recovery', 'security.har_aer_generate_v1 (job layer4-interventions)', 'Decision 06:30 §4 "apply immediately to the missing AER universities"'),
 ('pipeline', 'har.generate_sch_on', 'Human-assisted recovery: raise scholarship interventions',
  'On (1): the job raises an intervention for scholarship coverage cases in the states source not discovered, international eligibility unresolved and ownership conflict. Off (0): none.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1502, 'Human-assisted recovery', 'security.har_sch_generate_v1 (job layer4-interventions)', 'Decision 06:30 §5 "prioritising missing AER sources and scholarship coverage"'),
 ('pipeline', 'har.resume_on', 'Human-assisted recovery: resume work after valid input',
  'On (1): valid input marks the dependency resolved and hands the work back to its existing reader (a stored copy is used before any read; the readers keep their own caps and budgets). Off (0): valid input is recorded and waits.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1503, 'Human-assisted recovery', 'security.layer4_intervention_resolve_v1 (handlers'' resume_fn)', 'Decision 06:30 §7 "automatic resumption is mandatory"'),
 ('pipeline', 'batch.har_generate', 'Human-assisted recovery: interventions considered a run, per lane',
  'Each run of job layer4-interventions considers at most this many failures per lane for a new or changed intervention.',
  'number', to_jsonb(40), 1, 500, 'failures', 1504, 'Human-assisted recovery', 'security.layer4_interventions_tick_v1 (job layer4-interventions)', 'Decision 06:30 §4 "bounded and fair"'),
 ('pipeline', 'batch.har_verify', 'Human-assisted recovery: interventions checked a run',
  'Each run checks at most this many interventions whose work was resumed or whose recheck is due.',
  'number', to_jsonb(200), 10, 2000, 'interventions', 1505, 'Human-assisted recovery', 'security.layer4_interventions_tick_v1 (job layer4-interventions)', 'Decision 06:30 §6-§7'),
 ('pipeline', 'har.generate_per_provider_max', 'Human-assisted recovery: new interventions per provider a run',
  'One provider gets at most this many new interventions in a run, so one large provider never fills the batch.',
  'number', to_jsonb(2), 1, 20, 'interventions', 1506, 'Human-assisted recovery', 'security.har_aer_generate_v1; security.har_sch_generate_v1', 'Decision 06:30 §6 "block another provider"'),
 ('pipeline', 'har.open_max_per_lane', 'Human-assisted recovery: open interventions per lane',
  'A lane with this many interventions waiting for a person raises no new one until some are resolved (readiness; Layer 4 review limits are separate and unchanged).',
  'number', to_jsonb(150), 10, 2000, 'interventions', 1507, 'Human-assisted recovery', 'security.layer4_intervention_raise_v1', 'Decision 06:30 §6 "queue capacity managed by readiness"'),
 ('pipeline', 'har.evidence_items_max', 'Human-assisted recovery: evidence entries kept on a card',
  'Each list on an intervention card (official links, stored copies, quotes, attempts, conflicts) keeps at most this many entries, so the Inbox stays light.',
  'number', to_jsonb(5), 1, 20, 'entries', 1508, 'Human-assisted recovery', 'security.layer4_intervention_raise_v1', 'Inbox load time (about 22,000 px and timing out on 4 Nov 2026)'),
 ('pipeline', 'har.history_items', 'Human-assisted recovery: audit lines shown on a card',
  'The card shows the newest this many audit lines of its intervention; the full audit is kept in pipeline.layer4_intervention_events.',
  'number', to_jsonb(3), 0, 20, 'lines', 1509, 'Human-assisted recovery', 'security.layer4_inbox_items_v1', 'Decision 06:30 §3 "audit trail and reviewer identity"'),
 ('pipeline', 'har.verify_after_hours', 'Human-assisted recovery: wait for the resumed work before asking again',
  'After valid input the work is checked each run; if it has not produced its result after this long, the same intervention returns to the reviewer with what happened.',
  'number', to_jsonb(24), 1, 336, 'hours', 1510, 'Human-assisted recovery', 'security.layer4_interventions_tick_v1', 'Decision 06:30 §7 "close or reopen on the actual result"'),
 ('pipeline', 'har.ai_escalate_on', 'Human-assisted recovery: one stronger-model attempt before asking a person',
  'On (1): an interpretative failure gets one request to the pinned escalation model through the existing ops_diagnose lane (its daily cap, the AI ceiling and the credit floor apply) before it is shown; its proposals are checked against official evidence and only suggested. Also needs ops.ai_diagnosis_on. Off (0): no AI request.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1511, 'Human-assisted recovery', 'security.har_ai_escalate_v1 (job layer4-interventions)', 'Decision 06:30 §1 step 4: ships off (AI spend)'),
 ('pipeline', 'har.ai_requests_per_day', 'Human-assisted recovery: stronger-model requests a day',
  'At most this many escalation requests are queued in a day (UTC); the ops_diagnose lane''s own daily spend cap and the AI ceiling still apply.',
  'number', to_jsonb(10), 1, 200, 'requests', 1516, 'Human-assisted recovery', 'security.har_ai_tick_v1', 'Decision 06:30 §1 "a targeted fallback, not permission for unrestricted AI calls"'),
 ('pipeline', 'har.ai_wait_hours', 'Human-assisted recovery: longest wait for the stronger model',
  'An intervention waiting for its AI request longer than this is shown to the reviewer without it.',
  'number', to_jsonb(6), 1, 72, 'hours', 1512, 'Human-assisted recovery', 'security.har_ai_take_v1', 'Decision 06:30 §6 "not block"'),
 ('pipeline', 'har.ai_min_confidence', 'Human-assisted recovery: lowest AI confidence offered as a suggestion',
  'A validated AI proposal below this confidence is kept in the analysis but not offered as the suggested answer.',
  'number', to_jsonb(0.7), 0, 1, 'confidence (0 to 1)', 1513, 'Human-assisted recovery', 'security.har_ai_take_v1', 'Decision 06:30 §1 step 5'),
 ('pipeline', 'har.quote_min_chars', 'Human-assisted recovery: shortest quotation accepted',
  'A reviewer''s or the AI''s quotation from the official page must be at least this long to count as evidence.',
  'number', to_jsonb(20), 5, 500, 'characters', 1514, 'Human-assisted recovery', 'security.har_quote_ok_v1', 'Decision 06:30 §2 "the same provenance rules"')
on conflict (toolset_key, key) do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'har.ai_escalation_model', 'Human-assisted recovery: pinned escalation model',
  'The one qualified model the stronger-model step may use (an OpenRouter model identifier). Empty: no model is qualified, so no AI request is made even when the step is on. Never an automatic router.',
  'text', to_jsonb(''::text), null, null, null, 1515, 'Human-assisted recovery', 'security.har_ai_escalate_v1', 'Decision 06:30 §1 step 4; pinned-model rule (project instructions)')
on conflict (toolset_key, key) do nothing;

-- 2 the contract: handlers, failure classes, interventions, audit and supplied values ---------------------------------------------------------
create table if not exists pipeline.layer4_intervention_handlers (
  lane text primary key check (lane ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  validate_fn regprocedure not null,
  resume_fn regprocedure not null,
  verify_fn regprocedure not null,
  recheck_fn regprocedure not null,
  generate_fn regprocedure,
  generate_switch text,
  description text not null
);
comment on table pipeline.layer4_intervention_handlers is 'CF-247 human-assisted recovery (Platform Admin decision 4 Nov 2026 06:30 §7): the resume handler registry, one per lane. validate_fn(id bigint, action text, payload jsonb) -> {valid, normalised, request}: the same identity, official-host, provenance and field rules as extracted data; resume_fn(id, action, normalised) -> {scheduled, operation, stored_copy}: hands the work back to the lane''s existing reader (never admits or publishes); verify_fn(id) -> {state pending|succeeded|failed, admitted, published, evidence}; recheck_fn(id) -> {cleared, evidence}: the failure cleared without a person; generate_fn(limit) raises the lane''s interventions while generate_switch is 1.';
alter table pipeline.layer4_intervention_handlers enable row level security;
revoke all on pipeline.layer4_intervention_handlers from public, anon, authenticated;

create table if not exists pipeline.layer4_intervention_classes (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  lane text not null,
  workstream text not null,
  title text not null,
  required_input text not null,
  recommended_action text not null,
  unblocks text not null,
  allowed_actions jsonb not null,
  interpretative boolean not null default false,
  recheck_condition text not null,
  sort int not null
);
comment on table pipeline.layer4_intervention_classes is 'CF-247 human-assisted recovery (decision 06:30 §2, §6): each failure class that can need a person: its lane and workstream (the §9 report rows), the input it asks for, the recommended action, how the answer unblocks processing, the actions it allows with the lowest role rank for each, whether a stronger model may try it first (interpretative), and the condition rechecked automatically. Its time bounds are settings har.<code>.max_attempts, escalate_after_hours, recheck_hours, deadline_hours and assigned_to.';
alter table pipeline.layer4_intervention_classes enable row level security;
revoke all on pipeline.layer4_intervention_classes from public, anon, authenticated;

create table if not exists pipeline.layer4_interventions (
  id bigserial primary key,
  lane text not null,
  entity text not null check (length(entity) > 0),
  missing_fact text not null references pipeline.layer4_intervention_classes(code),
  provider_id uuid,
  course_id uuid,
  field text,
  subject text not null,
  status text not null default 'awaiting_input' check (status in ('ai_pending', 'awaiting_input', 'resuming', 'resolved', 'auto_resolved', 'not_published', 'returned_technical')),
  issue jsonb not null,
  evidence jsonb not null default '{}'::jsonb,
  ai_analysis jsonb,
  required_input jsonb not null,
  recommended jsonb not null,
  allowed_actions jsonb not null,
  resume_target jsonb not null,
  fingerprint text not null,
  closed_fingerprint text,
  automated_attempts int not null default 0,
  repeat_count int not null default 0,
  reopen_count int not null default 0,
  work_item_id bigint,
  integration_issue_id bigint,
  assigned_to text,
  next_action_at timestamptz,
  escalate_at timestamptz,
  escalated_at timestamptz,
  recover_by timestamptz,
  supplied jsonb,
  resolved_by uuid,
  input_at timestamptz,
  resumed_at timestamptz,
  verified_at timestamptz,
  admitted_at timestamptz,
  published_at timestamptz,
  verified_outcome text,
  outcome_detail jsonb,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lane, entity, missing_fact)
);
comment on table pipeline.layer4_interventions is 'CF-247 human-assisted recovery (Platform Admin decision 4 Nov 2026 06:30): one deduplicated intervention per lane, entity and missing fact, linked to its work item (pipeline.work_items, stage awaiting_review: no lease, no next attempt, no spend). It holds the issue (what was attempted, why it stopped, the impact), the prefilled evidence (official links, stored copies, quotes, prior attempts, conflicts), the AI analysis (confidence, uncertainty, validated proposals), the input required, the recommended action, the actions allowed per role, the resume target, the time bounds of its class and the verified outcome. Shown in the Layer 4 Inbox as "Human input needed" while awaiting_input; resolved only through security.layer4_intervention_resolve_v1. Never an admitted value.';
create index if not exists layer4_interventions_open_idx on pipeline.layer4_interventions (lane, status) where status in ('ai_pending', 'awaiting_input', 'resuming');
create index if not exists layer4_interventions_provider_idx on pipeline.layer4_interventions (provider_id);
alter table pipeline.layer4_interventions enable row level security;
revoke all on pipeline.layer4_interventions from public, anon, authenticated;
revoke all on sequence pipeline.layer4_interventions_id_seq from public, anon, authenticated;

create table if not exists pipeline.layer4_intervention_events (
  id bigserial primary key,
  intervention_id bigint not null references pipeline.layer4_interventions(id),
  at timestamptz not null default now(),
  actor uuid,
  actor_label text not null,
  role_rank int,
  action text not null,
  payload jsonb not null default '{}'::jsonb,
  result jsonb not null default '{}'::jsonb,
  status_before text,
  status_after text
);
comment on table pipeline.layer4_intervention_events is 'CF-247 human-assisted recovery (decision 06:30 §3, §7): the audit of every intervention: raised, evidence changed, repeat (counted only), reopened, every reviewer action with the reviewer, role rank, payload and validation result, resumed, verified, escalated, rechecked and AI steps. Append-only.';
create index if not exists layer4_intervention_events_item_idx on pipeline.layer4_intervention_events (intervention_id, id desc);
alter table pipeline.layer4_intervention_events enable row level security;
revoke all on pipeline.layer4_intervention_events from public, anon, authenticated;
revoke all on sequence pipeline.layer4_intervention_events_id_seq from public, anon, authenticated;

create table if not exists pipeline.layer4_intervention_values (
  id bigserial primary key,
  intervention_id bigint not null references pipeline.layer4_interventions(id),
  lane text not null,
  entity text not null,
  field text,
  value jsonb not null,
  quote text,
  source_url text,
  evidence_id uuid,
  actor uuid,
  state text not null default 'proposed' check (state in ('proposed', 'taken', 'admitted', 'refused')),
  state_at timestamptz,
  state_detail jsonb,
  created_at timestamptz not null default now()
);
comment on table pipeline.layer4_intervention_values is 'CF-247 human-assisted recovery (decision 06:30 §2 "manual entry follows the same rules"): structured information a reviewer supplied, with its quotation, official source and stored copy (provenance). A value here is a proposal, never admitted by this table: the lane''s own Layer 3 and Layer 4 admission takes it (state taken, then admitted or refused).';
create index if not exists layer4_intervention_values_open_idx on pipeline.layer4_intervention_values (lane, state) where state = 'proposed';
alter table pipeline.layer4_intervention_values enable row level security;
revoke all on pipeline.layer4_intervention_values from public, anon, authenticated;
revoke all on sequence pipeline.layer4_intervention_values_id_seq from public, anon, authenticated;

-- the failure classes (§2, §6). Ranks: 4 Pipeline Operator, 5 Data Steward, 6 Platform Admin (security.current_role_rank()).
insert into pipeline.layer4_intervention_classes(code, lane, workstream, title, required_input, recommended_action, unblocks, allowed_actions, interpretative, recheck_condition, sort) values
 ('aer_source_missing', 'aer_source', 'AER', 'No official entry-requirement source could be found',
  'The official web address of this university''s international academic entry requirements: its country or qualification table, a requirements document, or the page that states its general rule.',
  'provide_url', 'The address is checked to be on the university''s own website, attached as its entry-requirement source and read by the existing entry-matrix reader (a stored copy first); the first read goes to Layer 4 as usual.',
  '{"provide_url": 4, "attach_document": 4, "select_source": 4, "confirm_not_published": 5, "return_technical": 4, "reject_evidence": 4}', false,
  'a source of this university is attached and read', 10),
 ('aer_document_unverified', 'aer_source', 'AER', 'The official page names a requirements document whose address could not be verified',
  'The exact address of the document the official page names (for example its minimum academic entry requirements by country), copied from the official page.',
  'attach_document', 'The document is checked to be on the university''s own website, attached as its source and read by the existing reader (PDFs through the PDF step); the first read goes to Layer 4.',
  '{"attach_document": 4, "provide_url": 4, "select_source": 4, "confirm_not_published": 5, "return_technical": 4, "reject_evidence": 4}', true,
  'a source of this university is attached and read', 20),
 ('aer_rendered_only', 'aer_source', 'AER', 'Entry requirements are shown only inside a selector on the official site',
  'An official source that prints the same requirements (a document or a page), or confirmation, with the official sentence, that the requirements are course-specific so the course reader applies.',
  'attach_document', 'A printed source is attached and read like any other; a course-specific confirmation returns the university''s courses to the course reader. The rendered route stays a Platform Admin spend decision.',
  '{"attach_document": 4, "provide_url": 4, "confirm_scope": 4, "confirm_not_published": 5, "return_technical": 6, "reject_evidence": 4}', false,
  'a source of this university is attached and read', 30),
 ('aer_empty_read', 'aer_source', 'AER', 'Reads of this university''s courses found no entry requirement',
  'The official page that states the international entry requirements for these courses (course mapping), or confirmation, with the official sentence, that the university-wide rule applies to them.',
  'provide_url', 'The page is attached as the university''s source (or the scope recorded) and the course reads are returned to the scheduled reader, which reuses stored copies.',
  '{"provide_url": 4, "attach_document": 4, "confirm_scope": 4, "select_source": 4, "confirm_not_published": 5, "return_technical": 4, "reject_evidence": 4}', true,
  'a course entry row of this university is proposed or active', 40),
 ('aer_read_held', 'aer_source', 'AER', 'The read of an attached entry-requirement source is held',
  'Which official source is authoritative for this university (if another page should be read instead), or return to the reader''s technical recovery.',
  'return_technical', 'A selected source is attached and read; a return hands the read back to the reader''s technical recovery. The held rows are still decided in the existing AER review.',
  '{"select_source": 4, "provide_url": 4, "return_technical": 4, "reject_evidence": 4}', true,
  'the university''s held read is replaced or admitted', 50),
 ('aer_course_identity', 'aer_course', 'AER', 'The course a requirement page belongs to is ambiguous',
  'Which course this page belongs to (its course code), or the course''s own official page.',
  'confirm_identity', 'The course is confirmed (same university, active) and its read returns to the AER reader; the requirement is then checked and reviewed as usual.',
  '{"confirm_identity": 4, "provide_url": 4, "return_technical": 4, "reject_evidence": 4}', true,
  'the course''s held read is no longer held', 60),
 ('sch_source_missing', 'sch_coverage', 'Scholarships', 'No official scholarship source was discovered',
  'The address of the university''s own scholarship page or list for international students.',
  'provide_url', 'The address is checked to be on the university''s own website (not a directory site) and added as a listing source; the scholarship listing reader reads it and its scholarships go through the usual admission checks.',
  '{"provide_url": 4, "select_source": 4, "search_again": 4, "confirm_not_published": 5, "return_technical": 4}', false,
  'the coverage case is no longer source not discovered', 70),
 ('sch_international_unresolved', 'sch_coverage', 'Scholarships', 'Whether international students may apply is not established',
  'Whether international students may apply, with the sentence from the official page that says so.',
  'confirm_scope', 'Your answer and its quotation are kept as evidence and the page is read again through Read again; admission still needs the usual checks.',
  '{"confirm_scope": 4, "correct_value": 4, "reject_evidence": 4, "return_technical": 4}', true,
  'the coverage case is no longer international eligibility unresolved', 80),
 ('sch_ownership_conflict', 'sch_coverage', 'Scholarships', 'Which provider owns this scholarship source is in conflict',
  'Which provider owns the page (its exact name or id).',
  'confirm_identity', 'The ownership decision is recorded for the scholarship coverage lane; nothing is reassigned or published by it.',
  '{"confirm_identity": 6, "reject_evidence": 6, "return_technical": 4}', false,
  'the coverage case is no longer an ownership conflict', 90),
 ('fee_evidence_conflict', 'fee', 'Fees', 'Tuition evidence conflicts',
  'Which official source is authoritative, or the corrected fee (amount, currency, academic year, audience, basis) with the official sentence that states it.',
  'select_source', 'The value is recorded with its provenance as a proposal for the fee lane; the fee lane''s own checks and Layer 4 admit or refuse it.',
  '{"select_source": 4, "correct_value": 4, "confirm_scope": 4, "enter_value": 4, "return_technical": 4, "reject_evidence": 4}', true,
  'the fee lane has no conflicting evidence for the course', 100),
 ('aer_read_evidence', 'aer_item', 'AER', 'An incomplete entry-requirement read needs the official evidence again',
  'The official page or document that states the requirements the reader dropped (the same course''s page, or the university''s requirements document).',
  'attach_document', 'The evidence is checked to be on the university''s own site and attached; the course is read again by the existing reader (a corrected read, D-R2), and the new read replaces the incomplete one only through the usual gates.',
  '{"attach_document": 4, "provide_url": 4, "confirm_not_published": 5, "return_technical": 4, "reject_evidence": 4}', false,
  'the incomplete read is replaced or decided', 55),
 ('aer_read_rows_missing', 'aer_item', 'AER', 'Requirements were dropped from an entry-requirement read',
  'Each dropped requirement entered or corrected as a row (what it requires and its minimum, if any), each with the sentence from the official page that states it.',
  'enter_value', 'Each row''s quotation is checked against the requirements the reader dropped; the rows are kept as evidence and the course is read again (a corrected read) so the gates can pass. A row typed here is never admitted by itself.',
  '{"enter_value": 4, "correct_value": 4, "return_technical": 4, "reject_evidence": 4}', true,
  'the incomplete read is replaced or decided', 56),
 ('intake_incomplete', 'intake', 'Intakes', 'Intake commencement or application deadline is incomplete',
  'The missing commencement dates and application deadlines, with the official sentence that states them.',
  'enter_value', 'The dates are recorded with their provenance as a proposal for the intake lane, whose own checks and Layer 4 admit or refuse them.',
  '{"enter_value": 4, "provide_url": 4, "confirm_not_published": 5, "return_technical": 4}', true,
  'the intake lane has the dates for the course', 110)
on conflict (code) do nothing;

-- the time bounds of every class (§6), all settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
select 'pipeline', 'har.' || c.code || '.' || t.k, c.title || ': ' || t.label, t.help, t.kind,
       -- ownership is the Platform Admin's decision, and nothing automatic can settle it
       case when c.code = 'sch_ownership_conflict' and t.k = 'assigned_to' then to_jsonb('Platform Admin (provider identity)'::text)
            when c.code = 'sch_ownership_conflict' and t.k = 'max_attempts' then to_jsonb(0)
            -- several reads of a university with no row (CDU: 6 overnight) are the evidence of an empty read, not one
            when c.code = 'aer_empty_read' and t.k = 'max_attempts' then to_jsonb(3) else t.v end, t.lo, t.hi, t.unit, 1520 + c.sort + t.o, 'Human-assisted recovery',
       t.used_by, 'Platform Admin decision 4 Nov 2026 06:30 §6 (time-bound resolution by failure class)'
  from pipeline.layer4_intervention_classes c
 cross join (values
   (1, 'max_attempts', 'automated attempts before a person is asked', 'The platform''s own recovery attempts (discovery, reads, re-reads) this class needs before it raises an intervention; fewer, and the case stays with the automatic lanes.', 'number', to_jsonb(1), 0::numeric, 20::numeric, 'attempts', 'security.layer4_intervention_raise_v1'),
   (2, 'escalate_after_hours', 'escalate when unanswered for', 'An intervention still waiting for a person this long is escalated once, as one integration issue per class (har:<lane>:<class>).', 'number', to_jsonb(72), 1, 2160, 'hours', 'security.layer4_interventions_tick_v1'),
   (3, 'recheck_hours', 'recheck the failure every', 'While it waits, the platform checks this often whether the failure has cleared by itself (then the intervention closes without a person).', 'number', to_jsonb(24), 1, 720, 'hours', 'security.layer4_interventions_tick_v1'),
   (4, 'deadline_hours', 'recovery deadline', 'The case should be recovered within this long of the intervention being raised; later, it is reported as overdue.', 'number', to_jsonb(168), 1, 4320, 'hours', 'security.layer4_interventions_tick_v1; security.layer4_intervention_report_v1'),
   (5, 'assigned_to', 'assigned responsibility', 'Who is responsible for answering this class of intervention (shown on the card and in the report).', 'text', to_jsonb('Layer 4 reviewer (Pipeline Operator or above)'::text), null, null, null, 'security.layer4_intervention_raise_v1')
 ) t(o, k, label, help, kind, v, lo, hi, unit, used_by)
on conflict (toolset_key, key) do nothing;

-- 3 helpers ---------------------------------------------------------------------------------------------------------------------------------
create or replace function security.har_num_v1(p_class text, p_key text, p_default numeric) returns numeric
language sql stable set search_path to '' as $function$
-- a class's time bound (setting har.<class>.<key>)
  select security.pipeline_num_v1('har.' || p_class || '.' || p_key, p_default)
$function$;
revoke all on function security.har_num_v1(text, text, numeric) from public, anon, authenticated;

create or replace function security.har_text_v1(p_key text, p_default text) returns text
language sql stable security definer set search_path to '' as $function$
  select coalesce(nullif((select s.value #>> '{}' from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), ''), p_default)
$function$;
revoke all on function security.har_text_v1(text, text) from public, anon, authenticated;

create or replace function security.har_quote_ok_v1(p_quote text) returns boolean
language sql stable set search_path to '' as $function$
  select length(btrim(coalesce(p_quote, ''))) >= security.pipeline_num_v1('har.quote_min_chars', 20)
$function$;
revoke all on function security.har_quote_ok_v1(text) from public, anon, authenticated;

create or replace function security.har_cap_v1(p jsonb) returns jsonb
language sql stable set search_path to '' as $function$
-- the first har.evidence_items_max entries of a list (the card stays light; the full record stays where it is held)
  select case when jsonb_typeof(p) = 'array' then coalesce((select jsonb_agg(e order by n) from jsonb_array_elements(p) with ordinality z(e, n)
                                                             where n <= security.pipeline_num_v1('har.evidence_items_max', 5)), '[]'::jsonb)
              else coalesce(p, '[]'::jsonb) end
$function$;
revoke all on function security.har_cap_v1(jsonb) from public, anon, authenticated;

create or replace function security.har_official_url_v1(p_url text, p_provider uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- §2 "the same identity and provenance rules": an address a person or the AI offers must be a full https address on the provider's own sites
-- (security.url_on_provider_sites), never a search, social or directory site (security.third_party_host_v1). Says whether a stored copy of it
-- is held already (security.layer4_stored_copy_v1), so the reader can reuse it instead of buying a read.
declare v_url text := btrim(coalesce(p_url, ''));
begin
  if v_url !~* '^https://[^\s/]+\.[^\s]+$' then return jsonb_build_object('ok', false, 'reason', 'give the full official address, starting https://'); end if;
  if coalesce(security.third_party_host_v1(v_url), false) then
    return jsonb_build_object('ok', false, 'reason', 'this address is on a search, social or directory site; give the address on the provider''s own website');
  end if;
  if p_provider is null or not coalesce(security.url_on_provider_sites(v_url, p_provider), false) then
    return jsonb_build_object('ok', false, 'reason', 'this address is not on the provider''s own website; give the page on its official site');
  end if;
  return jsonb_build_object('ok', true, 'url', v_url, 'document', v_url ~* '\.(pdf|docx?)($|[?#])', 'stored_copy', security.layer4_stored_copy_v1(v_url));
end $function$;
revoke all on function security.har_official_url_v1(text, uuid) from public, anon, authenticated;

create or replace function security.har_event_v1(p_id bigint, p_action text, p_payload jsonb, p_result jsonb, p_before text, p_after text) returns void
language sql security definer set search_path to '' as $function$
-- the audit line of every step: the reviewer (auth.uid and role rank) or the system
  insert into pipeline.layer4_intervention_events(intervention_id, actor, actor_label, role_rank, action, payload, result, status_before, status_after)
  values (p_id, auth.uid(), coalesce((select u.email from auth.users u where u.id = auth.uid()), case when auth.uid() is null then 'system: job layer4-interventions' else auth.uid()::text end),
          case when auth.uid() is not null then security.current_role_rank() end, p_action, coalesce(p_payload, '{}'::jsonb), coalesce(p_result, '{}'::jsonb), p_before, p_after)
$function$;
revoke all on function security.har_event_v1(bigint, text, jsonb, jsonb, text, text) from public, anon, authenticated;

-- 4 raise: one deduplicated intervention per lane, entity and missing fact (§1 steps 6-8, §4 "do not repeatedly create") ------------------------
create or replace function security.layer4_intervention_raise_v1(p jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- p: class, entity, provider_id, course_id, field, subject, attempts (the platform's own attempts so far), signature (what makes this failure
-- the same failure), issue {summary, attempted[], why_stopped, impact}, evidence {official_links[], stored_copies[], quotes[], attempts[],
-- conflicts[]}, suggested (an answer already held, optional), resume_target {operation, work_item {lane, entity, kind}}.
-- Raised only after the class's automated attempts (har.<class>.max_attempts) and while the lane is under har.open_max_per_lane. An unchanged
-- failure only counts a repeat; a changed one updates the same item; a failure that returns after its item closed reopens the same item.
-- The linked work item waits for review (no lease, no next attempt, no spend) through security.work_item_report_v1.
declare c pipeline.layer4_intervention_classes; i pipeline.layer4_interventions; v_fp text; v_ent text := nullif(btrim(coalesce(p->>'entity', '')), '');
        v_att int := coalesce((p->>'attempts')::int, 0); v_wi jsonb; v_wid bigint; v_status text; v_was text; v_ev jsonb; v_issue jsonb; v_req jsonb; v_rec jsonb; v_res jsonb;
begin
  if security.pipeline_num_v1('har.on', 1) < 1 then return jsonb_build_object('raised', false, 'reason', 'har.on is 0'); end if;
  select * into c from pipeline.layer4_intervention_classes where code = p->>'class';
  if not found then raise exception 'unknown intervention class %', p->>'class' using errcode = '22023'; end if;
  if v_ent is null then raise exception 'an intervention needs its entity' using errcode = '22023'; end if;
  if v_att < security.har_num_v1(c.code, 'max_attempts', 1) then
    return jsonb_build_object('raised', false, 'reason', 'automated recovery has not used its attempts (' || v_att || ')');
  end if;
  v_fp := md5(c.code || '|' || coalesce(p->>'signature', (p->'evidence')::text, ''));
  v_ev := jsonb_build_object('official_links', security.har_cap_v1(p->'evidence'->'official_links'), 'stored_copies', security.har_cap_v1(p->'evidence'->'stored_copies'),
                             'quotes', security.har_cap_v1(p->'evidence'->'quotes'), 'attempts', security.har_cap_v1(p->'evidence'->'attempts'),
                             'conflicts', security.har_cap_v1(p->'evidence'->'conflicts'));
  v_issue := jsonb_build_object('summary', coalesce(p->'issue'->>'summary', c.title), 'attempted', security.har_cap_v1(p->'issue'->'attempted'),
                                'why_stopped', coalesce(p->'issue'->>'why_stopped', c.title), 'impact', p->'issue'->>'impact');
  v_req := jsonb_build_object('ask', c.required_input, 'accepts', (select jsonb_agg(k order by k) from jsonb_object_keys(c.allowed_actions) k));
  v_rec := jsonb_build_object('action', c.recommended_action, 'summary', c.required_input, 'suggested', p->'suggested', 'unblocks', c.unblocks);
  v_wi := coalesce(p->'resume_target'->'work_item', jsonb_build_object('lane', c.lane, 'entity', v_ent, 'kind', c.code));
  perform pg_advisory_xact_lock(hashtext('cf247:har:' || c.lane || ':' || v_ent || ':' || c.code));  -- fixed: one writer per intervention
  select * into i from pipeline.layer4_interventions x where x.lane = c.lane and x.entity = v_ent and x.missing_fact = c.code for update;
  if found then
    if i.status in ('ai_pending', 'awaiting_input', 'resuming') and i.fingerprint = v_fp
       or i.status not in ('ai_pending', 'awaiting_input', 'resuming') and i.closed_fingerprint = v_fp then
      update pipeline.layer4_interventions set repeat_count = repeat_count + 1, last_seen_at = now() where id = i.id;
      return jsonb_build_object('raised', false, 'id', i.id, 'repeat', true, 'status', i.status);
    end if;
    if i.status = 'resuming' then  -- the result of the resumed work decides (security.layer4_interventions_tick_v1)
      update pipeline.layer4_interventions set last_seen_at = now() where id = i.id;
      return jsonb_build_object('raised', false, 'id', i.id, 'status', i.status, 'reason', 'resumed work is being verified');
    end if;
    v_was := i.status;
    v_status := case when i.status in ('ai_pending', 'awaiting_input') then i.status
                     when c.interpretative and security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 then 'ai_pending' else 'awaiting_input' end;
    update pipeline.layer4_interventions set status = v_status, issue = v_issue, evidence = v_ev, fingerprint = v_fp, automated_attempts = v_att,
           reopen_count = reopen_count + case when i.status in ('ai_pending', 'awaiting_input') then 0 else 1 end,
           required_input = v_req, recommended = v_rec, allowed_actions = c.allowed_actions, resume_target = jsonb_build_object('operation', p->'resume_target'->>'operation', 'work_item', v_wi),
           subject = coalesce(nullif(p->>'subject', ''), subject), last_seen_at = now(), updated_at = now(),
           next_action_at = now() + make_interval(hours => security.har_num_v1(c.code, 'recheck_hours', 24)::int),
           escalate_at = case when i.status in ('ai_pending', 'awaiting_input') then escalate_at else now() + make_interval(hours => security.har_num_v1(c.code, 'escalate_after_hours', 72)::int) end,
           recover_by = case when i.status in ('ai_pending', 'awaiting_input') then recover_by else now() + make_interval(hours => security.har_num_v1(c.code, 'deadline_hours', 168)::int) end,
           escalated_at = case when i.status in ('ai_pending', 'awaiting_input') then escalated_at end
     where id = i.id returning * into i;
    perform security.har_event_v1(i.id, case when v_was in ('ai_pending', 'awaiting_input') then 'evidence_changed' else 'reopened' end,
                                  jsonb_build_object('signature', p->>'signature'), jsonb_build_object('fingerprint', v_fp), v_was, v_status);
  else
    if (select count(*) from pipeline.layer4_interventions x where x.lane = c.lane and x.status in ('ai_pending', 'awaiting_input'))
         >= security.pipeline_num_v1('har.open_max_per_lane', 150) then
      return jsonb_build_object('raised', false, 'reason', 'lane ' || c.lane || ' is at its open limit (har.open_max_per_lane)');
    end if;
    v_status := case when c.interpretative and security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 then 'ai_pending' else 'awaiting_input' end;
    insert into pipeline.layer4_interventions(lane, entity, missing_fact, provider_id, course_id, field, subject, status, issue, evidence, required_input, recommended,
                allowed_actions, resume_target, fingerprint, automated_attempts, assigned_to, next_action_at, escalate_at, recover_by)
    values (c.lane, v_ent, c.code, nullif(p->>'provider_id', '')::uuid, nullif(p->>'course_id', '')::uuid, nullif(p->>'field', ''), coalesce(nullif(p->>'subject', ''), c.title),
            v_status, v_issue, v_ev, v_req, v_rec, c.allowed_actions, jsonb_build_object('operation', p->'resume_target'->>'operation', 'work_item', v_wi), v_fp, v_att,
            security.har_text_v1('har.' || c.code || '.assigned_to', 'Layer 4 reviewer'),
            now() + make_interval(hours => security.har_num_v1(c.code, 'recheck_hours', 24)::int),
            now() + make_interval(hours => security.har_num_v1(c.code, 'escalate_after_hours', 72)::int),
            now() + make_interval(hours => security.har_num_v1(c.code, 'deadline_hours', 168)::int))
    returning * into i;
    perform security.har_event_v1(i.id, 'raised', jsonb_build_object('class', c.code, 'attempts', v_att), jsonb_build_object('fingerprint', v_fp), null, v_status);
  end if;
  -- §6: the work waits for the person without a lease or a next attempt; other work continues
  v_res := security.work_item_report_v1(v_wi->>'lane', v_wi->>'entity', v_wi->>'kind', 'review',
             jsonb_build_object('review_ref', 'intervention:' || i.id, 'provider_id', i.provider_id, 'field', i.field, 'owner', 'layer4_intervention',
                                'reason', 'waiting for human input: ' || c.title));
  select w.id into v_wid from pipeline.work_items w where w.lane = v_wi->>'lane' and w.entity = v_wi->>'entity' and w.work_kind = v_wi->>'kind';
  update pipeline.layer4_interventions set work_item_id = v_wid where id = i.id and work_item_id is distinct from v_wid;
  return jsonb_build_object('raised', true, 'id', i.id, 'status', i.status, 'work_item', v_wid);
end $function$;
revoke all on function security.layer4_intervention_raise_v1(jsonb) from public, anon, authenticated;
comment on function security.layer4_intervention_raise_v1(jsonb) is 'CF-247 human-assisted recovery (decision 06:30 §1 steps 6-8): the one way a lane asks for human input; deduplicated by (lane, entity, missing fact) and the failure''s fingerprint; links the work item (awaiting review, no lease). Lanes outside AER and scholarships call it from their own failure handling.';

-- 5 resolve: the one server function behind every reviewer action (§2, §3, §7) -----------------------------------------------------------------
create or replace function security.har_work_item_v1(p_id bigint, p_event text, p_detail jsonb) returns void
language plpgsql security definer set search_path to '' as $function$
-- reports to the intervention's work item, but hands shared work back ('decided') only when no other intervention on it still waits
declare i pipeline.layer4_interventions; v_wi jsonb;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  v_wi := i.resume_target->'work_item';
  if v_wi is null then return; end if;
  if p_event = 'decided' and exists (select 1 from pipeline.layer4_interventions x where x.id <> i.id and x.status in ('ai_pending', 'awaiting_input')
                                       and x.resume_target->'work_item' = v_wi) then return; end if;
  perform security.work_item_report_v1(v_wi->>'lane', v_wi->>'entity', v_wi->>'kind', p_event, coalesce(p_detail, '{}'::jsonb));
end $function$;
revoke all on function security.har_work_item_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.layer4_intervention_resolve_v1(p_id bigint, p_action text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 human-assisted recovery (decision 06:30 §2, §3, §7). p_payload: {value, reason}. The eleven actions of §2:
--   provide_url, attach_document, enter_value, confirm_identity, select_source, confirm_scope, correct_value, search_again (handled by the
--   lane's validator and resume handler), confirm_not_published (evidence-backed close), return_technical (back to the lane's technical
--   recovery), reject_evidence (refuses the evidence or AI suggestion on the card; the item keeps waiting).
-- Checks: a signed-in reviewer, the action offered on this item, the rank it needs, a reason. Input that fails validation updates the same item
-- with a specific request. Valid input is recorded with its provenance (pipeline.layer4_intervention_values: a proposal, never an admitted
-- value), the dependency is marked resolved, and the lane's resume handler schedules the next operation (while har.resume_on is 1). Nothing here
-- publishes: a URL or document is never approval to publish. Every call is audited.
declare i pipeline.layer4_interventions; c pipeline.layer4_intervention_classes; h pipeline.layer4_intervention_handlers; v_rank int; v_need int;
        v_reason text := btrim(coalesce(p_payload->>'reason', '')); v_valid jsonb; v_res jsonb; v_vid bigint; v_norm jsonb; v_out jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.pipeline_num_v1('har.on', 1) < 1 then raise exception 'human-assisted recovery is switched off (har.on is 0)'; end if;
  if coalesce(p_action, '') not in ('provide_url', 'attach_document', 'enter_value', 'confirm_identity', 'select_source', 'confirm_scope', 'correct_value',
                                    'search_again', 'confirm_not_published', 'return_technical', 'reject_evidence') then
    raise exception 'unknown action %', p_action using errcode = '22023';
  end if;
  v_rank := security.current_role_rank();
  select * into i from pipeline.layer4_interventions where id = p_id for update;
  if not found then raise exception 'no intervention %', p_id using errcode = 'P0002'; end if;
  if i.status <> 'awaiting_input' then raise exception 'this intervention is no longer waiting for input (%)', i.status; end if;
  if not (i.allowed_actions ? p_action) then raise exception 'this action is not offered for this intervention'; end if;
  v_need := (i.allowed_actions->>p_action)::int;
  if v_rank < v_need then raise exception 'your role cannot take this action (it needs rank %)', v_need using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept with the decision)'; end if;
  select * into c from pipeline.layer4_intervention_classes where code = i.missing_fact;
  select * into h from pipeline.layer4_intervention_handlers where lane = i.lane;
  if not found then raise exception 'no resume handler is registered for lane %', i.lane; end if;

  if p_action = 'return_technical' then
    update pipeline.layer4_interventions set status = 'returned_technical', closed_fingerprint = fingerprint, resolved_by = auth.uid(), input_at = now(),
           verified_outcome = 'returned_to_technical_recovery', outcome_detail = jsonb_build_object('reason', v_reason), updated_at = now() where id = i.id;
    perform security.har_work_item_v1(i.id, 'decided', '{}'::jsonb);
    perform security.har_event_v1(i.id, p_action, p_payload, '{}'::jsonb, i.status, 'returned_technical');
    return jsonb_build_object('ok', true, 'status', 'returned_technical', 'returns', 'The work goes back to its technical recovery; the same failure is not asked again unless it changes');
  elsif p_action = 'reject_evidence' then
    update pipeline.layer4_interventions set ai_analysis = coalesce(ai_analysis, '{}'::jsonb) || jsonb_build_object('rejected_by_reviewer', jsonb_build_object('at', now(), 'reason', v_reason)),
           recommended = (recommended - 'suggested') || jsonb_build_object('rejected_suggestion', recommended->'suggested'), updated_at = now() where id = i.id;
    perform security.har_event_v1(i.id, p_action, p_payload, '{}'::jsonb, i.status, i.status);
    return jsonb_build_object('ok', true, 'status', 'awaiting_input', 'returns', 'The evidence or suggestion is refused and kept on record; the item still waits for the missing input');
  elsif p_action = 'confirm_not_published' then
    v_valid := security.har_official_url_v1(p_payload->>'value', i.provider_id);
    if not coalesce((v_valid->>'ok')::boolean, false) then
      update pipeline.layer4_interventions set required_input = required_input || jsonb_build_object('follow_up', 'Evidence for "not published": ' || (v_valid->>'reason'), 'follow_up_at', now()),
             updated_at = now() where id = i.id;
      perform security.har_event_v1(i.id, 'insufficient', p_payload, v_valid, i.status, i.status);
      return jsonb_build_object('ok', false, 'status', 'awaiting_input', 'request', v_valid->>'reason');
    end if;
    insert into pipeline.layer4_intervention_values(intervention_id, lane, entity, field, value, quote, source_url, evidence_id, actor, state, state_at)
    values (i.id, i.lane, i.entity, 'not_published', jsonb_build_object('confirmed', true, 'reason', v_reason), p_payload->>'quote', v_valid->>'url',
            nullif(v_valid->>'stored_copy', '')::uuid, auth.uid(), 'proposed', now()) returning id into v_vid;
    update pipeline.layer4_interventions set status = 'not_published', closed_fingerprint = fingerprint, resolved_by = auth.uid(), input_at = now(), verified_at = now(),
           verified_outcome = 'evidenced_not_published', supplied = jsonb_build_object('value_id', v_vid, 'evidence_url', v_valid->>'url'), updated_at = now() where id = i.id;
    perform security.har_work_item_v1(i.id, 'succeeded', jsonb_build_object('outcome', 'not_needed'));
    perform security.har_event_v1(i.id, p_action, p_payload, v_valid, i.status, 'not_published');
    return jsonb_build_object('ok', true, 'status', 'not_published', 'returns', 'Recorded as not published, with your evidence; nothing is admitted or published');
  end if;

  -- the lane's validator: identity, official host, provenance, field rules, ownership
  execute format('select %s($1, $2, $3)', (h.validate_fn::oid)::regproc) into v_valid using i.id, p_action, p_payload;
  if not coalesce((v_valid->>'valid')::boolean, false) then
    update pipeline.layer4_interventions set required_input = required_input || jsonb_build_object('follow_up', coalesce(v_valid->>'request', 'the input could not be validated'), 'follow_up_at', now()),
           updated_at = now() where id = i.id;
    perform security.har_event_v1(i.id, 'insufficient', p_payload, v_valid, i.status, i.status);
    return jsonb_build_object('ok', false, 'status', 'awaiting_input', 'request', v_valid->>'request');
  end if;
  v_norm := coalesce(v_valid->'normalised', '{}'::jsonb);
  insert into pipeline.layer4_intervention_values(intervention_id, lane, entity, field, value, quote, source_url, evidence_id, actor)
  values (i.id, i.lane, i.entity, coalesce(v_norm->>'field', p_action), v_norm, v_norm->>'quote', v_norm->>'url', nullif(v_norm->>'stored_copy', '')::uuid, auth.uid())
  returning id into v_vid;
  update pipeline.layer4_interventions set status = 'resuming', supplied = v_norm || jsonb_build_object('action', p_action, 'value_id', v_vid, 'reason', v_reason),
         resolved_by = auth.uid(), input_at = now(), required_input = required_input - 'follow_up' - 'follow_up_at',
         next_action_at = now() + make_interval(hours => security.pipeline_num_v1('har.verify_after_hours', 24)::int), updated_at = now() where id = i.id;
  if security.pipeline_num_v1('har.resume_on', 1) >= 1 then
    execute format('select %s($1, $2, $3)', (h.resume_fn::oid)::regproc) into v_res using i.id, p_action, v_norm;
  else
    v_res := jsonb_build_object('scheduled', false, 'held', 'har.resume_on is 0: the valid input waits');
  end if;
  update pipeline.layer4_interventions set resumed_at = case when coalesce((v_res->>'scheduled')::boolean, false) then now() end,
         outcome_detail = jsonb_build_object('resume', v_res), updated_at = now() where id = i.id;
  perform security.har_work_item_v1(i.id, 'decided', '{}'::jsonb);  -- the dependency is resolved: the lane may take its work again
  v_out := jsonb_build_object('ok', true, 'status', 'resuming', 'validation', v_valid, 'resume', v_res, 'returns', c.unblocks);
  perform security.har_event_v1(i.id, p_action, p_payload, v_out, i.status, 'resuming');
  return v_out;
end $function$;
revoke all on function security.layer4_intervention_resolve_v1(bigint, text, jsonb) from public, anon, authenticated;
comment on function security.layer4_intervention_resolve_v1(bigint, text, jsonb) is 'CF-247 human-assisted recovery (decision 06:30 §2, §7): the one server function behind the eleven reviewer actions on a "Human input needed" item; validates through the lane''s handler, records provenance, resumes the work; never admits or publishes; audited.';

-- 6 the stronger-model step (§1 steps 4-5; ships off) ----------------------------------------------------------------------------------------
create or replace function security.har_class_issue_v1(p_lane text, p_class text, p_reason text) returns bigint
language plpgsql security definer set search_path to '' as $function$
-- one integration issue per lane and class (har:<lane>:<class>); an unchanged class never raises another; a closed one reopens on recurrence
declare c pipeline.layer4_intervention_classes; v_n int; v_old timestamptz; v_provs uuid[]; v_res jsonb;
begin
  select * into c from pipeline.layer4_intervention_classes where code = p_class;
  select count(*), min(created_at), array_agg(distinct provider_id) filter (where provider_id is not null) into v_n, v_old, v_provs
    from pipeline.layer4_interventions where lane = p_lane and missing_fact = p_class and status in ('ai_pending', 'awaiting_input', 'resuming');
  v_res := security.integration_issue_upsert_v1(jsonb_build_object(
    'fingerprint', 'har:' || p_lane || ':' || p_class, 'severity', 'P2', 'layer', 'Platform', 'subsystem', 'human-assisted recovery: ' || p_lane,
    'title', 'Human input needed: ' || c.title || ' (' || v_n || ' open)',
    'failure', v_n || ' intervention(s) of class ' || p_class || ' in lane ' || p_lane || ' wait for human input or verification; oldest since ' || coalesce(v_old::text, '-') || '. ' || coalesce(p_reason, ''),
    'expected', 'A reviewer supplies the missing input in Layer 4 (Human input needed) and the platform resumes the work by itself.',
    'source', 'layer4-interventions', 'validation_layer', 'V3', 'root_cause_class', 'human_decision', 'workstream', 'A10',
    'provider_ids', to_jsonb(coalesce(v_provs[1:50], '{}'::uuid[])),
    'evidence', jsonb_build_object('lane', p_lane, 'class', p_class, 'open', v_n, 'oldest', v_old, 'reason', p_reason)), 'layer4-interventions');
  return (v_res->>'id')::bigint;
end $function$;
revoke all on function security.har_class_issue_v1(text, text, text) from public, anon, authenticated;

create or replace function security.har_ai_proposals_v1(p_id bigint, p_answer jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- §1 step 5 and "AI must not invent source URLs, scores, eligibility, fees or admission decisions": a proposed address must be on the
-- provider's own site AND already present in evidence the platform holds (a stored copy of it, or a link on the card); a proposed value or
-- scope must carry a quotation of the minimum length and a source on the provider's site. Everything else is refused, with the reason.
declare i pipeline.layer4_interventions; p jsonb; v_ok jsonb := '[]'::jsonb; v_no jsonb := '[]'::jsonb; v_u jsonb;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  for p in select x from jsonb_array_elements(case when jsonb_typeof(p_answer->'proposals') = 'array' then p_answer->'proposals' else '[]'::jsonb end) x loop
    if nullif(p->>'url', '') is not null then
      v_u := security.har_official_url_v1(p->>'url', i.provider_id);
      if not coalesce((v_u->>'ok')::boolean, false) then v_no := v_no || jsonb_build_array(p || jsonb_build_object('refused', v_u->>'reason')); continue; end if;
      if v_u->>'stored_copy' is null and position(p->>'url' in i.evidence::text) = 0
         and not exists (select 1 from pipeline.evidence_artifacts e where e.source_url = p->>'url') then
        v_no := v_no || jsonb_build_array(p || jsonb_build_object('refused', 'the address is not in any evidence the platform holds (an AI may not invent an address)')); continue;
      end if;
    end if;
    if p->>'kind' in ('value', 'scope', 'identity') and not security.har_quote_ok_v1(p->>'quote') then
      v_no := v_no || jsonb_build_array(p || jsonb_build_object('refused', 'no quotation from the official page')); continue;
    end if;
    v_ok := v_ok || jsonb_build_array(p);
  end loop;
  return jsonb_build_object('validated', v_ok, 'refused', v_no);
end $function$;
revoke all on function security.har_ai_proposals_v1(bigint, jsonb) from public, anon, authenticated;

create or replace function security.har_ai_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- One request per interpretative intervention (status ai_pending) on the existing ops_diagnose worker lane, while har.ai_escalate_on and
-- ops.ai_diagnosis_on are 1, a pinned model is set (har.ai_escalation_model), security.ai_use_refusal_v1('ops_diagnose') allows it (credit
-- floor, daily ceiling, lane guard) and fewer than har.ai_requests_per_day were queued today. Answers are validated (security.har_ai_proposals_v1)
-- and offered only as a suggestion. When the step is off, or the answer is late, the item goes to the reviewer without it (never stuck).
declare r record; v_on boolean := security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 and security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1;
        v_model text := security.har_text_v1('har.ai_escalation_model', ''); v_refusal text; v_q int := 0; v_t int := 0; v_s int := 0; v_issue bigint; v_req bigint;
        v_p jsonb; v_best jsonb; v_lim int := security.pipeline_num_v1('batch.har_verify', 200)::int;
begin
  v_refusal := case when not v_on then 'the stronger-model step is off (har.ai_escalate_on or ops.ai_diagnosis_on is 0)'
                    when v_model = '' then 'no escalation model is pinned (har.ai_escalation_model)'
                    else security.ai_use_refusal_v1('ops_diagnose') end;
  for r in select i.* from pipeline.layer4_interventions i where i.status = 'ai_pending' order by i.updated_at limit v_lim loop
    if r.ai_analysis ? 'request_id' then
      select to_jsonb(q) into v_p from pipeline.ops_ai_diagnosis_requests q where q.id = (r.ai_analysis->>'request_id')::bigint;
      if v_p->>'state' = 'answered' then
        v_p := v_p || jsonb_build_object('checked', security.har_ai_proposals_v1(r.id, v_p->'answer'));
        select x into v_best from jsonb_array_elements(v_p->'checked'->'validated') x
         where coalesce((x->>'confidence')::numeric, 0) >= security.pipeline_num_v1('har.ai_min_confidence', 0.7) order by (x->>'confidence')::numeric desc limit 1;
        update pipeline.layer4_interventions set status = 'awaiting_input', updated_at = now(),
               ai_analysis = r.ai_analysis || jsonb_build_object('model', v_p->>'model', 'answered_at', v_p->>'answered_at', 'analysis', v_p->'answer'->>'analysis',
                             'confidence', v_p->'answer'->'confidence', 'uncertainty', v_p->'answer'->'uncertainty', 'validated', v_p->'checked'->'validated', 'refused', v_p->'checked'->'refused'),
               recommended = recommended || case when v_best is not null then jsonb_build_object('suggested', v_best || jsonb_build_object('from', 'AI, validated against official evidence; not a decision')) else '{}'::jsonb end
         where id = r.id;
        perform security.har_event_v1(r.id, 'ai_answered', '{}'::jsonb, v_p->'checked', 'ai_pending', 'awaiting_input');
        v_t := v_t + 1;
      elsif v_p->>'state' = 'refused' or r.updated_at < now() - make_interval(hours => security.pipeline_num_v1('har.ai_wait_hours', 6)::int) then
        update pipeline.layer4_interventions set status = 'awaiting_input', ai_analysis = r.ai_analysis || jsonb_build_object('skipped', 'the AI request was refused or late'), updated_at = now() where id = r.id;
        perform security.har_event_v1(r.id, 'ai_skipped', '{}'::jsonb, jsonb_build_object('state', v_p->>'state'), 'ai_pending', 'awaiting_input');
        v_s := v_s + 1;
      end if;
    elsif v_refusal is not null or v_q >= greatest(0, security.pipeline_num_v1('har.ai_requests_per_day', 10)
                                        - (select count(*) from pipeline.layer4_intervention_events e where e.action = 'ai_requested' and e.at >= date_trunc('day', now()))) then
      update pipeline.layer4_interventions set status = 'awaiting_input', ai_analysis = coalesce(r.ai_analysis, '{}'::jsonb) || jsonb_build_object('skipped', coalesce(v_refusal, 'the day''s escalation requests are used')),
             updated_at = now() where id = r.id;
      perform security.har_event_v1(r.id, 'ai_skipped', '{}'::jsonb, jsonb_build_object('reason', coalesce(v_refusal, 'daily requests used')), 'ai_pending', 'awaiting_input');
      v_s := v_s + 1;
    else
      v_issue := coalesce(r.integration_issue_id, security.har_class_issue_v1(r.lane, r.missing_fact, 'stronger-model escalation'));
      insert into pipeline.ops_ai_diagnosis_requests(issue_id, context, model, note)
      values (v_issue, jsonb_build_object('contract', 'har_intervention_v1', 'intervention_id', r.id, 'model', v_model, 'class', r.missing_fact, 'subject', r.subject,
                'question', r.required_input->>'ask', 'issue', r.issue, 'evidence', r.evidence,
                'instructions', 'Use only the evidence given. Never invent an address, score, eligibility, fee or decision. Propose an address only if it appears in the evidence; give a quotation for every value.',
                'answer_schema', jsonb_build_object('analysis', 'text', 'confidence', '0..1', 'uncertainty', 'text',
                                                    'proposals', '[{kind: url|value|scope|identity, url, value, quote, confidence}]')),
              v_model, 'human-assisted recovery escalation') returning id into v_req;
      update pipeline.layer4_interventions set integration_issue_id = v_issue, ai_analysis = coalesce(r.ai_analysis, '{}'::jsonb) || jsonb_build_object('request_id', v_req, 'model', v_model),
             updated_at = now() where id = r.id;
      perform security.har_event_v1(r.id, 'ai_requested', '{}'::jsonb, jsonb_build_object('request_id', v_req, 'model', v_model), 'ai_pending', 'ai_pending');
      v_q := v_q + 1;
    end if;
  end loop;
  return jsonb_build_object('requested', v_q, 'taken', v_t, 'skipped', v_s, 'held', v_refusal);
end $function$;
revoke all on function security.har_ai_tick_v1() from public, anon, authenticated;

-- 7 the job: raise, escalate to the stronger model, verify resumed work, recheck, escalate (§1, §6, §7) -------------------------------------
create or replace function security.layer4_interventions_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 human-assisted recovery (decision 06:30 §1, §6, §7). Job layer4-interventions. Each step is isolated: a failing lane or item never
-- stops the others.
--   1 each lane's generator (while its switch is 1) raises at most batch.har_generate failures;
--   2 the stronger-model step (security.har_ai_tick_v1; off unless switched on);
--   3 resumed work is verified by the lane's verify_fn: succeeded -> resolved (admitted and published recorded when they happen), the work
--     item succeeds and the class's integration issue closes when nothing of it is still open; failed, or no result after har.verify_after_hours
--     -> the same intervention returns to the reviewer with what happened, and the class's issue is (re)opened;
--   4 waiting items whose recheck is due: the lane's recheck_fn; a cleared failure closes without a person;
--   5 items unanswered past their class's escalate_after_hours are escalated once, as one integration issue per lane and class.
declare h record; r record; v jsonb; v_gen jsonb := '{}'::jsonb; v_ai jsonb; v_lim int := security.pipeline_num_v1('batch.har_generate', 40)::int;
        v_vlim int := security.pipeline_num_v1('batch.har_verify', 200)::int; v_ok int := 0; v_back int := 0; v_wait int := 0; v_clear int := 0; v_esc int := 0; v_err int := 0;
        v_issue bigint; v_req text;
begin
  if security.pipeline_num_v1('har.on', 1) < 1 then return jsonb_build_object('held', 'har.on is 0'); end if;
  for h in select * from pipeline.layer4_intervention_handlers x where x.generate_fn is not null order by x.lane loop
    if h.generate_switch is not null and security.pipeline_num_v1(h.generate_switch, 0) < 1 then
      v_gen := v_gen || jsonb_build_object(h.lane, jsonb_build_object('held', h.generate_switch || ' is 0')); continue;
    end if;
    begin
      execute format('select %s($1)', (h.generate_fn::oid)::regproc) into v using v_lim;
      v_gen := v_gen || jsonb_build_object(h.lane, v);
    exception when others then v_gen := v_gen || jsonb_build_object(h.lane, jsonb_build_object('error', left(sqlerrm, 200)));
    end;
  end loop;
  begin v_ai := security.har_ai_tick_v1(); exception when others then v_ai := jsonb_build_object('error', left(sqlerrm, 200)); end;

  for r in select i.id, i.lane, i.missing_fact, i.next_action_at, i.integration_issue_id, x.verify_fn from pipeline.layer4_interventions i
             join pipeline.layer4_intervention_handlers x on x.lane = i.lane where i.status = 'resuming' order by i.updated_at limit v_vlim loop
    begin
      execute format('select %s($1)', (r.verify_fn::oid)::regproc) into v using r.id;
      if v->>'state' = 'succeeded' then
        update pipeline.layer4_interventions set status = 'resolved', closed_fingerprint = fingerprint, verified_at = now(),
               verified_outcome = coalesce(v->>'outcome', 'succeeded_with_result'),
               admitted_at = case when coalesce((v->>'admitted')::boolean, false) then coalesce(admitted_at, now()) end,
               published_at = case when coalesce((v->>'published')::boolean, false) then coalesce(published_at, now()) end,
               outcome_detail = coalesce(outcome_detail, '{}'::jsonb) || jsonb_build_object('verify', v), updated_at = now() where id = r.id;
        perform security.har_work_item_v1(r.id, 'succeeded', jsonb_build_object('outcome', 'succeeded_with_result'));
        perform security.har_event_v1(r.id, 'verified', '{}'::jsonb, v, 'resuming', 'resolved');
        if r.integration_issue_id is not null and not exists (select 1 from pipeline.layer4_interventions x where x.integration_issue_id = r.integration_issue_id
                                                                and x.status in ('ai_pending', 'awaiting_input', 'resuming')) then
          perform security.integration_issue_close_v1(r.integration_issue_id, 'layer4-interventions', jsonb_build_object('outcome', 'passed', 'checked_at', now(),
                    'evidence', 'Every intervention of this class was answered and its resumed work verified by security.layer4_interventions_tick_v1 (last: intervention ' || r.id || ').',
                    'verify', v));
        end if;
        v_ok := v_ok + 1;
      elsif v->>'state' = 'failed' or r.next_action_at < now() then
        v_req := coalesce(v->>'request', 'The input was taken, but the resumed work has not produced its result (' || coalesce(v->>'evidence', v::text) || '). Check the input or give another source.');
        update pipeline.layer4_interventions set status = 'awaiting_input', reopen_count = reopen_count + 1,
               required_input = required_input || jsonb_build_object('follow_up', left(v_req, 600), 'follow_up_at', now()),
               outcome_detail = coalesce(outcome_detail, '{}'::jsonb) || jsonb_build_object('verify', v),
               next_action_at = now() + make_interval(hours => security.har_num_v1(missing_fact, 'recheck_hours', 24)::int), updated_at = now() where id = r.id;
        perform security.har_work_item_v1(r.id, 'review', jsonb_build_object('review_ref', 'intervention:' || r.id, 'reason', 'resumed work did not produce its result'));
        perform security.har_event_v1(r.id, 'resume_failed', '{}'::jsonb, v, 'resuming', 'awaiting_input');
        if r.integration_issue_id is not null then
          v_issue := security.har_class_issue_v1(r.lane, r.missing_fact, 'resumed work failed verification (intervention ' || r.id || ')');
        end if;
        v_back := v_back + 1;
      else
        v_wait := v_wait + 1;
      end if;
    exception when others then v_err := v_err + 1;
      perform security.har_event_v1(r.id, 'verify_error', '{}'::jsonb, jsonb_build_object('error', left(sqlerrm, 300)), 'resuming', 'resuming');
    end;
  end loop;

  for r in select i.id, i.status, i.missing_fact, x.recheck_fn from pipeline.layer4_interventions i join pipeline.layer4_intervention_handlers x on x.lane = i.lane
            where i.status in ('ai_pending', 'awaiting_input') and i.next_action_at <= now() order by i.next_action_at limit v_vlim loop
    begin
      execute format('select %s($1)', (r.recheck_fn::oid)::regproc) into v using r.id;
      if coalesce((v->>'cleared')::boolean, false) then
        update pipeline.layer4_interventions set status = 'auto_resolved', closed_fingerprint = fingerprint, verified_at = now(), verified_outcome = 'cleared_without_input',
               outcome_detail = coalesce(outcome_detail, '{}'::jsonb) || jsonb_build_object('recheck', v), updated_at = now() where id = r.id;
        perform security.har_work_item_v1(r.id, 'decided', '{}'::jsonb);
        perform security.har_event_v1(r.id, 'recheck_cleared', '{}'::jsonb, v, r.status, 'auto_resolved');
        v_clear := v_clear + 1;
      else
        update pipeline.layer4_interventions set next_action_at = now() + make_interval(hours => security.har_num_v1(r.missing_fact, 'recheck_hours', 24)::int) where id = r.id;
      end if;
    exception when others then v_err := v_err + 1;
    end;
  end loop;

  for r in select i.lane, i.missing_fact from pipeline.layer4_interventions i
            where i.status in ('ai_pending', 'awaiting_input') and i.escalate_at <= now() and i.escalated_at is null group by 1, 2 loop
    begin
      v_issue := security.har_class_issue_v1(r.lane, r.missing_fact, 'unanswered past har.' || r.missing_fact || '.escalate_after_hours');
      update pipeline.layer4_interventions set escalated_at = now(), integration_issue_id = v_issue, updated_at = now()
       where lane = r.lane and missing_fact = r.missing_fact and status in ('ai_pending', 'awaiting_input') and escalate_at <= now() and escalated_at is null;
      v_esc := v_esc + 1;
    exception when others then v_err := v_err + 1;
    end;
  end loop;
  return jsonb_build_object('generated', v_gen, 'ai', v_ai, 'verified', v_ok, 'returned_to_reviewer', v_back, 'waiting_result', v_wait,
                            'cleared', v_clear, 'escalated_classes', v_esc, 'errors', v_err);
end $function$;
revoke all on function security.layer4_interventions_tick_v1() from public, anon, authenticated;
comment on function security.layer4_interventions_tick_v1() is 'CF-247 human-assisted recovery (decision 06:30 §1, §6, §7): job layer4-interventions: raises interventions per lane (bounded, fair), runs the stronger-model step (off), verifies resumed work and closes or reopens, rechecks waiting items, escalates unanswered classes once.';

-- 8 AER (lanes aer_source and aer_course): validate, resume, verify, recheck, generate (§4) ------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'har.aer_empty_read_lookback_hours', 'Human-assisted recovery: course reads looked back over (AER)',
  'A university whose scheduled course reads in this window found no entry requirement (as many reads as har.aer_empty_read.max_attempts or more) is asked for its course mapping.',
  'number', to_jsonb(48), 6, 720, 'hours', 1517, 'Human-assisted recovery', 'security.har_aer_generate_v1', 'Morning measures 4 Nov 2026: CDU read 6 times with 0 rows')
on conflict (toolset_key, key) do nothing;

create or replace function security.har_aer_validate_v1(p_id bigint, p_action text, p_payload jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- AER input: an address or document must be on the university's own site (security.har_official_url_v1), and not a source that already
-- failed every read with no stored copy; a scope needs scope university_wide or course_specific and a quotation; an identity must be an
-- active course of the same university (by course code or id).
declare i pipeline.layer4_interventions; v jsonb; v_val text := btrim(coalesce(p_payload->>'value', '')); j jsonb; s record; v_c record;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_action in ('provide_url', 'attach_document', 'select_source') then
    v := security.har_official_url_v1(v_val, i.provider_id);
    if not coalesce((v->>'ok')::boolean, false) then return jsonb_build_object('valid', false, 'request', v->>'reason'); end if;
    select x.status, x.attempts, x.error into s from pipeline.entry_matrix_sources x where x.provider_id = i.provider_id and x.url = v->>'url';
    if found and s.status in ('failed', 'robots_disallowed') and s.attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) and v->>'stored_copy' is null then
      return jsonb_build_object('valid', false, 'request', 'This address was read before and could not be read (' || coalesce(s.error, s.status) || '). Give another official address or the document itself, or return the item to technical recovery.');
    end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'source_url', 'url', v->>'url', 'document', (v->>'document')::boolean, 'stored_copy', v->>'stored_copy'));
  elsif p_action = 'confirm_scope' then
    begin j := v_val::jsonb; exception when others then j := jsonb_build_object('scope', v_val); end;
    if jsonb_typeof(j) <> 'object' then j := jsonb_build_object('scope', v_val); end if;
    if coalesce(j->>'scope', '') not in ('university_wide', 'course_specific') then
      return jsonb_build_object('valid', false, 'request', 'Say whether the requirement is university_wide or course_specific, with the official sentence that says so.');
    end if;
    if not security.har_quote_ok_v1(coalesce(j->>'quote', p_payload->>'quote')) then
      return jsonb_build_object('valid', false, 'request', 'Add the sentence from the official page that shows the scope (a quotation, so it can be checked).');
    end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'scope', 'scope', j->>'scope', 'quote', coalesce(j->>'quote', p_payload->>'quote')));
  elsif p_action = 'confirm_identity' then
    select c.id, c.course_code into v_c from catalogue.courses c
     where c.provider_id = i.provider_id and c.lifecycle_status = 'active' and (upper(c.course_code) = upper(v_val) or c.id::text = v_val) limit 1;
    if not found then return jsonb_build_object('valid', false, 'request', 'No active course of this university has the code or id "' || left(v_val, 60) || '". Give the course code shown on the course record.'); end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'course_id', 'course_id', v_c.id, 'course_code', v_c.course_code));
  end if;
  return jsonb_build_object('valid', false, 'request', 'This action is not used for entry requirements; choose one of the offered actions.');
end $function$;
revoke all on function security.har_aer_validate_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_aer_resume_v1(p_id bigint, p_action text, p_norm jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- AER resume: an address becomes the university's entry-requirement source (found_via manual: a person's source; status found), so the
-- existing entry-matrix-read job takes it, using a stored copy first (security.entry_matrix_use_stored_v1) and PDFs through the PDF step; its
-- first read goes to Layer 4 as usual. A source that failed is offered once more only when the validator found a stored copy. A scope or a
-- course identity hands the work item back to its lane (the scheduled course reader and the AER technical check). Nothing is admitted here.
declare i pipeline.layer4_interventions; v_sid uuid;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_norm ? 'url' then
    insert into pipeline.entry_matrix_sources as s(provider_id, url, title, rank, found_via, status)
    values (i.provider_id, p_norm->>'url', left('Layer 4 intervention ' || i.id || ': ' || i.subject, 300), 1, 'manual', 'found')
    on conflict (provider_id, url) do update set status = 'found', error = null, attempts = 0, updated_at = now()
     where s.status in ('failed', 'inactive', 'robots_disallowed')
    returning s.id into v_sid;
    if v_sid is null then select x.id into v_sid from pipeline.entry_matrix_sources x where x.provider_id = i.provider_id and x.url = p_norm->>'url'; end if;
    return jsonb_build_object('scheduled', true, 'operation', 'entry-matrix-read reads the attached source' || case when p_norm->>'stored_copy' is not null then ' from its stored copy (no new read bought)' else '' end,
                              'source_id', v_sid, 'stored_copy', p_norm->>'stored_copy');
  elsif p_norm ? 'course_id' then
    return jsonb_build_object('scheduled', true, 'operation', 'the held AER item returns to its technical check with the course confirmed', 'course_id', p_norm->>'course_id');
  elsif p_norm ? 'scope' then
    return jsonb_build_object('scheduled', true, 'operation', case p_norm->>'scope' when 'course_specific' then 'the scheduled course reader reads this university''s courses'
                                                                   else 'the university-wide rule is recorded with its quotation for the reader' end, 'scope', p_norm->>'scope');
  end if;
  return jsonb_build_object('scheduled', false, 'held', 'nothing to resume for this input');
end $function$;
revoke all on function security.har_aer_resume_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_aer_admitted_v1(p_provider uuid, p_since timestamptz) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- what of the university became active since the input (admitted by the existing Layer 4), and whether the website projection returns it
-- (public.website_v2_provider, read only; the consumer API is not changed)
  with a as (select (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = p_provider and m.status = 'active' and m.updated_at >= p_since)
                  + (select count(*) from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
                      where c.provider_id = p_provider and x.status = 'active' and x.updated_at >= p_since) n)
  select jsonb_build_object('admitted', a.n > 0, 'active_since_input', a.n,
           'published', a.n > 0 and to_regprocedure('public.website_v2_provider(text)') is not null
                        and coalesce(jsonb_array_length(case when jsonb_typeof(public.website_v2_provider((select p.stable_key from catalogue.providers p where p.id = p_provider))->'item'->'entry_matrix') = 'array'
                                                             then public.website_v2_provider((select p.stable_key from catalogue.providers p where p.id = p_provider))->'item'->'entry_matrix' end), 0) > 0)
    from a
$function$;
revoke all on function security.har_aer_admitted_v1(uuid, timestamptz) from public, anon, authenticated;

create or replace function security.har_aer_verify_v1(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- succeeded when the attached source was read and its read finished (it is then in Layer 4 or recorded as a general rule), or when the
-- university's courses got entry rows after the input; failed when the source could not be read or its read is held (with a specific request);
-- otherwise pending.
declare i pipeline.layer4_interventions; s record; m record; v_adm jsonb; v_rows int;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  v_adm := security.har_aer_admitted_v1(i.provider_id, coalesce(i.input_at, i.created_at));
  if i.supplied ? 'url' then
    select x.id, x.status, x.error into s from pipeline.entry_matrix_sources x where x.provider_id = i.provider_id and x.url = i.supplied->>'url';
    if not found then return jsonb_build_object('state', 'failed', 'request', 'The source was not attached; give the address again.'); end if;
    if s.status in ('failed', 'robots_disallowed') then
      return jsonb_build_object('state', 'failed', 'request', 'The address could not be read (' || coalesce(s.error, s.status) || '). Give another official address or the document, or return the item to technical recovery.', 'evidence', s.error);
    end if;
    select r.state, r.error, r.review_item_id into m from pipeline.entry_matrix_runs r where r.source_id = s.id order by r.created_at desc limit 1;
    if found and m.state = 'done' then
      return v_adm || jsonb_build_object('state', 'succeeded', 'outcome', case when m.review_item_id is not null then 'read_in_layer4' else 'read_recorded' end, 'review_item_id', m.review_item_id);
    elsif found and m.state = 'failed' then
      return jsonb_build_object('state', 'failed', 'request', 'The source was read but the read is held (' || coalesce(m.error, 'failed') || '). Select another official source or return the item to technical recovery.', 'evidence', m.error);
    end if;
    return jsonb_build_object('state', 'pending', 'evidence', 'source ' || s.status);
  end if;
  select count(*) into v_rows from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
   where c.provider_id = i.provider_id and x.status in ('proposed', 'active') and x.created_at >= coalesce(i.input_at, i.created_at);
  if v_rows > 0 then return v_adm || jsonb_build_object('state', 'succeeded', 'outcome', 'course_rows_proposed', 'rows', v_rows); end if;
  if i.missing_fact = 'aer_course_identity' and exists (select 1 from pipeline.work_items w where w.id = i.work_item_id and w.stage = 'done') then
    return v_adm || jsonb_build_object('state', 'succeeded', 'outcome', 'held_item_recovered');
  end if;
  return jsonb_build_object('state', 'pending', 'evidence', 'no course entry row since the input');
end $function$;
revoke all on function security.har_aer_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.har_aer_recheck_v1(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- §6 recheck condition (pipeline.layer4_intervention_classes.recheck_condition): the failure cleared without a person
declare i pipeline.layer4_interventions; v boolean;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  v := case
    when i.missing_fact in ('aer_source_missing', 'aer_document_unverified', 'aer_rendered_only') then
      exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = i.provider_id and s.status = 'read')
    when i.missing_fact = 'aer_empty_read' then
      exists (select 1 from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
               where c.provider_id = i.provider_id and x.status in ('proposed', 'active') and x.created_at >= i.created_at)
    when i.missing_fact = 'aer_read_held' then
      not exists (select 1 from pipeline.aer_provider_coverage a where a.provider_id = i.provider_id and a.disposition in ('source_held', 'reader_failed'))
    when i.missing_fact = 'aer_course_identity' then
      not exists (select 1 from pipeline.work_items w where w.id = i.work_item_id and w.stage in ('parked', 'quarantined', 'awaiting_review'))
           and not exists (select 1 from pipeline.layer4_review_items r where r.id::text = i.entity and r.status = 'pending')
    else false end;
  return jsonb_build_object('cleared', coalesce(v, false), 'condition', (select c.recheck_condition from pipeline.layer4_intervention_classes c where c.code = i.missing_fact));
end $function$;
revoke all on function security.har_aer_recheck_v1(bigint) from public, anon, authenticated;

create or replace function security.har_aer_generate_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- §4: AER interventions from what the platform already holds, followed universities first (coverage.aer_priority_providers, in their order),
-- then the most eligible courses; at most har.generate_per_provider_max new or changed items per university and p_limit in all:
--   aer_source_missing        the inventory says the official site refused the free read (Deakin), or the coverage ledger records an automatic
--                             discovery attempt and no source (attempts counted from its evidence: none are recorded for providers never searched);
--   aer_document_unverified   the official page names a document whose address could not be verified (ACU, CQU);
--   aer_rendered_only         the requirements load only in a selector (JCU);
--   aer_empty_read            the scheduled course reads of the window (aer_schedule_runs) found no course entry row (CDU);
--   aer_read_held             the university's source read is held or failed (UWA, RMIT and others in the coverage ledger);
--   aer_course_identity       a held AER item whose blocker is a page shared by another programme (parked aer_technical work).
-- Nothing is read from the web. A failure whose fingerprint is unchanged is skipped before it uses the batch.
declare r record; v_res jsonb; v_n int := 0; v_rep int := 0; v_skip int := 0; v_per int := security.pipeline_num_v1('har.generate_per_provider_max', 2)::int;
        v_look timestamptz := now() - make_interval(hours => security.pipeline_num_v1('har.aer_empty_read_lookback_hours', 48)::int);
begin
  for r in
    with followed as (select x::uuid pid, n from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'coverage.aer_priority_providers'), '[]'::jsonb)) with ordinality z(x, n)),
    rd as (select s.provider_id, count(*) filter (where s.status = 'read') nread from pipeline.entry_matrix_sources s group by 1),
    -- course reads of the window made after the university's newest course entry row (CDU: 8 reads since 3 Nov, the last 6 with no row)
    reads0 as (select (e->>'provider_id')::uuid pid, a.ran_at, e->>'course_id' course
                 from pipeline.aer_schedule_runs a cross join lateral jsonb_array_elements(case when jsonb_typeof(a.detail->'new') = 'array' then a.detail->'new' else '[]'::jsonb end) e
                where a.ran_at >= v_look and e ? 'provider_id'),
    reads as (select q.pid, count(*) n, min(q.ran_at) first_at, jsonb_agg(distinct q.course) courses
                from reads0 q
               where q.ran_at > coalesce((select max(x.created_at) from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where c.provider_id = q.pid), '-infinity'::timestamptz)
               group by 1),
    cand as (
      select i.provider_id, i.provider_id::text entity, null::uuid course_id,
             case i.outcome when 'blocked_site' then 'aer_source_missing' when 'unverified_link' then 'aer_document_unverified' else 'aer_rendered_only' end cls,
             greatest(1, coalesce(jsonb_array_length(case when jsonb_typeof(i.evidence->'tried') = 'array' then i.evidence->'tried' end), 1)) attempts,
             i.outcome || '|' || coalesce(i.url, '') || '|' || i.id sig,
             jsonb_build_object('official_links', to_jsonb(array_remove(array[i.url, i.evidence->>'landing'], null)),
                                'stored_copies', case when i.evidence ? 'stored_copy' then jsonb_build_array(i.evidence->'stored_copy') else '[]'::jsonb end,
                                'quotes', coalesce(case when jsonb_typeof(i.evidence->'quotes') = 'array' then i.evidence->'quotes' end,
                                                   case when i.evidence ? 'landing_quote' then jsonb_build_array(i.evidence->'landing_quote') end, '[]'::jsonb),
                                'attempts', coalesce(case when jsonb_typeof(i.evidence->'tried') = 'array' then i.evidence->'tried' end, '[]'::jsonb)
                                            || jsonb_build_array(jsonb_build_object('method', i.evidence->>'method', 'at', i.evidence->>'fetched', 'outcome', i.outcome, 'shape', i.shape)),
                                'conflicts', case when i.boundary is not null then jsonb_build_array(i.boundary) else '[]'::jsonb end) ev,
             jsonb_build_object('summary', 'No entry-requirement source of this university could be read automatically',
                                'attempted', jsonb_build_array('free discovery on the official site (' || coalesce(i.evidence->>'method', 'read') || ')', 'stored copies checked'),
                                'why_stopped', i.shape, 'impact', 'none of its courses can show international entry requirements') issue,
             case when i.evidence ? 'next' then jsonb_build_object('note', i.evidence->>'next') end suggested
        from pipeline.aer_source_inventory i
       where i.outcome in ('blocked_site', 'unverified_link', 'verified_rendered_only') and coalesce((select rd.nread from rd where rd.provider_id = i.provider_id), 0) = 0
      union all
      select c.provider_id, c.provider_id::text, null, 'aer_source_missing',
             coalesce((c.evidence->>'discovery_attempts')::int, case when c.discovery_state <> 'not_discovered' then 1 else 0 end),
             'ledger|' || c.disposition || '|' || coalesce(c.discovery_state, ''),
             jsonb_build_object('official_links', '[]'::jsonb, 'stored_copies', '[]'::jsonb, 'quotes', '[]'::jsonb,
                                'attempts', jsonb_build_array(jsonb_build_object('discovery', c.discovery_state, 'since', c.disposition_since)), 'conflicts', '[]'::jsonb),
             jsonb_build_object('summary', 'No entry-requirement source has been found for this provider', 'attempted', jsonb_build_array('automatic discovery: ' || coalesce(c.discovery_state, 'none')),
                                'why_stopped', 'no official requirements page was identified', 'impact', c.courses_eligible || ' eligible course(s) without entry requirements'),
             null::jsonb
        from pipeline.aer_provider_coverage c
       where c.eligible and c.disposition = 'not_discovered' and c.sources = 0
         and not exists (select 1 from pipeline.aer_source_inventory i where i.provider_id = c.provider_id)
      union all
      select c.provider_id, c.provider_id::text, null, 'aer_read_held', greatest(1, coalesce(c.runs_held, 0) + coalesce(c.runs_failed, 0)),
             'held|' || c.disposition || '|' || coalesce(c.last_run_id::text, '') || '|' || c.sources_read || '|' || c.sources_failed,
             jsonb_build_object('official_links', coalesce((select jsonb_agg(s.url order by s.rank) from pipeline.entry_matrix_sources s where s.provider_id = c.provider_id), '[]'::jsonb),
                                'stored_copies', coalesce((select jsonb_agg(s.evidence_id) from pipeline.entry_matrix_sources s where s.provider_id = c.provider_id and s.evidence_id is not null), '[]'::jsonb),
                                'quotes', '[]'::jsonb, 'attempts', jsonb_build_array(jsonb_build_object('runs_held', c.runs_held, 'runs_failed', c.runs_failed, 'root_causes', to_jsonb(c.root_causes))),
                                'conflicts', coalesce(c.held_scopes, '[]'::jsonb)),
             jsonb_build_object('summary', 'The read of this university''s entry-requirement source is held', 'attempted', jsonb_build_array('matrix reads and re-reads', 'completeness gates'),
                                'why_stopped', c.disposition || ': ' || coalesce(array_to_string(c.root_causes, ', '), 'see the held runs'), 'impact', 'its matrix rows cannot be admitted'),
             null::jsonb
        from pipeline.aer_provider_coverage c where c.eligible and c.disposition in ('source_held', 'reader_failed')
      union all
      select rr.pid, rr.pid::text, null, 'aer_empty_read', rr.n::int, 'empty|' || rr.n || '|' || rr.courses::text,
             jsonb_build_object('official_links', coalesce((select jsonb_agg(s.url) from pipeline.entry_matrix_sources s where s.provider_id = rr.pid), '[]'::jsonb), 'stored_copies', '[]'::jsonb,
                                'quotes', '[]'::jsonb, 'attempts', jsonb_build_array(jsonb_build_object('course_reads', rr.n, 'since', rr.first_at, 'courses', rr.courses)), 'conflicts', '[]'::jsonb),
             jsonb_build_object('summary', rr.n || ' course read(s) of this university found no entry requirement', 'attempted', jsonb_build_array('scheduled course reads (aer-scheduled-read)'),
                                'why_stopped', 'the course pages read do not state international entry requirements', 'impact', 'its courses stay without entry requirements'),
             null::jsonb
        from reads rr
       where not exists (select 1 from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where c.provider_id = rr.pid and x.created_at >= rr.first_at)
      union all
      select w.provider_id, w.entity, li.entity_id, 'aer_course_identity', greatest(w.total_attempts, 1), 'shared|' || coalesce(w.failure_fingerprint, ''),
             jsonb_build_object('official_links', '[]'::jsonb, 'stored_copies', case when li.evidence_id is not null then jsonb_build_array(li.evidence_id) else '[]'::jsonb end,
                                'quotes', '[]'::jsonb, 'attempts', w.evidence, 'conflicts', jsonb_build_array(w.evidence->-1->'evidence')),
             jsonb_build_object('summary', 'The course read is held: its page is shared with another programme', 'attempted', jsonb_build_array('course read', 'completeness gate (E13)'),
                                'why_stopped', w.evidence->-1->>'message', 'impact', 'the course''s entry requirement cannot be reviewed'),
             null::jsonb
        from pipeline.work_items w join pipeline.layer4_review_items li on li.id::text = w.entity
       where w.lane = 'aer_technical' and w.stage in ('parked', 'quarantined') and w.evidence::text ~* '(shared_page|another programme|other_programme)'),
    ranked as (select c.*, coalesce(f.n, 1000000) fo, coalesce(k.courses_eligible, 0) ce,
                      md5(c.cls || '|' || c.sig) fp, row_number() over (partition by c.provider_id order by c.cls) pn
                 from cand c left join followed f on f.pid = c.provider_id left join pipeline.aer_provider_coverage k on k.provider_id = c.provider_id
                where not exists (select 1 from pipeline.layer4_interventions x where x.lane = (select l.lane from pipeline.layer4_intervention_classes l where l.code = c.cls)
                                    and x.entity = c.entity and x.missing_fact = c.cls
                                    and (x.status in ('ai_pending', 'awaiting_input', 'resuming') and x.fingerprint = md5(c.cls || '|' || c.sig)
                                         or x.closed_fingerprint = md5(c.cls || '|' || c.sig))))
    select rk.*, coalesce(p.display_name, p.short_name, p.canonical_name) pname from ranked rk join catalogue.providers p on p.id = rk.provider_id
     where rk.pn <= v_per order by rk.fo, rk.ce desc, rk.provider_id, rk.cls limit greatest(coalesce(p_limit, 0), 0)
  loop
    v_res := security.layer4_intervention_raise_v1(jsonb_build_object('class', r.cls, 'entity', r.entity, 'provider_id', r.provider_id, 'course_id', r.course_id,
               'subject', r.pname || ': ' || (select l.title from pipeline.layer4_intervention_classes l where l.code = r.cls), 'attempts', r.attempts, 'signature', r.sig,
               'issue', r.issue, 'evidence', r.ev, 'suggested', r.suggested,
               'resume_target', case when r.cls = 'aer_course_identity' then jsonb_build_object('operation', 'AER technical check of the held item',
                                                                                                    'work_item', jsonb_build_object('lane', 'aer_technical', 'entity', r.entity, 'kind', 'l4_item'))
                                     else jsonb_build_object('operation', 'entry-matrix-read and the scheduled course reader') end));
    if coalesce((v_res->>'raised')::boolean, false) then v_n := v_n + 1; elsif coalesce((v_res->>'repeat')::boolean, false) then v_rep := v_rep + 1; else v_skip := v_skip + 1; end if;
  end loop;
  return jsonb_build_object('raised_or_changed', v_n, 'repeats', v_rep, 'not_raised', v_skip);
end $function$;
revoke all on function security.har_aer_generate_v1(int) from public, anon, authenticated;

-- 9 scholarship coverage (lane sch_coverage): the v2.15.460 states mapped onto interventions (§5) ---------------------------------------------
create or replace function security.har_sch_validate_v1(p_id bigint, p_action text, p_payload jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- an address must be on the provider's own site and not a directory site; an audience needs international or domestic_only and a quotation;
-- an owner must be an active provider (by id or exact name)
declare i pipeline.layer4_interventions; v jsonb; v_val text := btrim(coalesce(p_payload->>'value', '')); j jsonb; v_pid uuid[];
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_action in ('provide_url', 'select_source') then
    v := security.har_official_url_v1(v_val, i.provider_id);
    if not coalesce((v->>'ok')::boolean, false) then return jsonb_build_object('valid', false, 'request', v->>'reason'); end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'source_url', 'url', v->>'url', 'stored_copy', v->>'stored_copy'));
  elsif p_action = 'search_again' then
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'search_again'));
  elsif p_action in ('confirm_scope', 'correct_value') then
    begin j := v_val::jsonb; exception when others then j := jsonb_build_object('audience', v_val); end;
    if jsonb_typeof(j) <> 'object' then j := jsonb_build_object('audience', v_val); end if;
    if coalesce(j->>'audience', '') not in ('international', 'domestic_only') then
      return jsonb_build_object('valid', false, 'request', 'Say whether international students may apply (international) or not (domestic_only), with the sentence from the official page.');
    end if;
    if not security.har_quote_ok_v1(coalesce(j->>'quote', p_payload->>'quote')) then
      return jsonb_build_object('valid', false, 'request', 'Add the sentence from the official page that says who may apply (a quotation, so it can be checked).');
    end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'audience', 'audience', j->>'audience', 'quote', coalesce(j->>'quote', p_payload->>'quote'),
                                                                              'url', i.evidence->'official_links'->>0));
  elsif p_action = 'confirm_identity' then
    v_pid := array(select p.id from catalogue.providers p where p.lifecycle_status = 'active'
                    and (p.id::text = v_val or lower(coalesce(p.display_name, p.canonical_name)) = lower(v_val)) limit 2);
    if coalesce(array_length(v_pid, 1), 0) <> 1 then
      return jsonb_build_object('valid', false, 'request', 'Give the owning provider''s id or exact name (' || coalesce(array_length(v_pid, 1), 0) || ' active provider(s) match).');
    end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'owner_provider_id', 'owner_provider_id', v_pid[1]));
  end if;
  return jsonb_build_object('valid', false, 'request', 'This action is not used for scholarships; choose one of the offered actions.');
end $function$;
revoke all on function security.har_sch_validate_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_sch_resume_v1(p_id bigint, p_action text, p_norm jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- an address becomes a listing source (source manual: a person's), read by the scholarship listing reader within its caps; an audience
-- confirmation is kept as evidence and the candidate page is read again through Read again (requested_at, the documented route); "search
-- again" brings the provider's scholarship discovery forward; an ownership decision is recorded for the coverage lane. Nothing is admitted.
declare i pipeline.layer4_interventions; v_id bigint; v_cand bigint;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_norm->>'field' = 'source_url' then
    insert into pipeline.scholarship_listing_pages as l(provider_id, url, url_norm, source, active, status, next_read_at, added_by, added_at)
    values (i.provider_id, p_norm->>'url', security.scholarship_url_norm(p_norm->>'url'), 'manual', true, 'waiting', now(), auth.uid(), now())
    on conflict (provider_id, url_norm) do update set source = 'manual', active = true, status = 'waiting', next_read_at = now()
     where l.source = 'suggested' or not l.active or l.status = 'failed'
    returning l.id into v_id;
    if v_id is null then select x.id into v_id from pipeline.scholarship_listing_pages x where x.provider_id = i.provider_id and x.url_norm = security.scholarship_url_norm(p_norm->>'url'); end if;
    return jsonb_build_object('scheduled', true, 'operation', 'the scholarship listing reader reads the page', 'listing_id', v_id);
  elsif p_norm->>'field' = 'audience' then
    v_cand := case when i.entity ~ '\|cand:[0-9]+$' then substring(i.entity from '\|cand:([0-9]+)$')::bigint end;
    if v_cand is null then return jsonb_build_object('scheduled', false, 'held', 'no candidate page to read again'); end if;
    update pipeline.scholarship_page_candidates set requested_at = now() where id = v_cand;
    return jsonb_build_object('scheduled', found, 'operation', 'the candidate page is read again (Read again); your quotation is kept as evidence', 'candidate_id', v_cand);
  elsif p_norm->>'field' = 'search_again' then
    update pipeline.scholarship_discovery_providers set next_discover_at = now() where provider_id = i.provider_id;
    return jsonb_build_object('scheduled', found, 'operation', 'scholarship discovery looks at the provider again within its caps');
  elsif p_norm ? 'owner_provider_id' then
    return jsonb_build_object('scheduled', true, 'operation', 'ownership decision recorded for the scholarship coverage lane (pipeline.layer4_intervention_values)');
  end if;
  return jsonb_build_object('scheduled', false, 'held', 'nothing to resume for this input');
end $function$;
revoke all on function security.har_sch_resume_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_sch_verify_v1(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- succeeded when the coverage case left its state (classified again by scholarship-coverage-classify), when a supplied listing was read, or
-- when an ownership decision is recorded; failed when the supplied listing could not be read
declare i pipeline.layer4_interventions; v_pid uuid; v_key text; l record; v_adm int;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  v_pid := i.provider_id; v_key := split_part(i.entity, '|', 2);
  select count(*) into v_adm from pipeline.scholarship_page_candidates c where c.provider_id = v_pid and c.admitted_at >= coalesce(i.input_at, i.created_at);
  if i.supplied ? 'owner_provider_id' then return jsonb_build_object('state', 'succeeded', 'outcome', 'decision_recorded'); end if;
  if i.supplied->>'field' = 'source_url' then
    select x.status, x.read_at, x.error into l from pipeline.scholarship_listing_pages x where x.provider_id = v_pid and x.url_norm = security.scholarship_url_norm(i.supplied->>'url');
    if found and l.status = 'failed' then
      return jsonb_build_object('state', 'failed', 'request', 'The page could not be read (' || coalesce(l.error, 'failed') || '). Give another page on the provider''s site.');
    end if;
    if found and l.status = 'read' and l.read_at >= coalesce(i.input_at, i.created_at) then
      return jsonb_build_object('state', 'succeeded', 'outcome', 'listing_read', 'admitted', v_adm > 0);
    end if;
  end if;
  if not exists (select 1 from pipeline.scholarship_coverage_items x where x.provider_id = v_pid and x.item_key = v_key and x.present
                   and x.state = case i.missing_fact when 'sch_source_missing' then 'source_not_discovered' when 'sch_international_unresolved' then 'international_unresolved'
                                                     else 'ownership_conflict' end) then
    return jsonb_build_object('state', 'succeeded', 'outcome', 'coverage_state_moved', 'admitted', v_adm > 0);
  end if;
  return jsonb_build_object('state', 'pending', 'evidence', 'the coverage case is still ' || i.missing_fact);
end $function$;
revoke all on function security.har_sch_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.har_sch_recheck_v1(p_id bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('cleared', not exists (select 1 from pipeline.scholarship_coverage_items x
            where x.provider_id = i.provider_id and x.item_key = split_part(i.entity, '|', 2) and x.present
              and x.state = case i.missing_fact when 'sch_source_missing' then 'source_not_discovered' when 'sch_international_unresolved' then 'international_unresolved'
                                                else 'ownership_conflict' end))
    from pipeline.layer4_interventions i where i.id = p_id
$function$;
revoke all on function security.har_sch_recheck_v1(bigint) from public, anon, authenticated;

create or replace function security.har_sch_generate_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- §5: scholarship coverage cases (pipeline.scholarship_coverage_items, kept by job scholarship-coverage-classify) in three states become
-- interventions, for admission-eligible providers only (security.scholarship_admission_provider_ok_v1: policy exclusions are not asked about):
--   source_not_discovered    -> sch_source_missing (raised once discovery has run, or for a register entry with no candidate; the register's
--                               page, when on the provider's own site, is offered as the suggestion)
--   international_unresolved -> sch_international_unresolved (the AI verdict is the automated attempt)
--   ownership_conflict       -> sch_ownership_conflict (Platform Admin)
-- Fair: oldest case first, at most har.generate_per_provider_max per provider and p_limit in all; unchanged cases are skipped.
declare r record; v_res jsonb; v_n int := 0; v_rep int := 0; v_skip int := 0; v_per int := security.pipeline_num_v1('har.generate_per_provider_max', 2)::int;
begin
  for r in
    with cand as (
      select x.*, x.provider_id::text || '|' || x.item_key entity,
             case x.state when 'source_not_discovered' then 'sch_source_missing' when 'international_unresolved' then 'sch_international_unresolved' else 'sch_ownership_conflict' end cls,
             case when x.state = 'source_not_discovered' and x.item_key = 'provider' then case when coalesce(x.evidence->>'discovery', 'never queued') <> 'never queued' then 1 else 0 end
                  else 1 end attempts,
             x.state || '|' || coalesce(x.reason, '') || '|' || x.evidence::text sig
        from pipeline.scholarship_coverage_items x
       where x.present and x.state in ('source_not_discovered', 'international_unresolved', 'ownership_conflict')
         and coalesce(security.scholarship_admission_provider_ok_v1(x.provider_id), false)),
    ranked as (select c.*, row_number() over (partition by c.provider_id order by c.first_seen, c.item_key) pn from cand c
                where not exists (select 1 from pipeline.layer4_interventions i where i.lane = 'sch_coverage' and i.entity = c.entity and i.missing_fact = c.cls
                                    and (i.status in ('ai_pending', 'awaiting_input', 'resuming') and i.fingerprint = md5(c.cls || '|' || c.sig) or i.closed_fingerprint = md5(c.cls || '|' || c.sig))))
    select rk.*, coalesce(p.display_name, p.short_name, p.canonical_name) pname from ranked rk join catalogue.providers p on p.id = rk.provider_id
     where rk.pn <= v_per order by rk.first_seen, rk.provider_id, rk.item_key limit greatest(coalesce(p_limit, 0), 0)
  loop
    v_res := security.layer4_intervention_raise_v1(jsonb_build_object('class', r.cls, 'entity', r.entity, 'provider_id', r.provider_id,
               'subject', r.pname || ': ' || coalesce(r.evidence->>'name', r.evidence->>'title', r.evidence->>'item', (select l.title from pipeline.layer4_intervention_classes l where l.code = r.cls)),
               'attempts', r.attempts, 'signature', r.sig,
               'issue', jsonb_build_object('summary', (select l.title from pipeline.layer4_intervention_classes l where l.code = r.cls), 'attempted', jsonb_build_array(coalesce(r.recovery, 'scholarship coverage classification'), r.reason),
                                           'why_stopped', r.reason, 'impact', 'the provider''s scholarships cannot be admitted or published from this case'),
               'evidence', jsonb_build_object('official_links', to_jsonb(array_remove(array[r.evidence->>'url', r.evidence->>'page', r.evidence->>'listing'], null)),
                                              'stored_copies', case when r.evidence->>'evidence_id' is not null then jsonb_build_array(r.evidence->>'evidence_id') else '[]'::jsonb end,
                                              'quotes', '[]'::jsonb, 'attempts', jsonb_build_array(jsonb_build_object('reason', r.reason, 'ai', r.evidence->'ai', 'discovery', r.evidence->'discovery')),
                                              'conflicts', case when r.state = 'ownership_conflict' then jsonb_build_array(jsonb_build_object('host', r.evidence->>'host', 'listed_under', r.evidence->>'listed_under')) else '[]'::jsonb end),
               'suggested', case when r.state = 'source_not_discovered' and r.evidence->>'page' is not null and coalesce(security.url_on_provider_sites(r.evidence->>'page', r.provider_id), false)
                                 then jsonb_build_object('url', r.evidence->>'page', 'from', 'the scholarship register (not yet verified)') end,
               'resume_target', jsonb_build_object('operation', 'scholarship readers', 'work_item', jsonb_build_object('lane', 'sch_coverage', 'entity', r.provider_id::text, 'kind', 'state:' || r.state))));
    if coalesce((v_res->>'raised')::boolean, false) then v_n := v_n + 1; elsif coalesce((v_res->>'repeat')::boolean, false) then v_rep := v_rep + 1; else v_skip := v_skip + 1; end if;
  end loop;
  return jsonb_build_object('raised_or_changed', v_n, 'repeats', v_rep, 'not_raised', v_skip);
end $function$;
revoke all on function security.har_sch_generate_v1(int) from public, anon, authenticated;

-- 10 fees and intakes: supplied values handed to the lane's own admission (§5; lanes raise their own interventions) -------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'har.value_year_window', 'Human-assisted recovery: academic years accepted around this year',
  'A fee or intake a person enters must be for a year within this many years of the current year.',
  'number', to_jsonb(2), 0, 10, 'years', 1518, 'Human-assisted recovery', 'security.har_value_validate_v1', 'Decision 06:30 §2 "field validation"')
on conflict (toolset_key, key) do nothing;

create or replace function security.har_value_validate_v1(p_id bigint, p_action text, p_payload jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- fee: {amount > 0, currency (three letters), year (within har.value_year_window of now), audience, basis, quote, url on the provider's site};
-- intake: {commencement: [dates], deadline (a date not after the first commencement), quote, url}; a source: an address on the provider's site.
declare i pipeline.layer4_interventions; v jsonb; j jsonb; v_val text := btrim(coalesce(p_payload->>'value', '')); v_y int; v_w int := security.pipeline_num_v1('har.value_year_window', 2)::int;
        v_d date[]; v_dl date;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_action in ('select_source', 'provide_url') then
    v := security.har_official_url_v1(v_val, i.provider_id);
    if not coalesce((v->>'ok')::boolean, false) then return jsonb_build_object('valid', false, 'request', v->>'reason'); end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'source_url', 'url', v->>'url', 'stored_copy', v->>'stored_copy'));
  end if;
  begin j := v_val::jsonb; exception when others then return jsonb_build_object('valid', false, 'request', 'Enter the value as the form shows (all of its parts).'); end;
  if jsonb_typeof(j) <> 'object' then return jsonb_build_object('valid', false, 'request', 'Enter the value as the form shows (all of its parts).'); end if;
  if not security.har_quote_ok_v1(j->>'quote') then return jsonb_build_object('valid', false, 'request', 'Add the sentence from the official page that states the value.'); end if;
  v := security.har_official_url_v1(j->>'url', i.provider_id);
  if not coalesce((v->>'ok')::boolean, false) then return jsonb_build_object('valid', false, 'request', 'The official page: ' || (v->>'reason')); end if;
  if i.lane = 'fee' then
    if p_action = 'confirm_scope' then
      if coalesce(j->>'audience', '') not in ('international', 'domestic') then return jsonb_build_object('valid', false, 'request', 'Say which audience the fee applies to (international or domestic).'); end if;
      return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'fee_audience', 'audience', j->>'audience', 'quote', j->>'quote', 'url', v->>'url', 'stored_copy', v->>'stored_copy'));
    end if;
    begin v_y := (j->>'year')::int; exception when others then v_y := null; end;
    if coalesce((j->>'amount') ~ '^[0-9]+(\.[0-9]{1,2})?$', false) is false or (j->>'amount')::numeric <= 0 then return jsonb_build_object('valid', false, 'request', 'Give the fee amount as a number.'); end if;
    if coalesce(j->>'currency', '') !~ '^[A-Z]{3}$' then return jsonb_build_object('valid', false, 'request', 'Give the currency as its three-letter code (for example AUD).'); end if;
    if v_y is null or abs(v_y - extract(year from now())::int) > v_w then return jsonb_build_object('valid', false, 'request', 'Give the academic year the fee is for (within ' || v_w || ' years of this year).'); end if;
    if coalesce(j->>'basis', '') not in ('annual', 'total', 'per_unit', 'per_semester') then return jsonb_build_object('valid', false, 'request', 'Say what the amount covers: annual, total, per_unit or per_semester.'); end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'tuition', 'amount', (j->>'amount')::numeric, 'currency', j->>'currency', 'year', v_y,
             'audience', coalesce(j->>'audience', 'international'), 'basis', j->>'basis', 'quote', j->>'quote', 'url', v->>'url', 'stored_copy', v->>'stored_copy'));
  elsif i.lane = 'intake' then
    begin
      v_d := array(select x::date from jsonb_array_elements_text(j->'commencement') x order by 1);
      v_dl := nullif(j->>'deadline', '')::date;
    exception when others then return jsonb_build_object('valid', false, 'request', 'Give the dates as YYYY-MM-DD.');
    end;
    if coalesce(array_length(v_d, 1), 0) = 0 then return jsonb_build_object('valid', false, 'request', 'Give at least one commencement date.'); end if;
    if v_dl is not null and v_dl > v_d[1] then return jsonb_build_object('valid', false, 'request', 'The application deadline must not be after the first commencement date.'); end if;
    if abs(extract(year from v_d[1])::int - extract(year from now())::int) > v_w then return jsonb_build_object('valid', false, 'request', 'The commencement is not within ' || v_w || ' years of this year.'); end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'intake', 'commencement', to_jsonb(v_d), 'deadline', v_dl, 'quote', j->>'quote', 'url', v->>'url', 'stored_copy', v->>'stored_copy'));
  end if;
  return jsonb_build_object('valid', false, 'request', 'This action is not used here; choose one of the offered actions.');
end $function$;
revoke all on function security.har_value_validate_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_value_resume_v1(p_id bigint, p_action text, p_norm jsonb) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- the value is already recorded as a proposal (pipeline.layer4_intervention_values, with its quotation, page and stored copy); the work item is
-- handed back, and the lane's own checks and Layer 4 take it from there (state taken, then admitted or refused)
  select jsonb_build_object('scheduled', true, 'operation', 'proposal recorded for the ' || i.lane || ' lane, whose own checks and Layer 4 admit or refuse it',
                            'value_id', (select max(v.id) from pipeline.layer4_intervention_values v where v.intervention_id = i.id))
    from pipeline.layer4_interventions i where i.id = p_id
$function$;
revoke all on function security.har_value_resume_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_value_verify_v1(p_id bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select case v.state when 'admitted' then jsonb_build_object('state', 'succeeded', 'outcome', 'admitted', 'admitted', true, 'published', coalesce((v.state_detail->>'published')::boolean, false))
                      when 'refused' then jsonb_build_object('state', 'failed', 'request', 'The ' || i.lane || ' lane refused the value: ' || coalesce(v.state_detail->>'reason', 'see its checks') || '. Correct it or select another source.')
                      else jsonb_build_object('state', 'pending', 'evidence', 'the value is ' || coalesce(v.state, 'not recorded')) end
    from pipeline.layer4_interventions i left join lateral (select x.* from pipeline.layer4_intervention_values x where x.intervention_id = i.id order by x.id desc limit 1) v on true
   where i.id = p_id
$function$;
revoke all on function security.har_value_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.har_value_recheck_v1(p_id bigint) returns jsonb
language sql stable set search_path to '' as $function$
  -- the fee and intake lanes close their own interventions when their evidence changes (they raise again with the new fingerprint)
  select jsonb_build_object('cleared', false, 'id', p_id)
$function$;
revoke all on function security.har_value_recheck_v1(bigint) from public, anon, authenticated;

-- 11 the handler registry ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.layer4_intervention_handlers(lane, title, validate_fn, resume_fn, verify_fn, recheck_fn, generate_fn, generate_switch, description) values
 ('aer_source', 'Entry requirements: sources and reads', 'security.har_aer_validate_v1(bigint,text,jsonb)', 'security.har_aer_resume_v1(bigint,text,jsonb)',
  'security.har_aer_verify_v1(bigint)', 'security.har_aer_recheck_v1(bigint)', 'security.har_aer_generate_v1(integer)', 'har.generate_aer_on',
  'An official address or document becomes the university''s entry-requirement source and is read by entry-matrix-read (stored copy first); a scope returns its courses to the scheduled reader.'),
 ('aer_course', 'Entry requirements: course identity', 'security.har_aer_validate_v1(bigint,text,jsonb)', 'security.har_aer_resume_v1(bigint,text,jsonb)',
  'security.har_aer_verify_v1(bigint)', 'security.har_aer_recheck_v1(bigint)', null, null,
  'A confirmed course returns the held AER item to its technical check (raised by the aer_source generator).'),
 ('sch_coverage', 'Scholarship coverage', 'security.har_sch_validate_v1(bigint,text,jsonb)', 'security.har_sch_resume_v1(bigint,text,jsonb)',
  'security.har_sch_verify_v1(bigint)', 'security.har_sch_recheck_v1(bigint)', 'security.har_sch_generate_v1(integer)', 'har.generate_sch_on',
  'An official page becomes a listing source; an audience confirmation re-reads the candidate (Read again); search again brings discovery forward; an owner is recorded.'),
 ('fee', 'Fees', 'security.har_value_validate_v1(bigint,text,jsonb)', 'security.har_value_resume_v1(bigint,text,jsonb)',
  'security.har_value_verify_v1(bigint)', 'security.har_value_recheck_v1(bigint)', null, null,
  'A corrected fee or selected source is recorded as a proposal for the fee lane (interface request: the fee lane raises its conflicts and takes the proposals).'),
 ('intake', 'Intakes', 'security.har_value_validate_v1(bigint,text,jsonb)', 'security.har_value_resume_v1(bigint,text,jsonb)',
  'security.har_value_verify_v1(bigint)', 'security.har_value_recheck_v1(bigint)', null, null,
  'Entered dates are recorded as a proposal for the intake lane (interface request: the intake lane raises its gaps and takes the proposals).')
on conflict (lane) do nothing;

-- 12 metrics (§9): a section of the existing operations report, no new dashboard ----------------------------------------------------------------
create or replace function security.layer4_intervention_report_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- CF-247 human-assisted recovery (decision 06:30 §9): per workstream: automatically resolved, human input needed, human resolved, resumed,
-- admitted, published, still blocked; the average time from creation to automatic resumption, the age of unresolved interventions, the
-- recovery success rate (resumed work verified, of the inputs given), overdue items and the open items per class.
  with x as (select i.*, c.workstream from pipeline.layer4_interventions i join pipeline.layer4_intervention_classes c on c.code = i.missing_fact),
  w as (select x.workstream,
               count(*) filter (where x.status = 'auto_resolved') auto_resolved,
               count(*) filter (where x.status in ('ai_pending', 'awaiting_input')) human_input_needed,
               count(*) filter (where x.input_at is not null) human_resolved,
               count(*) filter (where x.resumed_at is not null) resumed,
               count(*) filter (where x.admitted_at is not null) admitted,
               count(*) filter (where x.published_at is not null) published,
               count(*) filter (where x.status in ('ai_pending', 'awaiting_input', 'resuming')) still_blocked,
               count(*) filter (where x.status = 'resolved') verified,
               count(*) filter (where x.status = 'not_published') not_published,
               count(*) filter (where x.status = 'returned_technical') returned_technical,
               count(*) filter (where x.status in ('ai_pending', 'awaiting_input', 'resuming') and x.recover_by < now()) overdue,
               round(avg(extract(epoch from x.resumed_at - x.created_at) / 60) filter (where x.resumed_at is not null), 1) avg_minutes_to_resume,
               round(avg(extract(epoch from now() - x.created_at) / 3600) filter (where x.status in ('ai_pending', 'awaiting_input', 'resuming')), 1) avg_open_age_hours,
               round(max(extract(epoch from now() - x.created_at) / 3600) filter (where x.status in ('ai_pending', 'awaiting_input', 'resuming')), 1) max_open_age_hours,
               sum(x.repeat_count) repeats_not_raised, sum(x.reopen_count) reopened
          from x group by 1)
  select jsonb_build_object('at', now(),
    'switches', jsonb_build_object('on', security.pipeline_num_v1('har.on', 1), 'aer', security.pipeline_num_v1('har.generate_aer_on', 1),
                                   'scholarships', security.pipeline_num_v1('har.generate_sch_on', 1), 'resume', security.pipeline_num_v1('har.resume_on', 1),
                                   'ai_escalation', security.pipeline_num_v1('har.ai_escalate_on', 0)),
    'workstreams', coalesce((select jsonb_agg(jsonb_build_object('workstream', w.workstream, 'automatically_resolved', w.auto_resolved, 'human_input_needed', w.human_input_needed,
                     'human_resolved', w.human_resolved, 'resumed', w.resumed, 'admitted', w.admitted, 'published', w.published, 'still_blocked', w.still_blocked,
                     'verified', w.verified, 'not_published', w.not_published, 'returned_technical', w.returned_technical, 'overdue', w.overdue,
                     'avg_minutes_to_resume', w.avg_minutes_to_resume, 'avg_open_age_hours', w.avg_open_age_hours, 'max_open_age_hours', w.max_open_age_hours,
                     'recovery_success_rate', case when w.human_resolved > 0 then round(w.verified::numeric / w.human_resolved, 3) end,
                     'repeats_not_raised', w.repeats_not_raised, 'reopened', w.reopened) order by w.workstream) from w), '[]'::jsonb),
    'open_by_class', coalesce((select jsonb_object_agg(z.missing_fact, z.n) from (select x.missing_fact, count(*) n from x where x.status in ('ai_pending', 'awaiting_input') group by 1) z), '{}'::jsonb))
$function$;
revoke all on function security.layer4_intervention_report_v1() from public, anon, authenticated;
comment on function security.layer4_intervention_report_v1() is 'CF-247 human-assisted recovery (decision 06:30 §9): the recovery metrics per workstream; a section (human_assisted_recovery) of security.ops_report_v1.';

select pg_temp.edit_once('security.ops_report_v1(integer)', '5a1e21cc42f8f54cbf0d9f3f7fe81c71', '3ba694dc078995d88a983e8e92b2f425',
  array[array[$o$  return v_out;
end $o$, $n$  -- human-assisted recovery (Platform Admin decision 4 Nov 2026 06:30 §9): interventions per workstream (security.layer4_intervention_report_v1)
  begin
    v_out := v_out || jsonb_build_object('human_assisted_recovery', security.layer4_intervention_report_v1());
  exception when others then v_out := v_out || jsonb_build_object('human_assisted_recovery', jsonb_build_object('error', left(sqlerrm, 200)));
  end;
  return v_out;
end $n$]], array[1]);

-- 13 the Layer 4 kind "Human input needed", as this change's own functions (Coordinator 4 Nov 2026 06:53: the Inbox functions and screen are
--    owned by the Inbox performance change, cf247-l4-inbox-perf / 20261104410000; a kind supplies its counts, a page of items and lazy detail;
--    the Inbox calls these and routes the kind's decisions to security.layer4_intervention_resolve_v1)
create or replace function security.layer4_intervention_kind_v1() returns jsonb
language sql immutable set search_path to '' as $function$
-- the kind's label, order and the eleven actions of the decision's §2 (each item offers only its class's actions: detail.allowed)
  select '{"label": "Human input needed", "order": 20, "choices": [
     {"key": "provide_url", "label": "Give the official address", "input": "url", "returns": "Checked to be on the provider''s own website, then the work resumes by itself. An address is not approval to publish"},
     {"key": "attach_document", "label": "Give the document", "input": "url", "returns": "The official document is checked and read by the existing reader; what it finds is still reviewed before anything is admitted"},
     {"key": "select_source", "label": "Choose the authoritative source", "input": "url", "returns": "That source is used and read again; other sources stay as they are"},
     {"key": "enter_value", "label": "Enter the missing information", "input": "text", "returns": "Checked like an extracted value (quotation, official page, field rules) and handed to the lane''s own checks; it is a proposal, not an admitted value"},
     {"key": "correct_value", "label": "Correct the value against the quotation", "input": "text", "returns": "Your correction and its quotation are checked and handed back; the usual checks still decide"},
     {"key": "confirm_identity", "label": "Confirm the identity", "input": "text", "returns": "The provider, course or scholarship you name is checked and the work resumes for it"},
     {"key": "confirm_scope", "label": "Confirm who or what it applies to", "input": "text", "returns": "Your answer and its quotation are kept as evidence and the work resumes"},
     {"key": "search_again", "label": "Search again", "returns": "The automatic search runs again within its own limits"},
     {"key": "confirm_not_published", "label": "Confirm it is not published", "input": "url", "rank": 5, "returns": "Closed as not published, with the official page you give as evidence; asked again only if that changes"},
     {"key": "return_technical", "label": "Return to technical recovery", "returns": "The work goes back to its technical recovery; the same failure is not asked again unless it changes"},
     {"key": "reject_evidence", "label": "Reject this evidence", "returns": "The evidence or suggestion shown is refused and kept on record; the item still waits for the missing input"}]}'::jsonb
$function$;
revoke all on function security.layer4_intervention_kind_v1() from public, anon, authenticated;

create or replace function security.layer4_intervention_inbox_counts_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
-- counts only (no detail): waiting, oldest, late (layer4.target_days), and per provider; served from the open-status index
  with o as (select i.provider_id, i.created_at from pipeline.layer4_interventions i where i.status = 'awaiting_input')
  select jsonb_build_object('kind', 'intervention', 'n', (select count(*) from o), 'oldest', (select min(o.created_at) from o),
    'late', (select count(*) from o where o.created_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int)),
    'by_provider', coalesce((select jsonb_agg(jsonb_build_object('provider_id', z.provider_id, 'n', z.n, 'oldest', z.oldest) order by z.oldest)
                               from (select o.provider_id, count(*) n, min(o.created_at) oldest from o group by 1) z), '[]'::jsonb))
$function$;
revoke all on function security.layer4_intervention_inbox_counts_v1() from public, anon, authenticated;

create or replace function security.layer4_intervention_inbox_page_v1(p_args jsonb) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- one page of compact rows (no evidence), oldest first, keyset-paged by (created_at, id): p_args {provider_id, limit, after_at, after_ref}
  with x as (select i.id, i.provider_id, i.subject, i.missing_fact, i.created_at, coalesce(i.required_input->>'follow_up', i.issue->>'why_stopped', i.issue->>'summary') why,
                    i.recommended->>'action' suggestion, i.recover_by
               from pipeline.layer4_interventions i
              where i.status = 'awaiting_input'
                and (nullif(p_args->>'provider_id', '') is null or i.provider_id = (p_args->>'provider_id')::uuid)
                and (nullif(p_args->>'after_ref', '') is null or (i.created_at, i.id) > ((p_args->>'after_at')::timestamptz, (p_args->>'after_ref')::bigint))
              order by i.created_at, i.id
              limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200))  -- fixed: page size bounds, as the Inbox's own
  select jsonb_build_object('kind', 'intervention',
    -- the paging contract's "before": this kind's items for the same university at or before the cursor
    'before', case when nullif(p_args->>'after_ref', '') is not null then
                (select count(*) from pipeline.layer4_interventions b where b.status = 'awaiting_input'
                    and (nullif(p_args->>'provider_id', '') is null or b.provider_id = (p_args->>'provider_id')::uuid)
                    and (b.created_at, b.id) <= ((p_args->>'after_at')::timestamptz, (p_args->>'after_ref')::bigint)) end,
    'items', coalesce(jsonb_agg(jsonb_build_object('kind', 'intervention', 'ref', x.id::text, 'provider_id', x.provider_id,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = x.provider_id), 'subject', x.subject, 'why', x.why,
           'suggestion', x.suggestion, 'created_at', x.created_at, 'missing_fact', x.missing_fact,
           'late', x.created_at < now() - make_interval(days => security.pipeline_num_v1('layer4.target_days', 7)::int), 'overdue', x.recover_by < now()) order by x.created_at, x.id), '[]'::jsonb))
    from x
$function$;
revoke all on function security.layer4_intervention_inbox_page_v1(jsonb) from public, anon, authenticated;

create or replace function security.layer4_intervention_inbox_detail_v1(p_ref text) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- the card's four sections (decision 06:30 §3), read only when the card is opened, in the paging contract's shape
-- {sections:[{key, title, body}], actions:[{key, allowed, why?}]}: issue summary, evidence, recommended intervention, resolution (the actions
-- this item allows and whether the caller's rank may take each, the audit lines, the work resumed, status and time bounds). One item only.
  select jsonb_build_object('sections', jsonb_build_array(
      jsonb_build_object('key', 'issue', 'title', 'Issue summary', 'body', jsonb_strip_nulls(jsonb_build_object(
        'What is missing', c.title, 'Record', i.subject, 'What the platform attempted', i.issue->'attempted', 'Why it could not finish', i.issue->>'why_stopped',
        'Impact', i.issue->>'impact', 'Automatic attempts', i.automated_attempts, 'Seen again unchanged', i.repeat_count, 'Reopened', i.reopen_count))),
      jsonb_build_object('key', 'evidence', 'title', 'Evidence', 'body', jsonb_strip_nulls(jsonb_build_object(
        'Official links', i.evidence->'official_links', 'Stored copies', i.evidence->'stored_copies', 'Quotations', i.evidence->'quotes',
        'Previous attempts', i.evidence->'attempts', 'Conflicts or missing information', i.evidence->'conflicts',
        'AI analysis', case when i.ai_analysis is not null then jsonb_strip_nulls(jsonb_build_object('analysis', i.ai_analysis->>'analysis', 'confidence', i.ai_analysis->'confidence',
                                                                                  'uncertainty', i.ai_analysis->'uncertainty', 'refused', i.ai_analysis->'refused', 'skipped', i.ai_analysis->'skipped')) end))),
      jsonb_build_object('key', 'recommended', 'title', 'Recommended intervention', 'body', jsonb_strip_nulls(jsonb_build_object(
        'Next best action', (select ch->>'label' from jsonb_array_elements(security.layer4_intervention_kind_v1()->'choices') ch where ch->>'key' = i.recommended->>'action'),
        'Information needed', i.required_input->>'ask', 'Still needed after the last answer', i.required_input->>'follow_up',
        'Suggested answer', i.recommended->'suggested', 'How this unblocks processing', i.recommended->>'unblocks'))),
      jsonb_build_object('key', 'resolution', 'title', 'Resolution', 'body', jsonb_strip_nulls(jsonb_build_object(
        'Status', i.status, 'Responsible', i.assigned_to, 'Work resumed on an answer', i.resume_target->>'operation', 'Escalated if unanswered by', i.escalate_at,
        'Recovery deadline', i.recover_by, 'Verified outcome', i.verified_outcome, 'Admitted', i.admitted_at, 'Published', i.published_at,
        'Audit', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'by', e.actor_label, 'rank', e.role_rank, 'action', e.action, 'request', e.result->>'request') order by e.id desc), '[]'::jsonb)
                    from (select * from pipeline.layer4_intervention_events e where e.intervention_id = i.id order by e.id desc
                           limit security.pipeline_num_v1('har.history_items', 3)::int) e))))),
    'actions', (select coalesce(jsonb_agg(jsonb_build_object('key', ch->>'key', 'allowed', security.current_role_rank() >= (i.allowed_actions->>(ch->>'key'))::int,
                                                             'why', case when security.current_role_rank() < (i.allowed_actions->>(ch->>'key'))::int
                                                                         then 'needs rank ' || (i.allowed_actions->>(ch->>'key')) end)), '[]'::jsonb)
                  from jsonb_array_elements(security.layer4_intervention_kind_v1()->'choices') ch where i.allowed_actions ? (ch->>'key')))
    from pipeline.layer4_interventions i join pipeline.layer4_intervention_classes c on c.code = i.missing_fact
   where i.id::text = p_ref
$function$;
revoke all on function security.layer4_intervention_inbox_detail_v1(text) from public, anon, authenticated;

create or replace function security.layer4_intervention_inbox_decide_v1(p_ref text, p_choice text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- the Inbox's route for this kind (interface for public.admin_layer4_inbox 'decide'): resolve, then the decision's own audit line in
-- admin_control_events as every Inbox decision has
declare v_r jsonb; v_ev bigint; v_pid uuid;
begin
  v_r := security.layer4_intervention_resolve_v1(p_ref::bigint, p_choice, jsonb_build_object('value', p_value, 'reason', p_reason));
  select provider_id into v_pid from pipeline.layer4_interventions where id = p_ref::bigint;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'intervention:' || p_ref, jsonb_build_object('kind', 'intervention', 'ref', p_ref, 'choice', p_choice, 'value', p_value, 'reason', p_reason,
          'provider_id', v_pid, 'result', v_r), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', coalesce((v_r->>'ok')::boolean, false), 'kind', 'intervention', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'result', v_r,
                            'returns', v_r->>'returns', 'request', v_r->>'request');
end $function$;
revoke all on function security.layer4_intervention_inbox_decide_v1(text, text, text, text) from public, anon, authenticated;

-- 13b AER reads held by E13 or D-R3: governed recovery instead of Reject only (Platform Admin decision 4 Nov 2026 06:58 §1 and §3; Inbox paging
--     contract §2a: mode 'extend' on kind aer_review). The E13 and D-R3 gates still refuse approval of an incomplete read; these choices
--     recover it. Every action is recorded in pipeline.layer4_aer_recovery_actions; an unchanged problem never makes a second operation.
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'har.aer_case_items_max', 'Human-assisted recovery: held AER reads listed in one recovery case',
  'Held reads of the same university that fail the same way are grouped into one recovery case; the card lists at most this many of them.',
  'number', to_jsonb(20), 1, 200, 'reads', 1519, 'Human-assisted recovery', 'security.layer4_aer_recovery_detail_v1', 'Platform Admin decision 06:58 §3 "group repeated reader failures into one case"')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.layer4_aer_recovery_actions (
  id bigserial primary key,
  review_item_id uuid not null,
  case_key text not null,
  choice text not null check (choice in ('reread_stored', 'request_evidence', 'ai_analyse', 'open_intervention')),
  problem_fingerprint text not null,
  reason text not null,
  affected_rows jsonb not null default '[]'::jsonb,
  missing_quotes jsonb not null default '[]'::jsonb,
  previous_evidence jsonb not null default '{}'::jsonb,
  reviewer uuid,
  work_item_status text,
  next_operation text,
  intervention_id bigint references pipeline.layer4_interventions(id),
  result jsonb not null default '{}'::jsonb,
  at timestamptz not null default now(),
  unique (review_item_id, choice, problem_fingerprint)
);
comment on table pipeline.layer4_aer_recovery_actions is 'CF-247 (Platform Admin decision 4 Nov 2026 06:58 §1, §3): every recovery action on an AER read held by the E13 or D-R3 gate: the choice, the reason, the rows affected, the requirements dropped without a quotation in a row, the evidence the read used, the reviewer, the work item''s new status and the next automatic operation. One row per item, choice and unchanged problem (the problem fingerprint is the gate result), so an unchanged problem never makes a second operation.';
create index if not exists layer4_aer_recovery_actions_case_idx on pipeline.layer4_aer_recovery_actions (case_key, at desc);
alter table pipeline.layer4_aer_recovery_actions enable row level security;
revoke all on pipeline.layer4_aer_recovery_actions from public, anon, authenticated;
revoke all on sequence pipeline.layer4_aer_recovery_actions_id_seq from public, anon, authenticated;

create or replace function security.layer4_aer_recovery_state_v1(p_item uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- What is known about one held AER read, from the existing records only: its kind (course read or matrix run), the gate result (security.
-- course_entry_gate_v1 or security.entry_matrix_gate_v1, read only), the waiting rows, the dropped requirements and their quotations, the stored
-- copy, any corrected read already asked for (pipeline.aer_read_supersessions), the open intervention, and the recovery case: the university and
-- the gate's first reason, so repeated reader failures of one university group into one case.
declare r pipeline.layer4_review_items; g jsonb; v_run uuid; v_src uuid; v_pid uuid; v_drop jsonb := '[]'::jsonb; v_rows jsonb; v_case text; v_sup record;
begin
  select * into r from pipeline.layer4_review_items where id = p_item;
  if r.id is null or r.field_code not in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') then return null; end if;
  if r.field_code = 'course_entry_first_read' then
    select c.provider_id into v_pid from catalogue.courses c where c.id = r.entity_id;
    g := security.course_entry_gate_v1(r.id, '{}'::uuid[]);
    v_drop := coalesce(r.proposed_value->'dropped', (select f.value->'dropped' from pipeline.field_enrich_items f where f.id = nullif(r.proposed_value->>'item_id', '')::bigint), '[]'::jsonb);
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'quote', x.quote) order by x.id), '[]'::jsonb) into v_rows
      from catalogue.course_entry_requirements x where x.provenance->>'review_item_id' = r.id::text and x.status = 'proposed';
    select s.state, s.outcome, s.requested_at, s.new_item_id into v_sup from pipeline.aer_read_supersessions s where s.old_item_id = r.id order by s.requested_at desc limit 1;
  else
    select x.id, x.source_id, x.provider_id into v_run, v_src, v_pid from pipeline.entry_matrix_runs x where x.review_item_id = r.id order by x.created_at desc limit 1;
    g := case when v_run is not null then security.entry_matrix_gate_v1(v_run, '{}'::uuid[]) end;
    select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'quote', m.quote) order by m.id), '[]'::jsonb) into v_rows
      from catalogue.provider_entry_matrix m where m.run_id = v_run and m.status = 'proposed';
  end if;
  v_case := coalesce(v_pid::text, '-') || '|' || r.field_code || '|' || left(regexp_replace(coalesce(g->'reasons'->>0, 'incomplete'), '[0-9]+', '#', 'g'), 80);
  return jsonb_build_object('item', r.id, 'field_code', r.field_code, 'course_id', case when r.entity_type = 'course' then r.entity_id end, 'provider_id', v_pid,
    'run_id', v_run, 'source_id', v_src, 'complete', coalesce((g->>'complete')::boolean, false), 'reasons', coalesce(g->'reasons', '[]'::jsonb), 'gate', g,
    'waiting_rows', v_rows, 'dropped', v_drop,
    'missing_quotes', (select coalesce(jsonb_agg(d->'quote'), '[]'::jsonb) from jsonb_array_elements(v_drop) d where nullif(d->>'quote', '') is not null),
    'evidence_id', r.evidence_id, 'stored_copy', r.evidence_id is not null or exists (select 1 from pipeline.coverage_course_pages p where p.course_id = r.entity_id and p.evidence_id is not null),
    'corrected_read', case when v_sup.state is not null then jsonb_build_object('state', v_sup.state, 'outcome', v_sup.outcome, 'at', v_sup.requested_at, 'new_item', v_sup.new_item_id) end,
    'case_key', md5(v_case), 'case_label', left(coalesce(g->'reasons'->>0, 'incomplete read'), 160),
    'problem_fingerprint', md5(coalesce(g::text, '') || '|' || coalesce(r.evidence_id::text, '') || '|' || v_drop::text));
end $function$;
revoke all on function security.layer4_aer_recovery_state_v1(uuid) from public, anon, authenticated;

create or replace function security.layer4_aer_recovery_kind_v1() returns jsonb
language sql immutable set search_path to '' as $function$
-- the recovery choices appended to the aer_review kind (paging contract §2a); Approve all, Approve except and Reject the read stay built in
  select '{"choices": [
     {"key": "reread_stored", "label": "Re-read from stored evidence", "returns": "The existing reader reads the page again from its stored copy (no new paid read where a copy exists); the new read replaces this one only through the same gates"},
     {"key": "request_evidence", "label": "Request official evidence", "returns": "One Human input needed item asks for the official page or document for this case; when it is given, the course is read again by itself"},
     {"key": "ai_analyse", "label": "Ask AI to analyse the failure", "returns": "The pinned stronger model looks at this failure once (within the AI limits) and proposes rows with quotations; a proposal is checked and only suggested"},
     {"key": "open_intervention", "label": "Open human input", "returns": "One Human input needed item asks for the dropped requirements as rows with quotations; when they check out, the course is read again by itself"}]}'::jsonb
$function$;
revoke all on function security.layer4_aer_recovery_kind_v1() from public, anon, authenticated;

create or replace function security.layer4_aer_recovery_detail_v1(p_ref text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- the recovery state on an E13 or D-R3 card (decision 06:58 §3; paging contract §2a, shape {sections, actions}): the gate's counts and reasons,
-- the recommended recovery, whether a person is needed, the owner, the next automatic attempt, the last attempt and its status, and the case
-- the read belongs to (other held reads of the same university failing the same way). The E13 facts themselves stay on the built-in card.
declare st jsonb := security.layer4_aer_recovery_state_v1(p_ref::uuid); v_last record; v_iv pipeline.layer4_interventions; v_rec text; v_case jsonb; v_ai boolean;
        v_busy text;
begin
  if st is null then return jsonb_build_object('sections', '[]'::jsonb, 'actions', '[]'::jsonb); end if;
  select * into v_last from pipeline.layer4_aer_recovery_actions a where a.review_item_id = p_ref::uuid order by a.id desc limit 1;
  select * into v_iv from pipeline.layer4_interventions i where i.lane = 'aer_item' and i.status in ('ai_pending', 'awaiting_input', 'resuming')
     and (i.entity = p_ref or i.entity = (st->>'provider_id') || '|case:' || (st->>'case_key')) order by i.id desc limit 1;
  v_ai := security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 and security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1 and security.har_text_v1('har.ai_escalation_model', '') <> '';
  v_busy := case when st->'corrected_read'->>'state' = 'requested' then 'a corrected read of this item is already asked for'
                 when exists (select 1 from pipeline.field_enrich_items f where f.course_id = (st->>'course_id')::uuid and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased'))
                   then 'a read of this course is in progress' end;
  v_rec := case when (st->>'complete')::boolean then 'none: the read is complete'
                when v_iv.id is not null then 'answer the open Human input needed item (ref ' || v_iv.id || ')'
                when v_busy is not null then 'wait: ' || v_busy
                when coalesce((st->>'stored_copy')::boolean, false) and coalesce(st->'corrected_read'->>'state', '') <> 'superseded'
                     and not exists (select 1 from pipeline.layer4_aer_recovery_actions a where a.review_item_id = p_ref::uuid and a.choice = 'reread_stored') then 'reread_stored'
                when not coalesce((st->>'stored_copy')::boolean, false) then 'request_evidence'
                else 'open_intervention' end;
  select coalesce(jsonb_agg(jsonb_build_object('ref', z.id, 'subject', z.subject) order by z.created_at), '[]'::jsonb) into v_case
    from (select li.id, li.created_at, coalesce(c.display_title, c.canonical_title) subject from pipeline.layer4_review_items li left join catalogue.courses c on c.id = li.entity_id
           where li.status = 'pending' and li.field_code = st->>'field_code' and li.id <> p_ref::uuid
             and (st->>'course_id') is not null and c.provider_id = (st->>'provider_id')::uuid
             and (security.layer4_aer_recovery_state_v1(li.id)->>'case_key') = st->>'case_key'
           order by li.created_at limit security.pipeline_num_v1('har.aer_case_items_max', 20)::int) z;
  return jsonb_build_object('sections', jsonb_build_array(
      jsonb_build_object('key', 'recovery', 'title', 'Recovery', 'body', jsonb_strip_nulls(jsonb_build_object(
        'Waiting rows', jsonb_array_length(st->'waiting_rows'), 'Dropped requirements', jsonb_array_length(st->'dropped'),
        'Dropped without a row (quotations)', jsonb_array_length(st->'missing_quotes'), 'Why the read is held', st->'reasons',
        'Recommended recovery', v_rec, 'Human input needed', case when v_rec in ('open_intervention', 'request_evidence') or v_iv.id is not null then 'yes' else 'not yet' end,
        'Owner', case when v_iv.id is not null then v_iv.assigned_to when v_rec = 'reread_stored' then 'the entry reader (automatic)' else 'Layer 4 reviewer' end,
        'Next automatic attempt', case when v_busy is not null then 'the requested read' when v_iv.id is not null then coalesce(v_iv.next_action_at::text, 'when the input is given') else 'none until a recovery is chosen' end,
        'Last attempt', case when v_last.id is not null then v_last.choice || ' at ' || v_last.at || ': ' || coalesce(v_last.next_operation, '') end,
        'Last attempt status', coalesce(st->'corrected_read'->>'state', v_last.work_item_status)))),
      jsonb_build_object('key', 'case', 'title', 'Recovery case', 'body', jsonb_build_object('Case', st->>'case_label', 'Other held reads in this case', v_case))),
    'actions', jsonb_build_array(
      jsonb_build_object('key', 'reread_stored', 'allowed', v_busy is null and not (st->>'complete')::boolean, 'why', v_busy),
      jsonb_build_object('key', 'request_evidence', 'allowed', v_iv.id is null, 'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end),
      jsonb_build_object('key', 'ai_analyse', 'allowed', v_ai and v_iv.id is null,
                         'why', case when not v_ai then 'the stronger-model step is off (har.ai_escalate_on, ops.ai_diagnosis_on or no pinned model)'
                                     when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end),
      jsonb_build_object('key', 'open_intervention', 'allowed', v_iv.id is null, 'why', case when v_iv.id is not null then 'a Human input needed item is already open (ref ' || v_iv.id || ')' end)));
end $function$;
revoke all on function security.layer4_aer_recovery_detail_v1(text) from public, anon, authenticated;

create or replace function security.layer4_aer_recovery_decide_v1(p_ref text, p_choice text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- The four recovery choices on a held AER read (decision 06:58 §1). Approval is never reached from here: the E13 and D-R3 gates are untouched.
--   reread_stored     the existing corrected read: security.course_entry_correction_v1 (course reads, D-R2; scraper off, the stored page) or
--                     security.aer_reread_v1 (matrix runs, the stored copy); refused by their own rules when a read is already waiting
--   request_evidence  one aer_read_evidence intervention for the recovery case (all held reads of the university failing the same way)
--   ai_analyse        the aer_read_rows_missing intervention, sent first to the stronger model (only while har.ai_escalate_on is 1)
--   open_intervention the aer_read_rows_missing intervention for this read, for a person
-- Every call is recorded (pipeline.layer4_aer_recovery_actions and the Inbox decision row); the same choice on an unchanged problem returns the
-- recorded operation instead of starting another.
declare st jsonb; v_reason text := btrim(coalesce(p_reason, '')); a pipeline.layer4_aer_recovery_actions; v_res jsonb; v_iv jsonb; v_next text; v_ws text;
        v_ok boolean := true; v_req text; v_ev bigint; v_id bigint; v_wi jsonb; v_class text; v_ent text; v_ai boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 4 then raise exception 'your role cannot take this action (it needs rank 4)' using errcode = '42501'; end if;
  if p_choice not in ('reread_stored', 'request_evidence', 'ai_analyse', 'open_intervention') then raise exception 'unknown recovery choice %', p_choice using errcode = '22023'; end if;
  if length(v_reason) < 5 then raise exception 'give a reason (kept with the recovery)'; end if;
  st := security.layer4_aer_recovery_state_v1(p_ref::uuid);
  if st is null or not exists (select 1 from pipeline.layer4_review_items r where r.id = p_ref::uuid and r.status = 'pending') then
    raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
  select * into a from pipeline.layer4_aer_recovery_actions x where x.review_item_id = p_ref::uuid and x.choice = p_choice and x.problem_fingerprint = st->>'problem_fingerprint';
  if a.id is not null then
    v_res := jsonb_build_object('repeat', true, 'recorded', a.id, 'next_operation', a.next_operation, 'intervention_id', a.intervention_id);
    v_ok := false; v_req := 'This recovery was already started for the same unchanged problem (' || a.next_operation || '); its result is awaited.';
  else
    v_wi := jsonb_build_object('lane', 'aer_technical', 'entity', p_ref, 'kind', 'l4_item');
    if p_choice = 'reread_stored' then
      begin
        if st->>'field_code' = 'course_entry_first_read' then
          v_res := security.course_entry_correction_v1(p_ref::uuid, auth.uid(), 'Layer 4 recovery: ' || v_reason);
        else
          v_res := security.aer_reread_v1((st->>'source_id')::uuid, 'Layer 4 recovery: ' || v_reason, auth.uid());
        end if;
        v_next := 'the existing reader reads the stored page again; the new read replaces this one only through the same gates';
      exception when others then
        v_ok := false; v_req := sqlerrm || '. Choose Request official evidence or Open human input instead.'; v_res := jsonb_build_object('refused', sqlerrm);
      end;
    else
      v_ai := p_choice = 'ai_analyse';
      if v_ai and not (security.pipeline_num_v1('har.ai_escalate_on', 0) >= 1 and security.pipeline_num_v1('ops.ai_diagnosis_on', 0) >= 1 and security.har_text_v1('har.ai_escalation_model', '') <> '') then
        v_ok := false; v_req := 'The stronger-model step is switched off (har.ai_escalate_on, ops.ai_diagnosis_on, har.ai_escalation_model). Choose Open human input instead.';
        v_res := jsonb_build_object('held', 'AI step off');
      else
        v_class := case p_choice when 'request_evidence' then 'aer_read_evidence' else 'aer_read_rows_missing' end;
        v_ent := case p_choice when 'request_evidence' then (st->>'provider_id') || '|case:' || (st->>'case_key') else p_ref end;
        v_iv := security.layer4_intervention_raise_v1(jsonb_build_object('class', v_class, 'entity', v_ent, 'provider_id', st->>'provider_id', 'course_id', st->>'course_id',
                  'subject', coalesce((select coalesce(c.display_title, c.canonical_title) from catalogue.courses c where c.id = (st->>'course_id')::uuid), 'Entry requirements') || ': ' ||
                             case v_class when 'aer_read_evidence' then 'official evidence needed' else 'dropped requirements to enter' end,
                  'attempts', 99, 'signature', case v_class when 'aer_read_evidence' then st->>'case_key' else st->>'problem_fingerprint' end,
                  'issue', jsonb_build_object('summary', 'The read is held: ' || (st->>'case_label'), 'attempted', jsonb_build_array('AI course read', 'completeness gate'),
                                              'why_stopped', st->'reasons'->>0, 'impact', 'the course''s accurate rows cannot be admitted while the read is incomplete'),
                  'evidence', jsonb_build_object('stored_copies', case when st->>'evidence_id' is not null then jsonb_build_array(st->>'evidence_id') else '[]'::jsonb end,
                                                 'quotes', st->'missing_quotes', 'attempts', jsonb_build_array(jsonb_build_object('corrected_read', st->'corrected_read')),
                                                 'conflicts', st->'reasons'),
                  'resume_target', jsonb_build_object('operation', 'corrected read of the course by the existing reader (D-R2)', 'work_item', v_wi),
                  'review_item', p_ref));
        v_id := (v_iv->>'id')::bigint;
        if v_id is null then v_ok := false; v_req := 'No Human input needed item could be opened: ' || coalesce(v_iv->>'reason', 'refused'); end if;
        -- ai_analyse sends the new item to the stronger model first; open_intervention and request_evidence go straight to a person
        update pipeline.layer4_interventions set status = case when v_ai then 'ai_pending' else 'awaiting_input' end,
               resume_target = resume_target || jsonb_build_object('review_item', p_ref) where id = v_id and status in ('ai_pending', 'awaiting_input');
        v_next := case when v_id is null then null when v_ai then 'the stronger model analyses the failure once, then the item waits for a person'
                       else 'Human input needed item ' || v_id || ' waits for a person; the course is read again by itself when the input checks out' end;
        v_res := v_iv;
      end if;
    end if;
    select w.stage into v_ws from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = p_ref and w.work_kind = 'l4_item';
    insert into pipeline.layer4_aer_recovery_actions(review_item_id, case_key, choice, problem_fingerprint, reason, affected_rows, missing_quotes, previous_evidence, reviewer,
                work_item_status, next_operation, intervention_id, result)
    select p_ref::uuid, st->>'case_key', p_choice, case when v_ok then st->>'problem_fingerprint' else st->>'problem_fingerprint' || ':refused:' || md5(coalesce(v_req, '')) || ':' || now() end,
           v_reason, st->'waiting_rows', st->'missing_quotes',
           jsonb_build_object('evidence_id', st->>'evidence_id', 'corrected_read', st->'corrected_read', 'reasons', st->'reasons'), auth.uid(), coalesce(v_ws, 'none'),
           coalesce(v_next, v_req), v_id, coalesce(v_res, '{}'::jsonb)
    returning * into a;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'inbox_decide', 'aer_review:' || p_ref, jsonb_build_object('kind', 'aer_review', 'ref', p_ref, 'choice', p_choice, 'value', p_value, 'reason', v_reason,
          'provider_id', st->>'provider_id', 'recovery_action', a.id, 'result', v_res), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', v_ok, 'kind', 'aer_review', 'choice', p_choice, 'ref', p_ref, 'event_id', v_ev, 'request', v_req,
    'returns', case when v_ok then v_next end, 'result', jsonb_build_object('recovery_action', a.id, 'next_operation', a.next_operation, 'work_item_status', a.work_item_status,
                                                                          'intervention_id', a.intervention_id, 'detail', v_res));
end $function$;
revoke all on function security.layer4_aer_recovery_decide_v1(text, text, text, text) from public, anon, authenticated;

-- the aer_item lane: validate the evidence or the rows, then the correct reader restarts by itself (decision 06:58 §1 "automatically resume")
create or replace function security.har_aer_item_validate_v1(p_id bigint, p_action text, p_payload jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- evidence: an address on the university's own site; rows: a JSON list of {requirement, minimum?, quote}, each quotation at least
-- har.quote_min_chars long and found among the quotations of the requirements the reader dropped (whitespace and case ignored), so a typed
-- row is always backed by what the official page printed
declare i pipeline.layer4_interventions; v jsonb; j jsonb; e jsonb; v_drop jsonb; v_bad int := 0;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_action in ('attach_document', 'provide_url') then
    v := security.har_official_url_v1(p_payload->>'value', i.provider_id);
    if not coalesce((v->>'ok')::boolean, false) then return jsonb_build_object('valid', false, 'request', v->>'reason'); end if;
    return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'source_url', 'url', v->>'url', 'document', (v->>'document')::boolean, 'stored_copy', v->>'stored_copy'));
  end if;
  begin j := (p_payload->>'value')::jsonb; exception when others then j := null; end;
  if j is null or jsonb_typeof(j) <> 'array' or jsonb_array_length(j) = 0 then
    return jsonb_build_object('valid', false, 'request', 'Enter the dropped requirements as rows: each with what it requires, its minimum if any, and the sentence from the official page.');
  end if;
  -- every dropped quotation of the held read(s), not only those shown on the card
  v_drop := coalesce((select jsonb_agg(q) from (
              select jsonb_array_elements(security.layer4_aer_recovery_state_v1(x.id)->'missing_quotes') q
                from pipeline.layer4_review_items x
               where x.id::text = i.entity or x.id in (select a.review_item_id from pipeline.layer4_aer_recovery_actions a where a.intervention_id = i.id)) z), '[]'::jsonb);
  for e in select x from jsonb_array_elements(j) x loop
    if not security.har_quote_ok_v1(e->>'quote') or coalesce(e->>'requirement', '') = '' then v_bad := v_bad + 1; continue; end if;
    if not exists (select 1 from jsonb_array_elements_text(v_drop) q
                    where position(lower(regexp_replace(e->>'quote', '\s+', ' ', 'g')) in lower(regexp_replace(q, '\s+', ' ', 'g'))) > 0
                       or position(lower(regexp_replace(q, '\s+', ' ', 'g')) in lower(regexp_replace(e->>'quote', '\s+', ' ', 'g'))) > 0) then v_bad := v_bad + 1; end if;
  end loop;
  if v_bad > 0 then
    return jsonb_build_object('valid', false, 'request', v_bad || ' row(s) have no requirement or a quotation that is not one the reader dropped from the official page. Copy the sentence exactly from the page.');
  end if;
  return jsonb_build_object('valid', true, 'normalised', jsonb_build_object('field', 'entry_rows', 'rows', j, 'quote', j->0->>'quote'));
end $function$;
revoke all on function security.har_aer_item_validate_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_aer_item_resume_v1(p_id bigint, p_action text, p_norm jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- the correct reader restarts by itself: a document becomes the university's entry-requirement source (entry-matrix-read, stored copy first),
-- and every held course read of the case gets the existing corrected read (security.course_entry_correction_v1; its own rules refuse a second
-- request); typed rows stay evidence (pipeline.layer4_intervention_values) for the reviewer of the new read
declare i pipeline.layer4_interventions; v_items uuid[]; v_it uuid; v_ok int := 0; v_no jsonb := '[]'::jsonb; v_res jsonb;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  if p_norm->>'field' = 'source_url' and coalesce((p_norm->>'document')::boolean, false) then
    insert into pipeline.entry_matrix_sources as s(provider_id, url, title, rank, found_via, status)
    values (i.provider_id, p_norm->>'url', left('Layer 4 intervention ' || i.id || ': ' || i.subject, 300), 1, 'manual', 'found')
    on conflict (provider_id, url) do nothing;
  end if;
  v_items := case when i.entity like '%|case:%'
                  then array(select a.review_item_id from pipeline.layer4_aer_recovery_actions a join pipeline.layer4_review_items r on r.id = a.review_item_id
                              where a.intervention_id = i.id and r.status = 'pending' group by 1)
                  else array[i.entity::uuid] end;
  foreach v_it in array coalesce(v_items, '{}') loop
    begin
      if (select r.field_code from pipeline.layer4_review_items r where r.id = v_it) = 'course_entry_first_read' then
        v_res := security.course_entry_correction_v1(v_it, i.resolved_by, 'Human input needed ' || i.id || ': ' || coalesce(i.supplied->>'reason', 'input given'));
      else
        v_res := security.aer_reread_v1((select x.source_id from pipeline.entry_matrix_runs x where x.review_item_id = v_it order by x.created_at desc limit 1),
                                        'Human input needed ' || i.id, i.resolved_by);
      end if;
      v_ok := v_ok + 1;
    exception when others then v_no := v_no || jsonb_build_array(jsonb_build_object('item', v_it, 'refused', left(sqlerrm, 200)));
    end;
  end loop;
  return jsonb_build_object('scheduled', v_ok > 0 or (p_norm->>'field' = 'source_url' and coalesce((p_norm->>'document')::boolean, false)),
                            'operation', 'corrected read of ' || v_ok || ' held read(s) by the existing reader', 'refused', v_no);
end $function$;
revoke all on function security.har_aer_item_resume_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.har_aer_item_verify_v1(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- succeeded when every held read of the item or case was replaced (a corrected read superseded it) or decided; failed when the corrected read was
-- refused, with its reason; otherwise pending
declare i pipeline.layer4_interventions; v_items uuid[]; v_pending int; v_refused text;
begin
  select * into i from pipeline.layer4_interventions where id = p_id;
  v_items := case when i.entity like '%|case:%' then array(select a.review_item_id from pipeline.layer4_aer_recovery_actions a where a.intervention_id = i.id group by 1)
                  else array[i.entity::uuid] end;
  select count(*) into v_pending from pipeline.layer4_review_items r where r.id = any (v_items) and r.status = 'pending';
  if v_pending = 0 and cardinality(v_items) > 0 then return jsonb_build_object('state', 'succeeded', 'outcome', 'read_replaced'); end if;
  -- a corrected read asked for since the input and refused, with no other read of the item still asked for
  select s.outcome into v_refused from pipeline.aer_read_supersessions s where s.old_item_id = any (v_items) and s.state = 'refused' and s.requested_at >= coalesce(i.input_at, i.created_at)
     and not exists (select 1 from pipeline.aer_read_supersessions t where t.old_item_id = s.old_item_id and t.state = 'requested')
   order by s.requested_at desc limit 1;
  if v_refused is not null then
    return jsonb_build_object('state', 'failed', 'request', 'The corrected read was not used (' || v_refused || '). Give the official document, or correct the rows against the page.');
  end if;
  return jsonb_build_object('state', 'pending', 'evidence', v_pending || ' held read(s) still waiting');
end $function$;
revoke all on function security.har_aer_item_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.har_aer_item_recheck_v1(p_id bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- cleared when no held read of the item or case is still pending (decided, or replaced by another route)
  select jsonb_build_object('cleared', not exists (select 1 from pipeline.layer4_review_items r where r.status = 'pending'
           and (r.id::text = i.entity or r.id in (select a.review_item_id from pipeline.layer4_aer_recovery_actions a where a.intervention_id = i.id))))
    from pipeline.layer4_interventions i where i.id = p_id
$function$;
revoke all on function security.har_aer_item_recheck_v1(bigint) from public, anon, authenticated;

insert into pipeline.layer4_intervention_handlers(lane, title, validate_fn, resume_fn, verify_fn, recheck_fn, generate_fn, generate_switch, description) values
 ('aer_item', 'Entry requirements: held reads (E13, D-R3)', 'security.har_aer_item_validate_v1(bigint,text,jsonb)', 'security.har_aer_item_resume_v1(bigint,text,jsonb)',
  'security.har_aer_item_verify_v1(bigint)', 'security.har_aer_item_recheck_v1(bigint)', null, null,
  'Raised from the AER review card''s recovery choices (security.layer4_aer_recovery_decide_v1); valid evidence or rows restart the corrected read of every held read of the case.')
on conflict (lane) do nothing;

-- 14 the job (G1: catalogued first; ships ON: it raises, verifies, rechecks and escalates; it admits and spends nothing) -------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('layer4-interventions', 'Platform upkeep', 418, 'Human input needed (Layer 4 interventions)',
  'At :14 and :44: raises one Layer 4 intervention for each failure the platform could not recover (AER sources and reads, scholarship coverage), at most batch.har_generate a lane, fair by provider; verifies resumed work and closes or reopens it; rechecks waiting items; escalates unanswered classes once. Admits and spends nothing.',
  5, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'layer4-interventions') then
    perform cron.schedule('layer4-interventions', '14,44 * * * *', $c$select security.layer4_interventions_tick_v1()$c$);
  end if;
end $j$;

-- 15 root causes and remedies (workstream A's contract) ----------------------------------------------------------------------------------------
select security.ops_root_cause_register_v1('human_input_required', jsonb_build_object('class', 'dependency',
  'title', 'Recovery needs one fact only a person can supply',
  'description', 'Automatic recovery used its attempts and the failure needs an official address, document, identity, scope or value. One deduplicated Layer 4 intervention per lane, entity and missing fact (pipeline.layer4_interventions) asks for it; the work waits without a lease and resumes by itself.',
  'detect', jsonb_build_object('table', 'pipeline.layer4_interventions', 'status', jsonb_build_array('ai_pending', 'awaiting_input'))));
select security.ops_root_cause_register_v1('human_input_not_effective', jsonb_build_object('class', 'data',
  'title', 'Resumed work did not produce its result after human input',
  'description', 'A reviewer''s input was valid, but the resumed read or admission did not produce its result within har.verify_after_hours; the same intervention returns with a specific request.',
  'detect', jsonb_build_object('table', 'pipeline.layer4_intervention_events', 'action', 'resume_failed')));
create or replace function security.har_verify_issue_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- passed when no intervention linked to the issue still waits or is resuming
  select jsonb_build_object('passed', count(*) filter (where i.status in ('ai_pending', 'awaiting_input', 'resuming')) = 0,
                            'measure', jsonb_build_object('linked', count(*), 'open', count(*) filter (where i.status in ('ai_pending', 'awaiting_input', 'resuming')),
                                                          'resolved', count(*) filter (where i.status = 'resolved')),
                            'evidence', jsonb_build_object('issue', p_issue, 'at', now()))
    from pipeline.layer4_interventions i where i.integration_issue_id = p_issue
$function$;
revoke all on function security.har_verify_issue_v1(bigint) from public, anon, authenticated;
select security.ops_remedy_register_v1('layer4_intervention', jsonb_build_object('title', 'Ask a person in Layer 4 (Human input needed), then resume automatically',
  'treats', jsonb_build_array('human_input_required', 'human_input_not_effective'), 'authority', 'admin', 'verify_fn', 'security.har_verify_issue_v1(bigint)',
  'active', true, 'notes', 'Raised by job layer4-interventions; answered in the Layer 4 Inbox; resolved through security.layer4_intervention_resolve_v1. The controller does not act on it.'));

-- 16 component register -----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.layer4_interventions', 'Layer 4', 'Platform', 'Human-assisted recovery: one deduplicated intervention per lane, entity and missing fact', 'active', '{}', '20261104400000'),
 ('table', 'pipeline.layer4_intervention_classes', 'Layer 4', 'Platform', 'Human-assisted recovery: failure classes, actions and ranks', 'active', '{}', '20261104400000'),
 ('table', 'pipeline.layer4_intervention_handlers', 'Layer 4', 'Platform', 'Human-assisted recovery: the resume handler registry', 'active', '{}', '20261104400000'),
 ('table', 'pipeline.layer4_intervention_events', 'Layer 4', 'Platform', 'Human-assisted recovery: the audit', 'active', '{}', '20261104400000'),
 ('table', 'pipeline.layer4_intervention_values', 'Layer 4', 'Platform', 'Human-assisted recovery: supplied values with provenance (proposals)', 'active', '{}', '20261104400000'),
 ('job', 'layer4-interventions', 'Layer 4', 'Platform upkeep', 'Raise, verify, recheck and escalate interventions', 'active', '{}', '20261104400000'),
 ('function', 'security.layer4_intervention_resolve_v1', 'Layer 4', 'Platform', 'The one server function behind every intervention action', 'active', '{}', '20261104400000'),
 ('function', 'security.layer4_intervention_report_v1', 'Layer 4', 'Platform', 'The §9 recovery metrics (in ops_report_v1)', 'active', '{}', '20261104400000'),
 ('table', 'pipeline.layer4_aer_recovery_actions', 'Layer 4', 'Entry requirements', 'Recovery actions on AER reads held by E13 or D-R3 (decision 06:58)', 'active', '{}', '20261104400000'),
 ('function', 'security.layer4_aer_recovery_decide_v1', 'Layer 4', 'Entry requirements', 'Recovery choices on a held AER read (Inbox extend hook)', 'active', '{}', '20261104400000'),
 ('function', 'security.layer4_aer_recovery_detail_v1', 'Layer 4', 'Entry requirements', 'Recovery state on an E13 or D-R3 card (Inbox extend hook)', 'active', '{}', '20261104400000'),
 ('function', 'security.layer4_intervention_inbox_page_v1', 'Layer 4', 'Platform', 'Interventions for the Inbox: a keyset page (kind hook)', 'active', '{}', '20261104400000')
on conflict do nothing;

-- 17 post-check ----------------------------------------------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select * from (values ('security.ops_report_v1(integer)', '3ba694dc078995d88a983e8e92b2f425')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'post-check: % has md5 %', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
  if (select count(*) from pipeline.layer4_intervention_classes) <> 13 then raise exception 'post-check: 13 failure classes'; end if;
  if (select count(*) from pipeline.layer4_intervention_handlers) <> 6 then raise exception 'post-check: 6 lanes'; end if;
  if exists (select 1 from pipeline.layer4_intervention_classes c, lateral (select k from jsonb_object_keys(c.allowed_actions) k) a
              where a.k not in ('provide_url', 'attach_document', 'enter_value', 'confirm_identity', 'select_source', 'confirm_scope', 'correct_value',
                                'search_again', 'confirm_not_published', 'return_technical', 'reject_evidence')) then
    raise exception 'post-check: an action outside the decision''s §2 list';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'har.%.%' and key ~ '^har\.[a-z_]+\.(max_attempts|escalate_after_hours|recheck_hours|deadline_hours|assigned_to)$') <> 65 then
    raise exception 'post-check: every class has its five time bounds';
  end if;
  if security.pipeline_num_v1('har.ai_escalate_on', 0) <> 0 and not exists (select 1 from pipeline.layer4_interventions) then
    raise exception 'post-check: the stronger-model step ships off';
  end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'layer4-interventions') then raise exception 'post-check: the job is catalogued'; end if;
end $$;
