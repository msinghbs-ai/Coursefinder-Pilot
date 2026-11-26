// CF-247 s1217 (Platform Admin P0 26 Nov 2026 13:07, S1-API-Frontend-Delivery; F-OPS.17 to F-OPS.21; Master Plan section 6; hand-off s1162 and s1167):
// the "Autonomous PIM" block INSIDE the existing Data Delivery panel (Layer 2/3 Build & enrich > Operations). It is not another dashboard, tab or queue.
// It draws `pim`, the snapshot the existing data-delivery job counts into the existing admin_layer23('data_delivery') answer. Three views:
//   Delivery matrix: overall, country and domain coverage; the stage funnel; gains, throughput and the measured clearance estimate; oldest outstanding work;
//                    last and next processing; scheduler, lease and recovery state; AI and Firecrawl use; the genuine human interventions.
//   Requests & feedback: request status beside separate coverage figures. Shown only from `pim.requests` once the backend read (interface 6) is live; until then the
//                    screen says it is not available, and no request status, weight or coverage is estimated.
//   Refresh & maintenance: freshness of held values, source outcomes (a protected hold never removes a value), excluded gaps (workload, not delivered data),
//                    and the Academic entry, Scholarships and replacement-check lifecycle.
// s1218 (Platform Admin, SS-Programme-Control 14:25 26 Nov 2026, final frontend accuracy): each gain is shown with its gain_basis and rows with different bases are
// never added together (a mixed cell says so); "published-provider gain" is not "verified consumer delivery" (that is not counted per field); a measured zero reads
// "0, measured" and an unavailable figure "Not measured" (a missing value is never summed as 0); canonical field coverage (applicable, completed, backlog) and
// work-item counts (queued, running, held, failed) are shown as two groups, because work items can exceed the backlog.
// s1221 (SS-Programme-Control 26 Nov 2026 15:46; backend s1175, `pim.operations`): worker status and stalled processing (workers[], stalled_workers), freshness by country
// (freshness_by_country[]), and verified consumer read-back per stream and country (consumer[]; streams are different kinds of record and are never added). The request
// register stays "Not available" (operations.requests is `not_projected` with its reason) and verified feedback stays "Not available" (no authoritative source).
// Rules kept: a figure that is not counted is "Not measured" or "Unknown" with its reason, never 0; roll-ups are sums over pim.fields (the backend does not repeat
// them); countries come from the rows and domains from the field register (s930, no list is typed here); the screen adds no setting (its only controls are read-only filters, search and paging over the loaded snapshot, s1283), so every
// existing permission, backend control and the Consumer API are untouched. Detailed queue and lane work stays on Operations and Scheduled jobs (links below).
import{RecordDrill}from'./RecordTrace' // CF-247 s1282 (DR-19 increment 2)
import React,{useEffect,useMemo,useState}from'react'
import{StatusChip,fmtDateTime,fmtNumber,fmtRelative}from'./ui-kit'
import{fmtMoney}from'./lib/format'
import{hrefFor}from'./nav-map'
import{useLookups,countryName}from'./lib/lookups'
import{supabase}from'./lib/supabase'
import{usePageSearchEntries}from'./PageSearch'
import{JobsSummary}from'./PimJobsMonitor'
import ConsumerSample from'./PimConsumerSample'

const SAMPLE_TITLE={aer:'Academic entry',cdesc:'Course descriptions'} // labels for the two sampled streams; the backend returns the codes
const has=v=>v!=null&&v!==''&&Number.isFinite(Number(v))
/** Sum over the rows that carry the figure. A row with no value is counted as missing, never as 0. */
const agg=(rows,k)=>{let total=0,known=0;for(const r of rows)if(has(r[k])){total+=Number(r[k]);known++}return{total,known,missing:rows.length-known}}
const sum=(rows,k)=>agg(rows,k).total
const num=v=>has(v)?fmtNumber(Number(v)):''
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
/** A figure from the rows: Not measured when no row carries it; "at least" when some rows do not. */
function Fig({a,signed,unit,attr}){
  if(!a.known)return <NotMeasured/>
  const t=signed&&a.total>0?`+${fmtNumber(a.total)}`:fmtNumber(a.total)
  return <><strong {...attr}>{t}{unit?<small> {unit}</small>:null}</strong>{a.missing>0&&<small data-pim-partial>at least; {fmtNumber(a.missing)} row{a.missing===1?'':'s'} not counted</small>}{signed&&a.total===0&&<small data-pim-measured-zero>measured: none in the window</small>}</>
}
const BASIS_NONE='Basis not stated'
/** Rows grouped by the basis the backend measured their gain on. Gains on different bases are never added together. */
const byBasis=rows=>{const m=new Map();for(const r of rows){const k=r.gain_basis||'';if(!m.has(k))m.set(k,[]);m.get(k).push(r)}return[...m.entries()]}
const basisWord=b=>b||BASIS_NONE
const Val=({v,reason,unit})=>v==null?<NotMeasured reason={reason}/>:<strong data-pim-value={v}>{fmtNumber(Number(v))}{unit?<small> {unit}</small>:null}</strong>

// The field register (domains and plain labels) is read once a page load and shared; a failed read is tried again on the next use.
let registerRead=null
function loadRegister(){
  if(!registerRead)registerRead=Promise.resolve(supabase.rpc('admin_field_coverage',{p_action:'overview',p_args:{}})).then(({data,error})=>{if(error)throw error;return Array.isArray(data?.register)?data.register:[]}).catch(e=>{registerRead=null;throw e})
  return registerRead
}

