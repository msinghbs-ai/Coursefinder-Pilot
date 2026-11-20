// Guards: Platform Admin 20 Nov 2026 10:21 (s819: banned
// promotional words never stall admission: the list in the prompt, a deterministic word strip before Layer 4 with the same checks run again, and what reviewers
// remove surfaced as rule-tuning candidates; s820: the main hold reason in plain English and one-click Remove "word" & Admit; s821: one action bar per card).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { stripBanned, holdReason, holdCode, removedWords, ruleCandidates } from '../../src/lib/description-check.js'

const read = (f) => fs.readFileSync(f, 'utf8')
const M819 = read('supabase/migrations/20261120121000_cf247_s819_description_banned_word_strip_recovery.sql')
const M819R = read('supabase/migrations/20261120121100_cf247_s819_prompt_registry_words_note.sql')
const DS = read('supabase/functions/coverage-sweep/description.ts'), IDX = read('supabase/functions/coverage-sweep/index.ts')
const EDIT = read('src/DescriptionEditAdmit.jsx'), INBOX = read('src/Layer4Inbox.jsx'), HE = read('src/HumanEditsAudit.jsx')
const W = ['innovative', 'leading', 'world-class', 'vibrant', 'best']

test('s819 migrations: no public object added, G3 read before and after, they say what they replace and retire', () => {
  for (const m of [M819, M819R]) { expect((m.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2); expect(m).toMatch(/^-- Replaces:/m); expect(m).toMatch(/^-- Retires:/m)
    expect(m).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+(table|view)\b/i) }
})

test('s819: the word strip removes only listed promotional words (with an intensifier), tidies the sentence, never adds a word; the same rule on screen and in the database', () => {
  const cases = [['UTS is an innovative university of technology in Sydney.', 'UTS is a university of technology in Sydney.'],
    ['It is one of the most innovative and vibrant universities in Australia.', 'It is one of the universities in Australia.'],
    ['A world-class, leading research university with an open campus.', 'A research university with an open campus.'],
    ['An innovative university. An innovative campus.', 'A university. A campus.']]
  for (const [a, b] of cases) { expect(stripBanned(a, W).text).toBe(b); expect(M819).toContain(`'${a}'`); expect(M819).toContain(`'${b}'`) }
  expect(stripBanned('The university offers courses in Sydney.', W)).toEqual({ text: 'The university offers courses in Sydney.', removed: [], changed: false })
  expect(stripBanned('Our campus is in Sydney.', W).changed).toBe(false)                                  // "campus" is not promotional: never removed
  for (const [a] of cases) for (const w of stripBanned(a, W).text.toLowerCase().split(/\W+/).filter(Boolean)) expect(a.toLowerCase()).toContain(w)  // no word added
})

