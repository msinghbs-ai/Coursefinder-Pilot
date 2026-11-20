// CF-247 S1-UX s826 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24): Layer 4 › Inbox, "Waiting, grouped by rule" — a left-hand panel that groups the
// cards on this page by the check that holds them (course and university descriptions by their hold code, other kinds by the first clause of their
// reason), largest first. Preview the batch lists a group's cards; Show only these narrows the list to them, so a recurring pattern is worked through
// in one pass. It reads nothing and decides nothing: every card keeps S1-RM-Design's single-record card and action bar (s819-s821, Pilot PR 1411), and
// a server-checked group is decided in one step on Grid › Grouped decisions (s646). Shown only when it groups something.
// s892 (20 Nov 2026, CF-247 session S1-CourseLink-2027-CRICOS, Platform Admin 22:58): in By university, a group of one queue that can be settled in a batch
// (settleChoices: Course link and the other queues with a one-click decision; never entry requirements, departures or descriptions) has Preview & Settle Batch:
// one decision, one reason and a typed SETTLE n, then one decide per card at the person's own rank, as on Review by rule (s874).
import React,{useMemo,useState}from'react'
import{Layers}from'lucide-react'
import{fmtNumber}from'./lib/format.js'
import{groupsWorthShowing,ruleGroups}from'./lib/ops-pulse.js'
import{settleChoices}from'./lib/l4-rules.js'
import{supabase}from'./lib/supabase'
import'./ops-pulse.css'

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

export default function Layer4RuleGroups({items,render,kinds,onSettled}){
  const groups=useMemo(()=>ruleGroups(items),[items]),[rule,setRule]=useState(''),[preview,setPreview]=useState('')
  const g=groups.find(x=>x.key===rule),pv=groups.find(x=>x.key===preview)
  if(!groupsWorthShowing(groups))return <>{(items||[]).map(render)}</>
  const shown=g?g.items:items
  return <div className="l4r-wrap" data-l4-rule-groups={groups.length}>
    <aside className="l4r-side" aria-label="Waiting, grouped by rule">
      <p className="l4r-head"><Layers size={15} aria-hidden="true"/> <strong>Waiting, grouped by rule</strong></p>
      <p className="l4r-sub">The cards on this page, by the check that holds them. Preview a batch, then work through it card by card.</p>
      <button type="button" className={`l4r-grp${!rule?' on':''}`} aria-pressed={!rule} onClick={()=>{setRule('');setPreview('')}} data-l4-rule="all"><span>All on this page</span><span className="l4r-n">{fmtNumber((items||[]).length)}</span></button>
      {groups.map(x=><button key={x.key} type="button" className={`l4r-grp${rule===x.key?' on':''}`} aria-pressed={rule===x.key} onClick={()=>{setRule(x.key);setPreview(x.key)}} data-l4-rule={x.key}><span>{x.label}</span><span className="l4r-n">{fmtNumber(x.n)}</span></button>)}
      <div className="l4r-batch">
        {!pv?<p className="l4r-sub">Choose a rule to preview its batch.</p>:<div data-l4-rule-preview={pv.key}>
          <p className="l4r-sub"><strong>{pv.label}</strong>: {fmtNumber(pv.n)} card{pv.n===1?'':'s'} on this page</p>
          <ol className="l4r-list">{pv.items.slice(0,8).map(it=><li key={`${it.kind}:${it.ref}`}>{it.subject||it.provider||String(it.ref).slice(0,8)}{it.provider&&it.subject?<small> · {it.provider}</small>:null}</li>)}</ol>
          {pv.n>8&&<p className="l4r-sub">and {fmtNumber(pv.n-8)} more</p>}
          <div className="l4r-actions">
            <button type="button" className="op-btn sm" onClick={()=>setRule(pv.key)} disabled={rule===pv.key} data-l4-rule-only>{rule===pv.key?'Showing only these':`Show only these ${fmtNumber(pv.n)}`}</button>
            <a className="op-btn ghost sm" href="#layer-4-review?view=grid" data-l4-rule-grid>Grouped decisions</a>
          </div>
          {(()=>{const ks=[...new Set(pv.items.map(it=>it.kind))];return ks.length===1?<SettleBox key={pv.key} list={pv.items} choices={settleChoices(ks[0],kinds?.[ks[0]]?.choices)} onDone={onSettled}/>:null})()}
        </div>}
      </div>
    </aside>
    <div className="l4r-cards" data-l4-rule-shown={shown.length}>{shown.map(render)}</div>
  </div>
}
