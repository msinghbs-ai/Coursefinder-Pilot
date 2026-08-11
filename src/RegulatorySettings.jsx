import React, { useEffect, useMemo, useState } from 'react'
import { Database, RefreshCw, Search, Settings2 } from 'lucide-react'
import { api } from './lib/supabase'
import './settings.css'

export default function RegulatorySettings({ onError }) {
  const [rows, setRows] = useState([])
  const [q, setQ] = useState('')
  const [busy, setBusy] = useState(true)

  const load = () => {
    setBusy(true)
    api.regulatorySources().then(setRows).catch(e => onError(e.message)).finally(() => setBusy(false))
  }

  useEffect(load, [])

  const shown = useMemo(() => rows.filter(r => [
    r.country_name, r.country_code, r.source_label, r.system_name, r.source_type,
    ...(r.system_config?.coverage || []),
  ].filter(Boolean).join(' ').toLowerCase().includes(q.toLowerCase())), [rows, q])

  const countries = new Set(rows.map(r => r.country_code)).size
  const configured = new Set(rows.filter(r => r.source_id).map(r => r.country_code)).size
  const sources = rows.filter(r => r.source_id).length
  const healthy = rows.filter(r => r.last_success_at && (!r.last_failure_at || new Date(r.last_success_at) >= new Date(r.last_failure_at))).length

  return <div className="stack">
    <div className="section-head">
      <div>
        <span className="kicker">Platform Admin · Layer 1</span>
        <h2>Regulatory Sources</h2>
        <p>Authoritative country source registry used by the Layer 1 Worker. Source endpoints are configuration, not frontend code.</p>
      </div>
      <button className="secondary" onClick={load}><RefreshCw size={15} className={busy ? 'spin' : ''}/>Refresh</button>
    </div>

    <div className="metric-grid compact-grid">
      <Metric icon={Settings2} label="Pilot countries" value={countries}/>
      <Metric icon={Database} label="Configured countries" value={`${configured}/${countries}`}/>
      <Metric icon={Database} label="Authoritative sources" value={sources}/>
      <Metric icon={RefreshCw} label="Successful health checks" value={healthy}/>
    </div>

    <section className="panel full">
      <div className="panel-title table-title">
        <div><span className="kicker">Country → source → acquisition</span><h3>Layer 1 source control</h3><p>Multiple sources are supported where one regulator does not cover the complete provider/course domain.</p></div>
        <div className="searchbox"><Search size={16}/><input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search country or source…"/></div>
      </div>
      <div className="table-wrap"><table><thead><tr>
        <th>Country</th><th>Source</th><th>Method</th><th>Coverage</th><th>Auth</th><th>Trust</th><th>Status</th><th>Last success</th>
      </tr></thead><tbody>
        {shown.length ? shown.map((r,i)=><tr key={r.source_id || `${r.country_code}-${i}`}>
          <td><div className="cell-title"><strong>{r.country_name}</strong><span>{r.country_code} · {r.catalogue_status}</span></div></td>
          <td>{r.source_id ? <div className="cell-title"><strong>{r.source_label}</strong><a href={r.source_url || r.system_base_url} target="_blank" rel="noreferrer">{r.system_name || r.source_url}</a></div> : <span className="source-missing">Not configured</span>}</td>
          <td>{r.system_config?.acquisition_method || r.source_type || '—'}</td>
          <td><div className="coverage-list">{(r.system_config?.coverage || []).map(x=><span key={x}>{String(x).replaceAll('_',' ')}</span>)}</div></td>
          <td>{r.system_config?.auth || 'none'}</td>
          <td>{r.trust_rank ?? '—'}</td>
          <td><span className={`badge badge-${String(r.source_status || 'missing').replace(/[^a-z0-9]+/gi,'-').toLowerCase()}`}>{r.source_status || 'missing'}</span></td>
          <td>{fmt(r.last_success_at)}</td>
        </tr>) : <tr><td colSpan="8"><div className="table-empty">No regulatory source records returned.</div></td></tr>}
      </tbody></table></div>
    </section>

    <section className="panel settings-note">
      <div><strong>Worker resolution rule</strong><span>Country → active source(s) ordered by trust rank → system configuration → runtime secret.</span></div>
      <div><strong>Health telemetry</strong><span>Last check/success/failure remain empty until the Layer 1 Worker begins source health checks.</span></div>
      <div><strong>Security</strong><span>This screen is available only to Platform Admin. Worker source resolution is service-role only.</span></div>
    </section>
  </div>
}

function Metric({ icon: Icon, label, value }) {
  return <div className="metric-card mini"><div className="metric-icon"><Icon size={17}/></div><span>{label}</span><strong>{value}</strong></div>
}

function fmt(v) { return v ? new Date(v).toLocaleString() : 'Not checked yet' }
