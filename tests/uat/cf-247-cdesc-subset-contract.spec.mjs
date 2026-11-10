// Guards: Platform Admin directive 10 Nov 2026, Workstream C (recover the course readings stuck after the read by a deterministic subtractive subset of whole sentences: no AI call, no page read, no setting or word-list change, the same full check on the remainder, the existing record and machine admission path with the distinct reason subset_of_reading, the daily read cap untouched; no cutting for length; a university About page never stands in for a course page; additive Data Delivery keys); QA of PR 995 (Claude Integration Controller, 10 Nov 2026). G2 is guarded centrally by s32 and G3 by s57 (G4: not re-asserted here)
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261110230000_cf247_cdesc_subset_recovery.sql', 'utf8')
const R = fs.readFileSync('supabase/held/cdesc_subset_recovery_forward_recovery.sql', 'utf8')
const BW = fs.readFileSync('supabase/held/cdesc_subset_bulk_withdraw.sql', 'utf8')
const OD = fs.readFileSync('src/CourseDescriptionOnDemand.jsx', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const EDITS = [
  ['security.course_description_check_with_v1(uuid,jsonb,jsonb,jsonb)', '6e65745a7863f0dae97a743821475eb0', 'd310fa64f61f2243df1416d3e48f6bab'],
  ['security.course_description_machine_admit_v1(uuid,text)', '69b8911fe24f041b4cf67a844d8d8f6f', '569f3ceb95c3d31b378ce7288b7abd24'],
  ['security.course_description_machine_check_v1(uuid)', '4c321730269064b42ff9ac10a114336b', '2a5b91aa6b93b920bbb80df9920aca09'],
  ['security.course_description_machine_run_v1()', 'faa6dab1bfeef3464ba86fac11b34766', '42c73e9c0f376150e7778104dfa9830a'],
  ['security.data_delivery_cdesc_flow_v1()', 'bd500303727d5c11a708aa99341809a4', '3d4c538fc23977018982bc64023a4690'],
]
// the new functions are written CREATE OR REPLACE FUNCTION ... $function$ so that the central G2 scanner (s32) reads them
const fnBody = (name) => {
  const i = M.indexOf(`CREATE OR REPLACE FUNCTION ${name}(`)
  expect(i, name).toBeGreaterThan(-1)
  const j = M.indexOf('$function$;', M.indexOf('$function$', i + 40) + 10)
  return M.slice(i, j)
}

test('the migration follows the house pattern: header, five md5-guarded edits, new functions in the style the central G2 scanner reads, nothing dropped, no setting or data written', () => {
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
  for (const f of ['cdesc_sentence_fault_v1', 'cdesc_page_kind_v1', 'cdesc_subset_plan_v1', 'cdesc_subset_recover_v1', 'data_delivery_cdesc_subset_v1', 'cdesc_item_detail_v1']) {
    expect(M, f).toContain(`CREATE OR REPLACE FUNCTION security.${f}(`)
    expect(M, f).toMatch(new RegExp(`'security\\.${f}'`))   // component register row
  }
  expect(M).toContain('CREATE OR REPLACE FUNCTION public.admin_course_description_item_v1(')
  expect(M).not.toMatch(/^create or replace function (security|public)\.(cdesc_|data_delivery_cdesc_subset|admin_course_description_item)/m)   // upper case, so s32 scans them
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
  // nothing is cut for length: a reading whose only fault is its size, or whose remainder is still over the limits, stays held (QA B2)
  expect(plan).toContain("'over_length_needs_decision'")
  expect(plan).not.toMatch(/too_many_sentences|too_long|v_stop/)
  // fails closed: no bound page row is no proof
  expect(plan).toContain("'no_bound_page'")
  // a kept sentence that points back to a set-aside one: pronouns, the program, Another / Alternatively / Further / And / Which / Here / Each, a leading quote or bracket
  for (const w of ['another', 'alternatively', 'further', 'and', 'which', 'here', 'each', 'the (program|programme|course|degree', '\\[']) expect(plan, w).toContain(w)
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
  // unknown is not zero (v1.7): a read that failed or is still loading is "Not available" / "Reading", and only a server answer of no item is "Not tried"
  expect(OD).toContain("Not available: the stored item could not be read, so whether this was tried is unknown. This is not evidence that nothing was tried or that the page has no description.")
  expect(OD).toContain("setDetail({status:'error'})")
  expect(OD).toContain("useState({status:'loading'})")
  expect(OD).toContain("'Not tried: nothing has been read for this course.'")
})

test('standing rule: a university About page never stands in for a course page; one rule (cdesc_page_kind_v1) fails closed, is used by the subset plan first and by the owning machine check', () => {
  const pk = fnBody('security.cdesc_page_kind_v1')
  for (const k of ["'no_bound_page'", "'no_course_in_address'", "'university_about_page'", "'host_page_no_course_evidence'", "'host_page'", 'about-us', 'who-we-are', 'why-(study|choose', 'facts-(and', 'at-a-glance', 'about-(?!', '<@', 'v_fac']) expect(pk, k).toContain(k)
  expect(pk).toContain('\\.(html?|shtml|aspx?|php|jsp|cfm)$')   // file extensions are stripped before matching
  expect(pk).not.toMatch(/\b(insert|update|delete)\b/i)
  // every threshold or word list is marked as a fixed technical value
  expect((pk.match(/-- fixed:/g) || []).length).toBeGreaterThanOrEqual(4)
  const plan = fnBody('security.cdesc_subset_plan_v1')
  expect(plan).toContain('security.cdesc_page_kind_v1(')
  expect(plan.indexOf('cdesc_page_kind_v1')).toBeLessThan(plan.indexOf('cdesc_sentence_fault_v1'))   // the page is judged before any sentence work
  expect(M).toContain("('function', 'security.cdesc_page_kind_v1'")
  // the owning layer: a minimal md5-guarded step in the machine check, which delegates to the same function and declines as wrong_page_kind
  const i = M.indexOf("pg_temp.edit_all('security.course_description_machine_check_v1(uuid)'")
  expect(i).toBeGreaterThan(-1)
  const step = M.slice(i, M.indexOf('-- 3. the job', i))
  expect(step).toContain('security.cdesc_page_kind_v1(g.url, c.canonical_title, g.identity_basis)')
  expect(step).toContain("'wrong_page_kind'")
  expect(step.split('\n').length).toBeLessThan(20)
  expect(R).toContain('course_description_machine_check_v1')
})

test('time box: the recovery ends 20 s after it began or 45 s after the job began, part (a) takes at most 60 % so part (b) is not starved, and the result says when the box was reached', () => {
  const rec = fnBody('security.cdesc_subset_recover_v1')
  expect(rec).toContain('statement_timestamp()')
  expect(rec).toMatch(/v_dl := least\(v_t0 \+ make_interval\(secs => 20\), statement_timestamp\(\) \+ make_interval\(secs => 45\)\)/)
  expect(rec).toMatch(/v_dl_a := v_t0 \+ \(v_dl - v_t0\) \* 0\.6/)
  expect(rec).toMatch(/if clock_timestamp\(\) > v_dl_a then v_tb := true; exit; end if;/)
  expect(rec).toMatch(/if clock_timestamp\(\) > v_dl then v_tb := true; exit; end if;/)
  expect(rec).toContain("'time_box_reached'")
  for (const line of rec.split('\n').filter((l) => /make_interval\(secs|\* 0\.6/.test(l))) expect(line + (rec.split('\n')[rec.split('\n').indexOf(line) - 1] || ''), line).toContain('-- fixed:')
})

test('activation is stated plainly, with the pause and the way back; the bulk withdrawal is a paste file that nothing applies', () => {
  expect(M).toContain('applying this migration IS the activation of the subset recovery')
  expect(M).toContain('enrich.course_description_machine_on = 1')
  expect(M).toContain('set enrich.course_description_machine_on to 0')
  expect(M).toContain('supabase/held/cdesc_subset_bulk_withdraw.sql')
  expect(BW).toMatch(/^-- HELD \(not a migration, nothing applies it\)/)
  expect(BW).toContain("a.checks ? 'subset_of_reading'")
  expect(BW).toContain('security.course_description_machine_withdraw_v1(r.course_id, v_reason, v_actor)')
  expect(BW).toContain("raise exception 'set v_actor to the Platform Admin user id first'")
  expect(BW).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(BW).not.toMatch(/\bupdate\s+(pipeline|catalogue)\./i)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.includes('bulk_withdraw'))).toEqual([])
})

test('CI runs the fixture and this contract', () => {
  expect(WF).toContain('bash tests/fixtures/cdesc-subset/run.sh')
  expect(WF).toContain('tests/fixtures/cdesc-subset/**')
  expect(WF).toContain('supabase/migrations/20261110230*.sql')
  expect(WF).toContain('tests/uat/cf-247-cdesc-subset-contract.spec.mjs')
  expect(fs.existsSync('tests/fixtures/cdesc-subset/scenarios.sql')).toBe(true)
  expect(fs.existsSync('tests/fixtures/cdesc-subset/run.sh')).toBe(true)
})
