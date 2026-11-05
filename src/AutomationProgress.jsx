import React, { useEffect, useRef, useState } from 'react'
import { Button, Loading, Metric, SectionTitle, StatusChip, fmtDateTime, fmtMoney, fmtNumber } from './ui-kit'
import { hrefFor } from './nav-map'
import './automation-progress.css'

// CF-247 Automation Progress (Platform Admin decision 5 Nov 2026 16:36 §3-§8; decision 19:14 §10): a persistent section of Layer 2/3 Operations ›
// Intake Run & Validate › Process results showing what the intake dates automation is doing, from persisted records only:
// current state → work processed → data admitted → data published → failures → next action → historical evidence.
// Server: public.admin_intake_progress_v1 (read only, Operations read and above). Pause/Resume is the existing job on/off control
// (public.admin_automation_control, audited in pipeline.admin_control_events); no other scheduler or control is created here.
const STATE = {
  waiting: ['success', 'Waiting for the next run (healthy, idle)'], running: ['info', 'Running'], paused: ['warning', 'Paused'],
  switched_off: ['warning', 'Switched off in Pipeline settings'], failed: ['danger', 'Last run failed'], stalled: ['danger', 'Stalled: the next run is overdue'],
  missing: ['danger', 'Job not found'],
}
const UNI = {
  not_processed: ['neutral', 'Not processed'], zero_eligible: ['warning', 'Zero eligible'], admitted: ['success', 'Admitted'],
  eligible_not_admitted: ['warning', 'Eligible, not admitted'],
}
const WINDOWS = [['latest', 'Latest run'], ['24h', 'Last 24 hours'], ['7d', 'Last 7 days'], ['30d', 'Last 30 days']]
const KIND = { scheduled: 'Scheduled run', run_now: 'Governed Run Now', withdrawal: 'Governed withdrawal' }
const n = x => x == null ? 'Not held' : typeof x === 'number' ? fmtNumber(x) : String(x)
const when = x => x ? fmtDateTime(x) : 'none'
const words = x => String(x || '').replaceAll('_', ' ')
const plural = (x, one, many) => `${n(x)} ${Number(x) === 1 ? one : many}`
// pg_cron runs in UTC; an hourly schedule's minute is the same in Australian time
const every = c => /^\d{1,2} \* \* \* \*$/.test(c || '') ? `hourly at :${String(c.split(' ')[0]).padStart(2, '0')}` : `schedule ${c || 'not set'}`
const WINDOW_KEY = 'cf.intakeProgress.window'
function readWindow() { try { const v = localStorage.getItem(WINDOW_KEY); return WINDOWS.some(([k]) => k === v) ? v : 'latest' } catch { return 'latest' } }
function saveWindow(v) { try { localStorage.setItem(WINDOW_KEY, v) } catch { /* per-viewer convenience only */ } }
function Link({ url, children }) {
  try { if (!['https:', 'http:'].includes(new URL(url).protocol)) return null } catch { return null }
  return <a className="cf-link" href={url} target="_blank" rel="noreferrer">{children}</a>
}

function Funnel({ f, pending }) {
  const steps = [
    ['Eligible (pending work now)', pending, 'never examined at the latest measurement plus revisits due'],
    ['Selected', f.selected, `${n(f.selected_courses)} courses`],
    ['Examined', f.examined],
    ['Evidence found', f.evidence_found, 'course page wording stored'],
    ['Dates extracted', f.dates_extracted],
    ['Dates validated', f.dates_validated, 'passed evidence, calendar and applicability rules'],
    ['Values admitted', f.admitted],
    ['Values published', f.published, `${n(f.publication_failed)} not in the Website API source · ${n(f.provider_not_published)} provider not published · ${n(f.publication_not_checked)} not checked yet`],
    ['Values refused or held', f.refused_or_held, f.nothing_new ? `${n(f.nothing_new)} had nothing new` : ''],
    ['Awaiting the next revisit', f.awaiting_revisit, `${n(f.waiting_for_change)} wait for a change of their inputs`],
  ]
  return <ol className="ap-funnel" data-testid="ap-funnel">{steps.map(([label, v, note], i) =>
    <li key={label} data-step={i + 1}><span className="ap-step">{i + 1}</span><span className="ap-label">{label}</span><strong>{n(v)}</strong>{note && <small>{note}</small>}</li>)}</ol>
}

