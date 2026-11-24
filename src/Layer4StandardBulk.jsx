// CF-247 s1044 (Platform Admin brief 24 Nov 2026 15:11, UI-UX plan v1.2 Slice A): Layer 4 › Grid, the rows of the chosen queue on this page can be decided
// together: tick rows (up to 100), write one reason (8 or more characters, kept with every decision) and press Approve Selected or Reject Selected.
// Each card is decided on its own through the Inbox's own decision (admin_layer4_inbox 'decide') at the person's rank, so every gate, input and audit
// trail is the card's own. Only the decisions one batch may settle are offered (settleChoices: no per-record value, no link away, never entry requirements,
// descriptions or departures); a queue with none shows nothing. Nothing is written into the code: the choices come from the server's kind.
import React,{useMemo,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,fmtNumber}from'./ui-kit'
import{decisionsFor,settleChoices}from'./lib/l4-rules.js'

const MAX=100,MIN_REASON=8
const decide=async args=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:'decide',p_args:args});if(error)throw new Error(error.message);if(data&&data.ok===false)throw new Error(data.request||'more is needed');return data}

export default function Layer4StandardBulk({kind,kinds,rows,rank,onDecided}){
  const[pick,setPick]=useState([]),[reason,setReason]=useState(''),[busy,setBusy]=useState(false),[note,setNote]=useState(''),[err,setErr]=useState('')
  const choices=useMemo(()=>settleChoices(kind,kinds?.[kind]?.choices),[kind,kinds])
  const d=useMemo(()=>decisionsFor(kind,choices),[kind,choices])
  const ok=c=>c&&Number(rank)>=Number(c.rank||0)
  const list=(rows||[]).filter(r=>r.kind===kind)
  if(!kind||!choices.length||(!d.yes&&!d.no)||!list.length)return null
  const toggle=ref=>setPick(p=>p.includes(ref)?p.filter(x=>x!==ref):[...p,ref])
  const all=list.every(r=>pick.includes(r.ref))
  const run=async c=>{setBusy(true);setErr('');setNote('');let done=0;const bad=[]
    for(const ref of pick){try{await decide({kind,ref,choice:c.key,reason:reason.trim(),value:''});done++}catch(e){bad.push(e.message)}}
    setBusy(false);setNote(`${fmtNumber(done)} of ${fmtNumber(pick.length)} decided${bad.length?`; ${fmtNumber(bad.length)} not decided (${bad[0]})`:''}.`);setPick([]);if(done){setReason('');onDecided?.()}}
  const can=!busy&&pick.length>0&&reason.trim().length>=MIN_REASON
  return <details className="l4g-bulk" data-l4-bulk>
    <summary><strong>Decide several at once</strong> <small>tick rows on this page, one reason for all</small></summary>
    {err&&<p className="l4g-err" role="alert">{err}</p>}
    {note&&<p className="l4g-note" role="status" data-l4-bulk-note>{note}</p>}
    <div className="cf-table-wrap"><table className="cf-table" data-l4-bulk-table><thead><tr><th><input type="checkbox" aria-label="Tick every row on this page" checked={all} onChange={e=>setPick(e.target.checked?list.slice(0,MAX).map(r=>r.ref):[])}/></th><th>Item</th><th>University</th><th>Held because</th></tr></thead><tbody>
      {list.map(r=><tr key={r.ref} data-l4-bulk-row={r.ref}><td><input type="checkbox" aria-label={`Tick ${r.subject}`} checked={pick.includes(r.ref)} disabled={!pick.includes(r.ref)&&pick.length>=MAX} onChange={()=>toggle(r.ref)}/></td><td>{r.subject}</td><td>{r.provider||'—'}</td><td><small className="l4g-muted">{String(r.why||'').split(/(?<=[.;])\s/)[0]}</small></td></tr>)}
    </tbody></table></div>
    <div className="l4g-bar" data-l4-bulk-bar>
      <label>Reason<input value={reason} onChange={e=>setReason(e.target.value)} maxLength={300} placeholder={`Kept with every decision (${MIN_REASON} characters or more)`} data-l4-bulk-reason/></label>
      <div className="l4g-actions">
        {d.yes&&<Button compact variant="primary" disabled={!can||!ok(d.yes)} title={d.yes.label} onClick={()=>run(d.yes)} data-l4-bulk-approve>Approve Selected ({fmtNumber(pick.length)})</Button>}
        {d.no&&<Button compact disabled={!can||!ok(d.no)} title={d.no.label} onClick={()=>run(d.no)} data-l4-bulk-reject>Reject Selected</Button>}
      </div>
      <small className="l4g-muted">At most {MAX} at a time. A card that needs a value or more than a reason is decided on its own.</small>
    </div>
  </details>
}
