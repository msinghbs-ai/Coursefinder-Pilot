import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import ManualPimCandidateWorkspace from'./ManualPimCandidateWorkspace'

const fmt=v=>{if(v==null)return'—';if(typeof v==='string')return v;try{return JSON.stringify(v)}catch{return String(v)}}
const human=v=>String(v??'').replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase())
const when=v=>{if(!v)return'—';const d=new Date(v);return Number.isNaN(+d)?String(v):d.toLocaleString()}

export default function Layer4Intervention({type,data,publicationEnabled=true}){
 const[layer4,setLayer4]=useState(data?.layer4||{fields:[]})
 const[pub,setPub]=useState(data?.layer4_publication||{})
 const[pubScope,setPubScope]=useState('governed_publication')
 const[history,setHistory]=useState(null)
 const[candidatesOpen,setCandidatesOpen]=useState(false)
 const[busy,setBusy]=useState('')
 useEffect(()=>{setLayer4(data?.layer4||{fields:[]});setPub(data?.layer4_publication||{});setHistory(null);setPubScope('governed_publication');setCandidatesOpen(false)},[data?.id])
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
 async function publication(action){
  const reason=window.prompt('Publication decision reason code',action==='rollback'?'rollback_publication_decision':'manual_publication_decision');if(!reason)return
  const comment=window.prompt('Publication decision note (optional)','')||null
  setBusy('publication')
  try{
   const{data:preview,error:previewError}=await supabase.rpc('publication_control_preview',{p_entity_type:type,p_entity_ids:[data.id],p_target_scope:pubScope,p_action:action})
   if(previewError)throw previewError
   const label=`${human(action)} 1 ${human(type)} for ${human(pubScope)}?\n\nAutomatic publication: ${preview?.auto_publication_enabled?'ENABLED':'DISABLED'}\nThis records the governed publication decision only; consumer cutover remains separately controlled.`
   if(!window.confirm(label))return
   const{error}=await supabase.rpc('publication_control_execute',{p_entity_type:type,p_entity_ids:[data.id],p_target_scope:pubScope,p_action:action,p_confirmation_token:preview.confirmation_token,p_reason_code:reason,p_comment:comment})
   if(error)throw error
   const{data:r,error:e2}=await supabase.rpc('layer4_publication_state',{p_entity_type:type,p_entity_id:data.id,p_target_scope:pubScope})
   if(e2)throw e2
   setPub(r||{})
  }catch(e){window.alert(e.message||String(e))}finally{setBusy('')}
 }
 async function changePublicationScope(next){
  setPubScope(next)
  try{
   const{data:r,error}=await supabase.rpc('layer4_publication_state',{p_entity_type:type,p_entity_id:data.id,p_target_scope:next})
   if(error)throw error
   setPub(r||{})
  }catch(e){window.alert(e.message||String(e))}
 }
 const fields=Array.isArray(layer4?.fields)?layer4.fields:[]
 const providerContext=type==='provider'?data?.id:(data?.provider_id||data?.provider?.id||'')
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
   <strong>Publication control · preview required</strong>
   <label style={{display:'flex',gap:8,alignItems:'center',flexWrap:'wrap'}}>Target<select value={pubScope} onChange={e=>changePublicationScope(e.target.value)} disabled={busy==='publication'}><option value="governed_publication">Governed publication</option><option value="search_api">Search / API</option><option value="website">Website</option><option value="zoho">Zoho</option></select></label>
   <span>{human(pub?.effective_decision||'no_override')}{pub?.actor_email?' · '+pub.actor_email:''}{pub?.decided_at?' · '+when(pub.decided_at):''}</span>
   {pub?.can_decide&&<div style={{display:'flex',gap:5,flexWrap:'wrap'}}>
    <button className="m-secondary compact" disabled={busy==='publication'} onClick={()=>publication('publish')}>Preview & mark publishable</button>
    <button className="m-secondary compact" disabled={busy==='publication'} onClick={()=>publication('unpublish')}>Preview & mark not publishable</button>
    {pub?.effective_decision!=='no_override'&&<button className="m-secondary compact" disabled={busy==='publication'} onClick={()=>publication('rollback')}>Preview & rollback</button>}
   </div>}
   <small>Automatic publication is disabled. This control records an audited Layer 4 decision; it does not itself authorise Production, Website or Zoho cutover.</small>
  </div>}
  {['provider','course','campus','scholarship'].includes(type)&&<div className="m-record" style={{marginTop:8}}>
   <strong>Source-backed PIM candidate workflow</strong>
   <span>Register a new governed source candidate without writing canonical identity or publication state.</span>
   <button className="m-secondary compact" onClick={()=>setCandidatesOpen(x=>!x)}>{candidatesOpen?'Close candidate workspace':'Open candidate workspace'}</button>
   {candidatesOpen&&<div style={{marginTop:8}}><ManualPimCandidateWorkspace initialEntityType={type} initialProviderId={providerContext} onError={e=>window.alert(e?.message||String(e))}/></div>}
  </div>}
  {history&&<div className="m-record-list" style={{marginTop:8}}>
   <strong>Audit history · {history.field.display_label}</strong>
   {history.rows.map(x=><div className="m-record" key={x.id}><span>{human(x.event_type)} · {x.actor_email||x.actor_id} · {when(x.created_at)}</span><small>{human(x.reason_code)}{x.comment?' · '+x.comment:''}</small></div>)}
  </div>}
 </section>
}