function Universities({ rows, onDrill, busy }) {
  return <div className="intake-table-scroll"><table className="cf-table ap-table" data-testid="ap-universities">
    <thead><tr><th>University</th><th>Scope</th><th>State</th><th>Pending</th><th>Selected</th><th>Eligible</th><th>Admitted</th><th>Published</th><th>Held</th><th>Last run</th><th>Next revisit</th><th></th></tr></thead>
    <tbody>{rows.map(u => <tr key={u.provider_id} data-university={u.university} data-state={u.state}>
      <td>{u.university}</td><td>{u.pilot ? 'Pilot' : 'Other provider'}</td>
      <td><StatusChip value={u.state} tone={(UNI[u.state] || [])[0]} label={(UNI[u.state] || [])[1] || words(u.state)}/></td>
      <td>{u.pending == null ? 'Not measured' : n(u.pending)}</td><td>{n(u.selected)}</td><td>{n(u.eligible)}</td><td>{n(u.admitted)}</td><td>{n(u.published)}</td>
      <td>{n(u.held)}{u.withdrawn ? ` (${n(u.withdrawn)} withdrawn)` : ''}</td><td>{when(u.last_run)}</td><td>{u.next_revisit ? fmtDateTime(u.next_revisit) : 'on a change of its inputs'}</td>
      <td><Button compact disabled={!!busy} onClick={() => onDrill(u)}>Courses</Button></td></tr>)}</tbody></table></div>
}

function Failures({ data, filter, setFilter, busy }) {
  if (!data) return null
  return <section className="ap-block" data-testid="ap-failures" aria-label="Failures and holds">
    <h4>Failures and holds ({n(data.total)} intake rows{filter.university ? ` · ${filter.university}` : ''}{filter.class ? ` · ${words(filter.class)}` : ''})</h4>
    <div className="ap-chips">{(data.classes || []).map(c => <Button key={c.class} compact disabled={!!busy} aria-pressed={filter.class === c.class}
      onClick={() => setFilter({ ...filter, class: filter.class === c.class ? '' : c.class })}>{words(c.class)}: {n(c.rows)}{c.person_required ? ` (${n(c.person_required)} need a person)` : ''}</Button>)}
      {(filter.class || filter.provider_id) && <Button compact disabled={!!busy} onClick={() => setFilter({})}>Show all</Button>}</div>
    {(data.rows || []).length === 0 && <p>No failed or held row matches.</p>}
    {(data.rows || []).map(r => <article key={r.intake_id} className="ap-failure" data-class={r.class}>
      <p><StatusChip value={r.class} tone={r.person_required ? 'danger' : 'warning'} label={words(r.class)}/> <strong>{r.course_title || r.course_id}</strong> {r.intake} · {r.university} <Link url={r.course_url}>Course page</Link></p>
      <p>{r.reason}</p>
      <dl className="ap-facts">
        <div><dt>Evidence version</dt><dd>{[r.evidence_version?.calendar_set, r.evidence_version?.reader, r.evidence_version?.evidence_year, r.evidence_version?.rule].filter(Boolean).join(' · ') || 'not recorded'}</dd></div>
        <div><dt>Last attempt</dt><dd>{when(r.last_attempt)}</dd></div>
        <div><dt>Next action</dt><dd>{words(r.next_action) || 'not recorded'}</dd></div>
        <div><dt>Next revisit</dt><dd>{r.next_revisit_at ? fmtDateTime(r.next_revisit_at) : (r.revisit_trigger || 'when its inputs change')}</dd></div>
        <div><dt>Integration issue</dt><dd>{r.issue ? `${r.issue.ref} (${words(r.issue.status)}, ${r.issue.severity})` : 'none'}</dd></div>
        <div><dt>Recovers automatically</dt><dd>{r.auto_recover ? `Yes: ${r.automatic}` : 'No'}</dd></div>
        <div><dt>A person must act</dt><dd>{r.person_required ? 'Yes' : 'No'}</dd></div>
      </dl>
      <Link url={r.evidence_version?.calendar_url}>Calendar used</Link>
    </article>)}
    {data.total > (data.rows || []).length && <p>Showing the newest {n((data.rows || []).length)}; filter by class or university for the rest.</p>}
  </section>
}

