-- CF-247 StudySearch E16-1 and E16-2: a course page is bound or linked only when it is proved to be the course's own page.
-- Authority: Platform Admin 2 Nov 2026 07:21 (admin docs/platform/nz-enrichment-brief/2026-11-02-e16-final-disposition-decision.md §3):
--   "Prioritise E16-1 and extend the existing binding validation where necessary. The provider-course page matcher must verify: Exact
--   provider identity. Course code or approved equivalent identifier. Qualification level. Programme name. Award and credit-point variant.
--   Campus applicability where relevant. Domestic versus international audience. Handbook year or source validity. Programme-specific versus
--   shared-provider information. A matching domain or similar course title is insufficient. For shared pages, validate the exact section or
--   programme-specific evidence. Where identity cannot be proved, refuse automatic binding and route the exception through existing Layer 4
--   controls. Prevent downstream AI enrichment from reading a page with unsupported course identity."
--   E16-2 (decision pack 2 Nov 06:40): when no official link is primary, the projection no longer shows the most recently verified one.
-- Evidence: decision pack 2026-11-02-e16-sibling-variant-links-decision-pack.md and cohort ui-audit/e16-sibling-variant-cohort-2026-11-02.csv
--   (77 courses). Of the 77 links shown, 68 were written by the award-link lane (job exit-awards-apply, security.exit_awards_apply_v2,
--   Decision 254: a Graduate Certificate or Diploma takes its parent Master's page) and re-verified every hour at :37, which is why they are
--   the "most recently verified" link; 9 come from a page binding (pipeline.coverage_course_pages).
-- What:
--   * One check, security.course_page_check_v1(course, page address, page title, identity proof): verdict pass, refuse or unproven, with the
--     rule and a plain reason. Rules, in order: another provider's website; an older handbook year than the course already has, or older
--     than binding.handbook_max_age_years; a domestic page for an international course (or the reverse); a shared page (fee, application,
--     ESOS, course list, school international or ELICOS list page, or a page bound to other courses) unless an approved exception names this
--     course's own section; this course's own code (CRICOS, VET national code or another held identifier) in the address or title proves it;
--     another course's code refuses; a different qualification level (sibling award) unless an approved nested-award exception names this
--     award; a different award or credit-point variant; an address that is another course's at this provider; an address and title that do
--     not name the programme (a domain-only or similar-title match); another campus. With none of these, a read with an identity proof, a
--     page set by hand, or a person-confirmed link passes; anything else is unproven. Every word list and limit is a setting (G2).
--   * The existing binding guard (trigger coverage_page_refused_host on pipeline.coverage_course_pages, the SS-007 central point every binding
--     lane passes: site-map binder, course link search, search pass, re-identification, AI match, Firecrawl find, host pages, the reader)
--     runs the check whenever a page is bound or re-bound, first reads, or its identity proof changes. A refused page becomes 'mismatch' /
--     'identity_refused' with no identity, so it is not read, filled, AI-read or fee-read; one page_rejections row (source binding_check)
--     stops every lane binding it again; the existing Layer 4 course-link review (field official_course_url, kind course_link) gets one item,
--     unless the course already has a pending one or a person already decided that page (Decision 263). The trigger now also fires when only
--     identity_basis changes (host pages confirm a page that way).
--   * The award-link lane (security.exit_awards_apply_v2) passes through the same check instead of bypassing it. An exit or nested award
--     on its parent course's page is a possible genuine shared page: it passes only with programme-specific evidence (setting
--     binding.award_page_evidence: the parent page, or the exit award read from it, names this award; or a person recorded the award link
--     with evidence), never on a title match alone (integrator, 2 Nov 2026). The lane also honours the SS-007 remediation hold and the page
--     rejections and blocks (pipeline.page_rejections, pipeline.course_page_blocks), which it ignored before (USyd 000723J and 105221C,
--     UTS 114585M). A new link that fails is refused once (rejection + Layer 4); an award link already shown is left as it is and no longer
--     re-verified each hour: re-evaluating existing links is the separate governed §4 step.
--   * The binding guard also refuses, for every lane, a page already rejected or blocked for the course (read_status 'page_refused').
--   * AI enrichment (security.enrich_fields_slice_v1, source ai_stored) reads only a page that is read, has an identity proof and is not
--     refused by the check. The fee and tuition AI lanes already need an identity proof the refused page no longer has.
--   * Projection (search.refresh_course_enrichment_core_v1 and _scoped_v1), E16-2: one link, or a primary link, is shown as before. With
--     several active links and none primary, the link equal to courses.course_url is shown only when it passes the check; otherwise none (null).
--     Values change on those courses only; the consumer API shape does not (G3). Search documents follow at the next refresh.
-- md5 (before = live on 2 Nov 2026, rebuilt from this repository's migrations by tests/fixtures/e16-binding-validation/run.sh; after =
--   local replay on PostgreSQL 16):
--   security.coverage_page_refused_host_guard()                     33351b506da59359656ee196218d7882 -> f2e4102f8788816c3f22f26945785f55
--   security.exit_awards_apply_v2(uuid)                              8d4e5f7b2fedbe7c3e04ff8b039c40e7 -> e7080925ba79eef320f361bf236cb072
--   security.enrich_fields_slice_v1(uuid,integer)                    37b855677c98002ed2374f02cd1282f9 -> b677308fffdc23e5fbd2ad54d1b97d30
--   search.refresh_course_enrichment_core_v1(boolean)               ce80f74549625c23317aba5c737afda6 -> 6214bb43a019cf30a94cf12354579eb2
--   search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean) 3f0b051fdc0e8c34f757f8c21ff5b7d3 -> 82cc2006ba8447a5f23ca726b691c140
-- No existing binding, link, fee, value or Layer 4 item is changed by this migration. Nothing is re-evaluated (that is §4). No job, schedule
--   or status value is added. A passing test switches nothing on.
-- Rollback: re-apply the before definitions (the same edits reversed) and set binding.identity_check to 0; rejections and Layer 4 items
--   written after the release stay as records.
-- Replaces: security.coverage_page_refused_host_guard, security.exit_awards_apply_v2, security.enrich_fields_slice_v1, search.refresh_course_enrichment_core_v1, search.refresh_course_enrichment_core_scoped_v1 (same names; md5-guarded edits); trigger coverage_page_refused_host (same name; also on identity_basis)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No consumer API function, table or column is altered (G3).

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

