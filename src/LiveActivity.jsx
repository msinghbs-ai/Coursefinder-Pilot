// Live activity (Decision 214, v2.15.141). Platform Admin, 2 Oct 2026: "the UI should be more transparent what is
// running and happening at each layer at any given time". Every scheduled job by layer: running now, working through a
// queue (left, done in 24 hours, about how long to go), up to date, paused or failing; its last run and the worker's last
// summary; when it runs next; and what is waiting for a person. Read: admin_read('live_activity'), every 20 seconds
// while the page is open and visible. Read only.
// Decision 215 (v2.15.142): a scheduled run only sends the request, so it "succeeds" even when the worker refuses the
// work. Error replies from workers in the last few hours are now listed with a plain-English reading.
import React,{useEffect,useMemo,useRef,useState}from'react'
import{Activity,AlertTriangle,CheckCircle2,CirclePause,Clock,Loader2,RefreshCw,UserCheck}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import{fmtNumber,fmtTime}from'./lib/format.js'
import{errorReading}from'./lib/workerErrors.js'
import{Button}from'./ui-kit'

const REFRESH_MS=20000
// Areas in pipeline order, with the layer they belong to
export const AREAS=[
  ['Layer 1 register','Layer 1 · Registers','Official registers (CRICOS, NZQA) and rankings.'],
  ['Course pages','Layer 2 · Course pages','Finding and reading each course’s own page, and fee schedules.'],
  ['Layer 2 reading','Layer 2 · Provider reading','Provider-level reading waves and their housekeeping.'],
  ['Layer 3 AI','Layer 3 · AI checks','Tested models check what rules cannot decide.'],
  ['Admission','Admission','Rules that admit checked values into the catalogue.'],
  ['Scholarships','Scholarships','Discovery, reading, savings and the publishing review.'],
  ['Reports','Reports','Coverage, completeness and summary counts.'],
  ['Search and API','Search and website','Search index and the data the website reads.'],
  ['Platform upkeep','Platform upkeep','Health checks, credit balances and clean-up.'],
]
const NEEDS=[
  ['fee_schedules','Fee schedules to approve','coverage','attributes'],
  ['scholarships_ready','Scholarships ready to publish','scholarships','publishing'],
  ['scholarships_domestic','Domestic-only scholarships to check','scholarships','publishing'],
  ['layer4_reviews','Layer 4 reviews','layer4',null],
  ['flagged_values','Flagged values','layer4','flags'],
  ['ranking_links','Ranking links to review','rankings','datasets'],
]
const HIDE_KEYS=new Set(['ok','mode','worker','workerVersion','worker_version','scholarshipExtractor','phase','task'])

// Next run from a pg_cron schedule: "N seconds", or five fields (minute and hour lists, ranges and steps; UTC).
export function nextRun(schedule,now=new Date()){
  const s=String(schedule||'').trim();const sec=s.match(/^(\d+)\s+seconds?$/i)
  if(sec)return new Date(now.getTime()+Number(sec[1])*1000)
  const f=s.split(/\s+/);if(f.length!==5)return null
  const set=(field,lo,hi)=>{const out=new Set();for(const part of field.split(',')){const[r,st]=part.split('/');const step=Number(st||1);let a=lo,b=hi
    if(r!=='*'){const m=r.split('-');a=Number(m[0]);b=m.length>1?Number(m[1]):(st?hi:a)}for(let v=a;v<=b;v+=step)out.add(v)}return out}
  const mins=set(f[0],0,59),hrs=set(f[1],0,23),doms=f[2]==='*'?null:set(f[2],1,31),mons=f[3]==='*'?null:set(f[3],1,12),dows=f[4]==='*'?null:set(f[4].replace(/7/g,'0'),0,6)
  const t=new Date(now.getTime());t.setUTCSeconds(0,0);t.setUTCMinutes(t.getUTCMinutes()+1)
  for(let i=0;i<60*24*32;i++){
    if(mins.has(t.getUTCMinutes())&&hrs.has(t.getUTCHours())&&(!doms||doms.has(t.getUTCDate()))&&(!mons||mons.has(t.getUTCMonth()+1))&&(!dows||dows.has(t.getUTCDay())))return t
    t.setUTCMinutes(t.getUTCMinutes()+1)}
  return null
}
export const ago=(d,now=new Date())=>{if(!d)return'—';const s=Math.round((now-new Date(d))/1000);if(s<60)return`${Math.max(s,0)} s ago`;if(s<3600)return`${Math.round(s/60)} min ago`;if(s<86400)return`${Math.round(s/3600)} h ago`;return`${Math.round(s/86400)} d ago`}
export const until=(d,now=new Date())=>{if(!d)return'—';const s=Math.round((d-now)/1000);if(s<60)return'in under a minute';if(s<3600)return`in ${Math.round(s/60)} min`;if(s<86400)return`in ${Math.round(s/3600)} h`;return`in ${Math.round(s/86400)} d`}
const melb=d=>d?fmtTime(d,''):''


