-- CF-247 AER Phase B: continuous quality-control foundation (Platform Admin, CF-247 AER Consolidated Development, Coverage Recovery and
-- Continuous Assurance Mandate, 2 Nov 2026 14:45: §16 Phase B, detail in §11, §13 and §14; design in admin
-- docs/platform/nz-enrichment-brief/2026-11-02-aer-phase-a-baseline.md §5.1 B1–B7).
-- Why (live, read-only, 2 Nov 2026 14:48–15:27 AEDT): a source marked "read" says nothing about extraction (all 36 RMIT sources are read
--   while 7 of their latest runs are held); 1,442 of the 1,476 eligible AU/NZ providers have no AER source at all; nothing records a gap,
--   its root cause, when it was first and last seen, or whether it came back; Coverage & completeness says "Not measured here yet" for
--   academic entry requirements. The Platform Admin found every gap by hand.
-- What (additive; no AI, no fetch, no Firecrawl; reads existing data only):
--   1 pipeline.aer_source_manifests: one row per source and content hash, taken from the reading run already stored (shape, heading,
--     scope, expected and matched cells, omitted columns, hold reason). Nothing is read again.
--   2 pipeline.aer_gap_root_causes (one row per defect class, linked to every provider it affects), pipeline.aer_gap_findings (stable
--     fingerprint: md5 of provider, source, scope kind, scope key, study level and root cause; open, resolved or reopened, which are
--     observation states, not admission statuses) and pipeline.aer_gap_events (opened, resolved, reopened only: an unchanged source adds
--     no row, no duplicate).
--   3 security.aer_reconcile_v1 (job aer-reconcile, hourly at :27, created PAUSED: activation is a separate step): compares source ->
--     run -> manifest -> proposed -> Layer 4 -> active -> consumer outcome for every eligible provider; deduplicates by fingerprint;
--     resolves a finding only with closure evidence (a later complete run checked against its manifest, a source now read, no rows
--     waiting, no offending active row); reopens a resolved finding when the same fingerprint is found again. Single flight.
--   4 pipeline.aer_coverage_daily: four measures (source discovery, extraction, verified admission, consumer-resolvable) as numerator and
--     denominator over the eligible providers (country AU or NZ, active, published, enrols_international true; baseline §1.1), by
--     country and in all; open P0/P1/P2; new, resolved and reopened. Never every country of the reference table.
--   5 public.admin_aer actions 'coverage' and 'coverage_provider' (md5-guarded edit): Curator (rank 3) and above; viewers, counsellors and
--     consumers see none of it. Read by Coverage & completeness and Catalogue › Entry requirements.
--   6 Alerts: a P0 finding or a fall in consumer-resolvable providers opens one Platform health issue (aer:p0, aer:regression) that the
--     existing deduplicated platform-alerts job raises and later sends one recovery notice for; no alert per country or qualification.
--     Weekly: an AER section in the stored weekly scorecard (security.ops_scorecard_record_v1, md5-guarded edit); the Monday 08:00
--     Sydney e-mail through the existing alert delivery is built switched OFF (aer.weekly_email_enabled false) until the Platform Admin
--     confirms the destination (D-A7).
--   7 Catalogue-first gap queue (Platform Admin correction 2 Nov 2026 15:43; admin nz-enrichment-brief/2026-11-02-aer-catalogue-provider-
--     coverage-reconciliation.md): pipeline.aer_provider_coverage holds one row per eligible provider from catalogue.providers joined to
--     ref.countries (never entry.providers, the 40-provider pilot or the existing sources), with a report disposition (not_discovered,
--     source_held, reader_failed, awaiting_layer4, active_verified, course_only, source_not_published_evidenced, not_applicable_evidenced:
--     report words only, the admission vocabulary is unchanged), separate discovery, extraction and admission states, the exact source,
--     run and review ids, and a priority (universities and tertiary providers first, held sources next to them). Each run reports the
--     population against the 1,476 baseline (AU 1,279, NZ 197) with the exact provider ids that joined or left. Database metadata only:
--     no crawl. security.aer_coverage_verify_v1 compares the stored queue with a fresh catalogue anti-join.
--   8 Layer 4 review readiness (Platform Admin Layer 4 recovery mandate 2 Nov 2026 16:33 §9): pipeline.aer_review_readiness classifies
--     each pending AER Layer 4 item as review_ready, reader_correction_required, evidence_required, superseded_invalid or
--     awaiting_human_review (report classes; the Layer 4 status vocabulary is unchanged), linked to the same root causes. The reconcile
--     records every pending item as awaiting_human_review until a classification is loaded (security.aer_review_readiness_load_v1, run
--     by the Platform Admin); a defect named on pending items becomes one finding per provider and root cause; a settled item is never
--     reopened.
--   9 Weekly report (D-A7, Platform Admin 2 Nov 2026 ~16:40: "Email, copy to be stored in admin repo, and admin dashboard"): the same text
--     is e-mailed through the existing alert route (off until activated), written as Markdown by security.aer_weekly_markdown_v1 for the
--     workflow aer-weekly-report (Monday 08:07 Sydney; off unless repository variable AER_WEEKLY_REPORT_ENABLED is true), which commits
--     docs/platform/aer-weekly/YYYY-MM-DD.md to the aer-weekly-snapshot branch as the component-register snapshot does, and shown on
--     Coverage & completeness › Attributes › Academic entry requirements.
-- Consumer API: untouched (G3). No consumer function, table, column or edge function changes; nothing here is read by the consumer API.
-- Replaces: public.admin_aer, security.ops_scorecard_record_v1 (same names; md5-guarded edits adding the AER coverage read and the weekly AER section)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. Nothing in the catalogue changes when this migration is applied.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': edited';
end $f$;

-- 1 settings (G2) --------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'batch.aer_reconcile', 'AER reconcile: new findings written a run',
  'Most new AER gap findings recorded in one run of aer-reconcile (the rest are recorded in the next run). Findings already recorded are always updated.', 'number',
  to_jsonb(5000), 100, 50000, 'findings', 993, 'Job sizes', 'security.aer_reconcile_v1 (job aer-reconcile)', 'CF-247 AER mandate 2 Nov 2026 14:45 §16 Phase B: hourly reconciliation'),
 ('pipeline', 'aer.eligible_countries', 'AER assurance: countries measured',
  'Countries whose active, published, international-enrolling providers make up the AER denominator (mandate §9). Other countries are not counted.', 'list',
  '["AU", "NZ"]'::jsonb, null, null, null, 994, 'Entry requirements', 'security.aer_reconcile_v1; security.aer_coverage_read_v1', 'CF-247 AER mandate 2 Nov 2026 §9; Phase A baseline §1.1 (1,476 providers)'),
 ('pipeline', 'aer.stale_source_days', 'AER assurance: a read source is stale after',
  'A source read longer ago than this is a P2 "stale source" finding (mandate §11). Nothing is read again by this check.', 'number',
  to_jsonb(90), 7, 730, 'days', 995, 'Entry requirements', 'security.aer_reconcile_v1', 'CF-247 AER mandate §11 P2 stale source; Decision 8 (25 Oct 2026) planned 90 days'),
 ('pipeline', 'aer.alerts_enabled', 'AER assurance: open Platform health issues',
  'When on, a P0 finding or a fall in consumer-resolvable providers opens one Platform health issue, which the existing alert job raises (and sends a recovery notice for). No alert is sent for each missing country or qualification.', 'boolean',
  to_jsonb(true), null, null, null, 996, 'Entry requirements', 'security.aer_reconcile_v1', 'CF-247 AER mandate §14 event-driven alerts through the existing delivery'),
 ('pipeline', 'aer.regression_alert_providers', 'AER assurance: regression alert after a fall of',
  'Consumer-resolvable providers today fewer than yesterday''s final count by at least this many opens a critical Platform health issue.', 'number',
  to_jsonb(1), 1, 500, 'providers', 997, 'Entry requirements', 'security.aer_reconcile_v1', 'CF-247 AER mandate §14: significant verified coverage regression'),
 ('pipeline', 'aer.weekly_email_enabled', 'AER assurance: Monday e-mail on',
  'Sends the weekly AER report through the existing alert delivery on Monday (Sydney). Off until the Platform Admin confirms the destination (decision D-A7). The weekly section is kept in the scorecard either way.', 'boolean',
  to_jsonb(false), null, null, null, 998, 'Entry requirements', 'security.aer_reconcile_v1 (job aer-reconcile)', 'CF-247 AER mandate §14 weekly; D-A7 open, so built switched off'),
 ('pipeline', 'aer.weekly_send_hour', 'AER assurance: Monday e-mail from',
  'Hour of Monday (Australia/Sydney) from which the weekly AER report is sent, once a week.', 'number',
  to_jsonb(8), 0, 23, 'hour', 999, 'Entry requirements', 'security.aer_reconcile_v1 (job aer-reconcile)', 'CF-247 AER mandate §14: Monday 8:00 am Australia/Sydney'),
 ('pipeline', 'aer.baseline_eligible', 'AER assurance: eligible provider baseline',
  'The eligible provider count each country was reconciled to (catalogue.providers, AU/NZ, active, published, enrols international). Every run reports its own count against it, with the exact providers that joined or left.', 'list',
  '[{"country": "AU", "providers": 1279}, {"country": "NZ", "providers": 197}]'::jsonb, null, null, null, 1001, 'Entry requirements', 'security.aer_reconcile_v1; security.aer_coverage_read_v1',
  'Platform Admin 2 Nov 2026 15:43: AU 1,279 + NZ 197 = 1,476; report any delta exactly'),
 ('pipeline', 'aer.priority_provider_types', 'AER assurance: provider types first in the gap queue',
  'Provider types (ref.provider_types codes) put first in the AER gap queue; providers whose source is present but held sit next to them. Every other provider stays in the denominator.', 'list',
  '["university", "university_college", "higher_education_institute", "tafe_polytechnic", "wananga"]'::jsonb, null, null, null, 1002, 'Entry requirements', 'security.aer_provider_states_v1',
  'Platform Admin 2 Nov 2026 15:43 §4: universities and tertiary providers first'),
 ('pipeline', 'aer.not_applicable_provider_types', 'AER assurance: provider types where AER does not apply',
  'Provider types (ref.provider_types codes) whose register type is the evidence that academic entry requirements do not apply (for example school-level only). Empty until the Platform Admin decides; until then no provider is reported as not applicable.', 'list',
  '[]'::jsonb, null, null, null, 1003, 'Entry requirements', 'security.aer_provider_states_v1',
  'Platform Admin 2 Nov 2026 15:43 §2: not_applicable_evidenced only with evidence; the type list is a decision, so it starts empty'),
 ('pipeline', 'aer.postgraduate_levels', 'AER assurance: postgraduate study levels',
  'Study level short codes counted as postgraduate in the AER coverage figures (mandate §7).', 'list',
  '["MC", "MA", "MR", "DR", "GC", "GD", "ME"]'::jsonb, null, null, null, 1000, 'Entry requirements', 'security.aer_reconcile_v1; security.aer_weekly_section_v1', 'CF-247 AER mandate §7; Phase A baseline §3.2')
on conflict (toolset_key, key) do nothing;

-- 2 tables ------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_source_manifests (
  id bigserial primary key,
  source_id uuid not null,
  provider_id uuid not null,
  content_hash text not null,
  run_id uuid,
  run_state text,
  basis text not null default 'none',
  shape text not null check (shape in ('country_table', 'qualification_page', 'requirement_table', 'pdf_table', 'no_table', 'unparsed', 'policy_hold', 'unknown')),
  heading text,
  scope_country text,
  scope_label text,
  expected_cells int,
  matched_cells int,
  omitted_cells int,
  omitted_columns jsonb not null default '[]'::jsonb,
  sections jsonb not null default '{}'::jsonb,
  reason text,
  computed_at timestamptz not null default now(),
  unique (source_id, content_hash)
);
comment on table pipeline.aer_source_manifests is 'CF-247 AER Phase B (mandate 2 Nov 2026 14:45 §11, B1): the evidence-backed expected-section manifest of each AER source and content hash, taken from the reading run already stored in pipeline.entry_matrix_runs (completeness basis manifest-v1, or the held reason). Shape, heading, country or qualification scope, expected and matched published cells, omitted columns. Written by security.aer_reconcile_v1 (job aer-reconcile); no page is read again. Admin only; never read by the consumer API.';
alter table pipeline.aer_source_manifests enable row level security;
revoke all on pipeline.aer_source_manifests from public, anon, authenticated;
create index if not exists aer_source_manifests_provider_idx on pipeline.aer_source_manifests (provider_id);

create table if not exists pipeline.aer_gap_root_causes (
  code text primary key,
  label text not null,
  severity text not null check (severity in ('P0', 'P1', 'P2')),
  measure text not null check (measure in ('discovery', 'extraction', 'admission', 'consumer')),
  owner_role text not null,
  next_action text not null,
  description text not null,
  created_at timestamptz not null default now()
);
comment on table pipeline.aer_gap_root_causes is 'CF-247 AER Phase B (mandate §11, B2): one row per underlying AER defect class (for example a qualification page refused for having no country heading). Every finding names one root cause, so one parser defect affecting several providers is one root cause linked to all of them. Severity P0/P1/P2 as the mandate defines; owner role and the next approved action. Admin only.';
alter table pipeline.aer_gap_root_causes enable row level security;
revoke all on pipeline.aer_gap_root_causes from public, anon, authenticated;

