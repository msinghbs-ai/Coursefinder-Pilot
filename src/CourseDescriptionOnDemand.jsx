// Fill description / Recheck description (CF-247 F-CDESC.06, Platform Admin directive 10 Nov 2026). The Course Catalogue (tick courses), the Course Detail blade (one course)
// and the Provider Catalogue (one university) start the EXISTING governed Enrich fields task for the description field: no other scheduler, job kind or reader.
// The Course Catalogue shows each course's description state under its name (no new column: the saved column layout is untouched).
// Reads and writes only public.admin_enrich_fields('preview' | 'start' | 'verify' | 'description_tasks') and public.admin_course_description_state_v1, plus (Platform Admin, rank 6, only on a course with a live machine
// admission) the existing public.admin_course_description_machine_withdraw_v1.
// Every figure on this page comes from the server: the per-request bound is the existing "Run now: most courses in a cohort" setting, the day's room is the existing
// "Enrich fields: items per day" setting. Nothing is a number in this file except the poll interval.
// Honest states: the pipeline states (Missing, Source-ready, AI-read, Held, Machine-admitted, Human decision) are kept apart from the three consumer read-backs (Website feed, Zoho feed,
// Verified HTTP); "not applicable" is not a failure and "not checked" is not a pass.
import React,{useCallback,useEffect,useMemo,useRef,useState}from'react'
import { fmtNumber } from './lib/format'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,StatusChip,fmtDateTime}from'./ui-kit'
import{plainError}from'./lib/errors'
import'./course-description-on-demand.css'

const POLL_MS=15000 // fixed: how often an open task list looks again while a task is running (a screen refresh, not an operating value)

const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_enrich_fields',{p_action:action,p_args:args||{}});if(error)throw error;return data}
const readItems=async ids=>{const{data,error}=await supabase.rpc('admin_course_description_item_v1',{p_course_ids:ids});if(error)throw error;return data}
const readStates=async ids=>{const{data,error}=await supabase.rpc('admin_course_description_state_v1',{p_course_ids:ids});if(error)throw error;return data}
const withdrawCall=async(courseId,reason)=>{const{data,error}=await supabase.rpc('admin_course_description_machine_withdraw_v1',{p_course:courseId,p_reason:reason});if(error)throw error;return data}
const errText=e=>plainError(e)
const idOf=r=>String(r?.id??r?.course_id??'')
const titleOf=r=>r?.canonical_title??r?.display_title??r?.title??r?.course_title??'this course'
const short=id=>String(id||'').slice(0,8)
const num=n=>fmtNumber(Number(n||0))

// Where a description stands. Each state has its own words; none stands in for another.
export const DESC_STATE={
  missing:['Missing','warning','No stored course page is proved to be this course yet, so nothing can be read.'],
  source_ready:['Source-ready','info','A stored page proved to be this course is ready to be read.'],
  queued:['Queued','info','Already in an open Enrich fields task.'],
  ai_read:['AI-read','violet','The AI read it; the words wait for a person to decide in Layer 4.'],
  held:['Held','warning','Read, checked and held back (see the reason).'],
  not_stated:['Not stated on page','neutral','The page was read and does not state a description.'],
  failed:['Failed','danger','The last reading failed.'],
  locked:['Locked','neutral','A person locked this value; a read never overwrites it.'],
  machine_admitted:['Machine-admitted','success','Admitted by the machine admission route; the words are in the catalogue.'],
  human_decision:['Human decision','success','A person approved it in Layer 4; the words are in the catalogue.'],
  present:['Has description','success','A description is in the catalogue.'],
  inactive:['Inactive','neutral','Not an active course.'],
}
export function DescriptionStateChip({state}){const d=DESC_STATE[state];if(!d)return <span className="cdod-unknown" title="The state could not be read">—</span>;return <span data-desc-state={state}><StatusChip tone={d[1]} label={d[0]} title={d[2]}/></span>}

const FEED_STATE={
  matched:['Same words','success'],differs:['Different words','danger'],missing:['No description returned','danger'],pending:['Not in the feed yet','warning'],
  unknown:['Could not be read','warning'],not_applicable:['Not applicable','neutral'],not_carried:['Not carried by this feed','neutral'],not_checked:['Not checked','neutral'],
  present:['Present','success'],
}