// What a job is doing now, in one word, with the reason
export function jobState(j){
  const q=j.queue
  if(!j.active)return['paused','Paused','Switched off on Scheduled jobs']
  if(j.running)return['running','Running now','Started '+ago(j.last?.start)]
  if(j.last?.status==='failed')return['failing','Failing',j.last?.message||'The last run failed']
  if(q&&Number(q.left)>0&&Number(q.done_24h)===0)return['stuck','Stuck',`${fmtNumber(q.left)} ${q.unit} waiting; none done in 24 h`]
  if(q&&Number(q.left)>0)return['working','Working',`${fmtNumber(q.left)} ${q.unit} left`]
  if(q)return['done','Up to date',`Nothing waiting; ${fmtNumber(q.done_24h)} ${q.unit} done in 24 h`]
  return['scheduled','Scheduled',j.failed_24h?`${j.failed_24h} failed runs in 24 h`:'Runs on its schedule']
}
const ICON={running:Loader2,working:Activity,done:CheckCircle2,scheduled:Clock,paused:CirclePause,failing:AlertTriangle,stuck:AlertTriangle}
const eta=q=>{const left=Number(q?.left||0),rate=Number(q?.done_24h||0)/24;if(!left||!rate)return null;const h=left/rate;return h<1?`about ${Math.max(1,Math.round(h*60))} min to go`:h<48?`about ${Math.round(h)} h to go`:`about ${Math.round(h/24)} days to go`}
function summary(result){
  if(!result)return null
  const parts=[]
  for(const[k,v]of Object.entries(result)){if(HIDE_KEYS.has(k)||v==null)continue
    if(typeof v==='object'){for(const[k2,v2]of Object.entries(v)){if(typeof v2==='number')parts.push(`${k2.replace(/_/g,' ')} ${fmtNumber(v2)}`);else if(v2&&typeof v2==='object')for(const[k3,v3]of Object.entries(v2))if(typeof v3==='number')parts.push(`${k3.replace(/_/g,' ')} ${fmtNumber(v3)}`)}}
    else if(typeof v==='number')parts.push(k==='ms'?`took ${(v/1000).toFixed(1)} s`:`${k.replace(/([A-Z])/g,' $1').replace(/_/g,' ').toLowerCase()} ${fmtNumber(v)}`)
    else if(typeof v==='boolean'&&v)parts.push(k.replace(/_/g,' '))}
  return parts.slice(0,8).join(' · ')
}

