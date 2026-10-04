// Firecrawl work (v2.15.180, Decision 253). Platform Admin, 4 Oct 2026 15:51: Firecrawl only (Growth plan), by use case,
// for universities that enrol international students, and a result report to share with Firecrawl support.
// Reads: admin_firecrawl_read(), admin_firecrawl_report(since). Writes: admin_firecrawl_write(action,args) — Platform
// Admin with a reason. Runs are carried out by the coverage-sweep worker (mode fc_run). Every limit is a setting in the
// Firecrawl panel above (Target universities, Read pages, Find pages, Runs): nothing is fixed here.
import React,{useEffect,useState}from'react'
import{RefreshCw,Copy,Download,Play,Square}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,fmtDateTime,fmtNumber}from'./ui-kit'

const errText=e=>e?.message||String(e)
const ask=t=>{const r=window.prompt(`${t}\n\nReason (kept in the log):`);return r&&r.trim().length>=4?r.trim():null}
export const USE_CASE={read_page:'Read pages',find_page:'Find pages'}
const USE_HELP={read_page:'Course-like pages of target universities that need a browser or refused a plain read. Firecrawl reads them (proxy, wait and location from the settings). Each page then goes through the identity check.',
  find_page:'Courses of target universities without a page, or whose page is not a course page. Firecrawl searches the university’s own site. A page whose title matches goes to the identity check.'}
const RUN_STATUS={running:'Running',done:'Finished',stopped:'Stopped',stopped_credit_cap:'Stopped at its credit allowance',stopped_plan_reserve:'Stopped at the plan’s reserve'}
export const OUTCOME={read_course_page:'Read: the course page',read_other_page:'Read: not this course’s page',blocked:'Still blocked',not_found:'Page gone (404)',thin:'Almost empty page',timeout:'Timed out',
  fc_error:'Firecrawl error',rate_limited:'Rate limited',robots_disallowed:'Site’s robots rules say no',no_content:'No content',error:'Error',
  found_on_provider_site:'Found on the university’s site',provider_site_no_title_match:'University’s site, title did not match',other_sites_only:'Other sites only',no_results:'No results'}
const GOOD=new Set(['read_course_page','found_on_provider_site'])
const label=o=>OUTCOME[o]||(o?.startsWith('found_not_bound_')?`Found, not used (${o.slice(16).replace(/_/g,' ')})`:o)

// The support report as Markdown, ready to paste into a ticket to Firecrawl support. Dates stay as ISO text.
export function reportMarkdown(r,org='CourseFinder'){
  if(!r)return''
  const t=r.totals||{},a=r.account||{},L=[]
  L.push(`# Firecrawl usage report — ${org}`,'',`Calls since ${r.since} (report made ${r.generated_at}).`,'')
  if(r.account)L.push(`**Account:** plan ${fmtNumber(a.plan_credits)} credits, ${fmtNumber(a.remaining)} left (period ${a.period_start} to ${a.period_end}, read ${a.observed_at}).`,'')
  L.push('## Totals','',`| Calls | Succeeded | Failed | Credits | API errors | Timeouts | Rate limited (429) | Stealth/enhanced proxy used | Median time (ms) |`,'|---|---|---|---|---|---|---|---|---|',
    `| ${t.calls??0} | ${t.succeeded??0} | ${t.failed??0} | ${t.credits??0} | ${t.api_errors??0} | ${t.timeouts??0} | ${t.rate_limited??0} | ${t.stealth_used??0} | ${t.median_ms??'—'} |`,'')
  if((r.by_endpoint||[]).length){L.push('## By endpoint','','| Endpoint | Use | Calls | Succeeded | Credits |','|---|---|---|---|---|');for(const e of r.by_endpoint)L.push(`| ${e.endpoint} | ${USE_CASE[e.use_case]||e.use_case} | ${e.calls} | ${e.succeeded} | ${e.credits} |`);L.push('')}
  if(Object.keys(r.by_outcome||{}).length){L.push('## By result','','| Result | Calls |','|---|---|');for(const[k,v]of Object.entries(r.by_outcome))L.push(`| ${label(k)} | ${v} |`);L.push('')}
  if((r.errors||[]).length){L.push('## Errors','','| Error | Calls | First | Last | Sample scrape id | Sample URL |','|---|---|---|---|---|---|');for(const e of r.errors)L.push(`| ${String(e.error).replace(/\|/g,'/')} | ${e.calls} | ${e.first_at} | ${e.last_at} | ${e.sample_scrape_id||'—'} | ${e.sample_url||'—'} |`);L.push('')}
  if((r.by_site||[]).length){L.push('## Sites with failed page reads','');for(const s of r.by_site){L.push(`### ${s.site} — ${s.failed} of ${s.calls} failed`,'',`Page statuses: ${Object.entries(s.page_statuses||{}).map(([k,v])=>`${k}: ${v}`).join(', ')||'—'}. Proxies: ${(s.proxies||[]).join(', ')||'—'}.`)
    if((s.errors||[]).length)L.push(`Errors: ${s.errors.join(' · ')}`)
    L.push('','| URL | Scrape id | HTTP | Page status | Error | At |','|---|---|---|---|---|---|');for(const x of s.samples||[])L.push(`| ${x.url} | ${x.scrape_id||'—'} | ${x.http??'—'} | ${x.page_status??'—'} | ${String(x.error||'—').replace(/\|/g,'/')} | ${x.at} |`);L.push('')}}
  return L.join('\n')
}