// The one primary action (design section 3): "Fill / refresh course description now". The server decides what each course can take (fill_block / recheck_block from
// admin_course_description_state_v1); the screen only picks the mode that has a course to take. Fill and Recheck stay available as explicit modes under "Fill or Recheck only".
export const PRIMARY_LABEL='Fill / refresh course description now'
export function autoMode(ids,map){
  const rows=(ids||[]).map(i=>map?.[String(i)]).filter(Boolean)
  if(rows.some(r=>!r.fill_block))return'fill'
  if(rows.some(r=>!r.recheck_block))return'recheck'
  return'fill'
}
const dash=x=>x?String(x).replace(/^held:\s*/,''):''
// The durable stages of one course, read from the server state only (nothing here is guessed): the stored page, the AI reading, the checks, the decision, the catalogue.
export function descriptionStages(s,item){
  if(!s)return[]
  const never=!!item&&Number(item.attempts)===0&&!s.has_description // attempts 0: no valid source was read; never counted as a try or as evidence of absence
  const inFlight=['queued','waiting','ai','leased'].includes(s.last_state),notStated=s.state==='not_stated'
  const page=s.source_ready?{tone:'success',text:`Identified and read${s.page_read_at?` ${fmtDateTime(s.page_read_at)}`:''}`}:{tone:'warning',text:`Not ready${s.source_reason?`: ${String(s.source_reason).replaceAll('_',' ')}`:''}`}
  const ai=!s.last_item_id?{tone:'neutral',text:'Not read yet'}:never&&!inFlight?{tone:'neutral',text:'Not tried: no valid source was read'}:inFlight?{tone:'info',text:'In progress'}:s.last_state==='failed'?{tone:'danger',text:`Failed${s.last_attempt_at?` ${fmtDateTime(s.last_attempt_at)}`:''}`}:{tone:'success',text:`Read${s.last_attempt_at?` ${fmtDateTime(s.last_attempt_at)}`:''}`}
  const val=never&&!inFlight?{tone:'neutral',text:'Not reached'}:s.held_kind==='check'?{tone:'warning',text:`Held by a check: ${dash(s.last_reason)||'see the reason'}`}:notStated?{tone:'neutral',text:'The page does not state a description; nothing to check'}
    :(s.last_state==='review'||s.waiting_for_person||s.has_description||s.last_state==='filled')?{tone:'success',text:'Passed the checks'}:{tone:'neutral',text:'Not reached'}
  const dec=never&&!inFlight&&!s.waiting_for_person&&!s.locked?{tone:'neutral',text:'No decision: nothing was read, so this is not evidence the page has no description'}:s.has_description?(s.machine_admitted?{tone:'success',text:'Machine-admitted'}:s.human_decision?{tone:'success',text:'Human decision'}:{tone:'success',text:'Not decided by this pipeline'})
    :s.locked?{tone:'neutral',text:'Locked by a person'}:s.waiting_for_person?{tone:'violet',text:'Layer 4 needed: waiting for a person'}:s.rejected_same_evidence?{tone:'neutral',text:'Declined by a person on this same page'}
    :s.last_state==='failed'?{tone:'warning',text:'Technical recovery: the standing queue tries again'}:s.held_kind?{tone:'warning',text:`Held: ${String(s.held_kind).replaceAll('_',' ')}`}:{tone:'neutral',text:'No decision yet'}
  const cat={tone:s.has_description?'success':'neutral',text:s.has_description?'Description is in the catalogue':'No description yet'}
  return[['page','Stored page',page],['ai','AI reading',ai],['validation','Checks',val],['decision','Decision',dec],['catalogue','Catalogue',cat]]
}
// The result for the field, per item as the server stores it: value or empty, the source examined, the reason, the attempts and the next action.
// attempts 0 = never tried (no valid source was read): not an attempt, not evidence of absence. Only attempts 1 or more with the page not stating it is "tried, not found".
function FieldResult({s,item,detail}){
  const it=item||null,att=it==null?null:Number(it.attempts),chars=Number(detail?.catalogue_chars||0)
  const verdict=s.has_description?'A description is in the catalogue.':it==null?'Not tried: nothing has been read for this course.':att===0?'Never tried: no valid source was read. This is not evidence that the page has no description.'
    :s.state==='not_stated'?'Tried and not found: the page was read and does not state a description.':'Read, then held or declined (see the reason).'
  return <dl className="cdod-dl" data-cdod-field-result aria-label="Result for the course description">
    <Row label="Field">Course description</Row>
    <Row label="Value"><span data-cdod-value>{chars>0?`In the catalogue (${num(chars)} characters)`:Number(it?.reading_chars)>0?`Empty. A reading of ${num(it.reading_chars)} characters is held and not admitted.`:'Empty'}</span></Row>
    <Row label="Source examined">{it==null?'None':<><span data-cdod-source>{it.source||'No source recorded'}</span>{it.evidence_id?<> · evidence <code>{short(it.evidence_id)}</code></>:null}{it.storage_path?<> · <code data-cdod-storage>{it.storage_path}</code></>:null}{!it.evidence_id&&!it.storage_path?<span className="cdod-muted"> · no stored page was read</span>:null}</>}</Row>
    <Row label="Reason"><span data-cdod-reason>{it?.reason?String(it.reason):'No reason recorded'}</span></Row>
    <Row label="Attempts"><span data-cdod-attempts>{att==null?'None':num(att)}</span> <span className="cdod-muted" data-cdod-verdict>{verdict}</span></Row>
    <Row label="Next action"><span data-cdod-next-field>{nextAction(s)}</span></Row>
  </dl>
}
function nextAction(s){
  if(!s)return''
  if(s.has_description)return'Nothing to do: a description is in the catalogue.'
  if(s.fill_info?.next&&s.fill_block&&s.recheck_block)return s.fill_info.next
  if(s.next_retry_at)return`The standing queue tries again ${fmtDateTime(s.next_retry_at)}.`
  return s.fill_block?(s.fill_info?.next||''):'Use the button above to read the stored page now.'
}

