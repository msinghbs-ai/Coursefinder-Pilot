// CF-247 S831 (S1-AER, Platform Admin 20 Nov 2026 11:55 AEDT, item 4): the rule checks of one AER course entry read, shown in the Source quote drawer.
// Read only (public.layer4_aer_review_read, the same read the Inbox card uses). It shows what the rules already say; it decides nothing and changes no gate.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Loading}from'./ui-kit'

export const ruleChecks=aer=>{
  const rows=(aer?.rows||[]).filter(r=>r.status==='proposed'),gate=aer?.completeness_gate
  const quoted=rows.length>0&&rows.every(r=>String(r.quote||'').trim().length>0)
  const own=gate?!((gate.other_programme||[]).length||(gate.shared_page||[]).length):null
  return[
    {key:'quote',label:'Every waiting row has an exact quote from the stored page',state:rows.length?(quoted?'pass':'fail'):'none',detail:rows.length?`${rows.length} waiting row${rows.length===1?'':'s'}`:'No row waits'},
    {key:'identity',label:'The stored page is this course’s own page (no other programme shares it)',state:own==null?'none':own?'pass':'fail',detail:own===false?'The page is also the page of another programme':''},
    {key:'completeness',label:'Completeness gate: every printed requirement is accounted for',state:gate?(gate.complete===true?'pass':'fail'):'none',detail:gate&&gate.complete===false?(gate.reasons||[]).join('; '):''},
    {key:'overwrite',label:'No admitted row or manual lock is overwritten',state:'approval',detail:'The server checks this again when a person approves'},
  ]
}
const WORD={pass:'Passes',fail:'Does not pass',none:'Not available',approval:'Checked on approval'}
export default function AerRuleChecks({id}){
  const[aer,setAer]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{setAer(null);setErr('');supabase.rpc('layer4_aer_review_read',{p_review_item_id:id}).then(({data,error})=>{if(error)throw new Error(error.message);setAer(data||{})}).catch(e=>setErr(e.message))},[id])
  if(err)return <p className="l4g-err" role="alert">{err}</p>
  if(!aer)return <Loading compact/>
  if(aer.kind!=='course_entry_first_read')return <p className="l4g-muted">Rule checks are shown for a course entry read.</p>
  return <ul className="l4i-checks" data-l4-rule-checks>{ruleChecks(aer).map(c=><li key={c.key} data-l4-check={c.key} data-state={c.state}><strong>{WORD[c.state]}</strong> · {c.label}{c.detail&&<small> · {c.detail}</small>}</li>)}</ul>
}
