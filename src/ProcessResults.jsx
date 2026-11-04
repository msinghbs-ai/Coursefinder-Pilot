import React, { useEffect, useRef, useState } from 'react'
import { Button, Loading, Metric, SectionTitle, StatusChip, fmtDateTime } from './ui-kit'
import { processResultsApi } from './process-results-api'
import './intake-run-validate.css'

// CF-247 process accountability (Platform Admin decision 5 Nov 2026 §6, §8, §10): Layer 2/3 Operations › Process results. Shows the saved
// measurements of the intake dates process (what it did, how many, what was missed and why, the next revisit) and, per university, the
// calendars, re-read state, reader findings and recent decisions with their evidence, so the Platform Admin can validate from the screen.
const ACTIONS = {
  complete: 'Complete',
  awaiting_official_calendar: 'Awaiting official calendar',
  calendar_needs_correction: 'Calendar needs correction',
  course_identity_unresolved: 'Course identity unresolved',
  evidence_ambiguous: 'Evidence ambiguous',
  reader_correction_needed: 'Reader correction needed',
  human_decision_required: 'Human decision required',
  budget_or_operational_limit: 'Budget or operational limit',
  not_published_by_provider: 'Not published by provider',
  waiting_for_next_academic_year: 'Waiting for next academic year',
  ready_for_scheduled_recovery: 'Ready for scheduled recovery',
}
const label = k => ACTIONS[k] || String(k || 'Not classified').replaceAll('_', ' ')
const n = x => x == null ? 'Not held' : typeof x === 'number' ? x.toLocaleString('en-AU') : String(x)
function Link({ url, children }) {
  try { if (!['https:', 'http:'].includes(new URL(url).protocol)) return null } catch { return null }
  return <a className="cf-link" href={url} target="_blank" rel="noreferrer">{children || 'Official source'}</a>
}
function Quote({ text }) { return text ? <blockquote className="intake-evidence">{text}</blockquote> : null }

