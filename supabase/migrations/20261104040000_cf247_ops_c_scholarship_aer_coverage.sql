-- CF-247 Autonomous AI Operations, workstream C: scholarship and AER (entry requirements) completeness (P0 mandate, Platform Admin 3 Nov 2026 15:37,
-- §5 and §12; workstreams and ownership 3 Nov 2026 15:40, row C). Lands after workstream A's shared contract (20261104010000).
--
-- 1. Discovery work that can never run now ends with an outcome (IQ-00041, IQ-00058). Live 3 Nov 2026: 1,097 scholarship discovery rows were
--    'pending' with 0 attempts, every one for a provider the discovery picker refuses (Australian providers below scholarship_min_courses, schools,
--    type "other"); a further 246 'mapped' or 'empty' rows of refused providers came due again. The picker (public.svc_scholarship_discover_next) only
--    pushes a refused row 6 hours on (retry.scholarship_discovery_held_hours), so the rows waited forever, filled its pick window every 6 hours,
--    and kept the hourly refill from ever topping the queue up (it counts every 'pending' row as waiting work). With the Firecrawl daily budget
--    switched off (2 Nov) the holds were not applied at all and the platform health check reported 1,050 waiting and "stopped".
--    security.scholarship_discovery_settle_v1 (job scholarship-discovery-settle, hourly at :16, before the refill at :23) gives each such row the
--    outcome status 'not_eligible' with its reason (unpublished, search_off, directory_site or not_eligible) and the status it came from, and
--    returns it to that status, due, as soon as the reason clears (a provider grows past the course minimum, joins the scholarship pilot, is
--    published again). Its updated_at is never touched, so the health check's "last progress" stays truthful. Ships ON
--    (scholarship.discovery_settle_on): it stops waste and records outcomes; it reads nothing, spends nothing and admits nothing.
-- 2. Provider-level coverage reconciliation, a permanent mechanism (mandate 15:37 §5, §12; acceptance mandate 15:52 §8). security.scholarship_coverage_v1
--    and security.aer_coverage_v1 compare, per active provider and country, what the sources list against what the catalogue holds:
--    - scholarships: listing pages read and their items, listing members, the national register (scholarship.register_listings), candidates
--      (pending, rejected, admitted), scholarships admitted, published, held, in Layer 4 and archived, by category (research, undergraduate,
--      postgraduate, international) and by the facts a student needs (funding type, value, application dates, study level, academic and residency
--      requirements, country eligibility). Gaps: zero scholarships, under-represented against the listing, a category the listing shows but the
--      catalogue lacks, provider not searched, listing read only partly, listing items never turned into candidates, facts missing. Schools are not
--      applicable; a non-university provider the admission rule refuses is a policy gap (grouped), never missing data;
--    - AER: every AER-eligible provider plus every provider of a provider-level type the eligibility rule leaves out (so a major registered provider
--      is never silently omitted); entry-requirement sources and their manifests (published cells, countries and pathways named), matrix rows by
--      applicant country, qualification (curriculum) and study level, named pathways (coverage.aer_pathways: IB, A Levels, Nepal, India, China, US;
--      a gap only where the provider's own source names the pathway), domestic-only rows (never read as universal), course-level requirements on
--      courses with a bound official page, effective period, intakes and application deadlines. Each gap carries the input through which the
--      scheduled AER reader (Release C, D6) acts on it: pipeline.entry_matrix_sources (matrix), security.aer_schedule_courses_v1 (bound pages) or
--      pipeline.coverage_course_pages (pages to bind).
--    security.coverage_reconcile_v1 (job coverage-reconcile, hourly at :26) is incremental (security.coverage_due_v1): providers new or changed since
--    last reconciled, then open discrepancies due a recheck, then the periodic broad check, at most batch.coverage_reconcile a run; never the whole
--    catalogue every hour. It writes pipeline.coverage_provider_reconciliation and opens or updates ONE provider-level coverage investigation per
--    provider and domain in the integration queue (security.integration_issue_upsert_v1, fingerprint coverage:<domain>:<provider id>), never per
--    record. Providers outside coverage.provider_level_types without listing evidence are grouped per domain, country and gap. New issues a run
--    are limited by coverage.investigations_per_run. Ships ON: it reads and reports only (no read, no AI, no Firecrawl, no admission, no
--    publication). Layer 4 admission controls are unchanged; nothing is admitted.
-- 3. The AER coverage reader counted no course at all: security.aer_provider_states_v1 required catalogue.courses.publication_status = 'published',
--    and every AU and NZ course is 'unpublished' (live 3 Nov 2026: 25,380 active AU courses and 6,495 active NZ courses, none published; course
--    visibility follows the provider). courses_eligible, course_req_active and course_req_proposed were 0 for all 1,476 providers in
--    pipeline.aer_provider_coverage, so 'course_only' could never be reported and course-level requirements were invisible to the gap queue.
--    The filter is the course lifecycle only (md5-guarded edit, two lines).
-- 4. Root causes and remedies are registered through workstream A's contract (security.ops_root_cause_register_v1, security.ops_remedy_register_v1).
--    The one 'auto' remedy (sch_discovery_settle) calls only the settle mechanism above; coverage investigations are 'admin' remedies (recovery
--    needs reads, spend or Layer 4), with a verify function the controller can run.
--
-- Settings (G2): scholarship.discovery_settle_on, batch.scholarship_discovery_settle, coverage.* (section "Coverage reconciliation").
-- Edited live function (md5-guarded, live md5 read 3 Nov 2026 15:46 AEDT):
--   security.aer_provider_states_v1()   db5fb0c9f75b8bcca91bdcb34a2632d5 -> ea058f55ec77b191995e16985211b366
-- Not edited (read only): public.svc_scholarship_discover_next, security.scholarship_discovery_refill_v1, security.fc_sch_eligible_v1,
--   security.fc_sch_held_v1, security.aer_reconcile_v1, security.integration_issue_upsert_v1. None of the Release C (cf247-aer-scheduled-reading)
--   functions is touched: entry_matrix_enabled_v1, entry_matrix_fire_v1, course_entry_eligible_v1, course_entry_programme_v1,
--   aer_course_outcomes_build_v1, aer_schedule_*.
-- Replaces: security.aer_provider_states_v1 (same name; md5-guarded)
-- Retires: nothing (the indefinite 6-hour re-hold of refused discovery rows stops by itself once they carry an outcome; no object retires)
-- Consumer API: untouched (G3). No consumer function, table, column or edge function is read into a new shape or changed.
-- Nothing is dropped or deleted. Nothing spends: no AI, no Firecrawl, no admission, no publication.

do $guard$
begin
  if to_regclass('pipeline.ops_remedies') is null or to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is null
     or to_regprocedure('security.ops_root_cause_register_v1(text,jsonb)') is null then
    raise exception 'workstream C needs workstream A''s shared contract (20261104010000) first';
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

-- 0. the definitions the new code reads are the ones it was written against (not changed here; live md5s read 3 Nov 2026 15:43-15:50 AEDT)
do $g$
declare r record;
begin
  for r in select * from (values ('security.fc_sch_eligible_v1(uuid)', '2c44de24ea2d1bda123e1c8679591a9f'),
                                 ('security.integration_issue_upsert_v1(jsonb,text)', null),
                                 ('security.aer_eligible_v1()', 'ffafcedf3dadf707ca96b6b9425d0b3d'),
                                 ('security.scholarship_admission_provider_ok_v1(uuid)', null),  -- live 269f74a985acbc37f1f3b8615efa6254 (3 Nov 2026 15:46); read, not edited
                                 ('security.aer_reconcile_v1(integer)', '368319701d5998f1d7393dda48920b6d')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'workstream C reads %, which does not exist', r.sig; end if;
    if r.m is not null and md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % (md5 %) differs from the definition this change was written against', r.sig, md5(pg_get_functiondef(r.sig::regprocedure));
    end if;
  end loop;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'scholarship.discovery_settle_on', 'Scholarship discovery: refused providers end with an outcome',
  'On: a discovery row the picker can never take (provider unpublished, scholarship search switched off, website on a directory site, or not eligible under the Firecrawl scholarship rules while the daily budget is on) is given the status not_eligible with its reason, instead of waiting as pending for ever; it returns, due, as soon as the reason clears. Off: such rows wait and are re-held every few hours, as before.',
  'boolean', 'true'::jsonb, null, null, null, 1050, 'Scholarships', 'security.scholarship_discovery_settle_v1 (job scholarship-discovery-settle)',
  'CF-247 P0 autonomous operations (3 Nov 2026 15:37) §7 and §11 "high-volume scans of providers known to be ineligible"; IQ-00041, IQ-00058'),
 ('pipeline', 'batch.scholarship_discovery_settle', 'Scholarship discovery: rows given an outcome or returned per run',
  'At most this many discovery rows are given the not_eligible outcome, and at most this many returned, in one run of scholarship-discovery-settle.',
  'number', to_jsonb(1000), 50, 10000, 'rows', 1051, 'Scholarships', 'security.scholarship_discovery_settle_v1 (job scholarship-discovery-settle)',
  'CF-247 P0 autonomous operations §7 (1,343 refused rows live on 3 Nov 2026)'),
 ('pipeline', 'coverage.reconcile_on', 'Coverage reconciliation: run',
  'On: every hour, each active provider''s scholarships and entry requirements are compared with what its sources list, and the result is kept on the coverage ledger. Read-only over the catalogue.',
  'boolean', 'true'::jsonb, null, null, null, 1100, 'Coverage reconciliation', 'security.coverage_reconcile_v1 (job coverage-reconcile)',
  'CF-247 P0 autonomous operations §5 and §12'),
 ('pipeline', 'coverage.investigations_on', 'Coverage reconciliation: open provider investigations',
  'On: a provider whose coverage has a gap gets one provider-level coverage investigation per domain in the integration queue (updated, never duplicated). Off: the ledger is kept but no issue is opened.',
  'boolean', 'true'::jsonb, null, null, null, 1101, 'Coverage reconciliation', 'security.coverage_reconcile_v1 (job coverage-reconcile)',
  'CF-247 P0 autonomous operations §5 "open a provider-level coverage investigation rather than creating unrelated individual exceptions"'),
 ('pipeline', 'coverage.investigations_per_run', 'Coverage reconciliation: new investigations per run',
  'At most this many new provider investigations are opened in one run (largest shortfall first). Investigations already open are always updated. The rest wait for the next run and are counted in its answer.',
  'number', to_jsonb(25), 0, 500, 'issues', 1102, 'Coverage reconciliation', 'security.coverage_reconcile_v1 (job coverage-reconcile)',
  'CF-247 P0 autonomous operations §16 "avoid repetitive notifications"'),
 ('pipeline', 'coverage.provider_level_types', 'Coverage reconciliation: provider types investigated one by one',
  'Providers of these types are expected to publish scholarships and entry requirements: a gap opens an investigation for the provider itself, even with no listing evidence. Other providers are investigated one by one only when a listing or register shows what is missing, and are otherwise grouped per country and gap.',
  'list', '["university", "university_college", "tafe_polytechnic", "wananga"]'::jsonb, null, null, 'provider types', 1103, 'Coverage reconciliation',
  'security.scholarship_coverage_v1; security.aer_coverage_v1; security.coverage_reconcile_v1', 'CF-247 P0 autonomous operations §5 "a university with zero scholarships"'),
 ('pipeline', 'coverage.sch_represented_min_pct', 'Scholarship coverage: share of the listing the catalogue must hold',
  'A provider is under-represented when its admitted scholarships are fewer than this share of the largest count its sources list (national register, listing items, a stated total or listing members).',
  'number', to_jsonb(50), 5, 100, 'percent', 1104, 'Coverage reconciliation', 'security.scholarship_coverage_v1', 'CF-247 P0 autonomous operations §5 "substantially more eligible scholarships than the catalogue"'),
 ('pipeline', 'coverage.sch_listing_min_items', 'Scholarship coverage: listing size before the share is tested',
  'The under-representation test runs only when a source lists at least this many scholarships for the provider.',
  'number', to_jsonb(5), 1, 500, 'scholarships', 1105, 'Coverage reconciliation', 'security.scholarship_coverage_v1', 'CF-247 P0 autonomous operations §5'),
 ('pipeline', 'coverage.sch_category_min_items', 'Scholarship coverage: listed items before a category counts as missing',
  'A category (research, undergraduate, postgraduate, international) is missing when the sources list at least this many items of it and the catalogue holds none.',
  'number', to_jsonb(2), 1, 100, 'scholarships', 1106, 'Coverage reconciliation', 'security.scholarship_coverage_v1', 'CF-247 P0 autonomous operations §5 "missing categories"'),
 ('pipeline', 'coverage.sch_category_levels', 'Scholarship coverage: study levels of each category',
  'Each entry is category=level code|level code. A held scholarship counts in a category when one of its study-level scopes is listed here, or its name matches the category''s pattern.',
  'list', '["research=doctorate|masters_research", "postgraduate=masters_coursework|masters|masters_extended|graduate_certificate|graduate_diploma", "undergraduate=bachelor|bachelor_honours|associate_degree|diploma|advanced_diploma"]'::jsonb,
  null, null, 'categories', 1107, 'Coverage reconciliation', 'security.scholarship_coverage_v1', 'CF-247 P0 autonomous operations §5 (research, undergraduate, postgraduate)'),
 ('pipeline', 'coverage.sch_category_patterns', 'Scholarship coverage: name patterns of each category',
  'Each entry is category=pattern (a case-insensitive regular expression). Listed items (register name and level, listing item names) and held scholarship names are counted in a category when they match.',
  'list', '["research=research|phd|doctor|hdr|higher degree", "postgraduate=postgraduate|master|\\mgraduate", "undergraduate=undergraduate|bachelor|vet|diploma"]'::jsonb,
  null, null, 'categories', 1108, 'Coverage reconciliation', 'security.scholarship_coverage_v1', 'CF-247 P0 autonomous operations §5'),
 ('pipeline', 'coverage.aer_course_min_pct', 'Entry requirement coverage: courses with a stored page that must have requirements',
  'Course-level entry requirements are a gap when fewer than this share of the provider''s courses with a stored official page have a requirement row (active or waiting in Layer 4).',
  'number', to_jsonb(20), 1, 100, 'percent', 1109, 'Coverage reconciliation', 'security.aer_coverage_v1', 'CF-247 P0 autonomous operations §5 "course-level requirements"'),
 ('pipeline', 'coverage.intake_min_pct', 'Entry requirement coverage: active courses with an intake',
  'Intakes are a gap when fewer than this share of the provider''s active courses have an intake with a start date.',
  'number', to_jsonb(50), 1, 100, 'percent', 1110, 'Coverage reconciliation', 'security.aer_coverage_v1', 'CF-247 P0 autonomous operations §5 "intake and application deadlines"'),
 ('pipeline', 'coverage.deadline_min_pct', 'Entry requirement coverage: active courses with an application deadline',
  'Application deadlines are a gap when fewer than this share of the provider''s active courses have an intake with an application deadline.',
  'number', to_jsonb(25), 1, 100, 'percent', 1111, 'Coverage reconciliation', 'security.aer_coverage_v1', 'CF-247 P0 autonomous operations §5'),
 ('pipeline', 'coverage.sch_field_min_pct', 'Scholarship coverage: share of held scholarships that must carry each fact',
  'A fact a student needs (funding type, value, application dates, study level, academic requirements, residency requirements) is a gap when fewer than this share of the provider''s held scholarships carry it (tested once it holds coverage.sch_category_min_items or more).',
  'number', to_jsonb(50), 5, 100, 'percent', 1114, 'Coverage reconciliation', 'security.scholarship_coverage_v1', 'CF-247 P0 acceptance mandate 3 Nov 2026 15:52 §8 (funding type, value, dates, study level, academic and residency requirements)'),
 ('pipeline', 'coverage.sch_gap_fields', 'Scholarship coverage: facts whose absence is a gap',
  'The facts tested against coverage.sch_field_min_pct. The others (academic and residency requirements, country eligibility) are measured and shown on the ledger, but many scholarships genuinely have none, so their absence is not a gap unless listed here.',
  'list', '["funding_type", "value", "application_dates", "study_level"]'::jsonb, null, null, 'facts', 1119, 'Coverage reconciliation', 'security.scholarship_coverage_v1',
  'CF-247 P0 acceptance mandate 3 Nov 2026 15:52 §8; live 3 Nov 2026: 353 academic minimums across 2,180 scholarships, so a missing one is not evidence of a gap'),
 ('pipeline', 'coverage.sch_not_applicable_types', 'Scholarship coverage: provider types never in scope',
  'Providers of these types are never eligible for scholarships (the national register also lists schools): they are recorded as not_applicable, with no gap.',
  'list', '["school"]'::jsonb, null, null, 'provider types', 1120, 'Coverage reconciliation', 'security.scholarship_coverage_v1',
  'Scholarship pilot plan 3 Nov 2026 §3 "Schools are never eligible"; live: 375 register listings are for secondary schooling'),
 ('pipeline', 'coverage.aer_pathways', 'Entry requirement coverage: qualification pathways checked',
  'Each entry is pathway=pattern (case-insensitive, matched on the applicant country code, qualification name and level label). A pathway is a gap for a provider only when one of its entry-requirement sources names it and no held row (active or waiting in Layer 4) matches.',
  'list', '["IB=international baccalaureate|\\mIB\\M", "GCE A Level=a[ -]?levels?\\M|\\mgce\\M", "Nepal=\\mNP\\M|nepal|\\mNEB\\M|\\mHSEB\\M", "India=\\mIN\\M|india|\\mCBSE\\M|\\mISC\\M", "China=\\mCN\\M|china|gaokao", "US High School=\\mUS\\M|united states|american high school"]'::jsonb,
  null, null, 'pathways', 1115, 'Coverage reconciliation', 'security.aer_coverage_v1', 'CF-247 P0 acceptance mandate 3 Nov 2026 15:52 §8 (IB and country pathways such as Nepal)'),
 ('pipeline', 'batch.coverage_reconcile', 'Coverage reconciliation: providers looked at per run and domain',
  'At most this many providers of each domain are reconciled in one run: new or changed first, then open discrepancies due a recheck, then the periodic broad check.',
  'number', to_jsonb(300), 20, 5000, 'providers', 1116, 'Coverage reconciliation', 'security.coverage_due_v1; security.coverage_reconcile_v1 (job coverage-reconcile)', 'CF-247 P0 acceptance mandate 3 Nov 2026 15:52 §8 "avoid scanning the whole catalogue every hour"'),
 ('pipeline', 'coverage.discrepancy_recheck_hours', 'Coverage reconciliation: recheck a provider with a gap after',
  'A provider with an open coverage gap is reconciled again after this long even when nothing about it changed.',
  'number', to_jsonb(6), 1, 168, 'hours', 1117, 'Coverage reconciliation', 'security.coverage_due_v1', 'CF-247 P0 acceptance mandate §8 "prioritise providers with measurable coverage discrepancies"'),
 ('pipeline', 'coverage.broad_check_hours', 'Coverage reconciliation: every provider is reconciled at least every',
  'The periodic broad check: a provider not reconciled for this long is taken again, oldest first.',
  'number', to_jsonb(24), 6, 720, 'hours', 1118, 'Coverage reconciliation', 'security.coverage_due_v1', 'CF-247 P0 acceptance mandate §8 "periodic broader validation"'),
 ('pipeline', 'coverage.remedy_max_attempts', 'Coverage remedies: attempts before escalation',
  'The operations controller runs a coverage remedy at most this many times for one issue before it escalates the issue.',
  'number', to_jsonb(3), 1, 10, 'attempts', 1112, 'Coverage reconciliation', 'pipeline.ops_remedies (sch_discovery_settle, coverage_investigation, aer_course_counts)',
  'CF-247 P0 autonomous operations §3 "must not continue retrying indefinitely"'),
 ('pipeline', 'coverage.remedy_cooldown_minutes', 'Coverage remedies: wait between attempts',
  'The operations controller waits at least this long between two runs of a coverage remedy for the same issue.',
  'number', to_jsonb(60), 10, 1440, 'minutes', 1113, 'Coverage reconciliation', 'pipeline.ops_remedies (sch_discovery_settle, coverage_investigation, aer_course_counts)',
  'CF-247 P0 autonomous operations §3')
on conflict do nothing;

-- 2. the outcome of a refused discovery row (additive columns) and the coverage ledger ----------------------------------------------------
alter table pipeline.scholarship_discovery_providers add column if not exists settled_at timestamptz;
alter table pipeline.scholarship_discovery_providers add column if not exists settled_from text;
alter table pipeline.scholarship_discovery_providers add column if not exists settle_reason text;
comment on column pipeline.scholarship_discovery_providers.settle_reason is 'CF-247 workstream C: why discovery can never take this row now (unpublished, search_off, directory_site, not_eligible), set with status not_eligible by security.scholarship_discovery_settle_v1; cleared when the row returns.';
comment on column pipeline.scholarship_discovery_providers.settled_from is 'CF-247 workstream C: the status the row had when it was given the not_eligible outcome; it returns to it when the reason clears.';

create table if not exists pipeline.coverage_provider_reconciliation (
  domain text not null check (domain in ('scholarship', 'aer')),
  provider_id uuid not null references catalogue.providers(id),
  country text,
  provider_name text,
  provider_type text,
  disposition text not null,
  measures jsonb not null default '{}'::jsonb,
  categories jsonb not null default '{}'::jsonb,
  gaps text[] not null default '{}',
  shortfall int not null default 0,
  issue_fingerprint text,
  first_seen timestamptz not null default now(),
  disposition_since timestamptz not null default now(),
  previous_disposition text,
  computed_at timestamptz not null default now(),
  primary key (domain, provider_id)
);
comment on table pipeline.coverage_provider_reconciliation is 'CF-247 P0 autonomous operations (3 Nov 2026) §5 and §12, workstream C: the permanent provider-to-record coverage ledger, one row per domain (scholarship, aer) and active provider: what the provider''s sources list (listing pages and items, national register, entry-requirement sources and manifests, stored course pages) against what the catalogue holds (admitted, held, rejected and pending records, by category; matrix and course-level requirements, intakes and deadlines), the gaps found and the integration-queue fingerprint of its investigation. Written hourly by security.coverage_reconcile_v1 (job coverage-reconcile); a provider that leaves the population is marked out_of_scope, never removed. Never read by the consumer API.';
create index if not exists coverage_provider_reconciliation_disp_idx on pipeline.coverage_provider_reconciliation (domain, disposition);
alter table pipeline.coverage_provider_reconciliation enable row level security;
revoke all on pipeline.coverage_provider_reconciliation from public, anon, authenticated;

-- 3. discovery outcome for refused providers -----------------------------------------------------------------------------------------------
create or replace function security.scholarship_discovery_hold_reason_v1(p_provider uuid, p_website text)
returns text language sql stable security definer set search_path to '' as $function$
  -- CF-247 workstream C: the standing reasons public.svc_scholarship_discover_next refuses a provider (its holds, without the credit cap, which
  -- passes by itself); null when discovery can take it. Eligibility is enforced only while the Firecrawl daily budget is on, as in the picker.
  select case
    when exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider) then 'unpublished'
    when security.provider_sch_search_off_v1(p_provider) then 'search_off'
    when security.third_party_host_v1(coalesce(p_website, '')) then 'directory_site'
    when coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false)
         and not security.fc_sch_eligible_v1(p_provider) then 'not_eligible' end
