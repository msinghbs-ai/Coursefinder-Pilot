// CF-247 Layer 4 action lifecycle (Platform Admin decision 4 Nov 2026 12:24 §2-§4, §6; IQ-00279, RMIT Diploma of Commerce): what was done to
// a Layer 4 item, when, whether it worked, why the item is still waiting and what happens next. Read from public.admin_layer4_lifecycle (the
// persisted records: Inbox audit rows, recovery actions, corrected reads, work items, interventions), so the same block comes back after
// Refresh. The acknowledgement of a decision is shown only from the server's reply (ack), never before the server confirms it.
// Cards on one page are read in one call (a short batch), and only when the card is on screen. Times are Australian (AEDT/AEST), from the server.
import React,{useEffect,useRef,useState}from'react'
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

export const OUTCOME={accepted:'Accepted',refused:'Refused',deferred:'Deferred',queued:'Queued',already_requested:'Already requested',completed:'Completed',incomplete:'Still incomplete',human_input:'Human input needed',failed:'Failed'}
const TONE={refused:'danger',failed:'danger',deferred:'warning',already_requested:'warning',incomplete:'warning',human_input:'warning',awaiting_input:'warning',queued:'info',scheduled:'info',executing:'info',accepted:'info',completed:'success',verified:'success',resolved:'success',superseded:'success'}
const TIMES=[['first_entered','First entered Layer 4'],['item_created','This item created'],['last_entered','Last entered review'],['last_updated','Last updated'],
  ['last_reviewer_action','Last reviewer action'],['last_automated_attempt','Last automatic attempt'],['next_action','Next action'],['decided','Decided'],['admitted','Admitted'],['published','Published']]
const STEPS=[['requested','Requested'],['executed','Ran'],['valid','Valid extraction'],['approved','Layer 4 decision'],['admitted','Admitted'],['published','Published']]
const label=a=>String(a||'').replace(/_/g,' ')
const short=id=>id?String(id).slice(0,8):''
const ACTIVE=new Set(['scheduled','executing'])

/** The acknowledgement: the server's headline (observation 13:00 §3), its reference and time, the reason, the permitted alternative and what is next. */
export function Ack({a,action}){
  if(!a)return null
  const o=a.outcome||a.result?.outcome,head=a.headline||a.result?.headline
  return <div className={`l4lc-ack tone-${TONE[o]||'info'}`} role="status" data-l4-ack={o}>
    <strong data-l4-ack-headline>{head||`${action?`${label(action)}: `:''}${OUTCOME[o]||label(o)}`}</strong>
    {(a.ref||a.at)&&<span className="l4lc-ref"> · {[a.ref,a.at?.text].filter(Boolean).join(' · ')}</span>}
    {(a.reason||a.result?.reason)&&<p>{a.reason||a.result?.reason}</p>}
    {(a.alternative||a.result?.alternative)&&<p><em>Instead:</em> {a.alternative||a.result?.alternative}</p>}
    {a.next&&<p><em>Next:</em> {a.next}</p>}
  </div>}

/** One event of the history: a request, a read (attempt, operation, reader times), a validation, a supersession or a decision. */
function Event({h}){
  const r=h.result||{},rd=h.reader||{}
  return <li data-l4-event={h.action}>
    <span>{h.at?.text}</span> · <span>{h.by}</span> · <strong>{label(h.action)}{h.attempt?` (attempt ${h.attempt})`:''}</strong>{h.ref?` · ${h.ref}`:''}: {r.headline||OUTCOME[r.outcome]||label(r.outcome)}{r.reason&&!r.headline?` — ${r.reason}`:''}
    {(h.operation||rd.started)&&<small className="l4lc-ev" data-l4-event-detail>
      {h.operation&&<> Request {short(h.operation.request)} · enrich item {h.operation.enrich_item}{h.operation.job?` · job ${short(h.operation.job)}`:''}.</>}
      {rd.started&&<> Reader {rd.started.hm}{rd.completed?` → ${rd.completed.hm}`:' (not finished)'}{rd.stored_copy?` on stored copy ${short(rd.stored_copy)}`:''}{rd.cost_usd!=null?` · US$${rd.cost_usd}`:''}.</>}
      {r.headline&&r.reason&&<> {r.reason}.</>}
      {h.original_read&&<> Read {short(h.original_read)}{h.replacement_read?` → replacement ${short(h.replacement_read)}${h.re_entered?` (entered Layer 4 ${h.re_entered.text})`:''}`:''}.</>}
    </small>}</li>}

/** The Progress block of a Layer 4 card (decision 12:24 §2-§4; observation 13:00 §2-§5): a compact summary, then the times, steps and every
 *  event. ack: the server's reply to the last decision here. While a recovery is queued or running the block reads its progress again, as often
 *  and as many times as the server's settings say (layer4.lifecycle_poll_seconds, layer4.lifecycle_poll_max); when it settles, onSettled
 *  refreshes the list and the counts. */
