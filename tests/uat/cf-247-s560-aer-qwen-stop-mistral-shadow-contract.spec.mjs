// Guards: AER route decision "Stop Qwen, shadow Mistral" (Platform Admin 16 Nov 2026 16:52): Qwen3 30B is unqualified and the two AER v1 entry routes are off until a model qualifies; the AER v2 shadow holds Mistral Small 3.2 alone, provisional and off; nothing is qualified or switched on by this change
// CF-247 S560. Migration 20261116120000_cf247_aer_v1_qwen_stop_v2_mistral_shadow. Evidence: coursefinder-admin layer4-clearance-and-model-benchmark-2026-11-16.md (Admin #519).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261116120000_cf247_aer_v1_qwen_stop_v2_mistral_shadow.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('AER v1 entry reading stops: both routes switched off, Qwen3 30B unqualified, each change logged', () => {
  expect(code).toContain("where service_code in ('course_entry_requirements', 'entry_matrices') for update loop")
  expect(code).toContain('set enabled = false')
  expect(code).toContain("where model_code = 'qwen3-30b' and service_code in ('course_entry_requirements', 'entry_matrices', 'entry_requirements_v2_shadow')")
  expect(code).toContain("set status = 'unqualified'")
  expect((code.match(/insert into pipeline\.admin_control_events/g) || []).length).toBe(4)
  expect(code).toContain("raise exception 'post-check: still switched on: %'")
})

test('AER v2 shadow: Mistral Small 3.2 alone (no fallback across models), provisional, pending and still off', () => {
  expect(code).toContain("set cascade = array['mistral-small-3.2']")
  expect(code).toContain("set status = 'pending', provisional = true")
  expect(code).toContain("raise exception 'post-check: the AER v2 shadow must stay switched off'")
  expect(code).toContain("raise exception 'post-check: nothing is qualified on the AER v2 shadow by this change'")
})

test('a decision never switches anything on: no route enabled, no model qualified, nothing dropped', () => {
  expect(code).not.toMatch(/enabled\s*=\s*true/i)
  expect(code).not.toMatch(/status\s*=\s*'qualified'\s*,/)
  expect(code).not.toMatch(/set status = 'qualified'/)
  expect(code).not.toMatch(/aer\.v2_shadow_on/)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
