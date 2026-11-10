// Guards: Platform Admin directive 10 Nov 2026, Workstream C (recover the course readings stuck after the read by a deterministic subtractive subset of whole sentences: no AI call, no page read, no setting or word-list change, the same full check on the remainder, the existing record and machine admission path with the distinct reason subset_of_reading, the daily read cap untouched; additive Data Delivery keys); G2 (no number in code), G3 (consumer API untouched), G4 (governed tests)
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110230000_cf247_cdesc_subset_recovery.sql', 'utf8')
const R = fs.readFileSync('supabase/held/cdesc_subset_recovery_forward_recovery.sql', 'utf8')
const OD = fs.readFileSync('src/CourseDescriptionOnDemand.jsx', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const EDITS = [
  ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '6e65745a7863f0dae97a743821475eb0', 'd310fa64f61f2243df1416d3e48f6bab'],
  ['security.course_description_machine_admit_v1(uuid,text)', '69b8911fe24f041b4cf67a844d8d8f6f', '569f3ceb95c3d31b378ce7288b7abd24'],
  ['security.course_description_machine_run_v1()', 'faa6dab1bfeef3464ba86fac11b34766', '42c73e9c0f376150e7778104dfa9830a'],
  ['security.data_delivery_cdesc_flow_v1()', 'bd500303727d5c11a708aa99341809a4', '3d4c538fc23977018982bc64023a4690'],
]
const fnBody = (name) => {
  const i = M.indexOf(`create or replace function ${name}`)
  expect(i, name).toBeGreaterThan(-1)
  const j = M.indexOf('$f$;', M.indexOf('$f$', i + 40))
  return M.slice(i, j)
}

test('the migration follows the house pattern: header, four md5-guarded edits, four new functions, nothing dropped, no setting or data written', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  for (const [sig, before, after] of EDITS) {
    expect(M, sig).toContain(sig)
    expect(M, sig).toContain(before)
    expect(M, sig).toContain(after)
    expect(R, `${sig} (recovery)`).toContain(before)
  }
  expect(M).toContain('supabase/held/cdesc_subset_recovery_forward_recovery.sql')
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/\balter\s+table\b/i)
  expect(M).not.toContain('@@MD5_')
  // no setting is added or changed; no top-level data write at all
  expect(M).not.toMatch(/\b(insert\s+into|update|delete\s+from)\s+pipeline\.platform_toolset_settings/i)
  expect(M).toMatch(/differs from the definition this change (edits|replaces)/)
  for (const f of ['cdesc_sentence_fault_v1', 'cdesc_subset_plan_v1', 'cdesc_subset_recover_v1', 'data_delivery_cdesc_subset_v1']) {
    expect(M, f).toContain(`function security.${f}`)
    expect(M, f).toMatch(new RegExp(`'security\\.${f}'`))   // component register row
  }
  expect(M).toMatch(/revoke all on function security\.data_delivery_cdesc_subset_v1\(\) from public, anon, authenticated;/)
  expect(M).toMatch(/revoke all on function security\.cdesc_subset_recover_v1\(\) from public, anon, authenticated;/)
})

