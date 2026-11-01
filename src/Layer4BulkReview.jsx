// CF-247 SS-016 UR-18, slice 1 (Platform Admin decisions D-B1 to D-B3, 2 Nov 2026 05:18): provider bulk review inside the Layer 4 university view.
// One university and one field at a time, in the approved order: country, state or territory, campus, course delivery. Intake and English come
// later; academic entry requirements are never bulk-approved. Preview (any reviewer) lists every candidate with its class, reason and the
// evidence that covers it, with exact counts and a fingerprint of the plan. Apply is shown to the Platform Admin only and works only while the
// setting layer4.bulk_review_enabled is 1 (0 by default; switching it on in production is decision D-B4). The server checks role, switch and plan
// again (public.admin_layer4_inbox: bulk_preview, bulk_apply, bulk_reverse; security.layer4_bulk_review_v1).
import React,{useState}from'react'
import{ExternalLink,Layers}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtDate,fmtNumber}from'./ui-kit'

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
export const BULK_FIELDS=[['country','Country'],['state','State or territory'],['campus','Campus'],['location','Course delivery']]
export const BULK_CLASSES=[['eligible','Eligible'],['unchanged','Unchanged'],['protected','Protected'],['excluded_exception','Excluded: exception'],['excluded_conflict','Excluded: conflict'],['excluded_unsupported','Excluded: no evidence']]
const MODES=[['on_campus','On campus'],['online','Online'],['blended','Blended'],['on_campus_and_online','On campus and online']]
const PAGE=200
const valueText=(field,v)=>{if(!v)return'—';if(field==='country')return v.country||'not held';if(field==='state')return v.state||'not held';if(field==='campus')return v.linked?'linked':'not linked';return(MODES.find(m=>m[0]===v.mode)||[])[1]||v.mode||'not held'}

