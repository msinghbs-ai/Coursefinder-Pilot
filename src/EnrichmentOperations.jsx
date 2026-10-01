// Layer 2 outcome reporting (CF-245), compact style from v2.15.128.
//   view="overview"  tiles, coverage and backlog, where work stops, fetcher yield, hourly summary (8 columns, the
//                    detail per hour is in the row tooltip), backlog blockers and recent field admissions.
//   view="trace"     recent execution trace (History tab).
// Read: adminRead('enrichment_operations', {country_code, hours, limit}); observational only, nothing is changed here.
import React,{useEffect,useState}from'react'
import{Button,Empty,Metric as Card,SectionTitle}from'./ui-kit'
import{Activity,AlertTriangle,BarChart3,BookOpen,CheckCircle2,DollarSign,ListTree,RefreshCw,Workflow}from'lucide-react'
import{adminRead}from'./lib/supabase'
import'./enrichment-operations.css'
import{fmtNumber,fmtDateTime,fmtMoney,fmtPercent}from'./lib/format.js'

const n=v=>fmtNumber(v||0)
const ms=v=>v==null?'—':`${fmtNumber(Math.round(Number(v)))} ms`
const money=v=>v==null?'—':fmtMoney(v,'USD',{decimals:2})
const when=v=>v?fmtDateTime(v):'—'
const REASON={layer3_required:'Passed to Layer 3 (AI)',source_profile_qualification_required:'Site not checked yet',no_official_course_url:'No course page link yet',layer4_required:'Sent to a person',fetch_failed:'Page could not be fetched'}
const human=v=>REASON[v]||String(v??'—').replace(/[_-]+/g,' ').replace(/^\w/,m=>m.toUpperCase())
const fieldLabel=v=>({official_course_url:'Course page link',intake_availability:'Intakes',english_requirements:'English requirements',provider_current_international_tuition:'Tuition',scholarship:'Scholarships'}[v]||human(v))
const found=x=>Number(x.official_urls_found||0)+Number(x.intakes_found||0)+Number(x.english_requirements_found||0)+Number(x.provider_current_tuition_found||0)+Number(x.scholarships_found||0)
const hourTip=x=>`Course page links ${n(x.official_urls_found)} · intakes ${n(x.intakes_found)} · English ${n(x.english_requirements_found)} · tuition ${n(x.provider_current_tuition_found)} · scholarships ${n(x.scholarships_found)}\nUnchanged ${n(x.unchanged)} · rejected or blocked ${n(x.rejected_or_blocked)} · to Layer 4 ${n(x.layer4_referred)} · courses improved ${n(x.courses_improved_lower_bound)}\nRetries ${n(x.retries)} · 429 ${n(x.http_429)} · 5xx ${n(x.http_5xx)} · other failures ${n(x.other_runtime_failures)}\nResponse ${ms(x.p50_response_ms)} / ${ms(x.p95_response_ms)} · reading ${ms(x.p50_extraction_ms)} / ${ms(x.p95_extraction_ms)} (median / slowest 5%)`

