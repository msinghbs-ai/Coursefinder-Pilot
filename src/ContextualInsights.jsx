import React from'react'
import{Activity,BookOpen,CircleGauge,ExternalLink,GraduationCap,Info,TrendingUp,Users}from'lucide-react'

const human=v=>String(v??'').replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())
const num=v=>{const n=Number(v);return Number.isFinite(n)?n:null}
const fmt=v=>v==null||v===''?'—':typeof v==='number'?v.toLocaleString():String(v)
const date=v=>{if(!v)return'';const d=new Date(v);return Number.isNaN(+d)?String(v):d.toLocaleDateString(undefined,{day:'2-digit',month:'short',year:'numeric'})}
const pct=(v,unit)=>{const n=num(v);if(n==null)return fmt(v);const u=String(unit||'').toLowerCase();return u.includes('percent')||u==='%'?n.toFixed(1)+'%':n.toLocaleString(undefined,{maximumFractionDigits:1})}
const clamp=v=>Math.max(6,Math.min(100,num(v)??0))
function EvidenceButton({id,navigate}){return id?<button className="m-secondary compact ci-evidence" onClick={e=>{e.stopPropagation();navigate?.('Evidence',{evidence_id:id})}}><BookOpen size={11}/>Evidence</button>:null}
function WorkspaceButton({target,navigate}){return <button className="m-secondary compact ci-workspace" onClick={()=>navigate?.(target)}>Open full workspace <ExternalLink size={11}/></button>}
function ContextPill({children,tone='neutral'}){return <span className={'ci-pill '+tone}>{children}</span>}
function OutcomeCard({x,navigate}){
 const value=num(x.metric_value),bench=num(x.national_benchmark),delta=value!=null&&bench!=null?value-bench:null,unit=x.unit||''
 return <article className="ci-outcome-card">
  <div className="ci-outcome-top"><div><strong>{x.metric_name||x.metric_code||'Outcome metric'}</strong><small>{[x.study_area,x.study_level,x.audience].filter(Boolean).join(' · ')||'Provider context'}</small></div>{delta!=null&&<ContextPill tone={delta>=0?'good':'warn'}>{delta>=0?'+':''}{delta.toFixed(1)}</ContextPill>}</div>
  <div className="ci-outcome-value">{pct(x.metric_value,unit)}</div>
  <div className="ci-benchmark-copy">{bench!=null?<>vs benchmark <b>{pct(bench,unit)}</b></>:<>{[x.collection_year_from,x.collection_year_to].filter(Boolean).join('–')||'Governed observation'}</>}</div>
  <div className="ci-benchmark-track" aria-hidden="true"><span style={{width:clamp(value)+'%'}}/><i style={{left:clamp(bench)+'%'}}/></div>
  <div className="ci-card-foot"><small>{[x.collection_year_from,x.collection_year_to].filter(Boolean).join('–')||'Latest governed period'}</small><EvidenceButton id={x.evidence_id} navigate={navigate}/></div>
 </article>
}
function OutcomePanel({group,navigate}){
 const rows=(group?.items||[]).slice(0,5)
 return <section className="ci-panel ci-qilt">
  <header className="ci-panel-head"><div className="ci-title"><span><Activity size={16}/></span><div><h3>Student outcomes & benchmarks <b>({group?.source_label||'QILT'})</b></h3><p>{human(group?.granularity||'provider context')} · contextual benchmark data</p></div></div><div className="ci-head-actions"><ContextPill>{human(group?.relationship_state||'not available')}</ContextPill><WorkspaceButton target="Outcomes (QILT)" navigate={navigate}/></div></header>
  {rows.length?<div className="ci-outcome-grid">{rows.map((x,i)=><OutcomeCard x={x} navigate={navigate} key={x.id||i}/>)}</div>:<div className="ci-empty">No governed outcome metrics are currently related to this entity.</div>}
 </section>
}
function MiniTrend({values=[]}){const nums=values.map(num).filter(v=>v!=null);if(nums.length<2)return <div className="ci-trend-empty">Trend appears when multiple comparable observations are available.</div>;const min=Math.min(...nums),max=Math.max(...nums),range=max-min||1,pts=nums.slice(0,8).map((v,i)=>[i*(100/Math.max(1,Math.min(nums.length,8)-1)),38-((v-min)/range)*30]);return <svg className="ci-trend" viewBox="0 0 100 42" preserveAspectRatio="none" aria-label="Context trend"><polyline points={pts.map(p=>p.join(',')).join(' ')} fill="none" vectorEffect="non-scaling-stroke"/></svg>}
function FlowPanel({group,navigate}){
 const rows=(group?.items||[]),visible=rows.slice(0,6),latest=visible.find(x=>!x.is_suppressed&&num(x.metric_value)!=null)
 const markets=[...new Set(rows.map(x=>x.nationality).filter(Boolean))].slice(0,6)
 const values=visible.filter(x=>!x.is_suppressed).map(x=>x.metric_value)
 const direct=String(group?.relationship_state||'').startsWith('direct_')
 return <section className="ci-panel ci-prisms">
  <header className="ci-panel-head"><div className="ci-title"><span><CircleGauge size={16}/></span><div><h3>International student flow <b>({group?.source_label||'PRISMS'})</b></h3><p>{human(group?.granularity||'context')} · governed student-flow context</p></div></div><div className="ci-head-actions"><ContextPill tone={direct?'good':'info'}>{human(group?.relationship_state||'not available')}</ContextPill><WorkspaceButton target="Student Flow (PRISMS)" navigate={navigate}/></div></header>
  <div className="ci-flow-grid">
   <div className="ci-flow-state"><span className="ci-big-icon"><Users size={24}/></span><strong>{direct?'Directly mapped':'Context only'}</strong><p>{direct?'This observation is governed at the Provider/Course grain shown.':'No direct governed Course relationship is implied; displayed values retain their Provider/regional/study-area grain.'}</p></div>
   <div className="ci-flow-feature"><small>{latest?.metric_name||latest?.metric_code||'Latest governed observation'}</small><strong>{latest?fmt(latest.metric_value):'—'}</strong><span>{latest?[latest.subdivision,latest.study_area,latest.period_end&&date(latest.period_end)].filter(Boolean).join(' · '):'No directly comparable numeric observation available'}</span><MiniTrend values={values}/></div>
   <div className="ci-markets"><div className="ci-market-title"><TrendingUp size={13}/><strong>Source-market context</strong></div>{markets.length?<div className="ci-market-chips">{markets.map(x=><span key={x}>{x}</span>)}</div>:<p>No nationality breakdown is present in this bounded contextual response.</p>}{visible[0]?.evidence_id&&<EvidenceButton id={visible[0].evidence_id} navigate={navigate}/>}</div>
  </div>
 </section>
}
function ScholarshipPanel({group,navigate}){
 const rows=(group?.items||[]).slice(0,3)
 return <section className="ci-panel ci-scholarships">
  <header className="ci-panel-head"><div className="ci-title"><span><GraduationCap size={16}/></span><div><h3>Scholarships & funding</h3><p>Governed scope · exclusions override broad inclusion</p></div></div><ContextPill tone={rows.length?'good':'neutral'}>{rows.length?group.total+' related':'None related'}</ContextPill></header>
  {rows.length?<div className="ci-sch-list">{rows.map((x,i)=><div className="ci-sch-row" key={x.id||i}><div><strong>{x.name||'Scholarship'}</strong><small>{[human(x.relationship),x.audience,x.application_close_date?'Closes '+date(x.application_close_date):null].filter(Boolean).join(' · ')}</small></div><div><b>{x.award_value_text||'See details'}</b><EvidenceButton id={x.evidence_id} navigate={navigate}/></div></div>)}</div>:<div className="ci-sch-empty"><GraduationCap size={24}/><div><strong>No related governed scope</strong><p>No Scholarship is currently related to this entity by an accepted Course/Provider/field/study-level/campus scope.</p></div></div>}
  <WorkspaceButton target="Scholarships" navigate={navigate}/>
 </section>
}
export default function ContextualInsights({data,navigate,entityType='provider'}){
 if(!data)return null
 const outcomes=data.student_outcomes||{},flow=data.student_flow||{},sch=data.scholarships||{}
 return <section className="ci-workbench">
  <div className="ci-workbench-title"><div><h2>Related insights & funding</h2><p>{entityType==='course'?'Decision context alongside the Course. Provider/regional statistics retain their actual granularity and are not Course facts.':'Governed contextual outcomes, student flow and funding related to this Provider.'}</p></div><Info size={15}/></div>
  <OutcomePanel group={outcomes} navigate={navigate}/>
  <div className="ci-lower-grid"><FlowPanel group={flow} navigate={navigate}/><ScholarshipPanel group={sch} navigate={navigate}/></div>
  <p className="ci-authority">{data.authority_note}</p>
  <style>{`
.ci-workbench{margin-top:14px;display:grid;gap:11px}.ci-workbench-title{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}.ci-workbench-title h2{font-size:14px;margin:0;color:#0f172a}.ci-workbench-title p{font-size:9.5px;line-height:1.45;color:#64748b;margin:3px 0 0;max-width:760px}.ci-workbench-title>svg{color:#94a3b8}
.ci-panel{border:1px solid #dfe6f0;background:#fff;border-radius:12px;padding:12px;box-shadow:0 1px 2px rgba(15,23,42,.025)}.ci-panel-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;margin-bottom:10px}.ci-title{display:flex;gap:8px;align-items:flex-start}.ci-title>span{width:30px;height:30px;border-radius:9px;background:#eef2ff;color:#4f46e5;display:grid;place-items:center;flex:none}.ci-title h3{font-size:11.5px;margin:1px 0 2px;color:#0f172a}.ci-title h3 b{color:#475569}.ci-title p{font-size:8.5px;color:#64748b;margin:0}.ci-head-actions{display:flex;align-items:center;gap:6px;flex-wrap:wrap;justify-content:flex-end}.ci-pill{display:inline-flex;align-items:center;border-radius:999px;padding:4px 7px;background:#f1f5f9;color:#64748b;font-size:8px;font-weight:800;white-space:nowrap}.ci-pill.good{background:#ecfdf5;color:#15803d}.ci-pill.warn{background:#fff7ed;color:#b45309}.ci-pill.info{background:#eff6ff;color:#2563eb}.ci-workspace{display:inline-flex;gap:5px;align-items:center}.ci-evidence{display:inline-flex!important;gap:4px;align-items:center}
.ci-outcome-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}.ci-outcome-card{border:1px solid #e5eaf1;border-radius:9px;background:linear-gradient(180deg,#fff,#fbfcff);padding:9px;min-width:0}.ci-outcome-top{display:flex;justify-content:space-between;gap:6px;min-height:36px}.ci-outcome-top strong,.ci-outcome-top small{display:block}.ci-outcome-top strong{font-size:9.5px;color:#172033}.ci-outcome-top small{font-size:7.8px;color:#7c8ba0;margin-top:2px;line-height:1.3}.ci-outcome-value{font-size:22px;font-weight:900;letter-spacing:-.04em;color:#111827;margin:8px 0 2px}.ci-benchmark-copy{font-size:8px;color:#7c8ba0}.ci-benchmark-copy b{color:#475569}.ci-benchmark-track{height:6px;border-radius:99px;background:#e8edf5;margin:8px 0;position:relative}.ci-benchmark-track span{display:block;height:100%;border-radius:99px;background:linear-gradient(90deg,#818cf8,#4f46e5)}.ci-benchmark-track i{position:absolute;top:-2px;width:2px;height:10px;background:#0f172a;border-radius:2px;transform:translateX(-1px)}.ci-card-foot{display:flex;align-items:center;justify-content:space-between;gap:5px}.ci-card-foot>small{font-size:7.8px;color:#94a3b8}
.ci-lower-grid{display:grid;grid-template-columns:minmax(0,1.65fr) minmax(250px,.75fr);gap:11px}.ci-flow-grid{display:grid;grid-template-columns:minmax(180px,.8fr) minmax(210px,1fr) minmax(180px,.85fr);gap:9px}.ci-flow-state,.ci-flow-feature,.ci-markets{border:1px solid #e8edf4;background:#fbfcff;border-radius:9px;padding:10px;min-width:0}.ci-big-icon{width:42px;height:42px;border-radius:999px;background:#eef2ff;color:#4f46e5;display:grid;place-items:center}.ci-flow-state strong{display:block;font-size:10px;margin-top:7px}.ci-flow-state p,.ci-markets p{font-size:8.5px;color:#64748b;line-height:1.45;margin:4px 0 0}.ci-flow-feature>small,.ci-flow-feature>strong,.ci-flow-feature>span{display:block}.ci-flow-feature>small{font-size:8px;color:#64748b}.ci-flow-feature>strong{font-size:24px;letter-spacing:-.04em;margin-top:5px}.ci-flow-feature>span{font-size:8px;color:#7c8ba0;margin-top:2px}.ci-trend{width:100%;height:42px;margin-top:5px;overflow:visible}.ci-trend polyline{stroke:#5b5ce2;stroke-width:2}.ci-trend-empty{font-size:8px;color:#94a3b8;margin-top:10px}.ci-market-title{display:flex;align-items:center;gap:5px;color:#334155}.ci-market-title strong{font-size:9px}.ci-market-chips{display:flex;gap:5px;flex-wrap:wrap;margin:8px 0}.ci-market-chips span{border-radius:999px;background:#eef2ff;color:#4338ca;padding:4px 7px;font-size:8px;font-weight:750}
.ci-scholarships{display:flex;flex-direction:column}.ci-sch-list{display:grid;gap:6px}.ci-sch-row{border:1px solid #e8edf4;border-radius:8px;padding:8px;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px}.ci-sch-row strong,.ci-sch-row small,.ci-sch-row b{display:block}.ci-sch-row strong{font-size:9px}.ci-sch-row small{font-size:7.8px;color:#7c8ba0;margin-top:2px}.ci-sch-row b{font-size:9px;text-align:right}.ci-sch-empty{display:flex;align-items:flex-start;gap:10px;padding:10px 2px 12px;color:#64748b}.ci-sch-empty>svg{color:#7c8ba0;flex:none}.ci-sch-empty strong{font-size:10px;color:#334155}.ci-sch-empty p{font-size:8.5px;line-height:1.45;margin:3px 0 0}.ci-scholarships>.ci-workspace{align-self:flex-start;margin-top:auto}.ci-authority{font-size:8px;color:#7c8ba0;margin:0 2px;line-height:1.4}.ci-empty{border:1px dashed #dbe3ef;border-radius:8px;padding:16px;color:#7c8ba0;font-size:9px;text-align:center}
@media(max-width:1220px){.ci-outcome-grid{grid-template-columns:repeat(3,minmax(0,1fr))}.ci-lower-grid{grid-template-columns:1fr}.ci-flow-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}
@media(max-width:760px){.ci-panel-head{flex-direction:column}.ci-head-actions{justify-content:flex-start}.ci-outcome-grid{grid-template-columns:1fr 1fr}.ci-flow-grid{grid-template-columns:1fr}.ci-outcome-value{font-size:19px}.ci-sch-row{grid-template-columns:1fr}.ci-sch-row b{text-align:left}}
@media(max-width:460px){.ci-outcome-grid{grid-template-columns:1fr}}
`}</style>
 </section>
}
