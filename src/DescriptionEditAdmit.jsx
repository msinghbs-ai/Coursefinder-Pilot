// CF-247 s802/s803 (Platform Admin 20 Nov 2026 05:52, chat S1-Build): inline Edit & Approve on a Layer 4 University or Course description card.
// The editable text starts as the machine candidate. Each sentence's verbatim quote and the official page (a link) stay beside it; the
// character, sentence and word counts and the word-list check update as the person types. Approve As-Is admits the candidate unchanged
// (admission_source machine_human_approved, every quote check as before). Save Edit & Admit admits the edited text as human input: it is
// checked again on the server, the description is locked by hand unless the box is cleared, and the edit is listed in Data & Governance ›
// Human Edits & Periodic Audit for review in six months (a setting). Both go through public.admin_layer4_inbox (decide, choice edit_approve).
import React,{useEffect,useState}from'react'
import{ExternalLink}from'lucide-react'
import{supabase}from'./lib/supabase'
import{Button}from'./ui-kit'
import{checkDescription,isEdited,stripBanned,holdReason,markBanned}from'./lib/description-check.js'
import{cdRailOf,plainHold}from'./lib/l4-rules.js'
import HelpButton from'./HelpDrawer' // S1-UX s827: the ? help drawer, on the hold banner (S1-RM-Design, 20 Nov 2026 13:07)

const rpc=async(action,args)=>{const{data,error}=await supabase.rpc('admin_layer4_inbox',{p_action:action,p_args:args||{}});if(error)throw new Error(error.message);return data||{}}
let RULES=null,RULES_P=null
export const descriptionRules=()=>{if(RULES)return Promise.resolve(RULES);if(!RULES_P)RULES_P=rpc('description_rules').then(r=>{RULES=r;return r}).catch(e=>{RULES_P=null;throw e});return RULES_P}

export function CheckLine({text,rules,label='Checks'}){
  if(!rules)return <p className="dea-checks" data-dea-checks><small>Reading the limits…</small></p>
  const c=checkDescription(text,rules)
  return <p className={`dea-checks${c.ok?' ok':' bad'}`} data-dea-checks={c.ok?'ok':'problems'}>
    <small><strong>{label}:</strong> <span data-dea-chars>{c.chars} characters</span> ({rules.min_chars}–{rules.max_chars}) · <span data-dea-sentences>{c.sentences} sentence{c.sentences===1?'':'s'}</span> ({rules.min_sentences}–{rules.max_sentences}) · <span data-dea-words>{c.words} words</span>
      {c.banned.length?<> · <em data-dea-banned>Not allowed: {c.banned.join(', ')}</em></>:<> · <span data-dea-banned-none>no word from the lists</span></>}
      {!c.ok&&<><br/><span data-dea-problems>{c.problems.join('; ')}</span></>}</small></p>
}

// s820 (Platform Admin 20 Nov 2026 10:21): the main hold reason in plain English at the top of the card; the machine rule's code under Technical detail
export function HoldBanner({it,candidate,rules,label=''}){
  const h=holdReason(it?.why,candidate,rules)
  const title=h.kind==='banned'?h.title:(label||cdRailOf(it)||h.title) // s839: the rule's plain name, never the machine code
  return <div className={`dea-hold dea-hold-${h.kind}`} role="note" data-dea-hold={h.kind}>
    <strong>Main hold reason: {title}{h.kind==='banned'&&h.words?.length?<> — {h.words.map((w,i)=><React.Fragment key={w}>{i?', ':''}<code data-dea-hold-word>{w}</code></React.Fragment>)}</>:null}</strong>
    <span className="dea-hold-help"><HelpButton topic="layer4" label="Help: deciding a held description"/></span>
    {it?.why&&<details className="dea-tech"><summary>Technical detail</summary><small data-dea-hold-code>{it.why}</small></details>}
  </div>
}

// s838 (Platform Admin 20 Nov 2026 14:40): the same amber Main hold reason banner on every other card (AER and the rest): the rule in plain English,
// the ? help and the machine reason under Technical detail. The card's own decisions stay as they are.
export function CardHold({it,label}){
  return <div className="dea-hold dea-hold-card" role="note" data-dea-hold="card" data-l4-hold>
    <strong>Main hold reason: {plainHold(label)}</strong>
    <span className="dea-hold-help"><HelpButton topic="layer4" label="Help: deciding a held item"/></span>
    {it?.why&&<details className="dea-tech"><summary>Technical detail</summary><p className="l4i-why" data-dea-hold-code>{it.why}</p></details>}
  </div>
}

