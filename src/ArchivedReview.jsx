// Providers › Archived (v2.15.238, CF-247 R5; Platform Admin bug list of 10 Oct 2026, Feature 6).
// Archived means unpublished and hidden from the lists, search and every consumer API (Wix, Zoho, the website), with its background
// work stopped. This screen lists:
//  - archived providers: why (left the register, archived by hand, closed or merged at the departure review), when and by whom; Restore;
//  - courses that are not active and why (left the register, archived by hand, outside the import scope, suspended); Restore;
//  - how many provider departures wait in Layer 4 Review › Review queue (Bulk decisions › Provider departures) to record a closure or a merger.
// Read: public.admin_archive_read. Restore: public.admin_provider_restore, public.admin_course_edit('restore');
// several at once: public.admin_archive_restore_bulk (v2.15.240).
import React,{useEffect,useState}from'react'
import{RotateCcw,Search}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button,Loading,Pager,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'
import{ARCHIVE_SOURCE}from'./RecordEditor'

const LIMIT=50
const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')

export default function ArchivedReview({onError,navigate}){
  const[section,setSection]=useState('providers'),[query,setQuery]=useState(''),[q,setQ]=useState(''),[offset,setOffset]=useState(0)
  const[data,setData]=useState(null),[busy,setBusy]=useState(false),[working,setWorking]=useState(''),[note,setNote]=useState(''),[picked,setPicked]=useState(new Set())
  useEffect(()=>{const t=setTimeout(()=>setQ(query.trim()),280);return()=>clearTimeout(t)},[query])
  useEffect(()=>{setOffset(0);setPicked(new Set())},[section,q])
  const load=async()=>{setBusy(true);try{const{data:d,error}=await supabase.rpc('admin_archive_read',{p_section:section,p_query:q||null,p_limit:LIMIT,p_offset:offset});if(error)throw error;setData(d)}catch(e){onError?.(errText(e))}finally{setBusy(false)}}
  useEffect(()=>{load()},[section,q,offset])
  const restore=async(row)=>{setWorking(row.id);setNote('');try{
      const{error}=section==='providers'?await supabase.rpc('admin_provider_restore',{p_provider_id:row.id}):await supabase.rpc('admin_course_edit',{p_course_id:row.id,p_action:'restore',p_args:{}})
      if(error)throw error;setNote(`${row.name||row.title} restored. It returns to search after the next rebuild (a few minutes).`);await load()}catch(e){onError?.(errText(e))}finally{setWorking('')}}
  // v2.15.240 (Platform Admin feature request, 11 Oct 2026): tick several and restore them together
  const restorable=r=>section==='providers'||r.provider_status==='active'
  const toggle=id=>setPicked(s=>{const n=new Set(s);n.has(id)?n.delete(id):n.add(id);return n})
  const bulk=async()=>{const ids=[...picked];if(!ids.length)return;setWorking('bulk');setNote('');try{const{data:res,error}=await supabase.rpc('admin_archive_restore_bulk',{p_section:section,p_ids:ids});if(error)throw error;setNote(`${fmtNumber(res?.restored||0)} restored${res?.skipped?`, ${fmtNumber(res.skipped)} left as they were`:''}. They return to search after the next rebuild (a few minutes).`);setPicked(new Set());await load()}catch(e){onError?.(errText(e))}finally{setWorking('')}}
  const c=data?.counts||{},rows=data?.rows||[],can=Boolean(data?.can_restore)
  const pageIds=rows.filter(restorable).map(r=>r.id),allPicked=pageIds.length>0&&pageIds.every(id=>picked.has(id))
  return <div className="m-page-stack"><section className="m-panel ar-review" data-archived-review>
    <div className="m-workspace-head"><div><h2>Archived</h2><p>Archived providers and courses are unpublished and hidden from the lists, search, Wix, Zoho and the website, and their background work is stopped. Restore brings one back as it was.</p></div></div>
    <div className="ar-tabs" role="tablist" aria-label="Archived records">
      <button role="tab" aria-selected={section==='providers'} className={section==='providers'?'active':''} onClick={()=>setSection('providers')}>Providers ({fmtNumber(c.providers||0)})</button>
      <button role="tab" aria-selected={section==='courses'} className={section==='courses'?'active':''} onClick={()=>setSection('courses')}>Courses not active ({fmtNumber(c.courses||0)})</button>
    </div>
    {Number(c.departures_waiting)>0&&<p className="ar-why" data-departures-waiting>{fmtNumber(c.departures_waiting)} provider departure{Number(c.departures_waiting)===1?'':'s'} wait{Number(c.departures_waiting)===1?'s':''} in Layer 4 Review › Review queue (Bulk decisions › Provider departures) to record a closure or a merger (the providers are already archived). <Button compact onClick={()=>navigate?.('layer4',{tab:'review'})}>Open</Button></p>}
    <label className="m-searchbox"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder={section==='providers'?'Search provider name':'Search course, code or provider'} aria-label="Search archived records"/></label>
    {can&&<div className="ar-bulk" data-bulk-restore><span>{picked.size?`${fmtNumber(picked.size)} selected`:'Tick records to restore several at once'}</span>{picked.size>0&&<><Button compact variant="primary" onClick={bulk} disabled={working==='bulk'}><RotateCcw size={13}/>{working==='bulk'?'Restoring…':`Restore ${fmtNumber(picked.size)}`}</Button><Button compact onClick={()=>setPicked(new Set())}>Clear</Button></>}</div>}
    {note&&<p role="status" className="ar-why">{note}</p>}
    {busy&&!data?<Loading label="Loading archived records…"/>:<div className="cf-table-wrap"><table className="cf-table">
      <thead>{section==='providers'
        ?<tr>{can&&<th className="ar-check"><input type="checkbox" aria-label="Select all on this page" checked={allPicked} onChange={()=>setPicked(s=>{const n=new Set(s);pageIds.forEach(id=>allPicked?n.delete(id):n.add(id));return n})}/></th>}<th>Provider</th><th>Country</th><th>Why</th><th>When</th><th>Courses</th><th></th></tr>
        :<tr>{can&&<th className="ar-check"><input type="checkbox" aria-label="Select all on this page" checked={allPicked} onChange={()=>setPicked(s=>{const n=new Set(s);pageIds.forEach(id=>allPicked?n.delete(id):n.add(id));return n})}/></th>}<th>Course</th><th>Provider</th><th>Why</th><th>When</th><th></th></tr>}</thead>
      <tbody>{rows.length===0?<tr><td colSpan={7}>{busy?'Loading…':'Nothing archived matches.'}</td></tr>:rows.map(r=>section==='providers'
        ?<tr key={r.id} data-archived-provider={r.id}>{can&&<td className="ar-check"><input type="checkbox" aria-label={`Select ${r.name}`} checked={picked.has(r.id)} onChange={()=>toggle(r.id)}/></td>}<td><strong>{r.name}</strong></td><td>{r.country||'—'}</td>
          <td><StatusChip value="archived" tone="warning" label={ARCHIVE_SOURCE[r.source]||(r.status==='archived'?'Archived':'Not active')}/> <span className="ar-why">{r.reason||''}{r.departure==='needs_review'?' · departure waits for a decision':''}</span></td>
          <td className="ar-why">{r.at?fmtDateTime(r.at):'—'}{r.by?` · ${r.by}`:''}</td><td>{fmtNumber(r.courses||0)}</td>
          <td>{can&&<Button compact onClick={()=>restore(r)} disabled={working===r.id}><RotateCcw size={13}/>{working===r.id?'Restoring…':'Restore'}</Button>}</td></tr>
        :<tr key={r.id} data-archived-course={r.id}>{can&&<td className="ar-check">{restorable(r)?<input type="checkbox" aria-label={`Select ${r.title}`} checked={picked.has(r.id)} onChange={()=>toggle(r.id)}/>:null}</td>}<td><strong>{r.title}</strong>{r.code?<span className="l3v-code"> {r.code}</span>:null}</td>
          <td>{r.provider}{r.provider_status!=='active'?<span className="ar-why"> (provider archived)</span>:null}</td><td className="ar-why">{r.why}</td><td className="ar-why">{r.at?fmtDateTime(r.at):'—'}</td>
          <td>{can&&r.provider_status==='active'&&<Button compact onClick={()=>restore(r)} disabled={working===r.id}><RotateCcw size={13}/>{working===r.id?'Restoring…':'Restore'}</Button>}</td></tr>)}</tbody>
    </table></div>}
    {Number(data?.total)>LIMIT&&<Pager offset={offset} limit={LIMIT} total={Number(data.total)} onOffset={setOffset}/>}
  </section></div>
}
