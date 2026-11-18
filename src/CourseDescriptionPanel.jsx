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
// objective review-pack flags (C-DESC, 8 Nov 2026): they say what to look at first; none of them decides anything
const PACK_FLAG={same_words_elsewhere:'same words as another course',claim_word:'uses a claim word (the page quote has it)',marketing_word:'uses a marketing word (the page quote has it)',money_or_year:'names a price or a year'}
export function ChecksLine({d}){
  const c=d?.proposed?.checks,L=cdLimits(),re=d?.reask,now=d?.rules_now,pk=d?.pack
  if(!c&&!re&&!now&&!pk)return null
  return <p className="l4i-why" data-l4-cd-checks><small>
    {c&&<>Checks: {fmtNumber(c.sentences)} sentence{Number(c.sentences)===1?'':'s'}, {fmtNumber(c.chars)} characters{L?` (limits ${L.min_sentences} to ${L.max_sentences} sentences, ${L.min_chars} to ${L.max_chars} characters)`:''}. Every sentence is supported by its quote from the page.</>}
    {re&&<> The AI was asked once more because the first answer broke the {re.first?.rule==='sentence_count'?'sentence':'length'} limit ({fmtNumber(re.first?.sentences)} sentences, {fmtNumber(re.first?.chars)} characters); this is the rewrite{re.error?' (the re-ask failed, so this is the first answer)':''}.</>}
    {now&&now.ok===false&&<strong> Since it was proposed, it no longer passes: {String(now.rule||'').replace(/_/g,' ')}.</strong>}
    {pk&&<span data-l4-cd-flags> {(pk.flags||[]).length?<>Look at first: {(pk.flags||[]).map(f=>PACK_FLAG[f]||f).join('; ')}{Number(pk.same_words_on_other_courses)>0?` (${fmtNumber(pk.same_words_on_other_courses)} other)`:''}.</>:'No flag: nothing here asks for extra care, still check it against the page.'}{Number(pk.held_readings_this_decision_can_free)>0?` Deciding this lets up to ${fmtNumber(pk.held_readings_this_decision_can_free)} held readings of this university join the queue.`:''}</span>}
  </small></p>
}

// state for the Inbox: the summary of the pending course descriptions and the ready-first queue (the AER queue's pattern)
export function useCdQueue(on,pid){
  const[sum,setSum]=useState(null),[mode,setMode]=useState(''),[list,setList]=useState(null),[off,setOff]=useState(0),[err,setErr]=useState(''),[cap,setCap]=useState(null)
  const loadSum=()=>{if(!on){setSum(null);setCap(null);return}
    cdQueue('capacity').then(setCap).catch(()=>setCap(null));cdQueue('summary',{provider_id:pid||undefined,recheck:!!pid}).then(d=>{setCdLimits(d?.limits);setSum(d);setErr('')}).catch(e=>{setSum(null);setErr(plainError(e))})}
  const loadList=(o=off)=>{if(!on||!mode){setList(null);return}setList(null);(mode==='pack'?cdQueue('pack',{provider_id:pid||undefined,offset:o}):cdQueue('items',{provider_id:pid||undefined,offset:o,sample:mode==='sample'})).then(setList).catch(e=>{setList({items:[],total:0});setErr(plainError(e))})}
  useEffect(()=>{setMode('');setOff(0);loadSum()},[on,pid])
  useEffect(()=>{setOff(0);loadList(0)},[mode,on,pid])
  return{sum,cap,mode,setMode,list,off,setOff,loadSum,loadList,err}
}

