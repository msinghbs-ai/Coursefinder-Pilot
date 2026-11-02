// AU catalogue export: the three derived sheets, built only from the exported files (no further database reads).
//   website_api_v2_field_reconciliation  per course in the API population and consumer field: the database value, the projection value
//                                        (search.course_documents) and the consumer field name, with the comparison
//   field_state_reconciliation           per AU course and field: the state the data supports
//   data_dictionary_and_coverage         per dataset and column: origin, type, comment, filled count and percentage
// The consumer field mapping is documented in admin docs/integrations/wix/2026-11-02-au-export-field-mapping.md.

const blank = (v) => v === null || v === undefined || String(v).trim() === ''
const num = (v) => (blank(v) ? null : Number(v))
const arr = (v) => { if (blank(v)) return []; const s = String(v); if (s === '{}') return []; return s.replace(/^\{|\}$/g, '').split(',').map((x) => x.replace(/^"|"$/g, '')) }
const jlen = (v) => { if (blank(v)) return 0; try { const j = JSON.parse(v); return Array.isArray(j) ? j.length : 0 } catch { return 0 } }
const group = (rows, col) => { const m = new Map(); for (const r of rows) { const k = r[col]; if (!m.has(k)) m.set(k, []); m.get(k).push(r) } return m }
const t = (v) => v === 't'

export function compare(db, proj) {
  const nb = blank(db), np = blank(proj)
  if (nb && np) return 'both_null'
  if (nb) return 'projection_only'
  if (np) return 'db_only'
  const a = Number(db), b = Number(proj)
  if (!Number.isNaN(a) && !Number.isNaN(b) && String(db).trim() !== '' && String(proj).trim() !== '') return a === b ? 'equal' : 'differs'
  return String(db) === String(proj) ? 'equal' : 'differs'
}

// the projection's provider annual tuition: the latest year's annual or indicative_annual option (fee_year desc nulls last, amount)
function annualFrom(rows) {
  const a = rows.filter((f) => ['annual', 'indicative_annual'].includes(f.basis))
    .sort((x, y) => (num(y.fee_year) ?? -Infinity) - (num(x.fee_year) ?? -Infinity) || num(x.amount) - num(y.amount))
  return a.length ? a[0] : null
}
// api.website_v2_latest_fee: amount >= 1000, latest fee_year
function latestFee(opts) {
  const ok = opts.filter((o) => num(o.amount) !== null && num(o.amount) >= 1000).sort((x, y) => (num(y.fee_year) ?? -Infinity) - (num(x.fee_year) ?? -Infinity))
  return ok[0] || null
}
function durationMonths(c) {
  const v = num(c.duration_value); if (v === null) return null
  const f = { weeks: 12 / 52, months: 1, years: 12 }[String(c.duration_unit || '').toLowerCase()]
  return f === undefined ? null : Math.round(v * f)
}

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

