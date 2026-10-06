// CF-247 Decision 254 (6 Oct 2026, Platform Admin 06:59 and 10:56): Task manager, Phase A of the job system.
// Every long-running admin action is a job in pipeline.admin_jobs, worked by the database dispatcher a slice a minute.
// This page is the Task manager in the Windows sense (Platform Admin 6 Oct 12:01): only tasks that are waiting, running or
// paused. It starts a task, shows its progress from the database (so a refresh loses nothing), and lets a person pause,
// resume or cancel it. Finished tasks (done, failed, cancelled) live under Scheduled jobs › Jobs with the other job history. The first job kinds: Qualify adapters (read-only measurement by country, state, provider kind
// and adapter state) and Admit the passing fields (the deliberate step, Platform Admins only).
import React,{useEffect,useMemo,useRef,useState}from'react'
import{ListChecks,Play,Pause,Square,RefreshCw,CheckCircle2,XCircle,AlertTriangle}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Badge,Loading,SectionTitle,EmptyRow,fmtDateTime,fmtNumber}from'./ui-kit'

const errText=e=>e?.message||String(e)
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const FIELDS=['intakes','fee','english','delivery']
const FIELD_LABEL={intakes:'Intakes',fee:'Fee',english:'English',delivery:'Delivery'}
const STATE_TONE={queued:'neutral',running:'info',paused:'warning',done:'success',failed:'danger',cancelled:'neutral'}
const KIND_LABEL={qualify_adapters:'Qualify adapters',admit_qualified:'Admit passing fields'}
const pct=p=>{const t=Number(p?.total||0),d=Number(p?.done||0);return t?Math.round(d/t*100):0}

export function Progress({progress,state}){const v=pct(progress);return <div className="tm-progress" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={v} aria-label={`${v}% done`}><span style={{width:`${v}%`}} className={`tm-progress-${state||'queued'}`}/></div>}


// The per-provider result of a task and what it did. Used by the Task manager while a task runs and by Scheduled jobs › Jobs
// once it has finished. onAdmit (Platform Admins, finished Qualify runs only) starts the separate Admit task.
export function TaskResult({job,onAdmit}){
  if(!job)return null
  return <>
    {job.kind==='qualify_adapters'&&job.state==='done'&&onAdmit&&<p className="tm-admit"><Button variant="primary" compact onClick={onAdmit} data-task-admit><CheckCircle2 size={13}/> Admit the passing fields</Button> <small className="sl-sub">A separate task. Fields already admitted stay; values entered by hand are never changed.</small></p>}
    {(job.qualifications||[]).length>0&&<div className="cf-table-wrap"><table className="cf-table tm-table"><thead><tr><th>Provider</th><th>Adapter</th><th className="num">Pages read</th>{FIELDS.map(f=><th key={f}>{FIELD_LABEL[f]}</th>)}<th>Passing</th><th>Admitted now</th></tr></thead><tbody>
      {job.qualifications.map(q=><tr key={q.provider_id} data-qualified={q.provider_id}>
        <td>{q.name}{q.country?<small className="sl-sub"> {q.country}</small>:null}</td>
        <td><Badge tone={q.adapter==='admitting'?'success':q.adapter==='testing'?'info':'neutral'}>{q.adapter||'none'}</Badge></td>
        <td className="num">{fmtNumber(q.pages_read)}</td>
        {FIELDS.map(f=>{const x=(q.fields||{})[f];if(!x)return <td key={f}>—</td>;return <td key={f} title={x.why}><span className={`tm-field ${x.pass?'tm-pass':'tm-fail'}`}>{x.pass?<CheckCircle2 size={13}/>:<XCircle size={13}/>} {fmtNumber(x.read)}{x.agree_share!=null?` · ${Math.round(x.agree_share*100)}% agree`:''}</span><br/><small className="sl-sub">{x.why}</small></td>})}
        <td>{(q.passing||[]).map(f=>FIELD_LABEL[f]).join(', ')||'—'}</td>
        <td>{(q.admitted||[]).join(', ')||'—'}</td>
      </tr>)}
    </tbody></table></div>}
    <details className="tn-items" data-task-events><summary>What this task did ({(job.events||[]).length})</summary>
      <ul className="tm-events">{(job.events||[]).map((e,i)=><li key={i}><small className="sl-sub">{fmtDateTime(e.at)}</small> {e.note}</li>)}</ul>
    </details>
  </>
}