export default function Layer4BulkReview({provider,onError}){
  const[open,setOpen]=useState(false),[field,setField]=useState(''),[choices,setChoices]=useState(null),[val,setVal]=useState('')
  const[plan,setPlan]=useState(null),[busy,setBusy]=useState(false),[cls,setCls]=useState(''),[off,setOff]=useState(0)
  const[reason,setReason]=useState(''),[result,setResult]=useState(null),[revReason,setRevReason]=useState('')
  const pid=provider?.provider_id
  if(!pid)return null
  const value=()=>field==='country'?{country:val.trim().toUpperCase()}:field==='state'?{state:val.trim().toUpperCase()}:field==='campus'?{campus_id:val}:{mode:val}
  const run=(p)=>{setBusy(true);return p.catch(e=>onError?.(e.message)).finally(()=>setBusy(false))}
  const pick=f=>{setField(f);setPlan(null);setResult(null);setVal(f==='location'?'on_campus':'');setChoices(null)
    run(rpc('bulk_preview',{provider_id:pid,field:f,value:{}}).then(d=>{setChoices(d);if(f==='country')setVal(d.country||'')}))}
  const preview=(c=cls,o=0)=>{setCls(c);setOff(o);run(rpc('bulk_preview',{provider_id:pid,field,value:value(),class:c,limit:PAGE,offset:o}).then(setPlan))}
  const apply=()=>run(rpc('bulk_apply',{provider_id:pid,field,value:plan.value,fingerprint:plan.fingerprint,reason}).then(setResult))
  const reverse=()=>run(rpc('bulk_reverse',{operation_key:result.operation_key,reason:revReason}).then(r=>setResult({...result,reversal:r})))
  const n=plan?.counts||{},unit=plan?.unit==='campus'?'campuses':'courses'
  return <section className="l4b" data-l4-bulk>
    <header className="l4b-head">
      <Button compact onClick={()=>setOpen(!open)} aria-expanded={open} data-l4-bulk-toggle><Layers size={14}/>Bulk review</Button>
      {open&&<small>One university and one field at a time. Locked values and course-specific exclusions are never changed.</small>}
    </header>
    {open&&<div className="l4b-body">
      <div className="l4b-fields" role="toolbar" aria-label="Field to review">{BULK_FIELDS.map(([k,l])=><button key={k} type="button" className={field===k?'on':''} onClick={()=>pick(k)} data-bulk-field={k}>{l}</button>)}</div>
      {field&&!choices&&<Loading compact/>}
      {field&&choices&&<div className="l4b-value">
        {field==='country'&&<label>Country (two letters)<input value={val} onChange={e=>setVal(e.target.value)} maxLength={2} data-bulk-value/></label>}
        {field==='state'&&<label>State or territory code<input value={val} onChange={e=>setVal(e.target.value)} placeholder="for example VIC" data-bulk-value/></label>}
        {field==='campus'&&<label>Campus<select value={val} onChange={e=>setVal(e.target.value)} data-bulk-value><option value="">Choose a campus…</option>
          {(choices.campuses||[]).map(c=><option key={c.campus_id} value={c.campus_id}>{c.name}{c.city?` (${c.city})`:''} · {fmtNumber(c.courses)} courses linked</option>)}</select></label>}
        {field==='location'&&<label>Course delivery<select value={val} onChange={e=>setVal(e.target.value)} data-bulk-value>{MODES.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>}
        <Button compact variant="primary" disabled={!val||busy} onClick={()=>{setResult(null);preview('',0)}} data-bulk-preview>Preview</Button>
      </div>}
      {plan&&<>
        <div className="l4b-counts" data-bulk-counts>
          <span data-bulk-count="candidate"><small>{plan.unit==='campus'?'Candidate campuses':'Candidate courses'}</small><strong>{fmtNumber(n.candidate)}</strong></span>
          {BULK_CLASSES.map(([k,l])=><button key={k} type="button" className={cls===k?'on':''} onClick={()=>preview(cls===k?'':k,0)} data-bulk-count={k}><small>{l}</small><strong>{fmtNumber(n[k])}</strong></button>)}
        </div>
        <p className="l4b-note">{plan.unit==='campus'?`Country and state are kept on the campus: ${fmtNumber(n.courses_affected)} active courses are linked to the eligible campuses.`:`${fmtNumber(n.eligible)} ${unit} would change.`} Plan <code data-bulk-fingerprint>{String(plan.fingerprint||'').slice(0,12)}</code>: the same preview gives the same list.</p>
        <div className="l4b-table-wrap"><table className="l4b-table">
          <thead><tr><th>{plan.unit==='campus'?'Campus':'Course'}</th><th>Level</th><th>{plan.unit==='campus'?'Address':'Campuses'}</th><th>Now</th><th>Class</th><th>Why</th><th>Evidence</th></tr></thead>
          <tbody>{(plan.rows||[]).length===0?<tr><td colSpan={7}><Empty text="No rows in this class."/></td></tr>:plan.rows.map(r=><tr key={r.entity_id} data-bulk-row={r.class}>
            <td><strong>{r.title}</strong>{r.code&&<small> {r.code}</small>}</td><td>{r.level||'—'}</td><td>{r.campus||'—'}</td><td>{valueText(field,r.current)}</td>
            <td><em className={`l4b-class ${r.class}`}>{(BULK_CLASSES.find(c=>c[0]===r.class)||[])[1]||r.class}</em></td><td>{r.reason}</td>
            <td>{r.evidence?.page_url?<a href={r.evidence.page_url} target="_blank" rel="noreferrer">course page <ExternalLink size={11}/></a>:r.evidence?.url?<a href={r.evidence.url} target="_blank" rel="noreferrer">campus record <ExternalLink size={11}/></a>:'none'}
              {r.evidence?.read_at&&<small> read {fmtDate(r.evidence.read_at)}</small>}{r.evidence?.captured_at&&!r.evidence?.read_at&&<small> stored {fmtDate(r.evidence.captured_at)}</small>}</td></tr>)}</tbody>
        </table></div>
        {Number(plan.total)>PAGE&&<div className="l4i-pager"><Button compact disabled={off===0} onClick={()=>preview(cls,Math.max(0,off-PAGE))}>Previous</Button>
          <small data-bulk-range>{fmtNumber(off+1)}–{fmtNumber(Math.min(off+PAGE,plan.total))} of {fmtNumber(plan.total)}</small>
          <Button compact disabled={off+PAGE>=plan.total} onClick={()=>preview(cls,off+PAGE)}>Next</Button></div>}
        {!plan.can_apply?<p className="l4b-off" data-bulk-preview-only>You can preview. Only the Platform Admin applies bulk changes.</p>
        :!plan.enabled?<p className="l4b-off" data-bulk-off>Bulk apply is switched off (setting layer4.bulk_review_enabled is 0), so nothing can be written from here. Switching it on is a separate Platform Admin decision.</p>
        :<div className="l4b-apply">
          <label>Reason (kept with every course's decision)<input value={reason} onChange={e=>setReason(e.target.value)} data-bulk-reason/></label>
          <Button compact variant="primary" disabled={busy||!Number(n.eligible)||reason.trim().length<5} onClick={apply} data-bulk-apply>
            {result?.state==='partial'?'Apply the next batch':`Apply to ${fmtNumber(Math.min(Number(n.eligible),Number(plan.batch_size)))} of ${fmtNumber(n.eligible)} eligible ${unit}`}</Button>
          <small>Each Apply writes at most {fmtNumber(plan.batch_size)} {unit}; apply again to continue. Rows already written are not written twice.</small>
        </div>}
        {result&&<div className="l4b-result" role="status" data-bulk-result={result.state}>
          <strong>{result.state==='done'?'Done':'Partly applied: not finished'}</strong>
          <span>{['applied','unchanged','excluded','conflicted','failed','remaining'].map(k=>`${k} ${fmtNumber(result.totals?.[k]||0)}`).join(' · ')}</span>
          {(result.this_call||[]).filter(x=>x.outcome!=='applied').slice(0,20).map(x=><small key={x.entity_id}>{x.outcome}: {x.reason}</small>)}
          {plan.can_apply&&!result.reversal&&<div className="l4b-apply"><label>Reason to reverse<input value={revReason} onChange={e=>setRevReason(e.target.value)} data-bulk-reverse-reason/></label>
            <Button compact disabled={busy||revReason.trim().length<5} onClick={reverse} data-bulk-reverse>Reverse this operation</Button></div>}
          {result.reversal&&<span data-bulk-reversed>Reversal: {Object.entries(result.reversal.reversal||{}).map(([k,v])=>`${k} ${fmtNumber(v)}`).join(' · ')}</span>}
        </div>}
      </>}
    </div>}
  </section>
}
