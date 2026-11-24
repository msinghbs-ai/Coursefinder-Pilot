import './tokens.css'
import './ui-kit.css'
// Pipeline Maintenance Mode (CF-247, Platform Admin 15 Nov 2026): pause every scheduled job before a database change, watch what is
// still running drain to nothing, then resume exactly the jobs the pause switched off.
// Read and write: public.admin_pipeline_maintenance(action, args) with action status, pause or resume
// (migration 20261115180000_cf247_pipeline_maintenance_mode). Pause and resume are for the Platform Admin; anyone with an admin role sees the state.
// States: ACTIVE (jobs running), DRAINING (paused, work still in flight), SAFE (paused and nothing in flight: SAFE TO APPLY DB CHANGES).
import React,{useCallback,useEffect,useRef,useState}from'react'
import{Pause,Play,RefreshCw,ShieldCheck,Wrench}from'lucide-react'
import{supabase}from'../lib/supabase'
import{Button,SectionTitle,fmtDateTime,fmtNumber}from'./kit.jsx'

// fixed: screen refresh while paused, as the Platform Admin set it (15 Nov 2026); it reads status only and changes nothing
const POLL_MS=2000
const PLATFORM_ADMIN=6

export function elapsedText(seconds){
  const s=Math.max(0,Math.floor(Number(seconds)||0)),h=Math.floor(s/3600),m=Math.floor((s%3600)/60),r=s%60
  return `${h?`${h}:`:''}${String(m).padStart(h?2:1,'0')}:${String(r).padStart(2,'0')}`
}

function Count({label,value,detail}){
  const n=Number(value)||0
  return <span className={`ui-pm-badge ${n?'busy':'clear'}`} data-pm-count={label} title={detail||undefined}>{label} <b>{fmtNumber(n)}</b></span>
}