function University({ u, client, busy, execute }) {
  const [detail, setDetail] = useState(null)
  const held = u.held || {}, web = u.in_website_source || {}, adm = u.admitted_7_days || {}
  return <details className="intake-course" data-university={u.university}>
    <summary><strong>{u.university}</strong> · start dates {n(held.start_date)} of {n(held.month)} intake rows · deadlines {n(held.application_deadline)} · valid calendars {n(u.calendars_valid)}{u.calendars_set_aside?.length ? ` (${u.calendars_set_aside.length} set aside)` : ''} · future periods {n(u.future_periods)}</summary>
    <div className="intake-metrics">
      <Metric label="Active courses" value={n(u.active_courses)}/>
      <Metric label="Courses with intake months" value={n(u.courses_with_intakes)}/>
      <Metric label="Course pages stored" value={n(u.course_pages_stored)}/>
      <Metric label="Valid calendars" value={n(u.calendars_valid)}/>
      <Metric label="Latest calendar year" value={n(u.calendar_latest_year)}/>
      <Metric label="Future periods (dated)" value={`${n(u.future_periods)} (${n(u.future_dated_starts)})`}/>
      <Metric label="Future deadlines" value={n(u.future_deadlines)}/>
      <Metric label="Held: year / start / deadline" value={`${n(held.year)} / ${n(held.start_date)} / ${n(held.application_deadline)}`}/>
      <Metric label="Website API source: year / start / deadline" value={`${n(web.year)} / ${n(web.start_date)} / ${n(web.application_deadline)}`}/>
      <Metric label="Admitted in the window: year / start / deadline" value={`${n(adm.year)} / ${n(adm.start_date)} / ${n(adm.application_deadline)}`}/>
      <Metric label="Never examined" value={n(u.never_examined)}/>
      <Metric label="Waiting for a change only" value={n(u.waiting_for_change_only)}/>
      <Metric label="Reader findings open" value={n(u.reader_findings_open)}/>
      <Metric label="AI cost in the window (USD)" value={Number(u.ai_cost_usd_7_days || 0).toFixed(4)}/>
      <Metric label="Firecrawl credits" value={n(u.firecrawl_credits)}/>
    </div>
    <p>Last attempt {u.last_attempt ? fmtDateTime(u.last_attempt) : 'never'} · next timed revisit {u.next_revisit ? fmtDateTime(u.next_revisit) : 'on a change of evidence, calendar, reader or settings'} · calendar freshness {u.calendar_freshest ? fmtDateTime(u.calendar_freshest) : 'no valid calendar'}</p>
    <h4>What was missed, and why</h4>
    {u.reasons?.length ? <ul>{u.reasons.map((r, i) => <li key={i}><StatusChip value={label(r.next_action)}/> {r.reason} — {n(r.rows)} rows</li>)}</ul> : <p>Nothing held.</p>}
    {u.calendars_set_aside?.length > 0 && <><h4>Calendars set aside (not deleted)</h4><ul>{u.calendars_set_aside.map((c, i) => <li key={i}><Link url={c.url}>{c.url}</Link> — {c.reason || c.scope}</li>)}</ul></>}
    <p>Calendar re-read: {Object.entries(u.calendar_reread || {}).map(([k, v]) => `${k.replaceAll('_', ' ')} ${v}`).join(' · ') || 'not started'}</p>
    <Button compact disabled={!!busy} onClick={() => execute(`Reading ${u.university}`, async () => setDetail(await client.read('university', { provider_id: u.provider_id })))}>Show calendars and recent decisions</Button>
    {detail && <div className="process-detail">
      <h4>Calendars</h4>
      {(detail.calendars || []).map(c => <article key={c.proposal_id} className="intake-course">
        <p><Link url={c.url}>{c.url}</Link> · {c.used ? 'used' : `set aside: ${c.set_aside_reason || c.scope}`} · reader {c.parser} · approved {c.decided_at ? fmtDateTime(c.decided_at) : 'not dated'} · evidence {c.evidence_id || 'not stored'}</p>
        <ul>{(c.starts || []).map((s, i) => <li key={i}>{s.period}: {s.date || `${s.month}/${s.year ?? 'year not printed'}`} <Quote text={s.quote}/></li>)}</ul>
        {(c.deadlines || []).length > 0 && <ul>{c.deadlines.map((d, i) => <li key={i}>Applications close ({d.applies_to || 'unstated'}) {d.period}: {d.date} <Quote text={d.quote}/></li>)}</ul>}
      </article>)}
      {(detail.findings || []).length > 0 && <><h4>Calendar reader findings (given to the next read)</h4><ul>{detail.findings.map((f, i) => <li key={i}>{f.code.replaceAll('_', ' ')}: {f.detail} ({f.times}×)<Quote text={f.example}/></li>)}</ul></>}
      {(detail.flags || []).length > 0 && <><h4>Routed to a person</h4><ul>{detail.flags.map(f => <li key={f.id}>{f.reason} (flag {f.id}, {fmtDateTime(f.flagged_at)})</li>)}</ul></>}
      <h4>Recent decisions</h4>
      {(detail.recent || []).length === 0 && <p>No decision recorded yet.</p>}
      {(detail.recent || []).map((e, i) => <article key={i} className="intake-course">
        <p><StatusChip value={e.outcome}/> <strong>{e.course_title}</strong> <Link url={e.course_url}>Course page</Link> · {fmtDateTime(e.run_at)}{e.bounded ? ' · governed Run Now' : ''}</p>
        <p>{e.reason || (e.outcome === 'filled' ? 'Values admitted' : '')} · next action: {label(e.next_action)}{e.next_revisit_at ? ` · revisit ${fmtDateTime(e.next_revisit_at)}` : ''} · rule {e.rule}</p>
        <div className="intake-values"><div><strong>Before</strong><pre className="intake-evidence">{JSON.stringify(e.before)}</pre></div><div><strong>After</strong><pre className="intake-evidence">{JSON.stringify(e.after)}</pre></div></div>
        <Quote text={e.page_quote}/><Quote text={e.start_quote}/><Quote text={e.deadline_quote}/><Link url={e.calendar_url}>Calendar</Link>
      </article>)}
    </div>}
  </details>
}

