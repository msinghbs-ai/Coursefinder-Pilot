// CF-247 F-OPS.03A (Platform Admin P0, 9 Nov 2026 21:28): the Data Delivery summary at the TOP of Layer 2/3 > Operations. "I should not have to rely on your chat messages
// to know whether StudySearch is processing, admitting or publishing data."
// One row per data stream: coverage (n of N), net admission gain over the short and long windows (admitted minus withdrawn, from each stream's own ledger
// timestamps), Website and Zoho state, queue, holds with the largest exact reasons, processing speed, last and next run, and the automatic recovery status.
// It reuses the lane funnels below it (queue and hold stages, the reason breakdown), the Provider Catalogue and the Course Catalogue for drill-down; it
// is not another dashboard. Server: public.admin_layer23('data_delivery') (rank 3 and above, the same gate as Operations; SELECT only, counted by job
// data-delivery). It reloads itself at the interval in Pipeline settings > Data delivery (stops while the tab is hidden), and has a Refresh button.
// Unknown is never 0: a measure that is not counted, not built or failed shows "Not measured" or "Unknown" with the reason. A green job that admitted nothing
// in the window carries a visible flag that links to the reason breakdown. Times are Melbourne time, to the second where the page was read.
import React,{useCallback,useEffect,useRef,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber,fmtRelative}from'./ui-kit'
import{plainError}from'./lib/errors'
import'./data-delivery.css'

