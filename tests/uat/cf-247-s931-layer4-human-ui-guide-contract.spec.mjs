// Guards: CF-247 s931 (Decision 279, Platform Admin 21 Nov 2026 10:53 and 12:28; spec admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md §8): (a) the preservation map covers the inventory, (b) the three decisions map to each queue's server choices, (c) gapStateOf precedence, (d) the guide's Filter & Badge Reference covers every filter of the six screens at the UI version, (e) the UI map is regenerated; D3 filter arguments, the verified count of Approve all verified for provider, the CRICOS/NZQA code proof of course descriptions, one fresh read for every Layer 4 count
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { INVENTORY, PRESERVATION_MAP } from '../../src/lib/l4-preservation-map.js'
import { THREE_DECISIONS, L4_QUEUES, decisionsFor, holdHintOf, lockable, DESC_PART, descPartOf } from '../../src/lib/l4-rules.js'
import { gapStateOf, officialUrlProblem } from '../../src/lib/field-gap.js'
import { FILTER_REFERENCE, FILTER_REFERENCE_REVIEWED_FOR } from '../../src/guide/filterReference.js'
import { WORKED_EXAMPLES } from '../../src/guide/workedExamples.js'
import { LAYER4_GUIDE } from '../../src/guide/layer4Guide.js'
import { UI_VERSION } from '../../src/release-manifest.js'
import { mockAdmin } from './support/admin-mock.mjs'