insert into pipeline.aer_gap_root_causes(code, label, severity, measure, owner_role, next_action, description) values
 ('consumer_unevidenced', 'Active requirement without evidence', 'P0', 'consumer', 'Platform Admin',
  'Quarantine the rows on Catalogue › Entry requirements and admit them again through Layer 4 with their stored evidence.',
  'An active (consumer-resolvable) provider matrix or course requirement row has no stored evidence or no quote.'),
 ('consumer_unadmitted', 'Active requirement not admitted in Layer 4', 'P0', 'consumer', 'Platform Admin',
  'Quarantine the rows and send them through Layer 4; find how they became active.',
  'An active row read by the AI reader whose Layer 4 item is not approved (a Layer 4 bypass or a corrupted admission).'),
 ('consumer_number_without_scale', 'Active number without its scale', 'P0', 'consumer', 'Platform Admin',
  'Quarantine the rows; correct the scale from the stored quote through Layer 4.',
  'An active row holds a numeric minimum with no grading scale, which the admission rules refuse (no unsupported conversion).'),
 ('non_country_heading', 'Qualification page refused: no country in the heading', 'P1', 'extraction', 'PIM Admin',
  'Phase C2: classify qualification pages (IB, GAC) and read them as qualification rows; RMIT re-entry needs D-A2.',
  'The reader holds a page whose heading names no country (entryNonCountryShape), so a global qualification page cannot be read.'),
 ('requirement_type_columns', 'Pathway table refused: requirement-type columns', 'P1', 'extraction', 'PIM Admin',
  'Phase C2: classify pathway sources (Foundation equivalencies) separately from country tables.',
  'The reader holds a table whose columns are requirement types, not qualifications.'),
 ('reader_omission', 'Published minimums not read', 'P1', 'extraction', 'PIM Admin',
  'Phase C3: re-read only the omitted manifest cells from the stored copy (needs D-A2 and D-A3).',
  'The completeness guard found published cells or a whole column of the source table missing from the read.'),
 ('unscaled_column', 'Bare numbers with no printed scale', 'P1', 'extraction', 'Pipeline Operator',
  'Phase C4: find the printed scale on a first-party page, or record an evidenced case-by-case outcome.',
  'A column of bare numbers whose scale the page does not print is held (Platform Admin rule, 27 Oct 2026).'),
 ('pdf_table_layout', 'PDF table layout not read', 'P1', 'extraction', 'PIM Admin',
  'Step B PDF route: extend the table reader for this layout (column edges, missing rules).',
  'A PDF table is held because text crosses a column edge, lies outside the columns or has no drawn rules.'),
 ('policy_hold', 'Held by a decision', 'P1', 'extraction', 'Platform Admin',
  'Platform Admin decision to lift or keep the hold (consolidated decision list).',
  'A reading run is held by a recorded decision, not a reader defect.'),
 ('extraction_failed', 'Reading failed for another reason', 'P1', 'extraction', 'PIM Admin',
  'Investigate the reading run on Catalogue › Entry requirements › Sources, reads and holds.',
  'The latest reading run of a read source failed with a reason no other root cause covers.'),
 ('course_read_held', 'Course entry read held whole', 'P1', 'extraction', 'PIM Admin',
  'Course reading: a per-provider page limit with a reason, or a read of the course''s own section (E13 rules).',
  'A course entry read was held whole (for example the page is longer than the reading limit), so its requirements are unknown.'),
 ('manifest_unparsed', 'Completeness unknown: no table manifest', 'P2', 'extraction', 'Pipeline Operator',
  'Check the stored copy; the read cannot be checked against the published table, so it is reported as unknown.',
  'The run finished but the source''s tables could not be listed, so completeness is unknown, never assumed.'),
 ('not_extracted', 'Read but not extracted', 'P2', 'extraction', 'Pipeline Operator',
  'Queue the reading run through the existing entry-matrix-read job when reads are allowed (D-A3).',
  'The source was read but no reading run exists for it.'),
 ('source_unreadable', 'Source could not be fetched', 'P2', 'discovery', 'Pipeline Operator',
  'Find another first-party copy or route (rendered page, PDF) under the source acquisition rules.',
  'The source fetch failed (for example a blocked PDF); what it publishes is unknown.'),
 ('stale_source', 'Source not read recently', 'P2', 'discovery', 'Pipeline Operator',
  'Check for a newer edition when reads are allowed (edition check).',
  'The source was last read longer ago than aer.stale_source_days.'),
 ('no_source', 'No official AER source recorded', 'P2', 'discovery', 'Pipeline Operator',
  'Phase E discovery waves from stored copies, ordered by course count (needs D-A1).',
  'An eligible provider has no official entry requirements source recorded, so its coverage is unknown.'),
 ('awaiting_layer4', 'Requirements waiting for Layer 4', 'P2', 'admission', 'Layer 4 Reviewer',
  'Layer 4 › Review, AER path, one item at a time (never in bulk).',
  'Extracted requirements are proposed and wait for a Layer 4 decision.'),
 -- Layer 4 review readiness defects (mandate 16:33 §4 B and C): named on pending items by a loaded classification
 ('row_cap', 'Read cut at the row limit', 'P1', 'extraction', 'PIM Admin',
  'E13: per-provider row limit with a reason, or a read of the course''s own section; never a global raise.',
  'A course read stopped at the requirement row limit, so requirements published on the page are missing.'),
 ('quote_mismatch', 'Quote not found on the stored page', 'P1', 'extraction', 'PIM Admin',
  'Reader correction: quote matching against the stored copy.',
  'A proposed requirement''s quote cannot be matched to the stored official page.'),
 ('missing_score_basis', 'Score without its basis', 'P1', 'extraction', 'PIM Admin',
  'Reader correction: keep the printed scale or basis with the score.',
  'A proposed minimum carries no grading scale or score basis.'),
 ('programme_variant', 'Wrong programme variant', 'P1', 'extraction', 'PIM Admin',
  'Reader correction: bind the requirement to the course''s own variant (E13 variant check).',
  'A proposed requirement belongs to a sibling programme or variant, not this course.'),
 ('evidence_incomplete', 'Evidence not sufficient for admission', 'P1', 'admission', 'Pipeline Operator',
  'Return or hold the item for evidence under the playbook (source identity, edition, applicability).',
  'The stored evidence cannot support admission: wrong or stale source, incomplete table, unclear applicability or conflicting editions.'),
 ('superseded_read', 'Superseded or invalid read', 'P2', 'admission', 'Layer 4 Reviewer',
  'Recommend rejection with the demonstrated reason recorded (never in bulk).',
  'A pending item repeats an older read, belongs to another provider or course, or reads unrelated content.')
on conflict (code) do nothing;

create table if not exists pipeline.aer_gap_findings (
  id bigserial primary key,
  fingerprint text not null unique,
  root_cause text not null references pipeline.aer_gap_root_causes(code),
  provider_id uuid not null,
  source_id uuid,
  scope_kind text not null check (scope_kind in ('provider', 'source', 'country', 'qualification', 'study_level', 'review_items')),
  scope_key text,
  scope_label text,
  study_level text,
  severity text not null check (severity in ('P0', 'P1', 'P2')),
  state text not null default 'open' check (state in ('open', 'resolved', 'reopened')),
  evidence jsonb not null default '{}'::jsonb,
  owner_role text not null,
  next_action text not null,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  resolved_at timestamptz,
  closure_evidence jsonb,
  reopen_count int not null default 0,
  last_run_id bigint
);
comment on table pipeline.aer_gap_findings is 'CF-247 AER Phase B (mandate §11, B2): one row per AER gap, keyed by a stable fingerprint (md5 of provider, source, scope kind, scope key, study level and root cause), so a repeated detection updates last_seen and adds nothing. State open, resolved (only with closure evidence) or reopened (the same fingerprint found again). Severity, evidence, owner role, next action, first and last seen. Written by security.aer_reconcile_v1 only. Admin only; never read by the consumer API.';
alter table pipeline.aer_gap_findings enable row level security;
revoke all on pipeline.aer_gap_findings from public, anon, authenticated;
create index if not exists aer_gap_findings_provider_idx on pipeline.aer_gap_findings (provider_id, state);
create index if not exists aer_gap_findings_open_idx on pipeline.aer_gap_findings (state, severity, root_cause);

create table if not exists pipeline.aer_gap_events (
  id bigserial primary key,
  finding_id bigint not null references pipeline.aer_gap_findings(id),
  fingerprint text not null,
  event text not null check (event in ('opened', 'resolved', 'reopened')),
  run_id bigint,
  detail jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
comment on table pipeline.aer_gap_events is 'CF-247 AER Phase B (mandate §11, B2): append-only history of AER gap findings: opened, resolved (with the closure evidence) and reopened. An hourly observation that changes nothing adds no row. Feeds the new, resolved and reopened counts. Admin only.';
alter table pipeline.aer_gap_events enable row level security;
revoke all on pipeline.aer_gap_events from public, anon, authenticated;
create index if not exists aer_gap_events_at_idx on pipeline.aer_gap_events (at desc);
create index if not exists aer_gap_events_finding_idx on pipeline.aer_gap_events (finding_id, at desc);

create table if not exists pipeline.aer_reconcile_runs (
  id bigserial primary key,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  result jsonb not null default '{}'::jsonb
);
comment on table pipeline.aer_reconcile_runs is 'CF-247 AER Phase B (mandate §14 hourly, B3): one row per run of security.aer_reconcile_v1 (job aer-reconcile) with what it found, opened, resolved and reopened. Shows that the hourly reconciliation runs. Admin only.';
alter table pipeline.aer_reconcile_runs enable row level security;
revoke all on pipeline.aer_reconcile_runs from public, anon, authenticated;

create table if not exists pipeline.aer_coverage_daily (
  day date not null,
  country text not null,
  eligible int not null,
  discovery_n int not null,
  extraction_n int not null,
  admission_n int not null,
  consumer_n int not null,
  open_p0 int not null default 0,
  open_p1 int not null default 0,
  open_p2 int not null default 0,
  new_findings int not null default 0,
  resolved_findings int not null default 0,
  reopened_findings int not null default 0,
  detail jsonb not null default '{}'::jsonb,
  run_id bigint,
  computed_at timestamptz not null default now(),
  primary key (day, country)
);
comment on table pipeline.aer_coverage_daily is 'CF-247 AER Phase B (mandate §13, B4): one row per Sydney day and country (AU, NZ, ALL) with the four AER measures as numerator over the eligible-provider denominator (source discovery, extraction, verified admission, consumer-resolvable), open P0/P1/P2 findings and the day''s new, resolved and reopened findings. The last run of the day stands as the daily snapshot. Counts providers, so one provider''s row count cannot hide another''s gap. Admin only; never read by the consumer API.';
alter table pipeline.aer_coverage_daily enable row level security;
revoke all on pipeline.aer_coverage_daily from public, anon, authenticated;

create table if not exists pipeline.aer_provider_coverage (
  provider_id uuid primary key,
  provider_name text,
  country text not null,
  provider_type text,
  eligible boolean not null default true,
  disposition text not null check (disposition in ('not_discovered', 'source_held', 'reader_failed', 'awaiting_layer4', 'active_verified', 'course_only',
                                                    'source_not_published_evidenced', 'not_applicable_evidenced')),
  discovery_state text not null,
  extraction_state text not null,
  admission_state text not null,
  consumer_resolvable boolean not null default false,
  priority_tier int not null,
  priority_rank int not null,
  courses_eligible int not null default 0,
  sources int not null default 0,
  sources_read int not null default 0,
  sources_failed int not null default 0,
  runs_held int not null default 0,
  runs_failed int not null default 0,
  matrix_active int not null default 0,
  matrix_other int not null default 0,
  course_req_active int not null default 0,
  course_req_proposed int not null default 0,
  layer4 jsonb not null default '{}'::jsonb,
  held_scopes jsonb not null default '[]'::jsonb,
  root_causes text[] not null default '{}',
  evidence jsonb not null default '{}'::jsonb,
  first_seen timestamptz not null default now(),
  disposition_since timestamptz not null default now(),
  previous_disposition text,
  last_run_id bigint,
  updated_at timestamptz not null default now()
);
comment on table pipeline.aer_provider_coverage is 'CF-247 AER catalogue-first gap queue (Platform Admin 2 Nov 2026 15:43): one row per AU/NZ provider that is or was eligible (catalogue.providers joined to ref.countries; active, published, enrols international), never taken from entry.providers, the pilot or the existing sources. Report disposition (not_discovered, source_held, reader_failed, awaiting_layer4, active_verified, course_only, source_not_published_evidenced, not_applicable_evidenced: report words, not admission statuses), separate discovery, extraction and admission states, the exact source, run and review ids, open root causes and the queue priority. Written hourly by security.aer_reconcile_v1 from database metadata only. Admin only; never read by the consumer API.';
alter table pipeline.aer_provider_coverage enable row level security;
revoke all on pipeline.aer_provider_coverage from public, anon, authenticated;
create index if not exists aer_provider_coverage_queue_idx on pipeline.aer_provider_coverage (eligible, priority_rank);

create table if not exists pipeline.aer_review_readiness (
  review_item_id uuid primary key,
  field_code text not null,
  entity_type text not null,
  entity_id uuid not null,
  provider_id uuid not null,
  readiness text not null check (readiness in ('review_ready', 'reader_correction_required', 'evidence_required', 'superseded_invalid', 'awaiting_human_review')),
  root_cause text references pipeline.aer_gap_root_causes(code),
  reason text,
  evidence jsonb not null default '{}'::jsonb,
  basis text not null check (basis in ('reconcile_default', 'classification')),
  source text,
  item_status text not null,
  classified_at timestamptz not null default now(),
  settled_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table pipeline.aer_review_readiness is 'CF-247 AER Layer 4 review readiness (Platform Admin Layer 4 recovery mandate 2 Nov 2026 16:33 §9): one row per pending AER Layer 4 item (entry_matrix_first_run, entry_matrix_change, course_entry_first_read) with its readiness class (review_ready, reader_correction_required, evidence_required, superseded_invalid, awaiting_human_review: report classes, not Layer 4 statuses), the root cause it shares with other items, reason and evidence. Rows start as awaiting_human_review (security.aer_reconcile_v1) until a classification is loaded (security.aer_review_readiness_load_v1). A settled item keeps its row and is never reopened. Admin only; never read by the consumer API.';
alter table pipeline.aer_review_readiness enable row level security;
revoke all on pipeline.aer_review_readiness from public, anon, authenticated;
create index if not exists aer_review_readiness_provider_idx on pipeline.aer_review_readiness (provider_id, readiness) where settled_at is null;

-- 3 the eligible providers and the current findings --------------------------------------------------------------------------------
create or replace function security.aer_eligible_v1() returns table(provider_id uuid, country text)
language sql stable security definer set search_path to '' as $function$
  -- Phase A baseline §1.1: country in aer.eligible_countries, active, published, enrols international students
  select p.id, k.iso_alpha2::text
    from catalogue.providers p join ref.countries k on k.id = p.country_id
   where k.iso_alpha2::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb)))
     and p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true
