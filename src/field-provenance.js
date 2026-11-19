// CF-247 s812 (Platform Admin 20 Nov 2026 08:06): per-field provenance and lock pills, and the hand-off list for Bulk Queue to Intake Run & Validate.
// Pure helpers and the one API module; the screens are in FieldProvenance.jsx, CompletenessBar.jsx and BulkPrimaryCampus.jsx.
// The pills say only what is recorded: Human Locked comes from the lock table (pipeline.manual_locks, read through the Inbox dispatcher), Register and
// AI verified come from the description's recorded source tier. A field whose source is not recorded says so; nothing is guessed.

// the tracked provider fields (CompletenessBar.PROVIDER_TRACKED_FIELDS) and the lock columns that hold each
export const PROVIDER_LOCK_COLUMNS = {
  description: ['description'], website: ['website'], city: ['city'], state_region: ['state_region'], provider_type: ['provider_type', 'provider_type_id'],
  phone: ['phone'], email: ['email'], address: ['address_line1', 'address_line2', 'postcode'], established_year: ['established_year'],
}
// the tracked course fields: the facts the website reads and a person can lock by hand
export const COURSE_TRACKED_FIELDS = ['description', 'duration', 'tuition', 'intakes', 'english', 'course_url', 'official_url', 'lifecycle_status']
export const COURSE_FIELD_WORDS = {
  description: 'Description', duration: 'Duration', tuition: 'Tuition', intakes: 'Intakes', english: 'English requirements',
  course_url: 'Course page', official_url: 'Official page', lifecycle_status: 'Status',
}
export const COURSE_LOCK_COLUMNS = {
  description: ['description'], duration: ['duration_value', 'duration_unit'], tuition: ['tuition', 'tuition_fee'], intakes: ['intakes'], english: ['english'],
  course_url: ['course_url'], official_url: ['official_url'], lifecycle_status: ['lifecycle_status'],
}
const LOCK_WORDS = { display_name: 'Display name', canonical_name: 'Name', course_finder: 'Course Finder switch', address_line1: 'Address', postcode: 'Postcode' }

// the lock a tracked field holds, or null: the first of its columns that is locked
export function lockFor(locks, columns) {
  for (const c of columns || []) { const l = locks && locks[c]; if (l) return { column: c, mode: l.mode, set_at: l.set_at } }
  return null
}
// lock columns of the record that no tracked field covers (a name, a switch), in plain words
export function otherLocked(locks, mapping) {
  const known = new Set(Object.values(mapping).flat())
  return Object.keys(locks || {}).filter(c => !known.has(c)).map(c => LOCK_WORDS[c] || c.replaceAll('_', ' ')).sort()
}
export const lockWord = l => l?.mode === 'removed' ? 'Human Locked · empty' : 'Human Locked'
export const lockTitle = l => l ? `Locked by hand${l.set_at ? ` on ${String(l.set_at).slice(0, 10)}` : ''}; automation does not change it until the lock is released` : undefined

// Bulk Queue to Intake Run & Validate: the ticked providers are handed over, nothing is run. The intake page lists them and the operator picks one
// for the existing preview, fix and run steps (its own controls, size cap and reason apply). Kept for this browser tab only.
const QUEUE_KEY = 'cf.intake.queue.v1'
export function saveIntakeQueue(items) {
  const list = (items || []).filter(x => x && x.id).map(x => ({ id: String(x.id), name: String(x.name || '') }))
  try { sessionStorage.setItem(QUEUE_KEY, JSON.stringify(list)) } catch { /* storage may be unavailable; the hand-off then carries nothing */ }
  return list
}
export function readIntakeQueue() {
  try { const v = JSON.parse(sessionStorage.getItem(QUEUE_KEY) || '[]'); return Array.isArray(v) ? v.filter(x => x && x.id) : [] } catch { return [] }
}
export function clearIntakeQueue() { try { sessionStorage.removeItem(QUEUE_KEY) } catch { /* nothing to clear */ } }

// the outcome words of the primary campus preview
export const PRIMARY_OUTCOME = {
  will_mark: 'Will be marked primary', has_primary: 'Already has a primary campus', locked: 'Primary campus locked by hand', tie: 'Tied: left for a person',
  no_campus: 'No active campus', not_active: 'Not active', outside_rule: 'Outside the rule (AU, NZ, CA only)',
}
