// v2.15.127 Layer 3 Work queue: work by task and recent results. The course-page pattern requests panel was removed in
// clean-up batch 2 (9 Oct 2026).
// No paused banner that could contradict Control, no one-off manual run form, no duplicate links.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

test('source: the old workspace is no longer the Work queue, and the manual run form and banner are gone from it', () => {
  const ops = fs.readFileSync('src/Layer3Operations.jsx', 'utf8')
  expect(ops).toContain("import Layer3Work from'./Layer3Work'")
  expect(ops).not.toContain('Layer3Workspace')
  const w = fs.readFileSync('src/Layer3Work.jsx', 'utf8').split('\n').filter(l => !l.startsWith('//')).join('\n')
  for (const gone of ['Run eligible interpretation', 'AI interpretation is paused', 'Open Jobs', 'Technical identifiers', 'Governed']) expect(w).not.toContain(gone)
  expect(w).not.toContain('source_pattern_queue')
  expect(w).not.toContain('layer3-interpret')
})

test.describe('mocked browser', () => {
  test('work by task and recent results paged; no pattern request panel', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#layer-3-ai?tab=work')
    const w = page.locator('[data-layer3-work]')
    await expect(w.locator('[data-task="provider_intake_validation"]')).toContainText('Intakes')
    await expect(w.locator('[data-task="provider_intake_validation"]')).toContainText('5,348')
    await expect(w).toContainText('Oldest waiting 2 h')
    await expect(page.getByText('AI interpretation is paused')).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Run eligible interpretation' })).toHaveCount(0)
    await expect(w.locator('[data-layer3-source-pattern-queue]')).toHaveCount(0)
    await expect(w.locator('.l3w-runs tbody tr')).toHaveCount(25)
    await expect(w.locator('.l3w-runs')).toContainText('qwen3-30b-a3b-instruct-2507')
  })
})
