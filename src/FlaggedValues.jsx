// Flagged values (v2.15.109): values admitted automatically under a stated assumption, for an operator to confirm or
// correct. First flag: tuition admitted as per year because the page shows the fee without a period (Platform Admin
// rule, 29 Sep 2026). Read: public.admin_data_flags_read(args); write: public.admin_data_flag_resolve(flag, action,
// args), pipeline operators and admins only (migration 20260930040000_cf247_tuition_assumed_annual_flags).
import React,{useEffect,useState}from'react'
import{Check,Flag,Pencil,RefreshCw,Trash2,X}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,SectionTitle,StatusChip,fmtDateTime,fmtMoney,fmtNumber}from'./ui-kit'

const FLAG_TEXT={tuition_period_assumed_annual:'Tuition shown without a period — recorded as per year'}
const BASIS={annual:'Per year',total_indicative:'Whole course'}
const quoteList=q=>Array.isArray(q)?q:(()=>{try{return JSON.parse(q||'[]')}catch{return[]}})()

export default function FlaggedValues({onError}){
  const[data,setData]=useState(null),[status,setStatus]=useState('open'),[busy,setBusy]=useState(false),[edit,setEdit]=useState(null)
  const load=async(s=status)=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_data_flags_read',{p_args:{status:s,limit:200}});if(error)throw error;setData(d||{})}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  const act=async(id,action,args={},confirmText)=>{if(confirmText&&!window.confirm(confirmText))return;setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_data_flag_resolve',{p_flag_id:id,p_action:action,p_args:args});if(error)throw error;setEdit(null);if(status==='open')setData(d||{});else load()}catch(e){onError?.(e.message||String(e))}finally{setBusy(false)}}
  useEffect(()=>{load(status)},[status])
  if(!data)return <section className="m-panel"><Loading label="Loading flagged values…"/></section>
  const items=data.items||[],can=Boolean(data.can_edit)&&!busy,c=data.counts||{}
  return <section className="m-panel">
    <SectionTitle icon={Flag} title="Flagged values" subtitle="Values recorded automatically under an assumption. Confirm them, correct them, or remove them." action={<div className="l3c-actions">
      <select className="fv-filter" value={status} onChange={e=>setStatus(e.target.value)} aria-label="Show">
        <option value="open">To check ({fmtNumber(c.open||0)})</option><option value="confirmed">Confirmed ({fmtNumber(c.confirmed||0)})</option>
        <option value="corrected">Corrected ({fmtNumber(c.corrected||0)})</option><option value="removed">Removed ({fmtNumber(c.removed||0)})</option><option value="all">All</option></select>
      <Button compact onClick={()=>load()} disabled={busy}><RefreshCw size={14}/>Refresh</Button></div>}/>
    {!data.can_edit&&<p className="l3v-note">You can view these. Pipeline operators and admins can confirm or change them.</p>}
    <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Course</th><th>What was assumed</th><th className="num">Fee</th><th>Period</th><th>From the page</th><th>Status</th>{data.can_edit&&status==='open'&&<th>Action</th>}</tr></thead><tbody>
      {items.length?items.map(f=><tr key={f.id}>
        <td><strong>{f.course||'Course'}</strong><span className="l3v-code">{[f.course_code,f.provider].filter(Boolean).join(' · ')}</span></td>
        <td>{FLAG_TEXT[f.flag]||f.flag}<span className="l3v-code">{fmtDateTime(f.created_at)}</span></td>
        <td className="num">{edit?.id===f.id?<input className="fv-input" type="number" min="1" step="1" value={edit.amount} onChange={e=>setEdit({...edit,amount:e.target.value})} aria-label="Fee amount"/>:fmtMoney(Number(f.amount||0),f.currency||'AUD',{decimals:0})}</td>
        <td>{edit?.id===f.id?<select className="fv-input" value={edit.basis} onChange={e=>setEdit({...edit,basis:e.target.value})} aria-label="Fee period"><option value="annual">Per year</option><option value="total_indicative">Whole course</option></select>:(BASIS[f.basis]||f.basis||'—')}</td>
        <td>{quoteList(f.quotes).slice(0,2).map((q,i)=><q key={i} className="fv-quote">{q}</q>)}{f.page_url&&<a className="l3v-code" href={f.page_url} target="_blank" rel="noreferrer">Open the page</a>}</td>
        <td><StatusChip value={f.status} tone={f.status==='open'?'warning':f.status==='removed'?'neutral':'success'} label={{open:'To check',confirmed:'Confirmed',corrected:'Corrected',removed:'Removed'}[f.status]||f.status}/></td>
        {data.can_edit&&status==='open'&&<td><div className="l3c-row-actions">{edit?.id===f.id?<>
          <Button compact variant="primary" onClick={()=>act(f.id,'correct',{amount:Number(edit.amount),basis:edit.basis})} disabled={!can||!(Number(edit.amount)>0)}><Check size={14}/>Save</Button>
          <Button compact onClick={()=>setEdit(null)} disabled={busy}><X size={14}/>Cancel</Button></>:<>
          <Button compact variant="primary" onClick={()=>act(f.id,'confirm')} disabled={!can}><Check size={14}/>Confirm per year</Button>
          <Button compact onClick={()=>setEdit({id:f.id,amount:String(f.amount||''),basis:f.basis||'annual'})} disabled={!can}><Pencil size={14}/>Edit</Button>
          <Button compact variant="danger" onClick={()=>act(f.id,'remove',{},'Remove this fee from the course?')} disabled={!can} aria-label="Remove fee"><Trash2 size={14}/></Button></>}</div></td>}
      </tr>):<tr><td colSpan={7} className="cf-empty-cell">{status==='open'?'Nothing to check.':'None.'}</td></tr>}
    </tbody></table></div>
  </section>
}