-- 1. Settings (G2): every word list and limit the check uses ------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'binding.identity_check', 'Course page check: on',
  'Every automatic course page binding and award link is checked against the course (provider, code, level, programme, award and credit variant, campus, audience, handbook year, shared page). A page that fails is not bound, is not read by the AI, and goes to Layer 4 Review as a course link item. Switch off only to stop the check in an emergency.',
  'number', '1'::jsonb, 0, 1, 'on/off', 319, 'Course pages',
  'trigger coverage_page_refused_host, security.exit_awards_apply_v2, security.enrich_fields_slice_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): refuse automatic binding where identity cannot be proved'),
 ('pipeline', 'binding.level_patterns', 'Course page check: qualification levels',
  'LEVEL=pattern pairs (regular expressions, case ignored). The levels named by the course title and level, and by the page address and title, must share one. A page that names only another level (a Master''s page for a Graduate Certificate) is refused.',
  'list', '["GC=graduate[-_ ]?cert(ificate)?s?\\M|\\mgrad[-_ ]?cert|(^|/)gc-[a-z]|[-/]gc[0-9]{3}([-/]|$)", "GD=graduate[-_ ]?dip(loma)?s?\\M|\\mgrad[-_ ]?dip|(^|/)gd-[a-z]|[-/]gd[0-9]{3}([-/]|$)", "PGC=post[-_ ]?graduate[-_ ]?cert(ificate)?\\M|\\mpg[-_ ]?cert", "PGD=post[-_ ]?graduate[-_ ]?dip(loma)?\\M|\\mpg[-_ ]?dip", "M=\\mmasters?\\M|\\mmba\\M|(^|/)m[cr]-[a-z]|[-/]m[cr][0-9]{3}([-/]|$)", "B=\\mbachelors?\\M|(^|/)b-[a-z]", "D=\\mdoctor(ate|al)?\\M|\\mph\\.?d\\M", "AD=associate[-_ ]degree", "ADV=advanced[-_ ]diploma", "DIP=(?<!graduate[-_ ])(?<!advanced[-_ ])(?<!grad[-_ ])\\mdiploma\\M", "C4=certificate[-_ ](iv|4)\\M", "C3=certificate[-_ ](iii|3)\\M", "C2=certificate[-_ ](ii|2)\\M", "C1=certificate[-_ ](i|1)\\M"]'::jsonb,
  null, null, 'patterns', 320, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): qualification level'),
 ('pipeline', 'binding.variant_markers', 'Course page check: award variants',
  'Patterns (regular expressions, case ignored) for award variants. A page whose address or title names a variant the course title does not (Honours, Advanced, Professional, Extended, Research) is another version of the award and is refused.',
  'list', '["\\mhonours\\M|\\mhons\\M", "\\madvanced\\M(?![-_ ]diploma)", "\\mprofessional\\M(?![-_ ]doctor)", "\\mextended\\M", "\\mresearch\\M", "\\maccelerated\\M", "\\mfast[-_ ]?track\\M", "\\mgraduate[-_ ]entry\\M"]'::jsonb,
  null, null, 'patterns', 321, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): award and credit-point variant'),
 ('pipeline', 'binding.name_stop_words', 'Course page check: words that do not name a programme',
  'Words left out when the page address and title are compared with the programme name (level words, site words). A page whose remaining words share none with the course title is refused.',
  'list', '["the", "and", "for", "with", "from", "into", "our", "your", "are", "all", "study", "studies", "course", "courses", "program", "programs", "programme", "programmes", "degree", "degrees", "award", "awards", "master", "masters", "bachelor", "bachelors", "graduate", "graduates", "postgraduate", "undergraduate", "certificate", "certificates", "diploma", "diplomas", "associate", "advanced", "honours", "hons", "doctor", "doctorate", "coursework", "research", "level", "levels", "international", "domestic", "student", "students", "overview", "outcomes", "details", "entry", "requirements", "fees", "fee", "apply", "application", "how", "about", "handbook", "home", "index", "html", "htm", "php", "aspx", "www", "find", "search", "online", "campus", "page", "info", "information", "year", "years", "full", "time", "part", "credit", "credits", "points", "point", "university", "college", "institute", "school"]'::jsonb,
  null, null, 'words', 322, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): programme name; a domain-only or similar-title match is insufficient'),
 ('pipeline', 'binding.name_min_tokens', 'Course page check: words needed to judge the programme name',
  'The page address and title must leave at least this many programme words before a page is refused for not naming the programme. An address made only of codes is not judged by name.',
  'number', '2'::jsonb, 1, 5, 'words', 323, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): programme name'),
 ('pipeline', 'binding.name_stem_chars', 'Course page check: letters compared in a word',
  'Two words count as the same when their first letters, up to this many, agree (accounting and accountancy).',
  'number', '5'::jsonb, 3, 10, 'letters', 324, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): programme name'),
 ('pipeline', 'binding.shared_page_patterns', 'Course page check: shared pages',
  'Patterns (regular expressions, case ignored) for the last part of an address that is never one course''s page: fee, application, enrolment and ESOS pages, course lists, school international pages, English course lists.',
  'list', '["/(fees?|tuition|costs?|scholarships?)(-and-[a-z-]+)?/?$", "/(how-to-)?appl(y|ication|ications)(-[a-z-]+)?/?$", "/(enrol|enrolment|enrollment|enrolments)(-[a-z-]+)?/?$", "/esos(-[a-z-]+)?/?$", "/(courses?|programs?|programmes?|study-areas?|course-list|all-courses|find-a-course)/?$", "/international(-students?)?/?$", "/(elicos|english-courses?|english-language-courses?)/?$"]'::jsonb,
  null, null, 'patterns', 325, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): programme-specific versus shared-provider information (SS-007 classes A to E)'),
 ('pipeline', 'binding.shared_page_min_other_courses', 'Course page check: other courses that make a page shared',
  'A page bound to at least this many other courses of the provider is shared (a school''s international page for its year levels, one page for several English levels, one page for a master, its 180 and 240 point versions and certificate).',
  'number', '2'::jsonb, 1, 20, 'courses', 326, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): shared pages (SS-007: 3 or more courses)'),
 ('pipeline', 'binding.handbook_max_age_years', 'Course page check: oldest handbook year',
  'A page whose address names a handbook year older than this many years before the current year is refused, as is a year older than the course''s own page already shows.',
  'number', '2'::jsonb, 0, 10, 'years', 327, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): handbook year or source validity'),
 ('pipeline', 'binding.domestic_page_patterns', 'Course page check: domestic student pages',
  'Patterns (regular expressions, case ignored) for a page address meant for domestic students. It is refused for a course open to international students and not to domestic ones.',
  'list', '["/domestic(/|-|$)", "/(local|domestic|australian|nz|new-zealand)-students?(/|$)", "[?&](student[-_]?type|audience|studenttype)=domestic"]'::jsonb,
  null, null, 'patterns', 328, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): domestic versus international audience'),
 ('pipeline', 'binding.international_page_patterns', 'Course page check: international student pages',
  'Patterns (regular expressions, case ignored) for a page address meant for international students. It is refused for a course open to domestic students and not to international ones.',
  'list', '["/international(/|-|$)", "/international-students?(/|$)", "[?&](student[-_]?type|audience|studenttype)=international"]'::jsonb,
  null, null, 'patterns', 329, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): domestic versus international audience'),
 ('pipeline', 'binding.award_page_evidence', 'Course page check: evidence that lets an award use the parent course page',
  'A Graduate Certificate, Graduate Diploma or other exit or nested award may use the page of the longer course it sits within only with programme-specific evidence: page_names_award (the parent page, or the exit award read from it, names this award as available within the course) and recorded_by_hand (a person recorded the award link, with evidence). Remove a kind to stop accepting it. A title match alone is never enough.',
  'list', '["page_names_award", "recorded_by_hand"]'::jsonb, null, null, 'kinds', 331, 'Course pages', 'security.course_page_check_v1, security.exit_awards_apply_v2', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21; integrator 2 Nov: an exit or nested award on its parent page is a possible genuine shared page, allowed only with programme-specific evidence)'),
 ('pipeline', 'binding.identity_exceptions', 'Course page check: approved shared and nested-award pages',
  'Approved exceptions, one per line as provider id|kind|address pattern, kind shared_page or nested_award (for example 1719c3ba-…|shared_page|/programmes/master-of-applied-management). A matching page passes only when it also names this course''s own section or award (its title, code or section). Add a line only with a Platform Admin decision.',
  'list', '[]'::jsonb, null, null, 'exceptions', 330, 'Course pages', 'security.course_page_check_v1', 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): genuine shared-page and nested-award exceptions')
