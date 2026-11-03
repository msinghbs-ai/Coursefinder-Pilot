-- CF-247 scholarship coverage recovery (Platform Admin mandate 4 Nov 2026 05:08, §2-§5 and §9: IQ-00215 Torrens, IQ-00216 TAFE SA, IQ-00219 Box Hill,
-- systemic coverage assurance; admin docs/platform/nz-enrichment-brief/2026-11-04-independent-validation-recovery-mandate-0508.md). Lands after
-- workstream A's shared contract (20261104010000) and the work-continuity contract (20261104170000).
--
-- Why (live, read-only, 4 Nov 2026 05:10-05:45 AEDT):
--   D1 provider identity (IQ-00215): security.scholarship_university tests the WHOLE canonical name. Torrens University Australia's record carries its
--      CRICOS trading names joined by ';' ("Torrens University Australia; Torrens University Language Centre; Chifley Business School ...;
--      Blue Mountains International Hotel Management School ..."), so the "language cent" exclusion refuses a TEQSA-registered Australian University.
--      Admission eligibility is false; candidate 7887 (Motivational Scholarship: international, up to 25%, both models proved it) was refused
--      only with "not a university provider in a scholarship country". Of 43 scholarship-country providers with joined names, 1 is affected (Torrens).
--   D2 register pages never read: the 11 Oct 2026 one-off (20261011008400 §4c) rejected every register-sourced candidate as register_retired
--      without reading it, and security.scholarship_ai_enqueue_v1 skips source 'register'. 72 of the 74 are on the provider's own site
--      (51 providers; 7 admission-eligible today, 13 with D1 corrected): Torrens Alumni, Career Enhancement, Ironwood, Kings College Malaysia,
--      Pearl Pathway and PEPEA are never read.
--   D3 listing verdicts never traversed: with AI admission on, the candidate recorder suggests a listing page before the AI has answered, so an
--      AI 'listing' verdict never becomes a listing source. 618 international scholarship listing pages (158 providers) have no listing source
--      (TAFE SA 8435 "2026 TAFE SA International Scholarship Programs", the register's only TAFE SA item).
--   D4 listings read before fan-out: 17 of 23 active listing sources were last read by the retired recorder (page_state null, 0 members); their items
--      become candidates only at the next weekly read (Torrens listing 61: 8 items, 0 members, next read 9 Nov; Family Scholarship and the Three
--      Pillars page are not candidates).
--   D5 policy reported as missing data: provider-level providers the admission rule refuses (TAFE, university college and wananga outside the
--      non-university pilot) are reported 'zero' (P1) instead of blocked by policy: 45 providers, 26 open coverage issues (25 P1; IQ-00216 and
--      IQ-00219 among them). integration_issue_upsert_v1 never lowers a severity, so the issues stay P1 until a person changes them.
--   D6 sub-brand hosts (ownership): 50 register rows (9 providers, 16 hosts) point at a host the provider's discovery row does not own
--      (Torrens: 6 BMIHMS awards on bluemountains.edu.au). Ownership is the Platform Admin's decision; recorded as an ownership conflict.
--   D7 "Read again" does not read (Integration Controller, 4 Nov morning validation; Macquarie D5 paste): public.svc_scholarship_read_next takes
--      only pages whose next_read_at has passed; requested_at only orders them. 8 Macquarie pages requested 3 Nov 12:11 UTC wait for 12 Nov
--      (one for 11 Jan 2027).
--   Not a defect: the directory-site gate (v2.15.446) refused 1,130 candidates of 25 providers, none on the provider's own site; no D4 refusal
--   concerns Torrens, TAFE SA or Box Hill.
-- What:
--   1 One classification of every scholarship coverage case per provider in the 13 states of the mandate (pipeline.scholarship_coverage_state_codes),
--     reusing existing statuses: candidate admit_status/admit_reasons, AI verdicts, Layer 4 AI reviews, owner proposals, listing sources and members,
--     register rows, scholarships, round states, publication holds, and the consumer API (read only: api.website_v2_scholarship_item) for
--     "published and consumer-verified". security.scholarship_coverage_items_v1 (read only) classifies; job scholarship-coverage-classify
--     (security.scholarship_coverage_classify_v1, hourly at :29, after coverage-reconcile at :26) keeps pipeline.scholarship_coverage_items and
--     pipeline.scholarship_coverage_providers. Every unresolved case has an owner, its evidence, a next recovery time and an escalation condition,
--     and reports into the work-continuity record (security.work_item_report_v1, lane sch_coverage, one item per provider and state, only when its
--     signature changes): Layer 4 -> review; ownership -> identity_conflict (quarantine, escalated); unresolved international eligibility ->
--     ambiguity (parked, escalated); recoverable states -> dependency with the next recovery time; past sch_cov.escalate_after_hours, or a recovery
--     that did not move its case within sch_cov.verify_after_hours -> authority (escalated by job work-continuity as work_blocked:sch_coverage:*).
--     A provider is "evidence-backed no eligible scholarships" only when a complete listing read exists and every case is resolved with none
--     published. Ships ON (records and reports only).
--   2 Bounded recovery, job scholarship-coverage-recover (security.scholarship_coverage_recover_v1, hourly at :31): at most batch.sch_coverage_recover
--     actions a run and sch_cov.recover_per_provider_max per provider, only for admission-eligible providers that are not hidden or held, each
--     action at most once per case (pipeline.scholarship_coverage_recoveries, unique), so no paid read repeats and no review item is duplicated:
--     reopen_read (D2: a never-read register page goes to the candidate reader once), reread_stored (D1: a refused page is read again by the AI
--     from its stored copy, no Firecrawl), promote_listing (D3: an AI-classified international listing becomes a listing source), refresh_listing
--     (D4: a listing read before fan-out is read once now). Each family has its own switch and ships OFF (they spend Firecrawl or AI credit).
--   3 D1: security.scholarship_university (md5-guarded) also accepts a provider whose legal name (the first ';' segment) passes the existing
--     university test, while sch_cov.legal_name_identity_on is 1. Ships OFF (it makes more providers admission-eligible).
--   4 D5: security.scholarship_coverage_v1 (md5-guarded) reports a provider-level provider the admission rule refuses, other than type 'university',
--     as blocked by policy, while sch_cov.policy_disposition_on is 1. Ships OFF (it changes what coverage-reconcile reports for 45 providers; the
--     severities are the Platform Admin's decision).
--   5 D7: public.svc_scholarship_read_next (md5-guarded) treats a page requested after its last read as due. Bounded as before (the run size, at most
--     40 pages a call, five attempts, the Firecrawl budget in the worker); a page is read once per request (the recorder clears requested_at; a page
--     waiting for the scraper keeps its request but its read_at is after it, so it waits its retry hour). Ships ON: it makes the documented
--     "Read again" route do what it says; nothing reads a page that nobody asked for.
--   6 Root causes and remedies through workstream A's contract.
-- Activation:
--   ON: classification, work items and escalation (sch_cov.classify_on); Read again (D7, no switch: a route fix).
--   OFF: sch_cov.legal_name_identity_on, sch_cov.policy_disposition_on, sch_cov.recover_register_pages_on, sch_cov.recover_stored_reads_on,
--        sch_cov.recover_listings_on. Nothing here admits, decides a Layer 4 item, publishes, changes a cap, a budget, a manual binding or an owner.
-- Settings (G2): sch_cov.* and batch.sch_coverage_classify, batch.sch_coverage_recover (Settings > Pipeline settings, "Scholarship coverage recovery").
-- md5 (before = live, read 4 Nov 2026 05:12-05:40 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/sch-coverage-recovery/run.sh):
--   security.scholarship_university(uuid)      00ca2485d894ae4542b643a112c2b764 -> cee99ebcfe6ce05751a879260333e6d2
--   security.scholarship_coverage_v1(uuid[])    cf9a3828b285791bd3d2dd1e8015d481 -> 772004147c66c4031ff18a37260008af
--   public.svc_scholarship_read_next(integer)   b30f59a20dff4c874c9fbed2659586c7 -> 452c288e17dd7207574808737d88c14a
-- Called, not edited (live md5): security.work_item_report_v1(text,text,text,text,jsonb) 6a15318c0ecd6644b32f1883463c542e,
--   security.scholarship_admission_provider_ok_v1(uuid) 269f74a985acbc37f1f3b8615efa6254, public.svc_scholarship_read_record(...) ec72dc9952cce9f63e427377ec0513a8
--   (clears requested_at), api.website_v2_scholarship_item(uuid) (consumer API, read only).
-- Replaces: security.scholarship_university, security.scholarship_coverage_v1, public.svc_scholarship_read_next (same names; md5-guarded edits)
-- Retires: nothing (the whole-name university test stays reachable with sch_cov.legal_name_identity_on 0)
-- Consumer API: untouched (G3); it is only read. Nothing is dropped or deleted. Nothing is read, spent, admitted or published by this migration.

do $guard$
begin
  if to_regclass('pipeline.ops_remedies') is null or to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is null
     or to_regprocedure('security.ops_root_cause_register_v1(text,jsonb)') is null then
    raise exception 'scholarship coverage recovery needs workstream A''s shared contract (20261104010000) first';
  end if;
  if to_regclass('pipeline.work_items') is null or to_regprocedure('security.work_item_report_v1(text,text,text,text,jsonb)') is null then
    raise exception 'scholarship coverage recovery needs the work-continuity contract (20261104170000) first';
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

-- 0. definitions called, not edited, are the ones this change was written against ----------------------------------------------------------
do $g$
declare v_sig text;
begin
  if md5(pg_get_functiondef('security.work_item_report_v1(text,text,text,text,jsonb)'::regprocedure)) <> '6a15318c0ecd6644b32f1883463c542e' then
    raise exception 'live security.work_item_report_v1 differs from the definition this change was written against';
  end if;
  foreach v_sig in array array['security.scholarship_admission_provider_ok_v1(uuid)', 'security.third_party_host_v1(text)', 'security.url_on_provider_sites(text,uuid)',
                               'security.scholarship_url_norm(text)', 'security.fc_sch_held_v1(uuid,boolean)', 'security.scholarship_ai_active_v1()',
                               'security.australian_university(uuid)', 'security.provider_university_groups(uuid)', 'api.website_v2_scholarship_item(uuid)'] loop
    if to_regprocedure(v_sig) is null then raise exception 'this change reads %, which does not exist', v_sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) ------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'sch_cov.classify_on', 'Scholarship coverage: classify every case',
  '1: every hour each provider''s scholarship cases are classified (source not discovered, found but unread, traversal incomplete, rejected correctly or incorrectly, international eligibility unresolved, domestic only, expired, ownership conflict, awaiting Layer 4, admitted not published, published and consumer-verified, evidence-backed none), and unresolved cases are recorded as work items with an owner, evidence, a next recovery time and an escalation. Reads and records only. 0: off.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1400, 'Mandate 4 Nov 2026 05:08 §5: ships on (records and reports only)', 'Scholarship coverage recovery',
  'security.scholarship_coverage_classify_v1 (job scholarship-coverage-classify)'),
 ('pipeline', 'batch.sch_coverage_classify', 'Scholarship coverage: providers classified per run',
  'Each run classifies at most this many providers: never classified first, then those with an open coverage investigation, then the longest since classified.',
  'number', to_jsonb(40), 1, 500, 'providers', 1401, 'Mandate 4 Nov 2026 05:08 §5', 'Scholarship coverage recovery', 'security.scholarship_coverage_classify_v1'),
 ('pipeline', 'sch_cov.reclassify_hours', 'Scholarship coverage: classify a provider again after',
  'A provider is classified again once this long has passed since its last classification.',
  'number', to_jsonb(6), 1, 168, 'hours', 1402, 'Mandate 4 Nov 2026 05:08 §5 "avoid repetitive discovery"', 'Scholarship coverage recovery', 'security.scholarship_coverage_classify_v1'),
 ('pipeline', 'sch_cov.recheck_hours', 'Scholarship coverage: next recovery time of an unresolved case',
  'An unresolved case is due for its next recovery check this long after it was classified.',
  'number', to_jsonb(24), 1, 336, 'hours', 1403, 'Mandate 4 Nov 2026 05:08 §5 "next eligible recovery time"', 'Scholarship coverage recovery', 'security.scholarship_coverage_classify_v1'),
 ('pipeline', 'sch_cov.escalate_after_hours', 'Scholarship coverage: escalate an unresolved case after',
  'A case whose state escalates "after hours" is escalated (work item class authority, raised by job work-continuity) once it has been unresolved this long.',
  'number', to_jsonb(72), 1, 720, 'hours', 1404, 'Mandate 4 Nov 2026 05:08 §5 "escalation condition"', 'Scholarship coverage recovery', 'security.scholarship_coverage_classify_v1'),
 ('pipeline', 'sch_cov.verify_after_hours', 'Scholarship coverage: a recovery has failed when its case has not moved after',
  'After a recovery action, its case must change state within this time; otherwise the recovery is recorded as failed and the case is escalated.',
  'number', to_jsonb(48), 1, 336, 'hours', 1405, 'Mandate 4 Nov 2026 05:08 §9 steps 7-8', 'Scholarship coverage recovery', 'security.scholarship_coverage_classify_v1'),
 ('pipeline', 'sch_cov.legal_name_identity_on', 'Scholarship admission: test the legal name of a provider with joined trading names',
  '1: a provider whose record joins its trading names with ";" is tested as a university on its legal name (the first name), not on the whole text (Torrens University Australia was refused because a trading name contains "Language Centre"). Makes more providers admission-eligible. 0: whole name, as before.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1406, 'Mandate 4 Nov 2026 05:08 §2 (IQ-00215): ships off (admission scope)', 'Scholarship coverage recovery',
  'security.scholarship_university'),
 ('pipeline', 'sch_cov.policy_disposition_on', 'Scholarship coverage: report policy-refused providers as blocked by policy',
  '1: a TAFE, university college or wānanga that the admission rule refuses (outside the non-university pilot) is reported blocked by policy, not as zero scholarships. Severities of open issues are not changed automatically. 0: reported as zero, as before.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1407, 'Mandate 4 Nov 2026 05:08 §4: ships off (changes what coverage-reconcile reports)', 'Scholarship coverage recovery',
  'security.scholarship_coverage_v1'),
 ('pipeline', 'sch_cov.recover_register_pages_on', 'Scholarship coverage recovery: read never-read register pages once',
  '1: a provider page that came from the retired national register and was rejected unread (register_retired) is handed to the candidate reader once (one Firecrawl read, then the AI). 0: off.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1408, 'Mandate 4 Nov 2026 05:08 §2: ships off (Firecrawl and AI spend)', 'Scholarship coverage recovery',
  'security.scholarship_coverage_recover_v1 (reopen_read)'),
 ('pipeline', 'sch_cov.recover_stored_reads_on', 'Scholarship coverage recovery: read refused pages again from their stored copy',
  '1: a page refused only because its provider failed the admission rule, whose provider now passes, is read once more by the AI from its stored copy (no Firecrawl). 0: off.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1409, 'Mandate 4 Nov 2026 05:08 §2: ships off (AI spend)', 'Scholarship coverage recovery',
  'security.scholarship_coverage_recover_v1 (reread_stored)'),
 ('pipeline', 'sch_cov.recover_listings_on', 'Scholarship coverage recovery: traverse listing pages',
  '1: a page the AI classified as a listing of international scholarships becomes a listing source, and a listing read before items became candidates is read once now. One Firecrawl read each; then the normal weekly cadence. 0: off.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1410, 'Mandate 4 Nov 2026 05:08 §2 "listing traversal": ships off (Firecrawl spend)', 'Scholarship coverage recovery',
  'security.scholarship_coverage_recover_v1 (promote_listing, refresh_listing)'),
 ('pipeline', 'batch.sch_coverage_recover', 'Scholarship coverage recovery: actions per run',
  'Each run of the recovery takes at most this many actions across all providers.',
  'number', to_jsonb(10), 0, 200, 'actions', 1411, 'Mandate 4 Nov 2026 05:08 §5 "bounded automatic recovery"', 'Scholarship coverage recovery', 'security.scholarship_coverage_recover_v1'),
 ('pipeline', 'sch_cov.recover_per_provider_max', 'Scholarship coverage recovery: actions per provider per run',
  'One provider takes at most this many actions in a run, so a large provider never holds up the others.',
  'number', to_jsonb(3), 1, 50, 'actions', 1412, 'Mandate 4 Nov 2026 05:08 §5 "a failed provider must not prevent unrelated providers from progressing"', 'Scholarship coverage recovery',
  'security.scholarship_coverage_recover_v1')
on conflict (toolset_key, key) do nothing;

-- 2. tables (beside the consumer API; nothing it reads changes) ---------------------------------------------------------------------------------
create table if not exists pipeline.scholarship_coverage_state_codes (
  code text primary key,
  title text not null,
  resolved boolean not null,
  owner text not null,
  existing_status text not null,
  escalate_when text not null check (escalate_when in ('never', 'always', 'after_hours', 'recovery_failed')),
  work_event text not null check (work_event in ('succeeded', 'review', 'identity', 'ambiguity', 'dependency')),
  sort int not null);
comment on table pipeline.scholarship_coverage_state_codes is 'CF-247 (mandate 4 Nov 2026 05:08 §5): the 13 scholarship coverage states, each with its owner, the existing status it is read from, whether it is resolved, its escalation condition and how it reports into the work-continuity record.';
insert into pipeline.scholarship_coverage_state_codes(code, title, resolved, owner, existing_status, escalate_when, work_event, sort) values
 ('source_not_discovered', 'Source not discovered', false, 'scholarship discovery (job scholarship-discover)', 'scholarship_discovery_providers.status; register handoff_status', 'after_hours', 'dependency', 10),
 ('source_found_unread', 'Source found but unread', false, 'scholarship candidate reader and AI reader', 'scholarship_page_candidates.admit_status null; scholarship_listing_pages source suggested', 'after_hours', 'dependency', 20),
 ('traversal_incomplete', 'Listing traversal incomplete', false, 'scholarship listing reader (job scholarship-listings)', 'scholarship_listing_pages page_state; AI verdict listing', 'recovery_failed', 'dependency', 30),
 ('rejected_incorrectly', 'Candidate rejected incorrectly', false, 'scholarship coverage recovery (job scholarship-coverage-recover)', 'admit_reasons register_retired or the provider admission rule', 'recovery_failed', 'dependency', 40),
 ('international_unresolved', 'International eligibility unresolved', false, 'Layer 4 reviewer', 'admit_reasons international_not_stated with an AI scholarship verdict', 'always', 'ambiguity', 50),
 ('ownership_conflict', 'Provider ownership conflict', false, 'Platform Admin (provider identity)', 'scholarship_owner_proposals proposed; register page on a host the provider does not own', 'always', 'identity', 60),
 ('awaiting_layer4', 'Awaiting Layer 4', false, 'Layer 4 reviewer', 'scholarship_ai_reviews pending; layer4_review_items pending', 'never', 'review', 70),
 ('admitted_not_published', 'Admitted but not published', false, 'publishing (job scholarship-auto-publish)', 'scholarships active, not published or not in the consumer API', 'after_hours', 'dependency', 80),
 ('rejected_correctly', 'Candidate rejected correctly', true, 'none (resolved)', 'admit_status rejected or skipped with a verified reason', 'never', 'succeeded', 90),
 ('domestic_only', 'Domestic-only scholarship', true, 'none (resolved)', 'admit_reasons domestic_only; audience domestic', 'never', 'succeeded', 100),
 ('expired', 'Expired scholarship', true, 'none (resolved)', 'admit_reasons past_year_only or not_offered; round state ended', 'never', 'succeeded', 110),
 ('published_verified', 'Published and consumer-verified', true, 'none (resolved)', 'published and returned by the consumer API', 'never', 'succeeded', 120),
 ('evidence_backed_none', 'Evidence-backed no eligible scholarships', true, 'none (resolved)', 'a complete listing read and every case resolved, none published', 'never', 'succeeded', 130)
on conflict (code) do nothing;

create table if not exists pipeline.scholarship_coverage_items (
  provider_id uuid not null,
  item_key text not null,
  state text not null references pipeline.scholarship_coverage_state_codes(code),
  reason text,
  evidence jsonb not null default '{}'::jsonb,
  recovery text,
  owner text,
  next_recovery_at timestamptz,
  escalation jsonb,
  present boolean not null default true,
  first_seen timestamptz not null default now(),
  state_since timestamptz not null default now(),
  classified_at timestamptz not null default now(),
  primary key (provider_id, item_key));
comment on table pipeline.scholarship_coverage_items is 'CF-247 (mandate 4 Nov 2026 05:08 §5): every scholarship coverage case of a provider (a candidate page, a register entry, a listing item or listing source, a scholarship, the provider itself) in one of the 13 states, with its reason, evidence, owner, next recovery time, escalation and the recovery that applies. Kept by job scholarship-coverage-classify; a case no longer found is kept with present false.';
create index if not exists scholarship_coverage_items_state_idx on pipeline.scholarship_coverage_items(state) where present;

create table if not exists pipeline.scholarship_coverage_providers (
  provider_id uuid primary key,
  provider_state text not null references pipeline.scholarship_coverage_state_codes(code),
  states jsonb not null default '{}'::jsonb,
  unresolved int not null default 0,
  published_verified int not null default 0,
  reported jsonb not null default '{}'::jsonb,
  classified_at timestamptz not null default now());
comment on table pipeline.scholarship_coverage_providers is 'CF-247 (mandate 4 Nov 2026 05:08 §5): per provider, its coverage state (the most pressing unresolved state, or published and consumer-verified, or evidence-backed none), the count per state, and the signature last reported to the work-continuity record per state (reported only when it changes).';

create table if not exists pipeline.scholarship_coverage_recoveries (
  id bigint generated always as identity primary key,
  provider_id uuid not null,
  item_key text not null,
  action text not null check (action in ('reopen_read', 'reread_stored', 'promote_listing', 'refresh_listing')),
  state_before text not null,
  detail jsonb not null default '{}'::jsonb,
  at timestamptz not null default now(),
  outcome text check (outcome in ('succeeded', 'failed')),
  outcome_at timestamptz,
  unique (item_key, action));
comment on table pipeline.scholarship_coverage_recoveries is 'CF-247 (mandate 4 Nov 2026 05:08 §5, §9): each bounded recovery action, at most once per case and action (no repeated paid read, no duplicate review item), and its verified outcome (succeeded when the case moved, failed when it had not moved after sch_cov.verify_after_hours).';

-- 3. D1: the legal-name university test ------------------------------------------------------------------------------------------------------------
create or replace function security.scholarship_legal_name_ok_v1(p_provider_id uuid) returns boolean
language sql stable security definer set search_path to '' as $function$
  -- CF-247 (IQ-00215): a provider whose record joins its trading names with ';' passes when its legal name (the first name) passes the existing
  -- university name test; the whole joined text is never tested here
  select exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id
                  where p.id = p_provider_id and c.scholarship_ingestion_enabled and p.lifecycle_status = 'active' and position(';' in coalesce(p.canonical_name, '')) > 0
                    and btrim(split_part(p.canonical_name, ';', 1)) ~* '\m(university|université|universite)\M'
                    and btrim(split_part(p.canonical_name, ';', 1)) !~* '(college|pathways?|language cent|senior|theology|divinity)')
