// v2.16.40 (CF-247, S2-Build, Platform Admin 18 Nov 2026 13:02): Layer 4 › Inbox › Grid › Grouped decisions (src/Layer4GroupDecide.jsx; not the operational groups of src/Layer4Groups.jsx). One choice and one reason
// for every item of a group: AER course entry items held only because the stored page is shared with other programmes (grouped by university
// and page) and refused Boost study loads with the same quote at the same university. Groups are worked out on the server
// (public.admin_layer4_group_decide_read_v1); the AER audit sample, identity and page problems, campus postcodes and every other kind are never
// grouped. Each item is decided through the Inbox's own decision (public.admin_layer4_group_decide_v1 calls admin_layer4_inbox per item), at the
// rank one item needs, with a typed confirmation; a group that changed since it was shown is refused.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,EmptyInline,fmtNumber}from'./ui-kit'

const call=async(fn,args)=>{const{data,error}=await supabase.rpc(fn,args);if(error)throw new Error(error.message);return data}
const KINDS=[['aer_review','Entry requirements: shared stored page'],['boost_study_load','Refused study loads: same quote']]

export default function Layer4GroupDecide({onDecided}){
  const[kind,setKind]=useState('aer_review'),[d,setD]=useState(null),[err,setErr]=useState(''),[note,setNote]=useState('')
  const[pick,setPick]=useState([]),[choice,setChoice]=useState(''),[reason,setReason]=useState(''),[confirm,setConfirm]=useState(''),[busy,setBusy]=useState(false)
  const load=()=>{setD(null);setErr('');setPick([]);call('admin_layer4_group_decide_read_v1',{p_args:{kind}}).then(x=>{setD(x);setChoice((x.choices||[])[0]?.key||'')}).catch(e=>setErr(e.message))}
  useEffect(()=>{load();setNote('')},[kind])
  const groups=d?.groups||[],chosen=groups.filter(g=>pick.includes(g.group_key)),c=(d?.choices||[]).find(x=>x.key===choice)
  const allowed=c&&Number(d?.rank)>=Number(c.rank)
  const run=async()=>{setBusy(true);setErr('');let ok=0,bad=0;const lines=[]
    for(const g of chosen){
      try{const r=await call('admin_layer4_group_decide_v1',{p_args:{kind,group_key:g.group_key,refs:g.refs,choice,reason:reason.trim(),confirm:`${choice.toUpperCase()} ${g.n}`}});ok+=Number(r.decided||0);bad+=Number(r.not_decided||0);if(r.not_decided)lines.push(`${g.provider}: ${r.not_decided} not decided`)}
      catch(e){lines.push(`${g.provider}: ${e.message}`)}}
    setBusy(false);setConfirm('');setNote(`${fmtNumber(ok)} item(s) decided${bad?`, ${fmtNumber(bad)} not decided`:''}.${lines.length?' '+lines.join(' · '):''}`);onDecided?.();load()}
  const total=chosen.reduce((s,g)=>s+Number(g.n||0),0),phrase=`${(choice||'').toUpperCase()} ${total}`
  return <section className="l4g-groups" data-l4g-groups>
    <p className="l4g-help">One choice and one reason for every item of the groups you tick. Groups are worked out on the server: {d?.never_grouped||'audit samples and other kinds are decided one at a time.'} Each item is decided exactly as it would be on its own card, at the same rank, and logged.</p>
    <div className="l4g-bar">
      <label>Group by<select value={kind} onChange={e=>setKind(e.target.value)} data-l4g-group-kind>{KINDS.map(([k,l])=><option key={k} value={k}>{l}</option>)}</select></label>
      <label>Choice<select value={choice} onChange={e=>setChoice(e.target.value)} data-l4g-group-choice>{(d?.choices||[]).map(x=><option key={x.key} value={x.key}>{x.label}</option>)}</select></label>
      <label>Reason<input value={reason} onChange={e=>setReason(e.target.value)} maxLength={300} placeholder="Kept with every decision (8 characters or more)" data-l4g-group-reason/></label>
      <div className="l4g-actions"><Button compact onClick={load} data-l4g-group-refresh>Refresh</Button></div>
    </div>
    {err&&<p className="l4g-err" role="alert">{err}</p>}
    {note&&<p className="l4g-note" role="status" data-l4g-group-note>{note}</p>}
    {!d?<EmptyInline text="Working out the groups…"/>:!groups.length?<EmptyInline text="No group of two or more items is waiting for this kind."/>:<div className="cf-table-wrap"><table className="cf-table" data-l4g-group-table><thead><tr><th></th><th>University</th><th>{kind==='aer_review'?'Shared stored page':'Quote on the page'}</th><th>Items</th><th>{kind==='aer_review'?'Why grouped':'The model said'}</th></tr></thead><tbody>
      {groups.map(g=><tr key={g.group_key} data-l4g-group={g.group_key}><td><input type="checkbox" aria-label={`Choose ${g.provider}`} checked={pick.includes(g.group_key)} disabled={Number(g.n)>Number(d.max_items)} onChange={e=>setPick(p=>e.target.checked?[...p,g.group_key]:p.filter(x=>x!==g.group_key))}/></td>
        <td>{g.provider}</td><td>{kind==='aer_review'?<a href={g.label} target="_blank" rel="noreferrer">{g.label}</a>:<q>{g.label}</q>}</td><td>{fmtNumber(g.n)}{Number(g.n)>Number(d.max_items)&&<small className="l4g-muted"> over {fmtNumber(d.max_items)}: decide on By kind</small>}</td>
        <td><small className="l4g-muted">{kind==='aer_review'?g.detail?.why:Object.entries(g.detail?.model_said||{}).map(([k,v])=>`${k.replace(/_/g,' ')} ${v}`).join(' · ')}</small></td></tr>)}
    </tbody></table></div>}
    {chosen.length>0&&<div className="l4g-save" data-l4g-group-confirm>
      {!allowed?<small className="l4g-muted">Your role cannot make this choice (as for one item).</small>:<>
        <span>{fmtNumber(chosen.length)} group(s), {fmtNumber(total)} item(s). Type <strong>{phrase}</strong> to confirm.</span>
        <input value={confirm} onChange={e=>setConfirm(e.target.value)} aria-label="Confirmation" data-l4g-group-confirm-input/>
        <Button compact variant="primary" disabled={busy||confirm.trim()!==phrase||reason.trim().length<8} onClick={run} data-l4g-group-run>{busy?'Deciding…':`Decide ${fmtNumber(total)} item(s)`}</Button></>}
    </div>}
  </section>
}