// s821 (Platform Admin 20 Nov 2026 10:21): one action bar per description card. s838 (20 Nov 2026 14:40): Remove "word" & Admit sits under its cleaned-text
// preview, so the bar is three buttons in one row: Save Edit & Admit, Approve As-Is and Reject set apart on the right. Remove "word" & Admit (only when the candidate is held for banned
// words and the cleaned text passes every check), Save Edit & Admit (once the edited text passes), Approve As-Is (when nothing needs changing), and
// Reject, set apart (passed in as `reject`, the card's own Reject choice and its reason step). The Inbox no longer repeats Approve as read and Reject below.
export default function DescriptionEditAdmit({it,d,isCourse,rank,onDone,onCancel,reject=null,holdLabel=''}){
  const original=String(d.proposed?.description||''),held=!original.trim()
  const[text,setText]=useState(original),[lock,setLock]=useState(true),[reason,setReason]=useState(''),[busy,setBusy]=useState(''),[err,setErr]=useState(''),[rules,setRules]=useState(RULES)
  useEffect(()=>{descriptionRules().then(setRules).catch(e=>setErr(e.message))},[])
  const r=rules?.[isCourse?'course':'provider'],c=r?checkDescription(text,r):null,edited=isEdited(text,original)
  const sentences=Array.isArray(d.proposed?.sentences)?d.proposed.sentences:[],url=d.proposed?.source_url||d.source_url
  const banned=r?checkDescription(original,r).banned:[],strip=r&&banned.length?stripBanned(original,r.words):null
  const stripCheck=strip?.changed?checkDescription(strip.text,r):null,canStrip=!!(strip?.changed&&stripCheck?.ok&&!edited)
  const removeAdmit=async()=>{setBusy('strip');setErr('')
    try{const out=await rpc('decide',{kind:it.kind,ref:it.ref,choice:'edit_approve',value:strip.text,set_manual_lock:true,reason:`Removed banned word${strip.removed.length===1?'':'s'}: ${strip.removed.join(', ')}`});onDone?.(out)}catch(e){setErr(e.message)}finally{setBusy('')}}
  const save=async asIs=>{setBusy(asIs?'asis':'edit');setErr('')
    try{const out=await rpc('decide',{kind:it.kind,ref:it.ref,choice:'edit_approve',value:asIs?original:text.trim(),set_manual_lock:lock,reason:reason.trim()});onDone?.(out)}catch(e){setErr(e.message)}finally{setBusy('')}}
  const reasonOk=reason.trim().length>=5,low=rank<4
  return <div className="dea" data-dea={isCourse?'course':'provider'} data-dea-ref={it.ref}>
    {!held&&<HoldBanner it={it} candidate={original} rules={r} label={holdLabel}/>}
    {/* s838: the proposed text, each word from the lists marked in soft yellow */}
    {!held&&banned.length>0&&<div className="dea-proposed" data-dea-proposed><small>Proposed text</small>
      <p>{markBanned(original,r.words).map((x,i)=>x.word?<mark key={i} className="dea-ban" data-dea-ban-mark={x.word}>{x.text}</mark>:<React.Fragment key={i}>{x.text}</React.Fragment>)}</p></div>}
    {/* s838: the cleaned text directly above the primary Remove "word" & Admit (the action bar below keeps three buttons) */}
    {canStrip&&<div className="dea-strip" data-dea-strip><small>With {strip.removed.map(w=>`"${w}"`).join(', ')} removed (nothing else changed; every check passes):</small><p data-dea-strip-text>{strip.text}</p>
      <Button compact variant="primary" disabled={low||!!busy} onClick={removeAdmit} title="Admits the text with the banned word removed and locks it by hand" data-dea-remove-admit>{busy==='strip'?'Saving…':`Remove ${strip.removed.map(w=>`"${w}"`).join(', ')} & Admit`}</Button></div>}
    <p className="dea-head"><strong>Edit &amp; Approve</strong> <small>{held?'No machine text was proposed (the reading was held): write the description from the official page.':'Edit the text if it needs it, or approve it as read.'}</small></p>
    <label className="dea-field"><span>{isCourse?'Course description':'University description'}</span>
      <textarea value={text} onChange={e=>setText(e.target.value)} rows={isCourse?3:6} aria-label="Description to admit" data-dea-text/></label>
    <CheckLine text={text} rules={r}/>
    {sentences.length>0&&<details className="dea-quotes" open data-dea-quotes><summary>The page's own words ({sentences.length})</summary>
      <ol>{sentences.map((x,i)=><li key={i}><q>{x.quote}</q></li>)}</ol></details>}
    {d.proposed?.held_reason&&<p className="dea-held" data-dea-held><small>Held: {String(d.proposed.held_rule||'').replace(/_/g,' ')}{d.proposed.held_reason?` — ${d.proposed.held_reason}`:''}</small></p>}
    <p className="dea-src"><small>Official page: {url?<a href={url} target="_blank" rel="noreferrer" data-dea-source>{url} <ExternalLink size={11}/></a>:'none held'}</small></p>
    <label className="dea-lock"><input type="checkbox" checked={lock} onChange={e=>setLock(e.target.checked)} data-dea-lock/> Lock the description by hand when the edited text is admitted (automation will not change it; review due in {rules?.review_months||6} months)</label>
    <input value={reason} onChange={e=>setReason(e.target.value)} placeholder="Why (kept with the decision, at least 5 characters)" aria-label="Reason" data-dea-reason/>
    <div className="dea-actions" data-dea-bar>
      <Button compact variant="primary" disabled={low||!!busy||!edited||!c?.ok||!reasonOk} onClick={()=>save(false)} title={!edited?'Change the text first, or use Approve As-Is':!c?.ok?'The edited text does not pass the checks':''} data-dea-save>{busy==='edit'?'Saving…':'Save Edit & Admit'}</Button>
      <Button compact disabled={low||!!busy||held||edited||!reasonOk} onClick={()=>save(true)} title={held?'There is no machine text to approve':edited?'The text was changed: Save Edit & Admit, or undo the change':''} data-dea-asis>{busy==='asis'?'Saving…':'Approve As-Is'}</Button>
      {reject&&<span className="dea-bar-gap" aria-hidden="true"/>}{reject}
    </div>
    <p className="dea-minor">{edited&&!held&&<button type="button" className="dea-link" onClick={()=>setText(original)} data-dea-undo>Undo changes</button>}<button type="button" className="dea-link" onClick={onCancel} data-dea-close>Close the editor</button></p>
    {low&&<p className="dea-err"><small>Admitting a description needs a Pipeline Operator or above.</small></p>}
    {err&&<p className="dea-err" role="alert" data-dea-error>{err}</p>}
  </div>
}

