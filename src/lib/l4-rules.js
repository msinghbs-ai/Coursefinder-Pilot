// CF-247 s837 and s838 (Platform Admin 20 Nov 2026 14:40, S1-UI-Parity; mockup s820-s827): pure helpers (no React) for Layer 4 Review's default view,
// "Waiting, grouped by rule" with one focused card. The groups come from the server across the whole queue of one kind (public.admin_layer4_inbox
// rule_groups, security.layer4_rule_groups_v1, migration 20261120145000); these helpers only name them in plain English and order the queues.
// Shared by src/Layer4Focus.jsx, src/DescriptionEditAdmit.jsx (CardHold) and the s837/s838 spec.

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
export function groupLabel(g){const k=String(g?.key||'')
  if(k.startsWith('cd:'))return CD_RAIL[k.slice(3)]||CD_RAIL.other
  if(k.startsWith('aer:'))return g?.label||AER_RAIL[k.slice(4)]||prettyCode(k.slice(4))
  return g?.label||firstSentence(k.slice(k.indexOf(':')+1))||'Held by a check'}

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
  return gs.flatMap(g=>g.refs||[])}