// ---- state of the courses on the page ---------------------------------------------------------------------------------------------------------------------------
export function useDescriptionStates(ids,enabled){
  const key=ids.join(','),[map,setMap]=useState({}),[meta,setMeta]=useState({}),[err,setErr]=useState(''),[tick,setTick]=useState(0)
  useEffect(()=>{if(!enabled||!key){setMap({});return}let live=true
    readStates(key.split(',')).then(d=>{if(!live)return;const rows=Array.isArray(d?.courses)?d.courses:[];setMap(Object.fromEntries(rows.map(r=>[String(r.course_id),r])));setMeta({cap:Number(d?.courses_per_request)||null,machine:d?.machine_ledger,days:d?.recheck_days});setErr('')})
      .catch(e=>{if(live){setMap({});setErr(errText(e))}})
    return()=>{live=false}},[key,enabled,tick])
  return{map,meta,err,reload:()=>setTick(t=>t+1)}
}

// ---- preview, reason, queue --------------------------------------------------------------------------------------------------------------------------------------
function RunPanel({mode,scope,label,rank,onClose,onStarted,onError}){
  const[prev,setPrev]=useState(null),[err,setErr]=useState(''),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[done,setDone]=useState(null)
  const newKey=()=>`cdod:${globalThis.crypto?.randomUUID?globalThis.crypto.randomUUID():String(Date.now())+Math.random()}`
  const key=useRef(newKey()) // one key per request (mode and selection): a second tap never makes a second task; a changed mode or selection is a new request with a new key
  const word=mode==='recheck'?'Recheck description':'Fill description'
  const scopeKey=JSON.stringify(scope)
  useEffect(()=>{let live=true;setPrev(null);setErr('');setDone(null);key.current=newKey()
    call('preview',{mode,...scope}).then(d=>live&&setPrev(d||{})).catch(e=>live&&setErr(errText(e)))
    return()=>{live=false}},[mode,scopeKey])
  const canStart=Number(rank)>=4,reasonOk=reason.trim().length>=4,n=Number(prev?.to_queue||0)
  async function start(){setBusy(true);setErr('');try{const d=await call('start',{mode,reason:reason.trim(),idempotency_key:key.current,...scope});setDone(d||{});onStarted?.(d)}catch(e){const m=errText(e);setErr(m);onError?.(m)}finally{setBusy(false)}}
  const blocked=prev?.blocked||{},info=prev?.blocked_info||{},blockedN=Object.values(blocked).reduce((a,b)=>a+Number(b||0),0)
  const est=prev?.estimate
  return <div className="cdod-panel" role="group" aria-label={`${word} preview`} data-cdod-panel={mode}>
    <div className="cdod-panel-head"><strong>{word}</strong><span className="cdod-muted">{label}</span><button type="button" className="cdod-x" onClick={onClose} aria-label={`Close ${word}`}>Close</button></div>
    {!prev&&!err&&<Loading compact label="Checking each course…"/>}
    {err&&<p className="cdod-error" role="alert">{err}</p>}
    {prev&&<>
      <p className="cdod-sum" data-cdod-sum>
        <strong>{num(n)}</strong> will be queued{blockedN>0&&<>, <strong>{num(blockedN)}</strong> left out</>}{Number(prev.left_for_later)>0&&<>, <strong>{num(prev.left_for_later)}</strong> wait for the next request</>}.
        {' '}{mode==='recheck'?'Recheck reads the stored page again now and does not wait for the standing queue’s date.':'Fill reads the stored page of each course that has none yet.'}
      </p>
      {Object.keys(blocked).length>0&&<ul className="cdod-blocked" aria-label="Left out, and why">{Object.entries(blocked).map(([k,v])=><li key={k} data-cdod-block={k}><strong>{num(v)}</strong> {info[k]?.label||k}{info[k]?.next?<span className="cdod-muted"> — {info[k].next}</span>:null}</li>)}</ul>}
      {Array.isArray(prev.courses)&&prev.courses.length>0&&<ul className="cdod-courses" aria-label="Courses in this request">{prev.courses.map(c=><li key={c.course_id} data-cdod-course={c.course_id} data-will-queue={c.will_queue?'yes':'no'}>
        <span className="cdod-ctitle">{c.title}</span><span className="cdod-muted">{c.provider}</span>
        {c.will_queue?<StatusChip tone="success" label="Will be queued"/>:<span className="cdod-why"><StatusChip tone="neutral" label="Left out"/> {c.block_info?.label||c.block}{c.block_info?.next?<span className="cdod-muted"> — {c.block_info.next}</span>:null}</span>}
      </li>)}</ul>}
      <p className="cdod-muted" data-cdod-estimate>
        {est?.usd==null?'AI cost: not known.':`AI cost: about US$${Number(est.usd).toFixed(4)} (${num(est.items)} × US$${Number(est.usd_per_item).toFixed(4)}).`} No scraper credits: the stored page is read.
        {' '}At most {num(prev.limit?.courses_per_request)} courses a request; {num(prev.limit?.room_today)} of today’s {num(prev.limit?.items_per_day)} description readings are left.
      </p>
      {!done&&<>
        {canStart?<label className="cdod-reason"><span>Reason (kept with the task)</span><input value={reason} onChange={e=>setReason(e.target.value)} maxLength={300} placeholder="Why are you running this?" aria-label="Reason"/></label>
          :<p className="cdod-muted">Starting needs the Pipeline Operator role. You can still see what would happen.</p>}
        <div className="cdod-actions"><Button variant="primary" disabled={!canStart||!reasonOk||n<1||busy} onClick={start} title={n<1?'Nothing in this request can be queued.':!reasonOk?'Give a reason first.':undefined}>{busy?'Queuing…':`Queue ${num(n)} course${n===1?'':'s'}`}</Button><Button onClick={onClose}>Cancel</Button></div>
      </>}
      {done&&<p className="cdod-done" role="status" data-cdod-done>{done.repeat?'This request was already queued as task ':'Queued as task '}<code>{short(done.job_id)}</code> with {num(done.items)} course{Number(done.items)===1?'':'s'}. It is kept in the task list below and in Enrich fields tasks, and carries on if you close this page.</p>}
    </>}
  </div>
}