$function$;
revoke all on function security.aer_eligible_v1() from public, anon, authenticated;
comment on function security.aer_eligible_v1() is 'CF-247 AER Phase B: the eligible AU/NZ providers (Phase A baseline §1.1), the denominator of every AER measure.';

-- the root cause of a held or failed reading run, from the reason the reader stored (no page is read again)
create or replace function security.aer_run_cause_v1(p_state text, p_error text, p_completeness text) returns text
language sql immutable set search_path to '' as $function$
  select case
    when p_state = 'failed' then case
      when p_error ~* '^held_unparsed: not a country table: no country' then 'non_country_heading'
      when p_error ~* '^held_unparsed: not a country table' then 'requirement_type_columns'
      when p_error ~* '^held_incomplete' then 'reader_omission'
      when p_error ~* '^held_unparsed: no printed scale' then 'unscaled_column'
      when p_error ~* '^held_unparsed: PDF' then 'pdf_table_layout'
      when p_error ~* '^held:' then 'policy_hold'
      else 'extraction_failed' end
    when p_state = 'done' and p_completeness = 'incomplete' then 'reader_omission'
    when p_state = 'done' and p_completeness = 'unparsed' then 'manifest_unparsed'
  end
$function$;
revoke all on function security.aer_run_cause_v1(text, text, text) from public, anon, authenticated;

-- the manifest shape of a reading run
create or replace function security.aer_run_shape_v1(p_state text, p_error text, p_completeness text, p_basis text) returns text
language sql immutable set search_path to '' as $function$
  select case
    when p_error ~* '^held_unparsed: not a country table: no country' then 'qualification_page'
    when p_error ~* '^held_unparsed: not a country table' then 'requirement_table'
    when p_error ~* '^held_unparsed: PDF' or p_basis ~* 'pdf' then 'pdf_table'
    when p_error ~* '^held:' then 'policy_hold'
    when p_error ~* '^held_unparsed' or p_completeness = 'unparsed' then 'unparsed'
    when p_completeness in ('complete', 'incomplete') then 'country_table'
    when p_completeness = 'not_applicable' then 'no_table'
    else 'unknown' end
$function$;
revoke all on function security.aer_run_shape_v1(text, text, text, text) from public, anon, authenticated;

create or replace function security.aer_fingerprint_v1(p_provider uuid, p_source uuid, p_scope_kind text, p_scope_key text, p_level text, p_cause text) returns text
language sql immutable set search_path to '' as $function$
  select md5(concat_ws('|', p_provider::text, coalesce(p_source::text, ''), p_scope_kind, coalesce(p_scope_key, ''), coalesce(p_level, ''), p_cause))
$function$;
revoke all on function security.aer_fingerprint_v1(uuid, uuid, text, text, text, text) from public, anon, authenticated;
comment on function security.aer_fingerprint_v1(uuid, uuid, text, text, text, text) is 'CF-247 AER Phase B: the stable fingerprint of a gap: md5 of provider, source, scope kind, scope key, study level and root cause.';

-- every gap the existing data shows now (read-only): one row per fingerprint
create or replace function security.aer_current_findings_v1() returns table(fingerprint text, root_cause text, provider_id uuid, source_id uuid, scope_kind text,
  scope_key text, scope_label text, study_level text, evidence jsonb)
language sql stable security definer set search_path to '' as $function$
  with el as (select * from security.aer_eligible_v1()),
  src as (
    select s.id, s.provider_id, s.title, s.url, s.status, s.error, s.read_at, s.content_hash,
           r.id run_id, r.state, r.error run_error, r.content_hash run_hash, r.result->'completeness'->>'status' cstatus,
           coalesce(r.result->'completeness'->>'heading', substring(r.error from '\("([^"]{1,120})')) heading,
           (select k.iso_alpha2::text from ref.countries k where k.iso_alpha2 ~ '^[A-Z]{2}$'
               and lower(replace(coalesce(s.title, ''), '-', ' ')) like '%' || lower(k.name) || '%' order by length(k.name) desc limit 1) title_country
      from pipeline.entry_matrix_sources s
      left join lateral (select r1.* from pipeline.entry_matrix_runs r1 where r1.source_id = s.id order by r1.created_at desc limit 1) r on true),
  src_f as (
    -- a source whose fetch failed, a read source never extracted, a read source whose latest run is held or incomplete, a stale source
    select s.*, c.cause from src s
     cross join lateral (values
       (case when s.status = 'failed' then 'source_unreadable' end),
       (case when s.status = 'read' and s.run_id is null then 'not_extracted' end),
       (case when s.status = 'read' then security.aer_run_cause_v1(s.state, s.run_error, s.cstatus) end),
       (case when s.status = 'read' and s.read_at < now() - make_interval(days => security.pipeline_num_v1('aer.stale_source_days', 90)::int) then 'stale_source' end)) c(cause)
     where c.cause is not null),
  src_rows as (
    select f.cause, f.provider_id, f.id source_id,
           case when f.cause = 'non_country_heading' then 'qualification' when f.title_country is not null then 'country' else 'source' end scope_kind,
           case when f.cause = 'non_country_heading' then btrim(regexp_replace(lower(coalesce(f.heading, f.title, '')), '[^a-z0-9]+', ' ', 'g'))
                when f.title_country is not null then f.title_country else f.id::text end scope_key,
           coalesce(case when f.cause = 'non_country_heading' then f.heading end, f.title, f.url) scope_label,
           jsonb_build_object('source_title', f.title, 'url', f.url, 'source_status', f.status, 'source_error', left(f.error, 200), 'read_at', f.read_at,
                              'run_id', f.run_id, 'run_state', f.state, 'run_error', left(f.run_error, 300), 'completeness', f.cstatus) evidence
      from src_f f),
  prov_rows as (
    -- an eligible provider with no source
    select 'no_source' cause, e.provider_id, null::uuid source_id, 'provider' scope_kind, null::text scope_key, e.country scope_label, null::text study_level,
           jsonb_build_object('country', e.country) evidence
      from el e where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)
    union all
    -- extracted requirements waiting for Layer 4
    select 'awaiting_layer4', w.provider_id, null, 'provider', null, null, null,
           jsonb_build_object('matrix_proposed', sum(w.m), 'course_proposed', sum(w.c))
      from (select m.provider_id, count(*) m, 0 c from catalogue.provider_entry_matrix m where m.status = 'proposed' group by 1
            union all
            select c.provider_id, 0, count(*) from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where x.status = 'proposed' group by 1) w
     group by w.provider_id
    union all
    -- course entry reads held whole (course outcome register), by study level
    select 'course_read_held', o.provider_id, null, 'study_level', coalesce(l.short_code, 'none'), coalesce(l.short_code, 'none'), coalesce(l.short_code, 'none'),
           jsonb_build_object('courses', count(*), 'sample', (array_agg(jsonb_build_object('course_id', o.course_id, 'reason', left(o.read_reason, 160)) order by o.course_id))[1:5])
      from pipeline.aer_course_outcomes o join catalogue.courses c on c.id = o.course_id left join ref.study_levels l on l.id = c.study_level_id
     where o.outcome = 'source_unreadable'
     group by o.provider_id, l.short_code
    union all
    -- a defect named on pending Layer 4 items: one finding per provider and root cause, linked to every item (mandate 16:33 §9)
    select z.root_cause, z.provider_id, null, 'review_items', z.readiness, z.readiness, null,
           jsonb_build_object('items', count(*), 'sample', (array_agg(z.review_item_id order by z.review_item_id))[1:20])
      from pipeline.aer_review_readiness z
     where z.settled_at is null and z.root_cause is not null and z.readiness in ('reader_correction_required', 'evidence_required', 'superseded_invalid')
     group by z.root_cause, z.provider_id, z.readiness
    union all
    -- P0: active (consumer-resolvable) rows without evidence or quote
    select 'consumer_unevidenced', z.provider_id, null, 'provider', null, null, null, jsonb_build_object('rows', count(*), 'sample', (array_agg(z.id order by z.id))[1:20])
      from (select m.provider_id, m.id from catalogue.provider_entry_matrix m where m.status = 'active' and (m.evidence_id is null or btrim(coalesce(m.quote, '')) = '')
            union all
            select c.provider_id, x.id from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
             where x.status = 'active' and (x.evidence_id is null or btrim(coalesce(x.quote, '')) = '')) z
     group by z.provider_id
    union all
    -- P0: active AI-read rows whose Layer 4 item is not approved
    select 'consumer_unadmitted', z.provider_id, null, 'provider', null, null, null, jsonb_build_object('rows', count(*), 'sample', (array_agg(z.id order by z.id))[1:20])
      from (select m.provider_id, m.id from catalogue.provider_entry_matrix m
              left join pipeline.entry_matrix_runs r on r.id = m.run_id left join pipeline.layer4_review_items li on li.id = r.review_item_id
             where m.status = 'active' and coalesce(m.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')
            union all
            select c.provider_id, x.id from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
              left join pipeline.layer4_review_items li on li.id = nullif(x.provenance->>'review_item_id', '')::uuid
             where x.status = 'active' and coalesce(x.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')) z
     group by z.provider_id
    union all
    -- P0: active numeric minimum without its scale
    select 'consumer_number_without_scale', z.provider_id, null, 'provider', null, null, null, jsonb_build_object('rows', count(*), 'sample', (array_agg(z.id order by z.id))[1:20])
      from (select m.provider_id, m.id from catalogue.provider_entry_matrix m where m.status = 'active' and m.min_value is not null and coalesce(m.grade_scale, 'none') = 'none'
            union all
            select c.provider_id, x.id from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
             where x.status = 'active' and x.min_value is not null and coalesce(x.grade_scale, 'none') = 'none') z
     group by z.provider_id),
  allr as (
    select cause, provider_id, source_id, scope_kind, scope_key, scope_label, null::text study_level, evidence from src_rows
    union all
    select cause, provider_id, source_id, scope_kind, scope_key, scope_label, study_level, evidence from prov_rows)
  select distinct on (1) security.aer_fingerprint_v1(a.provider_id, a.source_id, a.scope_kind, a.scope_key, a.study_level, a.cause),
         a.cause, a.provider_id, a.source_id, a.scope_kind, a.scope_key, a.scope_label, a.study_level, a.evidence
    from allr a
   order by 1
$function$;
revoke all on function security.aer_current_findings_v1() from public, anon, authenticated;
comment on function security.aer_current_findings_v1() is 'CF-247 AER Phase B: every AER gap the existing data shows now (sources, reading runs and their stored completeness, proposed rows, the course outcome register, active rows), one row per fingerprint. Read-only; no page is read and no AI is called.';

-- the evidence that a finding no longer reproduced is resolved (null: keep it open; unknown is never complete)
create or replace function security.aer_closure_evidence_v1(p_cause text, p_provider uuid, p_source uuid, p_level text, p_scope_kind text default null, p_scope_key text default null) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare r record; v_n bigint;
begin
  if p_scope_kind = 'review_items' then
    -- no pending item of this provider is classified with this defect any more (settled, reclassified or ready)
    select count(*) into v_n from pipeline.aer_review_readiness z
     where z.provider_id = p_provider and z.root_cause = p_cause and z.readiness = p_scope_key and z.settled_at is null;
    return case when v_n = 0 then jsonb_build_object('basis', 'no pending review item with this defect', 'checked_at', now()) end;
  end if;
  if p_cause in ('non_country_heading', 'requirement_type_columns', 'reader_omission', 'unscaled_column', 'pdf_table_layout', 'policy_hold',
                 'extraction_failed', 'manifest_unparsed', 'not_extracted') then
    -- a later run of the same source finished, and its read is checked complete against the source's own table manifest
    -- (or the page has no table and rows were read)
    select r1.id, r1.state, r1.content_hash, r1.result->'completeness' c, jsonb_array_length(coalesce(r1.result->'rows', '[]'::jsonb)) n_rows
      into r from pipeline.entry_matrix_runs r1 where r1.source_id = p_source order by r1.created_at desc limit 1;
    if r.id is null or r.state <> 'done' then return null; end if;
    if coalesce(r.c->>'status', '') = 'complete' or (coalesce(r.c->>'status', '') = 'not_applicable' and r.n_rows > 0) then
      return jsonb_build_object('basis', 'later run checked against the source manifest', 'run_id', r.id, 'content_hash', r.content_hash,
        'completeness', r.c->>'status', 'expected', r.c->'expected', 'matched', r.c->'matched', 'rows_read', r.n_rows,
        'active_rows', (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'active'));
    end if;
    return null;
  elsif p_cause = 'source_unreadable' then
    select s.status, s.read_at into r from pipeline.entry_matrix_sources s where s.id = p_source;
    return case when r.status = 'read' then jsonb_build_object('basis', 'source now read', 'read_at', r.read_at) end;
  elsif p_cause = 'stale_source' then
    select s.status, s.read_at into r from pipeline.entry_matrix_sources s where s.id = p_source;
    return case when r.read_at >= now() - make_interval(days => security.pipeline_num_v1('aer.stale_source_days', 90)::int)
                then jsonb_build_object('basis', 'source read again', 'read_at', r.read_at) end;
  elsif p_cause = 'no_source' then
    select count(*) into v_n from pipeline.entry_matrix_sources s where s.provider_id = p_provider;
    return case when v_n > 0 then jsonb_build_object('basis', 'source recorded', 'sources', v_n) end;
  elsif p_cause = 'awaiting_layer4' then
    select (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = p_provider and m.status = 'proposed')
         + (select count(*) from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where c.provider_id = p_provider and x.status = 'proposed') into v_n;
    return case when v_n = 0 then jsonb_build_object('basis', 'nothing waits for Layer 4', 'proposed', 0) end;
  elsif p_cause = 'course_read_held' then
    select count(*) into v_n from pipeline.aer_course_outcomes o join catalogue.courses c on c.id = o.course_id left join ref.study_levels l on l.id = c.study_level_id
     where o.provider_id = p_provider and o.outcome = 'source_unreadable' and coalesce(l.short_code, 'none') = coalesce(p_level, 'none');
    return case when v_n = 0 then jsonb_build_object('basis', 'no course read held at this level', 'held', 0) end;
  elsif p_cause in ('consumer_unevidenced', 'consumer_unadmitted', 'consumer_number_without_scale') then
    -- the current findings no longer hold the provider for this check: no offending active row
    return jsonb_build_object('basis', 'no offending active row', 'checked_at', now());
  end if;
  return null;
end $function$;
revoke all on function security.aer_closure_evidence_v1(text, uuid, uuid, text, text, text) from public, anon, authenticated;
comment on function security.aer_closure_evidence_v1(text, uuid, uuid, text, text, text) is 'CF-247 AER Phase B: the evidence that closes a finding that is no longer found (mandate §12: auto-close only where verified evidence proves resolution); null keeps it open.';

-- 4 the four measures, by country and in all ------------------------------------------------------------------------------------------
create or replace function security.aer_measures_v1() returns table(country text, eligible int, discovery_n int, discovered_any int, extraction_n int, admission_n int,
  active_any int, consumer_n int, detail jsonb)
language sql stable security definer set search_path to '' as $function$
  with el as (select * from security.aer_eligible_v1()),
  pf as (
    select e.provider_id, e.country,
           exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id) disc_any,
           exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id and s.status = 'read') disc,
           exists (select 1 from pipeline.aer_gap_findings f join pipeline.aer_gap_root_causes rc on rc.code = f.root_cause
                    where f.provider_id = e.provider_id and f.state <> 'resolved' and rc.measure = 'extraction') ext_gap,
           (exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = e.provider_id and m.status = 'active')
            or exists (select 1 from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where c.provider_id = e.provider_id and x.status = 'active')) act,
           (exists (select 1 from catalogue.provider_entry_matrix m where m.provider_id = e.provider_id and m.status = 'proposed')
            or exists (select 1 from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where c.provider_id = e.provider_id and x.status = 'proposed')) prop,
           exists (select 1 from pipeline.aer_course_outcomes o where o.provider_id = e.provider_id and o.outcome in ('admitted_course', 'admitted_provider')) cons,
           exists (select 1 from pipeline.aer_gap_findings f where f.provider_id = e.provider_id and f.state <> 'resolved' and f.severity = 'P0') p0
      from el e),
  g as (select coalesce(c, 'ALL') country, count(*) eligible,
               count(*) filter (where disc) discovery_n, count(*) filter (where disc_any) discovered_any,
               count(*) filter (where disc and not ext_gap) extraction_n,
               count(*) filter (where act and not prop) admission_n, count(*) filter (where act) active_any,
               count(*) filter (where cons and not p0) consumer_n
          from (select pf.*, pf.country c from pf) x group by grouping sets ((c), ()))
  select g.country, g.eligible::int, g.discovery_n::int, g.discovered_any::int, g.extraction_n::int, g.admission_n::int, g.active_any::int, g.consumer_n::int,
         jsonb_build_object(
           'countries_published', (select count(distinct m.country_code) from catalogue.provider_entry_matrix m join el on el.provider_id = m.provider_id
                                    where m.status = 'active' and (g.country = 'ALL' or el.country = g.country)),
           'qualifications_active', (select count(distinct lower(m.qualification_name)) from catalogue.provider_entry_matrix m join el on el.provider_id = m.provider_id
                                      where m.status = 'active' and (g.country = 'ALL' or el.country = g.country)),
           'matrix_rows', (select jsonb_build_object('active', count(*) filter (where m.status = 'active'), 'proposed', count(*) filter (where m.status = 'proposed'))
                             from catalogue.provider_entry_matrix m join el on el.provider_id = m.provider_id where g.country = 'ALL' or el.country = g.country),
           'postgraduate', (select jsonb_build_object('active_rows', count(*) filter (where x.status = 'active'), 'proposed_rows', count(*) filter (where x.status = 'proposed'),
                                     'courses_active', count(distinct x.course_id) filter (where x.status = 'active'))
                              from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id join ref.study_levels l on l.id = c.study_level_id
                              join el on el.provider_id = c.provider_id
                             where l.short_code in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.postgraduate_levels'), '[]'::jsonb)))
                               and (g.country = 'ALL' or el.country = g.country)),
           'layer4_pending', (select coalesce(jsonb_object_agg(z.field_code, z.n), '{}'::jsonb) from (select li.field_code, count(*) n from pipeline.layer4_review_items li
                                where li.status = 'pending' and li.field_code in ('course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change') group by 1) z),
           'sources', (select jsonb_build_object('total', count(*), 'read', count(*) filter (where s.status = 'read'), 'failed', count(*) filter (where s.status = 'failed'),
                                                 'last_read', max(s.read_at))
                         from pipeline.entry_matrix_sources s join el on el.provider_id = s.provider_id where g.country = 'ALL' or el.country = g.country),
           'definitions', jsonb_build_object(
             'discovery', 'eligible providers with an official AER source read', 'extraction', 'of those, providers with no open extraction finding',
             'admission', 'eligible providers with active requirements and none waiting for Layer 4', 'consumer', 'eligible providers with a course that resolves to an admitted requirement and no open P0'))
    from g
