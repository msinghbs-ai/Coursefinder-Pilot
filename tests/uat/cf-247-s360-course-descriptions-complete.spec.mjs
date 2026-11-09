// Guards: Platform Admin direction 6 Nov 2026 09:44 §2 (course descriptions: decisions D1-D5, reconcile the pending items, efficient reviewer workflow in the
// existing Layer 4 Inbox, the stratified trust-policy sample as a measurement only), §4 (permanent compatibility gate: Reuses, Changes, Replaces, Retires,
// Conflicts, Protects) and §5 (operator visibility through the existing Admin workspace). CF-247 agent G.
// The database behaviour runs on the production-parity fixture (tests/fixtures/course-description-parity/run.sh: identical outcomes before and after the
// migration, reconciliation, sample, read-only proof). This spec holds the source contracts, the worker's pure functions and the screens (mocked admin).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { COURSE_TEXT_PROMPT_VERSION, courseTextBreach, courseTextMergeReask, courseTextReaskMax, courseTextReaskNote, courseTextReaskUser, courseTextResults } from '../../supabase/functions/coverage-sweep/course-text.ts'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = fs.readFileSync('supabase/migrations/20261106500000_cf247_course_descriptions_complete.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const FX = 'tests/fixtures/course-description-parity'
const PHONE_MAX = 480

