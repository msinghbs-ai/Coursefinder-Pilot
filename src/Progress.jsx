// Coverage & completeness › Progress (v2.15.266, CF-247). Platform Admin, 13 Oct 2026: "Show the adapter and scholarship journey and
// progress I can follow on the UI. Whatever you are providing per hour, what do we need to implement at the UI to have this on demand?
// Collect the crux of how the platform is progressing, what is running, and where we can tweak or run on demand." Mock-up approved
// ("Mock-up is good to go"); artifact comment: a job's row expands to the universities it is working on, each opening its journey.
// Four views (?view=): Overview (headline, needs attention, journey stages by group, fields and scholarships, Firecrawl and AI today,
// the hourly trend), Journeys (one row per university in onboarding; a selected row shows its journey and the actions for it),
// Running now (every scheduled job by journey stage; a job expands to the universities it works on; pause, resume, run now) and
// Levers (every setting that changes the pace, with what it did today, linking to the screen where it is changed).
// Replaces the Live activity page, the Pilot panel on Layer 2 › Onboarding, the Dashboard health strip, Layers and Recent activity,
// and Task manager's Running now (v2.15.266). Reads: admin_progress_read(view, args). Writes (existing calls only):
// admin_provider_onboarding('retry'), admin_firecrawl_search_resume, startProviderScans (Find scholarships now), admin_automation_control.
import React,{useEffect,useRef,useState}from'react'
import{AlertTriangle,ChevronDown,ChevronRight,RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Empty,Loading,StatusChip,fmtDateTime,fmtNumber,fmtTime}from'./ui-kit'
import{JOURNEY,Journey,ReasonAction,STOP,Stepper}from'./ProviderOnboarding'
import{startProviderScans}from'./ScholarshipActions'
import{errorReading,errorSteps}from'./lib/workerErrors.js'

const errText=e=>e?.message||String(e)
export const VIEWS=[['overview','Overview'],['journeys','Journeys'],['running','Running now'],['levers','Levers']]
export const GROUPS=[['all','All universities'],['pilot','Pilot'],['top','Top 50 Australia']]
const STAGES=[...JOURNEY.map(([k,l])=>[k,l]),['done','Done']]
const pct=(n,c)=>Number(c)?Math.round(Number(n||0)*100/Number(c)):null
const pctText=(n,c)=>{const p=pct(n,c);return p==null?'—':`${p}%`}
// Why a university is held up, and the next step (stop reasons from onboarding; holds and caps from the Firecrawl budget)
export const HELD={
  search_held:['Search held for a check','Check its adapter and website, then press Search again.'],
  search_stopped:['Course-page search stopped','Check the website on the Adapter builder (1.1), then press Search again.'],
  scholarship_cap:['Scholarship credits used (150)','Waits for its credits; nothing to do unless it matters today.'],
}
export function heldText(key){if(!key)return null;if(HELD[key])return HELD[key];const s=STOP[key];return s?[s[0],s[1]]:[key,'']}
const NEXT={provider_in:'Waits for a free place (up to 100 at once).',prepare:'Website and course pages are being found and read.',create_adapter:'The AI proposes the adapter; it is tested on stored pages.',admit:'Passing fields are admitted (automatic while switched on).',enrich:'Admitted values are written to its courses.',scholarship_adapter:'Its scholarship pages are being found.',admit_scholarships:'The AI reads each scholarship page; passing ones publish hourly.',done:'Done. Pages are read again on their schedule.'}
const STATE_OF=j=>!j.active?['Paused','warning']:j.running?['Running','success']:Number(j.failed_24h)>0?['Failing','danger']:['Waiting','neutral']

async function read(view,args){const{data,error}=await supabase.rpc('admin_progress_read',{p_view:view,p_args:args||{}});if(error)throw error;return data||{}}

function ViewTabs({view}){
  return <nav className="pg-views" aria-label="Progress views">{VIEWS.map(([k,l])=><a key={k} href={hrefFor('coverage','progress',k==='overview'?{}:{view:k})} className={`pg-view${view===k?' is-on':''}`} aria-current={view===k?'page':undefined} data-progress-view={k}>{l}</a>)}</nav>
}

