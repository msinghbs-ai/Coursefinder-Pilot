import React,{useEffect,useState}from'react'
import{supabase,api}from'./lib/supabase'

const human=v=>String(v??'').replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase())
const when=v=>v?new Date(v).toLocaleString():'—'

export default function ManualPimCandidateWorkspace({rank=null,onError,initialEntityType='',initialProviderId=''}){
 const[resolvedRank,setResolvedRank]=useState(rank==null?0:Number(rank)||0)
 const[items,setItems]=useState([]),[busy,setBusy]=useState(false),[status,setStatus]=useState(''),[type,setType]=useState('')
 const[form,setForm]=useState({entity_type:initialEntityType||'provider',target_provider_id:initialProviderId||'',source_kind:'authority',external_identifier:'',source_url:'',evidence_id:'',reason:'Register source-backed candidate for governed acquisition/reconciliation.'})
 const rpc=async(name,args={})=>{const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}
 useEffect(()=>{let live=true;if(rank!=null){setResolvedRank(Number(rank)||0);return()=>{live=false}}api.context().then(x=>live&&setResolvedRank(Number(x?.role_rank)||0)).catch(e=>onError?.(e));return()=>{live=false}},[rank])
 useEffect(()=>{setForm(x=>({...x,entity_type:initialEntityType||x.entity_type,target_provider_id:initialProviderId||x.target_provider_id}))},[initialEntityType,initialProviderId])
 const load=async()=>{setBusy(true);try{const r=await rpc('manual_pim_candidates_read',{p_status:status||null,p_entity_type:type||null,p_limit:100});setItems(r?.items||[])}catch(e){onError?.(e)}finally{setBusy(false)}}
 useEffect(()=>{if(resolvedRank>=5)load()},[resolvedRank,status,type])
 const patch=(k,v)=>setForm(x=>({...x,[k]:v}))
 const submit=async e=>{e.preventDefault();setBusy(true);try{await rpc('manual_pim_candidate_register',{p_entity_type:form.entity_type,p_target_provider_id:form.target_provider_id||null,p_source_kind:form.source_kind,p_external_identifier:form.external_identifier||null,p_source_url:form.source_url||null,p_evidence_id:form.evidence_id||null,p_candidate_payload:{surface:'manual_pim_candidate_workspace'},p_reason:form.reason});setForm(x=>({...x,external_identifier:'',source_url:'',evidence_id:'',reason:'Register source-backed candidate for governed acquisition/reconciliation.'}));await load()}catch(err){onError?.(err)}finally{setBusy(false)}}
 const decide=async(id,action)=>{const reason=window.prompt(`${human(action)} candidate — reason`,'Governed PIM candidate decision');if(!reason)return;setBusy(true);try{await rpc('manual_pim_candidate_decide',{p_candidate_id:id,p_action:action,p_reason:reason});await load()}catch(err){onError?.(err)}finally{setBusy(false)}}
 if(resolvedRank<5)return <section className="m-panel"><h2>Source-backed PIM candidates</h2><p>PIM Operator rank 5 or higher is required.</p></section>
 return <div className="m-page-stack">
  <section className="m-panel">
   <div className="m-workspace-head"><div><h2>Add source-backed candidate</h2><p>Provider, Course, Campus and Scholarship records remain candidates until governed source validation and reconciliation succeed. This form never writes canonical catalogue tables or publishes records.</p></div></div>
   <form className="m-form-grid" onSubmit={submit}>
    <label>Entity type<select value={form.entity_type} onChange={e=>patch('entity_type',e.target.value)}>{['provider','course','campus','scholarship'].map(x=><option key={x} value={x}>{human(x)}</option>)}</select></label>
    <label>Source authority<select value={form.source_kind} onChange={e=>patch('source_kind',e.target.value)}><option value="authority">Regulatory / authoritative</option><option value="first_party">Provider first-party</option></select></label>
    {form.entity_type!=='provider'&&<label>Canonical Provider ID<input value={form.target_provider_id} onChange={e=>patch('target_provider_id',e.target.value)} required placeholder="Provider UUID"/></label>}
    <label>Source identifier<input value={form.external_identifier} onChange={e=>patch('external_identifier',e.target.value)} placeholder="Stable/regulatory identifier where available"/></label>
    <label>Official source URL<input value={form.source_url} onChange={e=>patch('source_url',e.target.value)} placeholder="https://…"/></label>
    <label>Existing Evidence ID<input value={form.evidence_id} onChange={e=>patch('evidence_id',e.target.value)} placeholder="Optional when source URL is supplied"/></label>
    <label style={{gridColumn:'1/-1'}}>Reason<input value={form.reason} onChange={e=>patch('reason',e.target.value)} required/></label>
    <button className="m-primary" disabled={busy}>Register candidate</button>
   </form>
   <p className="m-help">Course, Campus and Provider-owned Scholarship candidates require a canonical Provider. Ambiguous identity should be sent to review; canonical Apply remains inside the existing acquisition/reconciliation path.</p>
  </section>
  <section className="m-panel">
   <div className="m-workspace-head"><div><h2>Candidate queue</h2><p>Review state is auditable and separate from canonical identity and publication.</p></div><button className="m-secondary compact" onClick={load} disabled={busy}>Refresh</button></div>
   <div className="m-filter-bar"><label>Status<select value={status} onChange={e=>setStatus(e.target.value)}><option value="">All</option>{['submitted','validated','needs_review','ready_for_acquisition','rejected','cancelled'].map(x=><option key={x} value={x}>{human(x)}</option>)}</select></label><label>Entity<select value={type} onChange={e=>setType(e.target.value)}><option value="">All</option>{['provider','course','campus','scholarship'].map(x=><option key={x} value={x}>{human(x)}</option>)}</select></label></div>
   <div className="dense-table-wrap"><table className="dense-table"><thead><tr><th>Entity</th><th>Source</th><th>Identifier</th><th>Status</th><th>Created</th><th>Actions</th></tr></thead><tbody>{items.length?items.map(x=><tr key={x.id}><td>{human(x.entity_type)}{x.target_provider_id&&<small style={{display:'block'}}>Provider {x.target_provider_id}</small>}</td><td>{human(x.source_kind)}<small style={{display:'block'}}>{x.source_url||`Evidence ${x.evidence_id||'—'}`}</small></td><td>{x.external_identifier||'—'}</td><td>{human(x.status)}</td><td>{when(x.created_at)}</td><td><div style={{display:'flex',gap:5,flexWrap:'wrap'}}>{x.status==='submitted'&&<button className="m-secondary compact" onClick={()=>decide(x.id,'validate')}>Validate</button>}{['submitted','validated'].includes(x.status)&&<button className="m-secondary compact" onClick={()=>decide(x.id,'review')}>Needs review</button>}{x.status==='validated'&&<button className="m-secondary compact" onClick={()=>decide(x.id,'ready')}>Ready for acquisition</button>}{!['rejected','cancelled'].includes(x.status)&&<button className="m-secondary compact" onClick={()=>decide(x.id,'reject')}>Reject</button>}</div></td></tr>):<tr><td colSpan="6">{busy?'Loading…':'No matching candidates.'}</td></tr>}</tbody></table></div>
  </section>
 </div>
}