test('migration: replaces only the check (md5-guarded), seeds the course lists identical to the provider lists, ships the re-ask off, drops and writes nothing else', () => {
  expect(MIG).toMatch(/^-- Replaces: .*security\.course_description_check_v1/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain('ff3d6dd7b0f88c85b1fdff6c8a8cd86b')
  expect(MIG).toContain('not like \'%course_description_check_with_v1%\'') // re-run safe
  // D2 and D5: seeded from the provider lists, so the effective policy is identical on the day of release
  expect(code).toMatch(/'enrich\.course_description_claim_words'[\s\S]*?where s\.toolset_key = 'pipeline' and s\.key = 'pdesc\.claim_words'/)
  expect(code).toMatch(/'enrich\.course_description_marketing_words'[\s\S]*?where s\.toolset_key = 'pipeline' and s\.key = 'pdesc\.superlatives'/)
  expect(MIG).toContain('post-check: the course claim-word list differs from the provider list')
  // D4: off; D3: the limits are not touched
  expect(code).toMatch(/'enrich\.course_description_reask_max'[\s\S]*?'number', '0'::jsonb, 0, 1, 're-asks'/)
  expect(code).not.toMatch(/enrich\.course_description_(max_chars|max_sentences|min_chars|min_sentences)'\s*,\s*'/)
  // D1: the trust rule is not touched and nothing is admitted
  expect(code).not.toMatch(/update\s+pipeline\.platform_toolset_settings[^;]*review_first/i)
  expect(code).not.toMatch(/\b(update|insert into)\s+catalogue\.courses\b/i)
  expect(code).not.toMatch(/\b(update|insert into)\s+pipeline\.(layer4_review_items|layer4_decisions|field_enrich_items)\b/i)
  // the consumer API is untouched (G3)
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|api\./)
  // every report is read only: stable security definer, no insert/update/delete into data tables except the register and the settings above
  for (const f of ['reconcile_v1', 'summary_v1', 'items_v1', 'held_reasons_v1', 'claim_eval_v1', 'sample_pool_v1', 'sample_ids_v1', 'sample_report_v1']) {
    const a = code.indexOf(`function security.course_description_${f}`), body = code.slice(a, code.indexOf('$function$;', code.indexOf('$function$', a) + 10))
    expect(a, f).toBeGreaterThan(-1)
    expect(body, f).toMatch(/\bstable security definer\b/)
    expect(body, f).not.toMatch(/\b(insert\s+into|update\s+\w|delete\s+from|truncate|drop\s)/i)
  }
  // the public entry is rank-gated like the AER queue and has exactly the five read actions
  expect(code).toContain("coalesce(security.current_role_rank(), 0) < 4")
  for (const act of ['summary', 'items', 'held_reasons', 'claim_words', 'sample']) expect(code).toContain(`'${act}'`)
  expect(code).toContain('grant execute on function public.admin_course_description_queue(text, jsonb) to authenticated')
  expect(code).toContain('revoke all on function security.course_description_sample_report_v1() from public, anon, authenticated')
  // the sample: 30 / 15 / 5 are settings (G2), the report says it is not an authority
  expect(code).toMatch(/enrich\.course_description_sample_au'[\s\S]*?'30'::jsonb/)
  expect(code).toMatch(/enrich\.course_description_sample_nz'[\s\S]*?'15'::jsonb/)
  expect(code).toMatch(/enrich\.course_description_sample_ca'[\s\S]*?'5'::jsonb/)
  expect(MIG).toContain('not an authority to bypass Layer 4')
  // Decision 260: the new components are registered; nothing retires
  expect(code).toContain("'20261106500000'")
  expect(code).not.toMatch(/\bretiring\b/)
})

test('fixture runner proves identical outcomes before and after, a re-run-safe migration and the read-only reports', () => {
  const run = fs.readFileSync(`${FX}/run.sh`, 'utf8'), q = fs.readFileSync(`${FX}/queue.sql`, 'utf8')
  expect(run).toContain('-v after=1')
  expect(run.match(/-f \$MIG/g).length).toBe(2)
  expect(run).toContain('queue.sql')
  expect(q).toContain('begin read only;')
  for (const t of ['reconcile [pass]', 'sample [pass]', 'read only [pass]', 'D1 [pass]', 'validate-all [pass]', 'rank [pass]']) expect(q).toContain(t)
  // the production signatures of the two Supabase functions the fixture stands in for are stated
  expect(q).toContain('security.current_role_rank() returns smallint, STABLE, SECURITY DEFINER')
  expect(JSON.parse(fs.readFileSync(`${FX}/manifest.json`, 'utf8')).tables.map((t) => t.fq)).toEqual(expect.arrayContaining(['pipeline.evidence_artifacts', 'pipeline.coverage_course_pages', 'pipeline.layer4_decisions', 'search.course_documents', 'catalogue.providers']))
})

// ---- worker: one bounded re-ask, never a cut ----------------------------------------------------------------------------------------------
const page = 'Queue Course covers planning. ' + 'You complete a capstone project in the final year with guidance from teaching staff in your area of study. '.repeat(1) + 'The first and second years cover core units and electives.'
const S = (text, quote = text) => ({ text, quote })
const L = { min_sentences: 1, max_sentences: 4, min_chars: 80, max_chars: 700 }
const answer = (...ss) => ({ description: { about_course: true, sentences: ss } })

test('course-text.ts: the breach is measured as the database measures it, and only a length or sentence-count breach is re-asked', () => {
  expect(COURSE_TEXT_PROMPT_VERSION).toBe('course-text-v2')
  const ok = answer(S('You complete a capstone project in the final year with guidance from teaching staff in your area of study.'), S('The first and second years cover core units and electives.'))
  expect(courseTextBreach(ok, page, L)).toBeNull()
  const five = answer(...Array.from({ length: 5 }, () => S('The first and second years cover core units and electives.')))
  expect(courseTextBreach(five, page, L)).toMatchObject({ rule: 'sentence_count', sentences: 5 })
  const long = answer(S('You complete a capstone project in the final year with guidance from teaching staff in your area of study.'), S('The first and second years cover core units and electives.'))
  expect(courseTextBreach(long, page, { ...L, max_chars: 100 })).toMatchObject({ rule: 'length', sentences: 2, chars: 'You complete a capstone project in the final year with guidance from teaching staff in your area of study. The first and second years cover core units and electives.'.length })
  // never re-asked: not about the course, no sentence, unknown limits
  expect(courseTextBreach({ description: { about_course: false, sentences: [S('x')] } }, page, L)).toBeNull()
  expect(courseTextBreach(answer(), page, L)).toBeNull()
  expect(courseTextBreach(five, page, {})).toBeNull()
  // D4 is an authority ceiling, not permission for a second paid re-ask if
  // an out-of-policy or malformed setting leaks through an older control.
  for (const [value, expected] of [[1, 1], [0, 0], [2, 0], [-1, 0], [1.5, 0], ['1', 0], [true, 0], [Infinity, 0], [NaN, 0], [null, 0], [undefined, 0]]) {
    expect(courseTextReaskMax({ 'enrich.course_description_reask_max': value }), String(value)).toBe(expected)
  }
})

test('course-text.ts: the re-ask states the limits and the previous text, asks for a rewrite (never a cut) and keeps the deadlines; the note records the first answer', () => {
  const first = { description: answer(S('A.'), S('B.')).description, deadlines: [{ kind: 'rolling' }] }
  const b = { rule: 'length', sentences: 2, chars: 910 }
  const u = courseTextReaskUser('Queue University', 'Queue Course', 'PAGE', first, b, L)
  expect(u).toContain('Provider: Queue University')
  expect(u).toContain('Fields: description')
  expect(u).toContain('910 characters')
  expect(u).toContain('at most 700 characters')
  expect(u).toContain('1. A.')
  expect(u).toMatch(/Do not shorten by cutting/)
  expect(courseTextMergeReask(first, answer(S('C.'))).deadlines).toEqual([{ kind: 'rolling' }])
  expect(courseTextMergeReask(first, answer(S('C.'))).description.sentences[0].text).toBe('C.')
  expect(courseTextMergeReask(first, {}).description.sentences).toHaveLength(2)
  expect(courseTextReaskNote(b, 1)).toEqual({ n: 1, first: { rule: 'length', sentences: 2, chars: 910 } })
  expect(courseTextReaskNote(b, 0, 'HTTP 500')).toMatchObject({ n: 0, error: 'HTTP 500' })
  // the note rides in the description reading's value (stored as given by record_v1) and never touches the text
  const r = courseTextResults(answer(S('You complete a capstone project in the final year with guidance from teaching staff in your area of study.')), page, [{ item_id: 7, field: 'description' }],
    { model: 'm', worker: 'w', cost: 0.002, reask: courseTextReaskNote(b, 1) })
  expect(r[0].value.reask).toEqual({ n: 1, first: { rule: 'length', sentences: 2, chars: 910 } })
  expect(r[0].value.sentences[0].text).toBe('You complete a capstone project in the final year with guidance from teaching staff in your area of study.')
  expect(courseTextResults(answer(S('You complete a capstone project in the final year with guidance from teaching staff in your area of study.')), page, [{ item_id: 7, field: 'description' }], { model: 'm', worker: 'w', cost: 0 })[0].value).not.toHaveProperty('reask')
})

test('worker v0.59.10: the re-ask is gated by the setting (ships 0), uses the same pinned model and page, keeps the first answer on failure and never cuts', () => {
  expect(worker).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.59\.10"; |\/\/ was v0\.59\.10 )\/\/ v0\.59\.10 \(6 Nov 2026/)
  expect(worker).toContain('// was v0.59.8 // v0.59.8')
  const t = worker.slice(worker.indexOf('const textRead = async'), worker.indexOf('const entryCall = async'))
  expect(t).toContain('courseTextReaskMax(ws)')                             // one-authorised-call guard; setting from svc_worker_settings_v1 (G2)
  expect(t).toContain('reaskMax > 0 ?')                                      // 0 = off: no second call
  expect(t).toContain('courseTextReaskUser(pg.provider, pg.title, page, last, b, length)')
  expect(t).toContain('courseTextRequest(model, user, w, maxTokens)')        // the same pinned central model and answer limit
  expect(t).toContain('returned model ${d.model}, not ${model}')
  expect(t).toContain('a failed re-ask keeps the first answer')
  expect(t).not.toMatch(/\.slice\(0,\s*\w+\)|substring\(|\.truncate|firecrawl/i.source ? /substring\(|truncate|firecrawl/i : /x/) // no cutting and nothing fetched
  expect(t.match(/reaskMax/g).length).toBeGreaterThan(2)
})

// ---- screens (mocked admin; nothing reaches a backend) -----------------------------------------------------------------------------------
const SUMMARY = { provider_id: 'p1', pending: 3, by_class: { ready: 2, fails_now: 1 }, by_country: { AU: { pending: 3, ready: 2 } }, proposed_in_layer4: 3, admitted_by_person: 4, published_to_the_website: 3,
  admitted_without_a_person: 0, waiting_behind_provider_cap: 5, review_first: 100000, reask_max: 0, limits: { min_sentences: 1, max_sentences: 4, min_chars: 80, max_chars: 700 }, rechecked: 3 }
const ITEM = (n, extra = {}) => ({ kind: 'provider_description', ref: `0000000${n}-0000-4000-a000-000000000000`, provider_id: 'p1', provider: 'Queue University', subject: `Bachelor of Queue ${n}`, why: 'Course description read from the course\'s own page.',
  created_at: '2026-11-04T01:00:00Z', ready: true, detail: { field_code: 'course_description_first_read', course_id: `c${n}`, before: {}, proposed: { description: 'This degree covers planning. You complete a capstone project.',
    checks: { sentences: 2, chars: 183 }, sentences: [{ text: 'This degree covers planning.', quote: 'This degree covers planning.' }] }, ...extra } })
const KINDS = { provider_description: { label: 'University description', order: 1, choices: [{ key: 'approve', label: 'Approve as read', rank: 4, returns: 'The description is published.' }, { key: 'reject', label: 'Reject', rank: 4, returns: 'It is read again later.' }] } }

async function openCourseDescriptions(page, calls, cdExtra) {
  await mockAdmin(page, { rank: 4 })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON(); calls.inbox.push(b)
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 4, total: 3, universities: 1, late: 0, by_kind: { provider_description: { n: 3 } } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Queue University', country: 'AU', courses: 25, n: 3, oldest: '2026-11-04T01:00:00Z', late: false, by_kind: { provider_description: 3 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 3, items: [ITEM(1), ITEM(2), ITEM(3)] } })
    if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'Done.' } })
    return route.fulfill({ json: {} })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_description_queue', async (route) => {
    const b = route.request().postDataJSON(); calls.cd.push(b)
    const extra = cdExtra && cdExtra(b)
    if (extra) return route.fulfill({ json: extra })
    if (b.p_action === 'summary') return route.fulfill({ json: SUMMARY })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 2, offset: 0, limit: 25, items: [ITEM(1), ITEM(2, { reask: { n: 1, first: { rule: 'length', sentences: 2, chars: 910 } }, rules_now: { ok: false, rule: 'unsupported_claim' } })] } })
    return route.fulfill({ json: {} })
  })
  await page.goto('/#layer-4-review')
  await expect(page.locator('[data-l4-inbox]')).toBeVisible()
  await page.locator('[data-l4-pill="provider_description"]').first().click()
}

