// Guards: CF-247 F-INT (11 Nov 2026, RMIT Rule B switch-on, Decision 271): an adapter's intakes reading keeps the page's own words around the months so the offering check can read the intake statement; Rule B never dates a course at a study level named in intake_dates.nearest_start_hold_levels (vocational and pathway courses follow their own calendar).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261111235900_cf247_rule_b_vocational_hold.sql', 'utf8')
const AD = fs.readFileSync('supabase/functions/coverage-sweep/adapters.ts', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('the adapter keeps the end of its whole match as the intake wording, not the months alone', () => {
  expect(AD).toContain('export function patternValues(a: Adapter, text: string, code = "", words?: Record<string, string>)')
  expect(AD).toContain('if (words) words[f] = ')
  expect(AD).toContain('export function patternWordsTail(w: string): string')
  expect(AD).toContain('intake_context: pIntakes && pIntakes.length ? [`adapter pattern: ${patternWordsTail(patWords.intakes || pat.intakes)}`.slice(0, 200)]')
  expect(AD).not.toContain('[`adapter pattern: ${pat.intakes}`.slice(0, 200)]')
  // the months read are unchanged: the value is still the bracketed part
  expect(AD).toContain('({ v: clean(m[1] ?? m[0]), w: clean(m[0]) })')
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v0.68.0";')
})

test('Rule B holds the study levels the setting names; the setting is a governed list', () => {
  expect(MIG).toContain("'intake_dates.nearest_start_hold_levels'")
  expect(MIG).toMatch(/'list', '\["certificate","certificate_i","certificate_ii","certificate_iii","certificate_iv","diploma","advanced_diploma","vocational_short_course","non_aqf_award","foundation"\]'::jsonb,\s*\n\s*0, null, 'study level codes'/)
  expect(MIG).toContain("'a vocational or pathway course is not dated from the main teaching calendar (month only)'")
  // md5-guarded edit, rehearsed on the live definition
  expect(MIG).toContain("'a99b42c7007436a78860a386652f81a9', '5e864efd7758ea2149e28f6566ac466b'")
  expect(MIG).toContain('raise exception \'post-check: security.intake_nearest_start_v1 does not have the recorded body\'')
  // narrows only: the provider list and month_unique_match are not touched
  expect(MIG).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(MIG).not.toMatch(/month_unique_match/)
})
