// Guards: StudySearch Feature Acceptance F-INT.03 (stage-by-stage execution, restore after reload) under IQ-00313; a stage the server did not report is never shown as done.
import { test, expect } from '@playwright/test'
import { intakeStageTimeline } from '../../src/intake-stage-timeline.js'
const by = (t, k) => t.find(s => s.key === k)

test('before anything is fixed every stage is pending or not recorded', () => {
  const t = intakeStageTimeline({})
  expect(t.map(s => s.key)).toEqual(['queued', 'selected', 'evidence', 'validated', 'admitted', 'readback', 'http'])
  expect(by(t, 'queued').state).toBe('pending'); expect(by(t, 'validated').state).toBe('pending'); expect(by(t, 'http').state).toBe('not_recorded')
})
test('a clean verified run shows done stages but HTTP stays not recorded', () => {
  const c = { course_id: 'c1', at_selection: [{}], website_intakes: [{ year: 2027 }], zoho_intakes: [{ year: 2027 }] }
  const t = intakeStageTimeline({ cohort: { cohort_id: 'x' }, run: { state: 'done', processed: 1, admitted: 1, failed: 0, finished_at: '2026-11-08T10:00:00Z' }, report: { cohort_id: 'x', as_at: '2026-11-08T10:01:00Z', totals: { selected: 1 }, courses: [c] } })
  for (const k of ['queued', 'selected', 'evidence', 'validated', 'admitted', 'readback']) expect(by(t, k).state).toBe('done')
  expect(by(t, 'http').state).toBe('not_recorded')
})
test('a Zoho read-back error is a warning, not a pass', () => {
  const c = { course_id: 'c1', at_selection: [{}], website_intakes: [], zoho_intakes: { error: 'Unsupported read-back' } }
  expect(by(intakeStageTimeline({ cohort: { cohort_id: 'x' }, report: { cohort_id: 'x', courses: [c] } }), 'readback').state).toBe('warning')
})
test('refused, unknown and admitted-nothing outcomes are not shown as success', () => {
  expect(by(intakeStageTimeline({ cohort: { cohort_id: 'x' }, run: { state: 'refused', refused: 'job is paused' } }), 'validated').state).toBe('failed')
  expect(by(intakeStageTimeline({ cohort: { cohort_id: 'x' }, run: { state: 'outcome_unknown' } }), 'validated').state).toBe('unknown')
  expect(by(intakeStageTimeline({ cohort: { cohort_id: 'x' }, run: { state: 'done', processed: 3, admitted: 0 } }), 'admitted').state).toBe('warning')
  expect(by(intakeStageTimeline({ cohort: { cohort_id: 'x' }, run: { state: 'done' } }), 'admitted').state).toBe('not_recorded')
})
test('http_verified true is the only way HTTP verification shows done', () => {
  expect(by(intakeStageTimeline({ report: { cohort_id: 'x', http_verified: true, courses: [] } }), 'http').state).toBe('done')
  expect(by(intakeStageTimeline({ report: { cohort_id: 'x', http_verified: 'yes', courses: [] } }), 'http').state).toBe('not_recorded')
})
