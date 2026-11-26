// CF-247 s1282 (DR-19 increments 2 to 4, SS-Programme-Control 26 Nov 2026 22:52): the record-level view of the Processing journey and diagnosis
// for a course field, beside the Layer 4 card's fold (Layer4Journey, s1272). It renders only what S2-RM-Design's existing reads return:
// public.admin_pim_record_trace_v1 (one course, every registered field: state, producer, attempts, absence, open and decided Layer 4 items, the
// diagnosis class and permitted actions, and field-level Website v3 delivery), public.admin_pim_provider_trace_v1 (the same diagnosis over a
// provider's courses for one field: the per-record list behind Data Delivery's holds and recoveries) and
// public.admin_pim_operational_recovery_measure_v1 (realised recovery gain). Nothing is diagnosed here.
// Seven facts are kept apart and never stand in for each other: record returned by a consumer, field populated, field value verified,
// international applicability verified, canonical admission, consumer delivery and actual recovery gain. A consumer returning the record is
// never shown as proof that a field is right. Where the backend holds no evidence the row reads Not verified or Not available.
// Design: admin docs/platform/2026-11-26-dr19-record-journey-and-diagnosis-design.md (increments 2 to 4).
import React,{useEffect,useRef,useState}from'react'
import{supabase}from'./lib/supabase'
import{api}from'./lib/supabase'
import{StatusChip,Button,fmtNumber}from'./ui-kit'
import{fmtDateTime}from'./lib/format.js'
import{hrefFor}from'./nav-map'
import Layer4Journey,{STATE}from'./Layer4Journey'
import{useCourseReports,ReportFlag}from'./reportFlags' // CF-247 s1285 (R3): Reported and Resolved per field
import'./layer4-item-lifecycle.css'

const rpc=(fn,args)=>supabase.rpc(fn,args).then(({data,error})=>{if(error)throw new Error(error.message);return data})
// the field register (course fields and plain labels), through the same coverage read Data Delivery's PIM block uses; read once a page load
let regRead=null
const loadRegister=()=>{if(!regRead)regRead=rpc('admin_field_coverage',{p_action:'overview',p_args:{}}).then(d=>Array.isArray(d?.register)?d.register:[]).catch(e=>{regRead=null;throw e});return regRead}
export const readTrace=(course,field=null)=>rpc('admin_pim_record_trace_v1',{p_course:course,p_field:field})
export const readProviderTrace=(provider,field,cls=null)=>rpc('admin_pim_provider_trace_v1',{p_provider:provider,p_field:field,p_class:cls,p_limit:null})
export const readRecoveryMeasure=()=>rpc('admin_pim_operational_recovery_measure_v1',{})

// the diagnosis classes of security.pim_record_trace_v1, as plain words and a tone
export const CLASS={verified:['Value held','success'],not_applicable:['Does not apply','neutral'],protected_hold:['Protected or in review','warning'],in_progress:['Being read now','info'],
  operational_failure:['Service failure (retry)','warning'],data_exception:['Explained gap','neutral'],software_defect:['Needs engineering','danger'],partial:['Partly held','warning'],awaiting_first_read:['Not read yet','neutral']}
const clsChip=c=>{const[l,t]=CLASS[c]||[String(c||'unknown').replace(/_/g,' '),'neutral'];return <StatusChip tone={t} label={l}/>}
const word=s=>String(s??'').replace(/_/g,' ')
const NA=({why})=><em className="l4j-na" data-l4j-na title={why||undefined}>Not available{why?` (${why})`:''}</em>
const NV=({why})=><em className="l4j-na" data-rt-nv>Not verified{why?` (${why})`:''}</em>
const when=v=>v?fmtDateTime(v):''
// a Layer 4 review item opens the existing journey fold; the kind only steers the lifecycle read, which reads review items the same way for these kinds
const l4Kind=code=>code==='official_course_url'?'course_link':String(code||'').startsWith('provider_description')?'provider_description':'aer_review'

