// Guards: E13 (Platform Admin 2 Nov 2026 05:18)
// "E13 — Entry-requirement completeness. Decision: APPROVE development of the whole-read completeness gate." A course entry read is proposed
// whole or held whole (rows over the limit, over_row_limit); a joined requirement cut by the limit is named; a row about a sibling programme
// variant is not proposed, and holds approval while it waits; a page shared with another programme holds approval; the limit stays a setting,
// raised only per provider; nothing incomplete reaches approval. No global raise, no re-read, no AI charge, nothing switched on by a test.
// The behaviour is run on isolated fixtures by tests/fixtures/e13-completeness-gate/run.sh (scratch PostgreSQL; the live definitions are
// rebuilt from this repository's migrations and checked against the live md5s); this spec holds the contract and the review screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261102010000_cf247_e13_entry_completeness_gate.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/e13-completeness-gate'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('\n$$', a)) }
const reader = fn('security.enrich_entry_record_v1')
const ui = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')

const BEFORE = { 'security.enrich_entry_record_v1(bigint,jsonb)': '857102dc182426a841a41e7244f7a088',
  'security.course_entry_review_apply_v1(uuid,text,jsonb,text)': 'ce8d0bad9717034342f165b1876fb632', 'security.aer_review_read_v1(uuid)': '62793b3544874e91a1e2aa26b80e8a14' }
const AFTER = { 'security.enrich_entry_record_v1(bigint,jsonb)': '9757abeeb3700c5cd2e02385def05869',
  'security.course_entry_review_apply_v1(uuid,text,jsonb,text)': '4be9267d8419dee7d9f80cb96ff4098b', 'security.aer_review_read_v1(uuid)': '50c31fc4df16b7bbbb39dab03aa9f9b2' }

test('the three changed functions are guarded by their live md5 before and checked after; the fixture run checks the same values', () => {
  const calls = [...m.matchAll(/select pg_temp\.(replace_once|edit_once)\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, how, sig, b, a]) => [sig, b, a, how])
  expect(calls).toEqual(Object.keys(BEFORE).map((s, i) => [s, BEFORE[s], AFTER[s], i === 0 ? 'replace_once' : 'edit_once']))
  expect(code).toContain("if v_md5 <> p_before then raise exception 'live % differs from the definition this change replaces (md5 %)', p_sig, v_md5; end if;")
  expect(code).toContain("raise exception '% after the change has md5 %, expected %'")
  expect(run).toContain(`"${Object.values(BEFORE).join(' ')}"`)  // the rebuilt definitions must equal live before the migration runs
  for (const [sig, after] of Object.entries(AFTER)) expect(m).toContain(after, sig)
  expect(run).toContain("grep -c 'already applied' | grep -qx 3")  // a second run changes nothing
})

test('rows over the limit hold the whole read: nothing proposed, no Layer 4 item, every row read kept on the item', () => {
  expect(reader).toContain('v_max := security.course_entry_max_rows_v1(g.provider_id);')
  const hold = reader.indexOf('if v_n > v_max then'), insert = reader.indexOf('insert into catalogue.course_entry_requirements'), review = reader.indexOf('insert into pipeline.layer4_review_items')
  expect(hold).toBeGreaterThan(0)
  expect(insert).toBeGreaterThan(hold); expect(review).toBeGreaterThan(hold)  // rows are inserted only after the whole read is known
  expect(reader.slice(hold, insert)).toContain("return 'held_partial';")
  expect(reader).toContain("format('held_partial: over_row_limit: the page has %s requirements and the limit is %s%s; nothing proposed (E13)'")
  expect(reader).toContain("value = jsonb_build_object('held', 'over_row_limit', 'limit', v_max, 'rows_read', v_keep, 'dropped', v_drop")
  expect(reader).not.toContain('if v_in >= v_max then')  // the cut that proposed the first rows is gone
  expect(fixtures).toContain("raise notice 'PASS over the limit held whole';")
})

test('a joined requirement cut by the limit is named, by its first word or its kind (both settings)', () => {
  const j = fn('security.course_entry_joined_v1')
  expect(j).toContain("security.toolset_setting('pipeline', 'entry.joined_condition_kinds')")
  expect(j).toContain("security.toolset_setting('pipeline', 'entry.joined_condition_words')")
  expect(fn('security.course_entry_gate_v1')).toContain("d->>'reason' = 'over_row_limit' and security.course_entry_joined_v1(d->>'quote', d->>'kind')")
  expect(m).toContain(`'["and", "plus", "together with", "as well as", "in addition"]'::jsonb`)
  expect(m).toContain(`'["work_experience"]'::jsonb`)
  expect(fixtures).toContain("raise notice 'PASS joined conditions';")
})

