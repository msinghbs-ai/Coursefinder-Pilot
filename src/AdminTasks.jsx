// CF-247 Decision 254 (6 Oct 2026, Platform Admin 06:59 and 10:56): Task manager, Phase A of the job system.
// Every long-running admin action is a job in pipeline.admin_jobs, worked by the database dispatcher a slice a minute.
// This page is the Task manager in the Windows sense (Platform Admin 6 Oct 12:01): only tasks that are waiting, running or
// paused. It starts a task, shows its progress from the database (so a refresh loses nothing), and lets a person pause,
// resume or cancel it. Finished tasks (done, failed, cancelled) live under Scheduled jobs › Jobs with the other job history. The first job kinds: Qualify adapters (read-only measurement by country, state, provider kind
// and adapter state) and Admit the passing fields (the deliberate step, Platform Admins only).
// v2.15.200 (Platform Admin 6 Oct 15:25 "Task manager doesn't seems to be the right place for the adapter qualification"):
// the Task manager starts nothing. It lists the tasks waiting, running or paused, with pause, resume and cancel. Tasks
// are started where the work is (Layer 2 › Adapters for Qualify and Admit, and every other JobButton).
// v2.15.244 (CF-247, Platform Admin 11 Oct 2026: "All background jobs using resources at any given time should be visible under
// task manager, with the controls planned. Any future feature or request follow the same guidelines"): task kinds come from the
// registry (pipeline.admin_job_kinds); "Running now" lists the scheduled jobs running this moment (pause or resume the schedule,
// run now), the worker calls on their way (shown, never killed) and the credits used this hour. On-demand scholarship tasks
// (Find scholarships now, Check scholarships for a course, Read a scholarship again) show what they found and attached.
import React,{useEffect,useRef,useState}from'react'
import{ListChecks,Play,Pause,Square,RefreshCw,CheckCircle2,XCircle,AlertTriangle}from'lucide-react'
import{supabase}from'./lib/supabase'
import{fmtTime}from'./lib/format'
import{ScholarshipJourney}from'./ScholarshipJourney'
import{Button,Badge,Loading,SectionTitle,EmptyRow,fmtDateTime,fmtNumber}from'./ui-kit'
import{Running as BackgroundJobs}from'./Progress'
import{plainError}from'./lib/errors'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
const FIELDS=['intakes','fee','english','delivery']
const FIELD_LABEL={intakes:'Intakes',fee:'Fee',english:'English',delivery:'Delivery'}
const STATE_TONE={queued:'neutral',running:'info',paused:'warning',done:'success',failed:'danger',cancelled:'neutral'}
export const KIND_LABEL={qualify_adapters:'Qualify adapters',admit_qualified:'Admit passing fields',reread_pages:'Read pages again',firecrawl_run:'Firecrawl run',adapter_apply:'Apply an adapter',central_page_read:'Read a central page',scholarship_provider_scan:'Find scholarships now',scholarship_course_check:'Check scholarships for a course',scholarship_reread:'Read a scholarship again'}
const SCH_KINDS=new Set(['scholarship_provider_scan','scholarship_course_check','scholarship_reread'])
const ago=s=>{const n=Number(s||0);return n<60?`${n} s`:n<3600?`${Math.floor(n/60)} min ${n%60} s`:`${Math.floor(n/3600)} h ${Math.floor(n%3600/60)} min`}
const MODE={scholarship_read:'Reading scholarship pages',scholarship_discover:'Finding scholarship pages',scholarship_listing:'Reading listing pages',read:'Reading course pages',link_search:'Searching for course pages'}
const PURPOSE={sch_scrape:'Scholarship pages (scraper)',sch_map:'Scholarship site maps',fc_read:'Course pages (Firecrawl run)',fc_search:'Searches (Firecrawl run)',scrape:'Course pages (scraper)',course_link_search:'Course-link search'}
const pct=p=>{const t=Number(p?.total||0),d=Number(p?.done||0);return t?Math.round(d/t*100):0}
// v2.15.331 (Platform Admin 23 Oct 2026 16:47: "i can't trust the task manager even after refreshing it nothing seems moving. UI should
// be responsive and refresh, otherwise there is no trust on the platform"): the pulse (public.admin_jobs_pulse) shows the page is alive:
// when it was last refreshed, when the task runner last ran and how many tasks it moves a minute, what is waiting, running and finished
// in the last 15 minutes, and for each task its place in line and its items (an Enrich fields task counts its items, not 0 of 0).
const ord=n=>{const v=n%100;return n+(v>=11&&v<=13?'th':({1:'st',2:'nd',3:'rd'}[n%10]||'th'))}
const timeOf=d=>fmtTime(d)
export function taskProgress(j,pj){const it=pj?.items;return it&&Number(it.total)>0?{done:Number(it.done||0),total:Number(it.total)}:j.progress}
export function taskLine(j,pj,perLane){
  const it=pj?.items,p=taskProgress(j,pj),items=it&&Number(it.total)>0
  if(j.state==='queued'){const place=Number(pj?.place||0);const when=place&&perLane?(place<=perLane?'starts within a minute':`starts in about ${Math.ceil(place/perLane)} min`):'';return `Waiting${place?` · ${ord(place)} in line`:''}${when?` · ${when}`:''}${items?` · ${fmtNumber(it.total)} item(s)`:''}`}
  return `${fmtNumber(p?.done||0)} of ${fmtNumber(p?.total||0)}${items?' item(s)':''}${items&&Number(it.with_ai)>0?` · ${fmtNumber(it.with_ai)} with the AI reader`:''}${items&&Number(it.filled)>0?` · ${fmtNumber(it.filled)} filled`:''}`
}
// hotfix D3 (Platform Admin 24 Oct 2026 13:17: "a dead task looks alive"): every running task says when it last forwarded work to its
// tool and when the next attempt is; once nothing has moved for tasks.stall_seconds it names the gate that holds it (admin_job_status_v1)
export function taskStatusLine(st){
  if(!st)return ''
  const at=v=>v?fmtTime(v):'not yet'
  return `Last forwarded ${at(st.last_forwarded_at)}${Number(st.forwarded)>0?` (${fmtNumber(st.forwarded)} sent)`:''} · next attempt ${at(st.next_attempt_at)}`
}
export function TaskBlocked({st}){
  const b=st?.blocked
  if(!b)return null
  return <small className="tm-blocked" role="status" data-task-blocked={b.code}><AlertTriangle size={12}/> <b>Blocked:</b> {b.words}{b.fix?<> · {b.fix}</>:null}</small>
}
// v2.15.333 (Platform Admin 23 Oct 2026 19:27: "Lets test openrouter where it goes bottleneck"): how the AI readers' OpenRouter requests
// went in the last 15 minutes (worker v0.43.0); rate-limited (429), server errors and timeouts say where OpenRouter pushes back.
export function orLine(o){
  const s=x=>fmtNumber(Number(x||0)),sec=ms=>ms==null?'—':`${(Number(ms)/1000).toFixed(1)} s`
  const bad=Number(o.http429||0)+Number(o.http5xx||0)+Number(o.timeout||0)
  return `OpenRouter (15 min): ${s(o.calls)} request(s) from ${s(o.worker_calls)} AI reader call(s)${Number(o.worker_open)>0?` (${s(o.worker_open)} running)`:''}, ${s(o.ok)} answered, typical ${sec(o.ms_p50)}, slowest ${sec(o.ms_p95)}${bad?` · ${s(o.http429)} rate-limited (429), ${s(o.http5xx)} server error(s), ${s(o.timeout)} timed out`:' · none rate-limited'}${Number(o.worker_failed)>0?` · ${s(o.worker_failed)} AI reader call(s) failed`:''}.`
}
export function TaskPulse({pulse,loadedAt}){
  if(!pulse)return null
  const r=pulse.runner||{},o=pulse.openrouter||{},late=(r.seconds_ago!=null&&Number(r.seconds_ago)>150)||(Number(o.calls)>0&&Number(o.http429||0)+Number(o.http5xx||0)+Number(o.timeout||0)>Number(o.calls)*0.05)
  return <div className={`m-alert compact${late?'':' tm-pulse-ok'}`} role="status" aria-live="polite" data-task-pulse data-task-pulse-late={late?'1':'0'}>
    {late?<AlertTriangle size={15}/>:<RefreshCw size={15}/>}
    <span><b>{r.seconds_ago!=null&&Number(r.seconds_ago)>150?`The task runner has not run for ${ago(r.seconds_ago)}.`:late?'OpenRouter is pushing back: lower Enrich fields: AI calls at once.':'Live.'}</b> Refreshed {timeOf(loadedAt)}. Task runner last ran {r.seconds_ago!=null?`${ago(r.seconds_ago)} ago`:'—'} and moves up to {fmtNumber(pulse.per_lane||1)} task(s) per lane each minute. <span data-task-counts>{fmtNumber(pulse.queued||0)} waiting · {fmtNumber(pulse.running||0)} running{Number(pulse.paused)>0?` · ${fmtNumber(pulse.paused)} paused`:''} · {fmtNumber(pulse.finished_15m||0)} finished in the last 15 minutes (Jobs tab)</span>. AI reader: {fmtNumber(pulse.ai_waiting||0)} value(s) waiting, {fmtNumber(pulse.ai_done_15m||0)} read in the last 15 minutes.{pulse.openrouter&&Number(pulse.openrouter.worker_calls)>0&&<> <span data-task-openrouter>{orLine(pulse.openrouter)}</span></>}</span>
  </div>
}

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
    {SCH_KINDS.has(job.kind)&&<><SchResult r={job.result||{}} kind={job.kind}/><ScholarshipJourney jobId={job.id}/></>}
    <details className="tn-items" data-task-events><summary>What this task did ({(job.events||[]).length})</summary>
      <ul className="tm-events">{(job.events||[]).map((e,i)=><li key={i}><small className="sl-sub">{fmtDateTime(e.at)}</small> {e.note}</li>)}</ul>
    </details>
  </>
}

