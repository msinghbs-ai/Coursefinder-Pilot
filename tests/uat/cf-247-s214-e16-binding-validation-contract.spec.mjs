// Guards: E16 (Platform Admin 2 Nov 2026 07:21)
// "Prioritise E16-1 and extend the existing binding validation where necessary ... A matching domain or similar course title is insufficient.
// For shared pages, validate the exact section or programme-specific evidence. Where identity cannot be proved, refuse automatic binding and
// route the exception through existing Layer 4 controls. Prevent downstream AI enrichment from reading a page with unsupported course
// identity. Every binding rule must have regression fixtures for its previously documented failure classes, including genuine shared-page
// exceptions." With E16-2: with several active links and none primary, the projection shows course_url only when it passes, otherwise none.
// The behaviour runs on isolated fixtures by tests/fixtures/e16-binding-validation/run.sh (scratch PostgreSQL; the five live definitions are
// rebuilt from this repository's migrations and checked against the live md5s); this spec holds the contract and the fixture coverage.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261102030000_cf247_e16_binding_validation.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/e16-binding-validation'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/before.mjs`, 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('\n$function$;', a)) }
const check = fn('security.course_page_check_v1')
const route = fn('security.binding_refusal_route_v1')
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); return m.slice(a, m.indexOf(']]', a)) }

const BEFORE = { 'security.coverage_page_refused_host_guard()': '33351b506da59359656ee196218d7882', 'security.exit_awards_apply_v2(uuid)': '8d4e5f7b2fedbe7c3e04ff8b039c40e7',
  'security.enrich_fields_slice_v1(uuid,integer)': '37b855677c98002ed2374f02cd1282f9', 'search.refresh_course_enrichment_core_v1(boolean)': 'ce80f74549625c23317aba5c737afda6',
  'search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)': '3f0b051fdc0e8c34f757f8c21ff5b7d3' }
const AFTER = { 'security.coverage_page_refused_host_guard()': 'f2e4102f8788816c3f22f26945785f55', 'security.exit_awards_apply_v2(uuid)': 'e7080925ba79eef320f361bf236cb072',
  'security.enrich_fields_slice_v1(uuid,integer)': 'b677308fffdc23e5fbd2ad54d1b97d30', 'search.refresh_course_enrichment_core_v1(boolean)': '6214bb43a019cf30a94cf12354579eb2',
  'search.refresh_course_enrichment_core_scoped_v1(uuid[],boolean)': '82cc2006ba8447a5f23ca726b691c140' }

test('five functions are edited only from their live md5 and checked after; the fixture run rebuilds them from the repository', () => {
  for (const [sig, b] of Object.entries(BEFORE)) {
    expect(m, sig).toMatch(new RegExp(`'${sig.replace(/[()[\]]/g, '\\$&')}', '${b}', '${AFTER[sig]}'`))
  }
  expect(code).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(code).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(run).toContain(`"${Object.values(BEFORE).join(' ')}"`)
  expect(run).toContain("grep -c 'already applied' | grep -qx 5")
  for (const f of ['20261004001260_cf247_adapter_admission_and_refused_hosts', '20261031030000_cf247_ss007_remediation_hold', '20261015010000_cf247_enrichment_waste_rules',
    '20261023017000_cf247_ai_reader_bound_pages_only', '20261016010000_cf247_api_data_fixes']) expect(before).toContain(f)
})

test('one check covers every §3 point, with every list and limit a setting (G2)', () => {
  for (const r of ['provider', 'older_year', 'old_year', 'audience', 'shared_page', 'own_code', 'other_code', 'level', 'variant', 'sibling', 'name', 'campus',
    'award_on_parent_page', 'exception_shared_page', 'exception_nested_award', 'identity_proof', 'unproven']) expect(check, r).toContain(`'${r}'`)
  for (const k of ['binding.level_patterns', 'binding.variant_markers', 'binding.name_stop_words', 'binding.shared_page_patterns', 'binding.domestic_page_patterns',
    'binding.international_page_patterns', 'binding.identity_exceptions', 'binding.award_page_evidence']) expect(check).toContain(`security.toolset_setting('pipeline', '${k}')`)
  for (const k of ['binding.name_min_tokens', 'binding.name_stem_chars', 'binding.shared_page_min_other_courses', 'binding.handbook_max_age_years']) expect(check).toContain(`security.pipeline_num_v1('${k}', `)
  for (const k of ['identity_check', 'level_patterns', 'variant_markers', 'name_stop_words', 'name_min_tokens', 'name_stem_chars', 'shared_page_patterns',
    'shared_page_min_other_courses', 'handbook_max_age_years', 'domestic_page_patterns', 'international_page_patterns', 'award_page_evidence', 'identity_exceptions'])
    expect(m).toMatch(new RegExp(`\\('pipeline', 'binding\\.${k}', 'Course page check: [^']+',\\n  '`))
  // the allowed cases need programme-specific evidence: an approved exception that names the course, or award evidence; never a title match
  expect(check).toContain("when ev.shared and ev.names_course and 'shared_page' = any (coalesce(ev.exceptions, '{}'))")
  expect(check).toContain("when ev.other_level and ev.award_evidence then")
  expect(check).toContain("a.link_type = 'exit_award'")
  expect(check).toContain("a.set_by = 'hand' and a.evidence_id is not null")
  expect(check).toContain('-- fixed: words of one or two letters carry no programme name')
})

