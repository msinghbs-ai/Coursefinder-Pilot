import React, { useEffect, useRef, useState } from 'react'
import { Button, Loading, Metric, SectionTitle, StatusChip, fmtDateTime } from './ui-kit'
import { intakeRunApi } from './intake-run-api'
import { intakeParity, parityByProvider, PARITY_LABEL } from './intake-parity'
import { runOutcomeNotice } from './intake-run-outcome'
import { intakeErrorMessage } from './intake-error-message'
import { intakeStageTimeline } from './intake-stage-timeline'
import { summariseEvidence } from './intake-evidence-view'
import './intake-run-validate.css'

const value = x => x == null ? 'Not held' : typeof x === 'object' ? JSON.stringify(x, null, 2) : String(x)
function Evidence({ data }) { return <pre className="intake-evidence">{value(data)}</pre> }
function EvidenceSummary({ data }) {
  return <dl className="intake-evidence-summary">{summariseEvidence(data).map(r => <div key={r.label}><dt>{r.label}</dt><dd>{r.value}</dd></div>)}</dl>
}
function Source({ url }) {
  try { if (!['https:', 'http:'].includes(new URL(url).protocol)) return null } catch { return null }
  return <a className="cf-link" href={url} target="_blank" rel="noreferrer">Official source</a>
}

