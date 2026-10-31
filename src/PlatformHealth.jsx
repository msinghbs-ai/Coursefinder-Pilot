// Platform health (v2.15.107): the result of the automatic health checks, in plain language.
// Server contract: admin_read('platform_health', {}) returns
//   {generated_at, overall:'ok'|'warning'|'critical', counts:{critical,warning,info},
//    issues:[{id,check_key,severity,area,title,detail,first_seen,last_seen,occurrences,acknowledged_at}],
//    checks:[{key,area,label,status:'ok'|'warning'|'critical'|'skipped',detail,checked_at}],
//    history:[{day,critical,warning}]}
// `detail` may be text or an object; both are shown. Older deployments return a different shape
// (or an error): the screen then says the checks are not available yet.
import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,BellRing,CheckCircle2,Gauge,Info,RefreshCw,ShieldAlert}from'lucide-react'
import{adminRead,supabase}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,StatusDot,fmtDate,fmtDateTime,fmtDayMonth,fmtNumber}from'./ui-kit'
import{scrubInternals}from'./lib/errors'
import{PAGES,resolveTarget}from'./nav-map'
import{describeSchedule}from'./automation-schedule'

// UI audit Phase 1 (24 Oct 2026): an internal address ("#layer-2-discovery?tab=operations") is never printed as text — it becomes
// a link named after the screen; a cron expression ("*/10 * * * *") reads as plain schedule words.
const ROUTE_RE=/^#[a-z0-9][a-z0-9-]*(\?[^\s]*)?$/i
const CRON_RE=/^(\S+\s+){4}\S+$/
export function isRouteFragment(v){return typeof v==='string'&&ROUTE_RE.test(v.trim())}
export function screenName(href){try{const raw=String(href||'').trim().replace(/^#/,''),[slug,qs='']=raw.split('?'),r=resolveTarget(slug,new URLSearchParams(qs)),page=PAGES[r?.page],tab=page?.tabs?.find(t=>t.key===r?.tab);return page?`${page.label}${tab&&tab.key!==page.tabs?.[0]?.key?` › ${tab.label}`:''}`:'the screen'}catch{return'the screen'}}
export function ScreenLink({href,prefix='Go to '}){return <a className="ph-fix" href={href} data-screen-link>{prefix}{screenName(href)}</a>}
const looksCron=v=>typeof v==='string'&&CRON_RE.test(v.trim())&&/[*\/]/.test(v)

export function isHealthContract(h){return Boolean(h&&typeof h.overall==='string'&&Array.isArray(h.checks))}
export function healthTone(overall){return overall==='ok'?'ok':overall==='warning'?'warning':overall==='critical'?'critical':'unknown'}
export const HEALTH_WORDS={ok:'All checks passing',warning:'Needs attention',critical:'Something is broken',unknown:'Health checks not available yet'}
// The page heading says what to do next, so it does not repeat the health dot's sentence (UI audit Phase 1)
const PAGE_WORDS={ok:'Every check passed',warning:'Some checks need attention',critical:'Fix the critical checks first',unknown:'The checks have not run yet'}
const SEVERITY_ORDER={critical:0,warning:1,info:2}
const SEVERITY_TONE={critical:'danger',warning:'warning',info:'info'}
const CHECK_TONE={ok:'success',warning:'warning',critical:'danger',skipped:'neutral'}

/** Shared read used by the page and the top-bar dot. Resolves to null when the checks are not deployed. */
export async function readPlatformHealth(){try{const h=await adminRead('platform_health',{});return isHealthContract(h)?h:null}catch{return null}}

function human(v){return String(v??'').replaceAll('_',' ').replace(/^\w/,c=>c.toUpperCase())}
function scalar(k,v){if(v==null||v==='')return'—';if(typeof v==='number')return fmtNumber(v);if(typeof v==='boolean')return v?'yes':'no';if(/(_at|since|_end)$/.test(k)&&!Number.isNaN(Date.parse(v)))return fmtDateTime(v);if(typeof v==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d/.test(v)&&!Number.isNaN(Date.parse(v)))return fmtDateTime(v);if(isRouteFragment(v))return screenName(v);if(looksCron(v))return describeSchedule(v).text;return scrubInternals(String(v))} // v2.15.341: raw ISO stamps become dates, raw errors become plain words
/** Detail text or object → short readable lines. Nested objects are summarised one level deep. */
// v2.15.131 (hc-details-text, hc-actions): plain names for detail keys, and where to go to fix each check.
const KEY_LABEL={layer3_stuck_over_1h:'Layer 3 items stuck over 1 hour',stuck_over_2h:'Stuck over 2 hours',openrouter_daily_ceiling_usd:'OpenRouter daily limit (US$)',openrouter_spend_24h_usd:'OpenRouter spend, last 24 h (US$)',
  scholarship_firecrawl_cap:'Scholarship Firecrawl allowance',scholarship_firecrawl_used:'Scholarship Firecrawl used',jobs_overdue:'Jobs overdue',jobs_failing:'Jobs failing',active_jobs:'Active jobs',created_24h:'New in 24 h',decided_24h:'Decided in 24 h',
  invoked_last_24h:'Called in 24 h',window_minutes:'Window (minutes)',by_function:'By function',db_size:'Database size',max_connections:'Connection limit',active_connections:'Active connections',compute_size:'Compute size',ms:'Response (ms)',run_ms:'Run time (ms)',slowest_probe_ms:'Slowest probe (ms)',
  oldest_minutes:'Oldest waiting (minutes)',last_processed_at:'Last processed',next_step:'Next step',cause:'Cause',held_24h:'Held in 24 h (delivery off)',failed_24h:'Failed in 24 h',last_sent_at:'Last delivered',delivery:'External delivery',waiting:'Waiting'}
const keyLabel=k=>KEY_LABEL[k]||human(k)
export const FIX_AT={search_refresh:['#scheduled-jobs?tab=automations','Automations'],alerts:['#environment','Pipeline settings › Alerts'],field_stalled:['#coverage?tab=attributes','Coverage › Attributes › Stalled fields'],cron:['#scheduled-jobs?tab=automations','Automations'],edge_calls:['#scheduled-jobs?tab=jobs','Jobs'],coverage_queues:['#coverage','Coverage & completeness'],admission:['#coverage','Coverage & completeness'],
  scholarship_queues:['#scholarships?tab=coverage','Scholarships › Coverage'],scholarship_review:['#scholarships?tab=coverage','Scholarships › Coverage'] /* v2.15.253: Layer 4 Scholarship publishing retired */,layer_queues:['#layer-4-review','Layer 4 Review'],budgets:['#models-services','Models & services'] /* v2.15.252: Layer 3 Control retired */,db_capacity:['#platform-health?tab=readiness','Capacity'],queue_watch:['#platform-health?tab=queues','Platform health › Work queues']}
export function DetailText({value}){
  if(value==null||value==='')return null
  if(isRouteFragment(value))return <span className="ph-detail"><ScreenLink href={String(value).trim()}/></span>
  if(typeof value!=='object')return <span className="ph-detail">{scalar('',value)}</span>
  const entries=Object.entries(value).filter(([,v])=>v!=null&&v!=='')
  if(!entries.length)return null
  return <span className="ph-detail">{entries.slice(0,6).map(([k,v])=><span key={k}><b>{keyLabel(k)}:</b> {isRouteFragment(v)?<ScreenLink href={String(v).trim()} prefix=""/>:Array.isArray(v)?(v.length&&typeof v[0]!=='object'?v.join(', '):`${fmtNumber(v.length)} item${v.length===1?'':'s'}`):typeof v==='object'?Object.entries(v).slice(0,4).map(([a,b])=>`${keyLabel(a)} ${scalar(a,b)}`).join(' · '):scalar(k,v)}</span>)}</span>
}

export default function PlatformHealth({onError}){
  const[data,setData]=useState(null),[state,setState]=useState('loading'),[alerts,setAlerts]=useState(null)
  const loadAlerts=()=>readPlatformAlerts().then(setAlerts)
  const load=()=>{setState('loading');loadAlerts();adminRead('platform_health',{}).then(h=>{if(isHealthContract(h)){setData(h);setState('ready')}else{setData(null);setState('missing')}}).catch(()=>{setData(null);setState('missing')})}
  useEffect(load,[])
  const areas=useMemo(()=>{
    const m=new Map()
    for(const i of [...(data?.issues||[])].sort((a,b)=>(SEVERITY_ORDER[a.severity]??9)-(SEVERITY_ORDER[b.severity]??9)||String(b.last_seen||'').localeCompare(String(a.last_seen||'')))){const k=i.area||'Other';if(!m.has(k))m.set(k,[]);m.get(k).push(i)}
    return [...m.entries()].sort((a,b)=>String(b[1][0]?.last_seen||'').localeCompare(String(a[1][0]?.last_seen||'')))
  },[data])
  if(state==='loading'&&!data)return <section className="m-panel"><Loading label="Running the health checks…"/></section>
  if(state==='missing')return <section className="m-panel ph-missing"><SectionTitle icon={Info} title="Health checks not available yet" subtitle="The automatic health checks have not been switched on for this environment. Everything else keeps working; this page will fill in once they are."/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  const tone=healthTone(data.overall),counts=data.counts||{}
  const checks=[...(data.checks||[])].sort((a,b)=>({critical:0,warning:1,ok:2,skipped:3}[a.status]??9)-({critical:0,warning:1,ok:2,skipped:3}[b.status]??9)||String(a.area).localeCompare(String(b.area)))
  return <>
    <section className={`m-panel ph-overall tone-${tone}`}>
      <div className="ph-overall-head"><StatusDot tone={tone} label={HEALTH_WORDS[tone]}/><div><h2 data-health-heading>{PAGE_WORDS[tone]}</h2><p>Checked {fmtDateTime(data.generated_at)} · {fmtNumber(checks.length)} checks</p></div><Button compact onClick={load} disabled={state==='loading'}><RefreshCw size={14}/>Check again</Button></div>
      <div className="cf-metric-grid">
        <Metric label="Critical" value={Number(counts.critical||0)} icon={ShieldAlert} tone={counts.critical?'danger':'neutral'} detail="Broken now; fix first"/>
        <Metric label="Warning" value={Number(counts.warning||0)} icon={AlertTriangle} tone={counts.warning?'warning':'neutral'} detail="Needs attention soon"/>
        <Metric label="For information" value={Number(counts.info||0)} icon={Info} tone={counts.info?'info':'neutral'} detail="Worth knowing, no action needed"/>
      </div>
    </section>
    <section className="m-panel">
      <SectionTitle icon={AlertTriangle} title="Open issues" subtitle="Grouped by area, newest first. An issue closes by itself when its check passes again."/>
      {areas.length?<div className="ph-areas">{areas.map(([area,items])=><div className="ph-area" key={area}><h3>{human(area)} <span>{fmtNumber(items.length)}</span></h3>
        <ul>{items.map(i=><li key={i.id||i.check_key+i.title}><StatusChip value={i.severity} tone={SEVERITY_TONE[i.severity]||'neutral'} label={human(i.severity)}/><div><strong>{scrubInternals(i.title)}</strong>{(FIX_AT[i.check_key]||FIX_AT[String(i.check_key||'').split(':')[0]])&&<a className="ph-fix" href={(FIX_AT[i.check_key]||FIX_AT[String(i.check_key).split(':')[0]])[0]}>Go to {(FIX_AT[i.check_key]||FIX_AT[String(i.check_key).split(':')[0]])[1]}</a>}<DetailText value={i.detail}/><small>First seen {fmtDateTime(i.first_seen)} · last seen {fmtDateTime(i.last_seen)}{Number(i.occurrences||0)>1?` · seen ${fmtNumber(i.occurrences)} times`:''}{i.acknowledged_at?` · acknowledged ${fmtDateTime(i.acknowledged_at)}`:''}</small>{alerts?.can_change&&!i.acknowledged_at&&i.severity!=='info'&&<AcknowledgeIssue issue={i} onDone={load} onError={onError}/>}</div></li>)}</ul></div>)}</div>
      :<Empty icon={CheckCircle2} text="No open issues."/>}
    </section>
    <section className="m-panel">
      <SectionTitle icon={CheckCircle2} title="Checks" subtitle="Every automatic check and its latest result. Skipped means the check could not run here, not that it failed."/>
      <div className="cf-table-wrap"><table className="cf-table ph-checks"><thead><tr><th>Check</th><th>Area</th><th>Result</th><th>Details</th><th>Checked</th></tr></thead><tbody>
        {checks.map(c=><tr key={c.key}><td><strong>{c.label||human(c.key)}</strong></td><td>{human(c.area)}</td><td><StatusChip value={c.status} tone={CHECK_TONE[c.status]||'neutral'} label={c.status==='ok'?'OK':human(c.status)}/></td><td><DetailText value={c.detail}/>{c.status!=='ok'&&FIX_AT[c.key]&&<a className="ph-fix" href={FIX_AT[c.key][0]}>Go to {FIX_AT[c.key][1]}</a>}</td><td>{fmtDateTime(c.checked_at)}</td></tr>)}
      </tbody></table></div>
    </section>
    <AlertsPanel alerts={alerts} onChange={loadAlerts} onError={onError}/>
    <Scorecard alerts={alerts}/>
    <HealthHistory history={data.history||[]}/>
  </>
}

// SS-014C/D (31 Oct 2026): alerts (external delivery off until the Platform Admin approves a destination, decision D7), acknowledgement
// and the weekly operational scorecard against targets T1 to T8. Server: public.admin_platform_alerts(p_action, p_args).
export async function readPlatformAlerts(){try{const{data,error}=await supabase.rpc('admin_platform_alerts',{p_action:'read',p_args:{}});return !error&&data&&!Array.isArray(data)&&data.settings?data:null}catch{return null}}
async function alertAction(action,args){const{data,error}=await supabase.rpc('admin_platform_alerts',{p_action:action,p_args:args});if(error)throw new Error(error.message||'The change was refused');return data}

export function AcknowledgeIssue({issue,onDone,onError}){
  const[open,setOpen]=useState(false),[reason,setReason]=useState(''),[busy,setBusy]=useState(false)
  if(!open)return <button type="button" className="cf-link" data-ack-issue={issue.id} onClick={()=>setOpen(true)}>Acknowledge</button>
  const save=()=>{setBusy(true);alertAction('acknowledge',{id:issue.id,reason:reason.trim()}).then(()=>{setOpen(false);onDone?.()}).catch(e=>onError?.(e.message)).finally(()=>setBusy(false))}
  return <span className="ph-ack" data-ack-form={issue.id}><input aria-label="Reason for acknowledging" placeholder="Reason (kept in the log)" value={reason} onChange={e=>setReason(e.target.value)}/>
    <Button compact disabled={busy||reason.trim().length<4} onClick={save}>Acknowledge</Button><button type="button" className="cf-link" onClick={()=>setOpen(false)}>Cancel</button></span>
}

const ALERT_STATUS={held:['Held (delivery off)','neutral'],pending:['Waiting to be sent','warning'],sending:['Being sent','info'],sent:['Delivered','success'],failed:['Failed','danger']}
export function AlertsPanel({alerts,onChange,onError}){
  const[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[note,setNote]=useState('')
  if(!alerts)return null
  const st=alerts.settings||{},counts=alerts.counts||{}
  const delivery=st.delivery_enabled?(st.webhook_enabled?'On: by webhook':'On: by the alert scheduled task'):'Off: alerts are recorded here only, nothing leaves the platform until the Platform Admin approves a destination'
  const test=()=>{setBusy(true);alertAction('test',{reason:reason.trim()}).then(()=>{setReason('');setNote('Test alert recorded.');onChange?.()}).catch(e=>onError?.(e.message)).finally(()=>setBusy(false))}
  return <section className="m-panel" data-platform-alerts>
    <SectionTitle icon={BellRing} title="Alerts" subtitle={`Critical issues open for ${fmtNumber(Number(st.confirm_minutes||0))} minutes become alerts; the same check alerts at most once in ${fmtNumber(Number(st.cooldown_minutes||0))} minutes; an open, unacknowledged issue is reminded after ${fmtNumber(Number(st.reminder_hours||0))} hours; a recovery notice follows. Settings: Pipeline settings › Alerts.`}/>
    <p className="sd-desc" data-alert-delivery={st.delivery_enabled?'on':'off'}><strong>External delivery:</strong> {delivery}{st.test_mode?' · test mode on':''}</p>
    <p className="sd-desc">Last 7 days: {Object.keys(ALERT_STATUS).filter(k=>counts[k]).map(k=>`${ALERT_STATUS[k][0]} ${fmtNumber(Number(counts[k]))}`).join(' · ')||'no alerts'}</p>
    {(alerts.recent||[]).length?<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Raised</th><th>Alert</th><th>Status</th></tr></thead><tbody>
      {alerts.recent.map(a=><tr key={a.id} data-alert-row={a.status}><td>{fmtDateTime(a.created_at)}</td><td>{scrubInternals(a.title)}{a.last_error?<div className="ph-detail">{a.last_error}</div>:null}</td><td><StatusChip value={a.status} tone={(ALERT_STATUS[a.status]||[])[1]||'neutral'} label={(ALERT_STATUS[a.status]||[a.status])[0]}/></td></tr>)}
    </tbody></table></div>:<Empty icon={CheckCircle2} text="No alerts yet."/>}
    {alerts.can_change&&<div className="ph-ack" data-alert-test><input aria-label="Reason for the test alert" placeholder="Reason for a test alert" value={reason} onChange={e=>setReason(e.target.value)}/><Button compact disabled={busy||reason.trim().length<4} onClick={test}>Send a test alert</Button>{note&&<small role="status">{note}</small>}</div>}
  </section>
}

const T_LABEL={T1:'Scheduled job reliability',T2:'AI spend and credit',T3:'Firecrawl credits',T4:'Futile enrichment items',T5:'Layer 4 review backlog',T6:'Website and Zoho API',T7:'Data freshness',T8:'Releases'}
const T_TONE={met:'success','on track so far':'success',missed:'danger','not fully observed':'warning'}
function tValue(k,t){
  switch(k){
    case'T1':return `${fmtNumber(Number(t.failed||0))} failed of ${fmtNumber(Number(t.runs||0))} runs; worst day ${fmtNumber(Number(t.worst_day||0))}`
    case'T2':return `US$${t.spend_usd} spent; worst day US$${t.worst_day_usd}; credit US$${Number(t.credit_usd||0).toFixed(2)}`
    case'T3':return `${fmtNumber(Number(t.credits_week||0))} credits this week; month ${fmtNumber(Number(t.month_used||0))} of ${fmtNumber(Number(t.month_limit||0))}`
    case'T4':return `${fmtNumber(Number(t.items||0))} items; worst day ${fmtNumber(Number(t.worst_day||0))}`
    case'T5':return `${fmtNumber(Number(t.pending_now||0))} pending; oldest ${t.oldest_pending_days??'—'} days`
    case'T6':return `${fmtNumber(Number(t.requests||0))} requests, ${fmtNumber(Number(t.server_errors||0))} server errors, drift ${fmtNumber(Number(t.contract_drift_now||0))}; search p95 ${t.search_p95_ms==null?'—':fmtNumber(Number(t.search_p95_ms))+' ms'} (${fmtNumber(Number(t.search_requests_measured||0))} measured)`
    case'T7':return `${fmtNumber(Number(t.refresh_requests||0))} refresh requests; wait p95 ${t.wait_p95_min??'—'} min, max ${t.wait_max_min??'—'} min; ${fmtNumber(Number(t.over_target||0))} over target`
    case'T8':return `${fmtNumber(Number(t.migrations_dated_in_week||0))} migrations in the week`
    default:return''}
}
export function Scorecard({alerts}){
  const cards=alerts?.scorecards||[],[idx,setIdx]=useState(0)
  if(!cards.length)return null
  const sc=cards[Math.min(idx,cards.length-1)]||{},tg=sc.targets||{}
  return <section className="m-panel" data-ops-scorecard={sc.week_start}>
    <SectionTitle icon={Gauge} title="Weekly operational scorecard" subtitle="Targets T1 to T8 (Operational limits) from existing measurements, recorded every morning. Each line says whether it was observed for the whole week, so far, or only measured at report time."
      action={cards.length>1?<span className="ph-ack">{cards.map((c,i)=><Button compact key={c.week_start} variant={i===idx?'primary':undefined} onClick={()=>setIdx(i)}>{c.complete?`Week of ${fmtDate(c.week_start)}`:'This week so far'}</Button>)}</span>:null}/>
    <p className="sd-desc">Week {fmtDate(sc.week_start)} to {fmtDate(sc.week_end)}{sc.complete?'':' (in progress)'} · met {fmtNumber(Number(sc.met||0))}, missed {fmtNumber(Number(sc.missed||0))} · recorded {fmtDateTime(sc.generated_at)}</p>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Target</th><th>Measured</th><th>Result</th><th>Basis</th></tr></thead><tbody>
      {Object.keys(T_LABEL).filter(k=>tg[k]).map(k=><tr key={k} data-scorecard-target={k}><td><strong>{k} · {T_LABEL[k]}</strong><div className="ph-detail">{tg[k].target}</div></td><td>{tValue(k,tg[k])}</td><td><StatusChip value={tg[k].status} tone={T_TONE[tg[k].status]||'neutral'} label={human(tg[k].status)}/></td><td><small>{tg[k].basis}</small></td></tr>)}
    </tbody></table></div>
  </section>
}

function HealthHistory({history}){
  const days=history.slice(-14),max=Math.max(1,...days.map(d=>Number(d.critical||0)+Number(d.warning||0)))
  return <section className="m-panel">
    <SectionTitle title="Last 14 days" subtitle="Warnings and critical issues raised each day."/>
    <div className="ph-legend"><span><i className="ph-sw warning"/>Warning</span><span><i className="ph-sw critical"/>Critical</span></div>
    <div className="ph-history" role="img" aria-label={days.map(d=>`${fmtDate(d.day)}: ${d.warning||0} warning, ${d.critical||0} critical`).join('; ')}>
      {days.map(d=>{const w=Number(d.warning||0),c=Number(d.critical||0);return <div className="ph-day" key={d.day} title={`${fmtDate(d.day)}: ${w} warning, ${c} critical`}>
        <div className="ph-stack">{c>0&&<span className="critical" style={{height:`${c/max*100}%`}}/>}{w>0&&<span className="warning" style={{height:`${w/max*100}%`}}/>}</div>
        <small>{fmtDayMonth(d.day)}</small></div>})}
    </div>
    <details className="ph-history-details"><summary>Show as a table</summary><div className="cf-table-wrap ph-history-table"><table className="cf-table"><thead><tr><th>Day</th><th className="num">Warning</th><th className="num">Critical</th></tr></thead><tbody>{[...days].reverse().filter(d=>d.warning||d.critical).map(d=><tr key={d.day}><td>{fmtDate(d.day)}</td><td className="num">{fmtNumber(d.warning||0)}</td><td className="num">{fmtNumber(d.critical||0)}</td></tr>)}{!days.some(d=>d.warning||d.critical)&&<tr><td colSpan={3} className="cf-empty-cell">No warnings or critical issues in the last 14 days.</td></tr>}</tbody></table></div></details>
  </section>
}