const MEASURES=[
  {key:'completeness',label:'Canonical completeness',help:'Values held out of the fields that apply (held divided by applicable).'},
  {key:'backlog',label:'Backlog',help:'Applicable fields that still hold no value (canonical). Work-item holds are not subtracted from it.'},
  {key:'canonical',label:'Canonical gain',help:'Values admitted in the window, on the basis shown for each field. Fields measured on different bases are not added together.'},
  {key:'published',label:'Published-provider gain',help:'Values admitted in the window for courses of a provider whose Published switch is on. This is not verified delivery to the website or Zoho, which is not counted per field.'},
]
const VIEWS=[{key:'matrix',label:'Delivery matrix'},{key:'requests',label:'Requests & feedback'},{key:'refresh',label:'Refresh & maintenance'}]

function cellOf(rows,measure){
  const a=agg(rows,'applicable'),h=agg(rows,'held')
  if(!rows.length)return{text:'—',small:'No field of this kind',tone:'none'}
  if(measure==='completeness'){if(!a.known||!h.known)return{text:'Not measured',small:'no count for these fields',tone:'unknown'};if(!(a.total>0))return{text:'—',small:'None apply',tone:'none'};return{text:pctText(h.total,a.total),small:`${fmtNumber(h.total)} of ${fmtNumber(a.total)}${a.missing||h.missing?' (at least)':''}`,pct:h.total/a.total*100}}
  if(measure==='backlog'){const b=agg(rows,'backlog');return b.known?{text:fmtNumber(b.total),small:a.total>0?`of ${fmtNumber(a.total)} applicable${b.missing?' (at least)':''}`:'None apply'}:{text:'Not measured',small:'no count for these fields',tone:'unknown'}}
  const k=measure==='canonical'?'canonical_gain_window':'published_gain_window'
  const groups=byBasis(rows)
  if(groups.length>1)return{text:'Mixed bases',small:`${fmtNumber(groups.length)} bases, not added`,tone:'mixed'}
  const g=agg(rows,k)
  if(!g.known)return{text:'Not measured',small:'no count for these fields',tone:'unknown'}
  return{text:g.total>0?`+${fmtNumber(g.total)}`:'0',small:g.total>0?'in the window':'measured: none in the window'}
}

/** The funnel for one scope, in two groups that are never added together: canonical field coverage (applicable, completed, backlog) and the work items in the queue
 *  (queued, running, held, failed). Work items are counted per queue item, not per course field, so a held count can exceed the backlog. */
function Funnel({rows,label}){
  const A=k=>agg(rows,k)
  const applicable=A('applicable'),held=A('held'),backlog=A('backlog'),queued=A('queued'),running=A('running'),review=A('review'),nosrc=A('no_source_found'),failed=A('failed')
  const hold=review.known||nosrc.known?{known:1,total:review.total+nosrc.total,missing:Math.max(review.missing,nosrc.missing)}:{known:0,total:0,missing:rows.length}
  const fig=(a)=>a.known?fmtNumber(a.total):<NotMeasured/>
  const field=[
    ['applicable','Applicable',fig(applicable),'fields that apply to a course'],
    ['completed','Completed',fig(held),applicable.known&&held.known?`value held · ${pctText(held.total,applicable.total)||'no applicable field'}`:'value held'],
    ['backlog','Backlog',fig(backlog),'applicable, no value held yet'],
  ]
  const items=[
    ['queued','Queued',fig(queued),'waiting for a worker'],
    ['running','Running',fig(running),'being processed now'],
    ['held','Held',fig(hold),hold.known?`${fmtNumber(review.total)} in review · ${fmtNumber(nosrc.total)} no source found`:'not counted'],
    ['failed','Failed',fig(failed),'last attempt failed'],
  ]
  const dl=(cells,g)=><dl className="pim-funnel" data-pim-funnel-group={g}>{cells.map(([k,t,v,x])=><div key={k} data-pim-stage={k}><dt>{t}</dt><dd><strong>{v}</strong><small>{x}</small></dd></div>)}</dl>
  return <div data-pim-funnel aria-label={`Stage funnel, ${label}`}>
    <h6 className="pim-group" data-pim-group="field">Canonical field coverage <small>per course field</small></h6>{dl(field,'field')}
    <h6 className="pim-group" data-pim-group="items">Work items in the queue <small>per queue item, not per field</small></h6>{dl(items,'items')}
  </div>
}