// What an on-demand scholarship task found and attached (11 Oct 2026)
function SchResult({r,kind}){
  return <div className="tm-sch" data-task-sch>
    <p><b>{r.phase_detail||'—'}</b> · {fmtNumber(r.done||0)} of {fmtNumber(r.total||0)} scholarship page(s) read · {fmtNumber(r.new_scholarships||0)} new scholarship(s) · course links changed on {fmtNumber(r.links_changed||0)} · {fmtNumber(r.credits||0)} credit(s){Number(r.candidates_waiting)>0?` · ${fmtNumber(r.candidates_waiting)} candidate page(s) waiting`:''}</p>
    {kind==='scholarship_course_check'&&<p>This course now has <b>{fmtNumber(r.linked_now||0)}</b> scholarship(s).{(r.added||[]).length>0&&<> Added: {(r.added||[]).map(x=><a key={x.id} href={`#scholarships?id=${x.id}`}>{x.name}</a>).reduce((a,b)=>[a,', ',b])}.</>}{(r.removed||[]).length>0&&<> No longer linked: {(r.removed||[]).map(x=>x.name).join(', ')}.</>}</p>}
  </div>
}

// Everything using resources (11 Oct 2026; v2.15.246, Platform Admin bugs 11/10-3, Fix 3: "Tasks manager was supposed to represent
// every Job running ... which consumes resources on the Platform - but shows nothing"): what is running this moment, every
// scheduled job that ran in the last 15 minutes with the time it used and its controls, every worker or API call by kind, AI and
// scraper spend, and the work waiting in each queue with the job that drains it. A scheduled job missing from the catalogue is
// flagged (standing rule G1). The board always shows, even when the read fails, so an empty page never hides a problem.
const QUEUE_TONE=n=>n>1000?'warning':n>0?'info':'neutral'
// v2.15.266: RunningNow (scheduled jobs running, worker calls, AI calls, credits, work waiting) moved to Coverage & completeness › Progress › Running now.

