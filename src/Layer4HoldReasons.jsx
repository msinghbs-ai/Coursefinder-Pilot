// CF-247 S831 (S1-AER, Platform Admin 20 Nov 2026 11:55 AEDT, item 4): Layer 4 › Inbox › Course entry first read: "Why items are held". The pending AER items counted by the
// reason their latest machine check stored (public.admin_layer4_aer_queue {hold_reasons}), and the items behind one reason.
// s1090 (Platform Admin 24 Nov 2026 22:35): (1) the counts and lists follow the screen's University and Destination country filters (provider_id, country);
// (2) the two reasons a person decides on (Provider matrix, change of an admitted table; Provider matrix, first run) open at once, each item with a tick box and one
// bar to Approve Selected or Reject Selected (a reason of 8 or more characters is kept with every decision); each item is decided on its own through the Inbox's own
// decide action, so the completeness gate, the rank checks and the audit trail are the card's own, and an item the server refuses is named, never skipped silently;
// (3) the long reason text of an item sits behind a toggle; (4) no catch-all "Other": every reason is named.
import React,{useEffect,useMemo,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtDate,fmtNumber}from'./ui-kit'
import{Drawer}from'./Layer4Grid'

const q=args=>supabase.rpc('admin_layer4_aer_queue',{p_args:{hold_reasons:true,...args}}).then(({data,error})=>{if(error)throw new Error(error.message);return data||{}})
const decide=async args=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:'decide',p_args:args});if(error)throw new Error(error.message);if(data&&data.ok===false)throw new Error(data.request||'more is needed');return data}
const PAGE=25 // the page the list asks for; the server allows at most 100
const MAX=100,MIN_REASON=8
/** The reasons a person decides on (the item has no machine rule that holds it): shown open, with the bulk bar. */
export const ACTIONABLE=['matrix_change','matrix_first_run']

function ReasonList({code,label,filter,kinds,ticked,onTick,onOpen,reload}){
  const[list,setList]=useState(null),[off,setOff]=useState(0)
  useEffect(()=>{setOff(0)},[code,filter.provider_id,filter.country,reload])
  useEffect(()=>{let live=true;setList(null);q({reason:code,offset:off,limit:PAGE,...filter}).then(d=>live&&setList(d)).catch(()=>live&&setList({items:[],total:0}));return()=>{live=false}},[code,off,filter.provider_id,filter.country,reload])
  const items=list?.items||[],sel=ACTIONABLE.includes(code) // only a reason a person decides on carries tick boxes
  return <div data-l4-hold-list={code}>
    <h4>{label}{list?` · ${fmtNumber(Number(list.total)||0)}`:''}</h4>
    {!list?<Loading compact/>:items.length===0?<Empty text="No item waits for this reason."/>:<div className="cf-table-wrap"><table className="cf-table"><thead><tr>{sel&&<th><input type="checkbox" aria-label="Tick every item on this page" checked={items.length>0&&items.every(it=>ticked.includes(it.id))} onChange={e=>onTick(items.map(it=>it.id),e.target.checked)} data-l4-hold-tick-all={code}/></th>}<th>University</th><th>Item</th><th>Country</th><th>Checked</th><th>Action</th></tr></thead><tbody>
      {items.map(it=><tr key={it.id} data-l4-hold-item={it.id}>{sel&&<td><input type="checkbox" aria-label={`Tick ${it.course} at ${it.provider}`} checked={ticked.includes(it.id)} onChange={e=>onTick([it.id],e.target.checked)} data-l4-hold-tick={it.id}/></td>}
        <td>{it.provider}</td><td>{it.course}{it.why&&<details className="l4i-more"><summary>Why it waits</summary><small className="sl-sub">{it.why}</small></details>}</td><td>{it.country||'—'}</td><td>{it.checked_at?fmtDate(it.checked_at):'—'}</td>
        <td><Button compact onClick={()=>onOpen(it)} data-l4-hold-open={it.id}>Check quotes</Button></td></tr>)}
    </tbody></table></div>}
    {list&&Number(list.total)>PAGE&&<div className="l4i-pager"><Button compact disabled={off===0} onClick={()=>setOff(Math.max(0,off-PAGE))}>Previous</Button><small>{off+1}–{Math.min(off+PAGE,list.total)} of {fmtNumber(list.total)}</small><Button compact disabled={off+PAGE>=list.total} onClick={()=>setOff(off+PAGE)}>Next</Button></div>}
  </div>}