test('the plan only drops whole sentences, adds nothing, and the remainder is judged by the SAME full check and the machine wording policy', () => {
  const plan = fnBody('security.cdesc_subset_plan_v1')
  expect(plan).toContain('security.course_description_check_v1(')
  expect(plan).toContain('security.cdesc_machine_text_check_v1(')
  expect(plan).toContain('cdesc_sentence_fault_v1')
  expect(plan).toContain("'enrich.course_description_max_sentences'")
  expect(plan).toContain("'enrich.course_description_max_chars'")
  // the kept sentences are the stored elements, selected, never rebuilt from new text
  expect(plan).not.toMatch(/\bregexp_replace\s*\(\s*[a-z_.]*text/i)
  expect(plan).not.toMatch(/\bsubstr(ing)?\s*\(/i)
  expect(plan).not.toMatch(/\bleft\s*\(\s*[a-z_.]*text/i)
  const rec = fnBody('security.cdesc_subset_recover_v1')
  // no AI call, no page read, no setting write
  expect(rec).not.toMatch(/net\.http|http_post|firecrawl|openrouter|enrich_ai_answers\s*\(|insert\s+into\s+pipeline\.enrich_ai_answers/i)
  expect(rec).not.toMatch(/platform_toolset_settings/)
  // it goes through the existing record and admission functions
  expect(rec).toContain('security.enrich_course_text_record_v1(')
  expect(rec).toContain('security.course_description_machine_admit_v1(')
  expect(rec).toContain('security.cdesc_reading_provenance_v1(')
  expect(rec).toContain('security.course_description_machine_policy_stamp_v1()')
  expect(rec).toContain('security.cdesc_provider_slots_v1(')
  // the daily read cap is read as the ceiling, never written or worked around
  expect(rec).toContain("'enrich.course_text_items_per_day'")
  expect(M).toContain('subset_of_reading')
})

test('G2: no operational number in the new code outside lines marked fixed', () => {
  const body = M.slice(M.indexOf('-- new functions'))
  const bad = []
  for (const [n, line] of body.split('\n').entries()) {
    if (line.trim().startsWith('--') || line.includes('-- fixed:')) continue
    // intervals and limits of 100 or more, or a literal day/second count in an interval
    if (/\binterval\s+'\s*\d+/i.test(line) || /make_interval\s*\([^)]*\b\d{2,}\b/i.test(line) || /\blimit\s+\d{3,}/i.test(line)) bad.push(`${n + 1}: ${line.trim().slice(0, 120)}`)
  }
  expect(bad).toEqual([])
})

test('G3: the consumer API is not read for change or changed', () => {
  const code = M.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(code).not.toMatch(/\bpublic\.website_|wix-course-api|zoho-api-v2/)
  expect(M).not.toMatch(/Consumer API change approved/)
})

test('Data Delivery: the additive subset key is read only and counted from the server; the screen file is not touched here', () => {
  const fn = fnBody('security.data_delivery_cdesc_subset_v1')
  for (const k of ["'known'", "'counted_at'", "'recovered'", "'recovered_by_cause'", "'not_recovered_by_reason'", "'retained_total'", "'admitted_24h'", "'admitted_7d'", "'withdrawn_total'"]) expect(fn, k).toContain(k)
  expect(fn).not.toMatch(/\b(insert|update|delete)\b\s+(into|from)?\s*(pipeline|catalogue)\./i)
  expect(M).toContain("'subset', security.data_delivery_cdesc_subset_v1()")
})

test('evidence-backed absence (Operating Model v1.7): only readings that were read are recovered; the per-field result shows the stored item with attempts, source, evidence and storage path and writes nothing', () => {
  const rec = fnBody('security.cdesc_subset_recover_v1')
  expect(rec).toContain("'^held: (")                               // a held reading only (a reason 'held: <rule>'): never 'no correct course page', 'no proven course page' or 'no allowed source had a value'
  expect(rec).not.toMatch(/\battempts\b/)                          // the recovery never counts, resets or reads an attempt
  const det = fnBody('security.cdesc_item_detail_v1')
  for (const k of ["'attempts'", "'reason'", "'source'", "'evidence_id'", "'storage_path'", "'reading_chars'", "'catalogue_chars'"]) expect(det, k).toContain(k)
  expect(det).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(M).toContain('public.admin_course_description_item_v1')
  expect(M).toMatch(/grant execute on function public\.admin_course_description_item_v1\(uuid\[\]\) to authenticated, service_role;/)
  // the screen reads the item as stored; attempts 0 is shown as never tried and is never described as evidence of absence
  expect(OD).toContain("supabase.rpc('admin_course_description_item_v1'")
  expect(OD).toContain('Never tried: no valid source was read. This is not evidence that the page has no description.')
  expect(OD).toContain('Number(item.attempts)===0')
})

test('standing rule: a university About page never stands in for a course page; the subset recovery checks the bound page itself, in its own functions, and the shared admission is not changed', () => {
  const pk = fnBody('security.cdesc_page_kind_v1')
  for (const k of ["'about-us'", "'who-we-are'", "'our-university'", "'about-the-university'", "'about'", "'overview'", "'host_page'", "'university_about_page'", "'host_page_no_course_evidence'"]) expect(pk, k).toContain(k)
  expect(pk).not.toMatch(/\b(insert|update|delete)\b/i)
  const plan = fnBody('security.cdesc_subset_plan_v1')
  expect(plan).toContain('security.cdesc_page_kind_v1(')
  expect(plan.indexOf('cdesc_page_kind_v1')).toBeLessThan(plan.indexOf('cdesc_sentence_fault_v1'))   // the page is judged before any sentence work
  expect(M).toContain("('function', 'security.cdesc_page_kind_v1'")
  // the only shared admission function edited is the audit of admit_v1 (via subset_of_reading); no page-kind rule is added there
  expect(M).not.toMatch(/university_about_page[^\n]*(course_description_machine_check_v1|enrich_course_text_record_v1)/)
})

test('CI runs the fixture and this contract', () => {
  expect(WF).toContain('bash tests/fixtures/cdesc-subset/run.sh')
  expect(WF).toContain('tests/fixtures/cdesc-subset/**')
  expect(WF).toContain('supabase/migrations/20261110230*.sql')
  expect(WF).toContain('tests/uat/cf-247-cdesc-subset-contract.spec.mjs')
  expect(fs.existsSync('tests/fixtures/cdesc-subset/scenarios.sql')).toBe(true)
  expect(fs.existsSync('tests/fixtures/cdesc-subset/run.sh')).toBe(true)
})
