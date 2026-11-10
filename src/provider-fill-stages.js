// CF-247 F-PDESC (Platform Admin decision 10 Nov 2026 19:47): what the Provider Fill Fields panel says about each provider, worked out from the server's status read only
// (public.admin_provider_description_run_v1 provider_status). Nothing here stores or decides anything: it puts the durable stages of a provider's description in plain words,
// so closing the browser loses nothing and no stage is painted as done unless the server says it is.
import { humanLabel } from './ui-kit'

const list = v => (Array.isArray(v) ? v : [])

// the exact code of a machine decision, in plain words (the code itself is always shown beside the words)
const CODE_WORDS = {
  refused_word: w => `a word the automatic text rule does not admit ("${w}")`,
  figure: w => (w === 'percentage' ? 'a percentage the automatic text rule does not admit' : `a figure the automatic text rule does not admit ("${w}")`),
  entity_encoded: () => 'web-page markup left in the wording',
}
const RULE_WORDS = {
  validation_not_about_page: 'the page is not the provider\'s own About or Overview page',
  validation_sentence_count: 'the number of sentences is outside the set range',
  validation_length: 'the length is outside the set range',
  validation_quote_not_on_page: 'a sentence\'s quote was not found on the page',
  validation_duplicate_other_provider: 'the wording is the same as another provider\'s description',
  identity_changed_since_read: 'the provider\'s identity record changed since the page was read',
  evidence_lineage_changed: 'the stored page changed since it was read',
  description_already_held: 'a description is already held',
  before_value_not_empty: 'a description is already held',
  manual_lock: 'a person has locked the description',
  prior_human_rejection: 'a person rejected an earlier description',
  machine_admission_off: 'automatic admission is switched off',
  provider_not_live: 'the provider is not active and published',
  out_of_scope: 'the provider is outside the description reader\'s scope',
  name_not_clean: 'a provider name is a placeholder or too short to prove identity',
  withdrawn_awaiting_review: 'an earlier machine description was withdrawn and a person decides the next one',
  description_cleared_after_admission: 'an admitted description was cleared by hand, so a person decides the next one',
  upgrade_too_short_or_unchanged: 'the page gives no fuller description than the one held',
  legacy_proposal_name_not_in_quote: 'the provider\'s name does not appear in a quote',
}
const SUBSET_WORDS = {
  every_sentence_refused: 'every sentence was refused, so none could be kept',
  no_sentence_to_leave_out: 'no single sentence caused the refusal',
  name_not_in_remaining_quotes: 'the provider\'s name is not in the quotes that remain',
  remainder_validation_sentence_count: 'too few sentences remain once the refused ones are left out',
  remainder_validation_length: 'what remains is too short or too long',
  remainder_validation_duplicate_other_provider: 'what remains matches another provider\'s description',
  remainder_validation_not_about_page: 'the page is not the provider\'s own About page',
  remainder_manual_lock: 'a person has locked the description',
  remainder_prior_human_rejection: 'a person rejected an earlier description',
}

/** The code inside the brackets of a ledger reason, e.g. "refused_word:campus", or '' when there is none. */
export function codeOf(reason) {
  const m = /\(([^)]+)\)/.exec(String(reason ?? ''))
  return m ? m[1] : ''
}
/** A machine decline in plain words. Returns { code, words }. */
export function declineWords(machine) {
  const code = codeOf(machine?.reason)
  const [head, tail] = String(code).split(':')
  if (CODE_WORDS[head]) return { code, words: CODE_WORDS[head](tail ?? '') }
  if (RULE_WORDS[code]) return { code, words: RULE_WORDS[code] }
  if (code.startsWith('identity_')) return { code, words: 'the provider\'s identity needs a person to confirm it' }
  return { code, words: code ? humanLabel(code).toLowerCase() : 'the automatic rule did not admit it' }
}
export function subsetWords(result) {
  if (!result) return ''
  return SUBSET_WORDS[result] || (String(result).startsWith('remainder_') ? `what remains does not pass the automatic rule (${result.replace('remainder_', '')})` : humanLabel(result).toLowerCase())
}

