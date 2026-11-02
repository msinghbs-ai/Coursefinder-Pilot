-- CF-247 Scholarship Coverage Recovery: discovery, catalogue enumeration and run outcomes (Platform Admin mandate 2 Nov 2026 17:41, §4, §5, §8;
-- overnight direction 2 Nov 2026 23:24 §1 Scholarships, §3, §4). Design and evidence: admin docs/platform/nz-enrichment-brief/
-- 2026-11-02-scholarship-unsw-diagnosis.md (Workstream A, root causes RC1-RC11, fixes F1-F10) and 2026-11-02-scholarship-coverage-baseline.md
-- (Workstream B, root causes RC1-RC11).
-- Why (live, read-only, 2 Nov 2026 17:42-20:30 AEDT): every scholarship_discover run since 16:50 failed (HTTP 500, statement timeout in
--   svc_scholarship_discover_next: the picker ordered all 1,138 pending rows by a per-row course count; 6.8 s for the same selection) while
--   the scheduler said "succeeded"; a refused site map was recorded as a final "empty" (UNSW since 12 Oct, 26 of 40 AU universities); only the
--   provider's website was ever mapped; listing pages were read one page at a time and only compared, never turned into candidates; umbrella
--   pages listing several awards were refused whole (UNSW Term 1 2027: 8 of 10 international awards not discovered); legacy addresses that
--   now open the catalogue home were read as pages; an all-time cap of 60,000 credits sat under the daily budget; run sizes were literals.
-- What:
--   F1 Pickers: svc_scholarship_discover_next orders a small window by a stored tier (pipeline.scholarship_discovery_providers.tier, refreshed
--      by the hourly refill) and checks the per-provider holds only on that window; a held provider waits retry.scholarship_discovery_held_hours
--      instead of blocking the head of the queue. svc_scholarship_candidate_next does the same over a window of candidates; the address skip
--      rules run when candidates are recorded and hourly (security.scholarship_candidate_skip_v1), not on every pick.
--   F2 Run outcomes: every worker call in pipeline.mode_outcome_ledger gets an outcome (succeeded, idle, zero_work_error, failed) from
--      security.worker_call_outcome_v1: HTTP 500, ok:false or an error is failed; no successful work with a refusal or error in the answer is
--      zero_work_error, never succeeded. security.job_outcomes_v1 reads them per mode with the scheduled jobs that call the mode. Job
--      worker-outcome-check (every 10 minutes, created PAUSED) opens one Platform health issue per mode (worker:<mode>) after
--      worker.outcome_failed_runs failed or zero-work-error runs in a row and resolves it on the next good run.
--   F3 A refused or failed map is "deferred" (tried again after retry.scholarship_discovery_deferred_hours), never "empty"; url_count is no
--      longer overwritten by a refusal. Re-discovery cadence: a mapped or empty provider is due again reread.scholarship_discovery_days after
--      its last map (next_discover_at), picked by the same picker.
--   F4 Every source: the picker returns the provider's sources (website, then each active listing source recorded for it, manual or auto),
--      and the worker maps each one (scholarship.sources_per_provider_max).
--   F5 Listing items become candidates: svc_scholarship_listing_record_v2 keeps listing membership (pipeline.scholarship_listing_members) and
--      turns each new item into a candidate on the provider's own site; an award of an umbrella page without its own page becomes a section
--      candidate "<page>#award-<code>" (setting scholarship.umbrella_sections_on). The admission check uses the section address as the
--      record's identity, so ten awards on one page are ten records and an award with its own page is still found by its name (no duplicate).
--   F6 Pagination: listing sources record page_state (single, complete, partial, failed), pages read, the stated total, and the address to
--      continue from; complete only when the pagination ended by itself. A partial source is read again after
--      retry.scholarship_listing_partial_hours from where it stopped.
--   F7 Moved and redirected sources: a candidate that now opens the catalogue home, a listing or a search page is refused as redirected_away
--      (no AI read); a scholarship page whose final address differs is recorded in pipeline.scholarship_source_moves (moved or
--      redirected_away), once per address, for Coverage and Layer 4 to act on. Nothing is withdrawn automatically by this.
--   F8 The all-time scholarship cap (scholarship_layer_settings firecrawl_cap, 60,000) is retired into the normal settings: with
--      scholarship.lifetime_cap_on off (default) svc_scholarship_fc_budget gives the worker the daily scholarship share as its ceiling; the
--      daily budget, the share and the per-university cap in svc_fc_spend stay the limits. No value is raised.
--   F9 Closed round versus ended: pipeline.scholarship_round_states classifies each active scholarship (open, opening_soon, closed_round,
--      ended, no_dates) from its dates and its page (gone, redirected away, award no longer listed, not currently offered), hourly by the
--      refill. The consumer API already reports a passed close date as current_status 'closed' and never 'open' (api.website_v2_scholarship_
--      item, unchanged); nothing here changes publication. An additive consumer field is a proposal only (admin record).
--   F10 Settings for the run sizes (security.scholarship_task_fire_v1, worker caps), the tier course threshold, the listing item and page
--      limits, the render waits, the map candidate cap and the pick windows; svc_worker_settings_v1 also returns the pipeline scholarship.* keys.
--   Proposed, built OFF (Platform Admin approval needed to switch on; overnight direction 23:24 §1):
--      P1 scholarship.non_university_admission (off): non-university providers of the governed types in scholarship.non_university_types,
--         with a recorded provider type basis and their own website, may be admitted (security.scholarship_admission_provider_ok_v1); off,
--         admission stays universities only, as today.
--      P2 scholarship.legitimacy_checks_on (off): the course-count minimum (firecrawl scholarship_min_courses) is replaced by evidence-based
--         legitimacy checks (security.scholarship_legitimacy_v1: active, published, international enrolment not refused, governed provider
--         type, own website not a directory site, at least scholarship.legitimacy_min_courses active courses); off, the minimum stays.
-- Firecrawl: no limit is raised; every new knob that spends defaults to today's normal value (the authority of 16:39 expired at 02:57).
-- Consumer API: untouched (G3). No consumer function, table or column changes.
-- Replaces: public.svc_scholarship_discover_next, public.svc_scholarship_discover_record, public.svc_scholarship_candidate_next, public.svc_scholarship_listing_next, public.svc_scholarship_fc_budget, public.svc_worker_settings_v1, public.svc_worker_report_v1, public.svc_scholarship_candidate_record, public.svc_scholarship_read_record, security.scholarship_task_fire_v1, security.scholarship_discovery_refill_v1, security.fc_provider_tier_v1, security.fc_sch_eligible_v1, security.scholarship_admit_from_provider_page_v1 (same names; md5-guarded); public.svc_scholarship_listing_record by public.svc_scholarship_listing_record_v2 (worker v0.58.0)
-- Retires: public.svc_scholarship_listing_record (marked retiring; dropped by a paste file once unused); the all-time scholarship cap (setting scholarship.lifetime_cap_on off)
-- Nothing is dropped, deleted or switched on. The new job is created paused.

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

-- a whole definition replaced, only from the definition it was written against
create or replace function pg_temp.replace_once(p_sig text, p_before text, p_after text, p_def text) returns text language plpgsql as $f$
begin
  if md5(pg_get_functiondef(p_sig::regprocedure)) = p_after then return p_sig || ': already applied'; end if;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_before then
    raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)); end if;
  execute p_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the replacement has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after; end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions the new code reads are the ones it was written against (not changed here)
