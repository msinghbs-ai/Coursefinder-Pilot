// Guards: Platform Admin 20 Nov 2026 14:40 and 14:41 (S1-UI-Parity s838; mockup s820-s827): every held Layer 4 card opens with the amber Main hold
// reason banner (with ? and a collapsible Technical detail); banned words are marked in soft yellow in the proposed text; the cleaned text sits directly
// above the primary Remove "word" & Admit; the action bar is three buttons in one row (Save Edit & Admit, Approve As-Is, Reject set apart on the right);
// Platform Health's stages 2 and 3 show their rate against the normal rate from the stored pulse (no extra read); the ? help opens and closes with Escape.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { markBanned } from '../../src/lib/description-check.js'
import { stageCards, stageRate } from '../../src/lib/ops-pulse.js'

const MIG = fs.readFileSync('supabase/migrations/20261120145000_cf247_s836_s838_rule_groups_pulse_rates.sql', 'utf8')
const EDIT = fs.readFileSync('src/DescriptionEditAdmit.jsx', 'utf8')

test('s838: the rates are built into the stored pulse by the 5-minute job, windows from settings, no extra read', () => {
  expect(MIG).toContain("$n$'stages', v_stages, 'checks', v_checks, 'rates', security.ops_pulse_rates_v1()),$n$")
  for (const k of ['pulse.rate_window_hours', 'pulse.baseline_days']) expect(MIG).toContain(`security.pipeline_num_v1('${k}'`)
  expect(MIG).not.toMatch(/interval\s+'\d+\s*(day|days|hour|hours)/i)
  const pulse = { stages: [], rates: { window_hours: 24, baseline_days: 7, capture: { window: 11860, normal: 2426, ratio: 4.89 }, autoclean: { rate: 84.1, normal_rate: 69.6, decided: 624, passed: 525 } } }
  expect(stageRate(pulse, 2)).toMatchObject({ key: 'capture', label: 'Capture rate vs normal', text: '11,860 pages in the last 24 h · 4.9× normal (normal 2,426 per 24 h, from the 7 days before)' })
  expect(stageRate(pulse, 3)).toMatchObject({ key: 'autoclean', label: 'Auto-clean pass rate', pct: 84, text: '84.1% admitted by the machine rules in the last 24 h (624 decided) · normal 69.6% (+14.5 points)' })
  expect(stageRate(pulse, 1)).toBe(null); expect(stageRate({ stages: [] }, 2)).toBe(null)
  expect(stageCards(pulse).map((c) => c.rate?.key || null)).toEqual([null, 'capture', 'autoclean', null])
})

test('s838: banned words are marked as whole words, any case; the rest of the text is unchanged', () => {
  const parts = markBanned('An Innovative university, leading in Sydney; not innovatively.', ['innovative', 'leading'])
  expect(parts.filter((p) => p.word).map((p) => p.text)).toEqual(['Innovative', 'leading'])
  expect(parts.map((p) => p.text).join('')).toBe('An Innovative university, leading in Sydney; not innovatively.')
  expect(markBanned('No list words here.', ['innovative'])).toEqual([{ text: 'No list words here.', word: '' }])
  expect(EDIT).toContain('export function CardHold({it,label})')
})

const W = ['innovative']
const RULES = { provider: { min_chars: 20, max_chars: 1200, min_sentences: 1, max_sentences: 5, words: W }, course: { min_chars: 20, max_chars: 360, min_sentences: 1, max_sentences: 2, words: W }, review_months: 6 }
const KINDS = { provider_description: { label: 'University description', order: 1, choices: [
  { key: 'approve', label: 'Approve as read', rank: 4, returns: 'Published.' }, { key: 'reject', label: 'Reject', rank: 4, returns: 'Read again later.' },
  { key: 'edit_approve', label: 'Save Edit & Admit', input: 'text', editor: true, rank: 4, returns: 'Admitted.' }] } }
const ITEM = { kind: 'provider_description', ref: 'b1', provider_id: 'p1', provider: 'Technology University Sydney', subject: 'University description', created_at: '2026-11-15T01:00:00Z',
  why: 'Machine rule pdesc-machine-v1 did not admit this: validation_refused_word',
  detail: { field_code: 'provider_description', proposed: { description: 'Technology University Sydney is an innovative university of technology in Sydney.', sentences: [], source_url: 'https://uni.example/about' }, machine: { reason_code: 'policy_refused_word' } } }

test.describe('mocked browser', () => {
  test('the description card: amber banner with ? (Escape closes), marked words, the cleaned text above Remove & Admit, one 3-button bar', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON()
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: KINDS, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { provider_description: { n: 1 } } } })
      if (b.p_action === 'rule_groups') return route.fulfill({ json: { kind: 'provider_description', built_in: true, total: 1, batch_max: 50, ms: 9, groups: [{ key: 'cd:banned_word', n: 1, late: 0, refs: ['b1'] }] } })
      if (b.p_action === 'rule_group_items') return route.fulfill({ json: { items: [ITEM], ms: 7 } })
      if (b.p_action === 'description_rules') return route.fulfill({ json: RULES })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    const card = page.locator('[data-l4-item="provider_description"]')
    await expect(card.locator('[data-dea-hold]')).toContainText('Main hold reason')
    await expect(card.locator('[data-dea-hold] details.dea-tech')).not.toHaveAttribute('open', '')
    await expect(card.locator('[data-dea-proposed] mark[data-dea-ban-mark="innovative"]')).toHaveText('innovative')
    expect(await card.locator('[data-dea-proposed] mark').evaluate((e) => getComputedStyle(e).backgroundColor)).not.toBe('rgba(0, 0, 0, 0)')
    const strip = card.locator('[data-dea-strip]')
    await expect(strip.locator('[data-dea-strip-text]')).toHaveText('Technology University Sydney is a university of technology in Sydney.')
    await expect(strip.locator('[data-dea-remove-admit]')).toHaveText('Remove "innovative" & Admit')
    const bar = card.locator('[data-dea-bar]')
    await expect(bar.locator('button')).toHaveCount(3)
    await expect(bar.locator('[data-dea-remove-admit]')).toHaveCount(0)
    const tops = await bar.locator('button').evaluateAll((bs) => bs.map((b) => Math.round(b.getBoundingClientRect().top)))
    expect(new Set(tops).size).toBe(1)                                              // one row
    const xs = await bar.locator('button').evaluateAll((bs) => bs.map((b) => b.getBoundingClientRect().left))
    expect(xs[2] - xs[1]).toBeGreaterThan(160)                                      // Reject set apart on the right
    await card.locator('[data-dea-hold] [data-help-open="layer4"]').click()
    await expect(page.locator('[data-help-drawer="layer4"] [data-help-steps="3"] li')).toHaveCount(3)
    await page.keyboard.press('Escape')
    await expect(page.locator('[data-help-drawer="layer4"]')).toHaveCount(0)
  })

  test('Platform Health: Page Capture and AI Extraction & Auto-Clean show their rate against normal', async ({ page }) => {
    await mockAdmin(page)
    const cur = '2026-11-20T00:05:00Z'
    const pulse = { status: 'ok', critical: 0, warning: 0, refreshed_at: cur, budget: { spend_usd: 3.2, cap_usd: 14 },
      stages: [1, 2, 3, 4].map((n) => ({ stage: n, status: 'ok', checks: 2, attention: [], queued: 1 })),
      rates: { window_hours: 24, baseline_days: 7, capture: { window: 11860, normal: 2426, ratio: 4.89 }, autoclean: { rate: 84.1, normal_rate: 69.6, decided: 624 } } }
    await page.route('**/rest/v1/rpc/admin_read', async (route) => {
      const body = route.request().postDataJSON() || {}
      if ((body.p_operation || body.operation) !== 'platform_health') return route.fallback()
      return route.fulfill({ json: { generated_at: cur, overall: 'ok', counts: { critical: 0, warning: 0, info: 0 }, issues: [], history: [], pulse, pulse_source: 'snapshot', checks: [] } })
    })
    await page.goto('/#platform-health')
    const board = page.locator('[data-health-pulse] [data-pipeline-board]')
    await expect(board.locator('[data-stage="2"] [data-stage-rate="capture"]')).toContainText('4.9× normal')
    await expect(board.locator('[data-stage="3"] [data-stage-rate="autoclean"]')).toContainText('normal 69.6%')
    await expect(board.locator('[data-stage="1"] [data-stage-rate]')).toHaveCount(0)
    await page.locator('[data-help-open="health"]').first().click()
    await expect(page.locator('[data-help-drawer="health"]')).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(page.locator('[data-help-drawer="health"]')).toHaveCount(0)
  })
})