// what the run left behind when it was parked, in plain words, grouped as the Platform Admin asked to see them apart
export const DISPATCH = {
  job_not_allowlisted: { kind: 'allowlist', words: 'Run Now is not switched on for this reader (the allowlist is off). The saved task is kept and the scheduled reader picks it up.' },
  job_not_catalogued: { kind: 'allowlist', words: 'The reader is not catalogued for Run Now. The saved task is kept.' },
  job_paused: { kind: 'paused', words: 'The reader is paused. The saved task is kept and resumes when it is switched on.' },
  reader_off: { kind: 'paused', words: 'The reader is switched off. The saved task is kept and resumes when it is switched on.' },
  ai_refused: { kind: 'cap', words: 'AI spending is not allowed right now (a spending guard or the approved model). The saved task is kept.' },
  ai_ceiling: { kind: 'cap', words: 'The approved AI spending limit for provider descriptions is reached. The saved task is kept; nothing more is spent.' },
  review_full: { kind: 'policy', words: 'The Layer 4 review queue for provider descriptions is full, so a person must decide some waiting items first. The saved task is kept.' },
  selection_changed_before_run: { kind: 'none', words: 'The evidence changed between the preview and the run, so nothing was started. Run it again.' },
  reader_dispatch_failed: { kind: 'error', words: 'The reader could not be started just now. The saved task is kept and the scheduled reader resumes it.' },
}
// the reasons the governed selection gives for a provider it will not read now
export const SELECTION = {
  existing_work: { kind: 'in_progress', words: 'A reading is already queued, in progress or waiting for a decision.' },
  pending: { kind: 'in_progress', words: 'A reading is already waiting for a decision.' },
  retry_wait: { kind: 'wait', words: 'A recent read failed and the reader waits before trying again.' },
  policy_retry_parked: { kind: 'wait', words: 'A policy hold is parked until the rule or the evidence changes.' },
  review_capacity_parked: { kind: 'policy', words: 'The Layer 4 review queue is full, so a person must decide some waiting items first.' },
  cost_reservation_uncertain: { kind: 'wait', words: 'An earlier paid call is being settled; the reader tries again after that.' },
  dead_letter_requires_retry: { kind: 'wait', words: 'Earlier tries failed; the reader needs a retry decision.' },
  no_verified_stored_source: { kind: 'source', words: 'There is no stored official About page for this provider yet.' },
  unchanged_unsuitable_evidence: { kind: 'source', words: 'The official page was read and does not give a suitable description; it is read again only when it changes.' },
  recovery_knowledge_unchanged_failure: { kind: 'source', words: 'The same failure happened on the same page; it is read again only when the page changes.' },
  description_current: { kind: 'up_to_date', words: 'The description is current under the recheck window.' },
  description_already_present: { kind: 'up_to_date', words: 'A description is already held.' },
  manual_description: { kind: 'up_to_date', words: 'A person wrote the description.' },
  manual_description_changed: { kind: 'up_to_date', words: 'A person changed the description.' },
  manual_lock: { kind: 'locked', words: 'Locked: a person has locked this provider\'s description. It is never overwritten.' },
  not_a_basic_registry_profile: { kind: 'up_to_date', words: 'This is not a basic registry description.' },
  upgrade_switched_off: { kind: 'policy', words: 'Upgrade is switched off: a Platform Admin policy decision. Nothing is queued until a Platform Admin switches it on.' },
  not_selected_by_governed_policy: { kind: 'policy', words: 'The governed selection did not offer this provider (scope, publication or type policy).' },
  provider_inactive: { kind: 'policy', words: 'The provider is not active.' },
  provider_not_published: { kind: 'policy', words: 'The provider is not published.' },
  invalid_description: { kind: 'wait', words: 'The description held does not pass the rules and is queued for a fresh read.' },
  description_lost: { kind: 'wait', words: 'The description was lost and is queued for a fresh read.' },
  unknown_provider: { kind: 'none', words: 'This provider was not found.' },
}
export const selectionWords = code => SELECTION[code]?.words || (code ? `The platform gave this reason: ${humanLabel(code).toLowerCase()}.` : 'The platform gave no reason.')

/** Is a thrown error a refusal of the person's role? */
export const isPermission = e => /42501|role (cannot|required)|permission denied|curator role|not allowed/i.test(`${e?.code ?? ''} ${e?.message ?? e ?? ''}`)