function Gains({rows,hours,hasConsumer}){
  const withBacklog=rows.filter(r=>Number(r.backlog)>0)
  const measured=withBacklog.filter(r=>r.clearance_hours!=null)
  const unmeasured=withBacklog.length-measured.length
  const longest=measured.reduce((m,r)=>!m||Number(r.clearance_hours)>Number(m.clearance_hours)?r:m,null)
  const groups=byBasis(rows)
  return <div className="pim-gains-wrap" data-pim-gains>
    {groups.map(([b,g])=>{const tp=agg(g,'throughput_per_hour')
      return <div key={b||'none'} className="pim-gains" data-pim-gain-group data-pim-basis={b||''}>
        <p className="sl-sub pim-basis" data-pim-gain-basis><strong>Measured on:</strong> {basisWord(b)}{groups.length>1?<> · {fmtNumber(new Set(g.map(r=>r.field)).size)} field{new Set(g.map(r=>r.field)).size===1?'':'s'}</>:null}</p>
        <div><span>Canonical gain, {hoursWord(hours)}</span><Fig a={agg(g,'canonical_gain_window')} signed attr={{'data-pim-gain':'canonical'}}/><small>values admitted</small></div>
        <div><span>Published-provider gain, {hoursWord(hours)}</span><Fig a={agg(g,'published_gain_window')} signed attr={{'data-pim-gain':'published'}}/><small>courses of a provider whose Published switch is on</small></div>
        <div><span>Throughput</span>{tp.known?<><strong data-pim-gain="throughput">{fmtNumber(Math.round(tp.total*100)/100)}<small> per hour</small></strong><small>{tp.total===0?'measured: none gained':'measured over the window'}{tp.missing?`; ${fmtNumber(tp.missing)} row${tp.missing===1?'':'s'} not counted`:''}</small></>:<NotMeasured/>}</div>
      </div>})}
    <div className="pim-gains" data-pim-gain-group-shared>
      <div><span>Verified consumer delivery</span><NotMeasured reason={hasConsumer?'Not counted per field. It is measured per stream and country in Verified consumer read-back below and, for academic entry and descriptions, as a sample in Sampled delivery read-back (counted on the checked courses only); streams are different kinds of record and are not added. Published-provider gain is not a delivery check.':'Not counted per field. Website and Zoho read-back is shown on each stream card above where it is measured; published-provider gain is not a delivery check.'}/></div>
      <div><span>Estimated clearance</span>
        {!withBacklog.length?<strong data-pim-clearance="none">Nothing outstanding</strong>
          :longest?<><strong data-pim-clearance={longest.clearance_hours}>{durText(longest.clearance_hours)}</strong><small>longest measured field ({word(longest.field)}; {basisWord(longest.gain_basis)}), from its own measured rate{unmeasured>0?`. ${fmtNumber(unmeasured)} of ${fmtNumber(withBacklog.length)} fields with a backlog gained nothing in the window, so they have no estimate.`:'.'} Fields are not combined.</small></>
          :<NotMeasured reason={`No field with a backlog gained a value in the window, so no rate can be measured (${fmtNumber(withBacklog.length)} field${withBacklog.length===1?'':'s'}).`}/>}
      </div>
    </div>
  </div>
}
const minutesAgo=(iso,now)=>{const t=iso?new Date(iso).getTime():NaN;return Number.isFinite(t)&&now?Math.max(0,Math.round((now-t)/60000)):null}
const ageWord=m=>m==null?'at an unknown time':m<1?'under a minute ago':m<120?`${fmtNumber(m)} min ago`:`${fmtNumber(Math.round(m/60))} h ago`
/** Verified consumer read-back for one consumer: matched out of expected, with pending, missing and not served kept apart. A null count is Not measured, never 0. */
function ConsumerCell({r,c}){
  const matched=r[`${c}_matched`],pending=r[`${c}_pending`],missing=r[`${c}_missing`],notServed=r[`${c}_not_served`],expected=Number(r.expected)
  if(!has(matched))return <NotMeasured reason={c==='z'?'Zoho read-back is not counted for this stream.':'Not counted.'}/>
  return <V><strong data-pim-matched={matched}>{fmtNumber(Number(matched))}</strong><small>{expected>0?`${pctText(Number(matched),expected)} of expected`:'none expected'}</small>
    <small>{has(pending)?`${fmtNumber(Number(pending))} pending`:'pending: not measured'} · {has(missing)?`${fmtNumber(Number(missing))} missing`:'missing: not measured'} · {has(notServed)?`${fmtNumber(Number(notServed))} not served`:'not served: not measured'}</small></V>
}
const HELPER_STREAM={aer:'aer',pdesc:'pdesc',intake:'int',cdesc_stages:'cdesc'} // which Data Delivery stream each helper snapshot feeds
const hoursWord=h=>{const n=Number(h);return !n?'the window':n%24===0?`${n/24===1?'24 h':`${n/24} d`}`:`${fmtNumber(n)} h`}