$function$;
revoke all on function security.aer_measures_v1() from public, anon, authenticated;
comment on function security.aer_measures_v1() is 'CF-247 AER Phase B (mandate §13): the four AER measures over the eligible providers, by country and in all, with their sub-figures. Read-only.';

-- 4b the catalogue-first gap queue: every eligible provider's report disposition, from database metadata only -------------------------
create or replace function security.aer_provider_states_v1() returns table(provider_id uuid, provider_name text, country text, provider_type text, disposition text,
  discovery_state text, extraction_state text, admission_state text, consumer_resolvable boolean, priority_tier int, priority_rank int, courses_eligible int,
  sources int, sources_read int, sources_failed int, runs_held int, runs_failed int, matrix_active int, matrix_other int, course_req_active int, course_req_proposed int,
  layer4 jsonb, held_scopes jsonb, root_causes text[], evidence jsonb)
language sql stable security definer set search_path to '' as $function$
  with el as (select e.provider_id, e.country from security.aer_eligible_v1() e),
  pv as (select el.provider_id, el.country, coalesce(p.display_name, p.short_name, p.canonical_name) pname, t.code ptype
           from el join catalogue.providers p on p.id = el.provider_id left join ref.provider_types t on t.id = p.provider_type_id),
  src as (
    select s.provider_id, count(*) n, count(*) filter (where s.status = 'read') nread, count(*) filter (where s.status = 'failed') nfail,
           count(*) filter (where s.status = 'read' and r.state = 'failed' and coalesce(r.error, '') ~* '^held') nheld,
           count(*) filter (where s.status = 'read' and ((r.state = 'failed' and coalesce(r.error, '') !~* '^held') or r.id is null)) nrfail,
           count(*) filter (where s.status = 'read' and r.state = 'done') ndone,
           count(*) filter (where r.result->>'outcome' = 'no_requirements_table' and li.status in ('approved', 'edited_approved')) nnotable,
           count(*) filter (where li.status = 'pending') l4pend,
           count(*) filter (where li.status is not null and li.status not in ('pending', 'approved', 'edited_approved', 'superseded')) l4other,
           coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'url', s.url, 'status', s.status, 'run_id', r.id, 'run_state', r.state,
                     'run_error', left(r.error, 160), 'review_item_id', li.id, 'review_status', li.status) order by s.rank, s.title), '[]'::jsonb) ev
      from pipeline.entry_matrix_sources s
      join el on el.provider_id = s.provider_id
      left join lateral (select r1.id, r1.state, r1.error, r1.result, r1.review_item_id from pipeline.entry_matrix_runs r1 where r1.source_id = s.id order by r1.created_at desc limit 1) r on true
      left join pipeline.layer4_review_items li on li.id = r.review_item_id
     group by s.provider_id),
  mx as (select m.provider_id, count(*) filter (where m.status = 'active') act, count(*) filter (where m.status <> 'active') other,
                count(*) filter (where m.status = 'proposed') prop
           from catalogue.provider_entry_matrix m join el on el.provider_id = m.provider_id group by 1),
  -- course-level requirements of the provider's eligible courses (active, published)
  cr as (select c.provider_id, count(*) filter (where x.status = 'active') act, count(*) filter (where x.status = 'proposed') prop
           from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id join el on el.provider_id = c.provider_id
          where c.lifecycle_status = 'active' and c.publication_status = 'published' group by 1),
  cc as (select c.provider_id, count(*) n from catalogue.courses c join el on el.provider_id = c.provider_id
          where c.lifecycle_status = 'active' and c.publication_status = 'published' and c.open_to_international is not false group by 1),
  co as (select o.provider_id, bool_or(o.outcome in ('admitted_course', 'admitted_provider')) cons, count(*) filter (where o.outcome = 'awaiting_review') aw
           from pipeline.aer_course_outcomes o join el on el.provider_id = o.provider_id group by 1),
  fd as (select g.provider_id, array_agg(distinct g.root_cause order by g.root_cause) causes, bool_or(g.severity = 'P0') p0,
                coalesce(jsonb_agg(distinct jsonb_build_object('kind', g.scope_kind, 'scope', g.scope_label)) filter (where g.scope_kind in ('country', 'qualification')), '[]'::jsonb) scopes
           from pipeline.aer_gap_findings g join el on el.provider_id = g.provider_id where g.state <> 'resolved' group by 1),
  na as (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.not_applicable_provider_types'), '[]'::jsonb)) code),
  pt as (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.priority_provider_types'), '[]'::jsonb)) code),
  d as (
    select pv.*, coalesce(src.n, 0) n, coalesce(src.nread, 0) nread, coalesce(src.nfail, 0) nfail, coalesce(src.nheld, 0) nheld, coalesce(src.nrfail, 0) nrfail,
           coalesce(src.ndone, 0) ndone, coalesce(src.nnotable, 0) nnotable, coalesce(src.l4pend, 0) l4pend, coalesce(src.l4other, 0) l4other, coalesce(src.ev, '[]'::jsonb) ev,
           coalesce(mx.act, 0) mact, coalesce(mx.other, 0) mother, coalesce(mx.prop, 0) mprop, coalesce(cr.act, 0) cact, coalesce(cr.prop, 0) cprop,
           coalesce(cc.n, 0) courses, coalesce(co.aw, 0) caw, coalesce(co.cons, false) and not coalesce(fd.p0, false) cons,
           coalesce(fd.causes, '{}') causes, coalesce(fd.scopes, '[]'::jsonb) scopes,
           case when pv.ptype in (select code from pt) then 1 else 2 end tier
      from pv left join src on src.provider_id = pv.provider_id left join mx on mx.provider_id = pv.provider_id left join cr on cr.provider_id = pv.provider_id
      left join cc on cc.provider_id = pv.provider_id left join co on co.provider_id = pv.provider_id left join fd on fd.provider_id = pv.provider_id),
  x as (
    select d.*, case
      when d.n = 0 then case
        when d.cact > 0 then 'course_only'                                   -- no matrix source, but course-level requirements are active
        when d.cprop > 0 or d.caw > 0 or d.mprop > 0 then 'awaiting_layer4'
        when d.mact > 0 then 'active_verified'
        when d.ptype in (select code from na) then 'not_applicable_evidenced' -- the register type is the evidence (setting, empty by default)
        else 'not_discovered' end
      when d.nfail = d.n or d.nrfail > 0 then 'reader_failed'
      when d.nheld > 0 then 'source_held'
      when d.mprop > 0 or d.cprop > 0 or d.l4pend > 0 or d.caw > 0 then 'awaiting_layer4'
      when d.mact > 0 then 'active_verified'
      when d.cact > 0 then 'course_only'
      when d.nnotable > 0 then 'source_not_published_evidenced'           -- an approved Layer 4 "no requirements table" note
      else 'reader_failed' end disp                                         -- read and finished, but nothing extracted and no evidence why
      from d)
  select x.provider_id, x.pname, x.country, x.ptype, x.disp,
         case when x.n = 0 then 'not_discovered' when x.nread > 0 then 'source_read' else 'source_unreadable' end,
         case when x.n = 0 then 'none' when x.nrfail > 0 or x.nfail = x.n then 'failed' when x.nheld > 0 then 'held' when x.ndone > 0 then 'complete' else 'none' end,
         case when (x.mact > 0 or x.cact > 0) and (x.mprop > 0 or x.cprop > 0 or x.l4pend > 0 or x.caw > 0) then 'active_and_awaiting'
              when x.mact > 0 or x.cact > 0 then 'active' when x.mprop > 0 or x.cprop > 0 or x.l4pend > 0 or x.caw > 0 then 'awaiting' else 'none' end,
         x.cons, x.tier,
         (row_number() over (order by x.tier,
            -- display order, not an operational value: held and failed sources sit with the providers still to be discovered
            array_position(array['source_held', 'reader_failed', 'not_discovered', 'awaiting_layer4', 'course_only', 'source_not_published_evidenced',
                                 'not_applicable_evidenced', 'active_verified'], x.disp), x.courses desc, x.pname, x.provider_id))::int,
         x.courses::int, x.n::int, x.nread::int, x.nfail::int, x.nheld::int, x.nrfail::int, x.mact::int, x.mother::int, x.cact::int, x.cprop::int,
         jsonb_build_object('matrix_pending', x.l4pend, 'matrix_returned_or_rejected', x.l4other, 'course_awaiting_review', x.caw),
         x.scopes, x.causes, jsonb_build_object('sources', x.ev)
    from x
$function$;
revoke all on function security.aer_provider_states_v1() from public, anon, authenticated;
comment on function security.aer_provider_states_v1() is 'CF-247 AER catalogue-first gap queue (Platform Admin 2 Nov 2026 15:43): every eligible provider with its report disposition, discovery/extraction/admission states, exact source, run and review ids and priority. Database metadata only; no crawl.';

-- the check the Platform Admin runs after activation: the stored queue against a fresh catalogue anti-join
create or replace function security.aer_coverage_verify_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  with fresh as (
    select p.id provider_id, k.iso_alpha2::text country,
           not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = p.id) no_source
      from catalogue.providers p join ref.countries k on k.id = p.country_id
     where k.iso_alpha2 in ('AU', 'NZ') and p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true),
  snap as (select c.provider_id, c.country, c.disposition, c.discovery_state from pipeline.aer_provider_coverage c where c.eligible)
  select jsonb_build_object(
    'run_id', (select max(r.id) from pipeline.aer_reconcile_runs r), 'checked_at', now(),
    'fresh', (select jsonb_build_object('AU', count(*) filter (where country = 'AU'), 'NZ', count(*) filter (where country = 'NZ'), 'no_source', count(*) filter (where no_source)) from fresh),
    'stored', (select jsonb_build_object('AU', count(*) filter (where country = 'AU'), 'NZ', count(*) filter (where country = 'NZ'),
                                         'not_discovered_state', count(*) filter (where discovery_state = 'not_discovered')) from snap),
    'missing_from_queue', (select coalesce(jsonb_agg(f.provider_id), '[]'::jsonb) from fresh f where not exists (select 1 from snap s where s.provider_id = f.provider_id)),
    'not_eligible_now', (select coalesce(jsonb_agg(s.provider_id), '[]'::jsonb) from snap s where not exists (select 1 from fresh f where f.provider_id = s.provider_id)),
    'discovery_mismatch', (select coalesce(jsonb_agg(f.provider_id), '[]'::jsonb) from fresh f join snap s on s.provider_id = f.provider_id
                            where f.no_source <> (s.discovery_state = 'not_discovered')),
    'ok', not exists (select 1 from fresh f where not exists (select 1 from snap s where s.provider_id = f.provider_id))
          and not exists (select 1 from snap s where not exists (select 1 from fresh f where f.provider_id = s.provider_id))
          and not exists (select 1 from fresh f join snap s on s.provider_id = f.provider_id where f.no_source <> (s.discovery_state = 'not_discovered')))
$function$;
revoke all on function security.aer_coverage_verify_v1() from public, anon, authenticated;
comment on function security.aer_coverage_verify_v1() is 'CF-247 AER (Platform Admin 2 Nov 2026 15:43 §5): compares the stored gap queue (pipeline.aer_provider_coverage, last run) with a fresh catalogue-to-AER anti-join written out independently of the reconcile (AU/NZ literal, as the Platform Admin''s rule states it); ok is true when no provider is missing, extra or differently discovered. Read-only.';

-- 5 the reconciliation --------------------------------------------------------------------------------------------------------------
create or replace function security.aer_reconcile_v1(p_limit int default null) returns jsonb
language plpgsql security definer set search_path to '' set statement_timeout to '120s' as $function$
declare v_run bigint; v_lim int := coalesce(p_limit, security.pipeline_num_v1('batch.aer_reconcile', 5000)::int);
        v_found int; v_new int := 0; v_obs int := 0; v_res int := 0; v_reo int := 0; v_man int; v_day date; f record; v_ev jsonb; v_p0 int;
        v_alerts boolean := coalesce((security.toolset_setting('pipeline', 'aer.alerts_enabled') #>> '{}')::boolean, true);
        v_today int; v_prev int; v_reg int := security.pipeline_num_v1('aer.regression_alert_providers', 1)::int; v_out jsonb; v_week date; v_weekly text;
        v_first boolean; v_left jsonb; v_joined jsonb; v_qn int; v_pop jsonb;
begin
  -- single flight: a run already in progress is not started again
  if not pg_try_advisory_xact_lock(hashtext('aer-reconcile')) then  -- fixed: lock key
    return jsonb_build_object('skipped', 'another aer-reconcile run is in progress');
  end if;
  insert into pipeline.aer_reconcile_runs default values returning id into v_run;
  v_day := (now() at time zone 'Australia/Sydney')::date;  -- fixed: the mandate's reporting time zone

  -- 1 manifests: one per source and content hash, from the run already stored
  insert into pipeline.aer_source_manifests(source_id, provider_id, content_hash, run_id, run_state, basis, shape, heading, scope_country, scope_label,
                                            expected_cells, matched_cells, omitted_cells, omitted_columns, sections, reason)
  select s.id, s.provider_id, r.content_hash, r.id, r.state, coalesce(r.result->'completeness'->>'basis', r.result->>'page_basis', 'none'),
         security.aer_run_shape_v1(r.state, r.error, r.result->'completeness'->>'status', coalesce(r.result->>'page_basis', '')),
         left(coalesce(r.result->'completeness'->>'heading', substring(r.error from '\("([^"]{1,200})')), 200),
         (select k.iso_alpha2::text from ref.countries k where k.iso_alpha2 ~ '^[A-Z]{2}$' and lower(replace(coalesce(s.title, ''), '-', ' ')) like '%' || lower(k.name) || '%'
           order by length(k.name) desc limit 1),
         left(s.title, 200),
         nullif(r.result->'completeness'->>'expected', '')::int, nullif(r.result->'completeness'->>'matched', '')::int,
         jsonb_array_length(coalesce(r.result->'completeness'->'omitted', '[]'::jsonb)), coalesce(r.result->'completeness'->'omitted_columns', '[]'::jsonb),
         jsonb_build_object('omitted', coalesce(r.result->'completeness'->'omitted', '[]'::jsonb), 'unexplained', jsonb_array_length(coalesce(r.result->'completeness'->'unexplained', '[]'::jsonb)),
                            'completeness', r.result->'completeness'->>'status', 'rows_read', jsonb_array_length(coalesce(r.result->'rows', '[]'::jsonb))),
         left(coalesce(r.error, r.result->'completeness'->>'reason'), 400)
    from pipeline.entry_matrix_sources s
    join lateral (select r1.* from pipeline.entry_matrix_runs r1 where r1.source_id = s.id order by r1.created_at desc limit 1) r on true
   where r.state in ('done', 'failed')
  on conflict (source_id, content_hash) do update set run_id = excluded.run_id, run_state = excluded.run_state, basis = excluded.basis, shape = excluded.shape,
         heading = excluded.heading, expected_cells = excluded.expected_cells, matched_cells = excluded.matched_cells, omitted_cells = excluded.omitted_cells,
         omitted_columns = excluded.omitted_columns, sections = excluded.sections, reason = excluded.reason, computed_at = now()
   where aer_source_manifests.run_id is distinct from excluded.run_id or aer_source_manifests.run_state is distinct from excluded.run_state;
  get diagnostics v_man = row_count;

  -- 1b Layer 4 review readiness: every pending AER item has a row (awaiting_human_review until classified); settled items are closed, never reopened
  insert into pipeline.aer_review_readiness(review_item_id, field_code, entity_type, entity_id, provider_id, readiness, basis, item_status)
  select li.id, li.field_code, li.entity_type, li.entity_id, r.provider_id, 'awaiting_human_review', 'reconcile_default', li.status
    from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
   where li.status = 'pending' and li.field_code in ('entry_matrix_first_run', 'entry_matrix_change')
  union
  select li.id, li.field_code, li.entity_type, li.entity_id, o.provider_id, 'awaiting_human_review', 'reconcile_default', li.status
    from pipeline.aer_course_outcomes o join pipeline.layer4_review_items li on li.id = o.review_item_id
   where o.outcome = 'awaiting_review' and li.status = 'pending' and li.field_code = 'course_entry_first_read'
  on conflict (review_item_id) do nothing;
  update pipeline.aer_review_readiness z set item_status = li.status, settled_at = now(), updated_at = now()
    from pipeline.layer4_review_items li where li.id = z.review_item_id and z.settled_at is null and li.status <> 'pending';

  -- 2 the current findings
  if to_regclass('pg_temp.aer_cur') is null then
    create temp table aer_cur (fingerprint text primary key, root_cause text, provider_id uuid, source_id uuid, scope_kind text, scope_key text,
                               scope_label text, study_level text, evidence jsonb) on commit drop;
  end if;
  truncate pg_temp.aer_cur;
  insert into pg_temp.aer_cur select * from security.aer_current_findings_v1();
  get diagnostics v_found = row_count;

  -- 3a found again after it was resolved: reopened
  for f in update pipeline.aer_gap_findings g set state = 'reopened', resolved_at = null, reopen_count = g.reopen_count + 1, last_seen = now(), evidence = c.evidence,
                  last_run_id = v_run, closure_evidence = null
             from pg_temp.aer_cur c where c.fingerprint = g.fingerprint and g.state = 'resolved'
           returning g.id, g.fingerprint loop
    insert into pipeline.aer_gap_events(finding_id, fingerprint, event, run_id, detail) values (f.id, f.fingerprint, 'reopened', v_run, '{}'::jsonb);
    v_reo := v_reo + 1;
  end loop;
  -- 3b still there: observed (no event; nothing duplicated)
  update pipeline.aer_gap_findings g set last_seen = now(), evidence = c.evidence, last_run_id = v_run, scope_label = c.scope_label
    from pg_temp.aer_cur c where c.fingerprint = g.fingerprint and g.state in ('open', 'reopened') and g.last_run_id is distinct from v_run;
  get diagnostics v_obs = row_count;
  -- 3c new: opened (P0 first; at most batch.aer_reconcile a run)
  for f in insert into pipeline.aer_gap_findings(fingerprint, root_cause, provider_id, source_id, scope_kind, scope_key, scope_label, study_level, severity, evidence,
                                                 owner_role, next_action, last_run_id)
           select c.fingerprint, c.root_cause, c.provider_id, c.source_id, c.scope_kind, c.scope_key, c.scope_label, c.study_level, rc.severity, c.evidence,
                  rc.owner_role, rc.next_action, v_run
             from pg_temp.aer_cur c join pipeline.aer_gap_root_causes rc on rc.code = c.root_cause
            where not exists (select 1 from pipeline.aer_gap_findings g where g.fingerprint = c.fingerprint)
            order by rc.severity, c.root_cause, c.fingerprint
            limit greatest(v_lim, 0)
           returning id, fingerprint loop
    insert into pipeline.aer_gap_events(finding_id, fingerprint, event, run_id) values (f.id, f.fingerprint, 'opened', v_run);
    v_new := v_new + 1;
  end loop;
  -- 3d no longer found: resolved only with closure evidence
  for f in select g.id, g.fingerprint, g.root_cause, g.provider_id, g.source_id, g.study_level, g.scope_kind, g.scope_key from pipeline.aer_gap_findings g
            where g.state in ('open', 'reopened') and not exists (select 1 from pg_temp.aer_cur c where c.fingerprint = g.fingerprint) loop
    v_ev := security.aer_closure_evidence_v1(f.root_cause, f.provider_id, f.source_id, f.study_level, f.scope_kind, f.scope_key);
    if v_ev is not null then
      update pipeline.aer_gap_findings set state = 'resolved', resolved_at = now(), closure_evidence = v_ev, last_run_id = v_run where id = f.id;
      insert into pipeline.aer_gap_events(finding_id, fingerprint, event, run_id, detail) values (f.id, f.fingerprint, 'resolved', v_run, v_ev);
      v_res := v_res + 1;
    end if;
  end loop;

  -- 4 the daily snapshot (the last run of the day stands)
  insert into pipeline.aer_coverage_daily(day, country, eligible, discovery_n, extraction_n, admission_n, consumer_n, open_p0, open_p1, open_p2,
                                          new_findings, resolved_findings, reopened_findings, detail, run_id, computed_at)
  select v_day, m.country, m.eligible, m.discovery_n, m.extraction_n, m.admission_n, m.consumer_n,
         (select count(*) from pipeline.aer_gap_findings g join security.aer_eligible_v1() e on e.provider_id = g.provider_id
           where g.state <> 'resolved' and g.severity = 'P0' and (m.country = 'ALL' or e.country = m.country)),
         (select count(*) from pipeline.aer_gap_findings g join security.aer_eligible_v1() e on e.provider_id = g.provider_id
           where g.state <> 'resolved' and g.severity = 'P1' and (m.country = 'ALL' or e.country = m.country)),
         (select count(*) from pipeline.aer_gap_findings g join security.aer_eligible_v1() e on e.provider_id = g.provider_id
           where g.state <> 'resolved' and g.severity = 'P2' and (m.country = 'ALL' or e.country = m.country)),
         (select count(*) from pipeline.aer_gap_events x join pipeline.aer_gap_findings g on g.id = x.finding_id join security.aer_eligible_v1() e on e.provider_id = g.provider_id
           where x.event = 'opened' and (x.at at time zone 'Australia/Sydney')::date = v_day and (m.country = 'ALL' or e.country = m.country)),
         (select count(*) from pipeline.aer_gap_events x join pipeline.aer_gap_findings g on g.id = x.finding_id join security.aer_eligible_v1() e on e.provider_id = g.provider_id
           where x.event = 'resolved' and (x.at at time zone 'Australia/Sydney')::date = v_day and (m.country = 'ALL' or e.country = m.country)),
         (select count(*) from pipeline.aer_gap_events x join pipeline.aer_gap_findings g on g.id = x.finding_id join security.aer_eligible_v1() e on e.provider_id = g.provider_id
           where x.event = 'reopened' and (x.at at time zone 'Australia/Sydney')::date = v_day and (m.country = 'ALL' or e.country = m.country)),
         m.detail || jsonb_build_object('discovered_any', m.discovered_any, 'active_any', m.active_any), v_run, now()
    from security.aer_measures_v1() m
  on conflict (day, country) do update set eligible = excluded.eligible, discovery_n = excluded.discovery_n, extraction_n = excluded.extraction_n,
         admission_n = excluded.admission_n, consumer_n = excluded.consumer_n, open_p0 = excluded.open_p0, open_p1 = excluded.open_p1, open_p2 = excluded.open_p2,
         new_findings = excluded.new_findings, resolved_findings = excluded.resolved_findings, reopened_findings = excluded.reopened_findings,
         detail = excluded.detail, run_id = excluded.run_id, computed_at = excluded.computed_at;

  -- 4b the catalogue-first gap queue and the population against the baseline (exact providers that joined or left)
  v_first := not exists (select 1 from pipeline.aer_provider_coverage);
  if to_regclass('pg_temp.aer_prov') is null then
    create temp table aer_prov on commit drop as select * from security.aer_provider_states_v1() limit 0;
  end if;
  truncate pg_temp.aer_prov;
  insert into pg_temp.aer_prov select * from security.aer_provider_states_v1();
  select coalesce(jsonb_agg(c.provider_id order by c.provider_id), '[]'::jsonb) into v_left
    from pipeline.aer_provider_coverage c where c.eligible and not exists (select 1 from pg_temp.aer_prov x where x.provider_id = c.provider_id);
  select coalesce(jsonb_agg(x.provider_id order by x.provider_id), '[]'::jsonb) into v_joined
    from pg_temp.aer_prov x where not exists (select 1 from pipeline.aer_provider_coverage c where c.provider_id = x.provider_id and c.eligible);
  update pipeline.aer_provider_coverage c set eligible = false, last_run_id = v_run, updated_at = now()
   where c.eligible and not exists (select 1 from pg_temp.aer_prov x where x.provider_id = c.provider_id);
  insert into pipeline.aer_provider_coverage as c (provider_id, provider_name, country, provider_type, eligible, disposition, discovery_state, extraction_state, admission_state,
         consumer_resolvable, priority_tier, priority_rank, courses_eligible, sources, sources_read, sources_failed, runs_held, runs_failed, matrix_active, matrix_other,
         course_req_active, course_req_proposed, layer4, held_scopes, root_causes, evidence, last_run_id)
  select x.provider_id, x.provider_name, x.country, x.provider_type, true, x.disposition, x.discovery_state, x.extraction_state, x.admission_state, x.consumer_resolvable,
         x.priority_tier, x.priority_rank, x.courses_eligible, x.sources, x.sources_read, x.sources_failed, x.runs_held, x.runs_failed, x.matrix_active, x.matrix_other,
         x.course_req_active, x.course_req_proposed, x.layer4, x.held_scopes, x.root_causes, x.evidence, v_run
    from pg_temp.aer_prov x
  on conflict (provider_id) do update set provider_name = excluded.provider_name, country = excluded.country, provider_type = excluded.provider_type, eligible = true,
         previous_disposition = case when c.disposition <> excluded.disposition then c.disposition else c.previous_disposition end,
         disposition_since = case when c.disposition <> excluded.disposition then now() else c.disposition_since end,
         disposition = excluded.disposition, discovery_state = excluded.discovery_state, extraction_state = excluded.extraction_state, admission_state = excluded.admission_state,
         consumer_resolvable = excluded.consumer_resolvable, priority_tier = excluded.priority_tier, priority_rank = excluded.priority_rank, courses_eligible = excluded.courses_eligible,
         sources = excluded.sources, sources_read = excluded.sources_read, sources_failed = excluded.sources_failed, runs_held = excluded.runs_held, runs_failed = excluded.runs_failed,
         matrix_active = excluded.matrix_active, matrix_other = excluded.matrix_other, course_req_active = excluded.course_req_active, course_req_proposed = excluded.course_req_proposed,
         layer4 = excluded.layer4, held_scopes = excluded.held_scopes, root_causes = excluded.root_causes, evidence = excluded.evidence, last_run_id = v_run, updated_at = now();
  get diagnostics v_qn = row_count;
  v_pop := jsonb_build_object(
    'by_country', (select coalesce(jsonb_object_agg(b->>'country', jsonb_build_object('eligible', (select count(*) from pg_temp.aer_prov x where x.country = b->>'country'),
                     'baseline', (b->>'providers')::int, 'delta', (select count(*) from pg_temp.aer_prov x where x.country = b->>'country') - (b->>'providers')::int)), '{}'::jsonb)
                     from jsonb_array_elements(coalesce(security.toolset_setting('pipeline', 'aer.baseline_eligible'), '[]'::jsonb)) b),
    'eligible', (select count(*) from pg_temp.aer_prov),
    'first_run', v_first,
    'joined', case when v_first then null else v_joined end, 'left', v_left,
    'dispositions', (select coalesce(jsonb_object_agg(z.disposition, z.n), '{}'::jsonb) from (select x.disposition, count(*) n from pg_temp.aer_prov x group by 1) z));

  -- 5 alerts through the existing Platform health issues and alert job (one issue per check; recovery when it clears)
  select count(*) into v_p0 from pipeline.aer_gap_findings g where g.state <> 'resolved' and g.severity = 'P0';
  select d.consumer_n into v_today from pipeline.aer_coverage_daily d where d.day = v_day and d.country = 'ALL';
  select d.consumer_n into v_prev from pipeline.aer_coverage_daily d where d.day < v_day and d.country = 'ALL' order by d.day desc limit 1;
  if v_alerts and v_p0 > 0 then
    insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
    values ('aer:p0', 'critical', 'admission', left('Academic entry requirements: ' || v_p0 || ' critical consumer data finding(s)', 300),
            jsonb_build_object('findings', v_p0, 'root_causes', (select jsonb_object_agg(z.root_cause, z.n) from (select g.root_cause, count(*) n from pipeline.aer_gap_findings g
                                 where g.state <> 'resolved' and g.severity = 'P0' group by 1) z),
                               'next_step', 'Quarantine the rows named on Coverage & completeness › Academic entry requirements and send them through Layer 4',
                               'resolve', 'Coverage & completeness › Attributes › Academic entry requirements'))
    on conflict (check_key) where resolved_at is null do update set severity = excluded.severity, title = excluded.title, detail = excluded.detail,
      last_seen = now(), occurrences = i.occurrences + 1;
  else
    update pipeline.platform_issues set resolved_at = now() where check_key = 'aer:p0' and resolved_at is null;
  end if;
  if v_alerts and v_prev is not null and v_prev - coalesce(v_today, 0) >= v_reg then
    insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
    values ('aer:regression', 'critical', 'admission', left('Academic entry requirements: consumer-resolvable providers fell from ' || v_prev || ' to ' || coalesce(v_today, 0), 300),
            jsonb_build_object('yesterday', v_prev, 'today', v_today, 'threshold', v_reg,
                               'next_step', 'Find the providers that stopped resolving on Coverage & completeness › Academic entry requirements',
                               'resolve', 'Coverage & completeness › Attributes › Academic entry requirements'))
    on conflict (check_key) where resolved_at is null do update set title = excluded.title, detail = excluded.detail, last_seen = now(), occurrences = i.occurrences + 1;
  else
    update pipeline.platform_issues set resolved_at = now() where check_key = 'aer:regression' and resolved_at is null;
  end if;

  -- 6 the Monday report through the existing alert delivery (off until the destination is confirmed, D-A7); once a week
  v_week := date_trunc('week', now() at time zone 'Australia/Sydney')::date;  -- fixed: Monday-to-Sunday weeks
  if coalesce((security.toolset_setting('pipeline', 'aer.weekly_email_enabled') #>> '{}')::boolean, false)
     and extract(isodow from now() at time zone 'Australia/Sydney') = 1
     and extract(hour from now() at time zone 'Australia/Sydney') >= security.pipeline_num_v1('aer.weekly_send_hour', 8) then
    v_weekly := security.aer_weekly_text_v1(security.aer_weekly_section_v1(v_week - 7));  -- fixed: the week just ended
    perform security.platform_alerts_add_v1(null, 'aer:weekly', 'raised', 'info', '[StudySearch] AER weekly report, week of ' || to_char(v_week - 7, 'DD Mon YYYY'),
                                            v_weekly, 'aer:weekly:' || v_week::text);
  end if;

  -- 7 the health page row and the run record
  update pipeline.platform_health_checks set status = case when v_p0 > 0 or exists (select 1 from pipeline.platform_issues p where p.check_key = 'aer:regression' and p.resolved_at is null)
                                                          then 'critical' else 'ok' end,
         detail = jsonb_build_object('open', (select jsonb_object_agg(z.severity, z.n) from (select g.severity, count(*) n from pipeline.aer_gap_findings g where g.state <> 'resolved' group by 1) z),
                                     'consumer_providers', v_today, 'run_id', v_run), checked_at = now()
   where key = 'aer';
  v_out := jsonb_build_object('run_id', v_run, 'manifests', v_man, 'found', v_found, 'opened', v_new, 'observed', v_obs, 'resolved', v_res, 'reopened', v_reo,
                              'open', coalesce((select jsonb_object_agg(z.severity, z.n) from (select g.severity, count(*) n from pipeline.aer_gap_findings g where g.state <> 'resolved' group by 1) z), '{}'::jsonb),
                              'held_back', greatest(0, (select count(*) from pg_temp.aer_cur c where not exists (select 1 from pipeline.aer_gap_findings g where g.fingerprint = c.fingerprint))),
                              'day', v_day, 'queue_rows', v_qn, 'population', v_pop);
  update pipeline.aer_reconcile_runs set finished_at = now(), result = v_out where id = v_run;
  return v_out;
end $function$;
revoke all on function security.aer_reconcile_v1(int) from public, anon, authenticated;
comment on function security.aer_reconcile_v1(int) is 'CF-247 AER Phase B (mandate §11, §14 hourly; B3): job aer-reconcile. Read-only over the AER data (sources, runs, rows, Layer 4, course outcomes): writes only the AER assurance tables, the aer:* Platform health issues and the aer health row. Manifests from stored runs; findings deduplicated by fingerprint; resolved only with closure evidence; reopened when found again; the daily four-measure snapshot; P0 and regression issues for the existing alert job; the Monday report when aer.weekly_email_enabled is on. No AI, no fetch. Single flight.';

-- 6 the weekly AER section (mandate §14), kept in the stored weekly scorecard and sent on Monday when switched on ----------------------
create or replace function security.aer_weekly_section_v1(p_week_start date) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_end date := p_week_start + 6; v_now record; v_before record; v jsonb;  -- fixed: Monday-to-Sunday weeks
begin
  select * into v_now from pipeline.aer_coverage_daily d where d.country = 'ALL' and d.day <= v_end order by d.day desc limit 1;
  select * into v_before from pipeline.aer_coverage_daily d where d.country = 'ALL' and d.day < p_week_start order by d.day desc limit 1;
  v := jsonb_build_object(
    'week_start', p_week_start, 'as_of', v_now.day,
    'eligible', v_now.eligible,
    'measures', case when v_now.day is null then null else jsonb_build_object(
      'discovery', jsonb_build_object('n', v_now.discovery_n, 'of', v_now.eligible, 'prior_week', v_before.discovery_n),
      'extraction', jsonb_build_object('n', v_now.extraction_n, 'of', v_now.eligible, 'prior_week', v_before.extraction_n),
      'admission', jsonb_build_object('n', v_now.admission_n, 'of', v_now.eligible, 'prior_week', v_before.admission_n),
      'consumer', jsonb_build_object('n', v_now.consumer_n, 'of', v_now.eligible, 'prior_week', v_before.consumer_n)) end,
    'open', jsonb_build_object('P0', v_now.open_p0, 'P1', v_now.open_p1, 'P2', v_now.open_p2),
    'changes', (select jsonb_build_object('opened', count(*) filter (where x.event = 'opened'), 'resolved', count(*) filter (where x.event = 'resolved'),
                                          'reopened', count(*) filter (where x.event = 'reopened'))
                  from pipeline.aer_gap_events x where (x.at at time zone 'Australia/Sydney')::date between p_week_start and v_end),
    'top_root_causes', (select coalesce(jsonb_agg(z order by z.providers desc, z.code), '[]'::jsonb) from (
                          select rc.code, rc.label, rc.severity, rc.owner_role, rc.next_action, count(distinct g.provider_id) providers, count(*) findings
                            from pipeline.aer_gap_findings g join pipeline.aer_gap_root_causes rc on rc.code = g.root_cause
                           where g.state <> 'resolved' group by rc.code, rc.label, rc.severity, rc.owner_role, rc.next_action
                           order by count(distinct g.provider_id) desc, rc.code limit 5) z),
    'no_progress_providers', (select count(distinct g.provider_id) from pipeline.aer_gap_findings g where g.state <> 'resolved' and g.severity in ('P0', 'P1')
                               and (g.first_seen at time zone 'Australia/Sydney')::date < p_week_start),
    'recovered', (select coalesce(jsonb_agg(jsonb_build_object('root_cause', g.root_cause, 'scope', g.scope_label, 'provider_id', g.provider_id)), '[]'::jsonb)
                    from pipeline.aer_gap_events x join pipeline.aer_gap_findings g on g.id = x.finding_id
                   where x.event = 'resolved' and g.scope_kind in ('country', 'qualification') and (x.at at time zone 'Australia/Sydney')::date between p_week_start and v_end),
    'postgraduate', v_now.detail->'postgraduate',
    'layer4_pending', v_now.detail->'layer4_pending',
    'readiness', (select coalesce(jsonb_object_agg(z.readiness, z.n), '{}'::jsonb) from (select r.readiness, count(*) n from pipeline.aer_review_readiness r
                    where r.settled_at is null group by 1) z),
    'spend_usd', (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'entry_matrix' and l.source <> 'opening'
                   and (l.at at time zone 'Australia/Sydney')::date between p_week_start and v_end),
    'next_work', 'Hourly reconciliation (aer-reconcile); Phase C reader and qualification work; Phase E discovery waves once approved',
    'decisions', (select coalesce(jsonb_agg(distinct rc.label), '[]'::jsonb) from pipeline.aer_gap_findings g join pipeline.aer_gap_root_causes rc on rc.code = g.root_cause
                   where g.state <> 'resolved' and rc.owner_role = 'Platform Admin'));
  return v;
exception when others then
  return jsonb_build_object('week_start', p_week_start, 'error', left(sqlerrm, 300));
end $function$;
revoke all on function security.aer_weekly_section_v1(date) from public, anon, authenticated;
comment on function security.aer_weekly_section_v1(date) is 'CF-247 AER Phase B (mandate §14 weekly): the AER section of the weekly report: the four measures against the prior week, open P0/P1/P2, opened/resolved/reopened, top root causes, providers with no progress, recovered country and qualification scopes, postgraduate coverage, Layer 4 workload, entry-matrix AI spend and decisions for the Platform Admin.';

create or replace function security.aer_weekly_text_v1(p jsonb) returns text
language sql immutable set search_path to '' as $function$
  select concat_ws(E'\n',
    'Eligible AU/NZ providers: ' || coalesce(p->>'eligible', 'not measured'),
    'Source discovery: ' || coalesce(p#>>'{measures,discovery,n}', '-') || ' (prior week ' || coalesce(p#>>'{measures,discovery,prior_week}', '-') || ')',
    'Extraction: ' || coalesce(p#>>'{measures,extraction,n}', '-') || ' (prior week ' || coalesce(p#>>'{measures,extraction,prior_week}', '-') || ')',
    'Verified admission: ' || coalesce(p#>>'{measures,admission,n}', '-') || ' (prior week ' || coalesce(p#>>'{measures,admission,prior_week}', '-') || ')',
    'Consumer-resolvable: ' || coalesce(p#>>'{measures,consumer,n}', '-') || ' (prior week ' || coalesce(p#>>'{measures,consumer,prior_week}', '-') || ')',
    'Open findings: P0 ' || coalesce(p#>>'{open,P0}', '0') || ', P1 ' || coalesce(p#>>'{open,P1}', '0') || ', P2 ' || coalesce(p#>>'{open,P2}', '0'),
    'This week: ' || coalesce(p#>>'{changes,opened}', '0') || ' opened, ' || coalesce(p#>>'{changes,resolved}', '0') || ' resolved, ' || coalesce(p#>>'{changes,reopened}', '0') || ' reopened',
    'Top root causes: ' || coalesce((select string_agg((z->>'label') || ' (' || (z->>'providers') || ' providers)', '; ') from jsonb_array_elements(p->'top_root_causes') z), 'none'),
    'Layer 4 workload: ' || coalesce((p->'layer4_pending')::text, '{}') || '; readiness ' || coalesce((p->'readiness')::text, '{}'),
    'Entry-matrix AI spend: US$' || coalesce(p->>'spend_usd', '0'),
    'Decisions for the Platform Admin: ' || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(p->'decisions') x), 'none'),
    'Details: Coverage & completeness › Attributes › Academic entry requirements.')
$function$;
revoke all on function security.aer_weekly_text_v1(jsonb) from public, anon, authenticated;

-- the copy kept in the admin repository each Monday (workflow aer-weekly-report): the same section as the e-mail and the dashboard
create or replace function security.aer_weekly_markdown_v1(p_week_start date default null) returns text
language plpgsql stable security definer set search_path to '' as $function$
declare v_ws date := coalesce(p_week_start, date_trunc('week', now() at time zone 'Australia/Sydney')::date - 7);  -- fixed: the week just ended (Monday to Sunday)
        v jsonb;
begin
  v := security.aer_weekly_section_v1(v_ws);
  return '# AER weekly report, week of ' || to_char(v_ws, 'DD Mon YYYY') || E'\n\n'
      || 'Generated ' || to_char(now() at time zone 'Australia/Sydney', 'DD Mon YYYY HH24:MI') || ' (Sydney) from the StudySearch database (security.aer_weekly_section_v1). '
      || 'The same report is on Coverage & completeness › Attributes › Academic entry requirements.' || E'\n\n'
      || (select string_agg('- ' || l, E'\n') from unnest(string_to_array(security.aer_weekly_text_v1(v), E'\n')) l) || E'\n\n'
      || '## Root causes' || E'\n\n| Root cause | Severity | Providers | Findings | Next action | Owner |\n|---|---|---:|---:|---|---|\n'
      || coalesce((select string_agg(format('| %s | %s | %s | %s | %s | %s |', z->>'label', z->>'severity', z->>'providers', z->>'findings', z->>'next_action', z->>'owner_role'), E'\n')
                    from jsonb_array_elements(v->'top_root_causes') z), '| none | | | | | |') || E'\n\n'
      || '## Layer 4 review readiness (pending AER items)' || E'\n\n'
      || coalesce((select string_agg(format('- %s: %s', x.key, x.value), E'\n') from jsonb_each_text(v->'readiness') x), '- none') || E'\n\n'
      || '```json' || E'\n' || jsonb_pretty(v) || E'\n```\n';
end $function$;
revoke all on function security.aer_weekly_markdown_v1(date) from public, anon, authenticated;
grant execute on function security.aer_weekly_markdown_v1(date) to supabase_read_only_user;
comment on function security.aer_weekly_markdown_v1(date) is 'CF-247 AER weekly report (D-A7, Platform Admin 2 Nov 2026 ~16:40): the Markdown copy committed each Monday by the aer-weekly-report workflow (aer-weekly-snapshot branch, docs/platform/aer-weekly/YYYY-MM-DD.md). Read-only; executable by the read-only role, as the watchdog is.';

-- load a review readiness classification (Platform Admin, through SQL or a migration): pending items only; a settled item is never reopened
create or replace function security.aer_review_readiness_load_v1(p_rows jsonb, p_source text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare x jsonb; v_ok int := 0; v_skip jsonb := '[]'::jsonb; li record;
begin
  if coalesce(btrim(p_source), '') = '' then raise exception 'name the classification source (document and date)'; end if;
  for x in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if x->>'readiness' not in ('review_ready', 'reader_correction_required', 'evidence_required', 'superseded_invalid', 'awaiting_human_review') then
      v_skip := v_skip || jsonb_build_object('item', x->>'review_item_id', 'why', 'unknown readiness class'); continue; end if;
    if x->>'root_cause' is not null and not exists (select 1 from pipeline.aer_gap_root_causes rc where rc.code = x->>'root_cause') then
      v_skip := v_skip || jsonb_build_object('item', x->>'review_item_id', 'why', 'unknown root cause'); continue; end if;
    select i.id, i.status, i.field_code, i.entity_type, i.entity_id into li from pipeline.layer4_review_items i where i.id = nullif(x->>'review_item_id', '')::uuid;
    if li.id is null or li.status <> 'pending' or li.field_code not in ('entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read') then
      v_skip := v_skip || jsonb_build_object('item', x->>'review_item_id', 'why', 'not a pending AER Layer 4 item'); continue; end if;
    insert into pipeline.aer_review_readiness as z (review_item_id, field_code, entity_type, entity_id, provider_id, readiness, root_cause, reason, evidence, basis, source, item_status)
    values (li.id, li.field_code, li.entity_type, li.entity_id,
            coalesce((select r.provider_id from pipeline.entry_matrix_runs r where r.review_item_id = li.id limit 1),
                     (select c.provider_id from catalogue.courses c where c.id = li.entity_id), li.entity_id),
            x->>'readiness', x->>'root_cause', left(x->>'reason', 500), coalesce(x->'evidence', '{}'::jsonb), 'classification', left(p_source, 300), li.status)
    on conflict (review_item_id) do update set readiness = excluded.readiness, root_cause = excluded.root_cause, reason = excluded.reason, evidence = excluded.evidence,
           basis = 'classification', source = excluded.source, classified_at = now(), updated_at = now()
     where z.settled_at is null;
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('loaded', v_ok, 'skipped', v_skip);
end $function$;
revoke all on function security.aer_review_readiness_load_v1(jsonb, text) from public, anon, authenticated;
comment on function security.aer_review_readiness_load_v1(jsonb, text) is 'CF-247 AER Layer 4 review readiness (mandate 16:33 §9): loads a classification ([{review_item_id, readiness, root_cause, reason, evidence}]) for pending AER items only, naming its source; refuses unknown classes, unknown root causes and settled or non-AER items. Changes no Layer 4 item. Run by the Platform Admin.';

-- 7 the Admin read (Curator and above, through admin_aer) -------------------------------------------------------------------------
create or replace function security.aer_coverage_read_v1(p_action text, p_args jsonb) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_day date; v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_size int; v_off int; v_q text := nullif(btrim(coalesce(p_args->>'q', '')), '');
        v_sev text := nullif(p_args->>'severity', ''); v_cc text := nullif(upper(coalesce(p_args->>'country', '')), ''); v_cause text := nullif(p_args->>'root_cause', '');
        v_disp text := nullif(p_args->>'disposition', '');
begin
  v_size := greatest(1, least(coalesce((p_args->>'page_size')::int, 50), 100));  -- fixed: a page is at most 100 rows (W11)
  v_off := greatest(0, coalesce((p_args->>'offset')::int, 0));
  select max(d.day) into v_day from pipeline.aer_coverage_daily d;
  if p_action = 'coverage_provider' then
    return jsonb_build_object(
      'provider', (select jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.short_name), 'country', e.country, 'eligible', e.provider_id is not null)
                     from catalogue.providers p left join security.aer_eligible_v1() e on e.provider_id = p.id where p.id = v_pid),
      'sources', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'url', s.url, 'title', s.title, 'rank', s.rank, 'status', s.status, 'read_at', s.read_at,
                     'error', left(s.error, 200), 'shape', mf.shape, 'scope_country', mf.scope_country, 'expected', mf.expected_cells, 'matched', mf.matched_cells,
                     'run_state', mf.run_state, 'reason', mf.reason) order by s.rank, s.title), '[]'::jsonb)
                    from pipeline.entry_matrix_sources s
                    left join lateral (select m.* from pipeline.aer_source_manifests m where m.source_id = s.id order by m.computed_at desc limit 1) mf on true
                   where s.provider_id = v_pid),
      'findings', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'root_cause', g.root_cause, 'label', rc.label, 'severity', g.severity, 'state', g.state,
                     'scope_kind', g.scope_kind, 'scope', g.scope_label, 'study_level', g.study_level, 'owner_role', g.owner_role, 'next_action', g.next_action,
                     'first_seen', g.first_seen, 'last_seen', g.last_seen, 'resolved_at', g.resolved_at, 'reopen_count', g.reopen_count, 'evidence', g.evidence,
                     'closure_evidence', g.closure_evidence) order by g.state = 'resolved', g.severity, g.root_cause), '[]'::jsonb)
                     from pipeline.aer_gap_findings g join pipeline.aer_gap_root_causes rc on rc.code = g.root_cause where g.provider_id = v_pid),
      'active', (select jsonb_build_object('rows', count(*), 'countries', coalesce(jsonb_agg(distinct m.country_code), '[]'::jsonb),
                                           'qualifications', count(distinct lower(m.qualification_name)), 'levels', coalesce(jsonb_agg(distinct m.level_label) filter (where m.level_label is not null), '[]'::jsonb))
                   from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.status = 'active'),
      'course', (select jsonb_build_object('active', count(*) filter (where x.status = 'active'), 'proposed', count(*) filter (where x.status = 'proposed'))
                   from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where c.provider_id = v_pid),
      'queue', (select to_jsonb(c) - 'evidence' from pipeline.aer_provider_coverage c where c.provider_id = v_pid),
      'evidence', (select c.evidence from pipeline.aer_provider_coverage c where c.provider_id = v_pid));
  end if;
  return jsonb_build_object(
    'as_at', (select max(r.finished_at) from pipeline.aer_reconcile_runs r),
    'day', v_day,
    'job', (select jsonb_build_object('active', j.active, 'schedule', j.schedule) from cron.job j where j.jobname = 'aer-reconcile'),
    'last_run', (select to_jsonb(r) from (select r.id, r.started_at, r.finished_at, r.result from pipeline.aer_reconcile_runs r order by r.id desc limit 1) r),
    'measures', (select coalesce(jsonb_agg(to_jsonb(d) - 'run_id' order by d.country = 'ALL' desc, d.country), '[]'::jsonb) from pipeline.aer_coverage_daily d where d.day = v_day),
    'progress', (select coalesce(jsonb_agg(jsonb_build_object('days', w.n, 'day', d.day, 'discovery_n', d.discovery_n, 'extraction_n', d.extraction_n,
                   'admission_n', d.admission_n, 'consumer_n', d.consumer_n, 'eligible', d.eligible) order by w.n), '[]'::jsonb)
                   from unnest(array[7, 30]) w(n)  -- fixed: the mandate's 7- and 30-day progress windows
                   join lateral (select x.* from pipeline.aer_coverage_daily x where x.country = 'ALL' and x.day <= v_day - w.n order by x.day desc limit 1) d on true),
    'open', (select jsonb_build_object('P0', count(*) filter (where g.severity = 'P0'), 'P1', count(*) filter (where g.severity = 'P1'), 'P2', count(*) filter (where g.severity = 'P2'))
               from pipeline.aer_gap_findings g where g.state <> 'resolved'),
    'changes_7d', (select jsonb_build_object('opened', count(*) filter (where x.event = 'opened'), 'resolved', count(*) filter (where x.event = 'resolved'),
                                             'reopened', count(*) filter (where x.event = 'reopened'))
                     from pipeline.aer_gap_events x where x.at > now() - make_interval(days => 7)),  -- fixed: display window
    'root_causes', (select coalesce(jsonb_agg(z order by z.sev, z.providers desc), '[]'::jsonb) from (
                      select rc.code, rc.label, rc.severity, rc.severity sev, rc.owner_role, rc.next_action, count(distinct g.provider_id) providers, count(*) findings
                        from pipeline.aer_gap_findings g join pipeline.aer_gap_root_causes rc on rc.code = g.root_cause
                       where g.state <> 'resolved' group by rc.code) z),
    'population', (select r.result->'population' from pipeline.aer_reconcile_runs r where r.finished_at is not null order by r.id desc limit 1),
    'dispositions', (select coalesce(jsonb_object_agg(z.disposition, z.n), '{}'::jsonb) from (select c.disposition, count(*) n from pipeline.aer_provider_coverage c
                      where c.eligible and (v_cc is null or c.country = v_cc) group by 1) z),
    -- the gap queue, in its priority order (universities and tertiary providers first, held sources next to them)
    'providers', (with fl as (
                    select c.*, (select count(*) filter (where g.severity = 'P0') from pipeline.aer_gap_findings g where g.provider_id = c.provider_id and g.state <> 'resolved') p0,
                           (select count(*) filter (where g.severity = 'P1') from pipeline.aer_gap_findings g where g.provider_id = c.provider_id and g.state <> 'resolved') p1,
                           (select count(*) filter (where g.severity = 'P2') from pipeline.aer_gap_findings g where g.provider_id = c.provider_id and g.state <> 'resolved') p2,
                           (select g.next_action from pipeline.aer_gap_findings g where g.provider_id = c.provider_id and g.state <> 'resolved' order by g.severity, g.root_cause limit 1) next_action,
                           (select g.owner_role from pipeline.aer_gap_findings g where g.provider_id = c.provider_id and g.state <> 'resolved' order by g.severity, g.root_cause limit 1) owner_role
                      from pipeline.aer_provider_coverage c
                     where c.eligible and (v_cc is null or c.country = v_cc) and (v_q is null or coalesce(c.provider_name, '') ilike '%' || v_q || '%')
                       and (v_disp is null or c.disposition = v_disp) and (v_cause is null or v_cause = any (c.root_causes))
                       and (v_sev is null or exists (select 1 from pipeline.aer_gap_findings g where g.provider_id = c.provider_id and g.state <> 'resolved' and g.severity = v_sev)))
                  select jsonb_build_object('total', (select count(*) from fl), 'offset', v_off, 'page_size', v_size,
                    'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', f.provider_id, 'name', f.provider_name, 'country', f.country, 'type', f.provider_type,
                       'disposition', f.disposition, 'discovery', f.discovery_state, 'extraction', f.extraction_state, 'admission', f.admission_state,
                       'consumer_resolvable', f.consumer_resolvable, 'priority', f.priority_rank, 'tier', f.priority_tier, 'courses', f.courses_eligible,
                       'p0', f.p0, 'p1', f.p1, 'p2', f.p2, 'next_action', f.next_action, 'owner_role', f.owner_role, 'sources', f.sources, 'active_rows', f.matrix_active,
                       'course_active', f.course_req_active, 'held_scopes', f.held_scopes, 'disposition_since', f.disposition_since,
                       'primary_url', (select s.url from pipeline.entry_matrix_sources s where s.provider_id = f.provider_id and s.status = 'read' order by s.rank, s.created_at limit 1))
                       order by f.priority_rank)
                      from (select * from fl order by fl.priority_rank limit v_size offset v_off) f), '[]'::jsonb))),
    'alerts', (select coalesce(jsonb_agg(jsonb_build_object('check', p.check_key, 'title', p.title, 'first_seen', p.first_seen)), '[]'::jsonb)
                 from pipeline.platform_issues p where p.check_key like 'aer:%' and p.resolved_at is null),
    'readiness', (select coalesce(jsonb_object_agg(z.readiness, z.n), '{}'::jsonb) from (select r.readiness, count(*) n from pipeline.aer_review_readiness r
                    where r.settled_at is null group by 1) z),
    'weekly', security.aer_weekly_section_v1(date_trunc('week', now() at time zone 'Australia/Sydney')::date - 7),  -- fixed: the week just ended
    'weekly_email', coalesce((security.toolset_setting('pipeline', 'aer.weekly_email_enabled') #>> '{}')::boolean, false));
end $function$;
revoke all on function security.aer_coverage_read_v1(text, jsonb) from public, anon, authenticated;
comment on function security.aer_coverage_read_v1(text, jsonb) is 'CF-247 AER Phase B (mandate §13; B5): the AER overview (four measures with numerator and denominator, 7- and 30-day progress, open P0/P1/P2, opened/resolved/reopened, root causes) and the provider drill-down with next action and owner. Read through public.admin_aer(''coverage'' / ''coverage_provider''), Curator and above. Admin only; never part of the consumer API.';

-- 8 admin_aer: the coverage actions (md5-guarded edit; Curator and above) ----------------------------------------------------------
select pg_temp.edit_once('public.admin_aer(text,jsonb)', '5e58f5d6126b3b2fe026e376a56c7686', '0593747bb6ddd55c785fc445a06eb242', array[
  array[$o$  -- ---------------------------------------------------------------- reads
  if p_action = 'summary' then$o$,
        $n$  -- ---------------------------------------------------------------- reads
  -- CF-247 AER Phase B (mandate 2 Nov 2026 §13, §15): AER coverage and the provider drill-down, Curator (rank 3) and above only;
  -- viewers and counsellors see none of it
  if p_action in ('coverage', 'coverage_provider') then
    if v_rank < 3 then raise exception 'curator role required: AER coverage is for operations roles' using errcode = '42501'; end if;
    return security.aer_coverage_read_v1(p_action, a);
  end if;
  if p_action = 'summary' then$n$]],
  array[1]);

-- 9 the weekly scorecard keeps the AER section (md5-guarded edit) -------------------------------------------------------------------
select pg_temp.edit_once('security.ops_scorecard_record_v1()', 'e0031afa54d1afb992fc74805ee0e623', 'a4b9b21d49bf92c38054858985beecb2', array[
  array[$o$    v := security.ops_scorecard_v1(w, v_old);
$o$,
        $n$    v := security.ops_scorecard_v1(w, v_old);
    v := v || jsonb_build_object('aer', security.aer_weekly_section_v1(w));  -- CF-247 AER Phase B (mandate §14 weekly)
$n$]],
  array[1]);

-- 10 the health page row, the job (catalogued, scheduled, paused), the register ----------------------------------------------------
insert into pipeline.platform_health_checks(key, area, label, status, detail, cadence_minutes, slow, sort_order)
values ('aer', 'admission', 'Academic entry requirements are reconciled (AER assurance)', 'skipped', '{}'::jsonb, 60, false, 160)
on conflict (key) do nothing;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-reconcile', 'Reports', 40, 'AER reconciliation (academic entry requirements)',
  'Hourly at :27 when switched on: compares every eligible AU/NZ provider''s AER sources, reading runs and their stored completeness, proposed rows, Layer 4 items, active rows and course outcomes; records each gap once by its fingerprint (new findings a run: AER reconcile: new findings written a run), resolves it only with closure evidence and reopens it when it comes back; keeps the daily four-measure snapshot and the catalogue-first gap queue (every eligible provider''s disposition, with the population against the 1,476 baseline); opens one Platform health issue for P0 findings or a coverage fall. Read-only over the catalogue: database metadata only; no AI, no Firecrawl, no page read, no crawl.',
  5, true, null)
on conflict (jobname) do nothing;
-- scheduled once and paused at once; activation is a separate, deliberate step; a second run leaves the job as it finds it
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'aer-reconcile') then
    perform cron.schedule('aer-reconcile', '27 * * * *', 'select security.aer_reconcile_v1(security.pipeline_num_v1(''batch.aer_reconcile'', 5000)::int)');
    perform cron.alter_job((select jobid from cron.job where jobname = 'aer-reconcile'), active := false);
  end if;