$function$;
revoke all on function security.scholarship_discovery_hold_reason_v1(uuid, text) from public, anon, authenticated;
comment on function security.scholarship_discovery_hold_reason_v1(uuid, text) is 'CF-247 workstream C: why scholarship discovery can never take this provider now (unpublished, search_off, directory_site, not_eligible), or null. The picker''s holds without the credit cap. Read-only.';

create or replace function security.scholarship_discovery_settle_v1(p_limit int default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 workstream C (IQ-00041, IQ-00058): discovery rows the picker can never take end with the outcome not_eligible and their reason, instead of
-- waiting as pending and being re-held every retry.scholarship_discovery_held_hours; a mapped or empty row is settled only once it is due (or was
-- re-held). Rows return to the status they came from, due (a mapped or empty row not before its re-read date), when the reason clears.
-- updated_at is not touched: it is the platform health check's "last progress" for discovery.
declare v_lim int := greatest(0, coalesce(p_limit, security.pipeline_num_v1('batch.scholarship_discovery_settle', 1000)::int));
        v_hold interval := make_interval(hours => security.pipeline_num_v1('retry.scholarship_discovery_held_hours', 6)::int);
        v_reread interval := make_interval(days => security.pipeline_num_v1('reread.scholarship_discovery_days', 30)::int);
        v_settled int := 0; v_restored int := 0; v_by jsonb; v_back jsonb;
begin
  if not security.scholarship_flag_v1('scholarship.discovery_settle_on', true) then
    return jsonb_build_object('on', false, 'settled', 0, 'restored', 0);
  end if;
  with c as (
    select d.provider_id, d.status, security.scholarship_discovery_hold_reason_v1(d.provider_id, d.website) why
      from pipeline.scholarship_discovery_providers d
     where coalesce(d.leased_until, '-infinity') < now()
       and (d.status in ('pending', 'deferred') or (d.status in ('mapped', 'empty') and d.next_discover_at is not null and d.next_discover_at <= now() + v_hold))),
  pick as (select c.* from c where c.why is not null order by c.provider_id limit v_lim),
  upd as (update pipeline.scholarship_discovery_providers d set status = 'not_eligible', settled_from = pick.status, settle_reason = pick.why, settled_at = now(),
                 next_discover_at = null, leased_until = null
            from pick where d.provider_id = pick.provider_id returning pick.why)
  select count(*), coalesce(jsonb_object_agg(why, n), '{}'::jsonb) into v_settled, v_by
    from (select why, count(*) n from upd group by why) g;
  v_settled := coalesce((select sum(value::int) from jsonb_each_text(v_by)), 0);
  -- settled rows, longest unchecked first: those whose reason has cleared return; the others keep the outcome with today's reason
  with w as (
    select d.provider_id, d.settle_reason, security.scholarship_discovery_hold_reason_v1(d.provider_id, d.website) why from pipeline.scholarship_discovery_providers d
     where d.status = 'not_eligible' order by d.settled_at nulls first, d.provider_id limit v_lim),
  why as (update pipeline.scholarship_discovery_providers d set settle_reason = w.why from w
           where d.provider_id = w.provider_id and w.why is not null and w.why is distinct from w.settle_reason returning d.provider_id),
  upd as (update pipeline.scholarship_discovery_providers d set status = coalesce(d.settled_from, 'pending'),
                 next_discover_at = case when coalesce(d.settled_from, 'pending') in ('mapped', 'empty') then greatest(now(), coalesce(d.discovered_at, '-infinity') + v_reread) else now() end,
                 settle_reason = null, settled_from = null, settled_at = now()
            from w where d.provider_id = w.provider_id and w.why is null returning d.status)
  select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) into v_back from (select status, count(*) n from upd group by status) g;
  v_restored := coalesce((select sum(value::int) from jsonb_each_text(v_back)), 0);
  return jsonb_build_object('on', true, 'settled', v_settled, 'settled_by_reason', v_by, 'restored', v_restored, 'restored_to', v_back,
    'waiting_takeable', (select count(*) from pipeline.scholarship_discovery_providers d where d.status in ('pending', 'deferred')),
    'not_eligible', (select count(*) from pipeline.scholarship_discovery_providers d where d.status = 'not_eligible'));
