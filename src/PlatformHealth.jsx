// Platform health (v2.15.107): the result of the automatic health checks, in plain language.
// Server contract: admin_read('platform_health', {}) returns
//   {generated_at, overall:'ok'|'warning'|'critical', counts:{critical,warning,info},
//    issues:[{id,check_key,severity,area,title,detail,first_seen,last_seen,occurrences,acknowledged_at}],
//    checks:[{key,area,label,status:'ok'|'warning'|'critical'|'skipped',detail,checked_at}],
//    history:[{day,critical,warning}]}
// `detail` may be text or an object; both are shown. Older deployments return a different shape
// (or an error): the screen then says the checks are not available yet.
import React,{useEffect,useMemo,useState}from'react'
import{AlertTriangle,CheckCircle2,Info,RefreshCw,ShieldAlert}from'lucide-react'
import{adminRead}from'./lib/supabase'
import{Button,Empty,Loading,Metric,SectionTitle,StatusChip,StatusDot,fmtDate,fmtDateTime,fmtDayMonth,fmtNumber}from'./ui-kit'

export function isHealthContract(h){return Boolean(h&&typeof h.overall==='string'&&Array.isArray(h.checks))}
export function healthTone(overall){return overall==='ok'?'ok':overall==='warning'?'warning':overall==='critical'?'critical':'unknown'}
export const HEALTH_WORDS={ok:'All checks passing',warning:'Needs attention',critical:'Something is broken',unknown:'Health checks not available yet'}
const SEVERITY_ORDER={critical:0,warning:1,info:2}
const SEVERITY_TONE={critical:'danger',warning:'warning',info:'info'}
const CHECK_TONE={ok:'success',warning:'warning',critical:'danger',skipped:'neutral'}

/** Shared read used by the page and the top-bar dot. Resolves to null when the checks are not deployed. */
export async function readPlatformHealth(){try{const h=await adminRead('platform_health',{});return isHealthContract(h)?h:null}catch{return null}}

function human(v){return String(v??'').replaceAll('_',' ').replace(/^\w/,c=>c.toUpperCase())}
function scalar(k,v){if(v==null||v==='')return'—';if(typeof v==='number')return fmtNumber(v);if(typeof v==='boolean')return v?'yes':'no';if(/(_at|since|_end)$/.test(k)&&!Number.isNaN(Date.parse(v)))return fmtDateTime(v);return String(v)}
/** Detail text or object → short readable lines. Nested objects are summarised one level deep. */
// v2.15.131 (hc-details-text, hc-actions): plain names for detail keys, and where to go to fix each check.
const KEY_LABEL={layer3_stuck_over_1h:'Layer 3 items stuck over 1 hour',stuck_over_2h:'Stuck over 2 hours',openrouter_daily_ceiling_usd:'OpenRouter daily limit (US$)',openrouter_spend_24h_usd:'OpenRouter spend, last 24 h (US$)',
  scholarship_firecrawl_cap:'Scholarship Firecrawl allowance',scholarship_firecrawl_used:'Scholarship Firecrawl used',jobs_overdue:'Jobs overdue',jobs_failing:'Jobs failing',active_jobs:'Active jobs',created_24h:'New in 24 h',decided_24h:'Decided in 24 h',
  invoked_last_24h:'Called in 24 h',window_minutes:'Window (minutes)',by_function:'By function',db_size:'Database size',max_connections:'Connection limit',active_connections:'Active connections',compute_size:'Compute size',ms:'Response (ms)',run_ms:'Run time (ms)',slowest_probe_ms:'Slowest probe (ms)'}
const keyLabel=k=>KEY_LABEL[k]||human(k)
export const FIX_AT={cron:['#scheduled-jobs?tab=automations','Automations'],edge_calls:['#scheduled-jobs?tab=jobs','Jobs'],coverage_queues:['#coverage','Coverage & completeness'],admission:['#coverage','Coverage & completeness'],
  scholarship_queues:['#scholarships?tab=publishing','Scholarship publishing'],scholarship_review:['#scholarships?tab=publishing','Scholarship publishing'],layer_queues:['#layer-4-review','Layer 4 Review'],budgets:['#layer-3-ai','Layer 3 Control'],db_capacity:['#platform-health?tab=readiness','Capacity']}
export function DetailText({value}){
  if(value==null||value==='')return null
  if(typeof value!=='object')return <span className="ph-detail">{String(value)}</span>
  const entries=Object.entries(value).filter(([,v])=>v!=null&&v!=='')
  if(!entries.length)return null
  return <span className="ph-detail">{entries.slice(0,6).map(([k,v])=><span key={k}><b>{keyLabel(k)}:</b> {Array.isArray(v)?(v.length&&typeof v[0]!=='object'?v.join(', '):`${fmtNumber(v.length)} item${v.length===1?'':'s'}`):typeof v==='object'?Object.entries(v).slice(0,4).map(([a,b])=>`${keyLabel(a)} ${scalar(a,b)}`).join(' · '):scalar(k,v)}</span>)}</span>
}

