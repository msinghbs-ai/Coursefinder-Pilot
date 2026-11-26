// CF-247 s1283 (SS-Programme-Control "Complete job and lane monitoring UI", 26 Nov 2026 22:51 AEDT; backend s1176, Pilot PR 1693):
// the PIM job, lane, rollup-target and admission-rule monitoring contract, drawn on the two existing screens. No new page, tab or dashboard.
//   Data Delivery: <JobsSummary> (states, counts by component type, attention items, snapshot freshness) from `pim.operations`, replacing the
//     138-row workers table. The full list opens on Scheduled jobs.
//   Scheduled jobs › Automations: <JobsMonitor> reads `public.admin_pim_jobs_v1` (Curator and above; the snapshot the background refresh keeps):
//     every component with filters, search, pagination and a detail drill-down.
// Every state, reason, finding and outcome class is the backend's own word (security.data_delivery_jobs_v1, security.pim_outcome_class_v1); this file
// only orders, filters and names the component type. A figure the backend does not record is shown as Not recorded, never as 0.
import React,{useEffect,useMemo,useState}from'react'
import{StatusChip,fmtDateTime,fmtNumber,fmtRelative,Pager,Loading}from'./ui-kit'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{usePageSearchEntries}from'./PageSearch'
import'./pim-jobs.css'

const has=v=>v!=null&&v!==''&&Number.isFinite(Number(v))
const word=s=>{const t=String(s||'').replaceAll('_',' ').trim();return t?t[0].toUpperCase()+t.slice(1):''}
// Presentation only: severity order and tone of the backend's states. A state the backend adds later is listed after these, with a neutral tone.
const STATE_ORDER=['degraded','held','shadow','idle','active','retired']
const STATE_TONE={degraded:'danger',held:'warning',shadow:'info',idle:'neutral',active:'success',retired:'neutral'}
const OUTCOMES=['productive','empty','held','failed','deferred','unmeasured']
const OUTCOME_TONE={productive:'success',empty:'neutral',held:'warning',failed:'danger',deferred:'info',unmeasured:'neutral'}
const TYPE_LABEL={cron:'Scheduled job',lane:'Lane',rollup:'Rollup target',rule:'Admission rule'}
const typeLabel=c=>c?.component==='lane'&&c?.kind?`${word(String(c.kind).replace(/_lane$/,''))} lane`:TYPE_LABEL[c?.component]||word(c?.component)
const rank=s=>{const i=STATE_ORDER.indexOf(s);return i<0?STATE_ORDER.length:i}
const nameOf=c=>c?.name||c?.code||(c?.jobid!=null?`Job ${c.jobid}`:'Unnamed component')
const keyOf=c=>`${c?.component}:${c?.jobid??c?.code??c?.name}`
const stateChip=s=><StatusChip tone={STATE_TONE[s]||'neutral'} label={word(s)||'Unknown'}/>
const when=iso=>iso?<>{fmtDateTime(iso)}<small>{fmtRelative(iso)}</small></>:<em className="pjm-nr">Not recorded</em>
const inText=iso=>{const s=Math.round((new Date(iso).getTime()-Date.now())/1000);if(!(s>-60))return 'due now';if(s<60)return 'in under a minute';if(s<3600)return `in ${Math.round(s/60)} min`;if(s<86400)return `in ${Math.round(s/3600)} h`;return `in ${Math.round(s/86400)} d`}
const nextWhen=iso=>iso?<>{fmtDateTime(iso)}<small>{inText(iso)}</small></>:<em className="pjm-nr">None in the search window</em>

/** Snapshot freshness line shared by both screens: when the jobs read was counted, how long it took, and a stale chip when the last count failed. */
function Fresh({snap,took}){
  const err=snap?.error
  return <p className="pjm-fresh" data-pjm-fresh>
    {snap?.as_at?<>Job and lane figures counted <strong data-pjm-as-at>{fmtDateTime(snap.as_at)}</strong> (Melbourne), {fmtRelative(snap.as_at)}{has(took??snap.took_ms)?`; the count took ${fmtNumber(Math.round(Number(took??snap.took_ms)/100)/10)} s`:''}.</>:<em className="pjm-nr">Not yet counted.</em>}
    {err&&<> <StatusChip tone="warning" label="Stale" title="The latest count failed; the last good count is shown"/> <small data-pjm-error>{String(err)}</small></>}
  </p>
}

