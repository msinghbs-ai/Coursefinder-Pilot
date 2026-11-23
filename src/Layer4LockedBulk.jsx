// CF-247 s1023 (Platform Admin 24 Nov 2026, HELD:LOCKS confirmation): Layer 4 › Grid › Periodic Audit - Locked Field Update. A person (Curator, rank 3
// or higher) ticks locked fee or intake items whose re-read differs from the live value and chooses Yes (Approve & Keep Lock) or No (Reject), with one
// audit reason for every item. The server writes the verified value and keeps the lock (public.admin_layer4_locked_update_bulk, at most
// layer4.locked_update_bulk_max items); nothing here writes a value. The university list and the items are read live; no list is written into the code.
import React,{useCallback,useEffect,useMemo,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,EmptyInline,fmtNumber}from'./ui-kit'

const inbox=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
const FIELDS=[['','All fields'],['tuition','Tuition fee'],['intakes','Intake']]
const MIN_REASON=8

export default function Layer4LockedBulk({rank,onDecided}){
  const[unis,setUnis]=useState([]),[provider,setProvider]=useState(''),[field,setField]=useState(''),[q,setQ]=useState('')
  const[rows,setRows]=useState(null),[total,setTotal]=useState(0),[err,setErr]=useState(''),[note,setNote]=useState('')
  const[pick,setPick]=useState([]),[reason,setReason]=useState(''),[busy,setBusy]=useState(false)
  const load=useCallback(()=>{setRows(null);setErr('');setPick([])
    inbox('items',{kind:'locked_field_update',provider_id:provider||undefined,limit:200}).then(d=>{setRows(d.items||[]);setTotal(Number(d.total??(d.items||[]).length))}).catch(e=>{setErr(e.message);setRows([])})},[provider])
  useEffect(()=>{inbox('universities',{kind:'locked_field_update'}).then(d=>setUnis((d.items||[]).filter(u=>Number(u.by_kind?.locked_field_update||0)>0))).catch(()=>setUnis([]))},[])
  useEffect(load,[load])
  const shown=useMemo(()=>(rows||[]).filter(r=>(!field||r.field===field)&&(!q||`${r.subject} ${r.provider}`.toLowerCase().includes(q.toLowerCase()))),[rows,field,q])
  const max=100 // the server's layer4.locked_update_bulk_max decides; a larger pick is refused with its own words
  const allowed=Number(rank)>=3,okReason=reason.trim().length>=MIN_REASON
  const toggle=ref=>setPick(p=>p.includes(ref)?p.filter(x=>x!==ref):[...p,ref])
  const all=shown.length>0&&shown.every(r=>pick.includes(r.ref))
  const run=async choice=>{setBusy(true);setErr('');setNote('')
    try{const{data,error}=await supabase.rpc('admin_layer4_locked_update_bulk',{p_refs:pick,p_choice:choice,p_reason:reason.trim()});if(error)throw new Error(error.message)
      if(!data?.ok)throw new Error(data?.request||'Not decided.')
      const bad=(data.items||[]).filter(i=>!i.ok);setNote(`${fmtNumber(data.decided)} of ${fmtNumber(data.asked)} decided${choice==='approve_keep_lock'?'; the lock is kept on each':''}.${bad.length?` ${fmtNumber(bad.length)} not decided: ${bad[0].request||'refresh and try again'}`:''}`)
      setReason('');onDecided?.();load()}
    catch(e){setErr(e.message)}finally{setBusy(false)}}
  return <section className="l4g-locked" data-l4-locked-bulk aria-label="Periodic Audit - Locked Field Update">
    <p className="l4g-help">These values are locked by a person. A later read of the source differs from the live value. Yes (Approve &amp; Keep Lock) writes the value read from the source and keeps the lock; No (Reject) keeps the live value. The reason is kept in the audit log for every item.</p>
    <div className="l4g-bar">
      <label>University<select value={provider} onChange={e=>setProvider(e.target.value)} data-l4-locked-university><option value="">All universities</option>{unis.map(u=><option key={u.provider_id} value={u.provider_id}>{u.name} ({fmtNumber(u.by_kind.locked_field_update)})</option>)}</select></label>
      <label>Field<select value={field} onChange={e=>setField(e.target.value)} data-l4-locked-field>{FIELDS.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
      <label>Search<input value={q} onChange={e=>setQ(e.target.value)} placeholder="Course or university" data-l4-locked-search/></label>
    </div>
    {err&&<p className="l4g-err" role="alert">{err}</p>}
    {note&&<p className="l4g-note" role="status" data-l4-locked-note>{note}</p>}
    {rows===null?<EmptyInline text="Reading the locked values…"/>:!shown.length?<EmptyInline text="No locked value is waiting for a decision."/>:<>
      <p className="l4g-count">{fmtNumber(shown.length)} shown{total>rows.length?` of ${fmtNumber(total)} waiting (narrow by university to see the rest)`:''} · {fmtNumber(pick.length)} ticked (at most {max} at once)</p>
      <div className="cf-table-wrap"><table className="cf-table" data-l4-locked-table><thead><tr><th><input type="checkbox" aria-label="Tick every shown item" checked={all} onChange={e=>setPick(e.target.checked?shown.slice(0,max).map(r=>r.ref):[])}/></th><th>University</th><th>Course and value read from the source</th><th>Seen</th></tr></thead><tbody>
        {shown.map(r=><tr key={r.ref} data-l4-locked-row={r.ref}><td><input type="checkbox" aria-label={`Tick ${r.subject}`} checked={pick.includes(r.ref)} disabled={!pick.includes(r.ref)&&pick.length>=max} onChange={()=>toggle(r.ref)}/></td><td>{r.provider}</td><td>{r.subject}</td><td>{fmtNumber(r.seen_count||1)}×</td></tr>)}
      </tbody></table></div></>}
    <div className="l4g-bar" data-l4-locked-bar>
      <label>Reason<input value={reason} onChange={e=>setReason(e.target.value)} maxLength={300} placeholder={`Kept with every decision (${MIN_REASON} characters or more)`} data-l4-locked-reason/></label>
      <div className="l4g-actions">
        <Button compact disabled={!allowed||busy||!pick.length||!okReason} onClick={()=>run('approve_keep_lock')} data-l4-choice="approve_keep_lock">Yes (Approve &amp; Keep Lock)</Button>
        <Button compact disabled={!allowed||busy||!pick.length||!okReason} onClick={()=>run('reject')} data-l4-choice="reject">No (Reject)</Button>
      </div>
      {!allowed&&<small className="l4g-muted">Curator rank or higher is needed to decide a locked value.</small>}
    </div>
  </section>
}
