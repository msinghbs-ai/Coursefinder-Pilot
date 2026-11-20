// CF-247 s837 and s838 (Platform Admin 20 Nov 2026 14:40, S1-UI-Parity; mockup s820-s827): pure helpers (no React) for Layer 4 Review's default view,
// "Waiting, grouped by rule" with one focused card. The groups come from the server across the whole queue of one kind (public.admin_layer4_inbox
// rule_groups, security.layer4_rule_groups_v1, migration 20261120145000); these helpers only name them in plain English and order the queues.
// Shared by src/Layer4Focus.jsx, src/DescriptionEditAdmit.jsx (CardHold, HoldBanner) and the s837/s838/s839 specs.
import{cdHoldKey}from'./cdesc-hold.js'

// course and university descriptions: the rail's short names for the hold codes (src/lib/cdesc-hold.js keeps the full explanations)
export const CD_RAIL={
  banned_word:'Contains a banned word',
  identity_margin_thin:'Page match not clear enough',
  binding_ambiguous:'More than one page could be this course',
  length:'Longer than the limit',
  sentence_count_over_2:'Longer than 1 to 2 sentences',
  duplicate:'Same wording as another course',
  quote_mismatch:'A sentence is not on its page',
  boilerplate_detected:'Marketing or claim wording',
  evidence_moved:'The page changed after it was read',
  wrong_page_kind:'Not a course overview page',
  rejected_before:'A person refused this before',
  first_provider_sample:'Waiting for the machine check',
  other:'Held by a check'
}
// AER: S1-AER's plain labels (security.layer4_aer_hold_reasons_v1), for cards shown outside the rail
export const AER_RAIL={
  gate_incomplete:'Completeness gate (partial table read)',
  audit_sample:'Audit sample (a person checks it)',
  all_rows_held:'All rows held (every row fails a row rule)',
  matrix_first_run:'Provider matrix, first run',
  matrix_change:'Provider matrix, change of an admitted table',
  no_bound_page:'No stored page bound',
  identity_not_admitted:"Page identity (the stored page is not proven to be this course's)"
}
const prettyCode=c=>{const s=String(c||'').replace(/_/g,' ').trim();return s?s[0].toUpperCase()+s.slice(1):'Held by a check'}
export const firstSentence=why=>String(why||'').trim().split(/(?<=[.;])\s+/)[0].replace(/[.;:]+$/,'').trim()

/** The plain name of one rule group from the server (key cd:<code>, aer:<code> or <kind>:<first sentence>). */
export function groupLabel(g){const k=String(g?.key||'').replace(/^sys~/,'')
  if(k.startsWith('cd:'))return CD_RAIL[k.slice(3)]||CD_RAIL.other
  if(k.startsWith('aer:')||k.startsWith('aerb:')){const c=k.slice(k.indexOf(':')+1);return g?.label||AER_RAIL[c]||prettyCode(c)}
  return plainHold(g?.label||firstSentence(k.slice(k.indexOf(':')+1)))}  // s873: plain English, codes to words

/** The main hold reason of one card in plain English (the rule group's name when the card is shown from a group). */
export function holdLabelOf(it,groupName){if(groupName)return groupName
  const why=String(it?.why||'')
  if(it?.kind==='aer_review'){const c=/did not admit this: ([a-z_]+)/.exec(why)?.[1];return c?(AER_RAIL[c]||prettyCode(c)):firstSentence(why)||'Held by a check'}
  return firstSentence(why)||'Held by a check'}

/** A group whose records may be decided as one batch: only course and university descriptions held for a banned word, each admitted with the word
 * removed (one decision per record, each with its reason). AER and every other group is previewed and worked card by card (S1-AER s831: no bulk approve). */
export const batchAdmits=g=>String(g?.key||'')==='cd:banned_word'

/** The queue a reviewer starts on: descriptions when any wait, else the largest built-in kind with waiting items. */
export function defaultKind(byKind,kinds){const n=k=>Number(byKind?.[k]?.n)||0
  if(n('provider_description')>0)return 'provider_description'
  const ks=Object.keys(byKind||{}).filter(k=>n(k)>0).sort((a,b)=>n(b)-n(a)||((kinds?.[a]?.order||99)-(kinds?.[b]?.order||99)))
  return ks[0]||''}

/** The refs of the chosen group, or of every group in order ("All in this queue"), oldest first within each group. */
export function refsOf(groups,key){const gs=Array.isArray(groups)?groups:[]
  if(key)return (gs.find(g=>g.key===key)?.refs)||[]
  return [...gs.filter(g=>!isRecoveryGroup(g)),...gs.filter(isRecoveryGroup)].flatMap(g=>g.refs||[])}  // s872: human action first, system queues last

/** s839 (20 Nov 2026): the rail name of a course description card's own hold code, so the card's Main hold reason is plain English in every view
 * (null when the card carries no known code, for example a university description, whose own reason wording is kept). */
