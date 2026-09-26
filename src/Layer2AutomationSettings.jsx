import React,{useEffect,useState}from'react'
import{Bot,RefreshCw,Save}from'lucide-react'
import{supabase}from'./lib/supabase'

// Package 7 (Decisions 141, 146): Platform Admin controls for Layer 2 automatic catalogue discovery.
// Providers in flight cannot exceed the Firecrawl concurrency; the vendor limit still governs fetches.
const rpc=async(fn,args)=>{const{data,error}=await supabase.rpc(fn,args);if(error)throw new Error(error.message);return data}
const when=v=>v?new Date(v).toLocaleString('en-AU',{day:'numeric',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}):'—'

export default function Layer2AutomationSettings({onError}){
  const[data,setData]=useState(null),[form,setForm]=useState(null),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[saved,setSaved]=useState(''),[error,setError]=useState('')
  const load=async()=>{setBusy(true);setError('');try{const r=await rpc('layer2_auto_discovery_settings_read_v1',{});setData(r);setForm({enabled:r.enabled,daily:r.daily_provider_cap,inFlight:r.providers_in_flight,candidates:r.candidates_per_provider})}catch(e){setError(e.message);onError?.(e.message)}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  const save=async()=>{setBusy(true);setError('');setSaved('');try{const r=await rpc('layer2_auto_discovery_settings_save_v1',{p_enabled:form.enabled,p_daily_provider_cap:Number(form.daily),p_providers_in_flight:Number(form.inFlight),p_candidates_per_provider:Number(form.candidates),p_reason:reason});setData(r);setReason('');setSaved('Saved. New values apply from the next scheduled run.')}catch(e){setError(e.message)}finally{setBusy(false)}}
  if(!data||!form)return <section className="l2as"><div className="l2as-head"><h3><Bot size={16}/> Layer 2 automation</h3></div>{error?<div className="l2as-error">{error}</div>:<p className="l2as-note">Loading…</p>}</section>
  const edit=data.can_edit,max=Number(data.firecrawl_concurrency||1)
  return <section className="l2as">
    <div className="l2as-head"><div><h3><Bot size={16}/> Layer 2 automation</h3><p>Automatic catalogue discovery: finds each waiting provider's course catalogue page from stored evidence, then runs the three-course identity check. Providers that fail go to a person.</p></div><button onClick={load} disabled={busy} aria-label="Refresh Layer 2 automation"><RefreshCw size={14}/></button></div>
    <div className="l2as-grid">
      <label className="l2as-switch"><input type="checkbox" checked={!!form.enabled} disabled={!edit} onChange={e=>setForm({...form,enabled:e.target.checked})}/><span><strong>{form.enabled?'On':'Off'}</strong><small>Run automatic discovery on its schedule</small></span></label>
      <label>Providers per day<input type="number" min="0" max="500" value={form.daily} disabled={!edit} onChange={e=>setForm({...form,daily:e.target.value})}/><small>0 pauses discovery without switching it off</small></label>
      <label>Providers in flight<input type="number" min="1" max={max} value={form.inFlight} disabled={!edit} onChange={e=>setForm({...form,inFlight:e.target.value})}/><small>Up to {max} (Firecrawl concurrency; change it under Acquisition providers)</small></label>
      <label>Candidate pages per provider<input type="number" min="1" max="5" value={form.candidates} disabled={!edit} onChange={e=>setForm({...form,candidates:e.target.value})}/><small>Each candidate costs the page plus three course pages if not already stored</small></label>
    </div>
    {edit?<div className="l2as-save"><label>Reason (kept in the audit)<input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why this change is needed"/></label><button className="primary" disabled={busy||reason.trim().length<8} onClick={save}><Save size={14}/>{busy?'Saving…':'Save'}</button></div>
      :<p className="l2as-note">Only a Platform Admin can change these settings.</p>}
    {saved&&<p className="l2as-ok">{saved}</p>}{error&&<div className="l2as-error">{error}</div>}
    <p className="l2as-note">Last changed {when(data.updated_at)}.</p>
    {(data.recent_changes||[]).length>0&&<details className="l2as-history"><summary>Recent changes</summary>{data.recent_changes.map((c,i)=><div key={i}><strong>{when(c.at)}</strong><span>{c.reason}</span><small>{c.after?.enabled?'On':'Off'} · {c.after?.daily_provider_cap} per day · {c.after?.providers_in_flight} in flight · {c.after?.candidates_per_provider} candidates</small></div>)}</details>}
  </section>
}
