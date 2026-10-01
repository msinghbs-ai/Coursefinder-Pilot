// Automations (v2.15.110): every scheduled job on the platform, in plain words, grouped by area. For each one: what it
// does, how often it runs (times in Melbourne time), its last run and the last 24 hours. Platform Admins can pause or resume one
// job or a whole area, run a job now, change how often it runs and, where the job works in batches, the batch size.
// Three upkeep jobs (health checks, job-history trim, duplicate-file removal) need the top admin role. Every change is
// logged and shown under "Recent changes".
// Read: public.admin_automations_read(); write: public.admin_automation_control(job, action, args)
// (migration 20260930050000_cf247_ui_control_sweep).
import React,{useEffect,useMemo,useState}from'react'
import{AlarmClock,Pause,Play,RefreshCw,Save,Zap}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{EVERY,describeSchedule}from'./automation-schedule'


const STATUS={succeeded:['success','Succeeded'],failed:['danger','Failed'],running:['info','Running'],starting:['info','Starting']}
const ACTION_LABEL={pause:'Paused',resume:'Resumed',pause_area:'Area paused',resume_area:'Area resumed',run_now:'Run now',set_every:'Frequency changed',set_batch:'Batch size changed'}

// v2.15.131 (au-error-text): known database errors in plain words; the original text stays in the tooltip.
const ERRORS=[[/statement timeout/i,'Took too long and was stopped by the database time limit'],[/deadlock/i,'Clashed with another job and was stopped; it will run again'],[/could not obtain lock|lock timeout/i,'Another job was using the same data; it will run again'],[/permission denied/i,'Not allowed to run: a permission is missing'],[/connection|network|fetch failed/i,'Could not connect; it will run again']]
const plainError=m=>{const hit=ERRORS.find(([r])=>r.test(String(m||'')));return hit?hit[1]:String(m||'').replace(/^ERROR:\s*/i,'').slice(0,160)}
export default function Automations({onError}){
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[failed,setFailed]=useState(''),[area,setArea]=useState('all'),[show,setShow]=useState('all'),[q,setQ]=useState('')
  const load=async()=>{setBusy(true);setFailed('');try{const{data:d,error}=await supabase.rpc('admin_automations_read');if(error)throw error;setData(d||{})}catch(e){setFailed(e.message||String(e))}finally{setBusy(false)}}
  const act=async(job,action,args={},confirmText)=>{if(confirmText&&!window.confirm(confirmText))return false;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_automation_control',{p_job:job,p_action:action,p_args:args});if(error)throw error;setData(d||{});return true}catch(e){onError?.(e.message||String(e));return false}finally{setBusy(false)}}
  useEffect(()=>{load()},[])
  const jobs=data?.jobs||[],rank=Number(data?.rank||0)
  const areas=useMemo(()=>[...new Set(jobs.map(j=>j.area))],[jobs])
  const shown=jobs.filter(j=>(area==='all'||j.area===area)&&(show==='all'||(show==='paused'&&!j.active)||(show==='failed'&&Number(j.failed_24h)>0))&&(!q||`${j.label} ${j.description} ${j.job}`.toLowerCase().includes(q.toLowerCase())))
  if(!data&&!failed)return <section className="m-panel"><Loading label="Loading automations…"/></section>
  if(failed&&!data)return <section className="m-panel"><Empty text={`Automations could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const paused=jobs.filter(j=>!j.active).length,failing=jobs.filter(j=>Number(j.failed_24h)>0).length,runs=jobs.reduce((n,j)=>n+Number(j.runs_24h||0),0)
  return <>
    <div className="cf-metric-grid">
      <Metric label="Automations" value={`${jobs.length-paused} running`} detail={paused?`${paused} paused`:'None paused'} icon={AlarmClock} tone={paused?'warning':'success'}/>
      <Metric label="Runs in the last 24 hours" value={fmtNumber(runs)} icon={Zap}/>
      <Metric label="Failed in the last 24 hours" value={failing?`${failing} automation${failing===1?'':'s'}`:'None'} tone={failing?'danger':'success'} icon={AlarmClock}/>
    </div>
    <section className="m-panel">
      <SectionTitle icon={AlarmClock} title="Automations" subtitle="Everything the platform runs on a schedule, in plain words. Times are Melbourne time." action={<div className="l3c-actions">
        <input className="au-search" type="search" placeholder="Find an automation" value={q} onChange={e=>setQ(e.target.value)} aria-label="Find an automation"/>
        <select className="fv-filter" value={area} onChange={e=>setArea(e.target.value)} aria-label="Area"><option value="all">All areas</option>{areas.map(a=><option key={a} value={a}>{a}</option>)}</select>
        <select className="fv-filter" value={show} onChange={e=>setShow(e.target.value)} aria-label="Show"><option value="all">All</option><option value="paused">Paused ({paused})</option><option value="failed">Failed in 24h ({failing})</option></select>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Updating…':'Refresh'}</Button></div>}/>
      {rank<5&&<p className="l3v-note">You can view automations. Only a Platform Admin can change them.</p>}
    </section>
    {areas.filter(a=>shown.some(j=>j.area===a)).map(a=><AreaPanel key={a} area={a} jobs={shown.filter(j=>j.area===a)} all={jobs.filter(j=>j.area===a)} rank={rank} busy={busy} act={act}/>)}
    {!shown.length&&<section className="m-panel"><Empty text="No automation matches."/></section>}
    <section className="m-panel"><SectionTitle title="Recent changes"/>
      {(data.events||[]).length?<ul className="l3c-events">{data.events.map((e,i)=><li key={i}><span>{fmtDateTime(e.at)}</span><strong>{ACTION_LABEL[e.action]||e.action}</strong><small>{[jobs.find(j=>j.job===e.target)?.label||e.target,e.detail?.minutes&&EVERY.find(x=>x[0]===Number(e.detail.minutes))?.[1],e.detail?.batch&&`batch ${e.detail.batch}`].filter(Boolean).join(' · ')}</small></li>)}</ul>:<Empty text="No changes recorded."/>}
    </section>
  </>
}

function AreaPanel({area,jobs,all,rank,busy,act}){
  const off=all.filter(j=>!j.active).length,can=rank>=5&&!busy
  return <section className="m-panel au-area" data-area={area}>
    <SectionTitle title={area} subtitle={`${all.length} automation${all.length===1?'':'s'}${off?`, ${off} paused`:''}`} action={rank>=5&&<div className="l3c-actions">
      <Button compact onClick={()=>act(null,'pause_area',{area},`Pause every automation in ${area}?`)} disabled={!can||off===all.length}><Pause size={14}/>Pause area</Button>
      <Button compact onClick={()=>act(null,'resume_area',{area})} disabled={!can||off===0}><Play size={14}/>Resume area</Button></div>}/>
    <div className="cf-table-wrap"><table className="cf-table au-table"><thead><tr><th>Automation</th><th>How often</th><th>Last run</th><th className="num">Last 24 hours</th><th>State</th>{rank>=5&&<th>Change</th>}</tr></thead><tbody>
      {jobs.map(j=><JobRow key={j.job} j={j} rank={rank} busy={busy} act={act}/>)}
    </tbody></table></div>
  </section>
}

function JobRow({j,rank,busy,act}){
  const s=describeSchedule(j.schedule),[batch,setBatch]=useState(j.batch==null?'':String(j.batch))
  useEffect(()=>setBatch(j.batch==null?'':String(j.batch)),[j.batch])
  const allowed=rank>=Number(j.control_rank||6),can=allowed&&!busy,last=j.last,st=STATUS[last?.status]||['neutral',last?.status||'—']
  return <tr className={j.active?'':'l3c-off'} data-job={j.job}>
    <td><strong>{j.label}</strong><span className="au-desc">{j.description}</span><span className="l3v-code">{j.job}</span></td>
    <td>{s.text}{j.batch!=null&&<span className="l3v-code">{fmtNumber(j.batch)} per run</span>}</td>
    <td>{last?<><StatusChip value={last.status} tone={st[0]} label={st[1]}/><span className="l3v-code">{fmtDateTime(last.at)}{last.seconds!=null&&` · ${last.seconds}s`}</span>{last.message&&<span className="au-error" title={last.message}>{plainError(last.message)}</span>}</>:'Not run yet'}</td>
    <td className="num">{fmtNumber(j.runs_24h||0)} runs<span className={`l3v-code ${Number(j.failed_24h)>0?'l3v-bad':''}`}>{fmtNumber(j.failed_24h||0)} failed</span></td>
    <td><StatusChip value={j.active?'on':'paused'} tone={j.active?'success':'warning'} label={j.active?'Running':'Paused'}/></td>
    {rank>=5&&<td>{allowed?<div className="au-controls">
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
    </div>:<span className="l3v-note">Top admin only</span>}</td>}
  </tr>
}