export default function FirecrawlWork({onError}){
  const[d,setD]=useState(null),[failed,setFailed]=useState(''),[busy,setBusy]=useState(false),[adapterFor,setAdapterFor]=useState(null)
  const load=async()=>{setFailed('');try{const{data,error}=await supabase.rpc('admin_firecrawl_read');if(error)throw error;setD(data||{})}catch(e){setFailed(errText(e))}}
  useEffect(()=>{load()},[])
  useEffect(()=>{if(!(d?.runs||[]).some(r=>r.status==='running'))return;const t=setTimeout(load,20000);return()=>clearTimeout(t)},[d])
  const write=async(action,args,question)=>{const reason=ask(question);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_firecrawl_write',{p_action:action,p_args:{...args,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(failed&&!d)return <section className="m-panel"><Empty text={`Firecrawl work could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if(!d)return <section className="m-panel"><Loading label="Loading Firecrawl work…"/></section>
  const can=Boolean(d.can_manage)&&!busy,v=d.plan?.vendor,b=d.plan?.budget||{},open=new Set((d.runs||[]).filter(r=>r.status==='running').map(r=>r.use_case))
  const targets=(d.targets||[]),inc=targets.filter(t=>t.included)
  const sum=k=>inc.reduce((a,t)=>a+Number(t[k]||0),0)
  const withAdapter=targets.filter(t=>t.adapter&&t.adapter!=='none'),done=withAdapter.filter(t=>t.adapter==='admitting'),working=withAdapter.filter(t=>t.adapter!=='admitting'),opened=adapterFor?targets.find(t=>t.provider_id===adapterFor):null
  const ADS={testing:['Testing — not admitting','warning'],admitting:['Admitting','success'],off:['Switched off','neutral']}
  return <div className="m-page-stack" data-firecrawl-work>
    <section className="m-panel" id="university-adapters" data-university-adapters><SectionTitle title="University adapters" subtitle="One adapter per university: where its course pages keep each field. Test an adapter on its confirmed pages, then switch admission on for it, or ask for an improvement."/>
      <ol className="tn-steps"><li><strong>Open</strong> a university below (or set one up).</li><li>Under <strong>Test, then admit</strong>, check the values it found against the course pages (each page link opens).</li><li>If they are right, press <strong>Admit from this adapter</strong>. If not, write what is wrong under <strong>Ask for an improvement</strong>.</li></ol>
      {done.length>0&&<div className="tn-adapter-done" data-adapters-done>{done.map(t=><details key={t.provider_id} className="tn-items" data-adapter-done={t.provider_id} open={adapterFor===t.provider_id}>
        <summary>{t.name} ({t.country}) · Adapter <strong>{t.adapter==='off'?'disabled':'enabled'}</strong> · Admission <strong>{t.adapter==='admitting'?'on':'off'}</strong> · {fmtNumber(t.intakes)} intakes, {fmtNumber(t.english)} English of {fmtNumber(t.courses)} courses</summary>
        <p className="sl-sub">Confirmed by the adapter {fmtNumber(t.adapter_confirmed)} · waiting to be read {fmtNumber(t.waiting_read)} · open requests {fmtNumber(t.requests_open)}. What it reads itself replaces held values, except values entered by hand.</p>
        <Button compact onClick={()=>setAdapterFor(adapterFor===t.provider_id?null:t.provider_id)}>{adapterFor===t.provider_id?'Close':'Work on this adapter'}</Button></details>)}</div>}
      {working.length===0?(done.length===0&&<Empty text="No university adapters yet."/>):<div className="cf-table-wrap"><table className="cf-table" data-adapter-list><thead><tr><th>University</th><th>State</th><th className="num">Confirmed by the adapter</th><th className="num">Waiting to be read</th><th className="num">Open requests</th><th></th></tr></thead><tbody>
        {working.map(t=><tr key={t.provider_id} data-adapter-row={t.provider_id} className={adapterFor===t.provider_id?'tn-sel':''}><td>{t.name}<small className="sl-sub">{t.country} · {t.domain}</small></td><td><span className={`cf-chip tone-${(ADS[t.adapter]||ADS.off)[1]}`}>{(ADS[t.adapter]||ADS.off)[0]}</span></td>
          <td className="num">{fmtNumber(t.adapter_confirmed)}</td><td className="num">{fmtNumber(t.waiting_read)}</td><td className="num">{fmtNumber(t.requests_open)}</td>
          <td><Button compact variant={adapterFor===t.provider_id?undefined:'primary'} onClick={()=>setAdapterFor(adapterFor===t.provider_id?null:t.provider_id)}>{adapterFor===t.provider_id?'Close':'Open'}</Button></td></tr>)}
      </tbody></table></div>}
      {d.can_manage&&<label className="tn-setup">Set up an adapter for <select aria-label="Set up an adapter for" value="" onChange={e=>e.target.value&&setAdapterFor(e.target.value)}><option value="">choose a university…</option>{targets.filter(t=>t.included&&(!t.adapter||t.adapter==='none')).map(t=><option key={t.provider_id} value={t.provider_id}>{t.name} ({t.country})</option>)}</select></label>}
      {opened&&<AdapterEditor key={adapterFor} providerId={adapterFor} onError={onError}/>}
      <AdapterEvaluation onPick={id=>setAdapterFor(id)} onError={onError}/>
      {d.figures_at&&<small className="sl-sub">Figures as at {fmtDateTime(d.figures_at)} (refreshed every 5 minutes).</small>}
    </section>
    <section className="m-panel"><SectionTitle title="Firecrawl work" subtitle="Firecrawl is used by use case, only for the target universities below. Every call a run makes is logged for the support report."/>
      <div className="tn-plan" data-firecrawl-plan>
        <div className="tn-plan-row">{v?<><strong>{fmtNumber(v.remaining)} of {fmtNumber(v.plan_credits)} credits left</strong><span>as Firecrawl reports it, period {fmtDateTime(v.period_start)} to {fmtDateTime(v.period_end)}, read {fmtDateTime(v.observed_at)}</span></>:<span>No reading from Firecrawl yet.</span>}
          <span>{fmtNumber(b.stop_at_remaining_units)} kept back · the platform stops Firecrawl work there</span>
          {b.allowed===false&&<span className="cf-chip tone-danger">At the reserve — Firecrawl work has stopped</span>}</div>
      </div>
      <div className="tn-starts" data-firecrawl-starts>{Object.keys(USE_CASE).map(u=><div key={u} className="tn-start"><Button compact variant="primary" disabled={!can||open.has(u)||!(d.backlog?.[u]>0)} onClick={()=>write('start',{use_case:u},`Start a Firecrawl run: ${USE_CASE[u]}? ${fmtNumber(d.backlog?.[u])} waiting. ${USE_HELP[u]} It stops at the run's credit allowance (a setting).`)}><Play size={13}/>{`${USE_CASE[u]} (${fmtNumber(d.backlog?.[u])} waiting)`}</Button><small className="sl-sub">{USE_HELP[u]}</small></div>)}</div>
      <h4 className="sl-h4">Runs</h4>
      {(d.runs||[]).length===0?<Empty text="No Firecrawl runs yet."/>:<div className="cf-table-wrap"><table className="cf-table" data-firecrawl-runs><thead><tr><th>Started</th><th>Use</th><th>Status</th><th className="num">Done</th><th className="num">Credits</th><th>Results</th><th></th></tr></thead><tbody>
        {d.runs.map(r=><tr key={r.id} data-firecrawl-run={r.id}><td>{fmtDateTime(r.created_at)}<small className="sl-sub">{r.reason}</small></td><td>{USE_CASE[r.use_case]||r.use_case}</td><td>{RUN_STATUS[r.status]||r.status}{r.last_call_at&&<small className="sl-sub">last call {fmtDateTime(r.last_call_at)}</small>}</td>
          <td className="num">{fmtNumber(r.done)} of {fmtNumber(r.items)}</td><td className="num">{fmtNumber(r.credits_used)} of {fmtNumber(r.credits_cap)}</td>
          <td><span className="tn-outcomes">{Object.entries(r.outcomes||{}).sort((a,b)=>b[1]-a[1]).map(([o,n])=><span key={o} className={`cf-chip tone-${GOOD.has(o)?'success':'neutral'}`} data-run-outcome={o}>{label(o)}: {fmtNumber(n)}</span>)}</span></td>
          <td><span className="sl-state">{can&&r.status==='running'&&<Button compact disabled={busy} onClick={()=>write('stop',{run_id:r.id},'Stop this Firecrawl run? Pages already read stay as they are.')}><Square size={12}/>Stop</Button>}
            {can&&['stopped','stopped_credit_cap','stopped_plan_reserve'].includes(r.status)&&r.done<r.items&&<Button compact disabled={busy} onClick={()=>{const add=window.prompt('Add credits to this run’s allowance (0 to keep it):','0');if(add===null)return;write('continue',{run_id:r.id,add_credits:Number(add)||0},'Continue this Firecrawl run?')}}>Continue</Button>}</span></td></tr>)}
      </tbody></table></div>}
    </section>
    <section className="m-panel" data-firecrawl-targets><SectionTitle title="Target universities" subtitle={`${inc.length} targets (${[...new Set(inc.map(t=>t.country))].map(c=>`${c} ${inc.filter(t=>t.country===c).length}`).join(', ')}). The rule is in the Target universities settings above. Add or take out a university by hand with a reason.`}/>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>University</th><th className="num">Active courses</th><th className="num">Confirmed page</th><th className="num">Page not readable</th><th className="num">No page</th><th className="num">Intakes</th><th className="num">English</th><th className="num">International fee</th><th></th></tr></thead><tbody>
        <tr className="tn-total"><td><strong>All targets</strong></td>{['courses','confirmed','unreadable','no_page','intakes','english','any_fee'].map(k=><td key={k} className="num"><strong>{fmtNumber(sum(k))}</strong></td>)}<td/></tr>
        {targets.map(t=><tr key={t.provider_id} data-firecrawl-target={t.provider_id} className={t.included?'':'tn-out'}><td>{t.name}<small className="sl-sub">{t.country} · {t.domain||'no website known'}{t.override_reason?` · by hand: ${t.override_reason}`:t.rule_match?'':' · not matched by the rule'}</small></td>
          {['courses','confirmed','unreadable','no_page','intakes','english','any_fee'].map(k=><td key={k} className="num">{fmtNumber(t[k])}</td>)}
          <td><span className="sl-state"><Button compact onClick={()=>{setAdapterFor(t.provider_id);document.getElementById('university-adapters')?.scrollIntoView({behavior:'smooth'})}}>Adapter</Button>{can&&<Button compact onClick={()=>write('target',{provider_id:t.provider_id,included:!t.included},t.included?`Take ${t.name} out of the targets? Firecrawl will not be used for it.`:`Add ${t.name} to the targets?`)}>{t.included?'Take out':'Add'}</Button>}</span></td></tr>)}
      </tbody></table></div>
      {(d.spend||[]).length>0&&<><h4 className="sl-h4">Firecrawl credits this period, by work</h4><div className="cf-table-wrap"><table className="cf-table" data-firecrawl-spend><thead><tr><th>Work</th><th className="num">Target universities</th><th className="num">Other providers</th></tr></thead><tbody>
        {[...new Set(d.spend.map(s=>s.purpose))].map(p=><tr key={p}><td>{p.replace(/_/g,' ')}</td><td className="num">{fmtNumber(d.spend.filter(s=>s.purpose===p&&s.target===true).reduce((a,s)=>a+Number(s.units),0))}</td><td className="num">{fmtNumber(d.spend.filter(s=>s.purpose===p&&s.target!==true).reduce((a,s)=>a+Number(s.units),0))}</td></tr>)}
      </tbody></table></div></>}
    </section>
    <SupportReport onError={onError}/>
  </div>
}

// What each target university needs next for data admission (Platform Admin 22:43: learn from the Flinders adapter).
const NEXT={find_pages:['Find pages first','warning','Many courses have no page yet. Run Find pages (Firecrawl search on the university site).'],
  adapter_page_data:['Adapter for page data','warning','Many pages cannot be read: the course data is in the page itself or needs a browser. Set up an adapter for its page data.'],
  adapter_intakes:['Adapter for start dates','warning','Pages are confirmed but start dates are mostly missing. Set up an adapter with a start-date pattern.'],
  adapter_english:['Adapter for English','warning','Pages are confirmed but English is mostly missing. Set up an adapter with an English pattern, or a central English policy.'],
  admit_as_is:['Admitted as it is','success','The general reader finds the fields. No adapter needed now.'],
  admitting:['Adapter admitting','success','Its adapter is switched on and admitting.']}
export function AdapterEvaluation({onPick,onError}){
  const[r,setR]=useState(null)
  useEffect(()=>{(async()=>{try{const{data,error}=await supabase.rpc('admin_adapter_evaluation');if(error)throw error;setR(data||{})}catch(e){onError?.(errText(e))}})()},[])
  if(!r)return null
  const u=r.universities||[],st=r.settings||{}
  return <details className="tn-items" data-adapter-evaluation open><summary>What each university needs next ({Object.entries(NEXT).map(([k,v])=>`${v[0]} ${u.filter(x=>x.next===k).length}`).join(' · ')})</summary>
    <p className="sl-sub">Rules learnt from the Flinders adapter: no page on {fmtNumber(st.no_page_share*100)}% or more of courses means find pages first, unreadable pages on {fmtNumber(st.unreadable_share*100)}% or more means an adapter for the page data, and start dates or English on under {fmtNumber(st.field_share*100)}% of confirmed pages means an adapter with patterns. The shares are settings (Firecrawl, Adapter evaluation).</p>
    <div className="cf-table-wrap"><table className="cf-table" data-adapter-eval><thead><tr><th>University</th><th className="num">Courses</th><th className="num">No page</th><th className="num">Not readable</th><th className="num">Confirmed</th><th className="num">Intakes</th><th className="num">English</th><th>Next step</th><th></th></tr></thead><tbody>
      {u.map(x=>{const n=NEXT[x.next]||[x.next,'neutral',''];return <tr key={x.provider_id} data-eval-row={x.provider_id}><td>{x.name}<small className="sl-sub">{x.country}</small></td><td className="num">{fmtNumber(x.courses)}</td><td className="num">{fmtNumber(x.no_page)}</td><td className="num">{fmtNumber(x.unreadable)}</td><td className="num">{fmtNumber(x.confirmed)}</td><td className="num">{fmtNumber(x.intakes)}</td><td className="num">{fmtNumber(x.english)}</td>
        <td><span className={`cf-chip tone-${n[1]}`}>{n[0]}</span><small className="sl-sub">{n[2]}</small></td><td>{x.next.startsWith('adapter_')&&<Button compact onClick={()=>onPick(x.provider_id)}>{x.adapter==='none'?'Set up adapter':'Adapter'}</Button>}</td></tr>})}
    </tbody></table></div>
    {r.figures_at&&<small className="sl-sub">Figures as at {fmtDateTime(r.figures_at)}.</small>}</details>
}

const SINCE={day:['Last 24 hours',1],week:['Last 7 days',7],month:['Last 30 days',30]}
function SupportReport({onError}){
  const[since,setSince]=useState('week'),[r,setR]=useState(null),[busy,setBusy]=useState(false),[copied,setCopied]=useState(false)
  const load=async(s=since)=>{setBusy(true);try{const from=new Date(Date.now()-SINCE[s][1]*86400000).toISOString();const{data,error}=await supabase.rpc('admin_firecrawl_report',{p_since:from});if(error)throw error;setR(data||{})}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[since])
  const md=reportMarkdown(r)
  const copy=async()=>{try{await navigator.clipboard.writeText(md);setCopied(true);setTimeout(()=>setCopied(false),2500)}catch(e){onError?.(errText(e))}}
  const download=()=>{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([md],{type:'text/markdown'}));a.download=`firecrawl-report-${String(r?.generated_at||'').slice(0,10)}.md`;a.click();URL.revokeObjectURL(a.href)}
  const t=r?.totals||{}
  return <section className="m-panel" data-firecrawl-report><SectionTitle title="Report for Firecrawl support" subtitle="Every Firecrawl call made by a run: what was asked, what came back, the scrape id, credits and proxy used. Copy or download it and attach it to a ticket."/>
    <div className="tn-starts"><select aria-label="Report period" value={since} onChange={e=>setSince(e.target.value)}>{Object.entries(SINCE).map(([k,[l]])=><option key={k} value={k}>{l}</option>)}</select>
      <Button compact disabled={busy||!r} onClick={copy}><Copy size={13}/>{copied?'Copied':'Copy report'}</Button><Button compact disabled={busy||!r} onClick={download}><Download size={13}/>Download (.md)</Button><Button compact disabled={busy} onClick={()=>load()}><RefreshCw size={13}/>Refresh</Button></div>
    {!r?<Loading label="Loading the report…"/>:<>
      <div className="cf-table-wrap"><table className="cf-table" data-report-totals><thead><tr><th className="num">Calls</th><th className="num">Succeeded</th><th className="num">Failed</th><th className="num">Credits</th><th className="num">Timeouts</th><th className="num">Rate limited</th><th className="num">Stealth used</th><th className="num">Median ms</th></tr></thead><tbody>
        <tr><td className="num">{fmtNumber(t.calls)}</td><td className="num">{fmtNumber(t.succeeded)}</td><td className="num">{fmtNumber(t.failed)}</td><td className="num">{fmtNumber(t.credits)}</td><td className="num">{fmtNumber(t.timeouts)}</td><td className="num">{fmtNumber(t.rate_limited)}</td><td className="num">{fmtNumber(t.stealth_used)}</td><td className="num">{fmtNumber(t.median_ms)}</td></tr></tbody></table></div>
      {(r.errors||[]).length>0&&<div className="cf-table-wrap"><table className="cf-table" data-report-errors><thead><tr><th>Error</th><th className="num">Calls</th><th>Last</th><th>Sample scrape id</th></tr></thead><tbody>
        {r.errors.map(e=><tr key={e.error}><td>{e.error}<small className="sl-sub">{e.sample_url}</small></td><td className="num">{fmtNumber(e.calls)}</td><td>{fmtDateTime(e.last_at)}</td><td><code>{e.sample_scrape_id||'—'}</code></td></tr>)}</tbody></table></div>}
      {(r.by_site||[]).length>0&&<details className="tn-items"><summary>Sites with failed page reads ({r.by_site.length})</summary><div className="cf-table-wrap"><table className="cf-table" data-report-sites><thead><tr><th>Site</th><th className="num">Failed</th><th>Page statuses</th><th>Proxies</th></tr></thead><tbody>
        {r.by_site.map(s=><tr key={s.site}><td>{s.site}</td><td className="num">{fmtNumber(s.failed)} of {fmtNumber(s.calls)}</td><td>{Object.entries(s.page_statuses||{}).map(([k,v])=>`${k}: ${v}`).join(', ')}</td><td>{(s.proxies||[]).join(', ')||'—'}</td></tr>)}</tbody></table></div></details>}
      {(t.calls||0)===0&&<Empty text="No Firecrawl calls logged in this period."/>}
    </>}
  </section>
}