export function reconciliation(data, ctx) {
  const header = ['course_id', 'course_stable_key', 'course_served', 'consumer_field', 'projection_column', 'database_source', 'database_value', 'projection_value', 'consumer_value', 'comparison']
  const rows = []
  const courses = new Map(data.courses.map((c) => [c.id, c]))
  const providers = new Map(data.providers.map((p) => [p.id, p]))
  const fees = group(data.course_fees, 'course_id'), intakes = group(data.course_intakes, 'course_id'), eng = group(data.english_requirements, 'course_id')
  const links = group(data.course_links, 'course_id'), camp = group(data.course_campuses, 'course_id'), sch = group(data.course_scholarships, 'course_id')
  const entry = group(data.course_entry_requirements, 'course_id')
  for (const d of data.search_course_documents) {
    const c = courses.get(d.course_id); if (!c) continue
    const p = providers.get(c.provider_id) || {}
    const f = fees.get(c.id) || [], cc = camp.get(c.id) || []
    const opts = f.filter((x) => t(x.x_in_projection_tuition_options))
    const ann = annualFrom(opts)
    const reg = f.find((x) => t(x.x_is_projection_regulatory_fee))
    const modes = [...new Set(cc.map((x) => x.delivery_mode).filter((m) => !blank(m)))].sort()
    const dbModes = modes.length ? modes : (blank(c.delivery_mode) ? [] : [c.delivery_mode])
    let subs = [...new Set(cc.map((x) => x.x_campus_subdivision_code).filter((m) => !blank(m)))].sort()
    if (!subs.length && ctx.regionFallback.includes(c.x_country_code) && !blank(c.x_provider_subdivision_code)) subs = [c.x_provider_subdivision_code]
    const vis = (rs) => (rs || []).filter((x) => t(x.x_consumer_visible))
    const vInt = vis(intakes.get(c.id))
    const early = vInt.map((x) => x.start_date).filter((s) => !blank(s) && s >= ctx.snapshotDate).sort()[0] || null
    const cand = (links.get(c.id) || []).filter((x) => t(x.x_projection_candidate))
    const primary = cand.find((x) => t(x.is_primary))
    let linkCmp, linkDb = cand.map((x) => x.url).sort().join(' | ') || null
    if (!cand.length && blank(d.official_course_url)) linkCmp = 'both_null'
    else if (!cand.length) linkCmp = 'projection_only'
    else if (blank(d.official_course_url)) linkCmp = 'db_only'
    else if (cand.length === 1 || primary) linkCmp = (primary || cand[0]).url === d.official_course_url ? 'equal' : 'differs'
    else linkCmp = cand.some((x) => x.url === d.official_course_url) ? 'chosen_among_candidates' : 'differs'
    const schOpts = vis(sch.get(c.id)).reduce((a, x) => a + Math.max(1, Number(x.x_calculated_savings || 0)), 0)
    // consumer tuition amount: from the projection columns (as served) and from the database rows (same rule)
    const projOpts = (() => { try { return JSON.parse(d.provider_tuition_options || '[]') } catch { return [] } })()
    const pLatest = latestFee(projOpts), dLatest = latestFee(opts)
    const tuitionServed = pLatest ? num(pLatest.amount) : (num(d.regulatory_tuition_amount) ?? 0) >= 1000 ? num(d.regulatory_tuition_amount) : null
    const tuitionDb = dLatest ? num(dLatest.amount) : (num(reg?.amount) ?? 0) >= 1000 ? num(reg.amount) : null
    const ent = (entry.get(c.id) || []).filter((r) => r.status === 'active' && r.kind === 'minimum_grade' && !blank(r.min_entry_score))
      .sort((x, y) => (y.audience === 'international') - (x.audience === 'international') || String(y.updated_at).localeCompare(String(x.updated_at)))[0]
    const hidden = !(p.lifecycle_status === 'active' && p.publication_status === 'published')
    const V = [
      [c.stable_key, d.course_stable_key], [c.course_code, d.course_code], [c.canonical_title, d.course_title], [c.description, d.description],
      [c.x_country_code, d.country_code], [c.x_provider_stable_key, d.provider_stable_key], [c.x_provider_name, d.provider_name],
      [c.x_study_level_code, d.study_level_code], [c.x_primary_field_code, d.primary_field_code], [c.x_primary_field_name, d.primary_field_name],
      [JSON.stringify(dbModes), JSON.stringify(arr(d.delivery_modes))], [JSON.stringify(subs), JSON.stringify(arr(d.subdivision_codes).sort())],
      [ann ? ann.amount : null, d.provider_annual_tuition_amount], [reg ? reg.amount : null, d.regulatory_tuition_amount],
      [tuitionDb, tuitionServed, tuitionServed], [vInt.length, jlen(d.intake_options)], [early, d.earliest_intake_date],
      [vis(eng.get(c.id)).length, jlen(d.english_requirement_options)], [linkDb, d.official_course_url, d.official_course_url, linkCmp],
      [schOpts, jlen(d.scholarship_options), jlen(d.scholarship_options)],
      [cc.length, null, cc.length, 'live_read'], [`${c.duration_value ?? ''} ${c.duration_unit ?? ''}`.trim() || null, null, durationMonths(c), 'live_read'],
      [ent ? ent.min_entry_score : null, null, ent ? ent.min_entry_score : null, 'live_read'],
      [hidden ? 'unpublished' : 'published', d.publication_status, hidden ? 'unpublished' : 'published', 'live_read'],
      [null, d.updated_at, d.updated_at, 'projection_only'],
    ]
    RECON_FIELDS.forEach(([field, col, src], i) => {
      const [db, proj, consumer, forced] = V[i]
      const cmp = forced || compare(db, proj)
      // a course with an active Layer 4 search block is not served: the course item is null (consumer_value empty)
      const served = !t(c.x_website_search_blocked)
      rows.push([c.id, c.stable_key, served, field, col, src, db ?? null, proj ?? null, !served ? null : consumer === undefined ? proj ?? null : consumer ?? null, cmp])
    })
  }
  return { header, rows, sheet: '11 API v2 reconciliation', idColumns: ['course_id', 'consumer_field'],
    note: 'Courses in the Website API v2 population only (search.course_documents); the others are listed in courses with x_in_website_api_v2 false. course_served false: an active Layer 4 search block, so the course item is null and consumer_value is empty. live_read: the consumer reads the database directly, so its value is the database value.' }
}

