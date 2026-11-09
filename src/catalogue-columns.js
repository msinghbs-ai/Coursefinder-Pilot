// CF-247 Course Catalogue columns (Platform Admin mandate 5 Nov 2026 17:31; decision 19:14 §3): the Course catalogue's column registry.
// It must equal pipeline.admin_table_columns (migration 20261106300000); the spec checks the two are the same. Only columns with a verified data
// contract are offered (docs/course-catalogue-columns.md §2.2). The first 11 default columns are today's columns in today's order and keys, so
// widths a person already set in this browser (cf-colw:course) still apply.
export const COURSE_SCREEN = 'courses'
export const PROVIDER_SCREEN = 'providers'
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
  C('intakes', 'Course information', 'Intakes', null, false, 160, 100),
  C('intake_month', 'Course information', 'Intake month', null, false, 130, 90),
  C('intake_year', 'Course information', 'Intake year', null, false, 110, 80),
  C('commencement_date', 'Course information', 'Exact commencement date', null, false, 170, 110),
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
  C('last_modified_at', 'Lifecycle and timestamps', 'Course record updated (as recorded)', 'modified', true, 150, 110),
  C('last_admitted_at', 'Lifecycle and timestamps', 'Last data admitted', 'admitted', true, 160, 110),
  C('last_published_at', 'Lifecycle and timestamps', 'Last published (website feed)', null, false, 170, 110),
  C('lifecycle_status', 'Lifecycle and timestamps', 'Lifecycle status', null, false, 130, 90),
  C('publication_status', 'Lifecycle and timestamps', 'Publication', null, false, 130, 90),
]
// CF-247 Provider Catalogue columns (Platform Admin directive 9 Nov 2026): the Provider catalogue's column registry, same mechanism as the Course
// catalogue's. It must equal the screen 'providers' rows of pipeline.admin_table_columns (migration 20261109200000); the spec checks the two are the
// same. The first 13 columns are today's provider table in today's order and keys (Adapter is shown to Platform Admin only); the rest are off by
// default. `order` is the registry's own sort number: it places a newly shown column among the shown ones.
const PH = { last_verified_at: 'Verified', publication_status: 'Published' }
const P = (key, group, label, order, sortKey, defaultVisible, width, minWidth, alwaysVisible = false) => ({ key, group, label, header: PH[key] || label, order, sortKey, defaultVisible, width, minWidth, alwaysVisible })
export const PROVIDER_COLUMNS = [
  P('canonical_name', 'Identity', 'Provider', 10, 'provider', true, 300, 160, true),
  P('adapter', 'Pipeline and enrichment', 'Adapter', 15, 'adapter', true, 150, 110),
  P('country_code', 'Identity', 'Country', 20, 'country', true, 110, 80),
  P('provider_type_name', 'Identity', 'Type', 30, 'type', true, 200, 120),
  P('subdivision_name', 'Identity', 'State / Region', 40, 'subdivision', true, 160, 96),
  P('city', 'Identity', 'City', 50, 'city', true, 150, 96),
  P('course_count', 'Course information', 'Courses', 60, 'courses', true, 95, 80),
  P('university_groups', 'Identity', 'Group', 70, null, true, 110, 80),
  P('evidence_count', 'Pipeline and enrichment', 'Evidence', 80, null, true, 95, 80),
  P('lifecycle_status', 'Lifecycle and timestamps', 'Lifecycle', 90, 'lifecycle', true, 115, 90),
  P('publication_status', 'Lifecycle and timestamps', 'Published', 100, 'publication', true, 130, 110),
  P('scholarship_search', 'Course information', 'Scholarship search', 110, null, true, 150, 110),
  P('last_verified_at', 'Lifecycle and timestamps', 'Source last verified', 120, 'verified', true, 150, 110),
  P('registration', 'Identity', 'Registration identity', 25, 'registration', false, 190, 120),
  P('scholarship_count', 'Course information', 'Scholarships', 62, 'scholarships', false, 130, 90),
  P('entry_coverage', 'Course information', 'Entry requirements coverage', 64, 'coverage', false, 220, 130),
  P('admission_state', 'Pipeline and enrichment', 'Description admission', 130, 'admission', false, 150, 100),
  P('description_filled', 'Pipeline and enrichment', 'Description populated', 135, 'description', false, 130, 90),
  P('description_text', 'Pipeline and enrichment', 'Description', 140, null, false, 300, 160),
  P('description_source', 'Pipeline and enrichment', 'Description source', 145, 'source', false, 170, 110),
  P('description_evidence', 'Pipeline and enrichment', 'Description evidence and source address', 150, null, false, 230, 130),
  P('description_admitted_at', 'Pipeline and enrichment', 'Last description admitted', 155, 'desc_admitted', false, 170, 110),
  P('reader_status', 'Pipeline and enrichment', 'Description reader status', 160, 'reader', false, 170, 110),
  P('last_read_ok_at', 'Pipeline and enrichment', 'Last successful page read', 165, 'last_read', false, 170, 110),
  P('hold_reason', 'Pipeline and enrichment', 'Held or declined reason', 170, null, false, 260, 140),
  P('next_retry_at', 'Pipeline and enrichment', 'Next retry', 175, 'next_retry', false, 160, 100),
  P('layer4_status', 'Pipeline and enrichment', 'Layer 4 decision', 180, 'layer4', false, 170, 110),
  P('canonical_status', 'Lifecycle and timestamps', 'Catalogue description', 190, 'canonical', false, 190, 120),
  P('website_state', 'Lifecycle and timestamps', 'Website feed sync', 195, 'website', false, 150, 100),
  P('zoho_state', 'Lifecycle and timestamps', 'Zoho publication', 200, 'zoho', false, 150, 100),
  P('mismatch', 'Lifecycle and timestamps', 'Catalogue and consumer mismatch', 205, 'mismatch', false, 200, 120),
  P('last_modified_at', 'Lifecycle and timestamps', 'Provider record updated (as recorded)', 210, 'modified', false, 190, 120),
]
// The picker's group headings per screen. The four group names are the database's (its CHECK constraint is not widened); the Provider screen shows its own wording.
export const GROUP_HEADINGS = {
  [PROVIDER_SCREEN]: { 'Identity': 'Provider identity and location', 'Course information': 'Courses, scholarships and coverage', 'Pipeline and enrichment': 'Description pipeline and adapter', 'Lifecycle and timestamps': 'Publication, consumers and timestamps' },
}
export const groupHeading = (screen, group) => GROUP_HEADINGS[screen]?.[group] || group
const REG = { [COURSE_SCREEN]: COURSE_COLUMNS, [PROVIDER_SCREEN]: PROVIDER_COLUMNS }
const MAPS = { [COURSE_SCREEN]: Object.fromEntries(COURSE_COLUMNS.map(c => [c.key, c])), [PROVIDER_SCREEN]: Object.fromEntries(PROVIDER_COLUMNS.map(c => [c.key, c])) }
const DEFAULT_SORT = { [COURSE_SCREEN]: 'course', [PROVIDER_SCREEN]: 'provider' }
/** A screen's registry in the order the server holds it (by its sort number); the Course registry is already in that order. */
export const registryOf = (screen = COURSE_SCREEN) => (screen === PROVIDER_SCREEN ? [...PROVIDER_COLUMNS].sort((a, b) => a.order - b.order) : COURSE_COLUMNS)
const mapOf = screen => MAPS[screen] || MAPS[COURSE_SCREEN]
export const columnOf = (key, screen = COURSE_SCREEN) => mapOf(screen)[key]
// The limits the server applies (pipeline settings catalogue_layout.*); the server's own values replace these once read.
export const DEFAULT_LIMITS = { max_columns: 60, width_min_px: 64, width_max_px: 1200 }
export function defaultLayout(screen = COURSE_SCREEN) { return { version: 1, columns: registryOf(screen).filter(c => c.defaultVisible).map(c => c.key), widths: {}, sort: DEFAULT_SORT[screen] || 'course', direction: 'asc' } }

