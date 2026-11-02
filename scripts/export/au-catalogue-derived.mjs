// AU catalogue export: the three derived sheets, built only from the exported files (no further database reads), streamed.
//   website_api_v2_field_reconciliation  per course in the API population and consumer field: the database value, the projection value
//                                        (search.course_documents) and the consumer field name, with the comparison
//   field_state_reconciliation           per AU course and field: the state the data supports
//   data_dictionary_and_coverage         per dataset and column: origin, type, comment, filled count and percentage
// Memory (run 41377240304, 2 Nov 2026: out of heap): no dataset is held. While each child CSV is read line by line, Agg keeps a small
// summary per course (counts, the one fee or score the rule picks, candidate links); the courses and projection files are then
// merge-joined in id order and each course's rows are written out at once.
// The consumer field mapping is documented in admin docs/integrations/wix/2026-11-02-au-export-field-mapping.md.

const blank = (v) => v === null || v === undefined || String(v).trim() === ''
const num = (v) => (blank(v) ? null : Number(v))
const arr = (v) => { if (blank(v)) return []; const s = String(v); if (s === '{}') return []; return s.replace(/^\{|\}$/g, '').split(',').map((x) => x.replace(/^"|"$/g, '')) }
const jlen = (v) => { if (blank(v)) return 0; try { const j = JSON.parse(v); return Array.isArray(j) ? j.length : 0 } catch { return 0 } }
const t = (v) => v === 't' || v === true

export function compare(db, proj) {
  const nb = blank(db), np = blank(proj)
  if (nb && np) return 'both_null'
  if (nb) return 'projection_only'
  if (np) return 'db_only'
  const a = Number(db), b = Number(proj)
  if (!Number.isNaN(a) && !Number.isNaN(b) && String(db).trim() !== '' && String(proj).trim() !== '') return a === b ? 'equal' : 'differs'
  return String(db) === String(proj) ? 'equal' : 'differs'
}

// projection order of provider tuition options: fee_year desc nulls last, basis, amount, id
const optOrder = (x, y) => ((num(y.fee_year) ?? -Infinity) - (num(x.fee_year) ?? -Infinity)) || String(x.basis ?? '').localeCompare(String(y.basis ?? '')) || (num(x.amount) - num(y.amount)) || String(x.id ?? '').localeCompare(String(y.id ?? ''))
// the projection's annual amount: latest year, then lowest amount, among annual / indicative_annual options
const annualOrder = (x, y) => ((num(y.fee_year) ?? -Infinity) - (num(x.fee_year) ?? -Infinity)) || (num(x.amount) - num(y.amount))
// api.website_v2_latest_fee: amount >= 1000, latest fee_year (first in option order on a tie)
function latestFee(opts) {
  let best = null
  for (const o of opts) {
    if (num(o.amount) === null || num(o.amount) < 1000) continue
    if (!best || (num(o.fee_year) ?? -Infinity) > (num(best.fee_year) ?? -Infinity)) best = o
  }
  return best
}
function durationMonths(c) {
  const v = num(c.duration_value); if (v === null) return null
  const f = { weeks: 12 / 52, months: 1, years: 12 }[String(c.duration_unit || '').toLowerCase()]
  return f === undefined ? null : Math.round(v * f)
}

// Layer 4 field codes per field (live vocabulary of pipeline.layer4_review_items for entity_type course, read 2 Nov 2026)
export const STATE_FIELDS = [
  { field: 'description', l4: [], has: (c) => !blank(c.description) },
  { field: 'duration', l4: [], has: (c) => !blank(c.duration_value) },
  { field: 'delivery_mode', l4: [], has: (c, s) => !blank(c.delivery_mode) || s.modes.size > 0 },
  { field: 'study_level', l4: [], has: (c) => !blank(c.study_level_id) },
  { field: 'field_of_study', l4: [], has: (c) => !blank(c.primary_field_id) },
  { field: 'official_url', l4: ['official_course_url'], rows: 'course_links' },
  { field: 'provider_current_tuition', l4: ['provider_current_tuition', 'provider_current_tuition_validation'], rows: 'course_fees', filter: (r) => r.fee_type === 'provider_current_tuition' },
  { field: 'regulatory_tuition', l4: [], rows: 'course_fees', filter: (r) => r.fee_type === 'tuition' && r.basis === 'registered_total_course' },
  { field: 'intakes', l4: ['course_intake'], rows: 'course_intakes' },
  { field: 'intake_year', l4: ['course_intake'], rows: 'course_intakes', filter: (r) => !blank(r.intake_year) },
  { field: 'intake_start_date', l4: ['course_intake'], rows: 'course_intakes', filter: (r) => !blank(r.start_date) },
  { field: 'application_deadline', l4: ['course_intake'], rows: 'course_intakes', filter: (r) => !blank(r.application_deadline) },
  { field: 'english', l4: ['course_english'], rows: 'english_requirements' },
  { field: 'entry_requirements', l4: ['course_entry_first_read'], rows: 'course_entry_requirements' },
  { field: 'campus', l4: [], has: (c, s) => s.campuses > 0 },
  { field: 'scholarships', l4: [], rows: 'course_scholarships', admitted: (r) => r.mapping_state === 'mapped', heldIf: (r) => r.mapping_state === 'needs_review' },
]
const BY_ROWS = {}
for (const F of STATE_FIELDS) if (F.rows) (BY_ROWS[F.rows] ||= []).push(F)

