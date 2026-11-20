// CF-247 S1-UX s824/s825 (Platform Admin 20 Nov 2026 10:31, 10:46 and 11:24): the pulse strip (five KPI cards with icons and three country completeness bars),
// the 4-stage pipeline board (Official Registers → Page Capture → AI Extraction & Auto-Clean → Live Catalogue: stage icons, status accent borders, a
// connected flow track, a health meter and the queued count in each stage, and the selected stage's action panel) and Active failures.
// Every figure comes from the stored ops pulse that admin_read 'platform_health' already returns (pulse key, s823 migration 20261120140000); these
// components make no read of their own. A stage action opens the existing screen where that stage's governed controls live.
// s838 (Platform Admin 20 Nov 2026 14:41): stages 2 and 3 also show their rate against the normal rate (capture rate, auto-clean pass rate), from the
// same stored pulse (rates, migration 20261120145000).
import React,{useState}from'react'
import{Activity,ArrowRight,Gauge,Inbox,Landmark,LibraryBig,OctagonAlert,ScanLine,Sparkles,Wallet}from'lucide-react'
import{STAGES,activeFailures,flowReach,kpiCards,stageCards}from'./lib/ops-pulse.js'
import{fmtDateTime,fmtNumber}from'./lib/format.js'
import'./ops-pulse.css'

const ICONS={Activity,Gauge,Inbox,OctagonAlert,Wallet,Landmark,ScanLine,Sparkles,LibraryBig}
const Icon=({name,size=18})=>{const C=ICONS[name]||Activity;return <C size={size} aria-hidden="true"/>}
const fmt=n=>n==null?'—':fmtNumber(n)

export function Meter({pct,label}){return <span className="op-meter" role="img" aria-label={label||(pct==null?'Not measured':`${pct}%`)}><i style={{width:`${pct==null?0:Math.max(2,pct)}%`}}/></span>}

export function PulseStrip({pulse}){
  if(!pulse)return null
  return <div className="op-kpis" data-pulse-strip>{kpiCards(pulse).map(k=><div key={k.key} className={`op-kpi tone-${k.tone}`} data-kpi={k.key}>
    <span className={`op-badge tone-${k.tone}`}><Icon name={k.icon}/></span>
    <div className="op-kpi-body"><small>{k.label}</small>
      {k.bars?<ul className="op-bars" data-kpi-bars>{k.bars.map(b=><li key={b.cc} data-country-bar={b.cc}><span className="op-cc" title={b.label}>{b.cc}</span><Meter pct={b.pct==null?null:Math.round(b.pct)} label={`${b.label}: ${b.text}`}/><b>{b.text}</b></li>)}</ul>
        :<b className="op-kpi-value">{k.value}</b>}
      {k.meterPct!=null&&<Meter pct={k.meterPct} label={`${k.meterPct}% of the daily cap`}/>}
      {k.detail&&<small>{k.detail}</small>}</div>
  </div>)}</div>
}

export function PipelineBoard({pulse}){
  const cards=stageCards(pulse),reach=flowReach(cards),[sel,setSel]=useState(()=>{const i=cards.findIndex(c=>c.tone==='warn'||c.tone==='crit');return i===-1?0:i})
  if(!pulse)return null
  const s=cards[sel]||cards[0]
  return <div className="op-board" data-pipeline-board>
    <div className="op-track" aria-hidden="true"><i style={{width:`${(reach-1)/3*100}%`}}/></div>
    <ol className="op-stages">{cards.map((c,i)=><li key={c.key}>
      <button type="button" className={`op-stage tone-${c.tone}${i===sel?' sel':''}`} aria-pressed={i===sel} onClick={()=>setSel(i)} data-stage={c.n} data-stage-tone={c.tone}>
        <span className="op-stage-head"><span className={`op-badge tone-${c.tone}`}><Icon name={c.icon}/></span><span className="op-stage-n">{c.n} · {c.name}</span></span>
        <span className="op-stage-status"><i className={`op-dot tone-${c.tone}`}/>{c.words}</span>
        <span className="op-stage-q"><b data-stage-queued>{fmt(c.queued)}</b><small>{c.queuedLabel}</small></span>
        <span className="op-stage-meter"><small>{c.meter}</small><Meter pct={c.meterPct} label={c.meterText}/><small data-stage-meter>{c.meterText}</small></span>
        {c.rate&&<span className={`op-stage-meter op-rate tone-${c.rate.tone}`} data-stage-rate={c.rate.key}><small>{c.rate.label}</small><Meter pct={c.rate.pct} label={c.rate.text}/><small>{c.rate.text}</small></span>}
      </button>
      {i<cards.length-1&&<span className={`op-arrow${i+1<reach?' on':''}`} aria-hidden="true"><ArrowRight size={18}/></span>}
    </li>)}</ol>
    <div className={`op-panel tone-${s.tone}`} data-stage-panel={s.n} aria-live="polite">
      <p><strong>{s.name}</strong> — {s.words}.{s.attention.length?` Needs attention: ${s.attention.map(a=>a.label||a.key).join(', ')}.`:''}</p>
      {s.rate&&<p className="op-hint" data-stage-panel-rate>{s.rate.label}: {s.rate.text}.</p>}
      <p className="op-hint">{s.actionHint}</p>
      <div className="op-actions"><a className="op-btn" href={s.href} data-stage-action={s.key}>{s.action}<ArrowRight size={14}/></a><a className="op-btn ghost" href={s.href}>Open {s.screen}</a></div>
    </div>
  </div>
}

export function ActiveFailures({pulse,limit=6}){
  const rows=activeFailures(pulse)
  if(!pulse)return null
  return <div className="op-fails" data-active-failures={rows.length}>{rows.length?<ul>{rows.slice(0,limit).map(r=><li key={r.stageN+r.key} className={`tone-${r.tone}`}>
      <span className={`op-badge sm tone-${r.tone}`}><Icon name={r.icon} size={15}/></span><span className="op-fail-label"><b>{r.label}</b><small>Stage {r.stageN} · {r.stage}</small></span>
      <a className="op-btn ghost sm" href={r.href}>Open<ArrowRight size={13}/></a></li>)}</ul>
    :<p className="op-none">No stage needs attention.</p>}</div>
}

export function PulseStamp({pulse}){if(!pulse?.refreshed_at)return null
  return <p className="op-stamp" data-pulse-stamp>Stored figures from {fmtDateTime(pulse.refreshed_at)} (rebuilt every 5 minutes){pulse.run_ms!=null?` · build ${fmt(pulse.run_ms)} ms`:''}</p>}

export{STAGES}