end $function$;
revoke all on function security.scholarship_discovery_settle_v1(int) from public, anon, authenticated;
comment on function security.scholarship_discovery_settle_v1(int) is 'CF-247 workstream C (IQ-00041, IQ-00058; P0 mandate §7, §11): job scholarship-discovery-settle. Scholarship discovery rows the picker can never take get the outcome not_eligible with the reason, and return to their status, due, when the reason clears. Switch scholarship.discovery_settle_on; size batch.scholarship_discovery_settle. No read, no spend.';

-- 4. scholarship coverage per provider (read-only) -----------------------------------------------------------------------------------------
create or replace function security.coverage_kv_v1(p_key text) returns table(k text, v text)
language sql stable security definer set search_path to '' as $function$
  -- a pipeline list setting of 'name=value' entries as rows
  select btrim(split_part(x, '=', 1)), btrim(substr(x, strpos(x, '=') + 1))
    from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', p_key), '[]'::jsonb)) x where strpos(x, '=') > 1
$function$;
revoke all on function security.coverage_kv_v1(text) from public, anon, authenticated;
comment on function security.coverage_kv_v1(text) is 'CF-247 workstream C: a pipeline list setting of name=value entries (coverage.sch_category_levels, coverage.sch_category_patterns, coverage.aer_pathways) as rows. Read-only.';