on conflict (toolset_key, key) do nothing;

-- 2. The check --------------------------------------------------------------------------------------------------------------------------
create or replace function security.course_page_check_v1(p_course uuid, p_url text, p_title text default null, p_identity text default null)
returns jsonb language sql stable security definer set search_path to '' as $function$
  with s as (
    select coalesce(security.toolset_setting('pipeline', 'binding.level_patterns'), '[]'::jsonb) lv,
           coalesce(security.toolset_setting('pipeline', 'binding.variant_markers'), '[]'::jsonb) vm,
           coalesce(security.toolset_setting('pipeline', 'binding.name_stop_words'), '[]'::jsonb) sw,
           coalesce(security.toolset_setting('pipeline', 'binding.shared_page_patterns'), '[]'::jsonb) sp,
           coalesce(security.toolset_setting('pipeline', 'binding.domestic_page_patterns'), '[]'::jsonb) dp,
           coalesce(security.toolset_setting('pipeline', 'binding.international_page_patterns'), '[]'::jsonb) ip,
           coalesce(security.toolset_setting('pipeline', 'binding.identity_exceptions'), '[]'::jsonb) ex,
           coalesce(security.toolset_setting('pipeline', 'binding.award_page_evidence'), '[]'::jsonb) ae,
           security.pipeline_num_v1('binding.name_min_tokens', 2) min_tok,
           security.pipeline_num_v1('binding.name_stem_chars', 5)::int stem,
           security.pipeline_num_v1('binding.shared_page_min_other_courses', 2) min_other,
           security.pipeline_num_v1('binding.handbook_max_age_years', 2) max_age),
  c as (
    select co.id, co.provider_id, co.canonical_title ctitle, security.course_title_key(co.canonical_title) tk,
           lower(co.canonical_title) || ' ' || coalesce(replace(sl.code, '_', ' '), '') ltext, co.course_url,
           co.open_to_international, co.open_to_domestic,
           regexp_replace(lower(coalesce(substring(pr.website from '^https?://([^/?#:]+)'), '')), '^www\.', '') phost
      from catalogue.courses co join catalogue.providers pr on pr.id = co.provider_id left join ref.study_levels sl on sl.id = co.study_level_id
     where co.id = p_course),
  u as (
    select lower(coalesce(p_url, '')) url,
           lower(coalesce(substring(p_url from '^https?://[^/?#]+(/[^?#]*)'), '/')) path,
           regexp_replace(lower(coalesce(substring(p_url from '^https?://([^/?#:]+)'), '')), '^www\.', '') host,
           lower(coalesce(substring(p_url from '#(.*)$'), '')) frag,
           lower(coalesce(nullif(btrim(p_title), ''),
             (select coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1') from pipeline.coverage_course_pages g join c on g.provider_id = c.provider_id
               where (g.url = p_url or g.candidates->>'final_url' = p_url) and g.read_status = 'read'
                 and coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1') is not null limit 1), '')) title),
  x as (
    select u.*,
           coalesce((select string_agg(seg, ' ' order by o) from (select seg, o from unnest(array_remove(string_to_array(u.path, '/'), '')) with ordinality q(seg, o) order by o desc limit 2) z), '') tail,
           coalesce((select seg from unnest(array_remove(string_to_array(u.path, '/'), '')) with ordinality q(seg, o) order by o desc limit 1), '') lastseg
      from u),
  t as (
    select x.*, c.*,
           btrim(regexp_replace(x.tail || ' ' || x.title, '[^a-z0-9]+', ' ', 'g')) tail_text,
           -- the award variant is judged on the page's own segment and title only, not on a section of the site (higher-degrees-by-research)
           btrim(regexp_replace(x.lastseg || ' ' || x.title, '[^a-z0-9]+', ' ', 'g')) var_text,
           regexp_split_to_array(x.path || ' ' || x.frag || ' ' || x.title, '[^a-z0-9]+') tokens,
           regexp_replace(x.lastseg, '[^a-z0-9]+', '-', 'g') slug
      from x, c),
  k as (
    select coalesce(array_agg(distinct lower(v)) filter (where v ~ '[A-Za-z]' and v ~ '[0-9]'), '{}') own
      from (select co.course_code v from catalogue.courses co where co.id = p_course
            union all select i.identifier from catalogue.course_identifiers i where i.course_id = p_course
            union all select o.vet_national_code from catalogue.course_regulatory_observations o where o.course_id = p_course and o.vet_national_code is not null) z),
  lv as (
    select array(select distinct split_part(e, '=', 1) from s, t, jsonb_array_elements_text(s.lv) e where t.ltext ~* substr(e, strpos(e, '=') + 1) order by 1) course_lv,
           array(select distinct split_part(e, '=', 1) from s, t, jsonb_array_elements_text(s.lv) e where (t.path || ' ' || t.title) ~* substr(e, strpos(e, '=') + 1) order by 1) page_lv),
  vm as (
    select array(select e from s, t, jsonb_array_elements_text(s.vm) e where t.var_text ~* e and not t.ltext ~* e) page_only,
           (select substring(t.var_text from '([0-9]{2,3}) ?(credit|point|pt)') from t) page_credit,
           (select substring(t.ltext from '([0-9]{2,3}) ?(credit|point|pt)') from t) course_credit),
  nm as (
    -- fixed: words of one or two letters carry no programme name
    select array(select distinct w from s, t, regexp_split_to_table(t.tail_text, '[^a-z]+') w where length(w) >= 3 and not s.sw ? w) page_tok,
           array(select distinct w from s, t, regexp_split_to_table(lower(t.ctitle), '[^a-z]+') w where length(w) >= 3 and not s.sw ? w) course_tok),
  yr as (
    select (select max(m[1]::int) from t, regexp_matches(t.path, '/((?:19|20)[0-9]{2})(?=/|$)', 'g') m) page_year,
           (select max(m[1]::int) from (select l.url from catalogue.course_links l where l.course_id = p_course and l.link_type = 'official_course' and l.status = 'active'
                                         union all select c.course_url from c
                                         union all select g.url from pipeline.coverage_course_pages g where g.course_id = p_course and g.status in ('bound', 'ambiguous')) z(url),
                   regexp_matches(lower(regexp_replace(coalesce(z.url, ''), '^https?://[^/?#]+', '')), '/((?:19|20)[0-9]{2})(?=/|$)', 'g') m) cur_year),
  sh as (
    select count(*) n_other, count(*) filter (where security.course_title_key(o.canonical_title) <> c.tk) n_diff
      from c join pipeline.coverage_course_pages g on g.provider_id = c.provider_id and g.course_id <> c.id and g.status in ('bound', 'ambiguous')
                                    and split_part(g.url, '#', 1) = split_part(p_url, '#', 1)  -- a section of a page is still that page
      join catalogue.courses o on o.id = g.course_id and o.lifecycle_status = 'active'),
  sib as (
    select (select o.canonical_title from t, catalogue.courses o
             where o.provider_id = t.provider_id and o.id <> t.id and o.lifecycle_status = 'active' and security.course_title_key(o.canonical_title) <> t.tk
               and t.slug like replace(security.course_title_key(o.canonical_title), ' ', '-') || '%'
               and length(security.course_title_key(o.canonical_title)) > case when t.slug like replace(t.tk, ' ', '-') || '%' then length(t.tk) else 0 end
             order by length(o.canonical_title) desc limit 1) other_title),
  cp as (
    select (select k2.name from t, catalogue.campuses k2
             where k2.provider_id = t.provider_id and k2.status = 'active' and btrim(coalesce(k2.name, '')) <> ''
               and exists (select 1 from catalogue.course_campuses cc where cc.course_id = t.id)
               and not exists (select 1 from catalogue.course_campuses cc where cc.course_id = t.id and cc.campus_id = k2.id)
               and position(' ' || security.course_title_key(k2.name) || ' ' in ' ' || t.tail_text || ' ') > 0
               and position(security.course_title_key(k2.name) in t.tk) = 0
               and not exists (select 1 from catalogue.course_campuses cc join catalogue.campuses k3 on k3.id = cc.campus_id
                                where cc.course_id = t.id and position(' ' || security.course_title_key(k3.name) || ' ' in ' ' || t.tail_text || ' ') > 0)
             limit 1) other_campus),
  ev as (
    select
      (t.host <> '' and t.phost <> '' and not (t.host = t.phost or t.host like '%.' || t.phost)
       and exists (select 1 from catalogue.providers o, lateral (select regexp_replace(lower(coalesce(substring(o.website from '^https?://([^/?#:]+)'), '')), '^www\.', '') b) ob
                    where o.id <> t.provider_id and ob.b <> '' and (t.host = ob.b or t.host like '%.' || ob.b))) other_provider,
      (t.open_to_international is true and t.open_to_domestic is not true and exists (select 1 from s, jsonb_array_elements_text(s.dp) e where t.url ~* e)) domestic_page,
      (t.open_to_domestic is true and t.open_to_international is false and exists (select 1 from s, jsonb_array_elements_text(s.ip) e where t.url ~* e)) international_page,
      (exists (select 1 from s, jsonb_array_elements_text(s.sp) e where t.path ~* e) or sh.n_other >= s.min_other) shared,
      (t.tokens && k.own) own_code,
      exists (select 1 from catalogue.course_identifiers i where i.provider_id = t.provider_id and i.course_id <> t.id and lower(i.identifier) = any (t.tokens)
                 and i.identifier ~ '[A-Za-z]' and i.identifier ~ '[0-9]' and not lower(i.identifier) = any (k.own)) other_code,
      -- the page names this course's own section or award (title, code or section), needed for an approved exception
      (t.tokens && k.own
       or position(' ' || t.tk || ' ' in ' ' || security.course_title_key(t.frag || ' ' || t.title) || ' ') > 0
       or (t.frag <> '' and security.course_title_key(t.frag) = t.tk)
       ) names_course,
      -- an exit or nested award on its parent course's page: programme-specific evidence only (binding.award_page_evidence), never a title match
      ((s.ae ? 'page_names_award'
        and (exists (select 1 from pipeline.coverage_course_pages g where g.provider_id = t.provider_id and g.url = p_url and g.course_id <> t.id
                       and position(' ' || t.tk || ' ' in ' ' || security.course_title_key(g.candidates->'adapter_extra'->>'exit_awards') || ' ') > 0)
             or exists (select 1 from pipeline.course_exit_awards a where a.child_course_id = t.id and a.page_url = p_url and a.active and a.link_type = 'exit_award'
                          and a.evidence_id is not null and position(' ' || t.tk || ' ' in ' ' || security.course_title_key(a.printed) || ' ') > 0)))
       or (s.ae ? 'recorded_by_hand'
           and exists (select 1 from pipeline.course_exit_awards a where a.child_course_id = t.id and a.page_url = p_url and a.active and a.set_by = 'hand' and a.evidence_id is not null))) award_evidence,
      (select array_agg(distinct split_part(e, '|', 2)) from s, jsonb_array_elements_text(s.ex) e
        where split_part(e, '|', 1) = t.provider_id::text and p_url ~* substr(e, length(split_part(e, '|', 1)) + length(split_part(e, '|', 2)) + 3)) exceptions,
      (cardinality(lv.page_lv) > 0 and cardinality(lv.course_lv) > 0 and not lv.page_lv && lv.course_lv) other_level,
      (cardinality(vm.page_only) > 0 or (vm.page_credit is not null and vm.course_credit is not null and vm.page_credit <> vm.course_credit)) other_variant,
      (cardinality(nm.page_tok) >= s.min_tok and cardinality(nm.course_tok) > 0
       and not exists (select 1 from unnest(nm.page_tok) a, unnest(nm.course_tok) b where left(a, s.stem) = left(b, s.stem))) other_name,
      (p_identity is not null
       or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = t.id and (g.url = p_url or g.candidates->>'final_url' = p_url)
                    and g.read_status = 'read' and g.identity_basis is not null)
       or (t.course_url = p_url and exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = t.id and m.field in ('official_url', 'course_url')))
       or exists (select 1 from catalogue.course_links l join pipeline.sources so on so.id = l.source_id
                   where l.course_id = t.id and l.url = p_url and l.link_type = 'official_course' and l.status = 'active' and so.source_type in ('layer4_human_review', 'manual_entry'))) proved,
      t.host, t.title, lv.course_lv, lv.page_lv, vm.page_only, vm.page_credit, vm.course_credit, yr.page_year, yr.cur_year, sh.n_other, sh.n_diff,
      sib.other_title, cp.other_campus, s.max_age
    from t, s, k, lv, vm, nm, yr, sh, sib, cp),
  v as (
    select ev.*,
      case
        when ev.host is null then array['refuse', 'no_course', 'the course is not in the catalogue']
        when ev.other_provider then array['refuse', 'provider', 'the page is on another provider''s website (' || ev.host || ')']
        when ev.page_year < ev.cur_year then array['refuse', 'older_year', 'the page is the ' || ev.page_year || ' handbook entry, and this course already has a ' || ev.cur_year || ' page']
        when ev.page_year < extract(year from now())::int - ev.max_age then array['refuse', 'old_year', 'the page is the ' || ev.page_year || ' handbook entry, older than the handbook years allowed']
        when ev.domestic_page then array['refuse', 'audience', 'the page is for domestic students, and this course is for international students']
        when ev.international_page then array['refuse', 'audience', 'the page is for international students, and this course is for domestic students']
        when ev.shared and ev.award_evidence then array['pass', 'award_on_parent_page', 'the page of the longer course, which names this award as available within it']
        when ev.shared and ev.names_course and 'shared_page' = any (coalesce(ev.exceptions, '{}')) then array['pass', 'exception_shared_page', 'an approved shared page that names this course''s own section']
        when ev.shared then array['refuse', 'shared_page', 'the page is shared by several courses, or is a fee, application or course list page, and nothing on it shows this course''s own section']
        when ev.own_code then array['pass', 'own_code', 'the page address or title shows this course''s own code']
        when ev.other_code then array['refuse', 'other_code', 'the page address or title shows another course''s code']
        when ev.other_level and ev.award_evidence then array['pass', 'award_on_parent_page', 'the page of the longer course, which names this award as available within it']
        when ev.other_level and ev.names_course and 'nested_award' = any (coalesce(ev.exceptions, '{}')) then array['pass', 'exception_nested_award', 'an approved page of the longer course that names this award']
        when ev.other_level then array['refuse', 'level', 'the page is for another qualification level (' || array_to_string(ev.page_lv, ', ') || '), not this course''s (' || array_to_string(ev.course_lv, ', ') || ')']
        when ev.other_variant then array['refuse', 'variant', 'the page is for another version of the award (' || coalesce(nullif(array_to_string(ev.page_only, ', '), ''), ev.page_credit || ' credit points') || ')']
        when ev.other_title is not null then array['refuse', 'sibling', 'the page address is another course''s at this provider (' || ev.other_title || ')']
        when ev.other_name then array['refuse', 'name', 'the page address and title do not name this programme']
        when ev.other_campus is not null then array['refuse', 'campus', 'the page is for another campus (' || ev.other_campus || ')']
        when ev.proved then array['pass', 'identity_proof', 'nothing on the page contradicts the course, and its identity is proved']
        else array['unproven', 'unproven', 'nothing on the page proves yet that it is this course''s own page']
      end r
    from ev right join (select 1) one on true)
  select jsonb_build_object('verdict', v.r[1], 'rule', v.r[2], 'reason', v.r[3], 'url', p_url,
           'checks', jsonb_strip_nulls(jsonb_build_object('course_levels', to_jsonb(v.course_lv), 'page_levels', to_jsonb(v.page_lv), 'variants', to_jsonb(v.page_only),
             'page_year', v.page_year, 'course_year', v.cur_year, 'other_courses_on_page', v.n_other, 'other_titles_on_page', v.n_diff,
             'other_course', v.other_title, 'other_campus', v.other_campus, 'exceptions', to_jsonb(v.exceptions), 'names_course', v.names_course,
             'own_code', v.own_code, 'award_evidence', v.award_evidence, 'proved', v.proved, 'title', nullif(v.title, ''))))
    from v
$function$;
comment on function security.course_page_check_v1(uuid, text, text, text) is 'CF-247 E16-1 (Platform Admin 2 Nov 2026 07:21): is this page the course''s own page? verdict pass, refuse or unproven, with the rule and a plain reason. Used by the binding guard, the award-link lane, the AI reader''s page choice and the search projection. Settings binding.*.';
revoke all on function security.course_page_check_v1(uuid, text, text, text) from public, anon, authenticated, service_role;

-- 3. A refusal: one page rejection, and the existing Layer 4 course-link review without a duplicate ----------------------------------------
create or replace function security.binding_refusal_route_v1(p_course uuid, p_url text, p_check jsonb, p_lane text, p_evidence uuid)
returns text language plpgsql security definer set search_path to '' as $function$
declare v_prov uuid; v_ev uuid;
begin
  select provider_id into v_prov from catalogue.courses where id = p_course;
  if v_prov is null or coalesce(btrim(p_url), '') = '' then return 'nothing'; end if;
  -- no lane binds this page to this course again (security.page_refused_v1); the row is kept as the record of why
  insert into pipeline.page_rejections(course_id, url, provider_id, evidence_id, source, reason, signals)
  values (p_course, p_url, v_prov, p_evidence, 'binding_check', coalesce(p_check->>'reason', 'the page is not proved to be this course''s page'),
          jsonb_build_object('rule', p_check->>'rule', 'lane', p_lane, 'check', p_check, 'decision', 'E16 (Platform Admin 2 Nov 2026 07:21)'))
  on conflict (course_id, url) do nothing;
  -- one course link item at a time per course (the same lock for every lane, so two lanes cannot both add one)
  perform pg_advisory_xact_lock(hashtext('layer4 course link ' || p_course::text));
  if exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = p_course and i.field_code = 'official_course_url' and i.status = 'pending') then
    return 'pending_item_kept';
  end if;
  -- Decision 263: a page a person or a rule already decided for this course is not raised again
  if exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = p_course and i.field_code = 'official_course_url'
                and i.proposed_value->>'course_url' = p_url) then
    return 'decided_before';
  end if;
  select e.id into v_ev from pipeline.evidence_artifacts e where e.id = p_evidence;
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
  values ('course', p_course, 'official_course_url', v_ev,
          (select coalesce(jsonb_agg(l.url order by l.is_primary desc, l.url), '[]'::jsonb) from catalogue.course_links l where l.course_id = p_course and l.link_type = 'official_course' and l.status = 'active'),
          jsonb_build_object('course_url', p_url),
          jsonb_build_object('source', 'binding check', 'page', p_url, 'rule', p_check->>'rule', 'lane', p_lane, 'check', p_check->'checks'),
          '{}'::jsonb, 'pending',
          'The page found automatically was not linked: ' || coalesce(p_check->>'reason', 'it is not proved to be this course''s page') || '. If it is this course''s own page, choose Use the new page; otherwise keep the page we hold.',
          'CF-CHG-20260915-247; E16 (Platform Admin 2 Nov 2026 07:21)');
  return 'item_created';
