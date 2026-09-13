import React,{useEffect,useMemo,useState}from'react'
import{ExternalLink}from'lucide-react'
import{supabase}from'./lib/supabase'

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
const failureClass=j=>j?.failure_class||j?.completion_class||(jobState(j)==='failed'?'Failed — inspect Job':(terminal.has(jobState(j))?'—':UNKNOWN))
const countLabel=v=>v==null?UNKNOWN:String(v)
const rateLabel=v=>v==null?UNKNOWN:`${Number(v).toFixed(2)}/min`
const evidenceLabel=j=>j?.evidence_count==null?UNKNOWN:`${j.evidence_count} produced${Number(j.verified_evidence_count)>0?` · ${j.verified_evidence_count} verified`:''}`

export default function ScheduledRuntimeHealth({jobs=[],error,onNavigate=()=>{}}){
 const[runtimeJobs,setRuntimeJobs]=useState(null),[runtimeError,setRuntimeError]=useState('')
 useEffect(()=>{let live=true;(async()=>{try{const{data,error:readError}=await supabase.rpc('admin_read',{p_operation:'jobs_runtime',p_args:{limit:50}});if(readError)throw readError;if(live){setRuntimeJobs(Array.isArray(data)?data:[]);setRuntimeError('')}}catch(e){if(live){setRuntimeJobs(null);setRuntimeError(e?.message||String(e))}}})();return()=>{live=false}},[jobs])
 const sourceJobs=runtimeJobs??jobs
 const metrics=useMemo(()=>{
   const recent=Array.isArray(sourceJobs)?sourceJobs:[]
   const queue=recent.map(queueWait).filter(v=>v!=null)
   const runs=recent.map(runDuration).filter(v=>v!=null)
   const failed=recent.filter(j=>jobState(j)==='failed').length
   const active=recent.filter(j=>['queued','running'].includes(jobState(j))).length
   const terminalMissingCompleted=recent.filter(j=>terminal.has(jobState(j))&&!validDate(j?.completed_at)).length
   const measurableWork=recent.filter(j=>Number.isFinite(Number(j?.processed_count))&&runDuration(j)>0)
   const processed=measurableWork.reduce((sum,j)=>sum+Number(j.processed_count),0)
   const executionSeconds=measurableWork.reduce((sum,j)=>sum+runDuration(j),0)
   const evidenceProduced=recent.reduce((sum,j)=>sum+(Number(j?.evidence_count)||0),0)
   return{recent,queueAvg:average(queue),runAvg:average(runs),failed,active,terminalMissingCompleted,queueMeasured:queue.length,runMeasured:runs.length,processed,weightedRate:executionSeconds>0?processed/executionSeconds*60:null,evidenceProduced}
 },[sourceJobs])
 const readError=error||runtimeError
 return <section className="m23-panel cf-scheduler-v2 cf-scheduler-runtime" aria-label="Scheduled Tasks Runtime Health">
   <div className="cf-scheduler-v2__subhead"><div><h3>Runtime Health</h3><p className="cf-scheduler-v2__note">Read-only measurements from the governed rank-4 Jobs runtime surface. Missing counters or timestamps remain unavailable rather than being treated as zero.</p></div><div className="cf-scheduler-v2__links"><button onClick={()=>onNavigate('#jobs')}>Jobs <ExternalLink size={12}/></button><button onClick={()=>onNavigate('#evidence')}>Evidence <ExternalLink size={12}/></button></div></div>
   {readError&&<div className="cf-scheduler-v2__message" data-error="true">Runtime metrics read unavailable; basic Jobs timing remains visible where available: {readError}</div>}
   <div className="cf-scheduler-runtime__summary">
     <article><strong>{metrics.recent.length}</strong><span>Recent Job sample</span></article>
     <article><strong>{durationLabel(metrics.queueAvg)}</strong><span>Average queue wait · {metrics.queueMeasured} measurable</span></article>
     <article><strong>{durationLabel(metrics.runAvg)}</strong><span>Average execution · {metrics.runMeasured} measurable</span></article>
     <article><strong>{metrics.weightedRate==null?UNKNOWN:`${metrics.weightedRate.toFixed(2)}/min`}</strong><span>Measured weighted throughput · {metrics.processed} records</span></article>
     <article><strong>{metrics.evidenceProduced}</strong><span>Evidence produced in sample</span></article>
     <article data-warning={metrics.terminalMissingCompleted>0?'true':'false'}><strong>{metrics.terminalMissingCompleted}</strong><span>Terminal Jobs missing completion timestamp</span></article>
   </div>
   <div className="cf-scheduler-v2__table-wrap"><table className="cf-scheduler-runtime__table"><thead><tr><th>Job / Profile</th><th>Status</th><th>Queue</th><th>Execution</th><th>Work</th><th>Rate</th><th>Evidence</th><th>Retry / Dedupe</th><th>Failure / Outcome</th><th>Follow</th></tr></thead><tbody>{metrics.recent.length?metrics.recent.slice(0,12).map((j,i)=><tr key={j.id||i}><td><strong>{human(j.job_type||j.domain||'Job')}</strong>{j.profile_key&&<><br/><small>{j.profile_key}</small></>}<br/><small className="cf-scheduler-v2__technical">{j.id||UNKNOWN}</small></td><td><span className="cf-scheduler-v2__status" data-state={jobState(j)}>{human(jobState(j))}</span></td><td>{durationLabel(queueWait(j))}</td><td>{durationLabel(runDuration(j))}<br/><small>{strictWhen(j.completed_at)}</small></td><td>{countLabel(j.processed_count)} processed{j.failed_count!=null&&<><br/><small>{j.failed_count} failed</small></>}</td><td>{rateLabel(j.throughput_records_per_min)}</td><td>{evidenceLabel(j)}</td><td>{j.retry_exhausted_count!=null?`${j.retry_exhausted_count} exhausted`:UNKNOWN}{j.dedupe_replay!=null&&<><br/><small>{j.dedupe_replay?'Dedupe replay':'Not replayed'}</small></>}</td><td className="cf-scheduler-runtime__failure">{failureClass(j)}</td><td><div className="cf-scheduler-v2__row-actions"><button onClick={()=>onNavigate('#jobs')}>Jobs</button><button onClick={()=>onNavigate('#evidence')}>Evidence</button></div></td></tr>):<tr><td colSpan={10} className="cf-scheduler-v2__empty">No recent Job records returned by the governed Jobs read surface.</td></tr>}</tbody></table></div>
   <p className="cf-scheduler-v2__note">Evidence produced and verified are separate counters; no acceptance/yield percentage is manufactured from unreviewed Evidence. Retry exhaustion is shown only when the runtime records that counter. Job <code>attempt_count</code> is intentionally not treated as retry count.</p>
 </section>
}