/** Increment 4: the seven facts, each from its own evidence. */
export function Verification({f,consumer}){
  const st=f.state||{},cf=f.consumer_field,comp=st.completeness,app=st.applicability||{}
  const hist=f.history||{},resolved=(hist.resolved_absences||[]),filledNow=(f.attempts||[]).some(a=>a.state==='filled')
  const w=consumer?.website_v3,z=consumer?.zoho_v3
  const yes=(t,tone='success')=><StatusChip tone={tone} label={t}/>
  const rows=[
    ['returned','Record returned by consumer',!consumer?<NA why="the consumer reads were not asked"/>:<>{w?.returned?yes('Website v3 returns it'):yes(w?.error?`Website v3: ${w.error}`:'Website v3 does not return it','neutral')} {z?.returned?yes('Zoho v3 returns it'):yes(z?.error?`Zoho v3: ${z.error}`:'Zoho v3 does not return it','neutral')}
      <small className="l4lc-ref"> Website v2 not read (frozen). A returned record says nothing about whether this field is right.</small></>],
    ['populated','Field populated',comp==='verified'?yes('A value is held'):comp==='none'?yes('No value held','neutral'):comp==='partial'?yes('Part of the value is held','warning'):<NA why={comp==='unmeasured'?'no held-value test for this field':'not measured'}/>],
    ['verified','Field value verified',f.field==='description'&&cf?.matches_canonical===true?<>{yes('Website text equals the catalogue','info')}<small className="l4lc-ref"> Consistency of delivery, not a check against the source.</small></>
      :<NV why={comp==='verified'?`a value is held${st.freshness?.last_verified_at?`, last checked ${when(st.freshness.last_verified_at)}`:''}; no independent check of the value is recorded`:'no value is held'}/>],
    ['international','International applicability verified',app.applicable===false?<>{yes('Does not apply to this course','neutral')}{app.reason&&<small className="l4lc-ref"> {app.reason}</small>}</>
      :<NA why="the field trace holds no international-applicability evidence"/>],
    ['admission','Canonical admission',comp==='verified'?yes('Admitted: the catalogue holds a value'):comp==='none'?yes('Not admitted','neutral'):<NA why="not measured for this field"/>],
    ['delivery','Consumer delivery',!cf?<NA why="the consumer reads were not asked"/>:cf.delivery==='not_mapped'?<NA why="this field has no Website v3 key"/>:cf.delivery==='not_read'?<NA why="Website v3 did not return the record"/>
      :<>{yes(cf.served?'Website v3 serves a value':'Website v3 serves no value',cf.served?'success':'neutral')}<small className="l4lc-ref"> {word(cf.delivery)}{cf.website_v3_key?` (key ${cf.website_v3_key})`:''}. Zoho per field: not measured.</small></>],
    ['gain','Actual recovery gain',resolved.length&&comp==='verified'?<>{yes('Realised: a gap was resolved and the value is now held')}<small className="l4lc-ref"> {resolved.length} resolved finding{resolved.length===1?'':'s'}, latest {when(resolved[0].resolved_at)}</small></>
      :filledNow&&comp==='verified'?yes('Realised: a read filled the value','success'):<NA why={resolved.length?'a gap was resolved but no value is held yet':'no recovery is recorded for this field'}/>],
  ]
  return <dl className="l4lc-steps rt-verify" data-rt-verify>{rows.map(([k,l,v])=><React.Fragment key={k}><dt>{l}</dt><dd data-rt-fact={k}>{v}</dd></React.Fragment>)}</dl>
}

