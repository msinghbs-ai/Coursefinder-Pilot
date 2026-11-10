// Read / refresh entry requirements now (CF-247 F-AER.01-.06, Platform Admin decision 10 Nov 2026 19:47: the one primary outcome action for academic entry requirements).
// One action and one stage timeline for a university (its entry-requirement matrix and the course-level reading) or for one course, in the AER workspace, the Provider detail
// and the Course detail blade. The action composes the EXISTING readers on the server (stored copy of the page first, read again of a failed source, replay of a held read,
// first reads of courses whose bound page is already stored) through public.admin_aer_read_now; no other job, scheduler or reader, no scraper and no page search.
// The server decides and records every request (pipeline.admin_control_events, area aer_read_now), so closing the browser loses nothing: this panel only asks again and shows
// what the server holds. Every figure and sentence on the page comes from the server. Nothing here is a number except the poll interval.
// Stages are reported separately and in the words of what is true: a packet awaiting a person is never called published; consumer visibility is not measured here and is never 0.
import React,{useCallback,useEffect,useState}from'react'
import{GraduationCap}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Loading,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{ReasonAction}from'./ProviderOnboarding'
import{plainError}from'./lib/errors'
import{hrefFor}from'./nav-map'
import'./aer-read-now.css'

const POLL_MS=15000 // fixed: how often an open panel looks again while a read is waiting or running (a screen refresh, not an operating value)

const call=async args=>{const{data,error}=await supabase.rpc('admin_aer_read_now',{p_args:args});if(error)throw error;return data}

// The nine outcomes the server can give, each in its own words; none stands in for another.
export const OUTCOME={
  queued:['info','Ready to start'],
  in_progress:['info','In progress'],
  human_review_required:['warning','Waiting for a person'],
  already_up_to_date:['success','Already up to date'],
  no_eligible_work:['neutral','No eligible work'],
  source_unavailable:['warning','Source unavailable'],
  switch_off:['neutral','Switched off'],
  budget_reached:['warning','Budget reached'],
  permission_denied:['danger','Permission denied'],
}
// What the evidence says, in words. A label from the server (worked out from the stored state and reason; never from a guess that a field was searched).
export const KIND={
  no_source_found:'No official source found',
  source_found_not_read:'Source found, not read',
  tried_not_found:'Read, no requirement kept',
  technical_failure:'Technical failure, can be retried',
  budget_hold:'Budget hold',
  human_review:'Waiting for a person',
}
const STAGE_TONE={done:['success','Done'],partial:['info','Partly'],waiting:['warning','Waiting for a person'],none:['neutral','None yet'],unknown:['neutral','Not measured']}
const FACT_LABEL={country:'country',qualification:'qualification',grade:'grade',scale:'scale',applicability:'applicability',source_page:'source page',year:'year'}
const factsText=m=>Object.entries(m||{}).map(([k,n])=>`${fmtNumber(Number(n))} ${FACT_LABEL[k]||k}`).join(', ')

const when=v=>v?fmtDateTime(v):'time not recorded'
function Source({s}){
  if(!s)return null
  if(!s.recorded)return <p className="arn-muted arn-source" data-arn-source="none">Source examined: {s.kind==='course_page'?'no official page is recorded for this course.':'no entry source is recorded for this provider.'}</p>
  if(s.kind==='course_page'){const l=s.last_read
    return <div className="arn-source" data-arn-source="course_page"><strong>Source examined:</strong> <a className="cf-link arn-url" href={s.url} target="_blank" rel="noopener noreferrer">{s.url}</a>
      <small className="arn-muted"> Page {s.binding||'status not recorded'}{s.matched_by?`, matched by ${String(s.matched_by).replace(/_/g,' ')}`:''}; {s.stored?`stored copy captured ${when(s.captured_at)}${s.content_hash?` (hash ${s.content_hash})`:''}`:'no stored copy'}.
      {l?` Last read ${when(l.at)}: ${l.state}${l.recorded_reason?` — ${l.recorded_reason}`:''}.`:' No read is recorded.'}</small></div>}
  return <div className="arn-source" data-arn-source="matrix_sources"><strong>Source examined</strong> ({fmtNumber(Number(s.count))}):
    <ul className="arn-sources">{(s.sources||[]).map((x,i)=><li key={i} data-arn-source-row={x.status}><a className="cf-link arn-url" href={x.url} target="_blank" rel="noopener noreferrer">{x.url}</a>
      <small className="arn-muted"> {x.status}{x.http_status?` (HTTP ${x.http_status})`:''}; {x.stored?'stored copy held':'no stored copy'}{x.content_hash?`, hash ${x.content_hash}`:''}; read {when(x.read_at)}.
      {x.last_run?` Last run: ${x.last_run.state}, ${x.last_run.rows_kept==null?'rows kept not recorded':`${fmtNumber(Number(x.last_run.rows_kept))} row(s) kept`}${x.last_run.error?` — ${x.last_run.error}`:''}.`:' No run is recorded.'}{x.error&&!x.last_run?` Recorded: ${x.error}.`:''}</small></li>)}</ul></div>
}