end $function$;
comment on function security.binding_refusal_route_v1(uuid, text, jsonb, text, uuid) is 'CF-247 E16-1: records a refused course page (pipeline.page_rejections, source binding_check) and routes it to the existing Layer 4 course-link review (field official_course_url) unless a pending item exists or a person already decided that page.';
revoke all on function security.binding_refusal_route_v1(uuid, text, jsonb, text, uuid) from public, anon, authenticated, service_role;

-- 4. The existing binding guard runs the check (every binding lane passes through it) -------------------------------------------------------
select pg_temp.edit_once('security.coverage_page_refused_host_guard()', '33351b506da59359656ee196218d7882', 'f2e4102f8788816c3f22f26945785f55', array[
 array[$o$AS $function$
begin
$o$, $n$AS $function$
declare v_new_evidence boolean := false; v_chk jsonb;
begin
$n$],
 array[$o$    new.status := 'mismatch'; new.read_status := 'not_course_page'; new.identity_basis := null; new.next_read_at := null;
  end if;
  return new;
$o$, $n$    new.status := 'mismatch'; new.read_status := 'not_course_page'; new.identity_basis := null; new.next_read_at := null;
  end if;
  -- 2 Nov 2026 (E16-1, Platform Admin 07:21): the page must not contradict this course (security.course_page_check_v1), whichever lane binds
  -- it. Checked when a page is bound or re-bound, when it is first read, or when its identity proof changes; a page set by hand is not.
  if new.status in ('bound', 'ambiguous') and coalesce(new.basis, '') <> 'manual' and security.pipeline_num_v1('binding.identity_check', 1) >= 1
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = new.course_id and k.field in ('official_url', 'course_url')) then
    if tg_op = 'INSERT' then
      v_new_evidence := true;
    else
      v_new_evidence := new.url is distinct from old.url or old.status not in ('bound', 'ambiguous') or new.identity_basis is distinct from old.identity_basis
                        or (new.read_status = 'read' and old.read_status is distinct from 'read');
    end if;
    -- a page already rejected or blocked for this course (pipeline.page_rejections, pipeline.course_page_blocks) is refused by every lane
    if v_new_evidence and security.page_refused_v1(new.course_id, new.url) then
      new.status := 'mismatch'; new.read_status := 'page_refused'; new.identity_basis := null; new.next_read_at := null;
      v_new_evidence := false;
    end if;
    if v_new_evidence then
      v_chk := security.course_page_check_v1(new.course_id, coalesce(nullif(new.candidates->>'final_url', ''), new.url),
                                             coalesce(nullif(new.candidates->>'page_title', ''), new.candidates->>'h1'), new.identity_basis);
      if v_chk->>'verdict' = 'refuse' then
        perform security.binding_refusal_route_v1(new.course_id, new.url, v_chk, coalesce(new.basis, 'unknown'), new.evidence_id);
        new.status := 'mismatch'; new.read_status := 'identity_refused'; new.identity_basis := null; new.next_read_at := null;
      end if;
    end if;
  end if;
  return new;
$n$]], array[1, 1]);