export default function AutomationProgress({ rank = 0, client }) {
  const [status, setStatus] = useState(null), [win, setWin] = useState(readWindow), [data, setData] = useState(null), [fails, setFails] = useState(null)
  const [filter, setFilter] = useState({}), [busy, setBusy] = useState(''), [error, setError] = useState(''), [snaps, setSnaps] = useState(null)
  const lock = useRef(false), failRef = useRef(null)
  const run = async (name, fn) => {
    if (lock.current) return
    lock.current = true; setBusy(name); setError('')
    try { await fn() } catch (e) { setError(e?.message || 'Request failed. Check access and refresh.') } finally { lock.current = false; setBusy('') }
  }
  const failArgs = f => ({ ...(f.class ? { class: f.class } : {}), ...(f.provider_id ? { provider_id: f.provider_id } : {}) })
  const load = (w = win, f = filter) => run('Loading automation progress', async () => {
    const [s, d, x] = await Promise.all([client.progress('status'), client.progress('window', { window: w }), client.progress('failures', failArgs(f))])
    setStatus(s); setData(d); setFails(x)
  })
  useEffect(() => { if (client?.progress) load() }, [client])
  if (!client?.progress) return null
  const pickWindow = w => { setWin(w); saveWindow(w); run('Loading history', async () => setData(await client.progress('window', { window: w }))) }
  const pickFilter = f => { setFilter(f); run('Loading failures', async () => setFails(await client.progress('failures', failArgs(f)))) }
  const drill = u => { pickFilter({ provider_id: u.provider_id, university: u.university }); setTimeout(() => failRef.current?.scrollIntoView?.({ block: 'start' }), 0) }
  const toggle = action => {
    const label = action === 'pause' ? 'Pause' : 'Resume'
    if (!window.confirm(`${label} the intake dates job (intake-dates-apply)? This uses the existing Automations control and is recorded with your name.`)) return
    run(`${label} requested`, async () => {
      await client.control(status.controls.job, action, { reason: `Process results › Automation progress: ${label.toLowerCase()}` })
      setStatus(await client.progress('status'))
    })
  }
  const openRunValidate = () => document.querySelector('[aria-label="Course intake Run & Validate"]')?.scrollIntoView?.({ block: 'start' })
  const s = status, c = s?.controls || {}, [tone, stateLabel] = STATE[s?.state] || ['neutral', words(s?.state)]
  const pending = s ? (s.pending?.never_examined == null ? null : s.pending.never_examined + (s.pending.revisit_due || 0)) : null
  const f = data?.funnel, alerts = (s?.alerts || []).slice().sort((a, b) => Number(b.tripped) - Number(a.tripped))
  return <section className="ap" data-testid="automation-progress" aria-label="Automation progress">
    <SectionTitle title="Automation progress: intake dates" subtitle="What the scheduled intake job is doing now, what each run processed, admitted and published, what failed and why, and what happens next. Counts come from the saved run records."/>
    {busy && <Loading label={`${busy}…`}/>}
    {error && <p role="alert">{error}</p>}
    {s && <>
      <div className="ap-state" data-state={s.state}>
        <StatusChip value={s.state} tone={tone} label={stateLabel}/>
        {s.latest_run_admitted_nothing && <StatusChip value="no_values_admitted" tone="warning" label="The last run completed but admitted no value"/>}
        <span>Job {s.job} · {every(s.schedule)} · last success {when(s.last_success)} · next run {s.next_run ? fmtDateTime(s.next_run) : 'not scheduled'}</span>
      </div>
      <div className="intake-metrics">
        <Metric label="Last run" value={s.last_run ? `${fmtDateTime(s.last_run.started_at)} → ${s.last_run.finished_at ? fmtDateTime(s.last_run.finished_at) : 'still open'}` : 'none'} detail={s.last_run ? `run ${s.last_run.runid} · ${words(s.last_run.status)}` : ''}/>
        <Metric label="Running now" value={s.running_run ? `run ${s.running_run}` : 'No run open'} detail={s.current_university || ''}/>
        <Metric label="Batch and scope" value={`${n(s.batch)} rows a run`} detail={`${n(s.pilot_share_pct)}% for the ${(s.scope || []).length} pilot universities · ${n(s.provider_share)} rows a provider a round`}/>
        <Metric label="Processing rate" value={`${n(s.rate_per_hour_24h)} rows an hour`} detail="over the last 24 hours"/>
        <Metric label="Pending eligible work" value={pending == null ? 'Not measured' : n(pending)} detail={`${n(s.pending?.never_examined)} never examined (measured ${when(s.pending?.measured_at)}) · ${n(s.pending?.revisit_due)} revisits due`}/>
        <Metric label="Held or blocked" value={n(s.held?.held)} detail={`${n(s.held?.timed_revisit)} on a revisit date · ${n(s.held?.waiting_for_change)} wait for a change · ${n(s.held?.person_required)} need a person`}/>
        <Metric label="AI use" value={fmtMoney(Number(s.usage?.ai_cost_usd || 0), 'USD', { decimals: 4 })} detail={`calendar reading, last ${n(s.usage?.ai_window_days)} days`}/>
        <Metric label="Firecrawl credits" value={`${n(s.usage?.firecrawl_credits_counted)} of ${n(s.usage?.firecrawl_budget)}`} detail="calendar refresh"/>
      </div>
      <p className="ap-scope">Pilot scope: {(s.scope || []).join(', ')}. Observer: job {s.observer?.job}, last run {when(s.observer?.last_run)}, last snapshot {when(s.observer?.last_snapshot)}.</p>
      <div className="intake-actions ap-controls" data-testid="ap-controls">
        <Button compact disabled={!!busy} onClick={() => load()}>Refresh</Button>
        {c.can_pause_resume && (s.active
          ? <Button compact disabled={!!busy} onClick={() => toggle('pause')}>Pause intake job</Button>
          : <Button compact variant="primary" disabled={!!busy} onClick={() => toggle('resume')}>Resume intake job</Button>)}
        <Button compact disabled={!!busy} onClick={openRunValidate}>Preview, Run Now and Verify publication</Button>
        <a className="cf-link" href={hrefFor('layer4')}>Review blockers in Layer 4</a>
        {rank >= 5 && <a className="cf-link" href={hrefFor('health', 'integration')}>Integration queue</a>}
      </div>
      {!c.can_pause_resume && <p className="ap-note">Read only: Pause and Resume are for the {c.control_rank >= 6 ? 'Platform Admin' : 'PIM Admin'} and above, through the existing Automations control.</p>}
      <section className="ap-block" aria-label="Alerts">
        <h4>Alerts</h4>
        <ul className="ap-alerts">{alerts.map(a => <li key={a.code} data-alert={a.code} data-tripped={a.tripped ? 'yes' : 'no'}>
          <StatusChip value={a.tripped ? 'raised' : 'clear'} tone={a.tripped ? 'danger' : 'success'} label={a.tripped ? 'Raised' : 'Clear'}/> <strong>{a.label}</strong>
          {a.tripped && <> · {n(a.affected)} affected · last successful stage: {a.last_success_stage} · next action: {a.next_action}{a.routed ? ' · in the integration queue' : ''}</>}
          {!a.tripped && a.zero_reason && <> · {words(a.zero_reason)}</>}
        </li>)}</ul>
      </section>
    </>}
    <section className="ap-block" aria-label="History">
      <div className="ap-windows" role="group" aria-label="History window">{WINDOWS.map(([k, label]) =>
        <Button key={k} compact variant={win === k ? 'primary' : undefined} aria-pressed={win === k} disabled={!!busy} onClick={() => pickWindow(k)}>{label}</Button>)}</div>
      {data?.empty && <p role="status">No intake run is recorded yet.</p>}
      {f && <>
        <p data-testid="ap-window-summary">{WINDOWS.find(([k]) => k === win)?.[1]}: {data.since === data.until ? fmtDateTime(data.since) : `${fmtDateTime(data.since)} to ${fmtDateTime(data.until)}`} · gross activity {plural(f.selected, 'row', 'rows')} in {plural(f.runs, 'run', 'runs')} ({n(f.scheduled_runs)} scheduled, {n(f.run_now_runs)} Run Now) · net data gain {n(f.net_gain)} (admitted {n(f.admitted)}, withdrawn {n(f.withdrawn)})</p>
        <Funnel f={f} pending={pending}/>
      </>}
      {data?.universities && <><h4>Universities</h4><Universities rows={data.universities} onDrill={drill} busy={busy}/></>}
      {(data?.runs || []).length > 0 && <details className="ap-runs"><summary>Runs in this window ({n(data.runs.length)})</summary><ul>{data.runs.map(r => <li key={r.run_at} data-kind={r.kind}>
        <strong>{fmtDateTime(r.run_at)}</strong> · {KIND[r.kind] || r.kind}{r.cron_run ? ` · run ${r.cron_run.runid} ${words(r.cron_run.status)}` : ''} · selected {n(r.selected)} · validated {n(r.validated)} · admitted {n(r.admitted)} · published {n(r.published)} · held {n(r.held)}{r.withdrawn ? ` · withdrawn ${n(r.withdrawn)}` : ''}
        <small> · {(r.by_provider || []).slice(0, 4).map(p => `${p.university}: ${n(p.rows)}`).join(', ')}</small></li>)}</ul></details>}
    </section>
    <div ref={failRef}><Failures data={fails} filter={filter} setFilter={pickFilter} busy={busy}/></div>
    <div className="intake-actions"><Button compact disabled={!!busy} onClick={() => run('Loading saved snapshots', async () => setSnaps(await client.progress('measurements')))}>Saved progress snapshots</Button></div>
    {snaps && <ul className="ap-snaps">{snaps.length === 0 ? <li>No snapshot saved yet. The process-results job saves one every hour.</li> : snaps.map(x => <li key={x.id}>{fmtDateTime(x.measured_at)} · {words(x.state)} · latest run admitted {n(x.latest_run?.admitted)} of {n(x.latest_run?.selected)}{x.alerts?.length ? ` · raised: ${x.alerts.map(words).join(', ')}` : ''}</li>)}</ul>}
  </section>
}
