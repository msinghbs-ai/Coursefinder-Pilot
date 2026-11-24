// CF-247 s931 (Decision 279; spec admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md §4.1, §5.5): Advanced filters (N), closed by default.
// It hosts the controls that moved off the old second toolbar row, with the same state and server arguments: View (Review by rule, By university,
// By kind, Grid, Decided, Groups), the AER order (Ready to decide first or All waiting). Grid's own
// Provider type, Reason contains, Order, Saved views and Tools stay in the Grid (shown when View = Grid). N counts the advanced filters that are set;
// a set filter also shows as a removable chip under the primary row. No new server call.
import React from'react'
import{SlidersHorizontal,X}from'lucide-react'

export const VIEWS=[['focus','Review by rule'],['university','By university'],['kind','By kind'],['grid','Grid'],['decided','Decided'],['group','Groups']]
/** The advanced filters that are set: [key, chip text, clear]. */
export function advancedSet({view,readyFirst,aerOrder}){const out=[]
  if(view&&view!=='focus')out.push(['view',`View: ${(VIEWS.find(v=>v[0]===view)||[])[1]||view}`])
  if(aerOrder&&!readyFirst)out.push(['aer','AER: All waiting'])
  return out}

export default function Layer4AdvancedFilters({open,onToggle,view,onView,readyFirst,onReadyFirst,aerOrder=false,readyCount=0,onClear}){
  const set=advancedSet({view,readyFirst,aerOrder}),n=set.length
  return <div className="l4a" data-l4-advanced>
    <button type="button" className={`l4i-other-toggle${open?' open':''}`} aria-expanded={open} onClick={onToggle} data-l4-other-views data-l4-advanced-toggle><SlidersHorizontal size={14}/> Advanced filters ({n})</button>
    {n>0&&<span className="l4a-chips" data-l4-advanced-chips>{set.map(([k,t])=><button key={k} type="button" className="l4a-chip" onClick={()=>onClear(k)} aria-label={`Remove ${t}`} data-l4-advanced-chip={k}><X size={12}/> {t}</button>)}</span>}
    {open&&<div className="l4a-panel" role="group" aria-label="Advanced filters" data-l4-advanced-panel>
      <div className="l4a-row"><small>View</small><div className="l4i-view" role="group" aria-label="View">{VIEWS.map(([v,l])=><button key={v} type="button" className={`l4i-other${view===v?' on':''}`} aria-pressed={view===v} onClick={()=>onView(v)} data-l4-view={v}>{l}</button>)}</div></div>
      {aerOrder&&<div className="l4a-row"><small>AER</small><div className="l4i-view" role="group" aria-label="Order" data-l4-aer-order>
        <button type="button" className={readyFirst?'on':''} aria-pressed={readyFirst} onClick={()=>onReadyFirst(true)} data-l4-aer-ready-first>Ready to decide ({readyCount})</button>
        <button type="button" className={!readyFirst?'on':''} aria-pressed={!readyFirst} onClick={()=>onReadyFirst(false)} data-l4-aer-all>All waiting</button></div></div>}
      {view==='grid'&&<p className="l4a-row"><small>Provider type, Reason contains, Order, Saved views and Tools are on the Grid below.</small></p>}
      <div className="l4a-row l4a-end"><button type="button" className="m-secondary compact" onClick={()=>onClear('all')} data-l4-advanced-clear>Clear advanced</button><button type="button" className="m-secondary compact" onClick={onToggle}>Close</button></div>
    </div>}
  </div>
}