do $trg$
begin
  if pg_get_triggerdef((select oid from pg_trigger where tgname = 'coverage_page_refused_host' and tgrelid = 'pipeline.coverage_course_pages'::regclass))
     not in ('CREATE TRIGGER coverage_page_refused_host BEFORE INSERT OR UPDATE OF url, status ON pipeline.coverage_course_pages FOR EACH ROW EXECUTE FUNCTION security.coverage_page_refused_host_guard()',
             'CREATE TRIGGER coverage_page_refused_host BEFORE INSERT OR UPDATE OF url, status, identity_basis ON pipeline.coverage_course_pages FOR EACH ROW EXECUTE FUNCTION security.coverage_page_refused_host_guard()') then
    raise exception 'trigger coverage_page_refused_host differs from the definition this change replaces';
  end if;
end $trg$;
-- the guard also runs when only the identity proof changes (host pages confirm a page that way)
create or replace trigger coverage_page_refused_host before insert or update of url, status, identity_basis on pipeline.coverage_course_pages
  for each row execute function security.coverage_page_refused_host_guard();

-- 5. The award-link lane takes another course's page only when the check passes ----------------------------------------------------------
select pg_temp.edit_once('security.exit_awards_apply_v2(uuid)', '8d4e5f7b2fedbe7c3e04ff8b039c40e7', 'e7080925ba79eef320f361bf236cb072', array[
 array[$o$v_courses uuid[] := '{}'; v_af text[];
begin$o$, $n$v_courses uuid[] := '{}'; v_af text[];
        v_chk jsonb; v_refused int := 0; v_held int := 0;
begin$n$],
 array[$o$    if r.register_check = 'fail' and r.set_by <> 'hand' then v_skipped := v_skipped + 1; continue; end if;
$o$, $n$    if r.register_check = 'fail' and r.set_by <> 'hand' then v_skipped := v_skipped + 1; continue; end if;
    -- 2 Nov 2026 (E16-1, Platform Admin 07:21): an award takes another course's page only when the page is proved to be its own (its code
    -- in the address or title, or an approved nested-award exception that names the award). A new link that fails is refused once (page
    -- rejection and the existing Layer 4 course-link review); an award link already shown is left for the governed re-evaluation (§4).
    -- a course under a remediation hold (SS-007), or a page rejected or blocked for this course, is never linked again by this lane
    if security.course_held_v1(r.child_course_id) or security.page_refused_v1(r.child_course_id, r.page_url) then v_refused := v_refused + 1; continue; end if;
    if security.pipeline_num_v1('binding.identity_check', 1) >= 1 then
      v_chk := security.course_page_check_v1(r.child_course_id, r.page_url, null, null);
      if v_chk->>'verdict' <> 'pass' then
        if exists (select 1 from catalogue.course_links l where l.course_id = r.child_course_id and l.link_type = 'official_course' and l.url = r.page_url and l.status = 'active') then
          v_held := v_held + 1;
        else
          perform security.binding_refusal_route_v1(r.child_course_id, r.page_url,
                    v_chk || jsonb_build_object('award_of', r.parent_course_id, 'link_type', r.link_type, 'set_by', r.set_by), 'award_link', r.evidence_id);
          v_refused := v_refused + 1;
        end if;
        continue;
      end if;
    end if;
$n$],
 array[$o$'errors', v_err, 'last_error', v_last);$o$, $n$'errors', v_err, 'last_error', v_last,
                            'refused_identity', v_refused, 'not_proved_left_for_review', v_held);$n$]], array[1, 1, 1]);

