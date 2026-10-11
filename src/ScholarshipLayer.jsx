// Scholarships at each layer (v2.15.173, Decision 251). Platform Admin, 4 Oct 2026 01:24: everything the scholarship
// pipeline uses — sources per country and how each is used, what ran and how it went, the per-run limits and the job
// switches — shown and controlled on the layer it belongs to, not kept in job commands or function text.
//   Layer 1: countries switched on, and the sources for each (ingest, university pages, reference, validation).
//   Layer 2: discovery and reading by country, refusals, worker answers, the jobs and their limits.
//   Layer 3: retired 11 Oct 2026 (the AI-run check read the retired candidate table).
//   Layer 4: the jobs after publishing (shown under Scholarship publishing).
// Read: public.admin_scholarship_layer_read(layer); write: public.admin_scholarship_layer_write(action, args) — Platform
// Admin, with a reason; every change is logged (migration 20261004000300).
import React,{useEffect,useState}from'react'
import{RefreshCw}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'
import{utcClockToMelbourne}from'./lib/format.js'

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
// v2.15.240 (Platform Admin, 11 Oct 2026: full control in the UI, simple): no reason prompt; each change is logged with who and when
const ask=t=>`Changed on screen: ${t}`.slice(0,300)

export default function ScholarshipLayer({layer,rank=3,onError,compact=false,only=''}){
  const[d,setD]=useState(null),[failed,setFailed]=useState(''),[busy,setBusy]=useState(false)
  const load=async()=>{setFailed('');try{const{data,error}=await supabase.rpc('admin_scholarship_layer_read',{p_layer:layer});if(error)throw error;setD(data||{})}catch(e){setFailed(errText(e))}}
  useEffect(()=>{setD(null);load()},[layer])
  const write=async(action,args,question)=>{const reason=ask(question);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_scholarship_layer_write',{p_action:action,p_args:{...args,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(failed&&!d)return <section className="m-panel"><Empty text={`Scholarships could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if(!d)return <section className="m-panel"><Loading label="Loading scholarships…"/></section>
  const can=Boolean(d.can_manage)&&!busy
  // v2.15.243 (Platform Admin, 11 Oct 2026): retired jobs (no schedule) and the always-on scraper setting are not listed
  const jobs=<Jobs jobs={(d.jobs||[]).filter(j=>j.schedule)} can={can} write={write}/>
  const shown=(d.settings||[]).filter(s=>s.key!=='read_via_scraper')
  const settings=shown.length>0&&<Settings settings={shown} can={can} write={write}/>
  if(compact)return <div className="sl-wrap" data-scholarship-layer={layer}>{jobs}</div>
  if(only==='controls')return <div className="sl-wrap" data-scholarship-layer={layer} data-sl-controls>{settings}{jobs}</div>
  return <div className="m-page-stack sl-wrap" data-scholarship-layer={layer}>
    {!d.can_manage&&<p className="l3v-note">You can view this. Only a Platform Admin can change it.</p>}
    {layer===1&&<Layer1 d={d} can={can} write={write}/>}
    {layer===2&&<Layer2 d={d}/>}
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
        <td>{s.unit==='on/off'
          // v2.15.242: on/off settings are a switch (saved straight away, with a reason)
          ?<span className="sl-val"><label className="sl-switch"><input type="checkbox" role="switch" aria-label={s.label} data-sl-switch={s.key} checked={Number(s.value)>=1} disabled={!can} onChange={e=>{const nv=e.target.checked?1:0;write('setting',{key:s.key,value:nv},`Turn "${s.label}" ${nv?'on':'off'}?`)}}/><span>{Number(s.value)>=1?'On':'Off'}</span></label></span>
          :<span className="sl-val"><input aria-label={s.label} inputMode="numeric" value={v} disabled={!can} onChange={e=>setVals(x=>({...x,[s.key]:e.target.value}))}/><small>{s.unit}</small>{can&&String(v)!==String(s.value)&&<Button compact variant="primary" onClick={()=>write('setting',{key:s.key,value:v},`Change "${s.label}" from ${s.value} to ${v}?`)}>Save</Button>}</span>}</td>
        <td>{s.unit==='on/off'?'On or off':`${fmtNumber(s.min)} to ${fmtNumber(s.max)}`}</td><td><small>{s.reason||'—'}{s.updated_at?` · ${fmtDateTime(s.updated_at)}`:''}</small></td></tr>})}
    </tbody></table></div></section>
}

function Layer1({d,can,write}){
  // v2.15.243 (Platform Admin, 11 Oct 2026): scholarships come only from each provider's own pages, read through the scraper;
  // national registers and feeds (Study Australia, Australia Awards, Manaaki) are retired, so only the countries are set here
  const countries=d.countries||[]
  return <>
    <section className="m-panel" data-sl-countries><SectionTitle title="Countries" subtitle="Scholarships are found and read only for countries switched on. Amounts are kept in each country's currency."/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Country</th><th>Currency</th><th className="num">Providers</th><th className="num">Universities searched or queued</th><th className="num">Scholarships</th><th className="num">Published</th><th>Scholarships</th></tr></thead><tbody>
        {countries.map(c=><tr key={c.code} data-sl-country={c.code}><td><strong>{c.name}</strong> <small>{c.code}</small></td><td>{c.currency}</td><td className="num">{fmtNumber(c.providers)}</td><td className="num">{fmtNumber(c.universities_queued)}</td><td className="num">{fmtNumber(c.scholarships)}</td><td className="num">{fmtNumber(c.published)}</td>
          <td><span className="sl-state"><span className={`sch-st ${c.enabled?'sch-st-pub':'sch-st-held'}`}>{c.enabled?'On':'Off'}</span>{can&&<Button compact onClick={()=>write('country',{code:c.code,enabled:!c.enabled},`Switch scholarships ${c.enabled?'off':'on'} for ${c.name}?`)}>{c.enabled?'Switch off':'Switch on'}</Button>}</span>{c.enabled&&!Number(c.providers)&&<small className="sl-sub">No providers in the catalogue yet</small>}</td></tr>)}
      </tbody></table></div></section>
  </>
}

function Counts({title,obj,labels}){const e=Object.entries(obj||{}).sort((a,b)=>b[1]-a[1]);return <div className="sl-counts"><small>{title}</small>{e.length?<ul>{e.map(([k,v])=><li key={k}><span>{labels[k]||human(k)}</span><b>{fmtNumber(v)}</b></li>)}</ul>:<span className="sl-sub">None yet</span>}</div>}

const PURPOSE={sch_map:'Mapping university sites',sch_search:'Searching for a page (retired)',sch_scrape:'Reading scholarship, listing and candidate pages'}
function Credits({fc}){
  const cap=Number(fc.cap||0),used=Number(fc.used||0),reserve=Number(fc.reserve||0),left=Math.max(0,cap-used),pct=cap?Math.min(100,Math.round(used/cap*100)):100
  const state=left<=0?'All used: scholarship pages wait until the cap is raised (there is no direct read).':left<=reserve?`Close to the cap: ${fmtNumber(left)} credits left.`:'Within the cap.'
  return <section className="m-panel" data-sl-credits><SectionTitle title="Firecrawl credits for scholarships" subtitle="Every scholarship page, listing page and candidate page is read through the scraper (Firecrawl, rendered page); there is no direct read. When the cap is used up, pages wait. The cap is a setting below."/>
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