$function$;
revoke all on function security.scholarship_legal_name_ok_v1(uuid) from public, anon, authenticated;

select pg_temp.edit_once('security.scholarship_university(uuid)', '00ca2485d894ae4542b643a112c2b764', 'cee99ebcfe6ce05751a879260333e6d2', array[
  array['                         or (p.canonical_name ~* ''\m(university|université|universite)\M'' and p.canonical_name !~* ''(college|pathways?|language cent|senior|theology|divinity)'')))
$function$',
        '                         or (p.canonical_name ~* ''\m(university|université|universite)\M'' and p.canonical_name !~* ''(college|pathways?|language cent|senior|theology|divinity)'')))
      -- CF-247 IQ-00215 (4 Nov 2026): joined trading names are tested on the legal name while sch_cov.legal_name_identity_on is 1
      or (security.pipeline_num_v1(''sch_cov.legal_name_identity_on'', 0) >= 1 and security.scholarship_legal_name_ok_v1(p_provider_id))
$function$']], array[1]);

-- 4. D5: policy-refused provider-level providers are blocked by policy (switch) ----------------------------------------------------------------------
select pg_temp.edit_once('security.scholarship_coverage_v1(uuid[])', 'cf9a3828b285791bd3d2dd1e8015d481', '772004147c66c4031ff18a37260008af', array[
  array['         when not a.admit_ok and not a.plevel then case when a.anchor > 0 then array[''admission_policy''] else ''{}''::text[] end',
        '         when not a.admit_ok and not a.plevel then case when a.anchor > 0 then array[''admission_policy''] else ''{}''::text[] end
         -- CF-247 IQ-00216/IQ-00219 (4 Nov 2026): a TAFE, university college or wananga outside the admission rule is blocked by policy, not missing data
         when not a.admit_ok and coalesce(a.ptype, '''') <> ''university'' and security.pipeline_num_v1(''sch_cov.policy_disposition_on'', 0) >= 1 then array[''admission_policy'']']], array[1]);

-- 5. D7: "Read again" reads ------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.svc_scholarship_read_next(integer)', 'b30f59a20dff4c874c9fbed2659586c7', '452c288e17dd7207574808737d88c14a', array[
  array['     where p.next_read_at<=now() and coalesce(p.leased_until,''-infinity'')<now() and p.attempts<5',
        '     -- CF-247 (4 Nov 2026, Integration Controller): a page asked for since its last read is due now; read once per request (the recorder clears it)
     where (p.next_read_at<=now() or (p.requested_at is not null and coalesce(p.read_at,''-infinity'')<p.requested_at)) and coalesce(p.leased_until,''-infinity'')<now() and p.attempts<5']], array[1]);

-- 6. the classification (read only) ------------------------------------------------------------------------------------------------------------------
create or replace function security.scholarship_coverage_items_v1(p_providers uuid[])
returns table(provider_id uuid, item_key text, state text, reason text, evidence jsonb, recovery text)
language sql stable security definer set search_path to '' as $function$
  -- CF-247 (mandate 4 Nov 2026 05:08 §5): every scholarship coverage case of the providers given, in one of the 13 states, from the existing
  -- statuses. Read-only; the consumer API is only read (api.website_v2_scholarship_item) for "published and consumer-verified".
  with pv as (select p.id, coalesce(t.code, '') ptype, security.scholarship_admission_provider_ok_v1(p.id) admit_ok, security.scholarship_legal_name_ok_v1(p.id) legal_ok
                from catalogue.providers p left join ref.provider_types t on t.id = p.provider_type_id where p.id = any (p_providers)),
  lst as (select l.* from pipeline.scholarship_listing_pages l join pv on pv.id = l.provider_id),
  cands as (select c.*, coalesce(security.url_on_provider_sites(c.url, c.provider_id), false) own, security.third_party_host_v1(coalesce(c.url, '')) dir
              from pipeline.scholarship_page_candidates c join pv on pv.id = c.provider_id),
  ai as (select distinct on (e.candidate_id) e.candidate_id, e.verdict, e.answer, e.model_code, e.at from pipeline.scholarship_ai_extractions e
           join cands c on c.id = e.candidate_id where e.error is null order by e.candidate_id, e.at desc),
  rv as (select r.candidate_id, r.scholarship_id, r.id, r.reason, r.created_at from pipeline.scholarship_ai_reviews r join pv on pv.id = r.provider_id where r.status = 'pending'),
  op as (select o.candidate_id, o.id, o.host from pipeline.scholarship_owner_proposals o join pv on pv.id = o.holder_provider_id where o.state = 'proposed'),
  cs as (
    select c.provider_id, 'cand:' || c.id item_key,
           case when exists (select 1 from rv where rv.candidate_id = c.id) then 'awaiting_layer4'
                when exists (select 1 from op where op.candidate_id = c.id) then 'ownership_conflict'
                when c.admit_status is null then 'source_found_unread'
                when c.admit_reasons && array['register_retired'] and c.own and not c.dir and c.read_status is null then 'rejected_incorrectly'
                when c.admit_reasons && array['not a university provider in a scholarship country'] and (pv.admit_ok or pv.legal_ok) then 'rejected_incorrectly'
                when c.admit_reasons && array['domestic_only'] then 'domestic_only'
                when c.admit_reasons && array['past_year_only', 'not_offered'] then 'expired'
                when c.admit_reasons && array['listing_page'] and ai.verdict = 'listing' and coalesce(ai.answer->>'is_scholarship', '') = 'true'
                     and ai.answer->>'audience' in ('international', 'both', 'international_and_domestic') and c.own and not c.dir
                     and not exists (select 1 from lst l where l.provider_id = c.provider_id and l.active and l.source in ('manual', 'auto')
                                                          and l.url_norm = security.scholarship_url_norm(coalesce(c.final_url, c.url))) then 'traversal_incomplete'
                when c.admit_reasons && array['international_not_stated'] and ai.verdict = 'scholarship' and coalesce(ai.answer->>'is_scholarship', '') = 'true' then 'international_unresolved'
                else 'rejected_correctly' end state,
           case when exists (select 1 from rv where rv.candidate_id = c.id) then 'pending AI review: ' || (select rv.reason from rv where rv.candidate_id = c.id limit 1)
                when exists (select 1 from op where op.candidate_id = c.id) then 'owner proposal (directory page)'
                when c.admit_status is null then case when c.read_status is null then 'waiting for the candidate reader' else 'waiting for the AI reader' end
                when c.admit_reasons && array['register_retired'] and c.own and not c.dir and c.read_status is null then 'register_page_never_read'
                when c.admit_reasons && array['not a university provider in a scholarship country'] and (pv.admit_ok or pv.legal_ok) then 'provider_identity_name_rule'
                when c.admit_reasons && array['not a university provider in a scholarship country'] then 'admission_policy'
                else array_to_string(c.admit_reasons, ', ') end reason,
           jsonb_build_object('candidate_id', c.id, 'url', c.url, 'title', c.title, 'source', c.source, 'read_status', c.read_status, 'admit_status', c.admit_status,
                              'admit_reasons', to_jsonb(c.admit_reasons), 'stored_copy', c.storage_path is not null, 'evidence_id', c.evidence_id, 'own_site', c.own,
                              'ai', case when ai.candidate_id is not null then jsonb_build_object('verdict', ai.verdict, 'model', ai.model_code, 'at', ai.at,
                                                                                                 'audience', ai.answer->>'audience', 'is_scholarship', ai.answer->'is_scholarship',
                                                                                                 'name', ai.answer->>'name') end) evidence,
           case when exists (select 1 from rv where rv.candidate_id = c.id) or exists (select 1 from op where op.candidate_id = c.id) then null
                when c.admit_reasons && array['register_retired'] and c.own and not c.dir and c.read_status is null then 'reopen_read'
                when c.admit_reasons && array['not a university provider in a scholarship country'] and (pv.admit_ok or pv.legal_ok) and c.storage_path is not null then 'reread_stored'
                when c.admit_reasons && array['listing_page'] and ai.verdict = 'listing' and coalesce(ai.answer->>'is_scholarship', '') = 'true'
                     and ai.answer->>'audience' in ('international', 'both', 'international_and_domestic') and c.own and not c.dir then 'promote_listing' end recovery
      from cands c join pv on pv.id = c.provider_id left join ai on ai.candidate_id = c.id
     where c.admitted_scholarship_id is null and c.matched_scholarship_id is null),
  -- register entries no candidate carries (the register was retired on 11 Oct 2026; its entries are evidence of what the provider lists)
  rg as (
    select r.provider_id, 'reg:' || r.register_code || ':' || r.listing_id item_key,
           case when r.handoff_status = 'provider_page_off_provider_site' then 'ownership_conflict' else 'source_not_discovered' end state,
           case when r.handoff_status = 'provider_page_off_provider_site' then 'register_page_on_unowned_host' else 'register_entry_without_candidate: ' || coalesce(r.handoff_status, 'none') end reason,
           jsonb_build_object('register', r.register_code, 'name', r.name, 'listed_under', r.provider_name, 'page', r.website_url, 'level', r.level_text,
                              'host', lower(substring(coalesce(r.website_url, '') from '^[a-z]+://(?:www\.)?([^/:?#]+)')), 'last_seen', r.last_seen_at) evidence,
           null::text recovery
      from scholarship.register_listings r join pv on pv.id = r.provider_id
     where r.departed_at is null and r.scholarship_id is null and r.candidate_id is null),
  -- listing items with their own page on the provider's site that are neither a member nor a candidate
  li as (
    select l.provider_id, 'list:' || l.id || ':' || security.scholarship_url_norm(i->>'url') item_key, 'traversal_incomplete' state,
           case when l.page_state is null then 'listing_read_before_fan_out' else 'item_not_yet_a_candidate' end reason,
           jsonb_build_object('listing_id', l.id, 'listing', l.url, 'item', i->>'name', 'url', i->>'url', 'read_at', l.read_at, 'page_state', l.page_state, 'next_read_at', l.next_read_at) evidence,
           case when l.page_state is null then 'refresh_listing' end recovery
      from lst l cross join lateral jsonb_array_elements(case when jsonb_typeof(l.items) = 'array' then l.items else '[]'::jsonb end) i
     where l.active and l.source in ('manual', 'auto') and coalesce(i->>'url', '') ~* '^https?://'
       and coalesce(security.url_on_provider_sites(i->>'url', l.provider_id), false) and security.scholarship_url_norm(i->>'url') <> l.url_norm
       and not exists (select 1 from pipeline.scholarship_listing_members m where m.listing_id = l.id and m.item_key = 'url:' || security.scholarship_url_norm(i->>'url'))
       and not exists (select 1 from cands c where c.provider_id = l.provider_id and c.url_norm = security.scholarship_url_norm(i->>'url'))
       and not exists (select 1 from scholarship.scholarships s where s.provider_id = l.provider_id and s.lifecycle_status = 'active'
                                                              and security.scholarship_url_norm(s.source_url) = security.scholarship_url_norm(i->>'url'))),
  -- suggested listing pages nobody accepted: found, never read
  ls as (
    select l.provider_id, 'listing:' || l.id item_key, 'source_found_unread' state, 'listing_suggested_not_accepted' reason,
           jsonb_build_object('listing_id', l.id, 'url', l.url, 'source', l.source) evidence, null::text recovery
      from lst l where l.source = 'suggested' and not l.active),
  sh as (
    select s.provider_id, 'sch:' || s.id item_key,
           case when s.publication_status = 'published' and api.website_v2_scholarship_item(s.id) is not null then 'published_verified'
                when s.publication_status = 'published' then 'admitted_not_published'
                when exists (select 1 from pipeline.scholarship_round_states rs where rs.scholarship_id = s.id and rs.state = 'ended') then 'expired'
                when s.audience = 'domestic' then 'domestic_only'
                when exists (select 1 from rv where rv.scholarship_id = s.id)
                  or exists (select 1 from pipeline.layer4_review_items r where r.entity_type = 'scholarship' and r.entity_id = s.id and r.status = 'pending') then 'awaiting_layer4'
                else 'admitted_not_published' end state,
           case when s.publication_status = 'published' and api.website_v2_scholarship_item(s.id) is null then 'published_but_not_returned_by_consumer_api'
                when s.publication_status <> 'published' then coalesce((select h.reason from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null limit 1),
                                                                        s.publication_status) end reason,
           jsonb_build_object('scholarship_id', s.id, 'name', s.name, 'publication_status', s.publication_status, 'audience', s.audience, 'page', s.source_url) evidence,
           null::text recovery
      from scholarship.scholarships s join pv on pv.id = s.provider_id where s.lifecycle_status = 'active'),
  -- the provider itself, when no source was found at all
  pr as (
    select pv.id provider_id, 'provider' item_key, 'source_not_discovered' state,
           'discovery ' || coalesce(dp.status, 'never queued') || coalesce(' (' || dp.settle_reason || ')', '') || coalesce(', kept ' || dp.kept_count || ' of ' || dp.url_count, '') reason,
           jsonb_build_object('discovery', dp.status, 'method', dp.method, 'kept', dp.kept_count, 'mapped', dp.url_count, 'discovered_at', dp.discovered_at,
                              'next_discover_at', dp.next_discover_at, 'admission_ok', pv.admit_ok, 'provider_type', pv.ptype) evidence, null::text recovery
      from pv left join pipeline.scholarship_discovery_providers dp on dp.provider_id = pv.id
     where not exists (select 1 from cands c where c.provider_id = pv.id) and not exists (select 1 from lst l where l.provider_id = pv.id and l.active)
       and not exists (select 1 from scholarship.scholarships s where s.provider_id = pv.id and s.lifecycle_status = 'active'))
  select * from cs union all select * from rg union all select * from li union all select * from ls union all select * from sh union all select * from pr
$function$;
revoke all on function security.scholarship_coverage_items_v1(uuid[]) from public, anon, authenticated;
comment on function security.scholarship_coverage_items_v1(uuid[]) is 'CF-247 (mandate 4 Nov 2026 05:08 §5): every scholarship coverage case of the providers given in one of the 13 states (pipeline.scholarship_coverage_state_codes), with reason, evidence and the recovery that applies. Read-only.';

-- 7. the job: classify, record, report, escalate (§5, §9) ----------------------------------------------------------------------------------------------
create or replace function security.scholarship_coverage_classify_v1(p_providers uuid[] default null) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 05:08 §5, §9): classifies the next providers (or those given), keeps their cases, verifies recoveries, records the provider
-- state and reports each unresolved state into the work-continuity record (lane sch_coverage) only when its signature changes.
declare v_ids uuid[]; v_now timestamptz := now(); v_esc numeric := security.pipeline_num_v1('sch_cov.escalate_after_hours', 72);
        v_re numeric := security.pipeline_num_v1('sch_cov.recheck_hours', 24); v_ver numeric := security.pipeline_num_v1('sch_cov.verify_after_hours', 48);
        r record; p record; v_sig text; v_rep jsonb; v_ev text; v_n int := 0; v_items int := 0; v_reports int := 0; v_ok int := 0; v_fail int := 0;
begin
  if p_providers is null and security.pipeline_num_v1('sch_cov.classify_on', 1) < 1 then return jsonb_build_object('ran', false, 'reason', 'sch_cov.classify_on is 0'); end if;
  if p_providers is not null then v_ids := p_providers;
  else
    select coalesce(array_agg(x.provider_id), '{}') into v_ids from (
      select l.provider_id from pipeline.coverage_provider_reconciliation l
        left join pipeline.scholarship_coverage_providers c on c.provider_id = l.provider_id
       where l.domain = 'scholarship' and l.disposition not in ('not_applicable', 'out_of_scope')
         and (c.provider_id is null or c.classified_at < v_now - make_interval(hours => security.pipeline_num_v1('sch_cov.reclassify_hours', 6)::int))
       order by (c.provider_id is null) desc, (l.issue_fingerprint is not null) desc, c.classified_at nulls first, l.provider_id
       limit security.pipeline_num_v1('batch.sch_coverage_classify', 40)::int) x;
  end if;
  if cardinality(v_ids) = 0 then return jsonb_build_object('ran', true, 'providers', 0); end if;

  create temp table if not exists sch_cov_now(provider_id uuid, item_key text, state text, reason text, evidence jsonb, recovery text) on commit drop;
  truncate sch_cov_now;
  insert into sch_cov_now select * from security.scholarship_coverage_items_v1(v_ids);
  get diagnostics v_items = row_count;

  insert into pipeline.scholarship_coverage_items as i(provider_id, item_key, state, reason, evidence, recovery, owner, next_recovery_at, escalation, present, first_seen, state_since, classified_at)
  select n.provider_id, n.item_key, n.state, n.reason, n.evidence, case when n.state in ('rejected_incorrectly', 'traversal_incomplete') then n.recovery end, k.owner,
         case when k.resolved then null else v_now + make_interval(hours => v_re::int) end, null, true, v_now, v_now, v_now
    from sch_cov_now n join pipeline.scholarship_coverage_state_codes k on k.code = n.state
  on conflict (provider_id, item_key) do update set
     state_since = case when i.state is distinct from excluded.state or not i.present then v_now else i.state_since end,
     state = excluded.state, reason = excluded.reason, evidence = excluded.evidence, recovery = excluded.recovery, owner = excluded.owner,
     next_recovery_at = excluded.next_recovery_at, present = true, classified_at = v_now;
  update pipeline.scholarship_coverage_items i set present = false, classified_at = v_now, next_recovery_at = null
   where i.provider_id = any (v_ids) and i.present and not exists (select 1 from sch_cov_now n where n.provider_id = i.provider_id and n.item_key = i.item_key);

  -- §9 steps 7-8: a recovery succeeded when its case moved; it failed when the case has not moved after sch_cov.verify_after_hours
  update pipeline.scholarship_coverage_recoveries x set outcome = 'succeeded', outcome_at = v_now
    from pipeline.scholarship_coverage_items i
   where x.outcome is null and i.provider_id = x.provider_id and i.item_key = x.item_key and x.provider_id = any (v_ids) and (not i.present or i.state <> x.state_before);
  get diagnostics v_ok = row_count;
  update pipeline.scholarship_coverage_recoveries x set outcome = 'failed', outcome_at = v_now
    from pipeline.scholarship_coverage_items i
   where x.outcome is null and i.provider_id = x.provider_id and i.item_key = x.item_key and x.provider_id = any (v_ids) and i.present and i.state = x.state_before
     and x.at < v_now - make_interval(hours => v_ver::int);
  get diagnostics v_fail = row_count;

  -- the escalation condition of each unresolved case
  update pipeline.scholarship_coverage_items i set escalation = jsonb_build_object('condition', k.escalate_when,
           'due_at', case k.escalate_when when 'always' then i.first_seen when 'after_hours' then i.first_seen + make_interval(hours => v_esc::int)
                                          when 'recovery_failed' then (select min(x.outcome_at) from pipeline.scholarship_coverage_recoveries x where x.item_key = i.item_key and x.outcome = 'failed') end,
           'due', case k.escalate_when when 'always' then true when 'after_hours' then i.first_seen < v_now - make_interval(hours => v_esc::int)
                                       when 'recovery_failed' then exists (select 1 from pipeline.scholarship_coverage_recoveries x where x.item_key = i.item_key and x.outcome = 'failed')
                                       else false end)
    from pipeline.scholarship_coverage_state_codes k
   where k.code = i.state and i.provider_id = any (v_ids) and i.present and not k.resolved;
  update pipeline.scholarship_coverage_items i set escalation = null
    from pipeline.scholarship_coverage_state_codes k where k.code = i.state and i.provider_id = any (v_ids) and (k.resolved or not i.present) and i.escalation is not null;

  -- the provider state and the work-continuity record
  for p in select x.id, coalesce(c.reported, '{}'::jsonb) reported,
                  (select coalesce(jsonb_object_agg(s.state, s.n), '{}'::jsonb) from (select i.state, count(*) n from pipeline.scholarship_coverage_items i
                     where i.provider_id = x.id and i.present group by 1) s) states
             from unnest(v_ids) x(id) left join pipeline.scholarship_coverage_providers c on c.provider_id = x.id loop
    v_rep := '{}'::jsonb;
    for r in select k.code, k.resolved, k.work_event, k.owner, count(i.item_key) n, bool_or(coalesce((i.escalation->>'due')::boolean, false)) due,
                    min(i.next_recovery_at) next_at, (array_agg(i.evidence order by i.first_seen))[1:3] sample, (array_agg(i.reason order by i.first_seen))[1] reason,
                    string_agg(i.item_key, ',' order by i.item_key) keys
               from pipeline.scholarship_coverage_state_codes k
               join pipeline.scholarship_coverage_items i on i.state = k.code and i.provider_id = p.id and i.present
              where not k.resolved group by k.code, k.resolved, k.work_event, k.owner loop
      v_sig := md5(r.n || '|' || r.due || '|' || r.keys);
      v_rep := v_rep || jsonb_build_object(r.code, v_sig);
      continue when p.reported->>r.code = v_sig;
      v_ev := case when r.due and r.work_event in ('dependency', 'ambiguity') then 'failed'
                   when r.work_event = 'review' then 'review' when r.work_event = 'identity' then 'failed' when r.work_event = 'ambiguity' then 'failed' else 'dependency' end;
      perform security.work_item_report_v1('sch_coverage', p.id::text, 'state:' || r.code, v_ev,
        jsonb_build_object('provider_id', p.id, 'owner', r.owner, 'field', r.code,
                           'class', case when r.work_event = 'identity' then 'identity_conflict' when r.work_event = 'ambiguity' then 'ambiguity' when r.due then 'authority' end,
                           'reason', r.code || ': ' || r.n || ' case(s); ' || coalesce(r.reason, ''), 'review_ref', 'sch_coverage:' || p.id || ':' || r.code,
                           'ref', jsonb_build_object('state', r.code, 'next_recovery_at', r.next_at, 'owner', r.owner),
                           'evidence', jsonb_build_object('cases', r.n, 'sample', to_jsonb(r.sample), 'escalation_due', r.due)));
      v_reports := v_reports + 1;
    end loop;
    -- a state reported before and now resolved or gone: the work item is done
    for r in select e.key code from jsonb_each_text(p.reported) e where not v_rep ? e.key loop
      perform security.work_item_report_v1('sch_coverage', p.id::text, 'state:' || r.code, 'succeeded', jsonb_build_object('provider_id', p.id, 'outcome', 'succeeded_with_result'));
      v_reports := v_reports + 1;
    end loop;
    insert into pipeline.scholarship_coverage_providers as c(provider_id, provider_state, states, unresolved, published_verified, reported, classified_at)
    select p.id,
           coalesce((select k.code from pipeline.scholarship_coverage_state_codes k where not k.resolved and p.states ? k.code order by k.sort limit 1),
                    case when coalesce((p.states->>'published_verified')::int, 0) > 0 then 'published_verified'
                         when exists (select 1 from pipeline.scholarship_listing_pages l where l.provider_id = p.id and l.active and l.source in ('manual', 'auto')
                                                                                       and l.status = 'read' and l.page_state in ('complete', 'single')) then 'evidence_backed_none'
                         else 'source_not_discovered' end),
           p.states, (select coalesce(sum(e.value::int), 0) from jsonb_each_text(p.states) e join pipeline.scholarship_coverage_state_codes k on k.code = e.key and not k.resolved),
           coalesce((p.states->>'published_verified')::int, 0), v_rep, v_now
    on conflict (provider_id) do update set provider_state = excluded.provider_state, states = excluded.states, unresolved = excluded.unresolved,
       published_verified = excluded.published_verified, reported = excluded.reported, classified_at = v_now;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ran', true, 'providers', v_n, 'cases', v_items, 'work_reports', v_reports, 'recoveries_succeeded', v_ok, 'recoveries_failed', v_fail);
end $function$;
revoke all on function security.scholarship_coverage_classify_v1(uuid[]) from public, anon, authenticated;
comment on function security.scholarship_coverage_classify_v1(uuid[]) is 'CF-247 (mandate 4 Nov 2026 05:08 §5, §9): job scholarship-coverage-classify. Classifies providers'' scholarship cases, verifies recoveries, records provider states and reports unresolved states into the work-continuity record (lane sch_coverage). Records only.';

-- 8. the job: bounded recovery (§5, §9) -- each family behind its own switch, all OFF --------------------------------------------------------------------
create or replace function security.scholarship_coverage_recover_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 (mandate 4 Nov 2026 05:08 §5, §9): at most batch.sch_coverage_recover actions a run and sch_cov.recover_per_provider_max per provider, each
-- at most once per case (pipeline.scholarship_coverage_recoveries is unique on case and action), only for admission-eligible providers that are not
-- hidden or held. Nothing admits, decides or publishes: the pages go back to the normal readers and the normal AI admission or Layer 4 route.
declare v_max int := security.pipeline_num_v1('batch.sch_coverage_recover', 10)::int; v_pp int := security.pipeline_num_v1('sch_cov.recover_per_provider_max', 3)::int;
        v_on jsonb := jsonb_build_object('reopen_read', security.pipeline_num_v1('sch_cov.recover_register_pages_on', 0) >= 1,
                                         'reread_stored', security.pipeline_num_v1('sch_cov.recover_stored_reads_on', 0) >= 1,
                                         'promote_listing', security.pipeline_num_v1('sch_cov.recover_listings_on', 0) >= 1,
                                         'refresh_listing', security.pipeline_num_v1('sch_cov.recover_listings_on', 0) >= 1);
        r record; v_cid bigint; v_lid bigint; v_done int := 0; v_skip int := 0; v_per jsonb := '{}'::jsonb; v_by jsonb := '{}'::jsonb; a record; v_k int;
begin
  if not exists (select 1 from jsonb_each(v_on) e where e.value = 'true'::jsonb) then return jsonb_build_object('ran', false, 'reason', 'every recovery switch is 0', 'switches', v_on); end if;
  for r in select i.* from pipeline.scholarship_coverage_items i
            where i.present and i.recovery is not null and i.state in ('rejected_incorrectly', 'traversal_incomplete')
              and coalesce((v_on->>i.recovery)::boolean, false)
              and not exists (select 1 from pipeline.scholarship_coverage_recoveries x where x.item_key = i.item_key and x.action = i.recovery)
            order by i.first_seen, i.provider_id, i.item_key loop
    exit when v_done >= v_max;
    if coalesce((v_per->>r.provider_id::text)::int, 0) >= v_pp then continue; end if;
    if not security.scholarship_admission_provider_ok_v1(r.provider_id) or security.fc_sch_held_v1(r.provider_id, true)
       or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id) then v_skip := v_skip + 1; continue; end if;
    v_cid := nullif(r.evidence->>'candidate_id', '')::bigint; v_lid := nullif(r.evidence->>'listing_id', '')::bigint; v_k := 0;
    if r.recovery = 'reopen_read' then
      -- one read of a page never read: back to the candidate reader (Firecrawl through svc_fc_spend, then the AI on the normal admission route)
      update pipeline.scholarship_page_candidates c set admit_status = null, admit_reasons = null, next_read_at = now(), attempts = 0, leased_until = null
       where c.id = v_cid and c.admit_status = 'rejected' and c.read_status is null and c.matched_scholarship_id is null and c.admitted_scholarship_id is null;
      get diagnostics v_k = row_count;
    elsif r.recovery = 'reread_stored' then
      -- one AI read from the stored copy (no Firecrawl: next_read_at keeps the candidate reader away); the answer takes the normal admission route
      select * into a from security.scholarship_ai_active_v1();
      if a.model_code is not null then
        update pipeline.scholarship_page_candidates c set admit_status = null, admit_reasons = null, next_read_at = 'infinity'
         where c.id = v_cid and c.admit_status = 'rejected' and c.storage_path is not null and c.matched_scholarship_id is null and c.admitted_scholarship_id is null
           and not exists (select 1 from pipeline.scholarship_ai_queue q where q.candidate_id = c.id and q.state in ('queued', 'leased'));
        get diagnostics v_k = row_count;
        if v_k > 0 then
          insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, candidate_id, provider_id, url, storage_path)
          select a.model_code, a.prompt_version, 'admit', c.id, c.provider_id, coalesce(c.final_url, c.url), c.storage_path from pipeline.scholarship_page_candidates c where c.id = v_cid;
        end if;
      end if;
    elsif r.recovery = 'promote_listing' then
      -- the AI said: a listing of international scholarships on the provider's own site; it becomes a listing source (read once now, then weekly)
      insert into pipeline.scholarship_listing_pages as l(provider_id, url, url_norm, source, active, status, next_read_at, added_at)
      select c.provider_id, coalesce(c.final_url, c.url), security.scholarship_url_norm(coalesce(c.final_url, c.url)), 'auto', true, 'waiting', now(), now()
        from pipeline.scholarship_page_candidates c where c.id = v_cid and not security.third_party_host_v1(coalesce(c.final_url, c.url))
      on conflict (provider_id, url_norm) do update set source = 'auto', active = true, status = 'waiting', next_read_at = now() where l.source = 'suggested';
      get diagnostics v_k = row_count;
    elsif r.recovery = 'refresh_listing' then
      -- a listing read before its items became candidates: read once now (the recorder fans its items out)
      if not exists (select 1 from pipeline.scholarship_coverage_recoveries x where x.action = 'refresh_listing' and (x.detail->>'listing_id')::bigint = v_lid) then
        update pipeline.scholarship_listing_pages l set next_read_at = now() where l.id = v_lid and l.active and l.page_state is null and l.next_read_at > now();
        get diagnostics v_k = row_count;
      end if;
    end if;
    -- recorded whatever happened, so the same case is never tried twice
    insert into pipeline.scholarship_coverage_recoveries(provider_id, item_key, action, state_before, detail)
    values (r.provider_id, r.item_key, r.recovery, r.state, jsonb_build_object('candidate_id', v_cid, 'listing_id', v_lid, 'changed', v_k, 'reason', r.reason))
    on conflict (item_key, action) do nothing;
    if v_k > 0 then
      v_done := v_done + 1; v_per := v_per || jsonb_build_object(r.provider_id::text, coalesce((v_per->>r.provider_id::text)::int, 0) + 1);
      v_by := v_by || jsonb_build_object(r.recovery, coalesce((v_by->>r.recovery)::int, 0) + 1);
    else v_skip := v_skip + 1; end if;
  end loop;
  return jsonb_build_object('ran', true, 'actions', v_done, 'by_action', v_by, 'skipped', v_skip, 'providers', (select count(*) from jsonb_object_keys(v_per)), 'switches', v_on);
end $function$;
revoke all on function security.scholarship_coverage_recover_v1() from public, anon, authenticated;
comment on function security.scholarship_coverage_recover_v1() is 'CF-247 (mandate 4 Nov 2026 05:08 §5, §9): job scholarship-coverage-recover. Bounded, once-per-case recovery (reopen_read, reread_stored, promote_listing, refresh_listing), each family behind a switch that ships off. Admits, decides and publishes nothing.';

-- 9. report and verification (read only) ----------------------------------------------------------------------------------------------------------------
create or replace function security.scholarship_coverage_report_v1(p_provider uuid default null) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 (mandate 4 Nov 2026 05:08 §5, §11): cases by state, providers by state, recoveries by action and outcome; one provider's cases when given
  select jsonb_build_object(
    'cases', (select coalesce(jsonb_object_agg(s.state, s.n), '{}'::jsonb) from (select i.state, count(*) n from pipeline.scholarship_coverage_items i
               where i.present and (p_provider is null or i.provider_id = p_provider) group by 1) s),
    'escalation_due', (select count(*) from pipeline.scholarship_coverage_items i where i.present and (i.escalation->>'due')::boolean and (p_provider is null or i.provider_id = p_provider)),
    'providers', (select coalesce(jsonb_object_agg(s.provider_state, s.n), '{}'::jsonb) from (select c.provider_state, count(*) n from pipeline.scholarship_coverage_providers c
                   where p_provider is null or c.provider_id = p_provider group by 1) s),
    'recoveries', (select coalesce(jsonb_object_agg(s.k, s.n), '{}'::jsonb) from (select x.action || ':' || coalesce(x.outcome, 'pending') k, count(*) n
                    from pipeline.scholarship_coverage_recoveries x where p_provider is null or x.provider_id = p_provider group by 1) s),
    'detail', case when p_provider is not null then (select coalesce(jsonb_agg(jsonb_build_object('key', i.item_key, 'state', i.state, 'reason', i.reason, 'owner', i.owner,
                    'next_recovery_at', i.next_recovery_at, 'escalation', i.escalation, 'recovery', i.recovery, 'evidence', i.evidence) order by i.state, i.item_key), '[]'::jsonb)
                    from pipeline.scholarship_coverage_items i where i.provider_id = p_provider and i.present) end)
$function$;
revoke all on function security.scholarship_coverage_report_v1(uuid) from public, anon, authenticated;

create or replace function security.scholarship_coverage_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247: the issue's providers have no unresolved recoverable case (rejected incorrectly, traversal incomplete, found but unread) and none due to escalate
  with pv as (select unnest(i.provider_ids) id from pipeline.integration_issues i where i.id = p_issue),
  m as (select count(*) filter (where c.state in ('rejected_incorrectly', 'traversal_incomplete', 'source_found_unread')) recoverable,
               count(*) filter (where (c.escalation->>'due')::boolean) due, count(*) filter (where c.state = 'published_verified') published
          from pipeline.scholarship_coverage_items c join pv on pv.id = c.provider_id where c.present)
  select jsonb_build_object('passed', m.recoverable = 0 and m.due = 0, 'measure', to_jsonb(m), 'evidence', 'pipeline.scholarship_coverage_items (security.scholarship_coverage_report_v1)') from m
$function$;
revoke all on function security.scholarship_coverage_verify_v1(bigint) from public, anon, authenticated;

create or replace function security.scholarship_coverage_classify_remedy_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247: the 'auto' remedy: classify the issue's providers now (records only)
declare v_ids uuid[]; v jsonb;
begin
  select i.provider_ids into v_ids from pipeline.integration_issues i where i.id = p_issue;
  if coalesce(cardinality(v_ids), 0) = 0 then return jsonb_build_object('ok', false, 'changed', false, 'evidence', 'issue has no provider'); end if;
  v := security.scholarship_coverage_classify_v1(v_ids);
  return jsonb_build_object('ok', true, 'changed', coalesce((v->>'work_reports')::int, 0) > 0, 'evidence', v);
end $function$;
revoke all on function security.scholarship_coverage_classify_remedy_v1(bigint) from public, anon, authenticated;

-- 10. root causes and remedies (workstream A's contract) ------------------------------------------------------------------------------------------------
select security.ops_root_cause_register_v1('sch_provider_identity_joined_names', jsonb_build_object('class', 'rule',
  'title', 'A university is refused by the name rule because its record joins its trading names',
  'description', 'security.scholarship_university tests the whole canonical name; Torrens University Australia''s record joins its CRICOS trading names (a Language Centre among them), so the exclusion refuses a TEQSA-registered Australian University and every page of it is refused (IQ-00215; 1 of 43 joined-name providers).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_items_v1(uuid[])', 'state', 'rejected_incorrectly', 'reason', 'provider_identity_name_rule')));
select security.ops_root_cause_register_v1('sch_register_pages_never_read', jsonb_build_object('class', 'rule',
  'title', 'Provider pages that came from the retired register were rejected unread',
  'description', 'The 11 Oct 2026 retirement (20261011008400 §4c) rejected every register-sourced candidate as register_retired without reading it, and the AI enqueue skips source register: 72 provider-site pages of 51 providers are never read (Torrens 6).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_items_v1(uuid[])', 'state', 'rejected_incorrectly', 'reason', 'register_page_never_read')));
select security.ops_root_cause_register_v1('sch_listing_verdict_not_traversed', jsonb_build_object('class', 'rule',
  'title', 'Pages the AI classifies as scholarship listings never become listing sources',
  'description', 'With AI admission on, the candidate recorder suggests a listing page before the AI answers; an AI listing verdict is final and the page is never traversed (618 international listing pages, 158 providers; TAFE SA 8435).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_items_v1(uuid[])', 'state', 'traversal_incomplete', 'recovery', 'promote_listing')));
select security.ops_root_cause_register_v1('sch_listing_read_before_fanout', jsonb_build_object('class', 'dependency',
  'title', 'A listing read before items became candidates waits a week for its next read',
  'description', 'Listing sources last read by the retired recorder (page_state null) have no members; their items become candidates only at the next weekly read (17 of 23 sources; Torrens listing 61).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_items_v1(uuid[])', 'state', 'traversal_incomplete', 'reason', 'listing_read_before_fan_out')));
select security.ops_root_cause_register_v1('sch_policy_reported_as_zero', jsonb_build_object('class', 'rule',
  'title', 'Providers the admission policy refuses are reported as zero scholarships',
  'description', 'security.scholarship_coverage_v1 reports a provider-level TAFE, university college or wananga outside the non-university pilot as zero (P1) instead of blocked by policy: 45 providers, 26 open coverage issues (IQ-00216, IQ-00219 among them).',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_v1(uuid[])', 'disposition', 'zero', 'measure', 'admission_ok false and provider_level true')));
select security.ops_root_cause_register_v1('sch_subbrand_host_unowned', jsonb_build_object('class', 'data',
  'title', 'Scholarship pages on a sub-brand host the provider does not own',
  'description', 'Register entries point at a host outside the provider''s discovery sites (50 entries, 9 providers, 16 hosts; Torrens: 6 BMIHMS awards on bluemountains.edu.au). Whose pages they are is a provider identity decision.',
  'detect', jsonb_build_object('fn', 'security.scholarship_coverage_items_v1(uuid[])', 'state', 'ownership_conflict', 'reason', 'register_page_on_unowned_host')));
select security.ops_root_cause_register_v1('sch_read_again_not_due', jsonb_build_object('class', 'rule',
  'title', 'Read again on a scholarship page does not read it',
  'description', 'public.svc_scholarship_read_next took only pages whose next_read_at had passed; requested_at only ordered them (8 Macquarie pages requested 3 Nov 2026 waited for 12 Nov).',
  'detect', jsonb_build_object('table', 'pipeline.scholarship_pages', 'measure', 'requested_at is not null and requested_at > read_at and next_read_at > now()')));

select security.ops_remedy_register_v1('sch_coverage_classify', jsonb_build_object('authority', 'auto',
  'treats', jsonb_build_array('sch_zero_scholarships', 'sch_under_represented', 'sch_category_missing', 'sch_listing_not_fanned_out', 'sch_provider_identity_joined_names',
                              'sch_register_pages_never_read', 'sch_listing_verdict_not_traversed', 'sch_listing_read_before_fanout', 'sch_subbrand_host_unowned'),
  'title', 'Classify the provider''s scholarship cases now (13 states, owners, recovery times, escalation)',
  'action_fn', 'security.scholarship_coverage_classify_remedy_v1(bigint)', 'verify_fn', 'security.scholarship_coverage_verify_v1(bigint)',
  'notes', 'Records only (pipeline.scholarship_coverage_items, work items in lane sch_coverage).'));
select security.ops_remedy_register_v1('sch_coverage_recover', jsonb_build_object('authority', 'release',
  'treats', jsonb_build_array('sch_register_pages_never_read', 'sch_listing_verdict_not_traversed', 'sch_listing_read_before_fanout', 'sch_provider_identity_joined_names'),
  'title', 'Bounded once-per-case recovery: reopen_read, reread_stored, promote_listing, refresh_listing (job scholarship-coverage-recover)',
  'verify_fn', 'security.scholarship_coverage_verify_v1(bigint)',
  'notes', 'Each family ships off: sch_cov.recover_register_pages_on, sch_cov.recover_stored_reads_on, sch_cov.recover_listings_on (Firecrawl or AI spend; Platform Admin).'));
select security.ops_remedy_register_v1('sch_legal_name_identity', jsonb_build_object('authority', 'admin', 'treats', jsonb_build_array('sch_provider_identity_joined_names'),
  'title', 'Test joined-name providers as universities on their legal name (sch_cov.legal_name_identity_on)',
  'verify_fn', 'security.scholarship_coverage_verify_v1(bigint)', 'notes', 'Ships off: widens admission eligibility (Torrens today).'));
select security.ops_remedy_register_v1('sch_policy_disposition', jsonb_build_object('authority', 'admin', 'treats', jsonb_build_array('sch_policy_reported_as_zero'),
  'title', 'Report policy-refused provider-level providers as blocked by policy; the Platform Admin sets the issue severities',
  'notes', 'sch_cov.policy_disposition_on ships off; integration_issue_upsert_v1 never lowers a severity, so the open P1 issues are changed by a person.'));
select security.ops_remedy_register_v1('sch_subbrand_host_decision', jsonb_build_object('authority', 'admin', 'treats', jsonb_build_array('sch_subbrand_host_unowned'),
  'title', 'Platform Admin decides whether a sub-brand host belongs to the provider (discovery allowed_hosts)',
  'notes', 'No host is added automatically; the case is quarantined (identity) with its evidence.'));
select security.ops_remedy_register_v1('sch_read_again_due', jsonb_build_object('authority', 'release', 'treats', jsonb_build_array('sch_read_again_not_due'),
  'title', 'A page requested since its last read is due (public.svc_scholarship_read_next, release 20261104370000)',
  'notes', 'Read once per request; the recorder clears requested_at.'));

-- 11. jobs (G1), catalogue first -----------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('scholarship-coverage-classify', 'Scholarships', 58, 'Scholarship coverage: classify every case',
  'Every hour at :29 (after coverage-reconcile): classifies each provider''s scholarship cases in 13 states, verifies recoveries, and records unresolved cases with an owner, evidence, a next recovery time and an escalation in the work-continuity record (lane sch_coverage). Switch sch_cov.classify_on; size batch.sch_coverage_classify. Reads and records only.',
  5, true, null),
 ('scholarship-coverage-recover', 'Scholarships', 59, 'Scholarship coverage: bounded recovery',
  'Every hour at :31: at most batch.sch_coverage_recover once-per-case recovery actions (read a never-read register page, read a refused page again from its stored copy, traverse a listing). Each family has its own switch (sch_cov.recover_*), all off until the Platform Admin switches them on. Admits, decides and publishes nothing.',
  5, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'scholarship-coverage-classify') then
    perform cron.schedule('scholarship-coverage-classify', '29 * * * *', 'select security.scholarship_coverage_classify_v1()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'scholarship-coverage-recover') then
    perform cron.schedule('scholarship-coverage-recover', '31 * * * *', 'select security.scholarship_coverage_recover_v1()');
  end if;
end $j$;

-- 12. register (housekeeping) ----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'scholarship-coverage-classify', 'Layer 2', 'Scholarships', 'Scholarship coverage cases in 13 states, work items and escalation', 'active', '{}', '20261104370000'),
 ('job', 'scholarship-coverage-recover', 'Layer 2', 'Scholarships', 'Bounded once-per-case scholarship coverage recovery (switches off)', 'active', '{}', '20261104370000'),
 ('table', 'pipeline.scholarship_coverage_state_codes', 'Layer 2', 'Scholarships', 'The 13 coverage states', 'active', '{}', '20261104370000'),
 ('table', 'pipeline.scholarship_coverage_items', 'Layer 2', 'Scholarships', 'Scholarship coverage cases per provider', 'active', '{}', '20261104370000'),
 ('table', 'pipeline.scholarship_coverage_providers', 'Layer 2', 'Scholarships', 'Scholarship coverage state per provider', 'active', '{}', '20261104370000'),
 ('table', 'pipeline.scholarship_coverage_recoveries', 'Layer 2', 'Scholarships', 'Scholarship coverage recovery actions and outcomes', 'active', '{}', '20261104370000')
on conflict do nothing;

-- 13. post-check ---------------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if md5(pg_get_functiondef('security.scholarship_university(uuid)'::regprocedure)) <> 'cee99ebcfe6ce05751a879260333e6d2' then raise exception 'post-check: scholarship_university'; end if;
  if md5(pg_get_functiondef('security.scholarship_coverage_v1(uuid[])'::regprocedure)) <> '772004147c66c4031ff18a37260008af' then raise exception 'post-check: scholarship_coverage_v1'; end if;
  if md5(pg_get_functiondef('public.svc_scholarship_read_next(integer)'::regprocedure)) <> '452c288e17dd7207574808737d88c14a' then raise exception 'post-check: svc_scholarship_read_next'; end if;
  if (select count(*) from pipeline.scholarship_coverage_state_codes) <> 13 then raise exception 'post-check: 13 states'; end if;
  if (select count(*) from cron.job where jobname in ('scholarship-coverage-classify', 'scholarship-coverage-recover')) <> 2 then raise exception 'post-check: jobs'; end if;
  if (select count(*) from pipeline.automation_catalogue where jobname in ('scholarship-coverage-classify', 'scholarship-coverage-recover')) <> 2 then raise exception 'post-check: catalogue'; end if;
  if (select authority from pipeline.ops_remedies where code = 'sch_coverage_recover') <> 'release' then raise exception 'post-check: recovery is never automatic by authority'; end if;
end $$;