/** Search and filter helpers over the backend rows. */
const hay=c=>[nameOf(c),c.code,c.name,c.component,c.kind,c.state,c.reason,c.purpose,c.owner,c.area,c.layer,c.runner,c.field,c.last_status,c.failure_reason,...(c.findings||[])].filter(Boolean).join(' ').toLowerCase()
const match=(c,q)=>!q||q.toLowerCase().split(/\s+/).every(t=>hay(c).includes(t))

/** Data Delivery: states, counts by component type and the attention items, paged. The full list is Scheduled jobs › Automations. */
export function JobsSummary({ops}){
  const [q,setQ]=useState(''),[state,setState]=useState(''),[type,setType]=useState(''),[off,setOff]=useState(0)
  const limit=10
  const states=ops?.states&&typeof ops.states==='object'?ops.states:null
  const by=ops?.by_component&&typeof ops.by_component==='object'?ops.by_component:null
  const attention=Array.isArray(ops?.attention)?ops.attention:null
  useEffect(()=>setOff(0),[q,state,type])
  const stateKeys=useMemo(()=>Object.keys(states||{}).sort((a,b)=>rank(a)-rank(b)||a.localeCompare(b)),[states])
  const shown=useMemo(()=>(attention||[]).filter(a=>(!state||a.state===state)&&(!type||a.component===type)&&match(a,q)).sort((a,b)=>rank(a.state)-rank(b.state)||nameOf(a).localeCompare(nameOf(b))),[attention,q,state,type])
  if(!states&&!by&&!attention)return <div data-pjm-summary="none"><h5 className="sl-h4" data-pim-section="jobs-monitoring">Jobs, lanes, rules and rollup targets</h5><p className="sl-sub"><em className="pjm-nr">Not available</em> The PIM snapshot carries no job and lane monitoring yet.</p></div>
  const page=shown.slice(off,off+limit)
  return <div className="pjm" data-pjm-summary>
    <h5 className="sl-h4" data-pim-section="jobs-monitoring">Jobs, lanes, rules and rollup targets</h5>
    <Fresh snap={ops?.jobs_snapshot}/>
    {states&&<ul className="pjm-states" data-pjm-states>{stateKeys.map(s=><li key={s} data-pjm-state={s}><button type="button" className="pjm-tile" aria-pressed={state===s} onClick={()=>setState(state===s?'':s)}><span>{word(s)}</span><strong>{fmtNumber(Number(states[s]))}</strong></button></li>)}</ul>}
    {by&&<div className="pjm-frame"><table className="pjm-table" data-pjm-by-component><thead><tr><th>Type</th>{stateKeys.map(s=><th key={s} className="pjm-num">{word(s)}</th>)}</tr></thead><tbody>
      {Object.keys(by).sort().map(t=><tr key={t} data-pjm-type={t}><td data-label="Type"><button type="button" className="cf-link" aria-pressed={type===t} onClick={()=>setType(type===t?'':t)}>{TYPE_LABEL[t]||word(t)}</button></td>{stateKeys.map(s=><td key={s} className="pjm-num" data-label={word(s)}>{has(by[t]?.[s])?fmtNumber(Number(by[t][s])):<span className="pjm-zero">0</span>}</td>)}</tr>)}</tbody></table></div>}
    {attention&&<>
      <h5 className="sl-h4" data-pjm-attention-title>Needs attention ({fmtNumber(attention.length)})</h5>
      <p className="sl-sub">Every component that is degraded, held, in shadow or has a finding, with the backend's reason. Findings are evidence for the owner; nothing changes by showing them.</p>
      <div className="pjm-filters" data-pjm-filters><label>Search<input type="search" value={q} placeholder="Name, reason or finding" onChange={e=>setQ(e.target.value)} data-pjm-search/></label>
        <label>State<select value={state} onChange={e=>setState(e.target.value)}><option value="">All</option>{stateKeys.map(s=><option key={s} value={s}>{word(s)}</option>)}</select></label>
        <label>Type<select value={type} onChange={e=>setType(e.target.value)}><option value="">All</option>{Object.keys(by||{}).sort().map(t=><option key={t} value={t}>{TYPE_LABEL[t]||word(t)}</option>)}</select></label></div>
      {page.length?<ul className="pjm-cards" data-pjm-attention>{page.map(a=><li key={keyOf(a)} data-pjm-attn={keyOf(a)}>
        <div className="pjm-card-head"><strong>{nameOf(a)}</strong>{stateChip(a.state)}<span className="cf-badge">{typeLabel(a)}</span></div>
        {a.reason&&<p className="pjm-reason" data-pjm-reason>{a.reason}</p>}
        {(a.findings||[]).length>0&&<p className="pjm-findings">{a.findings.map(f=><span key={f} className="cf-badge">{word(f)}</span>)}</p>}
        <p className="pjm-meta"><span>Heartbeat: {a.heartbeat?`${fmtDateTime(a.heartbeat)} (${fmtRelative(a.heartbeat)})`:'Not recorded'}</span><span>Next run: {a.next_run?`${fmtDateTime(a.next_run)} (${inText(a.next_run)})`:'none in the search window'}</span></p></li>)}</ul>
        :<p className="pjm-empty" data-pjm-attn-empty>{attention.length?'No attention item matches these filters.':'No component is degraded, held, in shadow or has a finding.'}</p>}
      {shown.length>limit&&<Pager offset={off} limit={limit} total={shown.length} onOffset={setOff} className="pjm-pager"/>}
    </>}
    <p className="sl-sub"><a className="cf-link" href={hrefFor('jobs','automations')} data-pjm-open-full>Open the full list, filters and drill-down in Scheduled jobs</a></p>
  </div>
}

