// CF-247 s931 (Decision 279; spec admin docs/design/2026-11-21-layer4-human-ui-and-guide-spec.md §6): why a value is blank, for logged-in users.
// One pure function gives the state of an empty field from what the record already holds; the FieldGap pill (src/ui-kit.jsx) draws it.
// Precedence (first match wins): In Layer 4 review > University-wide rule applies > No official website / course URL on file > Not stated on
// institution page; otherwise "—" with the existing empty reason label (EMPTY_REASON_LABELS), never a bare blank.
import { EMPTY_REASON_LABELS } from '../catalogue-columns.js'

export const GAP_STATES = {
  in_review: { label: n => `In Layer 4 review (${n} waiting)`, tone: 'info', tip: 'A reviewer is checking this value.' },
  university_wide: { label: () => 'University-wide rule applies', tone: 'violet', tip: 'The course has no value of its own; the university-wide value covers it.' },
  no_url: { label: () => 'No official website / course URL on file', tone: 'warning', tip: 'Nothing can be read because no official address is held.' },
  not_stated: { label: () => 'Not stated on institution page', tone: 'neutral', tip: 'The page was read and does not state it.' },
  none: { label: () => '—', tone: 'neutral', tip: '' },
}

/** The state of one empty field. `record` carries what the screen already has: review (waiting Layer 4 items for this field), universityWide,
 * url (the official address held), emptyReason (empty_reason_code), valueState (the field's value_state) and notStated (a read found nothing). */
export function gapStateOf(field, record = {}) {
  const r = record || {}
  const n = Number(r.review) || 0
  if (n > 0) return { state: 'in_review', count: n, field }
  if (r.universityWide) return { state: 'university_wide', field }
  const noAddress = r.url === null || r.url === '' || r.valueState === 'source_missing' || (r.emptyReason === 'source_unavailable' && !r.url)
  if (noAddress) return { state: 'no_url', field }
  if (r.notStated || r.emptyReason === 'not_published_by_provider' || r.valueState === 'not_stated' || r.scale === 'not_stated') return { state: 'not_stated', field }
  return { state: 'none', field, reason: r.emptyReason ? EMPTY_REASON_LABELS[r.emptyReason] || String(r.emptyReason).replace(/_/g, ' ') : '' }
}

/** The pill's words for a state. */
export const gapLabel = g => (GAP_STATES[g?.state] || GAP_STATES.none).label(g?.count)

/** Add official URL (D5, Curator rank 3+): https only, on the provider's own host (the provider's website host or a subdomain of it). */
export function officialUrlProblem(url, providerWebsite) {
  let u; try { u = new URL(String(url || '').trim()) } catch { return 'Enter a full address that starts with https://' }
  if (u.protocol !== 'https:') return 'The address must start with https://'
  let h = ''; try { h = new URL(String(providerWebsite || '')).hostname.replace(/^www\./, '') } catch { h = '' }
  if (!h) return 'The provider has no website on file; add the provider\'s website first'
  const host = u.hostname.replace(/^www\./, '')
  if (host !== h && !host.endsWith(`.${h}`)) return `The address must be on the provider's own site (${h})`
  return ''
}
