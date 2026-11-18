// Automations (v2.15.110): every scheduled job on the platform, in plain words, grouped by area. For each one: what it
// does, how often it runs (times in Melbourne time), its last run and the last 24 hours. Platform Admins can pause or resume one
// job or a whole area, run a job now, change how often it runs and, where the job works in batches, the batch size.
// Three upkeep jobs (health checks, job-history trim, duplicate-file removal) need the top admin role. Every change is
// logged and shown under "Recent changes".
// Read: public.admin_automations_read(); write: public.admin_automation_control(job, action, args)
// (migration 20260930050000_cf247_ui_control_sweep).
// Pipeline maintenance (pause every job for a database change): PipelineMaintenance.jsx, public.admin_pipeline_maintenance (20261115180000).
import React,{useEffect,useMemo,useState}from'react'
import{AlarmClock,Pause,Play,RefreshCw,Save,Zap}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Badge,Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDate,fmtDateTime,fmtNumber}from'./ui-kit'
import{EVERY,describeSchedule}from'./automation-schedule'
import{plainError}from'./lib/errors'
import{controlOwner,ADMISSION_PATHS,ADMISSION_WORDS,RETIREMENT_CRITERIA}from'./guide/operatingWords'
import PipelineMaintenance from'./PipelineMaintenance'


const STATUS={succeeded:['success','Succeeded'],failed:['danger','Failed'],running:['info','Running'],starting:['info','Starting']}
// v2.16.39 (Platform Admin 18 Nov 2026 12:50, Operations aligned with the consolidated dispatchers): the three dispatchers that took over the
// legacy scheduled jobs (CURRENT-STATE section 4) lead the tab, each with its lanes; jobs a dispatcher (or another job) replaced are retired and
// are hidden until "Show retired legacy jobs" is ticked, so the counts above are the jobs that still matter.
export const DISPATCHERS=[
  {job:'rollup-scheduler',label:'Reports and caches',what:'Runs every report and cache refresh from its own list (pipeline.rollup_targets).'},
  {job:'admission-rule-runner',label:'Admission rules',what:'Runs every admission rule from its own list (pipeline.admission_rules), in three lanes.'},
  {job:'coverage-lane-dispatch',label:'Coverage lanes',what:'Runs the coverage worker lanes from the field execution registry (pipeline.field_execution_registry), in three lanes.'},
]
export const lanesOf=(jobs,base)=>jobs.filter(j=>j.job===base||new RegExp(`^${base}-[a-z]$`).test(j.job))
export const replacedBy=(jobs,base)=>jobs.filter(j=>j.retirement&&String(j.retirement.replaced_by||'').startsWith(base)).length
export const isRetired=j=>Boolean(j?.retirement)

const ACTION_LABEL={pause:'Paused',resume:'Resumed',pause_area:'Area paused',resume_area:'Area resumed',run_now:'Run now',set_every:'Frequency changed',set_batch:'Batch size changed'}