export default function EnrichmentOperations({rank=4,view='overview',openNav=()=>{},openEvidence=()=>{}}){
 const[data,setData]=useState(null),[country,setCountry]=useState(''),[hours,setHours]=useState(24),[busy,setBusy]=useState(false),[error,setError]=useState('')
 const load=async()=>{setBusy(true);setError('');try{setData(await adminRead('enrichment_operations',{country_code:country||null,hours,limit:30}))}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 useEffect(()=>{if(rank>=4)load()},[rank,country,hours])
 const coverage=data?.coverage||[],work=data?.work||{},hourly=data?.hourly||[],blockers=data?.blockers||[],providers=data?.providers||[],reasons=data?.stop_reasons||[],admissions=data?.admissions||[],recent=data?.recent_items||[]
 if(rank<4)return null
 const filters=<div className="eops-filters"><select aria-label="Country" value={country} onChange={e=>setCountry(e.target.value)}><option value="">AU + NZ</option><option value="AU">Australia</option><option value="NZ">New Zealand</option></select><select aria-label="Window" value={hours} onChange={e=>setHours(Number(e.target.value))}><option value="24">Last 24 hours</option><option value="48">Last 48 hours</option><option value="168">Last 7 days</option></select><Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Refreshing…':'Refresh'}</Button></div>
 if(view==='trace')return <section className="m-panel" data-cf245-enrichment-trace="true">
  <SectionTitle icon={ListTree} title="Recent execution trace" subtitle="The latest courses Layer 2 worked on and where each one stopped." action={filters}/>
  {error&&<p className="fr-error" role="alert">{error}</p>}
  {recent.length?<div className="cf-table-wrap"><table className="cf-table eops-trace"><thead><tr><th>When</th><th>Provider / course</th><th>Result</th><th className="num">Facts</th><th className="num">Evidence</th><th>Stopped because</th><th></th></tr></thead><tbody>{recent.slice(0,20).map((x,i)=><tr key={x.run_item_id||i}><td>{when(x.event_at)}</td><td>{x.provider_name||'—'}<small className="eops-block">{x.course_code||x.course_id||'—'}</small></td><td>{human(x.status)}</td><td className="num">{n(x.fields_resolved)} of {n(x.fields_targeted)}</td><td className="num">{n(x.evidence_count)}</td><td>{x.stop_reason?human(x.stop_reason):'—'}</td><td>{x.evidence_id&&<Button compact onClick={()=>openEvidence(x.evidence_id)}>Evidence</Button>}</td></tr>)}</tbody></table></div>:<Empty text={busy?'Loading…':'No Layer 2 activity in this window.'}/>}
 </section>
 return <div className="m-page-stack eops-root" data-cf245-enrichment-operations="true">
  {error&&<p className="fr-error" role="alert">{error}</p>}
  <div className="cf-metric-grid">
   <Card icon={Workflow} label="Waiting / working" value={`${n(work.queued)} / ${n(work.processing)}`} detail="Courses in the current runs"/>
   <Card icon={Activity} label="Pages fetched" value={n(work.fetched)} detail={`${n(work.fetch_failures)} failed · ${n(work.http_429_24h)} rate-limited · ${n(work.http_5xx_24h)} site errors`} tone={Number(work.fetch_failures||0)>Number(work.fetched||0)/5?'warning':'neutral'}/>
   <Card icon={CheckCircle2} label="Facts accepted" value={n(work.admitted_source_records_24h)} detail={`${n(work.evidence_24h)} pages saved as evidence · ${n(work.layer3_24h)} passed to Layer 3`} tone="success"/>
   <Card icon={DollarSign} label="Fetcher cost" value={money(work.vendor_cost_usd_24h)} detail={`${n(work.vendor_units_24h)} paid units`}/>
  </div>
  <section className="m-panel">
   <SectionTitle icon={BarChart3} title="Coverage and what is left" subtitle="Courses that show each fact on Search and the website, from the latest hourly count." action={filters}/>
   {coverage.length?<div className="cf-table-wrap"><table className="cf-table eops-cov"><thead><tr><th>Country</th><th>Fact</th><th className="num">Have</th><th className="num">Coverage</th><th className="num">Added today</th><th className="num">Still missing</th><th className="num">Ready to fetch</th><th className="num">Blocked</th></tr></thead><tbody>{coverage.map(x=><tr key={`${x.country_code}-${x.field_key}`}><td>{x.country_code}</td><td><strong>{fieldLabel(x.field_key)}</strong></td><td className="num">{n(x.current)} of {n(x.total)}</td><td className="num">{fmtPercent(x.coverage_pct||0)}</td><td className="num">{x.added_day==null?<span className="eops-muted" title="Shown once a day-old count exists">—</span>:signed(x.added_day)}</td><td className="num">{n(x.remaining)}</td><td className="num">{n(x.queueable)}</td><td className="num" title={`${n(x.awaiting_qualification)} waiting for the site to be checked`}>{n(x.blocked)}</td></tr>)}</tbody></table></div>:<Empty text={busy?'Loading…':'No coverage count is available yet.'}/>}
  </section>
  <div className="eops-two">
   <section className="m-panel"><SectionTitle icon={AlertTriangle} title="Where work stops" subtitle="Why courses stopped in the last 7 days."/>{reasons.length?<Bars rows={reasons.map(x=>({label:human(x.reason),value:x.items,detail:`${n(x.fields_resolved)} of ${n(x.fields_targeted)} facts found`}))}/>:<Empty text="Nothing stopped."/>}</section>
   <section className="m-panel"><SectionTitle icon={Activity} title="Fetchers" subtitle="Last 7 days: pages fetched, failures and response time."/>{providers.length?<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Fetcher</th><th className="num">Fetched</th><th className="num">Failed</th><th className="num" title="Typical response time, then the slowest 5%">Response time</th></tr></thead><tbody>{providers.map(x=><tr key={x.provider}><td>{human(x.provider)}</td><td className="num">{n(x.succeeded)}</td><td className="num" title={`${n(x.retries)} retries`}>{n(x.failed)}</td><td className="num">{ms(x.p50_ms)}<small className="eops-block">slowest {ms(x.p95_ms)}</small></td></tr>)}</tbody></table></div>:<Empty text="No fetches in the last 7 days."/>}</section>
  </div>
  <section className="m-panel">
   <SectionTitle icon={BarChart3} title="By hour" subtitle="Pages fetched and facts found each hour. Hover a row for the full breakdown."/>
   {hourly.length?<div className="cf-table-wrap"><table className="cf-table eops-hourly"><thead><tr><th>Hour</th><th>Country</th><th className="num">Courses</th><th className="num">Pages fetched</th><th className="num">Failed</th><th className="num">Facts found</th><th className="num">Accepted</th><th className="num">To Layer 3</th><th className="num">Cost</th></tr></thead><tbody>{hourly.slice(-24).reverse().map((x,i)=><tr key={`${x.hour_utc}-${x.country_code}-${x.domain}-${i}`} title={hourTip(x)}><td>{when(x.hour_utc)}</td><td>{x.country_code||'—'}</td><td className="num">{n(x.items)}</td><td className="num">{n(x.fetched)}</td><td className="num">{n(x.fetch_failures)}</td><td className="num">{n(found(x))}</td><td className="num">{n(x.facts_admitted_lower_bound)}</td><td className="num">{n(x.layer3_escalated)}</td><td className="num">{money(x.vendor_cost_usd)}</td></tr>)}</tbody></table></div>:<Empty text={busy?'Loading…':'No Layer 2 activity in this window.'}/>}
  </section>
  <div className="eops-two">
   <section className="m-panel"><SectionTitle icon={AlertTriangle} title="Not ready to fetch" subtitle="Missing facts that cannot be fetched yet, and why."/>{blockers.length?<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Fact</th><th>Why</th><th className="num">Courses</th></tr></thead><tbody>{blockers.slice(0,12).map((x,i)=><tr key={`${x.country_code}-${x.field_key}-${x.reason}-${i}`}><td>{x.country_code} · {fieldLabel(x.field_key)}</td><td>{human(x.reason||x.state)}</td><td className="num">{n(x.courses)}</td></tr>)}</tbody></table></div>:<Empty text="Nothing blocked."/>}</section>
   <section className="m-panel"><SectionTitle icon={BookOpen} title="Recently accepted facts" subtitle="Facts Layer 2 accepted; publishing is a separate step."/>{admissions.length?<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Course</th><th>Fact</th><th></th></tr></thead><tbody>{admissions.slice(0,12).map(x=><tr key={x.id}><td>{x.course_title||x.course_id}<small className="eops-block">{x.provider_name||''}</small></td><td>{fieldLabel(x.field_key)}<small className="eops-block">{human(x.status)}</small></td><td>{x.evidence_id&&<Button compact onClick={()=>openEvidence(x.evidence_id)}>Evidence</Button>}</td></tr>)}</tbody></table></div>:<Empty text="Nothing accepted in this window."/>}</section>
  </div>
 </div>
}

function signed(v){const x=Number(v||0);return <span className={x>0?'eops-positive':''}>{x>0?'+':''}{n(x)}</span>}
function Bars({rows}){const max=Math.max(1,...rows.map(x=>Number(x.value||0)));return <div className="eops-bars">{rows.slice(0,10).map((x,i)=><div key={`${x.label}-${i}`}><span><strong>{x.label}</strong><small>{x.detail}</small></span><i><b style={{width:`${Math.max(3,100*Number(x.value||0)/max)}%`}}/></i><em>{n(x.value)}</em></div>)}</div>}
