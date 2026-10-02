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
      {bulk&&<th aria-label="Choose"/>}<th>University</th><th>{english?'What the policy says':'Start months'}</th>{english&&<><th>Course pages</th><th>Will be added</th></>}<th>Decision</th></tr></thead>
      <tbody>{list.map(x=>{const ag=agreement(x.plan);return <React.Fragment key={x.id}><tr data-policy={x.id}>
        {bulk&&<td>{x.status==='proposed'&&<input type="checkbox" aria-label={`Choose ${x.provider}`} checked={sel.has(x.id)} onChange={()=>toggle(x.id)} disabled={busy}/>}</td>}
        <td>{english?<button type="button" className="cf-link fs-open" onClick={()=>setOpen(open===x.id?null:x.id)} aria-expanded={open===x.id}>{x.provider}</button>:x.provider}
          <a href={x.url} target="_blank" rel="noreferrer" className="cf-link" aria-label="Open the document"><ExternalLink size={12}/></a>
          {english&&<button type="button" className="m-link-button fs-review" onClick={()=>setOpen(open===x.id?null:x.id)}>{open===x.id?'Hide courses':'Review courses'}</button>}</td>
        <td>{english?<>{Object.entries(x.defaults||{}).map(([lv,reqs])=><div key={lv} data-policy-default={lv}><strong>{LEVEL[lv]||lv}:</strong> {(reqs||[]).filter(r=>r.test_code==='IELTS').map(describeReq).join('; ')}</div>)}
            {Number(x.named_requirements||0)>0&&<div className="sd-desc">{fmtNumber(x.named_requirements)} courses named with their own score</div>}
            {(x.caveats||[]).map(c=><div key={c} className="pp-caveat" data-caveat={c}>{POLICY_CAVEAT[c]||c}</div>)}</>
          :(x.periods||[]).map(p=><div key={p.period}>{periodName(p.period)}: {(p.months||[]).map(m=>MONTHS[m-1]).join(', ')}{p.months?.length>1?' (several dates found)':''}</div>)}</td>
        {english&&<><td data-agreement>{ag.a+ag.d?`${fmtNumber(ag.a)} agree · ${fmtNumber(ag.d)} differ`:'None to compare'}{ag.blocked&&<div className="pp-caveat" data-blocked>Does not match most course pages, so it cannot be approved</div>}</td>
          <td>{fmtNumber(x.plan?.write||0)}{x.apply_summary?.written!=null&&<small className="sd-desc"> · {fmtNumber(x.apply_summary.written)} added</small>}</td></>}
        <td>{x.status!=='proposed'?<><StatusChip value={x.status} tone={x.status==='approved'?'success':'neutral'} label={x.status==='approved'?'Approved':'Rejected'}/>{x.decided_at&&<small className="sd-desc">{fmtDateTime(x.decided_at)}</small>}</>
          :can?<div className="sd-actions"><Button compact variant="primary" disabled={english&&ag.blocked} title={english&&ag.blocked?'Most course pages give a different score, so this document cannot be approved. Reject it, or approve another document of this university.':undefined} onClick={()=>decide(x,'approve')}><Check size={13}/>Approve</Button><Button compact onClick={()=>decide(x,'reject')}><X size={13}/>Reject</Button></div>
          :<StatusChip value="pending" tone="warning" label="Waiting for a Platform Admin"/>}</td>
      </tr>{open===x.id&&<tr className="fs-detail"><td colSpan={bulk?6:5}><PlanRows id={x.id}/></td></tr>}</React.Fragment>})}</tbody></table></div>}
  </section>
}
