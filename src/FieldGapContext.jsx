// CF-247 s931 (Decision 279 §6, D5): the record and role a FieldGap pill needs on Course detail, and Add official URL: https only, on the provider's own
// host, for Curator (rank 3) and above, saved through the course editor's own set_official_url action (public.admin_course_edit).
import React,{createContext,useContext}from'react'
import{supabase,adminRead}from'./lib/supabase'
import{FieldGap}from'./ui-kit'
import{gapStateOf,officialUrlProblem}from'./lib/field-gap.js'

export const GapCtx=createContext({rank:0,data:null,onChanged:null})
export function useAddUrl(){const{rank,data,onChanged}=useContext(GapCtx)
  if(!data?.id||Number(rank)<3)return null
  return async url=>{const pd=data.provider_id?await adminRead('provider_detail',{id:data.provider_id}).catch(()=>null):null,m=officialUrlProblem(url,pd?.website)
    if(m)return m
    const{data:r,error}=await supabase.rpc('admin_course_edit',{p_course_id:data.id,p_action:'set_official_url',p_args:{url,reason:'Official course page added from the "No official website / course URL on file" pill'}})
    if(error)return error.message;if(r&&r.ok===false)return r.error||r.message||'Not saved';onChanged?.();return ''}}
/** The gap of one course field from what Course detail already holds. */
export const courseGap=(field,data)=>gapStateOf(field,{review:Number(data?.layer4_pending?.[field])||0,url:data?.course_url||'',emptyReason:data?.empty_reason_code,
  valueState:(data?.field_states||[]).find?.(s=>s?.field_key===field||s?.field===field)?.value_state})
/** The pill of one empty course field (with Add official URL where it applies). */
export function CourseGap({field}){const{data}=useContext(GapCtx),add=useAddUrl();if(!data)return null
  return <FieldGap gap={courseGap(field,data)} canAct={!!add} onAddUrl={add}/>}