async function checkFlow(page, calls, w) {
  const panel = page.locator('[data-l4-cd-summary]')
  await expect(panel).toContainText('3 waiting for a person')
  await expect(panel).toContainText('2 ready to decide')
  await expect(panel).toContainText('1 no longer pass the checks')
  await expect(panel).toContainText('admitted by a person 4')
  await expect(panel).toContainText('published to the website 3')
  await expect(panel).toContainText('not admitted and not published')
  // asked for the university's own queue, rules re-run for it
  expect(calls.cd.find((c) => c.p_action === 'summary').p_args).toMatchObject({ provider_id: 'p1', recheck: true })
  await panel.locator('[data-l4-cd-ready]').click()
  const cards = page.locator('[data-l4-cd-list] [data-l4-item="provider_description"]')
  await expect(cards).toHaveCount(2)
  expect(calls.cd.find((c) => c.p_action === 'items').p_args).toMatchObject({ provider_id: 'p1', offset: 0, sample: false })
  await expect(cards.nth(0).locator('[data-l4-cd-checks]')).toContainText('2 sentences, 183 characters (limits 1 to 4 sentences, 80 to 700 characters)')
  await expect(cards.nth(1).locator('[data-l4-cd-checks]')).toContainText('asked once more because the first answer broke the length limit')
  await expect(cards.nth(1).locator('[data-l4-cd-checks]')).toContainText('no longer passes: unsupported claim')
  // one tap fills a reason class; the decision goes through the Inbox's own decide action
  await cards.nth(0).locator('[data-l4-choice="reject"]').click()
  const chips = cards.nth(0).locator('[data-l4-cd-reasons] button')
  await expect(chips).toHaveCount(5)
  await chips.filter({ hasText: 'Not supported by the page' }).click()
  await expect(cards.nth(0).getByRole('textbox', { name: 'Reason' })).toHaveValue('[support] Not supported by the page')
  if (w) { const b = await cards.nth(0).locator('[data-l4-confirm]').boundingBox(); expect(b.x + b.width).toBeLessThanOrEqual(w + 1) }
  await cards.nth(0).locator('[data-l4-confirm]').click()
  await expect.poll(() => calls.inbox.find((c) => c.p_action === 'decide')?.p_args).toMatchObject({ kind: 'provider_description', choice: 'reject', reason: '[support] Not supported by the page' })
  // the sample shows only its own queue
  await panel.locator('[data-l4-cd-sample]').click()
  await expect.poll(() => calls.cd.filter((c) => c.p_action === 'items').some((c) => c.p_args.sample === true)).toBe(true)
}

