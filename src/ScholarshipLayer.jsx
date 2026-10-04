// Scholarships at each layer (v2.15.173, Decision 251). Platform Admin, 4 Oct 2026 01:24: everything the scholarship
// pipeline uses — sources per country and how each is used, what ran and how it went, the per-run limits and the job
// switches — shown and controlled on the layer it belongs to, not kept in job commands or function text.
//   Layer 1: countries switched on, and the sources for each (ingest, university pages, reference, validation).
//   Layer 2: discovery and reading by country, refusals, worker answers, the jobs and their limits.
//   Layer 3: the AI check by country (off until a model passes its benchmark) with the existing AI control.
//   Layer 4: the jobs after publishing (shown under Scholarship publishing).
// Read: public.admin_scholarship_layer_read(layer); write: public.admin_scholarship_layer_write(action, args) — Platform
// Admin, with a reason; every change is logged (migration 20261004000300).
import React,{useEffect,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'
import{utcClockToMelbourne}from'./lib/format.js'
import ScholarshipAiControl from'./ScholarshipAiControl'

const ROLE={ingest:'Ingest — read into records',provider_pages:'University pages',reference:'Reference — for looking up',validation:'Validation — compare with our records'}
const ROLE_SHORT={ingest:'Ingest',provider_pages:'University pages',reference:'Reference',validation:'Validation'}
const REFUSAL={international_not_stated:'Page does not say international students can apply',no_named_title:'No scholarship name on the page',past_year_only:'Only past years mentioned',
  'not an Australian university provider':'Not a university','not a university provider in a scholarship country':'Not a university',not_a_scholarship:'Not a scholarship',domestic_only:'Domestic students only',
  listing_page:'A list of scholarships, not one',not_provider_domain:'Not on the university site',too_thin:'Too little text on the page',not_offered:'No longer offered'}
const READ={read:'Read',waiting:'Waiting',blocked:'Blocked by the site',too_thin:'Too little text',robots_disallowed:'Not allowed by the site',not_html:'Not a web page',gone:'Page gone',fetch_failed:'Could not fetch',name_mismatch:'Name not on the page'}
const OUTCOME={admitted:'Added as a scholarship',rejected:'Refused',waiting:'Not read yet',not_decided:'Read, not decided',duplicate:'Already held',matched_existing:'Matched a scholarship we hold',matched_held:'Matched a held scholarship',withdrawn:'Withdrawn'}
const DISC={mapped:'Searched — pages found',empty:'Searched — none found',failed:'Search failed',pending:'Waiting'}
const MODE={scholarship_discover:'Find pages',scholarship_read:'Re-read pages',scholarship_inspect:'Inspect a page',scholarship_reextract:'Read again'}
const errText=e=>e?.message||String(e)
const human=v=>String(v??'').replace(/_/g,' ')

// cron schedules are in UTC; shown in Melbourne clock time with daylight saving (shared helper in lib/format.js)
export function scheduleText(s){
  const p=String(s||'').trim().split(/\s+/);if(p.length!==5)return s||'—'
  const[mi,h,dom,mon,dow]=p,pad=n=>String(n).padStart(2,'0')
  if(/^\*\/\d+$/.test(mi)&&h==='*')return `Every ${mi.slice(2)} minutes`
  if(/^\d+-\d+\/\d+$/.test(mi)&&h==='*')return `Every ${mi.split('/')[1]} minutes`
  if(/^\d+$/.test(mi)&&h==='*')return `Hourly at :${pad(mi)}`
  if(/^\d+$/.test(mi)&&/^\*\/\d+$/.test(h))return `Every ${h.slice(2)} hours at :${pad(mi)}`
  if(/^\d+$/.test(mi)&&/^\d+$/.test(h)&&dom==='*'&&mon==='*'){const m=utcClockToMelbourne(h,mi),t=`${m.time} Melbourne time`;if(dow==='*')return `Daily at ${t}`;const days=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];return `${days[(Number(dow)+m.dayShift)%7]||'Weekly'}s at ${t}`}
  return s
}
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}

