// CF-247 S1-RM-Design (Platform Admin 18 Nov 2026 21:23, s694): the correlated, read-only sections of the Course and Provider
// drawers. Each adapter is a pure join over reads the admin already has (no new schema): the provider's campuses and their
// locality (admin_provider_destination_read), city figures, career outcomes and study rules (admin_destination_review), the
// course's applicable rules (admin_course_destination_read), rankings (admin_read provider_ranking_history), entry
// requirements (admin_entry_requirements) and the course's scholarships (course detail). CARD_SPEC is the column and field
// list for every card; the admin spec document prints it, and s694 holds the screen to it.
import { climateIcon } from './climate-icons.js'

const F = (key, label, column, v3, audience = 'student') => ({ key, label, column, v3, audience })
export const CARD_SPEC = {
  course: [
    { id: 'location', title: 'Location & weather', join: 'course › campus › postcode › locality (security.destination_locality_for_postcode_v1, approved localities only)', fields: [
      F('campus', 'Campus and city', 'catalogue.campuses.name, city', 'item.campuses[].name'),
      F('locality', 'Locality (city)', 'destination.localities.name', 'item.campuses[].locality.name'),
      F('summer_max', 'Summer mean max (°C)', "locality_metrics.numeric_value · metric_key climate_summer_mean_max_c", 'localities[].metrics[] key climate_summer_mean_max_c'),
      F('summer_min', 'Summer mean min (°C)', "locality_metrics · climate_summer_mean_min_c", 'localities[].metrics[] key climate_summer_mean_min_c'),
      F('winter_max', 'Winter mean max (°C)', "locality_metrics · climate_winter_mean_max_c", 'localities[].metrics[] key climate_winter_mean_max_c'),
      F('winter_min', 'Winter mean min (°C)', "locality_metrics · climate_winter_mean_min_c", 'localities[].metrics[] key climate_winter_mean_min_c'),
      F('rainfall', 'Annual rainfall (mm) with climate icon', "locality_metrics · climate_annual_rainfall_mm", 'localities[].metrics[] key climate_annual_rainfall_mm'),
      F('population', 'City population (ABS)', "locality_metrics · metric_category population (erp_persons)", 'localities[].metrics[] category population'),
      F('attribution', 'Attribution and period', 'locality_metrics.attribution_text, reference_period', 'localities[].metrics[].attribution'),
      F('match_share', 'Postcode match share', 'locality_postcodes.containment_share', null, 'internal'),
      F('dataset_edition', 'Dataset edition and status', 'locality_metrics.dataset_edition, status', null, 'internal'),
    ] },
    { id: 'careers', title: 'Career pathway, jobs & salary outlook', join: 'course field of study › career_outcomes.study_area_code (country of the course)', fields: [
      F('occupation', 'Occupation and code', 'career_outcomes.occupation_title, occupation_scheme, occupation_code', 'career_outcomes[].occupation_code'),
      F('growth', 'Projected growth / outlook', 'career_outcomes.job_outlook_rating, outlook_horizon_years', 'career_outcomes[].outlook'),
      F('median_salary', 'Median salary (AUD a year)', 'career_outcomes.median_salary, salary_currency, salary_period', 'career_outcomes[].median_salary'),
      F('shortage', 'Skills shortage status', 'career_outcomes.skill_shortage_status', 'career_outcomes[].shortage'),
      F('attribution', 'Attribution and period', 'career_outcomes.attribution_text, reference_period', 'career_outcomes[].attribution'),
      F('dataset_edition', 'Dataset edition and status', 'career_outcomes.dataset_edition, status', null, 'internal'),
    ] },
    { id: 'visa', title: 'Visa & living-cost snapshot', join: 'course › provider › country › study_rules (proven rule_applicability)', fields: [
      F('work_hours', 'Work limit while studying (hours a fortnight)', 'study_rules.work_hours_fortnight · work_rights', 'study_rules[] rule_category work_rights'),
      F('post_study_work', 'Post-study work rights (years)', 'study_rules.post_study_work_years_min, _max', 'study_rules[] rule_category post_study_work'),
      F('financial_capacity', 'Financial-capacity benchmark (a year)', 'study_rules.financial_capacity_annual, currency_code', 'study_rules[] rule_category financial_capacity'),
      F('visa_fees', 'Visa application charges', 'study_rules.application_fee_amount · visa_fee', 'study_rules[] rule_category visa_fee'),
      F('health_cover', 'Health cover rule', 'study_rules.title · health_insurance', 'study_rules[] rule_category health_insurance'),
      F('rule_id', 'Rule id', 'study_rules.id', null, 'internal'),
      F('approval_status', 'Approval and edition status', 'study_rules.approval_status, editions.status', null, 'internal'),
    ] },
    { id: 'entry', title: 'Entry requirements & scholarships', join: 'course › entry requirement rows and published scholarships', fields: [
      F('entry_rows', 'Academic entry requirements (kind, requirement, score and basis)', 'admin_entry_requirements course rows', 'item.entry_requirements.summary'),
      F('scholarships', 'Published scholarships (name, value, closing date)', 'course_scholarships.items', 'item.scholarships[].name'),
      F('raw_quote', 'Quote read from the page', 'entry requirement quote', null, 'internal'),
      F('layer4_queue_state', 'Waiting in Layer 4', 'entry requirement status proposed', null, 'internal'),
    ] },
  ],
  provider: [
    { id: 'rankings', title: 'Rankings', join: 'provider_id › ranking observations (provider_ranking_history)', fields: [
      F('qs', 'QS World University Rankings (latest edition and rank)', 'system_code qs_wur · edition_year, rank_display', 'rankings[] system qs_wur'),
      F('the', 'THE World University Rankings', 'system_code the_wur', 'rankings[] system the_wur'),
      F('arwu', 'ARWU (Academic Ranking of World Universities)', 'system_code arwu', 'rankings[] system arwu'),
      F('subject', 'Subject ranks', 'any other system_code (subject tables)', 'rankings[] subject'),
      F('overall_score', 'Overall score', 'overall_score', null, 'internal'),
    ] },
    { id: 'campus_cities', title: 'Campus city profiles', join: 'provider › campuses › locality › city figures', fields: [
      F('campus', 'Campus (primary first)', 'catalogue.campuses.name, is_primary', 'item.campuses[].is_primary'),
      F('weather', 'Summer and winter means, rainfall, climate icon', 'locality_metrics climate_*', 'localities[].metrics[] category climate'),
      F('population', 'City population', 'locality_metrics population', 'localities[].metrics[] category population'),
      F('match_share', 'Postcode match share and Layer 4 state', 'locality_postcodes.containment_share, in_layer4', null, 'internal'),
    ] },
    { id: 'scholarships_accreditations', title: 'Scholarships & accreditations', join: 'provider › scholarships and accreditation bodies', fields: [
      F('scholarships', 'Scholarships held for the provider', 'provider_detail.scholarship_count', 'item.scholarships[]'),
      F('accreditations', 'Accreditations (AACSB, EQUIS, AMBA)', 'catalogue.provider_accreditations.body_code (API v3 only today)', 'item.provider.accreditations[].body_code'),
      F('registrations', 'Provider registrations (CRICOS and others)', 'provider registrations', 'item.provider.registrations[]'),
    ] },
  ],
}
export const specFields = (blade, id) => (CARD_SPEC[blade] || []).find(c => c.id === id)?.fields || []

