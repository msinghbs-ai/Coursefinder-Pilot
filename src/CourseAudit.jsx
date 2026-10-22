// Course drawer › What happened (v2.15.322, Platform Admin 23 Oct 2026 07:16 "audit and logging of exactly what happened and was tried
// ... so I can make decision where the gap is"; 07:24 "read course pages with ai button"). Everything recorded for one course: its page
// and how it was found, every read, the page searches and AI page match tries, field fills with their reasons, admissions, values held,
// values set by hand. Read with AI reads the page again first in line and fills the missing fields with AI, with a reason, logged.
// Server: public.admin_course_audit(course), public.admin_course_read_now(course, reason).
import React,{useEffect,useState}from'react'
import{Bot,ChevronDown,ChevronRight,History}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const READ={read:['Read','success'],identity_mismatch:['Wrong page (refused)','danger'],blocked:['Blocked by the site','warning'],needs_render:['Needs a browser','warning'],fetch_failed:['Could not be read','warning'],robots_disallowed:['Site does not allow reading','warning'],refused_host:['Not the university’s site','danger']}
const FOUND={cricos_search:'CRICOS code search',cricos_code:'CRICOS code',title_search:'Web search by title',firecrawl_search:'Firecrawl search',serper_search:'Web search',ai_match:'AI page match',title_match:'University course list',cms_path_public:'University course list',manual:'Entered by a person',programme_list:'University programme list',firecrawl_upgrade:'Firecrawl'}
const FILL={filled:['Filled','success'],skipped:['Skipped','neutral'],failed:['Failed','danger'],queued:['Waiting','info'],leased:['Running','info'],waiting:['Waiting','info']}