/** Where a provider stands, as ONE of: locked, up_to_date, in_progress, recovering, person, held, extractable. */
export function classify(p) {
  const reader = p?.reader || {}
  const m = p?.machine
  const cur = m?.current_reading !== false
  if (p?.locked) return 'locked'
  if (['queued', 'reading'].includes(reader.state)) return 'in_progress'
  if (p?.l4_status === 'pending' || (reader.state === 'proposed' && !p?.description_present)) {
    if (m?.outcome === 'declined' && cur) {
      const [head] = String(codeOf(m.reason)).split(':')
      // the text rule declined words or figures and the recovery has not looked at it yet: the platform retries it by itself
      if (['refused_word', 'figure', 'entity_encoded'].includes(head) && !m.subset_result) return 'recovering'
      return 'person'
    }
    if (m?.outcome === 'admitted' && cur) return 'up_to_date'
    return m ? 'person' : 'recovering' // a proposal the machine rule has not looked at yet is looked at by the next settlement
  }
  if (p?.description_present && p?.quality_class !== 'basic_registry') return 'up_to_date'
  if (reader.state === 'held' && !p?.description_present) return 'held'
  return 'extractable'
}

/** The fill mode the server should be asked for, chosen from the provider's own state (never by the person). */
export const fillModeOf = p => (p?.description_present ? 'upgrade_basic' : 'missing')

/** The durable stages of one provider, each { key, label, state: done|pending|blocked|none, text, code? }. */
export function stagesOf(p) {
  const reader = p?.reader || {}
  const m = p?.machine
  const cur = m?.current_reading !== false
  const out = []
  // 1 source
  const via = reader.read_via
  const fresh = ['firecrawl', 'direct'].includes(via)
  if (p?.source_url) out.push({ key: 'source', label: 'Official source', state: 'done', url: p.source_url, text: via ? (fresh ? 'Read fresh from the official page' : 'Stored official evidence reused (no new page read)') : 'Official page identified', at: reader.source_captured_at })
  else out.push({ key: 'source', label: 'Official source', state: p?.hold_reason && /source|page|evidence/i.test(p.hold_reason) ? 'blocked' : 'pending', text: 'No official About page identified yet' })
  // 2 AI extraction
  if (reader.state === 'reading') out.push({ key: 'ai', label: 'AI extraction', state: 'pending', text: 'Reading now' })
  else if (reader.state === 'queued') out.push({ key: 'ai', label: 'AI extraction', state: 'pending', text: 'Queued for the reader' })
  else if (['proposed', 'admitted', 'superseded'].includes(reader.state)) out.push({ key: 'ai', label: 'AI extraction', state: 'done', text: `${reader.model ? `Proposed by ${reader.model}` : 'Description proposed'}${Number(reader.ai_calls) > 0 ? ` (${reader.ai_calls} call${Number(reader.ai_calls) === 1 ? '' : 's'})` : ' from stored evidence'}` })
  else if (reader.state === 'held') out.push({ key: 'ai', label: 'AI extraction', state: 'blocked', text: 'Nothing could be proposed' })
  else out.push({ key: 'ai', label: 'AI extraction', state: 'none', text: 'Not run yet' })
  // 3 validation (the exact machine code, in words)
  if (m && cur && m.outcome === 'declined') {
    const d = declineWords(m)
    const sub = m.subset_result ? ` Leaving the refused sentences out did not help: ${subsetWords(m.subset_result)}.` : ''
    out.push({ key: 'validation', label: 'Automatic checks', state: 'blocked', text: `Did not pass: ${d.words}.${sub}`, code: d.code })
  } else if (m && cur && m.outcome === 'admitted') {
    const s = m.subset
    out.push({ key: 'validation', label: 'Automatic checks', state: 'done', text: s ? `Passed after leaving out ${list(s.dropped).length} of ${s.given_sentences} sentences the rule refused (${list(s.dropped).map(x => x.code).join(', ')}). Nothing was reworded or added.` : 'Passed every check', code: s ? list(s.dropped).map(x => x.code).join(', ') : undefined })
  } else if (reader.state === 'held') {
    out.push({ key: 'validation', label: 'Automatic checks', state: 'blocked', text: `Held: ${p?.hold_reason || humanLabel(reader.rule) || 'no reason recorded'}`, code: reader.rule || undefined })
  } else if (reader.state === 'proposed') out.push({ key: 'validation', label: 'Automatic checks', state: 'pending', text: 'Not yet checked by the automatic rule' })
  else out.push({ key: 'validation', label: 'Automatic checks', state: 'none', text: 'Not checked yet' })
  // 4 decision
  const cls = classify(p)
  if (m && cur && m.outcome === 'admitted') out.push({ key: 'decision', label: 'Decision', state: 'done', text: 'Admitted by the machine rule (not a person\'s decision)' })
  else if (p?.admitted_at && p?.admitted_by === 'layer4') out.push({ key: 'decision', label: 'Decision', state: 'done', text: 'Admitted by a Layer 4 decision' })
  else if (cls === 'recovering') out.push({ key: 'decision', label: 'Decision', state: 'pending', text: 'Technical recovery: the platform checks this reading again by itself and leaves out only the sentences the rule refuses. No person is needed yet.' })
  else if (cls === 'person') out.push({ key: 'decision', label: 'Decision', state: 'blocked', text: 'A person decides in Layer 4 (the automatic rule cannot admit this reading).' })
  else out.push({ key: 'decision', label: 'Decision', state: 'none', text: p?.l4_status ? `Layer 4: ${humanLabel(p.l4_status)}` : 'No decision needed yet' })
  // 5 canonical
  out.push({ key: 'canonical', label: 'Catalogue description', state: p?.description_present ? 'done' : 'none', text: p?.description_present ? `Held${p.admitted_at ? `, admitted ${p.admitted_at}` : ''}${p.quality_class === 'basic_registry' ? ' (basic registry profile)' : ''}` : 'No description held' })
  return out
}