const num = v => (v == null || v === '' || Number.isNaN(Number(v)) ? null : Number(v))
const SHOWN = new Set(['approved', 'published'])
export const studentShown = row => !row?.status || SHOWN.has(String(row.status))

// course campuses (name, city) matched to the provider's campuses that carry a locality; the primary campus when none matches
export function campusLocalities(courseCampuses, providerCampuses) {
  const pcs = Array.isArray(providerCampuses) ? providerCampuses : []
  const norm = s => String(s || '').trim().toLowerCase()
  const mine = (Array.isArray(courseCampuses) ? courseCampuses : []).map(c => pcs.find(p => (norm(p.name) && norm(p.name) === norm(c.name)) || (norm(p.city) && norm(p.city) === norm(c.city) && p.locality)) || null).filter(Boolean)
  const list = mine.length ? mine : pcs.filter(p => p.is_primary).slice(0, 1)
  const seen = new Set()
  return list.filter(p => { const k = p.campus_id || p.name; if (seen.has(k)) return false; seen.add(k); return true })
    .map(p => ({ campus: p.name || p.city || 'Campus', city: p.city || null, is_primary: !!p.is_primary, locality: p.locality || null,
      pending: p.locality ? null : (p.in_layer4 ? 'in_layer4' : p.pending_locality ? 'pending_locality' : 'no_match'), match_share: num(p.locality?.match_share) }))
}

