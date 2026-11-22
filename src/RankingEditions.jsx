// CF-247 s971 (Platform Admin 22 Nov 2026 14:22): Rankings & statistics › Datasets › Ranking editions. Every edition of THE, QS and ARWU
// with its status, access, attribution and links. A Platform Admin publishes an edition (any other revision of the same year is superseded)
// or unpublishes it to roll back (the website then shows the latest edition still published), always with a reason
// (public.admin_ranking_editions_v1, logged in ranking.edition_status_changes). Pipeline Operators and PIM Admins read the list.
import React,{useCallback,useEffect,useState}from'react'
import{RefreshCw,Upload,Undo2}from'lucide-react'
import{supabase}from'./lib/supabase'
import{StatusChip,EmptyInline,fmtDateTime}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'
import{plainError}from'./lib/errors'

const STATUS={accepted:['Published','success'],superseded:['Not published','neutral'],parsed:['Loading','warning'],rejected:['Rejected','danger']}
const BODY={the_wur:'THE',qs_wur:'QS',arwu:'ARWU'}

export default function RankingEditions(){
 const[data,setData]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(''),[open,setOpen]=useState(null),[reason,setReason]=useState(''),[body,setBody]=useState('all')
 const load=useCallback(async()=>{setErr('');const{data:d,error}=await supabase.rpc('admin_ranking_editions_v1',{p_action:'list'});if(error){setErr(plainError(error));return}setData(d)},[])
 useEffect(()=>{load()},[load])
 const act=async(e,action)=>{setBusy(e.edition_id);setErr('');const{error}=await supabase.rpc('admin_ranking_editions_v1',{p_action:action,p_edition_id:e.edition_id,p_reason:reason});setBusy('');if(error){setErr(plainError(error));return}setOpen(null);setReason('');load()}
 const rows=(data?.editions||[]).filter(e=>body==='all'||e.system_code===body)
 return <section className="m-panel" data-ranking-editions>
  <div className="m-ranking-history-head"><div><h3>Ranking editions</h3><p>Every edition of each ranking body. The website shows, for each body, the latest edition marked Published. THE and ARWU are read by the Layer 1 readers; QS comes from the annual file upload below. {data?.can_publish?'You can publish an edition or unpublish it to roll back, with a reason.':'A Platform Admin publishes and unpublishes editions.'}</p></div>
   <div className="m-ranking-import-row-actions"><label className="m-compact-filter">Ranking<select value={body} onChange={e=>setBody(e.target.value)}><option value="all">All</option>{Object.entries(BODY).map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label><button type="button" className="m-secondary compact" onClick={load}><RefreshCw size={14}/>Refresh</button></div></div>
  {err&&<p className="m-error" role="alert">{err}</p>}
  {!data?<EmptyInline text="Loading editions…"/>:!rows.length?<EmptyInline text="No editions for this ranking."/>:
  <div className="m-table-wrap"><table className="m-table" data-ranking-editions-table><thead><tr><th>Ranking</th><th>Year</th><th>Status</th><th>Source</th><th>Rows</th><th>Linked to providers</th><th>Attribution</th><th>Last change</th>{data.can_publish&&<th/>}</tr></thead>
   <tbody>{rows.map(e=>{const[st,tone]=STATUS[e.status]||[e.status,'neutral'];return <React.Fragment key={e.edition_id}><tr data-edition={e.edition_id}>
    <td>{BODY[e.system_code]||e.system_code}</td><td>{e.edition_year}</td><td><StatusChip value={e.status} tone={tone} label={st}/></td>
    <td>{/_public_json_/.test(e.source_revision||'')?'Layer 1 reader':'File upload'}{e.source_url?<> · <a href={e.source_url} target="_blank" rel="noreferrer">page</a></>:null}</td>
    <td>{fmtNumber(e.rows)}</td><td>{fmtNumber(e.linked)}</td><td className="m-wrap"><small>{e.attribution||'—'}</small></td>
    <td>{e.last_change?<small>{e.last_change.action==='publish'?'Published':'Unpublished'} {fmtDateTime(e.last_change.changed_at)}: {e.last_change.reason}</small>:<small>{fmtDateTime(e.updated_at)}</small>}</td>
    {data.can_publish&&<td>{e.status==='accepted'?<button type="button" className="m-secondary compact" onClick={()=>{setOpen({id:e.edition_id,action:'unpublish'});setReason('')}}><Undo2 size={14}/>Unpublish</button>:e.status!=='rejected'&&e.status!=='parsed'?<button type="button" className="m-secondary compact" onClick={()=>{setOpen({id:e.edition_id,action:'publish'});setReason('')}}><Upload size={14}/>Publish</button>:null}</td>}
   </tr>{open?.id===e.edition_id&&<tr data-edition-confirm><td colSpan={9}><div className="m-inline-confirm"><label className="wide">Reason ({open.action==='publish'?'publish this edition':'roll back: unpublish this edition'})<input value={reason} onChange={x=>setReason(x.target.value)} placeholder="Why, in a few words"/></label>
    <button type="button" className="m-primary compact" disabled={busy===e.edition_id||reason.trim().length<5} onClick={()=>act(e,open.action)}>{open.action==='publish'?'Publish edition':'Unpublish edition'}</button><button type="button" className="m-secondary compact" onClick={()=>setOpen(null)}>Cancel</button></div></td></tr>}</React.Fragment>})}</tbody></table></div>}
 </section>
}
