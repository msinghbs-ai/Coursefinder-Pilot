// CF-247 RM1A-1 (O29, Admin destination data design v1.1 §6): the Recognition card in the course detail summary. It shows the course's
// registrations (CRICOS, NZQA and others) with their status, dates and source, which of them Website API v3 serves as recognition[], and why
// one is held. Read only: public.admin_course_recognition_read (any StudySearch role). Registrations are kept current by Layer 1, not here.
import React,{useEffect,useState}from'react'
import{ExternalLink}from'lucide-react'
import{StatusChip}from'./ui-kit'
import{supabase}from'./lib/supabase'
import{fmtDate}from'./lib/format.js'
// the summary's card markup (DetailSummary FactCard), repeated here so DetailSummary can import this file without an import cycle
function FactCard({label,value,sub,children,tone='',id}){return <div className={`ds-card${tone?' tone-'+tone:''}`} data-ds-card={id||label}>
  <small>{label}</small>{value!=null&&<strong>{value}</strong>}{children&&<div className="ds-card-body">{children}</div>}{sub&&<span className="ds-sub">{sub}</span>}</div>}

const HELD={registration_dates_inconsistent:'Held: the registration is active but its end date has passed. Layer 1 (F-DISC) reconciles it.',
  registration_source_missing:'Held: the registration has no active public source.'}

export default function CourseRecognition({courseId,client=null}){
  const[d,setD]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{if(!courseId)return;let live=true
    const call=client?client('admin_course_recognition_read',{p_course_id:courseId}):supabase.rpc('admin_course_recognition_read',{p_course_id:courseId})
    Promise.resolve(call).then(({data,error})=>{if(!live)return;if(error)setErr(error.message||'Not available');else setD(data)}).catch(e=>{if(live)setErr(String(e?.message||e))})
    return()=>{live=false}},[courseId])
  if(!courseId)return null
  if(err)return <FactCard id="recognition" label="Recognition" value="Not measured" sub={err} tone="warning"/>
  if(!d)return <FactCard id="recognition" label="Recognition" value="…"/>
  const regs=d.registrations||[],served=d.served||[]
  const value=served.length?served.map(x=>`${x.scheme} ${x.code}`).join(', '):'None served'
  const sub=d.held_reason?HELD[d.held_reason]||d.held_reason:!served.length?(regs.length?'No registration is in a scheme Website v3 serves yet (CRICOS only).':'No registration held.'):`Website v3 course detail${served[0]?.checked_on?` · register checked ${fmtDate(served[0].checked_on)}`:''}`
  return <FactCard id="recognition" label="Recognition (Website v3)" value={value} sub={sub} tone={d.held_reason?'warning':''}>
    {regs.length>0&&<span className="ds-pill-list" data-recognition-registrations>{regs.map((r,i)=><StatusChip key={i} tone={r.on_website_v3?'success':r.status==='active'?'neutral':'danger'}
      label={`${String(r.scheme||'').toUpperCase()} ${r.code}${r.status!=='active'?` (${r.status})`:''}`}
      title={[r.source_label,r.valid_to?`ends ${fmtDate(r.valid_to)}`:null,r.captured_at?`evidence ${fmtDate(r.captured_at)}`:null,r.on_website_v3?'served on Website v3':'not served on Website v3'].filter(Boolean).join(' · ')}/>)}
      {regs.find(r=>r.source_url)&&<a className="cf-link" href={regs.find(r=>r.source_url).source_url} target="_blank" rel="noreferrer">Register <ExternalLink size={11}/></a>}</span>}
  </FactCard>
}
