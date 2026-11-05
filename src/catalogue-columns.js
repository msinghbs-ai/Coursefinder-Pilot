// CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31; decision 19:14 §3): the Course catalogue's column registry.
// It must equal pipeline.admin_table_columns (migration 20261106300000); the spec checks the two are the same. Only columns with a verified data
// contract are offered (docs/course-catalogue-columns.md §2.2). The first 11 default columns are today's columns in today's order and keys, so
// widths a person already set in this browser (cf-colw:course) still apply.
export const COURSE_SCREEN = 'courses'
export const GROUPS = ['Identity', 'Course information', 'Pipeline and enrichment', 'Lifecycle and timestamps']
const C = (key, group, label, sortKey, defaultVisible, width, minWidth, alwaysVisible = false) => ({ key, group, label, header: HEADERS[key] || label, sortKey, defaultVisible, width, minWidth, alwaysVisible })
// Today's column headings are kept on the table (backward compatibility, v2.15.327 "Tuition Only"); the picker shows the mandate's names.
const HEADERS = { course_code: 'Course code', field_of_study: 'Field', fee_amount: 'Tuition Only', last_verified_at: 'Verified' }
export const COURSE_COLUMNS = [
  C('canonical_title', 'Identity', 'Course', 'course', true, 310, 160, true),
  C('course_code', 'Identity', 'Course code / CRICOS', null, true, 155, 96),
  C('provider_name', 'Identity', 'Provider', 'provider', true, 240, 120),
  C('country_name', 'Identity', 'Country', null, false, 130, 90),
  C('subdivision_name', 'Identity', 'State / Region', null, true, 150, 96),
  C('city_names', 'Identity', 'City', 'city', true, 150, 96),
  C('campus_count', 'Identity', 'Campus', null, false, 170, 96),
  C('level_name', 'Identity', 'Study level', null, true, 150, 96),
  C('field_of_study', 'Identity', 'Study area', 'field', true, 190, 110),
  C('duration', 'Course information', 'Duration', null, false, 130, 90),
  C('delivery_mode', 'Course information', 'Delivery mode', null, false, 140, 90),
  C('intl_fee_amount', 'Course information', 'International fee', 'intl_fee', true, 190, 110),
  C('fee_amount', 'Course information', 'Tuition (registered, CRICOS)', 'fee', true, 150, 100),
  C('intl_fee_year', 'Course information', 'Fee year', null, false, 100, 80),
  C('intakes', 'Course information', 'Intakes', null, false, 150, 100),
  C('deadline', 'Course information', 'Application deadline', null, false, 160, 100),
  C('english', 'Course information', 'English requirements', null, false, 160, 100),
  C('academic_entry', 'Course information', 'Academic entry requirements', null, false, 170, 100),
  C('has_scholarship', 'Course information', 'Scholarships', null, false, 120, 90),
  C('description', 'Course information', 'Course description', null, false, 160, 100),
  C('official_url', 'Course information', 'Official course URL', null, false, 180, 110),
  C('completeness_score_v2', 'Course information', 'Completeness', 'completeness', true, 120, 90),
  C('adapter_state', 'Pipeline and enrichment', 'Adapter status', 'adapter', true, 160, 110),
  C('adapter_last_read_at', 'Pipeline and enrichment', 'Adapter last read', null, false, 160, 110),
  C('adapter_result', 'Pipeline and enrichment', 'Adapter result', null, false, 200, 110),
  C('page_stored', 'Pipeline and enrichment', 'Stored course page', null, false, 140, 100),
  C('source_identity', 'Pipeline and enrichment', 'Source identity', null, false, 160, 100),
  C('last_verified_at', 'Pipeline and enrichment', 'Evidence last verified', 'verified', true, 145, 110),
  C('layer4_status', 'Pipeline and enrichment', 'Layer 4', null, false, 130, 90),
  C('enrichment_status', 'Pipeline and enrichment', 'Enrichment', null, false, 170, 110),
  C('last_admitted_field', 'Pipeline and enrichment', 'Last successful field admission', null, false, 220, 130),
  C('created_at', 'Lifecycle and timestamps', 'Created', null, false, 140, 100),
  C('last_modified_at', 'Lifecycle and timestamps', 'Last modified', 'modified', true, 150, 110),
  C('last_admitted_at', 'Lifecycle and timestamps', 'Last data admitted', 'admitted', true, 160, 110),
  C('lifecycle_status', 'Lifecycle and timestamps', 'Lifecycle status', null, false, 130, 90),
  C('publication_status', 'Lifecycle and timestamps', 'Publication', null, false, 130, 90),
]
const BY_KEY = Object.fromEntries(COURSE_COLUMNS.map(c => [c.key, c]))
export const columnOf = key => BY_KEY[key]
// The limits the server applies (pipeline settings catalogue_layout.*); the server's own values replace these once read.
export const DEFAULT_LIMITS = { max_columns: 60, width_min_px: 64, width_max_px: 1200 }
export function defaultLayout() { return { version: 1, columns: COURSE_COLUMNS.filter(c => c.defaultVisible).map(c => c.key), widths: {}, sort: 'course', direction: 'asc' } }