export default function ProcessResults({ rank = 0, client = processResultsApi }) {
  const [latest, setLatest] = useState(null), [history, setHistory] = useState(null), [error, setError] = useState(''), [busy, setBusy] = useState('')
  const lock = useRef(false)
  const execute = async (name, fn) => {
    if (lock.current) return
    lock.current = true; setBusy(name); setError('')
    try { await fn() } catch (e) { setError(e?.message || 'Request failed. Check access and refresh.') } finally { lock.current = false; setBusy('') }
  }
  const load = () => execute('Loading saved results', async () => setLatest(await client.read('latest', { process: 'intake-dates' })))
  useEffect(() => { load() }, [])
  const s = latest?.summary, t = s?.totals || {}, jobs = s?.jobs || {}
  return <section className="m-panel intake-run" aria-label="Process results">
    <SectionTitle title="Process results" subtitle="Saved measurements of the intake dates process for the top Australian universities: what it did, how many, what was missed and why, and when it is looked at again."/>
    {busy && <Loading label={`${busy}…`}/>}
    {error && <p role="alert">{error}</p>}
    <div className="intake-actions">
      <Button compact disabled={!!busy} onClick={load}>Refresh</Button>
      {rank >= 4 && <Button compact disabled={!!busy} onClick={() => execute('Measuring now', async () => { await client.read('measure'); setLatest(await client.read('latest', { process: 'intake-dates' })) })}>Measure now</Button>}
      <Button compact disabled={!!busy} onClick={() => execute('Loading earlier measurements', async () => setHistory(await client.read('history', { process: 'intake-dates' })))}>Earlier measurements</Button>
    </div>
    {!busy && !latest && !error && <p role="status">No measurement saved yet. The process-results job records one every hour.</p>}
    {s && <>
      <p>Measured {fmtDateTime(latest.measured_at)} by {latest.measured_by}. Job intake-dates-apply: {jobs.enabled ? 'on' : 'off'}, {jobs.intake_dates_apply?.schedule}, last run {jobs.intake_dates_apply?.last_run ? `${fmtDateTime(jobs.intake_dates_apply.last_run.at)} (${jobs.intake_dates_apply.last_run.status})` : 'none'}, last success {jobs.intake_dates_apply?.last_success ? fmtDateTime(jobs.intake_dates_apply.last_success) : 'none'}; {n(jobs.batch)} rows a run; unique month {jobs.month_unique_match ? 'on' : 'off'}; waiting rows looked at again after {n(jobs.revisit_days)} days. Calendar re-read: last run {jobs.calendar_reread?.last_run ? `${fmtDateTime(jobs.calendar_reread.last_run.at)} (${jobs.calendar_reread.last_run.status})` : 'none'}.</p>
      <div className="intake-metrics">
        <Metric label="Active courses" value={n(t.active_courses)}/>
        <Metric label="Course pages stored" value={n(t.course_pages_stored)}/>
        <Metric label="Valid calendars" value={n(t.calendars_valid)}/>
        <Metric label="Future periods" value={n(t.future_periods)}/>
        <Metric label="Intake rows" value={n(t.intake_rows)}/>
        <Metric label="With year" value={n(t.held_year)}/>
        <Metric label="With start date" value={n(t.held_start_date)}/>
        <Metric label="With deadline" value={n(t.held_application_deadline)}/>
        <Metric label="Start dates in Website API source" value={n(t.website_start_date)}/>
        <Metric label="Never examined" value={n(t.never_examined)}/>
      </div>
      {(s.universities || []).map(u => <University key={u.provider_id} u={u} client={client} busy={busy} execute={execute}/>)}
    </>}
    {history && <details open><summary>Earlier measurements</summary><ul>{history.map(h => <li key={h.id}>{fmtDateTime(h.measured_at)} · start dates {n(h.totals?.held_start_date)} · deadlines {n(h.totals?.held_application_deadline)} · years {n(h.totals?.held_year)} · never examined {n(h.totals?.never_examined)}</li>)}</ul></details>}
  </section>
}