const CLIMATE_KEYS = { summer_max: 'climate_summer_mean_max_c', summer_min: 'climate_summer_mean_min_c', winter_max: 'climate_winter_mean_max_c', winter_min: 'climate_winter_mean_min_c', rainfall: 'climate_annual_rainfall_mm' }
// one city's figures: climate means and rainfall (with its icon), population, and the attribution lines the licence requires
export function cityProfile(localityId, metricRows, { student = false } = {}) {
  const rows = (Array.isArray(metricRows) ? metricRows : []).filter(r => r.locality_id === localityId && (!student || studentShown(r)))
  const by = k => rows.find(r => r.metric_key === k)
  const climate = Object.fromEntries(Object.entries(CLIMATE_KEYS).map(([k, key]) => [k, num(by(key)?.numeric_value)]))
  const rain = by(CLIMATE_KEYS.rainfall)
  const pop = rows.find(r => r.metric_category === 'population')
  const hasClimate = Object.values(climate).some(v => v != null)
  return {
    locality_id: localityId, has_climate: hasClimate, climate,
    icon: rain ? climateIcon(rain.metric_key, rain.numeric_value) : (by(CLIMATE_KEYS.winter_min) ? climateIcon(CLIMATE_KEYS.winter_min, by(CLIMATE_KEYS.winter_min).numeric_value) : null),
    population: pop ? { value: num(pop.numeric_value), period: pop.reference_period || null, key: pop.metric_key } : null,
    attribution: [...new Set(rows.map(r => r.attribution_text).filter(Boolean))],
    periods: [...new Set(rows.map(r => r.reference_period).filter(Boolean))],
    editions: [...new Set(rows.map(r => r.dataset_edition).filter(Boolean))],
    statuses: [...new Set(rows.map(r => r.status).filter(Boolean))],
  }
}

// the course's field of study (ASCED, e.g. asced-0803) linked to career outcomes by study area; why it is empty when it is
export function careerOutlook(fieldCode, careerRows, { student = false, country = null } = {}) {
  const rows = (Array.isArray(careerRows) ? careerRows : []).filter(r => (!student || studentShown(r)) && (!country || !r.country_code || r.country_code === country))
  if (rows === null || !rows.length) return { state: 'not_loaded', items: [], held: 0 }
  const code = String(fieldCode || '').replace(/^asced-/, '')
  const linked = rows.filter(r => r.study_area_code && code && (code.startsWith(String(r.study_area_code)) || String(r.study_area_code).startsWith(code.slice(0, 2))))
  const withFigures = rows.filter(r => r.median_salary != null || r.job_outlook_rating != null || r.skill_shortage_status != null).length
  if (!linked.length) return { state: withFigures ? 'no_field_link' : 'figures_loading', items: [], held: rows.length, with_figures: withFigures }
  const items = linked.map(r => ({ occupation: r.occupation_title, code: `${r.occupation_scheme || ''} ${r.occupation_code || ''}`.trim(),
    growth: r.job_outlook_rating || null, horizon: num(r.outlook_horizon_years), median_salary: num(r.median_salary), currency: r.salary_currency || 'AUD',
    period: r.salary_period || 'annual', shortage: r.skill_shortage_status || null, attribution: r.attribution_text || null, edition: r.dataset_edition || null, status: r.status || null }))
    .sort((a, b) => (b.median_salary ?? -1) - (a.median_salary ?? -1))
  return { state: 'matched', items, held: rows.length, with_figures: withFigures }
}

