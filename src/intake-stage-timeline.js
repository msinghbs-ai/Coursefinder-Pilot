// F-INT.03: the stages one intake run passes through, read only from what the server already returned.
// Pure and read-only. A stage the server did not report is "Not recorded", never inferred as done.
const num = x => (typeof x === 'number' && Number.isFinite(x) ? x : null)
const FINISHED = new Set(['done', 'succeeded', 'completed', 'success'])
const stage = (key, label, state, detail, at = null) => ({ key, label, state, detail, at })

export function intakeStageTimeline({ cohort, preview, run, report } = {}) {
  const id = cohort?.cohort_id || report?.cohort_id || null
  const runState = String(run?.state || '').toLowerCase()
  const courses = report?.courses || preview?.courses || []
  const selected = num(report?.totals?.selected) ?? (courses.length || null)
  const withEvidence = courses.filter(c => (c.at_selection || c.evidence || []).length > 0).length
  const stages = []

  stages.push(id ? stage('queued', 'Cohort fixed', 'done', `Cohort ${id} is saved on the server.`) : stage('queued', 'Cohort fixed', 'pending', 'No cohort is fixed yet.'))
  stages.push(selected ? stage('selected', 'Courses selected', 'done', `${selected} course${selected === 1 ? '' : 's'} selected.`, preview?.as_at || null)
    : stage('selected', 'Courses selected', id ? 'not_recorded' : 'pending', id ? 'The server did not report the selection.' : 'Preview first.'))
  stages.push(courses.length ? stage('evidence', 'Evidence held', withEvidence === courses.length ? 'done' : 'warning', `${withEvidence} of ${courses.length} courses show stored page or calendar evidence.`)
    : stage('evidence', 'Evidence held', 'not_recorded', 'No course evidence is shown yet.'))

  if (!run) stages.push(stage('validated', 'Validated or refused', 'pending', 'The job has not been run.'))
  else if (runState === 'awaiting_response') stages.push(stage('validated', 'Validated or refused', 'pending', 'Waiting for the job response.', run.started_at || null))
  else if (runState === 'outcome_unknown') stages.push(stage('validated', 'Validated or refused', 'unknown', 'Outcome unknown. Verify the cohort; do not run it again as a new request.'))
  else if (runState === 'refused' || run.refused || run.error) stages.push(stage('validated', 'Validated or refused', 'failed', 'The job refused this run. The recorded reason is shown above.', run.finished_at || null))
  else if (FINISHED.has(runState)) stages.push(stage('validated', 'Validated or refused', 'done', `Job answered ${runState}.`, run.finished_at || null))
  else stages.push(stage('validated', 'Validated or refused', 'not_recorded', `Job state "${run.state ?? 'not supplied'}" is not a known outcome.`))

  const admitted = num(run?.admitted) ?? num(report?.totals?.admitted)
  if (admitted === null) stages.push(stage('admitted', 'Admitted or withdrawn', run && FINISHED.has(runState) ? 'not_recorded' : 'pending', run && FINISHED.has(runState) ? 'The job did not report how many were admitted.' : 'Nothing admitted yet.'))
  else stages.push(stage('admitted', 'Admitted or withdrawn', admitted > 0 ? 'done' : 'warning', `${admitted} admitted${num(run?.failed) ? `, ${run.failed} failed` : ''}${num(run?.skipped) ? `, ${run.skipped} skipped` : ''}.`))

  const read = report ? courses.filter(c => c.website_intakes != null && c.zoho_intakes != null && !c.zoho_intakes?.error && !c.website_intakes?.error).length : null
  stages.push(report ? stage('readback', 'Website and Zoho read-back', read === courses.length && courses.length ? 'done' : 'warning', `${read} of ${courses.length} courses were read back from both Website and Zoho without error.`, report.as_at || null)
    : stage('readback', 'Website and Zoho read-back', 'pending', 'Run Verify catalogue & publication.'))

  stages.push(report?.http_verified === true ? stage('http', 'HTTP verification', 'done', 'Authenticated HTTP check recorded.')
    : stage('http', 'HTTP verification', 'not_recorded', 'No authenticated HTTP check is recorded for this run. A database read-back is not HTTP proof.'))
  return stages
}
