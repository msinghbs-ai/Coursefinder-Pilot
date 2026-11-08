// F-INT.05: a job that answers "done" is not the same as courses admitted. Pure and read-only:
// it only words what the server already returned and never counts an unknown figure as success.
const num = x => (typeof x === 'number' && Number.isFinite(x) ? x : null)
const FINISHED = new Set(['done', 'succeeded', 'completed', 'success'])

export function runOutcomeNotice(run) {
  if (!run || !FINISHED.has(String(run.state || '').toLowerCase())) return null
  const processed = num(run.processed), admitted = num(run.admitted), failed = num(run.failed), skipped = num(run.skipped)
  if (processed === null || admitted === null) return null // unknown stays unknown; the screen already says so
  if (failed > 0) return { tone: 'warning', text: `The job reported done, but ${failed} of ${processed} courses failed. Verify the cohort before treating this run as a success.` }
  if (processed === 0) return { tone: 'warning', text: 'The job reported done but processed no courses. Nothing was admitted. Verify the cohort and review the eligibility stops.' }
  if (admitted === 0) return { tone: 'warning', text: `The job reported done and processed ${processed} courses, but admitted none${skipped ? ` (${skipped} skipped)` : ''}. A finished job is not data gain. Verify the cohort and review the skip reasons.` }
  return null
}