// the destination's visa and living-cost rules that apply to the course, with their figures when the full rule rows are readable
export function visaSnapshot(courseRules, ruleRows, { student = false } = {}) {
  const applied = (Array.isArray(courseRules) ? courseRules : []).filter(r => !student || SHOWN.has(String(r.approval_status || 'approved')))
  const full = new Map((Array.isArray(ruleRows) ? ruleRows : []).map(r => [r.id, r]))
  const rows = applied.map(r => ({ ...r, ...(full.get(r.rule_id) || {}), rule_id: r.rule_id, title: r.title }))
  const cat = c => rows.filter(r => String(r.rule_category) === c)
  const work = cat('work_rights')[0], psw = rows.find(r => r.post_study_work_years_min != null || r.post_study_work_years_max != null)
  const fin = rows.find(r => r.financial_capacity_annual != null) || cat('financial_capacity')[0]
  return {
    rules: rows.length,
    work_hours_fortnight: num(work?.work_hours_fortnight ?? work?.numeric_threshold),
    post_study_work: psw ? { min: num(psw.post_study_work_years_min), max: num(psw.post_study_work_years_max), title: psw.title } : null,
    financial_capacity: fin ? { amount: num(fin.financial_capacity_annual ?? fin.numeric_threshold), currency: fin.currency_code || 'AUD', title: fin.title } : null,
    visa_fees: cat('visa_fee').map(r => ({ title: r.title, amount: num(r.application_fee_amount ?? r.numeric_threshold), currency: r.currency_code || r.fee_currency || 'AUD', rule_id: r.rule_id, status: r.approval_status })),
    health_cover: cat('health_insurance').map(r => ({ title: r.title, rule_id: r.rule_id })),
    items: rows,
  }
}

const SYSTEMS = { qs_wur: 'QS World University Rankings', the_wur: 'THE World University Rankings', arwu: 'ARWU' }
// latest and previous edition per ranking system; any other system is a subject rank
export function rankingSnapshot(items) {
  const list = Array.isArray(items) ? items : []
  const sys = Object.entries(SYSTEMS).map(([code, label]) => {
    const rows = list.filter(r => r.system_code === code).sort((a, b) => Number(b.edition_year) - Number(a.edition_year))
    return { code, label, latest: rows[0] ? { year: rows[0].edition_year, rank: rows[0].rank_display || rows[0].rank_exact || null, score: num(rows[0].overall_score) } : null,
      previous: rows[1] ? { year: rows[1].edition_year, rank: rows[1].rank_display || rows[1].rank_exact || null } : null }
  })
  const subject = list.filter(r => !SYSTEMS[r.system_code]).map(r => ({ label: r.subject_name || r.system_name || r.system_code, year: r.edition_year, rank: r.rank_display || r.rank_exact || null }))
  return { systems: sys, subject, ranked: sys.filter(s => s.latest).length }
}

export const EMPTY_CAREERS = {
  not_loaded: 'Career outcomes are not loaded for this country yet.',
  figures_loading: 'Occupations are held; salary, growth and shortage figures arrive with the Jobs and Skills Australia load.',
  no_field_link: 'No occupation is linked to this field of study yet.',
}
