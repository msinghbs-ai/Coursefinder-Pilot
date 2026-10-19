// CF-247 v2.15.292 (19 Oct 2026): Coverage & completeness › Counsellor reports. Platform Admin, 19 Oct 2026 14:51: "Can I add some control
// for counsellor in zohoncreator or crm to flag or comment to pass on to studsearch platform admin for specific record. For example, missing
// field value, correct english requirement or fees or any fields reportable." Reports come from Zoho API v2 (report); each is closed as
// Fixed or Not changed with a reason, which Zoho reads back with report_status.
import React,{useEffect,useState}from'react'
import{MessageSquareWarning,CheckCircle2,CircleSlash,ExternalLink}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Metric,Pager,StatusChip,EmptyInline,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'

const errText=e=>String(e?.message||e||'').replace(/^.*?ERROR:\s*/,'')
const call=(action,args={})=>supabase.rpc('admin_counsellor_reports',{p_action:action,p_args:args}).then(({data,error})=>{if(error)throw error;return data})
export const ENTITY={course:'Course',provider:'Institute',campus:'Campus',contact:'Contact'}
export const ISSUE={missing:'Missing',wrong:'Wrong',out_of_date:'Out of date'}
const field=f=>String(f||'other').replace(/_/g,' ')
const tone=s=>s==='open'?'warning':s==='fixed'?'success':'neutral'
const statusLabel=s=>s==='open'?'Open':s==='fixed'?'Fixed':'Not changed'
const shown=v=>v==null?'—':typeof v==='string'?v:JSON.stringify(v)

export default function CounsellorReports({onError}){
 const[status,setStatus]=useState('open'),[entity,setEntity]=useState(''),[q,setQ]=useState(''),[offset,setOffset]=useState(0)
 const[data,setData]=useState(null),[busy,setBusy]=useState(false),[note,setNote]=useState(''),[picked,setPicked]=useState([])
 const load=()=>{setBusy(true);return call('list',{status,entity,q,limit:50,offset}).then(setData).catch(e=>onError?.(errText(e))).finally(()=>setBusy(false))}
 useEffect(()=>{load()},[status,entity,offset])
 useEffect(()=>{const t=setTimeout(()=>{setOffset(0);load()},300);return()=>clearTimeout(t)},[q])
 useEffect(()=>{setPicked([])},[status,entity,offset,q])
 const can=Boolean(data?.can_change),rows=data?.items||[],c=data?.counts||{}
 async function close(ids,outcome){
  const why=prompt(`${outcome==='fixed'?'Mark as fixed':'Mark as not changed'}: ${ids.length} report${ids.length>1?'s':''}. Reason (the counsellor sees it in Zoho):`)
  if(!why)return
  try{const r=await call('close',{ids,outcome,reason:why});setNote(`${r.closed} closed as ${outcome==='fixed'?'fixed':'not changed'}.`);setPicked([]);load()}catch(e){setNote('Not closed: '+errText(e))}}
 return <div className="m-page-stack" data-counsellor-reports>
  <div className="cf-metric-grid">
   <Metric label="Open" value={busy&&!data?'…':fmtNumber(c.open||0)} detail="Waiting for a check" icon={MessageSquareWarning} tone={c.open?'warning':'success'}/>
   <Metric label="Fixed" value={fmtNumber(c.fixed||0)} detail="Value corrected" icon={CheckCircle2} tone="success"/>
   <Metric label="Not changed" value={fmtNumber(c.not_changed||0)} detail="Checked, value kept" icon={CircleSlash}/>
   <Metric label="Last 7 days" value={fmtNumber(c.last_7_days||0)} detail="Reports received"/>
  </div>
  <section className="m-panel">
   <div className="m-workspace-head"><div><h2>Counsellor reports</h2><p>Counsellors report a missing or wrong value on a course, institute, campus or contact from Zoho Creator or Zoho CRM. Check it, correct the value where it is held, then close the report as Fixed or Not changed with a reason: Zoho shows the outcome to the counsellor. A corrected value reaches Zoho with the next sync.</p></div></div>
   <div className="m-search-row">
    <input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search record, provider, note or counsellor…"/>
    <label>Status<select value={status} onChange={e=>{setStatus(e.target.value);setOffset(0)}}><option value="open">Open</option><option value="fixed">Fixed</option><option value="not_changed">Not changed</option><option value="all">All</option></select></label>
    <label>On<select value={entity} onChange={e=>{setEntity(e.target.value);setOffset(0)}}><option value="">Everything</option>{Object.entries(ENTITY).map(([k,v])=><option key={k} value={k}>{v}s</option>)}</select></label>
    {can&&picked.length>0&&<><button className="m-secondary compact" onClick={()=>close(picked,'fixed')}>Fixed ({picked.length})</button><button className="m-secondary compact" onClick={()=>close(picked,'not_changed')}>Not changed ({picked.length})</button></>}
   </div>
   {note&&<p role="status">{note}</p>}
   <div className="dense-table-wrap"><table className="dense-table"><thead><tr>{can&&<th/>}<th><span>Record</span></th><th><span>Field</span></th><th><span>Report</span></th><th><span>Held when reported</span></th><th><span>From</span></th><th><span>Status</span></th></tr></thead><tbody>
    {rows.length?rows.map(r=><tr key={r.id} data-report-row={r.status}>
     {can&&<td>{r.status==='open'&&<input type="checkbox" aria-label="Select" checked={picked.includes(r.id)} onChange={e=>setPicked(p=>e.target.checked?[...p,r.id]:p.filter(x=>x!==r.id))}/>}</td>}
     <td className="primary-cell"><small>{ENTITY[r.entity]||r.entity}</small><br/><strong>{r.label||r.key}</strong>{r.provider_name&&<small> · {r.provider_name}</small>}<br/><small>{r.key}</small></td>
     <td><b>{field(r.field)}</b><br/><small>{ISSUE[r.issue]||'Wrong'}</small></td>
     <td>{r.note}{r.suggested_value&&<><br/><small>Suggested: <b>{r.suggested_value}</b></small></>}{r.source_url&&<><br/><a href={r.source_url} target="_blank" rel="noopener noreferrer"><ExternalLink size={12}/> Source</a></>}</td>
     <td><small className="cf-report-value">{shown(r.value_at_report)}</small></td>
     <td>{r.reporter?.name||r.reporter?.email||'Zoho'}{r.reporter?.email&&r.reporter?.name&&<><br/><small>{r.reporter.email}</small></>}<br/><small>{fmtDateTime(r.reported_at)}</small></td>
     <td><StatusChip tone={tone(r.status)} label={statusLabel(r.status)}/>{r.status!=='open'&&<small><br/>{r.reason}<br/>{r.closed_by} · {fmtDateTime(r.closed_at)}</small>}
      {can&&r.status==='open'&&<div><button className="m-secondary compact" onClick={()=>close([r.id],'fixed')}>Fixed</button><button className="m-secondary compact" onClick={()=>close([r.id],'not_changed')}>Not changed</button></div>}</td>
    </tr>):<tr><td colSpan={can?7:6}><EmptyInline text={busy?'Loading…':'No reports match.'}/></td></tr>}
   </tbody></table></div>
   <Pager offset={offset} limit={50} total={Number(data?.total||0)} onOffset={setOffset}/>
  </section>
 </div>
}