function GroupPicker({group,counts,onPick}){
  return <div className="pg-groups" role="group" aria-label="Group">{GROUPS.map(([k,l])=><Button key={k} compact className={group===k?'is-active':''} aria-pressed={group===k} onClick={()=>onPick(k)} data-progress-group={k}>{l}{counts?.[k]!=null?` (${fmtNumber(counts[k])})`:''}</Button>)}</div>
}

function Overview({group,setGroup,onError}){
  const[d,setD]=useState(null)
  const load=async()=>{try{setD(await read('overview',{group}))}catch(e){onError?.(errText(e))}}
  useEffect(()=>{setD(null);load()},[group])
  if(!d)return <Loading label="Reading progress…"/>
  const st=d.stages||{},f=d.fields||{},s=d.scholarships||{},pg=d.pages_hour||{},b=d.budget||{}
  const needs=[]
  for(const[k,n]of Object.entries(d.stop_reasons||{}))if(Number(n)>0){const h=heldText(k);needs.push({key:`stop:${k}`,tone:['nothing_ready','approve_central'].includes(k)?'warning':'neutral',title:`${fmtNumber(n)} ${Number(n)===1?'university':'universities'}: ${h[0]}`,hint:h[1],href:hrefFor('coverage','progress',{view:'journeys',group,held:'stopped',stop:k})})}
  for(const n of d.notices||[])needs.push({key:n.key,tone:n.severity==='high'?'danger':'warning',title:n.title,hint:[n.detail,n.hint].filter(Boolean).join(' ')})
  const journeyHref=stage=>hrefFor('coverage','progress',{view:'journeys',group,stage})
  return <div className="m-page-stack" data-progress-overview>
    <div className="pg-bar"><GroupPicker group={group} counts={d.groups} onPick={setGroup}/><span className="pg-spacer"/><small className="sd-desc">Course and scholarship counts as of {d.facts_at?fmtTime(d.facts_at):'—'} (hourly)</small><Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button></div>
    <section className="pg-tiles" aria-label="Headline">
      <div data-progress-tile="universities"><small>Universities</small><strong>{fmtNumber(d.universities)}</strong><span>{fmtNumber(st.done)} done</span></div>
      <div data-progress-tile="needs"><small>Need a person</small><strong>{fmtNumber(d.needs_person)}</strong><span>{fmtNumber(d.stopped)} stopped for another reason</span></div>
      <div data-progress-tile="scholarships"><small>Scholarships published</small><strong>{fmtNumber(s.published)}</strong><span>{fmtNumber(s.found)} found{s.published_before!=null?`, ${fmtNumber(s.published_before)} when picked`:''}</span></div>
      <div data-progress-tile="pages"><small>Course pages, last hour</small><strong>{fmtNumber(pg.correct)}</strong><span>correct; {fmtNumber(pg.wrong)} wrong, {fmtNumber(pg.failed)} not read</span></div>
      <div data-progress-tile="firecrawl"><small>Firecrawl today</small><strong>{fmtNumber(Math.round(b.billed_today||0))}</strong><span>of {fmtNumber(b.total)} a day</span></div>
    </section>
    <section className="m-panel" aria-label="Needs attention" data-progress-needs>
      <h3 className="sl-h4">Needs attention</h3>
      {needs.length===0?<Empty text="Nothing needs attention."/>:<ul className="pg-needs">{needs.map(n=><li key={n.key} className={`tone-${n.tone}`} data-progress-need={n.key}><AlertTriangle size={14} aria-hidden/><div><strong>{n.href?<a className="cf-link" href={n.href}>{n.title}</a>:n.title}</strong>{n.hint&&<small>{n.hint}</small>}</div></li>)}</ul>}
    </section>
    <section className="m-panel" aria-label="Journey stages" data-progress-stages>
      <h3 className="sl-h4">Where the universities are</h3>
      <ol className="pg-stages">{STAGES.map(([k,l],i)=><li key={k}><a href={journeyHref(k)} data-progress-stage={k}><small>{k==='done'?'':`${i+1}. `}{l}</small><strong>{fmtNumber(st[k]||0)}</strong></a></li>)}</ol>
    </section>
    <div className="pg-two">
      <section className="m-panel" aria-label="Fields" data-progress-fields>
        <h3 className="sl-h4">Courses with each field{f.courses_before!=null?' (when picked → now)':''}</h3>
        <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Field</th><th className="num">Courses</th><th className="num">Share</th></tr></thead><tbody>
          {[['intakes','Intakes'],['english','English'],['fee','Fee'],['delivery','Delivery']].map(([k,l])=><tr key={k} data-progress-field={k}><td>{l}</td><td className="num">{fmtNumber(f[k])}</td>
            <td className="num">{f[`${k}_before`]!=null?<>{pctText(f[`${k}_before`],f.courses_before)} → </>:''}<strong>{pctText(f[k],f.courses)}</strong></td></tr>)}
        </tbody></table></div>
        <small className="sd-desc">{fmtNumber(f.courses)} courses. {fmtNumber(s.waiting_ai)} scholarship pages wait for the AI.</small>
      </section>
      <section className="m-panel" aria-label="Firecrawl and AI today" data-progress-budget>
        <h3 className="sl-h4">Firecrawl and AI today</h3>
        <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Purpose</th><th className="num">Used</th><th className="num">Share</th><th className="num">Refused</th></tr></thead><tbody>
          {(b.groups||[]).map(g=><tr key={g.group} data-progress-share={g.group}><td>{g.label}</td><td className="num">{fmtNumber(Math.round(g.used))}</td>
            <td className="num"><StatusChip tone={Number(g.used)>=Number(g.share)?'danger':Number(g.used)>=0.8*Number(g.share)?'warning':'success'} label={`${pctText(g.used,g.share)} of ${fmtNumber(g.share)}`}/></td><td className="num">{fmtNumber(g.refused)}</td></tr>)}
          {(d.ai_today||[]).map(a=><tr key={a.use} data-progress-ai={a.use}><td>AI: {a.label}</td><td className="num">US${Number(a.spent||0).toFixed(2)}</td><td className="num">guard US${a.guard}</td><td className="num">—</td></tr>)}
        </tbody></table></div>
        <small className="sd-desc">OpenRouter balance US${d.openrouter_usd!=null?Number(d.openrouter_usd).toFixed(2):'—'}. Change shares and guards on <a className="cf-link" href={hrefFor('coverage','progress',{view:'levers'})}>Levers</a>.</small>
      </section>
    </div>
    <section className="m-panel" aria-label="Hourly trend" data-progress-trend>
      <h3 className="sl-h4">Every hour (last 24 hours, kept 90 days)</h3>
      {(d.trend||[]).length===0?<Empty text="The first hourly snapshot is taken at nine minutes past the hour."/>:
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Time</th><th className="num">Done</th><th className="num">Scholarships found</th><th className="num">Published</th><th className="num">Correct pages that hour</th><th className="num">Firecrawl billed today</th></tr></thead><tbody>
        {[...d.trend].reverse().slice(0,24).map(t=><tr key={t.at}><td>{fmtDateTime(t.at)}</td><td className="num">{fmtNumber(t.done)}</td><td className="num">{fmtNumber(t.found)}</td><td className="num">{fmtNumber(t.published)}</td><td className="num">{fmtNumber(t.pages_correct)}</td><td className="num">{fmtNumber(Math.round(t.billed_today||0))}</td></tr>)}
      </tbody></table></div>}
    </section>
  </div>
}

