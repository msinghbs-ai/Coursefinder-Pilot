// s892 (20 Nov 2026, CF-247 session S1-CourseLink-2027-CRICOS, Platform Admin 22:58 AEDT): Layer 4 Review › By university, Preview & Settle Batch on a rule group
// of one queue that can be settled in a batch (settleChoices: Course link and the other queues with a one-click decision; never entry requirements, departures or
// descriptions): one decision, one reason and a typed SETTLE n, then one decide per card at the person's own rank, as on Review by rule (s874).
import React,{useState}from'react'
import{fmtNumber}from'./lib/format.js'
import{settleChoices}from'./lib/l4-rules.js'
import{supabase}from'./lib/supabase'

const decide=async args=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:'decide',p_args:args});if(error)throw new Error(error.message);if(data&&data.ok===false)throw new Error(data.request||'more is needed');return data}

/** s892: one decision for every card of a group, confirmed by typing SETTLE n; each card is decided on its own. */
export function SettleBox({list,choices,onDone}){
  const[pick,setPick]=useState(''),[why,setWhy]=useState(''),[typed,setTyped]=useState(''),[run,setRun]=useState(null)
  const n=list.length,word=`SETTLE ${n}`,sc=choices.find(c=>c.key===pick)
  const go=async()=>{let ok=0;const failed=[];setRun({ok,failed,busy:true})
    for(const it of list){try{await decide({kind:it.kind,ref:it.ref,choice:sc.key,reason:why.trim(),value:''});ok++}catch(e){failed.push({ref:it.ref,subject:it.subject,error:e.message})}setRun({ok,failed:[...failed],busy:true})}
    setRun({ok,failed,busy:false});onDone?.({batch:true,admitted:ok,failed:failed.length})}
  if(!choices.length||!n)return null
  return <div className="l4r-settle" data-l4-uni-settle>
    <p className="l4r-sub"><strong>Preview &amp; Settle Batch</strong>: one decision for these {fmtNumber(n)} card{n===1?'':'s'}; each is decided on its own, with your reason.</p>
    <select value={pick} onChange={e=>{setPick(e.target.value);setTyped('')}} aria-label="Decision for every card" data-l4-settle-choice><option value="">Choose one decision…</option>{choices.map(c=><option key={c.key} value={c.key}>{c.label}</option>)}</select>
    {sc?.returns&&<p className="l4r-sub" data-l4-settle-returns>{sc.returns}</p>}
    <input value={why} onChange={e=>setWhy(e.target.value)} placeholder="Why (kept with every decision)" aria-label="Reason for the batch" data-l4-settle-reason/>
    <input value={typed} onChange={e=>setTyped(e.target.value)} placeholder={`Type ${word} to confirm`} aria-label="Type the confirmation" data-l4-settle-typed/>
    <button type="button" className="op-btn sm" disabled={!sc||why.trim().length<5||typed.trim()!==word||run?.busy} onClick={go} data-l4-settle-go>Settle {fmtNumber(n)}: {sc?.label||'…'}</button>
    {run&&<p className="l4r-sub" role="status" data-l4-settle-run>{run.busy?'Settling… ':''}{fmtNumber(run.ok)} settled{run.failed.length?`, ${fmtNumber(run.failed.length)} not settled (${run.failed[0].error})`:''}</p>}
  </div>
}


/** The settle box for a previewed group, when its cards are of one queue that can be settled. */
export function settleFor(pv,kinds,onDone){const ks=[...new Set((pv?.items||[]).map(it=>it.kind))]
  return ks.length===1?<SettleBox key={pv.key} list={pv.items} choices={settleChoices(ks[0],kinds?.[ks[0]]?.choices)} onDone={onDone}/>:null}
