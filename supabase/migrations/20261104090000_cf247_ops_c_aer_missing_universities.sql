-- CF-247 Autonomous AI Operations, workstream C: AER missing-university strategy (Platform Admin 3 Nov 2026 16:24 AEDT; admin
-- docs/platform/aer/2026-11-03-missing-universities-source-and-reader-strategy.md at 9fc8cbf6). Lands after 20261104040000 (workstream C coverage
-- ledger) and workstream A's contract (20261104010000).
--
-- 1. An accountable source inventory (pipeline.aer_source_inventory): for each of the eight universities with no entry-requirement source
--    (CDU, Deakin, UNE, Torrens, ACU, JCU, CQU, UniSQ), what free, read-only discovery on the official sites found on 3 Nov 2026 (WebSearch and
--    WebFetch; no Firecrawl, no paid search, no AI read): the exact verified URL, audience, study levels, page shape, the global qualifications
--    the page names, the identity boundary kept, and an outcome:
--      verified_attachable    an official page with a readable requirement table or list (direct read): attach as a source (paste file);
--      verified_general_only  an official page with only a general rule (Year 12 equivalent, bachelor equivalent): the reader can record an
--                             evidenced "no table" outcome; never a synthetic score (reader contract 6);
--      verified_rendered_only an official page whose requirements load in a selector (JavaScript): needs the rendered route (entry.render_hosts,
--                             existing Firecrawl rules), which is a spend decision, so not attached;
--      unverified_link        the official page names a document whose exact URL could not be verified: nothing is invented;
--      blocked_site           the official site refused the free read: the provider's courses are read from their stored course pages
--                             (security.aer_schedule_courses_v1) until a source is verified.
--    No URL is invented. Attachment is a separate paste file (docs/paste/PASTE-20261104-aer-missing-university-sources.sql), because an attached
--    source is read by the existing entry-matrix reader (AI within guard_entry_matrix, first read to Layer 4): the Integration Controller applies it.
-- 2. Report classifications (strategy §E; never new status values): security.aer_source_class_v1 gives no_source, source_found, read_held,
--    awaiting_layer4, active, course_only or evidenced_non_publication from pipeline.aer_provider_coverage (security.aer_reconcile_v1) and the
--    inventory. security.aer_coverage_v1 (workstream C, 20261104040000; md5-guarded edit of its own definition) adds that class, a source
--    fingerprint (md5 of the provider's sources and stored-copy hashes: a changed page changes it) and the inventory outcome to the ledger;
--    security.coverage_due_v1 treats a new inventory row as a change, so reconciliation stays incremental (no whole-site crawl).
-- 3. Root causes and remedies for what discovery and the UWA and RMIT diagnoses found, through workstream A's contract.
-- Reader fixes: the shared fixes the diagnoses need are in the worker (coverage-sweep, owned by workstream B) and are interface requests; no
--   database reader needs a change (the D-R3 gate, security.entry_matrix_gate_v1, already refuses the incomplete UWA read).
-- Edited (md5-guarded; workstream C's own functions from 20261104040000, not yet live; before = the after of that migration on the fixtures):
--   security.aer_coverage_v1(uuid[])   012a27171f32b8d6362e901f0edf7115 -> ec486095eb5a909b32e4e9a7b341ad90
--   security.coverage_due_v1(text,integer)   95f59636b46681f9f345bfa6233c6c3b -> 39b354778a124ba5a8bd13d987d7fb08
--   security.aer_course_population_v1()   f6cac5f2357e2091b9884295428341bb -> 0eb8ddc8b94133648ced5e8750752011   (Release C, live md5 read 3 Nov 2026 18:2x; edit authorised by the Integration Controller 18:30)
-- Replaces: security.aer_coverage_v1, security.coverage_due_v1, security.aer_course_population_v1 (same names; md5-guarded)
-- Retires: nothing
-- Consumer API: untouched (G3); security.aer_provider_stage_v1 only calls public.website_v2_provider/website_v2_course to read what is published.
-- Nothing is read from the web by this migration, nothing is attached, admitted or published; nothing is dropped or deleted. Of Release C only
-- security.aer_course_population_v1 is edited (the order of providers, behind coverage.aer_reader_priority_on; authorised 18:30); aer_schedule_*,
-- entry_matrix_enabled_v1, entry_matrix_fire_v1, course_entry_eligible_v1, course_entry_programme_v1 and aer_course_outcomes_build_v1 are not.

do $guard$
begin
  if to_regclass('pipeline.ops_remedies') is null or to_regclass('pipeline.coverage_provider_reconciliation') is null
     or to_regprocedure('security.aer_coverage_v1(uuid[])') is null then
    raise exception 'needs workstream A''s contract (20261104010000) and workstream C''s coverage ledger (20261104040000) first';
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

-- 1. the source inventory ------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_source_inventory (
  id bigserial primary key,
  provider_id uuid not null references catalogue.providers(id),
  url text,
  role text not null check (role in ('landing', 'country_table', 'pdf', 'selector', 'general', 'course_pages')),
  outcome text not null check (outcome in ('verified_attachable', 'verified_general_only', 'verified_rendered_only', 'unverified_link', 'blocked_site')),
  shape text not null,
  audience text,
  study_levels text[] not null default '{}',
  qualifications text[] not null default '{}',
  boundary text,
  evidence jsonb not null default '{}'::jsonb,
  attach boolean not null default false,
  verified_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  url_key text generated always as (coalesce(url, '')) stored,
  unique (provider_id, role, url_key)
);
comment on table pipeline.aer_source_inventory is 'CF-247 AER missing-university strategy (Platform Admin 3 Nov 2026 16:24), workstream C: the accountable inventory of official entry-requirement sources found by free, read-only discovery (official-site navigation; no Firecrawl, no paid search, no AI read), per provider: the exact verified URL (null when nothing could be verified), its role, outcome (verified_attachable, verified_general_only, verified_rendered_only, unverified_link, blocked_site), page shape, audience, study levels, global qualifications named, the identity boundary kept, and the provenance. A source is attached to pipeline.entry_matrix_sources only by a paste file the Integration Controller applies (attach = true marks those rows). Read by security.aer_source_class_v1 and security.aer_coverage_v1; never read by the consumer API.';
alter table pipeline.aer_source_inventory enable row level security;
revoke all on pipeline.aer_source_inventory from public, anon, authenticated;
revoke all on sequence pipeline.aer_source_inventory_id_seq from public, anon, authenticated;

create temporary table inv_src(provider_id uuid, url text, role text, outcome text, shape text, audience text, study_levels text[], qualifications text[],
  boundary text, evidence jsonb, attach boolean) on commit drop;
insert into inv_src values
 -- CDU
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'https://www.cdu.edu.au/international/how-apply/entry-requirements', 'country_table', 'verified_attachable',
  'html_table: undergraduate table of country secondary qualifications with minimums; general qualifications (GCE A Level, IB Diploma); TAFE, pre-masters, postgraduate coursework (general) and HDR tables',
  'international', '{undergraduate,postgraduate_coursework,research,vet}', '{"GCE A Level","IB Diploma","CBSE/CISCE"}',
  'CDU International College pathway PDFs on the page (diploma entry, pre-masters) are the college''s, not attached',
  '{"method": "WebFetch", "fetched": "2026-11-03T16:27+11:00", "quotes": ["Argentine Bachillerato 80% in the final year results", "French Baccalaureat with minimum grade score 11 out of 20.", "CBSE/CISCE: Minimum 60% average in best 4 academic subjects (including English)."], "global": "IB Diploma 24 points; GCE A-Level aggregate 6 over 3 subjects (as the page states)", "footer": "CDU CRICOS and TEQSA provider details", "stored_copy": {"evidence_id": "67481fa9-6f56-4f97-89bb-d9671ca40e80", "type": "source_snapshot", "captured": "2026-10-02"}}', true),
 -- Deakin
 ('c5c5d225-3d4c-4e41-8275-78eddd261073', null, 'landing', 'blocked_site',
  'unknown: the official site refused the free read (international entry requirements, English requirements and an international course page all failed or were outside the allowed list); search found the English page and the policy library only',
  'international', '{}', '{}', 'Deakin University only; Deakin College (pathway provider) excluded',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:28+11:00", "tried": ["https://www.deakin.edu.au/international-students/entry-requirements", "https://www.deakin.edu.au/international-students/entry-requirements/english", "https://www.deakin.edu.au/course/bachelor-commerce-international"], "found_by_search": ["https://policy.deakin.edu.au/document/view-current.php?id=161", "https://www.deakin.edu.au/international-students/entry-requirements/english"], "route": "stored course pages: 218 of 252 active courses have a bound official page (aer_course_outcomes, 3 Nov 2026)", "stored_copy": {"url": "https://www.deakin.edu.au/international-students/entry-requirements", "evidence_id": "5106f65f-fd16-4dc5-916b-f6070c8856d4", "type": "source_snapshot", "captured": "2026-10-02", "next": "read the stored copy (no new fetch) for the academic-requirements hrefs, then verify"}}', false),
 -- UNE
 ('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'https://www.une.edu.au/international/apply/eligibility/academic-requirements', 'general', 'verified_general_only',
  'general_text: no table and no minimum; undergraduate "at least equivalent to completion of Year 12 in Australia", postgraduate "comparable to an AQF bachelor degree"; course requirements in the Course Guide and Course Catalogue',
  'international', '{undergraduate,postgraduate}', '{}', 'University of New England (Australia) only, on une.edu.au',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:27+11:00", "quotes": ["at least equivalent to completion of Year 12 in Australia", "considered to be at least comparable to an Australian Qualifications Framework (AQF) bachelor degree"], "reader_contract": 6}', true),
 -- Torrens
 ('fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'https://www.torrens.edu.au/apply-online/admissions-criteria', 'general', 'verified_general_only',
  'general_text: General admission information set; undergraduate general admissions criteria and course-specific requirements; work and life experience table (AQF 5 Diploma, AQF Bachelor); no country table',
  'all (international named for English proficiency only)', '{undergraduate}', '{}',
  'names only Torrens University Australia; brand colleges are not named, so nothing is bound to them; the Think Education diploma is a separate provider',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:29+11:00", "also_seen": {"url": "https://www.torrens.edu.au/studying-with-us/international-students/studying-in-australia/india", "text": "Australian Year 12 or an equivalent qualification; postgraduate: must hold a bachelor''s level qualification"}, "stale_not_used": "https://www.torrens.edu.au/-/media/project/laureate/shared/pdf/international-study/2024-intl-entry-req-flyer.pdf (2024 edition)", "reader_contract": 6}', true),
 -- ACU
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'https://www.acu.edu.au/study-at-acu/how-to-apply/international-students/international-undergraduate-students', 'landing', 'unverified_link',
  'landing_text: "equivalent of an Australian Year 12 Certificate for most undergraduate courses"; links "Download the minimum academic entry requirement (PDF, 405KB)" (diplomas and bachelor degrees) whose exact URL could not be verified',
  'international', '{undergraduate,diploma}', '{}', 'ACU only',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:28+11:00", "pdf_search_result": "a search result titled \"1 Minimum academic entry requirements by country QUALIFICATION\" on acu.edu.au with a truncated path; fetching it failed (client_error); not invented", "next": "take the PDF href from the landing page''s stored copy or a permitted read, then attach (pdf route, column-fidelity gate)"}', false),
 -- JCU
 ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'https://www.jcu.edu.au/entry-options/entry-requirements/academic-and-english-language-entry-requirements/country-specific-academic-levels', 'selector', 'verified_rendered_only',
  'selector: choose schooling qualification, then JCU undergraduate course, "The required mark will then appear" (course-specific marks, data loaded dynamically; no static table)',
  'international (secondary school leavers)', '{undergraduate}', '{}',
  'Australian campuses; the page does not mention Singapore, so nothing is bound to JCU Singapore',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:27+11:00", "landing": "https://www.jcu.edu.au/applying-to-jcu/international/coursework/academic-and-english-language-entry-requirements", "landing_quote": "you must have completed a recognised Year 12 program or equivalent", "postgraduate": "Academic entry requirements vary for each of our postgraduate degrees.", "route": "rendered read (entry.render_hosts, Firecrawl within its rules) is a spend decision; course pages meanwhile", "stored_copy": {"url": "https://www.jcu.edu.au/applying-to-jcu/international/coursework/academic-and-english-language-entry-requirements", "evidence_id": "f82b38eb-f632-47b8-9f6b-9246d8439a36", "type": "source_snapshot", "captured": "2026-10-02"}}', false),
 -- CQU
 ('f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6', 'https://www.cqu.edu.au/study/international/entry-requirements/academic-requirements', 'landing', 'unverified_link',
  'general_text by level (diploma, undergraduate, postgraduate coursework and research, MBA special entry); refers to a "country specific academic requirements document" whose URL could not be verified',
  'international', '{diploma,undergraduate,postgraduate_coursework,research}', '{}', 'CQUniversity (cqu.edu.au) = catalogue provider f02d9d9b; CQU is an alias only',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:27+11:00", "quotes": ["Successful completion of the equivalent of Australian Year 12."], "next": "take the country document href from the page''s stored copy or a permitted read, then attach", "stored_copy": {"url": "https://www.cqu.edu.au/study/international/entry-requirements", "evidence_id": "2eac8bc6-a8ab-407d-af09-366296291b45", "type": "source_snapshot", "captured": "2026-10-05"}}', false),
 -- UniSQ
 ('551383f9-7732-4588-a843-dd2b97c13f6f', 'https://www.unisq.edu.au/international/apply/entry-requirements', 'country_table', 'verified_attachable',
  'html_table_partial: a Qualification | Grade table filled by a country selector (dynamic) plus static global rules: GCE A Level (best three subjects, A* = 6, A = 5, B = 4) and IB Diploma (minimum 24 points, Selection Rank 65)',
  'international', '{undergraduate}', '{"GCE A Level","IB Diploma"}', 'University of Southern Queensland (UniSQ); USQ only as an alias seen in service hostnames',
  '{"method": "WebSearch, WebFetch", "fetched": "2026-11-03T16:27+11:00", "copyright": "University of Southern Queensland 2026", "note": "a direct read keeps the static global rules; the per-country rows need the rendered route (spend decision)", "reader_contract": 5}', true);

do $$
declare v_n int;
begin
  select count(*) into v_n from inv_src s where not exists (select 1 from catalogue.providers p where p.id = s.provider_id);
  if v_n > 0 then raise exception '% inventory rows name an unknown provider', v_n; end if;
  if (select count(distinct provider_id) from inv_src) <> 8 then raise exception 'the inventory must cover the eight universities'; end if;
  insert into pipeline.aer_source_inventory(provider_id, url, role, outcome, shape, audience, study_levels, qualifications, boundary, evidence, attach, verified_at)
  select s.provider_id, s.url, s.role, s.outcome, s.shape, s.audience, s.study_levels, s.qualifications, s.boundary, s.evidence, s.attach, '2026-11-03 16:30+11'::timestamptz
    from inv_src s
  on conflict (provider_id, role, url_key) do nothing;
end $$;

-- 2. report classification -----------------------------------------------------------------------------------------------------------------
create or replace function security.aer_source_class_v1(p_provider uuid) returns text
language sql stable security definer set search_path to '' as $function$
  -- CF-247 AER missing-university strategy §E: a report classification, never a status value. From the AER reconcile disposition
  -- (pipeline.aer_provider_coverage) and the source inventory: no_source, source_found (a verified source not yet attached), read_held,
  -- awaiting_layer4, active, course_only, evidenced_non_publication.
  select case
    when c.disposition is null or c.disposition = 'not_discovered' then
      -- a source attached since the last AER reconcile, or a verified source not yet attached
      case when exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = p_provider)
             or exists (select 1 from pipeline.aer_source_inventory i where i.provider_id = p_provider and i.url is not null
                          and i.outcome in ('verified_attachable', 'verified_general_only', 'verified_rendered_only'))
           then 'source_found' else 'no_source' end
    when c.disposition in ('source_held', 'reader_failed') then 'read_held'
    when c.disposition = 'awaiting_layer4' then 'awaiting_layer4'
    when c.disposition = 'active_verified' then 'active'
    when c.disposition = 'course_only' then 'course_only'
    when c.disposition in ('source_not_published_evidenced', 'not_applicable_evidenced') then 'evidenced_non_publication'
    else c.disposition end
  from (select 1) one left join pipeline.aer_provider_coverage c on c.provider_id = p_provider
$function$;
revoke all on function security.aer_source_class_v1(uuid) from public, anon, authenticated;
comment on function security.aer_source_class_v1(uuid) is 'CF-247 AER missing-university strategy §E: report classification of a provider''s AER coverage (no_source, source_found, read_held, awaiting_layer4, active, course_only, evidenced_non_publication) from pipeline.aer_provider_coverage and pipeline.aer_source_inventory. Not a status value. Read-only.';

select pg_temp.edit_once('security.aer_coverage_v1(uuid[])', '012a27171f32b8d6362e901f0edf7115', 'ec486095eb5a909b32e4e9a7b341ad90', array[
  array[$e$  src as (select x.provider_id, count(*) n, count(*) filter (where x.status = 'read') nread, count(*) filter (where x.status = 'failed') nfail$e$,
        $e$  src as (select x.provider_id, count(*) n, count(*) filter (where x.status = 'read') nread, count(*) filter (where x.status = 'failed') nfail,
                md5(string_agg(x.url || '=' || coalesce(x.content_hash, ''), '|' order by x.url)) fp$e$],
  array[$e$           'courses_intake', h.intake, 'courses_deadline', h.deadline, 'aer_disposition', h.aer_disposition, 'provider_level', h.plevel,$e$,
        $e$           'courses_intake', h.intake, 'courses_deadline', h.deadline, 'aer_disposition', h.aer_disposition, 'provider_level', h.plevel,
           -- CF-247 AER missing-university strategy §E: report class, source fingerprint (changes when a page's stored copy changes), inventory outcomes
           'aer_class', security.aer_source_class_v1(h.id),
           'source_fingerprint', (select src.fp from src where src.provider_id = h.id),
           'inventory', (select jsonb_object_agg(i.outcome, i.n) from (select x.outcome, count(*) n from pipeline.aer_source_inventory x where x.provider_id = h.id group by 1) i),$e$]
]::text[][], array[1, 1]);

select pg_temp.edit_once('security.coverage_due_v1(text,integer)', '95f59636b46681f9f345bfa6233c6c3b', '39b354778a124ba5a8bd13d987d7fb08', array[
  array[$e$           union all select x.provider_id, x.updated_at from pipeline.entry_matrix_sources x, w where p_domain = 'aer' and x.updated_at > w.since$e$,
        $e$           union all select x.provider_id, x.updated_at from pipeline.entry_matrix_sources x, w where p_domain = 'aer' and x.updated_at > w.since
           union all select i.provider_id, i.recorded_at from pipeline.aer_source_inventory i, w where p_domain = 'aer' and i.recorded_at > w.since$e$]
]::text[][], array[1]);

-- 3. verify of the source attachment, root causes and remedies ------------------------------------------------------------------------------
create or replace function security.aer_source_inventory_verify_v1(p_issue bigint) returns jsonb
language sql stable security definer set search_path to '' as $function$
  -- CF-247 AER missing-university strategy: passed when every inventory source marked for attachment is in pipeline.entry_matrix_sources
  -- (the paste file has been applied) and has been read (status read, a stored copy hash).
  with a as (select i.provider_id, i.url, s.id source_id, s.status, s.content_hash from pipeline.aer_source_inventory i
               left join pipeline.entry_matrix_sources s on s.provider_id = i.provider_id and s.url = i.url where i.attach)
  select jsonb_build_object('passed', count(*) > 0 and count(*) filter (where a.source_id is null) = 0 and count(*) filter (where a.status <> 'read' or a.content_hash is null) = 0,
    'measure', jsonb_build_object('to_attach', count(*), 'attached', count(a.source_id), 'read', count(*) filter (where a.status = 'read' and a.content_hash is not null)),
    'evidence', jsonb_build_object('issue', p_issue, 'at', now(), 'not_attached', coalesce(jsonb_agg(a.url) filter (where a.source_id is null), '[]'::jsonb)))
    from a
$function$;
revoke all on function security.aer_source_inventory_verify_v1(bigint) from public, anon, authenticated;
comment on function security.aer_source_inventory_verify_v1(bigint) is 'CF-247 AER missing-university strategy: verify of remedy aer_source_attach (the inventory sources marked for attachment are in pipeline.entry_matrix_sources and read). Returns {passed, measure, evidence}. Read-only.';

select security.ops_root_cause_register_v1('aer_source_unverified', jsonb_build_object('class', 'dependency',
  'title', 'An official entry-requirement source could not be verified by a free read',
  'description', 'The official site refused the free read (Deakin), or the official page names a document whose exact URL could not be verified (ACU minimum academic entry PDF, CQU country document). Nothing is invented; the stored course pages carry the provider meanwhile.',
  'detect', jsonb_build_object('table', 'pipeline.aer_source_inventory', 'outcomes', jsonb_build_array('blocked_site', 'unverified_link'))));
select security.ops_root_cause_register_v1('aer_source_rendered_only', jsonb_build_object('class', 'policy',
  'title', 'Entry requirements published only in a JavaScript selector',
  'description', 'JCU (qualification x course selector) and UniSQ (country selector) load their minimums dynamically; reading them needs the rendered route (entry.render_hosts, Firecrawl within its rules), a spend decision.',
  'detect', jsonb_build_object('table', 'pipeline.aer_source_inventory', 'outcomes', jsonb_build_array('verified_rendered_only'))));
select security.ops_root_cause_register_v1('aer_source_not_attached', jsonb_build_object('class', 'dependency',
  'title', 'A verified official entry-requirement source is not attached',
  'description', 'Free discovery verified an official source (inventory attach = true) that is not yet in pipeline.entry_matrix_sources; the scheduled AER reader admits a provider only once an entry page is recorded.',
  'detect', jsonb_build_object('verify_fn', 'security.aer_source_inventory_verify_v1(bigint)')));
select security.ops_root_cause_register_v1('aer_reader_value_not_printed', jsonb_build_object('class', 'rule',
  'title', 'Matrix rows dropped because the value the reader gave is not printed in the row',
  'description', 'UWA run 4edb1e9f (28 Oct 2026, worker v0.52.0): all 8 China (Gaokao) rows, printed as "score range | percentage | ATAR" (for example "488 to 491 | 65% | 70"), were dropped as value_not_in_quote, leaving no China row; the dropped entries keep only the quote and reason, so the value the model gave cannot be recovered. The D-R3 gate refuses the read.',
  'detect', jsonb_build_object('fn', 'security.entry_matrix_gate_v1(uuid,uuid[])', 'reason', 'value_not_in_quote')));
select security.ops_root_cause_register_v1('aer_subject_rows_one_identity', jsonb_build_object('class', 'rule',
  'title', 'Subject prerequisite rows stored as matrix minimums with one identity',
  'description', 'UWA: 7 US Advanced Placement subject-equivalence rows ("Chemistry | Chemistry; 3 or higher") are stored as separate minimums with the same country, qualification, level and band; they are subject prerequisites (conditions.subject_minimums), not qualification minimums. The D-R3 gate flags them.',
  'detect', jsonb_build_object('fn', 'security.entry_matrix_gate_v1(uuid,uuid[])', 'finding', 'same_identity')));

select security.ops_remedy_register_v1('aer_source_attach', jsonb_build_object('title', 'Attach verified official entry-requirement sources (paste file)',
  'treats', jsonb_build_array('aer_source_not_attached'), 'authority', 'release', 'verify_fn', 'security.aer_source_inventory_verify_v1(bigint)',
  'max_attempts_key', 'coverage.remedy_max_attempts', 'cooldown_key', 'coverage.remedy_cooldown_minutes', 'active', true,
  'notes', 'docs/paste/PASTE-20261104-aer-missing-university-sources.sql, applied by the Integration Controller. Reading follows through the existing entry-matrix reader; first reads go to Layer 4.'));
select security.ops_remedy_register_v1('aer_source_discovery', jsonb_build_object('title', 'Verify a blocked or unexposed official source',
  'treats', jsonb_build_array('aer_source_unverified', 'aer_source_rendered_only'), 'authority', 'admin', 'verify_fn', 'security.coverage_investigation_verify_v1(bigint)',
  'max_attempts_key', 'coverage.remedy_max_attempts', 'cooldown_key', 'coverage.remedy_cooldown_minutes', 'active', true,
  'notes', 'Needs a permitted read (rendered route or a stored copy of the landing page) or a person; never an invented URL.'));
select security.ops_remedy_register_v1('aer_reader_row_fidelity', jsonb_build_object('title', 'Reader fixes for range rows and subject prerequisites (worker, workstream B), then a corrected read',
  'treats', jsonb_build_array('aer_reader_value_not_printed', 'aer_subject_rows_one_identity'), 'authority', 'release', 'verify_fn', 'security.coverage_investigation_verify_v1(bigint)',
  'max_attempts_key', 'coverage.remedy_max_attempts', 'cooldown_key', 'coverage.remedy_cooldown_minutes', 'active', true,
  'notes', 'Interface request to workstream B (coverage-sweep entry reader); then one governed Read again of the UWA source (security.aer_reread_v1) for Platform Admin review. Active rows are never rewritten.'));

-- 3b. the scheduled course reader takes providers with an AER shortfall first (Integration Controller authority, 3 Nov 2026 18:30, Release C) --
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'coverage.aer_reader_priority_on', 'Entry reading: providers with a coverage shortfall first',
  'On: the entry-reading population (security.aer_course_population_v1) puts the providers in coverage.aer_priority_providers first, then providers whose coverage ledger shows an entry-requirement shortfall, largest first, then the provider types in aer.priority_provider_types. Off: the order is types, then name, as before. Only the order changes: the per-run size, the daily cap, the 600-item back-pressure and every gate are unchanged.',
  'boolean', 'true'::jsonb, null, null, null, 1121, 'Coverage reconciliation', 'security.aer_course_population_v1 (job aer-scheduled-read; Read next batch)',
  'Integration Controller 3 Nov 2026 18:30 (Platform Admin P1 18:17): Deakin has 218 bound course pages the reader has not reached'),
 ('pipeline', 'coverage.aer_priority_providers', 'Entry reading and staged status: providers followed first',
  'Provider ids read first by the entry reader and reported by security.aer_provider_stage_v1: the eight universities of the missing-university strategy, UWA and RMIT.',
  'list', '["6f5cb7f7-7c70-4c06-970f-f368c3a786e2", "c5c5d225-3d4c-4e41-8275-78eddd261073", "fa0e0d13-838a-42ff-b6a3-9cea84bd80b2", "fec52f92-a8a3-4de8-a862-06f355e4e2f7", "030992c3-72c6-452d-8a3b-10ceb0fd77f2", "fe6af182-f5ca-4a3c-bfb4-b0773ff1b113", "f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6", "551383f9-7732-4588-a843-dd2b97c13f6f", "9109fe0c-9f44-4e2d-a136-eb00dec24701", "8e1adb6c-e069-43db-9584-bd054255e702"]'::jsonb,
  null, null, 'providers', 1122, 'Coverage reconciliation', 'security.aer_course_population_v1; security.aer_provider_stage_v1',
  'AER missing-university strategy (Platform Admin 3 Nov 2026 16:24) and P1 18:17'),
 ('pipeline', 'coverage.stage_gate_scan', 'Staged status: waiting Layer 4 items checked per provider',
  'security.aer_provider_stage_v1 runs the Layer 4 gates (D-R3 for matrix runs, E13 for course reads) on at most this many waiting items of each provider, newest first, and says how many it checked.',
  'number', to_jsonb(50), 1, 1000, 'items', 1123, 'Coverage reconciliation', 'security.aer_provider_stage_v1', 'Integration Controller 3 Nov 2026 18:30 item 2'),
 ('pipeline', 'coverage.stage_consumer_course_sample', 'Staged status: courses checked in the consumer projection',
  'security.aer_provider_stage_v1 reads the website projection (public.website_v2_course, read only) for at most this many of the provider''s courses with an active requirement.',
  'number', to_jsonb(20), 0, 500, 'courses', 1124, 'Coverage reconciliation', 'security.aer_provider_stage_v1', 'Integration Controller 3 Nov 2026 18:30 item 2')
on conflict do nothing;

select pg_temp.edit_once('security.aer_course_population_v1()', 'f6cac5f2357e2091b9884295428341bb', '0eb8ddc8b94133648ced5e8750752011', array[
  array[$e$                    coalesce(security.toolset_setting('pipeline', 'aer.priority_provider_types'), '[]'::jsonb) pt),$e$,
        $e$                    coalesce(security.toolset_setting('pipeline', 'aer.priority_provider_types'), '[]'::jsonb) pt,
                    -- CF-247 workstream C (Integration Controller 3 Nov 2026 18:30): followed providers, then the largest AER shortfall, first
                    coalesce((security.toolset_setting('pipeline', 'coverage.aer_reader_priority_on') #>> '{}')::boolean, false) gap_first,
                    coalesce(security.toolset_setting('pipeline', 'coverage.aer_priority_providers'), '[]'::jsonb) followed),$e$],
  array[$e$                case when s.pt ? coalesce(t.code, '') then 1 else 2 end tier$e$,
        $e$                case when s.gap_first and s.followed ? e.provider_id::text then -1000000
                     when s.gap_first and coalesce(k.shortfall, 0) > 0 then -least(k.shortfall, 999999)
                     when s.pt ? coalesce(t.code, '') then 1 else 2 end tier$e$],
  array[$e$           left join ref.provider_types t on t.id = p.provider_type_id$e$,
        $e$           left join ref.provider_types t on t.id = p.provider_type_id
           left join pipeline.coverage_provider_reconciliation k on k.domain = 'aer' and k.provider_id = e.provider_id$e$]
]::text[][], array[1, 1, 1]);

-- 3c. per-provider staged status (Integration Controller 3 Nov 2026 18:30 item 2) ------------------------------------------------------------
create or replace function security.aer_provider_stage_v1(p_providers uuid[] default null)
returns table(provider_id uuid, provider_name text, stage text, sources jsonb, reads jsonb, layer4 jsonb, admitted jsonb, consumer jsonb)
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 workstream C: where each followed provider stands, stage by stage, kept apart: sources attached; reads done or held (with the reason);
-- Layer 4 items judgement-ready or technically blocked (the D-R3 matrix gate and the E13 course gate, at most coverage.stage_gate_scan items a
-- provider); rows admitted (active); and what the website projection returns (public.website_v2_provider and public.website_v2_course, read only).
-- Discovery and an AI read never count as admission. Read-only.
declare v_ids uuid[] := coalesce(p_providers, array(select x::uuid from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'coverage.aer_priority_providers'), '[]'::jsonb)) x));
        v_scan int := greatest(1, security.pipeline_num_v1('coverage.stage_gate_scan', 50)::int);
        v_sample int := greatest(0, security.pipeline_num_v1('coverage.stage_consumer_course_sample', 20)::int);
        r record; i record; g jsonb; v_ready int; v_block int; v_checked int; v_why jsonb; v_pub int; v_seen int; v_prov jsonb; v_cpub int; v_ccheck int;
begin
  for r in select p.id, coalesce(p.display_name, p.short_name, p.canonical_name) nm, p.stable_key from catalogue.providers p where p.id = any (v_ids) order by 2 loop
    provider_id := r.id; provider_name := r.nm;
    select jsonb_build_object('attached', count(*), 'read', count(*) filter (where s.status = 'read'), 'failed', count(*) filter (where s.status = 'failed'),
                              'unread', count(*) filter (where s.status not in ('read', 'failed')), 'fingerprint', md5(string_agg(s.url || '=' || coalesce(s.content_hash, ''), '|' order by s.url)))
      into sources from pipeline.entry_matrix_sources s where s.provider_id = r.id;
    with lr as (select distinct on (x.source_id) x.* from pipeline.entry_matrix_runs x where x.provider_id = r.id order by x.source_id, x.created_at desc),
    cr as (select li.status, count(*) n from pipeline.layer4_review_items li join catalogue.courses c on c.id = li.entity_id
            where c.provider_id = r.id and li.field_code = 'course_entry_first_read' group by 1)
    select jsonb_build_object('matrix_done', (select count(*) from lr where lr.state = 'done'),
             'matrix_held', (select count(*) from lr where lr.state = 'failed'),
             'matrix_held_reasons', (select coalesce(jsonb_object_agg(w, n), '{}'::jsonb) from (select split_part(coalesce(lr.error, 'failed'), ':', 1) w, count(*) n from lr where lr.state = 'failed' group by 1) z),
             'course_reads', (select coalesce(jsonb_object_agg(cr.status, cr.n), '{}'::jsonb) from cr))
      into reads;
    v_ready := 0; v_block := 0; v_checked := 0; v_why := '{}'::jsonb;
    for i in (select 'matrix' kind, x.id run_id, li.id item_id, li.created_at from pipeline.entry_matrix_runs x join pipeline.layer4_review_items li on li.id = x.review_item_id
               where x.provider_id = r.id and li.status = 'pending'
              union all
              select 'course', null, li.id, li.created_at from pipeline.layer4_review_items li join catalogue.courses c on c.id = li.entity_id
               where c.provider_id = r.id and li.field_code = 'course_entry_first_read' and li.status = 'pending')
             order by 4 desc limit v_scan loop
      g := case i.kind when 'matrix' then security.entry_matrix_gate_v1(i.run_id, '{}'::uuid[]) else security.course_entry_gate_v1(i.item_id, '{}'::uuid[]) end;
      v_checked := v_checked + 1;
      if coalesce((g->>'complete')::boolean, false) then v_ready := v_ready + 1;
      else
        v_block := v_block + 1;
        v_why := v_why || jsonb_build_object(i.kind || ': ' || left(coalesce(g->'reasons'->>0, 'incomplete'), 90),
                                             coalesce((v_why->>(i.kind || ': ' || left(coalesce(g->'reasons'->>0, 'incomplete'), 90)))::int, 0) + 1);
      end if;
    end loop;
    layer4 := jsonb_build_object('pending', (select count(*) from (select li.id from pipeline.entry_matrix_runs x join pipeline.layer4_review_items li on li.id = x.review_item_id
                                                                    where x.provider_id = r.id and li.status = 'pending'
                                                                   union all select li.id from pipeline.layer4_review_items li join catalogue.courses c on c.id = li.entity_id
                                                                    where c.provider_id = r.id and li.field_code = 'course_entry_first_read' and li.status = 'pending') z),
                                 'checked', v_checked, 'judgement_ready', v_ready, 'technically_blocked', v_block, 'blocked_reasons', v_why);
    select jsonb_build_object('matrix_active', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = r.id and m.status = 'active'),
                              'matrix_proposed', (select count(*) from catalogue.provider_entry_matrix m where m.provider_id = r.id and m.status = 'proposed'),
                              'course_rows_active', count(*) filter (where x.status = 'active'), 'courses_with_active', count(distinct x.course_id) filter (where x.status = 'active'),
                              'course_rows_proposed', count(*) filter (where x.status = 'proposed'))
      into admitted from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id where c.provider_id = r.id;
    -- the website projection, read only (the consumer API is not changed or re-shaped; G3)
    v_prov := case when to_regprocedure('public.website_v2_provider(text)') is not null then public.website_v2_provider(r.stable_key) end;
    v_pub := coalesce(jsonb_array_length(case when jsonb_typeof(v_prov->'item'->'entry_matrix') = 'array' then v_prov->'item'->'entry_matrix' end), 0);
    v_cpub := 0; v_ccheck := 0;
    if to_regprocedure('public.website_v2_course(text)') is not null then
      for i in select c.stable_key from catalogue.courses c where c.provider_id = r.id and c.lifecycle_status = 'active'
                 and exists (select 1 from catalogue.course_entry_requirements x where x.course_id = c.id and x.status = 'active') order by c.id limit v_sample loop
        g := public.website_v2_course(i.stable_key)->'item'->'entry';
        v_ccheck := v_ccheck + 1;
        if g is not null and jsonb_typeof(g) = 'object' and (g->>'min_score' is not null or jsonb_array_length(coalesce(case when jsonb_typeof(g->'prerequisites') = 'array' then g->'prerequisites' end, '[]'::jsonb)) > 0)
          then v_cpub := v_cpub + 1; end if;
      end loop;
    end if;
    consumer := jsonb_build_object('provider_matrix_rows_published', v_pub, 'provider_found', coalesce(v_prov ? 'item', false),
                                   'courses_checked', v_ccheck, 'courses_with_published_entry', v_cpub);
    stage := case when v_pub > 0 or v_cpub > 0 then 'published'
                  when (admitted->>'matrix_active')::int + (admitted->>'course_rows_active')::int > 0 then 'admitted_not_published'
                  when v_ready > 0 then 'awaiting_judgement'
                  when v_block > 0 then 'technically_blocked'
                  when (reads->>'matrix_held')::int > 0 then 'read_held'
                  when (sources->>'read')::int > 0 or jsonb_typeof(reads->'course_reads') = 'object' and reads->'course_reads' <> '{}'::jsonb then 'read'
                  when (sources->>'attached')::int > 0 then 'source_attached'
                  else 'no_source' end;
    return next;
  end loop;
end $function$;
revoke all on function security.aer_provider_stage_v1(uuid[]) from public, anon, authenticated;
comment on function security.aer_provider_stage_v1(uuid[]) is 'CF-247 workstream C (Integration Controller 3 Nov 2026 18:30): per followed provider (coverage.aer_priority_providers, or those given), the AER stages kept apart: sources attached; reads done or held with reasons; Layer 4 items judgement-ready or technically blocked (D-R3 and E13 gates, coverage.stage_gate_scan items); active rows; and what the website projection returns (public.website_v2_provider, public.website_v2_course, read only). Discovery and an AI read never count as admission. Read-only.';

-- 4. register (housekeeping) --------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.aer_source_inventory', 'Layer 2', 'Entry requirements', 'Accountable inventory of official AER sources found by free discovery', 'active', '{}', '20261104090000')
on conflict do nothing;

-- 5. post-check ---------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(distinct provider_id) from pipeline.aer_source_inventory) < 8 then raise exception 'post-check: inventory'; end if;
  if exists (select 1 from pipeline.aer_source_inventory where outcome in ('blocked_site') and url is not null) then raise exception 'post-check: a blocked outcome names no URL'; end if;
  if exists (select 1 from pipeline.aer_source_inventory where attach and outcome not in ('verified_attachable', 'verified_general_only')) then raise exception 'post-check: only verified readable sources are marked for attachment'; end if;
  if (select count(*) from pipeline.ops_remedies where code in ('aer_source_attach', 'aer_source_discovery', 'aer_reader_row_fidelity')) <> 3 then raise exception 'post-check: remedies'; end if;
end $$;