end $j$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'aer-reconcile', 'Platform', 'Reports', 'AER hourly reconciliation (paused until activated)', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_source_manifests', 'Platform', 'Reports', 'AER source manifests from stored runs', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_gap_root_causes', 'Platform', 'Reports', 'AER gap root causes', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_gap_findings', 'Platform', 'Reports', 'AER gap findings by fingerprint', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_gap_events', 'Platform', 'Reports', 'AER gap history', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_reconcile_runs', 'Platform', 'Reports', 'AER reconciliation runs', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_coverage_daily', 'Platform', 'Reports', 'AER daily four-measure snapshot', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_provider_coverage', 'Platform', 'Reports', 'AER catalogue-first gap queue (one row per eligible provider)', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_provider_states_v1', 'Platform', 'Reports', 'AER report dispositions per eligible provider', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_coverage_verify_v1', 'Platform', 'Reports', 'AER queue against a fresh catalogue anti-join', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_reconcile_v1', 'Platform', 'Reports', 'Job aer-reconcile', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_current_findings_v1', 'Platform', 'Reports', 'Current AER gaps from existing data', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_measures_v1', 'Platform', 'Reports', 'The four AER measures', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_coverage_read_v1', 'Platform', 'Reports', 'AER overview and provider drill-down (admin_aer)', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_weekly_section_v1', 'Platform', 'Reports', 'AER section of the weekly report', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_weekly_markdown_v1', 'Platform', 'Reports', 'AER weekly report copy for the admin repository (workflow aer-weekly-report)', 'active', '{}', '20261102110000'),
 ('table', 'pipeline.aer_review_readiness', 'Platform', 'Reports', 'AER Layer 4 review readiness classes', 'active', '{}', '20261102110000'),
 ('function', 'security.aer_review_readiness_load_v1', 'Platform', 'Reports', 'Load an AER review readiness classification', 'active', '{}', '20261102110000')