export default function IntakeRunValidate({ rank = 0, client = intakeRunApi }) {
  const [caps, setCaps] = useState(null), [error, setError] = useState(''), [busy, setBusy] = useState('')
  const [scope, setScope] = useState(''), [size, setSize] = useState(''), [reason, setReason] = useState('')
  const [preview, setPreview] = useState(null), [cohort, setCohort] = useState(null), [run, setRun] = useState(null)
  const [report, setReport] = useState(null), [lookup, setLookup] = useState(''), [diagnostic, setDiagnostic] = useState(null)
  const lock = useRef(false), request = useRef(null)
  const execute = async (name, fn) => {
    if (lock.current) return
    lock.current = true; setBusy(name); setError('')
    try { await fn() } catch (e) {
      setError(intakeErrorMessage(name, e))
    }
    finally { lock.current = false; setBusy('') }
  }
  const load = () => execute('Loading capabilities', async () => {
    setCaps(null); setPreview(null)
    const c = await client.read('capabilities')
    if (c?.contract !== 'intake-run-validate-v1') throw new Error('The intake UI browser contract is unavailable. Ask the release integrator to supply the documented bridge.')
    setCaps(c); setScope(c.scopes?.[0]?.id || ''); setSize(String(c.default_size ?? ''))
    const savedId = new URLSearchParams(location.hash.split('?')[1] || '').get('intake_cohort')
    const saved = c.recent?.find(x => x.cohort_id === savedId) || c.recent?.[0]
    if (saved) {
      const result = await client.read('verify', { cohort_id: saved.cohort_id })
      restore(result)
    }
  })
  useEffect(() => { load() }, [client])
  const sizeValid = Number.isInteger(Number(size)) && Number(size) >= caps?.min_size && Number(size) <= caps?.max_size
  const canRun = caps?.can_run === true && rank >= caps?.control_rank
  const invalidate = () => { setPreview(null); setCohort(null); setRun(null); setReport(null); setDiagnostic(null); request.current = null }
  const restore = r => {
    setReport(r); setLookup(r.cohort_id)
    const saved = r.saved_request
    if (saved) {
      setCohort({ cohort_id: r.cohort_id }); setScope(saved.scope); setSize(String(saved.size)); setReason(saved.reason)
      request.current = { cohortId: r.cohort_id, key: saved.request_key, reason: saved.reason }
      const last = r.runs?.at(-1)
      setRun(last ? { ...last.result, ...last } : null)
    }
  }
  const verify = id => execute('Reading verification', async () => {
    const r = await client.read('verify', { cohort_id: id })
    restore(r)
  })
  const prepare = () => execute('Fixing cohort', async () => {
    const c = await client.prepare({ p_scope: scope, p_size: Number(size), p_reason: reason.trim(), p_preview_token: preview.token })
    // A bridge must refuse changed selection; never silently run a different cohort.
    if (!c?.cohort_id || c.preview_token !== preview.token || !c.request_key) throw new Error('Selection changed. Preview again before running.')
    setCohort(c); setLookup(c.cohort_id)
    request.current = { key: c.request_key, reason: c.reason || reason.trim(), cohortId: c.cohort_id }
    const [path, search = ''] = location.hash.split('?'); const params = new URLSearchParams(search)
    params.set('intake_cohort', c.cohort_id); history.replaceState(null, '', `${location.pathname}${location.search}${path || '#/layer-2-discovery'}?${params}`)
  })
  const start = () => execute('Running intake job', async () => {
    const q = request.current
    setRun({ state: 'awaiting_response' })
    try {
      const result = await client.run(q.cohortId, q.reason, q.key)
      setRun({ ...result?.result, ...result })
    }
    catch (e) { setRun({ state: 'outcome_unknown' }); throw e }
  })
  const courses = report?.courses || preview?.courses || []
  const unknown = run?.state === 'outcome_unknown'
  return <section className="m-panel intake-run" aria-label="Course intake Run & Validate">
    <SectionTitle title="Course intake Run & Validate" subtitle="Automatically selected courses, stored official evidence and approved academic calendars. The existing intake job applies its normal controls."/>
    {busy && <Loading label={`${busy}…`}/>}
    {error && <p role="alert">{error}</p>}
    {!caps && !busy && <p>Blocked: the required browser bridge is unavailable. Next action: ask the release integrator to provide the intake UI contract; no job has been started.</p>}
    <Button compact onClick={load} disabled={!!busy || !!cohort}>Refresh capabilities</Button>
    {caps && <>
      {!canRun && <p>Read only: your role or the job controls do not permit Run Now.</p>}
      {caps.universities?.length > 0 && <details><summary>Approved Australian universities and active course counts</summary>{caps.universities.map(u => <p key={u.id}>{u.name}: {u.active_courses} active courses</p>)}</details>}
      {caps.blocked_reason && <p role="status">Blocked: {caps.blocked_reason}. Next action: {caps.next_action || 'Ask the authorised operator to review the job controls.'}</p>}
      <div className="intake-form">
        <label>University scope<select value={scope} disabled={!!busy || !!cohort} onChange={e => { invalidate(); setScope(e.target.value) }}>
          <option value="">Select a scope</option>{(caps.scopes || []).map(s => <option key={s.id} value={s.id}>{s.label}</option>)}
        </select></label>
        <label>Cohort size<input type="number" min={caps.min_size} max={caps.max_size} step="1" value={size} disabled={!!busy || !!cohort} onChange={e => { invalidate(); setSize(e.target.value) }}/><small>Server limit: {caps.min_size}–{caps.max_size} courses</small></label>
        <label>Audited reason<textarea value={reason} disabled={!!busy || !!cohort} onChange={e => setReason(e.target.value)}/></label>
      </div>
      <div className="intake-actions">
        <Button disabled={!!busy || !!cohort || !scope || !sizeValid} onClick={() => execute('Previewing eligible courses', async () => { invalidate(); setPreview(await client.read('preview', { scope, size: Number(size) })) })}>Preview eligible courses</Button>
        <Button disabled={!!busy || !canRun || !!caps.blocked_reason || !preview?.token || !preview.courses?.length || !reason.trim() || !!cohort} onClick={prepare}>Fix previewed cohort</Button>
        <Button variant="primary" disabled={!!busy || !canRun || !!caps.blocked_reason || !cohort || (!!run && !unknown)} onClick={start}>{unknown ? 'Recover same request' : 'Run Now'}</Button>
        {cohort && <Button disabled={!!busy} onClick={() => verify(cohort.cohort_id)}>Verify catalogue & publication</Button>}
      </div>
      {cohort && <Button disabled={!!busy || run?.state === 'awaiting_response' || unknown} onClick={invalidate}>New cohort</Button>}
      {preview && <p>{preview.courses?.length || 0} selected of {preview.eligible_courses ?? 'unknown'} eligible courses. {preview.rule} Preview at {fmtDateTime(preview.as_at)}; expires {fmtDateTime(preview.expires_at)}.</p>}
      {preview?.universities && <details open><summary>Eligibility by university (bounded independent scans)</summary>{preview.universities.map(u => <p key={u.id}>{u.name}: {u.active_courses} active courses · {u.eligible_courses} eligible courses in {u.rows_planned} evaluated rows · scan limit {u.scan_limit}</p>)}</details>}
      {preview && <details><summary>Eligibility stops and missing evidence</summary><Evidence data={preview.skipped_by_reason || {}}/></details>}
      {preview && !preview.courses?.length && <p role="status">Blocked: no eligible intake values were found in this bounded preview. Unexamined rows are not classified as ineligible. Next action: review the evaluated scan limits and stored page/calendar evidence. The scope has not been widened.</p>}
      {cohort && <p>Fixed cohort: {cohort.cohort_id}. Reason: {request.current?.reason}. Saved on the server; results and the same request key are restored after refresh.</p>}
      {run && <div role="status"><StatusChip value={run.state}/>{run.outcome && <StatusChip value={run.outcome}/>}<p>Run: {run.run_id || 'Awaiting confirmed run ID'} · Started {fmtDateTime(run.started_at)} · Finished {fmtDateTime(run.finished_at)}</p>
        <p>{run.state === 'awaiting_response' ? 'Waiting for the synchronous job response; intermediate progress is not exposed.' : unknown ? 'Outcome unknown. Verify this cohort first. Recover same request uses the original idempotency key; it never creates a new run request.' : `Processed ${run.processed ?? 'unknown'} · Admitted ${run.admitted ?? 'unknown'} · Skipped ${run.skipped ?? 'unknown'} · Failed ${run.failed ?? 'unknown'}`}</p>
        {run.next_action && <p>{run.next_action}</p>}
        {runOutcomeNotice(run) && <p role="alert" className="intake-outcome-notice">{runOutcomeNotice(run).text}</p>}
        {(run.refused || run.error || run.result?.refused || run.result?.error) && <><p>{run.refused || run.error || run.result?.refused || run.result?.error}</p><p>Next action: verify the cohort and review the recorded refusal with an authorised operator. Resume only through existing job controls after resolving the cause.</p></>}
      </div>}
      {(cohort || report) && <details open className="intake-stages"><summary>Run stages</summary><ol>{intakeStageTimeline({ cohort, preview, run, report }).map(s => <li key={s.key} data-stage={s.key} data-state={s.state}><strong>{s.label}</strong> · {s.state.replaceAll('_', ' ')}{s.at ? ` · ${fmtDateTime(s.at)}` : ''}<br/><small>{s.detail}</small></li>)}</ol></details>}
      {caps.recent?.length > 0 && <label>Saved cohorts<select value="" disabled={!!busy} onChange={e => { if (e.target.value) verify(e.target.value) }}><option value="">Open a saved cohort</option>{caps.recent.map(r => <option key={r.cohort_id} value={r.cohort_id}>{fmtDateTime(r.created_at)} · {r.reason}</option>)}</select></label>}
      <div className="intake-actions"><label>Existing cohort ID<input value={lookup} onChange={e => setLookup(e.target.value)} placeholder="UUID"/></label><Button disabled={!!busy || (!!cohort && lookup !== cohort.cohort_id) || !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(lookup)} onClick={() => verify(lookup)}>Read existing cohort</Button></div>
      {report && <>
        <p>Verification at {fmtDateTime(report.as_at)} · Cohort {report.cohort_id}. {report.verdict || 'Verdict not supplied by backend'} {report.next_action}</p>
        <div className="intake-metrics">{Object.entries(report.totals || {}).filter(([, v]) => typeof v === 'number').map(([k, v]) => <Metric key={k} label={k.replaceAll('_', ' ')} value={v}/>)}</div>
        {courses.length > 0 && <details open><summary>Catalogue, Website and Zoho agreement by university</summary><div className="intake-table-scroll"><table><thead><tr><th>University</th><th>Courses</th><th>Website matches</th><th>Website differs</th><th>Website not read</th><th>Zoho matches</th><th>Zoho differs</th><th>Zoho not read</th></tr></thead><tbody>{parityByProvider(courses).map(r => <tr key={r.provider}><td>{r.provider}</td><td>{r.courses}</td><td>{r.website.match}</td><td>{r.website.differs}</td><td>{r.website.not_read + r.website.cannot_compare}</td><td>{r.zoho.match}</td><td>{r.zoho.differs}</td><td>{r.zoho.not_read + r.zoho.cannot_compare}</td></tr>)}</tbody></table></div><p>Read-only comparison of the values shown below. A side that was not read is counted as not read, never as a match.</p></details>}
        <details><summary>Audited runs and failure reasons</summary><Evidence data={report.runs}/><Evidence data={report.totals?.skipped_or_failed}/></details>
      </>}
      {courses.map(c => <article key={c.course_id} className="intake-course">
        <h3>{c.course_title || c.course_id}</h3><p>{c.provider_name || c.provider_id} · {c.pattern} · {(c.fills || []).join(', ')}</p><p>{c.eligibility_reason}</p><Source url={c.course_url}/>
        <details><summary>Source evidence and values at selection</summary>{(c.at_selection || c.evidence || []).map((e, i) => <div key={e.intake_id || i}><Source url={e.page_url}/><Source url={e.calendar_url}/><EvidenceSummary data={e}/><Evidence data={e}/></div>)}</details>
        {report && <><details open><summary>Before / after intake values</summary>{(c.added || []).map((a, i) => <div key={a.intake_id || i} className="intake-values"><div><strong>Before</strong><Evidence data={a.before}/></div><div><strong>After</strong><Evidence data={a.after}/></div></div>)}{!c.added?.length && <p>No newly admitted values recorded.</p>}<strong>Current catalogue</strong><Evidence data={c.now}/></details>
          <details><summary>Website / Zoho read-back</summary><p>Website matches: {c.published ?? 'unknown'}. Zoho response alone does not prove value consistency.</p>{(() => { const p = intakeParity(c); return <p data-testid="intake-parity">Website: {PARITY_LABEL[p.website.state]} ({p.website.note}) · Zoho: {PARITY_LABEL[p.zoho.state]} ({p.zoho.note})</p> })()}{c.publication && <p>Catalogue: {c.publication.catalogue} · Website: {c.publication.website} · Zoho: {c.publication.zoho}</p>}<strong>Website intakes</strong><Evidence data={c.website_intakes}/><strong>Zoho intakes</strong><Evidence data={c.zoho_intakes}/></details></>}
      </article>)}
      {caps.diagnostic?.approved === true && caps.diagnostic?.read_only === true && caps.diagnostic?.model && <><Button disabled={!!busy || !report?.cohort_id} onClick={() => execute('Reading AI diagnostic', async () => setDiagnostic(await client.read('diagnostic', { cohort_id: report.cohort_id })))}>AI diagnostic ({caps.diagnostic.model})</Button>{diagnostic && <Evidence data={diagnostic}/>}</>}
      {!caps.diagnostic?.approved && <p>AI diagnostic unavailable: no approved read-only diagnostic capability is advertised.</p>}
    </>}
  </section>
}
