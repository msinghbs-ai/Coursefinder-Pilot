// Coverage › Attributes › Fee schedules (Decision 205). Universities publish one international fee schedule for all
// their courses (often a PDF linked from the fee page). The coverage-sweep worker finds and reads each schedule and keeps
// the rows that carry a CRICOS code and an amount; each row is matched to the provider's course with that code.
// Nothing reaches the catalogue until a Platform Admin approves the document; approval writes a fee only where the
// course has none, and lists (does not change) courses whose current fee is different.
// Read/write: public.admin_provider_fee_schedules_read (Pipeline Operator and above) / admin_provider_fee_schedule_decide
// (Platform Admin).
import React,{useEffect,useState}from'react'
import{Check,ExternalLink,FileSpreadsheet,RefreshCw,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,SectionTitle,StatusChip}from'./ui-kit'
import{fmtDateTime,fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
export const FEE_OUTCOME={new:'Will be added',same:'Already the same',differs:'Different fee on record (not changed)',in_review:'Waiting in review (not changed)',
  several_amounts:'Several amounts (not used)',basis_not_used:'Per semester or other basis (not used)',annual_used:'Total (annual used instead)',no_course:'No course with this code'}
const money=(n,c)=>n==null?'—':`${c||''} ${fmtNumber(Number(n))}`.trim()

function Rows({id}){
  const[rows,setRows]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{supabase.rpc('admin_provider_fee_schedules_read',{p_source_id:id}).then(({data,error})=>error?setErr(errText(error)):setRows(data?.rows||[]))},[id])
  if(err)return <p className="fr-error" role="alert">{err}</p>
  if(!rows)return <Loading label="Loading rows…"/>
  return <div className="cf-table-wrap"><table className="cf-table" data-fee-rows><thead><tr><th>Course</th><th>CRICOS</th><th>Fee in schedule</th><th>Fee on record</th><th>On approval</th></tr></thead>
    <tbody>{rows.map(r=><tr key={r.row_id} data-outcome={r.outcome}>
      <td>{r.course_title||'—'}</td><td>{r.course_code}</td>
      <td>{money(r.amount,r.currency_code)} <small className="sd-desc">{r.basis==='annual'?'a year':r.basis==='total_indicative'?'total':r.basis}{r.fee_year?` · ${r.fee_year}`:''}</small></td>
      <td>{money(r.current_amount,r.currency_code)}</td>
      <td><StatusChip value={r.outcome} tone={r.outcome==='new'?'success':r.outcome==='differs'||r.outcome==='in_review'?'warning':'neutral'} label={FEE_OUTCOME[r.outcome]||r.outcome}/></td>
    </tr>)}</tbody></table></div>
}

export default function FeeSchedules(){
  const[data,setData]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[open,setOpen]=useState(null)
  const load=async()=>{setErr('');try{const{data:d,error}=await supabase.rpc('admin_provider_fee_schedules_read',{p_source_id:null,p_limit:50});if(error)throw error;setData(d)}catch(e){setErr(errText(e))}}
  useEffect(()=>{load()},[])
  const decide=async(doc,action)=>{
    const text=action==='approve'?`Approve the fee schedule for ${doc.provider}? ${fmtNumber(doc.new)} courses without a fee get the schedule's fee. Courses with a different fee are not changed.`:`Reject the fee schedule for ${doc.provider}? Nothing is written.`
    if(!window.confirm(text))return
    setBusy(true);setErr('')
    try{const{error}=await supabase.rpc('admin_provider_fee_schedule_decide',{p_source_id:doc.id,p_action:action,p_note:null});if(error)throw error;await load()}
    catch(e){setErr(errText(e))}finally{setBusy(false)}}
  if(!data)return err?<p className="fr-error" role="alert">{err}</p>:<Loading label="Loading fee schedules…"/>
  const t=data.totals||{},can=Boolean(data.can_decide)&&!busy
  return <section className="m-panel fs-panel" data-fee-schedules>
    <SectionTitle icon={FileSpreadsheet} title="Fee schedules" subtitle="Each university's international fee schedule, read and matched to its courses by CRICOS code. A Platform Admin approves each one; approval adds a fee only to courses that have none."
      action={<Button compact onClick={load}><RefreshCw size={14}/>Refresh</Button>}/>
    {err&&<p className="fr-error" role="alert">{err}</p>}
    <dl className="fs-totals">
      <div><dt>Providers searched</dt><dd>{fmtNumber(t.providers_searched||0)}</dd></div>
      <div><dt>Waiting to search</dt><dd>{fmtNumber(t.providers_queued||0)}</dd></div>
      <div><dt>Documents read</dt><dd>{fmtNumber(t.documents_read||0)} of {fmtNumber(t.documents_found||0)}</dd></div>
      <div><dt>Schedules with fees</dt><dd>{fmtNumber(t.with_fee_rows||0)}</dd></div>
      <div><dt>Waiting for approval</dt><dd>{fmtNumber(t.awaiting_decision||0)}</dd></div>
    </dl>
    {!(data.documents||[]).length?<p className="sd-desc">No fee schedule with fees yet.</p>:
    <div className="cf-table-wrap"><table className="cf-table" data-fee-documents><thead><tr><th>Provider</th><th>Year</th><th>Rows</th><th>Will be added</th><th>Same</th><th>Different</th><th>No course</th><th>Decision</th></tr></thead>
      <tbody>{data.documents.map(d=><React.Fragment key={d.id}><tr data-doc={d.id}>
        <td><button type="button" className="cf-link fs-open" onClick={()=>setOpen(open===d.id?null:d.id)} aria-expanded={open===d.id}>{d.provider}</button>
          <a href={d.url} target="_blank" rel="noreferrer" className="cf-link" aria-label="Open the schedule"><ExternalLink size={12}/></a>
          {d.read_at&&<small className="sd-desc">Read {fmtDateTime(d.read_at)}</small>}</td>
        <td>{d.fee_year||'—'}</td><td>{fmtNumber(d.rows)}</td><td>{fmtNumber(d.new)}</td><td>{fmtNumber(d.same)}</td><td>{fmtNumber(d.differs)}</td><td>{fmtNumber(d.no_course)}</td>
        <td>{d.decision?<><StatusChip value={d.decision} tone={d.decision==='approved'?'success':'neutral'} label={d.decision==='approved'?'Approved':'Rejected'}/>
            {d.apply_summary&&<small className="sd-desc">{fmtNumber(d.apply_summary.written||0)} fees added{d.apply_summary.refused?` · ${fmtNumber(d.apply_summary.refused)} refused`:''}</small>}</>
          :can?<div className="sd-actions"><Button compact variant="primary" disabled={!d.new} onClick={()=>decide(d,'approve')}><Check size={13}/>Approve</Button><Button compact onClick={()=>decide(d,'reject')}><X size={13}/>Reject</Button></div>
          :<StatusChip value="pending" tone="warning" label="Waiting for a Platform Admin"/>}</td>
      </tr>{open===d.id&&<tr className="fs-detail"><td colSpan={8}><Rows id={d.id}/></td></tr>}</React.Fragment>)}</tbody></table></div>}
  </section>
}