export default function PipelineMaintenance({rank=0,onError,onChanged}){
  const[st,setSt]=useState(null),[failed,setFailed]=useState(''),[busy,setBusy]=useState(false),[ask,setAsk]=useState(null),[reason,setReason]=useState(''),[now,setNow]=useState(Date.now())
  const live=useRef(true)
  const load=useCallback(async()=>{
    try{const{data,error}=await supabase.rpc('admin_pipeline_maintenance',{p_action:'status',p_args:{}});if(error)throw error
      if(live.current){setSt(data&&typeof data==='object'&&!Array.isArray(data)?data:null);setFailed('')}}
    catch(e){if(live.current)setFailed(e.message||String(e))}
  },[])
  useEffect(()=>{live.current=true;load();return()=>{live.current=false}},[load])
  const paused=Boolean(st?.is_paused)
  useEffect(()=>{if(!paused)return;const t=setInterval(load,POLL_MS);return()=>clearInterval(t)},[paused,load])
  useEffect(()=>{if(!paused)return;const t=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(t)},[paused])
  const act=async(action,why='')=>{
    setBusy(true)
    try{const{data,error}=await supabase.rpc('admin_pipeline_maintenance',{p_action:action,p_args:action==='pause'?{reason:why}:{}});if(error)throw error
      setSt(data);setAsk(null);setReason('');onChanged?.()}
    catch(e){onError?.(e.message||String(e))}
    finally{setBusy(false)}
  }
  if(failed&&!st)return <section className="ui-card ui-pm-card" data-pipeline-maintenance="error"><SectionTitle icon={Wrench} title="Pipeline maintenance" subtitle={`Could not read the maintenance state: ${failed}`} action={<Button compact onClick={load}><RefreshCw size={14}/>Try again</Button>}/></section>
  if(!st)return null
  const can=rank>=PLATFORM_ADMIN&&!busy,state=st.state||'ACTIVE'
  const elapsed=paused&&st.paused_at?Math.max(0,(now-new Date(st.paused_at).getTime())/1000):0
  const alertMin=Number(st.alert_after_minutes)||0,overdue=paused&&alertMin>0&&elapsed>alertMin*60
  const back=st.jobs_switched_on_again||[],leases=st.leases||{}
  return <section className="ui-card ui-pm-card" data-pipeline-maintenance={state} data-pm-state={state} data-pm-overdue={overdue?'yes':'no'}>
    <SectionTitle icon={Wrench} title="Pipeline maintenance" subtitle="Pause every scheduled job before a database change, wait until nothing is running, apply the change, then resume. Resume switches on only the jobs the pause switched off."
      action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button>}/>
    {state==='ACTIVE'&&<>
      <div className="ui-pm-meta"><span data-pm-active-jobs>{fmtNumber(st.active_jobs)} scheduled jobs running</span>
        {st.last_result?.action==='resume'&&<span>Last maintenance: {fmtNumber(st.last_result.restored)} jobs switched on again after {st.last_result.paused_minutes} minutes</span>}</div>
      {rank>=PLATFORM_ADMIN?<Button variant="danger" onClick={()=>setAsk('pause')} disabled={!can} data-pm-pause><Pause size={14}/>Pause &amp; Drain for Migration</Button>
        :<p className="ui-muted">The Platform Admin pauses and resumes the pipeline.</p>}
    </>}
    {paused&&<>
      {state==='SAFE'
        ?<div className="ui-pm-banner safe" role="status" data-pm-safe><ShieldCheck size={22}/>SAFE TO APPLY DB CHANGES<small>Nothing is running, leased or locked.</small></div>
        :<div className="ui-pm-banner draining" role="status" data-pm-draining>DRAINING<small>Paused; waiting for work already under way to finish.</small></div>}
      <div className="ui-pm-meta">
        <span>Paused <span className={`ui-pm-elapsed${overdue?' overdue':''}`} data-pm-elapsed>{elapsedText(elapsed)}</span>{overdue&&<strong className="ui-pm-err"> longer than {alertMin} minutes</strong>}</span>
        <span>Since {fmtDateTime(st.paused_at)}</span><span>By {/^[0-9a-f-]{36}$/i.test(st.paused_by||'')?'a Platform Admin':(st.paused_by||'—')}</span><span>Reason: {st.reason||'—'}</span>
        <span>{fmtNumber(st.jobs_switched_off)} jobs switched off</span>
      </div>
      <div className="ui-pm-badges">
        <Count label="Running cron jobs" value={st.running_cron} detail={(st.running_cron_detail||[]).map(r=>`${r.job}${r.stale?' (stale)':''}`).join(', ')}/>
        <Count label="Active DB queries" value={st.db_backends}/>
        <Count label="Edge worker calls" value={Number(st.edge_calls_in_flight||0)+Number(st.http_queue||0)}/>
        <Count label="Worker leases" value={st.leases_total} detail={`Field items ${leases.field_enrich_items||0}, course pages ${leases.coverage_course_pages||0}, Layer 4 claims ${leases.layer4_claims||0}`}/>
        <Count label="catalogue.* locks" value={st.catalogue_locks}/>
        <Count label="Jobs back on" value={back.length} detail={back.join(', ')}/>
      </div>
      {Number(st.api_reads)>0&&<p className="ui-muted">{fmtNumber(st.api_reads)} website, Zoho or admin read(s) in progress through the API. They are short and not counted; a migration waits for them.</p>}
      {back.length>0&&<p className="ui-pm-err" data-pm-back>Switched on again during the pause: {back.join(', ')}. Pause them on Automations before applying changes.</p>}
      {(st.db_backends_detail||[]).length>0&&<ul className="ui-pm-detail">{st.db_backends_detail.map(d=><li key={d.pid}>{d.app||d.user} · {d.state} · {d.query}</li>)}</ul>}
      {(st.locks_detail||[]).length>0&&<ul className="ui-pm-detail">{st.locks_detail.slice(0,8).map((l,i)=><li key={i}>{l.table} · {l.mode}{l.granted?'':' (waiting)'}</li>)}</ul>}
      {Number(st.settings_changed_since_pause)>0&&<p className="ui-muted">{fmtNumber(st.settings_changed_since_pause)} setting(s) changed since the pause. Resume does not change settings; it lists them.</p>}
      {rank>=PLATFORM_ADMIN?<Button variant="primary" onClick={()=>setAsk('resume')} disabled={!can} data-pm-resume><Play size={14}/>Resume Pipeline</Button>
        :<p className="ui-muted">The Platform Admin resumes the pipeline.</p>}
    </>}
    {ask&&<div className="ui-pm-backdrop" onClick={e=>{if(e.target===e.currentTarget&&!busy)setAsk(null)}}>
      <section className="ui-pm-dialog" role="dialog" aria-modal="true" aria-label={ask==='pause'?'Pause the pipeline':'Resume the pipeline'}>
        {ask==='pause'?<>
          <h3>Pause &amp; drain for migration?</h3>
          <p>Every active scheduled job ({fmtNumber(st.active_jobs)}) is switched off and a copy of every job and setting is kept. Jobs already off stay off. The website and Zoho APIs keep answering, but nothing is read, enriched, admitted or refreshed until you resume.</p>
          <label>Reason (optional)<input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Manual DB schema migration" data-pm-reason/></label>
        </>:<>
          <h3>Resume the pipeline?</h3>
          <p>The {fmtNumber(st.jobs_switched_off)} jobs the pause switched off are switched on again. Jobs that were off before the pause stay off, and no setting is changed.</p>
        </>}
        <div className="ui-pm-dialog-actions">
          <Button onClick={()=>setAsk(null)} disabled={busy}>Cancel</Button>
          {ask==='pause'
            ?<Button variant="danger" onClick={()=>act('pause',reason.trim()||'Manual DB schema migration')} disabled={busy} data-pm-confirm><Pause size={14}/>{busy?'Pausing…':'Pause all jobs'}</Button>
            :<Button variant="primary" onClick={()=>act('resume')} disabled={busy} data-pm-confirm><Play size={14}/>{busy?'Resuming…':'Resume Pipeline'}</Button>}
        </div>
      </section>
    </div>}
  </section>
}