export default function AdminTasks({rank=0,onError}){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[open,setOpen]=useState(()=>{try{return new URLSearchParams(window.location.hash.split('?')[1]||'').get('job')||''}catch{return ''}})
  const timer=useRef(null)
  const[pulse,setPulse]=useState(null),[loadedAt,setLoadedAt]=useState(null)
  const load=async(id=open)=>{try{const{data,error}=await supabase.rpc('admin_jobs',{p_action:'read',p_args:id?{id,running:true}:{running:true}});if(error)throw error;setD(data||{});setErr('');setLoadedAt(new Date().toISOString())}catch(e){setErr(errText(e));onError?.(errText(e))}
    // the pulse is extra: if it cannot be read the list still shows
    try{const{data,error}=await supabase.rpc('admin_jobs_pulse');if(!error)setPulse(data||null)}catch{}}
  useEffect(()=>{load(open)},[open])
  const live=Boolean((d?.jobs||[]).some(j=>['queued','running'].includes(j.state)))
  useEffect(()=>{clearInterval(timer.current);timer.current=setInterval(()=>{if(document.visibilityState==='visible')load(open)},live?5000:30000);return()=>clearInterval(timer.current)},[live,open])
  const act=async(action,args,q)=>{const reason=ask(q);if(!reason)return;setBusy(true);try{const{data,error}=await supabase.rpc('admin_jobs',{p_action:action,p_args:{...args,reason}});if(error)throw error;if(action==='start'&&data?.id)setOpen(data.id);await load(action==='start'&&data?.id?data.id:open)}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(!d)return <div className="m-page-stack" data-task-manager>{err?<div className="m-alert compact" role="alert"><AlertTriangle size={15}/><span>The task manager could not be read: {err}</span><button type="button" onClick={()=>load(open)}>Try again</button></div>:<div className="m-panel"><Loading label="Loading the task manager…"/></div>}</div>
  const job=d.job,canAdmit=Boolean(d.can_admit),kinds=d.kinds||{}
  const label=k=>kinds[k]?.label||KIND_LABEL[k]||k
  const startAdmit=j=>act('start',{kind:'admit_qualified',args:{qualification_job_id:j.id}},`Admit the passing fields of every adapter measured by "${j.title}"? Fields already admitted stay. Values entered by hand are never changed.`)
  return <div className="m-page-stack" data-task-manager>
    {err&&<div className="m-alert compact" role="alert"><AlertTriangle size={15}/><span>{err}</span><button type="button" aria-label="Dismiss" onClick={()=>setErr('')}>×</button></div>}
    <section className="m-panel" data-task-list>
      <SectionTitle icon={RefreshCw} title="Tasks started by people" subtitle={live?'Includes tasks started by enrichment plans (Started by says which). Refreshes every 5 seconds. Pause and cancel take effect at the next provider, never half way through one. Finished tasks move to the Jobs tab.':'Nothing is running or waiting. Finished tasks, with their results, are under the Jobs tab.'}/>
      <TaskPulse pulse={pulse} loadedAt={loadedAt}/>
      <div className="cf-table-wrap"><table className="cf-table tm-table"><thead><tr><th>Task</th><th>State</th><th>Progress</th><th>Result</th><th>Started by</th><th>When</th><th>Actions</th></tr></thead><tbody>
        {(d.jobs||[]).length===0&&<EmptyRow colSpan={7} text="No task started by a person is running or waiting. Background jobs are below."/>}
        {(d.jobs||[]).map(j=><tr key={j.id} data-task-row={j.id} className={open===j.id?'tm-open':''}>
          <td><button type="button" className="tm-link" onClick={()=>setOpen(open===j.id?'':j.id)}>{j.title}</button><br/><small className="sl-sub">{label(j.kind)}</small></td>
          <td><Badge tone={STATE_TONE[j.state]||'neutral'}>{j.state}</Badge>{j.cancel_requested&&j.state==='running'&&<small className="sl-sub"> cancelling…</small>}{j.pause_requested&&j.state==='running'&&<small className="sl-sub"> pausing…</small>}</td>
          <td className="tm-progress-cell"><Progress progress={taskProgress(j,pulse?.jobs?.[j.id])} state={j.state}/><small className="sl-sub" data-task-line>{taskLine(j,pulse?.jobs?.[j.id],Number(pulse?.per_lane||1))}</small>{j.state==='running'&&j.status&&<small className="sl-sub" data-task-status>{taskStatusLine(j.status)}</small>}<TaskBlocked st={j.status}/></td>
          <td>{SCH_KINDS.has(j.kind)?<>{j.result?.phase_detail||'Starting'}{j.result?.new_scholarships?` · ${fmtNumber(j.result.new_scholarships)} new`:''}{j.result?.credits!=null?` · ${fmtNumber(j.result.credits)} credit(s)`:''}</>:j.kind==='qualify_adapters'?<>{fmtNumber(j.result?.passing||0)} with a passing field</>:<>{fmtNumber(j.result?.passing||0)} admitted</>}{Number(j.result?.errors||0)>0&&<>, <span className="tm-err">{fmtNumber(j.result.errors)} error(s)</span></>}{j.error&&<><br/><span className="tm-err">{j.error}</span></>}</td>
          {/* v2.15.307: a task an enrichment plan started says so; automatic plans run as the Platform Admin who switched them on */}
          <td>{j.args?.plan_mode?<><span data-task-plan={j.args.plan_mode}>{j.args.plan_mode==='auto'?'Enrichment plan (automatic)':'Enrichment plan (Run now)'}</span><br/><small className="sl-sub">{j.args.plan_mode==='auto'?'runs as ':'by '}{j.requested_by_name}</small></>:j.requested_by_name}</td>
          <td>{fmtDateTime(j.finished_at||j.started_at||j.created_at)}</td>
          <td className="tm-actions">
            {['queued','running'].includes(j.state)&&(kinds[j.kind]?kinds[j.kind].can_pause:!SCH_KINDS.has(j.kind))&&<Button compact disabled={busy||j.pause_requested} onClick={()=>act('pause',{id:j.id},`Pause "${j.title}" at the next provider?`)}><Pause size={13}/> Pause</Button>}
            {j.state==='paused'&&<Button compact disabled={busy} onClick={()=>act('resume',{id:j.id},`Resume "${j.title}"?`)}><Play size={13}/> Resume</Button>}
            {['queued','running','paused'].includes(j.state)&&<Button compact disabled={busy||j.cancel_requested} onClick={()=>act('cancel',{id:j.id},`Cancel "${j.title}"? Work done so far is kept.`)}><Square size={13}/> Cancel</Button>}
          </td>
        </tr>)}
      </tbody></table></div>
    </section>
    {/* v2.15.285 (Platform Admin 16 Oct 2026: "Task manager doesnt show any job running in the background"; standing rule 11 Oct 2026: "All
        background jobs using resources at any given time should be visible under task manager"): the background jobs board is back here,
        the same board as Coverage & completeness › Progress › Running now (one component, one read). */}
    <section className="m-panel" data-task-background>
      <SectionTitle icon={RefreshCw} title="Background jobs" subtitle="Scheduled jobs and workers using the platform: running this moment, failing, paused, Firecrawl credits in the last hour. Pause, resume or run a job now."/>
      <BackgroundJobs rank={rank} onError={onError}/>
    </section>
    {/* v2.15.301: Progress › Running now retired; this is the board. The jobs by journey stage are on Layer 2/3 › Operations. */}
    <p className="sd-desc" data-task-running-link>The jobs by stage of the journey: <a className="cf-link" href="#layer-2-discovery">Layer 2/3 Build &amp; enrich › Operations</a>.</p>
    {job&&<section className="m-panel" data-task-detail={job.id}>
      <SectionTitle icon={ListChecks} title={job.title} subtitle={`${label(job.kind)} · ${job.state} · started by ${job.requested_by_name||''} · reason: ${job.reason}`} action={<Button compact onClick={()=>setOpen('')}>Close</Button>}/>
      <TaskResult job={job} onAdmit={job.kind==='qualify_adapters'&&job.state==='done'&&canAdmit?()=>startAdmit(job):null}/>
    </section>}
  </div>
}
