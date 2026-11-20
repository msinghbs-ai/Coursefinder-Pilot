// CF-247 S831 (S1-AER, Platform Admin 20 Nov 2026 11:55 AEDT, item 4): Layer 4 › Inbox › Course entry first read: "Why items are held". The pending AER items counted by the
// reason their latest machine check stored (public.admin_layer4_aer_queue {hold_reasons}), and the items behind one reason, so a person can go straight to the audit sample.
// Read only; a row opens the Source quote drawer, where the Inbox's own card decides (Approve, Approve except, Reject, each with a reason). Nothing is approved in bulk here.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import{Button,Empty,Loading,fmtDate,fmtNumber}from'./ui-kit'
import{Drawer}from'./Layer4Grid'

const q=args=>supabase.rpc('admin_layer4_aer_queue',{p_args:{hold_reasons:true,...args}}).then(({data,error})=>{if(error)throw new Error(error.message);return data||{}})
const PAGE=25 // the page the list asks for; the server allows at most 100
export default function Layer4HoldReasons({kinds,targetDays,renderItem,onError,onDecided}){
  const[sum,setSum]=useState(null),[reason,setReason]=useState(''),[list,setList]=useState(null),[off,setOff]=useState(0),[open,setOpen]=useState(null)
  const loadSum=()=>q({}).then(setSum).catch(e=>{setSum({reasons:[],total:0});onError?.(e.message)})
  useEffect(()=>{loadSum()},[])
  const loadList=(r=reason,o=off)=>{if(!r){setList(null);return}setList(null);q({reason:r,offset:o,limit:PAGE}).then(setList).catch(e=>{setList({items:[],total:0});onError?.(e.message)})}
  useEffect(()=>{loadList(reason,off)},[reason,off])
  if(!sum)return <Loading compact/>
  const rs=sum.reasons||[],label=rs.find(x=>x.code===reason)?.label||''
  return <section className="l4i-hold" data-l4-hold-reasons aria-label="Why items are held">
    <h3>Why items are held ({fmtNumber(Number(sum.total)||0)} pending)</h3>
    <p className="l4i-why"><small>Counted from the stored result of each item’s latest machine check{sum.as_at?` (read ${fmtDate(sum.as_at)})`:''}. None of these items passes its rule today; a held item is not approved in bulk.</small></p>
    {rs.length===0?<Empty text="No AER item waits."/>:<div className="cf-table-wrap"><table className="cf-table" data-l4-hold-table><thead><tr><th>Reason</th><th>Items</th><th>Action</th></tr></thead><tbody>
      {rs.map(x=><tr key={x.code} data-l4-hold-code={x.code} className={reason===x.code?'on':''}><td>{x.label}</td><td>{fmtNumber(Number(x.n)||0)}</td>
        <td><Button compact onClick={()=>{setOff(0);setReason(reason===x.code?'':x.code)}} aria-pressed={reason===x.code} data-l4-hold-show={x.code}>{reason===x.code?'Hide':x.code==='audit_sample'?'Show the audit sample':'Show items'}</Button></td></tr>)}
    </tbody></table></div>}
    {reason&&<div data-l4-hold-list>
      <h4>{label}{list?` · ${fmtNumber(Number(list.total)||0)}`:''}</h4>
      {!list?<Loading compact/>:(list.items||[]).length===0?<Empty text="No item waits for this reason."/>:<div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>University</th><th>Course</th><th>Country</th><th>Checked</th><th>Action</th></tr></thead><tbody>
        {list.items.map(it=><tr key={it.id} data-l4-hold-item={it.id}><td>{it.provider}</td><td>{it.course}<small className="sl-sub"> {it.why}</small></td><td>{it.country||'—'}</td><td>{it.checked_at?fmtDate(it.checked_at):'—'}</td>
          <td><Button compact onClick={()=>setOpen(it)} data-l4-hold-open={it.id}>Check quotes</Button></td></tr>)}
      </tbody></table></div>}
      {list&&Number(list.total)>PAGE&&<div className="l4i-pager"><Button compact disabled={off===0} onClick={()=>setOff(Math.max(0,off-PAGE))}>Previous</Button><small>{off+1}–{Math.min(off+PAGE,list.total)} of {fmtNumber(list.total)}</small><Button compact disabled={off+PAGE>=list.total} onClick={()=>setOff(off+PAGE)}>Next</Button></div>}
    </div>}
    {open&&<Drawer target={{kind:'aer_review',ref:open.id,subject:open.course}} kinds={kinds} targetDays={targetDays} renderItem={renderItem} onClose={()=>setOpen(null)} onDecided={r=>{onDecided?.(r);setOpen(null);loadSum();loadList()}}/>}
  </section>
}
