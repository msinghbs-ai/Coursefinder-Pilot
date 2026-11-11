// CF-247 F-INT (Platform Admin 11 Nov 2026 20:40, option B): the Rule B qualification register on Process results. The platform tries every university
// with an intake calendar (job intake-rule-b-qualify, a rolled-back trial of the intake planner) and shows what the nearest start would add and why a
// university is held. The Platform Admin approves every qualified university in one click with a reason; a passing trial never switches anything on.
import React,{useEffect,useRef,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,StatusChip,fmtDateTime,fmtNumber}from'./ui-kit'

const STATUS={qualified:'Qualified',held:'Held',listed:'On',paused:'Paused',error:'Error',pending:'Not tried yet'}
const TONE={qualified:'green',listed:'green',paused:'danger',error:'danger',held:'neutral',pending:'neutral'}
const n=v=>v==null?'—':fmtNumber(v)
const rpc=async(name,args)=>{const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data}

export default function RuleBRegister(){
  const[d,setD]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState(''),[reason,setReason]=useState(''),[msg,setMsg]=useState(''),[out,setOut]=useState([])
  const lock=useRef(false)
  const run=async(name,fn)=>{if(lock.current)return;lock.current=true;setBusy(name);setErr('');try{await fn()}catch(e){setErr(e?.message||'Request failed.')}finally{lock.current=false;setBusy('')}}
  const load=()=>run('Loading',async()=>setD(await rpc('admin_intake_rule_b_read_v1',{})))
  useEffect(()=>{load()},[])
  if(!d)return<section className="intake-course" aria-label="Nearest start qualification">{err?<p role="alert">{err}</p>:<p role="status">Loading the nearest-start qualification…</p>}</section>
  const rows=d.rows||[],c=d.counts||{}
  // leave a qualified university out of this approval (it stays qualified and can be approved later)
  const take=rows.filter(r=>r.status==='qualified'&&r.fresh&&!out.includes(r.provider_id)),takeRows=take.reduce((a,r)=>a+(r.rule_b_rows||0),0)
  return<section className="intake-course rb-register" aria-label="Nearest start qualification" data-testid="rule-b-register">
    <h3>Nearest start (Rule B): which universities qualify</h3>
    <p>Every university with an intake calendar is tried every {n(d.requalify_hours)} hours: the planner runs with the nearest start on and is rolled back, then the dates are checked (the page states the month as an intake, no vocational, pathway or research course, calendar evidence, one date per month). Qualified universities are switched on only by the approval below.</p>
    <p className="rb-counts">{['qualified','listed','paused','held','error','pending'].map(s=><span key={s}><StatusChip tone={TONE[s]} label={`${STATUS[s]} ${n(c[s]||0)}`}/> </span>)}</p>
    {err&&<p role="alert">{err}</p>}{msg&&<p role="status">{msg}</p>}
    <div className="intake-actions">
      <Button compact disabled={!!busy} onClick={load}>Refresh qualification</Button>
      {d.can_request&&<Button compact disabled={!!busy} onClick={()=>run('Queueing',async()=>{const r=await rpc('admin_intake_rule_b_request_v1',{p_provider:null});setMsg(`${n(r.queued)} universities queued; the job tries them every 10 minutes.`);setD(await rpc('admin_intake_rule_b_read_v1',{}))})}>Check all now</Button>}
    </div>
    {d.can_approve&&<div className="rb-approve">
      <label><span>Reason for approving all qualified universities</span><input className="fv-input" value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why these universities may take the nearest start"/></label>
      <Button disabled={!!busy||!take.length||reason.trim().length<8} onClick={()=>{if(!window.confirm(`Switch on the nearest start for ${take.length} qualified universities (about ${takeRows} dates)?`))return;run('Approving',async()=>{const r=await rpc('admin_intake_rule_b_approve_v1',{p_reason:reason.trim(),p_exclude:out});setMsg(`${n(r.approved)} universities switched on. The hourly intake run gives their dates.`);setReason('');setOut([]);setD(await rpc('admin_intake_rule_b_read_v1',{}))})}}>Approve all qualified ({n(take.length)} universities, about {n(takeRows)} dates)</Button>
    </div>}
    <div className="intake-table-scroll"><table className="cf-table">
      <thead><tr><th>University</th><th>Status</th><th>Nearest start would add</th><th>Other routes fill</th><th>Why</th><th>Checked</th>{d.can_request&&<th></th>}</tr></thead>
      <tbody>{rows.map(r=><tr key={r.provider_id} data-rule-b-provider={r.provider_id}>
        <td>{r.name}{r.country?` (${r.country})`:''}</td>
        <td><StatusChip tone={TONE[r.status]} label={STATUS[r.status]||r.status}/>{d.can_approve&&r.status==='qualified'&&<label className="rb-out"><input type="checkbox" checked={out.includes(r.provider_id)} onChange={e=>setOut(o=>e.target.checked?[...o,r.provider_id]:o.filter(x=>x!==r.provider_id))}/> Leave out</label>}</td>
        <td>{n(r.rule_b_rows)}{r.dates&&Object.keys(r.dates).length?<details><summary>Dates</summary><ul>{Object.entries(r.dates).map(([m,v])=><li key={m}>{m}: {Object.entries(v).map(([dt,k])=>`${dt} (${k})`).join(', ')}</li>)}</ul>{(r.sample||[]).map((x,i)=><blockquote key={i} className="intake-evidence">{x.course} · {x.intake} → {x.date}<br/>Page: {x.page}<br/>Calendar: {x.calendar}</blockquote>)}</details>:null}</td>
        <td>{n(r.other_rows)}</td>
        <td>{(r.reasons||[]).join('; ')||(r.last_error?`Error: ${r.last_error}`:'')}</td>
        <td>{r.checked_at?fmtDateTime(r.checked_at):'—'}{r.requested_at?' · queued':''}</td>
        {d.can_request&&<td><Button compact disabled={!!busy} aria-label={`Check ${r.name} now`} onClick={()=>run('Queueing',async()=>{await rpc('admin_intake_rule_b_request_v1',{p_provider:r.provider_id});setD(await rpc('admin_intake_rule_b_read_v1',{}))})}>Check now</Button></td>}
      </tr>)}</tbody>
    </table></div>
  </section>
}