do $g$
declare r record;
begin
  for r in select * from (values ('security.fc_sch_held_v1(uuid,boolean)', 'f8d6fb4bf9196dfa596b8274819670a6'), ('security.scholarship_university(uuid)', '00ca2485d894ae4542b643a112c2b764'),
                                 ('security.scholarship_url_norm(text)', 'f982225c9a6310a3af9574b049623e8f'), ('security.fc_courses_v1(uuid)', 'abf532d980ae473619bb4a60b68b2281'),
                                 ('security.coverage_country(uuid)', '4b8447c1330f83d63a8211494d3d9675'), ('public.svc_scholarship_listing_record(bigint,text,integer,jsonb,text)', 'a72f798fc8cdf221dc68dedb721dc161')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2): every value is today's value or the normal approved limit; the two proposals ship off ---------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'scholarship.discover_providers_max', 'Scholarship discovery: most universities a run',
  'Most universities one scholarship_discover run maps (the job asks for Universities searched per run, capped here).', 'number', to_jsonb(6), 1, 30, 'universities', 1001, 'Job sizes',
  'coverage-sweep scholarship_discover (worker v0.58.0)', 'CF-247 scholarship recovery F10: the worker cap was the literal 6'),
 ('pipeline', 'scholarship.candidates_max', 'Scholarship discovery: most candidate pages a run',
  'Most candidate pages one run screens (the job asks for Candidate pages read per run, capped here).', 'number', to_jsonb(60), 1, 200, 'pages', 1002, 'Job sizes',
  'coverage-sweep scholarship_discover phase candidates (worker v0.58.0)', 'CF-247 scholarship recovery F10: the worker cap was the literal 60'),
 ('pipeline', 'scholarship.read_max', 'Scholarship pages: most read a run',
  'Most scholarship pages one scholarship_read run reads (the job asks for Scholarship pages re-read per run, capped here).', 'number', to_jsonb(40), 1, 200, 'pages', 1003, 'Job sizes',
  'coverage-sweep scholarship_read (worker v0.58.0)', 'CF-247 scholarship recovery F10: the worker cap was the literal 40'),
 ('pipeline', 'scholarship.listing_max', 'Scholarship listings: most sources a run',
  'Most listing sources one scholarship_listing run reads.', 'number', to_jsonb(20), 1, 100, 'sources', 1004, 'Job sizes',
  'coverage-sweep scholarship_listing (worker v0.58.0)', 'CF-247 scholarship recovery F10: the worker cap was the literal 20'),
 ('pipeline', 'scholarship.listing_pages_max', 'Scholarship listings: pages followed a run',
  'Most pages of one paginated catalogue read in one run; the rest is read from where it stopped (the source stays partial until its pagination ends). Each page is one scraper credit inside the daily scholarship share.',
  'number', to_jsonb(10), 1, 100, 'pages', 1005, 'Job sizes', 'coverage-sweep scholarship_listing (worker v0.58.0)', 'CF-247 scholarship recovery F6: paginated catalogues'),
 ('pipeline', 'scholarship.listing_items_max', 'Scholarship listings: items kept from a page',
  'Most scholarship items taken from one listing page.', 'number', to_jsonb(80), 10, 1000, 'items', 1006, 'Job sizes',
  'coverage-sweep scholarshipListing (worker v0.58.0)', 'CF-247 scholarship recovery F10: the literal 80'),
 ('pipeline', 'scholarship.map_candidates_max', 'Scholarship discovery: candidates kept from a site map',
  'Most candidate addresses kept from one provider''s site maps in one run.', 'number', to_jsonb(6000), 100, 100000, 'addresses', 1007, 'Job sizes',
  'coverage-sweep scholarship_discover (worker v0.58.0)', 'CF-247 scholarship recovery F10: the literal 6000'),
 ('pipeline', 'scholarship.sources_per_provider_max', 'Scholarship discovery: sources mapped per university',
  'Most sources of one provider mapped in one run: its website first, then the scholarship catalogues recorded for it (Scholarships › Coverage listing sources). One map credit each, inside the daily scholarship share.',
  'number', to_jsonb(5), 1, 20, 'sources', 1008, 'Job sizes', 'public.svc_scholarship_discover_next; coverage-sweep scholarship_discover', 'CF-247 scholarship recovery F4: every catalogue of a provider'),
 ('pipeline', 'scholarship.render_wait_ms', 'Scholarship pages: wait for the page to render',
  'How long the scraper waits for a scholarship page to finish rendering before taking it.', 'number', to_jsonb(1500), 0, 30000, 'milliseconds', 1009, 'Scholarships',
  'coverage-sweep readSch (worker v0.58.0)', 'CF-247 scholarship recovery F10: the literal 1500'),
 ('pipeline', 'scholarship.catalogue_render_wait_ms', 'Scholarship listings: wait for a catalogue to render',
  'How long the scraper waits for a listing or search catalogue (results drawn by script, such as UNSW''s scholarship finders) before taking it.', 'number', to_jsonb(5000), 0, 30000, 'milliseconds', 1010, 'Scholarships',
  'coverage-sweep scholarship_listing (worker v0.58.0)', 'CF-247 scholarship recovery F6: script catalogues render their results after load'),
 ('pipeline', 'scholarship.discover_pick_window', 'Scholarship discovery: queue rows checked a pick',
  'The discovery picker checks the holds only on this many rows at the head of the queue (by tier and priority); rows found held wait their retry time.',
  'number', to_jsonb(60), 6, 1000, 'rows', 1011, 'Job sizes', 'public.svc_scholarship_discover_next', 'CF-247 scholarship recovery F1: the picker timed out ordering every pending row'),
 ('pipeline', 'scholarship.candidate_pick_window', 'Scholarship discovery: candidate rows checked a pick',
  'The candidate picker ranks and checks this many due candidates at the head of the queue.', 'number', to_jsonb(600), 60, 10000, 'rows', 1012, 'Job sizes',
  'public.svc_scholarship_candidate_next', 'CF-247 scholarship recovery F1'),
 ('pipeline', 'batch.scholarship_tier_refresh', 'Scholarship discovery: queue tiers refreshed an hour',
  'Discovery rows whose processing tier (top 50, Australian with many courses, overseas, others) is worked out in one hourly refill.', 'number', to_jsonb(500), 10, 5000, 'rows', 1013, 'Job sizes',
  'security.scholarship_discovery_tier_refresh_v1 (job scholarship-discover-refill)', 'CF-247 scholarship recovery F1: the tier is stored, not computed per pick'),
 ('pipeline', 'batch.scholarship_round_state', 'Scholarship rounds: records classified an hour',
  'Active scholarships whose round state (open, opening soon, closed round, ended, no dates) is worked out in one hourly refill.', 'number', to_jsonb(1000), 10, 10000, 'scholarships', 1014, 'Job sizes',
  'security.scholarship_round_state_refresh_v1 (job scholarship-discover-refill)', 'CF-247 scholarship recovery F9'),
 ('pipeline', 'batch.scholarship_candidate_skip', 'Scholarship discovery: candidates checked against skip rules an hour',
  'Unread candidates checked against the address skip rules in one hourly refill (new candidates are checked when they are recorded).', 'number', to_jsonb(5000), 100, 100000, 'candidates', 1015, 'Job sizes',
  'security.scholarship_candidate_skip_v1 (job scholarship-discover-refill)', 'CF-247 scholarship recovery F1: skip rules no longer run on every pick'),
 ('pipeline', 'reread.scholarship_discovery_days', 'Map a provider''s scholarship sources again after',
  'A provider whose sources were mapped (found pages or found none) is mapped again after this many days, so new scholarship pages are found (mandate §5 Stage F).',
  'number', to_jsonb(30), 1, 365, 'days', 1016, 'Re-reads and retries', 'public.svc_scholarship_discover_record; security.scholarship_discovery_refill_v1', 'CF-247 scholarship recovery F3: no re-discovery cadence existed'),
 ('pipeline', 'retry.scholarship_discovery_deferred_hours', 'Try a refused scholarship site map again after',
  'A provider whose map was refused (budget, share, cap) or failed (rate limit, server error, time-out) waits this long, then is mapped again. It is never recorded as having no scholarships.',
  'number', to_jsonb(6), 1, 168, 'hours', 1017, 'Re-reads and retries', 'public.svc_scholarship_discover_record', 'CF-247 scholarship recovery F3'),
 ('pipeline', 'retry.scholarship_discovery_held_hours', 'Look again at a held provider in the discovery queue after',
  'A provider at the head of the discovery queue that is held (not eligible, past its credit cap, search off, unpublished, directory site) waits this long before the picker looks at it again.',
  'number', to_jsonb(6), 1, 168, 'hours', 1018, 'Re-reads and retries', 'public.svc_scholarship_discover_next', 'CF-247 scholarship recovery F1: held rows blocked the head of the queue'),
 ('pipeline', 'retry.scholarship_listing_partial_hours', 'Continue a partly read scholarship catalogue after',
  'A catalogue whose pagination did not end in a run (page limit or a failed page) is read again from where it stopped after this long.', 'number', to_jsonb(1), 1, 72, 'hours', 1019, 'Re-reads and retries',
  'public.svc_scholarship_listing_record_v2', 'CF-247 scholarship recovery F6'),
 ('pipeline', 'scholarship.listing_fanout_on', 'Scholarship listings: items become candidates',
  'On: every item of a read listing or catalogue page on the provider''s own site becomes a candidate page (once; a page already held is not added again). Off: listing items are only compared on Scholarships › Coverage, as before.',
  'boolean', 'true'::jsonb, null, null, null, 1020, 'Scholarships', 'public.svc_scholarship_listing_record_v2', 'CF-247 scholarship recovery F5 (mandate §5 Stage C)'),
 ('pipeline', 'scholarship.umbrella_sections_on', 'Scholarship listings: each award of an umbrella page is a candidate',
  'On: an award listed on an umbrella page without a page of its own (for example UNSW''s international awards for one intake, keyed by their codes) becomes a candidate read as that award''s section of the page, and an admitted one is its own record. Off: only linked items become candidates.',
  'boolean', 'true'::jsonb, null, null, null, 1021, 'Scholarships', 'public.svc_scholarship_listing_record_v2; security.scholarship_admit_from_provider_page_v1; coverage-sweep readSchPage', 'CF-247 scholarship recovery F5'),
 ('pipeline', 'scholarship.lifetime_cap_on', 'Scholarship scraper: keep the all-time credit cap',
  'Off (normal): the daily scholarship share, the per-university cap and the monthly plan in the Firecrawl budget are the scholarship limits. On: the old all-time cap (Scholarships › Coverage › Scraper credits for scholarships) also applies.',
  'boolean', 'false'::jsonb, null, null, null, 1022, 'Scholarships', 'public.svc_scholarship_fc_budget', 'CF-247 scholarship recovery F8: the all-time cap retired into the normal budget settings'),
 ('pipeline', 'scholarship.non_university_admission', 'PROPOSED: admit scholarships of non-university providers',
  'Proposed (Platform Admin approval needed; overnight direction 2 Nov 2026 23:24 §1). On: a provider of a governed type listed below, with a recorded provider type basis and its own website, may have scholarships admitted. Off: universities only, as today.',
  'boolean', 'false'::jsonb, null, null, null, 1023, 'Scholarships', 'security.scholarship_admission_provider_ok_v1; security.scholarship_discovery_refill_v1', 'CF-247 scholarship recovery P1 (proposed, off)'),
 ('pipeline', 'scholarship.non_university_types', 'PROPOSED: provider types that may have scholarships admitted',
  'Provider type codes (reference provider types) whose providers may have scholarships admitted when the proposal above is on.', 'list',
  '["university_college", "higher_education_institute", "tafe_polytechnic", "private_vet", "wananga"]'::jsonb, null, null, null, 1024, 'Scholarships', 'security.scholarship_admission_provider_ok_v1', 'CF-247 scholarship recovery P1 (proposed)'),
 ('pipeline', 'scholarship.legitimacy_checks_on', 'PROPOSED: evidence-based legitimacy instead of the course minimum',
  'Proposed (Platform Admin approval needed; overnight direction 23:24 §1). On: a provider is searched for scholarships when the legitimacy checks pass (active, published, international enrolment not refused, governed provider type, own website not a directory site, enough active courses below), instead of the Firecrawl course minimum. Off: the course minimum applies, as today.',
  'boolean', 'false'::jsonb, null, null, null, 1025, 'Scholarships', 'security.fc_sch_eligible_v1; security.scholarship_legitimacy_v1', 'CF-247 scholarship recovery P2 (proposed, off)'),
 ('pipeline', 'scholarship.legitimacy_min_courses', 'PROPOSED: legitimacy check, active courses at least',
  'With the legitimacy checks on, a provider needs at least this many active courses in the catalogue.', 'number', to_jsonb(1), 0, 100, 'courses', 1026, 'Scholarships',
  'security.scholarship_legitimacy_v1', 'CF-247 scholarship recovery P2 (proposed)'),
 ('pipeline', 'worker.outcome_failed_runs', 'Worker runs: failed runs in a row before an issue',
  'A worker mode whose last this-many calls all failed or did no work because of an error opens one Platform health issue (worker:<mode>); the next good call resolves it.', 'number', to_jsonb(3), 1, 50, 'runs', 1027, 'Health report',
  'security.worker_outcome_check_v1 (job worker-outcome-check)', 'CF-247 scholarship recovery F2; overnight direction §3: a successful invocation with an underlying error is not success'),
 ('pipeline', 'worker.outcome_window_hours', 'Worker runs: calls looked at',
  'Worker calls younger than this are classified and checked.', 'number', to_jsonb(6), 1, 72, 'hours', 1028, 'Health report',
  'security.worker_outcome_check_v1; security.job_outcomes_v1', 'CF-247 scholarship recovery F2')
