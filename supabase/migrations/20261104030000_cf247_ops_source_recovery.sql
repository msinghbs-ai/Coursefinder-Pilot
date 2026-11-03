-- CF-247 P0 Autonomous AI Operations, workstream B: source discovery and coverage recovery (mandate 3 Nov 2026 15:37 §3, §4 and the D1 special
-- case; workstreams 15:40 §3: B owns source_proof_feed_v1, course_relink_*, field_gap_*, field_absence_*; migration 20261104030000, spec s246).
-- Builds on workstream A's shared contract (migration 20261104010000: pipeline.ops_root_causes, pipeline.ops_remedies, pipeline.ops_remedy_runs,
-- security.ops_root_cause_register_v1, security.ops_remedy_register_v1), which lands first.
-- Why (production, read-only, 3 Nov 2026 15:42-16:08 AEDT; evidence and samples in the workstream B report):
--   S1 Capacity read as "needs paid search". security.source_proof_feed_v1 sends a course whose stored page was refused as another course's
--      (read_status identity_mismatch) to course-relink only while proof.feed_per_run (50) lasts; every later one in the run is recorded
--      no_route, the D1 measure. Of the 2,246 no_route requests at 15:43, 1,625 are identity_mismatch courses the lane would relink with
--      capacity (all were relinked once before: 1,250 found no address, 283 had every candidate refused, 92 are still trying), so the
--      no_route count mixes "free route not yet re-asked" with "needs paid search".
--   S2 The D1 count is half a picture. proof.scan_per_run (2,000) is below the 3,741 unproven pages, so each run sees about half: the 14:44 run
--      reported 1,222 no_route and the 15:14 run 1,175 more, 2,246 distinct courses in all.
--   S3 Pages refused by the E16 binding check are never relinked. course-relink (18 Oct) and the feed take only read_status identity_mismatch;
--      the E16 check (2 Nov) refuses with identity_refused, page_refused, refused_host and not_course_page (389, 345, 60 and 16 courses with an
--      open identity_unresolved absence), which have no free route at all.
--   S4 The feed never sees most unresolved identities. It reads only pipeline.course_page_proofs, written by the standing gap queue; 2,865 of
--      the 3,949 courses with an open identity_unresolved absence (and 2,987 of 3,860 needs_source_discovery) have no proof row.
--   S5 Title-to-address matching. course-relink matches a stored provider address only to the exact slug of the full title: no diacritics
--      (Maori titles), apostrophes, "&" for "and", NZ "(Level n)" suffixes, bracketed qualifiers, or Canadian register titles ("Nursing: Master
--      of Science (MSN) - UBCO", "Bachelor of Science in Civil Engineering Civil Engineering"). Of the 8,904 courses that are no_route,
--      identity_unresolved or needs_source_discovery, 441 have an untried stored address of their own provider matching a title form (77 by
--      normalisation, 267 without the bracketed part). With the register forms and stored page titles, 179 of the 2,184 no_route courses
--      (57 providers) have one (16:06 AEDT).
--   S6 Address normalisation. course-relink compares a candidate with the refused page and de-duplicates by lower() only: 24 relinks spent a
--      try on the refused page itself in another spelling (scheme, www, trailing slash, fragment); 5 candidates were pages already rejected.
--   S7 Paid evidence not reused. 1,887 of the 2,184 no_route courses already had a paid Firecrawl course-page search (find_page); 634 hold
--      untried candidates from it. Paid search for them would pay twice; their stored candidates are free to try.
--   S8 Older handbook years. A bound page refused only because its address names an older handbook year (old_year) has the current year's
--      address as a deterministic candidate (canonical reconciliation).
--   S9 A known page whose direct read failed (fetch_failed, robots_disallowed, blocked, needs_render, too_thin at the reader's try limit) needs an
--      authorised page read, not a course-page search; today it is counted with D1.
-- What:
--   1 security.source_proof_feed_v1 (md5-guarded edit):
--      a capacity: a course with a free relink route beyond proof.feed_per_run is held as relink (state held, detail wait free_capacity) and taken
--        first next run, never recorded no_route (ships ON: it corrects what is recorded; no work is added or removed);
--      b the page states sent to course-relink are relink.statuses (ships ["identity_mismatch"], today's behaviour);
--      c with proof.absence_input_on, courses with an open absence in proof.absence_input_classes and no proof row are considered too
--        (ships OFF);
--      d the input fingerprint includes the recovery fingerprint (pipeline.field_absence_recovery.fingerprint), so a course is tried again only
--        when its candidate evidence changes;
--      e paid course-page search is never queued for a course whose previous paid search left untried candidates (stops waste; ships ON;
--        proof.search_per_run stays 0).
--   2 security.course_relink_tick_v1 and security.course_relink_provider_v1 (md5-guarded edits): the page states are relink.statuses; candidate
--      addresses are compared and de-duplicated in normalised form (security.course_relink_url_norm_v1) and never a page already rejected for the
--      course (ships ON: it only stops waste); with relink.slug_variants_on, title variants (security.course_relink_slugs_v1) match stored
--      provider addresses; with relink.year_current_on, the refused page's handbook year is moved to the current year; with
--      relink.stored_search_reuse_on, untried candidates of the course's previous course-page search are tried (each ships OFF). Every
--      candidate is still only bound for the reader, whose identity check decides (E16); nothing is admitted here.
--   3 The D1 recovery cohort (pipeline.field_absence_recovery, one row per course the feed has held without a free route; job
--      field-absence-recovery, hourly, records only, ships ON): its state (recovered_free, waiting_current_work, waiting_layer4, locked,
--      free_route_capacity, free_route_refused_status, free_route_stored_search, free_route_provider_list, free_route_canonical_year,
--      needs_authorised_read, needs_paid_research, needs_paid_discovery), the discovery step reached (mandate §4 order 1-8), the free routes
--      open, an evidence fingerprint, the paid search already spent and the fields filled since entry; every run in
--      pipeline.field_absence_recovery_runs. View pipeline.field_absence_recovery_providers: per provider, the states and the estimated
--      recovery yield. security.field_absence_d1_decision_v1(): the costed D1 decision table from measured history (firecrawl_calls,
--      course_link_search), read-only.
--   4 Workstream A's contract: root causes src_* and remedies registered (security.ops_root_cause_register_v1, security.ops_remedy_register_v1).
--      The auto remedy (rem_source_recovery_refresh) refreshes the cohort; its verify function measures real movement (cohort pages proven,
--      then fields filled since entry). The switch remedies are admin authority (a recorded setting change); the E16 rule items are release.
-- md5 (before = live, read 3 Nov 2026 15:42 AEDT and rebuilt locally from the repository's live files plus the 20261103190000 and 20261103210000
-- edits; after = local replay on PostgreSQL 16, tests/fixtures/ops-source-recovery/run.sh):
--   security.source_proof_feed_v1()                  cade6b2de219c216709129ce4bc447ff -> 87278b507bcec288603d85c22d8da105
--   security.course_relink_provider_v1(uuid,integer) 8f2f82c7e2ad360a0ade7cdee1f63cce -> 776844024ca5ee99011ad73dfd36360b
--   security.course_relink_tick_v1(integer)          b159c75a0ed1517fc9305b62984aa141 -> 0cd20104a975c471ed4dd9060569f3b8
-- Spend: none. No Firecrawl, AI or paid search is called or queued (proof.search_per_run stays 0; D1 stays off). Candidates are read directly
--   by the existing reader. D1 is not switched on.
-- Consumer API (G3): untouched.
-- Activation (each a recorded setting change by the Integration Controller or Platform Admin, separately from this release):
--   relink.statuses ["identity_mismatch", "identity_refused", "page_refused", "refused_host", "not_course_page"]; relink.slug_variants_on 1;
--   relink.year_current_on 1; relink.stored_search_reuse_on 1; proof.absence_input_on 1.
-- Replaces: security.source_proof_feed_v1, security.course_relink_tick_v1, security.course_relink_provider_v1 (same names; md5-guarded edits); the no_route count as the D1 measure (now pipeline.field_absence_recovery and security.field_absence_d1_decision_v1)
-- Retires: nothing
-- Nothing is dropped or deleted. One job is added (field-absence-recovery, records only).

-- 0. what this change builds on -------------------------------------------------------------------------------------------------------------
do $g$
declare r record;
begin
  if to_regclass('pipeline.ops_remedies') is null or to_regclass('pipeline.ops_root_causes') is null or to_regclass('pipeline.ops_remedy_runs') is null
     or to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is null or to_regprocedure('security.ops_root_cause_register_v1(text,jsonb)') is null then
    raise exception 'source recovery: apply workstream A''s shared contract (migration 20261104010000) first';
  end if;
  if to_regclass('pipeline.course_field_absence') is null or to_regclass('pipeline.source_proof_feed_runs') is null then
    raise exception 'source recovery: apply Release B (migration 20261103210000) first';
  end if;
  -- read against (not changed here)
  for r in select * from (values ('security.course_page_key_v1(uuid)', 'eed0e852746ed662c2a7df77dcd7f417'),
                                 ('security.source_proof_relink_asked_v1(uuid,timestamp with time zone)', '097641b28ede4fcf7a6dfa40a66012cf')) v(sig, m) loop
    if to_regprocedure(r.sig) is null then raise exception 'source recovery: % is missing', r.sig; end if;
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

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

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'relink.statuses', 'Relink: refused page states it tries',
  'course-relink (and the source-proof lane''s free route) builds candidate addresses for a course whose bound page is in one of these states. identity_mismatch: the reader found another course''s page. Adding identity_refused, page_refused, refused_host and not_course_page gives pages refused by the course page check (E16) the same free route; the reader''s identity check still decides every candidate.',
  'list', '["identity_mismatch"]'::jsonb, null, null, 'states', 1035, 'Source proof',
  'security.course_relink_statuses_v1 (course_relink_tick_v1, course_relink_provider_v1, source_proof_feed_v1, field_absence_recovery_refresh_v1)', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4): shared identity defect S3; ships today''s value'),
 ('pipeline', 'relink.slug_variants_on', 'Relink: match title variants to stored provider addresses',
  'On (1): a stored provider address (crawl lists, discovery links) is a candidate when its last part matches the course title without diacritics, apostrophes, "&" for "and", "(Level n)" or a bracketed qualifier, or when its stored page title is the course title. Off (0): the exact title only, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1036, 'Source proof', 'security.course_relink_provider_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 step 2 and 4): shared matching defect S5; ships off'),
 ('pipeline', 'relink.year_current_on', 'Relink: current handbook year for an older-year page',
  'On (1): when the course''s page address names a handbook year older than this year, the same address with this year is a candidate. Off (0): not tried.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1037, 'Source proof', 'security.course_relink_provider_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 step 3): canonical reconciliation S8; ships off'),
 ('pipeline', 'relink.stored_search_reuse_on', 'Relink: try candidates a previous course-page search left untried',
  'On (1): addresses a previous course-page search (paid, already stored) found but did not try are candidates, before any new search. Off (0): not tried.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1038, 'Source proof', 'security.course_relink_provider_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 step 6: existing Firecrawl evidence; never pay twice) S7; ships off'),
 ('pipeline', 'proof.absence_input_on', 'Source proof: also take open field absences without page proof',
  'On (1): besides courses the gap queue holds as waiting for page proof, the source-proof lane considers courses with an open absence in proof.absence_input_classes and no page proof row. Off (0): the gap queue''s courses only, as before.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1039, 'Source proof', 'security.source_proof_feed_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4): input gap S4; ships off'),
 ('pipeline', 'proof.absence_input_classes', 'Source proof: absence classes taken as input',
  'The absence classes (pipeline.field_absence_classes) whose open courses the source-proof lane considers when proof.absence_input_on is 1.',
  'list', '["identity_unresolved", "needs_source_discovery"]'::jsonb, null, null, 'classes', 1042, 'Source proof', 'security.source_proof_feed_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4): input gap S4'),
 ('pipeline', 'recovery.cohort_refresh_per_run', 'Recovery cohort: courses refreshed per run',
  'Job field-absence-recovery refreshes this many cohort courses a run, least recently refreshed first.',
  'number', to_jsonb(3000), 100, 40000, 'courses', 1043, 'Source proof', 'security.field_absence_recovery_refresh_v1 (job field-absence-recovery)', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1 cohort): bounded work'),
 ('pipeline', 'recovery.read_blocked_statuses', 'Recovery cohort: page states that need an authorised read',
  'A cohort course whose bound page is in one of these states after the reader''s tries needs an authorised page read (one Firecrawl page), not a course-page search.',
  'list', '["fetch_failed", "needs_render", "blocked", "robots_disallowed", "too_thin"]'::jsonb, null, null, 'states', 1044, 'Source proof',
  'security.field_absence_recovery_refresh_v1, security.field_absence_d1_decision_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1 cohort): S9'),
 ('pipeline', 'recovery.read_tries', 'Recovery cohort: reader tries before a page counts as blocked',
  'A bound page counts as needing an authorised read once the reader has tried it this many times (the read picker''s own limit).',
  'number', to_jsonb(3), 1, 10, 'tries', 1045, 'Source proof', 'security.field_absence_recovery_refresh_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1 cohort)'),
 ('pipeline', 'recovery.d1_history_days', 'D1 decision: history measured',
  'The D1 decision table measures credits per course and found and verified rates from course-page searches in this many days.',
  'number', to_jsonb(60), 7, 365, 'days', 1046, 'Source proof', 'security.field_absence_d1_decision_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1: incremental cost and expected benefit)'),
 ('pipeline', 'recovery.d1_read_credits', 'D1 decision: credits to read a found page',
  'Credits assumed for reading one found page when no read history exists in the window (a Firecrawl page read is about one credit).',
  'number', to_jsonb(1), 0, 10, 'credits', 1047, 'Source proof', 'security.field_absence_d1_decision_v1', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1)'),
 ('pipeline', 'ops.source_recovery_max_attempts', 'Remedy: source recovery refresh, most attempts per issue',
  'The operations controller runs the source recovery remedy at most this many times for one issue before it needs a governed decision.',
  'number', to_jsonb(5), 1, 20, 'attempts', 1048, 'Source proof', 'pipeline.ops_remedies rem_source_recovery_refresh (workstream A controller)', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §3: no indefinite retries)'),
 ('pipeline', 'ops.source_recovery_cooldown_hours', 'Remedy: source recovery refresh, hours between attempts',
  'Hours the operations controller waits between two runs of the source recovery remedy for one issue (pages need a read cycle to be proven).',
  'number', to_jsonb(6), 1, 168, 'hours', 1049, 'Source proof', 'pipeline.ops_remedies rem_source_recovery_refresh (workstream A controller)', 'CF-247 ops B (mandate 3 Nov 2026 15:37 §3)')
on conflict (toolset_key, key) do nothing;

-- 2. helpers -------------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_relink_statuses_v1() returns text[] language sql stable security definer set search_path to '' as $function$
  -- CF-247 ops B (S3): the refused page states course-relink tries (setting relink.statuses)
  select coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                    where s.toolset_key = 'pipeline' and s.key = 'relink.statuses' and jsonb_typeof(s.value) = 'array'), array['identity_mismatch'])
