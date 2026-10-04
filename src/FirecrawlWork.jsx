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
  const[d,setD]=useState(null),[failed,setFailed]=useState(''),[busy,setBusy]=useState(false)
  const load=async()=>{setFailed('');try{const{data,error}=await supabase.rpc('admin_firecrawl_read');if(error)throw error;setD(data||{})}catch(e){setFailed(errText(e))}}
  useEffect(()=>{load()},[])
  useEffect(()=>{if(!(d?.runs||[]).some(r=>r.status==='running'))return;const t=setTimeout(load,20000);return()=>clearTimeout(t)},[d])
  const write=async(action,args,question)=>{const reason=ask(question);if(!reason)return;setBusy(true);try{const{error}=await supabase.rpc('admin_firecrawl_write',{p_action:action,p_args:{...args,reason}});if(error)throw error;await load()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(failed&&!d)return <section className="m-panel"><Empty text={`Firecrawl work could not be loaded: ${failed}`}/><Button compact onClick={load}><RefreshCw size={14}/>Try again</Button></section>
  if(!d)return <section className="m-panel"><Loading label="Loading Firecrawl work…"/></section>
  const can=Boolean(d.can_manage)&&!busy,v=d.plan?.vendor,b=d.plan?.budget||{},open=new Set((d.runs||[]).filter(r=>r.status==='running').map(r=>r.use_case))
  const targets=(d.targets||[]),inc=targets.filter(t=>t.included)
  const sum=k=>inc.reduce((a,t)=>a+Number(t[k]||0),0)
  return <div className="m-page-stack" data-firecrawl-work>
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
          <td>{can&&<Button compact onClick={()=>write('target',{provider_id:t.provider_id,included:!t.included},t.included?`Take ${t.name} out of the targets? Firecrawl will not be used for it.`:`Add ${t.name} to the targets?`)}>{t.included?'Take out':'Add'}</Button>}</td></tr>)}
      </tbody></table></div>
      {(d.spend||[]).length>0&&<><h4 className="sl-h4">Firecrawl credits this period, by work</h4><div className="cf-table-wrap"><table className="cf-table" data-firecrawl-spend><thead><tr><th>Work</th><th className="num">Target universities</th><th className="num">Other providers</th></tr></thead><tbody>
        {[...new Set(d.spend.map(s=>s.purpose))].map(p=><tr key={p}><td>{p.replace(/_/g,' ')}</td><td className="num">{fmtNumber(d.spend.filter(s=>s.purpose===p&&s.target===true).reduce((a,s)=>a+Number(s.units),0))}</td><td className="num">{fmtNumber(d.spend.filter(s=>s.purpose===p&&s.target!==true).reduce((a,s)=>a+Number(s.units),0))}</td></tr>)}
      </tbody></table></div></>}
    </section>
    <SupportReport onError={onError}/>
  </div>
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
