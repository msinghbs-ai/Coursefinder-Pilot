// CF-247 (2 Oct 2026): Kimi K2 0905 and MiMo v2.6 Pro are candidate profiles only — paused, pinned, not in any cascade.
import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

test('candidate profiles are paused copies of the qualified Qwen3 30B profile, pinned to one named model each', async () => {
  const m = await fs.readFile('supabase/migrations-archive/20261002184100_cf247_candidates_kimi_k2_mimo_v26.sql', 'utf8')
  for (const code of ['openrouter-intake-l3c-kimi-k2-0905-v1', 'openrouter-intake-l3c-mimo-v2-6-pro-v1', 'openrouter-english-l3c-kimi-k2-0905-v1', 'openrouter-english-l3c-mimo-v2-6-pro-v1']) expect(m).toContain(`'${code}'`)
  expect(m).toContain("'moonshotai/kimi-k2-0905'")
  expect(m).toContain("'xiaomi/mimo-v2.6-pro'")
  expect(m).toContain('false, true,') // enabled = false, paused = true
  expect(m).not.toMatch(/layer3_route_tiers/) // no cascade placement
  expect(m).not.toMatch(/update pipeline\.layer3_model_profiles/) // no existing profile changed
  expect(m).not.toMatch(/\bdrop\b|delete from|truncate|on delete cascade/i)
})

test('English step 3 is MiMo v2.6 Pro, placed only with holdout evidence; Sonnet moves to step 4 and stays off', async () => {
  const m = await fs.readFile('supabase/migrations-archive/20261002184200_cf247_english_step3_mimo_on.sql', 'utf8')
  expect(m).toContain("v_code text := 'openrouter-english-l3c-mimo-v2-6-pro-v1'")
  expect(m).toContain("c.gold_set = 'l3r-english-h1'")
  expect(m).toMatch(/v_n < 30 or v_ok::numeric \/ v_n < 0\.80 or v_wrong > 0 then raise exception/)
  expect(m).toContain("set tier_no = 4")
  expect(m).toContain("tier_no = 3 and active = false")
  expect(m).not.toMatch(/openrouter-intake-/) // intake cascade untouched
  const s = await fs.readFile('supabase/migrations-archive/20261002184300_cf247_english_failures_to_mimo.sql', 'utf8')
  expect(s).toContain("l.before_value is null") // differences with a value on record stay with a person
  expect(s).toContain("l.field_code = 'course_english'")
  for (const f of [m, s]) expect(f).not.toMatch(/\bdrop\b|delete from|truncate|on delete cascade/i)
})