/** A saved layout made safe: known columns only, once each, the always-shown ones kept, widths within the limits. */
export function normaliseLayout(layout, limits = DEFAULT_LIMITS, screen = COURSE_SCREEN) {
  const d = defaultLayout(screen), map = mapOf(screen)
  if (!layout || typeof layout !== 'object' || !Array.isArray(layout.columns)) return d
  const seen = new Set(), columns = []
  for (const k of layout.columns) if (map[k] && !seen.has(k)) { seen.add(k); columns.push(k) }
  for (const c of REG[screen] || COURSE_COLUMNS) if (c.alwaysVisible && !seen.has(c.key)) columns.unshift(c.key)
  const widths = {}
  for (const [k, v] of Object.entries(layout.widths && typeof layout.widths === 'object' ? layout.widths : {})) {
    if (map[k] && Number.isFinite(Number(v))) widths[k] = clampWidth(k, Number(v), limits, screen)
  }
  const sortable = new Set((REG[screen] || COURSE_COLUMNS).map(c => c.sortKey).filter(Boolean))
  return { version: 1, columns: columns.slice(0, limits.max_columns || DEFAULT_LIMITS.max_columns), widths, sort: sortable.has(layout.sort) ? layout.sort : d.sort, direction: layout.direction === 'desc' ? 'desc' : 'asc' }
}
export function minWidthOf(key, limits = DEFAULT_LIMITS, screen = COURSE_SCREEN) { return Math.max(mapOf(screen)[key]?.minWidth || 0, limits.width_min_px || DEFAULT_LIMITS.width_min_px) }
export function clampWidth(key, px, limits = DEFAULT_LIMITS, screen = COURSE_SCREEN) { return Math.round(Math.min(limits.width_max_px || DEFAULT_LIMITS.width_max_px, Math.max(minWidthOf(key, limits, screen), px))) }
export function moveColumn(columns, key, by) {
  const i = columns.indexOf(key), j = i + by
  if (i < 0 || j < 0 || j >= columns.length) return columns
  const next = columns.slice(); next.splice(i, 1); next.splice(j, 0, key); return next
}
export function toggleColumn(columns, key, on, limits = DEFAULT_LIMITS, screen = COURSE_SCREEN) {
  if (mapOf(screen)[key]?.alwaysVisible) return columns
  if (!on) return columns.filter(k => k !== key)
  if (columns.includes(key) || columns.length >= (limits.max_columns || DEFAULT_LIMITS.max_columns)) return columns
  // a newly shown column goes where the registry puts it among the shown ones
  const order = registryOf(screen).map(c => c.key), at = order.indexOf(key)
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
  verified: 'Verified', modified: 'Course record updated', admitted: 'Last data admitted', adapter: 'Adapter status' }