export default function ScholarshipLayer({layer,rank=3,onError,compact=false}){
  const[d,setD]=useState(null),[failed,setFailed]=useState(''),[busy,setBusy]=useState(false),[country,setCountry]=useState('AU')
  const load=async()=>{setFailed('');try{const{data,error}=await supabase.rpc('admin_scholarship_layer_read',{p_layer:layer});if(error)throw error;setD(data||{})}catch(e){setFailed(errText(e))}}
  useEffect(()=>{setD(null);load()},[layer])
  const write=async(action,args,question)=>{const reason=ask(question);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_scholarship_layer_write',{p_action:action,p_args:{...args,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(failed&&!d)return <section className="m-panel"><Empty text={`Scholarships could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if(!d)return <section className="m-panel"><Loading label="Loading scholarships…"/></section>
  const can=Boolean(d.can_manage)&&!busy
  const jobs=<Jobs jobs={d.jobs||[]} can={can} write={write}/>
  const settings=(d.settings||[]).length>0&&<Settings settings={d.settings} can={can} write={write}/>
  if(compact)return <div className="sl-wrap" data-scholarship-layer={layer}>{jobs}</div>
  return <div className="m-page-stack sl-wrap" data-scholarship-layer={layer}>
    {!d.can_manage&&<p className="l3v-note">You can view this. Only a Platform Admin can change it.</p>}
    {layer===1&&<Layer1 d={d} can={can} write={write}/>}
    {layer===2&&<Layer2 d={d}/>}
    {layer===3&&<Layer3 d={d} rank={rank} country={country} setCountry={setCountry} onError={onError}/>}
    {settings}
    {jobs}
  </div>
}

function Jobs({jobs,can,write}){
  return <section className="m-panel" data-sl-jobs><SectionTitle title="Jobs" subtitle="What runs on a schedule at this layer. Runs and failures are the last 7 days; a run means the job started its work."/>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Job</th><th>When</th><th className="num">Runs</th><th className="num">Failed</th><th>Last run</th><th>State</th></tr></thead><tbody>
      {jobs.length?jobs.map(j=><tr key={j.jobname} data-sl-job={j.jobname}><td><strong>{j.label}</strong><small className="sl-sub">{j.what}</small>{j.last_failure&&<small className="sl-bad">Last failure: {j.last_failure}</small>}</td>
        <td>{j.schedule?scheduleText(j.schedule):'Not scheduled'}</td><td className="num">{fmtNumber(j.runs_7d||0)}</td><td className="num">{Number(j.failed_7d)?<b className="sl-bad">{fmtNumber(j.failed_7d)}</b>:'0'}</td>
        <td>{j.last_run?fmtDateTime(j.last_run):'Never'}</td>
        <td>{j.schedule?<span className="sl-state"><span className={`sch-st ${j.active?'sch-st-pub':'sch-st-held'}`}>{j.active?'Running':'Paused'}</span>{can&&<Button compact onClick={()=>write('job',{jobname:j.jobname,active:!j.active},`${j.active?'Pause':'Resume'} "${j.label}"?`)} aria-label={`${j.active?'Pause':'Resume'} ${j.label}`}>{j.active?'Pause':'Resume'}</Button>}</span>:'—'}</td></tr>)
        :<tr><td colSpan={6} className="cf-empty-cell">No jobs at this layer.</td></tr>}
    </tbody></table></div></section>
}

function Settings({settings,can,write}){
  const[vals,setVals]=useState({})
  return <section className="m-panel" data-sl-settings><SectionTitle title="Settings" subtitle="Values the jobs read each time they run. A Platform Admin can change them, with a reason."/>
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Setting</th><th>Value</th><th>Allowed</th><th>Last change</th></tr></thead><tbody>
      {settings.map(s=>{const v=vals[s.key]??String(s.value);return <tr key={s.key} data-sl-setting={s.key}><td><strong>{s.label}</strong><small className="sl-sub">{s.help}</small></td>
        <td><span className="sl-val"><input aria-label={s.label} inputMode="numeric" value={v} disabled={!can} onChange={e=>setVals(x=>({...x,[s.key]:e.target.value}))}/><small>{s.unit}</small>{can&&String(v)!==String(s.value)&&<Button compact variant="primary" onClick={()=>write('setting',{key:s.key,value:v},`Change "${s.label}" from ${s.value} to ${v}?`)}>Save</Button>}</span></td>
        <td>{fmtNumber(s.min)} to {fmtNumber(s.max)}</td><td><small>{s.reason||'—'}{s.updated_at?` · ${fmtDateTime(s.updated_at)}`:''}</small></td></tr>})}
    </tbody></table></div></section>
}

function Layer1({d,can,write}){
  const[form,setForm]=useState({country:'AU',role:'validation',label:'',url:'',use:''})
  const countries=d.countries||[],sources=d.sources||[]
  const groups=[...new Set(sources.map(s=>s.country))]
  return <>
    <section className="m-panel" data-sl-countries><SectionTitle title="Countries" subtitle="Scholarships are found and read only for countries switched on. Amounts are kept in each country's currency."/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Country</th><th>Currency</th><th className="num">Providers</th><th className="num">Universities searched or queued</th><th className="num">Scholarships</th><th className="num">Published</th><th>Scholarships</th></tr></thead><tbody>
        {countries.map(c=><tr key={c.code} data-sl-country={c.code}><td><strong>{c.name}</strong> <small>{c.code}</small></td><td>{c.currency}</td><td className="num">{fmtNumber(c.providers)}</td><td className="num">{fmtNumber(c.universities_queued)}</td><td className="num">{fmtNumber(c.scholarships)}</td><td className="num">{fmtNumber(c.published)}</td>
          <td><span className="sl-state"><span className={`sch-st ${c.enabled?'sch-st-pub':'sch-st-held'}`}>{c.enabled?'On':'Off'}</span>{can&&<Button compact onClick={()=>write('country',{code:c.code,enabled:!c.enabled},`Switch scholarships ${c.enabled?'off':'on'} for ${c.name}?`)}>{c.enabled?'Switch off':'Switch on'}</Button>}</span>{c.enabled&&!Number(c.providers)&&<small className="sl-sub">No providers in the catalogue yet</small>}</td></tr>)}
      </tbody></table></div></section>
    <section className="m-panel" data-sl-sources><SectionTitle title="Sources" subtitle="Each source is used one way: Ingest (read into scholarship records), University pages (a university's own scholarship pages), Reference (for looking up) or Validation (to compare with our records). Universities' own pages are also found automatically (Layer 2)."/>
      {groups.map(g=><div key={g} className="sl-group" data-sl-source-group={g}><h4>{g==='ALL'?'All countries':(countries.find(c=>c.code===g)?.name||g)}{countries.find(c=>c.code===g)?.detail_sources?<small> · plus {fmtNumber(countries.find(c=>c.code===g).detail_sources)} single scholarship pages registered as sources</small>:null}</h4>
        <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Source</th><th>Used as</th><th className="num">Records</th><th>Reading</th><th>State</th></tr></thead><tbody>
          {sources.filter(s=>s.country===g).map(s=><tr key={s.id} data-sl-source={s.label}><td><strong>{s.label||'—'}</strong>{s.url&&<a className="l3v-code" href={s.url} target="_blank" rel="noreferrer">{s.url.replace(/^https?:\/\//,'').slice(0,60)}</a>}{(s.use||s.ingestion)&&<small className="sl-sub">{s.use||s.ingestion}</small>}</td>
            <td>{can?<select aria-label={`Use of ${s.label}`} value={s.role} onChange={e=>write('source_role',{id:s.id,role:e.target.value},`Use "${s.label}" as ${ROLE_SHORT[e.target.value]}?`)}>{Object.entries(ROLE_SHORT).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select>:ROLE_SHORT[s.role]||s.role}</td>
            <td className="num">{fmtNumber(s.records||0)}</td>
            <td>{s.feed?<span className="sl-feed"><span>{s.feed.enabled?`Every ${Math.round(s.feed.cadence_hours/24)} days`:'Feed paused'}{s.qualification?` · ${human(s.qualification)}`:''}</span><small>Last read {s.feed.last_dispatched_at?fmtDateTime(s.feed.last_dispatched_at):'never'} · next {s.feed.next_due_at?fmtDateTime(s.feed.next_due_at):'—'}</small>{s.feed.last_error&&<small className="sl-bad">{s.feed.last_error}</small>}
                {can&&<Button compact onClick={()=>{const h=window.prompt(`Read "${s.label}" every how many hours? (24 to 2160)`,String(s.feed.cadence_hours));if(h&&h.trim())write('feed',{feed:s.feed.feed,cadence_hours:h.trim()},`Read "${s.label}" every ${h.trim()} hours?`)}}>Change how often</Button>}</span>
              :s.role==='provider_pages'?<small>Read through the university's pages (Layer 2)</small>:s.reader==='none'||s.role==='reference'||s.role==='validation'?<small>Not read automatically</small>:<small>—</small>}</td>
            <td><span className="sl-state"><span className={`sch-st ${s.status==='active'?'sch-st-pub':'sch-st-held'}`}>{s.status==='active'?'On':s.status==='registered'?'Registered':'Paused'}</span>{can&&<Button compact onClick={()=>write('source_status',{id:s.id,status:s.status==='active'?'paused':'active'},`${s.status==='active'?'Pause':'Turn on'} "${s.label}"?`)}>{s.status==='active'?'Pause':'Turn on'}</Button>}</span></td></tr>)}
        </tbody></table></div></div>)}
      {can&&<form className="sl-add" data-sl-add onSubmit={e=>{e.preventDefault();write('source_add',form,`Register "${form.label}" (${ROLE_SHORT[form.role]}, ${form.country==='ALL'?'all countries':form.country})?`).then(()=>setForm(f=>({...f,label:'',url:'',use:''})))}}>
        <h4>Add a source</h4>
        <label><small>Country</small><select value={form.country} onChange={e=>setForm({...form,country:e.target.value})}><option value="ALL">All countries</option>{countries.map(c=><option key={c.code} value={c.code}>{c.name}</option>)}</select></label>
        <label><small>Used as</small><select value={form.role} onChange={e=>setForm({...form,role:e.target.value})}>{Object.entries(ROLE).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
        <label><small>Name</small><input value={form.label} onChange={e=>setForm({...form,label:e.target.value})} placeholder="e.g. Study in New Zealand scholarships"/></label>
        <label><small>Address</small><input value={form.url} onChange={e=>setForm({...form,url:e.target.value})} placeholder="https://"/></label>
        <label className="sl-wide"><small>How it is used (optional)</small><input value={form.use} onChange={e=>setForm({...form,use:e.target.value})}/></label>
        <p className="sl-sub sl-wide">A source added for Ingest or University pages is registered, not read, until a reader exists for it. Reference and Validation sources are listed for people to use.</p>
        <Button type="submit" variant="primary" disabled={!form.label.trim()||!/^https?:\/\/\S+\.\S+$/i.test(form.url.trim())}>Register</Button>
      </form>}
    </section>
  </>
}

function Counts({title,obj,labels}){const e=Object.entries(obj||{}).sort((a,b)=>b[1]-a[1]);return <div className="sl-counts"><small>{title}</small>{e.length?<ul>{e.map(([k,v])=><li key={k}><span>{labels[k]||human(k)}</span><b>{fmtNumber(v)}</b></li>)}</ul>:<span className="sl-sub">None yet</span>}</div>}

const PURPOSE={sch_map:'Mapping university sites',sch_search:'Searching for a page',sch_scrape:'Reading pages that refuse a direct read'}
function Credits({fc}){
  const cap=Number(fc.cap||0),used=Number(fc.used||0),reserve=Number(fc.reserve||0),left=Math.max(0,cap-used),pct=cap?Math.min(100,Math.round(used/cap*100)):100
  const state=left<=0?'All used: scholarship work no longer uses Firecrawl.':left<=reserve?`Below the reserve: new pages that refuse a direct read are not retried; the ${fmtNumber(left)} left are kept for re-reading held scholarships' pages.`:'Within the cap.'
  return <section className="m-panel" data-sl-credits><SectionTitle title="Firecrawl credits for scholarships" subtitle="Firecrawl is used only when a university site refuses a direct read, and to map and search sites. The cap and the reserve are the settings below."/>
    <div className="sl-credit"><div className="sl-credit-bar" role="img" aria-label={`${fmtNumber(used)} of ${fmtNumber(cap)} credits used`}><span style={{width:`${pct}%`}}/>{cap>0&&<i style={{left:`${Math.max(0,Math.min(100,(cap-reserve)/cap*100))}%`}} title="Reserve starts here"/>}</div>
      <div className="sl-credit-figs"><span><b>{fmtNumber(used)}</b> used</span><span><b>{fmtNumber(left)}</b> left of <b>{fmtNumber(cap)}</b></span><span>Reserve <b>{fmtNumber(reserve)}</b></span></div>
      <p className={`sl-status ${left<=reserve?'sl-off':''}`} data-sl-credit-state>{state}</p>
      <ul className="sl-credit-use">{Object.entries(fc.by_purpose||{}).map(([k,v])=><li key={k}><span>{PURPOSE[k]||human(k)}</span><b>{fmtNumber(v.all)}</b><small>{fmtNumber(v.last_7_days)} in 7 days</small></li>)}</ul></div>
  </section>
}

function Layer2({d}){
  const names={AU:'Australia',NZ:'New Zealand',CA:'Canada',GB:'United Kingdom',US:'United States'}
  return <>
    <section className="m-panel" data-sl-countries2><SectionTitle title="Discovery and reading by country" subtitle="Universities' sites are searched for scholarship pages; each page found is read and admitted only if it is one scholarship, named, open to international students and currently offered."/>
      <div className="sl-cards">{(d.countries||[]).map(c=><article key={c.code} className="sl-card" data-sl-l2-country={c.code}><h4>{names[c.code]||c.code}<small> · {fmtNumber(c.pages_found||0)} pages found</small></h4>
        <Counts title="Universities" obj={c.discovery} labels={DISC}/>
        <Counts title="Pages found — reading" obj={c.page_reads} labels={READ}/>
        <Counts title="Pages found — outcome" obj={c.outcomes} labels={OUTCOME}/>
        <div className="sl-counts"><small>Most common reasons for refusing a page</small>{(c.refusals||[]).length?<ul>{c.refusals.map(r=><li key={r.reason}><span>{REFUSAL[r.reason]||human(r.reason)}</span><b>{fmtNumber(r.pages)}</b></li>)}</ul>:<span className="sl-sub">None</span>}</div>
        <Counts title="Known scholarship pages — last read" obj={c.rereads} labels={READ}/>
      </article>)}</div></section>
    {d.firecrawl&&<Credits fc={d.firecrawl}/>}
    <section className="m-panel" data-sl-worker><SectionTitle title="Worker answers (last 6 hours)" subtitle="Each job run sends work to the reading worker; this is what came back. Older answers are not kept."/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Work</th><th className="num">Sent</th><th className="num">Answered</th><th className="num">Succeeded</th><th className="num">Failed</th><th>Last failure</th></tr></thead><tbody>
        {(d.worker||[]).length?d.worker.map(w=><tr key={w.mode}><td>{MODE[w.mode]||human(w.mode)}</td><td className="num">{fmtNumber(w.sent)}</td><td className="num">{fmtNumber(w.answered)}</td><td className="num">{fmtNumber(w.ok)}</td><td className="num">{Number(w.failed)?<b className="sl-bad">{fmtNumber(w.failed)}</b>:'0'}</td><td><small>{w.last_failure||'—'}</small></td></tr>)
          :<tr><td colSpan={6} className="cf-empty-cell">No work sent in the last 6 hours.</td></tr>}
      </tbody></table></div></section>
  </>
}

function Layer3({d,rank,country,setCountry,onError}){
  const ai=d.ai||[],profiles=d.profiles||[],any=ai.some(a=>a.enabled),passed=profiles.filter(p=>p.benchmark_pass)
  return <>
    <section className="m-panel" data-sl-ai><SectionTitle title="AI check for scholarships" subtitle="Layer 3 checks scholarship pages with a pinned model. It runs only when switched on for a country with a model that has passed its benchmark; passing a benchmark never switches it on."/>
      <p className={`sl-status ${any?'':'sl-off'}`} data-sl-ai-state>{any?'Switched on for: '+ai.filter(a=>a.enabled).map(a=>a.country).join(', '):`Not running. Switched off for every country; ${passed.length?`${passed.length} model(s) passed the benchmark`:'no model has passed its benchmark yet'}. Scholarships are read by fixed rules in Layer 2 meanwhile.`}</p>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Country</th><th>State</th><th>Model</th><th>Task</th><th className="num">Daily budget</th><th className="num">Per run</th><th className="num">Runs so far</th></tr></thead><tbody>
        {ai.map(a=><tr key={a.country} data-sl-ai-country={a.country}><td>{a.country}</td><td><span className={`sch-st ${a.enabled?'sch-st-pub':'sch-st-held'}`}>{a.enabled?'On':'Off'}</span><small className="sl-sub">{human(a.state||'')}</small></td><td>{a.profile||'None chosen'}</td><td>{human(a.task)}</td><td className="num">US${a.budget_usd}</td><td className="num">{fmtNumber(a.max_records)}</td><td className="num">{fmtNumber(a.runs)}</td></tr>)}
      </tbody></table></div>
      <h4 className="sl-h4">Models</h4>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Profile</th><th>Model (pinned)</th><th>Benchmark</th><th>State</th></tr></thead><tbody>
        {profiles.map(p=><tr key={p.code}><td>{p.code}</td><td><code>{p.model}</code></td><td>{p.benchmark_pass?'Passed':'Not passed'}</td><td>{p.paused?'Paused':p.enabled?'On':'Off'}</td></tr>)}
      </tbody></table></div></section>
    <section className="m-panel"><SectionTitle title="Run the benchmark or a check" action={<select aria-label="Country" value={country} onChange={e=>setCountry(e.target.value)}>{ai.map(a=><option key={a.country} value={a.country}>{a.country}</option>)}</select>}/>
      <ScholarshipAiControl rank={rank} country={country} onError={m=>onError?.(m)}/></section>
  </>
}