on conflict (toolset_key, key) do nothing;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('firecrawl', 'scholarship_tier_courses', 'Scholarship discovery order: Australian providers with at least',
  'Order of the scholarship discovery queue: the top-50 cohort, then Australian providers with at least this many CRICOS courses, then overseas providers, then the rest. Order only: it never stops a provider being searched.',
  'number', to_jsonb(30), 0, 500, 'courses', 1029, 'Daily budget', 'security.fc_provider_tier_v1', 'CF-247 scholarship recovery F10: the literal 30 in the tier (baseline §1.4)')
on conflict (toolset_key, key) do nothing;

-- 2. schema: new columns and tables (additive) -----------------------------------------------------------------------------------------
alter table pipeline.scholarship_discovery_providers add column if not exists tier smallint;
alter table pipeline.scholarship_discovery_providers add column if not exists next_discover_at timestamptz;
alter table pipeline.scholarship_discovery_providers add column if not exists sources_mapped jsonb not null default '[]'::jsonb;
create index if not exists scholarship_discovery_pick_idx on pipeline.scholarship_discovery_providers ((coalesce(tier, 9)), priority, provider_id)
  where status in ('pending', 'deferred', 'mapped', 'empty');
comment on column pipeline.scholarship_discovery_providers.tier is 'CF-247 scholarship recovery F1: processing tier (0 top-50 cohort, 1 AU with many CRICOS courses, 2 overseas, 3 other AU); stored by the hourly refill so the picker orders by a column';
comment on column pipeline.scholarship_discovery_providers.next_discover_at is 'CF-247 scholarship recovery F3: when the provider is due again (deferred: after the retry time; mapped or empty: after the re-discovery cadence)';

alter table pipeline.scholarship_listing_pages add column if not exists page_state text check (page_state in ('single', 'complete', 'partial', 'failed'));
alter table pipeline.scholarship_listing_pages add column if not exists pages_read int;
alter table pipeline.scholarship_listing_pages add column if not exists total_stated int;
alter table pipeline.scholarship_listing_pages add column if not exists next_url text;
alter table pipeline.scholarship_listing_pages add column if not exists paging jsonb;
alter table pipeline.scholarship_listing_pages add column if not exists completed_at timestamptz;
comment on column pipeline.scholarship_listing_pages.page_state is 'CF-247 scholarship recovery F6: complete only when the pagination ended by itself (no next page, stated total reached, empty page); partial carries next_url';

alter table pipeline.mode_outcome_ledger add column if not exists outcome text check (outcome in ('succeeded', 'idle', 'zero_work_error', 'failed'));
comment on column pipeline.mode_outcome_ledger.outcome is 'CF-247 scholarship recovery F2: succeeded (work done), idle (nothing to do, no error), zero_work_error (no work done and an error or refusal in the answer), failed (HTTP error, ok:false or an error)';

create table if not exists pipeline.scholarship_listing_members (
  listing_id bigint not null, provider_id uuid not null, item_key text not null, name text, url text, code text,
  kind text not null check (kind in ('link', 'award_section')), candidate_id bigint, held_scholarship_id uuid,
  first_seen timestamptz not null default now(), last_seen timestamptz not null default now(), present boolean not null default true,
  primary key (listing_id, item_key));
comment on table pipeline.scholarship_listing_members is 'CF-247 scholarship recovery F5 (mandate §5 Stage C): one row per item of a provider''s scholarship listing or catalogue source (a linked scholarship page, or an award of an umbrella page keyed by its code), with the candidate it became or the record already holding it, and whether the last complete read still listed it. The independent anchor for listing-versus-record reconciliation.';
create index if not exists scholarship_listing_members_provider_idx on pipeline.scholarship_listing_members (provider_id);
alter table pipeline.scholarship_listing_members enable row level security;

create table if not exists pipeline.scholarship_source_moves (
  id bigserial primary key, kind text not null check (kind in ('candidate', 'scholarship')), ref text not null, provider_id uuid,
  old_url text not null, final_url text not null, outcome text not null check (outcome in ('moved', 'redirected_away')),
  first_seen timestamptz not null default now(), last_seen timestamptz not null default now(), seen int not null default 1,
  unique (kind, ref, final_url));
comment on table pipeline.scholarship_source_moves is 'CF-247 scholarship recovery F7: a scholarship or candidate page whose address now opens somewhere else: moved (another detail page) or redirected_away (the catalogue home, a listing or a search page). Recorded once per final address; for Scholarships › Coverage and Layer 4. Nothing is withdrawn by it.';
alter table pipeline.scholarship_source_moves enable row level security;

create table if not exists pipeline.scholarship_round_states (
  scholarship_id uuid primary key, state text not null check (state in ('open', 'opening_soon', 'closed_round', 'ended', 'no_dates')),
  basis text not null, open_date date, close_date date, evidence jsonb not null default '{}'::jsonb, decided_at timestamptz not null default now());
comment on table pipeline.scholarship_round_states is 'CF-247 scholarship recovery F9 (mandate §7: an expired scholarship is told from a temporarily closed round): the round state of each active scholarship from its dates and its page. closed_round: the close date passed, the page still offers it (a historical closed record, shown as closed, never as open); ended: the page is gone, redirects away, no longer lists the award or says it is no longer offered. Report state only: publication is unchanged.';
alter table pipeline.scholarship_round_states enable row level security;

-- 3. new functions ---------------------------------------------------------------------------------------------------------------------
create or replace function security.scholarship_flag_v1(p_key text, p_default boolean) returns boolean language sql stable security definer set search_path to '' as
$function$
  select coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = p_key), p_default)
$function$;