// ---- the saved tasks (kept on the server, so they are still there after the browser is closed) -----------------------------------------------------------------
const TASK_TONE={queued:'info',running:'info',completed:'success',failed:'danger',cancelled:'neutral',paused:'warning'}
export function DescriptionTasks({courseIds,refresh=0,onError}){
  const[tasks,setTasks]=useState(null),key=(courseIds||[]).join(',')
  const load=useCallback(()=>call('description_tasks',key?{course_ids:key.split(',')}:{}).then(d=>setTasks(Array.isArray(d?.tasks)?d.tasks:[])).catch(e=>onError?.(errText(e))),[key])
  useEffect(()=>{load()},[load,refresh])
  useEffect(()=>{if(!(tasks||[]).some(t=>['queued','running'].includes(t.state)))return;const t=setInterval(load,POLL_MS);return()=>clearInterval(t)},[tasks,load])
  if(tasks===null)return <Loading compact label="Loading tasks…"/>
  if(!tasks.length)return <Empty text="No Fill or Recheck description task yet."/>
  return <ul className="cdod-tasks" data-cdod-tasks>{tasks.map(t=><li key={t.id} data-task-id={t.id}>
    <div className="cdod-task-top"><StatusChip tone={TASK_TONE[t.state]||'neutral'} label={t.state}/><strong>{t.title}</strong></div>
    <div className="cdod-muted">Task <code>{short(t.id)}</code> · {fmtDateTime(t.created_at)}{t.finished_at?` · finished ${fmtDateTime(t.finished_at)}`:''}</div>
    <div className="cdod-muted">{Object.entries(t.by_state||{}).map(([k,v])=>`${num(v)} ${k}`).join(' · ')||'No items yet'} · {num(t.described_now)} of its courses have a description now</div>
    {t.reason&&<div className="cdod-muted">Reason: {t.reason}</div>}
  </li>)}</ul>
}

