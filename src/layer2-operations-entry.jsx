import React,{useEffect,useMemo,useState}from'react'
import{Button,Metric as KitMetric}from'./ui-kit'
import{createRoot}from'react-dom/client'
import{Activity,AlertTriangle,Archive,ChevronRight,Clock3,Cog,Database,Gauge,RefreshCw,ShieldCheck,SlidersHorizontal,X}from'lucide-react'
import{adminRead,api,supabase}from'./lib/supabase'
import EnrichmentOperations from'./EnrichmentOperations'
import'./layer2-operations.css'
import{fmtDateTime,fmtMoney,fmtNumber}from'./lib/format.js'
import{jobState}from'./LiveActivity'
import{errorReading,errorSteps}from'./lib/workerErrors'

const human=x=>String(x||'').replaceAll('_',' ').replace(/\b\w/g,m=>m.toUpperCase())
const fmtDate=x=>x?fmtDateTime(x):'—'
const sleep=ms=>new Promise(r=>setTimeout(r,ms))
const pct=(a,b)=>b>0?Math.round((100*a/b)*10)/10:0
const measuredBilling=b=>{if(!b)return'Not configured';if(b.subscription_cost_usd==null&&b.monetary_cost_basis==='subscription_cost_not_recorded')return'Quota measured · subscription cost not recorded';if(b.unit_cost_usd===0)return b.source==='internal_no_vendor_fee'?'Measured: no vendor fee':'Configured: US$0 cash/unit';return b.unit_cost_usd!=null?`Configured: ${fmtMoney(b.unit_cost_usd,'USD',{decimals:4})}/unit`:'Cost not available'}

function Entry(){const[rank,setRank]=useState(0),[open,setOpen]=useState(false);useEffect(()=>{let live=true,seq=0;const resolve=async()=>{const call=++seq;try{const{data}=await supabase.auth.getSession();if(!data.session){if(live&&call===seq)setRank(0);return}let ctx=null,last=null;for(let i=0;i<4&&!ctx;i++){try{ctx=await api.context()}catch(e){last=e;if(i<3)await sleep(250*(i+1))}}if(!ctx)throw last||new Error('context unavailable');if(live&&call===seq)setRank(Number(ctx?.role_rank||0))}catch{if(live&&call===seq){const{data}=await supabase.auth.getSession().catch(()=>({data:{session:null}}));if(!data?.session)setRank(0)}}};resolve();const{data}=supabase.auth.onAuthStateChange(()=>resolve());return()=>{live=false;seq++;data.subscription.unsubscribe()}},[]);if(rank<4)return null;return <><button className="l2o-launcher" onClick={()=>setOpen(true)}><Activity size={15}/><span>Layer 2 Operations</span></button>{open&&<Workspace rank={rank} onClose={()=>setOpen(false)}/>}</>}

export function Workspace({rank,onClose=()=>{},embedded=false,view='overview',navigate=null}){
 const go=(page,params={})=>{if(navigate){navigate(page,params);return}onClose();location.hash=`#${page}${params.tab?`/${params.tab}`:''}`}
 const openNav=label=>{onClose();requestAnimationFrame(()=>{const b=[...document.querySelectorAll('.m-nav-item')].find(x=>(x.textContent||'').trim()===label);b?.click()})}
 const openEvidence=id=>{onClose();location.hash=`#evidence${id?`?evidence_id=${encodeURIComponent(id)}`:''}`}
 // v2.15.128: one view per tab — overview (outcomes), start (fetch an area), history (daily progress, trace).
 // Decision 222 (v2.15.149): the views no longer read the retired pipeline (runs, alerts, sync control); each part loads
 // its own data from the course-page sweep.
 return <div className={embedded?'l2o-shell l2o-embedded':'l2o-shell'} role={embedded?'region':'dialog'} aria-label="Layer 2 Operations" data-l2-view={view}><main className="l2o-main">
 {view==='overview'&&<>
 <ActionRequired go={go}/>
 <EnrichmentOperations rank={rank} view="overview" openNav={openNav} openEvidence={openEvidence}/>
 </>}
 {view==='start'&&<FetchArea rank={rank} go={go}/>}
 {view==='history'&&<>
 <DailyProgress/>
 <EnrichmentOperations rank={rank} view="trace" openNav={openNav} openEvidence={openEvidence}/>
 </>}
 </main></div>}