create or replace function security.scholarship_coverage_v1(p_providers uuid[] default null)
returns table(provider_id uuid, country text, provider_name text, provider_type text, disposition text, measures jsonb, categories jsonb, gaps text[], shortfall int)
language sql stable security definer set search_path to '' as $function$
  -- CF-247 workstream C (P0 mandates 3 Nov 2026 15:37 §5, §12 and 15:52 §8): each active, published provider of a scholarship country (or only
  -- p_providers), what its sources list against what the catalogue holds. Anchors are independent of the discovery list: the national register,
  -- listing pages and their items, a stated total, listing members. Held records are also measured for the facts a student needs (funding type,
  -- value, application dates, study level, academic and residency requirements, country-specific eligibility). Read-only.
  with s as (select security.pipeline_num_v1('coverage.sch_represented_min_pct', 50) pct, security.pipeline_num_v1('coverage.sch_listing_min_items', 5) minl,
                    security.pipeline_num_v1('coverage.sch_category_min_items', 2) minc, security.pipeline_num_v1('coverage.sch_field_min_pct', 50) fpct,
                    coalesce(security.toolset_setting('pipeline', 'coverage.provider_level_types'), '[]'::jsonb) pl,
                    coalesce(security.toolset_setting('pipeline', 'coverage.sch_gap_fields'), '[]'::jsonb) gf,
                    coalesce(security.toolset_setting('pipeline', 'coverage.sch_not_applicable_types'), '[]'::jsonb) na),
  cat as (select k cat, v pat from security.coverage_kv_v1('coverage.sch_category_patterns')),
  lev as (select k cat, unnest(string_to_array(v, '|')) code from security.coverage_kv_v1('coverage.sch_category_levels')),
  pv as (select p.id, k.iso_alpha2::text cc, coalesce(p.display_name, p.short_name, p.canonical_name) nm, t.code ptype
           from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
          where k.scholarship_ingestion_enabled and p.lifecycle_status = 'active' and p.publication_status = 'published'
            and (p_providers is null or p.id = any (p_providers))),
  lp as (select l.provider_id, count(*) pages, count(*) filter (where l.read_at is not null) pages_read,
                count(*) filter (where l.page_state = 'complete' or l.completed_at is not null) pages_complete, coalesce(max(l.total_stated), 0) stated,
                coalesce(sum(case when jsonb_typeof(l.items) = 'array' then jsonb_array_length(l.items) else 0 end), 0) items
           from pipeline.scholarship_listing_pages l join pv on pv.id = l.provider_id
          where l.active and l.source in ('manual', 'auto') and not security.third_party_host_v1(coalesce(l.url, '')) group by 1),
  -- every listed name with the anchor it came from: register (name and level; the register lists awards open to international students),
  -- listing items, listing members
  ln as (select r.provider_id, 'register' src, coalesce(r.name, '') || ' ' || coalesce(r.level_text, '') txt, true intl
           from scholarship.register_listings r join pv on pv.id = r.provider_id where r.departed_at is null
         union all
         select l.provider_id, 'listing', coalesce(i->>'name', ''), coalesce(i->>'name', '') ~* 'international'
           from pipeline.scholarship_listing_pages l join pv on pv.id = l.provider_id
           cross join lateral jsonb_array_elements(case when jsonb_typeof(l.items) = 'array' then l.items else '[]'::jsonb end) i
          where l.active and l.source in ('manual', 'auto') and not security.third_party_host_v1(coalesce(l.url, ''))
         union all
         select m.provider_id, 'member', coalesce(m.name, ''), coalesce(m.name, '') ~* 'international'
           from pipeline.scholarship_listing_members m join pv on pv.id = m.provider_id where m.present),
  lc as (select ln.provider_id, cat.cat, count(*) filter (where ln.txt ~* cat.pat) n from ln cross join cat group by 1, 2),
  li as (select ln.provider_id, count(*) filter (where ln.src = 'register') reg, count(*) filter (where ln.src = 'member') members,
                count(*) filter (where ln.intl) intl from ln group by 1),
  ru as (select r.provider_id, count(*) unmatched from scholarship.register_listings r join pv on pv.id = r.provider_id
          where r.departed_at is null and r.scholarship_id is null group by 1),
  ca as (select c.provider_id, count(*) n, count(*) filter (where c.admit_status is null and c.matched_scholarship_id is null) pending,
                count(*) filter (where c.admit_status = 'rejected') rejected,
                count(*) filter (where c.admitted_scholarship_id is not null or c.matched_scholarship_id is not null) linked
           from pipeline.scholarship_page_candidates c join pv on pv.id = c.provider_id group by 1),
  ar as (select x.provider_id, count(*) archived from scholarship.scholarships x join pv on pv.id = x.provider_id where x.lifecycle_status <> 'active' group by 1),
  sc as (select x.* from scholarship.scholarships x join pv on pv.id = x.provider_id where x.lifecycle_status = 'active'),
  sf as (select sc.id, sc.provider_id,
                sc.award_value_type is not null f_funding,
                (sc.award_amount is not null or sc.award_percentage is not null or nullif(btrim(coalesce(sc.award_value_text, '')), '') is not null
                 or exists (select 1 from scholarship.award_tiers a where a.scholarship_id = sc.id)) f_value,
                (sc.application_close_date is not null or sc.application_open_date is not null
                 or exists (select 1 from scholarship.application_windows w where w.scholarship_id = sc.id and (w.opens_at is not null or w.closes_at is not null))) f_dates,
                exists (select 1 from scholarship.scopes o where o.scholarship_id = sc.id and o.study_level_id is not null) f_level,
                exists (select 1 from scholarship.criteria c where c.scholarship_id = sc.id and c.criterion_type in ('academic_minimum', 'institution_admission')) f_academic,
                (sc.audience is not null and sc.audience <> 'not_stated'
                 or exists (select 1 from scholarship.criteria c where c.scholarship_id = sc.id and c.criterion_type in ('student_type', 'nationality', 'citizenship_and_residency',
                            'citizenship_residency_restriction', 'visa_requirement'))) f_residency,
                coalesce(cardinality(sc.nationalities), 0) > 0 f_country
           from sc),
  so as (select sc.provider_id, count(*) active, count(*) filter (where sc.publication_status = 'published') published,
                count(*) filter (where sc.publication_status <> 'published' or exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = sc.id and h.released_at is null)) held,
                count(*) filter (where exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = sc.id and r.status = 'pending')) layer4,
                count(*) filter (where sc.audience in ('international', 'international_and_domestic')) intl,
                count(*) filter (where sc.audience = 'domestic') domestic
           from sc group by 1),
  sfa as (select sf.provider_id, jsonb_build_object('funding_type', count(*) filter (where f_funding), 'value', count(*) filter (where f_value),
                   'application_dates', count(*) filter (where f_dates), 'study_level', count(*) filter (where f_level),
                   'academic_requirements', count(*) filter (where f_academic), 'residency_requirements', count(*) filter (where f_residency),
                   'country_eligibility', count(*) filter (where f_country)) f from sf group by 1),
  scc as (select sc.provider_id, cat.cat,
                 count(distinct sc.id) filter (where sc.name ~* cat.pat or exists (select 1 from scholarship.scopes o join ref.study_levels sl on sl.id = o.study_level_id
                                                                                    join lev on lev.code = sl.code and lev.cat = cat.cat
                                                                                   where o.scholarship_id = sc.id and o.include_exclude is distinct from 'exclude')) n
            from sc cross join cat group by 1, 2),
  d as (select pv.*, dp.status disc, dp.settle_reason, coalesce(lp.pages, 0) pages, coalesce(lp.pages_read, 0) pages_read, coalesce(lp.pages_complete, 0) pages_complete,
               coalesce(lp.stated, 0) stated, coalesce(lp.items, 0) items, coalesce(li.reg, 0) reg, coalesce(ru.unmatched, 0) reg_unmatched, coalesce(li.members, 0) members,
               coalesce(li.intl, 0) list_intl, coalesce(ca.n, 0) cands, coalesce(ca.pending, 0) cand_pending, coalesce(ca.rejected, 0) cand_rejected, coalesce(ca.linked, 0) cand_linked,
               coalesce(so.active, 0) active, coalesce(so.published, 0) published, coalesce(so.held, 0) held, coalesce(so.layer4, 0) layer4, coalesce(ar.archived, 0) archived,
               coalesce(so.intl, 0) sch_intl, coalesce(so.domestic, 0) domestic, coalesce(sfa.f, '{}'::jsonb) fields,
               coalesce((select jsonb_object_agg(lc.cat, lc.n) from lc where lc.provider_id = pv.id), '{}'::jsonb) list_cat,
               coalesce((select jsonb_object_agg(scc.cat, scc.n) from scc where scc.provider_id = pv.id), '{}'::jsonb) sch_cat,
               coalesce(pv.ptype, '') in (select jsonb_array_elements_text(s.pl)) plevel, coalesce(pv.ptype, '') in (select jsonb_array_elements_text(s.na)) na,
               security.scholarship_admission_provider_ok_v1(pv.id) admit_ok, s.gf, s.pct, s.minl, s.minc, s.fpct
          from pv cross join s left join pipeline.scholarship_discovery_providers dp on dp.provider_id = pv.id left join lp on lp.provider_id = pv.id
          left join li on li.provider_id = pv.id left join ru on ru.provider_id = pv.id left join ca on ca.provider_id = pv.id left join so on so.provider_id = pv.id
          left join ar on ar.provider_id = pv.id left join sfa on sfa.provider_id = pv.id),
  a as (select d.*, greatest(d.reg, d.items, d.stated, d.members) anchor from d),
  g as (select a.*, case
         -- never in scope (schools), or refused by the admission rule (non-university providers while the pilot does not cover them):
         -- recorded, with the policy as the only gap, never as missing data
         when a.na then '{}'::text[]
         when not a.admit_ok and not a.plevel then case when a.anchor > 0 then array['admission_policy'] else '{}'::text[] end
         else array_remove(array[
           case when a.active = 0 and (a.plevel or a.anchor > 0) then 'zero_scholarships' end,
           case when a.anchor >= a.minl and a.active * 100 < a.pct * a.anchor then 'under_represented' end,
           case when (a.plevel or a.anchor > 0) and (a.disc is null or a.disc = 'not_eligible') then 'not_searched' end,
           case when a.pages > 0 and a.pages_complete = 0 then 'listing_partial' end,
           case when a.items > 0 and a.members = 0 then 'listing_not_fanned_out' end,
           case when a.list_intl >= a.minc and a.sch_intl = 0 then 'category_missing:international' end]
           || coalesce(array(select 'category_missing:' || e.key from jsonb_each_text(a.list_cat) e
                              where e.value::int >= a.minc and coalesce((a.sch_cat->>e.key)::int, 0) = 0 order by e.key), '{}')
           -- a fact a student needs, held for too few of the provider's scholarships (only once it holds enough to judge)
           || coalesce(array(select 'fields_incomplete:' || e.key from jsonb_each_text(a.fields) e
                              where a.active >= a.minc and a.gf ? e.key and e.value::int * 100 < a.fpct * a.active order by e.key), '{}'), null) end gaps
          from a)
  select g.id, g.cc, g.nm, g.ptype,
         case when g.na then 'not_applicable'
              when 'admission_policy' = any (g.gaps) then 'blocked_policy'
              when 'zero_scholarships' = any (g.gaps) then 'zero'
              when 'under_represented' = any (g.gaps) then 'under_represented'
              when exists (select 1 from unnest(g.gaps) x where x like 'category_missing:%') then 'category_gap'
              when 'not_searched' = any (g.gaps) then 'not_searched'
              when exists (select 1 from unnest(g.gaps) x where x like 'fields_incomplete:%') then 'fields_incomplete'
              when cardinality(g.gaps) > 0 then 'partial_listing'
              when g.anchor > 0 then 'represented'
              when g.active > 0 then 'records_without_listing'
              else 'no_evidence' end,
         jsonb_build_object('discovery', g.disc, 'discovery_reason', g.settle_reason, 'listing_pages', g.pages, 'listing_pages_read', g.pages_read,
           'listing_pages_complete', g.pages_complete, 'listing_items', g.items, 'listing_stated', g.stated, 'listing_members', g.members,
           'register', g.reg, 'register_unmatched', g.reg_unmatched, 'anchor', g.anchor, 'candidates', g.cands, 'candidates_pending', g.cand_pending,
           'candidates_rejected', g.cand_rejected, 'candidates_linked', g.cand_linked, 'admitted', g.active, 'published', g.published, 'held', g.held,
           'layer4_pending', g.layer4, 'archived', g.archived, 'international', g.sch_intl, 'domestic_only', g.domestic, 'fields', g.fields, 'provider_level', g.plevel,
           'admission_ok', g.admit_ok),
         jsonb_build_object('listed', g.list_cat || jsonb_build_object('international', g.list_intl), 'held', g.sch_cat || jsonb_build_object('international', g.sch_intl)),
         g.gaps, greatest(0, g.anchor - g.active)::int
    from g
$function$;
revoke all on function security.scholarship_coverage_v1(uuid[]) from public, anon, authenticated;
comment on function security.scholarship_coverage_v1(uuid[]) is 'CF-247 workstream C (P0 mandates 3 Nov 2026 §5/§12 and §8): per active scholarship-country provider (or the providers given), listing and register anchors against candidates, admitted, published, held, Layer 4 and archived scholarships, by category (coverage.sch_category_levels, coverage.sch_category_patterns) and by the facts held (funding type, value, dates, study level, academic and residency requirements, country eligibility), with gaps and a disposition. Read-only.';

