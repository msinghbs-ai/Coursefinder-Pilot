// Flagged values (v2.15.109): values admitted automatically under a stated assumption, for an operator to confirm or
// correct. First flag: tuition admitted as per year because the page shows the fee without a period (Platform Admin
// rule, 29 Sep 2026). Read: public.admin_data_flags_read(args); write: public.admin_data_flag_resolve(flag, action,
// args), pipeline operators and admins only (migration 20260930040000_cf247_tuition_assumed_annual_flags).
// Decision 219: public.admin_data_flag_resolve_bulk(ids, confirm | whole_course | remove) decides many at once.
import React,{useEffect,useState}from'react'
import{Check,Flag,Pencil,RefreshCw,Trash2,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'

const FLAG_TEXT={tuition_period_assumed_annual:'Tuition shown without a period — recorded as per year'}
const BASIS={annual:'Per year',total_indicative:'Whole course'}
// v2.15.137 (Decision 210): an approved fee schedule settles flags it answers; the rest show the schedule's fee.
const BY_SCHEDULE={confirmed_by_fee_schedule:'Same fee in the approved fee schedule',period_confirmed_by_fee_schedule:'Per year supported by the approved fee schedule'}
const quoteList=q=>Array.isArray(q)?q:(()=>{try{return JSON.parse(q||'[]')}catch{return[]}})()

export default function FlaggedValues({onError}){
  const[data,setData]=useState(null),[status,setStatus]=useState('open'),[busy,setBusy]=useState(false),[edit,setEdit]=useState(null),[uni,setUni]=useState(''),[q,setQ]=useState(''),[bulk,setBulk]=useState(''),[picked,setPicked]=useState(()=>new Set())
  const load=async(s=status)=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_data_flags_read',{p_args:{status:s,limit:200}});if(error)throw error;setData(d||{})}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  const act=async(id,action,args={},confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_data_flag_resolve',{p_flag_id:id,p_action:action,p_args:args});if(error)throw error;setEdit(null);if(status==='open')setData(d||{});else load()}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{load(status);setPicked(new Set())},[status])
  if(!data)return <section className="m-panel"><Loading label="Loading flagged values…"/></section>
  const all=data.items||[],can=Boolean(data.can_edit)&&!busy,c=data.counts||{}
  const unis=[...new Set(all.map(f=>f.provider).filter(Boolean))].sort()
  const items=all.filter(f=>(!uni||f.provider===uni)&&(!q||`${f.course||''} ${f.course_code||''}`.toLowerCase().includes(q.toLowerCase())))
  // Decision 219 (v2.15.146): tick rows (or every row shown) and decide them together in one call.
  const pickedShown=items.filter(f=>picked.has(f.id)),allShown=items.length>0&&items.every(f=>picked.has(f.id))
  const toggle=id=>setPicked(p=>{const n=new Set(p);n.has(id)?n.delete(id):n.add(id);return n})
  const toggleAll=()=>setPicked(p=>{const n=new Set(p);if(allShown)items.forEach(f=>n.delete(f.id));else items.forEach(f=>n.add(f.id));return n})
  const BULK={confirm:['confirmed as per year','Confirm {n} as per year?'],whole_course:['marked as whole course','Mark {n} as the fee for the whole course? The amounts stay; only the period changes.'],remove:['removed','Remove {n} from their courses?']}
  const decide=async action=>{const ids=pickedShown.map(f=>f.id);if(!ids.length)return;const n=`${ids.length} fee${ids.length===1?'':'s'}`
    if(!window.confirm(BULK[action][1].replace('{n}',n)))return
    setBusy(true);setBulk('');try{const{data:d,error}=await supabase.rpc('admin_data_flag_resolve_bulk',{p_flag_ids:ids,p_action:action,p_args:{}});if(error)throw error
      setBulk(`${fmtNumber(d?.done||0)} ${BULK[action][0]}${d?.skipped?`; ${fmtNumber(d.skipped)} already decided`:''}.`);setPicked(new Set());if(d?.read&&status==='open')setData(d.read);else load()}
    catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  return <section className="m-panel">
    <SectionTitle icon={Flag} title="Flagged values" subtitle="Values recorded automatically under an assumption. An approved fee schedule settles the ones it answers; confirm, correct or remove the rest." action={<div className="l3c-actions">
      <select className="fv-filter" value={status} onChange={e=>setStatus(e.target.value)} aria-label="Show">
        <option value="open">To check ({fmtNumber(c.open||0)})</option><option value="confirmed">Confirmed ({fmtNumber(c.confirmed||0)})</option>
        <option value="corrected">Corrected ({fmtNumber(c.corrected||0)})</option><option value="removed">Removed ({fmtNumber(c.removed||0)})</option><option value="all">All</option></select>
      <select className="fv-filter" value={uni} onChange={e=>setUni(e.target.value)} aria-label="University"><option value="">All universities</option>{unis.map(u=><option key={u} value={u}>{u}</option>)}</select>
      <span className="pq-search sl-search"><input type="search" value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a course" aria-label="Find a course"/></span>
      <Button compact onClick={()=>load()} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>}/>
    {bulk&&<p className="sb-done" role="status">{bulk}</p>}
    {data.can_edit&&status==='open'&&items.length>0&&<div className="fs-bar fv-bulk" data-flag-bulk>
      <label className="fv-pick-all"><input type="checkbox" checked={allShown} onChange={toggleAll} aria-label="Select every value shown"/> Select all {fmtNumber(items.length)} shown</label>
      <span className="sd-desc">{fmtNumber(pickedShown.length)} selected</span>
      <div className="sd-actions">
        <Button compact variant="primary" disabled={!can||!pickedShown.length} onClick={()=>decide('confirm')}><Check size={13}/>Confirm selected per year</Button>
        <Button compact disabled={!can||!pickedShown.length} onClick={()=>decide('whole_course')}>Mark selected as whole course</Button>
        <Button compact variant="danger" disabled={!can||!pickedShown.length} onClick={()=>decide('remove')}><Trash2 size={13}/>Remove selected</Button></div></div>}
    {!data.can_edit&&<p className="l3v-note">You can view these. Pipeline operators and admins can confirm or change them.</p>}
    <div className="cf-table-wrap"><table className="cf-table fv-table"><thead><tr>{data.can_edit&&status==='open'&&<th className="fv-pick"><span className="sd-desc">Pick</span></th>}<th>Course</th><th>What was assumed</th><th className="num">Fee</th><th>Period</th><th>From the page</th><th>Status</th>{data.can_edit&&status==='open'&&<th>Action</th>}</tr></thead><tbody>
      {items.length?items.map(f=><tr key={f.id} data-flag-row={f.id}>
        {data.can_edit&&status==='open'&&<td className="fv-pick"><input type="checkbox" checked={picked.has(f.id)} onChange={()=>toggle(f.id)} aria-label={`Select ${f.course||'course'}`}/></td>}
        <td><strong>{f.course||'Course'}</strong><span className="l3v-code">{[f.course_code,f.provider].filter(Boolean).join(' · ')}</span></td>
        <td>{FLAG_TEXT[f.flag]||f.flag}<span className="l3v-code">{fmtDateTime(f.created_at)}</span></td>
        <td className="num">{edit?.id===f.id?<input className="fv-input" type="number" min="1" step="1" value={edit.amount} onChange={e=>setEdit({...edit,amount:e.target.value})} aria-label="Fee amount"/>:<>{fmtMoney(Number(f.amount||0),f.currency||'AUD',{decimals:0})}{f.schedule&&<span className="l3v-code fv-schedule" data-schedule-fee>Fee schedule: {fmtMoney(Number(f.schedule.amount),f.currency||'AUD',{decimals:0})} a year{f.schedule.year?` (${f.schedule.year})`:''}</span>}</>}</td>
        <td>{edit?.id===f.id?<select className="fv-input" value={edit.basis} onChange={e=>setEdit({...edit,basis:e.target.value})} aria-label="Fee period"><option value="annual">Per year</option><option value="total_indicative">Whole course</option></select>:(BASIS[f.basis]||f.basis||'—')}</td>
        <td>{quoteList(f.quotes).slice(0,2).map((q,i)=><q key={i} className="fv-quote">{q}</q>)}{f.page_url&&<a className="l3v-code" href={f.page_url} target="_blank" rel="noreferrer">Open the page</a>}</td>
        <td><StatusChip value={f.status} tone={f.status==='open'?'warning':f.status==='removed'?'neutral':'success'} label={{open:'To check',confirmed:'Confirmed',corrected:'Corrected',removed:'Removed'}[f.status]||f.status}/>{BY_SCHEDULE[f.resolution?.action]&&<span className="l3v-code">{BY_SCHEDULE[f.resolution.action]}</span>}</td>
        {data.can_edit&&status==='open'&&<td><div className="l3c-row-actions">{edit?.id===f.id?<>
          <Button compact variant="primary" onClick={()=>act(f.id,'correct',{amount:Number(edit.amount),basis:edit.basis})} disabled={!can||!(Number(edit.amount)>0)}><Check size={14}/>Save</Button>
          <Button compact onClick={()=>setEdit(null)} disabled={busy}><X size={14}/>Cancel</Button></>:<>
          <Button compact variant="primary" onClick={()=>act(f.id,'confirm')} disabled={!can}><Check size={14}/>Confirm per year</Button>
          {f.schedule&&<Button compact onClick={()=>act(f.id,'correct',{amount:Number(f.schedule.amount),basis:'annual',note:'Fee from the approved fee schedule'+(f.schedule.year?` (${f.schedule.year})`:'')},`Use the fee schedule's ${f.schedule.amount} a year for this course?`)} disabled={!can}>Use schedule fee</Button>}
          <Button compact onClick={()=>setEdit({id:f.id,amount:String(f.amount||''),basis:f.basis||'annual'})} disabled={!can} aria-label="Edit fee" title="Edit fee"><Pencil size={14}/></Button>
          <Button compact variant="danger" onClick={()=>act(f.id,'remove',{},'Remove this fee from the course?')} disabled={!can} aria-label="Remove fee"><Trash2 size={14}/></Button></>}</div></td>}
      </tr>):<tr><td colSpan={8} className="cf-empty-cell">{status==='open'?'Nothing to check.':'None.'}</td></tr>}
    </tbody></table></div>
  </section>
}
