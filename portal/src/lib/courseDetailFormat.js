import { money, dateText, durationText, NOT_RECORDED } from './format.js'

// Pure formatting for the Course details panel and the Entry Requirements screen (no network, so a spec can load it). They read what the platform holds, through portal_course_detail_v1 and
// portal_aer_list_v1 (s1214). Nothing is calculated here: fee lines are shown as recorded and never added together, and
// a value the platform does not hold reads "Not recorded".

export const DELIVERY = { on_campus: 'On campus', online: 'Online', blended: 'Blended', on_campus_and_online: 'On campus and online' }

export const ENTRY_KIND = {
  minimum_grade: 'Minimum grade', prior_qualification: 'Prior qualification', subject_prerequisite: 'Subject requirement',
  work_experience: 'Work experience', portfolio_interview: 'Portfolio or interview', general_note: 'Note', override: 'Other pathway',
}
const words = s => String(s || '').replace(/[_-]+/g, ' ').trim()
const sentence = s => { const t = words(s); return t ? t.charAt(0).toUpperCase() + t.slice(1) : '' }

export const feeLabel = f => {
  if (f.fee_type === 'provider_current_tuition') return /total/i.test(f.basis || '') ? 'Tuition for the whole course (provider, indicative)' : 'Tuition per year (provider)'
  if (f.fee_type === 'tuition') return 'Registered tuition for the whole course (CRICOS)'
  if (f.fee_type === 'non_tuition') return 'Non-tuition fees for the whole course (CRICOS)'
  if (f.fee_type === 'estimated_total_course_cost') return 'Estimated total course cost (CRICOS)'
  return sentence(f.fee_type) || 'Fee'
}
export const feeIsAnnual = f => f.fee_type === 'provider_current_tuition' && !/total/i.test(f.basis || '')
export const feeAmount = f => money(f.amount, f.currency) || NOT_RECORDED
export const feeAudience = f => (f.audience === 'domestic' ? 'Domestic students' : f.audience === 'international' ? 'International students' : '')

// One academic entry line: the main words, the grade or score where one is held, and where it applies.
export function entryLine(r) {
  const main = r.description || ''
  const value = r.min_value !== null && r.min_value !== undefined && r.min_value !== '' ? `${Number(r.min_value)}${/percent/i.test(r.grade_scale || '') ? '%' : r.grade_scale ? ` (${r.grade_scale})` : ''}` : ''
  const score = r.min_entry_score !== null && r.min_entry_score !== undefined && r.min_entry_score !== '' ? `${Number(r.min_entry_score)}${r.min_entry_score_basis ? ` ${sentence(r.min_entry_score_basis)}` : ''}` : ''
  const grade = r.min_grade && main.includes(r.min_grade) ? '' : (r.min_grade || value || score)
  return { kind: ENTRY_KIND[r.kind] || sentence(r.kind), main, grade, country: r.country_code || '', countryName: r.country_name || '', url: r.source_url || '', asAt: r.as_at || '' }
}
// What applies to a student: lines that name no country apply to everyone; a line that names a country applies to that country only.
export const entryForMarket = (rows, market) => (rows || []).filter(r => !r.country_code || (market && r.country_code === market))
export function englishLine(e) {
  const overall = e.overall_score !== null && e.overall_score !== undefined ? `${Number(e.overall_score)} overall` : e.score_grade || ''
  const comps = e.component_scores && typeof e.component_scores === 'object' ? Object.entries(e.component_scores).filter(([, v]) => v !== null && v !== '').map(([k, v]) => `${sentence(k)} ${v}`) : []
  return { test: e.test_name || e.test_code || 'English test', overall, parts: comps.join(' · '), notes: e.notes || '' }
}
export function outcomeValue(o) {
  const n = o.value === null || o.value === undefined || o.value === '' ? NaN : Number(o.value)
  if (!Number.isFinite(n)) return NOT_RECORDED
  if (o.unit === 'AUD') return money(n, 'AUD')
  if (o.unit === 'percent') return `${Math.round(n * 10) / 10}%`
  return String(n)
}
export const intakeText = i => [i.label || dateText(i.start_date, 'day'), i.year && !String(i.label || '').includes(String(i.year)) ? i.year : ''].filter(Boolean).join(' ') || NOT_RECORDED
export const deliveryText = m => DELIVERY[m] || NOT_RECORDED
export { durationText }