-- 5. AER coverage per provider (read-only) -------------------------------------------------------------------------------------------------
create or replace function security.aer_coverage_v1(p_providers uuid[] default null)
returns table(provider_id uuid, country text, provider_name text, provider_type text, disposition text, measures jsonb, categories jsonb, gaps text[], shortfall int)
language sql stable security definer set search_path to '' as $function$
  -- CF-247 workstream C (P0 mandates 3 Nov 2026 §5/§12 and §8): each AER-eligible provider (security.aer_eligible_v1), plus every provider of a
  -- provider-level type in an AER country that the eligibility rule leaves out (so a major registered provider is never silently omitted), with
  -- what its sources list against what is held: entry-requirement sources and their manifests (published cells, countries and pathways named),
  -- matrix rows by applicant country, qualification (curriculum) and study level, the pathways in coverage.aer_pathways (IB, A Levels, Nepal and
  -- so on: a gap only where a source of the provider names the pathway), rows that are domestic only (never read as universal), course-level
  -- requirements on courses whose official page is bound, effective period, intakes and application deadlines. Each gap carries the input through
  -- which the scheduled AER reader can act on it (route). The AER disposition is read from pipeline.aer_provider_coverage. Read-only.
  with s as (select security.pipeline_num_v1('coverage.aer_course_min_pct', 20) cpct, security.pipeline_num_v1('coverage.intake_min_pct', 50) ipct,
                    security.pipeline_num_v1('coverage.deadline_min_pct', 25) dpct,
                    coalesce(security.toolset_setting('pipeline', 'coverage.provider_level_types'), '[]'::jsonb) pl),
  pw as (select k label, v pat from security.coverage_kv_v1('coverage.aer_pathways')),
  el as (select e.provider_id, e.country, true eligible from security.aer_eligible_v1() e
         union all
         select p.id, k.iso_alpha2::text, false from catalogue.providers p join ref.countries k on k.id = p.country_id join ref.provider_types t on t.id = p.provider_type_id
          cross join s
          where k.iso_alpha2::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb)))
            and p.lifecycle_status = 'active' and p.publication_status = 'published' and t.code in (select jsonb_array_elements_text(s.pl))
            and not exists (select 1 from security.aer_eligible_v1() e where e.provider_id = p.id)),
  pv as (select el.provider_id id, el.country cc, el.eligible, coalesce(p.display_name, p.short_name, p.canonical_name) nm, t.code ptype, p.enrols_international
           from el join catalogue.providers p on p.id = el.provider_id left join ref.provider_types t on t.id = p.provider_type_id
          where p_providers is null or el.provider_id = any (p_providers)),
  src as (select x.provider_id, count(*) n, count(*) filter (where x.status = 'read') nread, count(*) filter (where x.status = 'failed') nfail
            from pipeline.entry_matrix_sources x join pv on pv.id = x.provider_id group by 1),
  mf as (select distinct on (mm.source_id) mm.* from pipeline.aer_source_manifests mm join pv on pv.id = mm.provider_id order by mm.source_id, mm.computed_at desc),
  man as (select mf.provider_id, sum(coalesce(mf.expected_cells, 0)) expected, sum(coalesce(mf.matched_cells, 0)) matched, sum(coalesce(mf.omitted_cells, 0)) omitted,
                 array_remove(array_agg(distinct upper(mf.scope_country)), null) countries,
                 string_agg(coalesce(mf.heading, '') || ' ' || coalesce(mf.scope_label, '') || ' ' || coalesce(mf.sections::text, ''), ' ') txt
            from mf group by 1),
  mxr as (select m.* from catalogue.provider_entry_matrix m join pv on pv.id = m.provider_id),
  mx as (select m.provider_id, count(*) filter (where m.status = 'active') act, count(*) filter (where m.status = 'proposed') prop,
                count(*) filter (where m.status not in ('active', 'proposed')) other,
                array_remove(array_agg(distinct upper(m.country_code)) filter (where m.status in ('active', 'proposed')), null) countries,
                count(distinct upper(m.country_code)) filter (where m.status = 'active') countries_active,
                count(distinct lower(m.qualification_name)) filter (where m.status in ('active', 'proposed')) quals,
                count(distinct lower(m.qualification_name)) filter (where m.status = 'active') quals_active,
                count(distinct coalesce(m.study_level_id::text, m.aer_level, m.level_label)) filter (where m.status in ('active', 'proposed')) levels,
                count(*) filter (where m.status in ('active', 'proposed') and (m.edition is not null or m.intake_year is not null)) dated,
                count(*) filter (where m.status in ('active', 'proposed') and m.audience = 'domestic') domestic,
                count(*) filter (where m.status in ('active', 'proposed') and m.audience <> 'domestic') intl
           from mxr m group by 1),
  pwh as (select m.provider_id, pw.label from mxr m cross join pw
           where m.status in ('active', 'proposed') and (coalesce(m.country_code, '') || ' ' || coalesce(m.qualification_name, '') || ' ' || coalesce(m.level_label, '')) ~* pw.pat
           group by 1, 2),
  pwl as (select man.provider_id, pw.label from man cross join pw where man.txt ~* pw.pat),
  co as (select c.provider_id, c.id from catalogue.courses c join pv on pv.id = c.provider_id where c.lifecycle_status = 'active' and c.open_to_international is not false),
  cs as (select co.provider_id, count(*) courses,
                count(*) filter (where exists (select 1 from pipeline.aer_course_outcomes o where o.course_id = co.id and o.page_status = 'bound')) paged,
                count(*) filter (where exists (select 1 from catalogue.course_entry_requirements r where r.course_id = co.id and r.status = 'active')) req_active,
                count(*) filter (where exists (select 1 from catalogue.course_entry_requirements r where r.course_id = co.id and r.status in ('active', 'proposed'))) req_any,
                count(*) filter (where exists (select 1 from catalogue.course_entry_requirements r where r.course_id = co.id and r.status in ('active', 'proposed'))
                                   and not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = co.id and r.status in ('active', 'proposed') and r.audience <> 'domestic')) req_domestic_only,
                count(*) filter (where exists (select 1 from catalogue.course_entry_requirements r where r.course_id = co.id and r.status in ('active', 'proposed') and r.country_id is not null)) req_country,
                count(*) filter (where exists (select 1 from catalogue.course_intakes i where i.course_id = co.id and i.status = 'active' and (i.start_date is not null or nullif(btrim(coalesce(i.intake_label, '')), '') is not null))) intake,
                count(*) filter (where exists (select 1 from catalogue.course_intakes i where i.course_id = co.id and i.status = 'active' and i.application_deadline is not null)) deadline
           from co group by 1),
  d as (select pv.*, coalesce(src.n, 0) n, coalesce(src.nread, 0) nread, coalesce(src.nfail, 0) nfail, coalesce(man.expected, 0) expected, coalesce(man.matched, 0) matched,
               coalesce(man.omitted, 0) omitted, coalesce(man.countries, '{}') man_countries, coalesce(mx.act, 0) mact, coalesce(mx.prop, 0) mprop, coalesce(mx.other, 0) mother,
               coalesce(mx.countries, '{}') mx_countries, coalesce(mx.countries_active, 0) countries_active, coalesce(mx.quals, 0) quals, coalesce(mx.quals_active, 0) quals_active,
               coalesce(mx.levels, 0) levels, coalesce(mx.dated, 0) dated, coalesce(mx.domestic, 0) mx_domestic, coalesce(mx.intl, 0) mx_intl,
               coalesce(cs.courses, 0) courses, coalesce(cs.paged, 0) paged, coalesce(cs.req_active, 0) req_active, coalesce(cs.req_any, 0) req_any,
               coalesce(cs.req_domestic_only, 0) req_dom, coalesce(cs.req_country, 0) req_country, coalesce(cs.intake, 0) intake, coalesce(cs.deadline, 0) deadline,
               coalesce(array(select pwh.label from pwh where pwh.provider_id = pv.id order by 1), '{}') pathways_held,
               coalesce(array(select pwl.label from pwl where pwl.provider_id = pv.id order by 1), '{}') pathways_listed,
               apc.disposition aer_disposition, coalesce(pv.ptype, '') in (select jsonb_array_elements_text(s.pl)) plevel, s.cpct, s.ipct, s.dpct
          from pv cross join s left join src on src.provider_id = pv.id left join man on man.provider_id = pv.id left join mx on mx.provider_id = pv.id
          left join cs on cs.provider_id = pv.id left join pipeline.aer_provider_coverage apc on apc.provider_id = pv.id),
  g as (select d.*, array(select x from unnest(d.man_countries) x where not x = any (d.mx_countries) order by x) missing_countries,
               array(select x from unnest(d.pathways_listed) x where not x = any (d.pathways_held) order by x) missing_pathways from d),
  h as (select g.*, array_remove(array[
           case when not g.eligible then 'outside_aer_population' end,
           case when g.n = 0 and g.req_any = 0 and g.mact + g.mprop = 0 then 'no_source' end,
           case when g.n > 0 and g.nread = 0 then 'source_unread' end,
           case when g.omitted > 0 then 'cells_omitted' end,
           case when cardinality(g.missing_countries) > 0 then 'countries_missing' end,
           case when g.mx_domestic > 0 and g.mx_intl = 0 or g.req_dom > 0 and g.req_dom = g.req_any then 'domestic_only_source' end,
           case when g.paged > 0 and g.req_any * 100 < g.cpct * g.paged then 'course_level_gap' end,
           case when g.courses > 0 and g.intake * 100 < g.ipct * g.courses then 'intake_gap' end,
           case when g.courses > 0 and g.deadline * 100 < g.dpct * g.courses then 'deadline_gap' end]
           || coalesce(array(select 'pathway_missing:' || x from unnest(g.missing_pathways) x), '{}'), null) gaps from g)
  select h.id, h.cc, h.nm, h.ptype,
         case when cardinality(h.gaps) = 0 then coalesce(h.aer_disposition, 'covered') else coalesce(h.aer_disposition, 'unreconciled') || '+gaps' end,
         jsonb_build_object('eligible', h.eligible, 'enrols_international', h.enrols_international, 'sources', h.n, 'sources_read', h.nread, 'sources_failed', h.nfail,
           'manifest_cells', h.expected, 'manifest_matched', h.matched, 'manifest_omitted', h.omitted, 'matrix_active', h.mact, 'matrix_proposed', h.mprop,
           'matrix_other', h.mother, 'matrix_dated', h.dated, 'matrix_domestic', h.mx_domestic, 'courses', h.courses, 'courses_with_page', h.paged,
           'courses_req_active', h.req_active, 'courses_req_any', h.req_any, 'courses_req_domestic_only', h.req_dom, 'courses_req_country', h.req_country,
           'courses_intake', h.intake, 'courses_deadline', h.deadline, 'aer_disposition', h.aer_disposition, 'provider_level', h.plevel,
           -- the input through which the scheduled AER reader (Release C, D6) acts on each gap
           'routes', jsonb_strip_nulls(jsonb_build_object(
             'outside_aer_population', case when not h.eligible then 'security.aer_eligible_v1 (aer.eligible_countries; provider enrols_international, now ' || coalesce(h.enrols_international::text, 'not recorded') || ')' end,
             'no_source', case when h.n = 0 then 'pipeline.entry_matrix_sources: an entry page must be recorded before security.entry_matrix_enabled_v1 admits the provider' end,
             'source_unread', case when h.n > 0 and h.nread = 0 then 'pipeline.entry_matrix_sources status found: read by entry-matrix-read' end,
             'matrix', case when h.n > 0 then 'pipeline.entry_matrix_sources read_at: due again after entry.matrix_refresh_days (aer-scheduled-read step c)' end,
             'courses_due', case when h.paged > h.req_any then 'security.aer_schedule_courses_v1 (bound page; due unless waiting, tried within aer.schedule_retry_days or locked)' end,
             'courses_without_page', case when h.courses > h.paged then 'pipeline.coverage_course_pages status bound with a stored copy (course page binding, workstream B)' end))),
         jsonb_build_object('countries_listed', to_jsonb(h.man_countries), 'countries_held', to_jsonb(h.mx_countries), 'countries_active', h.countries_active,
           'countries_missing', to_jsonb(h.missing_countries), 'qualifications', h.quals, 'qualifications_active', h.quals_active, 'study_levels', h.levels,
           'pathways_listed', to_jsonb(h.pathways_listed), 'pathways_held', to_jsonb(h.pathways_held), 'pathways_missing', to_jsonb(h.missing_pathways)),
         h.gaps,
         (greatest(0, h.paged - h.req_any) + cardinality(h.missing_countries) + cardinality(h.missing_pathways) + h.omitted + case when h.eligible then 0 else 1 end)::int
    from h
$function$;
revoke all on function security.aer_coverage_v1(uuid[]) from public, anon, authenticated;
comment on function security.aer_coverage_v1(uuid[]) is 'CF-247 workstream C (P0 mandates 3 Nov 2026 §5/§12 and §8): per AER-eligible provider (and each provider-level type the eligibility rule leaves out), sources and manifests against matrix rows by applicant country, qualification and study level, named pathways (coverage.aer_pathways: IB, A Levels, Nepal), domestic-only rows, course-level requirements on courses with a bound page, effective period, intakes and deadlines; each gap with the scheduled AER reader input that acts on it. Read-only.';

-- 6. the reconciliation job: incremental ledger and provider-level investigations ----------------------------------------------------------
create or replace function security.coverage_due_v1(p_domain text, p_limit int default null)
returns table(provider_id uuid, why text) language sql stable security definer set search_path to '' as $function$
  -- CF-247 workstream C (mandate 15:52 §8 "incremental, driven by source or catalogue changes plus periodic broad checks"): the providers a
  -- coverage-reconcile run looks at, at most batch.coverage_reconcile: first those never reconciled or whose sources or records changed since they
  -- were last reconciled, then those with an open discrepancy not rechecked within coverage.discrepancy_recheck_hours (largest shortfall first),
  -- then those not looked at within coverage.broad_check_hours (oldest first). Read-only.
  with s as (select greatest(1, coalesce(p_limit, security.pipeline_num_v1('batch.coverage_reconcile', 300)::int)) lim,
                    make_interval(hours => security.pipeline_num_v1('coverage.discrepancy_recheck_hours', 6)::int) recheck,
                    make_interval(hours => security.pipeline_num_v1('coverage.broad_check_hours', 24)::int) broad),
  l as (select r.provider_id, r.computed_at, r.shortfall, cardinality(r.gaps) > 0 gapped from pipeline.coverage_provider_reconciliation r
         where r.domain = p_domain and r.disposition <> 'out_of_scope'),
  w as (select coalesce(min(l.computed_at), '-infinity') since from l),
  pop as (select x.provider_id from security.aer_eligible_v1() x where p_domain = 'aer'
          union
          -- AER: also every provider of a provider-level type in an AER country, so one the eligibility rule leaves out is still reconciled
          select p.id from catalogue.providers p join ref.countries k on k.id = p.country_id join ref.provider_types t on t.id = p.provider_type_id
           where p_domain = 'aer' and p.lifecycle_status = 'active' and p.publication_status = 'published'
             and k.iso_alpha2::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb)))
             and t.code in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'coverage.provider_level_types'), '[]'::jsonb)))
          union
          select p.id from catalogue.providers p join ref.countries k on k.id = p.country_id
           where p_domain = 'scholarship' and k.scholarship_ingestion_enabled and p.lifecycle_status = 'active' and p.publication_status = 'published'),
  -- change signals since the oldest reconciliation (indexed timestamps only; no full read of the records)
  ch as (select x.provider_id, max(x.at) at from (
           select c.provider_id, greatest(c.found_at, c.read_at, c.admitted_at) at from pipeline.scholarship_page_candidates c, w where p_domain = 'scholarship' and greatest(c.found_at, c.read_at, c.admitted_at) > w.since
           union all select x.provider_id, x.updated_at from scholarship.scholarships x, w where p_domain = 'scholarship' and x.updated_at > w.since
           union all select l.provider_id, l.read_at from pipeline.scholarship_listing_pages l, w where p_domain = 'scholarship' and l.read_at > w.since
           union all select r.provider_id, r.last_seen_at from scholarship.register_listings r, w where p_domain = 'scholarship' and r.provider_id is not null and r.last_seen_at > w.since
           union all select d.provider_id, greatest(d.updated_at, d.settled_at) from pipeline.scholarship_discovery_providers d, w where p_domain = 'scholarship' and greatest(d.updated_at, d.settled_at) > w.since
           union all select x.provider_id, x.updated_at from pipeline.entry_matrix_sources x, w where p_domain = 'aer' and x.updated_at > w.since
           union all select m.provider_id, m.updated_at from catalogue.provider_entry_matrix m, w where p_domain = 'aer' and m.updated_at > w.since
           union all select c.provider_id, r.updated_at from catalogue.course_entry_requirements r join catalogue.courses c on c.id = r.course_id, w where p_domain = 'aer' and r.updated_at > w.since
           union all select a.provider_id, a.updated_at from pipeline.aer_provider_coverage a, w where p_domain = 'aer' and a.updated_at > w.since) x
         where x.provider_id is not null group by 1),
  c as (select pop.provider_id,
               case when l.provider_id is null then 0 when ch.at > l.computed_at then 1 when l.gapped and l.computed_at < now() - s.recheck then 2
                    when l.computed_at < now() - s.broad then 3 end grp,
               case when l.provider_id is null then 'new' when ch.at > l.computed_at then 'changed' when l.gapped and l.computed_at < now() - s.recheck then 'discrepancy'
                    when l.computed_at < now() - s.broad then 'broad' end why,
               coalesce(l.shortfall, 0) shortfall, l.computed_at
          from pop cross join s left join l on l.provider_id = pop.provider_id left join ch on ch.provider_id = pop.provider_id)
  select c.provider_id, c.why from c cross join s where c.grp is not null
   order by c.grp, c.shortfall desc, c.computed_at nulls first, c.provider_id limit (select lim from s)
