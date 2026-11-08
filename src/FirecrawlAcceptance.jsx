// CF-247 OPS/UI (Platform Admin mandate 8 Nov 2026 section 3): Firecrawl acceptance, read only, on Settings > Services & limits > Firecrawl. Shows the plan
// allowance, the live remaining credits from the vendor reading (job firecrawl-credit), when it was last read, what each lane group and purpose used, the
// reserved floor kept back from course page search, and the daily spend against the daily shares. Credits, never money. Unknown stays "unknown".
// Server: public.admin_firecrawl_acceptance_v1 (rank 3 and above, SELECT only; reads the Controller's security.fc_* functions and edits none).
// The limits themselves are changed in the Firecrawl card's settings above (Platform Admin, with a reason).
import React,{useEffect,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import Card from'./Card'
import{Button,Loading,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'
import{cronText}from'./Progress'
import'./lane-funnels.css'

const num=x=>x==null?'unknown':fmtNumber(Math.round(Number(x)))
const GROUP={course_search:'Finding course pages',reads:'Reading pages',scholarships:'Scholarships',central:'Central pages',other:'Other'}
const ago=m=>m==null?'unknown':m<60?`${fmtNumber(m)} min ago`:m<2880?`${fmtNumber(Math.round(m/60))} h ago`:`${fmtNumber(Math.round(m/1440))} days ago`

export default function FirecrawlAcceptance({onError,client=null}){
  const[d,setD]=useState(null),[err,setErr]=useState('')
  const rpc=client||((fn,args)=>supabase.rpc(fn,args))
  const load=async()=>{try{const{data,error}=await rpc('admin_firecrawl_acceptance_v1',{});if(error)throw error;setD(data&&data.vendor?data:null);setErr('')}catch(e){setErr(plainError(e));onError?.(plainError(e))}}
  useEffect(()=>{load();const t=setInterval(()=>{if(document.visibilityState==='visible')load()},120000);return()=>clearInterval(t)},[])
  const a=d?.allowance||{},v=d?.vendor||{},f=d?.floor||{},s=d?.sync||{},day=d?.daily||{},u=d?.usage||{}
  const days=[...new Set((day.days||[]).map(x=>x.day))].sort().reverse()
  const groups=day.groups||[]
  const meta=d?<><span className={`cf-chip tone-${v.remaining_credits==null?'neutral':v.fresh?'success':'warning'}`} data-fc-acc-meta>{v.remaining_credits==null?'Remaining unknown':`${num(v.remaining_credits)} credits left`}{v.age_minutes!=null?`, read ${ago(v.age_minutes)}`:''}</span></>:null
  if(!d&&!err)return <Card id="services.toolset.firecrawl.acceptance" title="Firecrawl allowance and spend" data-fc-acceptance><Loading label="Reading the Firecrawl plan…"/></Card>
  if(!d)return err?<Card id="services.toolset.firecrawl.acceptance" title="Firecrawl allowance and spend" data-fc-acceptance><p role="alert" className="lf-error">Could not be read: {err}</p></Card>:null
  return <Card id="services.toolset.firecrawl.acceptance" title="Firecrawl allowance and spend" data-fc-acceptance meta={meta}
    subtitle="The plan, the live balance, the reserved floor and each day's spend against the daily shares. Credits are counted by the platform; they are not money, and the vendor bill is not shown here."
    action={<Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>}>
    <div className="lf" data-fc-acc>
      <div className="lf-three" data-fc-acc-tiles>
        <div data-fc-tile="allowance"><small>Allowance (plan)</small><strong>{num(a.plan_credits)} credits</strong><small>{a.plan_tier?`${a.plan_tier.replaceAll('_',' ')} · `:''}limit held by the platform {num(a.monthly_limit_credits)}; stop at {num(a.stop_at_remaining_credits)} left</small><small>Period {a.period_start?fmtDateTime(a.period_start):'unknown'} to {a.period_end?fmtDateTime(a.period_end):'unknown'}</small></div>
        <div data-fc-tile="remaining"><small>Live remaining (vendor reading)</small><strong>{num(v.remaining_credits)} credits</strong><small>Read {v.read_at?`${fmtDateTime(v.read_at)} (${ago(v.age_minutes)})`:'never'}</small><small>{v.fresh?`Estimated now ${num(v.estimated_now_credits)} after ${num(v.used_since_reading_credits)} used since the reading`:'The reading is too old to estimate from; the platform falls back to its own count'}</small>
          {v.above_plan&&<small className="lf-error">The vendor reports more credits left than the plan allowance (carry-over, a top-up or a plan not yet updated here). It is shown as read, not adjusted.</small>}</div>
        <div data-fc-tile="sync"><small>Last sync</small><strong>{s.last_start?fmtDateTime(s.last_start):'unknown'}</strong><small>Job {s.job} {s.scheduled===false?'is not scheduled':s.active?'is on':'is paused'}{s.schedule?`, ${cronText(s.schedule)}`:''}</small><small>{s.last_status?<>Last result <StatusChip value={s.last_status}/>{s.next_run?`, next ${fmtDateTime(s.next_run)}`:''}</>:'No run in the scheduler history'}</small></div>
      </div>
      <h4 className="sl-h4">Reserved floor</h4>
      <p className="sl-sub" data-fc-floor>{f.switched_off?'The floor is switched off (setting is 0).':<>Course page search may not spend the last <strong>{num(f.credits)}</strong> credits of the plan; those stay for entry requirements, English, scholarships and other work. {f.applies?<>Room above the floor for course page search now: <strong>{num(f.room_credits)}</strong> credits{f.under_floor?' (the balance is already under the floor, so course page search is stopped)':''}.</>:'No fresh vendor reading, so the floor cannot be applied and course page search is not held back by it.'}</>} Setting: <code>{f.setting}</code> (Platform Admin changes it in the card above, with a reason).</p>
      <h4 className="sl-h4">Daily spend against the shares</h4>
      <p className="sl-sub">Day total {num(day.total_credits)} credits; used today by the automatic lanes {num(day.used_today)}; the daily budget is {day.budget_on?'kept':'not enforced (observe only)'}. On-demand Run now credits have their own allowance and are left out of the days below.</p>
      <div className="cf-table-wrap lf-frame"><table className="cf-table lf-set-table" data-fc-days><thead><tr><th>Group</th><th className="num">Share a day</th><th className="num">Used today</th><th className="num">Left today</th><th className="num">Refused today</th>{days.map(x=><th key={x} className="num">{x}</th>)}</tr></thead>
        <tbody>{groups.map(g=><tr key={g.group} data-fc-group={g.group}><td data-label="Group">{GROUP[g.group]||g.label||g.group}</td><td className="num" data-label="Share a day">{num(g.share)}</td><td className="num" data-label="Used today">{num(g.used)}</td>
          <td className="num" data-label="Left today">{num(g.left)}</td><td className="num" data-label="Refused today">{num(g.refused)}</td>
          {days.map(x=>{const c=(day.days||[]).find(r=>r.day===x&&r.group===g.group);return <td key={x} className="num" data-label={x}>{c?num(c.credits):'0'}</td>})}</tr>)}</tbody></table></div>
      <h4 className="sl-h4">Use by lane group and purpose (last {fmtNumber(u.window_hours||24)} hours)</h4>
      <div className="cf-table-wrap lf-frame"><table className="cf-table lf-set-table" data-fc-usage><thead><tr><th>Group</th><th className="num">Credits in the window</th><th className="num">On demand</th><th className="num">This billing period</th></tr></thead>
        <tbody>{(u.by_group||[]).map(g=><tr key={g.group} data-fc-usage-group={g.group}><td data-label="Group">{GROUP[g.group]||g.group}</td><td className="num" data-label="Credits in the window">{num(g.credits_window??0)}</td><td className="num" data-label="On demand">{num(g.on_demand_window??0)}</td><td className="num" data-label="This billing period">{g.credits_period==null?'unknown':num(g.credits_period)}</td></tr>)}</tbody></table></div>
      <div className="cf-table-wrap lf-frame"><table className="cf-table lf-set-table" data-fc-purposes><thead><tr><th>Purpose</th><th>Group</th><th className="num">Credits</th><th className="num">Calls</th><th>Last use</th></tr></thead>
        <tbody>{(u.by_purpose||[]).map(p=><tr key={p.purpose}><td data-label="Purpose"><code>{p.purpose}</code></td><td data-label="Group">{GROUP[p.group]||p.group}</td><td className="num" data-label="Credits">{num(p.credits_window)}</td><td className="num" data-label="Calls">{num(p.calls_window)}</td><td data-label="Last use">{p.last_at?fmtDateTime(p.last_at):'—'}</td></tr>)}
          {(u.by_purpose||[]).length===0&&<tr><td colSpan={5} className="cf-empty-cell">No Firecrawl use in the window.</td></tr>}</tbody></table></div>
      <p className="sl-sub">Groups are shared by every lane that reads with them (Reading pages serves entry requirements, fees, descriptions and course pages). Each lane's own card on Layer 2/3 &rsaquo; Operations shows the credits of its group.</p>
    </div>
  </Card>
}
