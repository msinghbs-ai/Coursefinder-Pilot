import React,{useEffect,useMemo,useState}from'react'
import{createRoot}from'react-dom/client'
import{AlertTriangle,CheckCircle2,RefreshCw,Repeat2,ShieldCheck}from'lucide-react'
import{supabase}from'./lib/supabase'
import'./layer4-mass-operations.css'

const rpc=async(name,args={})=>{const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}
const count=v=>Number(v||0).toLocaleString()
const when=v=>v?new Date(v).toLocaleString():'Never'

function ScopeRules(){
 const[groups,setGroups]=useState([]),[rules,setRules]=useState([]),[busy,setBusy]=useState(false),[error,setError]=useState(''),[selected,setSelected]=useState(''),[decision,setDecision]=useState(''),[reason,setReason]=useState(''),[confirmation,setConfirmation]=useState('')
 const load=async()=>{setBusy(true);setError('');try{const[g,r]=await Promise.all([rpc('layer4_scholarship_scope_groups',{p_limit:200}),rpc('layer4_scope_rules_read',{p_limit:200})]);setGroups(Array.isArray(g)?g:[]);setRules(Array.isArray(r)?r:[])}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 useEffect(()=>{load()},[])
 const group=useMemo(()=>groups.find(x=>x.group_id===selected)||null,[groups,selected])
 const save=async()=>{if(!group||!decision||reason.trim().length<8||!confirmation.trim())return;setBusy(true);setError('');try{const r=await rpc('layer4_scope_rule_save',{p_scholarship_id:group.scholarship_id,p_candidate_reason:group.candidate_reason,p_decision:decision,p_reason:reason,p_confirmation:confirmation});setSelected('');setDecision('');setReason('');setConfirmation('');await load();if(r?.rule_id&&window.confirm(`Reusable ${decision} rule saved. Apply it to the current ${r.cohort_count} candidate cohort now?`)){await rpc('layer4_scope_rule_apply',{p_rule_id:r.rule_id,p_limit:5000});await load()}}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 const apply=async r=>{if(!window.confirm(`Apply this ${r.decision} rule to all current matching candidates?`))return;setBusy(true);setError('');try{await rpc('layer4_scope_rule_apply',{p_rule_id:r.id,p_limit:5000});await load()}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 const state=async r=>{const next=!r.enabled;const why=window.prompt(`${next?'Enable':'Disable'} reusable rule — reason`,'Eligibility rule maintenance');if(!why||why.trim().length<8)return;setBusy(true);setError('');try{await rpc('layer4_scope_rule_set_state',{p_rule_id:r.id,p_enabled:next,p_reason:why});await load()}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 return <section className="cf-l4mass" data-cf-layer4-scope-rules>
  <div className="cf-l4mass-head"><div><small>CF-206 · evidence-bound reuse</small><h2>Reusable Scholarship scope rules</h2><p>Cross-check once, save one governed rule, and automatically reuse it only while the Scholarship, Provider, candidate reason and first-party Evidence version remain identical.</p></div><button onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Refreshing…':'Refresh'}</button></div>
  {error&&<div className="cf-l4mass-error"><AlertTriangle size={14}/>{error}</div>}
  <div className="cf-l4mass-cards"><article><strong>{count(rules.filter(x=>x.enabled).length)}</strong><span>Enabled reusable rules</span><small>Exact Evidence-bound matches only</small></article><article><strong>{count(rules.reduce((n,x)=>n+Number(x.apply_count||0),0))}</strong><span>Automatically resolved rows</span><small>Across retained rule history</small></article><article><strong>{count(groups.length)}</strong><span>Cohorts still requiring review</span><small>Changed Evidence always returns here</small></article></div>
  <div className="cf-l4mass-note"><ShieldCheck size={14}/>A saved rule is deliberately invalidated by a new Evidence ID. Refreshing or changing the Scholarship source cannot silently inherit yesterday's decision.</div>
  <div className="cf-l4mass-decision">
   <div className="cf-l4mass-row"><div><strong>Create from reviewed cohort</strong><span>No Course-by-Course rule authoring.</span></div></div>
   <div className="cf-l4mass-form"><label>Cohort<select value={selected} onChange={e=>{setSelected(e.target.value);setConfirmation('')}}><option value="">Choose a reviewed cohort</option>{groups.map(g=><option key={g.group_id} value={g.group_id}>{g.provider_name} · {g.scholarship_name} · {g.candidate_count} courses</option>)}</select></label><label>Reusable decision<select value={decision} onChange={e=>setDecision(e.target.value)}><option value="">Choose decision</option><option value="accept" disabled={!group?.structural_ready}>Accept matching candidates</option><option value="reject">Reject matching candidates</option></select></label><label>Audited rule reason<textarea value={reason} onChange={e=>setReason(e.target.value)} placeholder="What first-party rule did you cross-check?"/></label><label>Confirmation<input value={confirmation} onChange={e=>setConfirmation(e.target.value)} placeholder={group?`SAVE RULE ${group.candidate_count}`:'Choose cohort first'}/></label></div>
   {group&&<><div className="cf-l4mass-meta"><span>Evidence {group.evidence_count}/{group.candidate_count}</span><span>Provider mismatch {group.provider_mismatch_count}</span><span>Study levels {group.study_level_count}</span>{group.semantic_warning&&<span className="warn">Eligibility/exclusion warning — inspect source before saving</span>}</div><small>Sample: {(group.sample_courses||[]).join(' · ')}</small></>}
   <div className="cf-l4mass-actions"><button className="primary" disabled={busy||!group||!decision||reason.trim().length<8||confirmation!==`SAVE RULE ${group?.candidate_count||0}`} onClick={save}><Repeat2 size={13}/>Save reusable rule</button></div>
  </div>
  <h3>Rule registry</h3>
  <div className="cf-l4mass-list">{rules.length===0?<article><strong>No reusable rules yet</strong><span>Create one only after the cohort source/eligibility rule has been cross-checked.</span></article>:rules.map(r=><article key={r.id} className={r.enabled?'':'blocked'}><div className="cf-l4mass-row"><div><strong>{r.scholarship_name}</strong><span>{r.provider_name}</span></div><span className="cf-l4mass-pill">{r.enabled?'Enabled':'Disabled'} · {r.decision}</span></div><p>{r.rule_reason}</p><div className="cf-l4mass-meta"><span>Applied {count(r.apply_count)} rows</span><span>Last used {when(r.last_applied_at)}</span><span>Evidence {String(r.evidence_id).slice(0,8)}…</span></div><small>{r.candidate_reason}</small><div className="cf-l4mass-actions"><button onClick={()=>apply(r)} disabled={busy||!r.enabled}><CheckCircle2 size={13}/>Apply to current matches</button><button onClick={()=>state(r)} disabled={busy}>{r.enabled?'Disable rule':'Enable rule'}</button></div></article>)}</div>
 </section>
}

let node=null,root=null,pending=false
function mount(){const active=location.hash.includes('layer-4-human-resolution')||location.hash.includes('layer-4-review');if(!active)return;if(node?.isConnected)return;const host=document.querySelector('[data-cf-layer4-mass-operations]');if(!host)return;node=document.createElement('div');node.dataset.cfLayer4RulesMount='true';host.insertAdjacentElement('afterend',node);root=createRoot(node);root.render(<ScopeRules/>)}
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;mount()},60)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});addEventListener('hashchange',schedule);if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
