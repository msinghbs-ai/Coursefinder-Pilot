import React, { useEffect, useRef, useState } from 'react'
import { Button, Loading, Metric, SectionTitle, StatusChip, fmtDateTime } from './ui-kit'
import { intakeRunApi } from './intake-run-api'
import './intake-run-validate.css'

const value = x => x == null ? 'Not held' : typeof x === 'object' ? JSON.stringify(x, null, 2) : String(x)
function Evidence({ data }) { return <pre className="intake-evidence">{value(data)}</pre> }
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
    try { await fn() } catch (e) { setError(e?.message || 'Request failed. Check access and refresh before continuing.') }
    finally { lock.current = false; setBusy('') }
  }
  const load = () => execute('Loading capabilities', async () => {
    setCaps(null); setPreview(null)
    const c = await client.read('capabilities')
    if (c?.contract !== 'intake-run-validate-v1') throw new Error('The intake UI browser contract is unavailable. Ask the release integrator to supply the documented bridge.')
    setCaps(c); setScope(c.scopes?.[0]?.id || ''); setSize(String(c.default_size ?? ''))
  })
  useEffect(() => { load() }, [client])
  const sizeValid = Number.isInteger(Number(size)) && Number(size) >= caps?.min_size && Number(size) <= caps?.max_size
  const canRun = caps?.can_run === true && rank >= caps?.control_rank
  const invalidate = () => { setPreview(null); setCohort(null); setRun(null); setReport(null); setDiagnostic(null); request.current = null }
  const verify = id => execute('Reading verification', async () => {
    const r = await client.read('verify', { cohort_id: id })
    setReport(r); setLookup(id)
  })
  const prepare = () => execute('Fixing cohort', async () => {
    const c = await client.prepare({ p_scope: scope, p_size: Number(size), p_reason: reason.trim(), p_preview_token: preview.token })
    // A bridge must refuse changed selection; never silently run a different cohort.
    if (!c?.cohort_id || c.preview_token !== preview.token) throw new Error('Selection changed. Preview again before running.')
    setCohort(c); request.current = { key: crypto.randomUUID(), reason: reason.trim(), cohortId: c.cohort_id }
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
      {caps.blocked_reason && <p role="status">Blocked: {caps.blocked_reason}. Next action: {caps.next_action || 'Ask the authorised operator to review the job controls.'}</p>}
      <div className="intake-form">
        <label>University scope<select value={scope} disabled={!!busy || !!cohort} onChange={e => { invalidate(); setScope(e.target.value) }}>
          <option value="">Select a scope</option>{(caps.scopes || []).map(s => <option key={s.id} value={s.id}>{s.label}</option>)}
        </select></label>
        <label>Cohort size<input type="number" min={caps.min_size} max={caps.max_size} step="1" value={size} disabled={!!busy || !!cohort} onChange={e => { invalidate(); setSize(e.target.value) }}/><small>Server limit: {caps.min_size}–{caps.max_size} courses</small></label>
        <label>Audited reason<textarea value={reason} disabled={!!busy || !!cohort} onChange={e => setReason(e.target.value)}/></label>
      </div>
      <div className="intake-actions">
        <Button disabled={!!busy || !!cohort || !scope || !sizeValid || !!caps.blocked_reason} onClick={() => execute('Previewing eligible courses', async () => { invalidate(); setPreview(await client.read('preview', { scope, size: Number(size) })) })}>Preview eligible courses</Button>
        <Button disabled={!!busy || !canRun || !!caps.blocked_reason || !preview?.token || !preview.courses?.length || !reason.trim() || !!cohort} onClick={prepare}>Fix previewed cohort</Button>
        <Button variant="primary" disabled={!!busy || !canRun || !!caps.blocked_reason || !cohort || (!!run && !unknown)} onClick={start}>{unknown ? 'Recover same request' : 'Run Now'}</Button>
        {cohort && <Button disabled={!!busy} onClick={() => verify(cohort.cohort_id)}>Verify catalogue & publication</Button>}
      </div>
      {preview && <p>{preview.courses?.length || 0} selected of {preview.eligible_courses ?? 'unknown'} eligible courses. {preview.rule} Preview at {fmtDateTime(preview.as_at)}; expires {fmtDateTime(preview.expires_at)}.</p>}
      {cohort && <p>Fixed cohort: {cohort.cohort_id}. Reason: {request.current?.reason}. Keep this cohort ID to resume verification after leaving this page.</p>}
      {run && <div role="status"><StatusChip value={run.state}/><p>Run: {run.run_id || 'Awaiting confirmed run ID'} · Started {fmtDateTime(run.started_at)} · Finished {fmtDateTime(run.finished_at)}</p>
        <p>{run.state === 'awaiting_response' ? 'Waiting for the synchronous job response; intermediate progress is not exposed.' : unknown ? 'Outcome unknown. Verify this cohort first. Recover same request uses the original idempotency key; it never creates a new run request.' : `Processed ${run.processed ?? 'unknown'} · Admitted ${run.admitted ?? 'unknown'} · Skipped ${run.skipped ?? 'unknown'} · Failed ${run.failed ?? 'unknown'}`}</p>
        {(run.refused || run.error || run.result?.refused || run.result?.error) && <><p>{run.refused || run.error || run.result?.refused || run.result?.error}</p><p>Next action: verify the cohort and review the recorded refusal with an authorised operator. Resume only through existing job controls after resolving the cause.</p></>}
      </div>}
      <div className="intake-actions"><label>Existing cohort ID<input value={lookup} onChange={e => setLookup(e.target.value)} placeholder="UUID"/></label><Button disabled={!!busy || (!!cohort && lookup !== cohort.cohort_id) || !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(lookup)} onClick={() => verify(lookup)}>Read existing cohort</Button></div>
      {report && <>
        <p>Verification at {fmtDateTime(report.as_at)} · Cohort {report.cohort_id}. {report.verdict || 'Verdict not supplied by backend'} {report.next_action}</p>
        <div className="intake-metrics">{Object.entries(report.totals || {}).filter(([, v]) => typeof v === 'number').map(([k, v]) => <Metric key={k} label={k.replaceAll('_', ' ')} value={v}/>)}</div>
        <details><summary>Audited runs and failure reasons</summary><Evidence data={report.runs}/><Evidence data={report.totals?.skipped_or_failed}/></details>
      </>}
      {courses.map(c => <article key={c.course_id} className="intake-course">
        <h3>{c.course_title || c.course_id}</h3><p>{c.provider_name || c.provider_id} · {c.pattern} · {(c.fills || []).join(', ')}</p>
        <details><summary>Source evidence and values at selection</summary>{(c.at_selection || c.evidence || []).map((e, i) => <div key={e.intake_id || i}><Source url={e.calendar_url}/><Evidence data={e}/></div>)}</details>
        {report && <><details open><summary>Before / after intake values</summary>{(c.added || []).map((a, i) => <div key={a.intake_id || i} className="intake-values"><div><strong>Before</strong><Evidence data={a.before}/></div><div><strong>After</strong><Evidence data={a.after}/></div></div>)}{!c.added?.length && <p>No newly admitted values recorded.</p>}<strong>Current catalogue</strong><Evidence data={c.now}/></details>
          <details><summary>Website / Zoho read-back</summary><p>Website matches: {c.published ?? 'unknown'}. Zoho response alone does not prove value consistency.</p><strong>Website intakes</strong><Evidence data={c.website_intakes}/><strong>Zoho intakes</strong><Evidence data={c.zoho_intakes}/></details></>}
      </article>)}
      {caps.diagnostic?.approved === true && caps.diagnostic?.read_only === true && caps.diagnostic?.model && <><Button disabled={!!busy || !report?.cohort_id} onClick={() => execute('Reading AI diagnostic', async () => setDiagnostic(await client.read('diagnostic', { cohort_id: report.cohort_id })))}>AI diagnostic ({caps.diagnostic.model})</Button>{diagnostic && <Evidence data={diagnostic}/>}</>}
      {!caps.diagnostic?.approved && <p>AI diagnostic unavailable: no approved read-only diagnostic capability is advertised.</p>}
    </>}
  </section>
}
