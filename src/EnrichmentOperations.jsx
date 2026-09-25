import React,{useEffect,useState}from'react'
import{Activity,AlertTriangle,BookOpen,CheckCircle2,Clock3,DollarSign,RefreshCw,ShieldCheck,Workflow}from'lucide-react'
import{adminRead}from'./lib/supabase'
import'./enrichment-operations.css'

const n=v=>Number(v||0).toLocaleString()
const ms=v=>v==null?'—':`${Math.round(Number(v)).toLocaleString()} ms`
const money=v=>v==null?'—':`$${Number(v).toFixed(4)}`
const when=v=>v?new Date(v).toLocaleString():'—'
const human=v=>String(v??'—').replace(/[_-]+/g,' ').replace(/\b\w/g,m=>m.toUpperCase())
const fieldLabel=v=>({official_course_url:'Official course URL',intake_availability:'Intake availability',english_requirements:'English requirements',provider_current_international_tuition:'Provider-current tuition',scholarship:'Scholarships'}[v]||human(v))

export default function EnrichmentOperations({rank=4,openNav=()=>{},openEvidence=()=>{}}){
 const[data,setData]=useState(null),[country,setCountry]=useState(''),[hours,setHours]=useState(24),[busy,setBusy]=useState(false),[error,setError]=useState('')
 const load=async()=>{setBusy(true);setError('');try{setData(await adminRead('enrichment_operations',{country_code:country||null,hours,limit:30}))}catch(e){setError(e.message||String(e))}finally{setBusy(false)}}
 useEffect(()=>{if(rank>=4)load()},[rank,country,hours])
 const coverage=data?.coverage||[],work=data?.work||{},hourly=data?.hourly||[],blockers=data?.blockers||[],providers=data?.providers||[],reasons=data?.stop_reasons||[],admissions=data?.admissions||[],recent=data?.recent_items||[]
 if(rank<4)return null
 return <section className="eops" data-cf245-enrichment-operations="true">
  <div className="eops-head"><div><span className="eops-kicker">Outcome reporting</span><h2>Enrichment Operations</h2><p>What actually enriched, where work stopped, and what reached Search/website. Acquisition, admission and publication remain separate stages.</p></div><div className="eops-actions"><label>Country<select value={country} onChange={e=>setCountry(e.target.value)}><option value="">AU + NZ</option><option value="AU">Australia</option><option value="NZ">New Zealand</option></select></label><label>Window<select value={hours} onChange={e=>setHours(Number(e.target.value))}><option value="24">24 hours</option><option value="48">48 hours</option><option value="168">7 days</option></select></label><button onClick={load} disabled={busy}><RefreshCw size={14}/>{busy?'Refreshing…':'Refresh'}</button></div></div>
  {error&&<div className="eops-alert"><AlertTriangle size={15}/>{error}</div>}
  <div className="eops-note"><ShieldCheck size={15}/><span>{data?.authority_note||'Metrics are observational and do not authorise canonical or publication mutation.'}</span></div>
  <div className="eops-kpis">
   <Card icon={Workflow} label="Queued / processing" value={`${n(work.queued)} / ${n(work.processing)}`} detail="Current managed-run state"/>
   <Card icon={Activity} label="Fetched · 24h" value={n(work.fetched)} detail={`${n(work.fetch_failures)} fetch failures`}/>
   <Card icon={BookOpen} label="Evidence · 24h" value={n(work.evidence_24h)} detail={`${n(work.layer3_24h)} Layer 3 fall-out`}/>
   <Card icon={CheckCircle2} label="Admitted source records · 24h" value={n(work.admitted_source_records_24h)} detail="Separate from Search publication"/>
   <Card icon={DollarSign} label="Vendor cost · 24h" value={money(work.vendor_cost_usd_24h)} detail={`${n(work.vendor_units_24h)} vendor units`}/>
   <Card icon={AlertTriangle} label="429 / 5xx · 24h" value={`${n(work.http_429_24h)} / ${n(work.http_5xx_24h)}`} detail="Provider/runtime pressure"/>
  </div>
  <div className="eops-grid">
   <article className="eops-panel eops-wide"><Panel title="Coverage & backlog" subtitle="Search/website-visible coverage from the latest hourly snapshot."/>
    <div className="eops-table-wrap"><table><thead><tr><th>Country</th><th>Field</th><th>Current</th><th>Coverage</th><th>+ hour</th><th>+ day</th><th>Remaining</th><th>Queueable</th><th>Blocked</th><th>Awaiting qualification</th></tr></thead><tbody>{coverage.map(x=><tr key={`${x.country_code}-${x.field_key}`}><td>{x.country_code}</td><td><strong>{fieldLabel(x.field_key)}</strong></td><td>{n(x.current)} / {n(x.total)}</td><td>{Number(x.coverage_pct||0).toFixed(2)}%</td><td>{x.added_hour==null?<span className="eops-muted">Baseline pending</span>:signed(x.added_hour)}</td><td>{x.added_day==null?<span className="eops-muted">Baseline pending</span>:signed(x.added_day)}</td><td>{n(x.remaining)}</td><td>{n(x.queueable)}</td><td>{n(x.blocked)}</td><td>{n(x.awaiting_qualification)}</td></tr>)}</tbody></table></div>
    {!coverage.length&&!busy&&<Empty text="No coverage snapshot is available yet."/>}
   </article>
   <article className="eops-panel"><Panel title="Where work stops" subtitle="Seven-day item stop reasons."/><Bars rows={reasons.map(x=>({label:human(x.reason),value:x.items,detail:`${n(x.fields_resolved)} / ${n(x.fields_targeted)} fields resolved`}))}/></article>
   <article className="eops-panel"><Panel title="Provider yield & latency" subtitle="Seven-day acquisition route performance."/><div className="eops-list">{providers.map(x=><div key={x.provider}><div><strong>{human(x.provider)}</strong><small>{n(x.succeeded)} succeeded · {n(x.failed)} failed · {n(x.retries)} retries</small></div><span>{ms(x.p50_ms)} p50<br/>{ms(x.p95_ms)} p95</span></div>)}</div></article>
   <article className="eops-panel eops-wide"><Panel title="Hourly enrichment funnel" subtitle="Acquisition and deterministic extraction are not reported as published enrichment."/>
    <div className="eops-table-wrap"><table><thead><tr><th>Hour</th><th>Country</th><th>Items</th><th>Fetched</th><th>Fetch fail</th><th>Evidence</th><th>Extraction</th><th>URLs</th><th>Intakes</th><th>English</th><th>Tuition</th><th>Scholarships</th><th>Admitted</th><th>Unchanged</th><th>Rejected / blocked</th><th>L3</th><th>L4</th><th>Courses improved</th><th>Vendor units / cost</th><th>Retries</th><th>429</th><th>5xx</th><th>Other failures</th><th>Response p50 / p95</th><th>Extraction p50 / p95</th></tr></thead><tbody>{hourly.slice(-24).reverse().map((x,i)=><tr key={`${x.hour_utc}-${x.country_code}-${x.domain}-${i}`}><td>{when(x.hour_utc)}</td><td>{x.country_code||'—'}</td><td>{n(x.items)}</td><td>{n(x.fetched)}</td><td>{n(x.fetch_failures)}</td><td>{n(x.evidence_created)}</td><td>{n(x.extraction_attempted)}</td><td>{n(x.official_urls_found)}</td><td>{n(x.intakes_found)}</td><td>{n(x.english_requirements_found)}</td><td>{n(x.provider_current_tuition_found)}</td><td>{n(x.scholarships_found)}</td><td>{n(x.facts_admitted_lower_bound)}</td><td>{n(x.unchanged)}</td><td>{n(x.rejected_or_blocked)}</td><td>{n(x.layer3_escalated)}</td><td>{n(x.layer4_referred)}</td><td>{n(x.courses_improved_lower_bound)}</td><td>{n(x.vendor_units)} / {money(x.vendor_cost_usd)}</td><td>{n(x.retries)}</td><td>{n(x.http_429)}</td><td>{n(x.http_5xx)}</td><td>{n(x.other_runtime_failures)}</td><td>{ms(x.p50_response_ms)} / {ms(x.p95_response_ms)}</td><td>{ms(x.p50_extraction_ms)} / {ms(x.p95_extraction_ms)}</td></tr>)}</tbody></table></div>
    {!hourly.length&&!busy&&<Empty text="No managed Layer 2 activity exists in this window."/>}
   </article>
   <article className="eops-panel"><Panel title="Backlog blockers" subtitle="Missing data classified before workload generation."/><div className="eops-list">{blockers.slice(0,12).map((x,i)=><div key={`${x.country_code}-${x.field_key}-${x.reason}-${i}`}><div><strong>{x.country_code} · {fieldLabel(x.field_key)}</strong><small>{human(x.reason||x.state)}</small></div><b>{n(x.courses)}</b></div>)}</div></article>
   <article className="eops-panel"><Panel title="Recent field admissions" subtitle="Canonical decision ledger; publication remains separate."/><div className="eops-list">{admissions.slice(0,12).map(x=><div key={x.id}><div><strong>{x.provider_name||'Provider'} · {x.course_title||x.course_id}</strong><small>{fieldLabel(x.field_key)} · {human(x.status)} · {human(x.reason_code)}</small></div><button onClick={()=>openEvidence(x.evidence_id)}>Evidence</button></div>)}</div></article>
   <article className="eops-panel eops-wide"><Panel title="Recent execution trace" subtitle="Drill into Jobs and Evidence without direct SQL."/><div className="eops-table-wrap"><table><thead><tr><th>Event</th><th>Provider / Course</th><th>Status</th><th>Fields</th><th>Evidence</th><th>Stop reason</th><th>Drill-down</th></tr></thead><tbody>{recent.slice(0,20).map((x,i)=><tr key={x.run_item_id||i}><td>{when(x.event_at)}</td><td>{x.provider_name||'—'}<small className="eops-block">{x.course_code||x.course_id||'—'}</small></td><td>{human(x.status)}</td><td>{n(x.fields_resolved)} / {n(x.fields_targeted)}</td><td>{n(x.evidence_count)}</td><td>{human(x.stop_reason)}</td><td><div className="eops-row-actions"><button onClick={()=>openNav('Jobs')}>Jobs</button>{x.evidence_id&&<button onClick={()=>openEvidence(x.evidence_id)}>Evidence</button>}</div></td></tr>)}</tbody></table></div></article>
  </div>
  <footer className="eops-footer"><Clock3 size={14}/><span>Observed {when(data?.observed_at)} · {data?.change_control_ref||'CF-CHG-20260915-245'} · Hour/day velocity remains unavailable until a real prior snapshot exists.</span></footer>
 </section>
}

function Card({icon:Icon,label,value,detail}){return <article className="eops-card"><Icon size={17}/><div><small>{label}</small><strong>{value}</strong><span>{detail}</span></div></article>}
function Panel({title,subtitle}){return <div className="eops-panel-head"><div><h3>{title}</h3><p>{subtitle}</p></div></div>}
function Empty({text}){return <div className="eops-empty">{text}</div>}
function signed(v){const x=Number(v||0);return <span className={x>0?'eops-positive':''}>{x>0?'+':''}{n(x)}</span>}
function Bars({rows}){const max=Math.max(1,...rows.map(x=>Number(x.value||0)));return <div className="eops-bars">{rows.slice(0,10).map((x,i)=><div key={`${x.label}-${i}`}><span><strong>{x.label}</strong><small>{x.detail}</small></span><i><b style={{width:`${Math.max(3,100*Number(x.value||0)/max)}%`}}/></i><em>{n(x.value)}</em></div>)}</div>}