export default function AerReadNow({providerId,courseId,onChanged,onError,className=''}){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[res,setRes]=useState(null)
  const args=courseId?{course_id:courseId}:{provider_id:providerId}
  const key=courseId?`c:${courseId}`:`p:${providerId}`
  const load=useCallback(async()=>{try{setD(await call({action:'status',...args}));setErr('')}catch(e){const m=plainError(e);setErr(m);onError?.(m)}},[key])
  useEffect(()=>{if(!providerId&&!courseId)return;setD(null);setRes(null);load()},[key])
  const inFlight=d?.outcome?.outcome==='in_progress'
  useEffect(()=>{if(!inFlight)return;const t=setInterval(load,POLL_MS);return()=>clearInterval(t)},[inFlight,load])
  if(!providerId&&!courseId)return null
  if(err&&!d)return <p className="fr-error" role="alert" data-aer-read-now="error">{err}</p>
  if(!d)return <div className="arn" data-aer-read-now="loading"><Loading compact label="Checking the entry requirements…"/></div>
  if(Array.isArray(d)||(d.known!==false&&!d.stages))return null
  if(d.known===false)return <p className="arn-muted" data-aer-read-now="unknown">{d.reason}</p>
  const o=d.outcome||{},[tone,label]=OUTCOME[o.outcome]||['neutral',String(o.outcome||'—')]
  const scope=d.scope,start=o.outcome==='queued'&&d.can_run
  const run=async note=>{try{const x=await call({action:'run',...args,note});setRes(x);await load();onChanged?.(x)}catch(e){const m=plainError(e);setErr(m);onError?.(m);throw e}}
  const l4=hrefFor('layer4','inbox',{provider:d.provider?.id})
  const f=d.facts||{}
  return <section className={`arn ${className}`.trim()} data-aer-read-now={scope} aria-label="Read or refresh entry requirements now">
    <div className="arn-head"><h3><GraduationCap size={14}/> Read / refresh entry requirements now</h3>
      <small className="arn-muted">{scope==='course'?`Course: ${d.course?.title||''}`:`${d.provider?.name||''}${d.provider?.country?` · ${d.provider.country}`:''}`}</small></div>
    <p className="arn-lead">{scope==='course'?'Reads this course’s requirements from the stored copy of its official page.':'Reads the university’s entry-requirement matrix and its courses’ requirements from what is already stored.'} {' '}
      Every result waits in Layer 4 for a person; nothing becomes active until a person approves it.</p>
    <div className="arn-outcome" role="status" data-arn-outcome={o.outcome} data-arn-reason={o.reason||undefined}>
      <StatusChip tone={tone} label={label}/> {o.class&&<span data-arn-class={o.class}><StatusChip tone="neutral" label={KIND[o.class]||o.class}/></span>} <span className="arn-text">{o.text}</span>
      {o.next_action&&<small className="arn-muted arn-next" data-arn-next> Next: {o.next_action}</small>}
    </div>
    <Source s={d.source}/>
    {(d.blocks||[]).length>0&&<ul className="arn-blocks" aria-label="Also held back" data-arn-blocks>{d.blocks.map((b,i)=><li key={i} data-arn-block={b.outcome}><StatusChip tone={(OUTCOME[b.outcome]||['neutral'])[0]} label={(OUTCOME[b.outcome]||[0,b.outcome])[1]}/> {b.text}</li>)}</ul>}
    {err&&<p className="fr-error" role="alert" data-arn-error>{err}</p>}
    <div className="arn-actions">
      <ReasonAction label="Read / refresh entry requirements now" confirm="Start" variant="primary" testid="aer-read-now" disabled={!start} onDo={run} placeholder="Why now (kept in the log)"/>
      {!d.can_run&&<small className="arn-muted" data-arn-permission>Starting needs the Platform Admin role. You can see what would happen.</small>}
      {d.can_run&&!start&&<small className="arn-muted" data-arn-nothing>Nothing to start right now: see the reason above.</small>}
      <a className="cf-link" href={l4} data-arn-layer4>Open Layer 4</a>
    </div>
    {res&&<p className="arn-result" role="status" data-arn-result={res.outcome}>
      {res.outcome==='queued'?`Started ${fmtNumber((res.started||[]).length)} read(s). You can close this page: they carry on, and the stages below update.`:res.text}
      {(res.skipped||[]).length>0&&<span className="arn-muted"> {fmtNumber(res.skipped.length)} request(s) were refused by the reader.</span>}</p>}
    <ol className="arn-stages" aria-label="Where the entry requirements stand" data-arn-stages>
      {(d.stages||[]).map(s=>{const[t,l]=STAGE_TONE[s.state]||['neutral',String(s.state)];return <li key={s.key} data-arn-stage={s.key} data-arn-state={s.state}>
        <span className="arn-stage-head"><strong>{s.label}</strong> <StatusChip tone={t} label={l}/> <span className="arn-n" data-arn-n={s.key}>{s.n==null?'Not measured':`${fmtNumber(Number(s.n))}${s.unit?` ${s.unit}${Number(s.n)===1?'':'s'}`:''}`}</span></span>
        <small className="arn-muted">{s.detail}</small></li>})}
    </ol>
    {Number(f.rows_in_reviewer_ready_packets)>0&&<p className="arn-facts" data-arn-facts>
      <strong>Facts for the reviewer:</strong> {fmtNumber(Number(f.rows_every_fact_stated))} of {fmtNumber(Number(f.rows_in_reviewer_ready_packets))} rows in complete packets state the country, qualification, grade, scale, applicability, source page and year.
      {Number(f.rows_with_a_fact_not_stated)>0&&<> {fmtNumber(Number(f.rows_with_a_fact_not_stated))} row(s) have a fact the page does not state ({factsText(f.not_stated)}); each is flagged for the reviewer and is never filled in or inferred.</>}</p>}
    <p className="arn-muted arn-foot" data-arn-foot>
      {d.last_request?`Last request ${fmtDateTime(d.last_request.at)}: ${(OUTCOME[d.last_request.outcome]||[0,d.last_request.outcome])[1].toLowerCase()}. `:'Not asked from this page yet. '}
      {d.next_scheduled_read?`The scheduled reader runs next at ${fmtDateTime(d.next_scheduled_read)}.`:'The scheduled reader’s next run is not known.'}
    </p>
  </section>
}
