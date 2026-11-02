// Guards: D-R2 and D-R3 (Platform Admin direction 2 Nov 2026 23:24)
// "AER D-R2: implement safe replacement of a pending AER read with a corrected, complete read" (same source and identity, new evidence version,
// immutable history, atomic supersession, no duplicate active review, no automatic approval, reviewer can inspect differences, manual decisions
// and locks protected) and "AER D-R3: apply whole-read completeness protection to provider entry-matrix runs … refuse approval when material
// completeness cannot be demonstrated; extend equivalent safeguards to the 170 incomplete course reads that bypass E13, using reproducible
// failure fixtures". The behaviour runs on isolated fixtures (tests/fixtures/aer-dr2-dr3/run.sh: scratch PostgreSQL, live definitions rebuilt
// from this repository's migrations and checked against the live md5s, each failure fixture labelled with the real item it reproduces); this
// spec holds the contract and the Layer 4 card.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261103010000_cf247_aer_dr2_dr3_supersede_and_matrix_gate.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/aer-dr2-dr3'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('\n$$', a)) }

const EDITS = {
  'security.course_entry_gate_v1(uuid,uuid[])': ['c1e99d43c6081f9a98c0eb698d943f32', '4fc06c081e451f2d0fb0a504a4fbe10f', 'replace_once'],
  'security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)': ['db3fde7584baf7e2960625d728603b99', '80c97f180f6d2ba54aad1abf2d058a24', 'edit_once'],
  'security.enrich_entry_record_v1(bigint,jsonb)': ['9757abeeb3700c5cd2e02385def05869', '7faf2de4c2afe0a671f8f54c4a140fe4', 'edit_once'],
  'security.aer_review_read_v1(uuid)': ['50c31fc4df16b7bbbb39dab03aa9f9b2', '9b4aed8b80471beaac513cdf0aa55e3d', 'edit_once'],
}

test('every edited live function is guarded by its live md5 before and checked after; the fixtures rebuild the same live values', () => {
  const calls = Object.fromEntries([...m.matchAll(/select pg_temp\.(replace_once|edit_once)\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, how, sig, b, a]) => [sig, [b, a, how]]))
  expect(calls).toEqual(EDITS)
  expect(m).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(m).not.toMatch(/__A_[A-Z]+__/)
  for (const [b] of Object.values(EDITS)) expect(run).toContain(b)
  expect(run).toContain("grep -c 'already applied' | grep -qx 4")  // a second run changes nothing
})

test('D-R3 matrix gate: every completeness part, settings-driven, and approval refused with nothing changed (Step C included)', () => {
  const g = fn('security.entry_matrix_gate_v1')
  for (const k of ['entry.matrix_gate', 'entry.matrix_gate_ignore_reasons', 'entry.matrix_rank_words', 'entry.matrix_score_words', 'entry.gate_cover_chars', 'entry.gate_cover_min_chars']) expect(g).toContain(`'${k}'`)
  for (const part of ["the read is not of the source''s current stored copy", "the reader''s completeness check did not pass", 'rows changed since the read', 'left with no row at all',
    'qualification named by a column label', "the provider''s rank is stored as the qualification''s minimum", 'the band holds label text, not a band',
    'the value has no scale or is not printed in its quote', 'another provider, source or stored copy', 'share one identity']) expect(g).toContain(part)
  const edit = m.slice(m.indexOf("select pg_temp.edit_once('security.entry_matrix_review_apply_v1"), m.indexOf('-- ---------------------------------------------------------------- 5.'))
  expect(edit.indexOf("raise exception 'Held (D-R3, incomplete read): %. Nothing was changed'")).toBeLessThan(edit.lastIndexOf('-- Step C (29 Oct 2026)'))
  expect(edit).toContain("if p_action = 'approve' and p_item is not null then")
  for (const p of ['PASS UWA shape: 177 rows without China cannot be approved', 'PASS ANU ladder shapes: rank as minimum, label as qualification, label as band',
    'PASS zero-row pages: dropped rows prove a table exists', 'PASS whole run approves; stale and changed runs held; reject and automatic path unchanged']) expect(fixtures).toContain(`raise notice '${p}';`)
  for (const id of ['a0595bd2-740a-48fd-bb88-596749e6727c', 'cad93a9a-6551-4fae-a507-20e5d3f01d0b', '02bc7d80-b0f9-4b48-9d64-5713535f66cc', 'd01d7b4f-4c3a-48dc-8718-cbcbf56717c5',
    '987dac71-a146-495e-b3b4-02a40854a50a', 'f6941f3d-0e0e-4528-b918-0736618af419']) expect(fixtures).toContain(id)  // labelled with the real item each reproduces
})