// CF-247 s802 (Platform Admin 20 Nov 2026 05:52): universities whose last reading was held (no machine text, for example Torrens and AUT) and that
// hold no description; a Pipeline Operator opens one for writing from its stored page, and it then waits here as a University description card.
export function HeldUniversities({rank,onOpened}){
  const[q,setQ]=useState(''),[list,setList]=useState(null),[err,setErr]=useState(''),[busy,setBusy]=useState('')
  const load=()=>{setList(null);setErr('');rpc('description_held_list',{q,limit:50}).then(setList).catch(e=>setErr(e.message))}
  useEffect(()=>{if(rank>=4){const t=setTimeout(load,250);return()=>clearTimeout(t)}},[q,rank])
  if(rank<4)return null
  const open=async id=>{setBusy(id);setErr('');try{const r=await rpc('description_open_held',{provider_id:id});onOpened?.(r);load()}catch(e){setErr(e.message)}finally{setBusy('')}}
  return <details className="dea-held-list" data-dea-held-list><summary><strong>Held universities: open for writing</strong> <small>{list?`${list.total||0} with no description and a held reading`:''}</small></summary>
    <p><small>The reader held these universities' descriptions (for example the first sentence did not name the university, or a sentence was not on the page). Open one to write its description by hand from the stored page; it is admitted as human input and locked.</small></p>
    <input value={q} onChange={e=>setQ(e.target.value)} placeholder="Find a university…" aria-label="Find a held university" data-dea-held-q/>
    {err&&<p className="dea-err" role="alert">{err}</p>}
    {!list?<small>Reading…</small>:(list.items||[]).length===0?<small>None.</small>:<ul>{list.items.map(x=><li key={x.provider_id} data-dea-held-uni={x.name}>
      <span><strong>{x.name}</strong> <small>{x.country} · held: {String(x.rule||'no candidate').replace(/_/g,' ')}{x.source_url?<> · <a href={x.source_url} target="_blank" rel="noreferrer">page <ExternalLink size={10}/></a></>:null}</small></span>
      <Button compact disabled={!!busy} onClick={()=>open(x.provider_id)} data-dea-open-held>{busy===x.provider_id?'Opening…':'Open for writing'}</Button></li>)}</ul>}
  </details>
}