test('s819: the admission strips only on a word refusal, re-runs the same validation and gate, keeps the quotes and the original, and leaves everything else declined', () => {
  expect(M819).toMatch(/cf_edit_def\('security\.provider_description_machine_admit_v1\(uuid\)'::regprocedure, 'e6a6f70bf5de372987df17c380cb5106'/)
  expect(M819).toContain("if v_decline in ('validation_refused_word', 'machine_text_refused_word') and v_tier in ('stored', 'direct', 'firecrawl') then")
  expect(M819).toContain("v_check := security.provider_description_validate_v1(i.entity_id, v_read.source_url, v_read.source_captured_at, jsonb_build_object('about_page', true, 'sentences', v_strip->'sentences'));")
  expect(M819).toContain("v_gate2 := security.provider_description_machine_gate_v1(i.entity_id, v_check->>'text'")
  expect(M819).toContain("'original_text', v_text0, 'original_sentences', v_sent")
  expect(M819).toContain("then 'words_removed: '")
  expect(M819).toContain("case when p_entity = 'course' then 'enrich.course_description_marketing_words' else 'pdesc.superlatives' end")
  expect(M819).toContain("s || jsonb_build_object('text', r->>'text', 'text_before_strip', s->>'text')")   // the sentence text changes; its quote is kept as it is
  expect(M819).not.toMatch(/create\s+(or replace\s+)?function\s+public\.|create\s+(table|view)\b|\bdelete\s+from\b/i)
  expect(M819).toMatch(/revoke all on function security\.description_strip_words_v1\(text, jsonb\) from public, anon, authenticated/)
})

test('s819: the live promotional word list is stated in both description prompts; registry v7 declares words_note', () => {
  expect(DS).toContain('${lengthNote(length)}${wordsNote(words)}\\nPage text:\\n${fenceSourceText(page)}')
  expect(DS).toContain('${copyNote(maxVerbatimChars)}${wordsNote(words)}\\nPage text:')
  expect(IDX.match(/ws\["enrich\.course_description_marketing_words"\]/g)).toHaveLength(2)
  expect(M819R).toContain("{{length_note}}{{words_note}}\\nPage text:")
  expect(M819R).toMatch(/update pipeline\.prompt_templates set status = 'retired'/)
})

test('s820: the main hold reason in plain English; the code under Technical detail', () => {
  const why = 'Machine rule pdesc-machine-v1 did not admit this: validation_refused_word'
  expect(holdCode(why)).toBe('validation_refused_word')
  expect(holdReason(why, 'UTS is an innovative university.', { words: W })).toMatchObject({ kind: 'banned', title: 'Contains 1 banned word', words: ['innovative'] })
  expect(holdReason('Machine rule pdesc-machine-v1 did not admit this: validation_first_sentence', 'A university in Sydney.', { words: W }).title).toBe('The first sentence does not name the university')
  expect(EDIT).toContain('Main hold reason: {h.title}'); expect(EDIT).toContain('<summary>Technical detail</summary>')
})

test('s819: rule-tuning candidates count the words reviewers removed and mark those already on the list', () => {
  expect(removedWords('UTS is an innovative university in Sydney.', 'UTS is a university in Sydney.')).toEqual(['innovative'])
  const rows = ruleCandidates([{ original: 'An innovative and unique university.', current: 'A university.' }, { original: 'A unique place.', edited: 'A place.' }], W)
  expect(rows).toEqual([{ word: 'unique', n: 2, on_list: false }, { word: 'innovative', n: 1, on_list: true }])
  expect(HE).toContain('<RuleTuning items={items}/>')
})

const RULES = { provider: { min_chars: 20, max_chars: 1200, min_sentences: 1, max_sentences: 5, words: W }, course: { min_chars: 20, max_chars: 360, min_sentences: 1, max_sentences: 2, words: W }, review_months: 6 }
const KINDS = { provider_description: { label: 'University description', order: 1, choices: [
  { key: 'approve', label: 'Approve as read', rank: 4, returns: 'Published.' }, { key: 'reject', label: 'Reject', rank: 4, returns: 'Read again later.' },
  { key: 'edit_approve', label: 'Save Edit & Admit', input: 'text', editor: true, rank: 4, returns: 'Admitted as human input and locked.' }] } }
const ITEM = { kind: 'provider_description', ref: '00000001-0000-4000-a000-000000000000', provider_id: 'p1', provider: 'Technology University Sydney', subject: 'University description',
  why: 'Machine rule pdesc-machine-v1 did not admit this: validation_refused_word', created_at: '2026-11-15T01:00:00Z', late: true,
  detail: { field_code: 'provider_description', before: {}, proposed: { description: 'Technology University Sydney is an innovative university of technology in Sydney. It teaches courses in many fields.',
    sentences: [{ text: 'Technology University Sydney is an innovative university of technology in Sydney.', quote: 'an innovative university of technology' }, { text: 'It teaches courses in many fields.', quote: 'courses in many fields' }],
    source_url: 'https://uni.example/about' } } }

test('s821: one action bar: Remove "innovative" & Admit admits the cleaned text and locks it; no second Approve as read / Reject row', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await mockAdmin(page, { rank: 6 })
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
    const b = route.request().postDataJSON(); calls.push(b)
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 1, universities: 1, late: 1, by_kind: { provider_description: { n: 1, late: 1 } } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p1', name: 'Technology University Sydney', country: 'AU', courses: 10, n: 1, oldest: '2026-11-15T01:00:00Z', late: true, by_kind: { provider_description: 1 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [ITEM] } })
    if (b.p_action === 'description_rules') return route.fulfill({ json: RULES })
    if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'Admitted.' } })
    return route.fulfill({ json: {} })
  })
  await page.goto('/#layer-4-review')
  await expect(page.locator('[data-l4-inbox]')).toBeVisible()
  await page.locator('[data-l4-pill="provider_description"]').first().click()
  const card = page.locator('[data-l4-item="provider_description"]').first()
  await expect(card.locator('[data-dea-hold="banned"]')).toContainText('Main hold reason: Contains 1 banned word — innovative')
  await expect(card.locator('[data-dea-strip-text]')).toHaveText('Technology University Sydney is a university of technology in Sydney. It teaches courses in many fields.')
  await expect(card.locator('[data-dea-bar] [data-dea-remove-admit]')).toHaveText('Remove "innovative" & Admit')
  await expect(card.locator('[data-l4-choice="approve"]')).toHaveCount(0)          // no duplicate Approve as read
  await expect(card.locator('[data-l4-choice="reject"]')).toHaveCount(1)           // Reject once, in the bar
  await expect(card.locator('[data-dea-bar] [data-l4-choice="reject"]')).toHaveCount(1)
  await card.locator('[data-dea-remove-admit]').click()
  await expect.poll(() => calls.find((c) => c.p_action === 'decide')?.p_args).toMatchObject({ kind: 'provider_description', ref: ITEM.ref, choice: 'edit_approve', set_manual_lock: true,
    value: 'Technology University Sydney is a university of technology in Sydney. It teaches courses in many fields.', reason: 'Removed banned word: innovative' })
})