test('E13 extension: uncovered dropped minimums, non-requirement rows and domestic routes stored for everyone hold course reads', () => {
  const c = fn('security.course_entry_read_check_v1')
  for (const k of ['entry.gate_hold_reasons', 'entry.nonrequirement_patterns', 'entry.domestic_audience_words', 'entry.gate_cover_chars', 'entry.gate_cover_min_chars']) expect(c).toContain(`'${k}'`)
  expect(m).toContain(`'["score_without_basis", "quote_not_on_page", "low_confidence"]'::jsonb`)
  const gate = m.slice(m.indexOf("select pg_temp.replace_once('security.course_entry_gate_v1"), m.indexOf('-- ---------------------------------------------------------------- 3.'))
  expect(gate).toContain('v_shared := security.course_entry_shared_page_v1(r.entity_id);')  // E13 unchanged, factored out
  expect(gate).toContain("'drops_uncovered', v_chk->'drops_uncovered'")
  expect(gate).toContain('no waiting row covers')
  for (const p of ['PASS uncovered dropped minimums hold the read', 'PASS a dropped duplicate of a kept row is not a lost requirement', 'PASS non-requirement rows hold approval',
    'PASS domestic routes stored for everyone are held until left out', 'PASS English notes are held until left out', 'PASS a clean read is unchanged']) expect(fixtures).toContain(`raise notice '${p}';`)
  for (const id of ['960bee1b-dde9-40e3-ad53-c7cf93f72ea2', '1ee33f6e-c36f-48cc-99ae-9d00a0adbbf9', '27757e93-8dd4-459a-a45e-01c604b21490', 'e0944462-2cd5-4f80-bad9-d041cf6d5c9a']) expect(fixtures).toContain(id)
})

