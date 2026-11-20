// Guards: CF-247 s917 standing mandate (Platform Admin 21 Nov 2026 10:07 AEDT): reported bug fixes and verified admission rules take effect
// immediately upon deploy — no unrequested shadow, off-by-default flag, 24-hour or next-day cutover, and no assumed future work — stated in
// CLAUDE.md and AGENTS.md
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

for (const f of ['CLAUDE.md', 'AGENTS.md']) {
  test(`${f} carries the standing mandate word for word`, () => {
    const s = fs.readFileSync(f, 'utf8')
    expect(s).toContain('### Standing Mandate: Immediate Live Activation (No Unrequested Shadow or Future Deferrals)')
    expect(s).toContain('MUST take effect **immediately upon deploy** in the same PR.')
    expect(s).toContain('NEVER place a bug fix or verified admission rule into shadow-only mode, behind an off-by-default flag, or on a 24-hour / next-day cutover timer unless the user explicitly instructs a shadow period first.')
    expect(s).toContain('NEVER defer a reported fix to "tomorrow", "a future lane", or "a follow-up PR" without explicit user confirmation.')
  })
}