// The Provider catalogue's sorts (migration 20261109200000): every sort key of the Provider registry.
export const PROVIDER_SORT_WORDS = { provider: 'Provider', country: 'Country', type: 'Type', subdivision: 'State / Region', city: 'City', courses: 'Courses', adapter: 'Adapter', lifecycle: 'Lifecycle', publication: 'Published',
  verified: 'Source last verified', registration: 'Registration identity', scholarships: 'Scholarships', coverage: 'Entry requirements coverage', admission: 'Description admission', description: 'Description populated',
  source: 'Description source', desc_admitted: 'Last description admitted', reader: 'Description reader status', last_read: 'Last successful page read', next_retry: 'Next retry', layer4: 'Layer 4 decision',
  canonical: 'Catalogue description', website: 'Website feed sync', zoho: 'Zoho publication', mismatch: 'Catalogue and consumer mismatch', modified: 'Provider record updated' }
const TIME_SORTS = new Set(['modified', 'admitted', 'verified'])
const PROVIDER_TIME_SORTS = new Set(['modified', 'verified', 'desc_admitted', 'last_read'])
const PROVIDER_COUNT_SORTS = new Set(['courses', 'scholarships'])
export function sortSentence(sort, direction, screen = COURSE_SCREEN) {
  if (screen === PROVIDER_SCREEN) {
    const w = PROVIDER_SORT_WORDS[sort] || sort
    if (PROVIDER_TIME_SORTS.has(sort)) return `${w}, ${direction === 'desc' ? 'newest first' : 'oldest first'}${sort === 'verified' ? '' : ' (Unknown last)'}`
    if (sort === 'next_retry') return `${w}, ${direction === 'desc' ? 'latest first' : 'soonest first'} (none last)`
    if (PROVIDER_COUNT_SORTS.has(sort)) return `${w}, ${direction === 'desc' ? 'most first' : 'fewest first'}`
    return `${w}, ${direction === 'desc' ? 'Z to A' : 'A to Z'}`
  }
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

const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
/** One intake as the website names it: "Feb 2027", the label when no month is held, never a guessed month or year. */
export function intakeName(i) {
  if (!i) return ''
  const m = Number(i.month) >= 1 && Number(i.month) <= 12 ? MONTH[Number(i.month) - 1] : null
  return [m || i.label || '', i.year || ''].filter(Boolean).join(' ').trim()
}
/** "Feb 2027 +1" over a course's intakes; list holds every intake's full line. */
export function intakeSummary(intakes) {
  const list = (Array.isArray(intakes) ? intakes : []).map(intakeName).filter(Boolean)
  const names = [...new Set(list)]
  return { names, short: names.length ? (names.length > 1 ? `${names[0]} +${names.length - 1}` : names[0]) : '' }
}
export const monthName = n => (Number(n) >= 1 && Number(n) <= 12 ? MONTH[Number(n) - 1] : null)