/** What happens next, in one sentence, for the person looking at the provider. */
export function nextAction(p, caps) {
  const reader = p?.reader || {}
  switch (classify(p)) {
    case 'locked': return 'Nothing: a person has locked the description. Only a person can unlock it.'
    case 'in_progress': return `Wait: the reader has it (${humanLabel(reader.state).toLowerCase()}). Open this panel again to see the result; nothing is lost if you close it.`
    case 'recovering': return 'Wait: the platform re-checks this reading every hour and admits the sentences that pass. You can come back to see the result.'
    case 'person': return 'Open Layer 4 and decide this description.'
    case 'held': return p?.next_retry_at ? `The reader tries again ${p.next_retry_at}. Extract now to ask for a new read sooner.` : 'Extract now to ask for a new read.'
    case 'up_to_date': return p?.website_publication === 'verified' || p?.website_publication === 'not_applicable' ? 'Nothing: the description is held and up to date.' : 'Nothing to extract. Use Details to check what the Website and Zoho return.'
    default: return caps && caps.enabled === false ? 'The reader is switched off; the request is saved and resumes when it is on.' : 'Extract now: the official page is read (stored evidence is reused), checked, and queued with the governed reader.'
  }
}

// reasons that are a refusal to spend or a policy wait, never an attempt at the source (the record function puts the read back with its try returned)
const NOT_AN_ATTEMPT = new Set(['ai_budget_refused', 'ai_ceiling', 'ai_daily_guard', 'ai_refused', 'model_pricing_unavailable', 'invalid_model_pricing', 'unrecognised_pricing_component', 'existing_cost_reservation_uncertain', 'source_identity_proof_missing', 'review_full'])