/** A saved layout made safe: known columns only, once each, the always-shown ones kept, widths within the limits. */
export function normaliseLayout(layout, limits = DEFAULT_LIMITS) {
  const d = defaultLayout()
  if (!layout || typeof layout !== 'object' || !Array.isArray(layout.columns)) return d
  const seen = new Set(), columns = []
  for (const k of layout.columns) if (BY_KEY[k] && !seen.has(k)) { seen.add(k); columns.push(k) }
  for (const c of COURSE_COLUMNS) if (c.alwaysVisible && !seen.has(c.key)) columns.unshift(c.key)
  const widths = {}
  for (const [k, v] of Object.entries(layout.widths && typeof layout.widths === 'object' ? layout.widths : {})) {
    if (BY_KEY[k] && Number.isFinite(Number(v))) widths[k] = clampWidth(k, Number(v), limits)
  }
  const sortable = new Set(COURSE_COLUMNS.map(c => c.sortKey).filter(Boolean))
  return { version: 1, columns: columns.slice(0, limits.max_columns || DEFAULT_LIMITS.max_columns), widths, sort: sortable.has(layout.sort) ? layout.sort : d.sort, direction: layout.direction === 'desc' ? 'desc' : 'asc' }
}
export function minWidthOf(key, limits = DEFAULT_LIMITS) { return Math.max(BY_KEY[key]?.minWidth || 0, limits.width_min_px || DEFAULT_LIMITS.width_min_px) }
export function clampWidth(key, px, limits = DEFAULT_LIMITS) { return Math.round(Math.min(limits.width_max_px || DEFAULT_LIMITS.width_max_px, Math.max(minWidthOf(key, limits), px))) }
export function moveColumn(columns, key, by) {
  const i = columns.indexOf(key), j = i + by
  if (i < 0 || j < 0 || j >= columns.length) return columns
  const next = columns.slice(); next.splice(i, 1); next.splice(j, 0, key); return next
}
export function toggleColumn(columns, key, on, limits = DEFAULT_LIMITS) {
  if (BY_KEY[key]?.alwaysVisible) return columns
  if (!on) return columns.filter(k => k !== key)
  if (columns.includes(key) || columns.length >= (limits.max_columns || DEFAULT_LIMITS.max_columns)) return columns
  // a newly shown column goes where the registry puts it among the shown ones
  const order = COURSE_COLUMNS.map(c => c.key), at = order.indexOf(key)
  const next = columns.slice(); let i = next.findIndex(k => order.indexOf(k) > at); if (i < 0) i = next.length; next.splice(i, 0, key); return next
}

// The seven field states (mandate §7), from the projection's field_states (coverage states and flags). Unknown = no state held.
export const FIELD_STATES = {
  populated: ['Populated', 'success'], missing: ['Missing', 'warning'], pending: ['Pending extraction', 'info'], review: ['Waiting for review', 'violet'],
  held: ['Held by validation', 'warning'], not_applicable: ['Not applicable', 'neutral'], failed: ['Failed', 'danger'],
}
export const ADAPTER_STATES = {
  ready: ['Ready', 'info'], processing: ['Processing', 'info'], completed: ['Completed', 'success'], held: ['Held', 'warning'], failed: ['Failed', 'danger'], not_configured: ['Not configured', 'neutral'],
}
export const SORT_WORDS = { course: 'Course', provider: 'Provider', city: 'City', field: 'Field', intl_fee: 'International fee', fee: 'Tuition Only', completeness: 'Completeness',
  verified: 'Verified', modified: 'Last modified', admitted: 'Last data admitted', adapter: 'Adapter status' }
const TIME_SORTS = new Set(['modified', 'admitted', 'verified'])
export function sortSentence(sort, direction) {
  const w = SORT_WORDS[sort] || sort
  if (TIME_SORTS.has(sort)) return `${w}, ${direction === 'desc' ? 'newest first' : 'oldest first'}${sort === 'verified' ? '' : ' (Unknown last)'}`
  if (sort === 'adapter') return `${w}, ${direction === 'desc' ? 'Not configured first' : 'Failed first'}`
  return `${w}, ${direction === 'desc' ? 'Z to A' : 'A to Z'}`
}
/** "Melbourne +2" with each city's state, so two cities of the same name stay apart. */
export function citySummary(cities) {
  const list = Array.isArray(cities) ? cities.filter(c => c && c.city) : []
  const label = c => `${c.city}${c.subdivision_code ? ` (${String(c.subdivision_code).replace(/^[A-Z]{2}-/, '')})` : ''}`
  const names = [...new Set(list.map(label))]
  return { names, short: names.length ? (names.length > 1 ? `${names[0]} +${names.length - 1}` : names[0]) : '' }
}