-- 6. AI enrichment reads only a page whose identity is proved and not refused ------------------------------------------------------------
select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', '37b855677c98002ed2374f02cd1282f9', 'b677308fffdc23e5fbd2ad54d1b97d30', array[
 array[$o$           where g.course_id = it.course_id and g.status in ('bound', 'ambiguous') and (g.status = 'bound' or g.identity_basis is not null);
          if v_path is null then
            update pipeline.field_enrich_items set reason = 'no correct course page: the page found is for another course'
             where id = it.id and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id and g.status = 'mismatch');
          end if;$o$,
       $n$           where g.course_id = it.course_id and g.status in ('bound', 'ambiguous') and (g.status = 'bound' or g.identity_basis is not null)
             -- 2 Nov 2026 (E16-1): only a page that was read with an identity proof and that the course page check does not refuse
             and g.read_status = 'read' and g.identity_basis is not null
             and (security.pipeline_num_v1('binding.identity_check', 1) < 1
                  or security.course_page_check_v1(it.course_id, coalesce(nullif(g.candidates->>'final_url', ''), g.url),
                                                   coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1'), g.identity_basis)->>'verdict' <> 'refuse');
          if v_path is null then
            update pipeline.field_enrich_items
               set reason = case when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id and g.status = 'mismatch')
                                 then 'no correct course page: the page found is for another course'
                                 else 'no proven course page: the page found is not proved to be this course''s (E16)' end
             where id = it.id and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = it.course_id);
          end if;$n$]], array[1]);

