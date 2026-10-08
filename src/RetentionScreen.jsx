// v2.15.219 (CF-247, Platform Admin 8 Oct 2026 10:31): Storage & retention. What takes space, the rule for each category, a preview that
// changes nothing, and Purge (Platform Admin, reason and typed confirmation) that runs in the background in small batches. Every run is logged.
// Reads and writes: admin_retention (Platform Admin only, checked on the server).
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtNumber}from'./ui-kit'
import{fmtDateTime}from'./lib/format.js'

const errText=e=>e?.message||String(e)
const mb=b=>b==null?'—':b>=1e9?`${(b/1e9).toFixed(2)} GB`:`${Math.round(b/1e6)} MB`
const when=t=>fmtDateTime(t)
const TONE={done:'tone-success',failed:'tone-danger',stopped:'tone-neutral',running:'tone-info',queued:'tone-info'}

function Detail({c}){
  const d=c.estimate?.detail||{}
  if(c.key==='retired_layer2')return <ul className="tn-list">{Object.entries(d).map(([k,v])=><li key={k}><small className="sl-sub">{k.replace(/_/g,' ')}: {fmtNumber(v)} rows</small></li>)}</ul>
  if(c.key==='directory_urls')return <small className="sl-sub">Directory sites: {(d.hosts||[]).join(', ')||'—'}</small>
  if(c.key==='evidence_audit')return <small className="sl-sub">{d.columns?`${fmtNumber(d.columns_done)} of ${fmtNumber(d.columns)} reference columns checked · ${fmtNumber(d.references)} referenced records · ${fmtNumber(d.evidence_records)} records in all · ${mb(d.evidence_files_bytes)} of evidence files`:'Not audited yet.'}</small>
  if(c.key==='evidence_unreferenced')return <small className="sl-sub">{d.audit_finished_at?`Based on the evidence audit finished ${fmtDateTime(d.audit_finished_at)}. Evidence created since then, or in the last 7 days, waits for the next audit.`:(d.note||'Run the evidence audit first.')}</small>
  return null
}

export default function RetentionScreen({onError}){
  const[r,setR]=useState(null),[busy,setBusy]=useState(''),[open,setOpen]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_retention',{p_action:'read',p_args:{}});if(error)throw error;setR(data)}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[])
  const active=(r?.categories||[]).some(c=>c.active)
  useEffect(()=>{if(!active)return;const t=setInterval(load,15000);return()=>clearInterval(t)},[active])
  if(!r)return <Loading label="Measuring storage…"/>
  const act=async(c,action)=>{
    const reason=window.prompt(action==='stop'?`Stop the ${c.label.toLowerCase()} run?\n\nReason (kept in the log):`:c.key==='evidence_audit'?`Run the evidence audit? It counts references in the background and deletes nothing.\n\nReason (kept in the log):`:`Purge ${c.label.toLowerCase()}?\n\nRule: ${c.rule}\n\nReason (kept in the log):`)
    if(!reason||reason.trim().length<4)return
    let confirm=''
    if(action==='purge'&&c.key!=='evidence_audit'){confirm=window.prompt(`Type ${c.key} to confirm. This cannot be undone.`)||'';if(confirm!==c.key)return}
    setBusy(c.key);try{const{error}=await supabase.rpc('admin_retention',{p_action:action,p_args:{category:c.key,reason:reason.trim(),confirm}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy('')}}
  return <div className="m-page-stack rt-screen" data-retention>
    <section className="m-panel"><div className="m-workspace-head"><div><h2>Storage & retention</h2><p>Database {mb(r.database_bytes)}. Each category shows what it holds and its rule. Preview changes nothing; Purge runs in the background in small batches and is logged. Values on record and the evidence behind them are never purged here.</p></div></div>
      <div className="cf-table-wrap"><table className="cf-table" data-retention-categories><thead><tr><th>Category</th><th>Size now</th><th>Would go</th><th>Measured</th><th>Status</th><th></th></tr></thead><tbody>
        {r.categories.map(c=>{const e=c.estimate,run=c.active||c.last;return <React.Fragment key={c.key}><tr data-retention-row={c.key}>
          <td><strong>{c.label}</strong><small className="sl-sub">{c.rule}</small></td>
          <td>{mb(e?.size_bytes)}</td>
          <td>{e?.purgeable_rows==null?'—':<>{fmtNumber(e.purgeable_rows)} {c.kind==='files'?'files':'rows'}<small className="sl-sub">about {mb(e.purgeable_bytes)}</small></>}</td>
          <td><small className="sl-sub">{when(e?.measured_at)}</small></td>
          <td>{run?<><span className={`cf-chip ${TONE[run.status]||'tone-neutral'}`} data-retention-status={run.status}>{run.status}</span><small className="sl-sub">{run.note||''}{run.error?` · ${run.error}`:''}</small></>:<small className="sl-sub">Never run</small>}</td>
          <td className="rt-actions"><Button compact onClick={()=>setOpen(open===c.key?'':c.key)}>{open===c.key?'Hide':'Preview'}</Button>
            {c.active?<Button compact disabled={busy===c.key} onClick={()=>act(c,'stop')}>Stop</Button>
              :c.key==='evidence_audit'?<Button compact disabled={Boolean(busy)} onClick={()=>act(c,'purge')}>Run audit</Button>
              :<Button compact variant="primary" disabled={Boolean(busy)||!e?.purgeable_rows} onClick={()=>act(c,'purge')}>Purge</Button>}</td></tr>
          {open===c.key&&<tr data-retention-preview={c.key}><td colSpan={6}><Detail c={c}/><small className="sl-sub"> Counts are measured in the background (hourly) and again when a purge starts; a preview changes nothing.</small></td></tr>}
        </React.Fragment>})}
      </tbody></table></div></section>
    <section className="m-panel"><h3 className="sl-h4">Runs</h3>{(r.runs||[]).length?<div className="cf-table-wrap"><table className="cf-table" data-retention-runs><thead><tr><th>When</th><th>Category</th><th>Status</th><th>Removed</th><th>Reason</th></tr></thead><tbody>
      {r.runs.map(x=><tr key={x.id}><td>{when(x.created_at)}</td><td>{x.category.replace(/_/g,' ')}</td><td><span className={`cf-chip ${TONE[x.status]||'tone-neutral'}`}>{x.status}</span></td><td>{fmtNumber(x.removed)}{x.bytes?` · ${mb(x.bytes)}`:''}</td><td><small className="sl-sub">{x.reason}</small></td></tr>)}
    </tbody></table></div>:<Empty text="No purge or audit has run yet."/>}</section>
  </div>
}
