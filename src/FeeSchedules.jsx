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

// Decision 213 (Platform Admin, 2 Oct 2026): approve several schedules at once, review every row, and close a schedule
// that has nothing to add (approval then records the decision and settles the flagged fees it answers, Decision 210).
const COUNTRY_NAME={AU:'Australia',NZ:'New Zealand',CA:'Canada'}
// Decision 217: follows the Coverage country and university filter (country/provider props)
export default function FeeSchedules({country='',provider=null}={}){
  const[data,setData]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(false),[open,setOpen]=useState(null),[show,setShow]=useState('all'),[picked,setPicked]=useState(()=>new Set()),[progress,setProgress]=useState('')
  const load=async()=>{setErr('');try{const{data:d,error}=await supabase.rpc('admin_provider_fee_schedules_read',{p_source_id:null,p_limit:300});if(error)throw error;setData(d);setPicked(new Set())}catch(e){setErr(errText(e))}}
  useEffect(()=>{load()},[])
  const one=async(doc,action)=>{const{error}=await supabase.rpc('admin_provider_fee_schedule_decide',{p_source_id:doc.id,p_action:action,p_note:null});if(error)throw error}
  const decide=async(doc,action)=>{
    const text=action==='approve'?(doc.new?`Approve the fee schedule for ${doc.provider}? ${fmtNumber(doc.new)} courses without a fee get the schedule's fee. Courses with a different fee are not changed.`:`Close the fee schedule for ${doc.provider}? It has nothing to add; approving records the decision and settles flagged fees it answers. Nothing else is written.`):`Reject the fee schedule for ${doc.provider}? Nothing is written.`
    if(!window.confirm(text))return
    setBusy(true);setErr('')
    try{await one(doc,action);await load()}catch(e){setErr(errText(e))}finally{setBusy(false)}}
  const bulk=async action=>{
    const docs=(data?.documents||[]).filter(d=>picked.has(d.id)&&!d.decision);if(!docs.length)return
    const adds=docs.reduce((n,d)=>n+Number(d.new||0),0)
    if(!window.confirm(action==='approve'?`Approve ${docs.length} fee schedules? ${fmtNumber(adds)} courses without a fee get a fee. Courses with a different fee are not changed.`:`Reject ${docs.length} fee schedules? Nothing is written.`))return
    setBusy(true);setErr('');const failed=[]
    for(let k=0;k<docs.length;k++){setProgress(`${k+1} of ${docs.length}`);try{await one(docs[k],action)}catch(e){failed.push(`${docs[k].provider}: ${errText(e)}`)}}
    setProgress('');if(failed.length)setErr(`Not done: ${failed.join(' · ')}`);await load();setBusy(false)}
  if(!data)return err?<p className="fr-error" role="alert">{err}</p>:<Loading label="Loading fee schedules…"/>
  const t=data.totals||{},can=Boolean(data.can_decide)&&!busy,everyDoc=data.documents||[]
  const scoped=Boolean(country||provider)
  const all=everyDoc.filter(d=>(!country||d.country===country)&&(!provider||d.provider_id===provider.id))
  const where=provider?provider.name:country?(COUNTRY_NAME[country]||country):''
  const docs=all.filter(d=>show==='all'||(show==='waiting'?!d.decision:Boolean(d.decision)))
  const waiting=docs.filter(d=>!d.decision),allPicked=waiting.length>0&&waiting.every(d=>picked.has(d.id))
  const toggle=id=>setPicked(p=>{const n=new Set(p);n.has(id)?n.delete(id):n.add(id);return n})
  const other=d=>Math.max(0,Number(d.rows||0)-Number(d.new||0)-Number(d.same||0)-Number(d.differs||0)-Number(d.no_course||0))
  return <section className="m-panel fs-panel" data-fee-schedules>
    <SectionTitle icon={FileSpreadsheet} title="Fee schedules" subtitle="Each university's international fee schedule, read and matched to its courses by CRICOS code. A Platform Admin approves each one; approval adds a fee only to courses that have none. Open a schedule to review every row."
      action={<Button compact onClick={load} disabled={busy}><RefreshCw size={14}/>Refresh</Button>}/>
    {err&&<p className="fr-error" role="alert">{err}</p>}
    {scoped&&<p className="sd-desc fs-scope" data-fee-scope>{all.length
      ?<>Showing {fmtNumber(all.length)} of {fmtNumber(everyDoc.length)} fee schedules: those for <strong>{where}</strong>, as chosen above.</>
      :<>No fee schedules for <strong>{where}</strong>. {country&&country!=='AU'?'Fee schedules are matched to courses by CRICOS code, so they cover Australian providers only; this country\'s fees come from course pages.':'Choose another university or country above to see its schedules.'}</>}</p>}
    <dl className="fs-totals">
      {!scoped&&<><div><dt>Providers searched</dt><dd>{fmtNumber(t.providers_searched||0)}</dd></div>
      <div><dt>Waiting to search</dt><dd>{fmtNumber(t.providers_queued||0)}</dd></div>
      <div><dt>Documents read</dt><dd>{fmtNumber(t.documents_read||0)} of {fmtNumber(t.documents_found||0)}</dd></div></>}
      <div><dt>Schedules with fees</dt><dd>{fmtNumber(scoped?all.length:(t.with_fee_rows||0))}</dd></div>
      <div><dt>Waiting for approval</dt><dd>{fmtNumber(scoped?all.filter(d=>!d.decision).length:(t.awaiting_decision||0))}</dd></div>
    </dl>
    <div className="fs-bar">
      <label><small>Show</small><select className="fv-filter" value={show} onChange={e=>{setShow(e.target.value);setPicked(new Set())}} aria-label="Show schedules">
        <option value="waiting">Waiting ({fmtNumber(all.filter(d=>!d.decision).length)})</option><option value="decided">Decided ({fmtNumber(all.filter(d=>d.decision).length)})</option><option value="all">All ({fmtNumber(all.length)})</option></select></label>
      {data.can_decide&&waiting.length>0&&<div className="sd-actions" data-fee-bulk>
        <span className="sd-desc">{fmtNumber(picked.size)} selected{progress?` · working ${progress}`:''}</span>
        <Button compact variant="primary" disabled={!can||!picked.size} onClick={()=>bulk('approve')}><Check size={13}/>Approve selected</Button>
        <Button compact disabled={!can||!picked.size} onClick={()=>bulk('reject')}><X size={13}/>Reject selected</Button></div>}
    </div>
    {!docs.length?<p className="sd-desc">{show==='waiting'?'Nothing is waiting for approval.':'No fee schedule here.'}</p>:
    <div className="cf-table-wrap"><table className="cf-table" data-fee-documents><thead><tr>
      {data.can_decide&&<th>{waiting.length>0&&<input type="checkbox" aria-label="Select every waiting schedule" checked={allPicked} onChange={()=>setPicked(allPicked?new Set():new Set(waiting.map(d=>d.id)))}/>}</th>}
      <th>Provider</th><th>Year</th><th>Rows</th><th>Will be added</th><th>Same</th><th>Different</th><th>No course</th><th>Other</th><th>Decision</th></tr></thead>
      <tbody>{docs.map(d=><React.Fragment key={d.id}><tr data-doc={d.id}>
        {data.can_decide&&<td>{!d.decision&&<input type="checkbox" aria-label={`Select ${d.provider}`} checked={picked.has(d.id)} onChange={()=>toggle(d.id)}/>}</td>}
        <td><button type="button" className="cf-link fs-open" onClick={()=>setOpen(open===d.id?null:d.id)} aria-expanded={open===d.id}>{d.provider}</button>
          <a href={d.url} target="_blank" rel="noreferrer" className="cf-link" aria-label="Open the schedule"><ExternalLink size={12}/></a>
          {d.read_at&&<small className="sd-desc">Read {fmtDateTime(d.read_at)}</small>}
          <button type="button" className="m-link-button fs-review" onClick={()=>setOpen(open===d.id?null:d.id)}>{open===d.id?'Hide rows':`Review ${fmtNumber(d.rows)} rows`}</button></td>
        <td>{d.fee_year||'—'}</td><td>{fmtNumber(d.rows)}</td><td>{fmtNumber(d.new)}</td><td>{fmtNumber(d.same)}</td><td>{fmtNumber(d.differs)}</td><td>{fmtNumber(d.no_course)}</td><td>{fmtNumber(other(d))}</td>
        <td>{d.decision?<><StatusChip value={d.decision} tone={d.decision==='approved'?'success':'neutral'} label={d.decision==='approved'?'Approved':'Rejected'}/>
            {d.apply_summary&&<small className="sd-desc">{fmtNumber(d.apply_summary.written||0)} fees added{d.apply_summary.refused?` · ${fmtNumber(d.apply_summary.refused)} refused`:''}</small>}</>
          :can?<div className="sd-actions"><Button compact variant="primary" onClick={()=>decide(d,'approve')}><Check size={13}/>{d.new?'Approve':'Close (nothing to add)'}</Button><Button compact onClick={()=>decide(d,'reject')}><X size={13}/>Reject</Button></div>
          :<StatusChip value="pending" tone="warning" label="Waiting for a Platform Admin"/>}</td>
      </tr>{open===d.id&&<tr className="fs-detail"><td colSpan={data.can_decide?10:9}><Rows id={d.id}/></td></tr>}</React.Fragment>)}</tbody></table></div>}
  </section>
}
