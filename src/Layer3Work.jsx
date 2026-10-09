// Layer 3 AI validation › Work queue (v2.15.127). Replaces the older operator workspace on this tab.
//   Work by task      public.admin_read('layer3_queue_status'): the cascade work items per task and state.
//   Course-page pattern requests: panel and its queue read removed in clean-up batch 2 (9 Oct 2026); the
//                     requests were retired by Decision 213.
//   Recent results    public.layer3_recent_interpretations(100), shown 25 at a time. Decision 221: a cascade claim no
//                     step has answered yet shows "Cascade · step not chosen yet" (it used to show its placeholder
//                     profile, Claude Sonnet 4.6, although no call went to it); answered rows show the cascade step.
// Removed here: the "AI interpretation is paused" banner (it counted the older model-route records and could
// contradict Control), the one-off manual run form for task types that no longer run, and duplicate links.
import React,{useEffect,useMemo,useState}from'react'
import{ListChecks,RefreshCw,Route,Sparkles}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,Pager,SectionTitle,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'

const TASK={provider_intake_validation:'Intakes',provider_english_validation:'English requirements',provider_current_tuition_validation:'Tuition',source_pattern:'Course-page pattern',
  course_description:'Course description',official_course_url:'Course page link',delivery_mode:'Delivery mode',duration:'Duration'}
const task=t=>TASK[t]||String(t||'').replace(/_/g,' ')
const RESULT={validated:['Value found','success'],admitted:['Settled','success'],no_candidate:['No value on the page','neutral'],escalated:['Sent to a person','warning'],layer4_required:['Sent to a person','warning'],
  rejected_validation:['Failed the checks','warning'],provider_error:['Model error','danger'],failed:['Failed','danger'],cancelled:['Cancelled','neutral'],pending:['Waiting','info'],queued:['Waiting','info'],
  running:['Running','info'],calling:['Running','info'],reserved:['Running','info']}
const result=s=>RESULT[s]||[String(s||'—').replace(/_/g,' '),'neutral']
const ago=s=>s==null?'—':s<3600?`${Math.round(s/60)} min`:s<172800?`${Math.round(s/3600)} h`:`${Math.round(s/86400)} days`
const shortModel=m=>String(m||'—').split('/').pop()
const COLS=[['pending','Waiting'],['running','Running'],['admitted','Settled'],['no_candidate','No value on page'],['layer4_required','Sent to a person'],['failed','Failed']]

async function rpc(name,args){const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}

export default function Layer3Work({rank,onError}){
  const[queue,setQueue]=useState(null),[runs,setRuns]=useState([]),[busy,setBusy]=useState(false),[offset,setOffset]=useState(0)
  const load=async()=>{setBusy(true);try{const[q,r]=await Promise.all([rpc('admin_read',{p_operation:'layer3_queue_status'}).catch(()=>null),rpc('layer3_recent_interpretations',{p_limit:100}).catch(()=>[])]);setQueue(q?.by_task_class||[]);setRuns(Array.isArray(r)?r:[])}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  const tasks=queue||[]
  const total=useMemo(()=>{const t={};for(const q of tasks)for(const[k,v]of Object.entries(q.status_counts||{})){const key=['queued','reserved','calling'].includes(k)?(k==='queued'?'pending':'running'):k;t[key]=(t[key]||0)+Number(v||0)}return t},[tasks])
  const oldest=tasks.reduce((m,q)=>q.oldest_pending_seconds!=null&&(m==null||q.oldest_pending_seconds>m)?q.oldest_pending_seconds:m,null)
  if(queue===null&&busy)return <Loading label="Loading the Layer 3 work queue"/>
  return <div className="m-page-stack" data-layer3-work>
    <div className="cf-metric-grid">
      <Metric icon={ListChecks} label="Waiting to run" value={total.pending||0} detail={oldest!=null?`Oldest waiting ${ago(oldest)}`:'Nothing waiting'}/>
      <Metric icon={Sparkles} label="Settled by AI" value={total.admitted||0} detail="Value found and passed the checks" tone="success"/>
      <Metric icon={Route} label="Sent to a person" value={total.layer4_required||0} detail="In Layer 4 review" tone={(total.layer4_required||0)>0?'warning':'neutral'}/>
      <Metric icon={RefreshCw} label="Failed" value={total.failed||0} detail={(total.failed||0)>0?'Retry from Control › Layer 3 work that failed':'None'} tone={(total.failed||0)>0?'danger':'neutral'}/>
    </div>

    <section className="m-panel">
      <SectionTitle icon={ListChecks} title="Work by task" subtitle="Every item Layer 2 handed to the AI, by task and where it is now. Run, pause and limits are on the Control tab." action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button>}/>
      {tasks.length===0?<Empty text="No Layer 3 work recorded yet."/>:<div className="cf-table-wrap"><table className="cf-table l3w-tasks"><thead><tr><th>Task</th>{COLS.map(([k,l])=><th key={k} className="num">{l}</th>)}<th>Oldest waiting</th><th>Last finished</th></tr></thead>
        <tbody>{tasks.map(q=>{const c=q.status_counts||{};const v=k=>k==='pending'?Number(c.pending||0)+Number(c.queued||0):k==='running'?Number(c.running||0)+Number(c.reserved||0)+Number(c.calling||0):Number(c[k]||0)
          return <tr key={q.task_class} data-task={q.task_class}><td><strong>{task(q.task_class)}</strong></td>{COLS.map(([k])=><td key={k} className="num">{fmtNumber(v(k))}</td>)}<td>{ago(q.oldest_pending_seconds)}</td><td>{q.last_completed_at?fmtDateTime(q.last_completed_at):'—'}</td></tr>})}</tbody></table></div>}
    </section>

    <section className="m-panel">
      <SectionTitle icon={Sparkles} title="Recent results" subtitle="The latest answers from the models, newest first."/>
      {runs.length===0?<Empty text="No recent results."/>:<><div className="cf-table-wrap"><table className="cf-table l3w-runs"><thead><tr><th>When</th><th>Task</th><th>Result</th><th>Model</th><th className="num">Cost</th><th>Next</th></tr></thead>
        <tbody>{runs.slice(offset,offset+25).map((r,i)=><tr key={r.id||r.interpretation_id||i}><td>{fmtDateTime(r.created_at||r.updated_at)}</td><td>{task(r.task_class)}</td>
          <td><StatusChip value={r.status} tone={result(r.status)[1]} label={result(r.status)[0]}/></td>
          <td>{r.model_pending?<span className="sd-desc" data-model-pending title="Waiting for the cascade: the model is the step that answers, cheapest switched-on step first">Cascade · step not chosen yet</span>
            :<span title={r.aggregator_response_model||r.model_identifier}>{shortModel(r.aggregator_response_model||r.model_identifier)}{r.cascade_tier_no?<small className="sd-desc"> · step {r.cascade_tier_no}</small>:null}</span>}</td>
          <td className="num">{fmtMoney(Number(r.estimated_cost_usd||0),'USD',{decimals:4})}</td>
          <td className="l3w-next">{r.review_state&&r.review_state!=='not_created'?<span title={r.escalation_reason||''}>With a person</span>:'—'}</td></tr>)}</tbody></table></div>
        {runs.length>25&&<Pager offset={offset} limit={25} total={runs.length} onOffset={setOffset}/>}</>}
    </section>
  </div>
}
