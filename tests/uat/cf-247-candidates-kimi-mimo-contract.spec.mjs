// CF-247 (2 Oct 2026): Kimi K2 0905 and MiMo v2.6 Pro are candidate profiles only — paused, pinned, not in any cascade.
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

test('candidate profiles are paused copies of the qualified Qwen3 30B profile, pinned to one named model each', async () => {
  const m = await fs.readFile('supabase/migrations/20261002184100_cf247_candidates_kimi_k2_mimo_v26.sql', 'utf8')
  for (const code of ['openrouter-intake-l3c-kimi-k2-0905-v1', 'openrouter-intake-l3c-mimo-v2-6-pro-v1', 'openrouter-english-l3c-kimi-k2-0905-v1', 'openrouter-english-l3c-mimo-v2-6-pro-v1']) expect(m).toContain(`'${code}'`)
  expect(m).toContain("'moonshotai/kimi-k2-0905'")
  expect(m).toContain("'xiaomi/mimo-v2.6-pro'")
  expect(m).toContain('false, true,') // enabled = false, paused = true
  expect(m).not.toMatch(/layer3_route_tiers/) // no cascade placement
  expect(m).not.toMatch(/update pipeline\.layer3_model_profiles/) // no existing profile changed
  expect(m).not.toMatch(/\bdrop\b|delete from|truncate|on delete cascade/i)
})