// the per-course summary, fed one record at a time
export class Agg {
  constructor(ctx) { this.ctx = ctx; this.c = new Map(); this.providerHidden = new Map() }
  get(id) {
    let s = this.c.get(id)
    if (!s) {
      s = { st: {}, annual: null, opts: [], reg: null, intakesVisible: 0, earliest: null, englishVisible: 0, cand: [], modes: new Set(), subs: new Set(),
        campuses: 0, schVisible: 0, entryBest: null, l4: {} }
      this.c.set(id, s)
    }
    return s
  }
  feed(dataset, r) {
    if (dataset === 'providers') { this.providerHidden.set(r.id, !(r.lifecycle_status === 'active' && r.publication_status === 'published')); return }
    if (dataset === 'layer4_course_review_items') {
      const s = this.get(r.entity_id), k = (s.l4[r.field_code] ||= { pending: 0, at: null, status: null })
      if (r.status === 'pending') k.pending++
      else if (!blank(r.decided_at) && (k.at === null || String(r.decided_at) > k.at)) { k.at = String(r.decided_at); k.status = r.status }
      return
    }
    const fields = BY_ROWS[dataset]
    if (!fields && dataset !== 'course_campuses') return
    const s = this.get(r.course_id)
    for (const F of fields || []) {
      if (F.filter && !F.filter(r)) continue
      const k = (s.st[F.field] ||= { admitted: 0, held: 0, proposed: 0, retired: 0, visible: 0 })
      if (F.admitted) { if (F.admitted(r)) k.admitted++; else if (F.heldIf && F.heldIf(r)) k.held++; else k.retired++ }
      else if (r.x_admission_state === 'admitted') k.admitted++
      else if (r.x_admission_state === 'held') { k.held++; if (r.status === 'proposed') k.proposed++ }
      else k.retired++
      if (t(r.x_consumer_visible)) k.visible++
    }
    if (dataset === 'course_fees') {
      if (t(r.x_in_projection_tuition_options)) {
        const o = { id: r.id, fee_year: r.fee_year, amount: r.amount, basis: r.basis }
        s.opts.push(o)
        if (['annual', 'indicative_annual'].includes(r.basis) && (!s.annual || annualOrder(o, s.annual) < 0)) s.annual = o
      }
      if (t(r.x_is_projection_regulatory_fee)) s.reg = { amount: r.amount }
    } else if (dataset === 'course_intakes') {
      if (t(r.x_consumer_visible)) {
        s.intakesVisible++
        if (!blank(r.start_date) && r.start_date >= this.ctx.snapshotDate && (s.earliest === null || r.start_date < s.earliest)) s.earliest = r.start_date
      }
    } else if (dataset === 'english_requirements') {
      if (t(r.x_consumer_visible)) s.englishVisible++
    } else if (dataset === 'course_links') {
      if (t(r.x_projection_candidate)) s.cand.push({ url: r.url, primary: t(r.is_primary) })
    } else if (dataset === 'course_campuses') {
      s.campuses++
      if (!blank(r.delivery_mode)) s.modes.add(r.delivery_mode)
      if (!blank(r.x_campus_subdivision_code)) s.subs.add(r.x_campus_subdivision_code)
    } else if (dataset === 'course_scholarships') {
      if (t(r.x_consumer_visible)) s.schVisible += Math.max(1, Number(r.x_calculated_savings || 0))
    } else if (dataset === 'course_entry_requirements') {
      if (r.status === 'active' && r.kind === 'minimum_grade' && !blank(r.min_entry_score)) {
        const cand = { score: r.min_entry_score, intl: r.audience === 'international', at: String(r.updated_at ?? '') }
        const b = s.entryBest
        if (!b || (cand.intl && !b.intl) || (cand.intl === b.intl && cand.at > b.at)) s.entryBest = cand
      }
    }
  }
}
const EMPTY = new Agg({ snapshotDate: '' }).get('')

