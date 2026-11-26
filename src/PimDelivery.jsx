// CF-247 s1217 (Platform Admin P0 26 Nov 2026 13:07, S1-API-Frontend-Delivery; F-OPS.17 to F-OPS.21; Master Plan section 6; hand-off s1162 and s1167):
// the "Autonomous PIM" block INSIDE the existing Data Delivery panel (Layer 2/3 Build & enrich > Operations). It is not another dashboard, tab or queue.
// It draws `pim`, the snapshot the existing data-delivery job counts into the existing admin_layer23('data_delivery') answer. Three views:
//   Delivery matrix: overall, country and domain coverage; the stage funnel; gains, throughput and the measured clearance estimate; oldest outstanding work;
//                    last and next processing; scheduler, lease and recovery state; AI and Firecrawl use; the genuine human interventions.
//   Requests & feedback: request status beside separate coverage figures. Shown only from `pim.requests` once the backend read (interface 6) is live; until then the
//                    screen says it is not available, and no request status, weight or coverage is estimated.
//   Refresh & maintenance: freshness of held values, source outcomes (a protected hold never removes a value), excluded gaps (workload, not delivered data),
//                    and the Academic entry, Scholarships and replacement-check lifecycle.
// Rules kept: a figure that is not counted is "Not measured" or "Unknown" with its reason, never 0; roll-ups are sums over pim.fields (the backend does not repeat
// them); countries come from the rows and domains from the field register (s930, no list is typed here); the screen adds no control and no setting, so every
// existing permission, backend control and the Consumer API are untouched. Detailed queue and lane work stays on Operations and Scheduled jobs (links below).
import React,{useEffect,useMemo,useState}from'react'
import{StatusChip,fmtDateTime,fmtNumber,fmtRelative}from'./ui-kit'
import{fmtMoney}from'./lib/format'
import{hrefFor}from'./nav-map'
import{useLookups,countryName}from'./lib/lookups'
import{supabase}from'./lib/supabase'

const sum=(rows,k)=>rows.reduce((a,r)=>a+(Number(r[k])||0),0)
const num=v=>v==null?'':fmtNumber(Number(v))
const word=s=>{const t=String(s||'').replaceAll('_',' ').trim();return t?t[0].toUpperCase()+t.slice(1):''}
const pctText=(n,d)=>d>0?`${fmtNumber(Math.round(n/d*1000)/10,{maxDecimals:1})}%`:null
/** Hours as the words a person reads: hours, days or years. Never a guess: the caller passes only a measured figure. */
function durText(h){const n=Number(h);if(!(n>=0))return '';if(n<48)return `${fmtNumber(Math.round(n*10)/10)} h`;const d=n/24;if(d<400)return `${fmtNumber(Math.round(d))} d`;return `about ${fmtNumber(Math.round(d/365*10)/10)} years`}
function untilText(iso,now){if(!iso)return '';const s=Math.round((new Date(iso).getTime()-now)/1000);if(!(s>-60))return 'due now';if(s<60)return 'in under a minute';if(s<3600)return `in ${Math.round(s/60)} min`;if(s<86400)return `in ${Math.round(s/3600)} h`;return `in ${Math.round(s/86400)} d`}

/** The word shown when a figure is not counted: never 0, never blank, with the reason beside it. */
function NotMeasured({reason,word:w='Not measured'}){return <span className="dd-unknown" data-dd-unknown data-pim-unknown><em>{w}</em>{reason&&<small title={reason}>{reason}</small>}</span>}
/** The way back from the detail screens (Scheduled jobs, Platform health › Queues & yield) to the primary monitoring screen. */
export const PimBacklink=()=><p className="l3v-note" data-pim-backlink>Progress by country and domain (backlog, gains, clearance, human interventions) is in <a className="cf-link" href={hrefFor('layer2','operations')}>Data Delivery › Autonomous PIM</a> on Layer 2/3 Build &amp; enrich › Operations.</p>
const V=({children})=><span className="pim-v">{children}</span> // one flex child per table cell, so a stacked phone row keeps a figure and its note together
const Val=({v,reason,unit})=>v==null?<NotMeasured reason={reason}/>:<strong data-pim-value={v}>{fmtNumber(Number(v))}{unit?<small> {unit}</small>:null}</strong>

