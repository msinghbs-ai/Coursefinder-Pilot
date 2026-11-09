// CF-247 OPS/UI (Platform Admin mandate 8 Nov 2026, directive 14:06): Layer 2/3 > Operations > Lane funnels. One funnel for every autonomous lane
// (P0 integrity, intakes, fees, English, course and provider descriptions, entry requirements, scholarships, discovery): is it on, when is it next due,
// how many items sit at each stage, what moved in 24 hours, how old the oldest waiting item is, what the last attempt did, why items are held, what it
// costs, where to drill down, and whether a person has to decide.
// A green job, a stage transfer (a value admitted to the catalogue) and published data are three different things and are labelled as three. A figure
// that was not counted shows "unknown", never 0.
// Server: public.admin_lane_funnel_v1 (rank 3 and above, SELECT only, counted by job lane-funnel). Pause / resume / run now are the EXISTING audited control
// public.admin_automation_control (PIM Admin and above, with a reason); nothing else here writes. Settings are listed with their range and last change and
// are changed on Settings > Pipeline settings (Platform Admin, with a reason).
import React,{useEffect,useRef,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'
import{cronText}from'./Progress'
import'./lane-funnels.css'

const VERDICT={
  transferring:['success','Transferring','Values were admitted or published in the window'],
  green_no_transfer:['warning','Job green, nothing moved','The job succeeded, items are waiting and nothing was admitted in the window'],
  green_transfer_unknown:['warning','Job green, transfer unknown','The job succeeded; this lane does not count admissions yet'],
  idle:['neutral','Idle','No job failed and nothing is waiting or nothing moved'],
  stalled:['danger','Stalled','A stage has eligible work and has not advanced'],
  failing:['danger','Failing','A job failed in the window'],
  off:['warning','Off or paused','A switch is off or every job is paused'],
  unknown:['neutral','Unknown','No job or switch is registered for this lane'],
}
const KIND={eligible:'Eligible',queued:'Queued',in_flight:'In flight',blocked:'Blocked',held:'Held',review_ready:'Review ready',human_review:'Waiting for a person',admitted:'Admitted (transfer)',published:'Published',withdrawn:'Withdrawn',resolved:'Resolved',failed:'Failed'}
const words=x=>String(x??'').replaceAll('_',' ')
const num=x=>x==null?'unknown':fmtNumber(Number(x))
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
function age(iso){if(!iso)return null;const ms=Date.now()-new Date(iso).getTime();if(!(ms>=0))return null;const h=ms/3600000;return h<1?`${Math.max(1,Math.round(ms/60000))} min`:h<48?`${Math.round(h)} h`:`${Math.round(h/24)} days`}
function drillHref(d){if(!d)return null;const[path,q]=String(d).split('?');const[page,tab]=path.split('/');return hrefFor(page,tab||'',q?Object.fromEntries(new URLSearchParams(q)):{})}
const reasonRows=r=>Array.isArray(r)?r.filter(x=>x&&x.reason!=null).map(x=>[words(x.reason),x.n,x.oldest]):r&&typeof r==='object'?Object.entries(r).flatMap(([group,obj])=>obj&&typeof obj==='object'?Object.entries(obj).map(([k,v])=>[`${words(k)} (${group})`,v,null]):[]):[]

function Reasons({r}){
  const rows=reasonRows(r).sort((a,b)=>(b[1]??-1)-(a[1]??-1));if(!rows.length)return null
  return <ul className="lf-reasons" data-lf-reasons>{rows.map(([k,n,o],i)=><li key={i}><span>{k}</span> <strong>{num(n)}</strong>{o&&<small> oldest {age(o)}</small>}</li>)}</ul>
}

function Stages({lane}){
  return <div className="cf-table-wrap lf-frame"><table className="cf-table lf-stages" data-lf-stages={lane.lane}>
    <thead><tr><th>Stage</th><th>What it means</th><th className="num">Now</th><th className="num">Oldest waiting</th><th className="num">Last 24 h</th><th className="num">Change on 24 h ago</th><th>Counted</th></tr></thead>
    <tbody>{(lane.stages||[]).map(s=>{
      const unknown=s.n==null,prev=s.n_prev,delta=!unknown&&prev!=null?Number(s.n)-Number(prev):null
      const href=drillHref(s.drill)
      return <tr key={s.key} data-lf-stage={s.key} data-lf-kind={s.kind} className={s.stalled?'is-stalled':unknown?'is-unknown':''}>
        <td data-label="Stage"><strong>{s.title}</strong><br/><small className="lf-kind">{KIND[s.kind]||s.kind}</small>{s.stalled&&<> <StatusChip tone="danger" label="Stalled"/></>}
          {s.zero_reason&&<small className="lf-zero"> · {words(s.zero_reason)}{s.zero_detail?`: ${s.zero_detail}`:''}</small>}
          {href&&<> <a className="cf-link lf-drill" href={href} data-lf-drill>Open</a></>}</td>
        <td data-label="What it means"><small>{s.what}</small><Reasons r={s.reasons}/></td>
        <td className="num" data-label="Now" data-lf-n={unknown?'unknown':s.n}>{unknown?<span className="lf-unknown" title={s.error||'Not counted yet'}>unknown</span>:num(s.n)}{s.error&&<small className="lf-error"> {s.error}</small>}</td>
        <td className="num" data-label="Oldest waiting">{s.oldest_at?age(s.oldest_at):s.kind==='eligible'||s.kind==='queued'||s.kind==='human_review'||s.kind==='review_ready'?<span className="lf-unknown">unknown</span>:'—'}</td>
        <td className="num" data-label="Last 24 h" data-lf-gain={s.gain==null?'unknown':s.gain}>{s.gain==null?<span className="lf-unknown">unknown</span>:num(s.gain)}</td>
        <td className="num" data-label="Change on 24 h ago">{delta==null?<span className="lf-unknown">unknown</span>:`${delta>0?'+':''}${fmtNumber(delta)}`}</td>
        <td data-label="Counted"><small>{s.measured_at?fmtDateTime(s.measured_at):'never'}{s.source==='progress contract'&&s.window_start?` (window from ${fmtDateTime(s.window_start)})`:''}</small>{s.stale&&<> <StatusChip tone="warning" label="Stale"/></>}</td>
      </tr>})}
    </tbody></table></div>
}

function Jobs({lane,rank,busy,onControl,asAt}){
  return <div className="cf-table-wrap lf-frame"><table className="cf-table lf-jobs" data-lf-jobs={lane.lane}>
    <thead><tr><th>Job</th><th>Schedule</th><th>State</th><th>Next run</th><th>Last attempt</th><th className="num">Runs (green / failed)</th><th>First run after release</th><th>Control</th></tr></thead>
    <tbody>{(lane.jobs||[]).map(j=>{
      // Operations load speed: the scheduler history is a summary kept by job lane-funnel; a job it does not hold is unknown, never "0 runs"
      const known=j.history_known!==false
      const state=!j.scheduled?['neutral','Not scheduled']:!j.active?['warning','Paused']:!known?['neutral','Unknown']:j.running?['info','Running']:Number(j.failed)>0?['danger','Failing']:['success','Waiting']
      const fr=j.first_run
      return <tr key={j.job} data-lf-job={j.job}>
        <td data-label="Job">{j.label||j.job}<br/><small>{j.job}</small></td>
        <td data-label="Schedule"><small title={j.schedule}>{j.schedule?cronText(j.schedule):'—'}</small></td>
        <td data-label="State"><StatusChip tone={state[0]} label={state[1]}/>{j.scheduled&&j.active&&known&&asAt&&<small className="lf-asat" data-lf-as-at title="The scheduler history is counted by job lane-funnel at the end of each of its runs, so this state is as at that time, up to a minute old."> as at {fmtDateTime(asAt)}</small>}</td>
        <td data-label="Next run">{j.next_run?fmtDateTime(j.next_run):j.scheduled&&j.active?<small>{/seconds/.test(j.schedule||'')?'continuous':'unknown'}</small>:'—'}</td>
        <td data-label="Last attempt">{!known&&j.scheduled?<span className="lf-unknown">unknown</span>:j.last_start?<>{fmtDateTime(j.last_start)} <StatusChip value={j.last_status}/>{j.last_message&&j.last_status!=='succeeded'&&<small className="lf-error"> {j.last_message}</small>}</>:<span className="lf-unknown">{j.scheduled?'none in the history read':'—'}</span>}</td>
        <td className="num" data-label="Runs">{j.scheduled?(known?`${fmtNumber(j.succeeded)} / ${fmtNumber(j.failed)}`:<span className="lf-unknown">unknown</span>):'—'}</td>
        <td data-label="First run after release">{fr?<><StatusChip value={fr.status}/> <small>{fr.release}{fr.reason?` · ${fr.reason}`:''}</small></>:<small>none registered</small>}</td>
        <td data-label="Control" className="lf-actions">{j.scheduled&&rank>=Number(j.control_rank||6)?<>
          {j.active?<Button compact disabled={busy} onClick={()=>onControl(j,'pause')}>Pause</Button>:<Button compact disabled={busy} onClick={()=>onControl(j,'resume')}>Resume</Button>}
          {j.active&&<Button compact disabled={busy} onClick={()=>onControl(j,'run_now')}>Run now</Button>}</>:<small>{j.scheduled?`Rank ${j.control_rank} or above`:''}</small>}</td>
      </tr>})}
    </tbody></table></div>
}

function Settings({lane}){
  const sw=lane.switches||[],set=lane.settings||[]
  return <div className="lf-settings" data-lf-settings={lane.lane}>
    {sw.length>0&&<ul className="lf-switches">{sw.map(s=><li key={s.key} data-lf-switch={s.key}><code>{s.key}</code> {s.on==null?<StatusChip tone="neutral" label="Unknown (not registered)"/>:<StatusChip tone={s.on?'success':'warning'} label={s.on?'On':'Off'}/>}{s.label&&<small> {s.label}</small>}</li>)}</ul>}
    {set.length===0?<p className="sl-sub">No setting is registered for this lane under its key prefixes.</p>:
      <div className="cf-table-wrap lf-frame"><table className="cf-table lf-set-table"><thead><tr><th>Setting</th><th className="num">Value</th><th>Range</th><th>Unit</th><th>Used by</th><th>Last change</th></tr></thead>
        <tbody>{set.map(s=><tr key={s.key} data-lf-setting={s.key}><td data-label="Setting"><strong>{s.label||s.key}</strong><br/><small><code>{s.key}</code></small></td>
          <td className="num" data-label="Value">{typeof s.value==='boolean'?(s.value?'on':'off'):Array.isArray(s.value)?`${s.value.length} listed`:String(s.value??'unknown')}</td>
          <td data-label="Range">{s.min!=null||s.max!=null?`${s.min??'—'} to ${s.max??'—'}`:'—'}</td><td data-label="Unit">{s.unit||'—'}</td><td data-label="Used by"><small>{s.used_by||'—'}</small></td>
          <td data-label="Last change"><small>{s.updated_at?fmtDateTime(s.updated_at):'—'}{s.reason?` · ${s.reason}`:''}</small></td></tr>)}</tbody></table></div>}
    <p className="sl-sub">Change a value on <a className="cf-link" href={hrefFor('environment','settings')} data-lf-settings-link>Settings &rsaquo; Pipeline settings</a> (Platform Admin, with a reason; the change is logged).</p>
  </div>
}

function Lane({lane,rank,busy,onControl,open,onToggle,asAt}){
  const v=VERDICT[lane.verdict]||VERDICT.unknown
  const human=(lane.stages||[]).find(s=>s.kind==='human_review'),adm=lane.transfer_24h,pub=lane.published_24h
  const oldest=(lane.stages||[]).filter(s=>s.oldest_at&&['eligible','queued','human_review','review_ready','blocked'].includes(s.kind)).map(s=>s.oldest_at).sort()[0]
  const lastJob=(lane.jobs||[]).filter(j=>j.last_start).sort((a,b)=>b.last_start.localeCompare(a.last_start))[0]
  const nextJob=(lane.jobs||[]).filter(j=>j.next_run).sort((a,b)=>a.next_run.localeCompare(b.next_run))[0]
  const b=lane.budget,jhs=lane.job_history_state||'current'
  return <details className="lf-lane" open={open} data-lf-lane={lane.lane} data-lf-verdict={lane.verdict} onToggle={e=>{if(e.currentTarget.open!==open)onToggle(e.currentTarget.open)}}>
    <summary>
      <span className="lf-name"><strong>{lane.title}</strong></span>
      <span className="lf-cell" data-label="State"><StatusChip tone={v[0]} label={v[1]} title={v[2]}/></span>
      <span className="lf-cell" data-label="Jobs">{fmtNumber(lane.jobs_active)} of {fmtNumber(lane.jobs_total)} on{nextJob?<small> · next {fmtDateTime(nextJob.next_run)}</small>:''}</span>
      <span className="lf-cell" data-label="Last attempt">{lastJob?<>{fmtDateTime(lastJob.last_start)} <StatusChip value={lastJob.last_status}/></>:<span className="lf-unknown">unknown</span>}</span>
      <span className="lf-cell" data-label="Transfer (24 h)" data-lf-transfer={adm==null?'unknown':adm}>{adm==null?<span className="lf-unknown">unknown</span>:fmtNumber(adm)}</span>
      <span className="lf-cell" data-label="Published (24 h)" data-lf-published={pub==null?'unknown':pub}>{pub==null?<span className="lf-unknown">unknown</span>:fmtNumber(pub)}</span>
      <span className="lf-cell" data-label="Waiting for a person">{human?num(human.n):<span className="lf-unknown">not counted</span>}</span>
      <span className="lf-cell" data-label="Oldest waiting">{oldest?age(oldest):<span className="lf-unknown">unknown</span>}</span>
      <span className="lf-cell" data-label="Credits (24 h)">{b?<>{fmtNumber(Number(b.credits_window||0))}<small> of group {b.label?.toLowerCase()}</small></>:'—'}</span>
    </summary>
    {open&&<div className="lf-body">
      <p className="sl-sub">{lane.what} {v[2]}.</p>
      {lane.screen&&<p className="sl-sub">Worked on: {lane.screen}.</p>}
      <div className="lf-three" data-lf-three><div><small>Job result</small>{jhs!=='current'?<><strong data-lf-job-result="unknown">unknown</strong><small>{jhs==='unknown'?'the scheduler history has not been counted':`the scheduler history is stale${asAt?` (as at ${fmtDateTime(asAt)})`:''}`}</small></>:<><strong>{lane.jobs_green>0?`${fmtNumber(lane.jobs_green)} green`:'no green job'}{lane.jobs_failing>0?`, ${fmtNumber(lane.jobs_failing)} failing`:''}</strong><small>the scheduler's word, not data{asAt?`, as at ${fmtDateTime(asAt)}`:''}</small></>}</div>
        <div><small>Stage transfer (admitted, 24 h)</small><strong>{adm==null?'unknown':fmtNumber(adm)}</strong><small>values placed in the catalogue</small></div>
        <div><small>Published (24 h)</small><strong>{pub==null?'unknown':fmtNumber(pub)}</strong><small>reached the consumer-visible stage</small></div></div>
      {b&&<p className="sl-sub" data-lf-budget>Firecrawl budget group &ldquo;{b.label}&rdquo;, shared by every lane that reads with it: used today {fmtNumber(Number(b.used_today||0))} of {fmtNumber(Number(b.share_today||0))} credits, refused today {fmtNumber(Number(b.refused_today||0))}, {fmtNumber(Number(b.credits_window||0))} credits in the window. Credits, not money.</p>}
      {(lane.issues||[]).length>0&&<p className="sl-sub" data-lf-issues>Issues: {lane.issues.map(i=>`${i.ref} ${words(i.status)} (${i.severity})`).join(' · ')}</p>}
      <h4 className="sl-h4">Stages</h4><Stages lane={lane}/>
      <h4 className="sl-h4">Jobs and controls</h4><Jobs lane={lane} rank={rank} busy={busy} onControl={onControl} asAt={asAt}/>
      <h4 className="sl-h4">Switches and settings</h4><Settings lane={lane}/>
    </div>}
  </details>
}

export default function LaneFunnels({rank=0,onError,client=null}){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[open,setOpen]=useState(()=>{try{return new URLSearchParams((location.hash.split('?')[1])||'').get('lane')||''}catch{return''}}),[msg,setMsg]=useState('')
  const lock=useRef(false)
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const load=async()=>{try{const{data,error}=await rpc('admin_lane_funnel_v1',{p_lane:null});if(error)throw error;setD(data&&Array.isArray(data.lanes)?data:{lanes:[]});setErr('')}catch(e){setErr(plainError(e));onError?.(plainError(e));setD(x=>x||{lanes:[]})}}
  useEffect(()=>{load();const t=setInterval(()=>{if(document.visibilityState==='visible')load()},60000);return()=>clearInterval(t)},[])
  // F-OPS.03A: the Data Delivery summary links here (#layer-2-discovery?tab=operations&lane=<lane>); open and show that lane when the address changes on this page
  useEffect(()=>{const h=()=>{try{const l=new URLSearchParams((location.hash.split('?')[1])||'').get('lane')||'';if(l){setOpen(l);setTimeout(()=>document.querySelector(`[data-lf-lane="${l.replace(/[^a-z0-9_]/gi,'')}"]`)?.scrollIntoView({block:'start'}),50)}}catch{}};window.addEventListener('hashchange',h);return()=>window.removeEventListener('hashchange',h)},[])
  const control=async(j,action)=>{
    const q={pause:`Pause the schedule of "${j.label||j.job}"? A run in progress finishes.`,resume:`Switch "${j.label||j.job}" on again?`,run_now:`Run "${j.label||j.job}" once now?`}[action]
    const reason=ask(q);if(!reason||lock.current)return
    lock.current=true;setBusy(true);setMsg('')
    try{const{error}=await rpc('admin_automation_control',{p_job:j.job,p_action:action,p_args:{reason,from:'lane funnels'}});if(error)throw error;setMsg(`${j.label||j.job}: ${{pause:'paused',resume:'switched on',run_now:'started once'}[action]}. Logged with your reason.`);await load()}
    catch(e){setErr(plainError(e));onError?.(plainError(e))}finally{lock.current=false;setBusy(false)}}
  if(!d)return <section className="m-panel" data-lane-funnels><Loading label="Reading the lane funnels…"/></section>
  const lanes=d.lanes||[]
  // an older server (or a mocked one) without the read renders nothing rather than an empty frame
  if(!lanes.length)return err?<section className="m-panel" data-lane-funnels role="alert"><p>Lane funnels could not be read: {err}</p></section>:null
  const stamps=lanes.flatMap(l=>(l.stages||[]).map(s=>s.measured_at)).filter(Boolean).sort()
  const jh=d.job_history,jhState=!jh?'':jh.known===false?'unknown':jh.stale?'stale':''
  const stale=lanes.flatMap(l=>l.stages||[]).filter(s=>s.stale).length,unknown=lanes.flatMap(l=>l.stages||[]).filter(s=>s.n==null).length
  return <section className="m-panel lf" data-lane-funnels aria-label="Lane funnels">
    <div className="cf-section-title"><div className="cf-section-heading"><h3>Lane funnels</h3><small>Every autonomous lane, stage by stage. A green job is not a transfer, and a transfer is not published data. &ldquo;Unknown&rdquo; means not counted, never zero.</small></div>
      <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>
    <p className="sl-sub" data-lf-stamp>Read {fmtDateTime(d.at)}. Oldest counted figure {stamps[0]?fmtDateTime(stamps[0]):'unknown'}; newest {stamps.length?fmtDateTime(stamps[stamps.length-1]):'unknown'}. {unknown>0?`${fmtNumber(unknown)} stage${unknown===1?'':'s'} not counted (unknown). `:''}{stale>0?`${fmtNumber(stale)} stale. `:''}Gains cover the last {fmtNumber(d.window_hours||24)} hours.</p>
    {jhState&&<p className="sl-sub" data-lf-job-history={jhState}>{jhState==='unknown'?'The scheduler history (running now, last attempt, runs) has not been counted yet, so those columns show unknown.':`The scheduler history (running now, last attempt, runs) was counted ${jh.measured_at?fmtDateTime(jh.measured_at):'at an unknown time'}${jh.age_seconds!=null?`, ${age(jh.measured_at)} ago`:''} and is stale.`}{jh.error?` The last attempt to count it again failed: ${jh.error}`:''}</p>}
    {err&&<p role="alert" className="lf-error">{err}</p>}{msg&&<p role="status" className="l4i-note">{msg}</p>}
    <div className="lf-head" aria-hidden="true"><span>Lane</span><span>State</span><span>Jobs on</span><span>Last attempt</span><span>Transfer 24 h</span><span>Published 24 h</span><span>Waiting for a person</span><span>Oldest waiting</span><span>Credits 24 h</span></div>
    <div className="lf-lanes">{lanes.map(l=><Lane key={l.lane} lane={l} rank={rank} busy={busy} onControl={control} asAt={jh?.known===false?null:jh?.measured_at} open={open===l.lane} onToggle={o=>setOpen(o?l.lane:(open===l.lane?'':open))}/>)}</div>
  </section>
}