const src = (f) => fs.readFileSync(`src/${f}`, 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261121200000_cf247_s931_layer4_filters_cd_code_proof.sql', 'utf8')

test('(a) every inventory ID of §3 has a row in the §4 map, and every map row an inventory ID', () => {
  const ids = new Set(INVENTORY), rows = new Set(Object.keys(PRESERVATION_MAP))
  expect(ids.size).toBe(INVENTORY.length)
  expect([...ids].filter((x) => !rows.has(x))).toEqual([])
  expect([...rows].filter((x) => !ids.has(x))).toEqual([])
  for (const [id, r] of Object.entries(PRESERVATION_MAP)) { expect(r.map, id).toMatch(/^(K|M|R|N)(\+(K|M|R|N))?$/); expect(r.to.length, id).toBeGreaterThan(3) }
  // moved controls keep their hooks in their new place
  const inbox = src('Layer4Inbox.jsx'), prim = src('Layer4PrimaryFilters.jsx'), adv = src('Layer4AdvancedFilters.jsx'), bar = src('Layer4DecisionBar.jsx')
  expect(prim).toContain('data-l4-kind={k}'); expect(adv).toContain('data-l4-view={v}'); expect(adv).toContain('data-l4-other-views'); expect(adv).toContain('data-l4-aer-ready-first')
  expect(bar).toContain('data-l4-choice={c.key}'); expect(bar).toContain('data-l4-bar'); expect(inbox).toContain('data-l4-refshow'); expect(inbox).toContain('data-l4-handoff')
  // the old kind toolbar and view row are retired in place (not stacked)
  expect(inbox).not.toContain('className="l4i-kinds"'); expect(inbox).not.toContain('aria-label="Kinds of decision"')
})

// §3: the server choices of each queue (public.admin_layer4_inbox summary)
const SERVER = { course_link: ['keep', 'use', 'enter', 'refuse'], held_scholarship: ['publish', 'not_international', 'not_scholarship', 'duplicate'], website_needed: ['website', 'cricos_only', 'archive'],
  pages_not_found: ['website', 'pages', 'release', 'cricos_only'], too_few_pages: ['pages', 'cricos_only'], nothing_ready: ['adapter', 'rebuild', 'cricos_only'], central_to_approve: ['open'],
  onboarding_failed: ['retry', 'builder'], site_down: ['website', 'archive', 'wait'], not_offered: ['archive_course', 'keep'], fee_check: ['course', 'keep'], counsellor_report: ['report_fixed', 'report_not_changed', 'course'],
  not_on_site: ['archive_course', 'keep', 'course'], no_page_first_run: ['approve', 'has_page', 'reject'], conjoint_first_run: ['approve', 'parent', 'reject'], aer_review: ['approve', 'approve_except', 'reject'],
  provider_description: ['edit_approve', 'approve', 'reject', 'approve_provider', 'reread'], course_page_needed: ['add_page', 'search_again', 'no_page'], provider_departure: ['closed', 'merged', 'reviewed'] }

test('(b) the three decisions of every queue are its own server choices; the rest stay under More options', () => {
  expect(Object.keys(THREE_DECISIONS).sort()).toEqual([...L4_QUEUES].sort())
  for (const q of L4_QUEUES) {
    const t = THREE_DECISIONS[q], keys = SERVER[q]
    for (const w of ['yes', 'no', 'resubmit']) if (t[w] && !(q === 'aer_review' && w === 'resubmit')) expect(keys, `${q}.${w}`).toContain(t[w])
    const d = decisionsFor(q, keys.map((key) => ({ key, label: key })))
    const shown = [d.yes, d.no, d.resubmit].filter(Boolean).map((c) => c.key)
    expect([...shown, ...d.more.map((c) => c.key)].sort(), q).toEqual([...keys].sort())     // nothing lost, nothing twice
  }
  expect(THREE_DECISIONS.aer_review.resubmit).toBe('aer_det_reread')                        // §5.4: the $0 re-read from the stored copy
  const hook = decisionsFor('course_english', [{ key: 'search_again' }, { key: 'reject_evidence' }, { key: 'correct_value' }, { key: 'return_technical' }])
  expect([hook.yes.key, hook.no.key, hook.resubmit.key, hook.more.map((c) => c.key)]).toEqual(['correct_value', 'reject_evidence', 'search_again', ['return_technical']])
  expect(lockable('provider_description', 'edit_approve')).toBe(true); expect(lockable('course_link', 'use')).toBe(false)   // D4
  expect(holdHintOf('aer:gate_incomplete').example).toContain('8 countries'); expect(holdHintOf('nothing:known').title).toBe('Held by a check')
  expect(DESC_PART).toEqual({ course: 'Course description', university: 'University description' })       // fix 2
  expect(descPartOf({ key: 'cd:identity_margin_thin' })).toBe('course'); expect(descPartOf({ key: 'provider_description:held' })).toBe('university')
})

test('(c) gapStateOf: In review > University-wide > No URL > Not stated; otherwise "—" with the empty reason label', () => {
  expect(gapStateOf('f', { review: 2, universityWide: true, url: '', emptyReason: 'not_published_by_provider' })).toMatchObject({ state: 'in_review', count: 2 })
  expect(gapStateOf('f', { universityWide: true, url: '', emptyReason: 'not_published_by_provider' }).state).toBe('university_wide')
  expect(gapStateOf('f', { url: '', emptyReason: 'not_published_by_provider' }).state).toBe('no_url')
  expect(gapStateOf('f', { valueState: 'source_missing' }).state).toBe('no_url')
  expect(gapStateOf('f', { url: 'https://x.edu.au', emptyReason: 'not_published_by_provider' }).state).toBe('not_stated')
  expect(gapStateOf('f', { url: 'https://x.edu.au', emptyReason: 'pending_extraction' })).toMatchObject({ state: 'none', reason: 'Waiting to be read' })
  // D5: Add official URL, https on the provider's own host
  expect(officialUrlProblem('https://study.csu.edu.au/courses/x', 'https://www.csu.edu.au')).toBe('')
  expect(officialUrlProblem('http://csu.edu.au/x', 'https://csu.edu.au')).toMatch(/https/)
  expect(officialUrlProblem('https://example.com/x', 'https://csu.edu.au')).toMatch(/own site/)
  expect(src('FieldGapContext.jsx')).toContain("Number(rank)<3")
  expect(src('FieldGapContext.jsx')).toContain("p_action:'set_official_url'")
})

const labelsIn = (s) => [...s.matchAll(/<(?:FilterSelect|PagedFilterSelect|TriFilter)\b[^>]*?\blabel="([^"]+)"/g)].map((x) => x[1])
test('(d) the Filter & Badge Reference covers every filter of the six screens and is reviewed for the UI version', () => {
  expect(FILTER_REFERENCE_REVIEWED_FOR).toBe(UI_VERSION)
  const has = (screen, label) => FILTER_REFERENCE.some((x) => (!screen || x.screen === screen) && x.label === label)
  const main = src('mature-main.jsx'), bar = main.slice(main.indexOf('function FilterBar('), main.indexOf('function MoreFilters('))
  for (const l of new Set(labelsIn(bar))) expect(['Courses', 'Providers', 'Scholarships'].some((s) => has(s, l)), `catalogue filter ${l}`).toBe(true)
  expect(has('Courses', 'State / Region')).toBe(true)                                             // regionLabel(country)
  for (const l of new Set(labelsIn(src('AerWorkspace.jsx')))) expect(has('Entry requirements', l), `Entry requirements filter ${l}`).toBe(true)
  for (const l of ['Module / Field', 'University', 'Destination country', 'Source country', 'Decision bucket']) { expect(src('Layer4PrimaryFilters.jsx')).toContain(`<small>${l}</small>`); expect(has('Layer 4', l), l).toBe(true) }
  for (const l of ['View', 'University list', 'AER']) { expect(src('Layer4AdvancedFilters.jsx')).toContain(`<small>${l}</small>`); expect(has('Layer 4', l), l).toBe(true) }
  for (const l of ['Show policies', 'Document type', 'Stage']) expect(has('English', l), l).toBe(true)
  for (const b of ['In Layer 4 review (N waiting)', 'University-wide rule applies', 'No official website / course URL on file', 'Not stated on institution page']) expect(has('Badges', b), b).toBe(true)
  expect(WORKED_EXAMPLES.map((x) => x.key)).toEqual(['W1', 'W2', 'W3', 'W4'])
  expect(WORKED_EXAMPLES[0].title).toContain('Charles Sturt University (CRICOS 00005F)')
  expect(LAYER4_GUIDE.map((x) => x.key)).toEqual(['tell', 'card', 'decide', 'who', 'report'])
  const g = src('PlatformGuide.jsx')
  for (const p of ["['filters','Filters & badges'", "['layer4','Layer 4 guide'", "['examples','Worked examples'", 'data-guide-filters', 'data-guide-layer4', 'data-guide-examples', '<CoverageNotice']) expect(g).toContain(p)
  expect(src('CoverageNotice.jsx')).toContain('useLookups()')                                     // §6.3: countries from the database
})

test('(e) the UI map is regenerated for this release', () => {
  const map = fs.readFileSync('docs/UI-MAP.md', 'utf8')
  expect(map).toContain(UI_VERSION)
})

test('D3 and fixes 1 and 3: md5-guarded, read only, admitted through the same machine rule', () => {
  for (const h of ["'bc44180df893137e80ff98dc109b972c', 'e0f40bd31849b05555071bf416f79565'", "'44854a2ab12b21593c2891d7069daf29', 'c880b723a057b5abe9fe0b2fc07ff9bb'", "'c09a0345410bd82bde15502814800b11', 'de1d932aaa90c1d5243ea4cc4473a046'"]) expect(MIG).toContain(h)
  expect(MIG).toContain("v_src text := nullif(upper(btrim(p_args->>'source_country')), '')")
  expect(MIG).toContain("security.layer4_item_source_country_v1(v_kind, r.ref, v_src)")
  expect(MIG).toContain("v_proof := v_proof or coalesce(g.identity_basis in ('cricos_code', 'nzqa_code'), false);")
  expect(MIG).toContain("security.course_description_machine_admit_v1(q.id, 'settle')")
  expect(MIG).toContain('create or replace function public.admin_layer4_cd_provider_verified_v1(p_ref uuid) returns jsonb')
  expect(MIG).toMatch(/language plpgsql stable security definer set search_path to '' as \$f\$\ndeclare v_rank int/)
  expect(MIG).toContain("'post-check: the manual locks changed'"); expect(MIG).toContain('security.consumer_api_check_v1()')
  expect(MIG).not.toMatch(/\bdrop\s+(table|function|view)\b|\bdelete\s+from\b|cron\.schedule\(/i)
  // fix 1: the box is filled with the provider's own count; fix 5: one fresh read for every count
  expect(src('Layer4DecisionBar.jsx')).toContain("supabase.rpc('admin_layer4_cd_provider_verified_v1',{p_ref:ref})")
  expect(src('Layer4Inbox.jsx')).toContain('Approve all verified for provider (${fmtNumber(Number(verified.eligible)||0)})')
  expect(src('Layer4Focus.jsx')).toContain('const done=r=>{setGone(s=>new Set([...s,cur]));onDecided?.(r);load(true)}')
  expect(src('Layer4Inbox.jsx')).toContain('countOf={k=>focus&&k===kind&&ftotal!=null&&!part?ftotal:Number(bk[k]?.n)||0}')
})

test.describe('mocked browser', () => {
  const item = { kind: 'course_link', ref: 'cl-1', provider_id: 'p1', provider: 'Charles Sturt University', subject: 'Bachelor of Nursing', created_at: '2026-11-02T01:00:00Z', why: 'Machine rule demo-v1 did not admit this: page_moved',
    detail: { course_id: 'c1', before: 'https://study.csu.edu.au/old', proposed: 'https://study.csu.edu.au/new' } }
  const kinds = { course_link: { label: 'Course link', order: 1, choices: [{ key: 'keep', label: 'Keep the page we hold', returns: 'Kept' }, { key: 'use', label: 'Use the new page', returns: 'Used' }, { key: 'enter', label: 'Enter another address', input: 'url', returns: 'Bound' }, { key: 'refuse', label: 'Refuse', returns: 'Refused' }] } }
  let n, left
  const route = async (page) => {
    n = 3; left = ['cl-1', 'cl-2', 'cl-3']
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (r) => {
      const b = r.request().postDataJSON()
      if (b.p_action === 'summary') return r.fulfill({ json: { kinds, target_days: 14, rank: 6, total: n, universities: 1, late: 0, by_kind: { course_link: { n } } } })
      if (b.p_action === 'rule_groups') return r.fulfill({ json: { kind: 'course_link', built_in: true, total: n, batch_max: 50, ms: 4, groups: [{ key: 'course_link:moved', label: 'The page moved', n, late: 0, refs: left } ] } })
      if (b.p_action === 'rule_group_items') return r.fulfill({ json: { items: (b.p_args.refs || []).map((ref) => ({ ...item, ref })) } })
      if (b.p_action === 'decide') { n -= 1; left = left.filter((x) => x !== b.p_args.ref); return r.fulfill({ json: { ok: true, kind: 'course_link', ref: b.p_args.ref, outcome: 'refused', headline: 'Refused' } }) }
      return r.fulfill({ json: {} })
    })
  }
  test('the card: Yes / No / Resubmit bar, More options, reject chips, Advanced filters (N); every count agrees after a decision', async ({ page }) => {
    await mockAdmin(page, { rank: 6, moreOpen: false }); await route(page)
    await page.goto('/#layer-4-review')
    const card = page.locator('[data-l4-focus-card] [data-l4-item="course_link"]')
    await expect(card).toBeVisible()
    await expect(card.locator('[data-l4-decision="yes"]')).toContainText('Yes (Approve)')
    await expect(card.locator('[data-l4-decision="no"]')).toContainText('No (Reject)')
    await expect(card.locator('[data-l4-decision="resubmit"]')).toHaveCount(0)                  // course_link has no re-read path (D2)
    await expect(card.locator('[data-l4-choice="keep"]')).toHaveCount(0)
    await card.locator('[data-l4-more-toggle]').click()
    await expect(card.locator('[data-l4-more] [data-l4-choice="keep"]')).toBeVisible()
    await expect(card.locator('[data-l4-refshow]')).toBeHidden()                                 // Technical detail, closed
    await expect(page.locator('[data-l4-advanced-toggle]')).toHaveText(/Advanced filters \(0\)/)
    await expect(page.locator('[data-l4-module-toggle]')).toContainText('Course link (3)')
    await expect(page.locator('[data-l4-focus-group="all"] .l4r-n')).toHaveText('3')
    await expect(page.locator('[data-l4-focus-pos]')).toContainText('Card 1 of 3')
    await card.locator('[data-l4-decision="no"]').click()
    await card.locator('[data-l4-reject-chip="Wrong course"]').click()
    await expect(card.getByLabel('Reason')).toHaveValue('Wrong course')
    await card.locator('[data-l4-confirm]').click()
    await expect(page.locator('[data-l4-module-toggle]')).toContainText('Course link (2)')
    await expect(page.locator('[data-l4-focus-group="all"] .l4r-n')).toHaveText('2')
    await expect(page.locator('[data-l4-focus-pos]')).toContainText('of 2')
  })
})