// The field register (domains and plain labels) is read once a page load and shared; a failed read is tried again on the next use.
let registerRead=null
function loadRegister(){
  if(!registerRead)registerRead=Promise.resolve(supabase.rpc('admin_field_coverage',{p_action:'overview',p_args:{}})).then(({data,error})=>{if(error)throw error;return Array.isArray(data?.register)?data.register:[]}).catch(e=>{registerRead=null;throw e})
  return registerRead
}

const MEASURES=[
  {key:'completeness',label:'Canonical completeness',help:'Values held out of the fields that apply (held divided by applicable).'},
  {key:'backlog',label:'Backlog',help:'Applicable fields that still hold no value.'},
  {key:'canonical',label:'Canonical gain',help:'Values admitted in the window.'},
  {key:'published',label:'Consumer gain',help:'Values admitted in the window for courses of a published provider. Consumer coverage as a share is not counted yet.'},
]
const VIEWS=[{key:'matrix',label:'Delivery matrix'},{key:'requests',label:'Requests & feedback'},{key:'refresh',label:'Refresh & maintenance'}]

function cellOf(rows,measure){
  const a=sum(rows,'applicable'),h=sum(rows,'held')
  if(!rows.length)return{text:'—',small:'No field of this kind',tone:'none'}
  if(measure==='completeness'){if(!(a>0))return{text:'—',small:'None apply',tone:'none'};return{text:pctText(h,a),small:`${fmtNumber(h)} of ${fmtNumber(a)}`,pct:h/a*100}}
  if(measure==='backlog')return{text:fmtNumber(sum(rows,'backlog')),small:a>0?`of ${fmtNumber(a)} applicable`:'None apply'}
  if(measure==='canonical')return{text:`+${fmtNumber(sum(rows,'canonical_gain_window'))}`,small:'in the window'}
  return{text:`+${fmtNumber(sum(rows,'published_gain_window'))}`,small:'in the window'}
}

/** The funnel for one scope: sums over the rows. Stage counts are work-item counts and can overlap, so they are shown as counts, not as parts of the backlog. */
function Funnel({rows,label}){
  const applicable=sum(rows,'applicable'),held=sum(rows,'held'),backlog=sum(rows,'backlog'),queued=sum(rows,'queued'),running=sum(rows,'running'),review=sum(rows,'review'),nosrc=sum(rows,'no_source_found'),failed=sum(rows,'failed')
  const cells=[
    ['applicable','Applicable',fmtNumber(applicable),'fields that apply to a course'],
    ['backlog','Backlog',fmtNumber(backlog),'applicable, no value held yet'],
    ['queued','Queued',fmtNumber(queued),'waiting for a worker'],
    ['running','Running',fmtNumber(running),'being processed now'],
    ['held','Held',fmtNumber(review+nosrc),`${fmtNumber(review)} in review · ${fmtNumber(nosrc)} no source found`],
    ['failed','Failed',fmtNumber(failed),'last attempt failed'],
    ['completed','Completed',fmtNumber(held),`value held · ${pctText(held,applicable)||'no applicable field'}`],
  ]
  return <dl className="pim-funnel" data-pim-funnel aria-label={`Stage funnel, ${label}`}>{cells.map(([k,t,v,s])=><div key={k} data-pim-stage={k}><dt>{t}</dt><dd><strong>{v}</strong><small>{s}</small></dd></div>)}</dl>
}

function Gains({rows,hours}){
  const canonical=sum(rows,'canonical_gain_window'),published=sum(rows,'published_gain_window'),perHour=sum(rows,'throughput_per_hour')
  const withBacklog=rows.filter(r=>Number(r.backlog)>0)
  const measured=withBacklog.filter(r=>r.clearance_hours!=null)
  const unmeasured=withBacklog.length-measured.length
  const longest=measured.reduce((m,r)=>!m||Number(r.clearance_hours)>Number(m.clearance_hours)?r:m,null)
  return <div className="pim-gains" data-pim-gains>
    <div><span>Canonical gain, {hoursWord(hours)}</span><strong data-pim-gain="canonical">+{fmtNumber(canonical)}</strong><small>values admitted</small></div>
    <div><span>Consumer gain, {hoursWord(hours)}</span><strong data-pim-gain="published">+{fmtNumber(published)}</strong><small>for courses of a published provider</small></div>
    <div><span>Throughput</span><strong data-pim-gain="throughput">{fmtNumber(Math.round(perHour*100)/100)}<small> per hour</small></strong><small>measured over the window</small></div>
    <div><span>Estimated clearance</span>
      {!withBacklog.length?<strong data-pim-clearance="none">Nothing outstanding</strong>
        :longest?<><strong data-pim-clearance={longest.clearance_hours}>{durText(longest.clearance_hours)}</strong><small>longest measured field ({word(longest.field)}), from its own measured rate{unmeasured>0?`. ${fmtNumber(unmeasured)} of ${fmtNumber(withBacklog.length)} fields with a backlog gained nothing in the window, so they have no estimate.`:'.'}</small></>
        :<NotMeasured reason={`No field with a backlog gained a value in the window, so no rate can be measured (${fmtNumber(withBacklog.length)} field${withBacklog.length===1?'':'s'}).`}/>}
    </div>
  </div>
}
const hoursWord=h=>{const n=Number(h);return !n?'the window':n%24===0?`${n/24===1?'24 h':`${n/24} d`}`:`${fmtNumber(n)} h`}