export default function PimDelivery({pim,now,rank=0,streams=null,snapshots=null,staleMinutes=null}){
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
  // s1270: the PIM views and sections are offered to the page search (a view is local state, so a closed view's sections are only found this way)
  const searchEntries=useMemo(()=>{
    const V=[['matrix','Delivery matrix','overall country domain coverage funnel gains throughput clearance processing workers consumer'],['requests','Requests & feedback','stakeholder requests feedback reported data issues'],['refresh','Refresh & maintenance','freshness stale source outcomes excluded gaps lifecycle']]
    const S=[['matrix','funnel','Stage funnel','queued running held failed work items canonical coverage'],['matrix','matrix','Country and domain matrix','completeness backlog gains published domain'],
      ['matrix','processing','Processing: scheduler, worker, leases and recovery','last queue pass next scheduled run leases stalled workers heartbeat jobs'],['matrix','jobs-monitoring','Jobs, lanes, rules and rollup targets','workers scheduled jobs stalled stuck degraded held attention heartbeat last success failed schedule component state'],
      ['matrix','consumer','Verified consumer read-back','website zoho matched expected pending missing not served delivery per stream'],['matrix','consumer-sample','Sampled delivery read-back','sample sampled coverage population verified delivery international applicability failure reasons last verification academic entry descriptions website zoho'],['matrix','consumption','AI and Firecrawl use','spend cost credits calls attempts'],['matrix','human','Needs a person','layer 4 review waiting enrich review'],
      ['requests','requests','Stakeholder requests','request register status weight coverage not projected'],['requests','issues','Reported data issues and verified feedback','counsellor reports fixed verified'],
      ['refresh','freshness','Freshness of held values','refresh window due to be verified oldest verified by field'],['refresh','fresh-country','Freshness by country','held due fresh stale country field'],
      ['refresh','sources','Source outcomes','blocked fetch failed read protected hold re-read'],['refresh','excluded','Excluded gaps','workload eligible closed to international no source revisit'],
      ['refresh','lifecycle','Academic entry by country','stages admitted no page next owner'],['refresh','scholarships','Scholarships by country','providers published reviews pending']]
    const out=[{id:'pim:root',kind:'section',label:'Autonomous PIM',path:'Data Delivery',keywords:'pim delivery go live coverage',target:'[data-dd-pim]'}]
    for(const[v,l,k]of V)out.push({id:`pim:view:${v}`,kind:'view',label:l,path:'Data Delivery › Autonomous PIM',keywords:k,jump:()=>{setView(v);return `[data-pim-panel="${v}"]`}})
    for(const[v,id,l,k]of S)out.push({id:`pim:sec:${id}`,kind:'section',label:l,path:`Data Delivery › Autonomous PIM › ${V.find(x=>x[0]===v)[1]}`,keywords:k,jump:()=>{setView(v);return `[data-pim-section="${id}"]`}})
    return out
  },[])
  usePageSearchEntries(searchEntries)
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
  const ops=pim.operations&&typeof pim.operations==='object'?pim.operations:null
  const streamTitle=id=>(Array.isArray(streams)?streams.find(x=>x.stream===id)?.title:null)||word(id)
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
    {snapshots&&typeof snapshots==='object'&&Object.keys(snapshots).length>0&&<p className="sl-sub" data-pim-helper-snapshots>Other Data Delivery counts, each kept as its last good result: {Object.entries(snapshots).map(([k,v],i)=>{const ago=minutesAgo(v?.as_at,now),stale=staleMinutes!=null&&ago!=null&&ago>Number(staleMinutes);return <span key={k} data-pim-helper-snapshot={k} data-pim-helper-state={v?.error?'error':stale?'stale':'ok'}>{i?'; ':''}{streamTitle(HELPER_STREAM[k]||k)} {v?.as_at?ageWord(ago):'not counted yet'}{(v?.error||stale)&&<> <StatusChip tone="warning" label={v?.error?'Last count failed':'Stale'} title={v?.error||''}/></>}</span>})}.</p>}
    <div className="pim-tabs" role="tablist" aria-label="PIM views">{VIEWS.map(v=><button key={v.key} type="button" role="tab" aria-selected={view===v.key} className={`cf-btn compact${view===v.key?' primary':''}`} data-pim-tab={v.key} onClick={()=>setView(v.key)}>{v.label}</button>)}</div>

    {view==='matrix'&&<div data-pim-panel="matrix">
      <div className="pim-controls">
        <label>Country <select value={country} onChange={e=>setCountry(e.target.value)} data-pim-country><option value="">All countries</option>{countries.map(c=><option key={c} value={c}>{countryName(lk,c)}</option>)}</select></label>
        <label>Measure <select value={measure} onChange={e=>setMeasure(e.target.value)} data-pim-measure>{MEASURES.map(m=><option key={m.key} value={m.key}>{m.label}</option>)}</select></label>
      </div>
      <p className="sl-sub" data-pim-measure-help>{MEASURES.find(m=>m.key===measure)?.help}</p>
      <h5 className="sl-h4" data-pim-scope data-pim-section="funnel">{scopeLabel}: stage funnel</h5>
      {scope.length?<><Funnel rows={scope} label={scopeLabel}/>
        <p className="sl-sub" data-pim-funnel-note>Work items are counted per queue item, not per course field. One field can have several items, and a held item can belong to a field that already holds a value, so work-item holds are not parts of the backlog, can be larger than it, and are never subtracted from it.</p>
        <Gains rows={scope} hours={hours} hasConsumer={Array.isArray(ops?.consumer)&&ops.consumer.length>0}/>
        <p className="sl-sub" data-pim-meaning>{pim.meaning?.clearance_hours?`Clearance: ${pim.meaning.clearance_hours}.`:''} {pim.meaning?.published_gain?`Published-provider gain: ${pim.meaning.published_gain}.`:''}</p>
        <p className="sl-sub" data-pim-oldest>Oldest outstanding work: {oldestRow?<><strong>{fmtDateTime(oldestRow.oldest_outstanding)}</strong> ({word(oldestRow.field)}, {countryName(lk,oldestRow.country)}; {fmtRelative(oldestRow.oldest_outstanding,'',now)})</>:<NotMeasured reason="No outstanding work item carries a start time in this scope."/>}</p>
      </>:<NotMeasured word="Not available" reason="No PIM rows for this country."/>}

      <h5 className="sl-h4" data-pim-section="matrix">Country and domain: {MEASURES.find(m=>m.key===measure)?.label.toLowerCase()}</h5>
      {regErr&&<p className="dd-stale" role="alert" data-pim-register-error>The field register could not be read ({regErr}); domains are shown as one group and fields by their code.</p>}
      <div className="lf-frame"><table className="cf-table pim-matrix" data-pim-matrix><thead><tr><th>Domain</th><th>All countries</th>{countries.map(c=><th key={c}>{countryName(lk,c)}</th>)}</tr></thead><tbody>
        {domains.map(([g,fields])=>{const inD=rows.filter(r=>fields.has(r.field));const a=cellOf(inD,measure)
          return <tr key={g} data-pim-domain-row={g} className={g===activeDomain?'is-active':''}>
            <td data-label="Domain"><V><button type="button" className="cf-link pim-domain" data-pim-domain={g} aria-pressed={g===activeDomain} onClick={()=>setDomain(g)}>{g}</button><small>{fmtNumber(fields.size)} field{fields.size===1?'':'s'}</small></V></td>
            <td data-label="All countries"><span data-pim-cell="all"><strong>{a.text}</strong><small>{a.small}</small></span></td>
            {countries.map(c=>{const x=cellOf(inD.filter(r=>r.country===c),measure);return <td key={c} data-label={countryName(lk,c)}><button type="button" className="pim-cell" data-pim-cell={c} onClick={()=>{setCountry(c);setDomain(g)}} title={`Open ${g} in ${countryName(lk,c)}`}><strong>{x.text}</strong><small>{x.small}</small>{x.pct!=null&&<span className="dd-bar" role="img" aria-label={`${Math.round(x.pct)}% complete`}><i style={{width:`${Math.min(100,x.pct)}%`}}/></span>}</button></td>})}
          </tr>})}
      </tbody></table></div>
      {/* CF-247 s1282 (DR-19 increment 2): from a field of this matrix to a provider's records, by hold or recovery class, each opening its trace */}
      <RecordDrill label="Records by field, hold or recovery" rank={rank}/>
      {(measure==='canonical'||measure==='published')&&<div className="sl-sub" data-pim-basis-legend><strong>Gain bases in this view.</strong> A gain is counted on the basis its field reports; fields on different bases are not added, and a cell that spans two shows Mixed bases.
        <ul>{byBasis(rows).map(([b,g])=>{const ds=domains.filter(([,fs])=>g.some(r=>fs.has(r.field))).map(([d])=>d);return <li key={b||'none'} data-pim-basis-item>{basisWord(b)}: {ds.join(', ')||'—'}</li>})}</ul></div>}

      {activeDomain&&<><h5 className="sl-h4" data-pim-fields-title>{activeDomain} in {scopeLabel}: by field</h5>
        <div className="lf-frame"><table className="cf-table pim-fields" data-pim-fields><thead><tr><th>Field</th>{!country&&<th>Country</th>}<th>Applicable</th><th>Completed</th><th>Backlog</th><th>Items queued</th><th>Items running</th><th>Items held</th><th>Items failed</th><th>Gain</th><th>Per hour</th><th>Clearance</th><th>Oldest outstanding</th></tr></thead><tbody>
          {scope.filter(r=>domainFields.has(r.field)).sort((a,b)=>String(a.field).localeCompare(b.field)||String(a.country).localeCompare(b.country)).map(r=>{
            const app=Number(r.applicable)
            return <tr key={`${r.country}-${r.field}`} data-pim-field={r.field} data-pim-country-row={r.country}>
              <td data-label="Field"><V>{labelOf(r.field)}<small>{r.field}</small></V></td>{!country&&<td data-label="Country">{countryName(lk,r.country)}</td>}
              <td data-label="Applicable">{!has(r.applicable)?<NotMeasured/>:app>0?num(r.applicable):<NotMeasured word="None apply" reason={Number(r.not_applicable)>0?`${fmtNumber(Number(r.not_applicable))} recorded not applicable`:null}/>}</td>
              <td data-label="Completed">{!has(r.held)?<NotMeasured/>:app>0?<V><strong>{num(r.held)}</strong><small>{pctText(Number(r.held),app)}</small></V>:'—'}</td>
              <td data-label="Backlog">{has(r.backlog)?num(r.backlog):<NotMeasured/>}</td><td data-label="Items queued">{has(r.queued)?num(r.queued):<NotMeasured/>}</td><td data-label="Items running">{has(r.running)?num(r.running):<NotMeasured/>}</td>
              <td data-label="Items held">{has(r.review)||has(r.no_source_found)?<V>{fmtNumber((Number(r.review)||0)+(Number(r.no_source_found)||0))}<small>{fmtNumber(Number(r.review)||0)} review · {fmtNumber(Number(r.no_source_found)||0)} no source</small></V>:<NotMeasured/>}</td>
              <td data-label="Items failed">{has(r.failed)?num(r.failed):<NotMeasured/>}</td>
              <td data-label="Gain" data-pim-gain-cell>{has(r.canonical_gain_window)?<V>{Number(r.canonical_gain_window)>0?`+${num(r.canonical_gain_window)}`:'0'}<small>{Number(r.canonical_gain_window)>0?'canonical':'measured: none'}</small>{has(r.published_gain_window)?<small>{fmtNumber(Number(r.published_gain_window))} published-provider</small>:<small>published-provider: not measured</small>}<small className="pim-basis-cell" data-pim-row-basis title={basisWord(r.gain_basis)}>{basisWord(r.gain_basis)}</small></V>:<NotMeasured/>}</td>
              <td data-label="Per hour">{!has(r.throughput_per_hour)?<NotMeasured/>:Number(r.throughput_per_hour)===0?<V>0<small>measured: none gained</small></V>:fmtNumber(Number(r.throughput_per_hour))}</td>
              <td data-label="Clearance">{!has(r.backlog)?<NotMeasured/>:Number(r.backlog)===0?'Nothing outstanding':r.clearance_hours==null?<NotMeasured reason="Nothing gained in the window"/>:durText(r.clearance_hours)}</td>
              <td data-label="Oldest outstanding">{r.oldest_outstanding?fmtDateTime(r.oldest_outstanding):'—'}</td>
            </tr>})}
        </tbody></table></div></>}

      <h5 className="sl-h4" data-pim-section="processing">Processing: scheduler, worker, leases and recovery</h5>
      <div className="pim-proc" data-pim-processing>
        <div><span>Last queue pass</span>{lastRun?<><strong data-pim-last-run>{fmtDateTime(lastRun)}</strong><small>{fmtRelative(lastRun,'',now)}{pim.gap_queue?.cycle_scanned!=null?` · scanned ${fmtNumber(Number(pim.gap_queue.cycle_scanned))}, found ${fmtNumber(Number(pim.gap_queue.cycle_found))}`:''}</small></>:<NotMeasured reason="The gap queue has not recorded a pass."/>}</div>
        <div><span>Next scheduled run</span>{nextRun?<><strong data-pim-next-run>{fmtDateTime(nextRun)}</strong><small>{untilText(nextRun,now)}</small></>:<NotMeasured reason="No active scheduled job has a next run."/>}</div>
        <div><span>Expired leases</span>{pim.leases?<><strong data-pim-leases={pim.leases.expired}>{fmtNumber(Number(pim.leases.expired))}</strong><small>{pim.leases.recovery}</small></>:has(ops?.expired_leases)?<><strong data-pim-leases={ops.expired_leases}>{fmtNumber(Number(ops.expired_leases))}</strong><small>counted in the worker status read</small></>:<NotMeasured reason="Leases were not counted."/>}</div>
        <div><span>Stalled workers</span>{Array.isArray(ops?.workers)&&has(ops?.stalled_workers)?<><strong data-pim-stalled={ops.stalled_workers}>{fmtNumber(Number(ops.stalled_workers))}</strong><small>of {fmtNumber(ops.workers.length)} scheduled jobs{ops.jobs_summary_at?`; job summary read ${ageWord(minutesAgo(ops.jobs_summary_at,now))}`:''}</small></>:<NotMeasured reason="The worker status is not in this PIM snapshot yet, so stalled processing is not shown."/>}</div>
      </div>
      {jobs.length>0&&<div className="lf-frame"><table className="cf-table pim-jobs" data-pim-jobs><thead><tr><th>Scheduled job</th><th>State</th><th>Schedule</th><th>Next run</th></tr></thead><tbody>
        {jobs.map(j=><tr key={j.job} data-pim-job={j.job}><td data-label="Scheduled job">{j.job}</td><td data-label="State">{j.active?<StatusChip tone="success" label="On"/>:<StatusChip tone="warning" label="Off"/>}</td><td data-label="Schedule"><code>{j.schedule||'—'}</code></td><td data-label="Next run">{j.next_run?`${fmtDateTime(j.next_run)} (${untilText(j.next_run,now)})`:j.active?<NotMeasured reason="No next run is recorded."/>:'—'}</td></tr>)}</tbody></table></div>}

      {/* s1283: the 138-row workers table is replaced by the backend-classified summary; the full list, filters and drill-down are Scheduled jobs › Automations */}
      <JobsSummary ops={ops}/>

      <h5 className="sl-h4" data-pim-section="consumer">Verified consumer read-back</h5>
      <p className="sl-sub" data-pim-consumer-meaning>Matched out of expected, per stream and country, from the verified read-back of what the website and Zoho read. Each stream counts a different kind of record, so streams are never added together. Not served is expected but not offered to that consumer (for example the provider is hidden or blocked in Layer 4); it is not counted as missing.</p>
      {Array.isArray(ops?.consumer)&&ops.consumer.length?<div className="lf-frame"><table className="cf-table pim-consumer" data-pim-consumer><thead><tr><th>Stream</th><th>Country</th><th>Expected</th><th>Website</th><th>Zoho</th><th>Read</th></tr></thead><tbody>
        {ops.consumer.flatMap(st=>{const label=streamTitle(st.stream),ago=minutesAgo(st.measured_at,now),stale=staleMinutes!=null&&ago!=null&&ago>Number(staleMinutes)
          const rowsC=(Array.isArray(st.rows)?st.rows:[]).filter(r=>!country||r.cc===country)
          if(st.error||!Array.isArray(st.rows))return [<tr key={st.stream} data-pim-consumer-stream={st.stream} data-pim-consumer-error><td data-label="Stream">{label}</td><td colSpan={5}><NotMeasured reason={`Could not be read${st.error?`: ${st.error}`:''}${st.measured_at?` (last read ${ageWord(ago)})`:''}.`}/></td></tr>]
          if(!rowsC.length)return []
          return rowsC.map((r,i)=><tr key={`${st.stream}-${r.cc}`} data-pim-consumer-stream={st.stream} data-pim-consumer-country={r.cc}><td data-label="Stream">{i===0?label:<small>{label}</small>}</td><td data-label="Country">{countryName(lk,r.cc)}</td>
            <td data-label="Expected">{has(r.expected)?fmtNumber(Number(r.expected)):<NotMeasured/>}</td><td data-label="Website"><ConsumerCell r={r} c="w"/></td><td data-label="Zoho"><ConsumerCell r={r} c="z"/></td>
            <td data-label="Read"><V>{ageWord(ago)}{stale&&<StatusChip tone="warning" label="Stale"/>}</V></td></tr>)})}</tbody></table></div>
        :<NotMeasured word="Not available" reason="The PIM snapshot carries no consumer read-back yet."/>}
      {/* s1288: the rotating sample behind the same reads (consumer_fields); counts the checked courses only, never extrapolated */}
      <ConsumerSample ops={ops} streamTitle={id=>(Array.isArray(streams)?streams.find(x=>x.stream===id)?.title:null)||SAMPLE_TITLE[id]}/>

      <h5 className="sl-h4" data-pim-section="consumption">Consumption in the last {hoursWord(hours)}</h5>
      <div className="pim-proc" data-pim-consumption>
        <div><span>AI attempts</span>{pim.ai?<><strong data-pim-ai-attempts>{fmtNumber(Number(pim.ai.attempts))}</strong><small>{fmtNumber(Number(pim.ai.failed))} failed</small></>:<NotMeasured/>}</div>
        <div><span>AI spend</span>{pim.ai?.cost_usd==null?<NotMeasured reason="Billed cost is blank until measured."/>:<><strong data-pim-ai-cost>{fmtMoney(Number(pim.ai.cost_usd),'USD',{decimals:2})}</strong><small>billed, every attempt included</small></>}</div>
        <div><span>Firecrawl calls</span>{pim.firecrawl?<><strong data-pim-fc-calls>{fmtNumber(Number(pim.firecrawl.calls))}</strong><small>{fmtNumber(Number(pim.firecrawl.credits))} credits</small></>:<NotMeasured/>}</div>
      </div>

      <h5 className="sl-h4" data-pim-section="human">Needs a person</h5>
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
      {Array.isArray(pim.requests)&&pim.requests.length>0?<><h5 className="sl-h4" data-pim-section="requests">Stakeholder requests</h5>
        <p className="sl-sub">Status keeps the Request Register Rules v1.3 meanings. Canonical coverage, consumer coverage (as the register reports it) and freshness of a request&rsquo;s scope sit beside the status as separate figures and never change it.</p>
        <div className="lf-frame"><table className="cf-table pim-requests" data-pim-requests><thead><tr><th>Request</th><th>Scope</th><th>Status</th><th>Weight</th><th>Canonical coverage</th><th>Consumer coverage</th><th>Freshness</th><th>Clarification</th></tr></thead><tbody>
          {pim.requests.map((r,i)=><tr key={r.id||i} data-pim-request={r.id||i}><td data-label="Request"><strong>{r.id}</strong><small>{r.title}</small></td><td data-label="Scope">{r.scope||<NotMeasured word="Unknown"/>}</td>
            <td data-label="Status">{r.status?<StatusChip tone="neutral" label={r.status}/>:<NotMeasured word="Unknown"/>}</td><td data-label="Weight">{r.weight==null?<NotMeasured word="Unknown"/>:fmtNumber(Number(r.weight))}</td>
            <td data-label="Canonical coverage">{r.canonical_pct==null?<NotMeasured/>:`${fmtNumber(Number(r.canonical_pct),{maxDecimals:1})}%`}</td><td data-label="Consumer coverage">{r.consumer_pct==null?<NotMeasured/>:`${fmtNumber(Number(r.consumer_pct),{maxDecimals:1})}%`}</td>
            <td data-label="Freshness">{r.fresh_pct==null?<NotMeasured/>:`${fmtNumber(Number(r.fresh_pct),{maxDecimals:1})}%`}</td><td data-label="Clarification">{r.clarification||'None'}</td></tr>)}</tbody></table></div></>
      :<div data-pim-requests-unavailable><h5 className="sl-h4" data-pim-section="requests">Stakeholder requests</h5>
        <NotMeasured word="Not available" reason="The request register is not part of the Data Delivery read yet (Master Plan section 6, interface 6, owned by S1-RM-Design). No request status, weight or request coverage is shown, and none is estimated."/>
        {ops?.requests?.status==='not_projected'&&<p className="sl-sub" data-pim-requests-reason><strong>Why:</strong> {ops.requests.reason}</p>}
        <p className="sl-sub">When the read arrives this view shows each request&rsquo;s Rules v1.3 status beside its canonical coverage, consumer coverage and freshness as separate figures. The internal gap register is never shown here.</p></div>}
      <h5 className="sl-h4" data-pim-section="issues">Reported data issues</h5>
      <NotMeasured word="Not available" reason="No authoritative source for verified feedback has been resolved: counsellor reports are not tied to a verified re-check, so no fixed or verified figure is shown."/>
      <h5 className="sl-h4" data-pim-section="coverage">Coverage of any scope, available now</h5>
      <p className="sl-sub">The figures a request would show beside its status are the country and domain figures on the <button type="button" className="cf-link" data-pim-goto="matrix" onClick={()=>setView('matrix')}>Delivery matrix</button>. Verified consumer coverage is not counted as a share yet; the matrix shows published-provider gain in the window, which is not a delivery check.</p>
    </div>}

    {view==='refresh'&&<div data-pim-panel="refresh">
      {pim.refresh?<>
        <h5 className="sl-h4" data-pim-section="freshness">Freshness of held values</h5>
        <p className="sl-sub" data-pim-refresh-meaning>{pim.refresh.meaning} Refresh window: {fmtNumber(Number(pim.refresh.window_days))} days. This first table is by field across all countries; the next is by country and field.</p>
        <div className="lf-frame"><table className="cf-table pim-refresh" data-pim-refresh><thead><tr><th>Field</th><th>Values held</th><th>Due to be verified</th><th>Fresh</th><th>Oldest verified</th></tr></thead><tbody>
          {(pim.refresh.fields||[]).map(f=>{const h=Number(f.held),d=Number(f.refresh_due)
            return <tr key={f.field} data-pim-refresh-field={f.field}><td data-label="Field"><V>{labelOf(f.field)}<small>{f.field}</small></V></td><td data-label="Values held">{fmtNumber(h)}</td><td data-label="Due to be verified">{fmtNumber(d)}</td>
              <td data-label="Fresh">{h>0?<V><strong>{pctText(h-d,h)}</strong><span className="dd-bar" role="img" aria-label={`${pctText(h-d,h)} fresh`}><i style={{width:`${Math.min(100,(h-d)/h*100)}%`}}/></span></V>:<NotMeasured word="None held"/>}</td>
              <td data-label="Oldest verified">{f.oldest_verified?fmtDateTime(f.oldest_verified):<NotMeasured word="Unknown"/>}</td></tr>})}</tbody></table></div>
        <h5 className="sl-h4" data-pim-section="fresh-country">Freshness by country</h5>
        {Array.isArray(ops?.freshness_by_country)&&ops.freshness_by_country.length?<>
          <div className="pim-controls"><label>Country <select value={country} onChange={e=>setCountry(e.target.value)} data-pim-fresh-country><option value="">All countries</option>{countries.map(c=><option key={c} value={c}>{countryName(lk,c)}</option>)}</select></label></div>
          <div className="lf-frame"><table className="cf-table pim-refresh" data-pim-fresh-by-country><thead><tr><th>Field</th><th>Country</th><th>Values held</th><th>Due to be verified</th><th>Fresh</th></tr></thead><tbody>
            {ops.freshness_by_country.filter(f=>!country||f.country===country).slice().sort((a,b)=>String(a.country).localeCompare(b.country)||labelOf(a.field).localeCompare(labelOf(b.field))).map(f=>{const h=Number(f.held),d=Number(f.refresh_due)
              return <tr key={`${f.country}-${f.field}`} data-pim-fresh-row={`${f.country}-${f.field}`}><td data-label="Field"><V>{labelOf(f.field)}<small>{f.field}</small></V></td><td data-label="Country">{countryName(lk,f.country)}</td>
                <td data-label="Values held">{has(f.held)?fmtNumber(h):<NotMeasured/>}</td><td data-label="Due to be verified">{has(f.refresh_due)?fmtNumber(d):<NotMeasured/>}</td>
                <td data-label="Fresh">{!has(f.held)||!has(f.refresh_due)?<NotMeasured/>:h>0?<V><strong>{pctText(h-d,h)}</strong><span className="dd-bar" role="img" aria-label={`${pctText(h-d,h)} fresh`}><i style={{width:`${Math.min(100,(h-d)/h*100)}%`}}/></span></V>:<NotMeasured word="None held"/>}</td></tr>})}</tbody></table></div>
          <p className="sl-sub">The oldest verified date is counted by field across all countries (first table), not by country.</p></>
          :<NotMeasured word="Not available" reason="The PIM snapshot carries no freshness by country yet."/>}
        <h5 className="sl-h4" data-pim-section="sources">Source outcomes</h5>
        <p className="sl-sub">Pages bound to courses, by their last read. A protected hold (blocked or robots disallowed) keeps its held values in coverage; nothing is read around it.</p>
        <div className="lf-frame"><table className="cf-table pim-sources" data-pim-sources><thead><tr><th>Outcome</th><th>Pages</th><th>Due for re-read</th><th>Protected hold</th></tr></thead><tbody>
          {(pim.refresh.sources||[]).map(s=><tr key={s.outcome} data-pim-source={s.outcome}><td data-label="Outcome">{word(s.outcome)}</td><td data-label="Pages">{fmtNumber(Number(s.pages))}</td><td data-label="Due for re-read">{fmtNumber(Number(s.due_for_reread))}</td><td data-label="Protected hold">{s.protected_hold?'Yes':'No'}</td></tr>)}</tbody></table></div></>
      :<NotMeasured word="Not available" reason="The snapshot carries no refresh figures."/>}
      {pim.excluded?<><h5 className="sl-h4" data-pim-section="excluded">Excluded gaps</h5>
        <p className="sl-sub" data-pim-excluded-meaning>{pim.excluded.meaning}</p>
        <dl className="pim-funnel" data-pim-excluded-totals>{Object.entries(pim.excluded.totals||{}).map(([k,v])=><div key={k} data-pim-excluded={k}><dt>{word(k)}</dt><dd><strong>{fmtNumber(Number(v))}</strong><small>gaps</small></dd></div>)}</dl>
        <div className="lf-frame"><table className="cf-table pim-excluded" data-pim-excluded-fields><thead><tr><th>Field</th><th>Reason</th><th>Gaps</th><th>Next revisit</th></tr></thead><tbody>
          {(pim.excluded.by_field||[]).map((x,i)=><tr key={`${x.field}-${x.reason}-${i}`}><td data-label="Field">{labelOf(x.field)}</td><td data-label="Reason">{word(x.reason)}</td><td data-label="Gaps">{fmtNumber(Number(x.gaps))}</td><td data-label="Next revisit">{x.next_revisit?fmtDateTime(x.next_revisit):'—'}</td></tr>)}</tbody></table></div></>:null}
      {pim.lifecycle?<><h5 className="sl-h4" data-pim-section="lifecycle">Academic entry by country</h5>
        <div className="lf-frame"><table className="cf-table pim-lifecycle" data-pim-academic><thead><tr><th>Country</th><th>Stage</th><th>Courses</th><th>Next owner</th></tr></thead><tbody>
          {(pim.lifecycle.academic_entry?.stages||[]).map((s,i)=><tr key={`${s.country}-${s.stage}-${i}`}><td data-label="Country">{countryName(lk,s.country)}</td><td data-label="Stage">{word(s.stage)}</td><td data-label="Courses">{fmtNumber(Number(s.courses))}</td><td data-label="Next owner">{pim.lifecycle.academic_entry?.next_owner?.[s.stage]||<NotMeasured word="Unknown"/>}</td></tr>)}</tbody></table></div>
        <h5 className="sl-h4" data-pim-section="scholarships">Scholarships by country</h5>
        <p className="sl-sub">Owner: {pim.lifecycle.scholarships?.owner||'not recorded'}.</p>
        <div className="lf-frame"><table className="cf-table pim-lifecycle" data-pim-scholarships><thead><tr><th>Country</th><th>Disposition</th><th>Providers</th><th>Published</th><th>Reviews pending</th></tr></thead><tbody>
          {(pim.lifecycle.scholarships?.providers||[]).map((s,i)=><tr key={`${s.country}-${s.disposition}-${i}`}><td data-label="Country">{countryName(lk,s.country)}</td><td data-label="Disposition">{word(s.disposition)}</td><td data-label="Providers">{fmtNumber(Number(s.providers))}</td><td data-label="Published">{fmtNumber(Number(s.scholarships_published))}</td><td data-label="Reviews pending">{fmtNumber(Number(s.reviews_pending))}</td></tr>)}</tbody></table></div>
        {pim.lifecycle.replacement_check&&<p className="sl-sub" data-pim-replacement><strong>Replacement check.</strong> {fmtNumber(Number(pim.lifecycle.replacement_check.checked))} guarded supersessions tested; {fmtNumber(Number(pim.lifecycle.replacement_check.flagged))} lost their successor and need a person. {pim.lifecycle.replacement_check.meaning}</p>}</>:null}
      {links}
    </div>}
  </section>
}
