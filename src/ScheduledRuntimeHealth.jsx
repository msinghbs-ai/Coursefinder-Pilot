import React,{useMemo}from'react'
import{ExternalLink}from'lucide-react'

const UNKNOWN='Unavailable'
const terminal=new Set(['completed','failed','cancelled','blocked','succeeded','success'])
const human=v=>String(v??'').replaceAll('_',' ').replace(/\b\w/g,x=>x.toUpperCase())
const validDate=v=>{if(!v)return null;const d=new Date(v);return Number.isNaN(d.getTime())?null:d}
const secondsBetween=(a,b)=>{const start=validDate(a),end=validDate(b);if(!start||!end||end<start)return null;return (end-start)/1000}
const durationLabel=seconds=>seconds==null?UNKNOWN:seconds<1?`${Math.round(seconds*1000)} ms`:seconds<60?`${seconds.toFixed(1)} s`:`${Math.floor(seconds/60)}m ${Math.round(seconds%60)}s`
const average=values=>{const xs=values.filter(v=>Number.isFinite(v));return xs.length?xs.reduce((a,b)=>a+b,0)/xs.length:null}
const jobState=j=>String(j?.status||j?.state||'unknown').toLowerCase()
const queueWait=j=>secondsBetween(j?.created_at,j?.started_at)
const runDuration=j=>secondsBetween(j?.started_at,j?.completed_at)
const totalDuration=j=>secondsBetween(j?.created_at,j?.completed_at)
const strictWhen=v=>{const d=validDate(v);return d?d.toLocaleString():UNKNOWN}
const failureClass=j=>j?.failure_class||j?.completion_class||(jobState(j)==='failed'?(j?.error_text||'Failed — inspect Job'):(terminal.has(jobState(j))?'—':UNKNOWN))

export default function ScheduledRuntimeHealth({jobs=[],error,onNavigate=()=>{}}){
 const metrics=useMemo(()=>{
   const recent=Array.isArray(jobs)?jobs:[]
   const queue=recent.map(queueWait).filter(v=>v!=null)
   const runs=recent.map(runDuration).filter(v=>v!=null)
   const totals=recent.map(totalDuration).filter(v=>v!=null)
   const failed=recent.filter(j=>jobState(j)==='failed').length
   const active=recent.filter(j=>['queued','running'].includes(jobState(j))).length
   const terminalMissingCompleted=recent.filter(j=>terminal.has(jobState(j))&&!validDate(j?.completed_at)).length
   return{recent,queueAvg:average(queue),runAvg:average(runs),totalAvg:average(totals),failed,active,terminalMissingCompleted,queueMeasured:queue.length,runMeasured:runs.length}
 },[jobs])
 return <section className="m23-panel cf-scheduler-v2 cf-scheduler-runtime" aria-label="Scheduled Tasks Runtime Health">
   <div className="cf-scheduler-v2__subhead"><div><h3>Runtime Health</h3><p className="cf-scheduler-v2__note">Read-only measurements from the governed Jobs surface. Missing timestamps remain unavailable rather than being treated as zero.</p></div><div className="cf-scheduler-v2__links"><button onClick={()=>onNavigate('#jobs')}>Jobs <ExternalLink size={12}/></button><button onClick={()=>onNavigate('#evidence')}>Evidence <ExternalLink size={12}/></button></div></div>
   {error&&<div className="cf-scheduler-v2__message" data-error="true">Runtime health unavailable: {error}</div>}
   {!error&&<>
     <div className="cf-scheduler-runtime__summary">
       <article><strong>{metrics.recent.length}</strong><span>Recent Job sample</span></article>
       <article><strong>{durationLabel(metrics.queueAvg)}</strong><span>Average queue wait · {metrics.queueMeasured} measurable</span></article>
       <article><strong>{durationLabel(metrics.runAvg)}</strong><span>Average execution · {metrics.runMeasured} measurable</span></article>
       <article><strong>{metrics.active}</strong><span>Queued / running</span></article>
       <article><strong>{metrics.failed}</strong><span>Failed</span></article>
       <article data-warning={metrics.terminalMissingCompleted>0?'true':'false'}><strong>{metrics.terminalMissingCompleted}</strong><span>Terminal Jobs missing completion timestamp</span></article>
     </div>
     <div className="cf-scheduler-v2__table-wrap"><table className="cf-scheduler-runtime__table"><thead><tr><th>Job</th><th>Status</th><th>Queue Wait</th><th>Execution</th><th>Total</th><th>Started</th><th>Completed</th><th>Failure / Outcome</th><th>Follow</th></tr></thead><tbody>{metrics.recent.length?metrics.recent.slice(0,12).map((j,i)=><tr key={j.id||i}><td><strong>{human(j.job_type||j.domain||'Job')}</strong><br/><small className="cf-scheduler-v2__technical">{j.id||UNKNOWN}</small></td><td><span className="cf-scheduler-v2__status" data-state={jobState(j)}>{human(jobState(j))}</span></td><td>{durationLabel(queueWait(j))}</td><td>{durationLabel(runDuration(j))}</td><td>{durationLabel(totalDuration(j))}</td><td>{strictWhen(j.started_at)}</td><td>{strictWhen(j.completed_at)}</td><td className="cf-scheduler-runtime__failure">{failureClass(j)}</td><td><div className="cf-scheduler-v2__row-actions"><button onClick={()=>onNavigate('#jobs')}>Jobs</button><button onClick={()=>onNavigate('#evidence')}>Evidence</button></div></td></tr>):<tr><td colSpan={9} className="cf-scheduler-v2__empty">No recent Job records returned by the governed Jobs read surface.</td></tr>}</tbody></table></div>
     <p className="cf-scheduler-v2__note">Throughput, processed/accepted/rejected counts, retry exhaustion, dedupe rate and Evidence yield are not shown until those values are exposed by an accepted governed read contract. Job <code>attempt_count</code> is intentionally not interpreted as retry count because its semantics vary by workload.</p>
   </>}
 </section>
}
