// Decision 211: who can apply and how long the award runs, as read from the scholarship's own provider page.
// Criteria come from scholarship_detail (criteria, active rows only); each shows the page's
// own words. Read only.
import React from'react'
import{ListChecks}from'lucide-react'

const DURATION={one_off:'One-off payment',first_year:'First year only',annual:'Paid each year',annual_program_duration:'Each year, for the length of the course',program_duration:'For the length of the course',per_semester:'Paid each semester'}
const STUDENT={domestic:'Domestic students',international:'International students'}
const STAGE={commencing:'New (commencing) students',current:'Current students'}
const SOURCE={scholarship_sweep:'provider page'}

export function criterionLabel(c){
  const codes=Array.isArray(c.value_codes)?c.value_codes:[]
  switch(c.criterion_type){
    case'student_type':return ['Student type',codes.map(x=>STUDENT[x]||x).join(' and ')]
    case'study_stage':return ['Study stage',STAGE[c.value_text]||c.value_text]
    case'study_load':return ['Study load',c.value_text==='full_time'?'Full-time':c.value_text]
    case'academic_minimum':return ['Minimum result',`${c.value_text} ${c.value_number}${c.value_json?.scale?` out of ${c.value_json.scale}`:''} or higher`]
    case'gender':return ['Open to',c.value_text==='women'?'Women':'Men']
    case'nationality':return ['Citizenship',codes.join(', ')]
    case'application_method':return ['Applying',c.value_text==='automatic'?'Considered automatically (no application)':c.value_text]
    case'published_eligibility_narrative':return ['Eligibility (as published)',c.value_text||'']
    default:return [String(c.criterion_type||'').replace(/_/g,' '),c.value_text||codes.join(', ')||(c.value_number??'')]
  }
}

export default function ScholarshipEligibility({data}){
  const all=data?.criteria
  const items=(Array.isArray(all)?all:[]).filter(c=>c.status==='active')
  const dur=data?.award_duration_basis
  if(!items.length&&!dur)return null
  return <section className="se-panel" data-scholarship-eligibility>
    <h4><ListChecks size={14}/>Eligibility and award</h4>
    {dur&&<p className="se-duration"><small>Award runs</small><b>{DURATION[dur]||dur}</b></p>}
    {items.length>0?<dl className="se-list">{items.map(c=>{const[k,v]=criterionLabel(c);return <div key={c.id}><dt>{k}</dt><dd><b>{v}</b>{c.human_text&&<small title={c.human_text}>“{c.human_text}”</small>}<em>{SOURCE[c.value_json?.by]||'recorded'}</em></dd></div>})}</dl>:<small>No eligibility read from the provider page yet.</small>}
  </section>
}
