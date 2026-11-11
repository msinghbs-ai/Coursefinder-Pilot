// CF-247 F-AER.08 step 3 (Platform Admin 11 Nov 2026, decision 2 "Code, title, then AI match, with verification"): the course labels an entry table prints
// for a university, each linked to one of its catalogue courses (by the CRICOS code on the row, by the exact title with a level the label names, or by a
// person here). A label with no single match waits here with suggested courses: suggestions only, nothing is linked until a person chooses. The label's
// waiting rows take the decision; a row whose course is not linked cannot be admitted (D-R3).
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Loading}from'./ui-kit'

const call=async(fn,args)=>{const{data,error}=await supabase.rpc(fn,args);if(error)throw new Error(error.message);return data||{}}
const METHOD={cricos:'CRICOS code on the row',title:'exact title and level',person:'a person'}

export function linkSummary(counts){const c=counts||{},n=k=>Number(c[k]||0)
  return`${n('confirmed')} linked · ${n('unresolved')} waiting for a person${n('rejected')?` · ${n('rejected')} with no catalogue course`:''}`}

export default function AerCourseLinks({providerId,rank,onDecided}){
  const[data,setData]=useState(null),[rev,setRev]=useState(0),[all,setAll]=useState(false)
  useEffect(()=>{if(!providerId)return;setData(null);call('admin_entry_course_links',{p_provider:providerId,p_state:all?null:'unresolved'}).then(setData).catch(e=>setData({error:e.message}))},[providerId,rev,all])
  if(!providerId)return null
  if(!data)return <Loading compact/>
  if(data.error)return <p className="l4i-err" role="alert">{data.error}</p>
  const links=data.links||[]
  return <details className="l4i-hook" data-l4-course-links open={Number(data.counts?.unresolved||0)>0||undefined}>
    <summary>Course links: {linkSummary(data.counts)}</summary>
    <p className="l4i-why"><small>Each course this table prints must be one of the university's catalogue courses before its rows can be admitted. Links by the CRICOS code or the exact title and level are made by the platform; the rest are chosen here. Suggestions are only suggestions.</small></p>
    <label className="l4i-why"><small><input type="checkbox" checked={all} onChange={e=>setAll(e.target.checked)} data-l4-course-links-all/> Show linked courses too</small></label>
    {links.length===0?<p className="l4i-why" data-l4-course-links-none><small>{all?'No course labels yet.':'No course waits for a person.'}</small></p>:
      <ul className="l4i-sample" data-l4-course-link-list>{links.map(l=><LinkRow key={l.id} l={l} rank={rank} onDone={()=>{setRev(v=>v+1);onDecided?.()}}/>)}</ul>}
  </details>
}

function LinkRow({l,rank,onDone}){
  const[pick,setPick]=useState(''),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState(''),[other,setOther]=useState('')
  const cands=Array.isArray(l.candidates)?l.candidates:[],waiting=l.state==='unresolved',low=rank<3
  const course=pick==='other'?other.trim():pick
  const save=async none=>{setBusy(true);setErr('');try{await call('admin_entry_course_link_decide',{p_link:l.id,p_course:none?null:course,p_reason:reason});onDone()}catch(e){setErr(e.message)}finally{setBusy(false)}}
  return <li data-l4-course-link={l.id} data-l4-course-link-state={l.state}>
    <strong>{l.label}</strong>{l.cricos&&<small> · CRICOS {l.cricos}</small>}<small> · {l.waiting_rows} waiting row{l.waiting_rows===1?'':'s'}</small>
    {l.state==='confirmed'&&<small> · linked to <em>{l.course}</em>{l.course_code?` (${l.course_code})`:''} by {METHOD[l.method]||l.method}</small>}
    {l.state==='rejected'&&<small> · no catalogue course ({l.reason})</small>}
    {l.evidence?.quote&&<q>{l.evidence.quote}</q>}
    {waiting&&<div className="l4i-confirm" data-l4-course-link-choose>
      {cands.length>0?cands.map(c=><label key={c.course_id} className="l4i-why"><input type="radio" name={`cl-${l.id}`} checked={pick===c.course_id} onChange={()=>setPick(c.course_id)} disabled={low} data-l4-course-link-pick={c.course_id}/> {c.title}{c.code?` (${c.code})`:''}{c.level?` · ${c.level}`:''}<small> · suggested: {c.why}{c.overlap!=null?`, ${Math.round(Number(c.overlap)*100)}% of title words shared`:''}</small></label>)
        :<p className="l4i-why"><small>No catalogue course shares enough of this title.</small></p>}
      <label className="l4i-why"><input type="radio" name={`cl-${l.id}`} checked={pick==='other'} onChange={()=>setPick('other')} disabled={low}/> Another course of this university (its catalogue id)</label>
      {pick==='other'&&<input value={other} onChange={e=>setOther(e.target.value)} placeholder="Course id from the course record" aria-label="Course id" data-l4-course-link-other/>}
      <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why (kept with the decision)" aria-label="Reason" disabled={low}/>
      <Button compact variant="primary" disabled={low||busy||!course||reason.trim().length<5} onClick={()=>save(false)} data-l4-course-link-save>{busy?'Saving…':'Link this course'}</Button>
      <Button compact disabled={low||busy||reason.trim().length<5} onClick={()=>save(true)} data-l4-course-link-none>No catalogue course</Button>
      {low&&<small> Layer 4 reviewer (rank 3) or above decides.</small>}
      {err&&<p className="l4i-err" role="alert">{err}</p>}
    </div>}
  </li>
}