// ---- Course Catalogue: tick courses, Fill / Recheck ----------------------------------------------------------------------------------------------------------------
export function useCourseDescriptionOnDemand({enabled,rows,rank,onError}){
  const[picked,setPicked]=useState([]),[mode,setMode]=useState(''),[refresh,setRefresh]=useState(0),[note,setNote]=useState(''),[started,setStarted]=useState(false)
  const ids=useMemo(()=>(rows||[]).map(idOf).filter(Boolean),[rows])
  const st=useDescriptionStates(ids,enabled)
  const cap=st.meta.cap
  const toggle=id=>setPicked(p=>{if(p.includes(id)){setNote('');return p.filter(x=>x!==id)}if(cap&&p.length>=cap){setNote(`At most ${cap} courses at a time (Pipeline settings › Run now: most courses in a cohort).`);return p}setNote('');return[...p,id]})
  // The tick and the state chip live inside the first column's cell, so the person's saved column layout (which columns, their order and widths) is not changed by this feature.
  const decorate=cols=>{
    if(!enabled||!cols?.length)return cols
    const first=cols[0]
    const wrapped={...first,render:r=>{const id=idOf(r),on=picked.includes(id),s=st.map[id];return <span className="cdod-first"><label className="cdod-pick" onClick={e=>e.stopPropagation()}><input type="checkbox" checked={on} onChange={()=>toggle(id)} aria-label={`Select ${titleOf(r)} for Fill or Recheck description`}/></label><span className="cdod-first-body">{first.render?first.render(r):(r[first.key]??'—')}<span className="cdod-state-line" data-cdod-state-line>{s?<DescriptionStateChip state={s.state}/>:<span className="cdod-unknown" title={st.err||'Not read yet'}>—</span>}</span></span></span>}}
    return[wrapped,...cols.slice(1)]
  }
  const bar=enabled?<div className="cdod-bar" data-cdod-bar>
    <div className="cdod-bar-row">
      <span className="cdod-count" aria-live="polite">{picked.length?`${picked.length} selected`:'Tick courses to fill or recheck their descriptions.'}</span>
      {picked.length>0&&<>
        <Button compact variant="primary" data-cdod-primary onClick={()=>setMode(autoMode(picked,st.map))}>{PRIMARY_LABEL}</Button>
        <details className="cdod-more" data-cdod-more><summary>Fill or Recheck only</summary><div className="cdod-actions"><Button compact onClick={()=>setMode('fill')}>Fill description</Button><Button compact onClick={()=>setMode('recheck')}>Recheck description</Button></div></details>
        <Button compact onClick={()=>{setPicked([]);setMode('');setNote('')}}>Clear</Button></>}
    </div>
    {note&&<p className="cdod-muted" role="status">{note}</p>}
    {st.err&&<p className="cdod-muted" role="status" data-cdod-state-error>Description states could not be read: {st.err}</p>}
    {mode&&picked.length>0&&<RunPanel mode={mode} scope={{course_ids:picked}} label={`${picked.length} course${picked.length===1?'':'s'} selected`} rank={rank} onError={onError} onClose={()=>{setMode('');if(started){setPicked([]);setStarted(false)}}} onStarted={()=>{setRefresh(x=>x+1);st.reload();setStarted(true)}}/>}
    <details className="cdod-tasks-fold" onToggle={e=>{if(e.currentTarget.open)setRefresh(x=>x+1)}}><summary>Recent Fill and Recheck description tasks</summary><DescriptionTasks refresh={refresh} onError={onError}/></details>
  </div>:null
  return{decorate,bar,picked}
}

