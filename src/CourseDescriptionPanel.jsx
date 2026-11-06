// CF-247 Course descriptions, the complete capability (Platform Admin 6 Nov 2026 09:44 §2, §5). No new dashboard: this is the reviewer help inside the
// existing Layer 4 › Inbox (the Course description / University description pill) and the operator view inside the existing Enrich fields screen.
// Everything here reads public.admin_course_description_queue (read only). A person still decides every description in the Inbox; nothing here admits,
// decides or changes a setting, and an AI reading waiting in Layer 4 is never counted as admitted or published.
import React,{useEffect,useState}from'react'
import'./layer4-inbox.css'
import{supabase}from'./lib/supabase'
import{hrefFor}from'./nav-map'
import{Button,Empty,Loading}from'./ui-kit'
import{fmtNumber}from'./lib/format.js'
import{plainError}from'./lib/errors'

export const cdQueue=async(action,args)=>{const{data,error}=await supabase.rpc('admin_course_description_queue',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}

// the limits the checks apply, as the server last said them (the card line states a reading's size against them)
let LIMITS=null
export const cdLimits=()=>LIMITS
export const setCdLimits=l=>{if(l&&typeof l==='object')LIMITS=l}

// Reason classes: one tap fills the reason with a tag the trust-policy sample report counts (identity, support, marketing, fragment, other).
export const CD_REJECT=[['[identity] ','Wrong course'],['[support] ','Not supported by the page'],['[marketing] ','Marketing wording'],['[fragment] ','Fragment or unfinished'],['[other] ','Other']]
export const CD_APPROVE=['Checked against the page']
export const isCourseDescription=d=>d?.field_code==='course_description_first_read'

export function ReasonChips({choice,onPick}){
  const list=choice==='reject'?CD_REJECT:choice==='approve'?CD_APPROVE.map(t=>['',t]):[]
  if(!list.length)return null
  return <div className="l4i-cd-chips" role="group" aria-label="Quick reasons" data-l4-cd-reasons>{list.map(([tag,t])=><button type="button" key={t} onClick={()=>onPick(`${tag}${t}`)}>{t}</button>)}</div>
}

// "2 sentences, 183 characters (limits 1 to 4 sentences, 80 to 700 characters)", the rewrite note and any change in the rules since it was proposed
export function ChecksLine({d}){
  const c=d?.proposed?.checks,L=cdLimits(),re=d?.reask,now=d?.rules_now
  if(!c&&!re&&!now)return null
  return <p className="l4i-why" data-l4-cd-checks><small>
    {c&&<>Checks: {fmtNumber(c.sentences)} sentence{Number(c.sentences)===1?'':'s'}, {fmtNumber(c.chars)} characters{L?` (limits ${L.min_sentences} to ${L.max_sentences} sentences, ${L.min_chars} to ${L.max_chars} characters)`:''}. Every sentence is supported by its quote from the page.</>}
    {re&&<> The AI was asked once more because the first answer broke the {re.first?.rule==='sentence_count'?'sentence':'length'} limit ({fmtNumber(re.first?.sentences)} sentences, {fmtNumber(re.first?.chars)} characters); this is the rewrite{re.error?' (the re-ask failed, so this is the first answer)':''}.</>}
    {now&&now.ok===false&&<strong> Since it was proposed, it no longer passes: {String(now.rule||'').replace(/_/g,' ')}.</strong>}
  </small></p>
}

// state for the Inbox: the summary of the pending course descriptions and the ready-first queue (the AER queue's pattern)
export function useCdQueue(on,pid){
  const[sum,setSum]=useState(null),[mode,setMode]=useState(''),[list,setList]=useState(null),[off,setOff]=useState(0),[err,setErr]=useState('')
  const loadSum=()=>{if(!on){setSum(null);return}cdQueue('summary',{provider_id:pid||undefined,recheck:!!pid}).then(d=>{setCdLimits(d?.limits);setSum(d);setErr('')}).catch(e=>{setSum(null);setErr(plainError(e))})}
  const loadList=(o=off)=>{if(!on||!mode){setList(null);return}setList(null);cdQueue('items',{provider_id:pid||undefined,offset:o,sample:mode==='sample'}).then(setList).catch(e=>{setList({items:[],total:0});setErr(plainError(e))})}
  useEffect(()=>{setMode('');setOff(0);loadSum()},[on,pid])
  useEffect(()=>{setOff(0);loadList(0)},[mode,on,pid])
  return{sum,mode,setMode,list,off,setOff,loadSum,loadList,err}
}

export function CdPanel({q,showProvider}){
  const s=q.sum
  if(!s)return q.err?null:null
  const by=s.by_class||{},ready=Number(by.ready||0),fails=Number(by.fails_now||0),stale=Number(s.pending||0)-ready-fails
  if(!Number(s.pending)&&!Number(s.admitted_by_person))return null
  return <div className="l4i-cd" data-l4-cd-summary>
    <p className="l4i-aer-sum"><small><strong>Course descriptions:</strong> {fmtNumber(s.pending)} waiting for a person · <strong>{fmtNumber(ready)} ready to decide</strong>{fails?` · ${fmtNumber(fails)} no longer pass the checks`:''}{stale>0?` · ${fmtNumber(stale)} stale (the course or its page changed)`:''}
      {s.provider_id?'':' (checks re-run for the oldest only)'} · admitted by a person {fmtNumber(s.admitted_by_person)} · published to the website {fmtNumber(s.published_to_the_website)}{Number(s.waiting_behind_provider_cap)?` · ${fmtNumber(s.waiting_behind_provider_cap)} more wait behind the first ten of their university`:''}. A reading waiting here is not admitted and not published.</small></p>
    {(ready>0||Number(s.pending)>0)&&<div className="l4i-view" role="group" aria-label="Order" data-l4-cd-order>
      <button type="button" className={q.mode==='ready'?'on':''} aria-pressed={q.mode==='ready'} onClick={()=>q.setMode(q.mode==='ready'?'':'ready')} data-l4-cd-ready>Ready to decide ({fmtNumber(ready)})</button>
      <button type="button" className={q.mode==='sample'?'on':''} aria-pressed={q.mode==='sample'} onClick={()=>q.setMode(q.mode==='sample'?'':'sample')} data-l4-cd-sample>Trust-policy sample</button>
      {q.mode&&<button type="button" onClick={()=>q.setMode('')} data-l4-cd-all>All waiting</button>}</div>}
  </div>
}

export function CdList({q,sum,render}){
  const l=q.list
  if(!l)return <Loading compact/>
  const items=l.items||[],step=Number(l.limit||25)
  return <div data-l4-cd-list>
    {items.length===0?<Empty text={q.mode==='sample'?'No description of the sample is waiting for a person.':'Nothing is ready to decide here.'}/>:items.map(render)}
    {(q.off>0||Number(l.total)>items.length)&&q.off>=0&&<div className="l4i-pager" data-l4-cd-pager>
      <Button compact disabled={q.off===0} onClick={()=>{const o=Math.max(0,q.off-step);q.setOff(o);q.loadList(o)}}>Previous</Button>
      <small>{fmtNumber(items.length?q.off+1:q.off)}–{fmtNumber(q.off+items.length)} of {fmtNumber(l.total)}{q.mode==='sample'?' in the sample':' ready'}, oldest first</small>
      <Button compact disabled={q.off+items.length>=Number(l.total)} onClick={()=>{const o=q.off+step;q.setOff(o);q.loadList(o)}}>Next</Button></div>}
  </div>
}

// ---- Enrich fields › Course descriptions (operator view, existing screen): what is held and why, the claim words, the sample -------------------
const RULE={length:'too long',sentence_count:'too many sentences',unsupported_claim:'a claim word not in the quote',quote_not_on_page:'quote not on the page',unsupported_sentence:'sentence not supported by its quote',
  unsupported_marketing:'a marketing word not in the quote',incomplete_sentence:'unfinished sentence',duplicate_other_course:'same words as another course',not_stated:'the page does not describe the course'}
const CLASS={ready:'ready to decide',fails_now:'no longer passes the checks',already_filled:'the course already has a description',locked:'locked by hand',page_changed:'the stored page changed',no_reading:'reading not stored',course_inactive:'course no longer active'}

export function CourseDescriptionsView(){
  const[sum,setSum]=useState(null),[held,setHeld]=useState(null),[err,setErr]=useState(''),[more,setMore]=useState('')
  const[words,setWords]=useState(null),[sample,setSample]=useState(null),[busy,setBusy]=useState('')
  useEffect(()=>{let live=true;Promise.all([cdQueue('summary'),cdQueue('held_reasons')]).then(([a,b])=>{if(live){setCdLimits(a?.limits);setSum(a);setHeld(b)}}).catch(e=>live&&setErr(plainError(e)));return()=>{live=false}},[])
  const load=async(k,fn,set)=>{setBusy(k);try{set(await fn())}catch(e){setErr(plainError(e))}finally{setBusy('')}}
  if(err&&!sum)return <p className="l3v-note" role="alert">{err}</p>
  if(!sum||!held)return <Loading compact/>
  const by=sum.by_class||{},rules=Object.entries(held.by_rule||{}).sort((a,b)=>b[1]-a[1]),L=sum.limits||{}
  const share=Number(held.readings)?Math.round(100*Number(held.passed_every_check)/Number(held.readings)):null
  return <div className="ef-cd" data-enrich-cd>
    <p className="sl-sub" data-enrich-cd-measures>Four measures, kept apart: <strong>{fmtNumber(sum.proposed_in_layer4)}</strong> proposed (waiting in Layer 4) · <strong>{fmtNumber(sum.admitted_by_person)}</strong> admitted by a person · <strong>{fmtNumber(sum.published_to_the_website)}</strong> published to the website · <strong>{fmtNumber(sum.admitted_without_a_person)}</strong> admitted without a person (stays 0 while a person must approve the first {fmtNumber(sum.review_first)} per university). {fmtNumber(sum.waiting_behind_provider_cap)} more readings wait behind a university&apos;s first waiting descriptions. An AI reading is never counted as admitted or published.</p>
    <div className="cf-table-wrap"><table className="cf-table" data-enrich-cd-classes><thead><tr><th>Waiting in Layer 4</th><th className="num">Items</th></tr></thead><tbody>
      {Object.entries(CLASS).filter(([k])=>by[k]).map(([k,l])=><tr key={k}><td>{l}</td><td className="num">{fmtNumber(by[k])}</td></tr>)}
      <tr><td><strong>Total waiting</strong></td><td className="num"><strong>{fmtNumber(sum.pending)}</strong></td></tr></tbody></table></div>
    <p className="sl-sub">Decide them in <a href={hrefFor('layer4','inbox',{kind:'provider_description'})} data-enrich-cd-open>Layer 4 › Inbox › Course description</a>, ready first. Limits: {L.min_sentences} to {L.max_sentences} sentences, {L.min_chars} to {L.max_chars} characters. One AI re-ask for a length breach is {Number(sum.reask_max)>0?`on (${sum.reask_max})`:'off'}.</p>
    <h4 className="ef-cd-h">Why readings were held, last {fmtNumber(held.days)} days</h4>
    <p className="sl-sub" data-enrich-cd-held>{fmtNumber(held.readings)} readings: {fmtNumber(held.passed_every_check)} passed every check{share!=null?` (${share}%)`:''}, {fmtNumber(held.held_by_a_check)} held by a check. AI cost US${Number(held.ai_cost_usd||0).toFixed(2)}{held.ai_cost_per_passing_reading_usd!=null?`, US$${Number(held.ai_cost_per_passing_reading_usd).toFixed(4)} per passing reading`:''}. Re-asks: {fmtNumber(held.reask?.attempted)} made, {fmtNumber(held.reask?.now_within_limits)} now within the limits, {fmtNumber(held.reask?.still_held)} still held.</p>
    {rules.length>0&&<ul className="l4i-plain">{rules.map(([r,n])=><li key={r}>{RULE[r]||r}: {fmtNumber(n)}{r==='unsupported_claim'&&held.claim_words&&Object.keys(held.claim_words).length?` (${Object.entries(held.claim_words).sort((a,b)=>b[1]-a[1]).map(([w,c])=>`${w} ${fmtNumber(c)}`).join(', ')})`:''}</li>)}</ul>}
    <div className="ef-actions">
      <Button compact disabled={busy!==''} onClick={()=>load('words',()=>cdQueue('claim_words'),setWords)} data-enrich-cd-words>{busy==='words'?'Evaluating…':'Evaluate the claim words'}</Button>
      <Button compact disabled={busy!==''} onClick={()=>load('sample',()=>cdQueue('sample'),setSample)} data-enrich-cd-sample>{busy==='sample'?'Reading…':'Trust-policy sample report'}</Button></div>
    {words&&<div data-enrich-cd-wordlist><p className="sl-sub">{words.note} Held readings in the last {fmtNumber(words.window_days)} days; every other rule is run again without the word.</p>
      {(words.words||[]).length===0?<Empty text="No reading is held by a claim word in this window."/>:(words.words||[]).map(w=><div key={w.word} className="ef-cd-word">
        <p><strong>{w.word}</strong>: {fmtNumber(w.held)} held, {fmtNumber(w.only_this_word)} held by this word alone, {fmtNumber(w.passes_every_other_rule_without_it)} would pass every other rule without it{Object.keys(w.next_rule||{}).length?`; the rest fall to ${Object.entries(w.next_rule).map(([r,n])=>`${RULE[r]||r} ${n}`).join(', ')}`:''}. The page says &quot;you&quot; in {fmtNumber(w.quote_addresses_the_reader)}.</p>
        <button type="button" className="l4i-linkish" onClick={()=>setMore(m=>m===w.word?'':w.word)} aria-expanded={more===w.word}>Examples</button>
        {more===w.word&&<div><p className="sl-sub">Looks harmless (the page addresses the reader):</p>{(w.suggested_harmless||[]).length?<ul className="l4i-plain">{w.suggested_harmless.map((x,i)=><li key={i}>{x.text}<br/><small>Page: <q>{x.quote}</q></small></li>)}</ul>:<small>none</small>}
          <p className="sl-sub">Looks like a real claim:</p>{(w.suggested_claim||[]).length?<ul className="l4i-plain">{w.suggested_claim.map((x,i)=><li key={i}>{x.text}<br/><small>Page: <q>{x.quote}</q></small></li>)}</ul>:<small>none</small>}</div>}
      </div>)}</div>}
    {sample&&<div data-enrich-cd-samplereport><p className="sl-sub">{sample.note}</p>
      <div className="cf-table-wrap"><table className="cf-table"><thead><tr><th>Country</th><th className="num">Wanted</th><th className="num">Eligible</th><th className="num">Selected</th><th className="num">Short</th></tr></thead><tbody>
        {(sample.strata||[]).map(r=><tr key={r.country}><td>{r.country}</td><td className="num">{fmtNumber(r.wanted)}</td><td className="num">{fmtNumber(r.eligible)}</td><td className="num">{fmtNumber(r.selected)}</td><td className="num">{fmtNumber(r.shortfall)}</td></tr>)}</tbody></table></div>
      <p className="sl-sub">{fmtNumber(sample.selected)} selected: {fmtNumber(sample.approved)} approved, {fmtNumber(sample.rejected)} rejected, {fmtNumber(sample.pending)} waiting for a person{sample.approval_share_of_decided!=null?`; approval share of those decided ${Math.round(100*Number(sample.approval_share_of_decided))}%`:''}. Rejections by reason: {Object.keys(sample.rejected_by_class||{}).length?Object.entries(sample.rejected_by_class).map(([k,n])=>`${k} ${n}`).join(', '):'none yet'}. Reviewer disagreement: {fmtNumber(sample.reviewer_disagreement?.passed_every_check_but_rejected)} passed every check but were rejected; {fmtNumber(sample.reviewer_disagreement?.approved_but_rules_now_fail)} approved but no longer pass the rules. Claim words present in {fmtNumber(sample.claim_support?.with_claim_words_in_quote)}; lowest sentence support {sample.claim_support?.lowest_sentence_support??'—'}.</p></div>}
    {err&&<small className="fr-error" role="alert">{err}</small>}
  </div>
}