// Decision 222 (v2.15.149): Fetch an area works on the course-page sweep (public.admin_coverage_fetch_area). Choose a
// country, state or university to see where it stands; Start puts it first in the sweep: the same priority pin as
// Scheduled jobs › Priority, a new site search where none was found, failed site maps retried, a page search for
// courses with no page, and found pages read now. Nothing admitted or entered by hand is changed.
const fa=async(action,args)=>{const{data,error}=await supabase.rpc('admin_coverage_fetch_area',{p_action:action,p_args:args});if(error)throw error;return data}
function FetchArea({rank,go}){const[countries,setCountries]=useState([]),[country,setCountry]=useState(''),[type,setType]=useState('university'),[scope,setScope]=useState({id:'',label:''}),[d,setD]=useState(null),[busy,setBusy]=useState(false),[err,setErr]=useState(''),[done,setDone]=useState(null)
 useEffect(()=>{fa('options',{}).then(x=>{const c=x?.countries||[];setCountries(c);setCountry(c[0]?.code||'')}).catch(e=>setErr(e.message||String(e)))},[])
 const args=()=>({country,scope_type:type,scope_id:type==='country'?null:scope.id||null})
 useEffect(()=>{setD(null);setDone(null);if(!country||(type!=='country'&&!scope.id))return;let live=true;setBusy(true);setErr('');fa('preview',args()).then(x=>live&&setD(x)).catch(e=>live&&setErr(e.message||String(e))).finally(()=>live&&setBusy(false));return()=>{live=false}},[country,type,scope.id])
 const loadPage=(kind,{countryCode,query,offset})=>fa('scope_page',{country:countryCode,kind,query,offset})
 const start=async()=>{setBusy(true);setErr('');try{const x=await fa('start',args());setD(x);setDone(x?.started||{})}catch(e){setErr(e.message||String(e))}finally{setBusy(false)}}
 const n=v=>fmtNumber(Number(v||0)),s=d?.sites||{},pg=d?.pages||{},f=d?.facts||{},name=type==='country'?(countries.find(c=>c.code===country)?.name||country):scope.label
 const nothing=done&&!Object.values(done).some(v=>Number(v)>0)
 return <section className="l2o-panel l2o-sync-panel" data-fetch-area><div className="l2o-panel-head"><div><h2>Fetch an area</h2><p>Choose a country, state or university to see where it stands in the course-page sweep. Start puts it first in the sweep.</p></div></div>
 {err&&<div className="fr-error" role="alert">{err}</div>}
 <div className="l2o-sync-selectors">
  <label>Country<select aria-label="Fetch an area country" value={country} onChange={e=>{setCountry(e.target.value);setScope({id:'',label:''})}}>{countries.map(c=><option key={c.code} value={c.code}>{c.name} ({c.code}) · {n(c.providers)} institutions · {n(c.courses)} courses</option>)}</select></label>
  <label>Scope<select aria-label="Fetch an area scope" value={type} onChange={e=>{setType(e.target.value);setScope({id:'',label:''})}}><option value="country">The whole country</option><option value="state">A state or region</option><option value="university">One university</option></select></label>
  {type!=='country'&&<PagedScopeSelect ariaLabel={type==='state'?'Fetch an area state':'Fetch an area university'} label={type==='state'?'State':'University'} kind={type==='state'?'state':'university'} country={country} value={scope.id} valueLabel={scope.label} loadPage={loadPage} onChange={(id,label)=>setScope({id,label})}/>}
 </div>
 {!d?<div className="l2o-empty">{busy?'Checking where it stands…':type==='country'?'Loading…':`Choose a ${type==='state'?'state':'university'}.`}</div>:<div className="l2o-sync-card" data-fetch-area-state>
  <div className="cf-metric-grid">
   <KitMetric label="Universities" value={n(d.providers)} detail={`${n(s.mapped)} sites mapped · ${n(s.not_found)} not found · ${n(s.to_search)} to search`}/>
   <KitMetric label="Courses" value={n(d.courses)} detail={`${n(pg.found)} pages found · ${n(pg.no_page)} with no page yet`}/>
   <KitMetric label="Pages read" value={n(pg.read)} detail={`${n(pg.to_read)} waiting to be read · ${n(pg.not_this_course)} not this course`}/>
   <KitMetric label="Facts admitted" value={n(f.official_url)} detail={`official pages · English ${n(f.english)} · intakes ${n(f.intakes)} · tuition ${n(f.provider_tuition)}`}/>
  </div>
  <p className="sd-desc" data-fetch-area-explain>{explainScope(d)}</p>
  <div className="l2o-sync-action l2-start-row"><div><strong>{d.first_in_sweep?`${name} is first in the sweep`:`Put ${name||'this area'} first in the sweep`}</strong><span>Searches again for sites not found, retries failed site maps, searches for pages of courses with none (a search that found nothing is repeated after 7 days) and reads found pages now. {n(d.searches_waiting)} page searches waiting. Facts counts update every hour.</span></div>
   <Button disabled={busy||rank<4} onClick={start}>{d.first_in_sweep?'Start again':'Start'}</Button></div>
  {done&&<div className={nothing?'l2o-note':'l2o-success'} role="status" data-fetch-area-done><strong>{nothing?'Already first in the sweep; nothing new to start':'Started'}</strong>
   <span>{n(done.joined)} universities joined · {n(done.site_search_again)} site searches · {n(done.site_map_retry)} site maps retried · {n(done.page_searches_queued)} page searches queued · {n(done.pages_to_read_now)} pages to read now.</span>
   <div className="l2o-action-buttons"><Button compact onClick={()=>go('activity')}>Open Live activity</Button>{Number(s.not_found)>0&&<Button compact onClick={()=>go('layer4',{tab:'websites'})}>Enter missing websites</Button>}<Button compact onClick={()=>go('coverage')}>Open Coverage</Button></div></div>}
 </div>}
 </section>}
