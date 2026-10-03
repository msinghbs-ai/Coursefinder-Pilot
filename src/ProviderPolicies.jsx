// Coverage › Attributes › English policies and academic calendars (Decision 227, 2 Oct 2026).
// The coverage-sweep worker reads each university's English language policy and academic calendar and parses them
// (no AI). An English policy gives a default requirement for undergraduate and postgraduate coursework courses and may
// name courses with their own requirement. Nothing reaches the catalogue until a Platform Admin approves the policy;
// approval adds the requirement only to courses that have none, and holds back research degrees, double degrees and
// courses the policy names. A default that most course pages disagree with cannot be approved.
// Read/write: public.admin_provider_policies_read (Pipeline Operator and above) / admin_provider_policy_decide
// (Platform Admin).
// v2.15.155 (3 Oct 2026, Platform Admin 00:57): tick several and Approve selected or Reject selected
// (public.admin_provider_policy_decide_bulk); approving one document closes the university's other waiting documents of the
// same kind, so a university never shows an approved document beside a greyed Approve button.
import React,{useEffect,useState}from'react'
import{CalendarDays,Check,ExternalLink,Languages,RefreshCw,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,SectionTitle,StatusChip}from'./ui-kit'
import{fmtDateTime,fmtNumber}from'./lib/format.js'
import{MONTHS}from'./RecordEditor'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
export const POLICY_OUTCOME={write:'Will be added',agrees:'Already the same',differs:'Different score on record (not changed)',other_value:'Other tests on record (not changed)',
  set_by_hand:'Set by hand (not changed)',in_review:'English review open (not changed)',waiting:'Waiting for the course page or the AI check',held:'Held back'}
export const POLICY_CAVEAT={level_not_stated:'The policy does not say which study levels this applies to',higher_unlisted:'Some courses need higher scores that the policy does not list',
  exceptions_unlisted:'The policy has exceptions it does not name',course_groups:'The policy also sets scores by course group'}
const LEVEL={undergraduate:'Undergraduate',postgraduate:'Postgraduate coursework'}
const TEST={IELTS:'IELTS',PTE:'PTE',TOEFL_IBT:'TOEFL iBT',CAE:'Cambridge'}
const minBand=c=>{const v=Object.values(c||{}).map(Number).filter(n=>!Number.isNaN(n));return v.length?Math.min(...v):null}
export function describeReq(r){const b=minBand(r.component_scores);return `${TEST[r.test_code]||r.test_code} ${fmtNumber(Number(r.overall_score))}${b!=null?` (no band below ${fmtNumber(b)})`:''}`}
// agreement with the scores course pages already gave (the approval gate: at least 10 compared, more differ than agree)
export function agreement(plan){const a=Number(plan?.agrees||0),d=Number(plan?.differs||0);return{a,d,blocked:a+d>=10&&d>a}}
const periodName=p=>p.replace(/^(\w)/,m=>m.toUpperCase()).replace('_',' ')
const CAL_COLS=['semester 1','semester 2','trimester 1','trimester 2','trimester 3']

function PlanRows({id}){
  const[rows,setRows]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{supabase.rpc('admin_provider_policies_read',{p_kind:'english_policy',p_id:id}).then(({data,error})=>error?setErr(errText(error)):setRows(data?.rows||[]))},[id])
  if(err)return <p className="fr-error" role="alert">{err}</p>
  if(!rows)return <Loading label="Loading courses…"/>
  return <div className="cf-table-wrap"><table className="cf-table" data-policy-rows><thead><tr><th>Course</th><th>Level</th><th>IELTS from the policy</th><th>IELTS on record</th><th>On approval</th></tr></thead>
    <tbody>{rows.map(r=><tr key={r.course_id} data-outcome={r.outcome}>
      <td>{r.title}</td><td>{r.study_level||'—'}</td><td>{r.ielts!=null?fmtNumber(Number(r.ielts)):'—'}</td><td>{r.existing?.IELTS!=null?fmtNumber(Number(r.existing.IELTS)):'—'}</td>
      <td><StatusChip value={r.outcome} tone={r.outcome==='write'?'success':r.outcome==='differs'?'warning':'neutral'} label={r.outcome==='held'?`Held back: ${r.reason}`:(POLICY_OUTCOME[r.outcome]||r.outcome)}/></td>
    </tr>)}</tbody></table></div>
}