export default function CourseAudit({courseId,onChanged,onError}){
  const[d,setD]=useState(null),[open,setOpen]=useState(true),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[msg,setMsg]=useState('')
  const load=async()=>{try{const{data,error}=await supabase.rpc('admin_course_audit',{p_course_id:courseId});if(error)throw error;setD(data||{})}catch(e){onError?.(errText(e));setD({})}}
  useEffect(()=>{if(courseId)load()},[courseId])
  const readNow=async()=>{if(reason.trim().length<4){setMsg('Write a reason first (it is kept with the request).');return}
    setBusy(true);setMsg('');try{const{data,error}=await supabase.rpc('admin_course_read_now',{p_course_id:courseId,p_reason:reason.trim()});if(error)throw error
      setMsg([data?.page_read_again?'The page is read again first in line (a few minutes).':null,(data?.ai_fields||[]).length?`AI fills ${data.ai_fields.join(', ')}.`:'No missing field for AI to fill.',data?.note].filter(Boolean).join(' '));setReason('');await load();onChanged?.()}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  if(!d)return <section className="m-detail-section ca-panel"><Loading label="Reading what happened…"/></section>
  const pg=d.page,held=d.held||{},rd=READ[pg?.read_status]||[pg?.read_status||'Not read yet','neutral']
  const intl=(held.fees||[]).filter(f=>f.audience==='international')
  return <section className="m-detail-section ca-panel" data-course-audit>
    <button type="button" className="re-toggle" onClick={()=>setOpen(o=>!o)} aria-expanded={open}><History size={14}/><span><strong>What happened to this course</strong><small>Every page tried, every read, every field attempt and what was admitted</small></span>{open?<ChevronDown size={14}/>:<ChevronRight size={14}/>}</button>
    {open&&<div className="ca-body">
      {d.can_read_now&&<div className="ca-read" data-read-now>
        <input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)} placeholder="Reason, e.g. page changed; fee missing" aria-label="Reason for Read with AI"/>
        <Button compact onClick={readNow} disabled={busy}><Bot size={13}/>{busy?'Asking…':'Read with AI'}</Button>
        <small>Reads the page again first in line, then AI fills the fields this course does not hold. Values set by hand are never changed.</small>
        {msg&&<p className="qw-msg" role="status">{msg}</p>}
      </div>}
      <h4>Course page</h4>
      {pg?<div className="ca-row"><a className="cf-link" href={pg.url} target="_blank" rel="noreferrer">{pg.url}</a>
        <small>Found by {FOUND[pg.basis]||pg.basis||'—'} · {pg.status==='bound'?'in use':pg.status==='mismatch'?'refused, being looked for again':pg.status} · <StatusChip value={pg.read_status} tone={rd[1]} label={rd[0]}/> {pg.read_at?`· read ${fmtDateTime(pg.read_at)} (${pg.fetched_via||'—'})`:''}{pg.identity_basis?` · proved by ${String(pg.identity_basis).replaceAll('_',' ')}`:''}{pg.next_read_at?` · next read ${fmtDateTime(pg.next_read_at)}`:''}</small></div>:<p className="ca-empty">No course page found yet.</p>}
      <h4>Held now</h4>
      <ul className="ca-held">
        <li><b>International fee</b> {intl.length?intl.map(f=>`${fmtMoney(f.amount,f.currency)} ${String(f.basis||'').replaceAll('_',' ')}${f.year?` (${f.year})`:''}`).join('; '):<em>none</em>}</li>
        <li><b>Intakes</b> {(held.intakes||[]).length?held.intakes.map(i=>[i.label,i.year].filter(Boolean).join(' ')).join(', '):<em>none</em>}</li>
        <li><b>English</b> {(held.english||[]).length?held.english.map(e=>`${e.test} ${Number(e.overall)}`).join('; '):<em>none</em>}</li>
        <li><b>Campus</b> {(held.campuses||[]).length?held.campuses.join(', '):<em>none</em>}</li>
        <li><b>Duration</b> {d.course?.duration_value!=null?`${fmtNumber(Number(d.course.duration_value))} ${d.course.duration_unit||''}`:<em>none</em>} · <b>Delivery</b> {d.course?.delivery_mode||<em>none</em>} · <b>Open to international</b> {d.course?.open_to_international==null?<em>not known</em>:d.course.open_to_international?'yes':'no'}</li>
      </ul>
      <Part title="Page reads kept" rows={d.reads} empty="No read kept." render={r=><><span>{fmtDateTime(r.at)}</span><small>{r.via||'—'} · {r.identity?`proved by ${String(r.identity).replaceAll('_',' ')}`:'not proved'} · {r.url}</small></>}/>
      <Part title="Page searches" rows={d.searches} empty="No page search." render={r=><><span>{r.stage} · {r.state}</span><small>{r.query||''} · {fmtNumber(r.results||0)} results{r.bound_url?` · bound ${r.bound_url}`:''}</small></>}/>
      <Part title="AI page match tries" rows={d.ai_match} empty="No AI page match try." render={r=><><span>Try {r.attempt||'—'} · {r.state==='chosen'?'chose a page':r.state==='none'?'no page fitted':r.state}</span><small>{fmtNumber(r.candidates||0)} pages offered{r.chosen_url?` · ${r.chosen_url}`:''}{r.reason?` · ${r.reason}`:''}{r.refused?` · refused: ${r.refused}`:''}{r.error?` · error: ${r.error}`:''} · {fmtDateTime(r.decided_at||r.created_at)}</small></>}/>
      <Part title="Page changes" rows={d.relinks} empty="No page change." render={r=><><span>{fmtDateTime(r.at)}</span><small>{r.old_url||'—'} → {r.new_url||'—'} · {r.reason||''}</small></>}/>
      <Part title="AI field fills" rows={d.field_fills} empty="No AI field fill." render={r=>{const f=FILL[r.state]||[r.state,'neutral'];return <><span>{String(r.field).replaceAll('_',' ')} <StatusChip value={r.state} tone={f[1]} label={f[0]}/></span><small>{r.value?`Value: ${r.value} · `:''}{r.reason||''}{r.quote?` · “${r.quote}”`:''} · {fmtDateTime(r.updated_at)}</small></>}}/>
      <Part title="Admissions and refusals" rows={d.admissions} empty="Nothing admitted or refused from a page reading." render={r=><><span>{String(r.field_key).replaceAll('_',' ')} · {r.status}</span><small>{r.reason_code||''} · {fmtDateTime(r.decided_at)}</small></>}/>
      <Part title="Fee reader" rows={d.fee_rows} empty="The fee reader matched no fee row to this course." render={r=><><span>{fmtMoney(r.amount_min,r.currency_code)}{r.amount_max&&r.amount_max!==r.amount_min?` – ${fmtMoney(r.amount_max,r.currency_code)}`:''} · {r.audience} · {r.outcome}</span><small>{r.note||''}{r.quote?` · “${r.quote}”`:''}</small></>}/>
      <Part title="Cross-checks" rows={d.crosschecks} empty="No cross-check finding." render={r=><><span>{r.field} · {r.state}</span><small>held {r.held_value} · page {r.page_value}{r.quote?` · “${r.quote}”`:''}</small></>}/>
      <Part title="Set by hand" rows={d.locks} empty="Nothing set by hand." render={r=><><span>{String(r.field).replaceAll('_',' ')} · {r.mode}</span><small>{fmtDateTime(r.at)}</small></>}/>
      <Part title="Read with AI requests" rows={d.read_now} empty="Not asked yet." render={r=><><span>{fmtDateTime(r.at)}</span><small>{r.detail?.reason} · {r.detail?.page_read_again?'page read again':'no page'} · AI: {(r.detail?.ai_fields||[]).join(', ')||'nothing missing'}</small></>}/>
    </div>}
  </section>
}
function Part({title,rows,empty,render}){return <><h4>{title} <small>{fmtNumber((rows||[]).length)}</small></h4>{(rows||[]).length?<ul className="qw-list ca-list">{rows.map((r,i)=><li key={i}>{render(r)}</li>)}</ul>:<p className="ca-empty">{empty}</p>}</>}