-- 7. E16-2: with several active links and none primary, the projection shows course_url only when it passes the check; otherwise none ----
select pg_temp.edit_once(f.sig, f.before, f.after, array[
 array[$o$  left join lateral (
    select l.url
    from catalogue.course_links l
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='official_course_url' and sg.source_id=l.source_id and sg.gate_status='approved'
    where l.course_id=d.course_id and l.status='active'
      and (l.valid_from is null or l.valid_from<=current_date) and (l.valid_to is null or l.valid_to>=current_date)
    order by l.is_primary desc,l.last_verified_at desc nulls last,l.updated_at desc nulls last,l.id limit 1
  ) lk on true$o$, $n$  left join lateral (
    -- 2 Nov 2026 (E16-2, Platform Admin 07:21): one link, or the primary link, as before; with several and none primary, the link equal to
    -- courses.course_url (the same page however it is spelled: case, http or https, www, a closing slash or a section) when it passes the
    -- course page check (security.course_page_check_v1), otherwise none, never the most recent one
    select case when count(*) <= 1 or bool_or(l.is_primary)
                then (array_agg(l.url order by l.is_primary desc,l.last_verified_at desc nulls last,l.updated_at desc nulls last,l.id))[1]
                else (select k.u from unnest(array_agg(l.url order by l.last_verified_at desc nulls last,l.updated_at desc nulls last,l.id)) with ordinality k(u, o)
                        join catalogue.courses c on c.id=d.course_id
                       where regexp_replace(regexp_replace(regexp_replace(lower(k.u),'#.*$',''),'^https?://(www\.)?',''),'/+$','')
                             =regexp_replace(regexp_replace(regexp_replace(lower(c.course_url),'#.*$',''),'^https?://(www\.)?',''),'/+$','')
                         and security.course_page_check_v1(d.course_id,k.u)->>'verdict'='pass'
                       order by (k.u=c.course_url) desc,k.o limit 1) end url
    from catalogue.course_links l
    join search.enrichment_source_gates sg on sg.projection_code='courses' and sg.domain_code='official_course_url' and sg.source_id=l.source_id and sg.gate_status='approved'
    where l.course_id=d.course_id and l.status='active'
      and (l.valid_from is null or l.valid_from<=current_date) and (l.valid_to is null or l.valid_to>=current_date)
  ) lk on true$n$]], array[1])
  from (values ('search.refresh_course_enrichment_core_v1(boolean)', 'ce80f74549625c23317aba5c737afda6', '6214bb43a019cf30a94cf12354579eb2'),
               ('search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)', '3f0b051fdc0e8c34f757f8c21ff5b7d3', '82cc2006ba8447a5f23ca726b691c140')) f(sig, before, after);