export function CdPanel({q,showProvider}){
  const s=q.sum
  if(!s)return q.err?null:null
  const by=s.by_class||{},ready=Number(by.ready||0),fails=Number(by.fails_now||0),stale=Number(s.pending||0)-ready-fails
  if(!Number(s.pending)&&!Number(s.admitted_by_person)&&!Number(s.admitted_by_machine))return null
  return <div className="l4i-cd" data-l4-cd-summary>
    <p className="l4i-aer-sum"><small><strong>Course descriptions:</strong> {fmtNumber(s.pending)} waiting for a person · <strong>{fmtNumber(ready)} ready to decide</strong>{fails?` · ${fmtNumber(fails)} no longer pass the checks`:''}{stale>0?` · ${fmtNumber(stale)} stale (the course or its page changed)`:''}
      {s.provider_id?'':' (checks re-run for the oldest only)'} · admitted by a person {fmtNumber(s.admitted_by_person)}{Number(s.admitted_by_machine)>0?` · admitted by the machine rule ${fmtNumber(s.admitted_by_machine)}`:''} · published to the website {fmtNumber(s.published_to_the_website)}{Number(s.waiting_behind_provider_cap)?` · ${fmtNumber(s.waiting_behind_provider_cap)} more wait behind the first ten of their university`:''}. A reading waiting here is not admitted and not published.</small></p>
    {q.cap&&q.cap.pending!=null&&<p className="l4i-aer-sum" data-l4-cd-capacity><small><strong>Review capacity:</strong> about {fmtNumber(q.cap.minutes_an_item)} minute{Number(q.cap.minutes_an_item)===1?'':'s'} an item ({q.cap.pace_basis==='measured'?'measured':'Layer 4 default, not yet measured for descriptions'}) · {fmtNumber(q.cap.hours_to_clear_waiting)} reviewer hours for the {fmtNumber(q.cap.pending)} waiting{Number(q.cap.held_first_readings_behind_the_provider_cap)>0?`, ${fmtNumber(q.cap.hours_to_clear_waiting_and_held)} once the ${fmtNumber(q.cap.held_first_readings_behind_the_provider_cap)} held readings join`:''} · to clear within {fmtNumber(q.cap.target_days)} days: {fmtNumber(q.cap.items_a_day_needed_incl_arrivals)} decisions a day (about {fmtNumber(q.cap.reviewer_hours_a_day_needed)} hours), with {fmtNumber(q.cap.arriving_a_day)} arriving a day · decided in the last {fmtNumber(q.cap.window_days)} days: {fmtNumber(q.cap.decided_in_window)}{q.cap.back_pressure?.on?` · new readings ${q.cap.back_pressure.new_readings_paused?'paused':'run'} (limit ${fmtNumber(q.cap.back_pressure.global_max)})`:''}.</small></p>}
    {(ready>0||Number(s.pending)>0)&&<div className="l4i-view" role="group" aria-label="Order" data-l4-cd-order>
      <button type="button" className={q.mode==='ready'?'on':''} aria-pressed={q.mode==='ready'} onClick={()=>q.setMode(q.mode==='ready'?'':'ready')} data-l4-cd-ready>Ready to decide ({fmtNumber(ready)})</button>
      <button type="button" className={q.mode==='pack'?'on':''} aria-pressed={q.mode==='pack'} onClick={()=>q.setMode(q.mode==='pack'?'':'pack')} data-l4-cd-pack>Review pack (by university)</button>
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
      <small>{fmtNumber(items.length?q.off+1:q.off)}–{fmtNumber(q.off+items.length)} of {fmtNumber(l.total)}{q.mode==='sample'?' in the sample':q.mode==='pack'?' in the pack':' ready'}{q.mode==='pack'?', university by university':', oldest first'}</small>
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
    <p className="sl-sub" data-enrich-cd-measures>Four measures, kept apart: <strong>{fmtNumber(sum.proposed_in_layer4)}</strong> proposed (waiting in Layer 4) · <strong>{fmtNumber(sum.admitted_by_person)}</strong> admitted by a person{Number(sum.admitted_by_machine)>0&&<> · <strong>{fmtNumber(sum.admitted_by_machine)}</strong> admitted by the machine rule (a machine decision, recorded apart; never counted as a person&apos;s)</>} · <strong>{fmtNumber(sum.published_to_the_website)}</strong> published to the website · <strong>{fmtNumber(sum.admitted_without_a_person)}</strong> admitted without a person (stays 0 while a person must approve the first {fmtNumber(sum.review_first)} per university). {fmtNumber(sum.waiting_behind_provider_cap)} more readings wait behind a university&apos;s first waiting descriptions. An AI reading is never counted as admitted or published.</p>
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
      <p className="sl-sub">{fmtNumber(sample.selected)} selected: {fmtNumber(sample.approved)} approved{Number(sample.approved_by_machine)>0?` (not counting ${fmtNumber(sample.approved_by_machine)} approved by the machine rule)`:''}, {fmtNumber(sample.rejected)} rejected, {fmtNumber(sample.pending)} waiting for a person{sample.approval_share_of_decided!=null?`; approval share of those decided ${Math.round(100*Number(sample.approval_share_of_decided))}%`:''}. Rejections by reason: {Object.keys(sample.rejected_by_class||{}).length?Object.entries(sample.rejected_by_class).map(([k,n])=>`${k} ${n}`).join(', '):'none yet'}. Reviewer disagreement: {fmtNumber(sample.reviewer_disagreement?.passed_every_check_but_rejected)} passed every check but were rejected; {fmtNumber(sample.reviewer_disagreement?.approved_but_rules_now_fail)} approved but no longer pass the rules. Claim words present in {fmtNumber(sample.claim_support?.with_claim_words_in_quote)}; lowest sentence support {sample.claim_support?.lowest_sentence_support??'—'}.</p></div>}
    {err&&<small className="fr-error" role="alert">{err}</small>}
  </div>
}