// ---- Course Detail blade ------------------------------------------------------------------------------------------------------------------------------------------
// Withdraw a machine-admitted description (rank 6). The server decides: it keeps a description a person changed or locked, and says so; nothing is guessed here.
const WITHDRAW_NO={no_live_machine_admission:'This course has no live machine admission (it may already be withdrawn).'}
function WithdrawPanel({courseId,onClose,onDone,onError}){
  const[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[err,setErr]=useState(''),[done,setDone]=useState(false),reasonOk=reason.trim().length>=4
  async function go(){setBusy(true);setErr('');try{const d=await withdrawCall(String(courseId),reason.trim());if(d?.ok){setDone(true);onDone?.(d)}else{const m=d?.reason||WITHDRAW_NO[d?.rule]||'The description was not withdrawn.';setErr(m);onError?.(m)}}catch(e){const m=errText(e);setErr(m);onError?.(m)}finally{setBusy(false)}}
  return <div className="cdod-panel" role="group" aria-label="Withdraw machine description" data-cdod-withdraw-panel>
    <div className="cdod-panel-head"><strong>Withdraw machine description</strong><button type="button" className="cdod-x" onClick={onClose} aria-label="Close Withdraw machine description">Close</button></div>
    {!done&&<>
      <p className="cdod-sum" data-cdod-withdraw-what>The description is removed from the catalogue and the search refresh runs again. The course returns to the gap queue, and a new reading is not admitted by the machine: it waits for a person in Layer 4. The text of the old description is kept in the ledger. A description that a person has changed or locked since is kept, and you are told.</p>
      <label className="cdod-reason"><span>Reason (kept in the log, at least 4 characters)</span><input value={reason} onChange={e=>setReason(e.target.value)} maxLength={300} placeholder="Why is this description withdrawn?" aria-label="Reason for withdrawing"/></label>
      {err&&<p className="cdod-error" role="alert">{err}</p>}
      <div className="cdod-actions"><Button variant="danger" disabled={!reasonOk||busy} onClick={go} title={!reasonOk?'Give a reason first.':undefined}>{busy?'Withdrawing…':'Withdraw description'}</Button><Button onClick={onClose}>Cancel</Button></div>
    </>}
    {done&&<p className="cdod-done" role="status" data-cdod-withdraw-done>The machine description was withdrawn. The course has no description now and is back in the gap queue; the old text is kept in the ledger.</p>}
  </div>
}
function Row({label,children}){return <div className="cdod-row"><dt>{label}</dt><dd>{children}</dd></div>}
export function CourseDescriptionBlock({courseId,rank,onError}){
  const enabled=Number(rank)>=3&&!!courseId,st=useDescriptionStates(courseId?[String(courseId)]:[],enabled)
  const[detail,setDetail]=useState(null)
  const[wd,setWd]=useState(false),[mode,setMode]=useState(''),[refresh,setRefresh]=useState(0),[ver,setVer]=useState(null),[verBusy,setVerBusy]=useState(false),[verErr,setVerErr]=useState('')
  const dkey=enabled?String(courseId):'',stamp=st.map[String(courseId)]?.last_item_id??'',stateKey=st.map[String(courseId)]?.state??''
  useEffect(()=>{if(!dkey){setDetail(null);return}let live=true
    readItems([dkey]).then(d=>{if(live)setDetail((Array.isArray(d?.courses)?d.courses:[])[0]||null)}).catch(()=>{if(live)setDetail(null)}) // an older server has no item read: the result shows what the state holds
    return()=>{live=false}},[dkey,stamp,stateKey,refresh])
  if(!enabled)return null
  const s=st.map[String(courseId)]
  async function verify(){setVerBusy(true);setVerErr('');try{const d=await call('verify',{course_ids:[String(courseId)]});setVer((d?.courses||[])[0]||{missing:true})}catch(e){setVerErr(errText(e))}finally{setVerBusy(false)}}
  const gain=!s?null:s.has_description?(s.last_state==='filled'?'The last task filled this description.':'A description is in the catalogue (not filled by this pipeline).'):'No description yet.'
  return <section className="m-detail-section cdod-block" data-cdod-block aria-label="Description pipeline">
    <div className="cdod-block-head"><h3>Description pipeline</h3>{s&&<DescriptionStateChip state={s.state}/>}</div>
    {!s&&!st.err&&<Loading compact label="Reading the description state…"/>}
    {st.err&&<p className="cdod-error" role="alert">{st.err}</p>}
    {s&&<>
      <p className="cdod-muted">{DESC_STATE[s.state]?.[2]}</p>
      <ol className="cdod-stages" data-cdod-stages aria-label="Where this description stands, stage by stage">{descriptionStages(s,detail?.item).map(([k,label,v])=><li key={k} data-cdod-stage={k}><span className="cdod-stage-name">{label}</span><StatusChip tone={v.tone} label={v.text}/></li>)}</ol>
      <FieldResult s={s} item={detail?.item} detail={detail}/>
      <dl className="cdod-dl">
        <Row label="Source page">{s.source_url?<a href={s.source_url} target="_blank" rel="noreferrer">{s.source_url}</a>:'None stored'}{!s.source_ready&&s.source_reason?<span className="cdod-muted"> · {String(s.source_reason).replaceAll('_',' ')}</span>:null}</Row>
        <Row label="Evidence">{s.evidence_id?<><code>{short(s.evidence_id)}</code>{s.page_read_at?` · page read ${fmtDateTime(s.page_read_at)}`:''}</>:'No evidence stored'}</Row>
        <Row label="Last attempt">{s.last_attempt_at?<>{fmtDateTime(s.last_attempt_at)} · {s.last_state}{s.last_reason?` · ${s.last_reason}`:''}</>:'Never tried'}</Row>
        <Row label="Next retry">{s.next_retry_at?fmtDateTime(s.next_retry_at):'No date is set'}</Row>
        {s.held_kind&&<Row label="Held">{String(s.held_kind).replaceAll('_',' ')}</Row>}
        <Row label="Run">{s.last_job_id?<code data-cdod-run>{short(s.last_job_id)}</code>:'No run yet'}</Row>
        {s.last_state==='failed'&&<Row label="Error"><span data-cdod-error-reason>{dash(s.last_reason)||'The last reading failed; no reason was recorded.'}</span></Row>}
        <Row label="Next action"><span data-cdod-next>{nextAction(s)}</span></Row>
        <Row label="Actual gain">{gain}</Row>
      </dl>
      <div className="cdod-actions">
        <Button compact variant="primary" data-cdod-primary disabled={!!s.fill_block&&!!s.recheck_block} onClick={()=>setMode(autoMode([courseId],st.map))} title={s.fill_block&&s.recheck_block?s.fill_info?.label:undefined}>{PRIMARY_LABEL}</Button>
        <Button compact onClick={verify} disabled={verBusy}>{verBusy?'Checking…':'Check the feeds'}</Button>
        {Number(rank)>=6&&s.state==='machine_admitted'&&<Button compact variant="danger" onClick={()=>setWd(true)} data-cdod-withdraw>Withdraw machine description</Button>}
      </div>
      {wd&&Number(rank)>=6&&<WithdrawPanel courseId={courseId} onError={onError} onClose={()=>setWd(false)} onDone={()=>{setRefresh(x=>x+1);st.reload()}}/>}
      <details className="cdod-more" data-cdod-more><summary>Fill or Recheck only</summary><div className="cdod-actions">
        <Button compact disabled={!!s.fill_block} onClick={()=>setMode('fill')} title={s.fill_info?.label}>Fill description</Button>
        <Button compact disabled={!!s.recheck_block} onClick={()=>setMode('recheck')} title={s.recheck_info?.label}>Recheck description</Button></div></details>
      {(s.fill_block||s.recheck_block)&&<p className="cdod-muted" data-cdod-why>{s.fill_block?<>Fill: {s.fill_info?.label}. {s.fill_info?.next} </>:null}{s.recheck_block?<>Recheck: {s.recheck_info?.label}. {s.recheck_info?.next}</>:null}</p>}
      {mode&&<RunPanel mode={mode} scope={{course_ids:[String(courseId)]}} label="This course" rank={rank} onError={onError} onClose={()=>setMode('')} onStarted={()=>{setRefresh(x=>x+1);st.reload()}}/>}
    </>}
    {verErr&&<p className="cdod-error" role="alert">{verErr}</p>}
    {ver&&!ver.missing&&<dl className="cdod-dl" data-cdod-feeds aria-label="What the consumers read">
      <Row label="Catalogue">{FeedState(ver.catalogue,ver.catalogue?.chars!=null?`${num(ver.catalogue.chars)} characters`:'')}</Row>
      <Row label="Website feed">{FeedState(ver.website)}</Row>
      <Row label="Zoho feed">{FeedState(ver.zoho)}</Row>
      <Row label="Verified HTTP">{FeedState(ver.http)}</Row>
    </dl>}
    {ver?.missing&&<p className="cdod-muted">The course was not found for the check.</p>}
    <details className="cdod-tasks-fold"><summary>Tasks that held this course</summary><DescriptionTasks courseIds={[String(courseId)]} refresh={refresh} onError={onError}/></details>
  </section>
}
function FeedState(x,extra){const d=FEED_STATE[x?.state];return <span data-feed-state={x?.state||'unknown'}>{d?<StatusChip tone={d[1]} label={d[0]}/>:<StatusChip tone="neutral" label="Unknown"/>}{extra?<span className="cdod-muted"> {extra}</span>:null}{x?.note?<span className="cdod-muted"> {x.note}</span>:null}</span>}

// ---- Provider Catalogue: one university ---------------------------------------------------------------------------------------------------------------------------
export function ProviderDescriptionFill({providerId,name,rank,onError}){
  const[mode,setMode]=useState(''),[refresh,setRefresh]=useState(0)
  if(Number(rank)<3||!providerId)return null
  return <section className="m-detail-section cdod-block" data-cdod-provider aria-label="Course descriptions">
    <div className="cdod-block-head"><h3>Course descriptions</h3></div>
    <p className="cdod-muted">Reads the stored pages of {name||'this university'}’s active courses that have no description. The same Enrich fields task, within the same limits; you see what would be queued first.</p>
    <div className="cdod-actions"><Button compact onClick={()=>setMode('fill')}>Fill course descriptions</Button><Button compact onClick={()=>setMode('recheck')}>Recheck course descriptions</Button></div>
    {mode&&<RunPanel mode={mode} scope={{provider_ids:[String(providerId)]}} label={name||'This university'} rank={rank} onError={onError} onClose={()=>setMode('')} onStarted={()=>setRefresh(x=>x+1)}/>}
    <details className="cdod-tasks-fold" onToggle={e=>{if(e.currentTarget.open)setRefresh(x=>x+1)}}><summary>Recent Fill and Recheck description tasks</summary><DescriptionTasks refresh={refresh} onError={onError}/></details>
  </section>
}