test('D-R2: same page and course, history kept, one transaction, one waiting read, nothing approved, decisions/claims/locks protected', () => {
  expect(m).toContain('create table if not exists pipeline.aer_read_supersessions(')
  expect(m).toContain("check (state in ('requested', 'superseded', 'refused'))")
  expect(m).toContain("raise exception 'D-R2 history is kept: a supersession record is never deleted'")
  expect(m).toContain("create unique index if not exists layer4_review_items_course_entry_pending_uq on pipeline.layer4_review_items(entity_id)\n  where field_code = 'course_entry_first_read' and status = 'pending';")
  const chk = fn('security.course_entry_correction_check_v1')
  for (const part of ['a person has decided it', 'a reviewer claimed it', 'the course has a manual lock', 'is not the page of the waiting read', 'the corrected read still drops', "'entry.supersede_claim_minutes'", "'entry.supersede_lock_fields'"]) expect(chk).toContain(part)
  const rec = m.slice(m.indexOf("select pg_temp.edit_once('security.enrich_entry_record_v1"), m.indexOf('-- ---------------------------------------------------------------- 6.'))
  // the old item is superseded before any new row is written, and only after the corrected read passed its check
  const check = rec.indexOf('v_chk := security.course_entry_correction_check_v1(v_sup.old_item_id, i.course_id, g.url, v_keep, v_drop);')
  const sup = rec.indexOf("update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where id = v_old.id and status = 'pending';")
  expect(check).toBeGreaterThan(0); expect(sup).toBeGreaterThan(check)
  expect(rec.indexOf('insert into catalogue.course_entry_requirements', sup)).toBeGreaterThan(sup)
  expect(rec).not.toMatch(/status = 'approved'|course_entry_review_apply_v1\(/)  // no automatic approval
  expect(fn('security.course_entry_correction_v1')).toContain('security.course_entry_read_enqueue_v1(o.entity_id, p_actor,')  // the existing stored-page read
  expect(m).toMatch(/revoke all on function security\.course_entry_correction_v1\(uuid, uuid, text\) from public, anon, authenticated;/)
  for (const p of ['PASS a complete corrected read supersedes the waiting read atomically; an incomplete one changes nothing', 'PASS decisions, claims, locks and the bound page are protected',
    'PASS decided-meanwhile refusal, immutable history, one waiting read per course']) expect(fixtures).toContain(`raise notice '${p}';`)
})

test('nothing is read, approved, withdrawn or re-opened by the change; the cap stays 6', () => {
  const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  const outside = code.replace(/\$def\$[\s\S]*?\$def\$/g, '').replace(/\$\$[\s\S]*?\$\$/g, '').replace(/\$[on]\$[\s\S]*?\$[on]\$/g, '').replace(/\$f\$[\s\S]*?\$f\$/g, '')
  expect(outside).not.toMatch(/\b(update|delete)\s+(pipeline|catalogue)\./)
  expect(outside).not.toMatch(/(select|perform)\s+security\.(course_entry_read_enqueue_v1|course_entry_correction_v1)\(|cron\.schedule/)
  expect(code).not.toMatch(/'entry\.max_rows_per_course',\s*'/)
})

test.describe('mocked browser', () => {
  const ITEM = 'd3000000-0000-4000-8000-000000000001'
  const open = async (page, read, kind = 'entry_matrix_first_run', calls = []) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      const kinds = { aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [
        { key: 'approve', label: 'Approve all rows', rank: 6 }, { key: 'approve_except', label: 'Approve except…', rank: 6, input: 'rows' }, { key: 'reject', label: 'Reject the read', rank: 6 }] } }
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { aer_review: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'The University of Western Australia', country: 'AU', n: 1, by_kind: { aer_review: 1 } }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [{ kind: 'aer_review', ref: ITEM, provider_id: 'p1', subject: 'International and overseas qualifications',
        why: 'Entry matrix first run', created_at: '2026-10-29T00:00:00Z', detail: { field_code: kind } }] } })
      if (b.p_action === 'decide') return route.fulfill({ json: { ok: true } })
      return route.fulfill({ json: {} })
    })
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', (route) => route.fulfill({ json: { review_item_id: ITEM, kind, status: 'pending', can_decide: true, lineage: {}, ...read } }))
    await page.goto('/#layer-4-review')
    return page.locator('[data-l4-item="aer_review"]')
  }
  const row = (id, q) => ({ id, status: 'proposed', country: 'US', qualification: 'USA American College Test (ACT)', quote: q })

  test('a matrix run with lost rows (UWA shape): held with the reasons, neither approval can be chosen', async ({ page }) => {
    const item = await open(page, { rows: [row('m1', 'Chemistry | Chemistry; 3 or higher')], completeness_gate: { rule: 'D-R3', complete: false, except_fixable: false, flagged: [],
      reasons: ['the reader dropped 8 published row(s) that no admitted row covers (value_not_in_quote 8); left with no row at all: CN, so the read is incomplete: replace it with a corrected read, or reject it'] } })
    const held = item.locator('[data-l4-aer-gate="held"]')
    await expect(held).toContainText('Held: this read is incomplete, so it cannot be approved (D-R3)')
    await expect(held).toContainText('left with no row at all: CN')
    for (const c of ['approve', 'approve_except']) await expect(item.locator(`[data-l4-choice="${c}"]`)).toBeDisabled()
    await expect(item.locator('[data-l4-choice="reject"]')).toBeEnabled()
  })

  test('a matrix run whose only problems are rows (ANU ACT shape): Approve except opens and needs every flagged row ticked', async ({ page }) => {
    const calls = []
    const item = await open(page, { rows: [row('m1', 'ANU Entrance Rank: 70 | Indicative score required: 20'), row('m2', 'ANU Entrance Rank: 80 | Indicative score required: 23')],
      completeness_gate: { rule: 'D-R3', complete: false, except_fixable: true, flagged: [{ id: 'm1', why: 'the band holds label text, not a band' }],
        reasons: ['1 waiting row(s) cannot be admitted as read (the band holds label text, not a band 1): leave them out with Approve except, or replace the read with a corrected one'] } }, 'entry_matrix_first_run', calls)
    await expect(item.locator('[data-l4-aer-flag="m1"]')).toHaveText('Cannot be admitted as read: the band holds label text, not a band')
    await expect(item.locator('[data-l4-choice="approve"]')).toBeDisabled()
    await item.locator('[data-l4-choice="approve_except"]').click()
    await item.getByLabel('Reason').fill('Band printed as label text; corrected read to follow')
    await item.locator('[data-l4-aer-tick="m2"]').check()
    await expect(item.locator('[data-l4-confirm]')).toBeDisabled()
    await item.locator('[data-l4-aer-tick="m2"]').uncheck()
    await item.locator('[data-l4-aer-tick="m1"]').check()
    await expect(item.locator('[data-l4-aer-flag-needed]')).toHaveText('Every row that cannot be admitted as read is ticked.')
    await item.locator('[data-l4-confirm]').click()
    expect(calls.filter((c) => c.p_action === 'decide')).toHaveLength(1)
  })

  test('a course read with a dropped minimum no row covers: Approve except stays closed', async ({ page }) => {
    const item = await open(page, { rows: [{ id: 'r1', status: 'proposed', kind: 'prior_qualification', quote: 'A bachelors degree' }],
      completeness_gate: { rule: 'E13', complete: false, rows_cut: 0, shared_page: [], other_programme: [], not_requirement: [], audience: [],
        drops_uncovered: [{ reason: 'score_without_basis', quote: 'GPA 5.0' }], reasons: ['the reader dropped 1 printed requirement(s) that no waiting row covers (score_without_basis 1), so the read is incomplete: replace it with a corrected read, or reject it'] } }, 'course_entry_first_read')
    await expect(item.locator('[data-l4-aer-gate="held"]')).toContainText('(E13)')
    for (const c of ['approve', 'approve_except']) await expect(item.locator(`[data-l4-choice="${c}"]`)).toBeDisabled()
  })

  test('a corrected read shows what it replaced: rows added, removed and unchanged (D-R2)', async ({ page }) => {
    const item = await open(page, { rows: [{ id: 'r2', status: 'proposed', kind: 'minimum_grade', quote: 'with a grade point average of 5 or higher' }],
      completeness_gate: { rule: 'E13', complete: true, rows_cut: 0, shared_page: [], other_programme: [], reasons: [] },
      supersedes: { review_item_id: 'd2000000-0000-4000-8000-000000000009', unchanged: 1, reason: 'quote and basis fixed',
        added: [{ kind: 'minimum_grade', score: 5, basis: 'grade point average', quote: 'with a grade point average of 5 or higher' }], removed: [] } }, 'course_entry_first_read')
    const s = item.locator('[data-l4-aer-supersedes="d2000000-0000-4000-8000-000000000009"]')
    await expect(s).toContainText('Replaces an earlier read (D-R2), Ref d2000000')
    await expect(s).toContainText('1 added · 0 removed · 1 unchanged')
    await expect(s.locator('[data-l4-aer-diff="added"]')).toContainText('5 (grade point average)')
    await expect(item.locator('[data-l4-choice="approve"]')).toBeEnabled()  // a person still decides: nothing approved automatically
  })
})