$function$;
revoke all on function security.coverage_due_v1(text, int) from public, anon, authenticated;
comment on function security.coverage_due_v1(text, int) is 'CF-247 workstream C: the providers one coverage-reconcile run looks at (batch.coverage_reconcile): new or changed since last reconciled first, then open discrepancies due a recheck (coverage.discrepancy_recheck_hours, largest shortfall first), then the periodic broad check (coverage.broad_check_hours). Read-only.';

create or replace function security.coverage_reconcile_v1(p_domain text default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 workstream C (P0 mandates 3 Nov 2026 §5/§12 and §8; job coverage-reconcile): each run takes the providers security.coverage_due_v1 names
-- (changed, discrepant, or due the broad check; never the whole catalogue every hour), refreshes their rows of
-- pipeline.coverage_provider_reconciliation and opens or updates one provider-level coverage investigation per provider and domain
-- (fingerprint coverage:<domain>:<provider id>) through security.integration_issue_upsert_v1. Providers outside coverage.provider_level_types
-- without listing evidence are grouped per domain, country and gap. At most coverage.investigations_per_run new issues a run (largest shortfall
-- first). Nothing is read from the web, nothing is admitted or published.
declare v_new_max int := greatest(0, security.pipeline_num_v1('coverage.investigations_per_run', 25)::int);
        v_issues boolean := security.scholarship_flag_v1('coverage.investigations_on', true);
        v_dom text; r record; v_fp text; v_new int := 0; v_upd int := 0; v_wait int := 0; v_grp int := 0; v_out jsonb := '{}'::jsonb;
        v_ledger int; v_gone int; v_ids uuid[]; v_why jsonb;
begin
  if not security.scholarship_flag_v1('coverage.reconcile_on', true) then return jsonb_build_object('on', false); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:coverage_reconcile'));  -- fixed: one run at a time
  create temp table if not exists cov_now(provider_id uuid, country text, provider_name text, provider_type text, disposition text, measures jsonb,
                                          categories jsonb, gaps text[], shortfall int) on commit drop;
  create temp table if not exists cov_due(provider_id uuid, why text) on commit drop;
  for v_dom in select unnest(array['scholarship', 'aer']) loop
    continue when p_domain is not null and p_domain <> v_dom;
    truncate pg_temp.cov_now;
    truncate pg_temp.cov_due;
    insert into pg_temp.cov_due select * from security.coverage_due_v1(v_dom, null);
    select coalesce(array_agg(x.provider_id), '{}') into v_ids from pg_temp.cov_due x;
    select coalesce(jsonb_object_agg(x.why, x.n), '{}'::jsonb) into v_why from (select x.why, count(*) n from pg_temp.cov_due x group by 1) x;
    if cardinality(v_ids) > 0 then
      if v_dom = 'scholarship' then insert into pg_temp.cov_now select * from security.scholarship_coverage_v1(v_ids);
      else insert into pg_temp.cov_now select * from security.aer_coverage_v1(v_ids); end if;
    end if;
    insert into pipeline.coverage_provider_reconciliation as l(domain, provider_id, country, provider_name, provider_type, disposition, measures, categories, gaps, shortfall, computed_at)
    select v_dom, c.provider_id, c.country, c.provider_name, c.provider_type, c.disposition, c.measures, c.categories, c.gaps, c.shortfall, now() from pg_temp.cov_now c
    on conflict (domain, provider_id) do update set country = excluded.country, provider_name = excluded.provider_name, provider_type = excluded.provider_type,
           previous_disposition = case when l.disposition is distinct from excluded.disposition then l.disposition else l.previous_disposition end,
           disposition_since = case when l.disposition is distinct from excluded.disposition then now() else l.disposition_since end,
           disposition = excluded.disposition, measures = excluded.measures, categories = excluded.categories, gaps = excluded.gaps,
           shortfall = excluded.shortfall, computed_at = now();
    get diagnostics v_ledger = row_count;
    -- a provider looked at that has left the population is marked, never removed
    update pipeline.coverage_provider_reconciliation l set previous_disposition = l.disposition, disposition = 'out_of_scope', disposition_since = now(), computed_at = now()
     where l.domain = v_dom and l.provider_id = any (v_ids) and l.disposition <> 'out_of_scope' and not exists (select 1 from pg_temp.cov_now c where c.provider_id = l.provider_id);
    get diagnostics v_gone = row_count;
    v_new := 0; v_upd := 0; v_wait := 0; v_grp := 0;
    if v_issues then
      -- one investigation per provider: provider-level types, or any provider whose sources list what is missing
      for r in select c.* from pg_temp.cov_now c
                where cardinality(c.gaps) > 0 and ((c.measures->>'provider_level')::boolean or coalesce((c.measures->>'anchor')::int, 0) > 0)
                  and (v_dom = 'aer' or c.gaps && array['zero_scholarships', 'under_represented', 'not_searched']
                       or exists (select 1 from unnest(c.gaps) x where x like 'category_missing:%' or x like 'fields_incomplete:%'))
                order by c.shortfall desc, c.provider_id loop
        v_fp := 'coverage:' || v_dom || ':' || r.provider_id;
        if not exists (select 1 from pipeline.integration_issues i where i.fingerprint = v_fp) then
          if v_new >= v_new_max then v_wait := v_wait + 1; continue; end if;
          v_new := v_new + 1;
        else v_upd := v_upd + 1; end if;
        perform security.integration_issue_upsert_v1(jsonb_build_object(
          'fingerprint', v_fp,
          'title', left(case v_dom when 'scholarship' then 'Scholarship coverage' else 'Entry requirement coverage' end || ': ' || coalesce(r.provider_name, r.provider_id::text)
                   || ' (' || coalesce(r.country, '?') || ') ' || r.disposition || ': ' || array_to_string(r.gaps, ', '), 300),
          'layer', 'Coverage', 'subsystem', case v_dom when 'scholarship' then 'scholarships' else 'entry requirements' end,
          'provider_ids', jsonb_build_array(r.provider_id), 'country_codes', jsonb_build_array(r.country),
          'failure', case v_dom when 'scholarship' then
                       'Sources list ' || coalesce(r.measures->>'anchor', '0') || ' scholarship(s); the catalogue holds ' || coalesce(r.measures->>'admitted', '0')
                       || ' (' || coalesce(r.measures->>'published', '0') || ' published, ' || coalesce(r.measures->>'held', '0') || ' held), '
                       || coalesce(r.measures->>'candidates_pending', '0') || ' candidate(s) waiting, ' || coalesce(r.measures->>'candidates_rejected', '0') || ' rejected. Gaps: '
                       || array_to_string(r.gaps, ', ')
                     else coalesce(r.measures->>'sources', '0') || ' entry-requirement source(s), ' || coalesce(r.measures->>'matrix_active', '0') || ' active and '
                       || coalesce(r.measures->>'matrix_proposed', '0') || ' proposed matrix rows; ' || coalesce(r.measures->>'courses_req_any', '0') || ' of '
                       || coalesce(r.measures->>'courses_with_page', '0') || ' courses with a bound page have requirements; intakes on ' || coalesce(r.measures->>'courses_intake', '0')
                       || ' and deadlines on ' || coalesce(r.measures->>'courses_deadline', '0') || ' of ' || coalesce(r.measures->>'courses', '0') || ' active courses. Gaps: '
                       || array_to_string(r.gaps, ', ') end,
          'expected', 'Provider coverage reconciles with what its sources list; each gap has a recovery route or an evidenced reason (P0 mandates 3 Nov 2026 §5, §8).',
          'source', 'coverage-reconcile', 'validation_layer', 'V4', 'root_cause_class', 'data_drift',
          'severity', case when r.disposition = 'zero' and (r.measures->>'provider_level')::boolean then 'P1'
                           when 'outside_aer_population' = any (r.gaps) and (r.measures->>'provider_level')::boolean then 'P1' else 'P2' end,
          'workstream', 'A2',
          'evidence', jsonb_build_object('coverage', jsonb_build_object('domain', v_dom, 'disposition', r.disposition, 'gaps', to_jsonb(r.gaps), 'measures', r.measures,
                                         'categories', r.categories, 'shortfall', r.shortfall, 'at', now())),
          'correlation_key', 'coverage:' || v_dom || ':' || coalesce(r.country, '?'),
          'remedy_code', 'coverage_investigation',
          'diagnosis', jsonb_build_object('root_cause', case v_dom when 'scholarship' then case when 'zero_scholarships' = any (r.gaps) then 'sch_zero_scholarships'
                                                                                              when 'under_represented' = any (r.gaps) then 'sch_under_represented'
                                                                                              when exists (select 1 from unnest(r.gaps) x where x like 'category_missing:%') then 'sch_category_missing'
                                                                                              when 'not_searched' = any (r.gaps) then 'sch_provider_not_searched'
                                                                                              else 'sch_fields_incomplete' end
                                                                   else case when 'outside_aer_population' = any (r.gaps) then 'aer_provider_outside_population'
                                                                             when 'no_source' = any (r.gaps) then 'aer_source_missing'
                                                                             when r.gaps <@ array['intake_gap', 'deadline_gap'] then 'aer_intake_deadline_gap'
                                                                             else 'aer_dimension_gap' end end,
                                          'confidence', 0.9, 'method', 'source-listing reconciliation (security.' || v_dom || '_coverage_v1)', 'at', now(),
                                          'evidence', jsonb_build_array(r.measures))), 'coverage-reconcile');
        update pipeline.coverage_provider_reconciliation l set issue_fingerprint = v_fp where l.domain = v_dom and l.provider_id = r.provider_id and l.issue_fingerprint is distinct from v_fp;
      end loop;
      -- the long tail, grouped per country and gap (from the ledger, so a partial run does not shrink the group)
      for r in select l.country, g.gap, array_agg(l.provider_id order by l.shortfall desc, l.provider_id) ids, count(*) n
                 from pipeline.coverage_provider_reconciliation l cross join lateral unnest(l.gaps) g(gap)
                where l.domain = v_dom and l.disposition <> 'out_of_scope' and not coalesce((l.measures->>'provider_level')::boolean, false)
                  and (coalesce((l.measures->>'anchor')::int, 0) = 0 and g.gap in ('no_source', 'intake_gap', 'deadline_gap', 'course_level_gap', 'domestic_only_source')
                       or g.gap = 'admission_policy')
                  and exists (select 1 from pg_temp.cov_now c where c.country is not distinct from l.country and g.gap = any (c.gaps))
                group by 1, 2 loop
        v_grp := v_grp + 1;
        perform security.integration_issue_upsert_v1(jsonb_build_object(
          'fingerprint', 'coverage:' || v_dom || ':' || coalesce(r.country, '?') || ':' || r.gap,
          'title', left(case v_dom when 'scholarship' then 'Scholarship coverage' else 'Entry requirement coverage' end || ': ' || r.n || ' other ' || coalesce(r.country, '?')
                   || ' providers with ' || r.gap, 300),
          'layer', 'Coverage', 'subsystem', case v_dom when 'scholarship' then 'scholarships' else 'entry requirements' end,
          'provider_ids', to_jsonb(r.ids), 'country_codes', jsonb_build_array(r.country),
          'failure', r.n || ' providers outside the provider-level types share the gap ' || r.gap || ' (grouped, not one issue each).',
          'expected', 'Each provider has a recovery route or an evidenced reason (P0 mandate 3 Nov 2026 §5; mandate 2 Nov 2026 §9 "one consolidated engineering issue").',
          'source', 'coverage-reconcile', 'validation_layer', 'V4', 'root_cause_class', 'data_drift', 'severity', 'P2', 'workstream', 'A2',
          'evidence', jsonb_build_object('coverage', jsonb_build_object('domain', v_dom, 'gap', r.gap, 'providers', r.n, 'at', now())),
          'correlation_key', 'coverage:' || v_dom || ':' || coalesce(r.country, '?'), 'remedy_code', 'coverage_investigation'), 'coverage-reconcile');
      end loop;
    end if;
    v_out := v_out || jsonb_build_object(v_dom, jsonb_build_object('looked_at', cardinality(v_ids), 'why', v_why, 'ledger_rows', v_ledger, 'out_of_scope', v_gone,
      'dispositions', (select coalesce(jsonb_object_agg(x.disposition, x.n), '{}'::jsonb) from (select c.disposition, count(*) n from pg_temp.cov_now c group by 1) x),
      'investigations_new', v_new, 'investigations_updated', v_upd, 'investigations_waiting', v_wait, 'groups', v_grp));
  end loop;
  return jsonb_build_object('on', true, 'issues_on', v_issues, 'at', now()) || v_out;
end $function$;
revoke all on function security.coverage_reconcile_v1(text) from public, anon, authenticated;
comment on function security.coverage_reconcile_v1(text) is 'CF-247 workstream C (P0 mandates 3 Nov 2026 §5/§12 and §8): job coverage-reconcile. Incremental: the providers security.coverage_due_v1 names (changed, discrepant, periodic broad check; batch.coverage_reconcile a run). Keeps the provider coverage ledger (pipeline.coverage_provider_reconciliation) for scholarships and AER and opens or updates one provider-level coverage investigation per provider and domain (coverage.investigations_on, coverage.investigations_per_run). Read-only over the catalogue; no read, spend, admission or publication.';

-- 7. remedies' action and verify functions (A's contract signatures) -----------------------------------------------------------------------
create or replace function security.scholarship_discovery_settle_remedy_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 workstream C: remedy sch_discovery_settle (authority auto). Runs the settle mechanism once; the same work the hourly job does.
declare v jsonb;
begin
  v := security.scholarship_discovery_settle_v1(null);
  return jsonb_build_object('ok', coalesce((v->>'on')::boolean, false), 'changed', coalesce((v->>'settled')::int, 0) + coalesce((v->>'restored')::int, 0),
                            'evidence', v || jsonb_build_object('issue', p_issue));