test('a row about a sibling programme variant is not proposed and does not count; waiting ones and shared pages hold approval', () => {
  const v = reader.indexOf('v_other := security.course_entry_variant_v1(i.course_id, v_q);')
  expect(v).toBeGreaterThan(0)
  expect(v).toBeLessThan(reader.indexOf('v_keep := v_keep ||'))
  expect(reader).toContain("jsonb_build_object('reason', 'other_programme', 'kind', v_kind, 'quote', v_q, 'names', v_other); continue;")
  const g = fn('security.course_entry_gate_v1')
  expect(g).toContain("x.status = 'proposed' and not (x.id = any (coalesce(p_exclude, '{}'::uuid[]))) and n.v is not null")
  expect(g).toContain("security.pipeline_num_v1('entry.shared_page_hold', 1) >= 1")
  for (const k of ['entry.variant_check', 'entry.variant_check_off_providers', 'entry.award_abbreviations']) expect(fn('security.course_entry_variant_v1')).toContain(`'${k}'`)
  for (const p of ['PASS sibling rows at read', 'PASS other-programme cases', 'PASS approval held: other programme', 'PASS approval held: shared page']) expect(fixtures).toContain(`raise notice '${p}';`)
})

test('the limit stays a setting (no global raise), with a per-provider value inside its range', () => {
  expect(code).not.toMatch(/update pipeline\.platform_toolset_settings/)
  expect(code).not.toMatch(/'entry\.max_rows_per_course',\s*'[^']*',\s*'[^']*',\s*'[^']*',\s*'number'/)  // not re-inserted either
  const r = fn('security.course_entry_max_rows_v1')
  expect(r).toContain("security.toolset_setting('pipeline', 'entry.max_rows_by_provider')")
  expect(r).toContain("join pipeline.platform_toolset_settings s on s.toolset_key = 'pipeline' and s.key = 'entry.max_rows_per_course'")
  expect(r).toContain("security.pipeline_num_v1('entry.max_rows_per_course', 6)::int)")
  for (const k of ['entry.max_rows_by_provider', 'entry.joined_condition_words', 'entry.joined_condition_kinds', 'entry.variant_check', 'entry.shared_page_hold', 'entry.variant_check_off_providers', 'entry.award_abbreviations'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}', 'Course entry requirements: [^']+',\\n  '`))
  expect(fixtures).toContain("raise notice 'PASS provider limit';")
})

test('an incomplete read never reaches approval: Approve and Approve except are refused with nothing changed; Reject is unchanged', () => {
  const e = m.slice(m.indexOf("select pg_temp.edit_once('security.course_entry_review_apply_v1"), m.indexOf("select pg_temp.edit_once('security.aer_review_read_v1"))
  expect(e).toContain("$o$    v_ex := coalesce(array(select jsonb_array_elements_text(coalesce(p_final->'exclude_row_ids', '[]'::jsonb))::uuid), '{}');\n$o$")
  expect(e).toContain('v_gate := security.course_entry_gate_v1(p_item, v_ex);')
  expect(e).toContain("raise exception 'Held (E13, incomplete read): %. Nothing was changed',")
  expect(e).toContain("using errcode = '55000';")
  // the gate is inside "if p_action = 'approve'" (the edit sits right after the exclusions are read), before the D4 check and any update
  expect(e).not.toMatch(/\bupdate\b/)
  expect(fixtures).toContain("raise notice 'PASS approval held: cut read';")
  expect(fixtures).toContain("perform pg_temp.ok((select status from catalogue.course_entry_requirements where id = v_row) = 'inactive', 'reject still works');")
})

test('no re-read, no AI or page fetch, nothing approved, withdrawn or re-opened by the change', () => {
  expect(code).not.toMatch(/course_entry_read_enqueue_v1\(|course_entry_batch_v1\(|insert into pipeline\.(admin_jobs|field_enrich_items)|cron\.schedule/)
  const outside = code.replace(/\$def\$[\s\S]*?\$def\$/g, '').replace(/\$\$[\s\S]*?\$\$/g, '').replace(/\$[on]\$[\s\S]*?\$[on]\$/g, '')
  expect(outside).not.toMatch(/\b(update|delete)\s+(pipeline|catalogue)\./)
  expect(m).toContain('the 59 approved capped reads stay as they are')
})

test.describe('mocked browser', () => {
  const ITEM = '5e130000-0000-4000-8000-000000000001'
  const inbox = (calls) => async (route) => {
    const b = route.request().postDataJSON(); calls.push(b)
    const kinds = { aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [
      { key: 'approve', label: 'Approve all rows', rank: 6, returns: 'Every waiting row becomes active once the checks pass' },
      { key: 'approve_except', label: 'Approve except…', rank: 6, input: 'rows', returns: 'The ticked rows stay unadmitted, marked excluded with your reason' },
      { key: 'reject', label: 'Reject the read', rank: 6, returns: 'No row is admitted' }] } }
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { aer_review: { n: 1 } } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p-eit', name: 'Eastern Institute of Technology', country: 'NZ', n: 1, by_kind: { aer_review: 1 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [{ kind: 'aer_review', ref: ITEM, provider_id: 'p-eit', subject: 'Master of Information Technology (240) (Level 9)',
      why: 'Course entry requirements first read', created_at: '2026-11-01T00:00:00Z', detail: { field_code: 'course_entry_first_read' } }] } })
    if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'The ticked rows stay unadmitted' } })
    return route.fulfill({ json: {} })
  }
  const read = (gate) => ({ review_item_id: ITEM, kind: 'course_entry_first_read', status: 'pending', can_decide: true, evidence_id: null, decision: null,
    lineage: { source_url: 'https://www.eit.ac.nz/programmes/master-of-information-technology/' }, completeness_gate: gate,
    rows: [{ id: 'r-own', status: 'proposed', kind: 'prior_qualification', description: 'A NZQF-listed undergraduate degree', quote: 'The academic entry requirement for the MIT (240) is one of the following: A NZQF-listed undergraduate degree' },
           { id: 'r-sib', status: 'proposed', kind: 'prior_qualification', description: 'A Bachelor Honours degree', quote: 'The academic entry requirement for the MIT (180) is one of the following: A Bachelor Honours degree' }] })
  const open = async (page, gate, calls) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', inbox(calls))
    await page.route('https://example.supabase.co/rest/v1/rpc/layer4_aer_review_read', (route) => route.fulfill({ json: read(gate) }))
    await page.goto('/#layer-4-review')
    return page.locator('[data-l4-item="aer_review"]')
  }

  test('a read cut by the row limit, or from a shared page: held, with the reasons, and neither approval can be chosen', async ({ page }) => {
    const calls = []
    const item = await open(page, { rule: 'E13', complete: false, rows_cut: 3, joined: [{ kind: 'work_experience', quote: 'plus two years of relevant work experience' }], other_programme: [],
      shared_page: ['Master of Information Technology (180) (Level 9)'], reasons: ['the reader cut 3 requirement(s) on this page at its row limit, so the read is incomplete: reject it',
        '1 of the cut requirement(s) belong to a requirement that was kept (for example "plus two years of relevant work experience")',
        'the stored page is also the page of 1 other programme(s) (Master of Information Technology (180) (Level 9)), so its rows cannot be told apart by programme: reject the read'] }, calls)
    const held = item.locator('[data-l4-aer-gate="held"]')
    await expect(held).toContainText('Held: this read is incomplete, so it cannot be approved (E13)')
    await expect(held).toContainText('The reader cut 3 requirement(s) on this page at its row limit')
    await expect(held).toContainText('plus two years of relevant work experience')
    await expect(held).toContainText('also the page of 1 other programme(s)')
    for (const c of ['approve', 'approve_except']) await expect(item.locator(`[data-l4-choice="${c}"]`)).toBeDisabled()
    await expect(item.locator('[data-l4-choice="reject"]')).toBeEnabled()
    expect(calls.some((c) => c.p_action === 'decide')).toBe(false)
  })

  test('a waiting row about another programme: marked; Approve all is held; Approve except needs that row ticked', async ({ page }) => {
    const calls = []
    const item = await open(page, { rule: 'E13', complete: false, rows_cut: 0, joined: [], shared_page: [], other_programme: [{ id: 'r-sib', names: 'MIT (180)', quote: '…' }],
      reasons: ['1 waiting row(s) are about another programme (MIT (180)): leave them out with Approve except, or reject the read'] }, calls)
    await expect(item.locator('[data-l4-aer-other="r-sib"]')).toHaveText('About another programme: MIT (180)')
    await expect(item.locator('[data-l4-aer-other="r-own"]')).toHaveCount(0)
    await expect(item.locator('[data-l4-choice="approve"]')).toBeDisabled()
    await item.locator('[data-l4-choice="approve_except"]').click()
    await item.getByLabel('Reason').fill('The MIT (180) route belongs to the 180 point master')
    await item.locator('[data-l4-aer-tick="r-own"]').check()
    await expect(item.locator('[data-l4-aer-other-needed]')).toHaveText('Tick the row about another programme to leave it out.')
    await expect(item.locator('[data-l4-confirm]')).toBeDisabled()
    await item.locator('[data-l4-aer-tick="r-own"]').uncheck()
    await item.locator('[data-l4-aer-tick="r-sib"]').check()
    await expect(item.locator('[data-l4-aer-other-needed]')).toHaveText('Every row about another programme is ticked.')
    await item.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status')).toContainText('Done.')
    const d = calls.filter((c) => c.p_action === 'decide')
    expect(d).toHaveLength(1)
    expect(JSON.parse(d[0].p_args.value)).toEqual(['r-sib'])
  })

  test('a whole read: says so, and every choice stays open', async ({ page }) => {
    const item = await open(page, { rule: 'E13', complete: true, rows_cut: 0, joined: [], other_programme: [], shared_page: [], reasons: [] }, [])
    await expect(item.locator('[data-l4-aer-gate="complete"]')).toContainText('Read whole: no requirement was cut and no row is about another programme.')
    for (const c of ['approve', 'approve_except', 'reject']) await expect(item.locator(`[data-l4-choice="${c}"]`)).toBeEnabled()
    expect(ui).toContain("const gate=aer?.kind==='course_entry_first_read'?aer.completeness_gate:null,held=gate?.complete===false")
  })
})