-- P2 (proposed): evidence-based legitimacy for scholarship search
create or replace function security.scholarship_legitimacy_v1(p_provider_id uuid) returns boolean language sql stable security definer set search_path to '' as
$function$
  select exists (select 1 from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id
                  where p.id = p_provider_id and p.lifecycle_status = 'active' and p.publication_status = 'published'
                    and p.enrols_international is not false and t.status = 'active' and t.code <> 'school'
                    and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)
                    and (select count(*) from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
                        >= security.pipeline_num_v1('scholarship.legitimacy_min_courses', 1))
$function$;

-- P1 (proposed): universities as today; with the proposal on, governed non-university providers with a verified source identity
create or replace function security.scholarship_admission_provider_ok_v1(p_provider_id uuid) returns boolean language sql stable security definer set search_path to '' as
$function$
  select security.scholarship_university(p_provider_id)
      or (security.scholarship_flag_v1('scholarship.non_university_admission', false)
          and exists (select 1 from catalogue.providers p join ref.provider_types t on t.id = p.provider_type_id join ref.countries k on k.id = p.country_id
                       where p.id = p_provider_id and p.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
                         and t.status = 'active' and p.provider_type_basis is not null
                         and t.code in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'scholarship.non_university_types'), '[]'::jsonb)))
                         and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)))
$function$;

create or replace function security.scholarship_discovery_tier_refresh_v1(p_limit int) returns int language plpgsql security definer set search_path to '' as
$function$
declare v int;
begin
  update pipeline.scholarship_discovery_providers d set tier = security.fc_provider_tier_v1(d.provider_id)
   where d.provider_id in (select x.provider_id from pipeline.scholarship_discovery_providers x
                            where x.status in ('pending', 'deferred', 'mapped', 'empty') order by (x.tier is not null), x.updated_at limit greatest(p_limit, 0));
  get diagnostics v = row_count;
  return v;
end $function$;

-- the address skip rules, on new or unread candidates (was: an update over every candidate on each pick)
create or replace function security.scholarship_candidate_skip_v1(p_provider_id uuid, p_limit int) returns int language plpgsql security definer set search_path to '' as
$function$
declare v int;
begin
  update pipeline.scholarship_page_candidates c set admit_status = 'skipped', admit_reasons = array['skipped: ' || r.label], read_status = coalesce(c.read_status, 'skipped'), read_at = now(), leased_until = null
    from pipeline.scholarship_skip_rules r
   where c.id in (select x.id from pipeline.scholarship_page_candidates x
                   where x.admit_status is null and x.matched_scholarship_id is null and x.source <> 'register' and x.read_status is null
                     and (p_provider_id is null or x.provider_id = p_provider_id) order by x.id desc limit greatest(p_limit, 0))
     and r.active and c.url ~* r.pattern and c.url !~* r.unless_pattern;
  get diagnostics v = row_count;
  return v;
end $function$;

-- F9: round state of each active scholarship (report only)
create or replace function security.scholarship_round_state_refresh_v1(p_limit int) returns int language plpgsql security definer set search_path to '' as
$function$
declare v int;
begin
  insert into pipeline.scholarship_round_states as rs (scholarship_id, state, basis, open_date, close_date, evidence, decided_at)
  select s.id,
         case when pg.ended is not null then 'ended'
              when s.application_close_date is not null and s.application_close_date < current_date then 'closed_round'
              when s.application_open_date is not null and s.application_open_date > current_date then 'opening_soon'
              when s.application_close_date is not null then 'open' else 'no_dates' end,
         coalesce(pg.ended, case when s.application_close_date < current_date then 'close_date_passed'
                                 when s.application_open_date > current_date then 'opens_later'
                                 when s.application_close_date is not null then 'close_date_ahead' else 'no_dates_on_record' end),
         s.application_open_date, s.application_close_date,
         jsonb_build_object('page_status', pg.read_status, 'page_read_at', pg.read_at, 'publication', s.publication_status), now()
    from scholarship.scholarships s
    left join lateral (select sp.read_status, sp.read_at,
                              case when sp.read_status in ('gone', 'redirected_away', 'section_missing') then 'page_' || sp.read_status
                                   when sp.read_status = 'read' and (sp.facts->'admission'->>'offered') = 'false' then 'page_not_offered' end ended
                         from pipeline.scholarship_pages sp where sp.scholarship_id = s.id limit 1) pg on true
   where s.id in (select x.id from scholarship.scholarships x left join pipeline.scholarship_round_states r on r.scholarship_id = x.id
                   where x.lifecycle_status = 'active' order by r.decided_at nulls first, x.id limit greatest(p_limit, 0))
  on conflict (scholarship_id) do update set state = excluded.state, basis = excluded.basis, open_date = excluded.open_date, close_date = excluded.close_date,
     evidence = excluded.evidence, decided_at = now();
  get diagnostics v = row_count;
  return v;
end $function$;

