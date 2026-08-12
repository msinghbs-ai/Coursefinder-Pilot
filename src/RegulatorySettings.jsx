import React, { useEffect, useMemo, useState } from 'react'
import {
  AlertTriangle, CheckCircle2, Database, MapPin, Play, RefreshCw,
  Repeat2, RotateCcw, Search, Settings2, ShieldCheck, StepForward
} from 'lucide-react'
import { api } from './lib/supabase'
import './settings.css'

const DEFAULT_BATCH = 2500
const RESULT_KEY = 'coursefinder-layer1-country-result-v2'
const STATCAN_RESULT_KEY = 'coursefinder-layer2a-statcan-ca-result-v1'

const COUNTRY_POLICY = {
  AU: {
    label: 'Australia',
    adapter: 'CRICOS consolidated ZIP',
    logic: 'Institutions → Courses → Locations → Course Locations',
    identity: 'CRICOS Provider Code + CRICOS Course Code',
    recommendedBatch: 2500,
    maxBatch: 5000,
    note: 'Full authoritative depth. Each bounded course slice also reconciles the matching provider campuses and course↔campus relationships.',
  },
  GB: {
    label: 'United Kingdom',
    adapter: 'UKVI + configured course seed',
    logic: 'UKVI provider register → configured course source',
    identity: 'Sponsor identity + configured course registration code',
    recommendedBatch: 1000,
    maxBatch: 2500,
    note: 'UKVI provider verification and the configured Layer 1 course source are processed through the country adapter.',
  },
  DE: {
    label: 'Germany',
    adapter: 'DAAD paged programmes API',
    logic: 'DAAD live pages → bounded programme slice',
    identity: 'DAAD programme ID + provider identity',
    recommendedBatch: 100,
    maxBatch: 250,
    note: 'The Germany adapter pages the live DAAD source and advances by deterministic record offset. Smaller batches limit upstream page fetches per execution.',
  },
  CA: {
    label: 'Canada',
    adapter: 'IRCC DLI live register',
    logic: 'IRCC DLI provider authority → federated Course sources',
    identity: 'IRCC DLI number + source-scoped stable programme identifier',
    recommendedBatch: 1000,
    maxBatch: 2500,
    note: 'Provider identity is live IRCC DLI. Course identity is source-scoped and never title-based; national Course-source coverage remains gated.',
  },
  IE: {
    label: 'Ireland',
    adapter: 'Configured Layer 1 seed + live freshness',
    logic: 'Country seed snapshot → source health check',
    identity: 'Configured regulatory/provider identifiers',
    recommendedBatch: 1000,
    maxBatch: 2500,
    note: 'Uses the preserved country seed contract until a production structured programme feed replaces it.',
  },
  NZ: {
    label: 'New Zealand',
    adapter: 'Configured Layer 1 seed + live freshness',
    logic: 'Country seed snapshot → source health check',
    identity: 'Configured regulatory/provider identifiers',
    recommendedBatch: 1000,
    maxBatch: 2500,
    note: 'Uses the preserved country seed contract until a production structured programme feed replaces it.',
  },
  US: {
    label: 'United States',
    adapter: 'Configured Layer 1 seed + live freshness',
    logic: 'Country seed snapshot → source health check',
    identity: 'Configured regulatory/provider identifiers',
    recommendedBatch: 1000,
    maxBatch: 2500,
    note: 'Uses the preserved country seed contract until a production structured programme feed replaces it.',
  },
}

