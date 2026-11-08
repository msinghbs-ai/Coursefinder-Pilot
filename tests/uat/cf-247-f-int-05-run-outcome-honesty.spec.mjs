// Guards: StudySearch Feature Acceptance F-INT.05 (producer success without admission, 0 eligible) under IQ-00313; Platform Admin rule that a succeeded job is not data gain.
import { test, expect } from '@playwright/test'
import { runOutcomeNotice } from '../../src/intake-run-outcome.js'

test('a finished job that admitted nothing is called out, not shown as success', () => {
  const n = runOutcomeNotice({ state: 'done', processed: 5, admitted: 0, skipped: 5, failed: 0 })
  expect(n.tone).toBe('warning'); expect(n.text).toContain('admitted none'); expect(n.text).toContain('5 skipped')
})
test('failures inside a done job are called out with the count', () => {
  expect(runOutcomeNotice({ state: 'done', processed: 4, admitted: 3, failed: 1 }).text).toContain('1 of 4 courses failed')
})
test('zero processed courses is called out', () => {
  expect(runOutcomeNotice({ state: 'succeeded', processed: 0, admitted: 0, failed: 0 }).text).toContain('processed no courses')
})
test('a clean run and unknown or unfinished figures give no notice', () => {
  expect(runOutcomeNotice({ state: 'done', processed: 1, admitted: 1, failed: 0, skipped: 0 })).toBeNull()
  expect(runOutcomeNotice({ state: 'done', processed: 1 })).toBeNull()
  expect(runOutcomeNotice({ state: 'awaiting_response' })).toBeNull()
  expect(runOutcomeNotice({ state: 'refused', processed: 0, admitted: 0 })).toBeNull()
  expect(runOutcomeNotice({ state: 'outcome_unknown' })).toBeNull()
  expect(runOutcomeNotice(null)).toBeNull()
})
