// CF-247 provider description autonomy mandate (4 November 2026).
// Extends Enrich fields' existing Provider descriptions card; decisions stay in Layer 4.
import React, { useEffect, useRef, useState } from 'react'
import { ExternalLink, RefreshCw } from 'lucide-react'
import { Button, Empty, Loading, Metric, StatusChip, humanLabel } from './ui-kit'
import { fmtDateTime, fmtNumber } from './lib/format.js'
import { plainError } from './lib/errors'
import { hrefFor } from './nav-map'
import { providerDescriptionRunApi } from './provider-description-run-api'
import './provider-description-run.css'

const list = value => Array.isArray(value) ? value : []
const shown = value => value == null || value === '' ? 'Not held' : typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value)
const cost = value => value == null ? 'Not available' : `US$${Number(value).toFixed(4)}`
const stamp = value => value ? fmtDateTime(value) : 'Not recorded'

export default function ProviderDescriptionRunValidate({ country = '', rank = 0, onError, metrics, onReloadMetrics, client = providerDescriptionRunApi }) {
  const [caps, setCaps] = useState(null), [scope, setScope] = useState({ country, provider_type: '', provider_id: '', description_state: 'missing', selection: 'top', size: '', mode: '' })
  const [preview, setPreview] = useState(null), [saved, setSaved] = useState(null), [history, setHistory] = useState([])
  const [reason, setReason] = useState(''), [explainReason, setExplainReason] = useState(''), [cohortInput, setCohortInput] = useState(''), [busy, setBusy] = useState(''), [error, setError] = useState(''), [note, setNote] = useState('')
  const [unknown, setUnknown] = useState(false), [diagnosis, setDiagnosis] = useState({}), epoch = useRef(0)
  const fail = e => { const message = plainError(e); setError(message); onError?.(message) }
  const useSaved = result => {
    if (result.history) setHistory(list(result.history))
    if (result.preview) {
      setPreview(result.preview); setSaved(null); setCohortInput(result.preview.token || result.preview.preview_token || ''); setDiagnosis({})
      if (result.scope || result.selection) setScope(s => ({ ...s, ...(result.scope || result.selection) }))
      return
    }
    if (result.cohort_id) {
      setSaved(result); setPreview(null); setCohortInput(result.cohort_id); setDiagnosis({})
      const savedScope = result.scope || result.selection
      if (savedScope) setScope(s => ({ ...s, ...savedScope }))
    }
  }
  useEffect(() => {
    let active = true
    const initialise = async () => {
      setBusy('load'); setError('')
      try {
        const capability = await client.call('capabilities')
        if (!active) return
        setCaps(capability)
        setScope(s => ({ ...s, country: s.country || list(capability.countries).find(x => x.enabled !== false)?.code || '', provider_type: list(capability.provider_types).find(x => x.enabled !== false)?.code || '', size: capability.default_size ?? '', mode: list(capability.modes).find(x => x.enabled !== false && x.allowed !== false)?.id || '' }))
        const result = await client.call('saved')
        if (active) useSaved(result)
      } catch (e) { if (active) fail(e) } finally { if (active) setBusy('') }
    }
    initialise()
    return () => { active = false; epoch.current++ }
  }, [client])
  useEffect(() => { if (country) change('country', country) }, [country])

  function change(key, value) {
    epoch.current++
    setScope(s => ({ ...s, [key]: value, ...(['country', 'provider_type', 'selection'].includes(key) ? { provider_id: '' } : {}) }))
    setPreview(null); setNote(''); setDiagnosis({}); setError('')
  }
  const operate = async (name, action) => {
    setBusy(name); setError(''); setNote('')
    try { await action() } catch (e) { fail(e) } finally { setBusy('') }
  }
  const refreshSaved = async (id = saved?.cohort_id) => {
    const result = await client.call('saved', id ? { cohort_id: id } : {})
    useSaved(result); setCaps(await client.call('capabilities')); await onReloadMetrics?.()
    return result
  }
  const selectPreview = () => operate('preview', async () => {
    const requestEpoch = epoch.current
    const result = await client.call('preview', { ...scope, size: Number(scope.size), provider_id: scope.selection === 'provider' ? scope.provider_id : null })
    if (requestEpoch === epoch.current) { setPreview(result); setSaved(null); setCohortInput(result.token || ''); setUnknown(false) }
  })
  const prepare = () => operate('prepare', async () => {
    const result = await client.call('prepare', { preview_token: preview.token, reason: reason.trim() })
    useSaved(result); setPreview(null); setUnknown(false)
    await refreshSaved(result.cohort_id)
    setNote('Cohort saved. Run Now uses this exact membership and the recorded audit reason.')
  })
  const run = () => operate('run', async () => {
    try {
      const result = await client.call('run', { cohort_id: saved.cohort_id })
      setUnknown(false)
      await refreshSaved(saved.cohort_id)
      setNote([humanLabel(result.state), result.reason, result.run_id ? `Run: ${result.run_id}` : ''].filter(Boolean).join(' · '))
    } catch (e) {
      setUnknown(true)
      throw e
    }
  })
  const verify = () => operate('verify', async () => { await client.call('verify', { cohort_id: saved.cohort_id }); await refreshSaved(saved.cohort_id); setNote('Read-back saved. Review each provider’s catalogue, Website and Zoho result below.') })
  const recover = () => operate('recover', async () => {
    const result = await refreshSaved(cohortInput.trim() || saved?.cohort_id)
    setUnknown(false)
    setNote(result.preview ? 'Recovered the saved preview and evidence. Save it as a fixed cohort before Run Now.' : result.cohort_id ? 'Recovered the saved cohort and its existing run references.' : 'No saved cohort was found.')
  })
  const explain = row => operate(`diagnose:${row.provider_id}`, async () => {
    const result = await client.call('diagnose', { cohort_id: saved?.cohort_id || null, provider_id: row.provider_id, preview_token: preview?.token || null, reason: explainReason.trim() })
    setDiagnosis(d => ({ ...d, [row.provider_id]: result }))
    setCaps(await client.call('capabilities'))
  })
  const rows = list(saved?.providers || preview?.providers)
  const totals = saved?.totals && {
    ...saved.totals,
    evidence_read: saved.totals.evidence_read ?? saved.totals.source_evidence_read,
    validation_failed: saved.totals.validation_failed ?? saved.totals.validation_failures,
    layer4_created: saved.totals.layer4_created ?? saved.totals.layer4_items,
    website_verified: saved.totals.website_verified ?? saved.totals.published,
    zoho_verified: saved.totals.zoho_verified ?? saved.zoho_verified,
    retries: saved.totals.retries ?? saved.totals.retried,
  }
  const locked = Boolean(saved?.cohort_id)
  const hasRuns = list(saved?.runs).length > 0 || Boolean(saved?.run_id)
  const validSize = caps && Number.isInteger(Number(scope.size)) && Number(scope.size) >= Number(caps.min_size) && Number(scope.size) <= Number(caps.max_size)
  const availableProviders = list(caps?.providers).filter(p => (!scope.country || p.country === scope.country) && (!scope.provider_type || (p.type || p.provider_type) === scope.provider_type))
  const canRun = caps?.can_run === true && rank >= Number(caps.control_rank ?? 5)
  const canExplain = (caps?.can_explain ?? caps?.can_run) === true && rank >= Number(caps.control_rank ?? 5)
  const notBusy = !busy
  return <div className="pdesc-run" data-provider-description-run-validate>
    {error && <p role="alert" className="pdesc-message pdesc-error">{error}</p>}
    {note && <p role="status" className="pdesc-message">{note}</p>}
    {busy && busy !== 'load' && <div role="status"><Loading compact label={busy === 'run' ? 'Submitting the saved cohort to the governed reader…' : busy === 'verify' ? 'Reading catalogue and consumer publication…' : busy.startsWith('diagnose:') ? 'Explaining stored evidence…' : 'Reading saved provider description work…'}/></div>}
    {!caps ? busy ? <Loading label="Loading governed description controls…"/> : <Empty text="Provider description controls are unavailable. Reload to retry the saved service."/> : <>
      <p className="sd-desc">The reader uses approved official evidence and the existing model. Each proposed description needs the applicable Layer 4 decision before admission. Current policy applies to every selection.</p>
      <div className="pdesc-policy" data-pdesc-policy><StatusChip value={caps.enabled && caps.job_active ? 'enabled' : 'paused'} label={caps.enabled && caps.job_active ? 'Reader on' : 'Reader paused'}/><span className="mdl-line" data-model-line="provider-description">Model: <strong>{caps.model ? shown(caps.model) : 'No model'}</strong> <a className="cf-link" href="#models-services?tab=ai&card=services.ai.services&at=services.ai.services&service=provider_description">change in Models &amp; services</a></span><span>AI ceiling: {cost(caps.policy?.ai_usd_max)}{caps.policy?.budget_period && ` (${caps.policy.budget_period})`}</span><span>Recorded AI spend (ledger): {cost(caps.policy?.recorded_cost_usd)}</span><span>Pending review limit: {shown(caps.policy?.pending_max)}</span></div>
      {(caps.policy?.reserved_usd != null || caps.policy?.remaining_usd != null || caps.policy?.daily_remaining_usd != null) && <div className="pdesc-policy" aria-label="Provider description spending allowance">
        {caps.policy.reserved_usd != null && <span>Reserved AI allowance: {cost(caps.policy.reserved_usd)}</span>}
        {caps.policy.remaining_usd != null && <span>Remaining approved AI allowance: {cost(caps.policy.remaining_usd)}</span>}
        {caps.policy.daily_remaining_usd != null && <span>Remaining shared daily allowance: {cost(caps.policy.daily_remaining_usd)}</span>}
      </div>}
      <fieldset className="pdesc-scope" disabled={Boolean(busy) || locked}>
        <legend>Provider scope</legend>
        <label>Country<select aria-label="Description country" value={scope.country} onChange={e => change('country', e.target.value)}>{list(caps.countries).map(c => <option key={c.code} value={c.code}>{c.label || c.code}{c.enabled === false ? ' — outside approved policy' : ''}</option>)}</select></label>
        <label>Provider type<select aria-label="Description provider type" value={scope.provider_type} onChange={e => change('provider_type', e.target.value)}>{list(caps.provider_types).map(t => <option key={t.code} value={t.code}>{t.label || humanLabel(t.code)}{t.enabled === false ? ' — outside approved policy' : ''}</option>)}</select></label>
        <label>Choose providers<select aria-label="Description provider selection" value={scope.selection} onChange={e => change('selection', e.target.value)}><option value="top">Top by active course count</option><option value="provider">Individual provider</option></select></label>
        {scope.selection === 'provider' && <label>Individual provider<select aria-label="Individual description provider" value={scope.provider_id} onChange={e => change('provider_id', e.target.value)}><option value="">Choose a provider</option>{availableProviders.map(p => <option key={p.provider_id} value={p.provider_id}>{p.name || p.provider}</option>)}</select></label>}
        <label>Description state<select aria-label="Description state" value={scope.description_state} onChange={e => change('description_state', e.target.value)}><option value="missing">Missing</option><option value="stale">Stale</option><option value="failed">Failed or held</option><option value="all">All eligible gaps</option></select></label>
        <label>Cohort size<input aria-label="Description cohort size" type="number" min={caps.min_size} max={caps.max_size} step="1" value={scope.size} onChange={e => change('size', e.target.value)}/><small>Approved range: {caps.min_size}–{caps.max_size}</small></label>
        <label>Processing mode<select aria-label="Description processing mode" value={scope.mode} onChange={e => change('mode', e.target.value)}>{list(caps.modes).map(m => <option key={m.id} value={m.id} disabled={m.enabled === false || m.allowed === false}>{m.label}</option>)}</select></label>
      </fieldset>
      <div className="pdesc-actions">
        <Button disabled={!notBusy || locked || !validSize || !scope.country || !scope.provider_type || !scope.mode || (scope.selection === 'provider' && !scope.provider_id)} onClick={selectPreview}>Preview providers</Button>
        {locked && <Button disabled={!notBusy} onClick={() => { epoch.current++; setSaved(null); setPreview(null); setCohortInput(''); setUnknown(false); setDiagnosis({}); setNote(''); setError('') }}>New cohort</Button>}
        <Button compact disabled={!notBusy} onClick={() => operate('refresh', async () => { await refreshSaved(); setNote('Saved results refreshed.') })}><RefreshCw size={14}/>Refresh saved results</Button>
      </div>
      {preview && <p data-pdesc-preview-summary><strong>{fmtNumber(preview.selected ?? rows.length)} selected</strong> from {shown(preview.eligible)} eligible providers. Selection as at {stamp(preview.as_at)}. {preview.expires_at && `Preview expires ${stamp(preview.expires_at)}.`}</p>}
      {list(preview?.exclusions).length > 0 && <details className="pdesc-exclusions"><summary>Eligibility exclusions ({preview.exclusions.length})</summary>{preview.exclusions.map((x, i) => <p key={x.provider_id || i}>{x.provider || x.name || x.country || x.provider_id}: {humanLabel(x.eligibility_reason || x.reason)}</p>)}</details>}
      <div className="pdesc-audit"><label>Audit reason<textarea aria-label="Provider description audit reason" value={reason} onChange={e => setReason(e.target.value)} disabled={Boolean(busy) || locked} placeholder="Explain why this bounded cohort is being processed"/></label>
        <Button disabled={!notBusy || !canRun || locked || !preview?.token || Number(preview.selected ?? rows.filter(r => r.eligible).length) === 0 || reason.trim().length < Number(caps.reason_min_chars ?? 5)} onClick={prepare}>Save previewed cohort</Button>
      </div>
      {!canRun && <p className="sd-desc">Your role can inspect evidence and refresh saved results for current read-back. An authorised operator must save or run a cohort, or verify consumer publication. The Website feed refreshes approved descriptions through its own scheduled check.</p>}
      {saved?.cohort_id && <section className="pdesc-saved" aria-label="Saved provider description cohort">
        <h4>Saved cohort</h4><p>Cohort: <code>{saved.cohort_id}</code></p>
        {saved.reason && <p>Audit reason: {saved.reason}</p>}
        {saved.created_at && <p>Saved: {stamp(saved.created_at)} {saved.requested_by && `· Requested by ${saved.requested_by}`}</p>}
        <div className="pdesc-actions"><Button variant="primary" disabled={!notBusy || !canRun || hasRuns || unknown || saved.can_run === false} onClick={run}>Run Now</Button><Button disabled={!notBusy || !canRun} title={!canRun ? 'An authorised operator is required to verify consumer publication. Refresh saved results to inspect current read-back.' : undefined} onClick={verify}>Verify catalogue & publication</Button></div>
        {unknown && <p role="status" className="pdesc-message">Outcome unknown. Recover this saved cohort before another action. The existing cohort ID is retained.</p>}
        {saved.reason_code && <p>Next action: {shown(saved.reason_code)}</p>}
        {totals && <div className="pdesc-totals">{[['selected', 'Providers selected'], ['evidence_read', 'Evidence read'], ['proposed', 'Descriptions proposed'], ['validation_failed', 'Validation failures'], ['layer4_created', 'Layer 4 items'], ['human_decisions_required', 'Human decisions required'], ['admitted', 'Descriptions admitted'], ['website_verified', 'Website verified'], ['zoho_verified', 'Zoho verified'], ['retries', 'Retries'], ['actual_ai_calls', 'Reported AI calls']].map(([key, label]) => <Metric key={key} label={label} value={totals[key] ?? 'Not measured'}/>)}<Metric label="Recorded AI cost" value={cost(totals.cost_usd)}/><Metric label="Reserved AI allowance" value={cost(totals.reserved_usd)}/></div>}
        {list(saved.runs).map((r, i) => <div className="pdesc-run-result" key={r.run_id || r.id || i}><StatusChip value={r.state || r.outcome}/><p>Run: <code>{shown(r.run_id || r.id)}</code> · Outcome: {shown(r.outcome)} · {stamp(r.started_at || r.created_at)}{r.finished_at ? ` to ${stamp(r.finished_at)}` : ''}</p>{(r.reason || r.result?.reason) && <p>Run detail: {humanLabel(r.result?.reason || r.reason)}</p>}</div>)}
        {saved.last_verification && <details><summary>Last saved publication verification</summary><p>Saved: {stamp(saved.verified_at)}</p><pre>{shown(saved.last_verification)}</pre></details>}
      </section>}
      <details className="pdesc-history" open={unknown}><summary>Saved runs and recovery</summary>
        <label>Saved cohorts<select aria-label="Saved provider description cohorts" value={cohortInput} disabled={Boolean(busy)} onChange={e => { const id = e.target.value; setCohortInput(id); if (id) operate('open', () => refreshSaved(id)) }}><option value="">Choose saved preview or cohort</option>{history.map(h => <option key={h.cohort_id} value={h.cohort_id}>{stamp(h.created_at)} · {humanLabel(h.state)}{h.selected != null ? ` · ${h.selected} providers` : ''} · {h.cohort_id}</option>)}</select></label>
        <label>Existing cohort ID<input aria-label="Existing provider description cohort ID" value={cohortInput} onChange={e => setCohortInput(e.target.value)} disabled={Boolean(busy)}/></label><Button disabled={!notBusy || !cohortInput.trim()} onClick={recover}>Recover saved cohort</Button>
      </details>
      {rows.length > 0 ? <>
        <label>Evidence explanation audit reason<textarea aria-label="Evidence explanation audit reason" value={explainReason} onChange={e => setExplainReason(e.target.value)} disabled={Boolean(busy) || !canExplain} placeholder="Explain why this evidence needs diagnosis"/><small>A reason is required for each saved explanation. This action cannot authorise admission.</small></label>
        <div className="pdesc-providers" aria-label="Provider description evidence">{rows.map(row => <ProviderEvidence key={row.provider_id} row={row} diagnosis={diagnosis[row.provider_id] || row.diagnosis} canDiagnose={caps.can_diagnose} diagnosisReason={caps.ai_diagnosis_reason} canExplain={canExplain && explainReason.trim().length >= Number(caps.reason_min_chars ?? 5)} busy={Boolean(busy)} onExplain={() => explain(row)}/>)}</div>
      </> : preview ? <Empty text="No provider meets this selection and the current policy. Inspect the exclusions; a short cohort does not widen eligibility."/> : null}
      {metrics && <details className="pdesc-history"><summary>Reader coverage and lifetime accounting</summary><div className="pdesc-totals">{[['eligible', 'Eligible'], ['present', 'Description present'], ['missing', 'Missing'], ['proposed', 'In Layer 4'], ['held', 'Held'], ['admitted', 'Admitted'], ['published', 'Published'], ['stored_pages_available', 'Stored About pages'], ['ai_reads', 'Reader records with a model'], ['backlog', 'Remaining']].map(([key, label]) => <Metric key={key} label={label} value={metrics[key] ?? 'Not measured'}/>)}<Metric label="Reported model calls" value={caps.policy?.actual_ai_calls ?? caps.actual_ai_calls ?? 'Not measured'}/><Metric label="Recorded billable calls (ledger)" value={caps.policy?.recorded_billable_calls ?? 'Not measured'}/><Metric label="Reader-recorded cost" value={cost(metrics.cost_usd)}/></div>{caps.policy?.ai_call_counter_scope && <p>{caps.policy.ai_call_counter_scope}</p>}<p>Last reader run: {stamp(metrics.last_run)}. Reader-recorded cost per admission: {cost(metrics.cost_per_admitted_usd)}.</p></details>}
    </>}
  </div>
}

