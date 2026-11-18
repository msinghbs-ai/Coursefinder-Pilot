// Fixtures for the correlated Course and Provider drawer sections (s694, s696): one Melbourne campus with BOM climate and ABS
// population figures, occupations held without figures yet (JSA), and the Australian student visa rules.
export const L1 = 'b82d1417-0000-4000-8000-00000000me1b'
export const providerDestination = { found: true, campuses: [
  { campus_id: 'c1', name: 'RMIT University - 124 Latrobe Street, Melbourne', city: 'Melbourne', postcode: '3000', is_primary: true, locality: { locality_id: L1, name: 'Melbourne', match_share: 0.987 }, in_layer4: false },
  { campus_id: 'c2', name: 'Bundoora campus', city: 'Bundoora', postcode: '3083', is_primary: false, locality: null, in_layer4: true }],
  registrations: [{ scheme: 'cricos', code: '00122A', status: 'active', label: 'CRICOS' }] }
const m = (id, category, key, value, unit, extra = {}) => ({ id, locality_id: L1, locality_name: 'Melbourne', country_code: 'AU', metric_category: category, metric_key: key, numeric_value: value, unit,
  reference_period: category === 'climate' ? '1991-2020' : '2024', dataset_edition: category === 'climate' ? 'BOM climate normals 1991-2020' : 'ABS ERP 2024', status: 'approved',
  attribution_text: category === 'climate' ? '© Commonwealth of Australia, Bureau of Meteorology' : 'Source: Australian Bureau of Statistics', source_url: 'https://example.gov.au', ...extra })
export const metrics = [
  m('mt1', 'climate', 'climate_summer_mean_max_c', 26.1, '°C'), m('mt2', 'climate', 'climate_summer_mean_min_c', 14.6, '°C'),
  m('mt3', 'climate', 'climate_winter_mean_max_c', 14.2, '°C'), m('mt4', 'climate', 'climate_winter_mean_min_c', 6.4, '°C'),
  m('mt5', 'climate', 'climate_annual_rainfall_mm', 648, 'mm'), m('mt6', 'population', 'erp_persons', 5350705, 'people'),
  { ...m('mt7', 'population', 'erp_persons', 254000, 'people'), id: 'mt7', locality_id: 'other', locality_name: 'Geelong' },
  { ...m('mt8', 'cost_of_living', 'rent_weekly_median', 560, 'AUD a week', { currency_code: 'AUD' }), id: 'mt8' }]
export const careers = [
  { id: 'co1', occupation_title: 'Accountant', occupation_scheme: 'OSCA', occupation_code: '221111', study_area_code: null, median_salary: null, status: 'approved', dataset_edition: 'JSA OSCA 2025' },
  { id: 'co2', occupation_title: 'Marketing Specialist', occupation_scheme: 'OSCA', occupation_code: '225113', study_area_code: null, median_salary: null, status: 'approved', dataset_edition: 'JSA OSCA 2025' }]
export const ruleRows = [
  { id: 'r-work', title: 'Student visa (subclass 500) work limit while the course is in session', rule_category: 'work_rights', work_hours_fortnight: 48, numeric_threshold: 48, approval_status: 'approved' },
  { id: 'r-fee', title: 'Student visa (subclass 500) application charge', rule_category: 'visa_fee', application_fee_amount: 2500, currency_code: 'AUD', approval_status: 'approved' },
  { id: 'r-osh', title: 'Student visa (subclass 500) Overseas Student Health Cover', rule_category: 'health_insurance', approval_status: 'approved' }]
export const courseDestination = { found: true, country_code: 'AU', registrations: [], field_schemes: [], excluded_rules: 0,
  study_rules: ruleRows.map(r => ({ rule_id: r.id, title: r.title, rule_category: r.rule_category, applies_through: 'country', approval_status: 'approved', edition_status: 'published' })) }
export const entry = { rows: [{ id: 'e1', kind: 'atar', description: 'Minimum ATAR', min_entry_score: 60, min_entry_score_basis: 'ATAR', status: 'approved', quote: 'Minimum selection rank 60' },
  { id: 'e2', kind: 'prerequisite', description: 'Units 3 and 4: English (EAL) 25', status: 'proposed', quote: 'Units 3 and 4: a study score of at least 25 in English (EAL)' }] }

export async function routeCorrelated(page) {
  const json = (r, data) => r.fulfill({ json: data })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_destination_read', r => json(r, providerDestination))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_course_destination_read', r => json(r, courseDestination))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_entry_requirements', r => json(r, entry))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_destination_review', r => {
    const k = (r.request().postDataJSON() || {}).p_kind
    return json(r, { rows: k === 'locality_metric' ? metrics : k === 'career_outcome' ? careers : k === 'study_rule' ? ruleRows : [] })
  })
}