test('every binding lane passes the existing guard; a refusal is recorded once and routed to the existing Layer 4 course link review', () => {
  const g = edit('security.coverage_page_refused_host_guard()')
  expect(g).toContain("v_chk := security.course_page_check_v1(new.course_id, coalesce(nullif(new.candidates->>'final_url', ''), new.url),")
  expect(g).toContain("new.status := 'mismatch'; new.read_status := 'identity_refused'; new.identity_basis := null; new.next_read_at := null;")
  expect(g).toContain("if v_new_evidence and security.page_refused_v1(new.course_id, new.url) then")
  expect(g).toContain("coalesce(new.basis, '') <> 'manual'")
  expect(m).toContain('create or replace trigger coverage_page_refused_host before insert or update of url, status, identity_basis on pipeline.coverage_course_pages')
  expect(route).toContain("on conflict (course_id, url) do nothing;")
  expect(route).toContain("i.field_code = 'official_course_url' and i.status = 'pending'")
  expect(route).toContain("i.proposed_value->>'course_url' = p_url")  // Decision 263: a decided page is not raised again
  expect(route).toContain("jsonb_build_object('course_url', p_url)")  // the existing course-link item shape
  expect(route).toContain("perform pg_advisory_xact_lock(hashtext('layer4 course link ' || p_course::text));")
})

test('the award-link lane uses the same check, honours holds and blocks, and leaves shown links to the governed re-evaluation', () => {
  const a = edit('security.exit_awards_apply_v2(uuid)')
  expect(a).toContain('if security.course_held_v1(r.child_course_id) or security.page_refused_v1(r.child_course_id, r.page_url) then')
  expect(a).toContain('v_chk := security.course_page_check_v1(r.child_course_id, r.page_url, null, null);')
  expect(a).toContain("if v_chk->>'verdict' <> 'pass' then")
  expect(a).toContain('v_held := v_held + 1;')
  expect(a.indexOf('v_chk := security.course_page_check_v1')).toBeLessThan(a.indexOf("'refused_identity', v_refused"))
})

test('AI enrichment reads only a proved page; the projection shows course_url only when it passes, otherwise none', () => {
  const s = edit('security.enrich_fields_slice_v1(uuid,integer)')
  expect(s).toContain("and g.read_status = 'read' and g.identity_basis is not null")
  expect(s).toContain("->>'verdict' <> 'refuse');")
  expect(s).toContain("'no proven course page: the page found is not proved to be this course''s (E16)'")
  const e = m.slice(m.indexOf('select pg_temp.edit_once(f.sig'), m.indexOf('from (values (\'search.refresh_course_enrichment_core_v1'))
  const p = e.slice(e.indexOf('$n$'))  // the new text
  expect(p).toContain('select case when count(*) <= 1 or bool_or(l.is_primary)')
  expect(p).toContain("and security.course_page_check_v1(d.course_id,k.u)->>'verdict'='pass'")
  expect(p).not.toContain('limit 1\n  ) lk on true')
})

test('nothing is changed, dropped, re-evaluated or switched on by the migration; the consumer API shape is untouched', () => {
  const outside = code.replace(/\$function\$[\s\S]*?\$function\$/g, '').replace(/\$[on]\$[\s\S]*?\$[on]\$/g, '')
  expect(outside).not.toMatch(/\b(update|delete)\s+(pipeline|catalogue|search)\./)
  expect(outside).not.toMatch(/cron\.schedule|insert into pipeline\.(layer4_review_items|page_rejections)/)
  expect(m).toContain("raise exception 'E16 post-check: this change must not refuse any page by itself'")
  expect(m).not.toMatch(/website_v2_|website_edge_|zoho_edge_|function api\./)
})

test('the fixtures cover every documented failure class and the allowed exceptions', () => {
  for (const p of ['PASS sibling award (Graduate Certificate/Diploma -> Master)', 'PASS older handbook year', 'PASS fee, application and course-list pages',
    'PASS school international page', 'PASS one page for many ELICOS levels', 'PASS EIT combined page', 'PASS genuine shared-page exception (allowed)',
    'PASS Lennox false positive (allowed)', 'PASS domain-only or similar-title match refused', 'PASS no duplicate Layer 4 item', 'PASS manual binding and the switch',
    'PASS award-link lane: title match refused, programme-specific evidence allowed, holds and blocks kept, no repeat',
    'PASS AI enrichment skips unproven and refused pages', 'PASS projection tie-break', 'PASS privileges']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(fixtures).toContain("'BSB80120'")
  expect(fixtures).toContain('bsb80120-graduate-certificate-in-management-learning')
  expect(fixtures).toContain("'blocked page never linked: '")
  expect(fixtures).toContain("'held course not linked again (SS-007 hold)'")
})