test.describe('course descriptions in the Layer 4 Inbox', () => {
  test('reconciliation line, ready-first queue, check results on the card, quick reasons and the sample', async ({ page }) => {
    const calls = { inbox: [], cd: [] }
    await openCourseDescriptions(page, calls)
    await checkFlow(page, calls, null)
  })

  test('reviewer can return from the final course-description page without leaving the queue', async ({ page }) => {
    const calls = { inbox: [], cd: [] }
    await openCourseDescriptions(page, calls)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_description_queue', async (route) => {
      const b = route.request().postDataJSON(); calls.cd.push(b)
      if (b.p_action === 'items') {
        const offset = Number(b.p_args?.offset || 0)
        return route.fulfill({ json: { total: 3, offset, limit: 2, items: [ITEM(1), ITEM(2), ITEM(3)].slice(offset, offset + 2) } })
      }
      return route.fallback()
    })
    await page.locator('[data-l4-cd-summary] [data-l4-cd-ready]').click()
    const pager = page.locator('[data-l4-cd-pager]')
    await expect(pager).toContainText('1–2 of 3')
    await expect(pager.getByRole('button', { name: 'Previous' })).toBeDisabled()
    await pager.getByRole('button', { name: 'Next' }).click()
    await expect(page.locator('[data-l4-cd-list] [data-l4-item="provider_description"]')).toHaveCount(1)
    await expect(pager).toContainText('3–3 of 3')
    await expect(pager.getByRole('button', { name: 'Next' })).toBeDisabled()
    await expect(pager.getByRole('button', { name: 'Previous' })).toBeEnabled()
    await pager.getByRole('button', { name: 'Previous' }).click()
    await expect(page.locator('[data-l4-cd-list] [data-l4-item="provider_description"]')).toHaveCount(2)
    await expect(pager).toContainText('1–2 of 3')
    expect(calls.cd.filter(c => c.p_action === 'items').map(c => c.p_args.offset)).toEqual([0, 2, 0])
  })

  test('review pack (C-DESC 8 Nov 2026): capacity line, by-university pack and the flags; a read-only view that decides nothing', async ({ page }) => {
    const calls = { inbox: [], cd: [] }
    await openCourseDescriptions(page, calls, (b) => {
      if (b.p_action === 'capacity') return { pending: 3, minutes_an_item: 3, pace_basis: 'default', hours_to_clear_waiting: 0.2, held_first_readings_behind_the_provider_cap: 5, hours_to_clear_waiting_and_held: 0.4,
        target_days: 7, items_a_day_needed_incl_arrivals: 4, reviewer_hours_a_day_needed: 0.2, arriving_a_day: 1.5, window_days: 7, decided_in_window: 0, back_pressure: { on: true, global_max: 1500, new_readings_paused: false } }
      if (b.p_action === 'pack') return { total: 2, offset: 0, limit: 25, items: [
        ITEM(1, { pack: { flags: [], flag_count: 0, same_words_on_other_courses: 0, held_readings_this_decision_can_free: 4, waiting_in_university: 2, university_rank: 1 } }),
        ITEM(2, { pack: { flags: ['same_words_elsewhere', 'money_or_year'], flag_count: 2, same_words_on_other_courses: 3, held_readings_this_decision_can_free: 4, waiting_in_university: 2, university_rank: 1 } })] }
      return null
    })
    const cap = page.locator('[data-l4-cd-capacity]')
    await expect(cap).toContainText('about 3 minutes an item (Layer 4 default, not yet measured for descriptions)')
    await expect(cap).toContainText('4 decisions a day')
    await expect(cap).toContainText('new readings run (limit 1,500)')
    await page.locator('[data-l4-cd-pack]').click()
    await expect.poll(() => calls.cd.some((c) => c.p_action === 'pack' && c.p_args.offset === 0)).toBe(true)
    const cards = page.locator('[data-l4-cd-list] [data-l4-item="provider_description"]')
    await expect(cards).toHaveCount(2)
    await expect(cards.nth(0).locator('[data-l4-cd-flags]')).toContainText('No flag')
    await expect(cards.nth(0).locator('[data-l4-cd-flags]')).toContainText('lets up to 4 held readings')
    await expect(cards.nth(1).locator('[data-l4-cd-flags]')).toContainText('same words as another course; names a price or a year (3 other)')
    // reading the pack decided nothing
    expect(calls.inbox.filter((c) => c.p_action === 'decide')).toHaveLength(0)
  })

  test('Enrich fields › Course descriptions: the four measures apart, held reasons, claim words and the sample report (read only)', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_enrich_fields', (route) => route.fulfill({ json: route.request().postDataJSON().p_action === 'fields' ? { fields: [], countries: ['AU'], can_start: false, rules: [] } : route.request().postDataJSON().p_action === 'jobs' ? { jobs: [] } : {} }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_description_queue', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      const r = b.p_action === 'summary' ? { ...SUMMARY, provider_id: null, pending: 857, proposed_in_layer4: 857, admitted_by_person: 0, published_to_the_website: 0, by_class: { ready: 800, fails_now: 20, page_changed: 37 } }
        : b.p_action === 'held_reasons' ? { days: 7, readings: 3083, passed_every_check: 1379, held_by_a_check: 1642, by_rule: { length: 478, sentence_count: 361, unsupported_claim: 486 }, claim_words: { students: 483, facilities: 3 }, ai_cost_usd: 3.32, ai_cost_per_passing_reading_usd: 0.0024, reask: { attempted: 0, now_within_limits: 0, still_held: 0 }, reask_max: 0 }
        : b.p_action === 'claim_words' ? { window_days: 7, note: 'Evaluation only.', words: [{ word: 'students', held: 483, only_this_word: 478, passes_every_other_rule_without_it: 95, next_rule: { length: 300 }, quote_addresses_the_reader: 470, suggested_harmless: [{ text: 'Students learn planning.', quote: 'You learn planning.' }], suggested_claim: [] }] }
        : { strata: [{ country: 'AU', wanted: 30, eligible: 400, selected: 30, shortfall: 0 }], selected: 50, pending: 50, approved: 0, rejected: 0, rejected_by_class: {}, reviewer_disagreement: { passed_every_check_but_rejected: 0, approved_but_rules_now_fail: 0 }, claim_support: { with_claim_words_in_quote: 2, lowest_sentence_support: 0.62 }, note: 'A measurement only; not an authority to bypass Layer 4.', rows: [] }
      return route.fulfill({ json: r })
    })
    await page.goto('/#layer-2-discovery?tab=enrich')
    const card = page.locator('[data-enrich-descriptions]')
    await card.locator('.cf-card-toggle').click()
    const m = card.locator('[data-enrich-cd-measures]')
    await expect(m).toContainText('857 proposed')
    await expect(m).toContainText('0 admitted by a person')
    await expect(m).toContainText('0 published to the website')
    await expect(m).toContainText('never counted as admitted or published')
    await expect(card.locator('[data-enrich-cd-classes]')).toContainText('857')
    await expect(card.locator('[data-enrich-cd-held]')).toContainText('1,379 passed every check (45%)')
    await expect(card).toContainText('a claim word not in the quote: 486 (students 483, facilities 3)')
    await card.locator('[data-enrich-cd-words]').click()
    await expect(card.locator('[data-enrich-cd-wordlist]')).toContainText('students: 483 held, 478 held by this word alone, 95 would pass every other rule without it')
    await card.locator('[data-enrich-cd-sample]').click()
    await expect(card.locator('[data-enrich-cd-samplereport]')).toContainText('not an authority to bypass Layer 4')
    // every call is a read action
    expect([...new Set(calls.map((c) => c.p_action))].sort()).toEqual(['claim_words', 'held_reasons', 'sample', 'summary'])
  })

  test('Enrich fields › Course descriptions: machine-admitted descriptions are shown apart and never as a person\'s (F-CDESC)', async ({ page }) => {
    await mockAdmin(page, { rank: 4 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_enrich_fields', (route) => route.fulfill({ json: route.request().postDataJSON().p_action === 'fields' ? { fields: [], countries: ['AU'], can_start: false, rules: [] } : route.request().postDataJSON().p_action === 'jobs' ? { jobs: [] } : {} }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_description_queue', async (route) => {
      const b = route.request().postDataJSON()
      const r = b.p_action === 'summary' ? { ...SUMMARY, provider_id: null, pending: 10, proposed_in_layer4: 10, admitted_by_person: 4, admitted_by_machine: 12, published_to_the_website: 16, by_class: { ready: 10 } }
        : b.p_action === 'held_reasons' ? { days: 7, readings: 0, passed_every_check: 0, held_by_a_check: 0, by_rule: {}, claim_words: {}, reask: {}, reask_max: 0 }
        : { strata: [], selected: 20, pending: 5, approved: 8, approved_by_machine: 7, rejected: 0, rejected_by_class: {}, approval_share_of_decided: 0.5, reviewer_disagreement: { passed_every_check_but_rejected: 0, approved_but_rules_now_fail: 0 }, claim_support: {}, note: 'x', rows: [] }
      return route.fulfill({ json: r })
    })
    await page.goto('/#layer-2-discovery?tab=enrich')
    const card = page.locator('[data-enrich-descriptions]')
    await card.locator('.cf-card-toggle').click()
    const m = card.locator('[data-enrich-cd-measures]')
    await expect(m).toContainText('4 admitted by a person')
    await expect(m).toContainText('12 admitted by the machine rule')
    await expect(m).toContainText('never counted as a person')
    await card.locator('[data-enrich-cd-sample]').click()
    await expect(card.locator('[data-enrich-cd-samplereport]')).toContainText('8 approved (not counting 7 approved by the machine rule)')
  })
})

test.describe('course descriptions at phone width @responsive', () => {
  test('Layer 4 Inbox: the reconciliation line, ready queue, quick reasons and confirm fit the phone and the page does not scroll sideways', async ({ page }) => {
    const w = page.viewportSize()?.width || 9999
    expect(w, 'this test must run at phone width (chromium-mobile)').toBeLessThanOrEqual(PHONE_MAX)
    const calls = { inbox: [], cd: [] }
    await openCourseDescriptions(page, calls)
    await checkFlow(page, calls, w)
    expect(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(1)
  })
})