// Layer 4 field codes per field (live vocabulary of pipeline.layer4_review_items for entity_type course, read 2 Nov 2026)
export const STATE_FIELDS = [
  { field: 'description', l4: [], has: (c) => !blank(c.description) },
  { field: 'duration', l4: [], has: (c) => !blank(c.duration_value) },
  { field: 'delivery_mode', l4: [], has: (c, x) => !blank(c.delivery_mode) || x.camp.some((r) => !blank(r.delivery_mode)) },
  { field: 'study_level', l4: [], has: (c) => !blank(c.study_level_id) },
  { field: 'field_of_study', l4: [], has: (c) => !blank(c.primary_field_id) },
  { field: 'official_url', l4: ['official_course_url'], rows: 'links' },
  { field: 'provider_current_tuition', l4: ['provider_current_tuition', 'provider_current_tuition_validation'], rows: 'fees', filter: (r) => r.fee_type === 'provider_current_tuition' },
  { field: 'regulatory_tuition', l4: [], rows: 'fees', filter: (r) => r.fee_type === 'tuition' && r.basis === 'registered_total_course' },
  { field: 'intakes', l4: ['course_intake'], rows: 'intakes' },
  { field: 'intake_year', l4: ['course_intake'], rows: 'intakes', filter: (r) => !blank(r.intake_year) },
  { field: 'intake_start_date', l4: ['course_intake'], rows: 'intakes', filter: (r) => !blank(r.start_date) },
  { field: 'application_deadline', l4: ['course_intake'], rows: 'intakes', filter: (r) => !blank(r.application_deadline) },
  { field: 'english', l4: ['course_english'], rows: 'english' },
  { field: 'entry_requirements', l4: ['course_entry_first_read'], rows: 'entry' },
  { field: 'campus', l4: [], has: (c, x) => x.camp.length > 0 },
  { field: 'scholarships', l4: [], rows: 'sch', admitted: (r) => r.mapping_state === 'mapped', heldIf: (r) => r.mapping_state === 'needs_review' },
]

export function fieldStates(data) {
  const header = ['course_id', 'course_stable_key', 'field', 'state', 'admitted_rows', 'held_rows', 'retired_rows', 'layer4_pending_items', 'layer4_latest_decision',
    'consumer_visible', 'course_in_website_api_v2', 'course_withheld_from_search']
  const rows = []
  const G = { links: group(data.course_links, 'course_id'), fees: group(data.course_fees, 'course_id'), intakes: group(data.course_intakes, 'course_id'),
    english: group(data.english_requirements, 'course_id'), entry: group(data.course_entry_requirements, 'course_id'), sch: group(data.course_scholarships, 'course_id') }
  const camp = group(data.course_campuses, 'course_id'), l4 = group(data.layer4_course_review_items, 'entity_id')
  for (const c of data.courses) {
    const x = { camp: camp.get(c.id) || [] }
    const items = l4.get(c.id) || []
    for (const F of STATE_FIELDS) {
      let admitted = 0, held = 0, retired = 0, proposed = 0, visible = 0
      if (F.has) { admitted = F.has(c, x) ? 1 : 0 } else {
        const rs = (G[F.rows].get(c.id) || []).filter(F.filter || (() => true))
        for (const r of rs) {
          if (F.admitted) { if (F.admitted(r)) admitted++; else if (F.heldIf && F.heldIf(r)) held++; else retired++ }
          else if (r.x_admission_state === 'admitted') admitted++
          else if (r.x_admission_state === 'held') { held++; if (r.status === 'proposed') proposed++ }
          else retired++
          if (t(r.x_consumer_visible)) visible++
        }
      }
      const mine = items.filter((i) => F.l4.includes(i.field_code))
      const pending = mine.filter((i) => i.status === 'pending').length
      const decided = mine.filter((i) => !blank(i.decided_at) && i.status !== 'pending').sort((a, b) => String(b.decided_at).localeCompare(String(a.decided_at)))[0]
      let state
      if (t(c.x_website_search_blocked) && admitted) state = 'quality_held'
      else if (admitted) state = 'available'
      else if (pending) state = 'layer4_pending'
      else if (held - proposed > 0) state = 'quality_held'
      else if (proposed) state = 'processing'
      else if (decided && decided.status === 'rejected') state = 'rejected'
      else state = 'missing'
      rows.push([c.id, c.stable_key, F.field, state, admitted, held, retired, pending, decided ? decided.status : null,
        F.has ? null : visible > 0, t(c.x_in_website_api_v2), t(c.x_website_search_blocked)])
    }
  }
  return { header, rows, sheet: '12 Field states', idColumns: ['course_id', 'field'],
    note: 'States: available (admitted value held); quality_held (course withheld by an active Layer 4 search block, or only unverified rows held); layer4_pending (a real pending pipeline.layer4_review_items row, no admitted value); processing (rows proposed, not admitted, no pending item); rejected (latest Layer 4 decision rejected, no admitted value); missing (not held: this says nothing about the source). not_applicable is never assigned: no confirmed not-applicable decision is held.' }
}

