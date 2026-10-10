// CF-247 Decision 229: intake check v1.3.0 is a separate contract chosen per profile; v1.2.0 is unchanged.
import fs from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import os from 'node:os'
import path from 'node:path'
import { test, expect } from '@playwright/test'

async function bundle(src, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('npx', ['esbuild', src, '--bundle', '--format=esm', '--platform=node', '--keep-names', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}

test('v1.2.0 contract file untouched; router dispatches by prompt_profile_version', async () => {
  const v12 = await fs.readFile('supabase/functions/_shared/cf247-intake-validation.ts', 'utf8')
  expect(v12).toContain('export const INTAKE_VALIDATOR_VERSION = "cf247-intake-validation-v1.2.0";')
  expect(v12).not.toContain('v1.3.0')
  const r = await fs.readFile('supabase/functions/layer3-model-routing/index.ts', 'utf8')
  expect(r).toContain('intakeBodyFor(tp, m, text')
  expect(r).toContain('intakeCheckFor(tp, r.answer, text, blockers)')
  expect(r).toContain('intakeCheckFor(profile, r.answer, text, blockers)')
  expect(r).toContain('contractVersionFor(task, profile)')
  const m = await fs.readFile('supabase/migrations-archive/20261002183800_cf247_intake_check_v13_profiles.sql', 'utf8')
  expect(m).toContain("'cf247-intake-validation-v1.3.0'")
  expect(m).toContain('true, true,') // enabled, paused
})

test('binding: v1.2.0 profiles keep their descriptor; v1.3.0 profiles get their own', async () => {
  const mr = await bundle('supabase/functions/_shared/cf247-model-routing.ts', 'mr')
  const p12 = { model_identifier: 'qwen/qwen3-30b-a3b-instruct-2507', max_output_tokens: 1200, timeout_ms: 45000, prompt_profile_version: 'cf247-intake-validation-v1.2.0' }
  const d12 = JSON.parse(mr.factBindingDescriptor('intake', p12))
  expect(d12.contract).toEqual(JSON.parse(JSON.stringify(mr.contractComponents('intake'))))
  expect(d12.contract.version).toBe('cf247-intake-validation-v1.2.0')
  const d13 = JSON.parse(mr.factBindingDescriptor('intake', { ...p12, prompt_profile_version: 'cf247-intake-validation-v1.3.0' }))
  expect(d13.contract.version).toBe('cf247-intake-validation-v1.3.0')
  expect(JSON.parse(mr.factBindingDescriptor('english', { ...p12, prompt_profile_version: 'cf247-intake-validation-v1.3.0' })).contract.version).not.toContain('intake')
})

test('v1.3.0 accepts the patterns read in the waiting reviews and still rejects the unsafe ones', async () => {
  const v = await bundle('supabase/functions/_shared/cf247-intake-validation-v13.ts', 'v13')
  const ok = (a, t) => v.validateIntakeAnswerV13(a, t)
  expect(ok({ status: 'months', months: [1, 2], quotes: ['Intake Months each year January', 'Intake Months each year February'] }, 'Dates and Fees Intake Months each year January February April May')).toMatchObject({ valid: true })
  expect(ok({ status: 'months', months: [1, 7], quotes: ['Commences January, July'] }, 'Study Load Commences Scheduled Tonsley On campus 20 hours per week Full Time January, July Apply Now')).toMatchObject({ valid: true })
  expect(ok({ status: 'months', months: [1, 2], quotes: ['12/01', '16/02'] }, 'Intake Dates 2026 12/01 | 16/02 | 13/04')).toMatchObject({ valid: true })
  expect(ok({ status: 'months', months: [1, 2], quotes: ['JAN 12', 'FEB 23'] }, 'Intake Dates JAN 12 FEB 23 APR 13')).toMatchObject({ valid: true })
  expect(ok({ status: 'months', months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], quotes: ['Intakes every Monday'] }, 'Intakes every Monday.')).toMatchObject({ valid: true })
  expect(ok({ status: 'months', months: [3], quotes: ['Starts in March 2027'] }, 'This course starts in July 2027.').errors).toContain('quote_not_in_page_text')
  expect(ok({ status: 'months', months: [3], quotes: ['Intake March'] }, 'Intake ' + 'x '.repeat(200) + 'March').errors).toContain('quote_not_in_page_text')
  expect(ok({ status: 'months', months: [2], quotes: ['Semester 1'] }, 'Commencing Semester 1').errors).toContain('month_not_in_quotes')
  expect(ok({ status: 'months', months: [1, 2], quotes: ['Intakes every Monday'] }, 'Intakes every Monday').errors).toContain('month_not_in_quotes')
  expect(ok({ status: 'months', months: [1], quotes: ['JAN 12'] }, 'JAN 5 and 12 FEB').errors).toContain('quote_not_in_page_text')
  expect(v.monthsWrittenV13('IELTS 6.5 overall 2026-2027')).toEqual([])
})