function Journeys({group,setGroup,params,onError}){
  const[f,setF]=useState({stage:params.get('stage')||'',held:params.get('held')||'',country:'',q:''}),[q,setQ]=useState('')
  const[d,setD]=useState(null),[sel,setSel]=useState(params.get('id')||''),[busy,setBusy]=useState(false),[msg,setMsg]=useState(''),[fail,setFail]=useState('')
  const stop=params.get('stop')||''
  const load=async()=>{try{setD(await read('journeys',{group,...f}))}catch(e){onError?.(errText(e))}}
  useEffect(()=>{const t=setTimeout(()=>setF(x=>({...x,q:q.trim()})),350);return()=>clearTimeout(t)},[q])
  useEffect(()=>{load()},[group,f])
  const rows=(d?.rows||[]).filter(r=>!stop||r.stop_reason===stop)
  const s=rows.find(r=>r.onboarding_id===sel)||(sel?{onboarding_id:sel,name:'Selected university',provider_id:null,status:null,held_by:null}:null)
  const run=async(fn,done)=>{setBusy(true);setFail('');setMsg('');try{await fn();setMsg(done);await load()}catch(e){setFail(errText(e))}finally{setBusy(false)}}
  const resume=r=>{const reason=window.prompt(`Search course pages again for ${r.name}? Check its website and adapter first.\n\nReason (kept in the log):`);if(!reason||reason.trim().length<4)return
    run(async()=>{const{error}=await supabase.rpc('admin_firecrawl_search_resume',{p_provider_id:r.provider_id,p_reason:reason.trim()});if(error)throw error},'Search starts again on the next run.')}
  return <div className="m-page-stack" data-progress-journeys>
    <div className="pg-bar">
      <GroupPicker group={group} onPick={g=>{setSel('');setGroup(g)}}/>
      <select aria-label="Stage" value={f.stage} onChange={e=>setF({...f,stage:e.target.value})} data-progress-filter="stage"><option value="">Every stage</option>{STAGES.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>
      <select aria-label="Held up" value={f.held} onChange={e=>setF({...f,held:e.target.value})} data-progress-filter="held"><option value="">Any</option><option value="person">Needs a person</option><option value="stopped">Stopped</option></select>
      <select aria-label="Country" value={f.country} onChange={e=>setF({...f,country:e.target.value})}><option value="">All countries</option><option value="AU">Australia</option><option value="NZ">New Zealand</option><option value="CA">Canada</option></select>
      <input type="search" className="po-search" aria-label="Find a university" placeholder="Find a university" value={q} onChange={e=>setQ(e.target.value)}/>
      <Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>
    </div>
    {stop&&<p className="sd-desc">Showing stopped for: <strong>{heldText(stop)[0]}</strong>. <a className="cf-link" href={hrefFor('coverage','progress',{view:'journeys',group})}>Show all</a></p>}
    {s&&<section className="m-panel pg-selected" data-progress-selected={s.onboarding_id}>
      <div className="pg-bar"><h3 className="sl-h4">{s.name}</h3><span className="pg-spacer"/><Button compact onClick={()=>setSel('')}>Close</Button></div>
      <Journey id={s.onboarding_id}/>
      <div className="sd-actions" data-progress-actions>
        {d?.can_manage&&s.status==='stopped'&&<ReasonAction label="Retry onboarding" testid="progress-retry" onDo={r=>run(async()=>{const{error}=await supabase.rpc('admin_provider_onboarding',{p_action:'retry',p_args:{ids:[s.onboarding_id],reason:r}});if(error)throw error},'Retrying from the step that stopped.')}/>}
        {d?.can_manage&&['search_held','search_stopped'].includes(s.held_by)&&<Button compact disabled={busy} onClick={()=>resume(s)} data-progress-search-again>Search again</Button>}
        {d?.can_run&&s.provider_id&&<Button compact disabled={busy} onClick={()=>run(async()=>{const r=await startProviderScans([s.provider_id],1);if(!r)throw new Error('Not started')},'Scholarship search started; progress is in Scheduled jobs › Task manager.')} data-progress-find-scholarships>Find scholarships now</Button>}
        {s.provider_id&&<a className="cf-link" href={hrefFor('layer2','onboarding',{q:s.name})}>Open on Layer 2 › Onboarding</a>}
        <a className="cf-link" href={hrefFor('scholarships','coverage')}>Scholarships › Coverage</a>
      </div>
      {msg&&<p role="status" className="sd-desc">{msg}</p>}{fail&&<p role="alert" className="fr-error">{fail}</p>}
    </section>}
    {!d?<Loading label="Reading journeys…"/>:rows.length===0?<Empty text="No university matches."/>:
    <div className="cf-table-wrap"><table className="cf-table pg-journeys"><thead><tr><th>University</th><th>Journey</th><th className="num">Intakes</th><th className="num">English</th><th className="num">Fee</th><th className="num">Delivery</th><th className="num">Scholarships</th><th>Held up by</th><th>Next step</th></tr></thead><tbody>
      {rows.map(r=>{const n=r.facts||{},h=heldText(r.held_by)
        return <tr key={r.onboarding_id} className={sel===r.onboarding_id?'is-selected':''} data-progress-row={r.provider_id}>
          <td><button type="button" className="tm-link" onClick={()=>setSel(sel===r.onboarding_id?'':r.onboarding_id)} aria-expanded={sel===r.onboarding_id}>{r.name}</button><br/><small className="sl-sub">{r.country}{r.grp?` · ${r.grp==='top'?'Top 50':'Pilot'}`:''} · {fmtNumber(n.courses)} courses</small></td>
          <td><Stepper stage={r.stage} status={r.status}/></td>
          {['intakes','english','fee','delivery'].map(k=><td key={k} className="num">{pctText(n[k],n.courses)}</td>)}
          <td className="num" data-progress-sch>{fmtNumber(n.scholarships_published)} / {fmtNumber(n.scholarships)}{Number(r.waiting_ai)>0?<small className="sl-sub"> · {fmtNumber(r.waiting_ai)} with AI</small>:''}</td>
          <td>{h?<StatusChip tone={['nothing_ready','approve_central','search_held'].includes(r.held_by)?'warning':'neutral'} label={h[0]}/>:''}</td>
          <td><small>{h?.[1]||NEXT[r.stage]||''}</small></td></tr>})}
    </tbody></table></div>}
    <small className="sd-desc">Scholarships: published / found. Fields: share of the university's courses (hourly). Up to 200 rows; use the filters to narrow.</small>
  </div>
}

function JobUnis({job}){
  const[d,setD]=useState(null),[fail,setFail]=useState('')
  useEffect(()=>{read('running_unis',{job}).then(setD).catch(e=>setFail(errText(e)))},[job])
  if(fail)return <p className="fr-error" role="alert">{fail}</p>
  if(!d)return <Loading compact label="Reading universities…"/>
  const u=d.unis||[]
  if(!u.length)return <Empty text="Not working on a particular university in the last hour."/>
  return <table className="cf-table pg-unis" data-progress-unis={job}><thead><tr><th>University</th><th>Where it is</th><th>What this job did for it</th><th/></tr></thead><tbody>
    {u.map(x=><tr key={x.provider_id} data-progress-uni={x.provider_id}><td><strong>{x.name}</strong><br/><small className="sl-sub">{x.country}</small></td>
      <td>{x.stage?<Stepper stage={x.stage}/>:'Not in onboarding'}</td><td>{x.what}</td>
      <td>{x.onboarding_id&&<a className="cf-link" href={hrefFor('coverage','progress',{view:'journeys',id:x.onboarding_id,group:'all'})} data-progress-open-journey>Open journey →</a>}</td></tr>)}
  </tbody></table>
}

function Running({rank,onError}){
  const[d,setD]=useState(null),[only,setOnly]=useState(true),[open,setOpen]=useState(''),[busy,setBusy]=useState(false)
  const timer=useRef(null)
  const load=async()=>{try{setD(await read('running'))}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load();timer.current=setInterval(()=>{if(document.visibilityState==='visible')load()},20000);return()=>clearInterval(timer.current)},[])
  const control=async(job,action,q)=>{if(!window.confirm(q))return;setBusy(true);try{const{error}=await supabase.rpc('admin_automation_control',{p_job:job,p_action:action,p_args:{}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  const seen=async e=>{setBusy(true);try{const{error}=await supabase.rpc('admin_live_error_ack',{p_function:e.function||'',p_status:e.status??null,p_message:e.message||''});if(error)throw error;await load()}catch(x){onError?.(errText(x))}finally{setBusy(false)}}
  if(!d)return <Loading label="Reading what is running…"/>
  const jobs=d.jobs||[],shown=jobs.filter(j=>!only||j.running||!j.active||Number(j.failed_24h)>0||Number(j.queue?.left||0)>0)
  const failing=jobs.filter(j=>Number(j.failed_24h)>0)
  return <div className="m-page-stack" data-progress-running>
    <section className="pg-tiles" aria-label="Summary">
      <div><small>Running this moment</small><strong>{fmtNumber(jobs.filter(j=>j.running).length)}</strong><span>{fmtNumber(jobs.length)} scheduled jobs</span></div>
      <div className={failing.length?'tone-danger':''}><small>Failing (24 h)</small><strong>{fmtNumber(failing.length)}</strong><span>jobs with a failed run</span></div>
      <div><small>Paused</small><strong>{fmtNumber(jobs.filter(j=>!j.active).length)}</strong><span>schedules</span></div>
      <div><small>Firecrawl, last hour</small><strong>{fmtNumber(Math.round(Object.values(d.credits_hour||{}).reduce((a,b)=>a+Number(b||0),0)))}</strong><span>{fmtNumber(d.refused_hour)} refused</span></div>
    </section>
    <div className="pg-bar"><label className="fcc-only"><input type="checkbox" checked={only} onChange={e=>setOnly(e.target.checked)}/> Only what is busy or needs attention</label><span className="pg-spacer"/><small className="sd-desc">Refreshes every 20 seconds. Click a job to see the universities it is working on.</small></div>
    <div className="cf-table-wrap"><table className="cf-table pg-jobs"><thead><tr><th>Stage of the journey</th><th>Job</th><th>How often</th><th>Now</th><th className="num">Last 24 h</th><th>Last result</th>{d.can_manage&&<th>Control</th>}</tr></thead><tbody>
      {shown.length===0&&<tr><td colSpan={7} className="cf-empty-cell">Nothing is busy or needs attention.</td></tr>}
      {shown.map(j=>{const[l,t]=STATE_OF(j),isOpen=open===j.job
        return <React.Fragment key={j.job}><tr data-progress-job={j.job} className={isOpen?'is-selected':''}>
          <td><small>{j.stage}</small></td>
          <td><button type="button" className="tm-link" aria-expanded={isOpen} onClick={()=>setOpen(isOpen?'':j.job)} data-progress-job-toggle={j.job}>{isOpen?<ChevronDown size={13}/>:<ChevronRight size={13}/>} {j.label||j.job}</button><br/><small className="sl-sub">{j.job}</small></td>
          <td><small>{j.schedule}</small></td><td><StatusChip tone={t} label={l}/></td>
          <td className="num">{fmtNumber(j.runs_24h)}{Number(j.failed_24h)>0&&<small className="sl-sub"> · {fmtNumber(j.failed_24h)} failed</small>}</td>
          <td><small>{j.worker?.summary||j.last?.message||j.last?.status||'—'}{j.last?.end?` · ${fmtTime(j.last.end)}`:''}</small></td>
          {d.can_manage&&<td className="tm-actions">{j.active?<Button compact disabled={busy} onClick={()=>control(j.job,'pause',`Pause the schedule of "${j.label||j.job}"? The run in progress finishes.`)}>Pause</Button>:<Button compact disabled={busy} onClick={()=>control(j.job,'resume',`Resume the schedule of "${j.label||j.job}"?`)}>Resume</Button>}
            <Button compact disabled={busy} onClick={()=>control(j.job,'run_now',`Run "${j.label||j.job}" once more now?`)}>Run now</Button></td>}
        </tr>
        {isOpen&&<tr className="pg-expand"><td colSpan={d.can_manage?7:6}>{j.description&&<p className="sd-desc">{j.description}</p>}<JobUnis job={j.job}/></td></tr>}</React.Fragment>})}
    </tbody></table></div>
    {(d.worker_errors||[]).length>0&&<section className="m-panel" data-worker-errors>
      <h3 className="sl-h4">Workers sending back errors</h3>
      <p className="sd-desc">A job's run can show as succeeded while the worker it calls refuses the work. These are the error replies from the last few hours. Mark one as seen once it is understood; it shows again only if it happens again.</p>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Job</th><th>Reply</th><th>What it means and what to do</th><th className="num">How often</th><th>Last</th>{rank>=4&&<th/>}</tr></thead>
        <tbody>{d.worker_errors.map((e,i)=><tr key={i} data-worker-error={e.status??'none'}>
          <td><strong>{e.job||e.function||'Unknown job'}</strong>{e.job&&e.function?<><br/><small className="sl-sub">{e.function}</small></>:null}</td>
          <td><StatusChip tone="danger" label={e.timed_out?'Timed out':e.status==null?'No reply':`Error ${e.status}`}/><br/><small className="sl-sub">{e.message||'—'}</small></td>
          <td>{errorReading(e)}<br/><small className="sd-desc" data-error-todo><b>What to do:</b> {errorSteps(e)}</small></td>
          <td className="num">{fmtNumber(e.count)}</td><td>{e.last?fmtDateTime(e.last):'—'}</td>
          {rank>=4&&<td><Button compact disabled={busy} onClick={()=>seen(e)} data-error-seen>Mark as seen</Button></td>}</tr>)}</tbody></table></div>
    </section>}
    <small className="sd-desc">Schedules are changed on <a className="cf-link" href={hrefFor('jobs','automations')}>Scheduled jobs › Automations</a>; tasks started by people are in <a className="cf-link" href={hrefFor('jobs','tasks')}>Task manager</a>.</small>
  </div>
}

function Levers({onError}){
  const[d,setD]=useState(null)
  useEffect(()=>{read('levers').then(setD).catch(e=>onError?.(errText(e)))},[])
  if(!d)return <Loading label="Reading levers…"/>
  const RUN=[['Find scholarships now','scholarships','coverage','Tick universities (up to 50); uses scholarship credits.'],['Read the waiting pages with AI again','layer4','aireview','From the first model, on the stored copy; no Firecrawl credit.'],['Retry stopped universities','layer2','onboarding','Tick stopped rows; they start again at the step that stopped.'],['Search again for a stopped university','services','limits','After its website is checked (Firecrawl credits by university).'],['Onboard universities not yet queued','layer2','onboarding','Adds every university without an admitting adapter.'],['Pause or run a scheduled job','coverage','progress','Running now, or Scheduled jobs › Automations.']]
  return <div className="m-page-stack" data-progress-levers>
    <p className="sd-desc">Every setting that changes the pace, with its value and what it did today. Each is changed on its own screen (Platform Admin, with a reason, logged); this lists them in one place.</p>
    {(d.sections||[]).map(s=><section key={s.title} className="m-panel" aria-label={s.title} data-progress-lever-section={s.title}>
      <h3 className="sl-h4">{s.title}</h3>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Lever</th><th>Now</th><th>What it did today</th><th/></tr></thead><tbody>
        {(s.rows||[]).map(r=><tr key={r.name} className={r.hot?'pg-hot':''} data-progress-lever={r.key||r.name}><td><strong>{r.name}</strong><br/><small className="sl-sub">{r.where}</small></td><td>{r.now==='true'?'On':r.now==='false'?'Off':r.now}</td><td>{r.effect||'—'}</td>
          <td><a className="cf-link" href={r.page==='coverage'&&r.tab==='progress'?hrefFor('coverage','progress',{view:'running'}):hrefFor(r.page,r.tab)}>Change</a></td></tr>)}
      </tbody></table></div>
    </section>)}
    <section className="m-panel" aria-label="Run on demand" data-progress-run>
      <h3 className="sl-h4">Run on demand</h3>
      <div className="pg-run">{RUN.map(([t,p,tab,what])=><a key={t} href={p==='coverage'?hrefFor('coverage','progress',{view:'running'}):hrefFor(p,tab)} className="pg-run-item"><strong>{t}</strong><small>{what}</small></a>)}</div>
    </section>
  </div>
}

export default function Progress({routeParams,rank=0,onError}){
  const params=routeParams||new URLSearchParams()
  const view=VIEWS.some(([k])=>k===params.get('view'))?params.get('view'):'overview'
  const[group,setGroup]=useState(GROUPS.some(([k])=>k===params.get('group'))?params.get('group'):'all')
  return <div className="m-page-stack" data-progress>
    <ViewTabs view={view}/>
    {view==='overview'&&<Overview group={group} setGroup={setGroup} onError={onError}/>}
    {view==='journeys'&&<Journeys key={params.toString()} group={group} setGroup={setGroup} params={params} onError={onError}/>}
    {view==='running'&&<Running rank={rank} onError={onError}/>}
    {view==='levers'&&<Levers onError={onError}/>}
  </div>
}
