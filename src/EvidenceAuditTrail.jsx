// v2.16.39 (CF-247, S2-Build, Platform Admin 18 Nov 2026 12:49): Evidence › Audit trail. The latest runs of the three dispatchers
// (rollup-scheduler, coverage-lane-dispatch, admission-rule-runner), the Boost model qualifications and the latest Layer 4 decisions,
// each with who, when and why. Read-only. Reads: admin_ops_audit_v1 (Curator and above, checked on the server).
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Empty,Loading}from'./ui-kit'
import{fmtDateTime}from'./lib/format.js'
import{plainError}from'./lib/errors'

const TONE={succeeded:'tone-success',ok:'tone-success',failed:'tone-danger',skipped:'tone-neutral',shadow:'tone-info',approve:'tone-success',approved:'tone-success',reject:'tone-danger',rejected:'tone-danger'}
const words=s=>String(s||'—').replace(/_/g,' ')
const VIEWS=[['dispatcher_runs','Dispatcher runs'],['boost_qualifications','Boost qualifications'],['layer4_decisions','Layer 4 decisions']]

export default function EvidenceAuditTrail({onError}){
  const[d,setD]=useState(null),[view,setView]=useState('dispatcher_runs'),[failed,setFailed]=useState(false)
  useEffect(()=>{let live=true;setD(null);supabase.rpc('admin_ops_audit_v1',{p_args:{failed_only:failed}}).then(({data,error})=>{if(!live)return;if(error){onError?.(plainError(error));setD({})}else setD(data||{})});return()=>{live=false}},[failed])
  const rows=d?.[view]||[]
  return <section className="m-panel" data-evidence-audit>
    <div className="m-workspace-head"><div><h2>Audit trail</h2><p>The latest {d?.rows||''} runs of the dispatchers, the Boost model qualifications and the latest Layer 4 decisions, with who, when and why. Read-only.</p></div></div>
    <div className="m-chip-row" role="tablist" aria-label="Audit trail">{VIEWS.map(([k,l])=><button key={k} role="tab" aria-selected={view===k} className={`cf-chip ${view===k?'tone-info':'tone-neutral'}`} data-audit-view={k} onClick={()=>setView(k)}>{l}</button>)}
      {view==='dispatcher_runs'&&<label className="sl-sub"><input type="checkbox" checked={failed} onChange={e=>setFailed(e.target.checked)} data-audit-failed/> Failed runs only</label>}</div>
    {!d?<Loading label="Reading the audit trail…"/>:!rows.length?<Empty text="Nothing recorded yet."/>:<div className="cf-table-wrap">
      {view==='dispatcher_runs'&&<table className="cf-table" data-audit-table="dispatcher_runs"><thead><tr><th>When</th><th>Dispatcher</th><th>Target</th><th>Mode</th><th>Status</th><th>Took</th></tr></thead><tbody>
        {rows.map((r,i)=><tr key={i}><td>{fmtDateTime(r.at)}</td><td>{r.dispatcher}</td><td>{r.target}</td><td>{words(r.mode)}</td><td><span className={`cf-chip ${TONE[r.status]||'tone-neutral'}`}>{words(r.status)}</span>{r.error&&<small className="sl-sub">{r.error}</small>}</td><td>{r.ms!=null?`${Math.round(r.ms)} ms`:'—'}</td></tr>)}</tbody></table>}
      {view==='boost_qualifications'&&<table className="cf-table" data-audit-table="boost_qualifications"><thead><tr><th>Qualified</th><th>Lane</th><th>Model</th><th>By</th><th>Why</th></tr></thead><tbody>
        {rows.map((r,i)=><tr key={i}><td>{fmtDateTime(r.at)}</td><td>{words(r.lane)}</td><td>{r.model}<small className="sl-sub">{r.provider}</small></td><td>{r.by||'Platform Admin decision (recorded by a migration)'}</td><td><small className="sl-sub">{r.reason}</small></td></tr>)}</tbody></table>}
      {view==='layer4_decisions'&&<table className="cf-table" data-audit-table="layer4_decisions"><thead><tr><th>When</th><th>Decision</th><th>Field</th><th>By</th><th>Reason</th><th>Evidence</th></tr></thead><tbody>
        {rows.map(r=><tr key={r.id}><td>{fmtDateTime(r.at)}</td><td><span className={`cf-chip ${TONE[r.action]||'tone-neutral'}`}>{words(r.action)}</span></td><td>{words(r.field)}<small className="sl-sub">{words(r.entity_type)}</small></td><td>{r.by||'Automatic rule'}</td><td><small className="sl-sub">{r.reason||'—'}</small></td><td>{r.evidence_id?<a href={`#evidence?evidence_id=${r.evidence_id}`}>Open</a>:'—'}</td></tr>)}</tbody></table>}
    </div>}
  </section>
}
