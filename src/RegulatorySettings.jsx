import React, { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, Database, MapPin, Play, RefreshCw, Repeat2, RotateCcw, Search, Settings2, ShieldCheck } from 'lucide-react'
import { api } from './lib/supabase'
import './settings.css'

const RUN_LIMIT = 100
const RESULT_KEY = 'coursefinder-layer1-latest-result-v1'

export default function RegulatorySettings({ onError }) {
  const [rows, setRows] = useState([])
  const [catalogue, setCatalogue] = useState(null)
  const [q, setQ] = useState('')
  const [busy, setBusy] = useState(true)
  const [runBusy, setRunBusy] = useState(false)
  const [runResult, setRunResult] = useState(null)
  const [confirmMode, setConfirmMode] = useState(null)
  const [confirmText, setConfirmText] = useState('')

  const load = () => {
    setBusy(true)
    Promise.all([api.regulatorySources(), api.dashboard()])
      .then(([sources, dashboard]) => { setRows(sources || []); setCatalogue(dashboard || null) })
      .catch(e => onError(e.message))
      .finally(() => setBusy(false))
  }

  useEffect(() => {
    load()
    try { const saved = sessionStorage.getItem(RESULT_KEY); if (saved) setRunResult(JSON.parse(saved)) } catch {}
  }, [])

  const remember = result => {
    setRunResult(result)
    try { sessionStorage.setItem(RESULT_KEY, JSON.stringify(result)) } catch {}
  }

  const runAll = async (apply, kind = apply ? 'apply' : 'dry-run') => {
    setRunBusy(true); onError('')
    try {
      const result = await api.runLayer1({ country: 'ALL', apply, maxRecords: RUN_LIMIT })
      remember({ ...result, controlKind: kind })
      load()
      return result
    } catch (e) { onError(e.message); return null }
    finally { setRunBusy(false) }
  }

  const approve = async () => {
    const expected = confirmMode === 'reset' ? 'RESET DATABASE' : 'APPLY ALL 100'
    if (confirmText.trim().toUpperCase() !== expected) return
    const mode = confirmMode
    setConfirmMode(null); setConfirmText(''); setRunBusy(true); onError('')
    try {
      if (mode === 'reset') {
        const result = await api.resetDatabase()
        remember({ mode: 'reset', controlKind: 'reset', catalogueStats: result, workerVersion: result.version, seedStatus: result.seed_preserved || [] })
      } else {
        const result = await api.runLayer1({ country: 'ALL', apply: true, maxRecords: RUN_LIMIT })
        remember({ ...result, controlKind: 'apply' })
      }
      load()
    } catch (e) { onError(e.message) }
    finally { setRunBusy(false) }
  }

  const shown = useMemo(() => rows.filter(r => [r.country_name, r.country_code, r.source_label, r.system_name, r.source_type, ...(r.system_config?.coverage || [])].filter(Boolean).join(' ').toLowerCase().includes(q.toLowerCase())), [rows, q])
  const configuredSources = rows.filter(r => r.source_id)
  const activeCountries = new Set(configuredSources.map(r => r.country_code)).size
  const healthySources = configuredSources.filter(r => r.last_success_at && (!r.last_failure_at || new Date(r.last_success_at) >= new Date(r.last_failure_at))).length
  const countryResults = runResult?.countries || []
  const failures = runResult?.failures || []
  const stats = runResult?.catalogueStats || {}
  const isApplyResult = runResult?.mode === 'apply'

  return <div className="stack">
    <div className="section-head">
      <div><span className="kicker">Platform Admin · Layer 1</span><h2>Regulatory Sources</h2><p>Authoritative regulatory source registry and Layer 1 execution control. Supabase Edge Functions resolve sources from this configuration.</p></div>
      <div style={{display:'flex',gap:8}}><button className="secondary" onClick={load}><RefreshCw size={15} className={busy ? 'spin' : ''}/>Refresh</button><button className="secondary" onClick={()=>{setConfirmMode('reset');setConfirmText('')}} disabled={runBusy}><RotateCcw size={15}/>Reset Database</button></div>
    </div>

    <section className="panel full ingestion-control">
      <div className="panel-title control-title"><div><span className="kicker">7 countries · controlled Layer 1 UAT</span><h3>Layer 1 ingestion control</h3><p>One Edge Function invocation orchestrates Australia, Canada, Germany, United Kingdom, Ireland, New Zealand and United States. Australia uses the dedicated CRICOS depth adapter so Provider, Course, Campus and Course↔Campus relationships are reconciled together.</p></div><span className="control-badge"><ShieldCheck size={15}/>Platform Admin</span></div>
      <div className="control-steps">
        <ControlStep number="1" title="Validate all" text={`Resolve sources, run live/freshness checks, capture evidence and parse up to ${RUN_LIMIT} records per country. No catalogue writes.`} status={runResult?.mode === 'dry-run' ? 'done' : 'ready'}><button className="secondary" onClick={() => runAll(false, 'dry-run')} disabled={runBusy}><Play size={15}/>{runBusy ? 'Edge Function running…' : 'Dry-run all 7'}</button></ControlStep>
        <ControlStep number="2" title="Apply all" text={`Reconcile and persist up to ${RUN_LIMIT} records per country, including AU Campus depth, then rebuild Search Projection.`} status={isApplyResult ? 'done' : 'guarded'}><button className="danger-soft" onClick={()=>{setConfirmMode('apply');setConfirmText('')}} disabled={runBusy}><AlertTriangle size={15}/>Apply all · 100/country</button></ControlStep>
        <ControlStep number="3" title="Prove idempotency" text="Run the identical all-country scope again. Existing identities, registrations, Campuses and Course↔Campus relationships must resolve without duplicate creation." status={isApplyResult ? 'ready' : 'waiting'}><button className="secondary" onClick={() => runAll(true, 'idempotency-rerun')} disabled={runBusy || !isApplyResult}><Repeat2 size={15}/>Re-run same scope</button></ControlStep>
      </div>
      <div className="control-note"><AlertTriangle size={16}/><span><strong>Reset boundary:</strong> Reset Database removes all catalogue/business/runtime UAT data and empties private evidence storage. It preserves Auth/RBAC, reference/PIM configuration, Regulatory Sources and the server-only Layer 1 seed snapshots required to rebuild from zero.</span></div>
    </section>

    {runResult && <section className={`panel full run-result ${isApplyResult ? 'apply-result' : ''}`}>
      <div className="panel-title result-title"><div><span className="kicker">Latest Layer 1 result</span><h3>{runResult.controlKind === 'reset' ? 'Clean database reset' : runResult.controlKind === 'idempotency-rerun' ? 'All-country idempotency re-run' : isApplyResult ? 'All-country controlled apply' : 'All-country dry-run'}</h3><p>Runtime {runResult.runtime || 'supabase_edge'} · {runResult.workerVersion || '—'} · {countryResults.length} successful country runs{failures.length ? ` · ${failures.length} failed` : ''}</p></div><span className={`result-status ${isApplyResult ? 'write' : 'safe'}`}><CheckCircle2 size={15}/>{runResult.controlKind === 'reset' ? 'Clean Layer 1 baseline' : isApplyResult ? 'Catalogue + depth + search finalised' : 'No catalogue writes'}</span></div>

      {runResult.mode !== 'reset' && <div className="country-result-grid">{countryResults.map(r => <div className="country-result" key={r.country}><div><strong>{r.country}</strong><span>{String(r.adapter || 'adapter').replaceAll('_',' ')}</span></div><div className="country-numbers"><span>Parsed <b>{num(r.parsedRecords)}</b></span><span>Selected <b>{num(r.selectedRecords)}</b></span><span>Providers +<b>{num(r.reconciliation?.provider_created)}</b></span><span>Courses +<b>{num(r.reconciliation?.course_created)}</b></span>{r.country === 'AU' && <><span>Campuses +<b>{num(r.depthReconciliation?.campuses_created)}</b></span><span>Course↔Campus +<b>{num(r.depthReconciliation?.course_links_created)}</b></span></>}<span>Conflicts <b>{num((r.reconciliation?.conflicts || 0) + (r.depthReconciliation?.conflicts || 0))}</b></span></div></div>)}</div>}
      {failures.length > 0 && <div className="control-note"><AlertTriangle size={16}/><span><strong>Country failures:</strong> {failures.map(x => `${x.country}: ${x.error}`).join(' · ')}</span></div>}

      {(runResult.mode === 'reset' || isApplyResult) && <><div className="panel-title" style={{marginTop:18}}><div><span className="kicker">Retained catalogue statistics</span><h3>Canonical + Data Depth + Search Projection</h3></div></div><div className="metric-grid control-metrics"><Metric icon={Database} label="Providers" value={num(stats.providers)}/><Metric icon={Database} label="Courses" value={num(stats.courses)}/><Metric icon={MapPin} label="Campuses" value={num(stats.campuses)}/><Metric icon={MapPin} label="Course↔Campus" value={num(stats.course_campus_links)}/><Metric icon={Database} label="Search documents" value={num(stats.search_documents)}/><Metric icon={RefreshCw} label="Search generation" value={num(stats.search_generation)}/>{runResult.mode === 'reset' && <><Metric icon={Database} label="Pipeline jobs" value={num(stats.pipeline_jobs)}/><Metric icon={Database} label="Evidence metadata" value={num(stats.evidence_metadata)}/><Metric icon={Database} label="Review queue" value={num(stats.review_queue)}/></>}</div></>}
      {runResult.controlKind === 'idempotency-rerun' && <div className="idempotency-hint"><ShieldCheck size={16}/><span>Idempotency passes when repeated country runs report zero new duplicate identities or AU depth relationships and retained Provider/Course/Campus/Course↔Campus/Search totals remain stable.</span></div>}
    </section>}

    <div className="metric-grid compact-grid"><Metric icon={Database} label="Configured regulatory sources" value={configuredSources.length}/><Metric icon={Settings2} label="Countries with sources" value={activeCountries}/><Metric icon={RefreshCw} label="Healthy sources" value={`${healthySources}/${configuredSources.length || 0}`}/><Metric icon={Database} label="Catalogue providers" value={num(catalogue?.providers)}/><Metric icon={Database} label="Catalogue courses" value={num(catalogue?.courses)}/><Metric icon={MapPin} label="Campuses" value={num(catalogue?.campuses)}/><Metric icon={MapPin} label="Course↔Campus" value={num(catalogue?.course_campus_links)}/><Metric icon={Search} label="Search documents" value={num(catalogue?.search_documents)}/></div>

    <section className="panel full"><div className="panel-title table-title"><div><span className="kicker">Country → source → acquisition</span><h3>Layer 1 source control</h3><p>Multiple regulatory/official sources are supported where one authority does not cover the complete provider/course identity and registration domain.</p></div><div className="searchbox"><Search size={16}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search country or source…"/></div></div><div className="table-wrap"><table><thead><tr><th>Country</th><th>Source</th><th>Method</th><th>Coverage</th><th>Auth</th><th>Trust</th><th>Status</th><th>Last success</th></tr></thead><tbody>{shown.length ? shown.map((r,i)=><tr key={r.source_id || `${r.country_code}-${i}`}><td><div className="cell-title"><strong>{r.country_name}</strong><span>{r.country_code} · {r.catalogue_status}</span></div></td><td>{r.source_id ? <div className="cell-title"><strong>{r.source_label}</strong><a href={r.source_url || r.system_base_url} target="_blank" rel="noreferrer">{r.system_name || r.source_url}</a></div> : <span className="source-missing">Not configured</span>}</td><td>{r.system_config?.acquisition_method || r.source_type || '—'}</td><td><div className="coverage-list">{(r.system_config?.coverage || []).map(x=><span key={x}>{String(x).replaceAll('_',' ')}</span>)}</div></td><td>{r.system_config?.auth || 'none'}</td><td>{r.trust_rank ?? '—'}</td><td><span className={`badge badge-${String(r.source_status || 'missing').replace(/[^a-z0-9]+/gi,'-').toLowerCase()}`}>{r.source_status || 'missing'}</span></td><td>{fmt(r.last_success_at)}</td></tr>) : <tr><td colSpan="8"><div className="table-empty">No regulatory source records returned.</div></td></tr>}</tbody></table></div></section>

    <section className="panel settings-note"><div><strong>Live adapters</strong><span>Australia uses the consolidated CRICOS Providers/Courses/Locations ZIP and reconciles Campuses plus Course Locations; United Kingdom validates the UKVI student sponsor register; Germany uses the DAAD programmes API.</span></div><div><strong>Seed-backed adapters</strong><span>Canada, Ireland, New Zealand and United States use the preserved core Layer 1 snapshot plus a live source freshness check until a reliable structured course feed is configured.</span></div><div><strong>Reset</strong><span>Reset Database returns catalogue/runtime data to zero while retaining only the configuration and Layer 1 seed needed to rebuild.</span></div></section>

    {confirmMode && <div className="confirm-backdrop" role="presentation" onMouseDown={() => setConfirmMode(null)}><div className="confirm-card" role="dialog" aria-modal="true" onMouseDown={e => e.stopPropagation()}><div className="confirm-icon"><AlertTriangle size={22}/></div><span className="kicker">{confirmMode === 'reset' ? 'Destructive database reset' : 'Controlled all-country write'}</span><h3>{confirmMode === 'reset' ? 'Reset Pilot to the clean Layer 1 execution seed?' : `Apply up to ${RUN_LIMIT} Layer 1 records per country?`}</h3><p>{confirmMode === 'reset' ? 'This removes Providers, Courses, Campuses, Course↔Campus relationships, Scholarships, Search Documents, Pipeline Jobs, Evidence, Reviews and import/export runtime records, and empties the evidence bucket. Auth/RBAC, reference/PIM configuration, Regulatory Sources and Layer 1 seed snapshots are preserved.' : 'This may create or link Providers, Courses, registration identities and authoritative AU Campus relationships across the configured countries. Search Projection and catalogue statistics are rebuilt after the country runs.'}</p><label>Type <strong>{confirmMode === 'reset' ? 'RESET DATABASE' : 'APPLY ALL 100'}</strong> to confirm</label><input autoFocus value={confirmText} onChange={e=>setConfirmText(e.target.value)} placeholder={confirmMode === 'reset' ? 'RESET DATABASE' : 'APPLY ALL 100'}/><div className="confirm-actions"><button className="secondary" onClick={() => setConfirmMode(null)}>Cancel</button><button className="danger-soft" disabled={confirmText.trim().toUpperCase() !== (confirmMode === 'reset' ? 'RESET DATABASE' : 'APPLY ALL 100')} onClick={approve}><AlertTriangle size={15}/>{confirmMode === 'reset' ? 'Reset Database' : 'Apply all countries'}</button></div></div></div>}
  </div>
}

function ControlStep({ number, title, text, status, children }) { return <div className={`control-step step-${status}`}><div className="step-number">{status === 'done' ? <CheckCircle2 size={18}/> : number}</div><div className="step-copy"><strong>{title}</strong><span>{text}</span></div><div className="step-action">{children}</div></div> }
function Metric({ icon: Icon, label, value }) { return <div className="metric-card mini"><div className="metric-icon"><Icon size={17}/></div><span>{label}</span><strong>{value}</strong></div> }
function fmt(v) { return v ? new Date(v).toLocaleString() : 'Not checked yet' }
function num(v) { return Number(v ?? 0).toLocaleString() }