export const RECON_HEADER = ['course_id', 'course_stable_key', 'course_served', 'consumer_field', 'projection_column', 'database_source', 'database_value', 'projection_value', 'consumer_value', 'comparison']
export const RECON_FIELDS = [
  ['item.course_id', 'course_stable_key', 'catalogue.courses.stable_key'],
  ['item.course_code', 'course_code', 'catalogue.courses.course_code'],
  ['item.title', 'course_title', 'catalogue.courses.canonical_title'],
  ['item.description', 'description', 'catalogue.courses.description (the course detail reads it directly; the projection copy feeds search)'],
  ['item.country_code', 'country_code', 'ref.countries.iso_alpha2 of the provider country'],
  ['item.provider.provider_id', 'provider_stable_key', 'catalogue.providers.stable_key'],
  ['item.provider.legal_name', 'provider_name', 'coalesce(providers.display_name, providers.canonical_name)'],
  ['item.study_level.code', 'study_level_code', 'ref.study_levels.code of courses.study_level_id'],
  ['item.study_area.code', 'primary_field_code', 'ref.fields_of_study.code of courses.primary_field_id'],
  ['item.study_area.name', 'primary_field_name', 'ref.fields_of_study.name of courses.primary_field_id'],
  ['item.delivery_modes', 'delivery_modes', 'distinct course_campuses.delivery_mode, else courses.delivery_mode'],
  ['item.subdivision_codes', 'subdivision_codes', 'distinct campus subdivision codes (provider subdivision for fallback countries)'],
  ['item.tuition (provider annual)', 'provider_annual_tuition_amount', 'course_fees with x_in_projection_tuition_options: latest annual or indicative_annual amount'],
  ['item.tuition (regulatory)', 'regulatory_tuition_amount', 'course_fees with x_is_projection_regulatory_fee'],
  ['item.tuition.amount', 'provider_tuition_options / regulatory_tuition_amount', 'api.website_v2_tuition rule applied to the database rows'],
  ['item.intakes (options)', 'intake_options', 'course_intakes with x_consumer_visible (count)'],
  ['earliest_intake_date (search filter)', 'earliest_intake_date', 'min start_date on or after the snapshot date of visible intakes'],
  ['item.english_requirements', 'english_requirement_options', 'english_requirements with x_consumer_visible (count)'],
  ['item.official_url', 'official_course_url', 'course_links with x_projection_candidate'],
  ['item.scholarship_count', 'scholarship_options', 'course_scholarships with x_consumer_visible (one option per calculated saving, at least one)'],
  ['item.campuses', '(read live from catalogue.course_campuses)', 'course_campuses rows (count)'],
  ['item.duration_months', '(read live from catalogue.courses)', 'courses.duration_value and duration_unit'],
  ['item.entry.min_score', '(read live from catalogue.course_entry_requirements)', 'first active minimum_grade row with min_entry_score (international first, latest updated)'],
  ['item.publication_status', 'publication_status', 'provider hidden check: published unless the provider is not active or not published'],
  ['item.freshness.projection_updated_at', 'updated_at', '(projection only)'],
]
export const RECON_META = { sheet: '11 API v2 reconciliation', idColumns: ['course_id', 'consumer_field'], perCourse: RECON_FIELDS.length,
  note: 'Courses in the Website API v2 population only (search.course_documents); the others are listed in courses with x_in_website_api_v2 false. course_served false: an active Layer 4 search block, so the course item is null and consumer_value is empty. live_read: the consumer reads the database directly, so its value is the database value.' }

