// Course drawer › What happened (v2.15.322, Platform Admin 23 Oct 2026 07:16 "audit and logging of exactly what happened and was tried
// ... so I can make decision where the gap is"; 07:24 "read course pages with ai button"). Everything recorded for one course: its page
// and how it was found, every read, the page searches and AI page match tries, field fills with their reasons, admissions, values held,
// values set by hand. Read with AI reads the page again first in line and fills the missing fields with AI, with a reason, logged.
// Server: public.admin_course_audit(course), public.admin_course_read_now(course, reason).
// CF-247 A1 (Platform Admin mandate 29 Oct 2026 12:23): the history left the course blade. The evidence button at the top of the course
// drawer opens one evidence overlay (CourseEvidenceOverlay, on the shared Overlay) with a single timeline: page discovery and reads, page
// changes, AI page matches and field fills, admissions and refusals, fee-reader outcomes, cross-checks, changes by hand, course entry
// requirement reads, and scholarship relationship checks, each with its date, outcome, source and evidence reference. It reads only what
// already existed: admin_course_audit, admin_aer course_list for this course, and the course's scholarship links already in course_detail.
// Read with AI (an action) stays in the blade.
import React,{useEffect,useMemo,useState}from'react'
import{Bot,ExternalLink,History}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'
import{plainError}from'./lib/errors'
import{hrefFor}from'./nav-map'
import{Overlay}from'./Overlay'

const errText=e=>plainError(e) // v2.15.341 (UI audit Phase 0): one plain reading, no internals
const READ={read:['Read','success'],identity_mismatch:['Wrong page (refused)','danger'],blocked:['Blocked by the site','warning'],needs_render:['Needs a browser','warning'],fetch_failed:['Could not be read','warning'],robots_disallowed:['Site does not allow reading','warning'],refused_host:['Not the university’s site','danger']}
const FOUND={cricos_search:'CRICOS code search',cricos_code:'CRICOS code',title_search:'Web search by title',firecrawl_search:'Firecrawl search',serper_search:'Web search',ai_match:'AI page match',title_match:'University course list',cms_path_public:'University course list',manual:'Entered by a person',programme_list:'University programme list',firecrawl_upgrade:'Firecrawl'}
const FILL={filled:['Filled','success'],skipped:['Skipped','neutral'],failed:['Failed','danger'],queued:['Waiting','info'],leased:['Running','info'],waiting:['Waiting','info']}
const AER_STATUS={active:['Active','success'],proposed:['Waiting in Layer 4','info'],unverified:['Quarantined','danger'],inactive:['Withdrawn','neutral'],superseded:['Superseded','neutral']}
const words=s=>String(s??'').replaceAll('_',' ')
const audit=async courseId=>{const{data,error}=await supabase.rpc('admin_course_audit',{p_course_id:courseId});if(error)throw error;return data||{}}