const SECONDS=new Intl.DateTimeFormat('en-AU',{timeZone:'Australia/Melbourne',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'})
const stampOf=v=>{const t=v?new Date(v):null;return t&&!Number.isNaN(t.getTime())?SECONDS.format(t):null}
const num=x=>x==null?'':fmtNumber(Number(x))
const hoursText=h=>{const n=Number(h);return n===168?'7 d':n%24===0&&n>=48?`${n/24} d`:`${fmtNumber(n)} h`}
const ago=(iso,now)=>iso?fmtRelative(iso,'',now):''
function until(iso,now){if(!iso)return'';const s=Math.round((new Date(iso).getTime()-now)/1000);if(!(s>-60))return'due now';if(s<60)return'in under a minute';if(s<3600)return`in ${Math.round(s/60)} min`;if(s<86400)return`in ${Math.round(s/3600)} h`;return`in ${Math.round(s/86400)} days`}
const RECOVERY={healthy:['success','Retrying on schedule'],recovering:['info','Recovering'],needs_attention:['warning','Needs attention'],failing:['danger','Last run failed'],off:['warning','Off'],unknown:['neutral','Unknown']}
const FLAG_TONE={warn:'warning',bad:'danger',info:'neutral'}

/** The word shown when a figure is not counted: never 0, never blank, with the reason beside it. */
function Unknown({reason,word='Not measured'}){return <span className="dd-unknown" data-dd-unknown><em>{word}</em>{reason&&<small title={reason}>{reason}</small>}</span>}
function Stale({m}){return m?.stale?<StatusChip tone="warning" label="Stale" title={`Counted ${m.age_minutes??'?'} min ago`}/>:null}

function href(screen,filters,extra){return hrefFor(screen,'',Object.fromEntries([...Object.entries(filters||{}).map(([k,v])=>[`f_${k}`,v]),...Object.entries(extra||{}).map(([k,v])=>[`f_${k}`,v])]))}

function Coverage({c,unit,drill}){
  if(!c?.known)return <Unknown reason={c?.reason} word="Unknown"/>
  const pct=c.pct==null?null:`${fmtNumber(Number(c.pct),{maxDecimals:1})}%`
  return <span data-dd-value={c.n}><strong>{num(c.n)}</strong>{c.total!=null&&<> of {num(c.total)}</>} <small>{unit}</small>
    {pct&&<span className="dd-bar" role="img" aria-label={`${pct} covered`}><i style={{width:`${Math.min(100,Number(c.pct))}%`}}/></span>}
    <small>{pct?`${pct} covered. `:''}{c.total==null&&<span data-dd-total-unknown title={c.total_reason}>Total not measured: {c.total_reason}. </span>}<Stale m={c}/></small></span>
}
function Net({n,hours}){
  if(!n?.known)return <Unknown reason={n?.reason} word="Unknown"/>
  const net=n.net,added=Number(n.added),removed=n.removed==null?null:Number(n.removed)
  const sign=v=>v>0?`+${fmtNumber(v)}`:v<0?`−${fmtNumber(Math.abs(v))}`:'0'
  return <span data-dd-net={net==null?'unknown':net} data-dd-added={added}>
    {net==null?<><strong>{sign(added)}</strong> <small>admitted</small></>:<strong>{sign(Number(net))}</strong>}
    <small>{fmtNumber(added)} in{removed==null?'':` · ${fmtNumber(removed)} out`}{removed==null&&<span data-dd-removed-unknown title={n.removed_reason}>; removals not measured: {n.removed_reason}</span>}</small>
    {n.partial&&<small data-dd-partial>{n.since?`Ledger starts ${fmtDateTime(n.since)}`:'No ledger events yet'}, shorter than {hoursText(hours)}</small>}
    <Stale m={n}/></span>
}
function Feed({f,drillLinks,note}){
  if(!f?.known)return <Unknown reason={f?.reason}/>
  return <span data-dd-value={f.matched}><strong>{num(f.matched)}</strong> <small>of {num(f.expected)} matched</small>
    <small>{drillLinks.pending?<a href={drillLinks.pending} data-dd-drill="pending">{num(f.pending)} pending</a>:<>{num(f.pending)} pending</>}{' · '}{drillLinks.missing?<a href={drillLinks.missing} data-dd-drill="missing">{num(f.missing)} missing</a>:<>{num(f.missing)} missing</>}{' · '}{num(f.not_applicable)} not applicable</small>
    <Stale m={f}/></span>
}
function Parts({p,label}){
  if(!p?.known)return <Unknown reason={p?.reason}/>
  return <span data-dd-value={p.n}><strong>{p.partial?'≥ ':''}{num(p.n)}</strong>
    {p.partial&&<small data-dd-partial>Some stages are not counted</small>}
    {(p.parts||[]).map(x=><small key={x.stage+x.title} data-dd-part={x.stage}>{x.title} {x.n==null?<em title={x.error||'not counted'}>unknown</em>:num(x.n)}</small>)}
    {p.causes_reason&&<small data-dd-causes-unknown>By cause: {p.causes_reason}</small>}</span>
}
function Holds({h}){
  if(!h?.known)return <Unknown reason={h?.reason}/>
  return <span data-dd-value={h.n}><strong>{h.partial?'≥ ':''}{num(h.n)}</strong>
    {h.partial&&<small data-dd-partial>Some stages are not counted</small>}
    {(h.parts||[]).map(x=><small key={x.stage+x.title}>{x.title} {x.n==null?<em title={x.error||'not counted'}>unknown</em>:num(x.n)}</small>)}
    {(h.reasons||[]).length>0&&<ul className="dd-reasons" data-dd-reasons>{h.reasons.map((r,i)=><li key={i}><span title={r.reason}>{r.reason}</span> <strong>{num(r.n)}</strong></li>)}</ul>}
    {h.causes_reason&&<small data-dd-causes-unknown>By cause: {h.causes_reason}</small>}</span>
}
function Speed({s}){
  if(!s?.known)return <Unknown reason={s?.reason}/>
  return <span data-dd-value={s.per_hour}><strong>{fmtNumber(Number(s.per_hour),{maxDecimals:1})}</strong> <small>per hour</small><small>{num(s.processed)} {s.basis||'items'} in {fmtNumber(Number(s.window_hours),{maxDecimals:1})} h</small></span>
}
function Runs({j,now}){
  if(!j?.known)return <Unknown reason={j?.reason} word="Unknown"/>
  const bad=j.last_status==='failed'
  return <span data-dd-last={j.last_run_at||''}>
    <small>Last</small> <strong>{fmtDateTime(j.last_run_at)}</strong> <small>{ago(j.last_run_at,now)}</small> <StatusChip tone={bad?'danger':j.last_status==='succeeded'?'success':'neutral'} label={bad?'Failed':j.last_status==='succeeded'?'OK':String(j.last_status||'').replaceAll('_',' ')||'Unknown'} title={j.last_message||undefined}/>
    <small>Next</small> {j.next_run_at?<><strong data-dd-next={j.next_run_at}>{fmtDateTime(j.next_run_at)}</strong> <small>{until(j.next_run_at,now)}</small></>:<em data-dd-unknown>{Number(j.active)>0?'Unknown':'Not scheduled (paused or off)'}</em>}</span>
}
function Recovery({r}){
  const[tone,label]=RECOVERY[r?.state]||RECOVERY.unknown
  return <span data-dd-recovery={r?.state||'unknown'}><StatusChip tone={tone} label={label}/><small>{r?.text}</small>{(r?.issue_refs||[]).length>0&&<small>Open: {r.issue_refs.join(', ')}</small>}</span>
}

function Stream({s,now,providerFilters,open,onToggle}){
  const dr=s.drill||{}
  const lanes=hrefFor('layer2','operations',{lane:s.lane})
  const filtersOk=dr.needs_provider_filters?providerFilters:true
  const link=(f,extra)=>dr.screen&&f&&filtersOk?href(dr.screen,f,extra):null
  const feedLink=(side,state)=>dr.screen==='providers'&&dr[side]&&providerFilters?href('providers',{[dr[side].key]:state}):null
  const flags=s.flags||[]
  const cells=[
    ['coverage','Coverage',<Coverage c={s.coverage} unit={s.unit}/>],
    ['net_short',`Net ${hoursText(s.net_short?.window_hours)}`,<Net n={s.net_short} hours={s.net_short?.window_hours}/>],
    ['net_long',`Net ${hoursText(s.net_long?.window_hours)}`,<Net n={s.net_long} hours={s.net_long?.window_hours}/>],
    ['website','Website',<Feed f={s.website} drillLinks={{pending:feedLink('website','pending'),missing:feedLink('website','missing')}}/>],
    ['zoho','Zoho',<Feed f={s.zoho} drillLinks={{pending:feedLink('zoho','pending'),missing:feedLink('zoho','missing')}}/>],
    ['queue','Queue',<Parts p={s.queue}/>],
    ['holds','Holds and reasons',<Holds h={s.holds}/>],
    ['speed','Speed',<Speed s={s.speed}/>],
    ['runs','Last and next run',<Runs j={s.jobs} now={now}/>],
    ['recovery','Automatic recovery',<Recovery r={s.recovery}/>],
  ]
  const filled=link(dr.filled,{}),missing=link(dr.missing,{})
  return <details className="dd-stream" data-dd-stream={s.stream} data-dd-stale={s.stale?'true':'false'} open={open} onToggle={e=>onToggle(e.currentTarget.open)}>
    <summary>
      <div className="dd-name" data-dd-cell="name"><strong>{s.title}</strong>
        {flags.map(f=><span key={f.code} className={`dd-flag tone-${FLAG_TONE[f.severity]||'neutral'}`} data-dd-flag={f.code} role="status"><span>{f.text}</span>{f.code.startsWith('green')&&<> <a href={lanes} onClick={e=>e.stopPropagation()} data-dd-reasons-link>See reasons</a></>}</span>)}
      </div>
      {cells.map(([k,label,node])=><div className="dd-cell" key={k} data-label={label} data-dd-cell={k}>{node}</div>)}
    </summary>
    <div className="dd-body">
      <p><strong>What this stream is.</strong> {s.what}</p>
      <p><strong>How the net gain is counted.</strong> {s.net_basis||'Not stated.'} Net = admitted minus withdrawn, from the ledger timestamps in the window.</p>
      {(s.coverage?.by_country||[]).length>0&&<table className="cf-table dd-countries"><thead><tr><th>Country</th><th>Covered</th><th>Of</th></tr></thead><tbody>
        {s.coverage.by_country.map(c=><tr key={c.cc}><td data-label="Country">{c.cc}</td><td data-label="Covered">{num(c.n)}</td><td data-label="Of">{c.total==null?'Not measured':num(c.total)}</td></tr>)}</tbody></table>}
      <div className="dd-drill" data-dd-drill-box>
        <strong>Open in the catalogue</strong>
        {filled&&<a href={filled} data-dd-drill="filled">Filled</a>}{missing&&<a href={missing} data-dd-drill="missing">Missing</a>}
        {dr.screen&&!filled&&!missing&&dr.screen!=='providers'&&<a href={hrefFor(dr.screen)} data-dd-drill="open">Open the list</a>}
        <a href={lanes} data-dd-drill="lane">Reason breakdown</a>
        {dr.needs_provider_filters&&!providerFilters&&<small data-dd-degraded>Provider Catalogue filters (Filled, Missing, Website and Zoho state) arrive with the Provider Catalogue columns release; these links appear then.</small>}
        {dr.note&&<small data-dd-drill-note>{dr.note}</small>}
      </div>
      <h4 className="sl-h4">Primary jobs</h4>
      <div className="lf-frame"><table className="cf-table"><thead><tr><th>Job</th><th>Last run</th><th>Result</th><th>Next run</th><th>Runs ({hoursText(s.net_short?.window_hours)})</th></tr></thead><tbody>
        {(s.jobs?.list||[]).map(j=><tr key={j.job}><td data-label="Job">{j.job}{!j.scheduled&&<small> not scheduled</small>}</td><td data-label="Last run">{j.last_start?fmtDateTime(j.last_start):'Unknown'}</td>
          <td data-label="Result">{j.last_status?`${String(j.last_status).replaceAll('_',' ')}${j.last_message?`: ${j.last_message}`:''}`:'Unknown'}</td><td data-label="Next run">{j.next_run?fmtDateTime(j.next_run):j.scheduled?'Paused':'Unknown'}</td>
          <td data-label="Runs">{j.scheduled?`${num(j.succeeded)} ok, ${num(j.failed)} failed`:'Unknown'}</td></tr>)}</tbody></table></div>
    </div>
  </details>
}

export default function DataDelivery({rank=0,onError,client=null}){
  const[d,setD]=useState(null),[err,setErr]=useState(null),[busy,setBusy]=useState(false),[now,setNow]=useState(()=>Date.now()),[open,setOpen]=useState({})
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const last=useRef(0),inflight=useRef(false)
  const load=useCallback(async()=>{
    if(inflight.current)return
    inflight.current=true;setBusy(true)
    try{const{data,error}=await rpc('admin_layer23',{p_action:'data_delivery',p_args:{}});if(error)throw error
      if(!data||!Array.isArray(data.streams))throw new Error('The Data Delivery read returned no streams')
      setD(data);setErr(null);last.current=Date.now()}
    catch(e){const m=plainError(e);setErr({message:m,at:new Date().toISOString()});onError?.(m)}
    finally{inflight.current=false;setBusy(false);setNow(Date.now())}
  },[])
  useEffect(()=>{load()},[])
  const every=Math.max(15,Number(d?.ui_refresh_seconds||60))*1000
  useEffect(()=>{
    // reload on the setting's interval while the tab is visible; nothing runs while it is hidden, and a hidden tab reloads when shown if it is overdue
    const t=setInterval(()=>{if(document.visibilityState==='visible')load();else setNow(Date.now())},every)
    const tick=setInterval(()=>{if(document.visibilityState==='visible')setNow(Date.now())},15000)
    const vis=()=>{if(document.visibilityState==='visible'&&Date.now()-last.current>=every)load()}
    document.addEventListener('visibilitychange',vis)
    return()=>{clearInterval(t);clearInterval(tick);document.removeEventListener('visibilitychange',vis)}
  },[every,load])
  if(rank<3)return null
  if(!d)return <section className="m-panel dd" data-data-delivery aria-label="Data delivery">{err?<div role="alert" data-dd-error><p>Data delivery could not be read: {err.message}</p><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></div>:<Loading label="Reading data delivery…"/>}</section>
  const streams=d.streams||[]
  const flagged=streams.filter(s=>(s.flags||[]).some(f=>f.code.startsWith('green')))
  const failing=streams.filter(s=>(s.flags||[]).some(f=>f.code==='job_failing'))
  const snap=d.snapshot||{}
  const age=snap.oldest_measured_at?Math.round((Date.now()-new Date(snap.oldest_measured_at).getTime())/60000):null
  return <section className="m-panel dd" data-data-delivery aria-label="Data delivery">
    <div className="cf-section-title"><div className="cf-section-heading"><h3>Data delivery</h3>
      <small>Is StudySearch processing, admitting and publishing data? Live from the database, by stream. &ldquo;Not measured&rdquo; and &ldquo;Unknown&rdquo; mean the figure is not counted here, never zero.</small></div>
      <Button compact onClick={load} disabled={busy} data-dd-refresh><RefreshCw size={14}/>Refresh</Button></div>
    <p className="sl-sub" data-dd-stamp>Updated <strong data-dd-updated>{stampOf(d.at)}</strong> (Melbourne). Reloads every {fmtNumber(every/1000)} s while this tab is open.
      {' '}Counts were taken {snap.newest_measured_at?`as recently as ${stampOf(snap.newest_measured_at)}`:'at an unknown time'}{age!=null?`, the oldest ${age} min ago`:''}.
      {Number(snap.failed_measures)>0&&<> <strong>{fmtNumber(snap.failed_measures)} measure(s) could not be counted.</strong></>}</p>
    {err&&<p role="alert" className="dd-stale" data-dd-stale-banner>The last refresh failed at {stampOf(err.at)} (Melbourne): {err.message}. These are the figures read at {stampOf(d.at)}; they may be out of date.</p>}
    {(flagged.length>0||failing.length>0)&&<p className="dd-summary" data-dd-summary>{flagged.length>0&&<><strong>{flagged.length}</strong> stream{flagged.length===1?'':'s'} ran green but admitted nothing in {hoursText(d.windows?.short_hours)} ({flagged.map(s=>s.title).join(', ')}). </>}{failing.length>0&&<><strong>{failing.length}</strong> with a failed run ({failing.map(s=>s.title).join(', ')}).</>}</p>}
    <div className="dd-head" aria-hidden="true"><span>Stream</span><span>Coverage</span><span>Net {hoursText(d.windows?.short_hours)}</span><span>Net {hoursText(d.windows?.long_hours)}</span><span>Website</span><span>Zoho</span><span>Queue</span><span>Holds and reasons</span><span>Speed</span><span>Last and next run</span><span>Automatic recovery</span></div>
    <div className="dd-streams">{streams.map(s=><Stream key={s.stream} s={s} now={now} providerFilters={Boolean(d.provider_filters_available)} open={Boolean(open[s.stream])} onToggle={o=>setOpen(x=>({...x,[s.stream]:o}))}/>)}</div>
    <p className="sl-sub">Net = admitted minus withdrawn, from each stream&rsquo;s own ledger timestamps. A job the scheduler reports as OK says nothing about data: the flag shows when it admitted nothing. Reload interval, windows and the number of reasons are settings (Settings &rsaquo; Pipeline settings &rsaquo; Data delivery).</p>
  </section>
}