function Outcomes({h24,d7}){
  const row=(label,w)=>w?<tr data-pjm-window={label}><td data-label="Window">{label}</td><td className="pjm-num" data-label="Runs">{has(w.executions)?fmtNumber(Number(w.executions)):<em className="pjm-nr">Not recorded</em>}</td>{OUTCOMES.map(o=><td key={o} className="pjm-num" data-label={word(o)} data-pjm-outcome={o}>{has(w[o])?fmtNumber(Number(w[o])):<em className="pjm-nr">—</em>}</td>)}<td className="pjm-num" data-label="Average time">{has(w.avg_seconds)?`${fmtNumber(Math.round(Number(w.avg_seconds)*10)/10)} s`:<em className="pjm-nr">Not recorded</em>}</td></tr>:null
  return <div className="pjm-frame"><table className="pjm-table"><thead><tr><th>Window</th><th className="pjm-num">Runs</th>{OUTCOMES.map(o=><th key={o} className="pjm-num">{word(o)}</th>)}<th className="pjm-num">Average time</th></tr></thead><tbody>{row('24 hours',h24)}{row('7 days',d7)}</tbody></table>
    {(h24?.partial_since||d7?.partial_since)&&<p className="pjm-note">Retained history starts {fmtDateTime(h24?.partial_since||d7?.partial_since)}; the window is partial. Unmeasured is an outcome the run does not record, never 0.</p>}</div>
}
const Row=({k,children})=>children==null||children===''||children===false?null:<><dt>{k}</dt><dd>{children}</dd></>

