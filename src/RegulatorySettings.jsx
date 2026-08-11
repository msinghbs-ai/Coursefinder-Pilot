import React, { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, Database, Play, RefreshCw, Repeat2, RotateCcw, Search, Settings2, ShieldCheck } from 'lucide-react'
import { api } from './lib/supabase'
import './settings.css'

const AU_LIMIT = 100

export default function RegulatorySettings({ onError }) {
  const [rows, setRows] = useState([])
  const [q, setQ] = useState('')
  const [busy, setBusy] = useState(true)
  const [runBusy, setRunBusy] = useState(false)
  const [runResult, setRunResult] = useState(null)
  const [confirmMode, setConfirmMode] = useState(null)
  const [confirmText, setConfirmText] = useState('')

  const load = () => {
    setBusy(true)
    api.regulatorySources().then(setRows).catch(e => onError(e.message)).finally(() => setBusy(false))
  }

  useEffect(() => {
    load()
    api.latestLayer1Job('AU').then(job => {
      if (job?.status === 'completed' && job.result) setRunResult({ ...job.result, jobId: job.jobId, controlKind: inferKind(job) })
    }).catch(e => onError(e.message))
  }, [])

  const runAu = async (apply, kind = apply ? 'apply' : 'dry-run') => {
    setRunBusy(true); setRunResult(null); onError('')
    try {
      const result = await api.runLayer1({ country: 'AU', apply, maxRecords: AU_LIMIT })
      setRunResult({ ...result, controlKind: kind })
      load()
      return result
    } catch (e) { onError(e.message); return null }
    finally { setRunBusy(false) }
  }

  const approve = async () => {
    const expected = confirmMode === 'reset' ? 'RESET AU UAT' : 'APPLY 100'
    if (confirmText.trim().toUpperCase() !== expected) return
    const mode = confirmMode
    setConfirmMode(null); setConfirmText(''); setRunBusy(true); onError('')
    try {
      if (mode === 'reset') {
        const result = await api.resetAuUat()
        setRunResult({ mode: 'reset', controlKind: 'reset', catalogueStats: result, workerVersion: result.version })
      } else {
        const result = await api.runLayer1({ country: 'AU', apply: true, maxRecords: AU_LIMIT })
        setRunResult({ ...result, controlKind: 'apply' })
      }
      load()
    } catch (e) { onError(e.message) }
    finally { setRunBusy(false) }
  }

  const shown = useMemo(() => rows.filter(r => [r.country_name, r.country_code, r.source_label, r.system_name, r.source_type, ...(r.system_config?.coverage || [])].filter(Boolean).join(' ').toLowerCase().includes(q.toLowerCase())), [rows, q])
  const countries = new Set(rows.map(r => r.country_code)).size
  const configured = new Set(rows.filter(r => r.source_id).map(r => r.country_code)).size
  const sources = rows.filter(r => r.source_id).length
  const healthy = rows.filter(r => r.last_success_at && (!r.last_failure_at || new Date(r.last_success_at) >= new Date(r.last_failure_at))).length
  const reconciliation = runResult?.reconciliation || {}
  const stats = runResult?.catalogueStats || {}
  const isApplyResult = runResult?.mode === 'apply'

  return <div className="stack">
    <div className="section-head">
      <div><span className="kicker">Platform Admin · Layer 1</span><h2>Regulatory Sources</h2><p>Authoritative country source registry used by Supabase Edge Functions. Source endpoints are configuration, not frontend code.</p></div>
      <div style={{display:'flex',gap:8}}><button className="secondary" onClick={load}><RefreshCw size={15} className={busy ? 'spin' : ''}/>Refresh</button><button className="secondary" onClick={()=>{setConfirmMode('reset');setConfirmText('')}} disabled={runBusy}><RotateCcw size={15}/>Reset AU UAT</button></div>
    </div>

    <section className="panel full ingestion-control">
      <div className="panel-title control-title"><div><span className="kicker">Australia · CRICOS · controlled UAT</span><h3>Layer 1 ingestion control</h3><p>CRICOS runs execute as one Supabase Edge Function invocation against the v2.9.1 service contract.</p></div><span className="control-badge"><ShieldCheck size={15}/>Platform Admin</span></div>
      <div className="control-steps">
        <ControlStep number="1" title="Validate" text="Fetch, hash, store evidence and parse 100 records. No catalogue writes." status={runResult?.mode === 'dry-run' ? 'done' : 'ready'}><button className="secondary" onClick={() => runAu(false, 'dry-run')} disabled={runBusy}><Play size={15}/>{runBusy ? 'Edge Function running…' : 'Run dry-run (100)'}</button></ControlStep>
        <ControlStep number="2" title="Apply" text="Reconcile CRICOS identities, persist 100 records, then rebuild Search Projection and catalogue statistics." status={isApplyResult ? 'done' : 'guarded'}><button className="danger-soft" onClick={()=>{setConfirmMode('apply');setConfirmText('')}} disabled={runBusy}><AlertTriangle size={15}/>Apply first 100</button></ControlStep>
        <ControlStep number="3" title="Prove idempotency" text="Run the same 100 again. Existing identities should resolve without duplicate creation." status={isApplyResult ? 'ready' : 'waiting'}><button className="secondary" onClick={() => runAu(true, 'idempotency-rerun')} disabled={runBusy || !isApplyResult}><Repeat2 size={15}/>Re-run same 100</button></ControlStep>
      </div>
      <div className="control-note"><AlertTriangle size={16}/><span><strong>Controlled write boundary:</strong> fixed to Australia and {AU_LIMIT} records. Reset returns business/runtime data to a clean Layer 1 execution baseline: 0 Providers, 0 Courses, 0 Search Documents, 0 Jobs, 0 Reviews and 0 Evidence, while preserving Auth/RBAC, reference seed, PIM families and Regulatory Source configuration.</span></div>
    </section>

    {runResult && <section className={`panel full run-result ${isApplyResult ? 'apply-result' : ''}`}>
      <div className="panel-title result-title"><div><span className="kicker">Latest Layer 1 result</span><h3>Australia · CRICOS · {runResult.controlKind === 'reset' ? 'UAT reset' : runResult.controlKind === 'idempotency-rerun' ? 'Idempotency re-run' : isApplyResult ? 'Controlled apply' : 'Dry-run'}</h3><p>Job {runResult.jobId || '—'} · Runtime {runResult.runtime || 'supabase_edge'} · {runResult.workerVersion || '—'}</p></div><span className={`result-status ${isApplyResult ? 'write' : 'safe'}`}><CheckCircle2 size={15}/>{runResult.controlKind === 'reset' ? 'Clean Layer 1 baseline restored' : isApplyResult ? 'Catalogue + search updated' : 'No catalogue writes'}</span></div>
      {runResult.mode !== 'reset' && <div className="metric-grid control-metrics"><Metric icon={Database} label="Parsed" value={num(runResult.parsedRecords)}/><Metric icon={Database} label="Selected" value={num(runResult.selectedRecords)}/><Metric icon={Database} label="Providers created" value={num(reconciliation.provider_created)}/><Metric icon={Database} label="Providers linked" value={num(reconciliation.provider_linked)}/><Metric icon={Database} label="Courses created" value={num(reconciliation.course_created)}/><Metric icon={Database} label="Courses linked" value={num(reconciliation.course_linked)}/><Metric icon={AlertTriangle} label="Conflicts" value={num(reconciliation.conflicts)}/><Metric icon={ShieldCheck} label="Evidence files" value={runResult.evidenceIds?.length ?? 0}/></div>}
      {(runResult.mode === 'reset' || isApplyResult) && <><div className="panel-title" style={{marginTop:18}}><div><span className="kicker">Retained catalogue statistics</span><h3>Canonical + Search Projection</h3></div></div><div className="metric-grid control-metrics"><Metric icon={Database} label="Providers" value={num(stats.providers)}/><Metric icon={Database} label="Courses" value={num(stats.courses)}/><Metric icon={Database} label="CRICOS course regs" value={num(stats.cricos_course_registrations)}/><Metric icon={Database} label="Search documents" value={num(stats.search_documents)}/><Metric icon={RefreshCw} label="Search generation" value={num(stats.search_generation)}/>{runResult.mode === 'reset' && <><Metric icon={Database} label="Pipeline jobs" value={num(stats.pipeline_jobs)}/><Metric icon={Database} label="Evidence metadata" value={num(stats.evidence_metadata)}/><Metric icon={Database} label="Review queue" value={num(stats.review_queue)}/></>}</div></>}
      {runResult.controlKind === 'idempotency-rerun' && <div className="idempotency-hint"><ShieldCheck size={16}/><span>Idempotency passes when the repeated batch creates no duplicate regulator identities or registrations and the retained statistics remain stable.</span></div>}
    </section>}

    <div className="metric-grid compact-grid"><Metric icon={Settings2} label="Pilot countries" value={countries}/><Metric icon={Database} label="Configured countries" value={`${configured}/${countries}`}/><Metric icon={Database} label="Authoritative sources" value={sources}/><Metric icon={RefreshCw} label="Successful health checks" value={healthy}/></div>

    <section className="panel full"><div className="panel-title table-title"><div><span className="kicker">Country → source → acquisition</span><h3>Layer 1 source control</h3><p>Multiple sources are supported where one regulator does not cover the complete provider/course domain.</p></div><div className="searchbox"><Search size={16}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search country or source…"/></div></div><div className="table-wrap"><table><thead><tr><th>Country</th><th>Source</th><th>Method</th><th>Coverage</th><th>Auth</th><th>Trust</th><th>Status</th><th>Last success</th></tr></thead><tbody>{shown.length ? shown.map((r,i)=><tr key={r.source_id || `${r.country_code}-${i}`}><td><div className="cell-title"><strong>{r.country_name}</strong><span>{r.country_code} · {r.catalogue_status}</span></div></td><td>{r.source_id ? <div className="cell-title"><strong>{r.source_label}</strong><a href={r.source_url || r.system_base_url} target="_blank" rel="noreferrer">{r.system_name || r.source_url}</a></div> : <span className="source-missing">Not configured</span>}</td><td>{r.system_config?.acquisition_method || r.source_type || '—'}</td><td><div className="coverage-list">{(r.system_config?.coverage || []).map(x=><span key={x}>{String(x).replaceAll('_',' ')}</span>)}</div></td><td>{r.system_config?.auth || 'none'}</td><td>{r.trust_rank ?? '—'}</td><td><span className={`badge badge-${String(r.source_status || 'missing').replace(/[^a-z0-9]+/gi,'-').toLowerCase()}`}>{r.source_status || 'missing'}</span></td><td>{fmt(r.last_success_at)}</td></tr>) : <tr><td colSpan="8"><div className="table-empty">No regulatory source records returned.</div></td></tr>}</tbody></table></div></section>

    <section className="panel settings-note"><div><strong>Execution runtime</strong><span>Layer 1 acquisition and reconciliation run in Supabase Edge Functions; Cloudflare only serves the Pilot application.</span></div><div><strong>Statistics finalisation</strong><span>Every Apply rebuilds Search Projection and returns canonical Provider/Course/CRICOS/Search totals.</span></div><div><strong>Reset boundary</strong><span>Reset removes catalogue, scholarship, search runtime, jobs, evidence, review/import/export and entity-bound PIM data. It preserves only platform configuration/reference seed required to authenticate and execute Layer 1.</span></div></section>

    {confirmMode && <div className="confirm-backdrop" role="presentation" onMouseDown={() => setConfirmMode(null)}><div className="confirm-card" role="dialog" aria-modal="true" onMouseDown={e => e.stopPropagation()}><div className="confirm-icon"><AlertTriangle size={22}/></div><span className="kicker">{confirmMode === 'reset' ? 'Destructive UAT reset' : 'Controlled catalogue write'}</span><h3>{confirmMode === 'reset' ? 'Reset to the clean Layer 1 execution seed?' : `Apply the first ${AU_LIMIT} CRICOS records?`}</h3><p>{confirmMode === 'reset' ? 'This removes all business/runtime UAT data, including Providers, Courses, Scholarships, Search Documents, Pipeline Jobs, Evidence, Reviews and import/export runtime records. It preserves Auth/RBAC, reference seed, PIM family definitions, Regulatory Source configuration and the private evidence bucket definition so Layer 1 can run again from zero.' : 'This may create or link Providers, Courses and CRICOS registrations. Search Projection and catalogue statistics are rebuilt after the write.'}</p><label>Type <strong>{confirmMode === 'reset' ? 'RESET AU UAT' : 'APPLY 100'}</strong> to confirm</label><input autoFocus value={confirmText} onChange={e=>setConfirmText(e.target.value)} placeholder={confirmMode === 'reset' ? 'RESET AU UAT' : 'APPLY 100'}/><div className="confirm-actions"><button className="secondary" onClick={() => setConfirmMode(null)}>Cancel</button><button className="danger-soft" disabled={confirmText.trim().toUpperCase() !== (confirmMode === 'reset' ? 'RESET AU UAT' : 'APPLY 100')} onClick={approve}><AlertTriangle size={15}/>{confirmMode === 'reset' ? 'Reset to clean seed' : 'Apply 100 records'}</button></div></div></div>}
  </div>
}

function inferKind(job) { return job?.payload?.apply ? 'apply' : 'dry-run' }
function ControlStep({ number, title, text, status, children }) { return <div className={`control-step step-${status}`}><div className="step-number">{status === 'done' ? <CheckCircle2 size={18}/> : number}</div><div className="step-copy"><strong>{title}</strong><span>{text}</span></div><div className="step-action">{children}</div></div> }
function Metric({ icon: Icon, label, value }) { return <div className="metric-card mini"><div className="metric-icon"><Icon size={17}/></div><span>{label}</span><strong>{value}</strong></div> }
function fmt(v) { return v ? new Date(v).toLocaleString() : 'Not checked yet' }
function num(v) { return Number(v ?? 0).toLocaleString() }