// What the numbers mean for this scope, in one plain sentence
export function explainScope(d){const s=d?.sites||{},pg=d?.pages||{},f=d?.facts||{}
 if(!Number(d?.courses))return'No active courses here.'
 if(Number(s.not_found)>0&&Number(s.mapped)===0)return'No website was found for this university, so no course pages can be found. Enter its website in Layer 4 › Websites to find.'
 if(Number(pg.to_read)>0||Number(d?.searches_waiting)>0)return'The sweep is still working here: pages are being searched for or read.'
 if(Number(pg.read)>0&&Number(f.english||0)===0&&Number(f.provider_tuition||0)===0)return'Pages are found and read, but none of them show English requirements or fees. The pages found may not carry them (for example handbook pages); those facts need another page on the university’s site.'
 if(Number(pg.no_page)>0)return'Some courses have no page yet; Start searches for them again.'
 return'The sweep has covered this area; counts update every hour.'}

// Decision 220 (v2.15.147): Action required lists only what someone can act on now — Layer 2 jobs (course pages and
// provider reading) that are failing or stuck, and workers sending back errors — each with what it means, what to do
// and a button to the screen where it is done. The old pipeline's alerts (stuck batches, paused profiles) are gone with it.
const L2_AREAS=new Set(['Course pages','Layer 2 reading'])
const TODO={failing:'Open Live activity to read the error. If it keeps failing, switch the job off on Scheduled jobs and report it.',
  stuck:'Work is waiting but none finished in 24 hours. Check Live activity for worker errors — usually the Firecrawl reserve or a site refusing reads.'}
function ActionRequired({go}){const[d,setD]=useState(null),[err,setErr]=useState('')
  const[web,setWeb]=useState(0)
  useEffect(()=>{let live=true;adminRead('live_activity',{}).then(x=>live&&setD(x||{})).catch(e=>live&&setErr(e.message||String(e)))
    // Decision 222: universities whose website the finder could not confirm wait for a person in Layer 4
    supabase.rpc('admin_provider_websites',{p_args:{limit:1}}).then(({data})=>live&&setWeb(Number(data?.total||0)));return()=>{live=false}},[])
  if(err)return <section className="l2o-panel" data-l2-action><div className="fr-error" role="alert">Could not check Layer 2 jobs: {err}</div></section>
  if(!d)return null
  const jobs=(d.jobs||[]).filter(j=>L2_AREAS.has(j.area)),labels=new Set(jobs.map(j=>j.label))
  const items=[...jobs.map(j=>{const[st,,why]=jobState(j);return st==='failing'||st==='stuck'?{key:j.job,title:j.label,state:st==='failing'?'Failing':'Stuck',means:why,todo:TODO[st],jobs:true}:null}).filter(Boolean),
    ...(web>0?[{key:'web',title:'Websites to find',state:`${fmtNumber(web)} universities`,means:'The website finder could not confirm these universities’ own sites, so none of their course pages can be found.',todo:'Open Layer 4 › Websites to find, check what was tried, and enter each university’s website. The sweep then maps the site and searches for its course pages.',web:true}]:[]),
    ...(d.worker_errors||[]).filter(e=>labels.has(e.job)||e.function==='coverage-sweep').map((e,i)=>({key:'w'+i,title:e.job||e.function,state:e.timed_out?'Timed out':e.status==null?'No reply':`Error ${e.status}`,means:errorReading(e),todo:errorSteps(e)+` (seen ${fmtNumber(e.count)} time${Number(e.count)===1?'':'s'})`}))]
  return <section className={items.length?'l2o-panel l2o-blockers':'l2o-panel'} data-l2-action>
    <div className="l2o-panel-head"><div><h2>Action required</h2><p>Layer 2 jobs and universities that need someone now, with what to do.</p></div><Button compact onClick={()=>go('activity')}>Open Live activity</Button></div>
    {items.length?items.map(it=><div className="l2o-blocker l2o-action" key={it.key} data-l2-action-item>
      <AlertTriangle size={15}/><div><strong>{it.title} · {it.state}</strong><span>{it.means}</span><small>What to do: {it.todo}</small>
        <div className="l2o-action-buttons">{!it.web&&<Button compact onClick={()=>go('activity')}>Open Live activity</Button>}{it.jobs&&<Button compact onClick={()=>go('jobs',{tab:'automations'})}>Open Scheduled jobs</Button>}{it.web&&<Button compact onClick={()=>go('layer4',{tab:'websites'})}>Open Websites to find</Button>}</div></div></div>)
    :<div className="l2o-ok" data-l2-action-none>Nothing needs action. Layer 2 jobs are running normally. <Button compact onClick={()=>go('activity')}>Open Live activity</Button></div>}
  </section>}