export default function AdminTasks({rank=0,onError}){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[open,setOpen]=useState(()=>{try{return new URLSearchParams(window.location.hash.split('?')[1]||'').get('job')||''}catch{return ''}})
  const[form,setForm]=useState({country:'',state:'',provider_kind:'university',adapter_state:'enabled'})
  const timer=useRef(null)
  const load=async(id=open)=>{try{const{data,error}=await supabase.rpc('admin_jobs',{p_action:'read',p_args:id?{id}:{}});if(error)throw error;setD(data||{});setErr('')}catch(e){setErr(errText(e));onError?.(errText(e))}}
  useEffect(()=>{load(open)},[open])
  const live=Boolean((d?.jobs||[]).some(j=>['queued','running'].includes(j.state)))
  useEffect(()=>{clearInterval(timer.current);timer.current=setInterval(()=>{if(document.visibilityState==='visible')load(open)},live?5000:30000);return()=>clearInterval(timer.current)},[live,open])
  const act=async(action,args,q)=>{const reason=ask(q);if(!reason)return;setBusy(true);try{const{data,error}=await supabase.rpc('admin_jobs',{p_action:action,p_args:{...args,reason}});if(error)throw error;if(action==='start'&&data?.id)setOpen(data.id);await load(action==='start'&&data?.id?data.id:open)}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  const states=useMemo(()=>(d?.states||[]).filter(s=>!form.country||s.country===form.country),[d,form.country])
  if(!d)return <div className="m-panel"><Loading label="Loading the task manager…"/></div>
  const job=d.job,canStart=rank>=5,canAdmit=Boolean(d.can_admit)
  const startQualify=()=>act('start',{kind:'qualify_adapters',args:{country:form.country||null,state:form.state||null,provider_kind:form.provider_kind,adapter_state:form.adapter_state}},`Qualify the ${form.adapter_state} adapters${form.state?' in '+form.state:form.country?' in '+form.country:''}${form.provider_kind==='university'?' (universities only)':''}? This measures each field against the admission rules and admits nothing.`)
  const startAdmit=j=>act('start',{kind:'admit_qualified',args:{qualification_job_id:j.id}},`Admit the passing fields of every adapter measured by "${j.title}"? Fields already admitted stay. Values entered by hand are never changed.`)
  return <div className="m-page-stack" data-task-manager>
    {err&&<div className="m-alert compact" role="alert"><AlertTriangle size={15}/><span>{err}</span><button type="button" aria-label="Dismiss" onClick={()=>setErr('')}>×</button></div>}
    <section className="m-panel" data-task-start>
      <SectionTitle icon={ListChecks} title="Qualify adapters" subtitle={`Measures every chosen adapter against the admission rules: a field passes when the adapter reads it on at least ${Math.round(Number(d.settings?.min_read_share||0.5)*100)}% of the read pages and, where the catalogue already holds values, at least ${Math.round(Number(d.settings?.min_agree_share||0.9)*100)}% agree (both set under Models & services › Firecrawl › Adapter evaluation). Nothing is admitted by this run.`}/>
      <div className="tm-form">
        <label><span>Country</span><select aria-label="Country" value={form.country} onChange={e=>setForm({...form,country:e.target.value,state:''})}><option value="">Any</option>{(d.countries||[]).map(c=><option key={c.code} value={c.code}>{c.name} ({fmtNumber(c.adapters)} adapters)</option>)}</select></label>
        <label><span>State or province</span><select aria-label="State" value={form.state} onChange={e=>setForm({...form,state:e.target.value})}><option value="">Any</option>{states.map(s=><option key={s.code} value={s.code}>{s.name} ({fmtNumber(s.adapters)})</option>)}</select></label>
        <label><span>Provider kind</span><select aria-label="Provider kind" value={form.provider_kind} onChange={e=>setForm({...form,provider_kind:e.target.value})}><option value="university">Universities</option><option value="any">Any provider</option></select></label>
        <label><span>Adapter state</span><select aria-label="Adapter state" value={form.adapter_state} onChange={e=>setForm({...form,adapter_state:e.target.value})}><option value="enabled">Switched on (testing or admitting)</option><option value="testing">Testing only</option><option value="admitting">Admitting only</option></select></label>
        <Button variant="primary" disabled={!canStart||busy} onClick={startQualify}><Play size={14}/> Qualify</Button>
      </div>
      {!canStart&&<p className="sl-sub">Operators (adapters) and Platform Admins can start a Qualify run.</p>}
    </section>
    <section className="m-panel" data-task-list>
      <SectionTitle icon={RefreshCw} title="Running and waiting" subtitle={live?'Refreshes every 5 seconds. Pause and cancel take effect at the next provider, never half way through one. Finished tasks move to the Jobs tab.':'Nothing is running or waiting. Finished tasks, with their results, are under the Jobs tab.'}/>
      <div className="cf-table-wrap"><table className="cf-table tm-table"><thead><tr><th>Task</th><th>State</th><th>Progress</th><th>Result</th><th>Started by</th><th>When</th><th>Actions</th></tr></thead><tbody>
        {(d.jobs||[]).length===0&&<EmptyRow colSpan={7} text="No task is running or waiting."/>}
        {(d.jobs||[]).map(j=><tr key={j.id} data-task-row={j.id} className={open===j.id?'tm-open':''}>
          <td><button type="button" className="tm-link" onClick={()=>setOpen(open===j.id?'':j.id)}>{j.title}</button><br/><small className="sl-sub">{KIND_LABEL[j.kind]||j.kind}</small></td>
          <td><Badge tone={STATE_TONE[j.state]||'neutral'}>{j.state}</Badge>{j.cancel_requested&&j.state==='running'&&<small className="sl-sub"> cancelling…</small>}{j.pause_requested&&j.state==='running'&&<small className="sl-sub"> pausing…</small>}</td>
          <td className="tm-progress-cell"><Progress progress={j.progress} state={j.state}/><small className="sl-sub">{fmtNumber(j.progress?.done||0)} of {fmtNumber(j.progress?.total||0)}</small></td>
          <td>{j.kind==='qualify_adapters'?<>{fmtNumber(j.result?.passing||0)} with a passing field</>:<>{fmtNumber(j.result?.passing||0)} admitted</>}{Number(j.result?.errors||0)>0&&<>, <span className="tm-err">{fmtNumber(j.result.errors)} error(s)</span></>}{j.error&&<><br/><span className="tm-err">{j.error}</span></>}</td>
          <td>{j.requested_by_name}</td>
          <td>{fmtDateTime(j.finished_at||j.started_at||j.created_at)}</td>
          <td className="tm-actions">
            {['queued','running'].includes(j.state)&&<Button compact disabled={busy||j.pause_requested} onClick={()=>act('pause',{id:j.id},`Pause "${j.title}" at the next provider?`)}><Pause size={13}/> Pause</Button>}
            {j.state==='paused'&&<Button compact disabled={busy} onClick={()=>act('resume',{id:j.id},`Resume "${j.title}"?`)}><Play size={13}/> Resume</Button>}
            {['queued','running','paused'].includes(j.state)&&<Button compact disabled={busy||j.cancel_requested} onClick={()=>act('cancel',{id:j.id},`Cancel "${j.title}"? Work done so far is kept.`)}><Square size={13}/> Cancel</Button>}
          </td>
        </tr>)}
      </tbody></table></div>
    </section>
    {job&&<section className="m-panel" data-task-detail={job.id}>
      <SectionTitle icon={ListChecks} title={job.title} subtitle={`${KIND_LABEL[job.kind]||job.kind} · ${job.state} · started by ${job.requested_by_name||''} · reason: ${job.reason}`} action={<Button compact onClick={()=>setOpen('')}>Close</Button>}/>
      <TaskResult job={job} onAdmit={job.kind==='qualify_adapters'&&job.state==='done'&&canAdmit?()=>startAdmit(job):null}/>
    </section>}
  </div>
}