$function$;
revoke all on function security.course_relink_statuses_v1() from public, anon, authenticated;

create or replace function security.course_relink_url_norm_v1(p_url text) returns text language sql immutable set search_path to '' as $function$
  -- CF-247 ops B (S6): one form of an address for comparison: lower case, no scheme, no www, no fragment, no tracking parameters, no index
  -- page, no trailing slash
  select nullif(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           lower(btrim(coalesce(p_url, ''))), '#.*$', ''), '^[a-z]+://(www\.)?', ''), '[?&](utm_[a-z]+|gclid|fbclid)=[^&]*', '', 'g'),
           '/(index|default)\.(html?|aspx?|php)$', ''), '/+$', ''), '')
$function$;

create or replace function security.course_relink_url_seg_v1(p_url text) returns text language sql immutable set search_path to '' as $function$
  -- CF-247 ops B (S5): the last part of an address, without query, fragment, trailing slash or page suffix
  select regexp_replace(coalesce(substring(lower(coalesce(p_url, '')) from '/([^/?#]+)/?(?:[?#].*)?$'), ''), '\.(html?|aspx?|php)$', '')
$function$;

create or replace function security.course_relink_slugs_v1(p_title text) returns text[] language sql immutable set search_path to '' as $function$
  -- CF-247 ops B (S5): the address forms of a course title: as written; without diacritics and apostrophes, "&" read as "and" and an NZ
  -- "(Level n)" removed; the same without any bracketed qualifier; and, for register titles, without a trailing campus code (" - UBCO"), the
  -- word "degree", a repeated last phrase ("Civil Engineering Civil Engineering"), with "Field: Award" read as "Award Field". Forms of 10
  -- letters or fewer are left out (too general).
  with t as (select lower(coalesce(p_title, '')) t0),
  n as (select t0, regexp_replace(regexp_replace(replace(regexp_replace(translate(t0, 'āēīōūàáâäãçèéêëìíîïñòóôöõùúûüý', 'aeiouaaaaaceeeeiiiinooooouuuuy'),
                 '[''’`]', '', 'g'), '&', ' and '), '\s*\(level [0-9]+\)', '', 'g'), '\s+', ' ', 'g') t1 from t),
  m as (select n.*, btrim(regexp_replace(regexp_replace(regexp_replace(t1, '\s+-\s+[a-z]{2,6}$', ''), '\([^)]*\)|\mdegree\M', '', 'g'), '\s+', ' ', 'g')) t2 from n),
  r as (select m.*, regexp_replace(t2, '(\m[a-z0-9 ]+\M) \1$', '\1') t3, regexp_replace(t2, '^([^:]+):\s*(.+)$', '\2 \1') t4 from m),
  s as (select regexp_replace(regexp_replace(t0, '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') s0,
               regexp_replace(regexp_replace(t1, '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') s1,
               regexp_replace(regexp_replace(regexp_replace(t1, '\([^)]*\)', '', 'g'), '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') s2,
               regexp_replace(regexp_replace(t3, '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') s3,
               regexp_replace(regexp_replace(t4, '[^a-z0-9]+', '-', 'g'), '(^-|-$)', '', 'g') s4 from r)
  select coalesce(array_agg(distinct x) filter (where length(x) > 10), '{}') from s, unnest(array[s.s0, s.s1, s.s2, s.s3, s.s4]) x  -- fixed: the length relink has used since 18 Oct
$function$;

create or replace function security.course_relink_stored_untried_v1(p_course uuid) returns text[] language sql stable security definer set search_path to '' as $function$
  -- CF-247 ops B (S7): addresses a previous course-page search found for the course but did not try (paid evidence already stored), never a
  -- page already rejected or blocked for the course
  select coalesce(array_agg(z.u order by z.o), '{}') from (
    select c.u, c.o from pipeline.course_link_search s cross join lateral jsonb_array_elements_text(case when jsonb_typeof(s.candidates) = 'array' then s.candidates else '[]'::jsonb end) with ordinality c(u, o)
     where s.course_id = p_course and s.state in ('none', 'error', 'verified') and c.o > coalesce(s.cand_idx, 0)
       and not exists (select 1 from pipeline.page_rejections pr where pr.course_id = p_course and security.course_relink_url_norm_v1(pr.url) = security.course_relink_url_norm_v1(c.u))
       and not exists (select 1 from pipeline.course_page_blocks b where b.course_id = p_course and security.course_relink_url_norm_v1(b.url) = security.course_relink_url_norm_v1(c.u))) z
$function$;
revoke all on function security.course_relink_stored_untried_v1(uuid) from public, anon, authenticated;

create or replace function security.course_relink_year_url_v1(p_url text) returns text language sql stable set search_path to '' as $function$
  -- CF-247 ops B (S8): the address with an older handbook year in its path moved to the current year (null when it has none, or it is current)
  select case when y is not null and y < extract(year from now())::int
              then regexp_replace(p_url, '/' || y::text || '(/|$)', '/' || extract(year from now())::int::text || '\1') end
    from (select (substring(coalesce(p_url, '') from '/((?:19|20)[0-9]{2})(?:/|$)'))::int y) z
$function$;

-- 3. the D1 recovery cohort ----------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.field_absence_recovery (
  course_id uuid primary key references catalogue.courses(id) on delete cascade,
  provider_id uuid not null,
  cohort text not null default 'd1',
  entered_at timestamptz not null default now(),
  entered_route text,
  state text not null default 'needs_paid_discovery' check (state in ('recovered_free', 'waiting_current_work', 'waiting_layer4', 'locked', 'free_route_capacity',
    'free_route_refused_status', 'free_route_stored_search', 'free_route_provider_list', 'free_route_canonical_year', 'needs_authorised_read',
    'needs_paid_research', 'needs_paid_discovery')),
  step int check (step between 1 and 8),
  free_routes text[] not null default '{}',
  fingerprint text,
  fingerprint_changed_at timestamptz,
  state_changed_at timestamptz,
  refreshed_at timestamptz,
  searched_before boolean not null default false,
  search_credits numeric not null default 0,
  recovered_at timestamptz,
  filled_since_entry int not null default 0,
  open_absences int not null default 0,
  detail jsonb not null default '{}'::jsonb
);
comment on table pipeline.field_absence_recovery is 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4, the D1 special case): the persistent recovery cohort: every course the source-proof lane has held without a free route (no_route, exhausted, or waiting for free capacity), with its state (recovered free, waiting on current work, waiting on Layer 4, locked, a free route open by kind, needs an authorised page read, needs paid search again or for the first time), the discovery step reached (mandate §4 order 1-8), the free routes open, an evidence fingerprint (a course is tried again only when it changes), the paid search already spent and the fields filled since entry. Written by security.field_absence_recovery_refresh_v1 (job field-absence-recovery); read by security.field_absence_d1_decision_v1 and the view pipeline.field_absence_recovery_providers.';
alter table pipeline.field_absence_recovery enable row level security;
create index if not exists field_absence_recovery_state_idx on pipeline.field_absence_recovery (state, provider_id);
create index if not exists field_absence_recovery_refreshed_idx on pipeline.field_absence_recovery (refreshed_at nulls first);

create table if not exists pipeline.field_absence_recovery_runs (
  id bigserial primary key, run_at timestamptz not null default now(), outcome text not null check (outcome in ('done', 'idle')),
  entered int not null default 0, refreshed int not null default 0, state_changes int not null default 0, recovered int not null default 0,
  states jsonb not null default '{}'::jsonb, ms int);
comment on table pipeline.field_absence_recovery_runs is 'CF-247 ops B: every run of job field-absence-recovery (security.field_absence_recovery_refresh_v1): courses entered into the D1 recovery cohort, refreshed, whose state changed and newly recovered, the cohort by state after the run, and the run time.';
alter table pipeline.field_absence_recovery_runs enable row level security;
create index if not exists field_absence_recovery_runs_at_idx on pipeline.field_absence_recovery_runs (run_at desc);

-- the cohort classification of a set of courses (read-only; the refresh and the decision table use it)
create or replace function security.field_absence_recovery_classify_v1(p_courses uuid[]) returns table(course_id uuid, provider_id uuid, state text, step int, free_routes text[],
  fingerprint text, searched_before boolean, search_credits numeric, filled int, open_absences int, detail jsonb)
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 ops B (mandate 3 Nov 2026 15:37 §4): each course's recovery state in the mandated discovery order. Free routes are found from stored
-- evidence only: the course's untried paid-search candidates (step 6), its provider's stored addresses matching a title form (steps 2 and 4),
-- the current-year address of an older handbook page (step 3), a free relink not yet taken (step 2). Nothing is fetched, bound or spent.
declare v_rl text[] := security.course_relink_statuses_v1();
        v_blocked text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                                       where s.toolset_key = 'pipeline' and s.key = 'recovery.read_blocked_statuses' and jsonb_typeof(s.value) = 'array'),
                                     array['fetch_failed', 'needs_render', 'blocked', 'robots_disallowed', 'too_thin']);
        v_tries int := greatest(1, security.pipeline_num_v1('recovery.read_tries', 3)::int);
        v_refused text[] := array['identity_mismatch', 'identity_refused', 'page_refused', 'refused_host', 'not_course_page'];  -- fixed: the refusal states the reader and the E16 check write
begin
  return query
  -- the paid course-page searches already made, read once (pipeline.firecrawl_calls has no course index)
  with fc as materialized (
    select f.course_id, sum(f.credits_used) cr from pipeline.firecrawl_calls f
     where f.use_case = 'find_page' and f.course_id = any (p_courses) group by f.course_id),
  b as materialized (
    select c.id cid, c.provider_id pid, c.canonical_title, g.status gstatus, g.read_status, coalesce(g.read_attempts, 0) ra, g.url page_url,
           coalesce(pp.proven, false) proven, pp.page_key, s.state sstate, x.state rstate, coalesce(jsonb_array_length(case when jsonb_typeof(x.candidates) = 'array' then x.candidates end), 0) rcands,
           q.state qstate,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_id = c.id and i.field_code = 'official_course_url' and i.status = 'pending') l4,
           exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field in ('official_url', 'course_url', 'all')) locked,
           coalesce(fc.cr, 0) paid, fc.course_id is not null paid_before,
           security.course_relink_stored_untried_v1(c.id) stored,
           security.course_relink_slugs_v1(c.canonical_title) slugs
      from unnest(p_courses) u(id) join catalogue.courses c on c.id = u.id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.course_page_proofs pp on pp.course_id = c.id
      left join pipeline.course_link_search s on s.course_id = c.id
      left join pipeline.course_relink x on x.course_id = c.id
      left join pipeline.source_proof_requests q on q.course_id = c.id
      left join fc on fc.course_id = c.id),
  -- the provider's stored addresses, read once per provider (crawl lists and discovery links), keyed by last part and by stored title
  u as materialized (
    select l.provider_id, l.url, security.course_relink_url_seg_v1(l.url) seg,
           lower(btrim(split_part(split_part(coalesce(l.title, ''), ' | ', 1), ' - ', 1))) tnorm
      from (select pu.provider_id, pu.url, pu.title from pipeline.coverage_provider_urls pu where pu.provider_id in (select distinct b.pid from b)
            union select dl.provider_id, dl.url, dl.anchor_text from pipeline.provider_discovery_links dl where dl.provider_id in (select distinct b.pid from b)) l),
  hit as (
    select b.cid, u.url from b cross join lateral unnest(b.slugs) bs(slug) join u on u.provider_id = b.pid and u.seg = bs.slug
    union
    select b.cid, u.url from b join u on u.provider_id = b.pid and u.tnorm = lower(btrim(b.canonical_title)) where length(b.canonical_title) > 10),
  lm as (
    select b.cid, array_agg(distinct h.url order by h.url) urls
      from b join hit h on h.cid = b.cid
     where security.course_relink_url_norm_v1(h.url) is distinct from security.course_relink_url_norm_v1(b.page_url)
       and not exists (select 1 from pipeline.page_rejections pr where pr.course_id = b.cid and security.course_relink_url_norm_v1(pr.url) = security.course_relink_url_norm_v1(h.url))
       and not exists (select 1 from pipeline.course_relink x where x.course_id = b.cid and jsonb_typeof(x.candidates) = 'array'
                         and exists (select 1 from jsonb_array_elements_text(x.candidates) xc where security.course_relink_url_norm_v1(xc) = security.course_relink_url_norm_v1(h.url)))
     group by b.cid),
  f as (
    select b.*, coalesce(lm.urls, '{}') list_urls, security.course_relink_year_url_v1(b.page_url) year_url,
           (select count(*) from pipeline.field_enrich_items e join pipeline.field_absence_recovery fr on fr.course_id = e.course_id
             where e.course_id = b.cid and e.state in ('filled', 'review') and e.updated_at > fr.entered_at)::int filled,
           (select count(*) from pipeline.course_field_absence a where a.course_id = b.cid and a.resolved_at is null)::int open_abs
      from b left join lm on lm.cid = b.cid),
  r as (
    select f.*, array_remove(array[
             case when f.read_status = any (v_rl) and f.rstate is null then 'relink_capacity' end,
             case when f.read_status = any (v_refused) and not f.read_status = any (v_rl) and f.rstate is null then 'relink_refused_status' end,
             case when cardinality(f.stored) > 0 then 'stored_search' end,
             case when cardinality(f.list_urls) > 0 then 'provider_list' end,
             case when f.year_url is not null and f.read_status = any (v_refused) then 'canonical_year' end], null) routes
      from f)
  select r.cid, r.pid,
         case when r.proven then 'recovered_free'
              when r.l4 then 'waiting_layer4'
              when r.locked then 'locked'
              when r.rstate = 'trying' or r.sstate in ('queued', 'found') or r.qstate = 'queued'
                   or (r.gstatus in ('bound', 'ambiguous') and coalesce(r.read_status, '') in ('', 'deferred', 'fetch_failed', 'needs_render', 'blocked') and r.ra < v_tries) then 'waiting_current_work'
              when 'relink_capacity' = any (r.routes) then 'free_route_capacity'
              when 'relink_refused_status' = any (r.routes) then 'free_route_refused_status'
              when 'stored_search' = any (r.routes) then 'free_route_stored_search'
              when 'provider_list' = any (r.routes) then 'free_route_provider_list'
              when 'canonical_year' = any (r.routes) then 'free_route_canonical_year'
              when r.gstatus in ('bound', 'ambiguous') and r.read_status = any (v_blocked) then 'needs_authorised_read'
              when r.paid_before then 'needs_paid_research'
              else 'needs_paid_discovery' end,
         case when r.proven then null
              when 'relink_capacity' = any (r.routes) or 'relink_refused_status' = any (r.routes) then 2
              when 'canonical_year' = any (r.routes) and not ('stored_search' = any (r.routes) or 'provider_list' = any (r.routes)) then 3
              when 'provider_list' = any (r.routes) then 4
              when 'stored_search' = any (r.routes) then 6
              when r.gstatus in ('bound', 'ambiguous') and r.read_status = any (v_blocked) then 6
              else 8 end,
         r.routes,
         md5(concat_ws('|', r.page_key, array_to_string(r.stored, ' '), array_to_string(r.list_urls, ' '), r.year_url)),  -- inputs only: a lane's own outcome never re-triggers it
         r.paid_before, r.paid, r.filled, r.open_abs,
         jsonb_build_object('read_status', r.read_status, 'page_status', r.gstatus, 'relink', r.rstate, 'search', r.sstate,
                            'stored_candidates', cardinality(r.stored), 'list_candidates', cardinality(r.list_urls), 'year_url', r.year_url)
    from r;