// Decision 220 (v2.15.147): History shows each country's daily progress — courses with each fact admitted, one row per
// day, with the change from the day before — from the hourly coverage build. It replaces the old pipeline's batch,
// run and fetch lists, which stopped when that pipeline was retired.
const FACTS=[['official_url','Official page'],['english','English'],['intakes','Intakes'],['provider_tuition','Tuition']]
function DailyProgress(){const[country,setCountry]=useState(''),[d,setD]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{let live=true;setErr('');adminRead('course_coverage',country?{country}:{}).then(x=>{if(!live)return;setD(x||{});if(!country){const top=(x?.countries||[])[0]?.code;if(top)setCountry(top)}}).catch(e=>live&&setErr(e.message||String(e)));return()=>{live=false}},[country])
  const days=useMemo(()=>{const m=new Map();for(const t of d?.trend||[]){if(!m.has(t.date))m.set(t.date,{date:t.date,total:0});const r=m.get(t.date);r[t.attribute]=Number(t.admitted||0);r.total=Math.max(r.total,Number(t.total||0))}return[...m.values()].sort((a,b)=>a.date<b.date?1:-1).slice(0,14)},[d])
  return <section className="l2o-panel" data-l2-daily>
    <div className="l2o-panel-head"><div><h2>Daily progress</h2><p>Courses with each fact admitted, by day, for one country. The last build of each day is kept; today updates every hour.</p></div>
      <label className="l2o-country">Country <select aria-label="Daily progress country" value={country} onChange={e=>setCountry(e.target.value)}>{(d?.countries||[]).map(c=><option key={c.code} value={c.code}>{c.code} · {fmtNumber(c.courses)} courses</option>)}</select></label></div>
    {err?<div className="fr-error" role="alert">{err}</div>:!d?<div className="l2o-empty">Loading…</div>:days.length?<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Day</th>{FACTS.map(([,l])=><th key={l} className="num">{l}</th>)}<th className="num">Courses</th></tr></thead><tbody>
      {days.map((r,i)=>{const prev=days[i+1];return <tr key={r.date} data-l2-day={r.date}><td>{r.date}</td>{FACTS.map(([k])=>{const v=r[k]||0,ch=prev?v-(prev[k]||0):null;return <td key={k} className="num">{fmtNumber(v)}{ch?<small className="l2o-delta">{ch>0?'+':''}{fmtNumber(ch)}</small>:null}</td>})}<td className="num">{fmtNumber(r.total)}</td></tr>})}
    </tbody></table></div>:<div className="l2o-empty">No daily figures for this country yet.</div>}
  </section>}