export default function PimDelivery({pim,now,rank=0}){
  const lk=useLookups()
  const[view,setView]=useState('matrix'),[country,setCountry]=useState(''),[measure,setMeasure]=useState('completeness'),[domain,setDomain]=useState('')
  const[register,setRegister]=useState(null),[regErr,setRegErr]=useState(null)
  // domain grouping and plain labels: the field register, read through the existing coverage read (one read per page load, not per refresh)
  useEffect(()=>{let on=true
    loadRegister().then(r=>{if(on)setRegister(r)}).catch(e=>{if(on)setRegErr(e?.message||'The field register could not be read')})
    return()=>{on=false}},[])
  const rows=useMemo(()=>Array.isArray(pim?.fields)?pim.fields:[],[pim])
  const regBy=useMemo(()=>Object.fromEntries((register||[]).map(r=>[r.field,r])),[register])
  const labelOf=f=>regBy[f]?.label||word(f)
  const groupOf=f=>regBy[f]?.group||(register?'Other fields':'Fields')
  const countries=useMemo(()=>{const seen=[...new Set(rows.map(r=>r.country))];const order=(lk?.countries||[]).map(c=>c.code);return seen.sort((a,b)=>{const ia=order.indexOf(a),ib=order.indexOf(b);return (ia<0?999:ia)-(ib<0?999:ib)||String(a).localeCompare(String(b))})},[rows,lk])
  const domains=useMemo(()=>{const g=new Map();for(const r of rows){const k=groupOf(r.field);if(!g.has(k))g.set(k,new Set());g.get(k).add(r.field)}
    const order=(register||[]).map(r=>r.group);return[...g.entries()].sort((a,b)=>{const ia=order.indexOf(a[0]),ib=order.indexOf(b[0]);return (ia<0?999:ia)-(ib<0?999:ib)||a[0].localeCompare(b[0])})},[rows,register])// eslint-disable-line
  if(!pim)return <section className="dd-pim" data-dd-pim aria-label="Autonomous PIM"><div className="cf-section-title"><div className="cf-section-heading"><h4 className="sl-h4">Autonomous PIM</h4></div></div>
    <NotMeasured word="Not available" reason="This Data Delivery read carries no PIM snapshot yet, so progress, gains and clearance are not shown. Nothing is estimated."/></section>
  const inCountry=r=>!country||r.country===country
  const scope=rows.filter(inCountry)
  const scopeLabel=country?countryName(lk,country):'All countries'
  const activeDomain=domain&&domains.some(([k])=>k===domain)?domain:(domains[0]?.[0]||'')
  const domainFields=new Set(domains.find(([k])=>k===activeDomain)?.[1]||[])
  const snapMs=pim.snapshot_at?new Date(pim.snapshot_at).getTime():null
  const ageMin=snapMs&&now?Math.max(0,Math.round((now-snapMs)/60000)):null
  const hours=pim.window_hours
  const jobs=Array.isArray(pim.jobs)?pim.jobs:[]
  const nextRun=jobs.filter(j=>j.active&&j.next_run).map(j=>j.next_run).sort()[0]||null
  const lastRun=pim.gap_queue?.last_run_at||null
  const hr=pim.human_required||{}
  const layer4Waiting=Array.isArray(hr.layer4_waiting)?hr.layer4_waiting:[]
  const l4Total=layer4Waiting.reduce((a,x)=>a+(Number(x.waiting)||0),0)
  const oldestRow=scope.filter(r=>r.oldest_outstanding).sort((a,b)=>String(a.oldest_outstanding).localeCompare(String(b.oldest_outstanding)))[0]
  const links=<div className="dd-drill" data-pim-drill>
    <strong>Open the detail</strong>
    <a href={hrefFor('layer2','operations')} data-pim-link="operations">{pim.drill?.operations||'Operations: lane funnels'}</a>
    <a href={hrefFor('jobs','automations')} data-pim-link="jobs">{pim.drill?.queues_and_lanes||'Scheduled jobs'}</a>
    <a href={hrefFor('health','queues')} data-pim-link="watchdog">Platform health › Queues &amp; yield (watchdog)</a>
    <a href={hrefFor('layer4')} data-pim-link="layer4">{pim.drill?.layer4||'Layer 4 Review'}</a>
  </div>

  return <section className="dd-pim" data-dd-pim data-pim-view={view} aria-label="Autonomous PIM">
    <div className="cf-section-title"><div className="cf-section-heading"><h4 className="sl-h4">Autonomous PIM</h4>
      <small>Progress of the automatic data pipeline by country and domain. Counted in the background about as often as the Data Delivery job runs; the age is below.</small></div></div>
    <p className="sl-sub" data-pim-stamp>PIM figures counted <strong data-pim-snapshot-at>{pim.snapshot_at?fmtDateTime(pim.snapshot_at):'at an unknown time'}</strong> (Melbourne){ageMin!=null?`, ${ageMin} min ago`:''}.
      {' '}Window: {hoursWord(hours)}. {pim.snapshot_error?'':'Figures are counts of the live database at that time.'}
      {pim.snapshot_error&&<> <StatusChip tone="warning" label="Stale" title="The latest PIM count failed"/> <small data-pim-snapshot-error title={pim.snapshot_error}>The latest count failed ({pim.snapshot_error}{pim.snapshot_failed_at?` at ${fmtDateTime(pim.snapshot_failed_at)}`:''}); these are the last good figures.</small></>}</p>
    <div className="pim-tabs" role="tablist" aria-label="PIM views">{VIEWS.map(v=><button key={v.key} type="button" role="tab" aria-selected={view===v.key} className={`cf-btn compact${view===v.key?' primary':''}`} data-pim-tab={v.key} onClick={()=>setView(v.key)}>{v.label}</button>)}</div>

    {view==='matrix'&&<div data-pim-panel="matrix">
      <div className="pim-controls">
        <label>Country <select value={country} onChange={e=>setCountry(e.target.value)} data-pim-country><option value="">All countries</option>{countries.map(c=><option key={c} value={c}>{countryName(lk,c)}</option>)}</select></label>
        <label>Measure <select value={measure} onChange={e=>setMeasure(e.target.value)} data-pim-measure>{MEASURES.map(m=><option key={m.key} value={m.key}>{m.label}</option>)}</select></label>
      </div>
      <p className="sl-sub" data-pim-measure-help>{MEASURES.find(m=>m.key===measure)?.help}</p>
      <h5 className="sl-h4" data-pim-scope>{scopeLabel}: stage funnel</h5>
      {scope.length?<><Funnel rows={scope} label={scopeLabel}/>
        <p className="sl-sub" data-pim-funnel-note>Stage counts are work-item counts from the queue; one course field can appear in more than one stage over time, so the stages are not parts of the backlog and are not added to it.</p>
        <Gains rows={scope} hours={hours}/>
        <p className="sl-sub" data-pim-meaning>{pim.meaning?.clearance_hours?`Clearance: ${pim.meaning.clearance_hours}.`:''} {pim.meaning?.published_gain?`Consumer gain: ${pim.meaning.published_gain}.`:''}</p>
        <p className="sl-sub" data-pim-oldest>Oldest outstanding work: {oldestRow?<><strong>{fmtDateTime(oldestRow.oldest_outstanding)}</strong> ({word(oldestRow.field)}, {countryName(lk,oldestRow.country)}; {fmtRelative(oldestRow.oldest_outstanding,'',now)})</>:<NotMeasured reason="No outstanding work item carries a start time in this scope."/>}</p>
      </>:<NotMeasured word="Not available" reason="No PIM rows for this country."/>}

      <h5 className="sl-h4">Country and domain: {MEASURES.find(m=>m.key===measure)?.label.toLowerCase()}</h5>
      {regErr&&<p className="dd-stale" role="alert" data-pim-register-error>The field register could not be read ({regErr}); domains are shown as one group and fields by their code.</p>}
      <div className="lf-frame"><table className="cf-table pim-matrix" data-pim-matrix><thead><tr><th>Domain</th><th>All countries</th>{countries.map(c=><th key={c}>{countryName(lk,c)}</th>)}</tr></thead><tbody>
        {domains.map(([g,fields])=>{const inD=rows.filter(r=>fields.has(r.field));const a=cellOf(inD,measure)
          return <tr key={g} data-pim-domain-row={g} className={g===activeDomain?'is-active':''}>
            <td data-label="Domain"><V><button type="button" className="cf-link pim-domain" data-pim-domain={g} aria-pressed={g===activeDomain} onClick={()=>setDomain(g)}>{g}</button><small>{fmtNumber(fields.size)} field{fields.size===1?'':'s'}</small></V></td>
            <td data-label="All countries"><span data-pim-cell="all"><strong>{a.text}</strong><small>{a.small}</small></span></td>
            {countries.map(c=>{const x=cellOf(inD.filter(r=>r.country===c),measure);return <td key={c} data-label={countryName(lk,c)}><button type="button" className="pim-cell" data-pim-cell={c} onClick={()=>{setCountry(c);setDomain(g)}} title={`Open ${g} in ${countryName(lk,c)}`}><strong>{x.text}</strong><small>{x.small}</small>{x.pct!=null&&<span className="dd-bar" role="img" aria-label={`${Math.round(x.pct)}% complete`}><i style={{width:`${Math.min(100,x.pct)}%`}}/></span>}</button></td>})}
          </tr>})}
      </tbody></table></div>

      {activeDomain&&<><h5 className="sl-h4" data-pim-fields-title>{activeDomain} in {scopeLabel}: by field</h5>
        <div className="lf-frame"><table className="cf-table pim-fields" data-pim-fields><thead><tr><th>Field</th>{!country&&<th>Country</th>}<th>Applicable</th><th>Completed</th><th>Backlog</th><th>Queued</th><th>Running</th><th>Held</th><th>Failed</th><th>Gain</th><th>Per hour</th><th>Clearance</th><th>Oldest outstanding</th></tr></thead><tbody>
          {scope.filter(r=>domainFields.has(r.field)).sort((a,b)=>String(a.field).localeCompare(b.field)||String(a.country).localeCompare(b.country)).map(r=>{
            const app=Number(r.applicable)
            return <tr key={`${r.country}-${r.field}`} data-pim-field={r.field} data-pim-country-row={r.country}>
              <td data-label="Field"><V>{labelOf(r.field)}<small>{r.field}</small></V></td>{!country&&<td data-label="Country">{countryName(lk,r.country)}</td>}
              <td data-label="Applicable">{app>0?num(r.applicable):<NotMeasured word="None apply" reason={Number(r.not_applicable)>0?`${fmtNumber(Number(r.not_applicable))} recorded not applicable`:null}/>}</td>
              <td data-label="Completed">{app>0?<V><strong>{num(r.held)}</strong><small>{pctText(Number(r.held),app)}</small></V>:'—'}</td>
              <td data-label="Backlog">{num(r.backlog)}</td><td data-label="Queued">{num(r.queued)}</td><td data-label="Running">{num(r.running)}</td>
              <td data-label="Held"><V>{num(Number(r.review)+Number(r.no_source_found))}<small>{fmtNumber(Number(r.review))} review · {fmtNumber(Number(r.no_source_found))} no source</small></V></td>
              <td data-label="Failed">{num(r.failed)}</td>
              <td data-label="Gain"><V>+{num(r.canonical_gain_window)}<small>{fmtNumber(Number(r.published_gain_window))} published</small></V></td>
              <td data-label="Per hour">{r.throughput_per_hour==null?<NotMeasured/>:fmtNumber(Number(r.throughput_per_hour))}</td>
              <td data-label="Clearance">{Number(r.backlog)===0?'Nothing outstanding':r.clearance_hours==null?<NotMeasured reason="Nothing gained in the window"/>:durText(r.clearance_hours)}</td>
              <td data-label="Oldest outstanding">{r.oldest_outstanding?fmtDateTime(r.oldest_outstanding):'—'}</td>
            </tr>})}
        </tbody></table></div></>}

      <h5 className="sl-h4">Processing: scheduler, worker, leases and recovery</h5>
      <div className="pim-proc" data-pim-processing>
        <div><span>Last queue pass</span>{lastRun?<><strong data-pim-last-run>{fmtDateTime(lastRun)}</strong><small>{fmtRelative(lastRun,'',now)}{pim.gap_queue?.cycle_scanned!=null?` · scanned ${fmtNumber(Number(pim.gap_queue.cycle_scanned))}, found ${fmtNumber(Number(pim.gap_queue.cycle_found))}`:''}</small></>:<NotMeasured reason="The gap queue has not recorded a pass."/>}</div>
        <div><span>Next scheduled run</span>{nextRun?<><strong data-pim-next-run>{fmtDateTime(nextRun)}</strong><small>{untilText(nextRun,now)}</small></>:<NotMeasured reason="No active scheduled job has a next run."/>}</div>
        <div><span>Expired leases</span>{pim.leases?<><strong data-pim-leases={pim.leases.expired}>{fmtNumber(Number(pim.leases.expired))}</strong><small>{pim.leases.recovery}</small></>:<NotMeasured reason="Leases were not counted."/>}</div>
        <div><span>Worker heartbeat</span><NotMeasured reason="The PIM read carries the job schedule, the last queue pass and expired leases; it does not carry a per-worker heartbeat."/></div>
      </div>
      {jobs.length>0&&<div className="lf-frame"><table className="cf-table pim-jobs" data-pim-jobs><thead><tr><th>Scheduled job</th><th>State</th><th>Schedule</th><th>Next run</th></tr></thead><tbody>
        {jobs.map(j=><tr key={j.job} data-pim-job={j.job}><td data-label="Scheduled job">{j.job}</td><td data-label="State">{j.active?<StatusChip tone="success" label="On"/>:<StatusChip tone="warning" label="Off"/>}</td><td data-label="Schedule"><code>{j.schedule||'—'}</code></td><td data-label="Next run">{j.next_run?`${fmtDateTime(j.next_run)} (${untilText(j.next_run,now)})`:j.active?<NotMeasured reason="No next run is recorded."/>:'—'}</td></tr>)}</tbody></table></div>}

      <h5 className="sl-h4">Consumption in the last {hoursWord(hours)}</h5>
      <div className="pim-proc" data-pim-consumption>
        <div><span>AI attempts</span>{pim.ai?<><strong data-pim-ai-attempts>{fmtNumber(Number(pim.ai.attempts))}</strong><small>{fmtNumber(Number(pim.ai.failed))} failed</small></>:<NotMeasured/>}</div>
        <div><span>AI spend</span>{pim.ai?.cost_usd==null?<NotMeasured reason="Billed cost is blank until measured."/>:<><strong data-pim-ai-cost>{fmtMoney(Number(pim.ai.cost_usd),'USD',{decimals:2})}</strong><small>billed, every attempt included</small></>}</div>
        <div><span>Firecrawl calls</span>{pim.firecrawl?<><strong data-pim-fc-calls>{fmtNumber(Number(pim.firecrawl.calls))}</strong><small>{fmtNumber(Number(pim.firecrawl.credits))} credits</small></>:<NotMeasured/>}</div>
      </div>

      <h5 className="sl-h4">Needs a person</h5>
      <div className="pim-proc" data-pim-human>
        <div><span>Enrich review</span>{hr.enrich_review==null?<NotMeasured/>:<strong data-pim-enrich-review>{fmtNumber(Number(hr.enrich_review))}</strong>}<small>fields an AI or reader could not settle</small></div>
        <div><span>Layer 4 waiting</span><strong data-pim-l4-total>{fmtNumber(l4Total)}</strong><small>across {fmtNumber(layer4Waiting.length)} kinds</small></div>
      </div>
      {layer4Waiting.length>0&&<div className="lf-frame"><table className="cf-table pim-l4" data-pim-l4><thead><tr><th>Decision</th><th>Waiting</th><th>Oldest</th></tr></thead><tbody>
        {layer4Waiting.map(x=><tr key={x.field}><td data-label="Decision"><a href={hrefFor('layer4')}>{word(x.field)}</a></td><td data-label="Waiting">{fmtNumber(Number(x.waiting))}</td><td data-label="Oldest">{x.oldest?fmtDateTime(x.oldest):'—'}</td></tr>)}</tbody></table></div>}
      <p className="sl-sub">Decisions are made in Layer 4 Review with its own permissions. This screen opens it and changes nothing.</p>
      {links}
    </div>}

    {view==='requests'&&<div data-pim-panel="requests">
      {Array.isArray(pim.requests)&&pim.requests.length>0?<><h5 className="sl-h4">Stakeholder requests</h5>
        <p className="sl-sub">Status keeps the Request Register Rules v1.3 meanings. Canonical coverage, consumer coverage and freshness of a request&rsquo;s scope sit beside the status as separate figures and never change it.</p>
        <div className="lf-frame"><table className="cf-table pim-requests" data-pim-requests><thead><tr><th>Request</th><th>Scope</th><th>Status</th><th>Weight</th><th>Canonical coverage</th><th>Consumer coverage</th><th>Freshness</th><th>Clarification</th></tr></thead><tbody>
          {pim.requests.map((r,i)=><tr key={r.id||i} data-pim-request={r.id||i}><td data-label="Request"><strong>{r.id}</strong><small>{r.title}</small></td><td data-label="Scope">{r.scope||<NotMeasured word="Unknown"/>}</td>
            <td data-label="Status">{r.status?<StatusChip tone="neutral" label={r.status}/>:<NotMeasured word="Unknown"/>}</td><td data-label="Weight">{r.weight==null?<NotMeasured word="Unknown"/>:fmtNumber(Number(r.weight))}</td>
            <td data-label="Canonical coverage">{r.canonical_pct==null?<NotMeasured/>:`${fmtNumber(Number(r.canonical_pct),{maxDecimals:1})}%`}</td><td data-label="Consumer coverage">{r.consumer_pct==null?<NotMeasured/>:`${fmtNumber(Number(r.consumer_pct),{maxDecimals:1})}%`}</td>
            <td data-label="Freshness">{r.fresh_pct==null?<NotMeasured/>:`${fmtNumber(Number(r.fresh_pct),{maxDecimals:1})}%`}</td><td data-label="Clarification">{r.clarification||'None'}</td></tr>)}</tbody></table></div></>
      :<div data-pim-requests-unavailable><h5 className="sl-h4">Stakeholder requests</h5>
        <NotMeasured word="Not available" reason="The request register is not part of the Data Delivery read yet (Master Plan section 6, interface 6, owned by S1-RM-Design). No request status, weight or request coverage is shown, and none is estimated."/>
        <p className="sl-sub">When the read arrives this view shows each request&rsquo;s Rules v1.3 status beside its canonical coverage, consumer coverage and freshness as separate figures. The internal gap register is never shown here.</p></div>}
      <h5 className="sl-h4">Reported data issues</h5>
      <NotMeasured word="Not available" reason="Counsellor reports are not yet tied to a verified re-check in this read, so no fixed or verified figure is shown."/>
      <h5 className="sl-h4">Coverage of any scope, available now</h5>
      <p className="sl-sub">The figures a request would show beside its status are the country and domain figures on the <button type="button" className="cf-link" data-pim-goto="matrix" onClick={()=>setView('matrix')}>Delivery matrix</button>. Consumer coverage is not counted as a share yet; the matrix shows consumer gain in the window.</p>
    </div>}

    {view==='refresh'&&<div data-pim-panel="refresh">
      {pim.refresh?<>
        <h5 className="sl-h4">Freshness of held values</h5>
        <p className="sl-sub" data-pim-refresh-meaning>{pim.refresh.meaning} Refresh window: {fmtNumber(Number(pim.refresh.window_days))} days. Freshness is counted by field across all countries, not by country.</p>
        <div className="lf-frame"><table className="cf-table pim-refresh" data-pim-refresh><thead><tr><th>Field</th><th>Values held</th><th>Due to be verified</th><th>Fresh</th><th>Oldest verified</th></tr></thead><tbody>
          {(pim.refresh.fields||[]).map(f=>{const h=Number(f.held),d=Number(f.refresh_due)
            return <tr key={f.field} data-pim-refresh-field={f.field}><td data-label="Field"><V>{labelOf(f.field)}<small>{f.field}</small></V></td><td data-label="Values held">{fmtNumber(h)}</td><td data-label="Due to be verified">{fmtNumber(d)}</td>
              <td data-label="Fresh">{h>0?<V><strong>{pctText(h-d,h)}</strong><span className="dd-bar" role="img" aria-label={`${pctText(h-d,h)} fresh`}><i style={{width:`${Math.min(100,(h-d)/h*100)}%`}}/></span></V>:<NotMeasured word="None held"/>}</td>
              <td data-label="Oldest verified">{f.oldest_verified?fmtDateTime(f.oldest_verified):<NotMeasured word="Unknown"/>}</td></tr>})}</tbody></table></div>
        <h5 className="sl-h4">Source outcomes</h5>
        <p className="sl-sub">Pages bound to courses, by their last read. A protected hold (blocked or robots disallowed) keeps its held values in coverage; nothing is read around it.</p>
        <div className="lf-frame"><table className="cf-table pim-sources" data-pim-sources><thead><tr><th>Outcome</th><th>Pages</th><th>Due for re-read</th><th>Protected hold</th></tr></thead><tbody>
          {(pim.refresh.sources||[]).map(s=><tr key={s.outcome} data-pim-source={s.outcome}><td data-label="Outcome">{word(s.outcome)}</td><td data-label="Pages">{fmtNumber(Number(s.pages))}</td><td data-label="Due for re-read">{fmtNumber(Number(s.due_for_reread))}</td><td data-label="Protected hold">{s.protected_hold?'Yes':'No'}</td></tr>)}</tbody></table></div></>
      :<NotMeasured word="Not available" reason="The snapshot carries no refresh figures."/>}
      {pim.excluded?<><h5 className="sl-h4">Excluded gaps</h5>
        <p className="sl-sub" data-pim-excluded-meaning>{pim.excluded.meaning}</p>
        <dl className="pim-funnel" data-pim-excluded-totals>{Object.entries(pim.excluded.totals||{}).map(([k,v])=><div key={k} data-pim-excluded={k}><dt>{word(k)}</dt><dd><strong>{fmtNumber(Number(v))}</strong><small>gaps</small></dd></div>)}</dl>
        <div className="lf-frame"><table className="cf-table pim-excluded" data-pim-excluded-fields><thead><tr><th>Field</th><th>Reason</th><th>Gaps</th><th>Next revisit</th></tr></thead><tbody>
          {(pim.excluded.by_field||[]).map((x,i)=><tr key={`${x.field}-${x.reason}-${i}`}><td data-label="Field">{labelOf(x.field)}</td><td data-label="Reason">{word(x.reason)}</td><td data-label="Gaps">{fmtNumber(Number(x.gaps))}</td><td data-label="Next revisit">{x.next_revisit?fmtDateTime(x.next_revisit):'—'}</td></tr>)}</tbody></table></div></>:null}
      {pim.lifecycle?<><h5 className="sl-h4">Academic entry by country</h5>
        <div className="lf-frame"><table className="cf-table pim-lifecycle" data-pim-academic><thead><tr><th>Country</th><th>Stage</th><th>Courses</th><th>Next owner</th></tr></thead><tbody>
          {(pim.lifecycle.academic_entry?.stages||[]).map((s,i)=><tr key={`${s.country}-${s.stage}-${i}`}><td data-label="Country">{countryName(lk,s.country)}</td><td data-label="Stage">{word(s.stage)}</td><td data-label="Courses">{fmtNumber(Number(s.courses))}</td><td data-label="Next owner">{pim.lifecycle.academic_entry?.next_owner?.[s.stage]||<NotMeasured word="Unknown"/>}</td></tr>)}</tbody></table></div>
        <h5 className="sl-h4">Scholarships by country</h5>
        <p className="sl-sub">Owner: {pim.lifecycle.scholarships?.owner||'not recorded'}.</p>
        <div className="lf-frame"><table className="cf-table pim-lifecycle" data-pim-scholarships><thead><tr><th>Country</th><th>Disposition</th><th>Providers</th><th>Published</th><th>Reviews pending</th></tr></thead><tbody>
          {(pim.lifecycle.scholarships?.providers||[]).map((s,i)=><tr key={`${s.country}-${s.disposition}-${i}`}><td data-label="Country">{countryName(lk,s.country)}</td><td data-label="Disposition">{word(s.disposition)}</td><td data-label="Providers">{fmtNumber(Number(s.providers))}</td><td data-label="Published">{fmtNumber(Number(s.scholarships_published))}</td><td data-label="Reviews pending">{fmtNumber(Number(s.reviews_pending))}</td></tr>)}</tbody></table></div>
        {pim.lifecycle.replacement_check&&<p className="sl-sub" data-pim-replacement><strong>Replacement check.</strong> {fmtNumber(Number(pim.lifecycle.replacement_check.checked))} guarded supersessions tested; {fmtNumber(Number(pim.lifecycle.replacement_check.flagged))} lost their successor and need a person. {pim.lifecycle.replacement_check.meaning}</p>}</>:null}
      {links}
    </div>}
  </section>
}