export function dictionary(data, ctx) {
  const header = ['dataset', 'column', 'origin', 'type', 'not_null', 'definition', 'rows', 'filled', 'filled_pct']
  const rows = []
  const tableOf = { courses: 'catalogue.courses', course_fees: 'catalogue.course_fees', course_intakes: 'catalogue.course_intakes', course_entry_requirements: 'catalogue.course_entry_requirements',
    english_requirements: 'catalogue.course_english_requirements', course_scholarships: 'scholarship.course_mappings', scholarship_master: 'scholarship.scholarships',
    scholarship_award_tiers: 'scholarship.award_tiers', scholarship_criteria: 'scholarship.criteria', scholarship_criterion_groups: 'scholarship.criterion_groups',
    scholarship_application_windows: 'scholarship.application_windows', scholarship_offering_cycles: 'scholarship.offering_cycles', scholarship_identifiers: 'scholarship.identifiers',
    provider_rankings: 'catalogue.provider_rankings', provider_entry_matrices: 'catalogue.provider_entry_matrix', course_links: 'catalogue.course_links',
    course_campuses: 'catalogue.course_campuses', course_identifiers: 'catalogue.course_identifiers', course_pages_held: 'pipeline.coverage_course_pages',
    search_course_documents: 'search.course_documents', layer4_course_review_items: 'pipeline.layer4_review_items', providers: 'catalogue.providers' }
  const cols = new Map((ctx.dictionary.columns || []).map((c) => [`${c.table}.${c.column}`, c]))
  const rules = new Map(ctx.manifestDatasets.map((d) => [d.name, d.consumer_rule]))
  for (const [name, rs] of Object.entries(data)) {
    const head = rs.header || Object.keys(rs[0] || {})
    for (const col of head) {
      const meta = cols.get(`${tableOf[name]}.${col}`)
      const filled = rs.filter((r) => !blank(r[col])).length
      const derivedDef = col.startsWith('x_') ? (rules.get(name) && rules.get(name).includes(col) ? rules.get(name) : 'Added by the export from a joined table or a rule; see the field mapping document.') : null
      rows.push([name, col, meta ? tableOf[name] : col.startsWith('x_') ? 'export flag or join' : (tableOf[name] || name), meta?.type ?? null, meta ? String(meta.not_null) : null,
        meta?.comment ?? derivedDef, rs.length, filled, rs.length ? Math.round((filled / rs.length) * 1000) / 10 : null])
    }
  }
  return { header, rows, sheet: '13 Dictionary and coverage', idColumns: ['dataset', 'column'],
    note: 'One row per exported column: where it comes from, its database type and comment, and how many rows hold a value (filled = not null and not blank).' }
}

export function buildDerived(data, ctx) {
  return {
    website_api_v2_field_reconciliation: reconciliation(data, ctx),
    field_state_reconciliation: fieldStates(data),
    data_dictionary_and_coverage: dictionary(data, ctx),
  }
}
