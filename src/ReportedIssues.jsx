// CF-247 s1285 (Reported data issues R3, SS-Programme-Control 26 Nov 2026 22:52 AEDT; design admin
// docs/platform/2026-11-26-dr19-record-journey-and-diagnosis-design.md section 8): one Layer 4 view of every reported data issue, whichever way it
// came in (Admin and Portal through the in-app store of R1, Zoho through the Zoho store), with its origin, Reported or Resolved state, the evidence
// behind a resolution and, when opened, the field trace (s1282) and the existing Processing journey and diagnosis fold (s1272).
// It reads one function, public.admin_reported_issues_v1, only when opened. Decisions stay on the existing Layer 4 cards
// (counsellor_feedback and counsellor_report): this view links to them and changes nothing.
import React,{useEffect,useState}from'react'
import{StatusChip,Button,fmtNumber}from'./ui-kit'
import{fmtDateTime}from'./lib/format.js'
import{hrefFor}from'./nav-map'
import Layer4Journey from'./Layer4Journey'
import{FieldTrace,readTrace}from'./RecordTrace'
import{readReports,originWord}from'./reportFlags'
import'./layer4-item-lifecycle.css'

const word=s=>String(s??'').replace(/_/g,' ')
const when=v=>v?fmtDateTime(v):''
const STAGE={received:['Reported','warning'],investigating:['Reported: investigating','warning'],awaiting_input:['Reported: asked the reporter','warning'],
  awaiting_verification:['Reported: fixed, awaiting verification','info'],fixed:['Resolved: fixed','success'],not_changed:['Resolved: not changed','neutral']}
const stageChip=s=>{const[l,t]=STAGE[s]||[word(s)||'Unknown','neutral'];return <StatusChip tone={t} label={l}/>}
const OUTCOME={verified:'the catalogue holds a value and the consumer read serves the changed value',catalogue_not_verified:'the catalogue holds no value for this field',
  consumer_not_serving:'the consumer read serves nothing for this field',consumer_unchanged:'the consumer read still serves the value that was reported',
  consumer_not_expected_value:'the consumer read does not serve the expected value',unsupported_field:'this field has no consumer key to check'}

/** The evidence behind a report's state: R1's check when held, else the current field state, said as such. */
export function Evidence({e,state}){
  if(!e)return null
  const warn=e.fixed_without_evidence&&<StatusChip tone="danger" label="Fixed, but no value is held" className="ri-nofix"/>
  if(e.basis==='verification')return <p className="l4lc-ref" data-ri-evidence="verification">{warn} Check {when(e.checked_at)}: {OUTCOME[e.outcome]||word(e.outcome)}{e.consumer_key?` (consumer key ${e.consumer_key})`:''}.</p>
  if(e.basis==='current_state')return <p className="l4lc-ref" data-ri-evidence="current_state">{warn} Current field state{state==='resolved'?', not a check made when it was closed':''}: {e.completeness==='verified'?'a value is held':e.completeness==='none'?'no value is held':'not measured'}{e.last_verified_at?`, last confirmed ${when(e.last_verified_at)}`:''}{e.applicable===false?', the field does not apply to this course':''}. The value itself is not verified here.</p>
  return <p className="l4lc-ref" data-ri-evidence="none">{warn} <em className="l4j-na" data-l4j-na>Not available ({e.why||'no evidence held'})</em></p>
}