export function cdRailOf(it){const d=it?.detail||{},code=d?.machine?.reason_code??d?.proposed?.held_rule
  if(!code)return null
  const k=code==='policy_refused_word'?'banned_word':cdHoldKey(code,d)
  return k==='other'?null:CD_RAIL[k]||null}

// CF-247 s870 (Platform Admin 20 Nov 2026 16:28): AER items the platform files under technical recovery (group B) are kept apart from the items a
// reviewer decides: the server's rule groups key them aerb:<code> (security.layer4_rule_groups_v1, migration 20261120145500).
export const isRecoveryGroup=g=>/^(aerb:|sys~)/.test(String(g?.key||''))||g?.recovery===true
/** A recovery group's batch: re-read from the stored copy ($0), or queue a stored-page fetch when no page is stored. */
export const batchRereads=g=>isRecoveryGroup(g)
/** One AER card's recovery action from its server check (rule_group_items reread): re-read, queue a fetch, or nothing. */
export function rereadAction(it){const v=it?.reread?.verdict
  if(v==='rereadable')return{key:'aer_det_reread',label:'Re-read from stored copy ($0)',why:'The stale partial read is replaced: the stored copy is read again by the deterministic reader (no AI, no Firecrawl), and its result goes through the same machine rule and Layer 4.'}
  if(v==='no_stored_page')return{key:'aer_page_fetch',label:'Queue stored-page fetch',why:'No page of this course is stored. The course goes on the Course page needed list; the search lane finds and stores its page under its own daily share.'}
  return null}
export const REREAD_SKIP={not_waiting:'no longer waiting',not_a_course_read:'an entry matrix (decided by the Platform Admin)',already_deterministic:'already read by the deterministic reader',
  not_technical_recovery:'waiting for a reviewer',audit_sample:'an audit sample (a person checks it)',locked:'locked by hand',course_not_active:'course not active',no_stored_page:'no stored page'}

// ---------- CF-247 s872 to s874 (Platform Admin 20 Nov 2026 17:13): one card contract for every Layer 4 queue ----------
/** The 19 Layer 4 queues (built-in kinds, in their Inbox order) the card contract and its CI test cover. */
export const L4_QUEUES=['course_link','held_scholarship','website_needed','pages_not_found','too_few_pages','nothing_ready','central_to_approve','onboarding_failed','site_down',
  'not_offered','fee_check','counsellor_report','not_on_site','provider_departure','no_page_first_run','conjoint_first_run','aer_review','provider_description','course_page_needed']
/** A reason in plain English: machine-rule prefixes, internal codes (snake_case, D-R3 style) and version tags leave the headline; the full text stays under Technical detail. */
export function plainHold(text){let t=String(text||'').trim()
  t=t.replace(/^Machine rule [\w.-]+ did not admit this:\s*/i,'').replace(/\b[A-Z]-[A-Z]?\d+\b/g,'').replace(/\b[a-z]+(?:_[a-z0-9]+)+\b/g,m=>m.replace(/_/g,' ')).replace(/\b[a-z-]+-v\d+(?:\.\d+)*\b/g,'')
  t=t.replace(/\(\s*\)/g,'').replace(/\s{2,}/g,' ').replace(/\s+([,.;:])/g,'$1').replace(/^[\s,;:.-]+/,'').trim()
  return t?t[0].toUpperCase()+t.slice(1):'Held by a check'}
/** The role of one decision in the standard action bar: admit (primary), edit (the person supplies a value: Save Edit & Admit), re-categorise, or set aside on the right. */
const INPUT=new Set(['url','text','provider','scholarship','courses','rows'])
export function choiceRole(c){const k=String(c?.key||'')
  if(/^(reject|refuse|archive|archive_course|dismiss|no_page|no_courses|no_locality|not_stated|closed|release)$/.test(k))return 'aside'
  if(/^(not_international|not_scholarship|duplicate|merged|cricos_only|report_not_changed|not_confirmed|reject_evidence)$/.test(k))return 'recategorise'
  if(INPUT.has(c?.input))return 'edit'
  return 'primary'}
const ROLE_ORDER={primary:0,edit:1,recategorise:2,aside:3}
export const orderChoices=list=>[...(list||[])].map((c,i)=>({c,i,r:choiceRole(c)})).sort((a,b)=>ROLE_ORDER[a.r]-ROLE_ORDER[b.r]||a.i-b.i).map(x=>({...x.c,role:x.r}))
/** Queues whose records are inspected in a batch but decided one at a time (as Grid › Clusters): entry requirements (the Platform Admin, A3), departures,
 * descriptions (each text is read) and every registered kind. */
const SETTLE_NEVER=new Set(['aer_review','provider_departure','provider_description','intervention','campus_locality','boost_study_load','scholarship_course_links'])
/** The decisions one batch may settle in a queue: no per-record value, no link away, not an approval of entry requirements or descriptions. */
export function settleChoices(kind,choices){if(SETTLE_NEVER.has(kind))return[]
  return (choices||[]).filter(c=>!c.link&&!c.input&&!c.editor)}