export default function RegulatorySettings({ onError }) {
  const [rows, setRows] = useState([])
  const [catalogue, setCatalogue] = useState(null)
  const [q, setQ] = useState('')
  const [busy, setBusy] = useState(true)
  const [runBusy, setRunBusy] = useState(false)
  const [statsCanBusy, setStatsCanBusy] = useState(false)
  const [country, setCountry] = useState('AU')
  const [batchSize, setBatchSize] = useState(DEFAULT_BATCH)
  const [offset, setOffset] = useState(0)
  const [runResult, setRunResult] = useState(null)
  const [statsCanResult, setStatsCanResult] = useState(null)
  const [latestJob, setLatestJob] = useState(null)
  const [confirmMode, setConfirmMode] = useState(null)
  const [confirmText, setConfirmText] = useState('')
  const [pendingOffset, setPendingOffset] = useState(0)

  const load = () => {
    setBusy(true)
    Promise.all([api.regulatorySources(), api.dashboard()])
      .then(([sources, dashboard]) => {
        setRows(sources || [])
        setCatalogue(dashboard || null)
      })
      .catch(e => onError(e.message))
      .finally(() => setBusy(false))
  }

  const loadLatest = selectedCountry => {
    api.latestLayer1Job(selectedCountry)
      .then(job => {
        setLatestJob(job || null)
        const resume = Number(job?.result?.nextOffset)
        if (job?.status === 'completed' && Number.isFinite(resume) && resume >= 0) setOffset(resume)
      })
      .catch(() => setLatestJob(null))
  }

  useEffect(() => {
    load()
    try {
      const saved = sessionStorage.getItem(RESULT_KEY)
      if (saved) {
        const parsed = JSON.parse(saved)
        setRunResult(parsed)
        if (parsed.requestedCountry) setCountry(parsed.requestedCountry)
        if (Number.isFinite(Number(parsed.batchSize))) setBatchSize(Number(parsed.batchSize))
        if (Number.isFinite(Number(parsed.nextOffset))) setOffset(Number(parsed.nextOffset))
      }
      const savedStatsCan = sessionStorage.getItem(STATCAN_RESULT_KEY)
      if (savedStatsCan) setStatsCanResult(JSON.parse(savedStatsCan))
    } catch {}
  }, [])

  useEffect(() => {
    const policy = COUNTRY_POLICY[country]
    if (policy) setBatchSize(policy.recommendedBatch)
    setOffset(0)
    setRunResult(null)
    loadLatest(country)
  }, [country])

  const remember = result => {
    setRunResult(result)
    try { sessionStorage.setItem(RESULT_KEY, JSON.stringify(result)) } catch {}
  }

  const rememberStatsCan = result => {
    setStatsCanResult(result)
    try { sessionStorage.setItem(STATCAN_RESULT_KEY, JSON.stringify(result)) } catch {}
  }

  const configuredCountries = useMemo(() => {
    const codes = [...new Set(rows.filter(r => r.source_id).map(r => r.country_code).filter(Boolean))]
    return codes.filter(code => COUNTRY_POLICY[code]).sort((a, b) => COUNTRY_POLICY[a].label.localeCompare(COUNTRY_POLICY[b].label))
  }, [rows])

  const selectedSources = useMemo(() => rows.filter(r => r.country_code === country), [rows, country])
  const policy = COUNTRY_POLICY[country] || COUNTRY_POLICY.AU
  const healthy = selectedSources.filter(r => r.source_id && r.last_success_at && (!r.last_failure_at || new Date(r.last_success_at) >= new Date(r.last_failure_at))).length
  const topResult = runResult?.countries?.[0] || runResult || {}
  const currentOffset = Number(topResult.offset ?? runResult?.offset ?? offset ?? 0)
  const currentBatch = Number(topResult.batchSize ?? runResult?.batchSize ?? batchSize ?? 0)
  const selectedRecords = Number(topResult.selectedRecords ?? 0)
  const totalRecords = Number(topResult.totalRecords ?? topResult.parsedRecords ?? runResult?.totalRecords ?? 0)
  const nextOffset = Number(topResult.nextOffset ?? runResult?.nextOffset ?? currentOffset + selectedRecords)
  const hasMore = Boolean(topResult.hasMore ?? runResult?.hasMore)
  const progressPct = totalRecords > 0 ? Math.min(100, Math.round((Math.min(nextOffset, totalRecords) / totalRecords) * 100)) : 0
  const stats = runResult?.catalogueStats || topResult?.catalogueStats || {}
  const rec = topResult?.reconciliation || {}
  const depth = topResult?.depthReconciliation || {}
  const statcanDiag = statsCanResult?.diagnostics || {}

  const shown = useMemo(() => rows.filter(r => [
    r.country_name, r.country_code, r.source_label, r.system_name, r.source_type,
    ...(r.system_config?.coverage || []),
  ].filter(Boolean).join(' ').toLowerCase().includes(q.toLowerCase())), [rows, q])

  async function execute({ apply, targetOffset, kind }) {
    setRunBusy(true)
    onError('')
    try {
      const result = await api.runLayer1({ country, apply, batchSize: Number(batchSize), offset: Number(targetOffset) })
      remember({ ...result, controlKind: kind })
      setOffset(Number(result?.nextOffset ?? targetOffset))
      loadLatest(country)
      load()
      return result
    } catch (e) {
      onError(e.message)
      return null
    } finally {
      setRunBusy(false)
    }
  }

  async function executeStatsCanDryRun() {
    setStatsCanBusy(true)
    onError('')
    try {
      const result = await api.runLayer2AStatsCan({ apply: false, sampleRows: 1000 })
      rememberStatsCan(result)
      load()
      return result
    } catch (e) {
      onError(e.message)
      return null
    } finally {
      setStatsCanBusy(false)
    }
  }

  function requestApply(targetOffset, kind = 'apply-batch') {
    setPendingOffset(Number(targetOffset))
    setConfirmMode(kind)
    setConfirmText('')
  }

  async function approve() {
    if (confirmMode === 'reset') {
      if (confirmText.trim().toUpperCase() !== 'RESET DATABASE') return
      setConfirmMode(null)
      setConfirmText('')
      setRunBusy(true)
      onError('')
      try {
        const result = await api.resetDatabase()
        remember({ mode: 'reset', controlKind: 'reset', catalogueStats: result, requestedCountry: country, workerVersion: result.version })
        setOffset(0)
        loadLatest(country)
        load()
      } catch (e) { onError(e.message) }
      finally { setRunBusy(false) }
      return
    }

    const expected = `APPLY ${country}`
    if (confirmText.trim().toUpperCase() !== expected) return
    const mode = confirmMode
    const target = pendingOffset
    setConfirmMode(null)
    setConfirmText('')
    await execute({ apply: true, targetOffset: target, kind: mode })
  }

  const batchValue = Math.max(1, Math.min(Number(batchSize || policy.recommendedBatch), policy.maxBatch))

  return <div className="stack">
    <div className="section-head">
      <div>
        <span className="kicker">Platform Admin · Production Layer 1</span>
        <h2>Regulatory ingestion</h2>
        <p>Country-specific Layer 1 execution with bounded batches, deterministic offsets, evidence capture and canonical reconciliation.</p>
      </div>
      <div style={{display:'flex',gap:8}}><button className="secondary" onClick={load}><RefreshCw size={15} className={busy ? 'spin' : ''}/>Refresh</button></div>
    </div>

    <section className="panel full ingestion-control">
      <div className="panel-title control-title">
        <div><span className="kicker">Country runner</span><h3>Layer 1 bounded ingestion</h3><p>Select one country. The Edge Function routes the request to that country's programmed adapter and returns the next bounded offset.</p></div>
        <span className="control-badge"><ShieldCheck size={15}/>Platform Admin</span>
      </div>

      <div className="grid-two" style={{alignItems:'stretch'}}>
        <div className="panel" style={{margin:0}}>
          <div className="panel-title"><div><span className="kicker">Execution scope</span><h3>{policy.label}</h3></div></div>
          <div className="fact-list">
            <label className="fact-row"><span>Country</span><select value={country} onChange={e=>setCountry(e.target.value)} disabled={runBusy || statsCanBusy} style={{minWidth:220}}>{configuredCountries.length ? configuredCountries.map(code=><option key={code} value={code}>{COUNTRY_POLICY[code]?.label || code} · {code}</option>) : Object.keys(COUNTRY_POLICY).map(code=><option key={code} value={code}>{COUNTRY_POLICY[code].label} · {code}</option>)}</select></label>
            <Fact label="Adapter" value={policy.adapter}/>
            <Fact label="Logic" value={policy.logic}/>
            <Fact label="Identity" value={policy.identity}/>
            <Fact label="Configured sources" value={selectedSources.filter(r=>r.source_id).length}/>
            <Fact label="Source health" value={`${healthy}/${selectedSources.filter(r=>r.source_id).length || 0} healthy`}/>
          </div>
        </div>

        <div className="panel" style={{margin:0}}>
          <div className="panel-title"><div><span className="kicker">Bounded policy</span><h3>Batch control</h3></div></div>
          <div className="fact-list">
            <label className="fact-row"><span>Batch size</span><input type="number" min="1" max={policy.maxBatch} step="100" value={batchSize} onChange={e=>setBatchSize(Math.max(1, Math.min(Number(e.target.value || 1), policy.maxBatch)))} disabled={runBusy} style={{width:130}}/></label>
            <label className="fact-row"><span>Offset</span><input type="number" min="0" step={Math.max(1,batchValue)} value={offset} onChange={e=>setOffset(Math.max(0, Number(e.target.value || 0)))} disabled={runBusy} style={{width:130}}/></label>
            <Fact label="Recommended" value={`${policy.recommendedBatch.toLocaleString()} records`}/>
            <Fact label="Hard maximum" value={`${policy.maxBatch.toLocaleString()} records`}/>
            <Fact label="Latest job" value={latestJob?.status ? `${latestJob.status}${latestJob.jobId ? ` · ${String(latestJob.jobId).slice(0,8)}…` : ''}` : 'No job loaded'}/>
          </div>
          <div className="control-note" style={{marginTop:14}}><ShieldCheck size={16}/><span>{policy.note}</span></div>
        </div>
      </div>

      <div className="control-steps" style={{marginTop:18}}>
        <ControlStep number="1" title="Validate batch" text={`Fetch and parse ${policy.label} using ${policy.adapter}. Offset ${Number(offset).toLocaleString()}, up to ${batchValue.toLocaleString()} records. No catalogue writes.`} status={runResult?.controlKind === 'dry-run' ? 'done' : 'ready'}><button className="secondary" onClick={()=>execute({apply:false,targetOffset:offset,kind:'dry-run'})} disabled={runBusy || statsCanBusy}><Play size={15}/>{runBusy ? 'Running…' : 'Validate batch'}</button></ControlStep>
        <ControlStep number="2" title="Apply bounded batch" text="Write only this bounded slice through the country adapter, then rebuild Search Projection and return the next offset." status={runResult?.mode === 'apply' ? 'done' : 'guarded'}><button className="danger-soft" onClick={()=>requestApply(offset,'apply-batch')} disabled={runBusy || statsCanBusy}><AlertTriangle size={15}/>Apply {country} batch</button></ControlStep>
        <ControlStep number="3" title="Continue" text="Advance to the exact next offset returned by the adapter. This keeps production ingestion deterministic and restartable." status={hasMore ? 'ready' : runResult ? 'done' : 'waiting'}><button className="secondary" onClick={()=>requestApply(nextOffset,'next-batch')} disabled={runBusy || statsCanBusy || !hasMore}><StepForward size={15}/>Run next batch</button></ControlStep>
        <ControlStep number="4" title="Idempotency check" text="Re-run the same bounded offset. Expected result: zero duplicate identities or depth relationships." status={runResult?.mode === 'apply' ? 'ready' : 'waiting'}><button className="secondary" onClick={()=>requestApply(currentOffset,'idempotency-rerun')} disabled={runBusy || statsCanBusy || runResult?.mode !== 'apply'}><Repeat2 size={15}/>Re-run current batch</button></ControlStep>
      </div>
    </section>

    {country === 'CA' && <section className="panel full ingestion-control">
      <div className="panel-title control-title">
        <div><span className="kicker">Canada · Layer 2A runtime gate</span><h3>Statistics Canada PSIS parser dry run</h3><p>Calls the dedicated authenticated <strong>statcan-ca-psis-etl</strong> worker. This is separate from the IRCC Layer 1 runner and performs no canonical writes.</p></div>
        <span className="control-badge"><ShieldCheck size={15}/>Dry-run only</span>
      </div>
      <div className="control-steps">
        <ControlStep number="A" title="Run StatsCan PSIS dry run" text="Download the current PSIS full-table CSV ZIP, capture private evidence, parse a 1,000-row sample and return institution/field/credential diagnostics. APPLY remains disabled in the worker." status={statsCanResult?.status === 'parser-dry-run-pass' ? 'done' : 'ready'}><button className="secondary" onClick={executeStatsCanDryRun} disabled={runBusy || statsCanBusy}><Play size={15}/>{statsCanBusy ? 'Running StatsCan…' : 'Run StatsCan PSIS Dry Run'}</button></ControlStep>
      </div>
      {statsCanResult && <div style={{marginTop:18}}>
        <div className="metric-grid control-metrics">
          <Metric icon={CheckCircle2} label="Parser status" value={statsCanResult.status || '—'}/>
          <Metric icon={Database} label="Sampled rows" value={num(statcanDiag.sampledRows)}/>
          <Metric icon={Database} label="Institutions" value={num(statcanDiag.institutionCountInSample)}/>
          <Metric icon={Database} label="Downloaded bytes" value={num(statsCanResult.downloadedBytes)}/>
          <Metric icon={ShieldCheck} label="Evidence" value={statsCanResult.evidenceId ? 'Captured' : 'Missing'}/>
          <Metric icon={AlertTriangle} label="Missing headers" value={num(statsCanResult.missingRequiredHeaders?.length)}/>
        </div>
        <div className="idempotency-hint"><ShieldCheck size={16}/><span>Worker {statsCanResult.workerVersion || '—'} · canonical identity writes {statsCanResult.canonicalIdentityWrite ? 'enabled' : 'disabled'} · provider mapping {statsCanResult.providerMappingRequired ? 'required' : 'not required'}.</span></div>
      </div>}
    </section>}

    {runResult && runResult.mode !== 'reset' && <section className="panel full run-result apply-result">
      <div className="panel-title result-title"><div><span className="kicker">Latest {country} result</span><h3>{runResult.controlKind === 'idempotency-rerun' ? 'Idempotency re-run' : runResult.mode === 'apply' ? 'Bounded apply' : 'Bounded validation'}</h3><p>Runtime {runResult.runtime || 'supabase_edge'} · {runResult.workerVersion || topResult.workerVersion || '—'} · adapter {String(topResult.adapter || policy.adapter).replaceAll('_',' ')}</p></div><span className={`result-status ${runResult.mode === 'apply' ? 'write' : 'safe'}`}><CheckCircle2 size={15}/>{runResult.mode === 'apply' ? 'Catalogue reconciled' : 'No catalogue writes'}</span></div>
      <div className="metric-grid control-metrics"><Metric icon={Database} label="Offset" value={num(currentOffset)}/><Metric icon={Database} label="Batch" value={num(currentBatch)}/><Metric icon={Database} label="Selected" value={num(selectedRecords)}/><Metric icon={Database} label="Available" value={num(totalRecords)}/><Metric icon={StepForward} label="Next offset" value={num(nextOffset)}/><Metric icon={RefreshCw} label="Progress" value={`${progressPct}%`}/></div>
      <div style={{height:8,background:'var(--surface-2,#edf1f5)',borderRadius:999,overflow:'hidden',margin:'4px 0 18px'}}><div style={{height:'100%',width:`${progressPct}%`,background:'currentColor',opacity:.55}}/></div>
      <div className="country-result-grid"><div className="country-result"><div><strong>Canonical reconciliation</strong><span>{country} · identifier-first</span></div><div className="country-numbers"><span>Providers +<b>{num(rec.provider_created)}</b></span><span>Providers existing <b>{num(rec.provider_existing)}</b></span><span>Courses +<b>{num(rec.course_created)}</b></span><span>Courses existing <b>{num(rec.course_existing)}</b></span><span>Conflicts <b>{num(rec.conflicts)}</b></span></div></div>{country === 'AU' && <div className="country-result"><div><strong>CRICOS depth</strong><span>Campuses + Course Locations</span></div><div className="country-numbers"><span>Locations <b>{num(depth.location_records)}</b></span><span>Campuses +<b>{num(depth.campuses_created)}</b></span><span>Course↔Campus +<b>{num(depth.course_links_created)}</b></span><span>Existing links <b>{num(depth.course_links_existing)}</b></span><span>Conflicts <b>{num(depth.conflicts)}</b></span></div></div>}</div>
      {runResult.mode === 'apply' && <><div className="panel-title" style={{marginTop:18}}><div><span className="kicker">Retained canonical statistics</span><h3>Catalogue + Search</h3></div></div><div className="metric-grid control-metrics"><Metric icon={Database} label="Providers" value={num(stats.providers)}/><Metric icon={Database} label="Courses" value={num(stats.courses)}/><Metric icon={MapPin} label="Campuses" value={num(stats.campuses)}/><Metric icon={MapPin} label="Course↔Campus" value={num(stats.course_campus_links)}/><Metric icon={Search} label="Search documents" value={num(stats.search_documents)}/><Metric icon={RefreshCw} label="Search generation" value={num(stats.search_generation)}/></div></>}
      <div className="idempotency-hint"><ShieldCheck size={16}/><span>{hasMore ? `Batch complete. Next production offset is ${nextOffset.toLocaleString()}.` : 'Adapter reports no further records in this source scope.'}</span></div>
    </section>}

    <div className="metric-grid compact-grid"><Metric icon={Database} label="Configured regulatory sources" value={rows.filter(r=>r.source_id).length}/><Metric icon={Settings2} label="Countries configured" value={configuredCountries.length}/><Metric icon={Database} label="Catalogue providers" value={num(catalogue?.providers)}/><Metric icon={Database} label="Catalogue courses" value={num(catalogue?.courses)}/><Metric icon={MapPin} label="Campuses" value={num(catalogue?.campuses)}/><Metric icon={MapPin} label="Course↔Campus" value={num(catalogue?.course_campus_links)}/><Metric icon={Search} label="Search documents" value={num(catalogue?.search_documents)}/></div>

    <section className="panel full"><div className="panel-title table-title"><div><span className="kicker">Country → source → programmed adapter</span><h3>Layer 1 source registry</h3><p>Execution is country-specific; this table remains the authoritative source configuration used by the Edge Function.</p></div><div className="searchbox"><Search size={16}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search country or source…"/></div></div><div className="table-wrap"><table><thead><tr><th>Country</th><th>Source</th><th>Adapter</th><th>Coverage</th><th>Auth</th><th>Trust</th><th>Status</th><th>Last success</th></tr></thead><tbody>{shown.length ? shown.map((r,i)=><tr key={r.source_id || `${r.country_code}-${i}`}><td><div className="cell-title"><strong>{r.country_name}</strong><span>{r.country_code} · {r.catalogue_status}</span></div></td><td>{r.source_id ? <div className="cell-title"><strong>{r.source_label}</strong><a href={r.source_url || r.system_base_url} target="_blank" rel="noreferrer">{r.system_name || r.source_url}</a></div> : <span className="source-missing">Not configured</span>}</td><td>{COUNTRY_POLICY[r.country_code]?.adapter || r.system_config?.acquisition_method || r.source_type || '—'}</td><td><div className="coverage-list">{(r.system_config?.coverage || []).map(x=><span key={x}>{String(x).replaceAll('_',' ')}</span>)}</div></td><td>{r.system_config?.auth || 'none'}</td><td>{r.trust_rank ?? '—'}</td><td><span className={`badge badge-${String(r.source_status || 'missing').replace(/[^a-z0-9]+/gi,'-').toLowerCase()}`}>{r.source_status || 'missing'}</span></td><td>{fmt(r.last_success_at)}</td></tr>) : <tr><td colSpan="8"><div className="table-empty">No regulatory source records returned.</div></td></tr>}</tbody></table></div></section>

    <section className="panel settings-note"><div><strong>Production execution</strong><span>Run one country at a time. Every request carries a deterministic offset and bounded batch size, so failed runs can be restarted without replaying the whole source.</span></div><div><strong>Canada</strong><span>CA Layer 1 uses live IRCC DLI Provider authority. The separate StatsCan PSIS Layer 2A dry-run validates outcomes acquisition and provider-mapping candidates without writing canonical identities.</span></div><div><strong>Other countries</strong><span>Country-specific adapters preserve stable regulatory/source identity and can be replaced without changing the Settings execution contract.</span></div></section>

    <section className="panel full"><div className="panel-title"><div><span className="kicker">Danger zone</span><h3>Reset Pilot database</h3><p>UAT-only destructive reset. This is not part of normal production ingestion.</p></div><button className="danger-soft" onClick={()=>{setConfirmMode('reset');setConfirmText('')}} disabled={runBusy || statsCanBusy}><RotateCcw size={15}/>Reset Database</button></div></section>

    {confirmMode && <div className="confirm-backdrop" role="presentation" onMouseDown={()=>setConfirmMode(null)}><div className="confirm-card" role="dialog" aria-modal="true" onMouseDown={e=>e.stopPropagation()}><div className="confirm-icon"><AlertTriangle size={22}/></div><span className="kicker">{confirmMode === 'reset' ? 'Destructive UAT reset' : 'Bounded regulatory write'}</span><h3>{confirmMode === 'reset' ? 'Reset the Pilot database?' : `Apply ${country} records ${pendingOffset.toLocaleString()}–${(pendingOffset + batchValue - 1).toLocaleString()}?`}</h3><p>{confirmMode === 'reset' ? 'This removes business/runtime UAT data while preserving the Layer 1 execution seed and platform configuration.' : `The request will use the ${policy.adapter} adapter, offset ${pendingOffset.toLocaleString()} and a maximum batch size of ${batchValue.toLocaleString()}. Search Projection is rebuilt after the write.`}</p><label>Type <strong>{confirmMode === 'reset' ? 'RESET DATABASE' : `APPLY ${country}`}</strong> to confirm</label><input autoFocus value={confirmText} onChange={e=>setConfirmText(e.target.value)} placeholder={confirmMode === 'reset' ? 'RESET DATABASE' : `APPLY ${country}`}/><div className="confirm-actions"><button className="secondary" onClick={()=>setConfirmMode(null)}>Cancel</button><button className="danger-soft" disabled={confirmText.trim().toUpperCase() !== (confirmMode === 'reset' ? 'RESET DATABASE' : `APPLY ${country}`)} onClick={approve}><AlertTriangle size={15}/>{confirmMode === 'reset' ? 'Reset Database' : 'Apply bounded batch'}</button></div></div></div>}
  </div>
}

function ControlStep({ number, title, text, status, children }) { return <div className={`control-step step-${status}`}><div className="step-number">{status === 'done' ? <CheckCircle2 size={18}/> : number}</div><div className="step-copy"><strong>{title}</strong><span>{text}</span></div><div className="step-action">{children}</div></div> }
function Metric({ icon: Icon, label, value }) { return <div className="metric-card mini"><div className="metric-icon"><Icon size={17}/></div><span>{label}</span><strong>{value}</strong></div> }
function Fact({ label, value }) { return <div className="fact-row"><span>{label}</span><strong>{value ?? '—'}</strong></div> }
function fmt(v) { return v ? new Date(v).toLocaleString() : 'Not checked yet' }
function num(v) { return Number(v ?? 0).toLocaleString() }