/** One field of one course: the diagnosis, the seven facts, evidence, attempts, history and the authorised actions. */
export function FieldTrace({f,consumer,courseId,rank=0,rep=null}){
  const g=f.diagnosis||{},abs=f.absence,att=f.attempts||[],l4=f.layer4||[],hist=f.history||{}
  return <div className="rt-field" data-rt-field={f.field} data-rt-class={g.class}>
    <p className="l4j-stop"><strong>{f.label||word(f.field)}</strong> {clsChip(g.class)} <ReportFlag rep={rep} field={f.field}/> {g.detail}{g.revisit_after?<small className="l4lc-ref"> · revisit after {when(g.revisit_after)}</small>:null}</p>
    <Verification f={f} consumer={consumer}/>
    <dl className="l4lc-steps l4j-diag">
      <dt>Producer</dt><dd data-rt="producer">{f.producer?.kind==='none'?'No automatic producer':word(f.producer?.kind)||'Not recorded'}{f.producer?.description?` · ${f.producer.description}`:''}{f.producer?.planner_listed===false?' · not offered to the enrich planner':''}</dd>
      <dt>Source evidence</dt><dd data-rt="evidence">{abs?.evidence_id||att.some(a=>a.evidence_id)?<>{[abs?.evidence_id,...att.map(a=>a.evidence_id)].filter(Boolean).filter((x,i,a)=>a.indexOf(x)===i).slice(0,3).map(id=><code key={id} className="rt-ev">{String(id).slice(0,8)}</code>)}
        <small className="l4lc-ref"> stored evidence ids; open them from the course record's Evidence section</small></>:<NA why="no stored evidence is linked to this field"/>}</dd>
      <dt>Why it is missing or held</dt><dd data-rt="absence">{abs?<>{word(abs.absence_class)}: {abs.reason}{abs.reader_version?` · reader ${abs.reader_version}`:''}{abs.classified_at?` · ${when(abs.classified_at)}`:''}</>:g.class==='verified'?'Nothing is missing':g.detail||'No finding recorded'}</dd>
      <dt>Processing attempts</dt><dd data-rt="attempts">{att.length?<ul className="l4j-sim">{att.map(a=><li key={a.id}>{when(a.updated_at)} · {word(a.state)}{a.source?` · ${a.source}`:''}{a.model?` · ${a.model}`:''}{a.attempts!=null?` · attempt ${a.attempts}`:''}{a.cost_usd!=null?` · US$${Number(a.cost_usd).toFixed(4)}`:''}{a.reason?` · ${a.reason}`:''}</li>)}</ul>:'0 recorded'}</dd>
      <dt>Recovery history</dt><dd data-rt="history">{(hist.resolved_absences||[]).length||(hist.decided_layer4||[]).length?<ul className="l4j-sim">
        {(hist.resolved_absences||[]).map((x,i)=><li key={`a${i}`}>Resolved {when(x.resolved_at)}: {word(x.absence_class)}{x.reason?` · ${x.reason}`:''}</li>)}
        {(hist.decided_layer4||[]).map(x=><li key={x.id}>Layer 4 {word(x.status)} {when(x.decided_at)}{x.change_control_ref?` · ${x.change_control_ref}`:''}</li>)}</ul>:'0 recorded'}</dd>
      <dt>Authorised actions</dt><dd data-rt="actions">{(g.permitted_actions||[]).length?(g.permitted_actions).join(' · '):'None offered'}{l4.length>0&&rank>=3&&<><br/>{l4.map(x=><a key={x.id} className="cf-link" href={hrefFor('layer4','inbox',{ref:x.id})} data-rt-l4-link={x.id}>Open the Layer 4 item ({word(x.field_code)})</a>)}</>}</dd>
    </dl>
    {rank>=3&&l4.map(x=><Layer4Journey key={x.id} kind={l4Kind(x.field_code)} refId={x.id}/>)}{rank<3&&l4.length>0&&<p className="l4lc-ref">An open Layer 4 item holds this field; a Curator or above decides it.</p>}
  </div>
}

/** Increment 3: every registered field of one course, read when opened. */
export function CourseFieldStatus({courseId,field=null,open:startOpen=false,rank=0}){
  const[t,setT]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[show,setShow]=useState('attention')
  const load=()=>{setBusy(true);setErr('');readTrace(courseId,field).then(setT).catch(e=>setErr(e.message)).finally(()=>setBusy(false))}
  const rep=useCourseReports(courseId,rank,!!t) // s1285: the course's reports, read with the trace (Curator and above)
  useEffect(()=>{if(startOpen&&courseId)load()},[courseId,field])
  const fields=t?.fields||[],attention=fields.filter(f=>!['verified','not_applicable'].includes(f.diagnosis?.class))
  const list=field||show==='all'?fields:attention
  const counts={};for(const f of fields)counts[f.diagnosis?.class]=(counts[f.diagnosis?.class]||0)+1
  const body=<>{busy&&!t&&<p className="l4lc-ref" role="status">Reading the field status…</p>}
    {err&&<p className="l4lc-err" role="alert" data-rt-error>The field status could not be read: {err}</p>}
    {t&&<section className="l4lc" data-rt-course={courseId}>
      {rep&&!rep.error&&(Number(rep.open)>0||Number(rep.resolved)>0)&&<p className="rt-counts" data-rf-course>Reported data issues: <ReportFlag rep={rep}/></p>}
      {!field&&<p className="rt-counts" data-rt-counts>{Object.entries(counts).map(([c,n])=><span key={c} className="rt-count">{clsChip(c)} {fmtNumber(n)}</span>)}</p>}
      {!field&&<div className="rt-show" role="group" aria-label="Fields shown"><button type="button" aria-pressed={show==='attention'} onClick={()=>setShow('attention')}>Needs attention ({fmtNumber(attention.length)})</button><button type="button" aria-pressed={show==='all'} onClick={()=>setShow('all')}>All fields ({fmtNumber(fields.length)})</button></div>}
      {list.length===0?<p className="l4lc-ref">Every field holds a value or does not apply.</p>:list.map(f=><FieldTrace key={f.field} f={f} consumer={t.consumer} courseId={courseId} rank={rank} rep={rep}/>)}
      <p className="l4lc-ref">Read {when(t.checked_at)} · <button type="button" className="l4j-refresh" onClick={load} disabled={busy}>{busy?'Reading…':'Refresh'}</button></p>
    </section>}</>
  if(startOpen)return body
  return <details className="l4z-fold l4j" data-rt-fold="course" onToggle={e=>{if(e.currentTarget.open&&!t&&!busy)load()}}>
    <summary>Field processing status and diagnosis</summary>{body}</details>
}

/** One record in a drill list: the course title from its detail and its field trace, read when opened. */
function DrillRecord({r,field,rank}){
  // the trace is read only when the record is opened: a class can list many records, and each closed one reads nothing
  const[title,setTitle]=useState(''),[opened,setOpened]=useState(false)
  return <details className="rt-rec" data-rt-record={r.course_id} onToggle={e=>{if(!e.currentTarget.open)return;setOpened(true);if(!title)api.courseDetail(r.course_id).then(d=>setTitle(d?.display_title||d?.canonical_title||'')).catch(()=>setTitle(''))}}>
    <summary><span>{title||`Course ${String(r.course_id).slice(0,8)}`}</span> {clsChip(r.class)} <small className="l4lc-ref">{r.detail}{r.revisit_after?` · revisit after ${when(r.revisit_after)}`:''}</small></summary>
    <p><a className="cf-link" href={hrefFor('courses','',{id:r.course_id})} data-rt-open-course>Open the course record</a></p>
    {opened&&<CourseFieldStatus courseId={r.course_id} field={field} open rank={rank}/>}
  </details>
}

/** A provider by name, through the existing admin search (admin_priority_search, as the record editor's picker). */
function ProviderSearch({value,onPick,onError}){
  const[q,setQ]=useState(''),[hits,setHits]=useState([]),t=useRef(null)
  useEffect(()=>{clearTimeout(t.current);if(q.trim().length<2){setHits([]);return}
    t.current=setTimeout(()=>rpc('admin_priority_search',{p_kind:'provider',p_q:q.trim()}).then(d=>setHits(d||[])).catch(e=>onError?.(e.message)),300);return()=>clearTimeout(t.current)},[q])  // fixed: typing pause before searching
  if(value)return <div className="rt-picked"><strong>{value.label}</strong> <Button compact onClick={()=>onPick(null)}>Change</Button></div>
  return <div><input className="fv-input" type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Type the provider name" aria-label="Find the provider" data-rt-provider-search/>
    {hits.length>0&&<ul className="rt-hits">{hits.map(h=><li key={h.id}><button type="button" onClick={()=>onPick(h)}><strong>{h.label}</strong> <small className="l4lc-ref">{h.detail}</small></button></li>)}</ul>}</div>
}

/** Increment 2: from a Data Delivery stream, field or hold, a provider's records by diagnosis class, each opening its trace. */
export function RecordDrill({field='',label='Records',rank=0}){
  // A button, not a nested <details>: the stream and matrix folds keep exactly one summary each; the body mounts (and reads) only when opened.
  const[open,setOpen]=useState(false)
  return <div className="l4z-fold l4j rt-drill" data-rt-drill={field||'any'} data-rt-open={open?'true':'false'}>
    <button type="button" className="rt-toggle" aria-expanded={open} onClick={()=>setOpen(!open)} data-rt-drill-toggle>{label}: open a provider's records</button>
    {open&&<DrillBody fieldIn={field} rank={rank}/>}
  </div>
}

function DrillBody({fieldIn='',rank=0}){
  const[reg,setReg]=useState([]),[field,setField]=useState(fieldIn),[prov,setProv]=useState(null),[sum,setSum]=useState(null),[cls,setCls]=useState(''),[recs,setRecs]=useState(null),[err,setErr]=useState(''),[gain,setGain]=useState(null)
  useEffect(()=>{loadRegister().then(r=>setReg((r||[]).filter(x=>!x.level||x.level==='course'))).catch(()=>setReg([]));readRecoveryMeasure().then(setGain).catch(()=>setGain(null))},[])
  useEffect(()=>{setSum(null);setCls('');setRecs(null);setErr('');if(prov&&field)readProviderTrace(prov.id,field).then(setSum).catch(e=>setErr(e.message))},[prov?.id,field])
  useEffect(()=>{setRecs(null);if(prov&&field&&cls)readProviderTrace(prov.id,field,cls).then(d=>setRecs(d.records||[])).catch(e=>setErr(e.message))},[cls])
  const g=gain||{}
  return <div className="rt-drill-body">
    <div className="rt-pick">
      <label className="rt-field-pick"><small>Field</small><select value={field} onChange={e=>setField(e.target.value)} aria-label="Field" data-rt-field-select>
        <option value="">Choose a field</option>{reg.map(r=><option key={r.field} value={r.field}>{r.label||word(r.field)}</option>)}{field&&!reg.some(r=>r.field===field)&&<option value={field}>{word(field)}</option>}</select></label>
      <div className="rt-prov-pick"><small>Provider</small><ProviderSearch value={prov} onPick={setProv} onError={setErr}/></div>
    </div>
    {gain&&<p className="l4lc-ref" data-rt-gain>Operational recovery (platform-wide): {fmtNumber(Number(g.items||0))} field reads handed back{g.filled_by_field&&Object.keys(g.filled_by_field).length?`, filled: ${Object.entries(g.filled_by_field).map(([k,v])=>`${word(k)} ${fmtNumber(v)}`).join(', ')}`:', 0 filled so far'}{g.cost_usd!=null?`, US$${Number(g.cost_usd).toFixed(4)}`:''}{g.measured_at?` · measured ${when(g.measured_at)}`:''}.</p>}
    {err&&<p className="l4lc-err" role="alert">{err}</p>}
    {prov&&field&&!sum&&!err&&<p className="l4lc-ref" role="status">Reading the provider's records…</p>}
    {sum&&<section className="l4lc" data-rt-provider={prov.id}>
      <p className="l4lc-ref">{fmtNumber(sum.courses_read)} of {fmtNumber(sum.active_courses)} active courses read{sum.stopped_short?' (the read stops at the limit set in Settings)':''}.</p>
      <div className="rt-classes" role="group" aria-label="Diagnosis classes">{Object.entries(sum.by_class||{}).sort((a,b)=>b[1]-a[1]).map(([c,n])=><button key={c} type="button" className="rt-class" aria-pressed={cls===c} onClick={()=>setCls(cls===c?'':c)} data-rt-class-pick={c}>{clsChip(c)} {fmtNumber(n)}</button>)}</div>
      {(sum.top_details||[]).length>0&&<ul className="l4j-sim" data-rt-top>{sum.top_details.map((x,i)=><li key={i}>{(CLASS[x.class]||[word(x.class)])[0]}: {x.detail} ({fmtNumber(x.courses)})</li>)}</ul>}
      {cls&&!recs&&<p className="l4lc-ref" role="status">Reading the records…</p>}
      {recs&&<div className="rt-recs" data-rt-records>{recs.length===0?<p className="l4lc-ref">0 records in this class.</p>:recs.map(r=><DrillRecord key={r.course_id} r={r} field={field} rank={rank}/>)}</div>}
    </section>}
  </div>
}

export{STATE}
