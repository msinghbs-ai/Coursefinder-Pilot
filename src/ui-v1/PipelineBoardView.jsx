import './tokens.css'
import './ui-kit.css'
// v1.1 four-stage pipeline board (v1.2 plan, Slice 3): moved from src/OpsPulse.jsx. Reads nothing: the stored pulse comes from the caller.
import React,{useState}from'react'
import{Activity,ArrowRight,Gauge,Inbox,Landmark,LibraryBig,OctagonAlert,ScanLine,Sparkles,Wallet}from'lucide-react'
import{stageCards,flowReach}from'../lib/ops-pulse.js'
import{fmtDateTime,fmtNumber}from'../lib/format.js'
const ICONS={Activity,Gauge,Inbox,OctagonAlert,Wallet,Landmark,ScanLine,Sparkles,LibraryBig}
const Icon=({name,size=18})=>{const C=ICONS[name]||Activity;return <C size={size} aria-hidden="true"/>}
const fmt=n=>n==null?'—':fmtNumber(n)

export function Meter({pct,label}){return <span className="ui-op-meter" role="img" aria-label={label||(pct==null?'Not measured':`${pct}%`)}><i style={{width:`${pct==null?0:Math.max(2,pct)}%`}}/></span>}

export function PipelineBoard({pulse}){
  const cards=stageCards(pulse),reach=flowReach(cards),[sel,setSel]=useState(()=>{const i=cards.findIndex(c=>c.tone==='warn'||c.tone==='crit');return i===-1?0:i})
  if(!pulse)return null
  const s=cards[sel]||cards[0]
  return <div className="ui-op-board" data-pipeline-board>
    <div className="ui-op-track" aria-hidden="true"><i style={{width:`${(reach-1)/3*100}%`}}/></div>
    <ol className="ui-op-stages">{cards.map((c,i)=><li key={c.key}>
      <button type="button" className={`ui-op-stage tone-${c.tone}${i===sel?' sel':''}`} aria-pressed={i===sel} onClick={()=>setSel(i)} data-stage={c.n} data-stage-tone={c.tone}>
        <span className="ui-op-stage-head"><span className={`ui-op-badge tone-${c.tone}`}><Icon name={c.icon}/></span><span className="ui-op-stage-n">{c.n} · {c.name}</span></span>
        <span className="ui-op-stage-status"><i className={`ui-op-dot tone-${c.tone}`}/>{c.words}</span>
        <span className="ui-op-stage-q"><b data-stage-queued>{fmt(c.queued)}</b><small>{c.queuedLabel}</small></span>
        <span className="ui-op-stage-meter"><small>{c.meter}</small><Meter pct={c.meterPct} label={c.meterText}/><small data-stage-meter>{c.meterText}</small></span>
        {c.rate&&<span className={`ui-op-stage-meter ui-op-rate tone-${c.rate.tone}`} data-stage-rate={c.rate.key}><small>{c.rate.label}</small><Meter pct={c.rate.pct} label={c.rate.text}/><small>{c.rate.text}</small></span>}
      </button>
      {i<cards.length-1&&<span className={`ui-op-arrow${i+1<reach?' on':''}`} aria-hidden="true"><ArrowRight size={18}/></span>}
    </li>)}</ol>
    <div className={`ui-op-panel tone-${s.tone}`} data-stage-panel={s.n} aria-live="polite">
      <p><strong>{s.name}</strong> — {s.words}.{s.attention.length?` Needs attention: ${s.attention.map(a=>a.label||a.key).join(', ')}.`:''}</p>
      {s.rate&&<p className="ui-op-hint" data-stage-panel-rate>{s.rate.label}: {s.rate.text}.</p>}
      <p className="ui-op-hint">{s.actionHint}</p>
      <div className="ui-op-actions"><a className="ui-op-btn" href={s.href} data-stage-action={s.key}>{s.action}<ArrowRight size={14}/></a><a className="ui-op-btn ghost" href={s.href}>Open {s.screen}</a></div>
    </div>
  </div>
}

export function PulseStamp({pulse}){if(!pulse?.refreshed_at)return null
  return <p className="ui-op-stamp" data-pulse-stamp>Stored figures from {fmtDateTime(pulse.refreshed_at)} (rebuilt every 5 minutes){pulse.run_ms!=null?` · build ${fmt(pulse.run_ms)} ms`:''}</p>}

