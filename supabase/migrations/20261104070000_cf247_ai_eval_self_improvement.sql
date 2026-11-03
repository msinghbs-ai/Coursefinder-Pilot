-- CF-247 P0 Autonomous AI Operations, workstream E: AI evaluation and controlled self-improvement (Platform Admin mandate 3 Nov 2026 15:37,
-- admin docs/platform/nz-enrichment-brief/2026-11-03-p0-autonomous-ai-operations-mandate-1537.md §6, §15, §19 Phase 4; ownership
-- 2026-11-03-ai-operations-workstreams-1540.md §3, row E). Lands after workstream A (20261104010000: pipeline.ops_remedies and the registers).
-- Why (live, read-only, 3 Nov 2026 15:42-16:08 AEDT):
--   * The platform's AI instructions live in three places and none of them is versioned with its evidence:
--       - worker code constants (coverage-sweep): COURSE_TEXT_SYSTEM (course-text-v1: course description and application deadline),
--         PAGE_ID_SYSTEM (cf247-page-identity-v1.0.2), AI_MATCH_SYSTEM (register course to provider page), ENTRY_PROMPT (entry-matrix-v0.1.4),
--         COURSE_ENTRY_SYSTEM (course-entry-v1), DESCRIPTION_SYSTEM (provider-description-v2), FEE_AI_PROMPT; each item records only a
--         prompt_version label (pipeline.field_enrich_items has no version column; scholarship_ai_extractions has prompt_version);
--       - database rows: pipeline.scholarship_ai_prompts (v1 inactive, v2 active since 11 Oct) and pipeline.layer3_model_profiles
--         (prompt_system, structured_output_schema, quality_benchmark, holdout_qualification; 45 profiles, most paused or retired);
--       - pinned model settings: pipeline entry.matrix_model (openai/gpt-4.1-mini), firecrawl builder_model (qwen/qwen3-30b-a3b-instruct-2507),
--         pipeline.central_ai_settings (openai/gpt-4.1-mini), pipeline.scholarship_ai_models (qwen3-30b active, gpt-4.1-mini and gpt-4.1
--         candidates). Every model is named; the only router profile (openrouter-free-router-v1) is retired. No "auto" routing exists.
--   * Trusted ground truth exists but is not collected: 2,348 Layer 4 decisions (all by signed-in people), 8,000 people's edits
--     (manual_edit_log), 7,464 locks set by people, 919 scholarship readings a person admitted or refused, and quote-checked readings.
--   * Evidence for the seeded proposals (counts in each proposal's production_evidence): deadline reads held by the database checks (413 of
--     1,529), "the page does not state it" on intakes (13,900) and English (12,834), and course-page identity (448 of 639 proposed course links
--     a person decided were rejected; the matcher agreed with a person's page in 986 of 2,077 choices; 18,000 field reads refused as another
--     course's page).
-- What (new objects only; no existing function, table or job is edited):
--   1 Evaluation datasets from trusted ground truth only (pipeline.ai_eval_examples), per task family (pipeline.ai_eval_families):
--     course_fields, course_description, deadline, entry_requirements, scholarship_classification, page_identity, provider_course_matching.
--     Sources (pipeline.ai_eval_source_map, data): Layer 4 approve / edit-and-approve / reject decisions by a person with a reason; people's
--     corrections (manual_edit_log); locks a person set (only where no edit already gives the label); quote-checked readings (state filled, a
--     quote, a stored page, a source whose quote the platform checks); scholarship readings a person admitted or refused; and match cases (the
--     candidate list the matcher saw, labelled by the page a person chose). Unreviewed AI output is refused in data (trigger
--     security.ai_eval_example_trusted_trg): a person-tier example needs a person; a quote-tier example needs a quote and a page; no other
--     source kind exists. A quote-tier example a person later contradicts is set inactive. Examples are deduplicated by label (a manual edit
--     that only repeats a Layer 4 decision adds nothing). Job ai-eval (hourly, at minute 7) adds new examples incrementally.
--   2 Versioned instructions and rules (pipeline.ai_instruction_versions): the live baselines registered with their home and the md5 of their
--     text (the worker constant stays the source; spec s250 checks the md5 against the code), candidates with their full text. A prompt names
--     one pinned, listed model (security.ai_model_pinned_ok_v1): never a router, never "auto". Improvement proposals
--     (pipeline.ai_improvement_proposals) carry problem observed, current method, proposed change, production evidence, expected benefit,
--     risks, evaluation set and acceptance criteria, actual results and status (proposed, evaluating, canary, accepted, rejected, rolled_back);
--     every change of status is kept (pipeline.ai_proposal_events). A rejected or rolled-back proposal enters the ledger
--     (pipeline.ai_rejected_proposals) by fingerprint, and the same change is refused if proposed again.
--   3 Offline regression evaluation: pipeline.ai_eval_sets (frozen, versioned), pipeline.ai_eval_runs and pipeline.ai_eval_answers. The worker
--     answers later (public.svc_ai_eval_run_next_v1 and public.svc_ai_eval_answer_record_v1, through its existing guards and budgets); this
--     migration makes no AI call. Scoring (security.ai_eval_metrics_v1, security.ai_eval_score_v1) gives accuracy, false positives and
--     negatives, coverage, source integrity, reliability, cost and tokens, overall and on person-decided examples; security.ai_eval_compare_v1
--     judges a candidate against the current version on the mandate §6 criteria.
--   4 Canary and rollback: security.ai_canary_pick_v1 sends a bounded share of live items to a candidate only when ai_eval.canary_on is 1
--     (ships 0); canaries are judged only on later decisions by a person (never on the canary's own output), and a failing canary is rolled back
--     automatically. Operational adjustments (a setting on the allow-list pipeline.ai_auto_tunable_settings, inside its min and max and
--     ai_eval.auto_step_max_pct) may be accepted automatically when ai_eval.auto_accept_on is 1 (ships 0). Prompts, extraction schemas and
--     rule sets reach "accepted" only through the release path (security.ai_proposal_record_release_v1, refused on the AI path); admission
--     rules, security, code and schema go to a release; paid permissions and approval boundaries to the Platform Admin
--     (pipeline.ai_approval_boundaries). The AI path cannot write the boundaries, the allow-list or its own proposal's authority
--     (security.ai_eval_boundary_guard_trg, security.ai_proposal_guard_trg; also refused while an ops remedy runs).
--   5 Three proposals seeded from live evidence (deadline extraction, "not stated" on intakes and English, course-page identity), status proposed.
--   6 Root causes ai_quote_not_verbatim, ai_page_identity_mismatch and ai_instruction_regression, and remedies ai_canary_rollback (auto: it only
--     stops a failing canary) and ai_improvement_proposal (release), registered in workstream A's registers.
-- Activation: dataset refresh, scoring and comparison only record and report, so they ship on (ai_eval.refresh_on 1; no spend, no admission).
--   Worker answering of offline runs (ai_eval.offline_runs_on), canary routing (ai_eval.canary_on) and automatic acceptance of operational
--   adjustments (ai_eval.auto_accept_on) ship 0: the first two spend from the AI budget, the third changes live settings.
-- Consumer API: untouched (G3). No consumer function, table, column or edge function changes. No Firecrawl or AI spend.
-- Replaces: nothing (pipeline.scholarship_ai_prompts and pipeline.layer3_model_profiles stay the homes of their text; they are registered as homes, not copied)
-- Retires: nothing
-- Nothing is dropped or deleted. The new job only records.

do $guard$ begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'workstream A (20261104010000, pipeline.ops_remedies) must land before this migration';
  end if;
end $guard$;

-- 1. settings (pipeline toolset; Settings › Pipeline settings, section "AI evaluation") -------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'ai_eval.refresh_on', 'AI evaluation: collect examples and score runs',
  'When 1, job ai-eval adds new trusted examples (Layer 4 decisions, people''s corrections and locks, quote-checked readings, scholarship decisions) and scores recorded evaluation runs. It reads and records only; it spends nothing and admits nothing.',
  'number', to_jsonb(1), 0, 1, 'switch', 1400, 'AI evaluation', 'security.ai_eval_tick_v1 (job ai-eval)', 'Platform Admin mandate 3 Nov 2026 15:37 §6: evaluation inputs from verified decisions and validated evidence; records only, ships on'),
 ('pipeline', 'batch.ai_eval_examples', 'AI evaluation: new examples taken per source a run',
  'Job ai-eval adds at most this many new examples from each trusted source a run, oldest first, so a large backlog is taken over several hours.',
  'number', to_jsonb(2000), 100, 20000, 'examples', 1401, 'AI evaluation', 'security.ai_eval_dataset_refresh_v1 (job ai-eval)', 'Mandate §6; bounded incremental collection'),
 ('pipeline', 'ai_eval.set_max_examples', 'AI evaluation: examples in an evaluation set',
  'A frozen evaluation set takes at most this many active examples of its family, people''s decisions first, then the newest.',
  'number', to_jsonb(2000), 50, 20000, 'examples', 1402, 'AI evaluation', 'security.ai_eval_set_freeze_v1', 'Mandate §6: evaluation datasets'),
 ('pipeline', 'ai_eval.min_person_examples', 'AI evaluation: decisions by a person needed to judge a change',
  'A candidate is judged only on a set holding at least this many examples decided by a person; with fewer it stays under evaluation (not enough ground truth), never accepted on quote-checked readings alone.',
  'number', to_jsonb(30), 0, 5000, 'examples', 1403, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6: unreviewed AI output is not ground truth'),
 ('pipeline', 'ai_eval.min_benefit_pts', 'AI evaluation: smallest benefit that counts',
  'A candidate must gain at least this many percentage points of accuracy or coverage over the current version (with no regression) to pass.',
  'number', to_jsonb(1), 0.1, 50, 'points', 1404, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6 acceptance: measurable benefit'),
 ('pipeline', 'ai_eval.max_accuracy_drop_pts', 'AI evaluation: accuracy loss allowed',
  'The largest drop in accuracy (overall, and on decisions by a person) a candidate may show and still pass.',
  'number', to_jsonb(0), 0, 10, 'points', 1405, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6: no unacceptable regression in accuracy'),
 ('pipeline', 'ai_eval.max_fp_rate_rise_pts', 'AI evaluation: rise in wrong values admitted allowed',
  'The largest rise in false positives (a value given where a person rejected it, or a wrong value) a candidate may show. This is the data admission safety criterion.',
  'number', to_jsonb(0), 0, 10, 'points', 1406, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6: data admission safety'),
 ('pipeline', 'ai_eval.max_coverage_drop_pts', 'AI evaluation: coverage loss allowed',
  'The largest drop in coverage (values found where a person or a checked quote holds one) a candidate may show.',
  'number', to_jsonb(0), 0, 10, 'points', 1407, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6: coverage'),
 ('pipeline', 'ai_eval.min_source_integrity_pct', 'AI evaluation: values with their quote on the page',
  'Of the values a candidate gives in a family that needs a quote, at least this share must carry a quote found on the stored page.',
  'number', to_jsonb(100), 90, 100, 'percent', 1408, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6: source integrity'),
 ('pipeline', 'ai_eval.max_cost_rise_pct', 'AI evaluation: cost rise allowed',
  'The largest rise in AI cost for the same evaluation set a candidate may show.',
  'number', to_jsonb(10), 0, 200, 'percent', 1409, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6: cost'),
 ('pipeline', 'ai_eval.max_error_rate_rise_pts', 'AI evaluation: rise in failed answers allowed',
  'The largest rise in answers that failed or are missing a candidate may show (execution reliability).',
  'number', to_jsonb(1), 0, 20, 'points', 1410, 'AI evaluation', 'security.ai_eval_compare_v1', 'Mandate §6: execution reliability'),
 ('pipeline', 'ai_eval.offline_runs_on', 'AI evaluation: let the worker answer offline runs',
  'When 1, the worker may lease queued offline evaluation runs (public.svc_ai_eval_run_next_v1) and answer them with the pinned model, inside the existing OpenRouter guards. 0 leaves runs queued. Ships 0: answering spends from the AI budget.',
  'number', to_jsonb(0), 0, 1, 'switch', 1417, 'AI evaluation', 'public.svc_ai_eval_run_next_v1 (worker, when built)', 'Mandate §6: offline regression evaluation; spends, so ships off'),
 ('pipeline', 'ai_eval.canary_on', 'AI evaluation: canary routing',
  'When 1, a candidate in canary receives a bounded share of live items (ai_eval.canary_share_pct, ai_eval.canary_max_items_per_day). 0 sends every item to the current version. Ships 0: a canary spends from the existing AI budgets.',
  'number', to_jsonb(0), 0, 1, 'switch', 1411, 'AI evaluation', 'security.ai_canary_pick_v1 (public.svc_ai_instruction_pick_v1)', 'Mandate §6: controlled canary execution; spends, so ships off'),
 ('pipeline', 'ai_eval.canary_share_pct', 'AI evaluation: share of live items sent to a canary',
  'The share of eligible live items a canary candidate receives (by a stable hash of the item, so an item always gets the same version).',
  'number', to_jsonb(5), 1, 20, 'percent', 1412, 'AI evaluation', 'security.ai_canary_pick_v1', 'Mandate §6: bounded share of live work'),
 ('pipeline', 'ai_eval.canary_max_items_per_day', 'AI evaluation: canary items a day',
  'A canary candidate receives at most this many live items a day.',
  'number', to_jsonb(50), 1, 1000, 'items', 1413, 'AI evaluation', 'security.ai_canary_pick_v1', 'Mandate §6: bounded share of live work'),
 ('pipeline', 'ai_eval.canary_min_judged', 'AI evaluation: canary items a person must have decided',
  'A canary is judged only after at least this many of its items have a later decision by a person; until then it keeps running inside its share.',
  'number', to_jsonb(20), 5, 1000, 'items', 1414, 'AI evaluation', 'security.ai_eval_tick_v1', 'Mandate §6: canary judged on verified decisions'),
 ('pipeline', 'ai_eval.auto_accept_on', 'AI evaluation: accept operational adjustments automatically',
  'When 1, a proposed change to a setting on the AI allow-list (batch sizes and similar), inside its minimum and maximum and ai_eval.auto_step_max_pct, is tried and accepted automatically when its measured results pass, or put back when they do not. 0: such proposals wait. Prompts, rules, admission, security, code, schema and paid permissions never use this path.',
  'number', to_jsonb(0), 0, 1, 'switch', 1415, 'AI evaluation', 'security.ai_proposal_advance_v1', 'Mandate §6 and §15: reversible settings optimisation within approved bounds; ships off'),
 ('pipeline', 'ai_eval.auto_step_max_pct', 'AI evaluation: largest automatic setting change',
  'An operational adjustment may move a setting by at most this share of its current value at a time.',
  'number', to_jsonb(25), 1, 50, 'percent', 1416, 'AI evaluation', 'security.ai_proposal_submit_v1', 'Mandate §6: adjustments within established guardrails')
on conflict (toolset_key, key) do nothing;

-- 2. tables ------------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.ai_eval_families (
  code text primary key check (code ~ '^[a-z][a-z0-9_]*$'),
  title text not null,
  description text not null,
  needs_quote boolean not null default true,
  instruction_codes text[] not null default '{}',
  sort int not null default 100
);
comment on table pipeline.ai_eval_families is 'CF-247 P0 workstream E (mandate §6): the AI task families evaluated (course fields, descriptions, deadlines, entry requirements, scholarship classification, page identity, provider and course matching), whether a value needs a quote on the page, and the instructions that serve each. Never read by the consumer API.';
alter table pipeline.ai_eval_families enable row level security;

create table if not exists pipeline.ai_eval_source_map (
  source_kind text not null check (source_kind in ('l4_decision', 'human_correction', 'manual_lock', 'quote_evidence', 'scholarship_review', 'match_case')),
  entity text not null,
  field text not null,
  action text not null default '*',
  family text not null references pipeline.ai_eval_families(code),
  label text check (label in ('accept', 'correct', 'reject', 'no_value')),
  primary key (source_kind, entity, field, action)
);
comment on table pipeline.ai_eval_source_map is 'CF-247 P0 workstream E (mandate §6): which trusted source rows become evaluation examples, for which family and with which label (Layer 4 field codes, people''s corrections by entity, field and action, locks, quote-checked fields by reading source). Data, not code: a new field is a row. Read by security.ai_eval_dataset_refresh_v1.';
alter table pipeline.ai_eval_source_map enable row level security;

create table if not exists pipeline.ai_eval_examples (
  id bigserial primary key,
  family text not null references pipeline.ai_eval_families(code),
  source_kind text not null check (source_kind in ('l4_decision', 'human_correction', 'manual_lock', 'quote_evidence', 'scholarship_review', 'match_case')),
  tier text not null check (tier in ('person', 'verified_quote')),
  basis text not null check (basis in ('person', 'rule_decision', 'batch_decision', 'quote_check')),
  source_ref text not null unique,
  label_key text not null,
  entity text not null,
  entity_id uuid,
  field text not null,
  label text not null check (label in ('accept', 'correct', 'reject', 'no_value')),
  expected jsonb,
  rejected jsonb,
  reason text,
  quote text,
  evidence_id uuid,
  page_ref text,
  input_ref text,
  decided_by uuid,
  decided_at timestamptz,
  active boolean not null default true,
  inactive_reason text,
  added_at timestamptz not null default now(),
  check ((tier = 'verified_quote') = (source_kind = 'quote_evidence'))
);
create unique index if not exists ai_eval_examples_label_key on pipeline.ai_eval_examples(label_key);
create index if not exists ai_eval_examples_family on pipeline.ai_eval_examples(family, active, tier);
create index if not exists ai_eval_examples_entity on pipeline.ai_eval_examples(entity_id, family);
comment on table pipeline.ai_eval_examples is 'CF-247 P0 workstream E (mandate §6): evaluation ground truth, one row per trusted label: a Layer 4 decision by a person, a person''s correction or lock, a quote-checked reading, a scholarship reading a person decided, or a match case labelled by a person. Unreviewed AI output is refused (security.ai_eval_example_trusted_trg). Filled by job ai-eval; deduplicated by label_key. Never read by the consumer API.';
alter table pipeline.ai_eval_examples enable row level security;

create table if not exists pipeline.ai_eval_sets (
  id bigserial primary key,
  family text not null references pipeline.ai_eval_families(code),
  version int not null,
  example_count int not null,
  person_count int not null,
  quote_count int not null,
  frozen_at timestamptz not null default now(),
  note text,
  unique (family, version)
);
comment on table pipeline.ai_eval_sets is 'CF-247 P0 workstream E (mandate §6): frozen, versioned evaluation sets per family (members in pipeline.ai_eval_set_members), so a baseline and a candidate are scored on exactly the same examples.';
alter table pipeline.ai_eval_sets enable row level security;

create table if not exists pipeline.ai_eval_set_members (
  set_id bigint not null references pipeline.ai_eval_sets(id),
  example_id bigint not null references pipeline.ai_eval_examples(id),
  primary key (set_id, example_id)
);
comment on table pipeline.ai_eval_set_members is 'CF-247 P0 workstream E (mandate §6): the examples of a frozen evaluation set (pipeline.ai_eval_sets).';
alter table pipeline.ai_eval_set_members enable row level security;

create table if not exists pipeline.ai_instruction_versions (
  id bigserial primary key,
  family text not null references pipeline.ai_eval_families(code),
  code text not null check (code ~ '^[a-z][a-z0-9_.-]*$'),
  kind text not null check (kind in ('prompt', 'extraction_schema', 'rule_set', 'operational_setting')),
  version text not null,
  home text not null,
  body text,
  spec jsonb not null default '{}',
  body_md5 text not null,
  model_identifier text,
  status text not null check (status in ('current', 'previous', 'candidate', 'rolled_back', 'rejected')),
  parent_id bigint references pipeline.ai_instruction_versions(id),
  note text,
  created_at timestamptz not null default now(),
  unique (code, version)
);
create unique index if not exists ai_instruction_versions_current on pipeline.ai_instruction_versions(code) where status = 'current';
comment on table pipeline.ai_instruction_versions is 'CF-247 P0 workstream E (mandate §6): versions of the platform''s AI instructions and rules (prompt text, extraction schema, rule set, operational setting). A live baseline records its home (worker constant, database row) and the md5 of its text; a candidate holds its full text. One current version per code; previous versions are kept for rollback. A prompt names one pinned, listed model, never a router.';
alter table pipeline.ai_instruction_versions enable row level security;

create table if not exists pipeline.ai_approval_boundaries (
  change_class text primary key,
  authority text not null check (authority in ('auto', 'release', 'admin')),
  note text not null
);
comment on table pipeline.ai_approval_boundaries is 'CF-247 P0 workstream E (mandate §6, §15): who may accept each class of AI improvement: auto (operational adjustments inside guardrails), release (prompts, schemas, rule sets, admission rules, security, code, schema) or admin (paid permissions, approval boundaries). Written only by a release migration; refused on the AI path and while an ops remedy runs (security.ai_eval_boundary_guard_trg).';
alter table pipeline.ai_approval_boundaries enable row level security;

create table if not exists pipeline.ai_auto_tunable_settings (
  toolset_key text not null,
  key text not null,
  note text not null,
  primary key (toolset_key, key)
);
comment on table pipeline.ai_auto_tunable_settings is 'CF-247 P0 workstream E (mandate §6): the settings an operational adjustment may change automatically (batch sizes and similar), always inside the setting''s own minimum and maximum. Never a spending, budget, guard, admission, lock or AI-evaluation setting (checked on write). Written only by a release migration (security.ai_eval_boundary_guard_trg).';
alter table pipeline.ai_auto_tunable_settings enable row level security;

create table if not exists pipeline.ai_improvement_proposals (
  id bigserial primary key,
  code text not null unique,
  family text not null references pipeline.ai_eval_families(code),
  change_class text not null references pipeline.ai_approval_boundaries(change_class),
  authority text not null check (authority in ('auto', 'release', 'admin')),
  title text not null,
  problem_observed text not null,
  current_method text not null,
  proposed_change text not null,
  production_evidence jsonb not null,
  expected_benefit text not null,
  risks text not null,
  baseline_version_id bigint references pipeline.ai_instruction_versions(id),
  candidate_version_id bigint references pipeline.ai_instruction_versions(id),
  target_setting jsonb,
  eval_set_id bigint references pipeline.ai_eval_sets(id),
  acceptance_criteria jsonb not null,
  actual_results jsonb not null default '{}',
  applied jsonb,
  status text not null default 'proposed' check (status in ('proposed', 'evaluating', 'canary', 'accepted', 'rejected', 'rolled_back')),
  status_reason text,
  release_ref text,
  fingerprint text not null,
  proposed_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  decided_at timestamptz
);
create index if not exists ai_improvement_proposals_status on pipeline.ai_improvement_proposals(status);
create index if not exists ai_improvement_proposals_fp on pipeline.ai_improvement_proposals(fingerprint);
comment on table pipeline.ai_improvement_proposals is 'CF-247 P0 workstream E (mandate §6): one improvement to the platform''s AI: problem observed, current method, proposed change, production evidence, expected benefit, risks, evaluation set and acceptance criteria, actual results, and status (proposed, evaluating, canary, accepted, rejected, rolled_back). Its authority comes from pipeline.ai_approval_boundaries and cannot be changed (security.ai_proposal_guard_trg).';
alter table pipeline.ai_improvement_proposals enable row level security;

create table if not exists pipeline.ai_proposal_events (
  id bigserial primary key,
  proposal_id bigint not null references pipeline.ai_improvement_proposals(id),
  from_status text,
  to_status text not null,
  by_path text not null,
  reason text,
  detail jsonb not null default '{}',
  at timestamptz not null default now()
);
comment on table pipeline.ai_proposal_events is 'CF-247 P0 workstream E (mandate §6): every status change of an improvement proposal, with the path that made it (ai, release, engineering) and the reason. History is kept; nothing is rewritten.';
alter table pipeline.ai_proposal_events enable row level security;

create table if not exists pipeline.ai_rejected_proposals (
  fingerprint text primary key,
  proposal_id bigint not null references pipeline.ai_improvement_proposals(id),
  family text not null,
  change_class text not null,
  summary text not null,
  outcome text not null check (outcome in ('rejected', 'rolled_back')),
  reason text not null,
  results jsonb not null default '{}',
  at timestamptz not null default now()
);
comment on table pipeline.ai_rejected_proposals is 'CF-247 P0 workstream E (mandate §6): the ledger of improvements that were rejected or rolled back, by fingerprint of the change (family, class, target and normalised content). The same change is refused if proposed again (security.ai_proposal_guard_trg).';
alter table pipeline.ai_rejected_proposals enable row level security;

create table if not exists pipeline.ai_eval_runs (
  id bigserial primary key,
  proposal_id bigint not null references pipeline.ai_improvement_proposals(id),
  arm text not null check (arm in ('baseline', 'candidate')),
  version_id bigint not null references pipeline.ai_instruction_versions(id),
  set_id bigint not null references pipeline.ai_eval_sets(id),
  model_identifier text,
  state text not null default 'queued' check (state in ('queued', 'answering', 'recorded', 'scored', 'failed')),
  leased_until timestamptz,
  worker text,
  metrics jsonb,
  requested_at timestamptz not null default now(),
  recorded_at timestamptz,
  scored_at timestamptz,
  unique (proposal_id, arm, set_id)
);
comment on table pipeline.ai_eval_runs is 'CF-247 P0 workstream E (mandate §6): one offline regression run of one instruction version (baseline or candidate) on one frozen evaluation set. The worker answers it later through its existing guards (public.svc_ai_eval_run_next_v1, public.svc_ai_eval_answer_record_v1); scored by security.ai_eval_score_v1.';
alter table pipeline.ai_eval_runs enable row level security;

create table if not exists pipeline.ai_eval_answers (
  run_id bigint not null references pipeline.ai_eval_runs(id),
  example_id bigint not null references pipeline.ai_eval_examples(id),
  verdict text check (verdict in ('accept', 'reject', 'no_value')),
  value jsonb,
  quote text,
  quote_on_page boolean,
  tokens_in int,
  tokens_out int,
  cost_usd numeric,
  error text,
  at timestamptz not null default now(),
  primary key (run_id, example_id)
);
comment on table pipeline.ai_eval_answers is 'CF-247 P0 workstream E (mandate §6): the answer an instruction version gave to one evaluation example, with the worker''s deterministic quote-on-page check, tokens, cost and any error.';
alter table pipeline.ai_eval_answers enable row level security;

create table if not exists pipeline.ai_canary_assignments (
  proposal_id bigint not null references pipeline.ai_improvement_proposals(id),
  item_key text not null,
  family text not null,
  entity_id uuid,
  arm text not null check (arm in ('current', 'candidate')),
  version_id bigint not null references pipeline.ai_instruction_versions(id),
  verdict text check (verdict in ('accept', 'reject', 'no_value')),
  value jsonb,
  quote_on_page boolean,
  cost_usd numeric,
  tokens_in int,
  tokens_out int,
  error text,
  assigned_at timestamptz not null default now(),
  answered_at timestamptz,
  primary key (proposal_id, item_key)
);
comment on table pipeline.ai_canary_assignments is 'CF-247 P0 workstream E (mandate §6): which version each live item got while a candidate was in canary, and its answer. Judged only on a later decision by a person for the same item (never on the canary''s own output).';
alter table pipeline.ai_canary_assignments enable row level security;

revoke all on pipeline.ai_eval_families, pipeline.ai_eval_source_map, pipeline.ai_eval_examples, pipeline.ai_eval_sets, pipeline.ai_eval_set_members,
  pipeline.ai_instruction_versions, pipeline.ai_approval_boundaries, pipeline.ai_auto_tunable_settings, pipeline.ai_improvement_proposals,
  pipeline.ai_proposal_events, pipeline.ai_rejected_proposals, pipeline.ai_eval_runs, pipeline.ai_eval_answers, pipeline.ai_canary_assignments
  from anon, authenticated, service_role;

-- 3. helpers and guards --------------------------------------------------------------------------------------------------------------------
-- the AI path: set (for the call) by every function the platform's AI or its jobs run; boundary writes are refused while it is on
create or replace function security.ai_eval_ai_path_v1() returns boolean
language sql stable set search_path to '' as $function$
  select coalesce(current_setting('cf247.ai_eval_path', true), '') = 'on' or security.ops_remedy_guard_active_v1()
$function$;
revoke all on function security.ai_eval_ai_path_v1() from public, anon, authenticated;

-- a value compared across sources: a single-key object gives its value; text is trimmed and lower case; addresses lose the scheme
-- difference http/https and a trailing slash
create or replace function security.ai_eval_norm_v1(p jsonb) returns text
language sql immutable set search_path to '' as $function$
  select case when p is null or p = 'null'::jsonb then null else
    regexp_replace(regexp_replace(lower(btrim(
      case when jsonb_typeof(p) = 'object' and (select count(*) from jsonb_object_keys(p)) = 1 then (select v #>> '{}' from jsonb_each(p) e(k, v))
           when jsonb_typeof(p) = 'string' then p #>> '{}' else p::text end)), '^http://', 'https://'), '/+$', '') end
$function$;

-- a prompt names one pinned model that the platform lists somewhere (a model register, a central setting or a model setting); never a
-- router, never "auto", never a list
create or replace function security.ai_model_pinned_ok_v1(p_model text) returns boolean
language sql stable security definer set search_path to '' as $function$
  select coalesce(p_model, '') ~ '^[a-z0-9][a-z0-9._-]*/[a-zA-Z0-9][a-zA-Z0-9._:-]*$'
     and p_model !~* '(^openrouter/|(^|[/:._-])auto([/:._-]|$)|router)'
     and (exists (select 1 from pipeline.scholarship_ai_models m where m.model_identifier = p_model and m.status in ('active', 'candidate'))
       or exists (select 1 from pipeline.layer3_model_profiles l where l.model_identifier = p_model and l.retired_at is null)
       or exists (select 1 from pipeline.central_ai_settings c where c.model_identifier = p_model)
       or exists (select 1 from pipeline.platform_toolset_settings s where s.kind = 'text' and s.key ~ 'model$' and s.value #>> '{}' = p_model))
$function$;
revoke all on function security.ai_model_pinned_ok_v1(text) from public, anon, authenticated;

create or replace function security.ai_eval_boundary_guard_trg() returns trigger
language plpgsql set search_path to '' as $function$
-- the approval boundaries and the allow-list change only in a release migration (cf247.release names it), never on the AI path or in a remedy
begin
  if security.ai_eval_ai_path_v1() then
    raise exception 'ai guard: the AI cannot change its approval boundaries (%)', tg_table_name using errcode = '42501';
  end if;
  if coalesce(current_setting('cf247.release', true), '') !~ '^[0-9]{14}$' then
    raise exception 'ai guard: % changes only in a release migration', tg_table_name using errcode = '42501';
  end if;
  if tg_table_name = 'ai_auto_tunable_settings' and tg_op <> 'DELETE' then
    if new.toolset_key <> 'pipeline' or new.key ~* '(ai_eval|guard|budget|cap|credit|spend|share|admission|lock|review|layer4|_on$|paid|search_per|firecrawl|openrouter|model)' then
      raise exception 'ai guard: % is not an operational setting the AI may tune', new.key using errcode = '42501';
    end if;
    if not exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = new.toolset_key and s.key = new.key and s.kind = 'number'
                    and s.min_value is not null and s.max_value is not null) then
      raise exception 'ai guard: % needs a numeric setting with a minimum and a maximum', new.key using errcode = '22023';
    end if;
  end if;
  return coalesce(new, old);
end $function$;
create or replace trigger ai_approval_boundaries_guard before insert or update or delete on pipeline.ai_approval_boundaries for each row execute function security.ai_eval_boundary_guard_trg();
create or replace trigger ai_auto_tunable_settings_guard before insert or update or delete on pipeline.ai_auto_tunable_settings for each row execute function security.ai_eval_boundary_guard_trg();

create or replace function security.ai_eval_example_trusted_trg() returns trigger
language plpgsql set search_path to '' as $function$
-- ground truth only: a person-tier example names the person who decided it; a quote-tier example has a quote and a stored page; the label,
-- family and source never change after the example exists
begin
  if new.tier = 'person' and new.decided_by is null then
    raise exception 'ai_eval: % is not ground truth: no person decided it', new.source_ref using errcode = '22023';
  end if;
  if new.tier = 'verified_quote' and (coalesce(btrim(new.quote), '') = '' or (new.evidence_id is null and coalesce(new.page_ref, '') = '')) then
    raise exception 'ai_eval: % is not ground truth: no quote on a stored page', new.source_ref using errcode = '22023';
  end if;
  if new.label in ('accept', 'correct') and new.expected is null then
    raise exception 'ai_eval: % has no expected value', new.source_ref using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and (new.source_ref, new.family, new.tier, new.label, new.expected, new.rejected, new.decided_by)
                       is distinct from (old.source_ref, old.family, old.tier, old.label, old.expected, old.rejected, old.decided_by) then
    raise exception 'ai_eval: an example''s label and source are kept as recorded (%)', old.source_ref using errcode = '42501';
  end if;
  return new;
end $function$;
create or replace trigger ai_eval_examples_trusted before insert or update on pipeline.ai_eval_examples for each row execute function security.ai_eval_example_trusted_trg();

create or replace function security.ai_instruction_version_trg() returns trigger
language plpgsql set search_path to '' as $function$
begin
  if tg_op = 'INSERT' then
    if new.status = 'candidate' and coalesce(new.body, '') = '' and new.spec = '{}'::jsonb then
      raise exception 'ai_eval: candidate % % has no text, schema or rules', new.code, new.version using errcode = '22023';
    end if;
    if new.body is not null then new.body_md5 := md5(new.body); end if;
  elsif (new.code, new.kind, new.version, new.body, new.spec, new.body_md5, new.model_identifier, new.family)
        is distinct from (old.code, old.kind, old.version, old.body, old.spec, old.body_md5, old.model_identifier, old.family) then
    raise exception 'ai_eval: a version is never rewritten; register a new one (% %)', old.code, old.version using errcode = '42501';
  end if;
  if new.kind = 'prompt' and not security.ai_model_pinned_ok_v1(new.model_identifier) then
    raise exception 'ai_eval: % % must name one pinned, listed model (got %); routing across models is not allowed', new.code, new.version, coalesce(new.model_identifier, 'none') using errcode = '22023';
  end if;
  return new;
end $function$;
create or replace trigger ai_instruction_versions_guard before insert or update on pipeline.ai_instruction_versions for each row execute function security.ai_instruction_version_trg();

create or replace function security.ai_proposal_guard_trg() returns trigger
language plpgsql set search_path to '' as $function$
-- a proposal's authority is the boundary table's, never the proposer's; it cannot change after submission; a change already rejected or rolled
-- back is refused; on the AI path a prompt, schema, rule, admission, security, code, schema or paid change never reaches accepted
declare v_auth text; v_path text := case when security.ai_eval_ai_path_v1() then 'ai' when coalesce(current_setting('cf247.release', true), '') <> '' then 'release' else 'engineering' end;
begin
  if tg_op = 'INSERT' then
    select b.authority into v_auth from pipeline.ai_approval_boundaries b where b.change_class = new.change_class;
    if v_auth is null then raise exception 'ai_eval: unknown change class %', new.change_class using errcode = '22023'; end if;
    if new.authority is distinct from v_auth then
      raise exception 'ai_eval: a change of class % has authority %, not %', new.change_class, v_auth, new.authority using errcode = '42501';
    end if;
    if exists (select 1 from pipeline.ai_rejected_proposals r where r.fingerprint = new.fingerprint) then
      raise exception 'ai_eval: this change was % before (proposal %); it is not proposed again',
        (select r.outcome from pipeline.ai_rejected_proposals r where r.fingerprint = new.fingerprint),
        (select r.proposal_id from pipeline.ai_rejected_proposals r where r.fingerprint = new.fingerprint) using errcode = '23505';
    end if;
    if new.status <> 'proposed' then raise exception 'ai_eval: a proposal starts as proposed' using errcode = '22023'; end if;
    return new;
  end if;
  if (new.code, new.family, new.change_class, new.authority, new.fingerprint, new.proposed_by, new.problem_observed, new.current_method, new.proposed_change,
      new.production_evidence, new.expected_benefit, new.risks, new.baseline_version_id, new.candidate_version_id, new.target_setting, new.created_at)
     is distinct from (old.code, old.family, old.change_class, old.authority, old.fingerprint, old.proposed_by, old.problem_observed, old.current_method, old.proposed_change,
      old.production_evidence, old.expected_benefit, old.risks, old.baseline_version_id, old.candidate_version_id, old.target_setting, old.created_at) then
    raise exception 'ai_eval: proposal % is kept as submitted; submit a new proposal', old.code using errcode = '42501';
  end if;
  if old.status <> 'proposed' and new.acceptance_criteria is distinct from old.acceptance_criteria then
    raise exception 'ai_eval: the acceptance criteria of % are fixed once evaluation starts', old.code using errcode = '42501';
  end if;
  if new.status is distinct from old.status then
    if not ((old.status, new.status) in (('proposed', 'evaluating'), ('proposed', 'canary'), ('proposed', 'rejected'), ('evaluating', 'canary'), ('evaluating', 'rejected'),
             ('evaluating', 'accepted'), ('canary', 'accepted'), ('canary', 'rolled_back'), ('canary', 'rejected'), ('accepted', 'rolled_back'))) then
      raise exception 'ai_eval: % cannot go from % to %', old.code, old.status, new.status using errcode = '22023';
    end if;
    if new.status = 'accepted' and old.authority <> 'auto' and (v_path = 'ai' or coalesce(new.release_ref, '') = '') then
      raise exception 'ai_eval: a change of class % (%) is accepted only through the % path with its release reference', old.change_class, old.code, old.authority using errcode = '42501';
    end if;
    if new.status = 'accepted' and old.authority = 'auto' and v_path = 'ai' and security.pipeline_num_v1('ai_eval.auto_accept_on', 0) <> 1 then
      raise exception 'ai_eval: automatic acceptance is off (ai_eval.auto_accept_on)' using errcode = '42501';
    end if;
    insert into pipeline.ai_proposal_events(proposal_id, from_status, to_status, by_path, reason, detail)
    values (old.id, old.status, new.status, v_path, new.status_reason, coalesce(new.actual_results, '{}'::jsonb));
    if new.status in ('rejected', 'rolled_back') then
      insert into pipeline.ai_rejected_proposals(fingerprint, proposal_id, family, change_class, summary, outcome, reason, results)
      values (old.fingerprint, old.id, old.family, old.change_class, old.title, new.status, coalesce(new.status_reason, new.status), coalesce(new.actual_results, '{}'::jsonb))
      on conflict (fingerprint) do nothing;
      new.decided_at := now();
    elsif new.status = 'accepted' then
      new.decided_at := now();
    end if;
  end if;
  new.updated_at := now();
  return new;
end $function$;
create or replace trigger ai_improvement_proposals_guard before insert or update on pipeline.ai_improvement_proposals for each row execute function security.ai_proposal_guard_trg();

-- 4. datasets ------------------------------------------------------------------------------------------------------------------------------
create or replace function security.ai_eval_dataset_refresh_v1() returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '50s' as $function$
-- fixed: the statement time-out keeps a slow run from holding the scheduler (technical safety, not a business limit)
-- Adds new trusted examples from each source (at most batch.ai_eval_examples each, oldest first; incremental by source_ref), skips a label
-- already held (label_key), and sets inactive a quote-checked example a person has since contradicted.
declare v_n int := greatest(security.pipeline_num_v1('batch.ai_eval_examples', 2000), 1)::int; v jsonb := '{}'; c int;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  -- Layer 4 decisions by a person, with a reason (approve, edit and approve, reject; a return is not a decision on the value)
  with src as (
    select 'layer4_decisions:' || d.id source_ref, m.family, r.entity_type entity, r.entity_id, r.field_code field,
           case d.action when 'approve' then 'accept' when 'edit_and_approve' then 'correct' else 'reject' end label,
           case when d.action in ('approve', 'edit_and_approve') then coalesce(d.final_value, d.proposed_value) end expected,
           case when d.action in ('reject', 'edit_and_approve') then d.proposed_value end rejected,
           d.reason, coalesce(d.evidence_id, r.evidence_id) evidence_id, 'layer4_review_items:' || r.id input_ref, d.actor_id decided_by, d.created_at decided_at,
           case when d.reason ~ '^Decided by rule' then 'rule_decision' when d.reason ~ '^\[?L4B-' then 'batch_decision' else 'person' end basis
      from pipeline.layer4_decisions d
      join pipeline.layer4_review_items r on r.id = d.review_item_id
      join pipeline.ai_eval_source_map m on m.source_kind = 'l4_decision' and m.entity = r.entity_type and m.field = r.field_code and m.action = '*'
     where d.action in ('approve', 'edit_and_approve', 'reject') and coalesce(btrim(d.reason), '') <> ''
       and exists (select 1 from auth.users u where u.id = d.actor_id)
       and not exists (select 1 from pipeline.ai_eval_examples x where x.source_ref = 'layer4_decisions:' || d.id)
     order by d.created_at limit v_n)
  insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, entity_id, field, label, expected, rejected, reason, evidence_id, input_ref, decided_by, decided_at)
  select family, 'l4_decision', 'person', basis, source_ref,
         md5(concat_ws('|', family, entity_id, case when label in ('accept', 'correct') then 'positive' else 'negative' end, coalesce(security.ai_eval_norm_v1(expected), security.ai_eval_norm_v1(rejected), field))),
         entity, entity_id, field, label, expected, rejected, reason, evidence_id, input_ref, decided_by, decided_at from src
  on conflict do nothing;
  get diagnostics c = row_count; v := v || jsonb_build_object('l4_decision', c);

  -- corrections a person made (manual_edit_log)
  with src as (
    select 'manual_edit_log:' || e.id source_ref, m.family, e.entity, e.entity_id, e.field,
           case when m.label = 'correct' and security.ai_eval_norm_v1(e.after) is not distinct from security.ai_eval_norm_v1(e.before) then 'accept' else m.label end label,
           case when m.label in ('accept', 'correct') then e.after end expected,
           case when m.label in ('reject', 'no_value', 'correct') and jsonb_typeof(e.before) = 'string' then e.before end rejected,
           coalesce(e.reason, e.action) reason, e.actor decided_by, e.at decided_at
      from pipeline.manual_edit_log e
      join pipeline.ai_eval_source_map m on m.source_kind = 'human_correction' and m.entity = e.entity and m.field = e.field and m.action = e.action
     where exists (select 1 from auth.users u where u.id = e.actor)
       and not exists (select 1 from pipeline.ai_eval_examples x where x.source_ref = 'manual_edit_log:' || e.id)
     order by e.at limit v_n)
  insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, entity_id, field, label, expected, rejected, reason, decided_by, decided_at)
  select family, 'human_correction', 'person', 'person', source_ref,
         md5(concat_ws('|', family, entity_id, case when label in ('accept', 'correct') then 'positive' else 'negative' end, coalesce(security.ai_eval_norm_v1(expected), security.ai_eval_norm_v1(rejected), field))),
         entity, entity_id, field, label, expected, rejected, reason, decided_by, decided_at from src
  where label in ('reject', 'no_value') or expected is not null
  on conflict do nothing;
  get diagnostics c = row_count; v := v || jsonb_build_object('human_correction', c);

  -- locks a person set, where no correction already labels the same thing (the value is the one held now)
  with src as (
    select 'manual_locks:' || l.entity || ':' || l.entity_id || ':' || l.field source_ref, m.family, l.entity, l.entity_id, l.field,
           case l.mode when 'removed' then 'no_value' else 'accept' end label,
           case when l.mode = 'removed' then null
                when l.entity = 'course' then (select to_jsonb(c.course_url) from catalogue.courses c where c.id = l.entity_id)
                when l.field = 'website' then (select to_jsonb(p.website) from catalogue.providers p where p.id = l.entity_id)
                when l.field = 'display_name' then (select to_jsonb(p.display_name) from catalogue.providers p where p.id = l.entity_id)
                when l.field = 'canonical_name' then (select to_jsonb(p.canonical_name) from catalogue.providers p where p.id = l.entity_id) end expected,
           l.set_by decided_by, l.set_at decided_at
      from pipeline.manual_locks l
      join pipeline.ai_eval_source_map m on m.source_kind = 'manual_lock' and m.entity = l.entity and m.field = l.field
     where exists (select 1 from auth.users u where u.id = l.set_by)
       and not exists (select 1 from pipeline.manual_edit_log e where e.entity_id = l.entity_id and e.field = l.field and e.actor is not null)
       and not exists (select 1 from pipeline.ai_eval_examples x where x.source_ref = 'manual_locks:' || l.entity || ':' || l.entity_id || ':' || l.field)
     order by l.set_at limit v_n)
  insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, entity_id, field, label, expected, reason, decided_by, decided_at)
  select family, 'manual_lock', 'person', 'person', source_ref, md5(concat_ws('|', family, entity_id, case when label in ('accept', 'correct') then 'positive' else 'negative' end, coalesce(security.ai_eval_norm_v1(expected), field))),
         entity, entity_id, field, label, expected, 'locked by a person', decided_by, decided_at from src
  where label = 'no_value' or expected is not null
  on conflict do nothing;
  get diagnostics c = row_count; v := v || jsonb_build_object('manual_lock', c);

  -- scholarship readings a person admitted or refused
  with src as (
    select 'scholarship_ai_reviews:' || s.id source_ref, m.family, coalesce(s.scholarship_id, s.provider_id) entity_id,
           case s.status when 'admitted' then 'accept' else 'reject' end label,
           case when s.status = 'admitted' then coalesce(s.decision, '{}'::jsonb) || jsonb_build_object('url', s.url) end expected,
           case when s.status = 'refused' then jsonb_build_object('url', s.url) end rejected,
           coalesce(s.note, s.reason) reason, s.storage_path page_ref,
           case when cardinality(s.extraction_ids) > 0 then 'scholarship_ai_extractions:' || s.extraction_ids[cardinality(s.extraction_ids)] end input_ref,
           s.decided_by, s.decided_at
      from pipeline.scholarship_ai_reviews s
      join pipeline.ai_eval_source_map m on m.source_kind = 'scholarship_review' and m.entity = 'scholarship' and m.field = 'scholarship' and m.action = s.status
     where exists (select 1 from auth.users u where u.id = s.decided_by)
       and not exists (select 1 from pipeline.ai_eval_examples x where x.source_ref = 'scholarship_ai_reviews:' || s.id)
     order by s.decided_at limit v_n)
  insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, entity_id, field, label, expected, rejected, reason, page_ref, input_ref, decided_by, decided_at)
  select family, 'scholarship_review', 'person', 'person', source_ref, md5(concat_ws('|', family, source_ref)),
         'scholarship', entity_id, 'scholarship', label, expected, rejected, reason, page_ref, input_ref, decided_by, decided_at from src
  on conflict do nothing;
  get diagnostics c = row_count; v := v || jsonb_build_object('scholarship_review', c);

  -- readings whose quote the platform checked on the stored page
  with src as (
    select 'field_enrich_items:' || i.id source_ref, m.family, i.course_id, i.provider_id, i.field, i.value, i.quote, i.evidence_id, i.storage_path, i.updated_at
      from pipeline.field_enrich_items i
      join pipeline.ai_eval_source_map m on m.source_kind = 'quote_evidence' and m.entity = 'course' and m.field = i.field and m.action = i.source
     where i.state = 'filled' and coalesce(btrim(i.quote), '') <> '' and (i.evidence_id is not null or i.storage_path is not null) and i.value is not null
       and not exists (select 1 from pipeline.ai_eval_examples x where x.source_ref = 'field_enrich_items:' || i.id)
     order by i.updated_at limit v_n)
  insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, entity_id, field, label, expected, quote, evidence_id, page_ref, input_ref, decided_at)
  select family, 'quote_evidence', 'verified_quote', 'quote_check', source_ref, md5(concat_ws('|', family, coalesce(course_id, provider_id), field, security.ai_eval_norm_v1(value))),
         'course', coalesce(course_id, provider_id), field, 'accept', value, quote, evidence_id, storage_path, source_ref, updated_at from src
  on conflict do nothing;
  get diagnostics c = row_count; v := v || jsonb_build_object('quote_evidence', c);

  -- match cases: the candidate list the matcher saw, labelled with the page a person chose for that course
  with lab as (
    select distinct on (x.entity_id) x.entity_id, x.id, x.expected, x.basis, x.decided_by, x.decided_at
      from pipeline.ai_eval_examples x
     where x.family = 'page_identity' and x.entity = 'course' and x.tier = 'person' and x.label in ('accept', 'correct') and x.active
     order by x.entity_id, x.decided_at desc),
  src as (
    select 'coverage_ai_match:' || cm.id source_ref, lab.entity_id, lab.expected, lab.basis, lab.decided_by, lab.decided_at, cm.id match_id, lab.id label_id
      from pipeline.coverage_ai_match cm join lab on lab.entity_id = cm.course_id
     where jsonb_typeof(cm.candidates) = 'array' and jsonb_array_length(cm.candidates) > 0
       and not exists (select 1 from pipeline.ai_eval_examples x where x.source_ref = 'coverage_ai_match:' || cm.id)
     order by cm.id limit v_n)
  insert into pipeline.ai_eval_examples(family, source_kind, tier, basis, source_ref, label_key, entity, entity_id, field, label, expected, reason, input_ref, decided_by, decided_at)
  select 'provider_course_matching', 'match_case', 'person', basis, source_ref, md5(concat_ws('|', 'provider_course_matching', source_ref)),
         'course', entity_id, 'course_page_match', 'accept', expected, 'the page a person chose (example ' || label_id || ')', source_ref, decided_by, decided_at from src
  on conflict do nothing;
  get diagnostics c = row_count; v := v || jsonb_build_object('match_case', c);

  -- a quote-checked example a person has since contradicted is no longer ground truth
  update pipeline.ai_eval_examples q set active = false, inactive_reason = 'a person decided otherwise (example ' || p.id || ')'
    from pipeline.ai_eval_examples p
   where q.active and q.tier = 'verified_quote' and p.tier = 'person' and p.family = q.family and p.entity_id = q.entity_id and p.decided_at > q.decided_at
     and (p.label in ('reject', 'no_value') or (p.label in ('accept', 'correct') and security.ai_eval_norm_v1(p.expected) is distinct from security.ai_eval_norm_v1(q.expected)))
     and (p.field = q.field or exists (select 1 from pipeline.ai_eval_source_map m where m.source_kind = 'l4_decision' and m.field = p.field and m.family = q.family
                                        and q.field = any (case p.field when 'course_english' then array['english'] when 'course_intake' then array['intakes']
                                                                       when 'course_entry_first_read' then array['entry_requirements'] else array[]::text[] end)));
  get diagnostics c = row_count; v := v || jsonb_build_object('contradicted', c);
  return v;
end $function$;
revoke all on function security.ai_eval_dataset_refresh_v1() from public, anon, authenticated;

create or replace function security.ai_eval_counts_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  select coalesce(jsonb_object_agg(f.code, jsonb_build_object(
           'title', f.title,
           'active', (select count(*) from pipeline.ai_eval_examples x where x.family = f.code and x.active),
           'person', (select count(*) from pipeline.ai_eval_examples x where x.family = f.code and x.active and x.tier = 'person'),
           'verified_quote', (select count(*) from pipeline.ai_eval_examples x where x.family = f.code and x.active and x.tier = 'verified_quote'),
           'by_label', (select coalesce(jsonb_object_agg(label, n), '{}') from (select x.label, count(*) n from pipeline.ai_eval_examples x where x.family = f.code and x.active group by 1) z),
           'by_source', (select coalesce(jsonb_object_agg(k, n), '{}') from (select x.source_kind || ':' || x.basis k, count(*) n from pipeline.ai_eval_examples x where x.family = f.code and x.active group by 1) z),
           'inactive', (select count(*) from pipeline.ai_eval_examples x where x.family = f.code and not x.active)) order by f.sort), '{}')
    from pipeline.ai_eval_families f
$function$;
revoke all on function security.ai_eval_counts_v1() from public, anon, authenticated;

create or replace function security.ai_eval_set_freeze_v1(p_family text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_max int := security.pipeline_num_v1('ai_eval.set_max_examples', 2000)::int; v_set bigint; v_ver int;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  if not exists (select 1 from pipeline.ai_eval_families where code = p_family) then raise exception 'ai_eval: unknown family %', p_family using errcode = '22023'; end if;
  select coalesce(max(version), 0) + 1 into v_ver from pipeline.ai_eval_sets where family = p_family;
  insert into pipeline.ai_eval_sets(family, version, example_count, person_count, quote_count, note) values (p_family, v_ver, 0, 0, 0, 'active examples, people''s decisions first')
  returning id into v_set;
  insert into pipeline.ai_eval_set_members(set_id, example_id)
  select v_set, x.id from pipeline.ai_eval_examples x where x.family = p_family and x.active
   order by (x.tier = 'person') desc, x.decided_at desc nulls last, x.id limit v_max;
  update pipeline.ai_eval_sets s set example_count = z.n, person_count = z.p, quote_count = z.q
    from (select count(*) n, count(*) filter (where x.tier = 'person') p, count(*) filter (where x.tier = 'verified_quote') q
            from pipeline.ai_eval_set_members m join pipeline.ai_eval_examples x on x.id = m.example_id where m.set_id = v_set) z where s.id = v_set;
  return (select jsonb_build_object('set_id', s.id, 'family', s.family, 'version', s.version, 'examples', s.example_count, 'person', s.person_count, 'verified_quote', s.quote_count)
            from pipeline.ai_eval_sets s where s.id = v_set);
end $function$;
revoke all on function security.ai_eval_set_freeze_v1(text) from public, anon, authenticated;

-- 5. instructions and proposals ------------------------------------------------------------------------------------------------------------
create or replace function security.ai_instruction_register_v1(p_spec jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- registers a version: a live baseline (status current, with its home and the md5 of its text) or a candidate (full text, schema or rules).
-- Re-registering the same code and version with the same content changes nothing.
declare v record; v_id bigint; v_md5 text := coalesce(md5(p_spec->>'body'), p_spec->>'body_md5', md5(coalesce(p_spec->'spec', '{}'::jsonb)::text));
begin
  select * into v from pipeline.ai_instruction_versions where code = p_spec->>'code' and version = p_spec->>'version';
  if found then
    if v.body_md5 <> v_md5 then raise exception 'ai_eval: % % is already registered with other content', v.code, v.version using errcode = '23505'; end if;
    return jsonb_build_object('id', v.id, 'action', 'already registered');
  end if;
  if coalesce(p_spec->>'status', 'candidate') not in ('current', 'candidate') then raise exception 'ai_eval: register a version as current or candidate' using errcode = '22023'; end if;
  if p_spec->>'status' = 'current' and security.ai_eval_ai_path_v1() then
    raise exception 'ai_eval: the AI cannot make a version current; that is the release path' using errcode = '42501';
  end if;
  insert into pipeline.ai_instruction_versions(family, code, kind, version, home, body, spec, body_md5, model_identifier, status, parent_id, note)
  values (p_spec->>'family', p_spec->>'code', p_spec->>'kind', p_spec->>'version', coalesce(p_spec->>'home', 'proposal'), p_spec->>'body', coalesce(p_spec->'spec', '{}'::jsonb), v_md5,
          p_spec->>'model', coalesce(p_spec->>'status', 'candidate'),
          (select x.id from pipeline.ai_instruction_versions x where x.code = p_spec->>'code' and x.status = 'current'), p_spec->>'note')
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'action', 'registered');
end $function$;
revoke all on function security.ai_instruction_register_v1(jsonb) from public, anon, authenticated;

create or replace function security.ai_proposal_fingerprint_v1(p_family text, p_class text, p_target text, p_change jsonb) returns text
language sql immutable set search_path to '' as $function$
  select md5(concat_ws('|', p_family, p_class, lower(btrim(coalesce(p_target, ''))),
             regexp_replace(lower(coalesce(p_change #>> '{}', p_change::text, '')), '\s+', ' ', 'g')))
$function$;

create or replace function security.ai_proposal_criteria_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- the acceptance criteria in force when a proposal is submitted; snapshotted into the proposal so later setting changes do not move them
  select jsonb_build_object(
    'min_benefit_pts', security.pipeline_num_v1('ai_eval.min_benefit_pts', 1),
    'max_accuracy_drop_pts', security.pipeline_num_v1('ai_eval.max_accuracy_drop_pts', 0),
    'max_fp_rate_rise_pts', security.pipeline_num_v1('ai_eval.max_fp_rate_rise_pts', 0),
    'max_coverage_drop_pts', security.pipeline_num_v1('ai_eval.max_coverage_drop_pts', 0),
    'min_source_integrity_pct', security.pipeline_num_v1('ai_eval.min_source_integrity_pct', 100),
    'max_cost_rise_pct', security.pipeline_num_v1('ai_eval.max_cost_rise_pct', 10),
    'max_error_rate_rise_pts', security.pipeline_num_v1('ai_eval.max_error_rate_rise_pts', 1),
    'min_person_examples', security.pipeline_num_v1('ai_eval.min_person_examples', 30),
    'consumer_api', 'unchanged (G3): no consumer function, table, column or edge function is touched')
$function$;
revoke all on function security.ai_proposal_criteria_v1() from public, anon, authenticated;

create or replace function security.ai_proposal_submit_v1(p_spec jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- records a proposal with every field the mandate asks for; its authority comes from pipeline.ai_approval_boundaries (any authority in the
-- spec is ignored). Extra criteria may add measures but never loosen the ones in force (the settings win). An operational adjustment must target an allow-listed setting, inside its minimum and maximum and the step limit.
declare v_class text := p_spec->>'change_class'; v_auth text; v_fp text; v_target text; v_change jsonb; s record; v_id bigint; v_new numeric; k text; v_ts jsonb;
begin
  if coalesce(p_spec->>'proposed_by', '') = 'platform_ai' then perform set_config('cf247.ai_eval_path', 'on', true); end if;
  foreach k in array array['code', 'family', 'change_class', 'title', 'problem_observed', 'current_method', 'proposed_change', 'expected_benefit', 'risks', 'proposed_by'] loop
    if length(btrim(coalesce(p_spec->>k, ''))) < 2 then raise exception 'ai_eval: a proposal needs %', k using errcode = '22023'; end if;
  end loop;
  if jsonb_typeof(p_spec->'production_evidence') is distinct from 'object' or not (p_spec->'production_evidence' ? 'measured_at') or not (p_spec->'production_evidence' ? 'counts') then
    raise exception 'ai_eval: a proposal needs production evidence with measured_at and counts' using errcode = '22023';
  end if;
  select b.authority into v_auth from pipeline.ai_approval_boundaries b where b.change_class = v_class;
  if v_auth is null then raise exception 'ai_eval: unknown change class %', v_class using errcode = '22023'; end if;
  if v_class = 'operational_adjustment' then
    select t.toolset_key, t.key, st.value, st.min_value, st.max_value into s
      from pipeline.ai_auto_tunable_settings t join pipeline.platform_toolset_settings st on st.toolset_key = t.toolset_key and st.key = t.key
     where t.toolset_key = coalesce(p_spec#>>'{target_setting,toolset}', 'pipeline') and t.key = p_spec#>>'{target_setting,key}';
    if not found then raise exception 'ai_eval: % is not a setting the AI may tune', coalesce(p_spec#>>'{target_setting,key}', 'no setting') using errcode = '42501'; end if;
    if p_spec->'target_setting' ?| array['min_value', 'max_value'] then raise exception 'ai_eval: a setting''s minimum and maximum are not changed by the AI' using errcode = '42501'; end if;
    v_new := (p_spec#>>'{target_setting,value}')::numeric;
    if v_new is null or v_new < s.min_value or v_new > s.max_value then
      raise exception 'ai_eval: % = % is outside its range % to %', s.key, v_new, s.min_value, s.max_value using errcode = '22023';
    end if;
    if abs(v_new - (s.value #>> '{}')::numeric) > abs((s.value #>> '{}')::numeric) * security.pipeline_num_v1('ai_eval.auto_step_max_pct', 25) / 100 then
      raise exception 'ai_eval: % may move by at most % percent at a time', s.key, security.pipeline_num_v1('ai_eval.auto_step_max_pct', 25) using errcode = '22023';
    end if;
    v_target := s.toolset_key || '.' || s.key; v_change := to_jsonb(v_new); v_ts := jsonb_build_object('toolset', s.toolset_key, 'key', s.key, 'value', v_new);
  else
    v_target := coalesce((select x.code from pipeline.ai_instruction_versions x where x.id = (p_spec->>'candidate_version_id')::bigint), p_spec->>'target');
    v_change := coalesce((select to_jsonb(coalesce(x.body, x.spec::text)) from pipeline.ai_instruction_versions x where x.id = (p_spec->>'candidate_version_id')::bigint), p_spec->'change');
    if v_change is null then raise exception 'ai_eval: a % proposal names its candidate version or change', v_class using errcode = '22023'; end if;
  end if;
  v_fp := security.ai_proposal_fingerprint_v1(p_spec->>'family', v_class, v_target, v_change);
  if exists (select 1 from pipeline.ai_improvement_proposals p where p.fingerprint = v_fp and p.status in ('proposed', 'evaluating', 'canary', 'accepted')) then
    return jsonb_build_object('ok', false, 'refused', 'already proposed', 'proposal', (select p.code from pipeline.ai_improvement_proposals p where p.fingerprint = v_fp order by p.id desc limit 1));
  end if;
  if exists (select 1 from pipeline.ai_rejected_proposals r where r.fingerprint = v_fp) then
    return jsonb_build_object('ok', false, 'refused', 'rejected before', 'ledger', (select to_jsonb(r) - 'results' from pipeline.ai_rejected_proposals r where r.fingerprint = v_fp));
  end if;
  insert into pipeline.ai_improvement_proposals(code, family, change_class, authority, title, problem_observed, current_method, proposed_change, production_evidence,
         expected_benefit, risks, baseline_version_id, candidate_version_id, target_setting, eval_set_id, acceptance_criteria, fingerprint, proposed_by)
  values (p_spec->>'code', p_spec->>'family', v_class, v_auth, p_spec->>'title', p_spec->>'problem_observed', p_spec->>'current_method', p_spec->>'proposed_change',
          p_spec->'production_evidence', p_spec->>'expected_benefit', p_spec->>'risks', (p_spec->>'baseline_version_id')::bigint, (p_spec->>'candidate_version_id')::bigint,
          v_ts,
          (p_spec->>'eval_set_id')::bigint, coalesce(p_spec->'acceptance_criteria_extra', '{}'::jsonb) || security.ai_proposal_criteria_v1(), v_fp, p_spec->>'proposed_by')
  on conflict (code) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', false, 'refused', 'code already used', 'proposal', p_spec->>'code'); end if;
  insert into pipeline.ai_proposal_events(proposal_id, from_status, to_status, by_path, reason)
  values (v_id, null, 'proposed', case when security.ai_eval_ai_path_v1() then 'ai' when coalesce(current_setting('cf247.release', true), '') <> '' then 'release' else 'engineering' end, 'submitted');
  return jsonb_build_object('ok', true, 'id', v_id, 'code', p_spec->>'code', 'authority', v_auth, 'fingerprint', v_fp);
end $function$;
revoke all on function security.ai_proposal_submit_v1(jsonb) from public, anon, authenticated;

-- 6. offline evaluation ----------------------------------------------------------------------------------------------------------------------
create or replace function security.ai_eval_run_open_v1(p_proposal bigint, p_arm text) returns bigint
language plpgsql security definer set search_path to '' as $function$
-- opens (once) the baseline or candidate run of a proposal on its frozen set; the worker answers it later. Nothing is called here.
declare p record; v_ver bigint; v_id bigint;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  select * into p from pipeline.ai_improvement_proposals where id = p_proposal;
  if p.eval_set_id is null then raise exception 'ai_eval: proposal % has no evaluation set', p.code using errcode = '22023'; end if;
  v_ver := case p_arm when 'baseline' then p.baseline_version_id when 'candidate' then p.candidate_version_id end;
  if v_ver is null then raise exception 'ai_eval: proposal % has no % version', p.code, p_arm using errcode = '22023'; end if;
  insert into pipeline.ai_eval_runs(proposal_id, arm, version_id, set_id, model_identifier)
  select p.id, p_arm, v_ver, p.eval_set_id, v.model_identifier from pipeline.ai_instruction_versions v where v.id = v_ver
  on conflict (proposal_id, arm, set_id) do nothing returning id into v_id;
  if v_id is null then select id into v_id from pipeline.ai_eval_runs where proposal_id = p.id and arm = p_arm and set_id = p.eval_set_id; end if;
  if p.status = 'proposed' then update pipeline.ai_improvement_proposals set status = 'evaluating', status_reason = 'offline runs opened' where id = p.id; end if;
  return v_id;
end $function$;
revoke all on function security.ai_eval_run_open_v1(bigint, text) from public, anon, authenticated;

create or replace function public.svc_ai_eval_run_next_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- the worker leases one queued offline run: the version to use (text or home, pinned model) and the examples (input references only).
-- The worker answers through its existing OpenRouter guards and budgets.
declare r record;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  if security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 1 then return jsonb_build_object('run', null, 'why', 'ai_eval.offline_runs_on is 0'); end if;
  select * into r from pipeline.ai_eval_runs
   where state = 'queued' or (state = 'answering' and leased_until < now())
   order by requested_at limit 1 for update skip locked;
  if not found then return jsonb_build_object('run', null); end if;
  update pipeline.ai_eval_runs set state = 'answering', leased_until = now() + interval '30 minutes' where id = r.id;  -- fixed: claim lease
  return jsonb_build_object('run', r.id, 'arm', r.arm, 'set_id', r.set_id,
    'version', (select jsonb_build_object('id', v.id, 'code', v.code, 'version', v.version, 'kind', v.kind, 'home', v.home, 'body', v.body, 'spec', v.spec, 'model', v.model_identifier)
                  from pipeline.ai_instruction_versions v where v.id = r.version_id),
    'examples', (select coalesce(jsonb_agg(jsonb_build_object('example_id', x.id, 'entity', x.entity, 'entity_id', x.entity_id, 'field', x.field,
                                                             'input_ref', x.input_ref, 'evidence_id', x.evidence_id, 'page_ref', x.page_ref) order by x.id), '[]')
                   from pipeline.ai_eval_set_members m join pipeline.ai_eval_examples x on x.id = m.example_id where m.set_id = r.set_id));
end $function$;
revoke all on function public.svc_ai_eval_run_next_v1() from public, anon, authenticated;
grant execute on function public.svc_ai_eval_run_next_v1() to service_role;

create or replace function public.svc_ai_eval_answer_record_v1(p_run bigint, p_answers jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- records the worker's answers for a run: [{example_id, verdict, value, quote, quote_on_page, tokens_in, tokens_out, cost_usd, error}].
-- Answers are kept as given; the run is recorded when every member has an answer (or with done: true).
declare c int; v_left int;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  if not exists (select 1 from pipeline.ai_eval_runs where id = p_run and state in ('queued', 'answering')) then
    raise exception 'ai_eval: run % is not open for answers', p_run using errcode = '22023';
  end if;
  insert into pipeline.ai_eval_answers(run_id, example_id, verdict, value, quote, quote_on_page, tokens_in, tokens_out, cost_usd, error)
  select p_run, (a->>'example_id')::bigint, a->>'verdict', a->'value', a->>'quote', (a->>'quote_on_page')::boolean, (a->>'tokens_in')::int, (a->>'tokens_out')::int,
         (a->>'cost_usd')::numeric, a->>'error'
    from jsonb_array_elements(coalesce(p_answers->'answers', p_answers)) a
   where exists (select 1 from pipeline.ai_eval_set_members m join pipeline.ai_eval_runs r on r.set_id = m.set_id where r.id = p_run and m.example_id = (a->>'example_id')::bigint)
  on conflict (run_id, example_id) do nothing;
  get diagnostics c = row_count;
  select count(*) into v_left from pipeline.ai_eval_set_members m join pipeline.ai_eval_runs r on r.set_id = m.set_id
   where r.id = p_run and not exists (select 1 from pipeline.ai_eval_answers a where a.run_id = p_run and a.example_id = m.example_id);
  if v_left = 0 or coalesce((p_answers->>'done')::boolean, false) then
    update pipeline.ai_eval_runs set state = 'recorded', recorded_at = now(), leased_until = null, worker = left(p_answers->>'worker', 60) where id = p_run;
  end if;
  return jsonb_build_object('run', p_run, 'recorded', c, 'unanswered', v_left);
end $function$;
revoke all on function public.svc_ai_eval_answer_record_v1(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.svc_ai_eval_answer_record_v1(bigint, jsonb) to service_role;

create or replace function security.ai_eval_metrics_v1(p_pairs jsonb) returns jsonb
language sql immutable set search_path to '' as $function$
-- the scoring rules, on pairs [{label, expected, rejected, needs_quote, tier, answered, verdict, value, quote_on_page, error, cost_usd, tokens_in, tokens_out}]:
--   accept / correct: right when a value is given and equals the expected value; a different value is a false positive (a wrong value
--     admitted); no value is a false negative.
--   reject / no_value: right when no value is given, or (reject with a known rejected value) a different value; giving the rejected value, or
--     any value where none should be, is a false positive.
--   coverage: values given where one is expected. Source integrity: values carrying a quote found on the page, in families that need a quote.
--   reliability: answers that failed or are missing. Points are percentages of the pairs.
  with p as (
    select x->>'label' label, security.ai_eval_norm_v1(x->'expected') exp, security.ai_eval_norm_v1(x->'rejected') rej, coalesce((x->>'needs_quote')::boolean, true) nq,
           x->>'tier' tier, coalesce((x->>'answered')::boolean, false) and x->>'error' is null ok,
           x->>'verdict' = 'accept' and x->'value' is not null and x->'value' <> 'null'::jsonb has_value, security.ai_eval_norm_v1(x->'value') val,
           coalesce((x->>'quote_on_page')::boolean, false) qop, coalesce((x->>'cost_usd')::numeric, 0) cost, coalesce((x->>'tokens_in')::int, 0) tin, coalesce((x->>'tokens_out')::int, 0) tout
      from jsonb_array_elements(coalesce(p_pairs, '[]'::jsonb)) x),
  s as (
    select *, ok and case when label in ('accept', 'correct') then has_value and val = exp
                          else not has_value or (label = 'reject' and rej is not null and val is distinct from rej) end correct,
           ok and has_value and ((label in ('accept', 'correct') and val is distinct from exp) or label = 'no_value' or (label = 'reject' and (rej is null or val = rej))) fp,
           ok and label in ('accept', 'correct') and not has_value fn
      from p),
  m as (
    select count(*) n, count(*) filter (where correct) right_n, count(*) filter (where fp) fp_n, count(*) filter (where fn) fn_n,
           count(*) filter (where not ok) failed_n, count(*) filter (where label in ('accept', 'correct')) pos_n,
           count(*) filter (where label in ('accept', 'correct') and ok and has_value) covered_n,
           count(*) filter (where ok and has_value and nq) quoted_need_n, count(*) filter (where ok and has_value and nq and qop) quoted_ok_n,
           sum(cost) cost, sum(tin) tin, sum(tout) tout,
           count(*) filter (where tier = 'person') pn, count(*) filter (where tier = 'person' and correct) pright, count(*) filter (where tier = 'person' and fp) pfp
      from s)
  select jsonb_build_object(
    'examples', n, 'right', right_n, 'false_positives', fp_n, 'false_negatives', fn_n, 'failed', failed_n,
    'accuracy_pct', case when n > 0 then round(100.0 * right_n / n, 2) end,
    'fp_rate_pts', case when n > 0 then round(100.0 * fp_n / n, 2) end,
    'fn_rate_pts', case when n > 0 then round(100.0 * fn_n / n, 2) end,
    'coverage_pct', case when pos_n > 0 then round(100.0 * covered_n / pos_n, 2) end,
    'source_integrity_pct', case when quoted_need_n > 0 then round(100.0 * quoted_ok_n / quoted_need_n, 2) else 100 end,
    'error_rate_pts', case when n > 0 then round(100.0 * failed_n / n, 2) end,
    'cost_usd', round(coalesce(cost, 0), 6), 'tokens_in', coalesce(tin, 0), 'tokens_out', coalesce(tout, 0),
    'cost_per_right_usd', case when right_n > 0 then round(coalesce(cost, 0) / right_n, 6) end,
    'person', jsonb_build_object('examples', pn, 'accuracy_pct', case when pn > 0 then round(100.0 * pright / pn, 2) end, 'fp_rate_pts', case when pn > 0 then round(100.0 * pfp / pn, 2) end))
  from m
$function$;

create or replace function security.ai_eval_score_v1(p_run bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- scores a recorded run on every member of its set (a member with no answer counts as failed)
declare v jsonb;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  select security.ai_eval_metrics_v1(coalesce(jsonb_agg(jsonb_build_object(
           'label', x.label, 'expected', x.expected, 'rejected', x.rejected, 'needs_quote', f.needs_quote, 'tier', x.tier, 'answered', a.example_id is not null,
           'verdict', a.verdict, 'value', a.value, 'quote_on_page', a.quote_on_page, 'error', a.error, 'cost_usd', a.cost_usd, 'tokens_in', a.tokens_in, 'tokens_out', a.tokens_out)), '[]'))
    into v
    from pipeline.ai_eval_runs r
    join pipeline.ai_eval_set_members m on m.set_id = r.set_id
    join pipeline.ai_eval_examples x on x.id = m.example_id
    join pipeline.ai_eval_families f on f.code = x.family
    left join pipeline.ai_eval_answers a on a.run_id = r.id and a.example_id = x.id
   where r.id = p_run;
  update pipeline.ai_eval_runs set metrics = v, state = 'scored', scored_at = now() where id = p_run and state in ('recorded', 'scored');
  return v;
end $function$;
revoke all on function security.ai_eval_score_v1(bigint) from public, anon, authenticated;

create or replace function security.ai_eval_verdict_v1(p_base jsonb, p_cand jsonb, p_crit jsonb) returns jsonb
language sql immutable set search_path to '' as $function$
-- the mandate §6 criteria: accuracy (overall and on people's decisions), source integrity, coverage, data admission safety (false
-- positives), cost, execution reliability and consumer compatibility; and a measurable benefit
  with d as (
    select coalesce((p_cand->>'accuracy_pct')::numeric, 0) - coalesce((p_base->>'accuracy_pct')::numeric, 0) acc,
           coalesce((p_cand#>>'{person,accuracy_pct}')::numeric, 0) - coalesce((p_base#>>'{person,accuracy_pct}')::numeric, 0) pacc,
           coalesce((p_cand->>'coverage_pct')::numeric, 0) - coalesce((p_base->>'coverage_pct')::numeric, 0) cov,
           coalesce((p_cand->>'fp_rate_pts')::numeric, 0) - coalesce((p_base->>'fp_rate_pts')::numeric, 0) fp,
           coalesce((p_cand->>'error_rate_pts')::numeric, 0) - coalesce((p_base->>'error_rate_pts')::numeric, 0) err,
           -- cost per example, so arms of different sizes (a canary) compare fairly; a measure without a count compares its totals
           case when coalesce((p_base->>'cost_usd')::numeric, 0) > 0
                then 100 * (((p_cand->>'cost_usd')::numeric / coalesce(nullif((p_cand->>'examples')::numeric, 0), 1))
                            / ((p_base->>'cost_usd')::numeric / coalesce(nullif((p_base->>'examples')::numeric, 0), 1)) - 1)
                when coalesce((p_cand->>'cost_usd')::numeric, 0) > 0 then 100 else 0 end cost,
           coalesce((p_cand->>'source_integrity_pct')::numeric, 0) si),
  c as (
    select jsonb_build_object(
      'accuracy', jsonb_build_object('delta_pts', round(acc, 2), 'person_delta_pts', round(pacc, 2), 'pass', acc >= -(p_crit->>'max_accuracy_drop_pts')::numeric and pacc >= -(p_crit->>'max_accuracy_drop_pts')::numeric),
      'source_integrity', jsonb_build_object('candidate_pct', si, 'pass', si >= (p_crit->>'min_source_integrity_pct')::numeric),
      'coverage', jsonb_build_object('delta_pts', round(cov, 2), 'pass', cov >= -(p_crit->>'max_coverage_drop_pts')::numeric),
      'admission_safety', jsonb_build_object('fp_rate_delta_pts', round(fp, 2), 'pass', fp <= (p_crit->>'max_fp_rate_rise_pts')::numeric),
      'cost', jsonb_build_object('per_example_delta_pct', round(cost, 2), 'pass', cost <= (p_crit->>'max_cost_rise_pct')::numeric),
      'execution_reliability', jsonb_build_object('error_rate_delta_pts', round(err, 2), 'pass', err <= (p_crit->>'max_error_rate_rise_pts')::numeric),
      'consumer_compatibility', jsonb_build_object('pass', true, 'basis', p_crit->>'consumer_api')) crit,
      greatest(acc, cov) >= (p_crit->>'min_benefit_pts')::numeric benefit
    from d)
  select jsonb_build_object('criteria', crit, 'benefit', benefit,
    'regressions', (select coalesce(jsonb_agg(k order by k), '[]') from jsonb_each(crit) e(k, v) where not (v->>'pass')::boolean),
    'passed', benefit and not exists (select 1 from jsonb_each(crit) e(k, v) where not (v->>'pass')::boolean))
  from c
$function$;

create or replace function security.ai_eval_compare_v1(p_proposal bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- judges an evaluating proposal once its baseline and candidate runs are scored on the same set: rejected (with the ledger entry) when it
-- regresses or brings no benefit; kept evaluating when the set holds too few decisions by a person; otherwise it has passed offline and may go
-- to canary (security.ai_proposal_advance_v1)
declare p record; b jsonb; c jsonb; v jsonb; v_person int;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  select * into p from pipeline.ai_improvement_proposals where id = p_proposal for update;
  select metrics into b from pipeline.ai_eval_runs where proposal_id = p.id and arm = 'baseline' and set_id = p.eval_set_id and state = 'scored';
  select metrics into c from pipeline.ai_eval_runs where proposal_id = p.id and arm = 'candidate' and set_id = p.eval_set_id and state = 'scored';
  if b is null or c is null then return jsonb_build_object('proposal', p.code, 'verdict', 'waiting for scored runs'); end if;
  select person_count into v_person from pipeline.ai_eval_sets where id = p.eval_set_id;
  v := security.ai_eval_verdict_v1(b, c, p.acceptance_criteria) || jsonb_build_object('baseline', b, 'candidate', c, 'set_id', p.eval_set_id, 'person_examples', v_person, 'at', now());
  if v_person < (p.acceptance_criteria->>'min_person_examples')::numeric then
    v := v || jsonb_build_object('verdict', 'not enough decisions by a person to judge', 'passed', false);
    update pipeline.ai_improvement_proposals set actual_results = actual_results || jsonb_build_object('offline', v) where id = p.id;
  elsif (v->>'passed')::boolean then
    v := v || jsonb_build_object('verdict', 'passed offline');
    update pipeline.ai_improvement_proposals set actual_results = actual_results || jsonb_build_object('offline', v) where id = p.id;
  elsif p.status = 'evaluating' then
    v := v || jsonb_build_object('verdict', 'rejected');
    update pipeline.ai_improvement_proposals set actual_results = actual_results || jsonb_build_object('offline', v), status = 'rejected',
           status_reason = case when jsonb_array_length(v->'regressions') > 0 then 'regression in ' || (v->>'regressions') else 'no measurable benefit' end where id = p.id;
  end if;
  return jsonb_build_object('proposal', p.code) || v;
end $function$;
revoke all on function security.ai_eval_compare_v1(bigint) from public, anon, authenticated;

-- 7. canary, acceptance and rollback ---------------------------------------------------------------------------------------------------------
create or replace function security.ai_canary_pick_v1(p_code text, p_item_key text, p_family text default null, p_entity_id uuid default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- the version an item uses: the current one, unless ai_eval.canary_on is 1 and a candidate of this code is in canary, the item falls in the
-- share (stable hash) and today's canary count is under the cap. The assignment is recorded so the item always gets the same version.
declare v_cur record; p record; a record; v_bucket int;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  select id, version, body_md5, model_identifier into v_cur from pipeline.ai_instruction_versions where code = p_code and status = 'current';
  if security.pipeline_num_v1('ai_eval.canary_on', 0) <> 1 then
    return jsonb_build_object('version_id', v_cur.id, 'version', v_cur.version, 'model', v_cur.model_identifier, 'canary', false, 'why', 'canary off');
  end if;
  select pr.* into p from pipeline.ai_improvement_proposals pr join pipeline.ai_instruction_versions cv on cv.id = pr.candidate_version_id
   where pr.status = 'canary' and cv.code = p_code order by pr.id limit 1;
  if not found then return jsonb_build_object('version_id', v_cur.id, 'version', v_cur.version, 'model', v_cur.model_identifier, 'canary', false, 'why', 'no candidate in canary'); end if;
  select * into a from pipeline.ai_canary_assignments where proposal_id = p.id and item_key = p_item_key;
  if not found then
    v_bucket := abs(hashtext(p.code || ':' || p_item_key)) % 100;
    insert into pipeline.ai_canary_assignments(proposal_id, item_key, family, entity_id, arm, version_id)
    select p.id, p_item_key, coalesce(p_family, p.family), p_entity_id,
           case when v_bucket < security.pipeline_num_v1('ai_eval.canary_share_pct', 5)
                 and (select count(*) from pipeline.ai_canary_assignments c where c.proposal_id = p.id and c.arm = 'candidate'
                        and c.assigned_at >= date_trunc('day', now() at time zone 'Australia/Sydney') at time zone 'Australia/Sydney')
                     < security.pipeline_num_v1('ai_eval.canary_max_items_per_day', 50)
                then 'candidate' else 'current' end,
           case when v_bucket < security.pipeline_num_v1('ai_eval.canary_share_pct', 5)
                 and (select count(*) from pipeline.ai_canary_assignments c where c.proposal_id = p.id and c.arm = 'candidate'
                        and c.assigned_at >= date_trunc('day', now() at time zone 'Australia/Sydney') at time zone 'Australia/Sydney')
                     < security.pipeline_num_v1('ai_eval.canary_max_items_per_day', 50)
                then p.candidate_version_id else v_cur.id end
    returning * into a;
  end if;
  return (select jsonb_build_object('version_id', v.id, 'version', v.version, 'model', v.model_identifier, 'body', case when a.arm = 'candidate' then v.body end,
                                    'canary', a.arm = 'candidate', 'proposal', p.code) from pipeline.ai_instruction_versions v where v.id = a.version_id);
end $function$;
revoke all on function security.ai_canary_pick_v1(text, text, text, uuid) from public, anon, authenticated;

create or replace function public.svc_ai_instruction_pick_v1(p_code text, p_item_key text, p_family text default null, p_entity_id uuid default null) returns jsonb
language sql security definer set search_path to '' as $function$
  select security.ai_canary_pick_v1(p_code, p_item_key, p_family, p_entity_id)
$function$;
revoke all on function public.svc_ai_instruction_pick_v1(text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.svc_ai_instruction_pick_v1(text, text, text, uuid) to service_role;

create or replace function public.svc_ai_canary_answer_record_v1(p_proposal_code text, p_item_key text, p_answer jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  update pipeline.ai_canary_assignments c set verdict = p_answer->>'verdict', value = p_answer->'value', quote_on_page = (p_answer->>'quote_on_page')::boolean,
         cost_usd = (p_answer->>'cost_usd')::numeric, tokens_in = (p_answer->>'tokens_in')::int, tokens_out = (p_answer->>'tokens_out')::int, error = p_answer->>'error', answered_at = now()
    from pipeline.ai_improvement_proposals p where p.id = c.proposal_id and p.code = p_proposal_code and c.item_key = p_item_key and c.answered_at is null;
  return jsonb_build_object('recorded', found);
end $function$;
revoke all on function public.svc_ai_canary_answer_record_v1(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_ai_canary_answer_record_v1(text, text, jsonb) to service_role;

create or replace function security.ai_canary_judge_v1(p_proposal bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- judges a canary on the items a person has decided since they were answered (a decision by a person on the same entity and family, made
-- after the answer; a quote-checked reading is never used here, as it may be the canary's own output). Compares the candidate arm with the
-- current arm. Fewer judged items than ai_eval.canary_min_judged: keeps running. A failure rolls back automatically.
declare p record; v_c jsonb; v_b jsonb; v jsonb; v_n int;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  select * into p from pipeline.ai_improvement_proposals where id = p_proposal for update;
  with j as (
    select c.arm, jsonb_build_object('label', x.label, 'expected', x.expected, 'rejected', x.rejected, 'needs_quote', f.needs_quote, 'tier', x.tier, 'answered', true,
                                     'verdict', c.verdict, 'value', c.value, 'quote_on_page', c.quote_on_page, 'error', c.error, 'cost_usd', c.cost_usd,
                                     'tokens_in', c.tokens_in, 'tokens_out', c.tokens_out) pair
      from pipeline.ai_canary_assignments c
      join lateral (select * from pipeline.ai_eval_examples x where x.entity_id = c.entity_id and x.family = c.family and x.tier = 'person' and x.active
                       and x.decided_at > c.answered_at order by x.decided_at limit 1) x on true
      join pipeline.ai_eval_families f on f.code = x.family
     where c.proposal_id = p.id and c.answered_at is not null)
  select security.ai_eval_metrics_v1((select coalesce(jsonb_agg(pair), '[]') from j where arm = 'candidate')),
         security.ai_eval_metrics_v1((select coalesce(jsonb_agg(pair), '[]') from j where arm = 'current')),
         (select count(*) from j where arm = 'candidate') into v_c, v_b, v_n;
  if v_n < security.pipeline_num_v1('ai_eval.canary_min_judged', 20) then
    return jsonb_build_object('proposal', p.code, 'verdict', 'canary running', 'judged', v_n);
  end if;
  v := security.ai_eval_verdict_v1(v_b, v_c, p.acceptance_criteria) || jsonb_build_object('candidate', v_c, 'current', v_b, 'judged', v_n, 'at', now());
  if (v->>'passed')::boolean then
    update pipeline.ai_improvement_proposals set actual_results = actual_results || jsonb_build_object('canary', v || jsonb_build_object('verdict', 'passed canary')) where id = p.id;
    return jsonb_build_object('proposal', p.code, 'verdict', 'passed canary') || v;
  end if;
  perform security.ai_proposal_rollback_v1(p.id, 'canary failed: ' || case when jsonb_array_length(v->'regressions') > 0 then 'regression in ' || (v->>'regressions') else 'no measurable benefit' end, v);
  return jsonb_build_object('proposal', p.code, 'verdict', 'rolled back') || v;
end $function$;
revoke all on function security.ai_canary_judge_v1(bigint) from public, anon, authenticated;

create or replace function security.ai_proposal_advance_v1(p_proposal bigint, p_to text, p_reason text, p_measure jsonb default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- the platform's own moves (AI path): to canary after passing offline (or, for an operational adjustment, a trial of the new value inside its
-- guardrails); to accepted only for an operational adjustment whose measured results pass, with automatic acceptance on. Every other
-- acceptance is the release path (security.ai_proposal_record_release_v1).
declare p record; v jsonb; v_prev jsonb;
begin
  perform set_config('cf247.ai_eval_path', 'on', true);
  select * into p from pipeline.ai_improvement_proposals where id = p_proposal for update;
  if p_to = 'canary' and p.change_class = 'operational_adjustment' then
    if security.pipeline_num_v1('ai_eval.auto_accept_on', 0) <> 1 then return jsonb_build_object('ok', false, 'refused', 'automatic acceptance is off (ai_eval.auto_accept_on)'); end if;
    select s.value into v_prev from pipeline.platform_toolset_settings s join pipeline.ai_auto_tunable_settings t on t.toolset_key = s.toolset_key and t.key = s.key
     where s.toolset_key = p.target_setting->>'toolset' and s.key = p.target_setting->>'key'
       and (p.target_setting->>'value')::numeric between s.min_value and s.max_value;
    if v_prev is null then return jsonb_build_object('ok', false, 'refused', 'the setting is no longer tunable or the value is outside its range'); end if;
    update pipeline.platform_toolset_settings set value = to_jsonb((p.target_setting->>'value')::numeric), updated_at = now(),
           reason = 'AI operational adjustment ' || p.code || ' (trial): ' || left(p_reason, 200)
     where toolset_key = p.target_setting->>'toolset' and key = p.target_setting->>'key';
    insert into pipeline.admin_control_events(area, action, target, detail) values ('ai_eval', 'trial', p.target_setting->>'key',
      jsonb_build_object('proposal', p.code, 'before', v_prev, 'value', p.target_setting->'value'));
    update pipeline.ai_improvement_proposals set status = 'canary', status_reason = p_reason, applied = jsonb_build_object('before', v_prev, 'value', p.target_setting->'value', 'at', now()) where id = p.id;
    return jsonb_build_object('ok', true, 'proposal', p.code, 'status', 'canary', 'before', v_prev);
  elsif p_to = 'canary' then
    if not coalesce((p.actual_results#>>'{offline,passed}')::boolean, false) then return jsonb_build_object('ok', false, 'refused', 'not passed offline'); end if;
    if security.pipeline_num_v1('ai_eval.canary_on', 0) <> 1 then return jsonb_build_object('ok', false, 'refused', 'canary routing is off (ai_eval.canary_on)'); end if;
    update pipeline.ai_improvement_proposals set status = 'canary', status_reason = p_reason where id = p.id;
    return jsonb_build_object('ok', true, 'proposal', p.code, 'status', 'canary');
  elsif p_to = 'accepted' and p.change_class = 'operational_adjustment' then
    if p.status <> 'canary' then return jsonb_build_object('ok', false, 'refused', 'not in trial'); end if;
    if p_measure is null then return jsonb_build_object('ok', false, 'refused', 'measured before and after results are needed'); end if;
    v := security.ai_eval_verdict_v1(p_measure->'before', p_measure->'after', p.acceptance_criteria) || jsonb_build_object('measure', p_measure, 'at', now());
    if (v->>'passed')::boolean then
      update pipeline.ai_improvement_proposals set status = 'accepted', status_reason = p_reason, actual_results = actual_results || jsonb_build_object('trial', v) where id = p.id;
      return jsonb_build_object('ok', true, 'proposal', p.code, 'status', 'accepted') || v;
    end if;
    perform security.ai_proposal_rollback_v1(p.id, 'trial failed: ' || (v->>'regressions'), v);
    return jsonb_build_object('ok', false, 'proposal', p.code, 'status', 'rolled_back') || v;
  elsif p_to = 'accepted' then
    -- the guard trigger refuses this on the AI path for every class but operational adjustments
    update pipeline.ai_improvement_proposals set status = 'accepted', status_reason = p_reason where id = p.id;
  end if;
  return jsonb_build_object('ok', false, 'refused', 'unknown move ' || p_to);
end $function$;
revoke all on function security.ai_proposal_advance_v1(bigint, text, text, jsonb) from public, anon, authenticated;

create or replace function security.ai_proposal_rollback_v1(p_proposal bigint, p_reason text, p_results jsonb default '{}') returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- puts back what the proposal changed (the previous setting value, or the previous current version) and records it in the ledger
declare p record; v_prev bigint;
begin
  select * into p from pipeline.ai_improvement_proposals where id = p_proposal for update;
  if p.status not in ('canary', 'accepted') then return jsonb_build_object('ok', false, 'refused', 'nothing to roll back (' || p.status || ')'); end if;
  if p.change_class = 'operational_adjustment' and p.applied ? 'before' then
    update pipeline.platform_toolset_settings set value = p.applied->'before', updated_at = now(), reason = 'AI operational adjustment ' || p.code || ' put back: ' || left(p_reason, 200)
     where toolset_key = p.target_setting->>'toolset' and key = p.target_setting->>'key' and value = p.applied->'value';
    insert into pipeline.admin_control_events(area, action, target, detail) values ('ai_eval', 'rollback', p.target_setting->>'key', jsonb_build_object('proposal', p.code, 'restored', p.applied->'before'));
  end if;
  if p.candidate_version_id is not null and exists (select 1 from pipeline.ai_instruction_versions where id = p.candidate_version_id and status = 'current') then
    select id into v_prev from pipeline.ai_instruction_versions where id = p.baseline_version_id;
    update pipeline.ai_instruction_versions set status = 'rolled_back' where id = p.candidate_version_id;
    update pipeline.ai_instruction_versions set status = 'current' where id = v_prev;
  elsif p.candidate_version_id is not null then
    update pipeline.ai_instruction_versions set status = 'rolled_back' where id = p.candidate_version_id and status = 'candidate';
  end if;
  update pipeline.ai_improvement_proposals set status = 'rolled_back', status_reason = p_reason, actual_results = actual_results || jsonb_build_object('rollback', p_results) where id = p.id;
  return jsonb_build_object('ok', true, 'proposal', p.code, 'status', 'rolled_back');
end $function$;
revoke all on function security.ai_proposal_rollback_v1(bigint, text, jsonb) from public, anon, authenticated;

create or replace function security.ai_proposal_record_release_v1(p_proposal bigint, p_release_ref text, p_by text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- the release path: a release (migration) or the Platform Admin records that a prompt, schema or rule change shipped. Refused on the AI path.
-- Needs a passed canary (or, when no canary ran, a passed offline evaluation and the release reference). The candidate becomes current and
-- the baseline previous (kept for rollback).
declare p record;
begin
  if security.ai_eval_ai_path_v1() then raise exception 'ai_eval: the AI cannot accept its own % change', (select change_class from pipeline.ai_improvement_proposals where id = p_proposal) using errcode = '42501'; end if;
  select * into p from pipeline.ai_improvement_proposals where id = p_proposal for update;
  if not (coalesce((p.actual_results#>>'{canary,passed}')::boolean, false) or coalesce((p.actual_results#>>'{offline,passed}')::boolean, false)) then
    raise exception 'ai_eval: % has no passed evaluation to accept', p.code using errcode = '22023';
  end if;
  if coalesce(p_release_ref, '') = '' or coalesce(p_by, '') = '' then raise exception 'ai_eval: name the release and who accepted it' using errcode = '22023'; end if;
  update pipeline.ai_instruction_versions set status = 'previous' where id = p.baseline_version_id and status = 'current';
  update pipeline.ai_instruction_versions set status = 'current' where id = p.candidate_version_id;
  update pipeline.ai_improvement_proposals set status = 'accepted', release_ref = p_release_ref, status_reason = 'released by ' || p_by where id = p.id;
  return jsonb_build_object('ok', true, 'proposal', p.code, 'status', 'accepted', 'release', p_release_ref);
end $function$;
revoke all on function security.ai_proposal_record_release_v1(bigint, text, text) from public, anon, authenticated;

-- 8. the job and the remedies -----------------------------------------------------------------------------------------------------------------
create or replace function security.ai_eval_tick_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- job ai-eval: collect new examples, score recorded runs, judge proposals whose two runs are scored, judge canaries. Records only.
declare v jsonb := '{}'; r record;
begin
  if security.pipeline_num_v1('ai_eval.refresh_on', 1) <> 1 then return jsonb_build_object('skipped', 'ai_eval.refresh_on is 0'); end if;
  perform set_config('cf247.ai_eval_path', 'on', true);
  v := jsonb_build_object('examples', security.ai_eval_dataset_refresh_v1());
  for r in select id from pipeline.ai_eval_runs where state = 'recorded' order by id loop perform security.ai_eval_score_v1(r.id); end loop;
  for r in select p.id from pipeline.ai_improvement_proposals p where p.status = 'evaluating' and p.actual_results->'offline' is null
              and (select count(*) from pipeline.ai_eval_runs x where x.proposal_id = p.id and x.set_id = p.eval_set_id and x.state = 'scored') = 2 loop
    v := v || jsonb_build_object('compared', coalesce(v->'compared', '[]') || jsonb_build_array(security.ai_eval_compare_v1(r.id)->>'verdict'));
  end loop;
  for r in select id from pipeline.ai_improvement_proposals where status = 'canary' and change_class <> 'operational_adjustment' loop
    v := v || jsonb_build_object('canaries', coalesce(v->'canaries', '[]') || jsonb_build_array(security.ai_canary_judge_v1(r.id)->>'verdict'));
  end loop;
  return v;
end $function$;
revoke all on function security.ai_eval_tick_v1() from public, anon, authenticated;

-- remedy for the controller (workstream A): a failing canary is stopped (rolled back). Only stops waste; the issue names the proposal.
create or replace function security.ai_remedy_canary_rollback_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_code text; v_id bigint; v jsonb;
begin
  select i.diagnosis#>>'{evidence,0,proposal}' into v_code from pipeline.integration_issues i where i.id = p_issue;
  select id into v_id from pipeline.ai_improvement_proposals where code = v_code and status = 'canary';
  if v_id is null then return jsonb_build_object('ok', true, 'changed', false, 'evidence', jsonb_build_object('proposal', v_code, 'note', 'no canary running')); end if;
  v := security.ai_canary_judge_v1(v_id);
  if v->>'verdict' = 'canary running' then v := security.ai_proposal_rollback_v1(v_id, 'stopped by the operations controller (issue ' || p_issue || ')'); end if;
  return jsonb_build_object('ok', true, 'changed', true, 'evidence', v);
end $function$;
revoke all on function security.ai_remedy_canary_rollback_v1(bigint) from public, anon, authenticated;

create or replace function security.ai_remedy_canary_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('passed', coalesce(p.status in ('rolled_back', 'rejected', 'accepted'), true),
                            'measure', jsonb_build_object('proposal', p.code, 'status', p.status), 'evidence', p.actual_results)
    from pipeline.integration_issues i left join pipeline.ai_improvement_proposals p on p.code = i.diagnosis#>>'{evidence,0,proposal}' where i.id = p_issue
$function$;
revoke all on function security.ai_remedy_canary_verify_v1(bigint) from public, anon, authenticated;

-- 9. seed data (release path) ------------------------------------------------------------------------------------------------------------------
do $seed$
begin
  perform set_config('cf247.release', '20261104070000', true);

  insert into pipeline.ai_eval_families(code, title, description, needs_quote, instruction_codes, sort) values
   ('course_fields', 'Course fields', 'Intakes, English, delivery, duration, campus, international availability and tuition read from a course page.', true, '{course-fields}', 10),
   ('course_description', 'Descriptions', 'Course and provider descriptions, each sentence supported by a quote on the page.', true, '{course-text,provider-description}', 20),
   ('deadline', 'Application deadlines', 'Application closing dates stated on a course page, tied to the page''s own intake words.', true, '{course-text}', 30),
   ('entry_requirements', 'Entry requirements', 'Academic entry requirements by country of prior education (provider tables and course pages).', true, '{entry-matrix,course-entry}', 40),
   ('scholarship_classification', 'Scholarship classification', 'Whether a page is a scholarship offered to international students, and its facts.', true, '{scholarship-page}', 50),
   ('page_identity', 'Page identity', 'Whether a page is the official page of one course (or that the course has no public page).', false, '{page-identity}', 60),
   ('provider_course_matching', 'Provider and course matching', 'Matching a register course to its page among candidates, and a provider to its own website.', false, '{course-page-match}', 70)
  on conflict (code) do nothing;

  insert into pipeline.ai_eval_source_map(source_kind, entity, field, action, family, label) values
   ('l4_decision', 'course', 'course_english', '*', 'course_fields', null),
   ('l4_decision', 'course', 'course_intake', '*', 'course_fields', null),
   ('l4_decision', 'course', 'provider_current_tuition', '*', 'course_fields', null),
   ('l4_decision', 'course', 'provider_current_tuition_validation', '*', 'course_fields', null),
   ('l4_decision', 'course', 'course_description_first_read', '*', 'course_description', null),
   ('l4_decision', 'provider', 'provider_description', '*', 'course_description', null),
   ('l4_decision', 'course', 'course_entry_first_read', '*', 'entry_requirements', null),
   ('l4_decision', 'provider', 'entry_matrix_first_run', '*', 'entry_requirements', null),
   ('l4_decision', 'provider', 'entry_matrix_change', '*', 'entry_requirements', null),
   ('l4_decision', 'provider', 'conjoint_rule_first_run', '*', 'entry_requirements', null),
   ('l4_decision', 'course', 'official_course_url', '*', 'page_identity', null),
   ('l4_decision', 'provider', 'no_page_first_run', '*', 'provider_course_matching', null),
   ('l4_decision', 'scholarship', 'scope_resolution', '*', 'scholarship_classification', null),
   ('human_correction', 'course', 'official_url', 'set_official_url', 'page_identity', 'correct'),
   ('human_correction', 'course', 'official_url', 'remove_official_url', 'page_identity', 'no_value'),
   ('human_correction', 'scholarship', 'source_url', 'set_core', 'page_identity', 'correct'),
   ('human_correction', 'course', 'tuition', 'set_tuition', 'course_fields', 'correct'),
   ('human_correction', 'course_entry', 'status', 'withdraw', 'entry_requirements', 'reject'),
   ('human_correction', 'provider', 'website', 'set_core', 'provider_course_matching', 'correct'),
   ('human_correction', 'provider', 'course_finder', 'set_course_finder', 'provider_course_matching', 'correct'),
   ('manual_lock', 'course', 'official_url', '*', 'page_identity', null),
   ('manual_lock', 'provider', 'website', '*', 'provider_course_matching', null),
   ('manual_lock', 'provider', 'display_name', '*', 'provider_course_matching', null),
   ('manual_lock', 'provider', 'canonical_name', '*', 'provider_course_matching', null),
   ('scholarship_review', 'scholarship', 'scholarship', 'admitted', 'scholarship_classification', 'accept'),
   ('scholarship_review', 'scholarship', 'scholarship', 'refused', 'scholarship_classification', 'reject'),
   -- the fields and reading sources whose quote the platform checks on the stored page (skip reasons "the quote is not on the page",
   -- "held: quote_not_on_page", "date_not_in_quote"; adapter values are the page's own text)
   ('quote_evidence', 'course', 'intakes', 'ai_stored', 'course_fields', 'accept'), ('quote_evidence', 'course', 'intakes', 'adapter', 'course_fields', 'accept'),
   ('quote_evidence', 'course', 'english', 'ai_stored', 'course_fields', 'accept'), ('quote_evidence', 'course', 'english', 'adapter', 'course_fields', 'accept'),
   ('quote_evidence', 'course', 'delivery', 'ai_stored', 'course_fields', 'accept'), ('quote_evidence', 'course', 'delivery', 'adapter', 'course_fields', 'accept'),
   ('quote_evidence', 'course', 'duration', 'ai_stored', 'course_fields', 'accept'), ('quote_evidence', 'course', 'duration', 'adapter', 'course_fields', 'accept'),
   ('quote_evidence', 'course', 'international', 'ai_stored', 'course_fields', 'accept'), ('quote_evidence', 'course', 'international', 'adapter', 'course_fields', 'accept'),
   ('quote_evidence', 'course', 'campus', 'adapter', 'course_fields', 'accept'),
   ('quote_evidence', 'course', 'deadline', 'ai_stored', 'deadline', 'accept'),
   ('quote_evidence', 'course', 'entry_requirements', 'ai_stored', 'entry_requirements', 'accept')
  on conflict do nothing;

  insert into pipeline.ai_approval_boundaries(change_class, authority, note) values
   ('operational_adjustment', 'auto', 'A setting on pipeline.ai_auto_tunable_settings, inside its minimum and maximum and ai_eval.auto_step_max_pct, with ai_eval.auto_accept_on; tried, measured, kept or put back'),
   ('prompt', 'release', 'Prompt text lives in worker code or a database row; a change ships through the release path after offline evaluation and canary'),
   ('extraction_schema', 'release', 'An answer schema change is a worker and database change: release path'),
   ('rule_set', 'release', 'A matching or acceptance rule set change: release path'),
   ('admission_rule', 'release', 'Admission rules (what is published without a person) always go to the release path (mandate §6, §15)'),
   ('security', 'release', 'Security controls: release path'),
   ('code', 'release', 'Production code: release path'),
   ('schema', 'release', 'Database schema and constraints: release path'),
   ('paid_permission', 'admin', 'Paid-service permissions and budgets need the Platform Admin''s explicit authorisation (mandate §15)'),
   ('approval_boundary', 'admin', 'The AI never changes its own approval boundaries (mandate §6); only the Platform Admin, through a release')
  on conflict (change_class) do nothing;

  insert into pipeline.ai_auto_tunable_settings(toolset_key, key, note)
  select s.toolset_key, s.key, 'Batch size: the AI may adjust it inside its range (IQ-00053: tune on measured time-outs and throughput)'
    from pipeline.platform_toolset_settings s
   where s.toolset_key = 'pipeline' and s.key in ('batch.enrich_fields', 'enrich.ai_items_per_call', 'batch.coverage_read', 'batch.coverage_admit')
     and s.kind = 'number' and s.min_value is not null and s.max_value is not null
  on conflict do nothing;
end $seed$;

-- the live baselines (worker constants keep the text; the md5 is of that text, checked by spec s250 against the code) and database homes
do $base$
declare r jsonb;
begin
  perform set_config('cf247.release', '20261104070000', true);
  for r in select * from jsonb_array_elements(jsonb_build_array(
    jsonb_build_object('family', 'deadline', 'code', 'course-text', 'kind', 'prompt', 'version', 'course-text-v1', 'status', 'current', 'model', 'openai/gpt-4.1-mini',
      'home', 'worker coverage-sweep/course-text.ts COURSE_TEXT_SYSTEM', 'body_md5', '155175239f78d88d63a6415b25b05085', 'note', 'description and deadline; the central model (pipeline.central_ai_settings)'),
    jsonb_build_object('family', 'page_identity', 'code', 'page-identity', 'kind', 'prompt', 'version', 'cf247-page-identity-v1.0.2', 'status', 'current', 'model', 'qwen/qwen3-30b-a3b-instruct-2507',
      'home', 'worker coverage-sweep/pageid.ts PAGE_ID_SYSTEM', 'body_md5', '6772d2f5e6ce80e0872b2a1465514598'),
    jsonb_build_object('family', 'provider_course_matching', 'code', 'course-page-match', 'kind', 'prompt', 'version', 'ai-match-v0.10.0', 'status', 'current', 'model', 'qwen/qwen3-30b-a3b-instruct-2507',
      'home', 'worker coverage-sweep/index.ts AI_MATCH_SYSTEM (AI_MATCH_MODEL)', 'body_md5', 'a74c2a5448b4c36b91ab281427e2d900'),
    jsonb_build_object('family', 'entry_requirements', 'code', 'entry-matrix', 'kind', 'prompt', 'version', 'entry-matrix-v0.1.4', 'status', 'current', 'model', 'openai/gpt-4.1-mini',
      'home', 'worker coverage-sweep/entry.ts ENTRY_PROMPT (setting entry.matrix_model)', 'body_md5', 'c2c3d6846e14e3b4718987a0cc6ae14d'),
    jsonb_build_object('family', 'entry_requirements', 'code', 'course-entry', 'kind', 'prompt', 'version', 'course-entry-v1', 'status', 'current', 'model', 'openai/gpt-4.1-mini',
      'home', 'worker coverage-sweep/course-entry.ts COURSE_ENTRY_SYSTEM', 'body_md5', '512a486462f452f2d184cbb62a2ec999'),
    jsonb_build_object('family', 'course_description', 'code', 'provider-description', 'kind', 'prompt', 'version', 'provider-description-v2', 'status', 'current', 'model', 'openai/gpt-4.1-mini',
      'home', 'worker coverage-sweep/description.ts DESCRIPTION_SYSTEM', 'body_md5', 'f539da5e1d69e8fde6a113459ceede75'),
    jsonb_build_object('family', 'scholarship_classification', 'code', 'scholarship-page', 'kind', 'prompt', 'version', 'scholarship-v2', 'status', 'current', 'model', 'qwen/qwen3-30b-a3b-instruct-2507',
      'home', 'pipeline.scholarship_ai_prompts version 2 (active)', 'body_md5', coalesce((select md5(p.text) from pipeline.scholarship_ai_prompts p where p.version = 2), md5('scholarship-v2'))),
    jsonb_build_object('family', 'provider_course_matching', 'code', 'course-page-candidates', 'kind', 'rule_set', 'version', 'candidates-v0.10.0', 'status', 'current',
      'home', 'worker coverage-sweep/index.ts candidate list for AI_MATCH; Layer 4 rules of 10 Oct (no third-party directories) and Decision 263 (provider page over handbook) applied after',
      'spec', jsonb_build_object('directory_hosts_as_hints', true, 'provider_page_over_handbook', 'Layer 4 rule (Decision 263), after the choice'))))
  loop
    perform security.ai_instruction_register_v1(r);
  end loop;
end $base$;

-- three proposals from live evidence (read-only, 3 Nov 2026 15:43-16:08 AEDT); each waits for its candidate run and evaluation set
do $prop$
declare v_base bigint; v_cand bigint; r jsonb;
begin
  perform set_config('cf247.release', '20261104070000', true);
  -- P1 deadline extraction
  select id into v_base from pipeline.ai_instruction_versions where code = 'course-text' and version = 'course-text-v1';
  perform security.ai_instruction_register_v1(jsonb_build_object('family', 'deadline', 'code', 'course-text', 'kind', 'prompt', 'version', 'course-text-v2-candidate', 'status', 'candidate',
    'model', 'openai/gpt-4.1-mini', 'home', 'proposal ai-p1-deadline-verbatim (worker change at release)',
    'body', $b$You read one course page of a university or education provider and report only what this page states about this course. description: 1 or more sentences that tell a prospective student what this course is (what it covers, how it is structured, who it is for). Each sentence is a plain, factual paraphrase of one passage of the page about this course, and for each sentence give that passage's exact words as its quote, copied character for character from the page text. Never use text about the provider in general, other courses, news, events, rankings or marketing banners. Do not state rankings, ratings, awards, employment or graduate outcomes, salaries, accreditations or facilities unless the quoted words state them. Do not use superlatives or marketing words (best, leading, world-class, top, renowned, prestigious, excellent) unless they are inside the quote. Write in Australian English, third person, present tense. Set about_course to false and give no sentences when the page does not describe this course. deadlines: every application closing date the page states for this course. kind is date when the page prints a full date (day, month and year), rolling when the page says applications are open all year or assessed as received, not_stated otherwise. date is that date as YYYY-MM-DD only when kind is date and the page prints the day, the month and the year; never work out a date from a start date or a term, and never assume a year. quote is the whole sentence or table row of the page that states the deadline, copied character for character, and it must contain the date exactly as printed (do not reformat it, and do not join words from two places). intake is the intake, start or semester the page ties the deadline to, copied character for character from that same quote or from the heading directly above it (for example 'February 2027 intake', 'Semester 1'), or null when the page gives one deadline for the course; never name an intake in your own words. Give an empty list when the page states none.$b$,
    'note', 'course-text-v1 with the deadline paragraph changed: the quote is the whole sentence or row and holds the date as printed; the intake is copied from the quote or its heading'));
  select id into v_cand from pipeline.ai_instruction_versions where code = 'course-text' and version = 'course-text-v2-candidate';
  r := security.ai_proposal_submit_v1(jsonb_build_object('code', 'ai-p1-deadline-verbatim', 'family', 'deadline', 'change_class', 'prompt', 'proposed_by', 'engineering',
    'baseline_version_id', v_base, 'candidate_version_id', v_cand,
    'title', 'Deadline quotes copied whole, with the intake taken from the quote',
    'problem_observed', 'Of 1,529 application-deadline reads of stored course pages, 267 were recorded and 413 were held by the database checks: the intake the model named did not match a held intake (178), the quote was not on the page and the intake did not match (128), the date was not in the quote (69), the quote was not on the page (38). 85 more failed.',
    'current_method', 'course-text-v1 (worker COURSE_TEXT_SYSTEM, central model openai/gpt-4.1-mini): the model gives a quote "that states the deadline" and names the intake "in the page''s own words"; the database then checks the quote is on the page, the date is in the quote and the intake matches.',
    'proposed_change', 'course-text-v2-candidate: the quote is the whole sentence or table row and must contain the date exactly as printed; the intake is copied from that quote or the heading directly above it, never paraphrased. Description rules unchanged. Same model, same answer schema.',
    'production_evidence', jsonb_build_object('measured_at', '2026-11-03T15:46+11:00', 'source', 'pipeline.field_enrich_items field deadline, grouped by state and reason (read-only)',
      'counts', jsonb_build_object('reads', 1529, 'filled', 267, 'failed', 85, 'held_intake_not_matched', 178, 'held_quote_not_on_page_and_intake_not_matched', 128,
                                   'held_date_not_in_quote', 69, 'held_quote_not_on_page', 38, 'not_stated', 467, 'rolling', 121),
      'trusted_examples', jsonb_build_object('person', 0, 'verified_quote', 267)),
    'expected_benefit', 'Up to 413 held deadlines become checkable (27% of reads); fewer quotes off the page. A deadline held in error is still refused by the database checks, so the gain is in coverage, not in looser admission.',
    'risks', 'Longer quotes cost a few more output tokens. No person has yet decided a deadline (0 Layer 4 decisions), so the evaluation set is quote-checked readings made by v1 itself, which favours v1; the change cannot pass until ai_eval.min_person_examples decisions exist or a canary is judged on Layer 4 decisions.',
    'acceptance_criteria_extra', jsonb_build_object('family_metric', 'held deadlines with quote_not_on_page, date_not_in_quote or intake_not_matched fall by at least a third on the canary')));
  raise notice 'P1: %', r;

  -- P2 "not stated" on intakes and English
  perform security.ai_instruction_register_v1(jsonb_build_object('family', 'course_fields', 'code', 'course-fields', 'kind', 'extraction_schema', 'version', 'course-fields-v1', 'status', 'current',
    'home', 'worker coverage-sweep enrich_ai (course fields from the stored page, enrich.page_chars from the start of the page)',
    'spec', jsonb_build_object('page_text', 'first enrich.page_chars characters', 'not_stated', 'one value, no basis')));
  perform security.ai_instruction_register_v1(jsonb_build_object('family', 'course_fields', 'code', 'course-fields', 'kind', 'extraction_schema', 'version', 'course-fields-v2-candidate', 'status', 'candidate',
    'home', 'proposal ai-p2-not-stated-sections (worker and database change at release)',
    'spec', jsonb_build_object('page_text', 'the sections whose headings name entry requirements, English language, international students, key dates, intakes or how to apply first, then the rest of the page up to enrich.page_chars',
                               'not_stated', jsonb_build_object('values', jsonb_build_array('not_on_page', 'page_cut', 'other_page_named'), 'basis', 'the headings read'),
                               'answer_adds', jsonb_build_array('not_stated_kind', 'headings_read', 'page_chars_total'))));
  select id into v_base from pipeline.ai_instruction_versions where code = 'course-fields' and version = 'course-fields-v1';
  select id into v_cand from pipeline.ai_instruction_versions where code = 'course-fields' and version = 'course-fields-v2-candidate';
  r := security.ai_proposal_submit_v1(jsonb_build_object('code', 'ai-p2-not-stated-sections', 'family', 'course_fields', 'change_class', 'extraction_schema', 'proposed_by', 'engineering',
    'baseline_version_id', v_base, 'candidate_version_id', v_cand,
    'title', 'Read the requirement and dates sections first, and say why a value is not stated',
    'problem_observed', '"The page does not state it" is the main answer for intakes (13,900 reads; 1,207 recorded) and English (12,834 reads; 294 recorded). A further 2,800 intake quotes named no month or semester. The platform cannot tell a page that lacks the value from a page whose section was beyond the text sent, or a page that points to another page.',
    'current_method', 'enrich_ai reads the stored course page from its start up to enrich.page_chars (24,000) characters and answers one not_stated value with no basis.',
    'proposed_change', 'Send the sections whose headings name entry requirements, English language, international students, key dates, intakes or how to apply first, then the rest of the page; record not_stated as not_on_page, page_cut or other_page_named with the headings read and the page length. The database checks stay as they are.',
    'production_evidence', jsonb_build_object('measured_at', '2026-11-03T15:46+11:00', 'source', 'pipeline.field_enrich_items fields intakes and english, grouped by state, source and reason (read-only)',
      'counts', jsonb_build_object('intakes_not_stated', 13900, 'intakes_filled', 1207, 'intakes_no_month_in_quote', 2800, 'english_not_stated', 12834, 'english_filled', 294,
                                   'english_quote_without_ielts_score', 387, 'l4_course_english_decisions', jsonb_build_object('approve', 12, 'edit_and_approve', 2, 'reject', 7)),
      'trusted_examples', jsonb_build_object('person', 21, 'verified_quote_intakes_and_english', 1501)),
    'expected_benefit', 'More intakes and English requirements found on pages already stored (no new reads, no Firecrawl); and a measured split of "not stated" into absent, cut off and elsewhere, which tells source discovery (workstream B) where another page is needed.',
    'risks', 'Section selection may miss a heading wording and lose text the head of the page held; the not_stated kinds are new answer fields (schema change, release path). Only 21 English decisions by a person exist, so acceptance needs more Layer 4 English decisions or a judged canary.',
    'acceptance_criteria_extra', jsonb_build_object('family_metric', 'coverage of intakes and English rises on person-decided examples with no rise in false positives')));
  raise notice 'P2: %', r;

  -- P3 course-page identity and matching
  perform security.ai_instruction_register_v1(jsonb_build_object('family', 'provider_course_matching', 'code', 'course-page-candidates', 'kind', 'rule_set', 'version', 'candidates-v0.11.0-candidate', 'status', 'candidate',
    'home', 'proposal ai-p3-page-identity-rules (worker change at release)',
    'spec', jsonb_build_object('before_the_model', jsonb_build_array(
        'drop a candidate whose host is not the provider''s own site or a host listed for it (third-party directories are hints only)',
        'drop a handbook or listing page when the provider''s own course page for the same code or title is a candidate (Decision 263)',
        'drop a candidate whose qualification type differs from the course''s (pageid.ts qualType)'),
      'answer', 'choice 0 when no candidate is left')));
  select id into v_base from pipeline.ai_instruction_versions where code = 'course-page-candidates' and version = 'candidates-v0.10.0';
  select id into v_cand from pipeline.ai_instruction_versions where code = 'course-page-candidates' and version = 'candidates-v0.11.0-candidate';
  r := security.ai_proposal_submit_v1(jsonb_build_object('code', 'ai-p3-page-identity-rules', 'family', 'provider_course_matching', 'change_class', 'rule_set', 'proposed_by', 'engineering',
    'baseline_version_id', v_base, 'candidate_version_id', v_cand,
    'title', 'Apply the people''s page rules before the matcher chooses',
    'problem_observed', 'Of 639 proposed course links a person approved or rejected in Layer 4, 448 were rejected (70%): third-party course directories (160), title mismatches (98), a handbook page where the provider''s own course page exists (80 by person and by rule). Field reads were refused because the page was another course''s: intakes 6,441, English 4,603, delivery 4,262, duration 1,092; page_rejections holds 4,343 binding-check refusals. On courses whose page a person later chose, the matcher''s choice agreed with the person in 986 of 2,077 cases (47%).',
    'current_method', 'candidates-v0.10.0 with AI_MATCH_SYSTEM (qwen/qwen3-30b-a3b-instruct-2507): the model chooses among all candidates, directories included as hints; the rules of 10 Oct (no directories) and Decision 263 (provider page over handbook) are applied afterwards, in Layer 4.',
    'proposed_change', 'candidates-v0.11.0-candidate: apply the same three rules to the candidate list before the model chooses (host is the provider''s, provider page over handbook or listing, qualification type matches); choice 0 when none is left. Same model and prompt.',
    'production_evidence', jsonb_build_object('measured_at', '2026-11-03T15:49+11:00', 'source', 'pipeline.layer4_decisions official_course_url by reason; pipeline.field_enrich_items skip reasons; pipeline.page_rejections by source (read-only)',
      'counts', jsonb_build_object('l4_url_decided_by_person', 639, 'l4_url_rejected', 448, 'rejected_third_party_directory', 160, 'rejected_title_match', 98, 'rejected_handbook_over_course_page', 80,
                                   'reads_refused_other_course_page', jsonb_build_object('intakes', 6441, 'english', 4603, 'delivery', 4262, 'duration', 1092),
                                   'page_rejections_binding_check', 4343, 'match_cases_with_person_label', 5829,
                                   'matcher_choices_on_person_labelled_courses', 2077, 'matcher_agreed_with_person', 986),
      'measured_again_at', '2026-11-03T16:16+11:00',
      'trusted_examples', jsonb_build_object('person_page_identity_deduplicated', 4204, 'person_match_cases', 5829)),
    'expected_benefit', 'Fewer wrong course links sent to Layer 4 (people''s time) and fewer field reads wasted on another course''s page; the rules already decide these cases in Layer 4, so admission does not loosen.',
    'risks', 'A provider whose own pages live on a second domain could lose its right candidate; the host rule uses the provider''s verified hosts. Rule-decided Layer 4 rows (basis rule_decision) agree with the rule by construction, so acceptance is judged on person and batch decisions.',
    'acceptance_criteria_extra', jsonb_build_object('family_metric', 'false positives on match cases fall with no loss of coverage on person-labelled cases')));
  raise notice 'P3: %', r;
end $prop$;

-- root causes and remedies in workstream A's registers
select security.ops_root_cause_register_v1('ai_quote_not_verbatim', jsonb_build_object('class', 'rule', 'title', 'AI answer quote not on the page',
  'description', 'A reading''s quote is not found on the stored page, or does not hold the value (date not in quote, intake not matched), so the value is held. Treated by an instruction improvement (workstream E).',
  'detect', jsonb_build_object('table', 'pipeline.field_enrich_items', 'state', 'skipped', 'reasons', jsonb_build_array('the quote is not on the page', 'held: quote_not_on_page', 'held: date_not_in_quote', 'held: intake_not_matched'))));
select security.ops_root_cause_register_v1('ai_page_identity_mismatch', jsonb_build_object('class', 'rule', 'title', 'AI chose or read another course''s page',
  'description', 'A course link the matcher proposed is rejected in Layer 4, or a reading is refused because the page is another course''s. Treated by matching rules applied before the model (workstream E proposal) and by relinking (workstream B).',
  'detect', jsonb_build_object('tables', jsonb_build_array('pipeline.layer4_decisions (official_course_url, reject)', 'pipeline.field_enrich_items (no correct course page)', 'pipeline.page_rejections (binding_check)'))));
select security.ops_root_cause_register_v1('ai_instruction_regression', jsonb_build_object('class', 'rule', 'title', 'A candidate AI instruction does worse than the current one',
  'description', 'A candidate in canary loses accuracy, coverage or source integrity, admits more wrong values, costs more or fails more than the current version on items a person has decided.',
  'detect', jsonb_build_object('function', 'security.ai_canary_judge_v1', 'proposals', 'pipeline.ai_improvement_proposals status canary')));
select security.ops_remedy_register_v1('ai_canary_rollback', jsonb_build_object('title', 'Stop a failing AI canary and put the current version back',
  'treats', jsonb_build_array('ai_instruction_regression'), 'authority', 'auto',
  'action_fn', 'security.ai_remedy_canary_rollback_v1(bigint)', 'verify_fn', 'security.ai_remedy_canary_verify_v1(bigint)',
  'notes', 'Only stops a canary (no spend, no admission); the issue''s diagnosis evidence names the proposal. The rejected-proposal ledger keeps the change from being proposed again.'));
select security.ops_remedy_register_v1('ai_improvement_proposal', jsonb_build_object('title', 'Propose and evaluate an AI instruction or rule change',
  'treats', jsonb_build_array('ai_quote_not_verbatim', 'ai_page_identity_mismatch'), 'authority', 'release',
  'notes', 'pipeline.ai_improvement_proposals: offline evaluation, canary behind ai_eval.canary_on, acceptance through the release path (security.ai_proposal_record_release_v1).'));

-- 10. job, catalogue and register -------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('ai-eval', 'Platform upkeep', 96, 'AI evaluation: collect ground truth and judge improvements',
  'Every hour (minute 7): adds new trusted examples to the AI evaluation sets (Layer 4 decisions by a person, people''s corrections and locks, quote-checked readings, scholarship decisions; batch.ai_eval_examples per source), sets aside a quote-checked example a person has since contradicted, scores evaluation runs the worker has answered, judges improvement proposals on the mandate §6 criteria, and judges canaries on later decisions by a person (a failing canary is rolled back). Records only: no AI call, no Firecrawl, no admission. Switch: ai_eval.refresh_on.',
  5, false, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'ai-eval') then
    perform cron.schedule('ai-eval', '7 * * * *', $c$select security.ai_eval_tick_v1()$c$);
  end if;
end $j$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.ai_eval_families', 'Platform', 'AI evaluation', 'AI task families evaluated', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_eval_source_map', 'Platform', 'AI evaluation', 'Which trusted source rows become evaluation examples', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_eval_examples', 'Platform', 'AI evaluation', 'Evaluation ground truth (people''s decisions, corrections, locks, quote-checked readings)', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_eval_sets', 'Platform', 'AI evaluation', 'Frozen evaluation sets', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_eval_set_members', 'Platform', 'AI evaluation', 'Members of frozen evaluation sets', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_instruction_versions', 'Platform', 'AI evaluation', 'Versions of AI instructions and rules, with rollback', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_approval_boundaries', 'Platform', 'AI evaluation', 'Who may accept each class of AI improvement', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_auto_tunable_settings', 'Platform', 'AI evaluation', 'Settings the AI may tune inside their range', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_improvement_proposals', 'Platform', 'AI evaluation', 'AI improvement proposals with evidence, criteria and results', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_proposal_events', 'Platform', 'AI evaluation', 'Status history of AI improvement proposals', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_rejected_proposals', 'Platform', 'AI evaluation', 'Ledger of rejected and rolled-back AI changes', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_eval_runs', 'Platform', 'AI evaluation', 'Offline regression runs', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_eval_answers', 'Platform', 'AI evaluation', 'Answers of offline regression runs', 'active', '{}', '20261104070000'),
 ('table', 'pipeline.ai_canary_assignments', 'Platform', 'AI evaluation', 'Canary assignments and answers', 'active', '{}', '20261104070000'),
 ('job', 'ai-eval', 'Platform', 'AI evaluation', 'Collects ground truth, scores runs, judges proposals and canaries (records only)', 'active', '{}', '20261104070000')
on conflict do nothing;