// ---- s664 (CF-247 S1-Courses, Platform Admin 18 Nov 2026): "Why this is held & recommended action" on a Layer 4 course description card ----------
// Every hold reason of the machine rule cdesc-machine-v2 in plain English, with what to do. The raw rule code is never shown; the facts behind it are
// (how the page was matched and how firmly, whether every quote is on the page, the sentence count against the limit).
export const CD_HOLD={
  identity_margin_thin:{title:'The page match is not clear enough',why:'The page was found by an AI match, or another page scored almost as high, and the page itself does not prove the course by its own CRICOS or NZQA code or exact title.',action:'Open the official page. If it is this course\'s own page, approve as read; if it is another course or a shared page, reject (bad page / wrong course).'},
  binding_ambiguous:{title:'More than one page could be this course',why:'The course has more than one candidate page, so the platform has not settled which page is its own.',action:'Check the page against the course title and code, then approve as read or reject (bad page / wrong course).'},
  first_provider_sample:{title:'Waiting for the machine check',why:'This description has not been checked by the machine rule yet. It is admitted automatically when its own page proves the course and every sentence matches its quote.',action:'Nothing to do unless it stays here after the next run; then read the reason again.'},
  sentence_count_over_2:{title:'Longer than 1 to 2 sentences',why:'The description was written by the earlier reader and has more sentences than the limit now allows.',action:'Choose Re-read (1-2 sentences). The stored page is read again; nothing is marked bad.'},
  length:{title:'Longer than the limit',why:'The description has more characters than the limit now allows.',action:'Choose Re-read (1-2 sentences).'},
  boilerplate_detected:{title:'Marketing or claim wording',why:'A word the admission policy does not admit on its own (for example "accredited", "innovative" or "leading") is in the description.',action:'Choose Re-read (1-2 sentences); the reader leaves such words out. Approve as read only if the page itself supports the word.'},
  quote_mismatch:{title:'A sentence is not supported by its quote',why:'At least one sentence does not match the words it quotes from the stored page.',action:'Choose Re-read (1-2 sentences), or reject if the page is not about this course.'},
  evidence_moved:{title:'The page changed after it was read',why:'A newer copy of the course page was stored after this description was written.',action:'Choose Re-read (1-2 sentences) so the new copy is read.'},
  wrong_page_kind:{title:'Not a course overview page',why:'The page is an entry, fees, how-to-apply or structure page, or a university-wide page, so it does not describe this course.',action:'Reject (bad page / wrong course), then set the right page on the course record.'},
  duplicate:{title:'Same wording as another course',why:'Another course already holds, or is waiting with, almost the same words (often shared qualification wording).',action:'Check that the page is this course\'s own; approve as read only if the wording truly belongs to this course.'},
  rejected_before:{title:'A person refused this before',why:'A person rejected an earlier description for this course, this page or these words.',action:'Decide it yourself; the machine rule never overrides a person.'},
  other:{title:'Held by a check',why:'The machine rule did not admit it.',action:'Read the reason and the page, then decide.'}
}
// the machine rule's code (with the check_ / policy_ prefixes it records) to the explanation key above
export function cdHoldKey(code,d){
  const c=String(code||'')
  if(!c)return 'first_provider_sample'
  if(c==='identity_margin_thin'||c==='identity_not_allowed')return 'identity_margin_thin'
  if(c==='binding_ambiguous')return 'binding_ambiguous'
  if(c==='check_sentence_count')return 'sentence_count_over_2'
  if(c==='check_length')return 'length'
  if(c.startsWith('policy_')||c==='check_unsupported_claim'||c==='check_unsupported_marketing')return 'boilerplate_detected'
  if(/^check_(quote_not_on_page|unsupported_sentence|copied_sentence)$/.test(c)||c==='source_recheck_failed')return 'quote_mismatch'
  if(c==='evidence_moved'||c==='page_url_changed'||c==='reading_other_evidence')return 'evidence_moved'
  if(c==='wrong_page_kind')return 'wrong_page_kind'
  if(c.startsWith('duplicate_')||c==='check_duplicate_other_course')return 'duplicate'
  if(c.startsWith('rejected_before')||c==='withdrawn_awaiting_person')return 'rejected_before'
  return 'other'
}
const BASIS={cricos_code:'the course\'s own CRICOS code on the page',nzqa_code:'the course\'s own NZQA code on the page',exact_title:'the exact course title',degree_name:'the degree name only',title_level:'the title and level',field_award:'the field and award',adapter_title:'the adapter\'s title'}
const FOUND={ai_match:'an AI match',cricos_code_on_page:'its CRICOS code on the page'}
export function CdWhy({d}){
  const m=d?.machine||null,b=d?.binding||null,lim=d?.limits||{},key=cdHoldKey(m?.reason_code,d),h=CD_HOLD[key]||CD_HOLD.other
  const n=Array.isArray(d?.proposed?.sentences)?d.proposed.sentences.length:null,max=Number(lim.max_sentences)||2
  const score=b&&b.score!=null?Number(b.score):null,ru=b&&b.runner_up!=null?Number(b.runner_up):null
  const quoteOk=key!=='quote_mismatch'
  return <div className="l4i-cd-why" role="note" data-l4-cd-why={key}>
    <p><strong>Why this is held: {h.title}.</strong> {h.why}</p>
    <ul className="l4i-plain">
      <li data-l4-cd-why-match>Page match: {b?<>found by {FOUND[b.basis]||String(b.basis||'no recorded method').replace(/_/g,' ')}{score!=null?`, score ${score.toFixed(2)}`:''}{ru!=null?` against ${ru.toFixed(2)} for the next page`:''}; proved by {BASIS[b.identity_basis]||'no recorded proof'}.</>:'no bound page recorded.'}</li>
      <li data-l4-cd-why-quotes>Quote check: {quoteOk?'every sentence is on the stored page in the words it quotes.':'at least one sentence is not supported by its quote.'}</li>
      {n!=null&&<li data-l4-cd-why-count>Sentence count: {n} of at most {max}{n>max?' (over the limit)':''}.</li>}
    </ul>
    <p><strong>Recommended action:</strong> {h.action}</p>
  </div>
}
// the course description card's four decisions: university descriptions keep their two
export const CD_CHOICE_LABEL={approve:'Approve as read',reread:'Re-read (1-2 sentences)',approve_provider:'Approve all verified for provider',reject:'Reject (bad page / wrong course)'}
export const CD_CHOICE_ORDER=['approve','reread','approve_provider','reject']
export function cdChoices(choices,isCourse){
  const list=choices||[]
  if(!isCourse)return list.filter(c=>c.key!=='reread'&&c.key!=='approve_provider')
  return CD_CHOICE_ORDER.map(k=>list.find(c=>c.key===k)).filter(Boolean).map(c=>({...c,label:CD_CHOICE_LABEL[c.key]||c.label}))
}
