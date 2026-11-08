// CF-247 F-INT.06: the controls and settings that govern the intake dates job, read from the progress status the server already returns.
// Nothing here is a value of its own: a field the server does not return reads "Not held", never a default or a guess (G2: values live in settings).
const num = x => (typeof x === 'number' && Number.isFinite(x)) ? String(x) : null
const str = x => (typeof x === 'string' && x.trim()) ? x.trim() : null

export function summariseControls(status) {
  const s = status && typeof status === 'object' ? status : {}
  const c = s.controls && typeof s.controls === 'object' ? s.controls : {}
  const o = s.observer && typeof s.observer === 'object' ? s.observer : {}
  const who = c.can_pause_resume ? 'You can pause and resume this job' : (num(c.control_rank) != null ? `Pause and Resume need rank ${num(c.control_rank)} or above` : null)
  const rows = [
    ['Job', str(s.job)],
    ['Schedule (pg_cron)', str(s.schedule)],
    ['Rows a run', num(s.batch)],
    ['Share for pilot universities (%)', num(s.pilot_share_pct)],
    ['Rows a provider a round', num(s.provider_share)],
    ['Progress observer window (hours)', num(o.window_hours)],
    ['Stall raised after (hours)', num(o.stall_hours)],
    ['Who can change the job', who],
  ]
  return rows.map(([label, v]) => ({ label, value: v ?? 'Not held', held: v != null }))
}