/** The drill-down of one component, every figure from the backend row. */
function Detail({c}){
  const eff=c.effective_state&&c.effective_state!==c.state
  return <div className="pjm-detail" data-pjm-detail={keyOf(c)}>
    <section><h6>Why it is {word(c.state).toLowerCase()}</h6><dl>
      <Row k="Reason">{c.reason||<em className="pjm-nr">The backend gives no reason</em>}</Row>
      <Row k="Findings">{(c.findings||[]).length?c.findings.map(f=><span key={f} className="cf-badge">{word(f)}</span>):null}</Row>
      <Row k="Effective state">{eff?<>{stateChip(c.effective_state)}{c.moved_to&&<small>moved to {String(c.moved_to)}</small>}</>:null}</Row>
      <Row k="Runner">{c.runner?<>{c.runner}{(c.runner_jobids||[]).length>0&&<small>job {c.runner_jobids.join(', ')}</small>}</>:null}</Row>
      <Row k="Mode">{c.mode?`${word(c.mode)}${c.enabled===false?', switched off':''}`:null}</Row>
      <Row k="Registered">{c.registered?word(c.registered):null}</Row>
      <Row k="Idle since">{c.idle_since?when(c.idle_since):null}</Row></dl></section>
    <section><h6>Timing</h6><dl>
      <Row k="Schedule">{c.schedule?<code>{c.schedule}</code>:<em className="pjm-nr">Not recorded</em>}</Row>
      <Row k="Heartbeat (last start)">{when(c.heartbeat)}</Row>
      <Row k="Last end">{c.last_end?<>{fmtDateTime(c.last_end)}<small>{word(c.last_status)}{has(c.last_ms)?` in ${fmtNumber(Math.round(Number(c.last_ms)/100)/10)} s`:''}</small></>:<em className="pjm-nr">Not recorded</em>}</Row>
      <Row k="Last success">{when(c.last_success)}</Row>
      <Row k="Last failure">{c.last_failed_at?<>{fmtDateTime(c.last_failed_at)}{c.failure_reason&&<small>{c.failure_reason}</small>}</>:null}</Row>
      <Row k="Next run">{nextWhen(c.next_run)}</Row>
      <Row k="Stalled after">{has(c.stall_after_hours)?`${fmtNumber(Math.round(Number(c.stall_after_hours)*10)/10)} h without success`:null}</Row>
      <Row k="Time budget">{has(c.budget_ms)?`${fmtNumber(Math.round(Number(c.budget_ms)/100)/10)} s`:null}</Row></dl></section>
    <section><h6>Executions by outcome</h6><Outcomes h24={c.h24} d7={c.d7}/></section>
    <section><h6>What it is</h6><dl>
      <Row k="Purpose">{c.purpose}</Row><Row k="Owner">{c.owner}</Row><Row k="Area">{c.area}</Row><Row k="Layer">{c.layer}</Row>
      <Row k="Field">{c.field}</Row><Row k="Fills">{c.fills!=null?String(typeof c.fills==='object'?JSON.stringify(c.fills):c.fills):null}</Row><Row k="Uses AI">{c.uses_ai==null?null:c.uses_ai?'Yes':'No'}</Row></dl></section>
  </div>
}