// the reconciliation rows of one course (c: its courses record; d: its projection record; agg: the summaries)
export function reconRows(c, d, agg, ctx) {
  const s = agg.c.get(c.id) || EMPTY
  const modes = [...s.modes].sort()
  const dbModes = modes.length ? modes : (blank(c.delivery_mode) ? [] : [c.delivery_mode])
  let subs = [...s.subs].sort()
  if (!subs.length && (ctx.regionFallback || []).includes(c.x_country_code) && !blank(c.x_provider_subdivision_code)) subs = [c.x_provider_subdivision_code]
  const cand = s.cand, primary = cand.find((x) => x.primary)
  let linkCmp
  const linkDb = cand.map((x) => x.url).sort().join(' | ') || null
  if (!cand.length && blank(d.official_course_url)) linkCmp = 'both_null'
  else if (!cand.length) linkCmp = 'projection_only'
  else if (blank(d.official_course_url)) linkCmp = 'db_only'
  else if (cand.length === 1 || primary) linkCmp = (primary || cand[0]).url === d.official_course_url ? 'equal' : 'differs'
  else linkCmp = cand.some((x) => x.url === d.official_course_url) ? 'chosen_among_candidates' : 'differs'
  const projOpts = (() => { try { return JSON.parse(d.provider_tuition_options || '[]') } catch { return [] } })()
  const pLatest = latestFee(projOpts), dLatest = latestFee([...s.opts].sort(optOrder))
  const tuitionServed = pLatest ? num(pLatest.amount) : (num(d.regulatory_tuition_amount) ?? 0) >= 1000 ? num(d.regulatory_tuition_amount) : null
  const tuitionDb = dLatest ? num(dLatest.amount) : (num(s.reg?.amount) ?? 0) >= 1000 ? num(s.reg.amount) : null
  const hidden = agg.providerHidden.has(c.provider_id) ? agg.providerHidden.get(c.provider_id) : null
  const pub = hidden === null ? null : hidden ? 'unpublished' : 'published'
  const V = [
    [c.stable_key, d.course_stable_key], [c.course_code, d.course_code], [c.canonical_title, d.course_title], [c.description, d.description],
    [c.x_country_code, d.country_code], [c.x_provider_stable_key, d.provider_stable_key], [c.x_provider_name, d.provider_name],
    [c.x_study_level_code, d.study_level_code], [c.x_primary_field_code, d.primary_field_code], [c.x_primary_field_name, d.primary_field_name],
    [JSON.stringify(dbModes), JSON.stringify(arr(d.delivery_modes))], [JSON.stringify(subs), JSON.stringify(arr(d.subdivision_codes).sort())],
    [s.annual ? s.annual.amount : null, d.provider_annual_tuition_amount], [s.reg ? s.reg.amount : null, d.regulatory_tuition_amount],
    [tuitionDb, tuitionServed, tuitionServed], [s.intakesVisible, jlen(d.intake_options)], [s.earliest, d.earliest_intake_date],
    [s.englishVisible, jlen(d.english_requirement_options)], [linkDb, d.official_course_url, d.official_course_url, linkCmp],
    [s.schVisible, jlen(d.scholarship_options), jlen(d.scholarship_options)],
    [s.campuses, null, s.campuses, 'live_read'], [`${c.duration_value ?? ''} ${c.duration_unit ?? ''}`.trim() || null, null, durationMonths(c), 'live_read'],
    [s.entryBest ? s.entryBest.score : null, null, s.entryBest ? s.entryBest.score : null, 'live_read'],
    [pub, d.publication_status, pub, 'live_read'],
    [null, d.updated_at, d.updated_at, 'projection_only'],
  ]
  // a course with an active Layer 4 search block is not served: the course item is null (consumer_value empty)
  const served = !t(c.x_website_search_blocked)
  return RECON_FIELDS.map(([field, col, src], i) => {
    const [db, proj, consumer, forced] = V[i]
    return [c.id, c.stable_key, served, field, col, src, db ?? null, proj ?? null, !served ? null : consumer === undefined ? proj ?? null : consumer ?? null, forced || compare(db, proj)]
  })
}

export const STATE_HEADER = ['course_id', 'course_stable_key', 'field', 'state', 'admitted_rows', 'held_rows', 'retired_rows', 'layer4_pending_items', 'layer4_latest_decision',
  'consumer_visible', 'course_in_website_api_v2', 'course_withheld_from_search']
export const STATE_META = { sheet: '12 Field states', idColumns: ['course_id', 'field'], perCourse: STATE_FIELDS.length,
  note: 'States: available (admitted value held); quality_held (course withheld by an active Layer 4 search block, or only unverified rows held); layer4_pending (a real pending pipeline.layer4_review_items row, no admitted value); processing (rows proposed, not admitted, no pending item); rejected (latest Layer 4 decision rejected, no admitted value); missing (not held: this says nothing about the source). not_applicable is never assigned: no confirmed not-applicable decision is held.' }