// the blade keeps the action: Read with AI with a reason (the history itself is in the evidence overlay)
export default function CourseAudit({courseId,onChanged,onError}){
  const[d,setD]=useState(null),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[msg,setMsg]=useState('')
  const load=async()=>{try{setD(await audit(courseId))}catch(e){onError?.(errText(e));setD({})}}
  useEffect(()=>{if(courseId)load()},[courseId])
  const readNow=async()=>{if(reason.trim().length<4){setMsg('Write a reason first (it is kept with the request).');return}
    setBusy(true);setMsg('');try{const{data,error}=await supabase.rpc('admin_course_read_now',{p_course_id:courseId,p_reason:reason.trim()});if(error)throw error
      setMsg([data?.page_read_again?'The page is read again first in line (a few minutes), then its fee goes to the AI fee reader first in line.':null,(data?.ai_fields||[]).length?`AI fills ${data.ai_fields.join(', ')}.`:'No missing field for AI to fill.',data?.note].filter(Boolean).join(' '));setReason('');await load();onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!d||!d.can_read_now)return null
  return <section className="m-detail-section ca-panel" data-course-read-ai>
    <div className="ca-read" data-read-now>
      <strong className="ca-read-title"><Bot size={14}/>Read with AI</strong>
      <input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason, e.g. page changed; fee missing" aria-label="Reason for Read with AI"/>
      <Button compact onClick={readNow} disabled={busy}><Bot size={13}/>{busy?'Asking…':'Read with AI'}</Button>
      <small>Reads the page again first in line; then the AI fee reader reads its fee first in line (even when a fee is held) and AI fills the fields this course does not hold from the new page. Changing the official page does the same. Values set by hand are never changed. What happened to this course is under Evidence and history at the top of this panel.</small>
      {msg&&<p className="qw-msg" role="status">{msg}</p>}
    </div>
  </section>
}

// one event per recorded step; at is null when the record keeps no date (shown last, marked)
function timeline(d,aerRows,scholarships){
  const ev=[],add=(kind,area,at,outcome,tone,detail,url,evidence)=>ev.push({kind,area,at:at||null,outcome,tone,detail,url,evidence})
  const pg=d.page
  if(pg)add('discovery','Page found',pg.bound_at,pg.status==='bound'?'In use':pg.status==='mismatch'?'Refused, being looked for again':words(pg.status),pg.status==='bound'?'success':'warning',`Found by ${FOUND[pg.basis]||words(pg.basis)||'—'}${pg.identity_basis?` · proved by ${words(pg.identity_basis)}`:''}${pg.next_read_at?` · next read ${fmtDateTime(pg.next_read_at)}`:''}`,pg.url)
  for(const r of d.searches||[])add('discovery','Page search',r.done_at||r.queued_at,`${words(r.stage)} · ${words(r.state)}`,r.bound_url?'success':'neutral',`${r.query||''} · ${fmtNumber(r.results||0)} results`,r.bound_url)
  for(const r of d.reads||[])add('read','Page read',r.at,r.identity?`Proved by ${words(r.identity)}`:'Not proved',r.identity?'success':'warning',`Read via ${r.via||'—'}`,r.url,r.evidence_id)
  for(const r of d.relinks||[])add('change','Page changed',r.at,'Page changed','info',`${r.old_url||'—'} → ${r.new_url||'—'}${r.reason?` · ${r.reason}`:''}`,r.new_url)
  for(const r of d.ai_match||[])add('ai','AI page match',r.decided_at||r.created_at,r.state==='chosen'?'Chose a page':r.state==='none'?'No page fitted':words(r.state),r.state==='chosen'?'success':r.error||r.refused?'danger':'neutral',`Try ${r.attempt||'—'} · ${fmtNumber(r.candidates||0)} pages offered${r.reason?` · ${r.reason}`:''}${r.refused?` · refused: ${r.refused}`:''}${r.error?` · error: ${r.error}`:''}`,r.chosen_url)
  for(const r of d.field_fills||[]){const f=FILL[r.state]||[words(r.state),'neutral'];add('ai',`AI field fill: ${words(r.field)}`,r.updated_at,f[0],f[1],`${r.value?`Value: ${r.value} · `:''}${r.reason||''}${r.quote?` · “${r.quote}”`:''}`)}
  for(const r of d.admissions||[])add('admission',`Admission: ${words(r.field_key)}`,r.decided_at,words(r.status),/admit|accept|approved/i.test(r.status)?'success':/refus|reject/i.test(r.status)?'danger':'neutral',words(r.reason_code))
  for(const r of d.fee_rows||[])add('fee','Fee reader',r.created_at,words(r.outcome),/match|admit|kept|used/i.test(r.outcome)?'success':'neutral',`${fmtMoney(r.amount_min,r.currency_code)}${r.amount_max&&r.amount_max!==r.amount_min?` – ${fmtMoney(r.amount_max,r.currency_code)}`:''} · ${r.audience||''}${r.fee_year?` · ${r.fee_year}`:''}${r.note?` · ${r.note}`:''}${r.quote?` · “${r.quote}”`:''}`)
  for(const r of d.crosschecks||[])add('check',`Cross-check: ${words(r.field)}`,r.found_at,words(r.state),/agree|match|ok/i.test(r.state)?'success':'warning',`held ${r.held_value??'—'} · page ${r.page_value??'—'}${r.quote?` · “${r.quote}”`:''}`)
  for(const r of d.scope||[])add('change','Scope changed',r.at,`${words(r.from_status)} → ${words(r.to_status)}`,'info',[words(r.rule),r.scope_tag].filter(Boolean).join(' · '))
  if(d.credential)add('read','Credential read',d.credential.read_at,words(d.credential.outcome),'neutral',[d.credential.study_level_code,words(d.credential.basis)].filter(Boolean).join(' · '))
  for(const r of d.locks||[])add('manual',`Set by hand: ${words(r.field)}`,r.at,words(r.mode),'violet','A person set this value; automation does not change it.')
  for(const r of d.read_now||[])add('manual','Read with AI asked',r.at,r.detail?.page_read_again?'Page read again':'No page',r.detail?.page_read_again?'info':'neutral',`${r.detail?.reason||''} · AI: ${(r.detail?.ai_fields||[]).join(', ')||'nothing missing'}`)
  for(const r of aerRows||[]){const s=AER_STATUS[r.status]||[words(r.status),'neutral'];add('aer',`Entry requirement: ${words(r.requirement_kind)}`,r.as_at||r.updated_at,s[0],s[1],`${r.description||''}${r.quote?` · “${r.quote}”`:''}`,r.source_url,r.evidence_id)}
  for(const x of scholarships||[])add('scholarship',`Scholarship link: ${x.name||'Scholarship'}`,x.mapped_at||x.checked_at||x.verified_at||x.updated_at,x.publication_status==='published'?'Linked, published':words(x.publication_status||'linked'),x.publication_status==='published'?'success':'neutral',x.mapping_basis?`Linked because ${words(x.mapping_basis)}`:'',x.source_url,x.evidence_id)
  return ev
}
const AREAS=[['all','Everything'],['discovery','Page found'],['read','Reads'],['change','Changes'],['ai','AI'],['admission','Admissions'],['fee','Fees'],['check','Cross-checks'],['manual','By hand'],['aer','Entry requirements'],['scholarship','Scholarships']]

export function CourseEvidenceOverlay({courseId,title,scholarships,onClose,onError}){
  const[d,setD]=useState(null),[aerRows,setAer]=useState(null),[err,setErr]=useState(''),[order,setOrder]=useState('newest'),[area,setArea]=useState('all')
  useEffect(()=>{let on=true
    audit(courseId).then(x=>on&&setD(x)).catch(e=>{if(on){setErr(errText(e));setD({})}})
    supabase.rpc('admin_aer',{p_action:'course_list',p_args:{course:courseId,status:'',offset:0,page_size:100}}).then(({data,error})=>{if(on)setAer(error?[]:(data?.rows||[]))}).catch(()=>on&&setAer([]))
    return()=>{on=false}},[courseId])
  const events=useMemo(()=>d?timeline(d,aerRows,scholarships):[],[d,aerRows,scholarships])
  const shown=useMemo(()=>{const t=x=>x.at?Date.parse(x.at):NaN;const dated=events.filter(x=>area==='all'||x.kind===area);return dated.sort((a,b)=>{const x=t(a),y=t(b);if(isNaN(x)&&isNaN(y))return 0;if(isNaN(x))return 1;if(isNaN(y))return -1;return order==='newest'?y-x:x-y})},[events,order,area])
  const counts=useMemo(()=>events.reduce((m,x)=>(m[x.kind]=(m[x.kind]||0)+1,m),{}),[events])
  const pg=d?.page,held=d?.held||{},rd=READ[pg?.read_status]||[pg?.read_status||'Not read yet','neutral'],intl=(held.fees||[]).filter(f=>f.audience==='international')
  return <Overlay variant="panel" onClose={onClose} title={title||'This course'} eyebrow="Evidence and history" closeLabel="Close evidence and history" className="ca-overlay" bodyClassName="ca-overlay-body" data-course-evidence>
    {err&&<p className="fr-error" role="alert">{err}</p>}
    {!d?<Loading label="Reading what happened…"/>:<>
      <section className="ca-now" data-course-audit>
        <h3><History size={15}/>What happened to this course</h3>
        <p className="ca-empty">Every page tried, every read, every field attempt and what was admitted, in one timeline.</p>
        <h4>Course page</h4>
        {pg?<div className="ca-row"><a className="cf-link" href={pg.url} target="_blank" rel="noreferrer">{pg.url}</a>
          <small>Found by {FOUND[pg.basis]||pg.basis||'—'} · {pg.status==='bound'?'in use':pg.status==='mismatch'?'refused, being looked for again':pg.status} · <StatusChip value={pg.read_status} tone={rd[1]} label={rd[0]}/> {pg.read_at?`· read ${fmtDateTime(pg.read_at)} (${pg.fetched_via||'—'})`:''}</small></div>:<p className="ca-empty">No course page found yet.</p>}
        <h4>Held now</h4>
        <ul className="ca-held">
          <li><b>International fee</b> {intl.length?intl.map(f=>`${fmtMoney(f.amount,f.currency)} ${words(f.basis)}${f.year?` (${f.year})`:''}`).join('; '):<em>none</em>}</li>
          <li><b>Intakes</b> {(held.intakes||[]).length?held.intakes.map(i=>[i.label,i.year].filter(Boolean).join(' ')).join(', '):<em>none</em>}</li>
          <li><b>English</b> {(held.english||[]).length?held.english.map(e=>`${e.test} ${Number(e.overall)}`).join('; '):<em>none</em>}</li>
          <li><b>Campus</b> {(held.campuses||[]).length?held.campuses.join(', '):<em>none</em>}</li>
          <li><b>Duration</b> {d.course?.duration_value!=null?`${fmtNumber(Number(d.course.duration_value))} ${d.course.duration_unit||''}`:<em>none</em>} · <b>Delivery</b> {d.course?.delivery_mode||<em>none</em>} · <b>Open to international</b> {d.course?.open_to_international==null?<em>not known</em>:d.course.open_to_international?'yes':'no'}</li>
        </ul>
      </section>
      <div className="ca-tl-tools">
        <div className="ca-tl-areas" role="group" aria-label="Show">{AREAS.filter(([k])=>k==='all'||counts[k]).map(([k,l])=><button type="button" key={k} className={`m-secondary compact${area===k?' active':''}`} aria-pressed={area===k} onClick={()=>setArea(k)} data-ca-area={k}>{l}{k!=='all'&&<small> {counts[k]}</small>}</button>)}</div>
        <button type="button" className="m-secondary compact" onClick={()=>setOrder(o=>o==='newest'?'oldest':'newest')} data-ca-order={order}>{order==='newest'?'Newest first':'Oldest first'}</button>
      </div>
      {aerRows==null&&<small className="ca-empty">Reading entry requirements…</small>}
      {shown.length?<ol className="ca-timeline" data-course-timeline>{shown.map((x,i)=><li key={i} className="ca-event" data-ca-kind={x.kind}>
        <time dateTime={x.at||undefined}>{x.at?fmtDateTime(x.at):'Date not recorded'}</time>
        <div className="ca-event-main"><span className="ca-event-head"><strong>{x.area}</strong> <StatusChip tone={x.tone} label={x.outcome||'—'}/></span>
          {x.detail&&<small className="ca-event-detail">{x.detail}</small>}
          {(x.url||x.evidence)&&<span className="ca-event-links">{x.url&&<a className="cf-link" href={x.url} target="_blank" rel="noreferrer">Source <ExternalLink size={11}/></a>}{x.evidence&&<a className="cf-link" href={hrefFor('evidence','',{evidence_id:x.evidence})} data-ca-evidence>Evidence {String(x.evidence).slice(0,8)}</a>}</span>}
        </div></li>)}</ol>:<p className="ca-empty">Nothing recorded for this course yet.</p>}
    </>}
  </Overlay>
}
