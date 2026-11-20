// CF-247 S1-UX s826 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24): Layer 4 › Inbox, "Waiting, grouped by rule" — a left-hand panel that groups the
// cards on this page by the check that holds them (course and university descriptions by their hold code, other kinds by the first clause of their
// reason), largest first. Preview the batch lists a group's cards; Show only these narrows the list to them, so a recurring pattern is worked through
// in one pass. It reads nothing and decides nothing: every card keeps S1-RM-Design's single-record card and action bar (s819-s821, Pilot PR 1411), and
// a server-checked group is decided in one step on Grid › Grouped decisions (s646). Shown only when it groups something.
import React,{useMemo,useState}from'react'
import{Layers}from'lucide-react'
import{fmtNumber}from'./lib/format.js'
import{groupsWorthShowing,ruleGroups}from'./lib/ops-pulse.js'
import'./ops-pulse.css'

export default function Layer4RuleGroups({items,render}){
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
        </div>}
      </div>
    </aside>
    <div className="l4r-cards" data-l4-rule-shown={shown.length}>{shown.map(render)}</div>
  </div>
}
