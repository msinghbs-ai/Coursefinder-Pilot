// CF-247 v2.15.300 (Platform Admin, 20 Oct 2026 10:35: "Rework layer 2 into layer 2/3 so its cleared it has combined operations ... Only
// actionable and operation relative information and items should be retained"; choice "Operations first"). Layer 2/3 › Operations: each
// stage of finding, building, admitting and enriching, with the universities working on it now, waiting for it, and stopped for a person
// (each kind opens Layer 4 › Inbox on that kind), and the scheduled jobs behind it (pause, resume, run now). Onboarding is switched and
// paced here. Reads public.admin_layer23('operations') and admin_progress_read('running'); controls admin_automation_control and
// admin_provider_onboarding (Platform Admin, with a reason).
import React,{useEffect,useMemo,useState}from'react'
import{ChevronDown,ChevronRight,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Loading,Metric,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{Settings,ReasonAction,Approvals,estimate}from'./ProviderOnboarding'
import{cronText}from'./Progress'
import'./layer23.css'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const KIND={website_needed:'Website needed',site_down:'Website not answering',pages_not_found:'Course pages not found',too_few_pages:'Too few course pages',
  nothing_ready:'Adapter has nothing ready',onboarding_failed:'Adapter proposal failed',central_to_approve:'Central pages to approve',course_link:'Course link',
  fee_check:'Fee fails the check',not_offered:'Course not offered',not_on_site:"Course not on the university's site",counsellor_report:'Counsellor report',held_scholarship:'Held scholarship'}
const WAIT={website:'queued for onboarding',pages:'sites waiting to be mapped',adapter:'in a Build adapter wave, not yet checked',enrich:'ready to admit',scholarships:'held pages waiting for the AI re-check'}
const jobState=j=>!j?['Not scheduled','neutral']:!j.active?['Paused','warning']:j.running?['Running','success']:Number(j.failed_24h)>0?['Failing','danger']:['Waiting','neutral']

export default function Layer23Operations({rank=0,actorId='',onError}){
  const[d,setD]=useState(null),[jobs,setJobs]=useState(null),[ob,setOb]=useState(null),[open,setOpen]=useState(''),[busy,setBusy]=useState(false),[msg,setMsg]=useState('')
  const load=async()=>{setBusy(true);try{
      const{data,error}=await supabase.rpc('admin_layer23',{p_action:'operations',p_args:{}});if(error)throw error;setD(data||{})
      supabase.rpc('admin_progress_read',{p_view:'running',p_args:{}}).then(({data:r,error:e})=>{if(!e)setJobs(r||{})},()=>{})
      if(rank>=4)supabase.rpc('admin_provider_onboarding',{p_action:'read',p_args:{q:'#none#'}}).then(({data:r,error:e})=>{if(!e)setOb(r||{})},()=>{})
    }catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load();const t=setInterval(()=>{if(document.visibilityState==='visible')load()},60000);return()=>clearInterval(t)},[])
  const byJob=useMemo(()=>Object.fromEntries((jobs?.jobs||[]).map(j=>[j.job,j])),[jobs])
  const control=async(job,action,q)=>{if(!window.confirm(q))return;setBusy(true);try{const{error}=await supabase.rpc('admin_automation_control',{p_job:job,p_action:action,p_args:{}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const act=async(action,a,done)=>{setMsg('');try{const{error}=await supabase.rpc('admin_provider_onboarding',{p_action:action,p_args:a});if(error)throw error;if(done)setMsg(done);await load()}catch(e){onError?.(errText(e));throw e}}
  if(!d)return <Loading label="Reading Layer 2/3 operations…"/>
  const stages=d.stages||[],canJobs=Boolean(jobs?.can_manage)
  const stoppedAll=stages.reduce((n,s)=>n+Number(s.stopped||0),0),runningAll=stages.reduce((n,s)=>n+Number(s.running||0),0)
  const failing=stages.flatMap(s=>(s.jobs||[]).filter(j=>Number(byJob[j]?.failed_24h)>0)).length
  const paused=stages.flatMap(s=>(s.jobs||[]).filter(j=>byJob[j]&&!byJob[j].active)).length
  return <div className="m-page-stack l23" data-layer23-operations>
    <section className="l23-tiles">
      <Metric label="Working now" value={fmtNumber(runningAll)} detail="Universities in a stage at this moment"/>
      <a className="l23-tile-link" href={hrefFor('layer4','inbox')} data-layer23-inbox><Metric label="Stopped for a person" value={fmtNumber(stoppedAll)} detail="Open Layer 4 › Inbox" tone={stoppedAll?'warning':'success'}/></a>
      <Metric label="Jobs failing or paused" value={`${fmtNumber(failing)} · ${fmtNumber(paused)}`} detail="Failing in 24 h · paused" tone={failing?'danger':paused?'warning':'success'}/>
      <Metric label="Finished every stage" value={fmtNumber(d.done)} detail={`Onboarding ${d.settings?.enabled===false?'switched off':`on, up to ${fmtNumber(d.settings?.max_active||0)} at once`}${d.settings?.auto_admit?' · admits automatically':''}`} tone="success"/>
    </section>
    {ob?.pace&&<p className="sd-desc" data-layer23-pace>Pace: {fmtNumber(ob.pace.finished_last_hour||0)} universities finished a stage in the last hour ({fmtNumber(ob.pace.finished_last_6_hours||0)} in 6 hours), up to {fmtNumber(ob.settings?.max_active||0)} at once. {estimate(ob.counts?.queued,ob.pace)}</p>}
    <div className="l23-bar"><small className="sd-desc">Refreshes every minute. {d.as_at?`As at ${fmtDateTime(d.as_at)}.`:''}</small><Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>
    {msg&&<p className="l4i-note" role="status">{msg}</p>}
    <div className="cf-table-wrap"><table className="cf-table l23-stages" data-layer23-stages><thead><tr><th>Stage</th><th className="num">Working now</th><th className="num">Waiting</th><th>Stopped for a person</th><th>Jobs</th></tr></thead>
      <tbody>{stages.map(s=>{const isOpen=open===s.key,list=(s.jobs||[]).map(j=>byJob[j]||{job:j,missing:true}),bad=list.filter(j=>!j.missing&&(!j.active||Number(j.failed_24h)>0)).length,run=list.filter(j=>j.running).length
        return <React.Fragment key={s.key}><tr data-layer23-stage={s.key}>
          <td><strong>{s.order}. {s.label}</strong><small className="sl-sub l23-what">{s.what}</small></td>
          <td className="num">{fmtNumber(s.running)}</td>
          <td className="num">{fmtNumber(s.waiting)}<small className="sl-sub">{WAIT[s.key]}</small>{s.key==='enrich'&&Number(d.enrich_review)>0&&<a className="cf-link l23-sub" href={hrefFor('layer2','enrich')} data-layer23-enrich-review>{fmtNumber(d.enrich_review)} Enrich fields values to review →</a>}</td>
          <td>{Number(s.stopped)===0?<small className="sl-sub">None</small>:<ul className="l23-kinds">{Object.entries(s.stopped_by_kind||{}).sort((a,b)=>b[1]-a[1]).map(([k,n])=><li key={k}><a className="cf-link" href={hrefFor('layer4','inbox',{kind:k})} data-layer23-kind={k}>{KIND[k]||k} <strong>{fmtNumber(n)}</strong></a></li>)}</ul>}</td>
          <td><button type="button" className="tm-link" aria-expanded={isOpen} onClick={()=>setOpen(isOpen?'':s.key)} data-layer23-jobs-toggle={s.key}>{isOpen?<ChevronDown size={13}/>:<ChevronRight size={13}/>} {fmtNumber(list.length)} jobs</button>
            <small className="sl-sub">{run?`${fmtNumber(run)} running`:'none running'}{bad?` · ${fmtNumber(bad)} paused or failing`:''}</small></td>
        </tr>
        {isOpen&&<tr className="pg-expand"><td colSpan={5}><table className="cf-table l23-jobs" data-layer23-jobs={s.key}><thead><tr><th>Job</th><th>How often</th><th>Now</th><th className="num">Last 24 h</th>{canJobs&&<th>Control</th>}</tr></thead><tbody>
          {list.map(j=>{const[l,t]=jobState(j.missing?null:j);return <tr key={j.job} data-layer23-job={j.job}><td>{j.label||j.job}<br/><small className="sl-sub">{j.job}</small></td><td><small title={j.schedule}>{j.schedule?cronText(j.schedule):'—'}</small></td>
            <td><StatusChip tone={t} label={l}/></td><td className="num">{fmtNumber(j.runs_24h||0)}{Number(j.failed_24h)>0&&<small className="sl-sub"> · {fmtNumber(j.failed_24h)} failed</small>}</td>
            {canJobs&&<td className="tm-actions">{j.missing?null:j.active?<Button compact disabled={busy} onClick={()=>control(j.job,'pause',`Pause the schedule of "${j.label||j.job}"? The run in progress finishes.`)}>Pause</Button>:<Button compact disabled={busy} onClick={()=>control(j.job,'resume',`Resume the schedule of "${j.label||j.job}"?`)}>Resume</Button>}
              {!j.missing&&<Button compact disabled={busy} onClick={()=>control(j.job,'run_now',`Run "${j.label||j.job}" once more now?`)}>Run now</Button>}</td>}</tr>})}
        </tbody></table></td></tr>}</React.Fragment>})}</tbody></table></div>
    {/* the central pages (fee schedules, English policies, calendars) waiting across universities, approved in bulk (from the old Onboarding tab) */}
    {rank>=4&&<Approvals count={ob?.approvals_waiting}/>}
    {rank>=6&&ob&&<section className="m-panel l23-onboard" data-layer23-onboarding>
      <h3 className="sl-h4">Onboarding</h3>
      <p className="sd-desc">New universities start by themselves{ob.settings?.auto_start_new?'':' (switched off)'}. {fmtNumber(ob.not_queued??0)} universities without an adapter are not yet queued.</p>
      <div className="sd-actions"><ReasonAction label={`Onboard universities not yet queued (${fmtNumber(ob.not_queued??0)})`} variant="primary" testid="start-all" disabled={!Number(ob.not_queued)} onDo={r=>act('start',{scope:'no_adapter',reason:r},'Queued, largest universities first. Universities already in onboarding are not queued twice.')}/></div>
      <Settings s={ob.settings} actorId={actorId} act={act}/>
    </section>}
    <small className="sd-desc">Each university's own journey, adapter and actions are on <a className="cf-link" href={hrefFor('layer2','universities')}>Universities</a>. Every scheduled job is on <a className="cf-link" href={hrefFor('jobs','automations')}>Scheduled jobs</a>.</small>
  </div>
}