end $function$;
revoke all on function security.field_absence_recovery_classify_v1(uuid[]) from public, anon, authenticated;

create or replace function security.field_absence_recovery_refresh_v1() returns jsonb language plpgsql security definer set search_path to '' as $function$
-- CF-247 ops B (mandate 3 Nov 2026 15:37 §4, D1 cohort): job field-absence-recovery. Enters every course the source-proof lane holds without a
-- free route (no_route, exhausted, or held for free capacity) into the persistent cohort, then refreshes recovery.cohort_refresh_per_run courses,
-- least recently refreshed first: state, discovery step, free routes, evidence fingerprint, paid search already spent, fields filled since
-- entry. Records only: nothing is bound, read, searched or admitted.
declare v_n int := greatest(1, security.pipeline_num_v1('recovery.cohort_refresh_per_run', 3000)::int);
        v_t0 timestamptz := clock_timestamp(); v_in int; v_ids uuid[]; v_chg int := 0; v_rec int := 0; v_states jsonb;
begin
  insert into pipeline.field_absence_recovery(course_id, provider_id, entered_route, detail)
  select q.course_id, q.provider_id, q.route || case when q.route = 'relink' then ':' || q.state else '' end, jsonb_build_object('entered_from', q.detail)
    from pipeline.source_proof_requests q join catalogue.courses c on c.id = q.course_id
   where q.route in ('no_route', 'exhausted') or (q.route = 'relink' and q.state = 'held')
      or (q.route = 'relink' and q.state = 'done' and q.outcome in ('relink_absent', 'not_taken'))  -- relinked again and still no page
  on conflict (course_id) do nothing;
  get diagnostics v_in = row_count;
  v_ids := array(select fr.course_id from pipeline.field_absence_recovery fr order by fr.refreshed_at nulls first, fr.course_id limit v_n);
  with o as (select fr.course_id, fr.state, fr.recovered_at from pipeline.field_absence_recovery fr where fr.course_id = any (v_ids)),
  k as (select * from security.field_absence_recovery_classify_v1(v_ids)),
  u as (
    update pipeline.field_absence_recovery fr set
           state = k.state, step = k.step, free_routes = k.free_routes,
           state_changed_at = case when fr.state is distinct from k.state then now() else fr.state_changed_at end,
           fingerprint_changed_at = case when fr.fingerprint is distinct from k.fingerprint then now() else fr.fingerprint_changed_at end,
           fingerprint = k.fingerprint, searched_before = k.searched_before, search_credits = k.search_credits,
           recovered_at = case when k.state = 'recovered_free' then coalesce(fr.recovered_at, now()) else fr.recovered_at end,
           filled_since_entry = k.filled, open_absences = k.open_absences, detail = fr.detail || k.detail, refreshed_at = now()
      from k where fr.course_id = k.course_id
    returning fr.course_id, fr.state)
  select count(*) filter (where o.state is distinct from u.state), count(*) filter (where u.state = 'recovered_free' and o.recovered_at is null) into v_chg, v_rec
    from u join o on o.course_id = u.course_id;
  select coalesce(jsonb_object_agg(z.state, z.n), '{}'::jsonb) into v_states from (select fr.state, count(*) n from pipeline.field_absence_recovery fr group by 1) z;
  insert into pipeline.field_absence_recovery_runs(outcome, entered, refreshed, state_changes, recovered, states, ms)
  values (case when cardinality(v_ids) = 0 then 'idle' else 'done' end, v_in, cardinality(v_ids), v_chg, v_rec, v_states,
          (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds
  return jsonb_build_object('entered', v_in, 'refreshed', cardinality(v_ids), 'state_changes', v_chg, 'recovered', v_rec, 'states', v_states,
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds
end $function$;
revoke all on function security.field_absence_recovery_refresh_v1() from public, anon, authenticated;

create or replace view pipeline.field_absence_recovery_providers with (security_invoker = true) as
  -- CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1: estimated provider-level recovery yield)
  with rl as (select x.provider_id, count(*) filter (where x.state = 'found') found,
                     count(*) filter (where x.state in ('found', 'absent') and jsonb_typeof(x.candidates) = 'array' and jsonb_array_length(x.candidates) > 0) tried
                from pipeline.course_relink x group by 1),
  g as (select coalesce(sum(found)::numeric / nullif(sum(tried), 0), 0) rate from rl)
  select fr.provider_id, p.canonical_name provider, count(*) courses,
         count(*) filter (where fr.state = 'recovered_free') recovered_free,
         count(*) filter (where fr.state = 'waiting_current_work') waiting_current_work,
         count(*) filter (where fr.state = 'waiting_layer4') waiting_layer4,
         count(*) filter (where fr.state = 'locked') locked,
         count(*) filter (where fr.state like 'free_route_%') free_route_open,
         count(*) filter (where fr.state = 'needs_authorised_read') needs_authorised_read,
         count(*) filter (where fr.state = 'needs_paid_research') needs_paid_research,
         count(*) filter (where fr.state = 'needs_paid_discovery') needs_paid_discovery,
         round(coalesce(max(rl.found)::numeric / nullif(max(rl.tried), 0), max(g.rate)), 3) relink_found_rate,
         round(count(*) filter (where fr.state like 'free_route_%') * coalesce(max(rl.found)::numeric / nullif(max(rl.tried), 0), max(g.rate)), 1) est_free_recoveries,
         sum(fr.search_credits) paid_search_credits_spent, sum(fr.filled_since_entry) fields_filled_since_entry
    from pipeline.field_absence_recovery fr join catalogue.providers p on p.id = fr.provider_id
    left join rl on rl.provider_id = fr.provider_id cross join g
   group by fr.provider_id, p.canonical_name;
comment on view pipeline.field_absence_recovery_providers is 'CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1): the recovery cohort per provider: courses by state and the estimated free recoveries (free routes open times the provider''s measured relink found rate, or the platform rate when it has none).';
revoke all on pipeline.field_absence_recovery_providers from public, anon, authenticated;

create or replace function security.field_absence_d1_decision_v1() returns jsonb language plpgsql stable security definer set search_path to '' set statement_timeout to '30s' as $function$
-- CF-247 ops B (mandate 3 Nov 2026 15:37 §4 D1; Platform Admin D1 13:09: a quantified credit requirement and projected yield before any budget
-- request): the costed decision table for the cohort courses that still need paid discovery after the free routes, from measured history in
-- recovery.d1_history_days: credits per searched course (pipeline.firecrawl_calls, find_page), found rate (a search that found the course on the
-- provider's site), verified rate (pipeline.course_link_search verified) by search stage, read credits per page and the share of page reads
-- that read a course page (read_page; the expected yield of an authorised read of a known page). Courses
-- searched before are priced at the repeat rate (courses searched more than once). Read-only; D1 stays off.
declare v_since timestamptz := now() - make_interval(days => security.pipeline_num_v1('recovery.d1_history_days', 60)::int);
        v_read numeric; v_read_ok numeric; h jsonb; v_rows jsonb;
begin
  select coalesce(avg(f.credits_used) filter (where f.outcome like 'read_%'), security.pipeline_num_v1('recovery.d1_read_credits', 1)),
         coalesce(avg((f.outcome = 'read_course_page')::int), 0) into v_read, v_read_ok
    from pipeline.firecrawl_calls f where f.use_case = 'read_page' and f.at >= v_since;
  with fc as (select f.course_id, count(*) calls, sum(f.credits_used) cr, bool_or(f.outcome = 'found_on_provider_site') found,
                     count(distinct f.at::date) days
                from pipeline.firecrawl_calls f where f.use_case = 'find_page' and f.at >= v_since and f.course_id is not null group by 1),
  j as (select fc.*, coalesce(s.stage, 'title') stage, s.state = 'verified' verified from fc left join pipeline.course_link_search s on s.course_id = fc.course_id)
  select jsonb_object_agg(z.k, z.v) into h from (
    select j.stage k, jsonb_build_object('courses', count(*), 'credits_per_course', round(avg(j.cr), 2), 'found_rate', round(avg(j.found::int), 3),
                                         'verified_rate', round(avg(coalesce(j.verified, false)::int), 3)) v from j group by j.stage
    union all
    select 'repeat', jsonb_build_object('courses', count(*), 'credits_per_course', round(avg(j.cr), 2), 'found_rate', round(avg(j.found::int), 3),
                                        'verified_rate', round(avg(coalesce(j.verified, false)::int), 3)) from j where j.days > 1) z;
  with c as (select fr.*, case when c.course_code ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end stage  -- fixed: the CRICOS code form
               from pipeline.field_absence_recovery fr join catalogue.courses c on c.id = fr.course_id
              where fr.state in ('needs_paid_discovery', 'needs_paid_research', 'needs_authorised_read')),
  k as (select c.state, c.stage, count(*) n,
               case when c.state = 'needs_authorised_read' then v_read_ok  -- the page is known: the measured share of page reads that read a course page
                    when c.state = 'needs_paid_research' then coalesce((h->'repeat'->>'verified_rate')::numeric, 0)
                    else coalesce((h->c.stage->>'verified_rate')::numeric, 0) end vr,
               case when c.state = 'needs_authorised_read' then v_read
                    when c.state = 'needs_paid_research' then coalesce((h->'repeat'->>'credits_per_course')::numeric, (h->c.stage->>'credits_per_course')::numeric, 0)
                                                              + coalesce((h->'repeat'->>'found_rate')::numeric, 0) * v_read
                    else coalesce((h->c.stage->>'credits_per_course')::numeric, 0) + coalesce((h->c.stage->>'found_rate')::numeric, 0) * v_read end cpc,
               case when c.state = 'needs_authorised_read' then v_read_ok else coalesce((h->(case when c.state = 'needs_paid_research' then 'repeat' else c.stage end)->>'found_rate')::numeric, 0) end fr,
               count(distinct c.provider_id) providers
          from c group by c.state, c.stage)
  select coalesce(jsonb_agg(jsonb_build_object('state', k.state, 'stage', k.stage, 'courses', k.n, 'providers', k.providers,
           'credits_per_course', round(k.cpc, 2), 'credits_total', round(k.n * k.cpc), 'expected_found', round(k.n * k.fr), 'expected_verified', round(k.n * k.vr),
           'credits_per_verified', case when k.vr > 0 then round(k.cpc / k.vr, 1) end) order by k.state, k.stage), '[]'::jsonb) into v_rows from k;
  return jsonb_build_object('at', now(), 'history_since', v_since, 'history', h, 'read_credits_per_page', round(v_read, 2), 'read_course_page_rate', round(v_read_ok, 3), 'rows', v_rows,
    'cohort', (select coalesce(jsonb_object_agg(z.state, z.n), '{}'::jsonb) from (select fr.state, count(*) n from pipeline.field_absence_recovery fr group by 1) z),
    'paid_search_enabled', security.pipeline_num_v1('proof.search_per_run', 0) > 0);
end $function$;
revoke all on function security.field_absence_d1_decision_v1() from public, anon, authenticated;

-- the movement a remedy is judged by: pages proven, then fields filled (mandate §13: a job is not proof of enrichment)
create or replace function security.field_absence_recovery_measure_v1() returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('at', now(),
    'cohort', (select count(*) from pipeline.field_absence_recovery),
    'cohort_proven', (select count(*) from pipeline.field_absence_recovery fr join pipeline.course_page_proofs pp on pp.course_id = fr.course_id and pp.proven),
    'cohort_recovered', (select count(*) from pipeline.field_absence_recovery fr where fr.state = 'recovered_free'),
    'cohort_filled', (select coalesce(sum(fr.filled_since_entry), 0) from pipeline.field_absence_recovery fr),
    'needs_paid', (select count(*) from pipeline.field_absence_recovery fr where fr.state in ('needs_paid_discovery', 'needs_paid_research')),
    'proven_pages', (select count(*) from pipeline.course_page_proofs pp where pp.proven))
$function$;
revoke all on function security.field_absence_recovery_measure_v1() from public, anon, authenticated;

create or replace function security.field_absence_recovery_action_v1(p_issue bigint) returns jsonb language plpgsql security definer set search_path to '' as $function$
-- CF-247 ops B: action of remedy rem_source_recovery_refresh (authority auto): measure, refresh the cohort (records only), report the change.
declare v_before jsonb := security.field_absence_recovery_measure_v1(); v_r jsonb;
begin
  v_r := security.field_absence_recovery_refresh_v1();
  return jsonb_build_object('ok', true, 'changed', coalesce((v_r->>'state_changes')::int, 0) + coalesce((v_r->>'entered')::int, 0),
                            'evidence', jsonb_build_object('issue', p_issue, 'before', v_before, 'refresh', v_r));
end $function$;
revoke all on function security.field_absence_recovery_action_v1(bigint) from public, anon, authenticated;

create or replace function security.field_absence_recovery_verify_v1(p_issue bigint) returns jsonb language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 ops B: verify of the source recovery remedies. Passed only on real data movement since the remedy's first run for the issue: more
-- cohort pages proven, or more fields filled for cohort courses. A refresh that ran is not a pass.
declare v_before jsonb; v_after jsonb := security.field_absence_recovery_measure_v1(); v_dp int; v_df int;
begin
  select coalesce(x.before, x.evidence->'before') into v_before from pipeline.ops_remedy_runs x
   where x.issue_id = p_issue and x.remedy_code like 'rem_source_recovery%' order by x.started_at, x.id limit 1;
  if v_before is null or v_before->>'cohort_proven' is null then
    return jsonb_build_object('passed', false, 'measure', jsonb_build_object('after', v_after), 'evidence', 'no baseline: the remedy has not run for this issue');
  end if;
  v_dp := (v_after->>'cohort_proven')::int - (v_before->>'cohort_proven')::int;
  v_df := (v_after->>'cohort_filled')::int - (v_before->>'cohort_filled')::int;
  return jsonb_build_object('passed', v_dp > 0 or v_df > 0,
    'measure', jsonb_build_object('before', v_before, 'after', v_after, 'proven_delta', v_dp, 'filled_delta', v_df),
    'evidence', case when v_dp > 0 or v_df > 0 then format('%s cohort pages proven and %s fields filled since the first run', v_dp, v_df)
                     else 'no cohort page proven and no field filled since the first run' end);
end $function$;
revoke all on function security.field_absence_recovery_verify_v1(bigint) from public, anon, authenticated;

-- 4. md5-guarded edits of the live lane -----------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.source_proof_feed_v1()', 'cade6b2de219c216709129ce4bc447ff', '87278b507bcec288603d85c22d8da105', array[
  -- the page states with a free relink route, and the absence input switch
  [$o$        r record; v_route text;$o$,
   $n$        v_rl text[] := security.course_relink_statuses_v1();  -- CF-247 ops B (S3): relink.statuses
        v_abs boolean := security.pipeline_num_v1('proof.absence_input_on', 0) >= 1;
        v_abs_classes text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                                           where s.toolset_key = 'pipeline' and s.key = 'proof.absence_input_classes' and jsonb_typeof(s.value) = 'array'), '{}');
        r record; v_route text;$n$],
  -- S4: open absences without a proof row join the input (proof.absence_input_on); S1: a course held for free capacity is taken first
  [$o$        from pipeline.course_page_proofs pp
        join catalogue.courses c on c.id = pp.course_id and c.lifecycle_status = 'active'$o$,
   $n$        from (select p0.course_id, p0.page_key, p0.proven from pipeline.course_page_proofs p0
              union all
              select a.course_id, security.course_page_key_v1(a.course_id), false
                from (select distinct a0.course_id from pipeline.course_field_absence a0
                       where v_abs and a0.resolved_at is null and a0.absence_class = any (v_abs_classes)
                         and not exists (select 1 from pipeline.course_page_proofs p1 where p1.course_id = a0.course_id)) a) pp
        join catalogue.courses c on c.id = pp.course_id and c.lifecycle_status = 'active'$n$],
  [$o$       order by q.considered_at nulls first, pp.course_id$o$,
   $n$       order by coalesce(q.route = 'relink' and q.state = 'held', false) desc, q.considered_at nulls first, pp.course_id$n$],
  -- S7 and the recovery fingerprint: a course is tried again only when its candidate evidence changes
  [$o$           md5(concat_ws('|', w.page_key, p.lists, p.verified, p.recipe)) fp,$o$,
   $n$           md5(concat_ws('|', w.page_key, p.lists, p.verified, p.recipe, (select fr.fingerprint from pipeline.field_absence_recovery fr where fr.course_id = w.course_id))) fp,
           cardinality(security.course_relink_stored_untried_v1(w.course_id)) > 0 stored_untried,$n$],
  -- S1, S3 and S7: the free route by relink.statuses; beyond the run's free capacity the course waits for it (never no_route); paid search never
  -- for a course whose previous paid search left untried candidates
  [$o$      when r.read_status = 'identity_mismatch' and v_free > 0 then 'relink'
      when r.read_status = 'identity_mismatch' then 'no_route'
      when r.recipe is not null and v_paid > 0 and coalesce(r.sstate, 'none') in ('none', 'error') then 'search'$o$,
   $n$      when r.read_status = any (v_rl) and v_free > 0 then 'relink'
      when r.read_status = any (v_rl) then 'relink_wait'
      when r.recipe is not null and v_paid > 0 and coalesce(r.sstate, 'none') in ('none', 'error') and not r.stored_untried then 'search'$n$],
  [$o$      values (r.course_id, r.provider_id, v_route, case when v_act then 'queued' else 'held' end,$o$,
   $n$      values (r.course_id, r.provider_id, case when v_route = 'relink_wait' then 'relink' else v_route end, case when v_act then 'queued' else 'held' end,$n$],
  [$o$              case when v_act then now() end, null, null, now(), jsonb_build_object('read_status', r.read_status, 'search', r.sstate))$o$,
   $n$              case when v_act then now() end, null, null, now(), jsonb_build_object('read_status', r.read_status, 'search', r.sstate)
                                                                 || case when v_route = 'relink_wait' then '{"wait": "free_capacity"}'::jsonb else '{}'::jsonb end)$n$]
], array[1, 1, 1, 1, 1, 1, 1]);

