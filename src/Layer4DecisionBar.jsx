// CF-247 s931 (Decision 279, Platform Admin 21 Nov 2026 10:53; spec admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md §4.2, §5.3, §5.4):
// the review card's decision bar. Three decisions, Yes (Approve), No (Reject) and Resubmit to Review with AI, each the queue's own server choice
// (THREE_DECISIONS in src/lib/l4-rules.js); every other choice stays under More options. Each button keeps data-l4-choice={server key} and the
// server's rank gate; a decision the queue does not have is not drawn. Resubmit only calls the queue's existing re-read path (§5.4) and shows
// today's AI budget before confirm. RejectReasonChips: the four one-click reasons of No, which fill the reason field.
import React,{useEffect,useState}from'react'
import{ArrowRight,ChevronDown}from'lucide-react'
import{supabase}from'./lib/supabase'
import{roleName}from'./nav-map'
import{DECISION_LABEL,REJECT_REASONS,decisionsFor}from'./lib/l4-rules.js'

const MORE='l4-more-open' // §10 risk: More options remembers its last opened state per queue, for this browser tab
const readMore=k=>{try{const m=JSON.parse(sessionStorage.getItem(MORE)||'{}');return m[k]===true||(m[k]===undefined&&m['*']===true)}catch{return false}}
const saveMore=(k,v)=>{try{const m=JSON.parse(sessionStorage.getItem(MORE)||'{}');m[k]=v;sessionStorage.setItem(MORE,JSON.stringify(m))}catch{}}

/** The three decisions and More options of one card. `choices` are the card's server choices (already filtered for the card); `extraResubmit` is a
 * Resubmit that is not a server choice of the queue (an AER card's re-read from the stored copy), drawn only when its server check allows it. */
export default function Layer4DecisionBar({kind,choices,rank,open,needs,gated,onChoose,extraResubmit=null,before=null,hidden=()=>false}){
  const t=decisionsFor(kind,choices),resubmit=t.resubmit||extraResubmit
  const[more,setMore]=useState(()=>readMore(kind))
  const btn=(c,which)=>{if(!c||hidden(c))return null;const low=rank<needs(c),stop=gated(c)
    return <button key={c.key} type="button" className={`l4d-btn l4d-${which}${open?.key===c.key?' on':''}${c.link?' link':''} role-${c.role||'primary'}`} data-l4-choice={c.key} data-l4-decision={which} data-l4-role={c.role}
      disabled={low||stop} title={low?`Needs ${roleName(needs(c))} (rank ${needs(c)}) or above`:stop?'Held: this read is incomplete (see above)':c.returns}
      onClick={()=>onChoose(c)}><span>{c.key==='approve_keep_lock'?'Yes (Approve & Keep Lock)':DECISION_LABEL[which]}</span><small>{c.label}</small>{c.link&&<ArrowRight size={12}/>}</button>}
  const rest=t.more.filter(c=>!hidden(c))
  return <div className="l4d" data-l4-decisions>
    <div className="l4i-choices l4i-bar l4d-bar" data-l4-bar>
      {before}
      {btn(t.yes,'yes')}{btn(t.no,'no')}{btn(resubmit,'resubmit')}
      {rest.length>0&&<button type="button" className={`l4d-more-toggle${more?' open':''}`} aria-expanded={more} onClick={()=>{setMore(!more);saveMore(kind,!more)}} data-l4-more-toggle>More options <ChevronDown size={13}/></button>}
    </div>
    {more&&rest.length>0&&<div className="l4d-more" data-l4-more>{rest.map(c=>{const low=rank<needs(c),stop=gated(c)
      return <button key={c.key} type="button" className={`${open?.key===c.key?'on':''}${c.link?' link':''} role-${c.role||'primary'}`} data-l4-role={c.role} disabled={low||stop}
        title={low?`Needs ${roleName(needs(c))} (rank ${needs(c)}) or above`:stop?'Held: this read is incomplete (see above)':c.returns} onClick={()=>onChoose(c)} data-l4-choice={c.key}>{c.label}{c.link&&<ArrowRight size={12}/>}</button>})}</div>}
  </div>
}

/** §4.2: No (Reject) opens these four one-click reasons; a chip fills the reason field (its minimum length is unchanged), free text stays. */
export function RejectReasonChips({onPick}){
  return <div className="l4d-chips" role="group" aria-label="Why it is rejected" data-l4-reject-chips>{REJECT_REASONS.map(r=><button key={r} type="button" onClick={()=>onPick(r)} data-l4-reject-chip={r}>{r}</button>)}</div>
}

/** §5.4: today's AI budget, from the existing AI overview read (public.admin_ai_overview_v1); a role that cannot read it sees that it is not shown. */
export function AiBudgetLine({onState}){
  const[b,setB]=useState(null)
  useEffect(()=>{let on=true;supabase.rpc('admin_ai_overview_v1').then(({data,error})=>{if(!on)return;if(error){setB({error:true});onState?.({unknown:true});return}
    const or=data?.openrouter||{},spent=Number(or.spent_today_usd),cap=Number(data?.ceiling_usd??or.daily_ceiling_usd)
    const used=Number.isFinite(spent)&&Number.isFinite(cap)&&cap>0&&spent>=cap;setB({spent,cap,used});onState?.({used})}).catch(()=>on&&setB({error:true}));return()=>{on=false}},[])
  if(!b)return <p className="l4i-next" data-l4-ai-budget="reading"><small>Reading today's AI budget…</small></p>
  if(b.error)return <p className="l4i-next" data-l4-ai-budget="unknown"><small>AI budget today: not shown for your role. The re-read still stops at the daily ceiling.</small></p>
  const f=n=>Number.isFinite(n)?`US$${n.toFixed(2)}`:'—'
  return <p className="l4i-next" data-l4-ai-budget={b.used?'used':'ok'}><small>AI budget today: {f(b.spent)} of {f(b.cap)} used.{b.used?' Today\'s AI budget is used; try tomorrow or decide Yes / No.':''}</small></p>
}

/** The verified count of "Approve all verified for provider", read before the person confirms (public.admin_layer4_cd_provider_verified_v1). */
export function useVerifiedCount(ref,on){const[v,setV]=useState(null)
  useEffect(()=>{if(!on||!ref){setV(null);return}let live=true;supabase.rpc('admin_layer4_cd_provider_verified_v1',{p_ref:ref}).then(({data,error})=>live&&setV(error?{error:error.message}:data||{eligible:0})).catch(e=>live&&setV({error:e.message}));return()=>{live=false}},[ref,on])
  return v}