export default function PlatformHealth({onError}){
  const[data,setData]=useState(null),[state,setState]=useState('loading')
  const load=()=>{setState('loading');adminRead('platform_health',{}).then(h=>{if(isHealthContract(h)){setData(h);setState('ready')}else{setData(null);setState('missing')}}).catch(()=>{setData(null);setState('missing')})}
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
      <div className="ph-overall-head"><StatusDot tone={tone} label={HEALTH_WORDS[tone]}/><div><h2>{HEALTH_WORDS[tone]}</h2><p>Checked {fmtDateTime(data.generated_at)} · {fmtNumber(checks.length)} checks</p></div><Button compact onClick={load} disabled={state==='loading'}><RefreshCw size={14}/>Check again</Button></div>
      <div className="cf-metric-grid">
        <Metric label="Critical" value={Number(counts.critical||0)} icon={ShieldAlert} tone={counts.critical?'danger':'neutral'} detail="Broken now; fix first"/>
        <Metric label="Warning" value={Number(counts.warning||0)} icon={AlertTriangle} tone={counts.warning?'warning':'neutral'} detail="Needs attention soon"/>
        <Metric label="For information" value={Number(counts.info||0)} icon={Info} tone={counts.info?'info':'neutral'} detail="Worth knowing, no action needed"/>
      </div>
    </section>
    <section className="m-panel">
      <SectionTitle icon={AlertTriangle} title="Open issues" subtitle="Grouped by area, newest first. An issue closes by itself when its check passes again."/>
      {areas.length?<div className="ph-areas">{areas.map(([area,items])=><div className="ph-area" key={area}><h3>{human(area)} <span>{fmtNumber(items.length)}</span></h3>
        <ul>{items.map(i=><li key={i.id||i.check_key+i.title}><StatusChip value={i.severity} tone={SEVERITY_TONE[i.severity]||'neutral'} label={human(i.severity)}/><div><strong>{i.title}</strong>{FIX_AT[i.check_key]&&<a className="ph-fix" href={FIX_AT[i.check_key][0]}>Go to {FIX_AT[i.check_key][1]}</a>}<DetailText value={i.detail}/><small>First seen {fmtDateTime(i.first_seen)} · last seen {fmtDateTime(i.last_seen)}{Number(i.occurrences||0)>1?` · seen ${fmtNumber(i.occurrences)} times`:''}{i.acknowledged_at?` · acknowledged ${fmtDateTime(i.acknowledged_at)}`:''}</small></div></li>)}</ul></div>)}</div>
      :<Empty icon={CheckCircle2} text="No open issues."/>}
    </section>
    <section className="m-panel">
      <SectionTitle icon={CheckCircle2} title="Checks" subtitle="Every automatic check and its latest result. Skipped means the check could not run here, not that it failed."/>
      <div className="cf-table-wrap"><table className="cf-table ph-checks"><thead><tr><th>Check</th><th>Area</th><th>Result</th><th>Details</th><th>Checked</th></tr></thead><tbody>
        {checks.map(c=><tr key={c.key}><td><strong>{c.label||human(c.key)}</strong></td><td>{human(c.area)}</td><td><StatusChip value={c.status} tone={CHECK_TONE[c.status]||'neutral'} label={c.status==='ok'?'OK':human(c.status)}/></td><td><DetailText value={c.detail}/>{c.status!=='ok'&&FIX_AT[c.key]&&<a className="ph-fix" href={FIX_AT[c.key][0]}>Go to {FIX_AT[c.key][1]}</a>}</td><td>{fmtDateTime(c.checked_at)}</td></tr>)}
      </tbody></table></div>
    </section>
    <HealthHistory history={data.history||[]}/>
  </>
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
    <div className="cf-table-wrap ph-history-table"><table className="cf-table"><thead><tr><th>Day</th><th className="num">Warning</th><th className="num">Critical</th></tr></thead><tbody>{[...days].reverse().filter(d=>d.warning||d.critical).map(d=><tr key={d.day}><td>{fmtDate(d.day)}</td><td className="num">{fmtNumber(d.warning||0)}</td><td className="num">{fmtNumber(d.critical||0)}</td></tr>)}{!days.some(d=>d.warning||d.critical)&&<tr><td colSpan={3} className="cf-empty-cell">No warnings or critical issues in the last 14 days.</td></tr>}</tbody></table></div>
  </section>
}