/** One report opened: the trace of the reported field, the journey fold of its Layer 4 item, and links to the card and the course. */
function ReportTrace({x,rank}){
  const[t,setT]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{if(x.course_id&&x.field_code)readTrace(x.course_id,x.field_code).then(setT).catch(e=>setErr(e.message))},[x.ref])
  const f=(t?.fields||[]).find(y=>y.field===x.field_code)
  return <div className="ri-trace" data-ri-trace={x.ref}>
    <p className="ri-links">{x.state==='open'&&<a className="cf-link" href={hrefFor('layer4','inbox',{provider:x.provider_id||'',kind:x.l4_kind,ref:x.ref,review_at:x.created_at})} data-ri-card>Open the Layer 4 card</a>}
      {x.course_id&&<a className="cf-link" href={hrefFor('courses','',{id:x.course_id})} data-ri-course>Open the course record</a>}</p>
    {!x.course_id||!x.field_code?<p className="l4lc-ref"><em className="l4j-na" data-l4j-na>Not available ({!x.course_id?'not a course report':'the report names no register field'})</em>: no field trace.</p>
      :err?<p className="l4lc-err" role="alert">The field trace could not be read: {err}</p>
      :!t?<p className="l4lc-ref" role="status">Reading the field trace…</p>
      :f?<FieldTrace f={f} consumer={t.consumer} courseId={x.course_id} rank={rank}/>:<p className="l4lc-ref"><em className="l4j-na" data-l4j-na>Not available (the trace holds no {word(x.field_code)} field)</em></p>}
    <Layer4Journey kind={x.l4_kind} refId={x.ref}/>
  </div>
}

function ReportRow({x,rank}){
  const[open,setOpen]=useState(false)
  return <li className="ri-item" data-ri-item={x.ref} data-ri-origin={x.origin} data-ri-state={x.state}>
    <div className="ri-head">
      <StatusChip tone="info" label={originWord(x.origin)} className="ri-origin"/>{stageChip(x.stage)}
      <strong>{x.course||(x.entity==='provider'?x.provider:`${word(x.entity)} record`)}</strong>
      {x.course&&x.provider&&<small className="l4lc-ref">{x.provider}</small>}
    </div>
    <dl className="l4lc-steps ri-dl">
      <dt>Field</dt><dd data-ri-field>{x.field||(x.field_code?word(x.field_code):x.reported_field?`${word(x.reported_field)} (no register field)`:'Not given')}</dd>
      {(x.issue_labels||[]).length>0&&<><dt>Issue</dt><dd>{x.issue_labels.join(', ')}</dd></>}
      {x.note&&<><dt>Note</dt><dd>{x.note}</dd></>}
      {x.displayed&&<><dt>Value at report</dt><dd>{x.displayed}</dd></>}
      <dt>Reported</dt><dd>{when(x.created_at)}{Number(x.repeat)>1?<> · <StatusChip tone="warning" label={`Reported ${fmtNumber(Number(x.repeat))} times`}/></>:null}</dd>
      {x.state==='resolved'&&<><dt>Resolved</dt><dd>{x.resolved_at?when(x.resolved_at):<em className="l4j-na" data-l4j-na>Not available (no closing time recorded)</em>}{x.resolution_note?` · ${x.resolution_note}`:''}</dd></>}
      <dt>Evidence</dt><dd><Evidence e={x.evidence} state={x.state}/></dd>
    </dl>
    <button type="button" className="rt-toggle" aria-expanded={open} onClick={()=>setOpen(!open)} data-ri-open>Field trace and processing journey</button>
    {open&&<ReportTrace x={x} rank={rank}/>}
  </li>
}