end $function$;
revoke all on function security.scholarship_discovery_settle_remedy_v1(bigint) from public, anon, authenticated;
comment on function security.scholarship_discovery_settle_remedy_v1(bigint) is 'CF-247 workstream C: action of remedy sch_discovery_settle (authority auto): security.scholarship_discovery_settle_v1 once. Returns {ok, changed, evidence}.';

create or replace function security.scholarship_discovery_settle_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 workstream C: verify of remedy sch_discovery_settle. Passed when no waiting discovery row (pending or deferred) belongs to a provider
  -- discovery can never take, and every row the settle mechanism parked still has its reason.
  with w as (select d.provider_id, d.status, security.scholarship_discovery_hold_reason_v1(d.provider_id, d.website) why from pipeline.scholarship_discovery_providers d
              where d.status in ('pending', 'deferred', 'not_eligible')),
  m as (select count(*) filter (where status <> 'not_eligible' and why is not null) waiting_refused,
               count(*) filter (where status <> 'not_eligible' and why is null) waiting_takeable,
               count(*) filter (where status = 'not_eligible') settled,
               count(*) filter (where status = 'not_eligible' and why is null) settled_but_takeable from w)
  select jsonb_build_object('passed', m.waiting_refused = 0 and m.settled_but_takeable = 0, 'measure', to_jsonb(m),
                            'evidence', jsonb_build_object('issue', p_issue, 'at', now(),
                              'sample', (select coalesce(jsonb_agg(x.provider_id), '[]'::jsonb) from (select w.provider_id from w where w.status <> 'not_eligible' and w.why is not null order by 1 limit 5) x)))
    from m
$function$;
revoke all on function security.scholarship_discovery_settle_verify_v1(bigint) from public, anon, authenticated;
comment on function security.scholarship_discovery_settle_verify_v1(bigint) is 'CF-247 workstream C: verify of remedy sch_discovery_settle: no waiting discovery row of a refused provider, and no settled row whose reason has cleared. Returns {passed, measure, evidence}. Read-only.';

create or replace function security.coverage_investigation_verify_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 workstream C: verify of remedy coverage_investigation. For an issue coverage:<domain>:<provider id>, recomputes that provider's coverage
-- now; passed when it has no gap. For a grouped issue coverage:<domain>:<country>:<gap>, passed when no provider of the issue still has the gap.
declare v_fp text; v_dom text; v_key text; v_prov uuid; v_gap text; v_ids uuid[]; m jsonb; v_left int;
begin
  select i.fingerprint, i.provider_ids into v_fp, v_ids from pipeline.integration_issues i where i.id = p_issue;
  if v_fp is null or v_fp not like 'coverage:%' then return jsonb_build_object('passed', false, 'measure', null, 'evidence', jsonb_build_object('error', 'not a coverage issue', 'issue', p_issue)); end if;
  v_dom := split_part(v_fp, ':', 2); v_key := split_part(v_fp, ':', 3); v_gap := nullif(split_part(v_fp, ':', 4), '');
  if v_gap is null then
    v_prov := v_key::uuid;
    if v_dom = 'scholarship' then select jsonb_build_object('gaps', to_jsonb(c.gaps), 'disposition', c.disposition, 'measures', c.measures) into m from security.scholarship_coverage_v1(array[v_prov]) c;
    else select jsonb_build_object('gaps', to_jsonb(c.gaps), 'disposition', c.disposition, 'measures', c.measures) into m from security.aer_coverage_v1(array[v_prov]) c; end if;
    return jsonb_build_object('passed', m is not null and jsonb_array_length(m->'gaps') = 0, 'measure', m,
                              'evidence', jsonb_build_object('issue', p_issue, 'provider_id', v_prov, 'in_population', m is not null, 'at', now()));
  end if;
  if v_dom = 'scholarship' then select count(*) into v_left from security.scholarship_coverage_v1(v_ids) c where true and v_gap = any (c.gaps);
  else select count(*) into v_left from security.aer_coverage_v1(v_ids) c where true and v_gap = any (c.gaps); end if;
  return jsonb_build_object('passed', v_left = 0, 'measure', jsonb_build_object('providers', cardinality(v_ids), 'still_with_gap', v_left),
                            'evidence', jsonb_build_object('issue', p_issue, 'gap', v_gap, 'country', v_key, 'at', now()));
end $function$;
revoke all on function security.coverage_investigation_verify_v1(bigint) from public, anon, authenticated;
comment on function security.coverage_investigation_verify_v1(bigint) is 'CF-247 workstream C: verify of remedy coverage_investigation: the provider (or every provider of a grouped issue) no longer has the coverage gap. Returns {passed, measure, evidence}. Read-only.';

create or replace function security.aer_course_counts_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 workstream C: verify of remedy aer_course_counts (authority release). Passed when the AER reader counts eligible courses again: the
  -- stored coverage (written by aer-reconcile) and a fresh read both have courses for the providers that have active courses.
  with f as (select count(*) filter (where s.courses_eligible > 0) fresh_with_courses, count(*) filter (where s.course_req_active + s.course_req_proposed > 0) fresh_with_req
               from security.aer_provider_states_v1() s),
  t as (select count(*) filter (where c.courses_eligible > 0) stored_with_courses from pipeline.aer_provider_coverage c where c.eligible),
  a as (select count(distinct c.provider_id) with_active_courses from catalogue.courses c join security.aer_eligible_v1() e on e.provider_id = c.provider_id
         where c.lifecycle_status = 'active' and c.open_to_international is not false)
  select jsonb_build_object('passed', f.fresh_with_courses > 0 and t.stored_with_courses > 0 and f.fresh_with_courses >= a.with_active_courses,
                            'measure', jsonb_build_object('fresh_with_courses', f.fresh_with_courses, 'fresh_with_requirements', f.fresh_with_req,
                                                          'stored_with_courses', t.stored_with_courses, 'providers_with_active_courses', a.with_active_courses),
                            'evidence', jsonb_build_object('issue', p_issue, 'at', now()))
    from f, t, a
$function$;
revoke all on function security.aer_course_counts_verify_v1(bigint) from public, anon, authenticated;
comment on function security.aer_course_counts_verify_v1(bigint) is 'CF-247 workstream C: verify of remedy aer_course_counts: the AER coverage reader counts eligible courses (fresh and stored). Returns {passed, measure, evidence}. Read-only.';

-- 8. the AER coverage reader counts courses again (md5-guarded) ----------------------------------------------------------------------------
select pg_temp.edit_once('security.aer_provider_states_v1()', 'db5fb0c9f75b8bcca91bdcb34a2632d5', 'ea058f55ec77b191995e16985211b366', array[
  array[$e$          where c.lifecycle_status = 'active' and c.publication_status = 'published' group by 1),$e$,
        $e$          where c.lifecycle_status = 'active' group by 1),  -- CF-247 workstream C: course visibility follows the provider; no AU or NZ course is 'published'$e$],
  array[$e$          where c.lifecycle_status = 'active' and c.publication_status = 'published' and c.open_to_international is not false group by 1),$e$,
        $e$          where c.lifecycle_status = 'active' and c.open_to_international is not false group by 1),$e$]
]::text[][], array[1, 1]);