export default function Layer4HoldReasons({kinds,targetDays,renderItem,onError,onDecided,providerId='',country='',rank=0}){
  const[sum,setSum]=useState(null),[reason,setReason]=useState(''),[open,setOpen]=useState(null),[ticked,setTicked]=useState([]),[why,setWhy]=useState(''),[busy,setBusy]=useState(false),[note,setNote]=useState(''),[tick,setTickN]=useState(0)
  const filter=useMemo(()=>({...(providerId?{provider_id:providerId}:{}),...(country?{country}:{})}),[providerId,country])
  const loadSum=()=>q(filter).then(setSum).catch(e=>{setSum({reasons:[],total:0});onError?.(e.message)})
  useEffect(()=>{setSum(null);setReason('');setTicked([]);setNote('');loadSum()},[providerId,country])
  if(!sum)return <Loading compact/>
  const rs=sum.reasons||[],actionable=rs.filter(x=>ACTIONABLE.includes(x.code)&&Number(x.n)>0),others=rs.filter(x=>!ACTIONABLE.includes(x.code))
  const labelOf=c=>rs.find(x=>x.code===c)?.label||c
  const choices=kinds?.aer_review?.choices||[],yes=choices.find(c=>c.key==='approve'),no=choices.find(c=>c.key==='reject')
  const ok=c=>c&&Number(rank)>=Number(c.rank||0)
  const setT=(ids,on)=>setTicked(t=>on?[...new Set([...t,...ids])].slice(0,MAX):t.filter(x=>!ids.includes(x)))
  const run=async c=>{setBusy(true);setNote('');let done=0;const bad=[]
    for(const ref of ticked){try{await decide({kind:'aer_review',ref,choice:c.key,reason:why.trim(),value:''});done++}catch(e){bad.push(e.message)}}
    setBusy(false);setNote(`${fmtNumber(done)} of ${fmtNumber(ticked.length)} decided${bad.length?`; ${fmtNumber(bad.length)} not decided (${bad[0]})`:''}.`);setTicked([]);if(done){setWhy('');setTickN(n=>n+1);loadSum();onDecided?.({batch:true,admitted:done,failed:bad.length})}}
  const can=!busy&&ticked.length>0&&why.trim().length>=MIN_REASON
  return <section className="l4i-hold" data-l4-hold-reasons aria-label="Why items are held">
    <h3>Why items are held ({fmtNumber(Number(sum.total)||0)} pending{providerId||country?', for the filters chosen':''})</h3>
    <p className="l4i-why"><small>Counted from the stored result of each item’s latest machine check{sum.as_at?` (read ${fmtDate(sum.as_at)})`:''}. Items a person decides are listed open below; the rest are held by a check and are not approved in bulk.</small></p>
    {rs.length===0?<Empty text="No AER item waits for these filters."/>:<div className="cf-table-wrap"><table className="cf-table" data-l4-hold-table><thead><tr><th>Reason</th><th>Items</th><th>Action</th></tr></thead><tbody>
      {rs.map(x=>{const act=ACTIONABLE.includes(x.code);return <tr key={x.code} data-l4-hold-code={x.code} className={reason===x.code?'on':''}><td>{x.label}</td><td>{fmtNumber(Number(x.n)||0)}</td>
        <td>{act?<small>Listed below</small>:<Button compact onClick={()=>setReason(reason===x.code?'':x.code)} aria-pressed={reason===x.code} data-l4-hold-show={x.code}>{reason===x.code?'Hide':x.code==='audit_sample'?'Show the audit sample':'Show items'}</Button>}</td></tr>})}
    </tbody></table></div>}
    {actionable.map(x=><ReasonList key={x.code} code={x.code} label={x.label} filter={filter} kinds={kinds} ticked={ticked} onTick={setT} onOpen={setOpen} reload={tick}/>)}
    {actionable.length>0&&<div className="l4g-bar" data-l4-bulk-bar data-l4-hold-bulk>
      {note&&<p className="l4g-note" role="status" data-l4-bulk-note>{note}</p>}
      <label>Reason<input value={why} onChange={e=>setWhy(e.target.value)} maxLength={300} placeholder={`Kept with every decision (${MIN_REASON} characters or more)`} data-l4-bulk-reason/></label>
      <div className="l4g-actions">
        {yes&&<Button compact variant="primary" disabled={!can||!ok(yes)} title={ok(yes)?yes.label:`Needs rank ${yes.rank}`} onClick={()=>run(yes)} data-l4-bulk-approve>Approve Selected ({fmtNumber(ticked.length)})</Button>}
        {no&&<Button compact disabled={!can||!ok(no)} title={ok(no)?no.label:`Needs rank ${no.rank}`} onClick={()=>run(no)} data-l4-bulk-reject>Reject Selected</Button>}
      </div>
      <small className="l4g-muted">At most {MAX} at a time. Each item is decided on its own: one the completeness gate holds, or that needs more than a reason, is named and left for its card.</small>
    </div>}
    {reason&&!ACTIONABLE.includes(reason)&&<ReasonList code={reason} label={labelOf(reason)} filter={filter} kinds={kinds} ticked={[]} onTick={()=>{}} onOpen={setOpen} reload={tick}/>}
    {open&&<Drawer target={{kind:'aer_review',ref:open.id,subject:open.course}} kinds={kinds} targetDays={targetDays} renderItem={renderItem} onClose={()=>setOpen(null)} onDecided={r=>{onDecided?.(r);setOpen(null);setTickN(n=>n+1);loadSum()}}/>}
  </section>
}