-- F2: what a worker call achieved
create or replace function security.worker_call_outcome_v1(p_status int, p_body jsonb, p_items int, p_ok int, p_failed int) returns text language sql immutable set search_path to '' as
$function$
  -- items that waited or were refused are not work done: a run whose every item waited for the scraper did nothing
  with w as (select coalesce(sum(case when e.key in ('waiting_scraper', 'deferred', 'credits_refused', 'scrape_failed', 'record_failed', 'blocked', 'fetch_failed') and jsonb_typeof(e.value) = 'number'
                                      then (e.value #>> '{}')::numeric end), 0) n
               from jsonb_each(coalesce(case when jsonb_typeof(p_body->'tally') = 'object' then p_body->'tally' end, '{}'::jsonb)
                               || coalesce(case when jsonb_typeof(p_body->'candidates'->'tally') = 'object' then p_body->'candidates'->'tally' end, '{}'::jsonb)) e)
  select case when coalesce(p_status, 200) >= 400 or coalesce(p_body->>'ok', 'true') = 'false' or p_body ? 'error' then 'failed'
              when coalesce(p_ok, 0) - w.n <= 0 and (coalesce(p_failed, 0) > 0 or w.n > 0
                   or coalesce(p_body::text, '') ~* '"(errors?|last_error)"\s*:\s*"|map:(budget|scholarship_share|credits_refused|credits_reserve|target_list_refused|no_firecrawl_key|timeout|[45][0-9][0-9])|credits_refused|statement timeout|section_missing') then 'zero_work_error'
              when coalesce(p_ok, 0) = 0 and coalesce(p_items, 0) = 0 then 'idle'
              when coalesce(p_ok, 0) - w.n <= 0 then 'zero_work_error'
              else 'succeeded' end
    from w
$function$;

-- F2: outcomes per worker mode with the scheduled jobs that call it (Curator screens, Progress, the integration queue)
create or replace function security.job_outcomes_v1(p_hours int) returns table(mode text, jobs text[], calls int, succeeded int, idle int, zero_work_error int, failed int, last_outcome text, last_at timestamptz, last_good_at timestamptz)
language sql stable security definer set search_path to '' as
$function$
  select l.mode,
         (select array_agg(j.jobname order by j.jobname) from cron.job j where j.command ~ ('''mode'',\s*''' || l.mode || '''') or j.command ~ ('"mode"\s*:\s*"' || l.mode || '"')),
         count(*)::int, count(*) filter (where l.outcome = 'succeeded')::int, count(*) filter (where l.outcome = 'idle')::int,
         count(*) filter (where l.outcome = 'zero_work_error')::int, count(*) filter (where l.outcome = 'failed')::int,
         (array_agg(l.outcome order by l.run_at desc, l.id desc))[1], max(l.run_at), max(l.run_at) filter (where l.outcome in ('succeeded', 'idle'))
    from pipeline.mode_outcome_ledger l
   where l.run_at > now() - make_interval(hours => greatest(p_hours, 1))
   group by l.mode
$function$;

create or replace function security.worker_outcome_check_v1() returns jsonb language plpgsql security definer set search_path to '' as
$function$
declare v_n int := security.pipeline_num_v1('worker.outcome_failed_runs', 3)::int; v_h int := security.pipeline_num_v1('worker.outcome_window_hours', 6)::int;
        r record; v_open int := 0; v_resolved int := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('worker-outcome-check')) then return jsonb_build_object('skipped', 'running'); end if;  -- fixed: lock key
  -- calls recorded before this change have no outcome yet: classified once, from what was recorded
  update pipeline.mode_outcome_ledger l set outcome = security.worker_call_outcome_v1(l.status, coalesce(l.detail, '{}'::jsonb) || jsonb_build_object('tally', l.landed), l.items, l.ok, l.failed)
   where l.outcome is null and l.run_at > now() - make_interval(hours => v_h);
  for r in select o.mode, o.jobs, (select array_agg(x.outcome order by x.run_at desc, x.id desc) from (select y.id, y.outcome, y.run_at from pipeline.mode_outcome_ledger y where y.mode = o.mode order by y.run_at desc, y.id desc limit v_n) x) last_n
             from security.job_outcomes_v1(v_h) o loop
    if cardinality(r.last_n) >= v_n and r.last_n <@ array['failed', 'zero_work_error'] then
      insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
      values ('worker:' || r.mode, 'critical', 'pipeline', left('Worker ' || r.mode || ': the last ' || v_n || ' runs did no work because of an error', 300),
              jsonb_build_object('mode', r.mode, 'jobs', to_jsonb(r.jobs), 'last_outcomes', to_jsonb(r.last_n),
                                 'last_answer', (select left(coalesce(y.detail::text, ''), 600) from pipeline.mode_outcome_ledger y where y.mode = r.mode order by y.run_at desc, y.id desc limit 1),
                                 'next_step', 'Read the last answers of this worker mode; the scheduler shows these runs as succeeded because it only posts the request'))
      on conflict (check_key) where resolved_at is null do update set title = excluded.title, detail = excluded.detail, last_seen = now(), occurrences = i.occurrences + 1;
      v_open := v_open + 1;
    elsif r.last_n[1] in ('succeeded', 'idle') then
      update pipeline.platform_issues set resolved_at = now() where check_key = 'worker:' || r.mode and resolved_at is null;
      if found then v_resolved := v_resolved + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('open', v_open, 'resolved', v_resolved);
end $function$;

-- F5, F6: a read listing or catalogue source; its items become candidates once, with membership kept
create or replace function public.svc_scholarship_listing_record_v2(p_id bigint, p_status text, p_http_status int, p_items jsonb, p_error text, p_paging jsonb) returns jsonb
language plpgsql security definer set search_path to '' as
$function$
declare l record; v_items jsonb := case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end; v_hash text; v_state text; v_keys text[] := '{}';
        e jsonb; v_url text; v_norm text; v_key text; v_code text; v_kind text; v_cid bigint; v_held uuid; v_new int := 0; v_members int := 0;
        v_fan boolean := security.scholarship_flag_v1('scholarship.listing_fanout_on', true); v_sec boolean := security.scholarship_flag_v1('scholarship.umbrella_sections_on', true);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into l from pipeline.scholarship_listing_pages where id = p_id;
  if l.id is null then return jsonb_build_object('ok', false, 'error', 'no listing source'); end if;
  v_state := case when p_status <> 'read' then 'failed' when coalesce(p_paging->>'state', '') in ('complete', 'partial') then p_paging->>'state' else 'single' end;
  select md5(coalesce(string_agg(lower(btrim(x->>'name')), '|' order by lower(btrim(x->>'name'))), '')) into v_hash from jsonb_array_elements(v_items) x;
  update pipeline.scholarship_listing_pages
     set status = case when p_status = 'read' then 'read' else 'failed' end, http_status = p_http_status, read_at = now(), error = left(p_error, 300),
         items = case when p_status = 'read' then v_items else items end, item_hash = case when p_status = 'read' then v_hash else item_hash end,
         page_state = v_state, pages_read = nullif(p_paging->>'pages_read', '')::int, total_stated = nullif(p_paging->>'total_stated', '')::int,
         next_url = case when v_state = 'partial' then nullif(p_paging->>'next_url', '') end, paging = p_paging,
         completed_at = case when v_state = 'complete' then now() else completed_at end,
         next_read_at = case when v_state = 'partial' then now() + make_interval(hours => security.pipeline_num_v1('retry.scholarship_listing_partial_hours', 1)::int)
                             when p_status = 'read' then now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_listing_days', 7)::int)
                             else now() + make_interval(days => security.pipeline_num_v1('retry.scholarship_listing_failed_days', 1)::int) end
   where id = p_id;
  if p_status = 'read' then
    for e in select * from jsonb_array_elements(v_items) loop
      v_url := nullif(btrim(coalesce(e->>'url', '')), ''); v_code := upper(coalesce(e->>'code', '')); v_cid := null; v_held := null;
      if v_url is not null and v_url ~* '^https?://' then
        if not coalesce(security.url_on_provider_sites(v_url, l.provider_id) or security.url_on_provider_site(v_url, l.url), false) then continue; end if;
        v_norm := security.scholarship_url_norm(v_url); v_key := 'url:' || v_norm; v_kind := 'link';
        if v_norm = l.url_norm then continue; end if;
      elsif v_code ~ '^[A-Z]{4}[0-9]{4}$' then
        v_url := l.url || '#award-' || lower(v_code); v_norm := l.url_norm || '#award-' || lower(v_code); v_key := 'award:' || v_code; v_kind := 'award_section';
      else continue;
      end if;
      -- already held: a record whose page or identifier is this address, or (a section) a record of the provider with the same name
      select s.id into v_held from scholarship.scholarships s
       where s.provider_id = l.provider_id and s.lifecycle_status = 'active'
         and (security.scholarship_url_norm(s.source_url) = v_norm
              or exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id = s.id and security.scholarship_url_norm(sp.url) = v_norm)
              or (v_kind = 'award_section' and scholarship.normalise_title(s.name) in (scholarship.normalise_title(coalesce(e->>'name', '')), scholarship.normalise_title(coalesce(e->>'name', '') || ' (' || v_code || ')'))))
       limit 1;
      select c.id into v_cid from pipeline.scholarship_page_candidates c where c.provider_id = l.provider_id and c.url_norm = v_norm;
      if v_cid is null and v_held is null and v_fan and (v_kind = 'link' or v_sec) then
        insert into pipeline.scholarship_page_candidates(provider_id, url, url_norm, title, source)
        values (l.provider_id, v_url, v_norm, nullif(left(coalesce(e->>'name', ''), 300), ''), 'map')
        on conflict (provider_id, url_norm) do nothing returning id into v_cid;
        if v_cid is not null then v_new := v_new + 1; end if;
      end if;
      insert into pipeline.scholarship_listing_members as m (listing_id, provider_id, item_key, name, url, code, kind, candidate_id, held_scholarship_id)
      values (p_id, l.provider_id, v_key, left(e->>'name', 300), v_url, nullif(v_code, ''), v_kind, v_cid, v_held)
      on conflict (listing_id, item_key) do update set name = excluded.name, last_seen = now(), present = true,
         candidate_id = coalesce(excluded.candidate_id, m.candidate_id), held_scholarship_id = coalesce(excluded.held_scholarship_id, m.held_scholarship_id);
      v_members := v_members + 1; v_keys := v_keys || v_key;
    end loop;
    -- only a read that saw the whole catalogue says an item is no longer listed
    if v_state in ('complete', 'single') then
      update pipeline.scholarship_listing_members set present = false where listing_id = p_id and present and item_key <> all (v_keys);
    end if;
    if v_new > 0 then perform security.scholarship_candidate_skip_v1(l.provider_id, v_new); end if;
  end if;
  return jsonb_build_object('ok', true, 'items', jsonb_array_length(v_items), 'members', v_members, 'new_candidates', v_new, 'page_state', v_state);
end $function$;

revoke all on function public.svc_scholarship_listing_record_v2(bigint, text, int, jsonb, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_scholarship_listing_record_v2(bigint, text, int, jsonb, text, jsonb) to service_role;
revoke all on function security.job_outcomes_v1(int) from public, anon, authenticated;
revoke all on function security.worker_outcome_check_v1() from public, anon, authenticated;
revoke all on function security.scholarship_round_state_refresh_v1(int) from public, anon, authenticated;
revoke all on function security.scholarship_candidate_skip_v1(uuid, int) from public, anon, authenticated;
revoke all on function security.scholarship_discovery_tier_refresh_v1(int) from public, anon, authenticated;

-- 4. whole replacements (md5-guarded) ------------------------------------------------------------------------------------------------
select pg_temp.replace_once('public.svc_scholarship_discover_next(integer)', '139bc97b784ac031db99d13b656f7c84', '270852dc23732cf206d0d483f7e63354', $def$
CREATE OR REPLACE FUNCTION public.svc_scholarship_discover_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_win uuid[]; v_ok uuid[] := '{}'; v_held uuid[] := '{}'; r record;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- CF-247 scholarship recovery F1/F3: a small window at the head of the queue, ordered by the stored tier (no per-row course count);
  -- pending and deferred rows when due, mapped and empty rows when their re-discovery date has come
  select array_agg(x.provider_id order by x.t, x.priority, x.due, x.provider_id) into v_win from (
    select d.provider_id, coalesce(d.tier, 9) t, d.priority, coalesce(d.next_discover_at, '-infinity') due from pipeline.scholarship_discovery_providers d
     where d.status in ('pending', 'deferred', 'mapped', 'empty') and coalesce(d.leased_until,'-infinity')<now() and d.attempts<3
       and (case when d.status in ('pending', 'deferred') then coalesce(d.next_discover_at, '-infinity') else d.next_discover_at end) <= now()
     order by coalesce(d.tier, 9), d.priority, coalesce(d.next_discover_at, '-infinity'), d.provider_id
     limit greatest(1, security.pipeline_num_v1('scholarship.discover_pick_window', 60)::int)) x;
  -- the holds, only on the window (v2.15.237 unpublished, v2.15.265 eligibility and cap, directory site, v2.15.271 search off)
  for r in select d.provider_id, d.website from pipeline.scholarship_discovery_providers d where d.provider_id = any (coalesce(v_win, '{}')) loop
    if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id) or security.fc_sch_held_v1(r.provider_id, true)
       or security.third_party_host_v1(coalesce(r.website, '')) or security.provider_sch_search_off_v1(r.provider_id) then v_held := v_held || r.provider_id;
    else v_ok := v_ok || r.provider_id; end if;
  end loop;
  if cardinality(v_held) > 0 then
    update pipeline.scholarship_discovery_providers set next_discover_at = now() + make_interval(hours => security.pipeline_num_v1('retry.scholarship_discovery_held_hours', 6)::int)
     where provider_id = any (v_held);
  end if;
  with pick as (
    select d.provider_id from pipeline.scholarship_discovery_providers d
     where d.provider_id = any (v_ok) and coalesce(d.leased_until,'-infinity')<now()
     order by coalesce(d.tier, 9), d.priority, coalesce(d.next_discover_at, '-infinity'), d.provider_id
     limit greatest(1,least(coalesce(p_limit,3), security.pipeline_num_v1('scholarship.discover_providers_max', 6)::int)) for update skip locked),
  upd as (update pipeline.scholarship_discovery_providers d set leased_until=now()+interval '5 minutes', attempts=d.attempts+1, updated_at=now()  -- fixed: claim lease
            from pick where d.provider_id=pick.provider_id returning d.provider_id, d.website, d.reason, d.allowed_hosts)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id',u.provider_id,'website',u.website,'reason',u.reason,'hosts',to_jsonb(u.allowed_hosts),
           'names',security.provider_name_list(u.provider_id),'held',security.scholarship_held_without_page(u.provider_id),
           -- F4: every source recorded for the provider (manual first), after its website
           'sources',(select coalesce(jsonb_agg(z.url order by z.o, z.id), '[]'::jsonb) from (select l.url, l.id, case l.source when 'manual' then 0 else 1 end o
                        from pipeline.scholarship_listing_pages l where l.provider_id = u.provider_id and l.active and l.source in ('manual', 'auto')
                         and not security.third_party_host_v1(l.url) order by 3, l.id limit greatest(0, security.pipeline_num_v1('scholarship.sources_per_provider_max', 5)::int - 1)) z))),'[]'::jsonb) into v from upd u;
  return v;
end $function$
$def$);

select pg_temp.replace_once('public.svc_scholarship_discover_record(uuid,text,text,text,integer,jsonb,jsonb,text)', 'ed20bfe8862da0e5e26ce2f7189469e8', '9ead26f30f8bb68d55673350d61e00d6', $def$
CREATE OR REPLACE FUNCTION public.svc_scholarship_discover_record(p_provider_id uuid, p_status text, p_site_origin text, p_method text, p_url_count integer, p_candidates jsonb, p_matches jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v_kept int; v_matched int:=0; m jsonb; r jsonb; v_cid bigint; v_new int; v_status text;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.scholarship_page_candidates(provider_id,url,url_norm,title,source)
  select p_provider_id, c->>'url', security.scholarship_url_norm(c->>'url'), nullif(left(c->>'title',300),''), coalesce(c->>'source','sitemap')
    from jsonb_array_elements(coalesce(p_candidates,'[]')) c
   where coalesce(c->>'url','') ~* '^https?://' and (security.url_on_provider_sites(c->>'url', p_provider_id) or security.url_on_provider_site(c->>'url', p_site_origin))
  on conflict (provider_id,url_norm) do update set title=coalesce(pipeline.scholarship_page_candidates.title, excluded.title);
  get diagnostics v_new = row_count;
  -- CF-247 scholarship recovery F1: the address skip rules on the candidates just recorded (was: on every pick)
  if v_new > 0 then perform security.scholarship_candidate_skip_v1(p_provider_id, v_new); end if;
  select count(*) into v_kept from pipeline.scholarship_page_candidates where provider_id=p_provider_id;
  -- F3: a refused or failed map is deferred and tried again (never a final "empty", and its last count is kept); a map that ran is due again
  -- after the re-discovery cadence
  v_status := case when p_status in ('mapped', 'empty', 'deferred', 'failed') then p_status else 'failed' end;
  update pipeline.scholarship_discovery_providers set status=v_status, site_origin=coalesce(p_site_origin,site_origin), method=p_method,
         url_count=case when v_status='deferred' then url_count else p_url_count end, kept_count=v_kept,
         discovered_at=case when v_status='deferred' then discovered_at else now() end, leased_until=null, last_error=p_error, updated_at=now(),
         attempts=case when v_status in ('mapped', 'empty', 'deferred') then 0 else attempts end,
         next_discover_at=case when v_status='deferred' then now()+make_interval(hours => security.pipeline_num_v1('retry.scholarship_discovery_deferred_hours', 6)::int)
                               when v_status in ('mapped', 'empty') then now()+make_interval(days => security.pipeline_num_v1('reread.scholarship_discovery_days', 30)::int)
                               else next_discover_at end,
         sources_mapped=coalesce(to_jsonb(string_to_array(p_method, '+')), '[]'::jsonb)
   where provider_id=p_provider_id;
  for m in select * from jsonb_array_elements(coalesce(p_matches,'[]')) loop
    select id into v_cid from pipeline.scholarship_page_candidates where provider_id=p_provider_id and url_norm=security.scholarship_url_norm(m->>'url');
    if v_cid is null then continue; end if;
    if (select provider_id from scholarship.scholarships where id=(m->>'scholarship_id')::uuid) is distinct from p_provider_id then continue; end if;
    r:=security.scholarship_page_match_v1((m->>'scholarship_id')::uuid, m->>'url', m->>'basis', v_cid);
    if (r->>'matched')::boolean then v_matched:=v_matched+1; end if;
  end loop;
  update pipeline.scholarship_discovery_providers set matched_count=coalesce(matched_count,0)+v_matched where provider_id=p_provider_id;
  return jsonb_build_object('kept',v_kept,'matched',v_matched,'status',v_status,'new',v_new);
end $function$
$def$);

select pg_temp.replace_once('public.svc_scholarship_candidate_next(integer)', '05a40ab97bec72d3b3ff2aa2c7dddf41', 'ff53456e678bf7c5470df6a0fbf6f965', $def$
CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_ok uuid[] := '{}'; v_p record;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- CF-247 scholarship recovery F1: the skip rules run when candidates are recorded and hourly (security.scholarship_candidate_skip_v1);
  -- the holds are checked once per provider in a window of due candidates, not per candidate row
  create temp table if not exists sch_cand_win(id bigint, provider_id uuid, url text, requested boolean, tier int, priority int, found_at timestamptz) on commit drop;
  truncate sch_cand_win;
  insert into sch_cand_win
  select c.id, c.provider_id, c.url, c.requested_at is not null, coalesce(d.tier, 9), d.priority, c.found_at
    from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
   where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3
   order by (c.requested_at is not null) desc, coalesce(d.tier, 9), (d.priority not in (0,3)), c.found_at, c.id
   limit greatest(1, security.pipeline_num_v1('scholarship.candidate_pick_window', 600)::int);
  for v_p in select distinct w.provider_id from sch_cand_win w loop
    -- v2.15.237 unpublished; v2.15.265 eligibility and cap; v2.15.271 search off
    if not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = v_p.provider_id) and not security.fc_sch_held_v1(v_p.provider_id, true)
       and not security.provider_sch_search_off_v1(v_p.provider_id) then v_ok := v_ok || v_p.provider_id; end if;
  end loop;
  with ranked as (
    select w.id, w.requested, w.tier, w.priority, row_number() over (partition by w.provider_id order by (w.url ~* 'international') desc, w.found_at, w.id) rn
      from sch_cand_win w where w.provider_id = any (v_ok) and not security.third_party_host_v1(w.url)),
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by r.requested desc, r.tier, r.rn, (r.priority not in (0,3)), c.id -- 11 Oct 2026: on-demand candidates first
     limit greatest(1,least(coalesce(p_limit,30), security.pipeline_num_v1('scholarship.candidates_max', 60)::int)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id  -- fixed: claim lease
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$
$def$);

select pg_temp.replace_once('public.svc_scholarship_listing_next(integer)', 'f8184295da30ebd598115ce2ea45f616', '0ce6a0268db2c2b31d6946cd1fe427e1', $def$
CREATE OR REPLACE FUNCTION public.svc_scholarship_listing_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select l.id from pipeline.scholarship_listing_pages l
     where l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = l.provider_id)
       and not security.fc_sch_held_v1(l.provider_id, true) and not security.third_party_host_v1(l.url)  -- v2.15.265
     order by l.next_read_at nulls first, l.id limit greatest(1, least(coalesce(p_limit, 6), security.pipeline_num_v1('scholarship.listing_max', 20)::int)) for update skip locked),
  upd as (update pipeline.scholarship_listing_pages l set next_read_at = now() + interval '15 minutes' from pick where l.id = pick.id returning l.id, l.provider_id, l.url, l.next_url, l.page_state)  -- fixed: claim lease
  -- CF-247 scholarship recovery F6: a partly read catalogue continues from the address it stopped at
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url, 'next_url', case when u.page_state = 'partial' then u.next_url end,
           'hosts', (select to_jsonb(coalesce(d.allowed_hosts, '{}') || array[regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '')])
                       from pipeline.scholarship_discovery_providers d where d.provider_id = u.provider_id))), '[]'::jsonb) into v from upd u;
  return v;
end $function$
$def$);

select pg_temp.replace_once('public.svc_scholarship_fc_budget()', '5a58bfd5a6f3001fdb9e1387ed046650', '2b64ac9f5f0a0682cdb809014b51c905', $def$
CREATE OR REPLACE FUNCTION public.svc_scholarship_fc_budget()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_used numeric := (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose in ('sch_map', 'sch_search', 'sch_scrape'));
        v_life boolean := security.scholarship_flag_v1('scholarship.lifetime_cap_on', false);
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return jsonb_build_object(
    'used', v_used,
    -- CF-247 scholarship recovery F8: the all-time cap is retired into the normal settings. Off (default): the worker's ceiling is the daily
    -- scholarship share above what is used, and svc_fc_spend (daily budget, share, per-university cap, monthly plan) decides each call.
    'cap', case when v_life then (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_cap')
                else v_used + security.fc_setting_num_v1('daily_share_scholarships', 3500) end,
    'lifetime_cap', v_life,
    'reserve', (select s.value from pipeline.scholarship_layer_settings s where s.key = 'firecrawl_reserve'),
    -- 11 Oct 2026: read scholarship pages through the scraper first (1 = on, 0 = off)
    'scraper', coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key = 'read_via_scraper'), 1));
end $function$
$def$);

select pg_temp.replace_once('public.svc_worker_settings_v1()', '9f61ab21cbfc1d752c537998500fa936', '5ef1c297c311ea346d95d04b2d430c34', $def$
CREATE OR REPLACE FUNCTION public.svc_worker_settings_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb) from pipeline.platform_toolset_settings s
           where (s.toolset_key = 'firecrawl' and s.key in ('read_proxy', 'map_limit_course_site', 'map_limit_central', 'map_limit_central_search', 'map_limit_scholarships',
                                                          'search_results_website', 'search_results_register', 'search_results_cricos',
                                                          'search_results_scholarship_search', 'search_results_scholarship_discover'))
              or (s.toolset_key = 'pipeline' and (s.key like 'enrich.%' or s.key like 'reading.%'))  -- v2.15.275: Enrich fields worker values
              or (s.toolset_key = 'pipeline' and s.key like 'scholarship.%'));  -- CF-247 scholarship recovery F10: scholarship worker sizes and waits
end $function$
$def$);

select pg_temp.replace_once('security.scholarship_task_fire_v1(text[])', 'b4f57757292bf861e217e759e9f7aad2', '9940af62a514f24509812b054b1afa8a', $def$
CREATE OR REPLACE FUNCTION security.scholarship_task_fire_v1(p_steps text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_step text; v_mode text; v_body jsonb; v_sent int := 0;
begin
  foreach v_step in array coalesce(p_steps, '{}') loop
    v_mode := case when v_step in ('discover', 'candidates') then 'scholarship_discover' else 'scholarship_read' end;
    -- CF-247 scholarship recovery F10: the sizes are the Scholarships settings the scheduled jobs use
    v_body := case v_step
      when 'discover' then jsonb_build_object('mode', v_mode, 'phase', 'discover', 'limit', security.scholarship_setting('discover_limit', 6)::int)
      when 'candidates' then jsonb_build_object('mode', v_mode, 'phase', 'candidates', 'read_limit', security.scholarship_setting('candidate_read_limit', 30)::int)
      else jsonb_build_object('mode', v_mode, 'limit', security.scholarship_setting('read_limit', 40)::int) end;
    if not exists (select 1 from pipeline.edge_request_log l where l.function_name = 'coverage-sweep' and l.mode = v_mode and l.created_at > now() - interval '45 seconds'  -- fixed: fire guard
                    and not exists (select 1 from net._http_response r where r.id = l.request_id)) then
      perform pipeline.svc_pilot_submit_nonce('coverage-sweep', v_body);
      v_sent := v_sent + 1;
    end if;
  end loop;
  return v_sent;
end $function$
$def$);

select pg_temp.replace_once('security.fc_provider_tier_v1(uuid)', 'f6977adcef5e7f0df41b34f6f47b9fc2', '3d0aa9dc690e23df4fd0c7248aaa7300', $def$
CREATE OR REPLACE FUNCTION security.fc_provider_tier_v1(p_provider_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 scholarship recovery F10: the course threshold of the order is the setting scholarship_tier_courses (was the literal 30)
  select case when exists (select 1 from pipeline.onboarding_pilot o where o.provider_id = p_provider_id and o.cohort = 'au-top-2026-10-12') then 0
              when security.coverage_country(p_provider_id) is distinct from 'AU' then 2
              when security.fc_courses_v1(p_provider_id) >= security.fc_setting_num_v1('scholarship_tier_courses', 30) then 1 else 3 end
$function$
$def$);

select pg_temp.replace_once('security.fc_sch_eligible_v1(uuid)', '06e6fb6f46698c3f59c5b4e754b3d6e2', '8064816107a9b44bb2aeccbfa4a2d867', $def$
CREATE OR REPLACE FUNCTION security.fc_sch_eligible_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- CF-247 scholarship recovery P2 (proposed, off until the Platform Admin switches scholarship.legitimacy_checks_on): evidence-based legitimacy
  -- instead of the course minimum
  if security.scholarship_flag_v1('scholarship.legitimacy_checks_on', false) then return security.scholarship_legitimacy_v1(p_provider_id); end if;
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  return security.coverage_country(p_provider_id) is distinct from 'AU' or security.fc_courses_v1(p_provider_id) >= security.fc_setting_num_v1('scholarship_min_courses', 30);
end $function$
$def$);

select pg_temp.replace_once('security.scholarship_discovery_refill_v1(integer)', 'ae7d6339945caa175c822754bfeebaff', '46a66f131b574375db6e9edbc2ad3f36', $def$
CREATE OR REPLACE FUNCTION security.scholarship_discovery_refill_v1(p_keep integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pending int; v_added int := 0; v_tier int; v_due int; v_skip int; v_round int;
begin
  perform security.provider_sch_search_auto_v1();  -- v2.15.271: directory-only providers switched Off
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status in ('pending', 'deferred');
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'
      from (select p.id provider_id, k.iso_alpha2 cc,
                   coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) website,
                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
               -- CF-247 scholarship recovery P1 (proposed, off): with non-university admission on, governed non-university providers overseas too
               and (k.iso_alpha2 = 'AU' or security.scholarship_admission_provider_ok_v1(p.id))
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website, k.iso_alpha2) q
     where q.website is not null
       -- v2.15.265: qualifying providers only, never a directory site; top-50, Australian 30+, overseas
       and security.fc_sch_eligible_v1(q.provider_id) and not security.third_party_host_v1(q.website)
       and not security.provider_sch_search_off_v1(q.provider_id)  -- v2.15.271
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
     order by security.fc_provider_tier_v1(q.provider_id), q.n desc, q.provider_id limit greatest(0, p_keep - v_pending)
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  -- CF-247 scholarship recovery F1: the stored processing tier, a batch an hour
  v_tier := security.scholarship_discovery_tier_refresh_v1(security.pipeline_num_v1('batch.scholarship_tier_refresh', 500)::int);
  -- F3: providers mapped before the cadence existed are due the cadence after their last map
  update pipeline.scholarship_discovery_providers set next_discover_at = coalesce(discovered_at, now()) + make_interval(days => security.pipeline_num_v1('reread.scholarship_discovery_days', 30)::int)
   where status in ('mapped', 'empty') and next_discover_at is null;
  get diagnostics v_due = row_count;
  -- F1: the address skip rules on unread candidates; F9: round states
  v_skip := security.scholarship_candidate_skip_v1(null, security.pipeline_num_v1('batch.scholarship_candidate_skip', 5000)::int);
  v_round := security.scholarship_round_state_refresh_v1(security.pipeline_num_v1('batch.scholarship_round_state', 1000)::int);
  return jsonb_build_object('pending_before', v_pending, 'added', v_added, 'tiers', v_tier, 'cadence_set', v_due, 'skipped', v_skip, 'round_states', v_round);
end $function$
$def$);

-- 5. edits (md5-guarded) -------------------------------------------------------------------------------------------------------------
-- admission: P1 provider rule (universities unless the proposal is on); F5 an award section's address is its identity
select pg_temp.edit_once('security.scholarship_admit_from_provider_page_v1(bigint)', 'ebed8647a65be18c127bf4a8cb2f1b0e', '5b3557c1ea4488f3e9b751ad9e7371e9', array[
  array[$e$elsif not security.scholarship_university(c.provider_id) then$e$,
        $e$elsif not security.scholarship_admission_provider_ok_v1(c.provider_id) /* CF-247 scholarship recovery P1 (proposed, off): universities, as before */ then$e$],
  array[$e$v_norm:=security.scholarship_url_norm(v_url);$e$,
        $e$v_norm:=security.scholarship_url_norm(v_url);
  -- CF-247 scholarship recovery F5: one award of an umbrella page ("<page>#award-<code>") is its own record, keyed by its section address
  if c.url_norm ~ '#award-[a-z]{4}[0-9]{4}$' then v_norm:=c.url_norm; end if;$e$]
]::text[][], array[1, 1]);

-- candidates: F7 redirected away is refused without an AI read; F5 an award no longer on its umbrella page is gone
select pg_temp.edit_once('public.svc_scholarship_candidate_record(bigint,text,integer,text,text,text,text,jsonb)', '2bfb43c34e48aca7194ec8bb196c1662', '44c06460d022b98dfa5404c28ccaa368', array[
  array[$e$next_read_at=case when p_read_status in ('read','robots_disallowed','gone') then$e$,
        $e$next_read_at=case when p_read_status in ('read','robots_disallowed','gone','redirected_away','section_missing') then$e$],
  array[$e$         admit_status=case when not v_ai and p_read_status='read'$e$,
        $e$         admit_status=case when p_read_status in ('redirected_away','section_missing') then 'rejected'  -- CF-247 scholarship recovery F7, F5
                           when not v_ai and p_read_status='read'$e$],
  array[$e$         admit_reasons=case when not v_ai and p_read_status='read'$e$,
        $e$         admit_reasons=case when p_read_status in ('redirected_away','section_missing') then array[p_read_status]
                            when not v_ai and p_read_status='read'$e$]
]::text[][], array[1, 1, 1]);

-- scholarship pages: F7 a page whose final address differs is recorded once per address
select pg_temp.edit_once('public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)', 'ece9139335e8e6832158353fa097d2e9', 'ec72dc9952cce9f63e427377ec0513a8', array[
  array[$e$  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried$e$,
        $e$  -- CF-247 scholarship recovery F7: a page that now opens elsewhere (moved, or redirected away to a home, listing or search page)
  if p_final_url is not null and v_url is not null and split_part(p_final_url, '#', 1) <> split_part(v_url, '#', 1)
     and security.scholarship_url_norm(p_final_url) <> security.scholarship_url_norm(v_url) then
    insert into pipeline.scholarship_source_moves as mv (kind, ref, provider_id, old_url, final_url, outcome)
    values ('scholarship', p_scholarship_id::text, v_pid, v_url, p_final_url, case when p_read_status = 'redirected_away' then 'redirected_away' else 'moved' end)
    on conflict (kind, ref, final_url) do update set last_seen = now(), seen = mv.seen + 1, outcome = excluded.outcome;
  end if;
  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried$e$]
]::text[][], array[1]);

-- worker ledger: F2 every call gets its outcome
select pg_temp.edit_once('public.svc_worker_report_v1(text,integer,integer,jsonb,text)', '11e82a3abcefc6ff7c16541a6d71f9cf', '6f3b816265f1a517b9d79140041669bb', array[
  array[$e$  returning id into v_id;
  return v_id;$e$,
        $e$  returning id into v_id;
  -- CF-247 scholarship recovery F2: what the call achieved (an HTTP 500 or no work with an error is never "succeeded")
  update pipeline.mode_outcome_ledger set outcome = security.worker_call_outcome_v1(coalesce(p_status, 200), p_body, v_items, v_ok, v_failed) where id = v_id;
  return v_id;$e$]
]::text[][], array[1]);

-- 6. the job (G1): catalogued, created paused ------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('worker-outcome-check', 'Platform upkeep', 96, 'Worker runs: failures behind a successful schedule',
  'Every 10 minutes when switched on: classifies each worker call (succeeded, idle, no work because of an error, failed) and opens one Platform health issue per worker mode whose last runs (Worker runs: failed runs in a row before an issue) all failed or did no work because of an error; the next good run resolves it. The scheduler shows these runs as succeeded because it only posts the request. Read-only over the pipeline: no AI, no Firecrawl.',
  5, false, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'worker-outcome-check') then
    perform cron.schedule('worker-outcome-check', '4-59/10 * * * *', 'select security.worker_outcome_check_v1()');
    perform cron.alter_job((select jobid from cron.job where jobname = 'worker-outcome-check'), active := false);
  end if;
end $j$;

-- 7. register (housekeeping) ----------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'worker-outcome-check', 'Platform', 'Platform upkeep', 'Worker run outcomes behind a successful schedule (paused until activated)', 'active', '{}', '20261103050000'),
 ('table', 'pipeline.scholarship_listing_members', 'Layer 2', 'Scholarships', 'Listing and catalogue membership of scholarship items', 'active', '{}', '20261103050000'),
 ('table', 'pipeline.scholarship_source_moves', 'Layer 2', 'Scholarships', 'Scholarship pages that moved or redirect away', 'active', '{}', '20261103050000'),
 ('table', 'pipeline.scholarship_round_states', 'Layer 2', 'Scholarships', 'Closed round versus ended scholarship (report)', 'active', '{}', '20261103050000'),
 ('function', 'public.svc_scholarship_listing_record_v2', 'Layer 2', 'Scholarships', 'Listing read with pagination state and fan-out to candidates', 'active', '{public.svc_scholarship_listing_record}', '20261103050000'),
 ('function', 'security.worker_call_outcome_v1', 'Platform', 'Platform upkeep', 'Outcome of one worker call', 'active', '{}', '20261103050000'),
 ('function', 'security.job_outcomes_v1', 'Platform', 'Platform upkeep', 'Worker outcomes per mode with the jobs that call it', 'active', '{}', '20261103050000'),
 ('function', 'security.worker_outcome_check_v1', 'Platform', 'Platform upkeep', 'Job worker-outcome-check', 'active', '{}', '20261103050000'),
 ('function', 'security.scholarship_discovery_tier_refresh_v1', 'Layer 2', 'Scholarships', 'Stored discovery tier', 'active', '{}', '20261103050000'),
 ('function', 'security.scholarship_candidate_skip_v1', 'Layer 2', 'Scholarships', 'Address skip rules on new and unread candidates', 'active', '{}', '20261103050000'),
 ('function', 'security.scholarship_round_state_refresh_v1', 'Layer 2', 'Scholarships', 'Round states of active scholarships', 'active', '{}', '20261103050000'),
 ('function', 'security.scholarship_admission_provider_ok_v1', 'Layer 2', 'Scholarships', 'Provider rule for scholarship admission (non-university proposal off)', 'active', '{}', '20261103050000'),
 ('function', 'security.scholarship_legitimacy_v1', 'Layer 2', 'Scholarships', 'Evidence-based legitimacy (proposal off)', 'active', '{}', '20261103050000'),
 ('function', 'security.scholarship_flag_v1', 'Layer 2', 'Scholarships', 'Boolean pipeline setting reader', 'active', '{}', '20261103050000')
on conflict do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = 'public.svc_scholarship_listing_record_v2',
       retire_after = (now() + make_interval(days => security.pipeline_num_v1('hygiene.retire_after_days', 14)::int))::date, updated_at = now()
 where kind = 'function' and name = 'public.svc_scholarship_listing_record' and status = 'active';

-- 8. post-check ------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'worker-outcome-check' and active) then raise exception 'scholarship recovery post-check: the job must be paused'; end if;
  if security.scholarship_flag_v1('scholarship.non_university_admission', true) or security.scholarship_flag_v1('scholarship.legitimacy_checks_on', true) then
    raise exception 'scholarship recovery post-check: the eligibility proposals must ship off'; end if;
  if security.scholarship_flag_v1('scholarship.lifetime_cap_on', true) is null then raise exception 'scholarship recovery post-check: lifetime cap setting missing'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where (toolset_key = 'pipeline' and (key like 'scholarship.%' or key in ('batch.scholarship_tier_refresh', 'batch.scholarship_round_state',
        'batch.scholarship_candidate_skip', 'reread.scholarship_discovery_days', 'retry.scholarship_discovery_deferred_hours', 'retry.scholarship_discovery_held_hours',
        'retry.scholarship_listing_partial_hours', 'worker.outcome_failed_runs', 'worker.outcome_window_hours'))
        or (toolset_key = 'firecrawl' and key = 'scholarship_tier_courses')) and label is not null and used_by is not null) < 29 then
    raise exception 'scholarship recovery post-check: settings incomplete (G2)'; end if;
  if exists (select 1 from pipeline.scholarship_listing_members) or exists (select 1 from pipeline.scholarship_round_states) then
    raise exception 'scholarship recovery post-check: applying the migration must not run anything'; end if;
end $$;
select 'CF-247 scholarship recovery: pickers, deferred maps, sources, listing fan-out and pagination, moves, round states, outcomes (job paused); proposals off' ok;