-- 9. root causes and remedies (workstream A's contract) -----------------------------------------------------------------------------------
select security.ops_root_cause_register_v1('sch_discovery_waits_refused', jsonb_build_object('class', 'rule',
  'title', 'Scholarship discovery rows of refused providers wait for ever',
  'description', 'public.svc_scholarship_discover_next only pushes a refused provider''s row retry.scholarship_discovery_held_hours on; nothing gives it an outcome, so it waits as pending, fills the pick window every few hours and counts as waiting work (IQ-00041, IQ-00058).',
  'detect', jsonb_build_object('verify_fn', 'security.scholarship_discovery_settle_verify_v1(bigint)', 'measure', 'waiting_refused > 0',
                               'fingerprints', jsonb_build_array('health:scholarship_queues:discover', 'health:queue_watch:scholarship_discover'))));
select security.ops_root_cause_register_v1('sch_refill_counts_refused', jsonb_build_object('class', 'capacity',
  'title', 'The scholarship refill counts refused rows as waiting work',
  'description', 'security.scholarship_discovery_refill_v1 tops the queue up only while fewer than p_keep rows are pending or deferred; refused rows kept that count above it, so newly eligible providers were never queued.',
  'detect', jsonb_build_object('verify_fn', 'security.scholarship_discovery_settle_verify_v1(bigint)', 'measure', 'waiting_refused > 0')));
select security.ops_root_cause_register_v1('sch_holds_off_with_budget_off', jsonb_build_object('class', 'policy',
  'title', 'With the Firecrawl daily budget off, refused providers count as takeable',
  'description', 'security.fc_sch_held_v1 applies the eligibility hold only while firecrawl.daily_budget_on is on; with it off (2 Nov 2026) the health check counted 1,050 refused rows as stalled discovery.',
  'detect', jsonb_build_object('setting', 'firecrawl.daily_budget_on', 'verify_fn', 'security.scholarship_discovery_settle_verify_v1(bigint)')));
select security.ops_root_cause_register_v1('sch_provider_not_searched', jsonb_build_object('class', 'policy',
  'title', 'A provider expected to publish scholarships is not searched',
  'description', 'A provider of a provider-level type (or with listing evidence) has no discovery row or is settled not_eligible (for example below scholarship_min_courses). Lifting it is a policy decision (scholarship pilot, D-M6/D-M7).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'gap', 'not_searched')));
select security.ops_root_cause_register_v1('sch_zero_scholarships', jsonb_build_object('class', 'data',
  'title', 'Provider with zero scholarships', 'description', 'An expected or listed provider holds no active scholarship.',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'gap', 'zero_scholarships')));
select security.ops_root_cause_register_v1('sch_under_represented', jsonb_build_object('class', 'data',
  'title', 'Provider''s sources list many more scholarships than the catalogue holds',
  'description', 'Admitted scholarships are below coverage.sch_represented_min_pct of the largest source count (register, listing items, stated total, members).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'gap', 'under_represented')));
select security.ops_root_cause_register_v1('sch_category_missing', jsonb_build_object('class', 'data',
  'title', 'A scholarship category the sources list is missing',
  'description', 'Research, undergraduate, postgraduate or international scholarships are listed (coverage.sch_category_min_items or more) and none is held.',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'gap', 'category_missing:*')));
select security.ops_root_cause_register_v1('sch_listing_not_fanned_out', jsonb_build_object('class', 'dependency',
  'title', 'Listing items are never turned into candidates',
  'description', 'Listing pages are read and hold items, but pipeline.scholarship_listing_members is empty: the worker records listings through the retiring svc_scholarship_listing_record, not _v2 (F5 fan-out), and no page_state is written (F6).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'gap', 'listing_not_fanned_out')));
select security.ops_root_cause_register_v1('aer_source_missing', jsonb_build_object('class', 'data',
  'title', 'No entry-requirement source for an eligible provider',
  'description', 'An AER-eligible provider has no source in pipeline.entry_matrix_sources and no matrix or course-level requirement.',
  'detect', jsonb_build_object('fn', 'security.aer_coverage_v1(uuid[])', 'gap', 'no_source')));
select security.ops_root_cause_register_v1('aer_dimension_gap', jsonb_build_object('class', 'data',
  'title', 'Entry requirements held do not cover what the source lists',
  'description', 'Countries listed in a source manifest but not held, cells omitted, a source never read, or course-level requirements on fewer than coverage.aer_course_min_pct of courses with a stored page.',
  'detect', jsonb_build_object('fn', 'security.aer_coverage_v1(uuid[])', 'gaps', jsonb_build_array('source_unread', 'cells_omitted', 'countries_missing', 'course_level_gap'))));
select security.ops_root_cause_register_v1('aer_intake_deadline_gap', jsonb_build_object('class', 'data',
  'title', 'Intakes or application deadlines missing for most courses',
  'description', 'Fewer than coverage.intake_min_pct of active courses have an intake with a start date, or fewer than coverage.deadline_min_pct have an application deadline.',
  'detect', jsonb_build_object('fn', 'security.aer_coverage_v1(uuid[])', 'gaps', jsonb_build_array('intake_gap', 'deadline_gap'))));
select security.ops_root_cause_register_v1('sch_admission_policy', jsonb_build_object('class', 'policy',
  'title', 'Listed scholarships of a provider the admission rule refuses',
  'description', 'The national register or a listing names scholarships of a non-university provider, but security.scholarship_admission_provider_ok_v1 refuses it (P1 non-university admission off, or outside the pilot list, D-M6/D-M7). Grouped per country; a Platform Admin decision, not missing data.',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'gap', 'admission_policy')));
select security.ops_root_cause_register_v1('sch_fields_incomplete', jsonb_build_object('class', 'data',
  'title', 'Held scholarships lack facts a student needs',
  'description', 'Funding type, value, application dates, study level, academic or residency requirements are held for fewer than coverage.sch_field_min_pct of the provider''s scholarships.',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'gap', 'fields_incomplete:*')));
select security.ops_root_cause_register_v1('aer_provider_outside_population', jsonb_build_object('class', 'data',
  'title', 'A major registered provider is outside the AER population',
  'description', 'A provider of a provider-level type in an AER country is active and published but security.aer_eligible_v1 leaves it out (enrols_international not true), so the scheduled AER reader never sees it.',
  'detect', jsonb_build_object('fn', 'security.aer_coverage_v1(uuid[])', 'gap', 'outside_aer_population')));
select security.ops_root_cause_register_v1('aer_domestic_only_source', jsonb_build_object('class', 'rule',
  'title', 'Entry requirements held only from a domestic source',
  'description', 'Every requirement held for the provider (matrix) or for its courses is audience domestic. It is never read as a universal or international requirement.',
  'detect', jsonb_build_object('fn', 'security.aer_coverage_v1(uuid[])', 'gap', 'domestic_only_source')));
select security.ops_root_cause_register_v1('aer_course_counts_blind', jsonb_build_object('class', 'rule',
  'title', 'The AER coverage reader counted no course',
  'description', 'security.aer_provider_states_v1 required catalogue.courses.publication_status = published; no AU or NZ course is, so courses_eligible and course-level requirement counts were 0 for all 1,476 providers.',
  'detect', jsonb_build_object('verify_fn', 'security.aer_course_counts_verify_v1(bigint)')));

select security.ops_remedy_register_v1('sch_discovery_settle', jsonb_build_object('title', 'Give refused scholarship discovery rows an outcome (and return them when eligible)',
  'treats', jsonb_build_array('sch_discovery_waits_refused', 'sch_refill_counts_refused', 'sch_holds_off_with_budget_off'), 'authority', 'auto',
  'action_fn', 'security.scholarship_discovery_settle_remedy_v1(bigint)', 'verify_fn', 'security.scholarship_discovery_settle_verify_v1(bigint)',
  'max_attempts_key', 'coverage.remedy_max_attempts', 'cooldown_key', 'coverage.remedy_cooldown_minutes', 'active', true,
  'notes', 'Also runs hourly as job scholarship-discovery-settle. No read, no spend, no admission. Switch: scholarship.discovery_settle_on.'));
select security.ops_remedy_register_v1('coverage_investigation', jsonb_build_object('title', 'Provider-level coverage investigation (scholarships or entry requirements)',
  'treats', jsonb_build_array('sch_provider_not_searched', 'sch_zero_scholarships', 'sch_under_represented', 'sch_category_missing', 'sch_listing_not_fanned_out',
                              'sch_fields_incomplete', 'sch_admission_policy', 'aer_source_missing', 'aer_dimension_gap', 'aer_intake_deadline_gap', 'aer_provider_outside_population',
                              'aer_domestic_only_source'),
  'authority', 'admin', 'verify_fn', 'security.coverage_investigation_verify_v1(bigint)',
  'max_attempts_key', 'coverage.remedy_max_attempts', 'cooldown_key', 'coverage.remedy_cooldown_minutes', 'active', true,
  'notes', 'Recovery needs reads, spend, a policy decision or Layer 4, so it is not run automatically. The verify recomputes the provider''s coverage.'));
select security.ops_remedy_register_v1('aer_course_counts', jsonb_build_object('title', 'AER coverage reader counts courses by lifecycle (release 20261104040000)',
  'treats', jsonb_build_array('aer_course_counts_blind'), 'authority', 'release', 'verify_fn', 'security.aer_course_counts_verify_v1(bigint)',
  'max_attempts_key', 'coverage.remedy_max_attempts', 'cooldown_key', 'coverage.remedy_cooldown_minutes', 'active', true,
  'notes', 'Fixed by this migration; verified after aer-reconcile has run once.'));

-- 10. jobs (G1): catalogued; both ship active (they stop waste, record outcomes and report; nothing spends or admits) ----------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('scholarship-discovery-settle', 'Scholarships', 57, 'Scholarship discovery: outcome for refused providers',
  'Every hour at :16 (before the refill at :23): a discovery row the picker can never take (provider unpublished, search off, directory site, or not eligible under the Firecrawl scholarship rules) gets the status not_eligible with its reason instead of waiting for ever; it returns, due, when the reason clears. Switch scholarship.discovery_settle_on; size batch.scholarship_discovery_settle. No read, no AI, no Firecrawl.',
  5, true, null),
 ('coverage-reconcile', 'Platform upkeep', 97, 'Coverage reconciliation: scholarships and entry requirements per provider',
  'Every hour at :26: compares each active provider''s scholarships and entry requirements with what its sources list (listings, national register, entry-requirement sources and manifests, stored course pages, intakes and deadlines), keeps the coverage ledger and opens or updates one provider-level coverage investigation per provider in the integration queue. Switches coverage.reconcile_on and coverage.investigations_on. Read-only: no read, no AI, no Firecrawl, no admission.',
  5, false, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'scholarship-discovery-settle') then
    perform cron.schedule('scholarship-discovery-settle', '16 * * * *', 'select security.scholarship_discovery_settle_v1()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'coverage-reconcile') then
    perform cron.schedule('coverage-reconcile', '26 * * * *', 'select security.coverage_reconcile_v1()');
  end if;
end $j$;

-- 11. register (housekeeping) --------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'scholarship-discovery-settle', 'Layer 2', 'Scholarships', 'Outcome for scholarship discovery rows of refused providers', 'active', '{}', '20261104040000'),
 ('job', 'coverage-reconcile', 'Platform', 'Platform upkeep', 'Provider-level scholarship and AER coverage ledger and investigations', 'active', '{}', '20261104040000'),
 ('table', 'pipeline.coverage_provider_reconciliation', 'Platform', 'Platform upkeep', 'Provider coverage ledger (scholarship, aer)', 'active', '{}', '20261104040000')
on conflict do nothing;

-- 12. post-check ---------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if md5(pg_get_functiondef('security.aer_provider_states_v1()'::regprocedure)) <> 'ea058f55ec77b191995e16985211b366' then raise exception 'post-check: aer_provider_states_v1'; end if;
  if (select count(*) from cron.job where jobname in ('scholarship-discovery-settle', 'coverage-reconcile')) <> 2 then raise exception 'post-check: jobs'; end if;
  if (select count(*) from pipeline.automation_catalogue where jobname in ('scholarship-discovery-settle', 'coverage-reconcile')) <> 2 then raise exception 'post-check: catalogue'; end if;
  if (select count(*) from pipeline.ops_remedies where code in ('sch_discovery_settle', 'coverage_investigation', 'aer_course_counts')) <> 3 then raise exception 'post-check: remedies'; end if;
  if (select authority from pipeline.ops_remedies where code = 'coverage_investigation') <> 'admin' then raise exception 'post-check: coverage investigations are never automatic'; end if;
end $$;
