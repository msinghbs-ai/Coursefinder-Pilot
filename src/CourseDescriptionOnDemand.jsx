// Fill description / Recheck description (CF-247 F-CDESC.06, Platform Admin directive 10 Nov 2026). The Course Catalogue (tick courses), the Course Detail blade (one course)
// and the Provider Catalogue (one university) start the EXISTING governed Enrich fields task for the description field: no other scheduler, job kind or reader.
// The Course Catalogue shows each course's description state under its name (no new column: the saved column layout is untouched).
// Reads and writes only public.admin_enrich_fields('preview' | 'start' | 'verify' | 'description_tasks') and public.admin_course_description_state_v1.
// Every figure on this page comes from the server: the per-request bound is the existing "Run now: most courses in a cohort" setting, the day's room is the existing
// "Enrich fields: items per day" setting. Nothing is a number in this file except the poll interval.
// Honest states: the pipeline states (Missing, Source-ready, AI-read, Held, Machine-admitted, Human decision) are kept apart from the three consumer read-backs (Website feed, Zoho feed,
// Verified HTTP); "not applicable" is not a failure and "not checked" is not a pass.
import React,{useCallback,useEffect,useMemo,useRef,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,StatusChip,fmtDateTime}from'./ui-kit'
import{plainError}from'./lib/errors'
import'./course-description-on-demand.css'

const POLL_MS=15000 // fixed: how often an open task list looks again while a task is running (a screen refresh, not an operating value)

const call=async(action,args)=>{const{data,error}=await supabase.rpc('admin_enrich_fields',{p_action:action,p_args:args||{}});if(error)throw error;return data}
const readStates=async ids=>{const{data,error}=await supabase.rpc('admin_course_description_state_v1',{p_course_ids:ids});if(error)throw error;return data}
const errText=e=>plainError(e)
const idOf=r=>String(r?.id??r?.course_id??'')
const titleOf=r=>r?.canonical_title??r?.display_title??r?.title??r?.course_title??'this course'
const short=id=>String(id||'').slice(0,8)
const num=n=>Number(n||0).toLocaleString('en-AU')

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
        <Button compact onClick={()=>setMode('fill')}>Fill description</Button>
        <Button compact onClick={()=>setMode('recheck')}>Recheck description</Button>
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
function Row({label,children}){return <div className="cdod-row"><dt>{label}</dt><dd>{children}</dd></div>}
export function CourseDescriptionBlock({courseId,rank,onError}){
  const enabled=Number(rank)>=3&&!!courseId,st=useDescriptionStates(courseId?[String(courseId)]:[],enabled)
  const[mode,setMode]=useState(''),[refresh,setRefresh]=useState(0),[ver,setVer]=useState(null),[verBusy,setVerBusy]=useState(false),[verErr,setVerErr]=useState('')
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
      <dl className="cdod-dl">
        <Row label="Source page">{s.source_url?<a href={s.source_url} target="_blank" rel="noreferrer">{s.source_url}</a>:'None stored'}{!s.source_ready&&s.source_reason?<span className="cdod-muted"> · {String(s.source_reason).replaceAll('_',' ')}</span>:null}</Row>
        <Row label="Evidence">{s.evidence_id?<><code>{short(s.evidence_id)}</code>{s.page_read_at?` · page read ${fmtDateTime(s.page_read_at)}`:''}</>:'No evidence stored'}</Row>
        <Row label="Last attempt">{s.last_attempt_at?<>{fmtDateTime(s.last_attempt_at)} · {s.last_state}{s.last_reason?` · ${s.last_reason}`:''}</>:'Never tried'}</Row>
        <Row label="Next retry">{s.next_retry_at?fmtDateTime(s.next_retry_at):'No date is set'}</Row>
        {s.held_kind&&<Row label="Held">{String(s.held_kind).replaceAll('_',' ')}</Row>}
        <Row label="Actual gain">{gain}</Row>
      </dl>
      <div className="cdod-actions">
        <Button compact disabled={!!s.fill_block} onClick={()=>setMode('fill')} title={s.fill_info?.label}>Fill description</Button>
        <Button compact disabled={!!s.recheck_block} onClick={()=>setMode('recheck')} title={s.recheck_info?.label}>Recheck description</Button>
        <Button compact onClick={verify} disabled={verBusy}>{verBusy?'Checking…':'Check the feeds'}</Button>
      </div>
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