/** Scheduled jobs › Automations: every component of public.admin_pim_jobs_v1 with search, filters, pagination and a drill-down. */
export function JobsMonitor(){
  const [data,setData]=useState(null),[err,setErr]=useState(''),[q,setQ]=useState(''),[type,setType]=useState(''),[state,setState]=useState(''),[finding,setFinding]=useState(''),[outcome,setOutcome]=useState(''),[off,setOff]=useState(0),[open,setOpen]=useState('')
  const limit=20
  const load=()=>{setErr('');supabase.rpc('admin_pim_jobs_v1').then(({data:d,error})=>{if(error)setErr(error.message||'The job monitoring read failed.');else setData(d||{})})}
  useEffect(()=>{let live=true;setErr('');Promise.resolve(supabase.rpc('admin_pim_jobs_v1')).then(({data:d,error})=>{if(!live)return;if(error)setErr(error.message||'The job monitoring read failed.');else setData(d||{})},e=>live&&setErr(String(e?.message||e)));return()=>{live=false}},[])
  useEffect(()=>setOff(0),[q,type,state,finding,outcome])
  const comps=useMemo(()=>Array.isArray(data?.components)?data.components:[],[data])
  const opts=useMemo(()=>({types:[...new Set(comps.map(c=>c.component))].sort(),states:[...new Set(comps.map(c=>c.state))].sort((a,b)=>rank(a)-rank(b)),findings:[...new Set(comps.flatMap(c=>c.findings||[]))].sort()}),[comps])
  const rows=useMemo(()=>comps.filter(c=>(!type||c.component===type)&&(!state||c.state===state)&&(!finding||(c.findings||[]).includes(finding))&&(!outcome||Number(c.h24?.[outcome])>0)&&match(c,q)).sort((a,b)=>rank(a.state)-rank(b.state)||nameOf(a).localeCompare(nameOf(b))),[comps,q,type,state,finding,outcome])
  const searchEntries=useMemo(()=>[{id:'pjm',tab:'automations',label:'Job and lane monitoring',keywords:'jobs lanes workers dispatchers rollup rules heartbeat next run outcomes productive empty held failed deferred snapshot drill-down stalled degraded',node:'[data-pjm-monitor]'}],[])
  usePageSearchEntries(searchEntries)
  const clear=()=>{setQ('');setType('');setState('');setFinding('');setOutcome('')}
  const filtered=q||type||state||finding||outcome
  const page=rows.slice(off,off+limit)
  return <section className="pjm" data-pjm-monitor aria-labelledby="pjm-h">
    <h3 id="pjm-h" className="pjm-title">Job and lane monitoring</h3>
    <p className="sl-sub">Every scheduled job, lane, rollup target and admission rule, with the state and reason the backend records. Read from the snapshot the platform keeps; nothing here starts, stops or changes a job.</p>
    {!data&&!err&&<Loading label="Reading the job and lane snapshot…"/>}
    {err&&<div className="pjm-alert" role="alert" data-pjm-read-error><strong>The job and lane read failed.</strong> {err} <button type="button" className="cf-btn compact" onClick={()=>{setData(null);load()}}>Try again</button></div>}
    {data&&<>
      <Fresh snap={data}/>
      {data.as_at==null&&data.error&&<p className="pjm-empty" data-pjm-not-counted>The platform has not counted the jobs yet ({String(data.error)}). Try again in a few minutes.</p>}
      {data.states&&<ul className="pjm-states" data-pjm-states>{Object.keys(data.states).sort((a,b)=>rank(a)-rank(b)).map(s=><li key={s} data-pjm-state={s}><button type="button" className="pjm-tile" aria-pressed={state===s} onClick={()=>setState(state===s?'':s)}><span>{word(s)}</span><strong>{fmtNumber(Number(data.states[s]))}</strong></button></li>)}</ul>}
      {comps.length>0&&<>
        <div className="pjm-filters" data-pjm-filters>
          <label>Search<input type="search" value={q} placeholder="Name, reason, purpose, owner" onChange={e=>setQ(e.target.value)} data-pjm-search/></label>
          <label>Type<select value={type} onChange={e=>setType(e.target.value)}><option value="">All types</option>{opts.types.map(t=><option key={t} value={t}>{TYPE_LABEL[t]||word(t)}</option>)}</select></label>
          <label>State<select value={state} onChange={e=>setState(e.target.value)}><option value="">All states</option>{opts.states.map(s=><option key={s} value={s}>{word(s)}</option>)}</select></label>
          <label>Finding<select value={finding} onChange={e=>setFinding(e.target.value)}><option value="">Any</option>{opts.findings.map(f=><option key={f} value={f}>{word(f)}</option>)}</select></label>
          <label>24 h outcome<select value={outcome} onChange={e=>setOutcome(e.target.value)}><option value="">Any</option>{OUTCOMES.map(o=><option key={o} value={o}>Has {o} runs</option>)}</select></label>
          {filtered?<button type="button" className="cf-btn compact" onClick={clear} data-pjm-clear>Clear filters</button>:null}</div>
        <p className="pjm-count" data-pjm-count aria-live="polite"><strong>{fmtNumber(rows.length)}</strong> of {fmtNumber(comps.length)} components{filtered?' match':''}</p>
        {rows.length?<>
          <div className="pjm-frame"><table className="pjm-table pjm-list" data-pjm-list><thead><tr><th>Component</th><th>State and reason</th><th>Heartbeat</th><th>Next run</th><th>24 h outcomes</th><th></th></tr></thead><tbody>
            {page.map(c=>{const k=keyOf(c),isOpen=open===k;return <React.Fragment key={k}><tr data-pjm-row={k} data-pjm-row-state={c.state} data-pjm-row-type={c.component}>
              <td data-label="Component" data-primary><strong>{nameOf(c)}</strong><small>{typeLabel(c)}{c.area?` · ${c.area}`:''}</small></td>
              <td data-label="State">{stateChip(c.state)}{c.reason&&<small data-pjm-reason>{c.reason}</small>}{(c.findings||[]).length>0&&<span className="pjm-findings">{c.findings.map(f=><span key={f} className="cf-badge">{word(f)}</span>)}</span>}</td>
              <td data-label="Heartbeat">{when(c.heartbeat)}{c.last_status&&<small>{word(c.last_status)}</small>}</td>
              <td data-label="Next run">{nextWhen(c.next_run)}</td>
              <td data-label="24 h outcomes">{c.h24&&has(c.h24.executions)?<span className="pjm-outs">{OUTCOMES.filter(o=>Number(c.h24[o])>0).map(o=><StatusChip key={o} tone={OUTCOME_TONE[o]} label={`${fmtNumber(Number(c.h24[o]))} ${o}`}/>)}{Number(c.h24.executions)===0&&<small>No runs in 24 h</small>}</span>:<em className="pjm-nr">Not recorded</em>}</td>
              <td data-label=""><button type="button" className="cf-btn compact" aria-expanded={isOpen} onClick={()=>setOpen(isOpen?'':k)} data-pjm-toggle={k}>{isOpen?'Hide details':'Details'}</button></td></tr>
              {isOpen&&<tr className="pjm-detail-row"><td colSpan={6}><Detail c={c}/></td></tr>}</React.Fragment>})}</tbody></table></div>
          {rows.length>limit&&<Pager offset={off} limit={limit} total={rows.length} onOffset={n=>{setOff(n);setOpen('')}} className="pjm-pager"/>}</>
          :<p className="pjm-empty" data-pjm-empty>No component matches these filters. <button type="button" className="cf-link" onClick={clear}>Clear filters</button></p>}
        <details className="pjm-tools" data-pjm-toolset><summary>AI and Firecrawl use by service</summary>
          <p className="sl-sub">{data.toolset?.attribution||'By service and use case only.'}</p>
          {Array.isArray(data.toolset?.ai)&&<div className="pjm-frame"><table className="pjm-table"><thead><tr><th>AI service</th><th className="pjm-num">Attempts 24 h</th><th className="pjm-num">Billed 24 h</th><th className="pjm-num">Attempts 7 d</th><th className="pjm-num">Billed 7 d</th></tr></thead><tbody>
            {data.toolset.ai.map(s=><tr key={s.service}><td data-label="AI service">{s.service}</td><td className="pjm-num" data-label="Attempts 24 h">{fmtNumber(Number(s.h24?.attempts))}</td><td className="pjm-num" data-label="Billed 24 h">{has(s.h24?.billed_usd)?`US$${Number(s.h24.billed_usd).toFixed(2)}`:'—'}</td><td className="pjm-num" data-label="Attempts 7 d">{fmtNumber(Number(s.d7?.attempts))}</td><td className="pjm-num" data-label="Billed 7 d">{has(s.d7?.billed_usd)?`US$${Number(s.d7.billed_usd).toFixed(2)}`:'—'}</td></tr>)}</tbody></table></div>}
          <p className="pjm-note" data-pjm-ai-note>Failed attempts per service are not shown: the backend's not-OK count treats every answered request as not OK, so it would equal the attempts. Shown again when the backend count is corrected.</p>
          {Array.isArray(data.toolset?.firecrawl)&&<div className="pjm-frame"><table className="pjm-table"><thead><tr><th>Firecrawl use</th><th className="pjm-num">Calls 24 h</th><th className="pjm-num">Failed 24 h</th><th className="pjm-num">Credits 24 h</th><th className="pjm-num">Calls 7 d</th><th className="pjm-num">Credits 7 d</th></tr></thead><tbody>
            {data.toolset.firecrawl.map(s=><tr key={s.use_case}><td data-label="Firecrawl use">{s.use_case}</td><td className="pjm-num" data-label="Calls 24 h">{fmtNumber(Number(s.h24?.calls))}</td><td className="pjm-num" data-label="Failed 24 h">{fmtNumber(Number(s.h24?.failed))}</td><td className="pjm-num" data-label="Credits 24 h">{has(s.h24?.credits)?fmtNumber(Number(s.h24.credits)):'—'}</td><td className="pjm-num" data-label="Calls 7 d">{fmtNumber(Number(s.d7?.calls))}</td><td className="pjm-num" data-label="Credits 7 d">{has(s.d7?.credits)?fmtNumber(Number(s.d7.credits)):'—'}</td></tr>)}</tbody></table></div>}
        </details>
        {data.meaning&&<p className="pjm-note" data-pjm-meaning>{data.meaning}</p>}
      </>}
    </>}
  </section>
}
