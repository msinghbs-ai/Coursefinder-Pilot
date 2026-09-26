import React,{useEffect,useMemo,useState}from'react'
import{CheckCircle2,RefreshCw,Search}from'lucide-react'
import{supabase}from'./lib/supabase'

// Package 7 (Decision 141): per-provider Layer 2 onboarding. An operator supplies the provider's course
// catalogue page; "Check" is a dry run (no change), "Validate & qualify" starts the existing
// three-course identity check. Nothing reaches the catalogue unless that check passes 3 of 3.
const STATES=[['','All'],['needs_catalogue_page','Needs catalogue page'],['identity_check_running','Identity check running'],['needs_person','Needs a person'],['qualified','Qualified'],['site_limited','Site limited'],['not_yet_assessed','Not yet assessed']]
const LABEL={needs_catalogue_page:'Needs catalogue page',identity_check_running:'Identity check running',needs_person:'Needs a person',qualified:'Qualified',site_limited:'Site limited',not_yet_assessed:'Not yet assessed',in_progress:'In progress'}
const AUTO={checking:'Automatic check running',passed:'Qualified automatically',failed:'Automatic candidate failed',error:'Automatic attempt could not start',needs_person:'Automatic discovery found no working page'}
const n=v=>Number(v||0).toLocaleString('en-AU')
const when=v=>v?new Date(v).toLocaleString('en-AU',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}):''
const httpsOf=u=>{const s=String(u||'').trim();if(!s)return'https://';return s.replace(/^http:\/\//i,'https://').replace(/^(?!https:\/\/)/i,'https://')}
const rpc=async(fn,args)=>{const{data,error}=await supabase.rpc(fn,args);if(error)throw new Error(error.message);return data}

export default function ProviderOnboarding({rank=0,openEvidence}){
  const[country,setCountry]=useState('AU'),[state,setState]=useState('needs_catalogue_page'),[data,setData]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[open,setOpen]=useState(null)
  const load=async()=>{setBusy(true);setError('');try{setData(await rpc('layer2_provider_onboarding_queue_v1',{p_country:country,p_limit:200}))}catch(e){setError(e.message)}finally{setBusy(false)}}
  useEffect(()=>{load()},[country])
  const rows=useMemo(()=>(data?.items||[]).filter(r=>!state||r.state===state).slice(0,50),[data,state])
  return <section className="l2o-panel l2po">
    <div className="l2o-panel-head"><div><h2>Provider onboarding</h2><p>Courses reach Layer 2 once their provider is qualified. Supply the provider's course catalogue page; it is accepted only if three of its courses resolve correctly.</p></div>
      <div className="l2po-tools"><select aria-label="Onboarding country" value={country} onChange={e=>setCountry(e.target.value)}><option value="AU">Australia</option><option value="NZ">New Zealand</option></select><button onClick={load} disabled={busy} aria-label="Refresh provider onboarding"><RefreshCw size={14}/></button></div></div>
    {data&&<p className="l2po-summary"><strong>{n(data.providers_waiting)}</strong> providers · <strong>{n(data.courses_waiting)}</strong> courses waiting for qualification{data.computed_at&&<small> · counts updated {when(data.computed_at)}</small>}</p>}
    <div className="l2po-chips">{STATES.map(([v,l])=><button key={v||'all'} type="button" className={state===v?'on':''} onClick={()=>setState(v)}>{l}</button>)}</div>
    {error&&<div className="l2o-error">{error}</div>}
    {!data&&busy?<div className="l2o-empty">Loading providers…</div>:rows.length===0?<div className="l2o-empty">No providers in this state.</div>:
    <div className="l2po-table-wrap"><table className="l2po-table"><thead><tr><th>Provider</th><th>Courses waiting</th><th>State</th><th>Last submission</th><th/></tr></thead><tbody>
      {rows.map(r=><React.Fragment key={r.provider_id}><tr className={open===r.provider_id?'on':''}>
        <td><strong>{r.provider}</strong>{r.website&&<small>{r.website}</small>}</td>
        <td>{n(r.courses_waiting)}</td>
        <td><span className={`l2po-state s-${r.state}`}>{LABEL[r.state]||r.state}</span>{r.auto_latest&&<small>{AUTO[r.auto_latest.status]||r.auto_latest.status}{r.auto_latest.reason?` · ${r.auto_latest.reason}`:''}</small>}</td>
        <td>{r.last_submission?<small>{r.last_submission.dry_run?'Checked':(r.last_submission.origin==='automatic'?'Submitted automatically':'Submitted')} {when(r.last_submission.at)}</small>:<small>—</small>}</td>
        <td>{r.ready_for_submission&&<button type="button" onClick={()=>setOpen(open===r.provider_id?null:r.provider_id)}>{open===r.provider_id?'Close':'Onboard'}</button>}</td>
      </tr>{open===r.provider_id&&<tr className="l2po-detail"><td colSpan={5}><Onboard row={r} rank={rank} onDone={load} openEvidence={openEvidence}/></td></tr>}</React.Fragment>)}
    </tbody></table></div>}
    <p className="l2o-note">Showing up to 50 providers, largest first. Site-limited providers need a different acquisition route and are reviewed separately.</p>
  </section>
}

function Onboard({row,rank,onDone,openEvidence}){
  const[url,setUrl]=useState(httpsOf(row.suggested_start)),[reason,setReason]=useState('Course catalogue page checked on the provider website'),[check,setCheck]=useState(null),[busy,setBusy]=useState(''),[msg,setMsg]=useState(''),[error,setError]=useState('')
  const canAct=rank>=4
  const run=async dry=>{setBusy(dry?'check':'submit');setError('');setMsg('');try{
      if(!dry&&!window.confirm(`Start the three-course identity check for ${row.provider} using\n${url}?\n\nThis uses provider credits for three courses.`)){setBusy('');return}
      const r=await rpc('layer2_provider_catalogue_submit_v1',{p_provider_id:row.provider_id,p_catalogue_url:url.trim(),p_reason:reason,p_dry_run:dry})
      if(dry){setCheck({url:url.trim(),controls:(r.control_course_ids||[]).length});setMsg(`Ready: ${(r.control_course_ids||[]).length} control courses will be checked; all three must resolve.`)}
      else{setMsg('Identity check started. The provider qualifies automatically if all three control courses resolve.');setCheck(null);onDone?.()}
    }catch(e){setError(e.message)}finally{setBusy('')}}
  const checked=check&&check.url===url.trim()
  const cands=Array.isArray(row.candidates)?row.candidates:[]
  return <div className="l2po-onboard">
    {cands.length>0&&<div className="l2po-cands"><span>Candidates found in stored evidence</span>{cands.map(c=>{const u=httpsOf(c.url);return <div key={c.url} className={url.trim()===u?'on':''}>
      <button type="button" onClick={()=>{setUrl(u);setMsg('');setCheck(null)}}>Use</button>
      <span><strong>{c.link_text||u}</strong><small>{u} · score {c.score} · on {c.found_on_pages} page{Number(c.found_on_pages)===1?'':'s'}</small></span>
      {c.evidence_id&&openEvidence&&<button type="button" className="link" onClick={()=>openEvidence(c.evidence_id)}>View evidence</button>}
    </div>})}</div>}
    <label>Course catalogue page<input value={url} onChange={e=>{setUrl(e.target.value);setMsg('')}} placeholder="https://…" spellCheck={false}/></label>
    <label>Reason (kept in the audit)<input value={reason} onChange={e=>setReason(e.target.value)}/></label>
    <div className="l2po-actions">
      <button type="button" disabled={!canAct||!!busy} onClick={()=>run(true)}><Search size={13}/>{busy==='check'?'Checking…':'Check'}</button>
      <button type="button" className="primary" disabled={!canAct||!!busy||!checked} onClick={()=>run(false)}><CheckCircle2 size={13}/>{busy==='submit'?'Starting…':'Validate & qualify'}</button>
      <a href={url} target="_blank" rel="noreferrer">Open page</a>
    </div>
    {!canAct&&<p className="l2o-note">Onboarding a provider needs the Pipeline Operator role.</p>}
    {msg&&<p className="l2po-msg">{msg}</p>}{error&&<div className="l2o-error">{error}</div>}
  </div>
}