select pg_temp.edit_once('security.course_relink_tick_v1(integer)', 'b159c75a0ed1517fc9305b62984aa141', '0cd20104a975c471ed4dd9060569f3b8', array[
  [$o$                where p.read_status = 'identity_mismatch' and not exists$o$,
   $n$                where p.read_status = any (security.course_relink_statuses_v1()) and not exists$n$]], array[1]);

select pg_temp.edit_once('security.course_relink_provider_v1(uuid,integer)', '8f2f82c7e2ad360a0ade7cdee1f63cce', '776844024ca5ee99011ad73dfd36360b', array[
  [$o$     where p.provider_id = p_provider_id and p.read_status = 'identity_mismatch'$o$,
   $n$     where p.provider_id = p_provider_id and p.read_status = any (security.course_relink_statuses_v1())$n$],
  [$o$      select distinct on (lower(q.url)) q.url, q.src, q.rk from ($o$,
   $n$      select distinct on (security.course_relink_url_norm_v1(q.url)) q.url, q.src, q.rk from ($n$],
  [$o$         where length(r.slug) > 10 and regexp_replace(substring(lower(l.url) from '/([^/?#]+)/?(?:[?#].*)?$'), '\.html?$', '') = r.slug) q
      where lower(q.url) <> lower(r.old_url)
        and not exists (select 1 from pipeline.course_page_blocks b where b.course_id = r.course_id and b.url = q.url)
      order by lower(q.url), q.rk) z;$o$,
   $n$         where length(r.slug) > 10 and regexp_replace(substring(lower(l.url) from '/([^/?#]+)/?(?:[?#].*)?$'), '\.html?$', '') = r.slug
        union all
        -- CF-247 ops B (S5, relink.slug_variants_on): title forms (diacritics, apostrophes, "&", "(Level n)", bracketed qualifiers) and stored page titles
        select l.url, 'url_list_variant', 3.5 from (
          select pu.url, pu.title from pipeline.coverage_provider_urls pu where pu.provider_id = p_provider_id
          union select dl.url, dl.anchor_text from pipeline.provider_discovery_links dl where dl.provider_id = p_provider_id) l,
          lateral (select c2.canonical_title t from catalogue.courses c2 where c2.id = r.course_id) ct
         where security.pipeline_num_v1('relink.slug_variants_on', 0) >= 1
           and (security.course_relink_url_seg_v1(l.url) = any (security.course_relink_slugs_v1(ct.t))
                or (length(ct.t) > 10 and lower(btrim(split_part(split_part(coalesce(l.title, ''), ' | ', 1), ' - ', 1))) = lower(btrim(ct.t))))
        union all
        -- CF-247 ops B (S8, relink.year_current_on): the refused page's address with the current handbook year
        select security.course_relink_year_url_v1(r.old_url), 'url_year', 2.4
         where security.pipeline_num_v1('relink.year_current_on', 0) >= 1 and security.course_relink_year_url_v1(r.old_url) is not null
        union all
        -- CF-247 ops B (S7, relink.stored_search_reuse_on): candidates a previous course-page search found and did not try (paid evidence, stored)
        select su.u, 'stored_search', 4 + su.o / 1000.0
          from unnest(security.course_relink_stored_untried_v1(r.course_id)) with ordinality su(u, o)
         where security.pipeline_num_v1('relink.stored_search_reuse_on', 0) >= 1) q
      where q.url is not null
        and security.course_relink_url_norm_v1(q.url) is distinct from security.course_relink_url_norm_v1(r.old_url)  -- CF-247 ops B (S6): the refused page in another spelling is not a candidate
        and not exists (select 1 from pipeline.course_page_blocks b where b.course_id = r.course_id and security.course_relink_url_norm_v1(b.url) = security.course_relink_url_norm_v1(q.url))
        and not exists (select 1 from pipeline.page_rejections pr where pr.course_id = r.course_id and security.course_relink_url_norm_v1(pr.url) = security.course_relink_url_norm_v1(q.url))
      order by security.course_relink_url_norm_v1(q.url), q.rk) z;$n$]
], array[1, 1, 1]);

