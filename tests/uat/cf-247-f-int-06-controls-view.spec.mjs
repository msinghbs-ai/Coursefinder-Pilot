// Guards: F-INT.06 (first-run and scheduled controls observed from the UI, IQ-00313): the Automation progress controls block reads only what the progress status returns; absent fields read "Not held"; G2 (no operational value in code).
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

test('controls rows come only from the status; absent fields read Not held', async ({ page }) => {
  await page.goto('/')
  const out = await page.evaluate(async () => {
    const { summariseControls } = await import('/src/intake-controls-view.js')
    return { full: summariseControls({ job: 'intake-dates-apply', schedule: '17 * * * *', batch: 40, pilot_share_pct: 70, provider_share: 5, observer: { window_hours: 24, stall_hours: 6 }, controls: { can_pause_resume: true, control_rank: 5 } }), empty: summariseControls(null) }
  })
  const val = (rows, l) => rows.find(r => r.label === l)
  expect(val(out.full, 'Rows a run')).toMatchObject({ value: '40', held: true })
  expect(val(out.full, 'Who can change the job').value).toBe('You can pause and resume this job')
  for (const r of out.empty) expect(r).toMatchObject({ value: 'Not held', held: false })
  expect(out.empty.length).toBe(out.full.length)
})

test('the block is mounted in Automation progress and carries no number of its own', () => {
  expect(fs.readFileSync('src/AutomationProgress.jsx', 'utf8')).toContain('data-testid="ap-controls-settings"')
  const helper = fs.readFileSync('src/intake-controls-view.js', 'utf8').split('\n').filter(l => !l.startsWith('//')).join('\n')
  expect(helper).not.toMatch(/(?:\?\?|\|\|)\s*\d/)
})