const COUNTRY_NAME={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
export default function ProviderPolicies({country='',provider=null}={}){
  const[kind,setKind]=useState('english_policy'),[data,setData]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[open,setOpen]=useState(null),[show,setShow]=useState('waiting'),[sel,setSel]=useState(()=>new Set()),[note,setNote]=useState('')
  // v2.15.162 (Platform Admin, 3 Oct 2026 12:05): each study period is its own column with the suggested month as an input;
  // Approve applies the months as shown, edited or not. Edited months are saved by hand (admin_provider_calendar_set) and the
  // parsed document is closed, so what the course pages get is always what the Platform Admin saw.
  const[months,setMonths]=useState({})
  const monthOf=(x,per)=>{const e=months[x.id]?.[per];if(e!==undefined)return e;const f=(x.periods||[]).find(q=>q.period===per);return f?.months?.[0]?String(f.months[0]):''}
  const edited=x=>(x.periods||[]).some(q=>{const e=months[x.id]?.[q.period];return e!==undefined&&e!==(q.months?.[0]?String(q.months[0]):'')})
  const approveCalendar=async x=>{
    const periods=(x.periods||[]).map(q=>({period:q.period,month:monthOf(x,q.period)})).filter(q=>q.month)
    if(!periods.length){setErr('Give a month for at least one period.');return}
    const text=`Approve the academic calendar for ${x.provider}: ${periods.map(q=>`${periodName(q.period)} starts in ${MONTHS[Number(q.month)-1]}`).join(', ')}? Waiting intake reviews for its semester-only course pages are answered within 10 minutes; courses with intakes already are not changed.`
    if(!window.confirm(text))return
    setBusy(true);setErr('')
    try{
      if(edited(x)){
        const{error:e1}=await supabase.rpc('admin_provider_calendar_set',{p_provider_id:x.provider_id,p_periods:periods,p_url:x.url,p_note:'Months set by a Platform Admin on the Academic calendars list'});if(e1)throw e1
        const{error:e2}=await supabase.rpc('admin_provider_policy_decide',{p_id:x.id,p_action:'reject',p_note:'Replaced by the months entered on the Academic calendars list'});if(e2)throw e2
      }else{const{error}=await supabase.rpc('admin_provider_policy_decide',{p_id:x.id,p_action:'approve',p_note:null});if(error)throw error}
      setSel(new Set());await load()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  const load=async(k=kind)=>{setErr('');try{const{data:d,error}=await supabase.rpc('admin_provider_policies_read',{p_kind:k,p_id:null});if(error)throw error;setData(d)}catch(e){setErr(errText(e))}}
  useEffect(()=>{setData(null);setOpen(null);setSel(new Set());setNote('');load(kind)},[kind])
  const decide=async(x,action)=>{
    const add=Number(x.plan?.write||0)
    const text=action==='approve'?(kind==='english_policy'?`Approve the English policy for ${x.provider}? ${fmtNumber(add)} courses with no English requirement get it within 10 minutes; courses that already have one are not changed.`:`Approve the academic calendar for ${x.provider}? Its start months are recorded for turning semester names into months.`):`Reject this ${kind==='english_policy'?'English policy':'calendar'} for ${x.provider}? Nothing is written.`
    if(!window.confirm(text))return
    setBusy(true);setErr('')
    try{const{error}=await supabase.rpc('admin_provider_policy_decide',{p_id:x.id,p_action:action,p_note:null});if(error)throw error;setSel(new Set());await load()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  const decideMany=async(rows,action)=>{
    const ids=rows.map(x=>x.id);if(!ids.length)return
    const add=rows.reduce((a,x)=>a+Number(x.plan?.write||0),0),unis=new Set(rows.map(x=>x.provider_id)).size
    const what=kind==='english_policy'?'English policies':'academic calendars'
    const text=action==='approve'?`Approve ${fmtNumber(ids.length)} ${what} for ${fmtNumber(unis)} universities?${kind==='english_policy'?` Up to ${fmtNumber(add)} courses with no English requirement get one within 10 minutes; courses that already have one are not changed.`:''} Where two documents of one university are chosen, the first is approved and the other is closed.`:`Reject ${fmtNumber(ids.length)} ${what}? Nothing is written.`
    if(!window.confirm(text))return
    setBusy(true);setErr('');setNote('')
    try{const{data:r,error}=await supabase.rpc('admin_provider_policy_decide_bulk',{p_ids:ids,p_action:action,p_note:null});if(error)throw error
      const sk=r?.skipped||[]
      setNote(`${action==='approve'?'Approved':'Rejected'} ${fmtNumber(r?.done||0)}.${sk.length?` Not ${action==='approve'?'approved':'rejected'}: ${fmtNumber(sk.length)} (${[...new Set(sk.map(x=>x.reason))].join('; ')}).`:''}`)
      setSel(new Set());await load()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(!data)return <section className="m-panel fs-panel" data-provider-policies>{err?<p className="fr-error" role="alert">{err}</p>:<Loading label="Loading policies…"/>}</section>
  const t=data.totals||{},can=Boolean(data.can_decide)&&!busy
  const all=(data.proposals||[]).filter(x=>(!country||x.country===country)&&(!provider||x.provider_id===provider.id))
  const list=all.filter(x=>show==='all'||(show==='waiting'?x.status==='proposed':x.status!=='proposed'))
  const where=provider?provider.name:country?(COUNTRY_NAME[country]||country):''
  const nv=t.no_values_by_style||{}
  const english=kind==='english_policy'
  const approvable=x=>x.status==='proposed'&&!(english&&agreement(x.plan).blocked)
  const waitingShown=list.filter(x=>x.status==='proposed')
  const chosen=waitingShown.filter(x=>sel.has(x.id))
  const toggle=id=>setSel(s=>{const n=new Set(s);n.has(id)?n.delete(id):n.add(id);return n})
  const bulk=Boolean(data.can_decide)&&waitingShown.length>0
  return <section className="m-panel fs-panel" data-provider-policies>
    <SectionTitle icon={english?Languages:CalendarDays} title={english?'English policies':'Academic calendars'}
      subtitle={english?'Each university\'s English language policy, read from its own site and parsed without AI. A Platform Admin approves each one; approval gives its default score to undergraduate and postgraduate coursework courses that have none, and holds back research degrees, double degrees and courses the policy names.':'When each study period (Semester 1, Trimester 2, Term 3) starts at each university, read from its academic calendar. It is used for one thing only: a course page that gives its start as a study period ("starts in Semester 1") rather than a month is turned into that month. A course\'s start months still come from its own page; a calendar never adds a start to a course whose page does not name one. A Platform Admin approves each calendar.'}
      action={<Button compact onClick={()=>load()} disabled={busy}><RefreshCw size={14}/>Refresh</Button>}/>
    <div className="pp-kind" role="group" aria-label="Document type">
      <Button compact variant={english?'primary':undefined} aria-pressed={english} onClick={()=>setKind('english_policy')}><Languages size={13}/>English policies</Button>
      <Button compact variant={!english?'primary':undefined} aria-pressed={!english} onClick={()=>setKind('intake_calendar')}><CalendarDays size={13}/>Academic calendars</Button>
    </div>
    {err&&<p className="fr-error" role="alert">{err}</p>}
    {where&&<p className="sd-desc fs-scope" data-policy-scope>Showing {fmtNumber(all.length)} for <strong>{where}</strong>, as chosen above.</p>}
    <dl className="fs-totals">
      <div><dt>Universities with a document found</dt><dd>{fmtNumber(t.providers_found||0)}</dd></div>
      <div><dt>Documents read</dt><dd>{fmtNumber(t.documents_read||0)} of {fmtNumber(t.documents_found||0)}</dd></div>
      <div><dt>Waiting for approval</dt><dd>{fmtNumber((data.proposals||[]).filter(x=>x.status==='proposed').length)}</dd></div>
      <div><dt>Read, nothing usable</dt><dd title={Object.entries(nv).map(([k,n])=>`${k}: ${n}`).join(' · ')}>{fmtNumber(Object.values(nv).reduce((a,n)=>a+Number(n),0))}</dd></div>
    </dl>
    {english&&(nv.bands||nv.by_faculty||nv.course_specific)?<p className="sd-desc" data-policy-not-usable>Not usable as a default: {[nv.bands&&`${fmtNumber(nv.bands)} set scores by English band`,nv.by_faculty&&`${fmtNumber(nv.by_faculty)} by faculty`,nv.course_specific&&`${fmtNumber(nv.course_specific)} send you to each course page`].filter(Boolean).join(', ')}. Those courses keep getting English from their own pages.</p>:null}
    <div className="fs-bar"><label><small>Show</small><select className="fv-filter" value={show} onChange={e=>setShow(e.target.value)} aria-label="Show policies">
      <option value="waiting">Waiting ({fmtNumber(all.filter(x=>x.status==='proposed').length)})</option><option value="decided">Decided ({fmtNumber(all.filter(x=>x.status!=='proposed').length)})</option><option value="all">All ({fmtNumber(all.length)})</option></select></label></div>
    {bulk&&<div className="sd-actions pp-bulk" data-policy-bulk>
      <Button compact onClick={()=>setSel(new Set(waitingShown.filter(approvable).map(x=>x.id)))} disabled={busy}>Select all that can be approved ({fmtNumber(waitingShown.filter(approvable).length)})</Button>
      {chosen.length>0&&<Button compact onClick={()=>setSel(new Set())} disabled={busy}>Clear ({fmtNumber(chosen.length)})</Button>}
      <Button compact variant="primary" onClick={()=>decideMany(chosen.filter(approvable),'approve')} disabled={busy||!chosen.filter(approvable).length}><Check size={13}/>Approve selected ({fmtNumber(chosen.filter(approvable).length)}){english&&chosen.length?` · up to ${fmtNumber(chosen.filter(approvable).reduce((a,x)=>a+Number(x.plan?.write||0),0))} courses`:''}</Button>
      <Button compact onClick={()=>decideMany(chosen,'reject')} disabled={busy||!chosen.length}><X size={13}/>Reject selected ({fmtNumber(chosen.length)})</Button>
    </div>}
    {note&&<p className="sd-desc" role="status" data-policy-bulk-result>{note}</p>}
    {!list.length?<p className="sd-desc">{show==='waiting'?'Nothing is waiting for approval.':'Nothing here yet.'}</p>:
    <div className="cf-table-wrap"><table className="cf-table" data-policy-list><thead><tr>
      {bulk&&<th aria-label="Choose"/>}<th>University</th>{english?<th>What the policy says</th>:CAL_COLS.map(c=><th key={c}>{periodName(c)}</th>)}{!english&&<th>Other periods</th>}{english&&<><th>Course pages</th><th>Will be added</th></>}<th>Decision</th></tr></thead>
      <tbody>{list.map(x=>{const ag=agreement(x.plan);return <React.Fragment key={x.id}><tr data-policy={x.id}>
        {bulk&&<td>{x.status==='proposed'&&<input type="checkbox" aria-label={`Choose ${x.provider}`} checked={sel.has(x.id)} onChange={()=>toggle(x.id)} disabled={busy}/>}</td>}
        <td>{english?<button type="button" className="cf-link fs-open" onClick={()=>setOpen(open===x.id?null:x.id)} aria-expanded={open===x.id}>{x.provider}</button>:x.provider}
          <a href={x.url} target="_blank" rel="noreferrer" className="cf-link" aria-label="Open the document"><ExternalLink size={12}/></a>
          {english&&<button type="button" className="m-link-button fs-review" onClick={()=>setOpen(open===x.id?null:x.id)}>{open===x.id?'Hide courses':'Review courses'}</button>}</td>
        {english&&<td>{Object.entries(x.defaults||{}).map(([lv,reqs])=><div key={lv} data-policy-default={lv}><strong>{LEVEL[lv]||lv}:</strong> {(reqs||[]).filter(r=>r.test_code==='IELTS').map(describeReq).join('; ')}</div>)}
            {Number(x.named_requirements||0)>0&&<div className="sd-desc">{fmtNumber(x.named_requirements)} courses named with their own score</div>}
            {(x.caveats||[]).map(c=><div key={c} className="pp-caveat" data-caveat={c}>{POLICY_CAVEAT[c]||c}</div>)}</td>}
        {!english&&CAL_COLS.map(c=>{const q=(x.periods||[]).find(z=>z.period===c);return <td key={c} data-period={c}>{!q?'—':x.status==='proposed'&&can?<select className="fv-input" aria-label={`${x.provider} ${periodName(c)} month`} value={monthOf(x,c)} onChange={e=>setMonths(m=>({...m,[x.id]:{...(m[x.id]||{}),[c]:e.target.value}}))} disabled={busy}><option value="">Month…</option>{MONTHS.map((m,i)=><option key={m} value={i+1}>{m}</option>)}</select>:(q.months||[]).map(m=>MONTHS[m-1]).join(', ')}{q&&q.months?.length>1&&<small className="sd-desc"> several dates found</small>}</td>})}
        {!english&&<td>{(x.periods||[]).filter(q=>!CAL_COLS.includes(q.period)).map(q=><div key={q.period}>{periodName(q.period)}: {x.status==='proposed'&&can?<select className="fv-input" aria-label={`${x.provider} ${periodName(q.period)} month`} value={monthOf(x,q.period)} onChange={e=>setMonths(m=>({...m,[x.id]:{...(m[x.id]||{}),[q.period]:e.target.value}}))} disabled={busy}><option value="">Month…</option>{MONTHS.map((m,i)=><option key={m} value={i+1}>{m}</option>)}</select>:(q.months||[]).map(m=>MONTHS[m-1]).join(', ')}</div>)||'—'}</td>}
        {english&&<><td data-agreement>{ag.a+ag.d?`${fmtNumber(ag.a)} agree · ${fmtNumber(ag.d)} differ`:'None to compare'}{ag.blocked&&<div className="pp-caveat" data-blocked>Does not match most course pages, so it cannot be approved</div>}</td>
          <td>{fmtNumber(x.plan?.write||0)}{x.apply_summary?.written!=null&&<small className="sd-desc"> · {fmtNumber(x.apply_summary.written)} added</small>}</td></>}
        <td>{x.status!=='proposed'?<><StatusChip value={x.status} tone={x.status==='approved'?'success':'neutral'} label={x.status==='approved'?'Approved':'Rejected'}/>{x.decided_at&&<small className="sd-desc">{fmtDateTime(x.decided_at)}</small>}</>
          :can?<div className="sd-actions"><Button compact variant="primary" disabled={english&&ag.blocked} title={english&&ag.blocked?'Most course pages give a different score, so this document cannot be approved. Reject it, or approve another document of this university.':undefined} onClick={()=>english?decide(x,'approve'):approveCalendar(x)}><Check size={13}/>{!english&&edited(x)?'Approve as edited':'Approve'}</Button><Button compact onClick={()=>decide(x,'reject')}><X size={13}/>Reject</Button></div>
          :<StatusChip value="pending" tone="warning" label="Waiting for a Platform Admin"/>}</td>
      </tr>{open===x.id&&<tr className="fs-detail"><td colSpan={bulk?6:5}><PlanRows id={x.id}/></td></tr>}</React.Fragment>})}</tbody></table></div>}
  </section>
}

// v2.15.161 (Decision 228, rapid admission plan step 1): universities whose course pages name only study periods, with
// the start months a Platform Admin enters by hand from the university's calendar. The job provider-calendar-intakes
// answers the waiting reviews within 10 minutes; a calendar never adds a start to a course whose page names none.
// Read: public.admin_semester_intakes_read(); write: public.admin_provider_calendar_set (migrations 20261003001500/001510).
export function CalendarByHand({country=''}){
  const[data,setData]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[form,setForm]=useState({}),[note,setNote]=useState('')
  const load=async()=>{setErr('');const{data:d,error}=await supabase.rpc('admin_semester_intakes_read');if(error)throw error;setData(d)}
  useEffect(()=>{load().catch(e=>setErr(errText(e)))},[])
  if(!data)return <section className="m-panel fs-panel" data-calendar-by-hand>{err?<p className="fr-error" role="alert">{err}</p>:<Loading label="Loading waiting intake reviews…"/>}</section>
  const rows=(data.providers||[])
  const save=async p=>{const f=form[p.provider_id]||{};const periods=(p.periods||[]).map(per=>({period:per,month:f[per]||''})).filter(x=>x.month)
    if(!periods.length||!/^https?:\/\//.test(f.url||'')){setErr('Give a month for at least one period and the calendar page address.');return}
    if(!window.confirm(`Set ${p.provider}: ${periods.map(x=>`${periodName(x.period)} starts in ${MONTHS[Number(x.month)-1]}`).join(', ')}? The waiting reviews are answered within 10 minutes; courses with intakes already are left alone.`))return
    setBusy(true);setErr('');setNote('')
    try{const{data:r,error}=await supabase.rpc('admin_provider_calendar_set',{p_provider_id:p.provider_id,p_periods:periods,p_url:f.url,p_note:f.note||null});if(error)throw error
      setNote(`Saved for ${p.provider}: ${fmtNumber(r?.to_answer||0)} reviews will be answered.`);await load()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  const set=(id,k,v)=>setForm(x=>({...x,[id]:{...(x[id]||{}),[k]:v}}))
  return <section className="m-panel fs-panel" data-calendar-by-hand>
    <SectionTitle icon={CalendarDays} title="Start months by hand" subtitle={`${fmtNumber(rows.reduce((a,r)=>a+Number(r.reviews||0),0))} intake reviews wait because the course page names only a study period. Enter the month each period starts, from the university's calendar page, and the reviews are answered within 10 minutes (Decision 228). Courses with intakes already, or set by hand, are left alone.`}/>
    {err&&<p className="fr-error" role="alert">{err}</p>}{note&&<p className="sd-desc" role="status">{note}</p>}
    {!rows.length?<p className="sd-desc">No intake review is waiting on a calendar.</p>:
    <div className="cf-table-wrap"><table className="cf-table" data-calendar-by-hand-list><thead><tr><th>University</th><th>Waiting</th><th>Periods on its pages</th><th>Start months</th>{data.can_set&&<th>Calendar page and save</th>}</tr></thead><tbody>
      {rows.map(p=>{const f=form[p.provider_id]||{};const known=p.months||{};return <tr key={p.provider_id} data-calendar-provider={p.provider_id}>
        <td><strong>{p.provider}</strong>{p.sample&&<div className="sd-desc">{String(p.sample).slice(0,120)}</div>}</td>
        <td>{fmtNumber(p.reviews||0)}{Number(p.answerable||0)>0&&<div className="sd-desc">{fmtNumber(p.answerable)} answerable now</div>}</td>
        <td>{(p.periods||[]).map(periodName).join(', ')||'—'}</td>
        <td>{(p.periods||[]).map(per=><div key={per} className="re-line"><small>{periodName(per)}</small>{data.can_set?<select className="fv-input" aria-label={`${p.provider} ${periodName(per)} month`} value={f[per]??(known[per]||'')} onChange={e=>set(p.provider_id,per,e.target.value)} disabled={busy}><option value="">Month…</option>{MONTHS.map((m,i)=><option key={m} value={i+1}>{m}</option>)}</select>:<span>{known[per]?MONTHS[Number(known[per])-1]:'—'}</span>}</div>)}</td>
        {data.can_set&&<td><input className="fv-input" type="url" placeholder={p.calendar_url||'https://'} value={f.url??(p.calendar_url||'')} onChange={e=>set(p.provider_id,'url',e.target.value)} aria-label={`${p.provider} calendar page`} disabled={busy}/>
          <Button compact variant="primary" onClick={()=>save(p)} disabled={busy}><Check size={13}/>Save</Button></td>}
      </tr>})}</tbody></table></div>}
  </section>
}