export function ItemLifecycle({kind,refId,ack,seen=true,onSettled}){
  const[lc,setLc]=useState(null),[err,setErr]=useState(''),[tick,setTick]=useState(0)
  const polls=useRef(0),was=useRef(null)
  useEffect(()=>{polls.current=0},[ack?.ref])
  useEffect(()=>{if(!seen)return;let live=true;readLifecycle(kind,refId).then(v=>{if(!live)return;setLc(v);setErr('')
      if(was.current&&ACTIVE.has(was.current)&&v&&!ACTIVE.has(v.stage))onSettled?.()
      was.current=v?.stage||null}).catch(e=>live&&setErr(e.message));return()=>{live=false}},[kind,refId,seen,ack?.ref,tick])
  useEffect(()=>{const p=lc?.poll;if(!p||!seen||polls.current>=Number(p.max||0))return
    const t=setTimeout(()=>{polls.current+=1;setTick(x=>x+1)},Math.max(5,Number(p.every_seconds)||15)*1000);return()=>clearTimeout(t)},[lc,seen])
  if(err)return <p className="l4lc-err" data-l4-lifecycle-error>Progress could not be read: {err}</p>
  if(!lc||lc.found===false)return ack?<div className="l4lc" data-l4-lifecycle><Ack a={ack}/></div>:null
  const t=lc.times||{},last=lc.last_action,rc=lc.recovery
  return <section className="l4lc" data-l4-lifecycle data-stage={lc.stage}>
    {ack?<Ack a={ack}/>:last&&<Ack a={{...last.result,ref:last.ref,at:last.at}} action={last.action}/>}
    <dl className="l4lc-times l4lc-summary" data-l4-summary>
      <dt>First entered Layer 4</dt><dd data-l4-time="first_entered">{t.first_entered?.text||'—'}</dd>
      {lc.group_label&&<><dt>Person needed</dt><dd data-l4-group={lc.group}>{lc.group_label}: {lc.person_needed}</dd></>}
      <dt>Status</dt><dd><span className={`l4lc-chip tone-${TONE[lc.stage]||'info'}`} data-l4-stage>{lc.stage_label}</span>{lc.why_pending&&<span data-l4-why-pending> {lc.why_pending}</span>}</dd>
      <dt>Last reviewer action</dt><dd data-l4-last-reviewer>{last&&last.by==='reviewer'?`${label(last.action)} · ${last.at?.text||''}`:(t.last_reviewer_action?.text||'none yet')}</dd>
      {rc&&<><dt>Last recovery</dt><dd data-l4-last-recovery>{`Attempt ${rc.attempt}: ${rc.result?.headline||label(rc.result?.outcome)} · ${rc.at?.text||''}`}</dd></>}
      {lc.open&&<><dt>Next</dt><dd data-l4-next>{lc.next?.text||'—'}{lc.next?.at?.text?` (${lc.next.at.text})`:''}{lc.owner?` · ${lc.owner}`:''}</dd></>}
      {lc.waiting?.text&&<><dt>Waiting</dt><dd data-l4-waiting>{lc.waiting.text}</dd></>}
    </dl>
    {lc.poll&&<p className="l4lc-ref" data-l4-polling>Updating by itself while the recovery runs.</p>}
    {lc.repeat_guard&&<p className="l4lc-guard" data-l4-repeat-guard><em>Not offered again:</em> {lc.repeat_guard.why}.</p>}
    {(lc.predecessor||lc.successor)&&<p className="l4lc-link" data-l4-lineage>
      {lc.predecessor&&<>Replaces an earlier read ({short(lc.predecessor.ref)}, superseded{lc.predecessor.at?.text?` ${lc.predecessor.at.text}`:''}). </>}
      {lc.successor&&<>Replaced by a corrected read ({short(lc.successor.ref)}, now {label(lc.successor.status)}{lc.successor.complete===true?', complete: ready for review':lc.successor.complete===false?', still held':''}).</>}</p>}
    {lc.evidence&&typeof lc.evidence==='object'&&<details className="l4lc-more" data-l4-evidence-held><summary>What the platform holds</summary>
      <dl className="l4lc-steps">{Object.entries(lc.evidence).map(([k,v])=><React.Fragment key={k}><dt>{k}</dt><dd>{v!==null&&typeof v==='object'?Object.entries(v).map(([a,b])=>`${a}: ${typeof b==='object'?JSON.stringify(b):b}`).join('; '):String(v)}</dd></React.Fragment>)}</dl></details>}
    <details className="l4lc-more"><summary>Event history, times and steps</summary>
      {(lc.history||[]).length>0&&<ol className="l4lc-history" data-l4-history>{lc.history.map((h,i)=><Event key={i} h={h}/>)}</ol>}
      <dl className="l4lc-times" data-l4-times>{TIMES.filter(([k])=>t[k]?.text).map(([k,l])=><React.Fragment key={k}><dt>{l}</dt><dd data-l4-time-all={k}>{t[k].text}</dd></React.Fragment>)}
        {Number(lc.entries)>1&&<><dt>Entries</dt><dd data-l4-entries>{lc.entries} (re-entered)</dd></>}</dl>
      <dl className="l4lc-steps" data-l4-steps>{STEPS.map(([k,l])=><React.Fragment key={k}><dt>{l}</dt><dd>{lc.steps?.[k]??'—'}</dd></React.Fragment>)}</dl>
    </details>
  </section>}