function ProviderEvidence({ row, diagnosis, canDiagnose, diagnosisReason, canExplain, busy, onExplain }) {
  const publication = { ...(row.publication || row.verification || {}) }
  for (const key of ['catalogue', 'website', 'zoho']) {
    if (row[key] && typeof row[key] === 'object') publication[key] = { ...row[key], ...(typeof publication[key] === 'object' ? publication[key] : publication[key] ? { status: publication[key] } : {}) }
    else if (!publication[key] && row[key]) publication[key] = row[key]
  }
  const sentences = list(row.sentences)
  return <article className="pdesc-provider" data-pdesc-provider={row.provider_id}>
    <div className="pdesc-provider-head"><h4>{row.provider || row.name}</h4><StatusChip value={row.state || (row.eligible ? 'eligible' : 'excluded')}/></div>
    <p>{humanLabel(row.type)} · {row.country} · {fmtNumber(row.active_course_count ?? 0)} active courses</p>
    <dl className="pdesc-identity"><dt>Provider ID</dt><dd>{shown(row.provider_id)}</dd><dt>Stable identity</dt><dd>{shown(row.stable_key)}</dd><dt>Registration</dt><dd>{shown(row.registration)}</dd><dt>Eligibility</dt><dd>{humanLabel(row.eligibility_reason) || 'Not recorded'}</dd>{row.manual_locked != null && <><dt>Manual lock</dt><dd>{row.manual_locked ? 'Protected' : 'Not locked'}</dd></>}</dl>
    <p>Approval: {row.state === 'admitted' ? 'Authorised and admitted' : row.state === 'proposed' && row.review_item_id ? 'Awaiting existing Layer 4 decision' : row.approval_status ? humanLabel(row.approval_status) : 'A human decision is required for a new proposal'}. {row.required_approval && shown(row.required_approval)}</p>
    <div className="pdesc-descriptions"><section><h5>Current description</h5><p>{row.current_description || 'No current description'}</p></section><section><h5>Proposed description</h5><p>{row.proposed_description || 'No proposal yet'}</p></section></div>
    <details><summary>Official source and supporting evidence</summary>
      <dl className="pdesc-identity"><dt>Official URL</dt><dd>{row.source_url ? <a href={row.source_url} target="_blank" rel="noreferrer">{row.source_url} <ExternalLink size={12}/></a> : 'No approved stored source'}</dd><dt>Stored evidence</dt><dd>{row.evidence_id ? <a href={hrefFor('evidence', '', { evidence_id: row.evidence_id })}>{row.evidence_id}</a> : 'Not available'}</dd><dt>Captured</dt><dd>{stamp(row.source_captured_at)}{row.source_age_days != null && ` · ${Number(row.source_age_days).toFixed(1)} days old`}</dd><dt>Evidence version</dt><dd>{shown(row.content_hash || row.source_hash || row.evidence_version)}</dd><dt>Reader / model</dt><dd>{[row.worker || (row.reader_version !== row.model && row.reader_version), row.model].filter(Boolean).join(' · ') || 'Not recorded'}</dd><dt>Prompt version</dt><dd>{shown(row.prompt_version)}</dd><dt>Allowed estimated cost</dt><dd>{cost(row.estimated_cost_usd)}</dd><dt>Recorded AI cost</dt><dd>{cost(row.cost_usd)}</dd></dl>
      {row.ai_calls != null && <p>Reported AI calls: {fmtNumber(row.ai_calls)}. Reserved allowance: {cost(row.reserved_usd)}.</p>}
      {row.cost_uncertain && <p className="pdesc-message">The model-call outcome or final cost needs reconciliation. Its approved allowance remains reserved.</p>}
      {row.evidence_quote && <blockquote>{row.evidence_quote}</blockquote>}
      {sentences.length > 0 && <ol className="pdesc-claims">{sentences.map((s, i) => <li key={i}><p>{s.text || s.sentence || s.claim}</p><blockquote>{s.quote || s.evidence_quote || 'No supporting quotation recorded'}</blockquote>{s.on_page != null && <p>Quotation on stored page: {s.on_page ? 'verified' : 'not verified'}</p>}{s.source_url && <a href={s.source_url} target="_blank" rel="noreferrer">Claim source</a>}</li>)}</ol>}
      {row.checks && <pre>{shown(row.checks)}</pre>}
    </details>
    {row.review_item_id && <p><a className="cf-link" href={hrefFor('layer4', 'inbox', { provider: row.provider_id, kind: 'provider_description', ref: row.review_item_id, ...(row.review_created_at ? { review_at: row.review_created_at } : {}) })}>Open Layer 4 decision {row.review_item_id}</a></p>}
    <details><summary>Catalogue / Website / Zoho read-back</summary><dl className="pdesc-identity">{[['catalogue', 'Catalogue'], ['website', 'Website'], ['zoho', 'Zoho']].map(([key, label]) => <React.Fragment key={key}><dt>{label}</dt><dd>{shown(publication[key]?.status || publication[key] || row[`${key}_status`])}</dd></React.Fragment>)}</dl>{publication.as_at && <p>Verified: {stamp(publication.as_at)}</p>}<pre>{Object.keys(publication).length ? shown(publication) : 'Publication has not been verified for this cohort.'}</pre></details>
    <div className="pdesc-actions"><Button compact disabled={busy || !canExplain} onClick={onExplain}>{canDiagnose ? 'AI-assisted Explain Evidence' : 'Explain evidence'}</Button></div>
    {(diagnosisReason || !canDiagnose) && <p className="sd-desc">{diagnosisReason || 'AI-assisted diagnosis is unavailable under the current approved permissions. Evidence explanations use the saved validation result.'}</p>}
    {diagnosis && <div className="pdesc-message" role="status"><strong>Evidence explanation</strong><p>{diagnosis.explanation || diagnosis.reason || diagnosis.summary || shown(diagnosis)}</p>{diagnosis.required_evidence && <p>Evidence needed: {shown(diagnosis.required_evidence)}</p>}
      {diagnosis.request_id && <p>Existing Operations diagnosis request: <code>{diagnosis.request_id}</code> · {humanLabel(diagnosis.request_status)}{diagnosis.integration_issue_id ? ` · Integration issue ${diagnosis.integration_issue_id}` : ''}</p>}
      {diagnosis.ai_reason && <p>{diagnosis.ai_reason}</p>}
      {diagnosis.answer && <><strong>AI evidence explanation</strong><pre>{shown(diagnosis.answer)}</pre></>}
      {diagnosis.model && <p>Model: {diagnosis.model} · Recorded cost: {cost(diagnosis.cost_usd)}{diagnosis.answered_at && ` · Answered ${stamp(diagnosis.answered_at)}`}</p>}
      {diagnosis.request_id && !diagnosis.answer && <p>Refresh saved results to read the persisted Operations response when available.</p>}
    </div>}
  </article>
}
