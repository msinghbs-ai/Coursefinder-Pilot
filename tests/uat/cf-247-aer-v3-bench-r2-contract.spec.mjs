// Guards: AER v3 benchmark round 2 (Platform Admin 16 Nov 2026 14:06, Layer 4 clearance and model benchmark step 2): only allowed catalogue models, the same prompt text, evidence only (nothing qualified or switched on)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261116100000_cf247_aer_v3_bench_r2.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('four pinned candidates of the unchanged prompt on the frozen set; Gemini 2.5 Flash is an allowed model; no GPT and no Gemini 3', () => {
  expect(code).toContain("'google/gemini-2.5-flash'")
  expect(code).toContain("where p.version = 'aer-v2-course-v3-qwen3-30b'")  // the new row copies the existing prompt text and sha-256
  for (const v of ['qwen3-30b', 'mistral-small-3.2', 'mimo-v2.6-flash', 'gemini-2.5-flash']) expect(code).toContain(`'aer-v2-course-v3-${v}'`)
  expect(code).toContain("model_identifier = 'google/gemini-2.5-flash' and status = 'allowed'")
  expect(code).not.toMatch(/gpt-4|gemini-3|openrouter\/auto/i)
  expect(code).toContain('"allow_fallbacks": false')
  expect(code).toMatch(/v\.id, 5,/)
})

test('runs are only queued: the switches stay off, nothing is qualified, no route or production reader changes', () => {
  expect(code).toContain("perform security.ai_eval_run_open_v1(p.id, 'candidate')")
  expect(code).toContain('offline runs, AER v3 runs and the shadow reader stay off')
  expect(code).toContain("service_code = 'entry_requirements_v2_shadow' and status = 'qualified'")
  expect(code).not.toMatch(/update\s+pipeline\.platform_toolset_settings/i)
  expect(code).not.toMatch(/(insert into|update)\s+pipeline\.(ai_route|ai_service|route)/i)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