-- 8. Housekeeping register --------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_page_check_v1', 'Pipeline', 'Coverage', 'E16-1: is this page the course''s own page (pass, refuse or unproven), for every binding lane, the award links, the AI reader and the projection', 'active', '{}', '20261102030000'),
 ('function', 'security.binding_refusal_route_v1', 'Pipeline', 'Coverage', 'E16-1: a refused course page: one page rejection and one Layer 4 course-link item, no duplicates', 'active', '{}', '20261102030000')
on conflict do nothing;

-- post-check
do $$
begin
  if exists (select 1 from pipeline.page_rejections where source = 'binding_check') then
    raise exception 'E16 post-check: this change must not refuse any page by itself'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key like 'binding.%'
        and key in ('binding.award_page_evidence', 'binding.identity_check', 'binding.level_patterns', 'binding.variant_markers', 'binding.name_stop_words', 'binding.name_min_tokens',
                    'binding.name_stem_chars', 'binding.shared_page_patterns', 'binding.shared_page_min_other_courses', 'binding.handbook_max_age_years',
                    'binding.domestic_page_patterns', 'binding.international_page_patterns', 'binding.identity_exceptions')) <> 13 then
    raise exception 'E16 post-check: a course page check setting is missing'; end if;
  if has_function_privilege('authenticated', 'security.course_page_check_v1(uuid,text,text,text)', 'execute')
     or has_function_privilege('anon', 'security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)', 'execute') then
    raise exception 'E16 post-check: the check and the route are not for the signed-in or anonymous roles'; end if;
  if pg_get_triggerdef((select oid from pg_trigger where tgname = 'coverage_page_refused_host' and tgrelid = 'pipeline.coverage_course_pages'::regclass))
     <> 'CREATE TRIGGER coverage_page_refused_host BEFORE INSERT OR UPDATE OF url, status, identity_basis ON pipeline.coverage_course_pages FOR EACH ROW EXECUTE FUNCTION security.coverage_page_refused_host_guard()' then
    raise exception 'E16 post-check: the binding guard does not run on identity_basis'; end if;
end $$;