// v2.15.131 (au-error-text): known database errors in plain words; the original text stays in the tooltip.
export default function Automations({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[failed,setFailed]=useState(''),[area,setArea]=useState('all'),[show,setShow]=useState('all'),[q,setQ]=useState(''),[retired,setRetired]=useState(false)
  const load=async()=>{setBusy(true);setFailed('');try{const{data:d,error}=await supabase.rpc('admin_automations_read');if(error)throw error;setData(d||{})}catch(e){setFailed(e.message||String(e))}finally{setBusy(false)}}
  const act=async(job,action,args={},confirmText)=>{if(confirmText&&!window.confirm(confirmText))return false;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_automation_control',{p_job:job,p_action:action,p_args:args});if(error)throw error;setData(d||{});return true}catch(e){onError?.(e.message||String(e));return false}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  const everyJob=data?.jobs||[],rank=Number(data?.rank||0),retiredCount=everyJob.filter(isRetired).length
  const jobs=useMemo(()=>retired?everyJob:everyJob.filter(j=>!isRetired(j)),[everyJob,retired])
  const areas=useMemo(()=>[...new Set(jobs.map(j=>j.area))],[jobs])
  const shown=jobs.filter(j=>(area==='all'||j.area===area)&&(show==='all'||(show==='paused'&&!j.active)||(show==='failed'&&Number(j.failed_24h)>0))&&(!q||`${j.label} ${j.description} ${j.job}`.toLowerCase().includes(q.toLowerCase())))
  if(!data&&!failed)return <section className="m-panel"><Loading label="Loading automations…"/></section>
  if(failed&&!data)return <section className="m-panel"><Empty text={`Automations could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const paused=jobs.filter(j=>!j.active).length,failing=jobs.filter(j=>Number(j.failed_24h)>0).length,runs=jobs.reduce((n,j)=>n+Number(j.runs_24h||0),0)
  return <>
    {/* Pipeline Maintenance Mode (Platform Admin 15 Nov 2026): pause every job before a database change, resume exactly those jobs */}
    <PipelineMaintenance rank={rank} onError={onError} onChanged={load}/>
    <Dispatchers jobs={everyJob}/>
    <div className="cf-metric-grid">
      <Metric label="Automations" value={`${fmtNumber(jobs.length-paused)} running`} detail={`${paused?`${fmtNumber(paused)} paused`:'None paused'}${!retired&&retiredCount?` · ${fmtNumber(retiredCount)} retired, hidden`:''}`} icon={AlarmClock} tone={paused?'warning':'success'}/>
      <Metric label="Runs in the last 24 hours" value={fmtNumber(runs)} icon={Zap}/>
      <Metric label="Failed in the last 24 hours" value={failing?`${failing} automation${failing===1?'':'s'}`:'None'} tone={failing?'danger':'success'} icon={AlarmClock}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={AlarmClock} title="Automations" subtitle="Everything the platform runs on a schedule, in plain words. Times are Melbourne time." action={<div className="l3c-actions">
        <input className="au-search" type="search" placeholder="Find an automation" value={q} onChange={e=>setQ(e.target.value)} aria-label="Find an automation"/>
        <select className="fv-filter" value={area} onChange={e=>setArea(e.target.value)} aria-label="Area"><option value="all">All areas</option>{areas.map(a=><option key={a} value={a}>{a}</option>)}</select>
        <select className="fv-filter" value={show} onChange={e=>setShow(e.target.value)} aria-label="Show"><option value="all">All</option><option value="paused">Paused ({paused})</option><option value="failed">Failed in 24h ({failing})</option></select>
        <label className="fcc-only au-retired-toggle"><input type="checkbox" checked={retired} onChange={e=>setRetired(e.target.checked)} data-au-show-retired/> Show retired legacy jobs ({fmtNumber(retiredCount)})</label>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button></div>}/>
      {rank<5&&<p className="l3v-note">You can view automations. Each one names the role that changes it (PIM Admin or Platform Admin): note the job, the error and when, and hand it to that role.</p>}
    </section>
    {/* SS-020 step 2 (Decision 269, 3 Nov 2026): each area starts collapsed (the tab was about 40,800 px with 486 buttons); a search or a
        Paused or Failed filter opens the areas that match, and an area with a failure in 24 hours says so on its closed header */}
    {areas.filter(a=>shown.some(j=>j.area===a)).map(a=><AreaPanel key={a} area={a} jobs={shown.filter(j=>j.area===a)} all={jobs.filter(j=>j.area===a)} rank={rank} busy={busy} act={act} filtered={Boolean(q)||show!=='all'||retired}/>)}
    {!shown.length&&<section className="m-panel"><Empty text="No automation matches."/></section>}
    <section className="m-panel"><SectionTitle title="Recent changes"/>
      {(data.events||[]).length?<ul className="l3c-events">{data.events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{ACTION_LABEL[e.action]||e.action}</strong><small>{[everyJob.find(j=>j.job===e.target)?.label||e.target,e.detail?.minutes&&EVERY.find(x=>x[0]===Number(e.detail.minutes))?.[1],e.detail?.batch&&`batch ${e.detail.batch}`].filter(Boolean).join(' · ')}</small></li>)}</ul>:<Empty text="No changes recorded."/>}
    </section>
  </>
}

function Dispatchers({jobs}){
  return <section className="m-panel au-dispatchers" data-au-dispatchers>
    <SectionTitle icon={Zap} title="Dispatchers" subtitle="Three dispatchers run what used to be separate scheduled jobs. Each takes its work from its own list every minute; the jobs it replaced are retired and kept switched off until they are removed."/>
    <div className="au-dispatcher-grid">{DISPATCHERS.map(d=>{const lanes=lanesOf(jobs,d.job),on=lanes.filter(j=>j.active).length,runs=lanes.reduce((n,j)=>n+Number(j.runs_24h||0),0),bad=lanes.reduce((n,j)=>n+Number(j.failed_24h||0),0)
      const last=lanes.map(j=>j.last).filter(Boolean).sort((a,b)=>String(b.at).localeCompare(String(a.at)))[0],took=replacedBy(jobs,d.job)
      const tone=!lanes.length?'neutral':on<lanes.length?'warning':bad?'danger':'success'
      return <article key={d.job} className="au-dispatcher" data-au-dispatcher={d.job}>
        <header><strong>{d.label}</strong><StatusChip value={tone} tone={tone} label={!lanes.length?'Not found':on===lanes.length?(bad?'Failures in 24 hours':'Running'):`${on} of ${lanes.length} lanes on`}/></header>
        <code>{d.job}</code><p>{d.what}</p>
        <dl><div><dt>Lanes</dt><dd>{fmtNumber(lanes.length)}</dd></div><div><dt>Runs in 24 hours</dt><dd>{fmtNumber(runs)}</dd></div><div><dt>Failed</dt><dd className={bad?'l3v-bad':''}>{fmtNumber(bad)}</dd></div><div><dt>Legacy jobs replaced</dt><dd data-au-replaced>{fmtNumber(took)}</dd></div></dl>
        <small>{last?`Last run ${fmtDateTime(last.at)}`:'Not run yet'}</small>
      </article>})}</div>
  </section>
}

function AreaPanel({area,jobs,all,rank,busy,act,filtered}){
  const off=all.filter(j=>!j.active&&!j.retirement).length,can=rank>=5&&!busy // UR-07: retired jobs are not counted as resumable
  const failing=all.filter(j=>Number(j.failed_24h)>0).length,[opened,setOpened]=useState(false),open=opened||filtered
  return <section className="m-panel au-area" data-area={area} data-area-open={open?'yes':'no'}>
    <SectionTitle title={<button type="button" className="cf-linkbtn au-area-toggle" aria-expanded={open} onClick={()=>setOpened(!opened)} data-area-toggle={area}>{open?'▾':'▸'} {area}</button>} subtitle={`${all.length} automation${all.length===1?'':'s'}${off?`, ${off} paused`:''}${failing?`, ${failing} failed in 24 hours`:''}`} action={rank>=5&&<div className="l3c-actions">
      <Button compact onClick={()=>act(null,'pause_area',{area},`Pause every automation in ${area}?`)} disabled={!can||off===all.length}><Pause size={14}/>Pause area</Button>
      <Button compact onClick={()=>act(null,'resume_area',{area})} disabled={!can||off===0}><Play size={14}/>Resume area</Button></div>}/>
    {open&&<div className="cf-table-wrap"><table className="cf-table au-table"><thead><tr><th>Automation</th><th>How often</th><th>Last run</th><th className="num">Last 24 hours</th><th>State</th>{rank>=5&&<th>Change</th>}</tr></thead><tbody>
      {jobs.map(j=><JobRow key={j.job} j={j} rank={rank} busy={busy} act={act}/>)}
    </tbody></table></div>}
  </section>
}

// UI audit Phase 1 (24 Oct 2026): a decision reference "(Decision 262 …)" is for the change log, not the row; the full text stays on hover
export const plainDescription=t=>String(t||'').replace(/\s*\((?:Decision|Decisions)\s+\d+[^)]*\)/gi,'').replace(/\s{2,}/g,' ').trim()
function JobRow({j,rank,busy,act}){
  const s=describeSchedule(j.schedule),[batch,setBatch]=useState(j.batch==null?'':String(j.batch))
  useEffect(()=>setBatch(j.batch==null?'':String(j.batch)),[j.batch])
  const allowed=rank>=Number(j.control_rank||6),can=allowed&&!busy,last=j.last,st=STATUS[last?.status]||['neutral',last?.status||'—']
  // SS-016 UR-08 (Platform Admin 1 Nov 2026 22:01): the same words as the Platform guide: who changes it, and how its values get in
  const owner=controlOwner(j.control_rank),adm=ADMISSION_PATHS.find(x=>x.job===j.job)
  return <tr className={j.active?'':'l3c-off'} data-job={j.job}>
    <td title={j.job}><strong>{j.label||j.job}</strong><span className="au-desc" title={j.description||undefined}>{plainDescription(j.description)}</span>{j.catalogued===false&&<Badge tone="warning" data-uncatalogued-job>Not catalogued: no label or owner</Badge>}
      <span className="l3v-code" data-control-owner={owner}>Changed by {owner}</span>{adm&&<span className="l3v-code" data-admission-path={adm.path} title={adm.person}>{ADMISSION_WORDS[adm.path]}{adm.path==='auto'?`: ${adm.switch}`:''}</span>}</td>
    <td>{s.text}{j.batch!=null&&<span className="l3v-code">{fmtNumber(j.batch)} per run</span>}</td>
    <td>{last?<><StatusChip value={last.status} tone={st[0]} label={st[1]}/><span className="l3v-code">{fmtDateTime(last.at)}{last.seconds!=null&&` · ${last.seconds}s`}</span>{last.message&&<span className="au-error">{plainError(last.message)}</span>}</>:'Not run yet'}</td>
    <td className="num">{fmtNumber(j.runs_24h||0)} runs<span className={`l3v-code ${Number(j.failed_24h)>0?'l3v-bad':''}`}>{fmtNumber(j.failed_24h||0)} failed</span></td>
    <td>{j.retirement?<StatusChip value={j.retirement.status} tone="neutral" label={j.retirement.status==='retired'?'Retired':'Retiring'}/>:<StatusChip value={j.active?'on':'paused'} tone={j.active?'success':'warning'} label={j.active?'Running':'Paused'}/>}</td>
    {rank>=5&&<td>{j.retirement?<span className="l3v-note" data-retired-job={j.job}>{/* UR-07 (1 Nov 2026): no Resume, run or schedule controls for a retired job */}Retired{j.retirement.replaced_by?`: replaced by ${j.retirement.replaced_by}`:': no replacement named yet, so removal needs an approved decision'}{j.retirement.retire_after?` · removal after ${fmtDate(j.retirement.retire_after)}`:''}. History stays visible.{j.retirement.note&&<small data-retired-note> {j.retirement.note}</small>}
        {/* SS-016 UR-12 (Platform Admin 1 Nov 2026 22:01): the checks before removal, beside the retiring job */}
        <details data-retirement-criteria><summary>Checks before removal</summary><ul>{RETIREMENT_CRITERIA.map(c=><li key={c}>{c}</li>)}</ul></details></span>:allowed?<div className="au-controls">
      <div className="l3c-row-actions">
        {j.active?<Button compact onClick={()=>act(j.job,'pause',{},`Pause "${j.label}"?`)} disabled={!can} aria-label="Pause" title="Pause"><Pause size={14}/></Button>
          :<Button compact variant="primary" onClick={()=>act(j.job,'resume')} disabled={!can}><Play size={14}/>Resume</Button>}
        <Button compact onClick={()=>act(j.job,'run_now',{},`Run "${j.label}" now? It runs once, in addition to its schedule.`)} disabled={!can} aria-label="Run now" title="Run now (once, in addition to the schedule)"><Zap size={14}/></Button>
      </div>
      <select className="fv-input" value={s.every&&EVERY.some(x=>x[0]===s.every)?String(s.every):''} onChange={e=>{const v=Number(e.target.value);if(v)act(j.job,'set_every',{minutes:v},`Run "${j.label}" ${EVERY.find(x=>x[0]===v)[1].toLowerCase()}?`)}} disabled={!can} aria-label={`How often ${j.label} runs`}>
        <option value="">{s.every&&EVERY.some(x=>x[0]===s.every)?'':'Change how often…'}</option>{EVERY.map(([v,l])=><option key={v} value={v}>{l}</option>)}</select>
      {j.batch!=null&&<form className="au-batch" onSubmit={e=>{e.preventDefault();act(j.job,'set_batch',{batch:Number(batch)})}}>
        <input className="fv-input" type="number" min="1" max="500" value={batch} onChange={e=>setBatch(e.target.value)} disabled={!can} aria-label={`Batch size for ${j.label}`}/>
        <Button compact type="submit" disabled={!can||!(Number(batch)>=1&&Number(batch)<=500)||Number(batch)===Number(j.batch)}><Save size={14}/>Save</Button></form>}
    </div>:<span className="l3v-note" data-control-denied data-job-owner>{owner} only</span>}</td>}
  </tr>
}
