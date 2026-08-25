import React,{useEffect,useState}from'react'
import{createRoot}from'react-dom/client'
import{GraduationCap,Search,X,ExternalLink}from'lucide-react'
import{supabase,api}from'./lib/supabase'
import'./scholarship-selection.css'

const host=document.getElementById('scholarship-selection-root')
const root=host?createRoot(host):null
const rpc=async(courseId)=>{const{data,error}=await supabase.rpc('scholarship_selection_for_course',{p_course_id:courseId});if(error)throw error;return data}

function Entry(){const[rank,setRank]=useState(0),[open,setOpen]=useState(false)
 useEffect(()=>{let live=true;const load=async()=>{try{const{data}=await supabase.auth.getSession();if(!data.session){if(live)setRank(0);return}const c=await api.context();if(live)setRank(Number(c?.role_rank||0))}catch{}};load();const{data}=supabase.auth.onAuthStateChange(load);return()=>{live=false;data.subscription.unsubscribe()}},[])
 if(rank<3)return null
 return <><button className="ss-launcher" onClick={()=>setOpen(true)}><GraduationCap size={15}/>Scholarship Selection</button>{open&&<Workspace onClose={()=>setOpen(false)}/>}</>}

function Workspace({onClose}){const[courseId,setCourseId]=useState(''),[data,setData]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState('')
 const run=async()=>{setBusy(true);setError('');setData(null);try{setData(await rpc(courseId.trim()))}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 return <div className="ss-shell" role="dialog" aria-label="Scholarship Selection"><header><div><small>M2.3 · CF-CHG-20260825-036</small><h1>Scholarship Selection</h1><p>Decision support only. Structural relevance never proves student eligibility.</p></div><button onClick={onClose}><X size={18}/></button></header><main><section className="ss-panel"><label>Course ID<input aria-label="Course ID" value={courseId} onChange={e=>setCourseId(e.target.value)} placeholder="Canonical course UUID"/></label><button className="ss-primary" disabled={busy||!courseId.trim()} onClick={run}><Search size={14}/>{busy?'Checking…':'Find scholarship candidates'}</button>{error&&<div className="ss-error">{error}</div>}</section>{data&&<><section className="ss-contract"><strong>{data.course_title}</strong><span>{data.provider_name}</span><em>Eligibility inference permitted: {data.eligibility_inference_permitted?'YES':'NO'}</em></section><div className="ss-list">{(data.candidates||[]).length===0?<div className="ss-empty">No structurally relevant scholarship candidates were returned.</div>:(data.candidates||[]).map(c=><article key={c.scholarship_id}><div className="ss-row"><div><strong>{c.name}</strong><span>{c.selection_state} · eligibility {c.eligibility_state}</span></div><b>{c.derived_score?.scope_fit_score??0}</b></div><div className="ss-grid"><section><h2>SOURCE FACT</h2><p>{c.source_fact?.award_value_text||'No award value recorded'}</p><small>Audience {c.source_fact?.audience||'—'} · matched scopes {c.source_fact?.matched_scope_count??0}/{c.source_fact?.scope_count??0}</small>{c.source_fact?.source_url&&<a href={c.source_fact.source_url} target="_blank" rel="noreferrer">Open source <ExternalLink size={12}/></a>}</section><section><h2>DERIVED SCORE</h2><p>{c.derived_score?.scope_fit_score??0} / 100 structural fit</p><small>{c.derived_score?.meaning}</small></section><section><h2>MISSING / UNRESOLVED</h2><p>{c.missing_unresolved?.reason}</p><small>{c.missing_unresolved?.non_machine_evaluable_count??0} mandatory criterion/criteria require human interpretation.</small></section></div></article>)}</div></>}</main></div>}

if(root)root.render(<Entry/>)
