import React,{useEffect,useMemo,useState}from'react'
import{createRoot}from'react-dom/client'
import{AlertTriangle,CheckCircle2,ClipboardCheck,RefreshCw,Search,ShieldCheck,Wrench}from'lucide-react'
import{supabase}from'./lib/supabase'
import'./layer4-mass-operations.css'

const rpc=async(name,args={})=>{const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}
const human=v=>String(v??'').replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase())
const when=v=>v?new Date(v).toLocaleString():'—'
const count=v=>Number(v||0).toLocaleString()

function Layer4MassOperations(){
 const[summary,setSummary]=useState({}),[groups,setGroups]=useState([]),[reviewGroups,setReviewGroups]=useState([]),[diagnostics,setDiagnostics]=useState([]),[findings,setFindings]=useState([]),[history,setHistory]=useState([])
 const[busy,setBusy]=useState(false),[error,setError]=useState(''),[query,setQuery]=useState(''),[tab,setTab]=useState('scope'),[decision,setDecision]=useState(null),[resolve,setResolve]=useState(null)
 const load=async()=>{setBusy(true);setError('');try{const[s,g,r,d,f,h]=await Promise.all([rpc('layer4_mass_summary'),rpc('layer4_scholarship_scope_groups',{p_limit:200}),rpc('layer4_review_groups',{p_limit:200}),rpc('layer4_quality_diagnostics'),rpc('layer4_quality_findings_read',{p_status:'open',p_limit:100}),rpc('layer4_mass_operations_history',{p_limit:50})]);setSummary(s||{});setGroups(Array.isArray(g)?g:[]);setReviewGroups(Array.isArray(r)?r:[]);setDiagnostics(Array.isArray(d)?d:[]);setFindings(Array.isArray(f)?f:[]);setHistory(Array.isArray(h)?h:[])}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 useEffect(()=>{load()},[])
 const filtered=useMemo(()=>groups.filter(g=>!query||[g.scholarship_name,g.provider_name,g.candidate_reason,...(g.sample_courses||[])].join(' ').toLowerCase().includes(query.toLowerCase())),[groups,query])
 const openScope=async g=>{setBusy(true);setError('');try{const p=await rpc('layer4_scholarship_scope_preview',{p_scholarship_id:g.scholarship_id,p_candidate_reason:g.candidate_reason});setDecision({kind:'scope',group:g,preview:p,action:'',reason:'',confirmation:''})}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 const openReview=g=>setDecision({kind:'review',group:g,action:'',reason:'',confirmation:''})
 const applyDecision=async()=>{if(!decision?.action||!decision?.reason||!decision?.confirmation)return;setBusy(true);setError('');try{if(decision.kind==='scope')await rpc('layer4_scholarship_scope_bulk_decide',{p_scholarship_id:decision.group.scholarship_id,p_candidate_reason:decision.group.candidate_reason,p_action:decision.action,p_reason:decision.reason,p_confirmation:decision.confirmation});else await rpc('layer4_review_bulk_decide',{p_entity_type:decision.group.entity_type,p_field_code:decision.group.field_code,p_escalation_reason:decision.group.escalation_reason||'',p_action:decision.action,p_reason:decision.reason,p_confirmation:decision.confirmation,p_limit:500});setDecision(null);await load()}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 const track=async d=>{setBusy(true);setError('');try{await rpc('layer4_quality_finding_upsert',{p_finding_type:d.type,p_domain:'layer4',p_title:d.title,p_detail:`${d.detail} ${d.recommendation||''}`.trim(),p_severity:d.severity,p_group_key:{diagnostic:d.title}});await load()}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 const resolveFinding=async()=>{if(!resolve?.id||!resolve?.note?.trim())return;setBusy(true);setError('');try{await rpc('layer4_quality_finding_resolve',{p_finding_id:resolve.id,p_status:'resolved',p_note:resolve.note});setResolve(null);await load()}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 const mutationAllowed=Boolean(summary.mass_mutation_allowed)
 return <section className="cf-l4mass" data-cf-layer4-mass-operations>
  <div className="cf-l4mass-head">
   <div><small>CF-205 · governed cohort operations</small><h2>Layer 4 mass operations</h2><p>Resolve repeatable review work by governed cohort instead of one record at a time. Every mass decision is previewed, confirmed and audited; Publication remains separate.</p></div>
   <button onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Refreshing…':'Refresh'}</button>
  </div>
  {error&&<div className="cf-l4mass-error"><AlertTriangle size={14}/>{error}</div>}
  <div className="cf-l4mass-cards">
   <article><strong>{count(summary.scholarship_scope_pending)}</strong><span>Scholarship Course-scope review</span><small>{count(summary.scholarship_scope_groups)} cohort(s)</small></article>
   <article><strong>{count(summary.generic_review_pending)}</strong><span>Generic Layer 4 review</span><small>{count(summary.generic_review_groups)} cohort(s)</small></article>
   <article><strong>{count(summary.missing_evidence+summary.provider_mismatch)}</strong><span>Structural blockers</span><small>{count(summary.missing_evidence)} missing Evidence · {count(summary.provider_mismatch)} provider mismatch</small></article>
   <article><strong>{count(summary.open_findings)}</strong><span>Tracked findings</span><small>Errors, issues and improvements</small></article>
  </div>
  <div className="cf-l4mass-tabs">{[['scope','Scholarship scope'],['review','Review queue'],['quality','Errors & improvements'],['history','Mass audit']].map(([k,l])=><button key={k} className={tab===k?'active':''} onClick={()=>{setTab(k);setDecision(null)}}>{l}</button>)}</div>
  {tab==='scope'&&<div className="cf-l4mass-body">
   <div className="cf-l4mass-toolbar"><label><Search size={14}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search university, scholarship, rule or course"/></label><span>{filtered.length} cohort(s) shown</span></div>
   <div className="cf-l4mass-list">{filtered.map(g=><article key={g.group_id} className={g.structural_ready?'':'blocked'}>
    <div className="cf-l4mass-row"><div><strong>{g.scholarship_name}</strong><span>{g.provider_name}</span></div><span className="cf-l4mass-pill">{count(g.candidate_count)} courses</span></div>
    <p>{g.candidate_reason}</p>
    <div className="cf-l4mass-meta"><span>Evidence {count(g.evidence_count)}/{count(g.candidate_count)}</span><span>Already mapped {count(g.already_mapped_count)}</span><span>Provider mismatch {count(g.provider_mismatch_count)}</span><span>Study levels {count(g.study_level_count)}</span>{g.semantic_warning&&<span className="warn">Semantic scope warning</span>}</div>
    <small>Sample: {(g.sample_courses||[]).join(' · ')||'—'}</small>
    <div className="cf-l4mass-actions"><button onClick={()=>openScope(g)}><ClipboardCheck size={13}/>Preview cohort</button></div>
   </article>)}</div>
  </div>}
  {tab==='review'&&<div className="cf-l4mass-body"><p className="cf-l4mass-note">Generic Layer 4 cohorts can be rejected or returned to Layer 2/3 in batches of up to 500. Bulk approve is intentionally not available because proposed scalar values may differ.</p><div className="cf-l4mass-list">{reviewGroups.map(g=><article key={g.group_id}><div className="cf-l4mass-row"><div><strong>{human(g.entity_type)} · {human(g.field_code)}</strong><span>{g.escalation_reason||'No escalation reason'}</span></div><span className="cf-l4mass-pill">{count(g.item_count)} items</span></div><div className="cf-l4mass-meta"><span>Missing Evidence {count(g.missing_evidence_count)}</span><span>Oldest {when(g.oldest_at)}</span></div><div className="cf-l4mass-actions"><button onClick={()=>openReview(g)}><ClipboardCheck size={13}/>Open cohort action</button></div></article>)}</div></div>}
  {tab==='quality'&&<div className="cf-l4mass-body"><div className="cf-l4mass-quality">{diagnostics.map(d=><article key={d.title} className={`sev-${d.severity}`}><div className="cf-l4mass-row"><div><strong>{d.title}</strong><span>{human(d.type)} · {human(d.severity)}</span></div><span className="cf-l4mass-pill">{count(d.count)}</span></div><p>{d.detail}</p><small>{d.recommendation}</small><div className="cf-l4mass-actions"><button onClick={()=>track(d)} disabled={busy}><Wrench size={13}/>Track finding</button></div></article>)}</div><h3>Open findings</h3><div className="cf-l4mass-list">{findings.map(f=><article key={f.id}><div className="cf-l4mass-row"><div><strong>{f.title}</strong><span>{human(f.finding_type)} · {human(f.severity)} · {human(f.status)}</span></div><span>{when(f.last_seen_at)}</span></div><p>{f.detail||'—'}</p>{resolve?.id===f.id?<div className="cf-l4mass-decision"><label>Resolution note<textarea value={resolve.note} onChange={e=>setResolve(x=>({...x,note:e.target.value}))}/></label><div className="cf-l4mass-actions"><button className="primary" onClick={resolveFinding} disabled={!resolve.note.trim()||busy}>Resolve</button><button onClick={()=>setResolve(null)}>Cancel</button></div></div>:<button onClick={()=>setResolve({id:f.id,note:''})}><CheckCircle2 size={13}/>Resolve finding</button>}</article>)}</div></div>}
  {tab==='history'&&<div className="cf-l4mass-body"><div className="cf-l4mass-list">{history.map(h=><article key={h.id}><div className="cf-l4mass-row"><div><strong>{human(h.target_kind)} · {human(h.action)}</strong><span>{h.reason}</span></div><span>{when(h.created_at)}</span></div><div className="cf-l4mass-meta"><span>Before {count(h.before_count)}</span><span>Affected {count(h.affected_count)}</span><span>{h.change_control_ref}</span></div></article>)}</div></div>}
  {decision&&<div className="cf-l4mass-decision" data-cf-layer4-mass-decision>
   <div className="cf-l4mass-row"><div><strong>{decision.kind==='scope'?decision.group.scholarship_name:`${human(decision.group.entity_type)} · ${human(decision.group.field_code)}`}</strong><span>One decision for the whole current cohort</span></div><button onClick={()=>setDecision(null)}>Close</button></div>
   {decision.kind==='scope'&&decision.preview&&<><div className="cf-l4mass-cards compact"><article><strong>{count(decision.preview.candidate_count)}</strong><span>Current cohort</span></article><article><strong>{count(decision.preview.missing_evidence_count)}</strong><span>Missing Evidence</span></article><article><strong>{count(decision.preview.provider_mismatch_count)}</strong><span>Provider mismatch</span></article><article><strong>{count(decision.preview.already_mapped_count)}</strong><span>Already mapped</span></article></div>{decision.preview.semantic_warning&&<p className="cf-l4mass-warning"><AlertTriangle size={14}/>This cohort contains eligibility/exclusion semantics. Cross-check the source and sample before mass acceptance.</p>}<div className="cf-l4mass-sample">{(decision.preview.sample||[]).map(x=><span key={x.course_id}>{x.course_title}{x.course_code?` · ${x.course_code}`:''}</span>)}</div></>}
   <div className="cf-l4mass-form"><label>Action<select value={decision.action} onChange={e=>setDecision(x=>({...x,action:e.target.value,confirmation:''}))}><option value="">Choose action</option>{decision.kind==='scope'?<><option value="accept" disabled={!decision.preview?.structural_ready}>Accept whole cohort</option><option value="reject">Reject whole cohort</option></>:<><option value="reject">Reject cohort</option><option value="request_more_evidence">Request more Evidence</option><option value="return_layer2">Return to Layer 2</option><option value="return_layer3">Return to Layer 3</option></>}</select></label><label>Reason<textarea value={decision.reason} onChange={e=>setDecision(x=>({...x,reason:e.target.value}))} placeholder="Required audited reason"/></label><label>Confirmation<input value={decision.confirmation} onChange={e=>setDecision(x=>({...x,confirmation:e.target.value}))} placeholder={decision.kind==='scope'&&decision.action?(decision.action==='accept'?decision.preview?.accept_confirmation:decision.preview?.reject_confirmation):decision.action?`${decision.action.toUpperCase()} ${Math.min(Number(decision.group.item_count||0),500)}`:'Choose action first'}/></label></div>
   {!mutationAllowed&&<p className="cf-l4mass-warning"><ShieldCheck size={14}/>Pipeline Operator role is required for mass mutation. Curators can preview and cross-check.</p>}
   <div className="cf-l4mass-actions"><button className="primary" disabled={busy||!mutationAllowed||!decision.action||decision.reason.trim().length<8||!decision.confirmation.trim()} onClick={applyDecision}>Apply audited cohort decision</button><button onClick={()=>setDecision(null)}>Cancel</button></div>
  </div>}
 </section>
}

let mountedNode=null,mountedRoot=null,pending=false
function mount(){
 const active=location.hash.includes('layer-4-human-resolution')||location.hash.includes('layer-4-review')
 if(!active){if(mountedNode&&!mountedNode.isConnected){mountedNode=null;mountedRoot=null}return}
 if(mountedNode?.isConnected)return
 const stacks=[...document.querySelectorAll('.m23-stack')]
 const host=stacks.find(x=>(x.textContent||'').includes('Layer 4'))
 if(!host)return
 const node=document.createElement('div');node.dataset.cfLayer4MassMount='true';host.prepend(node);mountedNode=node;mountedRoot=createRoot(node);mountedRoot.render(<Layer4MassOperations/>)
}
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;mount()},40)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true})
addEventListener('hashchange',schedule)
if(document.readyState==='loading')addEventListener('DOMContentLoaded',schedule,{once:true});else schedule()
