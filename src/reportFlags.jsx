// CF-247 s1285 (Reported data issues R3, SS-Programme-Control 26 Nov 2026 22:52 AEDT): the one read of the unified report view
// (public.admin_reported_issues_v1, Curator and above) and the Reported and Resolved indicators the course record drawer shows per field.
// Origins: Admin and Portal reports are the in-app store (R1, s1281); Zoho reports are the Zoho store. Nothing here closes or changes a report.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{StatusChip,fmtNumber}from'./ui-kit'

export const readReports=args=>supabase.rpc('admin_reported_issues_v1',{p_args:args||{}}).then(({data,error})=>{if(error)throw new Error(error.message);return data})
export const ORIGIN={admin:'Admin',portal:'Portal',zoho:'Zoho',unknown:'Unknown origin'}
export const originWord=o=>ORIGIN[o]||String(o||'unknown').replace(/_/g,' ')

/** The course's reports by field, read once when asked (only for Curator and above, who may open the reports). */
export function useCourseReports(courseId,rank=0,active=true){
  const[rep,setRep]=useState(null)
  useEffect(()=>{setRep(null);if(!active||!courseId||rank<3)return;readReports({mode:'course',course_id:courseId}).then(setRep).catch(e=>setRep({error:e.message}))},[courseId,rank,active])
  return rep
}

/** Reported (open reports) and Resolved (closed reports) for one field, or for the whole course when no field is given. */
export function ReportFlag({rep,field=null}){
  if(!rep||rep.error)return null
  const x=field?rep.by_field?.[field]:{open:rep.open,resolved:rep.resolved,fixed:rep.fixed,origins:[...new Set(Object.values(rep.by_field||{}).flatMap(v=>v.origins||[]))]}
  if(!x||(!Number(x.open)&&!Number(x.resolved)))return null
  const from=(x.origins||[]).map(originWord).join(', ')
  return <span className="rf-flags" data-rf-field={field||'course'}>
    {Number(x.open)>0&&<StatusChip tone="warning" label={`Reported: ${fmtNumber(Number(x.open))} open`} title={from?`From ${from}`:undefined} className="rf-reported"/>}
    {Number(x.resolved)>0&&<StatusChip tone="success" label={`Resolved: ${fmtNumber(Number(x.resolved))}${Number(x.fixed)?` (${fmtNumber(Number(x.fixed))} fixed)`:''}`} title={from?`From ${from}`:undefined} className="rf-resolved"/>}
  </span>
}