export default function LiveActivity({navigate,rank=0}){
  const[data,setData]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[live,setLive]=useState(true),[onlyActive,setOnlyActive]=useState(false),[tick,setTick]=useState(Date.now())
  const timer=useRef(null)
  // Decision 218: an operator marks an error as seen; it shows again only if it happens again
  const seen=async e=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_live_error_ack',{p_function:e.function||'',p_status:e.status??null,p_message:e.message||''});if(error)throw error;if(d)setData(d);setErr('')}catch(x){setErr(x.message||String(x))}finally{setBusy(false)}}
  const load=async()=>{setBusy(true);try{const d=await adminRead('live_activity',{});setData(d);setErr('')}catch(e){setErr(e.message||String(e))}finally{setBusy(false);setTick(Date.now())}}
  useEffect(()=>{load()},[])
  useEffect(()=>{clearInterval(timer.current);if(!live)return
    timer.current=setInterval(()=>{if(document.visibilityState==='visible')load()},REFRESH_MS);return()=>clearInterval(timer.current)},[live])
  const now=new Date(tick)
  const byArea=useMemo(()=>{const m=new Map();for(const j of data?.jobs||[]){if(!m.has(j.area))m.set(j.area,[]);m.get(j.area).push(j)}return m},[data])
  const counts=useMemo(()=>{const c={running:0,working:0,failing:0,stuck:0,paused:0};for(const j of data?.jobs||[]){const s=jobState(j)[0];if(s in c)c[s]++}return c},[data])
  const np=data?.needs_person||{}
  if(!data&&!err)return <section className="m-panel"><p className="sd-desc">Loading live activity…</p></section>
  return <div className="la" data-live-activity>
    <section className="m-panel la-head">
      <div><strong>{counts.running} running now · {counts.working} working through a queue{counts.failing+counts.stuck?` · ${counts.failing+counts.stuck} need attention`:''}{counts.paused?` · ${counts.paused} paused`:''}{data?.worker_errors?.length?` · ${fmtNumber(data.worker_errors.reduce((t,e)=>t+Number(e.count||0),0))} worker error replies`:''}</strong>
        <small className="sd-desc" data-live-updated>{live?`Live: refreshes every ${REFRESH_MS/1000} s`:'Paused'} · updated {melb(data?.now)}{busy?' · updating…':''}{data?.in_flight?` · ${fmtNumber(data.in_flight)} worker calls in flight`:''}</small></div>
      <div className="sd-actions">
        <label className="la-toggle"><input type="checkbox" checked={onlyActive} onChange={e=>setOnlyActive(e.target.checked)}/> Only what is busy or needs attention</label>
        <Button compact onClick={()=>setLive(v=>!v)} aria-pressed={live}>{live?'Pause updates':'Resume updates'}</Button>
        <Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>
      {err&&<p className="fr-error" role="alert">{err}</p>}
    </section>

    <section className="m-panel" data-needs-person>
      <h3 className="la-h"><UserCheck size={16}/>Waiting for a person</h3>
      <div className="la-needs">{NEEDS.map(([k,label,page,tab])=><button type="button" key={k} className={Number(np[k])?'la-need on':'la-need'} onClick={()=>navigate?.(page,tab?{tab}:{})} data-need={k}>
        <b>{fmtNumber(np[k]||0)}</b><span>{label}</span></button>)}</div>
    </section>

    {(data?.worker_errors||[]).length>0&&<section className="m-panel la-errors" data-worker-errors>
      <h3 className="la-h"><AlertTriangle size={16}/>Workers sending back errors<small className="sd-desc">A job’s run can show as succeeded while the worker it calls refuses the work. These are the error replies from the last few hours. Mark one as seen once it is understood; it shows again only if it happens again.</small></h3>
      <div className="cf-table-wrap"><table className="cf-table la-table"><thead><tr><th>Job</th><th>Reply</th><th>What it means</th><th>How often</th><th>Last</th>{rank>=4&&<th>Action</th>}</tr></thead>
        <tbody>{data.worker_errors.map((e,i)=><tr key={i} data-worker-error={e.status??'none'}>
          <td><strong>{e.job||e.function||'Unknown job'}</strong>{e.job&&e.function?<small className="sd-desc">{e.function}</small>:null}</td>
          <td><span className="la-state failing"><AlertTriangle size={13}/>{e.timed_out?'Timed out':e.status==null?'No reply':`Error ${e.status}`}</span><small className="sd-desc la-msg">{e.message||'—'}</small></td>
          <td>{errorReading(e)}</td>
          <td>{fmtNumber(e.count)}</td>
          <td>{ago(e.last,now)}<small className="sd-desc">{melb(e.last)}</small></td>
          {rank>=4&&<td><Button compact disabled={busy} onClick={()=>seen(e)} data-error-seen>Mark as seen</Button></td>}</tr>)}</tbody></table></div>
    </section>}

    {AREAS.filter(([a])=>byArea.has(a)).map(([area,title,about])=>{
      const jobs=byArea.get(area).filter(j=>!onlyActive||['running','working','failing','stuck'].includes(jobState(j)[0]))
      if(!jobs.length)return null
      return <section className="m-panel la-area" key={area} data-area={area}>
        <h3 className="la-h">{title}<small className="sd-desc">{about}</small></h3>
        <div className="cf-table-wrap"><table className="cf-table la-table"><thead><tr><th>Job</th><th>Now</th><th>Last run</th><th>Last result</th><th>Next run</th></tr></thead>
          <tbody>{jobs.map(j=>{const[st,label,why]=jobState(j),Icon=ICON[st],nr=j.active?nextRun(j.schedule,now):null,e=eta(j.queue),sum=summary(j.worker?.result)
            return <tr key={j.job} data-job={j.job} data-state={st}>
              <td><strong>{j.label}</strong><small className="sd-desc">{j.description}</small></td>
              <td><span className={`la-state ${st}`}><Icon size={13} className={st==='running'?'la-spin':''}/>{label}</span><small className="sd-desc">{why}{e?` · ${e}`:''}</small></td>
              <td>{ago(j.last?.start,now)}<small className="sd-desc">{j.last?.status==='failed'?'failed':j.last?.status||'—'}{j.runs_24h?` · ${fmtNumber(j.runs_24h)} runs in 24 h`:''}{j.failed_24h?` · ${fmtNumber(j.failed_24h)} failed`:''}</small></td>
              <td>{sum?<><span className="la-sum">{sum}</span><small className="sd-desc">{ago(j.worker?.at,now)}</small></>:<small className="sd-desc">{j.worker?'No reply kept from the last few hours':'—'}</small>}</td>
              <td>{nr?<>{until(nr,now)}<small className="sd-desc">{melb(nr)}</small></>:'—'}</td></tr>})}</tbody></table></div>
      </section>})}
  </div>
}
