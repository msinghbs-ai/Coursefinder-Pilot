import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'

const fmt=v=>{if(v==null)return'—';if(typeof v==='string')return v;try{return JSON.stringify(v)}catch{return String(v)}}
const human=v=>String(v??'').replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase())
const when=v=>{if(!v)return'—';const d=new Date(v);return Number.isNaN(+d)?String(v):d.toLocaleString()}

export default function Layer4Intervention({type,data,publicationEnabled=true}){
 const[layer4,setLayer4]=useState(data?.layer4||{fields:[]})
 const[pub,setPub]=useState(data?.layer4_publication||{})
 const[history,setHistory]=useState(null)
 const[busy,setBusy]=useState('')
 useEffect(()=>{setLayer4(data?.layer4||{fields:[]});setPub(data?.layer4_publication||{});setHistory(null)},[data?.id])
 async function refresh(){
  const{data:r,error}=await supabase.rpc('layer4_effective_entity',{p_entity_type:type,p_entity_id:data.id})
  if(error)throw error
  setLayer4(r||{fields:[]})
 }
 async function edit(f){
  const current=f.effective_value==null?'':(typeof f.effective_value==='string'?f.effective_value:JSON.stringify(f.effective_value))
  const raw=window.prompt('Layer 4 effective value — '+f.display_label,current)
  if(raw===null)return
  let value=raw
  if(f.value_kind==='duration'||f.value_kind==='json'){try{value=JSON.parse(raw)}catch{return window.alert('Value must be valid JSON')}}
  const reason=window.prompt('Reason code','human_correction');if(!reason)return
  const comment=window.prompt('Comment / decision note (optional)','')||null
  setBusy(f.field_code)
  try{
   const{error}=await supabase.rpc('layer4_override_apply',{p_entity_type:type,p_entity_id:data.id,p_field_code:f.field_code,p_value:value,p_reason_code:reason,p_comment:comment,p_evidence_refs:[],p_approval_context:{surface:'admin_detail_blade'}})
   if(error)throw error
   await refresh()
  }catch(e){window.alert(e.message||String(e))}finally{setBusy('')}
 }
 async function revert(f){
  const reason=window.prompt('Revert reason code','revert_to_underlying');if(!reason)return
  const comment=window.prompt('Comment / decision note (optional)','')||null
  setBusy(f.field_code)
  try{
   const{error}=await supabase.rpc('layer4_override_revert',{p_entity_type:type,p_entity_id:data.id,p_field_code:f.field_code,p_reason_code:reason,p_comment:comment})
   if(error)throw error
   await refresh()
  }catch(e){window.alert(e.message||String(e))}finally{setBusy('')}
 }
 async function audit(f){
  setBusy('history')
  try{
   const{data:r,error}=await supabase.rpc('layer4_override_history',{p_entity_type:type,p_entity_id:data.id,p_field_code:f.field_code})
   if(error)throw error
   setHistory({field:f,rows:r||[]})
  }catch(e){window.alert(e.message||String(e))}finally{setBusy('')}
 }
 async function publication(event){
  const reason=window.prompt('Publication decision reason code',event==='revert'?'revert_publication_override':'manual_publication_decision');if(!reason)return
  const comment=window.prompt('Publication decision note (optional)','')||null
  setBusy('publication')
  try{
   const{error}=await supabase.rpc('layer4_publication_decide',{p_entity_type:type,p_entity_id:data.id,p_target_scope:'governed_publication',p_event_type:event,p_readiness_snapshot:data?.state_summary||{},p_overridden_checks:[],p_reason_code:reason,p_comment:comment,p_approval_context:{surface:'admin_detail_blade'}})
   if(error)throw error
   const{data:r,error:e2}=await supabase.rpc('layer4_publication_state',{p_entity_type:type,p_entity_id:data.id,p_target_scope:'governed_publication'})
   if(e2)throw e2
   setPub(r||{})
  }catch(e){window.alert(e.message||String(e))}finally{setBusy('')}
 }
 const fields=Array.isArray(layer4?.fields)?layer4.fields:[]
 return <section className="m-detail-section cf-layer4-override">
  <div style={{display:'flex',justifyContent:'space-between',gap:8,alignItems:'flex-start'}}>
   <div><h3>Layer 4 governed intervention</h3><p className="m-help">Effective-value overlay only. Underlying source and canonical history remain preserved.</p></div>
   <span className="m-role-pill">{Number(layer4?.active_override_count||0)} active L4</span>
  </div>
  <div className="m-record-list">
   {fields.map(f=><div className="m-record" key={f.field_code} style={f.effective_source==='L4'?{borderColor:'#c4b5fd'}:{}}>
    <div style={{display:'flex',gap:6,alignItems:'center',flexWrap:'wrap'}}>
     <strong>{f.display_label}</strong>
     {f.effective_source==='L4'&&<span className="m-role-pill">L4 effective</span>}
     {f.editability_class==='immutable'&&<small>Immutable source/history</small>}
    </div>
    <span>Underlying: {fmt(f.underlying_value)}</span>
    <span>Effective: {fmt(f.effective_value)}</span>
    {f.upstream_changed&&<small style={{color:'#b45309',fontWeight:800}}>Underlying source changed after this override — review required.</small>}
    {f.effective_source==='L4'&&<small>Edited by {f.actor_email||f.actor_id||'authorised user'} · {when(f.edited_at)} · {human(f.reason_code||'human decision')}{f.comment?' · '+f.comment:''}</small>}
    <div style={{display:'flex',gap:5,flexWrap:'wrap'}}>
     {f.can_edit&&<button className="m-secondary compact" disabled={busy===f.field_code} onClick={()=>edit(f)}>Edit effective value</button>}
     {f.effective_source==='L4'&&f.can_edit&&<button className="m-secondary compact" disabled={busy===f.field_code} onClick={()=>revert(f)}>Revert</button>}
     {Number(f.history_count||0)>0&&<button className="m-secondary compact" disabled={busy==='history'} onClick={()=>audit(f)}>Audit ({f.history_count})</button>}
    </div>
   </div>)}
  </div>
  {publicationEnabled&&<div className="m-record" style={{marginTop:8}}>
   <strong>Publication override · separate decision</strong>
   <span>{human(pub?.effective_decision||'no_override')}{pub?.actor_email?' · '+pub.actor_email:''}{pub?.decided_at?' · '+when(pub.decided_at):''}</span>
   {pub?.can_decide&&<div style={{display:'flex',gap:5,flexWrap:'wrap'}}>
    <button className="m-secondary compact" disabled={busy==='publication'} onClick={()=>publication('publishable')}>Mark publishable</button>
    <button className="m-secondary compact" disabled={busy==='publication'} onClick={()=>publication('not_publishable')}>Mark not publishable</button>
    {pub?.effective_decision!=='no_override'&&<button className="m-secondary compact" disabled={busy==='publication'} onClick={()=>publication('revert')}>Revert publication decision</button>}
   </div>}
   <small>This does not authorise Production, Website or Zoho cutover.</small>
  </div>}
  {history&&<div className="m-record-list" style={{marginTop:8}}>
   <strong>Audit history · {history.field.display_label}</strong>
   {history.rows.map(x=><div className="m-record" key={x.id}><span>{human(x.event_type)} · {x.actor_email||x.actor_id} · {when(x.created_at)}</span><small>{human(x.reason_code)}{x.comment?' · '+x.comment:''}</small></div>)}
  </div>}
 </section>
}