-- 5. job field-absence-recovery (G1; its command has no number) -----------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('field-absence-recovery', 'Course pages', 50, 'Track the courses that need paid page search (D1 recovery cohort)',
  'Hourly at :26: every course the source-proof lane holds without a free route enters the D1 recovery cohort (pipeline.field_absence_recovery); recovery.cohort_refresh_per_run of them are refreshed: recovered without paid search, waiting on current work, waiting on Layer 4, locked, a free route open (relink capacity, a refused page state, stored search candidates, the provider''s stored addresses, the current handbook year), needing an authorised page read, or still needing paid search (again or for the first time). Records only: nothing is read, bound, searched or admitted. The costed D1 decision table is security.field_absence_d1_decision_v1().',
  4, false, 'pages')
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'field-absence-recovery') then
    perform cron.schedule('field-absence-recovery', '26 * * * *', $c$select security.field_absence_recovery_refresh_v1()$c$);
  end if;
end $j$;
update pipeline.automation_catalogue set description = description || ' A course beyond the run''s free capacity waits for it (route relink, held) instead of counting as needing paid search; the page states tried are relink.statuses; paid search is never queued for a course whose previous search left untried candidates (CF-247 ops B).'
 where jobname = 'source-proof-feed' and description not like '%CF-247 ops B%';
