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

const HELD={not_on_latest_register_edition:'Held: this registration is not on the latest CRICOS edition. It is released by itself if a later edition lists it; its removal waits for the register departures approval.',
  registration_dates_inconsistent:'Held: the registration is active but its end date has passed. Layer 1 (F-DISC) reconciles it.',
  registration_source_missing:'Held: the registration has no active public source.'}

export default function CourseRecognition({courseId,client=null}){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[x,setX]=useState(null)
  // v2.16.19 RM0F: the registrations by scheme (never merged), the country's field-of-study scheme and the study rules proven for this course
  useEffect(()=>{if(!courseId)return;let live=true
    const call=client?client('admin_course_destination_read',{p_course_id:courseId}):supabase.rpc('admin_course_destination_read',{p_course_id:courseId})
    Promise.resolve(call).then(({data,error})=>{if(live&&!error)setX(data)}).catch(()=>{});return()=>{live=false}},[courseId])
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
  const codes=d.field_codes||[]
  const codeLine=codes.length?`ASCED ${codes.map(c=>`${c.code} ${c.name}`).join(' · ')}`:d.field_codes_held_reason?`Field codes held: ${d.field_codes_held_reason}`:'No register field code held.'
  return <FactCard id="recognition" label="Recognition (Website v3)" value={value} sub={sub} tone={d.held_reason?'warning':''}>
    {regs.length>0&&<span className="ds-pill-list" data-recognition-registrations>{regs.map((r,i)=><StatusChip key={i} tone={r.on_website_v3?'success':r.status==='active'?'neutral':'danger'}
      label={`${String(r.scheme||'').toUpperCase()} ${r.code}${r.status!=='active'?` (${r.status})`:''}`}
      title={[r.source_label,r.valid_to?`ends ${fmtDate(r.valid_to)}`:null,r.captured_at?`evidence ${fmtDate(r.captured_at)}`:null,r.on_website_v3?'served on Website v3':'not served on Website v3'].filter(Boolean).join(' · ')}/>)}
      {regs.find(r=>r.source_url)&&<a className="cf-link" href={regs.find(r=>r.source_url).source_url} target="_blank" rel="noreferrer">Register <ExternalLink size={11}/></a>}</span>}
    <span className="ds-sub" data-recognition-field-codes title="Field of education codes the national register prints, served as field_of_study_codes[] on API v3 course detail">{codeLine}</span>
    {x?.found&&<span className="ds-sub" data-recognition-schemes title="One line per scheme the course holds. Schemes are never merged or converted into one another.">{(x.registrations||[]).length?`Schemes held: ${[...new Set(x.registrations.map(r=>`${r.label||String(r.scheme).toUpperCase()}${r.authority?` (${r.authority})`:''}`))].join(' · ')}`:'No registration scheme held.'}{(x.field_schemes||[]).length?` Field scheme for ${x.country_code}: ${x.field_schemes.map(f=>`${String(f.scheme).toUpperCase()}${f.status==='planned'?' (not loaded yet)':''}`).join(', ')}.`:''}</span>}
    {x?.found&&<span className="ds-sub" data-recognition-study-rules>{(x.study_rules||[]).length?<>Study rules proven for this course: {x.study_rules.map((r,i)=><React.Fragment key={r.rule_id}>{i>0&&' · '}<a className="cf-link" href="#destination-data?tab=rules" title={`Proven through the ${r.applies_through}; rule ${r.approval_status}, edition ${r.edition_status}`}>{r.title}</a></React.Fragment>)}</>:'No study rule is proven for this course yet.'}</span>}
  </FactCard>
}