/** The Layer 4 view: a closed panel above the queues, read only when opened. */
export default function ReportedIssues({rank=0}){
  const[open,setOpen]=useState(false),[origin,setOrigin]=useState('all'),[state,setState]=useState('open'),[offset,setOffset]=useState(0),[d,setD]=useState(null),[err,setErr]=useState('')
  const load=(o=offset)=>{setErr('');setD(null);readReports({origin,state,offset:o}).then(setD).catch(e=>setErr(e.message))}
  useEffect(()=>{if(open&&rank>=3)load(0)},[open,origin,state])
  if(rank<3)return null
  const by=d?.counts?.by_origin||{},fig=d?.figures||{},known=d?.counts?.origins_known||['admin','portal','zoho'],n=o=>by[o]?(state==='all'?Number(by[o].open)+Number(by[o].resolved):Number(by[o][state])||0):0
  const total=Number(d?.total)||0,lim=Number(d?.limit)||0
  return <section className="l4z-fold l4j ri" data-ri-panel data-ri-open={open?'true':'false'}>
    <button type="button" className="rt-toggle ri-toggle" aria-expanded={open} onClick={()=>setOpen(!open)} data-ri-toggle>Reported data issues (Admin, Portal and Zoho)</button>
    {open&&<div className="ri-body">
      {err&&<p className="l4lc-err" role="alert" data-ri-error>The reports could not be read: {err}</p>}
      {!d&&!err&&<p className="l4lc-ref" role="status">Reading the reports…</p>}
      {d&&<>
        <dl className="ri-figures" data-ri-figures>
          <div><dt>Submitted</dt><dd>{fmtNumber(Number(fig.submitted)||0)}</dd></div>
          <div><dt>Reported (open)</dt><dd>{fmtNumber(Number(fig.open)||0)}</dd></div>
          <div><dt>Awaiting verification</dt><dd>{fmtNumber(Number(fig.awaiting_verification)||0)}</dd></div>
          <div><dt>Resolved</dt><dd>{fmtNumber(Number(fig.resolved)||0)}{Number(fig.resolved)?` (${fmtNumber(Number(fig.fixed)||0)} fixed, ${fmtNumber(Number(fig.not_changed)||0)} not changed)`:''}</dd></div>
          <div><dt>Median time to resolve</dt><dd>{fig.median_resolution_hours==null?<em className="l4j-na" data-l4j-na>Not available (nothing resolved yet)</em>:`${fmtNumber(Number(fig.median_resolution_hours))} h`}</dd></div>
          <div><dt>Recurring course fields</dt><dd>{fmtNumber(Number(fig.recurring_course_fields)||0)} <small className="l4lc-ref">in {fmtNumber(Number(fig.recurrence_days)||0)} days</small></dd></div>
        </dl>
        <div className="rt-show" role="group" aria-label="Origin">
          <button type="button" aria-pressed={origin==='all'} onClick={()=>{setOrigin('all');setOffset(0)}} data-ri-origin-pick="all">All origins</button>
          {known.map(o=><button key={o} type="button" aria-pressed={origin===o} onClick={()=>{setOrigin(o);setOffset(0)}} data-ri-origin-pick={o}>{originWord(o)} ({fmtNumber(n(o))})</button>)}
        </div>
        <div className="rt-show" role="group" aria-label="State">
          {[['open','Reported'],['resolved','Resolved'],['all','All']].map(([k,l])=><button key={k} type="button" aria-pressed={state===k} onClick={()=>{setState(k);setOffset(0)}} data-ri-state-pick={k}>{l}</button>)}
        </div>
        <p className="l4lc-ref">The Portal reporter is not released yet, so Portal shows only what has arrived. Zoho reports are read from the Zoho store; their decisions stay on the Layer 4 card. Read {when(d.measured_at)} · <button type="button" className="l4j-refresh" onClick={()=>load(offset)}>Refresh</button></p>
        {total===0?<p className="l4lc-ref" data-ri-empty>0 reports{origin!=='all'?` from ${originWord(origin)}`:''}{state==='open'?' waiting':state==='resolved'?' resolved':''}.</p>
          :<ul className="ri-list" data-ri-list>{(d.items||[]).map(x=><ReportRow key={`${x.store}:${x.ref}`} x={x} rank={rank}/>)}</ul>}
        {total>lim&&<div className="l4i-pager"><Button compact disabled={offset===0} onClick={()=>{const o=Math.max(0,offset-lim);setOffset(o);load(o)}}>Previous</Button>
          <small className="l4lc-ref">{fmtNumber(offset+1)} to {fmtNumber(Math.min(offset+lim,total))} of {fmtNumber(total)}</small>
          <Button compact disabled={offset+lim>=total} onClick={()=>{const o=offset+lim;setOffset(o);load(o)}}>Next</Button></div>}
      </>}
    </div>}
  </section>
}