on conflict do nothing;

-- post-check: nothing switched on, nothing changed in the catalogue, the edits are the intended ones
do $$
begin
  if exists (select 1 from cron.job where jobname = 'aer-reconcile' and active) then raise exception 'AER Phase B post-check: the job must be paused'; end if;
  if not exists (select 1 from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname = 'aer-reconcile') then
    raise exception 'AER Phase B post-check: the job is not scheduled and catalogued'; end if;
  if coalesce((select (value #>> '{}')::boolean from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'aer.weekly_email_enabled'), true) then
    raise exception 'AER Phase B post-check: the Monday e-mail must be off (D-A7)'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('batch.aer_reconcile', 'aer.eligible_countries', 'aer.stale_source_days',
        'aer.alerts_enabled', 'aer.regression_alert_providers', 'aer.weekly_email_enabled', 'aer.weekly_send_hour', 'aer.postgraduate_levels', 'aer.baseline_eligible',
        'aer.priority_provider_types', 'aer.not_applicable_provider_types') and label is not null and used_by is not null) <> 11 then
    raise exception 'AER Phase B post-check: settings incomplete (G2)'; end if;
  if exists (select 1 from pipeline.aer_gap_findings) or exists (select 1 from pipeline.aer_coverage_daily) or exists (select 1 from pipeline.aer_provider_coverage)
     or exists (select 1 from pipeline.aer_review_readiness) then
    raise exception 'AER Phase B post-check: applying the migration must not run the reconciliation'; end if;
  if md5(pg_get_functiondef('public.admin_aer(text,jsonb)'::regprocedure)) <> '0593747bb6ddd55c785fc445a06eb242' then
    raise exception 'AER Phase B post-check: admin_aer has an unexpected definition'; end if;
  if md5(pg_get_functiondef('security.ops_scorecard_record_v1()'::regprocedure)) <> 'a4b9b21d49bf92c38054858985beecb2' then
    raise exception 'AER Phase B post-check: ops_scorecard_record_v1 has an unexpected definition'; end if;
end $$;
select 'AER Phase B: manifests, findings, reconcile (paused), daily measures, coverage read, alerts and weekly section' ok;
