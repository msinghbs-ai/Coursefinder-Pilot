// CF-247 Layer 4 action lifecycle (Platform Admin decision 4 Nov 2026 12:24 §2-§4, §6; IQ-00279, RMIT Diploma of Commerce): what was done to
// a Layer 4 item, when, whether it worked, why the item is still waiting and what happens next. Read from public.admin_layer4_lifecycle (the
// persisted records: Inbox audit rows, recovery actions, corrected reads, work items, interventions), so the same block comes back after
// Refresh. The acknowledgement of a decision is shown only from the server's reply (ack), never before the server confirms it.
// Cards on one page are read in one call (a short batch), and only when the card is on screen. Times are Australian (AEDT/AEST), from the server.
import React,{useEffect,useState}from'react'
import{supabase}from'./lib/supabase'
import'./layer4-item-lifecycle.css'

let queue=[],timer=null
const flush=async()=>{const q=queue;queue=[];timer=null
  try{const{data,error}=await supabase.rpc('admin_layer4_lifecycle',{p_args:{items:q.map(x=>({kind:x.kind,ref:x.ref}))}})
    if(error)throw new Error(error.message)
    for(const x of q)x.ok(data?.items?.[`${x.kind}:${x.ref}`]||null)}
  catch(e){for(const x of q)x.fail(e)}}
/** One card's lifecycle; calls made in the same moment (one page of cards) share one read. */
export const readLifecycle=(kind,ref)=>new Promise((ok,fail)=>{queue.push({kind,ref,ok,fail});if(!timer)timer=setTimeout(flush,30)})

export const OUTCOME={accepted:'Accepted',refused:'Refused',queued:'Queued',already_requested:'Already requested',completed:'Completed',incomplete:'Still incomplete',human_input:'Human input needed',failed:'Failed'}
const TONE={refused:'danger',failed:'danger',already_requested:'warning',incomplete:'warning',human_input:'warning',queued:'info',accepted:'info',completed:'success'}
const TIMES=[['first_entered','First entered Layer 4'],['item_created','This item created'],['last_entered','Last entered review'],['last_updated','Last updated'],
  ['last_reviewer_action','Last reviewer action'],['last_automated_attempt','Last automatic attempt'],['next_action','Next action'],['decided','Decided'],['admitted','Admitted'],['published','Published']]
const STEPS=[['requested','Requested'],['executed','Ran'],['valid','Valid extraction'],['approved','Layer 4 decision'],['admitted','Admitted'],['published','Published']]
const label=a=>String(a||'').replace(/_/g,' ')

/** The acknowledgement line: what was done, its reference and time, the result, the reason, the permitted alternative and what happens next. */
export function Ack({a,action}){
  if(!a)return null
  const o=a.outcome||a.result?.outcome
  return <div className={`l4lc-ack tone-${TONE[o]||'info'}`} role="status" data-l4-ack={o}>
    <strong>{action?`${label(action)}: `:''}{OUTCOME[o]||label(o)}</strong>
    {(a.ref||a.at)&&<span className="l4lc-ref"> · {[a.ref,a.at?.text].filter(Boolean).join(' · ')}</span>}
    {(a.reason||a.result?.reason)&&<p>{a.reason||a.result?.reason}</p>}
    {(a.alternative||a.result?.alternative)&&<p><em>Instead:</em> {a.alternative||a.result?.alternative}</p>}
    {a.next&&<p><em>Next:</em> {a.next}</p>}
  </div>}

/** The Progress block of a Layer 4 card. ack: the reply of the last decision on this card (shown until the persisted record is read back). */
export function ItemLifecycle({kind,refId,ack,seen=true}){
  const[lc,setLc]=useState(null),[err,setErr]=useState('')
  useEffect(()=>{if(!seen)return;let live=true;readLifecycle(kind,refId).then(v=>{if(live){setLc(v);setErr('')}}).catch(e=>live&&setErr(e.message));return()=>{live=false}},[kind,refId,seen,ack?.ref])
  if(err)return <p className="l4lc-err" role="alert" data-l4-lifecycle-error>Progress could not be read: {err}</p>
  if(!lc||lc.found===false)return ack?<div className="l4lc" data-l4-lifecycle><Ack a={ack}/></div>:null
  const t=lc.times||{},last=lc.last_action
  return <section className="l4lc" data-l4-lifecycle data-stage={lc.stage}>
    {ack?<Ack a={ack}/>:last&&<Ack a={{...last.result,ref:last.ref,at:last.at}} action={last.action}/>}
    <p className="l4lc-stage"><span className={`l4lc-chip tone-${TONE[lc.stage]||'info'}`} data-l4-stage>{lc.stage_label}</span>
      {lc.why_pending&&<span data-l4-why-pending> {lc.why_pending}</span>}</p>
    {lc.next?.text&&<p className="l4lc-next" data-l4-next><em>Next:</em> {lc.next.text}{lc.next.at?.text?` (${lc.next.at.text})`:''}{lc.owner?` · ${lc.owner}`:''}</p>}
    {lc.repeat_guard&&<p className="l4lc-guard" data-l4-repeat-guard><em>Not offered again:</em> {lc.repeat_guard.why}.</p>}
    {(lc.predecessor||lc.successor)&&<p className="l4lc-link" data-l4-lineage>
      {lc.predecessor&&<>Replaces an earlier read ({String(lc.predecessor.ref).slice(0,8)}, superseded{lc.predecessor.at?.text?` ${lc.predecessor.at.text}`:''}). </>}
      {lc.successor&&<>Replaced by a corrected read ({String(lc.successor.ref).slice(0,8)}, now {label(lc.successor.status)}).</>}</p>}
    <dl className="l4lc-times" data-l4-times>{TIMES.filter(([k])=>t[k]?.text).map(([k,l])=><React.Fragment key={k}><dt>{l}</dt><dd data-l4-time={k}>{t[k].text}</dd></React.Fragment>)}
      {Number(lc.entries)>1&&<><dt>Entries</dt><dd data-l4-entries>{lc.entries} (re-entered)</dd></>}</dl>
    <details className="l4lc-more"><summary>Steps and history</summary>
      <dl className="l4lc-steps" data-l4-steps>{STEPS.map(([k,l])=><React.Fragment key={k}><dt>{l}</dt><dd>{lc.steps?.[k]??'—'}</dd></React.Fragment>)}</dl>
      {(lc.history||[]).length>0&&<ol className="l4lc-history" data-l4-history>{lc.history.map((h,i)=><li key={i}>
        <span>{h.at?.text}</span> · <span>{h.by}</span> · <strong>{label(h.action)}</strong>{h.ref?` (${h.ref})`:''}: {OUTCOME[h.result?.outcome]||label(h.result?.outcome)}{h.result?.reason?` — ${h.result.reason}`:''}</li>)}</ol>}
    </details>
  </section>}