function PagedScopeSelect({ariaLabel,label,kind,country,value,valueLabel,loadPage,onChange}){const[open,setOpen]=useState(false),[search,setSearch]=useState(''),[offset,setOffset]=useState(0),[data,setData]=useState({items:[],total:0,has_more:false}),[loading,setLoading]=useState(false);const debounced=useMemo(()=>search,[search]);useEffect(()=>{setOffset(0)},[search,country,kind]);useEffect(()=>{if(!open)return;let live=true;setLoading(true);const t=setTimeout(()=>loadPage(kind,{countryCode:country,query:search,offset}).then(x=>live&&setData(x||{items:[],total:0,has_more:false})).catch(()=>live&&setData({items:[],total:0,has_more:false})).finally(()=>live&&setLoading(false)),220);return()=>{live=false;clearTimeout(t)}},[open,kind,country,search,offset]);const page=Math.floor(offset/10)+1,pages=Math.max(1,Math.ceil(Number(data.total||0)/10));return <label className="l2o-paged-scope">{label}<button type="button" aria-label={ariaLabel} aria-haspopup="listbox" aria-expanded={open} onClick={()=>setOpen(x=>!x)}><span>{valueLabel||`Choose ${label.toLowerCase()}`}</span><ChevronRight size={14}/></button>{open&&<div className="l2o-scope-popover" role="listbox" aria-label={`${label} options`}><input value={search} onChange={e=>setSearch(e.target.value)} placeholder={`Search ${label.toLowerCase()}…`}/>{loading&&<small>Loading…</small>}{(data.items||[]).map(x=><button type="button" role="option" aria-selected={String(value)===String(x.value)} key={x.value} onClick={()=>{onChange(x.value,x.label);setOpen(false);setSearch('');setOffset(0)}}><span>{x.label}</span>{x.meta&&<small>{x.meta}</small>}</button>)}{!loading&&!(data.items||[]).length&&<small>No matching options</small>}{Number(data.total||0)>10&&<div className="l2o-scope-pager"><button type="button" disabled={offset===0} onClick={()=>setOffset(o=>Math.max(0,o-10))}>Previous</button><span>{page} / {pages}</span><button type="button" disabled={!data.has_more} onClick={()=>setOffset(o=>o+10)}>Next</button></div>}</div>}</label>}


function PolicyModal({source,rank,onClose,onSaved}){const[mode,setMode]=useState(source.schedule_mode||'manual'),[batch,setBatch]=useState(source.batch_size||10),[routing,setRouting]=useState(source.routing_strategy||'direct_then_best_value'),[paid,setPaid]=useState(source.max_paid_attempts_per_entity||2),[concurrency,setConcurrency]=useState(source.max_concurrency||1),[busy,setBusy]=useState(false),[error,setError]=useState('');const save=async()=>{if(rank<5){setError('PIM Admin role required');return}setBusy(true);setError('');try{const patch={schedule_mode:mode,batch_size:Number(batch),routing_strategy:routing,max_paid_attempts_per_entity:Number(paid),max_concurrency:Number(concurrency),auto_handoff_layer3:true,stop_on_identity_mismatch:true};const{data,e}=await supabase.functions.invoke('layer2-config-control',{body:{action:'update_policy',profile_id:source.profile_id,patch}});if(e)throw e;if(data?.error)throw new Error(data.error);await onSaved()}catch(e){setError(e.message)}finally{setBusy(false)}};return <div className="l2o-modal"><div className="l2o-card"><div className="l2o-modal-head"><div><small>{source.country_code} · {source.data_type}</small><h2>{source.provider_name||source.source_label}</h2></div><button onClick={onClose}><X size={15}/></button></div><label>Automation<select value={mode} onChange={e=>setMode(e.target.value)}><option value="manual">Manual</option><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="disabled">Disabled</option></select></label><label>Batch size<input type="number" min="1" max="500" value={batch} onChange={e=>setBatch(e.target.value)}/></label><label>Run concurrency<input type="number" min="1" max="8" value={concurrency} onChange={e=>setConcurrency(e.target.value)}/></label><label>Provider routing<select value={routing} onChange={e=>setRouting(e.target.value)}><option value="direct_then_best_value">Direct first · best-value fallback</option><option value="lowest_cost_proven">Lowest-cost proven</option><option value="highest_success">Highest success</option><option value="manual_provider">Manual provider</option></select></label><label>Maximum paid attempts / item<input type="number" min="0" max="5" value={paid} onChange={e=>setPaid(e.target.value)}/></label><div className="l2o-note">Run concurrency controls this source profile. Acquisition-vendor concurrency, credentials and paid-provider ceilings are managed centrally under Administration.</div>{error&&<div className="l2o-error">{error}</div>}<div className="l2o-actions"><button disabled={busy} onClick={save}>Save policy</button><button onClick={onClose}>Cancel</button></div></div></div>}
function Kpi({icon,value,label}){return <KitMetric icon={()=>icon} label={label} value={value}/>}
function Metric({label,value}){return <KitMetric label={label} value={value}/>}
const root=document.getElementById('layer2-operations-root');if(root)createRoot(root).render(<Entry/>)