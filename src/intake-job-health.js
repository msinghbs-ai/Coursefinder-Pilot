// F-INT.06: a green scheduled run is not the same as work done. Pure and read-only: it only words what the
// progress bridge already returned, and an unknown figure is never read as success or as failure.
const num = x => (typeof x === 'number' && Number.isFinite(x) ? x : null)
const OK = new Set(['succeeded', 'success', 'done', 'completed'])
const BAD = new Set(['failed', 'error'])

// One run in the history list. Returns null when the run needs no flag or the figures are not held.
export function runHealth(run) {
  const status = String(run?.cron_run?.status || '').toLowerCase()
  if (BAD.has(status)) return { tone: 'danger', text: 'The scheduled run failed.' }
  if (!OK.has(status)) return null
  const selected = num(run.selected), admitted = num(run.admitted), published = num(run.published)
  if (selected === null || admitted === null) return null
  if (selected === 0) return { tone: 'warning', text: 'The scheduled run finished but selected no rows. A finished run is not data gain.' }
  if (admitted === 0 && (published === null || published === 0)) return { tone: 'warning', text: `The scheduled run finished and selected ${selected} rows, but admitted and published none. A finished run is not data gain.` }
  return null
}

// The job-level state. "Waiting (healthy, idle)" must not hide a stage the observer reports as stalled or a raised alert.
export function stateConflict(status) {
  if (!status || status.state !== 'waiting') return null
  const stalled = (status.observer?.transitions || []).filter(t => t?.stalled === true)
  const raised = (status.alerts || []).filter(a => a?.tripped === true)
  if (!stalled.length && !raised.length) return null
  const parts = []
  if (stalled.length) parts.push(`${stalled.length === 1 ? 'stage' : 'stages'} ${stalled.map(t => t.title || t.key).join(', ')} ${stalled.length === 1 ? 'is' : 'are'} stalled`)
  if (raised.length) parts.push(`${raised.length} ${raised.length === 1 ? 'alert is' : 'alerts are'} raised`)
  return { tone: 'warning', text: `The job is waiting for its next run, but ${parts.join(' and ')}. The job being on schedule does not mean the work is moving.` }
}