// ---- university adapter (field mappings), one university at a time ---------------------------------------------------
const AD_FIELDS=[['title_strip','Taken off page titles','A pattern (regular expression) removed from the page title and heading before comparing, for example ^[A-Z]{2,8}\\s+ for a course code in front.'],
  ['course_title_strip','Taken off catalogue titles','A pattern removed from our course title before comparing, for example \\s*\\(level \\d+\\)$.'],
  ['json_source','Page data script','The id of a <script> holding the page’s data as JSON, for example __NEXT_DATA__ (CourseLoop handbooks). Empty if none.']]
export function AdapterEditor({providerId,onError}){
  const[d,setD]=useState(null),[a,setA]=useState(null),[paths,setPaths]=useState('{}'),[sections,setSections]=useState('{}'),[patterns,setPatterns]=useState('{}'),[pick,setPick]=useState('{}'),[terms,setTerms]=useState('{}'),[busy,setBusy]=useState(false),[err,setErr]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_uni_adapter_read',{p_provider_id:providerId});if(error)throw error;setD(data||{});if(!a){const x=data?.adapter||{};setA({enabled:Boolean(x.enabled),title_strip:x.title_strip||'',course_title_strip:x.course_title_strip||'',json_source:x.json_source||'',section_chars:x.section_chars||2000,notes:x.notes||''});setPaths(JSON.stringify(x.json_paths||{},null,2));setSections(JSON.stringify(x.sections||{},null,2));setPatterns(JSON.stringify(x.patterns||{},null,2));setPick(JSON.stringify(x.pick||{},null,2));setTerms(JSON.stringify(x.term_months||{},null,2))}}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[providerId])
  useEffect(()=>{const p=(d?.previews||[])[0];if(!p||p.done_at)return;const t=setTimeout(load,6000);return()=>clearTimeout(t)},[d])
  const body=()=>{let jp,sc,pt,pk,tm;try{jp=JSON.parse(paths||'{}');sc=JSON.parse(sections||'{}');pt=JSON.parse(patterns||'{}');pk=JSON.parse(pick||'{}');tm=JSON.parse(terms||'{}')}catch{throw new Error('JSON paths, headings, patterns, pick and term months must be valid JSON objects')}return{...a,json_paths:jp,sections:sc,patterns:pt,pick:pk,term_months:tm}}
  const act=async(action,q)=>{setErr('');let adapter;try{adapter=body()}catch(e){setErr(e.message);return}const reason=ask(q);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_uni_adapter_write',{p_action:action,p_args:{provider_id:providerId,adapter,reason}});if(error)throw error;await load()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(!d||!a)return <div className="tn-adapter"><Loading label="Loading the adapter…"/></div>
  const can=Boolean(d.can_manage)&&!busy,prev=(d.previews||[])[0],res=prev?.result
  return <div className="tn-adapter" data-adapter-editor={providerId}><h4 className="sl-h4">Adapter: {d.provider?.name}</h4>
    <AdapterReview providerId={providerId} can={Boolean(d.can_manage)} onError={onError}/>
    <AdapterBuilder providerId={providerId} onError={onError} onUse={x=>{setA({...a,json_source:x.json_source||a.json_source||''});setPaths(JSON.stringify({...JSON.parse(paths||'{}'),...(x.json_paths||{})},null,2));setPatterns(JSON.stringify({...JSON.parse(patterns||'{}'),...(x.patterns||{})},null,2));setPick(JSON.stringify({...JSON.parse(pick||'{}'),...(x.pick||{})},null,2));const el=document.querySelector(`[data-adapter-editor="${providerId}"] [data-adapter-settings]`);if(el)el.open=true}}/>
    <details className="tn-items" data-adapter-settings><summary>Adapter settings (where this university keeps each field)</summary>
    <p className="sl-sub">How this university names and lays out its course pages. Change them, press Preview to try them on stored pages, then Save and Apply. Pages now: {Object.entries(d.pages||{}).map(([k,v])=>`${k.replace(/_/g,' ')} ${fmtNumber(v)}`).join(' · ')}</p>
    <div className="tn-adapter-grid">
      <label><input type="checkbox" checked={a.enabled} disabled={!can} onChange={e=>setA({...a,enabled:e.target.checked})}/> Switched on (the reader and Read pages use it)</label>
      {AD_FIELDS.map(([k,l,h])=><label key={k}><strong>{l}</strong><input aria-label={l} value={a[k]} disabled={!can} onChange={e=>setA({...a,[k]:e.target.value})}/><small className="sl-sub">{h}</small></label>)}
      <label><strong>Where each field is in the page data</strong><textarea aria-label="JSON paths" rows={6} value={paths} disabled={!can} onChange={e=>setPaths(e.target.value)}/><small className="sl-sub">Field to dotted path: title, code (CRICOS or programme code), ielts_overall, ielts_min_band, english, intakes, fee, duration. * takes every item of a list.</small></label>
      <label><strong>Where each field is on the page</strong><textarea aria-label="Headings" rows={4} value={sections} disabled={!can} onChange={e=>setSections(e.target.value)}/><small className="sl-sub">Field to heading pattern, for example {'{"intakes":"(start dates|intakes)"}'}. The field is read from the text after the heading.</small></label>
      <label><strong>Patterns on the page text</strong><textarea aria-label="Patterns" rows={6} value={patterns} disabled={!can} onChange={e=>setPatterns(e.target.value)}/><small className="sl-sub">Field to pattern; the bracketed part is the value. Fields: intakes, fee, ielts_overall, campus, mode, duration, study_level, student_type, not_admitting, aqf_level. A value found this way is marked as the adapter’s own reading; intakes and English from it are admitted only with admission switched on. Tuition is never admitted from pages. Write “any text” as (?:.|\n) with a limit up to 250, never (.|\s) or [\s\S]: overlapping choices can stall the reader on long pages.</small></label>
      <label><strong>Which match to take</strong><textarea aria-label="Pick" rows={2} value={pick} disabled={!can} onChange={e=>setPick(e.target.value)}/><small className="sl-sub">Field to first, last or all, for pages that print a field more than once (domestic and international views). First is used when a field is not listed.</small></label>
      <label><strong>Term names to months</strong><textarea aria-label="Term months" rows={3} value={terms} disabled={!can} onChange={e=>setTerms(e.target.value)}/><small className="sl-sub">The university’s own published mapping, for example {'{"Semester 1":"February","Spring Session":"July"}'} from its key-dates page. A term name found by the intakes pattern becomes these months.</small></label>
      <label><strong>Notes</strong><input aria-label="Notes" value={a.notes} disabled={!can} onChange={e=>setA({...a,notes:e.target.value})}/></label>
    </div>
    {err&&<p className="cf-chip tone-danger">{err}</p>}
    {d.can_manage&&<div className="tn-starts"><Button compact disabled={!can} onClick={()=>act('preview','Try this adapter on up to 8 stored pages of this university? No Firecrawl credits, nothing changed.')}>Preview on stored pages</Button>
      <Button compact variant="primary" disabled={!can} onClick={()=>act('save','Save this adapter?')}>Save</Button>
      <Button compact disabled={!can||!d.adapter?.enabled} onClick={()=>act('apply','Apply the saved adapter to this university’s stored pages and read its waiting pages again? Every change is logged. Nothing is admitted unless the identity basis is allowed for the country.')}>Apply</Button></div>}
    {prev&&<div data-adapter-preview><h4 className="sl-h4">Preview {fmtDateTime(prev.created_at)}{prev.done_at?'':' (running…)'}</h4>
      {res&&<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Course</th><th>Was</th><th>Adapter</th><th>Page</th><th>Found</th></tr></thead><tbody>
        {(res.pages||[]).map((x,i)=><tr key={i}><td>{x.course}<small className="sl-sub">{x.code} · {x.url}</small></td><td>{(x.was||'').replace(/_/g,' ')}{x.identity_before?` (${x.identity_before})`:''}</td>
          <td>{x.identity?<span className="cf-chip tone-success">{x.identity}</span>:<span className="cf-chip tone-neutral">no match</span>}<small className="sl-sub">{x.how||''}{x.json_found===false&&a.json_source?' · no page data':''}</small></td>
          <td><small className="sl-sub">{x.page?.title||'—'} · {x.page?.h1||'—'} · {fmtNumber(x.page?.text_chars)} characters{(x.page?.scripts||[]).length?` · scripts: ${x.page.scripts.map(s=>s.id||s.type).join(', ')}`:''}</small></td>
          <td><small className="sl-sub">{x.found?`intakes ${(x.found.intakes||[]).join(', ')||'—'}${x.found.intakes_by==='adapter'?' (pattern)':''} · IELTS ${x.found.english?.ielts_overall??'—'} · fee ${x.found.fee??'—'}`:x.error||'—'}</small>{x.found?.extra&&Object.keys(x.found.extra).length>0&&<small className="sl-sub" data-preview-extra>{Object.entries(x.found.extra).map(([k,v])=>`${k.replace(/_/g,' ')}: ${v}`).join(' · ')}</small>}</td></tr>)}
      </tbody></table></div>}
      {res?.json_shape&&<details className="tn-items"><summary>Page data paths ({res.json_shape.length})</summary><pre className="tn-pre">{res.json_shape.join('\n')}</pre></details>}
    </div>}
    </details>
    {(d.applied||[]).length>0&&<p className="sl-sub" data-adapter-applied>Applied: {d.applied.map(x=>`${x.before==='identity_mismatch'?'refused pages confirmed':'fields added'} (${x.identity}) ${fmtNumber(x.n)}`).join(' · ')}</p>}
  </div>
}

// Decision 254 (Platform Admin 23:41): the visual adapter builder. Capture sample pages with Firecrawl (screenshot, text
// blocks, page-data values), mark which block or value holds each attribute, add comments, and ask the pinned preferred
// model for a proposal. The proposal only fills the adapter settings below: Save, Apply and admission stay separate.
const B_FIELDS=['intakes','fee','ielts_overall','english','campus','mode','duration','study_level','student_type','not_admitting','aqf_level','title','code']
export function AdapterBuilder({providerId,onUse,onError}){
  const[r,setR]=useState(null),[busy,setBusy]=useState(false),[marks,setMarks]=useState([]),[comments,setComments]=useState(''),[tab,setTab]=useState(0)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_adapter_builder',{p_action:'read',p_args:{provider_id:providerId}});if(error)throw error;setR(data||{});const dr=(data?.drafts||[])[0];if(dr&&!marks.length){setMarks(dr.marks||[]);setComments(dr.comments||'')}}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[providerId])
  const dr=(r?.drafts||[])[0]
  useEffect(()=>{if(!dr||!['capturing','proposing'].includes(dr.status))return;const t=setTimeout(load,5000);return()=>clearTimeout(t)},[r])
  const act=async(action,args,q)=>{const reason=q?ask(q):'builder';if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_adapter_builder',{p_action:action,p_args:{provider_id:providerId,...args,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!r)return null
  const b=r.budget||{},can=Boolean(r.can_manage)&&!busy,caps=dr?.captures||[],cap=caps[tab],last=(dr?.proposals||[]).slice(-1)[0]
  const markOf=(kind,ref)=>marks.find(m=>m.sample===tab&&m.kind===kind&&m.ref===ref)?.field||''
  const setMark=(kind,ref,value,field)=>setMarks(ms=>[...ms.filter(m=>!(m.sample===tab&&m.kind===kind&&m.ref===ref)),...(field?[{sample:tab,kind,ref,value:String(value||'').slice(0,160),field}]:[])])
  const pick=(kind,ref,value)=><select aria-label={`Attribute for ${ref}`} value={markOf(kind,ref)} disabled={!can} onChange={e=>setMark(kind,ref,value,e.target.value)}><option value="">—</option>{B_FIELDS.map(f=><option key={f} value={f}>{f.replace(/_/g,' ')}</option>)}</select>
  return <details className="tn-items" data-adapter-builder open={Boolean(dr)}><summary>Visual adapter builder {dr?`· ${dr.status}`:''} · AI today US$ {Number(b.used_usd||0).toFixed(3)} of {b.limit_usd} · {b.proposals||0} of {b.limit_proposals} proposals · model {b.model}</summary>
    <ol className="tn-steps"><li><strong>Capture</strong> sample pages (Firecrawl, about 1 credit each).</li><li><strong>Mark</strong> the text block or page-data value that holds each attribute, and add comments.</li><li><strong>Propose</strong>: the pinned model suggests the settings and they are tried on the samples.</li><li><strong>Use this proposal</strong> fills the settings below. Then Preview, Save and Apply as usual.</li></ol>
    {can&&<div className="tn-starts"><Button compact disabled={!can||['capturing','proposing'].includes(dr?.status)} onClick={()=>act('start',{},'Capture sample pages of this university with Firecrawl (screenshot and page)? About 1 credit a page.')}>{dr?'Capture new samples':'Capture sample pages'}</Button>
      {dr&&caps.length>0&&<Button compact disabled={!can} onClick={()=>act('marks',{draft_id:dr.id,marks,comments},null)}>Keep marks</Button>}
      {dr&&caps.length>0&&<Button compact variant="primary" disabled={!can||dr.status==='proposing'} onClick={()=>act('propose',{draft_id:dr.id,marks,comments},null)}>Ask for a proposal</Button>}</div>}
    {dr?.status==='capturing'&&<Loading label="Capturing the sample pages…"/>}
    {caps.length>0&&<><div className="tn-tabs" data-builder-samples>{caps.map((c,i)=><Button key={i} compact variant={i===tab?'primary':undefined} onClick={()=>setTab(i)}>{c.kind||`Sample ${i+1}`}: {c.course}</Button>)}</div>
      {cap&&(cap.error?<p className="cf-chip tone-danger">{cap.error}</p>:<div className="tn-builder" data-builder-sample={tab}>
        <div className="tn-shot">{cap.screenshot_url?<a href={cap.screenshot_url} target="_blank" rel="noreferrer"><img src={cap.screenshot_url} alt={`Screenshot of ${cap.course}`} loading="lazy"/></a>:<small className="sl-sub">No screenshot.</small>}<small className="sl-sub"><a href={cap.url} target="_blank" rel="noreferrer">{cap.url}</a> · {fmtNumber(cap.credits)} credits</small></div>
        <div className="tn-blocks"><h5>Text blocks</h5><ul className="tn-list" data-builder-blocks>{(cap.blocks||[]).map(x=><li key={x.id}><strong>[{x.id}] {x.heading}</strong> {pick('block',String(x.id),x.text)}<small className="sl-sub">{x.text}</small></li>)}</ul>
          {(cap.leaves||[]).length>0&&<><h5>Page data ({cap.json_source})</h5><ul className="tn-list" data-builder-leaves>{cap.leaves.map(x=><li key={x.path}><code>{x.path}</code> {pick('json',x.path,x.value)}<small className="sl-sub">{x.value}</small></li>)}</ul></>}</div></div>)}
      <label><strong>Comments for the model</strong><textarea aria-label="Comments for the model" rows={3} value={comments} disabled={!can} placeholder="For example: start dates are the months under Start dates in the international view" onChange={e=>setComments(e.target.value)}/></label></>}
    {dr?.status==='proposing'&&<Loading label="The model is proposing settings…"/>}
    {last&&<div data-builder-proposal><h4 className="sl-h4">Proposal {fmtDateTime(last.at)} · {last.model} · US$ {Number(last.cost||0).toFixed(4)}</h4>
      {last.kind==='error'?<p className="cf-chip tone-danger">{last.error}</p>:<>
        <p className="sl-sub">{last.reason}</p>{(last.dropped||[]).length>0&&<p className="cf-chip tone-warning">Left out by the rules: {last.dropped.join(' · ')}</p>}
        <div className="cf-table-wrap"><table className="cf-table" data-builder-output><thead><tr><th>Sample</th><th>Confirmed by</th><th>Intakes</th><th>Fee</th><th>IELTS</th><th>Other fields</th></tr></thead><tbody>
          {(last.output||[]).map((o,i)=><tr key={i}><td>{o.course}<small className="sl-sub">{o.code}</small></td><td>{o.identity||'—'}</td><td>{(o.intakes||[]).join(', ')||'—'}</td><td>{o.fee!=null?fmtNumber(o.fee):'—'}{o.fee_year?` (${o.fee_year})`:''}</td><td>{o.ielts??'—'}</td><td><small className="sl-sub">{Object.entries(o.extra||{}).map(([k,v])=>`${k.replace(/_/g,' ')}: ${v}`).join(' · ')||'—'}</small></td></tr>)}
        </tbody></table></div>
        <details><summary>Proposed settings</summary><pre className="tn-pre">{JSON.stringify(last.adapter,null,2)}</pre></details>
        {can&&<Button compact variant="primary" onClick={()=>onUse(last.adapter||{})}>Use this proposal</Button>}</>}</div>}
  </details>
}

// Test before admitting, then switch admission on; ask for improvements (Decision 253 amended, Platform Admin 17:19).
// Admission by field and course exclusions (Decision 254, Platform Admin 5 Oct 05:50).
const ADMIT_FIELDS=[['intakes','Intakes'],['english','English (IELTS)'],['fee','Fees']]
const ADMIT_LABEL=Object.fromEntries(ADMIT_FIELDS)
export function AdapterReview({providerId,can,onError}){
  const[r,setR]=useState(null),[req,setReq]=useState(''),[busy,setBusy]=useState(false)
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_uni_adapter_review',{p_provider_id:providerId});if(error)throw error;setR(data||{})}catch(e){onError?.(errText(e))}}
  useEffect(()=>{load()},[providerId])
  const control=async(action,args,q)=>{const reason=q?ask(q):'request';if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_uni_adapter_control',{p_action:action,p_args:{provider_id:providerId,...args,reason}});if(error)throw error;if(action==='request')setReq('');await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!r)return null
  const on=Boolean(r.admit?.on),fields=r.admit?.fields||ADMIT_FIELDS.map(([k])=>k)
  return <div className="tn-adapter-review" data-adapter-review={providerId}>
    <h4 className="sl-h4">Test, then admit</h4>
    <p className="sl-sub">{fmtNumber(r.confirmed_total)} pages confirmed by this adapter. Check the values below against the pages. Nothing this adapter confirms is admitted until admission is switched on here (the country rules allow adapter identities).</p>
    <div className="tn-plan-row" data-adapter-admit><span className={`cf-chip tone-${on?'success':'warning'}`}>{on?'Admitting what this adapter confirms':'Not admitting yet'}</span>
      {r.admit?.reason&&<small className="sl-sub">{r.admit.reason} · {fmtDateTime(r.admit.changed_at)}</small>}
      {can&&<Button compact variant={on?undefined:'primary'} disabled={busy} onClick={()=>control('admit',{admit:!on},on?'Stop admitting what this adapter confirms? Values already admitted stay.':'Admit what this adapter confirms (the fields ticked below) through the existing admission rules?')}>{on?'Stop admitting':'Admit from this adapter'}</Button>}</div>
    <div className="tn-plan-row" data-adapter-admit-fields><small className="sl-sub">Fields admitted when admission is on:</small>
      {ADMIT_FIELDS.map(([k,label])=><label key={k} className="tn-check"><input type="checkbox" aria-label={`Admit ${label}`} checked={fields.includes(k)} disabled={!can||busy}
        onChange={e=>{const next=e.target.checked?[...fields,k]:fields.filter(x=>x!==k);control('admit',{admit:on,fields:next},`${e.target.checked?'Admit':'Stop admitting'} ${label.toLowerCase()} from this adapter? Values already admitted stay.`)}}/> {label}</label>)}</div>
    {(r.exclusions||[]).length>0&&<details className="tn-items" data-adapter-exclusions><summary>Courses excluded from admission ({fmtNumber(r.exclusions.length)})</summary>
      <ul className="tn-list">{r.exclusions.map((x,i)=><li key={i}><span className="cf-chip tone-warning">{ADMIT_LABEL[x.field]||x.field}</span> {x.course} <small className="sl-sub">{x.code} · {x.reason} · {fmtDateTime(x.set_at)}</small>
        {can&&<Button compact disabled={busy} onClick={()=>control('exclude',{course_id:x.course_id,field:x.field,exclude:false},`Admit ${(ADMIT_LABEL[x.field]||x.field).toLowerCase()} for ${x.course} again?`)}>Stop excluding</Button>}</li>)}</ul></details>}
    {(r.confirmed||[]).length>0&&<details className="tn-items" open><summary>What it would admit (latest {r.confirmed.length})</summary><div className="cf-table-wrap"><table className="cf-table" data-adapter-confirmed><thead><tr><th>Course</th><th>How</th><th>Intakes</th><th>IELTS</th><th>Admitted</th></tr></thead><tbody>
      {r.confirmed.map((x,i)=><tr key={i}><td>{x.course}<small className="sl-sub">{x.code} · <a href={x.url} target="_blank" rel="noreferrer">{x.url}</a></small></td><td>{x.identity}</td><td>{(x.intakes||[]).join(', ')||'—'}</td><td>{x.ielts??'—'}{x.english_context&&<small className="sl-sub">{x.english_context}</small>}</td><td>{x.link_admitted?'link':''}{x.english_admitted?' English':''}{!x.link_admitted&&!x.english_admitted?'—':''}</td></tr>)}
    </tbody></table></div></details>}
    {(r.readings||[]).length>0&&<details className="tn-items" open><summary>What it read on pages confirmed by CRICOS code ({fmtNumber(r.readings_total)} pages, intakes on {fmtNumber(r.intakes_by_adapter)}, latest {r.readings.length})</summary>
      <p className="sl-sub">Values marked “pattern” are the adapter’s own reading. They are admitted only with admission switched on above, for the fields ticked, and never for an excluded course. Location, mode, duration and level are shown for checking and are not admitted. Use Exclude on a row whose reading is wrong.</p>
      <div className="cf-table-wrap"><table className="cf-table" data-adapter-readings><thead><tr><th>Course</th><th>Intakes</th><th>Held now</th><th>Fee</th><th>Other fields</th>{can&&<th>Exclude</th>}</tr></thead><tbody>
      {r.readings.map((x,i)=><tr key={i}><td>{x.course}<small className="sl-sub">{x.code} · <a href={x.url} target="_blank" rel="noreferrer">{x.url}</a></small></td>
        <td>{(x.intakes||[]).join(', ')||'—'}{x.intakes_by==='adapter'&&<span className="cf-chip tone-neutral">pattern</span>}{x.intake_context&&<small className="sl-sub">{x.intake_context}</small>}</td>
        <td>{(x.intakes_now||[]).join(', ')||'—'}</td><td>{x.fee!=null?fmtNumber(x.fee):'—'}{x.fee_by==='adapter'&&<span className="cf-chip tone-neutral">pattern</span>}</td>
        <td><small className="sl-sub">{Object.entries(x.extra||{}).map(([k,v])=>`${k.replace(/_/g,' ')}: ${v}`).join(' · ')||'—'}</small></td>
        {can&&<td>{ADMIT_FIELDS.map(([k,label])=><Button key={k} compact disabled={busy} aria-label={`Exclude ${label} for ${x.course}`} onClick={()=>control('exclude',{url:x.url,field:k,exclude:true},`Exclude ${label.toLowerCase()} for ${x.course} from admission? Give the reason (kept in the log).`)}>{label}</Button>)}</td>}</tr>)}
    </tbody></table></div></details>}
    <h4 className="sl-h4">Ask for an improvement</h4>
    {can&&<div className="tn-request"><textarea aria-label="Improvement request" rows={2} value={req} placeholder="For example: intakes are under 'Start dates', IELTS is in the entry requirements tab" onChange={e=>setReq(e.target.value)}/>
      <Button compact disabled={busy||req.trim().length<4} onClick={()=>control('request',{request:req.trim()})}>Send request</Button></div>}
    {(r.requests||[]).length>0&&<ul className="tn-list" data-adapter-requests>{r.requests.map(x=><li key={x.id}><span className={`cf-chip tone-${x.status==='open'?'warning':x.status==='done'?'success':'neutral'}`}>{x.status}</span> {x.request} <small className="sl-sub">{fmtDateTime(x.requested_at)}{x.answer?` · ${x.answer}`:''}</small>
      {can&&x.status==='open'&&<Button compact onClick={()=>{const answer=window.prompt('Note (optional):','');if(answer===null)return;control('answer',{id:x.id,status:'done',answer},null)}}>Mark done</Button>}</li>)}</ul>}
  </div>
}