// the field-state rows of one course
export function stateRows(c, agg) {
  const s = agg.c.get(c.id) || EMPTY
  return STATE_FIELDS.map((F) => {
    let admitted, held = 0, retired = 0, proposed = 0, visible = null
    if (F.has) admitted = F.has(c, s) ? 1 : 0
    else { const k = s.st[F.field] || { admitted: 0, held: 0, proposed: 0, retired: 0, visible: 0 }; ({ admitted, held, retired, proposed } = k); visible = k.visible > 0 }
    let pending = 0, decided = null
    for (const code of F.l4) { const k = s.l4[code]; if (!k) continue; pending += k.pending; if (k.at && (!decided || k.at > decided.at)) decided = k }
    let state
    if (t(c.x_website_search_blocked) && admitted) state = 'quality_held'
    else if (admitted) state = 'available'
    else if (pending) state = 'layer4_pending'
    else if (held - proposed > 0) state = 'quality_held'
    else if (proposed) state = 'processing'
    else if (decided && decided.status === 'rejected') state = 'rejected'
    else state = 'missing'
    return [c.id, c.stable_key, F.field, state, admitted, held, retired, pending, decided ? decided.status : null, visible, t(c.x_in_website_api_v2), t(c.x_website_search_blocked)]
  })
}

// tests and small inputs: field states from whole arrays (each dataset an array of row objects)
export function fieldStates(data) {
  const agg = new Agg({ snapshotDate: '' })
  for (const [name, rows] of Object.entries(data)) if (name !== 'courses') for (const r of rows) agg.feed(name, r)
  return { header: STATE_HEADER, rows: data.courses.flatMap((c) => stateRows(c, agg)) }
}

export const DICT_HEADER = ['dataset', 'column', 'origin', 'type', 'not_null', 'definition', 'rows', 'filled', 'filled_pct']
export const DICT_META = { sheet: '13 Dictionary and coverage', idColumns: ['dataset', 'column'],
  note: 'One row per exported column: where it comes from, its database type and comment, and how many rows hold a value (filled = not null and not blank).' }
const TABLE_OF = { courses: 'catalogue.courses', course_fees: 'catalogue.course_fees', course_intakes: 'catalogue.course_intakes', course_entry_requirements: 'catalogue.course_entry_requirements',
  english_requirements: 'catalogue.course_english_requirements', course_scholarships: 'scholarship.course_mappings', scholarship_master: 'scholarship.scholarships',
  scholarship_award_tiers: 'scholarship.award_tiers', scholarship_criteria: 'scholarship.criteria', scholarship_criterion_groups: 'scholarship.criterion_groups',
  scholarship_application_windows: 'scholarship.application_windows', scholarship_offering_cycles: 'scholarship.offering_cycles', scholarship_identifiers: 'scholarship.identifiers',
  provider_rankings: 'catalogue.provider_rankings', provider_entry_matrices: 'catalogue.provider_entry_matrix', course_links: 'catalogue.course_links',
  course_campuses: 'catalogue.course_campuses', course_identifiers: 'catalogue.course_identifiers', course_pages_held: 'pipeline.coverage_course_pages',
  search_course_documents: 'search.course_documents', layer4_course_review_items: 'pipeline.layer4_review_items', providers: 'catalogue.providers' }

// dictionary rows from the per-dataset column counts gathered while each file was read ({ name, header, rows, filled[] , rule })
export function dictionaryRows(stats, dictionary) {
  const cols = new Map((dictionary.columns || []).map((c) => [`${c.table}.${c.column}`, c]))
  const out = []
  for (const x of stats) {
    x.header.forEach((col, i) => {
      const meta = cols.get(`${TABLE_OF[x.name]}.${col}`)
      const derivedDef = col.startsWith('x_') ? (x.rule && x.rule.includes(col) ? x.rule : 'Added by the export from a joined table or a rule; see the field mapping document.') : null
      out.push([x.name, col, meta ? TABLE_OF[x.name] : col.startsWith('x_') ? 'export flag or join' : (TABLE_OF[x.name] || (x.derived ? 'derived (field mapping document)' : x.name)), meta?.type ?? null, meta ? String(meta.not_null) : null,
        meta?.comment ?? derivedDef, x.rows, x.filled[i], x.rows ? Math.round((x.filled[i] / x.rows) * 1000) / 10 : null])
    })
  }
  return out
}
