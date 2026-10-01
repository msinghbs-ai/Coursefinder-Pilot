import React from'react'
import{Activity,BookOpen,CircleGauge,ExternalLink,GraduationCap,Info,TrendingUp,Users}from'lucide-react'
import{fmtNumber,fmtDate,fmtPercent}from'./lib/format.js'

const human=v=>String(v??'').replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())
const num=v=>{const n=Number(v);return Number.isFinite(n)?n:null}
const fmt=v=>v==null||v===''?'—':typeof v==='number'?fmtNumber(v):String(v)
const date=v=>{if(!v)return'';const d=new Date(v);return Number.isNaN(+d)?String(v):fmtDate(d)}
const pct=(v,unit)=>{const n=num(v);if(n==null)return fmt(v);const u=String(unit||'').toLowerCase();return u.includes('percent')||u==='%'?fmtPercent(n):fmtNumber(n,{maxDecimals:1})}
const clamp=v=>Math.max(6,Math.min(100,num(v)??0))
function EvidenceButton({id,navigate}){return id?<button className="m-secondary compact ci-evidence" onClick={e=>{e.stopPropagation();navigate?.('Evidence',{evidence_id:id})}}><BookOpen size={11}/>Evidence</button>:null}
function WorkspaceButton({target,navigate}){return <button className="m-secondary compact ci-workspace" onClick={()=>navigate?.(target)}>Open full workspace <ExternalLink size={11}/></button>}
function ContextPill({children,tone='neutral'}){return <span className={'ci-pill '+tone}>{children}</span>}
function OutcomeCard({x,navigate}){
 const value=num(x.metric_value),bench=num(x.national_benchmark),delta=value!=null&&bench!=null?value-bench:null,unit=x.unit||''
 return <article className="ci-outcome-card">
  <div className="ci-outcome-top"><div><strong>{x.metric_name||x.metric_code||'Outcome metric'}</strong><small>{[x.study_area,x.study_level,x.audience].filter(Boolean).join(' · ')||'Provider context'}</small></div>{delta!=null&&<ContextPill tone={delta>=0?'good':'warn'}>{delta>=0?'+':''}{delta.toFixed(1)}</ContextPill>}</div>
  <div className="ci-outcome-value">{pct(x.metric_value,unit)}</div>
  <div className="ci-benchmark-copy">{bench!=null?<>National benchmark <b>{pct(bench,unit)}</b></>:<>{[x.collection_year_from,x.collection_year_to].filter(Boolean).join('–')||'Governed observation'}</>}</div>
  {(num(x.confidence_low)!=null&&num(x.confidence_high)!=null)&&<div className="ci-confidence">CI {pct(x.confidence_low,unit)} – {pct(x.confidence_high,unit)}</div>}
  {x.response_count!=null&&<div className="ci-responses">Based on {fmtNumber(x.response_count)} responses</div>}
  <div className="ci-benchmark-track" aria-hidden="true"><span style={{width:clamp(value)+'%'}}/><i style={{left:clamp(bench)+'%'}}/></div>
  <div className="ci-card-foot"><small>{[x.collection_year_from,x.collection_year_to].filter(Boolean).join('–')||'Latest period'}</small><EvidenceButton id={x.evidence_id} navigate={navigate}/></div>
 </article>
}
function OutcomePanel({group,navigate}){
 const rows=(group?.items||[]).slice(0,5)
 return <section className="ci-panel ci-qilt">
  <header className="ci-panel-head"><div className="ci-title"><span><Activity size={16}/></span><div><h3>Student outcomes & benchmarks <b>({group?.source_label||'QILT'})</b></h3><p>{human(group?.granularity||'provider context')} · contextual benchmark data</p></div></div><div className="ci-head-actions"><ContextPill>{human(group?.relationship_state||'not available')}</ContextPill><WorkspaceButton target="Outcomes (QILT)" navigate={navigate}/></div></header>
  {rows.length?<div className="ci-outcome-grid">{rows.map((x,i)=><OutcomeCard x={x} navigate={navigate} key={x.id||i}/>)}</div>:<div className="ci-empty">No outcome figures are linked to this record yet.</div>}
 </section>
}
function MiniTrend({values=[]}){const nums=values.map(num).filter(v=>v!=null);if(nums.length<2)return <div className="ci-trend-empty">Trend appears when multiple comparable observations are available.</div>;const min=Math.min(...nums),max=Math.max(...nums),range=max-min||1,pts=nums.slice(0,8).map((v,i)=>[i*(100/Math.max(1,Math.min(nums.length,8)-1)),38-((v-min)/range)*30]);return <svg className="ci-trend" viewBox="0 0 100 42" preserveAspectRatio="none" aria-label="Context trend"><polyline points={pts.map(p=>p.join(',')).join(' ')} fill="none" vectorEffect="non-scaling-stroke"/></svg>}
function FlowPanel({group,navigate}){
 const rows=(group?.items||[]),visible=rows.slice(0,6),latest=visible.find(x=>!x.is_suppressed&&num(x.metric_value)!=null)
 const markets=[...new Set(rows.map(x=>x.nationality).filter(Boolean))].slice(0,6)
 const metricKey=latest?.metric_code||latest?.metric_name||null
 const trendRows=metricKey?rows.filter(x=>!x.is_suppressed&&(x.metric_code||x.metric_name)===metricKey&&num(x.metric_value)!=null).slice(0,8).reverse():[]
 const values=trendRows.map(x=>x.metric_value)
 const direct=String(group?.relationship_state||'').startsWith('direct_')
 return <section className="ci-panel ci-prisms">
  <header className="ci-panel-head"><div className="ci-title"><span><CircleGauge size={16}/></span><div><h3>International student flow <b>({group?.source_label||'PRISMS'})</b></h3><p>{human(group?.granularity||'context')} · governed student-flow context</p></div></div><div className="ci-head-actions"><ContextPill tone={direct?'good':'info'}>{human(group?.relationship_state||'not available')}</ContextPill><WorkspaceButton target="Student Flow (PRISMS)" navigate={navigate}/></div></header>
  <div className="ci-flow-grid">
   <div className="ci-flow-state"><span className="ci-big-icon"><Users size={24}/></span><strong>{direct?'Directly mapped':'Context only'}</strong><p>{direct?'This figure is for the provider or course shown.':'These figures are for the provider, region or study area, not this course on its own.'}</p></div>
   <div className="ci-flow-feature"><small>{latest?.metric_name||latest?.metric_code||'Latest figure'}</small><strong>{latest?fmt(latest.metric_value):'—'}</strong><span>{latest?[latest.subdivision,latest.study_area,latest.period_end&&date(latest.period_end)].filter(Boolean).join(' · '):'No directly comparable numeric observation available'}</span><MiniTrend values={values}/></div>
   <div className="ci-markets"><div className="ci-market-title"><TrendingUp size={13}/><strong>Source-market context</strong></div>{markets.length?<div className="ci-market-chips">{markets.map(x=><span key={x}>{x}</span>)}</div>:<p>No breakdown by nationality is available.</p>}{visible[0]?.evidence_id&&<EvidenceButton id={visible[0].evidence_id} navigate={navigate}/>}</div>
  </div>
 </section>
}
function ScholarshipPanel({group,navigate}){
 const rows=(group?.items||[]).slice(0,3)
 return <section className="ci-panel ci-scholarships">
  <header className="ci-panel-head"><div className="ci-title"><span><GraduationCap size={16}/></span><div><h3>Scholarships & funding</h3><p>Governed scope · exclusions override broad inclusion</p></div></div><ContextPill tone={rows.length?'good':'neutral'}>{rows.length?group.total+' related':'None related'}</ContextPill></header>
  {rows.length?<div className="ci-sch-list">{rows.map((x,i)=><div className="ci-sch-row" key={x.id||i}><div><strong>{x.name||'Scholarship'}</strong><small>{[human(x.relationship),x.audience,x.application_close_date?'Closes '+date(x.application_close_date):null].filter(Boolean).join(' · ')}</small></div><div><b>{x.award_value_text||'See details'}</b><EvidenceButton id={x.evidence_id} navigate={navigate}/></div></div>)}</div>:<div className="ci-sch-empty"><GraduationCap size={24}/><div><strong>Nothing related yet</strong><p>No Scholarship is currently related to this entity by an accepted Course/Provider/field/study-level/campus scope.</p></div></div>}
  <WorkspaceButton target="Scholarships" navigate={navigate}/>
 </section>
}
export default function ContextualInsights({data,navigate,entityType='provider'}){
 if(!data)return null
 const outcomes=data.student_outcomes||{},flow=data.student_flow||{},sch=data.scholarships||{}
 return <section className="ci-workbench">
  <div className="ci-workbench-title"><div><h2>Related insights & funding</h2><p>{entityType==='course'?'Decision context alongside the Course. Provider/regional statistics retain their actual granularity and are not Course facts.':'Graduate outcomes, student numbers and funding related to this provider.'}</p></div><Info size={15}/></div>
  <OutcomePanel group={outcomes} navigate={navigate}/>
  <div className="ci-lower-grid"><FlowPanel group={flow} navigate={navigate}/><ScholarshipPanel group={sch} navigate={navigate}/></div>
  <p className="ci-authority">{data.authority_note}</p>
  <style>{`
.ci-workbench{margin-top:14px;display:grid;gap:11px}.ci-workbench-title{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}.ci-workbench-title h2{font-size:var(--cf-fs-lg);margin:0;color:var(--cf-slate-900)}.ci-workbench-title p{font-size:var(--cf-fs-xs);line-height:1.45;color:var(--cf-slate-500);margin:3px 0 0;max-width:760px}.ci-workbench-title>svg{color:var(--cf-slate-400)}
.ci-panel{border:1px solid var(--cf-slate-200);background:var(--cf-white);border-radius:var(--cf-radius-xl);padding:12px;box-shadow:var(--cf-shadow-xs)}.ci-panel-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:10px}.ci-title{display:flex;gap:8px;align-items:flex-start}.ci-title>span{width:30px;height:30px;border-radius:var(--cf-radius-md);background:var(--cf-green-75);color:var(--cf-teal-700);display:grid;place-items:center;flex:none}.ci-title h3{font-size:var(--cf-fs-md);margin:1px 0 2px;color:var(--cf-slate-900)}.ci-title h3 b{color:var(--cf-slate-600)}.ci-title p{font-size:var(--cf-fs-2xs);color:var(--cf-slate-500);margin:0}.ci-head-actions{display:flex;align-items:center;gap:6px;flex-wrap:wrap;justify-content:flex-end}.ci-pill{display:inline-flex;align-items:center;border-radius:var(--cf-radius-pill);padding:4px 7px;background:var(--cf-slate-100);color:var(--cf-slate-500);font-size:var(--cf-fs-3xs);font-weight:800;white-space:nowrap}.ci-pill.good{background:var(--cf-green-75);color:var(--cf-green-700)}.ci-pill.warn{background:var(--cf-orange-50);color:var(--cf-amber-700)}.ci-pill.info{background:var(--cf-blue-50);color:var(--cf-blue-600)}.ci-workspace{display:inline-flex;gap:5px;align-items:center}.ci-evidence{display:inline-flex!important;gap:4px;align-items:center}
.ci-outcome-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}.ci-outcome-card{border:1px solid var(--cf-slate-200);border-radius:var(--cf-radius-md);background:linear-gradient(180deg,var(--cf-white),var(--cf-slate-25));padding:9px;min-width:0}.ci-outcome-top{display:flex;justify-content:space-between;gap:6px;min-height:36px}.ci-outcome-top strong,.ci-outcome-top small{display:block}.ci-outcome-top strong{font-size:var(--cf-fs-xs);color:var(--cf-slate-850)}.ci-outcome-top small{font-size:7.8px;color:var(--cf-slate-450);margin-top:2px;line-height:1.3}.ci-outcome-value{font-size:var(--cf-fs-3xl);font-weight:900;letter-spacing:-.04em;color:var(--cf-teal-700);margin:8px 0 2px}.ci-benchmark-copy{font-size:var(--cf-fs-3xs);color:var(--cf-slate-450)}.ci-benchmark-copy b{color:var(--cf-slate-600)}.ci-benchmark-track{height:6px;border-radius:99px;background:var(--cf-slate-175);margin:8px 0;position:relative}.ci-benchmark-track span{display:block;height:100%;border-radius:99px;background:linear-gradient(90deg,var(--cf-green-300),var(--cf-teal-700))}.ci-benchmark-track i{position:absolute;top:-2px;width:2px;height:10px;background:var(--cf-slate-900);border-radius:var(--cf-radius-xs);transform:translateX(-1px)}.ci-confidence{font-size:7.7px;color:var(--cf-slate-500);margin-top:3px}.ci-responses{font-size:7.7px;color:var(--cf-slate-400);margin-top:2px}.ci-card-foot{display:flex;align-items:center;justify-content:space-between;gap:5px}.ci-card-foot>small{font-size:7.8px;color:var(--cf-slate-400)}
.ci-lower-grid{display:grid;grid-template-columns:minmax(0,1.65fr) minmax(250px,.75fr);gap:11px}.ci-flow-grid{display:grid;grid-template-columns:minmax(180px,.8fr) minmax(210px,1fr) minmax(180px,.85fr);gap:9px}.ci-flow-state,.ci-flow-feature,.ci-markets{border:1px solid var(--cf-slate-175);background:var(--cf-slate-25);border-radius:var(--cf-radius-md);padding:10px;min-width:0}.ci-big-icon{width:42px;height:42px;border-radius:var(--cf-radius-pill);background:var(--cf-indigo-50);color:var(--cf-indigo-600);display:grid;place-items:center}.ci-flow-state strong{display:block;font-size:var(--cf-fs-xs);margin-top:7px}.ci-flow-state p,.ci-markets p{font-size:var(--cf-fs-2xs);color:var(--cf-slate-500);line-height:1.45;margin:4px 0 0}.ci-flow-feature>small,.ci-flow-feature>strong,.ci-flow-feature>span{display:block}.ci-flow-feature>small{font-size:var(--cf-fs-3xs);color:var(--cf-slate-500)}.ci-flow-feature>strong{font-size:var(--cf-fs-4xl);letter-spacing:-.04em;margin-top:5px}.ci-flow-feature>span{font-size:var(--cf-fs-3xs);color:var(--cf-slate-450);margin-top:2px}.ci-trend{width:100%;height:42px;margin-top:5px;overflow:visible}.ci-trend polyline{stroke:var(--cf-indigo-550);stroke-width:2}.ci-trend-empty{font-size:var(--cf-fs-3xs);color:var(--cf-slate-400);margin-top:10px}.ci-market-title{display:flex;align-items:center;gap:5px;color:var(--cf-slate-700)}.ci-market-title strong{font-size:var(--cf-fs-2xs)}.ci-market-chips{display:flex;gap:5px;flex-wrap:wrap;margin:8px 0}.ci-market-chips span{border-radius:var(--cf-radius-pill);background:var(--cf-indigo-50);color:var(--cf-indigo-700);padding:4px 7px;font-size:var(--cf-fs-3xs);font-weight:750}
.ci-scholarships{display:flex;flex-direction:column}.ci-sch-list{display:grid;gap:6px}.ci-sch-row{border:1px solid var(--cf-slate-175);border-radius:var(--cf-radius-md);padding:8px;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px}.ci-sch-row strong,.ci-sch-row small,.ci-sch-row b{display:block}.ci-sch-row strong{font-size:var(--cf-fs-2xs)}.ci-sch-row small{font-size:7.8px;color:var(--cf-slate-450);margin-top:2px}.ci-sch-row b{font-size:var(--cf-fs-2xs);text-align:right}.ci-sch-empty{display:flex;align-items:flex-start;gap:10px;padding:10px 2px 12px;color:var(--cf-slate-500)}.ci-sch-empty>svg{color:var(--cf-slate-450);flex:none}.ci-sch-empty strong{font-size:var(--cf-fs-xs);color:var(--cf-slate-700)}.ci-sch-empty p{font-size:var(--cf-fs-2xs);line-height:1.45;margin:3px 0 0}.ci-scholarships>.ci-workspace{align-self:flex-start;margin-top:auto}.ci-authority{font-size:var(--cf-fs-3xs);color:var(--cf-slate-450);margin:0 2px;line-height:1.4}.ci-empty{border:1px dashed var(--cf-slate-225);border-radius:var(--cf-radius-md);padding:16px;color:var(--cf-slate-450);font-size:var(--cf-fs-2xs);text-align:center}
@media(max-width:1220px){.ci-outcome-grid{grid-template-columns:repeat(3,minmax(0,1fr))}.ci-lower-grid{grid-template-columns:1fr}.ci-flow-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}
@media(max-width:760px){.ci-panel-head{flex-direction:column}.ci-head-actions{justify-content:flex-start}.ci-outcome-grid{grid-template-columns:1fr 1fr}.ci-flow-grid{grid-template-columns:1fr}.ci-outcome-value{font-size:var(--cf-fs-2xl)}.ci-sch-row{grid-template-columns:1fr}.ci-sch-row b{text-align:left}}
@media(max-width:460px){.ci-outcome-grid{grid-template-columns:1fr}}
`}</style>
 </section>
}