update pipeline.automation_catalogue set description = description || ' Candidates are compared in normalised form and never a page already rejected for the course; title variants, the current handbook year and a previous search''s untried candidates join when their settings are on (CF-247 ops B).'
 where jobname = 'course-relink' and description not like '%CF-247 ops B%';

-- 6. root causes and remedies (workstream A's contract) --------------------------------------------------------------------------------------
select security.ops_root_cause_register_v1(x.code, x.spec) from (values
 ('src_proof_capacity_overflow', jsonb_build_object('class', 'capacity', 'title', 'Free relink capacity recorded as needing paid search',
   'description', 'Courses with a free relink route beyond proof.feed_per_run were recorded no_route (the D1 measure). Fixed by migration 20261104030000: held as relink waiting for capacity.',
   'detect', jsonb_build_object('sql', 'select count(*) from pipeline.source_proof_requests q join pipeline.coverage_course_pages g on g.course_id = q.course_id where q.route = ''no_route'' and g.read_status = any (security.course_relink_statuses_v1())',
                                'evidence_at', '2026-11-03T15:43+11:00', 'count', 1625, 'relinked_before', 1625))),
 ('src_relink_refused_status', jsonb_build_object('class', 'rule', 'title', 'Pages refused by the E16 check have no free relink',
   'description', 'course-relink and the source-proof lane take only identity_mismatch; identity_refused, page_refused, refused_host and not_course_page pages never get candidates.',
   'detect', jsonb_build_object('sql', 'select g.read_status, count(*) from pipeline.coverage_course_pages g where g.read_status in (''identity_refused'', ''page_refused'', ''refused_host'', ''not_course_page'') and not exists (select 1 from pipeline.course_relink x where x.course_id = g.course_id) group by 1',
                                'evidence_at', '2026-11-03T15:44+11:00', 'counts', jsonb_build_object('identity_refused', 389, 'page_refused', 345, 'refused_host', 60, 'not_course_page', 16)))),
 ('src_feed_input_gap', jsonb_build_object('class', 'rule', 'title', 'Unresolved identities never reach the source-proof lane',
   'description', 'The lane reads only pipeline.course_page_proofs (the gap queue''s courses); open identity_unresolved and needs_source_discovery absences without a proof row are never routed.',
   'detect', jsonb_build_object('sql', 'select a.absence_class, count(distinct a.course_id) from pipeline.course_field_absence a where a.resolved_at is null and not exists (select 1 from pipeline.course_page_proofs pp where pp.course_id = a.course_id) group by 1',
                                'evidence_at', '2026-11-03T15:44+11:00', 'counts', jsonb_build_object('identity_unresolved', 2865, 'needs_source_discovery', 2987)))),
 ('src_title_slug_match', jsonb_build_object('class', 'rule', 'title', 'Stored provider addresses matched to the exact title slug only',
   'description', 'Diacritics, apostrophes, "&", NZ "(Level n)" and bracketed qualifiers stop a stored provider address matching its course.',
   'detect', jsonb_build_object('fn', 'security.field_absence_recovery_classify_v1 (free_route_provider_list)', 'evidence_at', '2026-11-03T15:46+11:00', 'courses_with_untried_list_match', 441, 'no_route_with_register_forms', 179))),
 ('src_url_normalisation', jsonb_build_object('class', 'rule', 'title', 'Candidate addresses compared by lower case only',
   'description', 'course-relink re-tried the refused page in another spelling (scheme, www, trailing slash, fragment) and pages already rejected for the course.',
   'detect', jsonb_build_object('evidence_at', '2026-11-03T15:49+11:00', 'refused_page_retried', 24, 'rejected_page_retried', 5))),
 ('src_paid_evidence_unused', jsonb_build_object('class', 'policy', 'title', 'Untried candidates of earlier paid searches',
   'description', 'Courses already searched (find_page) hold untried candidates; a new paid search would pay twice.',
   'detect', jsonb_build_object('fn', 'security.course_relink_stored_untried_v1', 'evidence_at', '2026-11-03T15:48+11:00', 'no_route_searched_before', 1887, 'with_untried_candidates', 634))),
 ('src_handbook_year', jsonb_build_object('class', 'data', 'title', 'Bound page is an older handbook year',
   'description', 'The page is refused only for its handbook year; the current-year address is a deterministic candidate.',
   'detect', jsonb_build_object('fn', 'security.course_relink_year_url_v1', 'evidence_at', '2026-11-03T15:45+11:00', 'old_year_refusals_identity_unresolved', 24))),
 ('src_read_blocked', jsonb_build_object('class', 'dependency', 'title', 'Known page whose direct read is blocked',
   'description', 'The course page is known but the direct read failed at the reader''s try limit; it needs an authorised page read, not a course-page search.',
   'detect', jsonb_build_object('fn', 'security.field_absence_recovery_classify_v1 (needs_authorised_read)'))),
 ('src_page_check_rule', jsonb_build_object('class', 'rule', 'title', 'Course page check refuses a read page with an identity proof',
   'description', 'security.course_page_check_v1 (E16, not owned by workstream B) refuses pages read with an identity proof: campus rule matching the provider''s own name (Durham College, UBC Vancouver), name rule on generic titles (AUT Arion pages with an NZQA code proof). Interface request to the E16 owner.',
   'detect', jsonb_build_object('evidence_at', '2026-11-03T15:45+11:00', 'refused_read_with_identity', 202, 'by_rule', jsonb_build_object('name', 69, 'shared_page', 47, 'old_year', 24, 'sibling', 23, 'variant', 20, 'campus', 13, 'level', 6))))
) x(code, spec);

select security.ops_remedy_register_v1(x.code, x.spec) from (values
 ('rem_source_recovery_refresh', jsonb_build_object('title', 'Refresh the D1 recovery cohort and measure movement',
   'treats', array['src_proof_capacity_overflow', 'src_feed_input_gap', 'src_paid_evidence_unused', 'src_read_blocked', 'src_title_slug_match', 'src_handbook_year', 'src_relink_refused_status'],
   'authority', 'auto', 'action_fn', 'security.field_absence_recovery_action_v1(bigint)', 'verify_fn', 'security.field_absence_recovery_verify_v1(bigint)',
   'max_attempts_key', 'ops.source_recovery_max_attempts', 'cooldown_key', 'ops.source_recovery_cooldown_hours', 'active', true,
   'notes', 'Records only (the cohort); the source-proof lane and course-relink act on the changed fingerprints by their own schedules. Verified by cohort pages proven, then fields filled.')),
 ('rem_relink_free_routes_on', jsonb_build_object('title', 'Switch on the free relink routes (statuses, title forms, handbook year, stored candidates, absence input)',
   'treats', array['src_relink_refused_status', 'src_title_slug_match', 'src_handbook_year', 'src_paid_evidence_unused', 'src_feed_input_gap'],
   'authority', 'admin', 'action_fn', null, 'verify_fn', 'security.field_absence_recovery_verify_v1(bigint)',
   'max_attempts_key', 'ops.source_recovery_max_attempts', 'cooldown_key', 'ops.source_recovery_cooldown_hours', 'active', true,
   'notes', 'A recorded setting change: relink.statuses, relink.slug_variants_on, relink.year_current_on, relink.stored_search_reuse_on, proof.absence_input_on.')),
 ('rem_relink_url_normalised', jsonb_build_object('title', 'Candidates compared in normalised form; rejected pages never candidates',
   'treats', array['src_url_normalisation', 'src_proof_capacity_overflow'],
   'authority', 'release', 'action_fn', null, 'verify_fn', 'security.field_absence_recovery_verify_v1(bigint)', 'active', true,
   'notes', 'Shipped in migration 20261104030000.')),
 ('rem_page_check_rules', jsonb_build_object('title', 'Course page check: campus and name rule corrections (E16 owner)',
   'treats', array['src_page_check_rule'], 'authority', 'release', 'action_fn', null, 'verify_fn', 'security.field_absence_recovery_verify_v1(bigint)', 'active', true,
   'notes', 'Interface request from workstream B; not built here.'))
) x(code, spec);

-- 7. component register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.field_absence_recovery', 'Layer 2', 'Course pages', 'The D1 recovery cohort: state, discovery step, free routes, fingerprint, paid search spent', 'active', '{}', '20261104030000'),
 ('table', 'pipeline.field_absence_recovery_runs', 'Layer 2', 'Course pages', 'Every run of job field-absence-recovery', 'active', '{}', '20261104030000'),
 ('view', 'pipeline.field_absence_recovery_providers', 'Layer 2', 'Course pages', 'The recovery cohort per provider with the estimated free recoveries', 'active', '{}', '20261104030000'),
 ('job', 'field-absence-recovery', 'Layer 2', 'Course pages', 'Refreshes the D1 recovery cohort hourly (records only)', 'active', '{}', '20261104030000')
on conflict do nothing;

-- 8. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'proof.search_per_run') <> 0 then
    raise exception 'source recovery post-check: proof.search_per_run must stay 0 (D1 off)'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('relink.slug_variants_on', 'relink.year_current_on',
        'relink.stored_search_reuse_on', 'proof.absence_input_on') and (value #>> '{}')::numeric = 0) <> 4 then
    raise exception 'source recovery post-check: a new free route did not ship off'; end if;
  if (select command from cron.job where jobname = 'field-absence-recovery') <> 'select security.field_absence_recovery_refresh_v1()' then
    raise exception 'source recovery post-check: job field-absence-recovery runs another command'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'field-absence-recovery') then
    raise exception 'source recovery post-check: job field-absence-recovery is not catalogued'; end if;
  if (select count(*) from pipeline.ops_remedies where code in ('rem_source_recovery_refresh', 'rem_relink_free_routes_on', 'rem_relink_url_normalised', 'rem_page_check_rules')) <> 4 then
    raise exception 'source recovery post-check: a remedy is not registered'; end if;
end $$;