/** The outcome for the description field (the only field the reader produces), from the read's own state, rule, tries, next try, how it was read and its evidence. Returns { kind, title, text }. */
export function fieldOutcome(p) {
  const r = p?.reader || {}
  const src = p?.source_url ? `Source examined: ${p.source_url}${r.read_via ? (['firecrawl', 'direct'].includes(r.read_via) ? ' (read fresh)' : ' (stored evidence reused, not read again)') : ''}${p.evidence_id ? `; evidence ${p.evidence_id}` : ''}.` : 'No source examined yet.'
  const tries = Number(r.tries) > 0 ? ` Attempts counted: ${r.tries}.` : ''
  const next = p?.next_retry_at ? ` Next try: ${p.next_retry_at}.` : ''
  const m = p?.machine
  if (p?.description_present && r.state === 'admitted') return { kind: 'found', title: 'Found and admitted', text: `${src}${p.quality_class === 'basic_registry' ? ' This is a basic registry description, marked with its registry provenance.' : ''}` }
  if (['proposed'].includes(r.state)) return { kind: 'found', title: m?.outcome === 'admitted' ? 'Found and admitted by the machine rule' : 'Found, not yet admitted', text: src }
  if (r.state === 'dead_letter') return { kind: 'technical', title: 'Technical failures used every try', text: `${src}${tries} The reader needs a retry decision.${r.reason ? ` Last failure: ${r.reason}` : ''}` }
  if (r.state === 'queued' && NOT_AN_ATTEMPT.has(r.rule)) return { kind: 'not_attempt', title: 'Not an attempt: waiting for the AI budget or policy', text: `No page was judged and no try was used (${humanLabel(r.rule).toLowerCase()}).${next}` }
  if (r.state === 'queued' && r.rule === 'retry') return { kind: 'technical', title: 'Technical failure: it will be tried again', text: `${src}${tries}${next}${r.reason ? ` Failure: ${r.reason}` : ''}` }
  if (r.state === 'queued' || r.state === 'reading') return { kind: 'working', title: r.state === 'reading' ? 'Reading now' : 'Queued for the reader', text: `${src}${tries}${next}` }
  if (r.state === 'held') {
    const h = heldKind(r)
    return { kind: h.kind, title: h.title, text: `${p?.source_url ? src : ''}${tries} ${h.text}${r.reason ? ` (${r.reason})` : ''}${next}${h.kind === 'not_found' ? ' An unchanged page is not read again until the page changes or the next try is due.' : ''}`.replace(/\s+/g, ' ').trim() }
  }
  return { kind: 'none', title: 'Not read yet', text: src }
}

// the live held rules, by what they mean (counts of 10 Nov 2026 in the comments are for reading only)
const NOT_ATTEMPTED = new Set(['insufficient_verified_facts', 'home_not_read', 'about_not_read']) // 472, 104, 25: no page was read
const SOURCE_UNAVAILABLE = new Set(['no_about_page', 'not_about_page', 'robots_disallowed', 'wrong_host']) // no About page found on the provider's own site, a page that is not an About page, robots.txt, a host that is not the provider's
const IDENTITY = new Set(['provider_name_not_proved', 'provider_name_conflict', 'provider_host_conflict', 'provider_subunit_source']) // the page does not prove it is the provider's own
const NOT_STATED = new Set(['not_stated', 'no_about_page'])

/** What a held read means. 'Tried, not found' only for a real read (read_via and content_hash exist) whose rule says the page does not describe the institution. */
export function heldKind(r) {
  const rule = String(r?.rule ?? '')
  const real = Boolean(r?.read_via) && Boolean(r?.content_hash)
  if (/^machine_declined/.test(rule)) return { kind: 'person', title: 'Held for a person or policy', text: 'The automatic rule did not admit the reading; a person decides in Layer 4, or the platform recovers it by leaving out the refused sentences.' }
  if (NOT_ATTEMPTED.has(rule)) return { kind: 'not_attempted', title: 'Not attempted', text: rule === 'insufficient_verified_facts' ? 'The register holds too few verified facts to find this provider\'s page, so no page was read.' : 'The provider\'s page could not be reached by an earlier step, so no page was read.' }
  if (IDENTITY.has(rule)) return { kind: 'identity', title: 'Held: identity or host not proved', text: real ? 'A page was read but it does not prove it is this provider\'s own page.' : 'The page found does not belong to this provider\'s own site.' }
  if (NOT_STATED.has(rule) && real) return { kind: 'not_found', title: 'Tried, not found', text: 'The official page was read and does not describe the institution.' }
  if (SOURCE_UNAVAILABLE.has(rule) || !real) return { kind: 'source_unavailable', title: 'Source unavailable', text: 'No usable official page could be read (' + (rule ? rule.replace(/_/g, ' ') : 'no reason recorded') + '); no description was judged.' }
  return { kind: 'insufficient', title: 'Insufficient or ambiguous evidence', text: 'The page was read but what it says did not pass the checks (' + (rule ? rule.replace(/_/g, ' ') : 'no reason recorded') + ').' }
}
