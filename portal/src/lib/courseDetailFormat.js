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

// s1355: a registered fee is labelled with the course's own register (CRICOS, NZQA, MTCU ... from `regulator.label`), never a fixed one. With no register the label says "registered" only.
export const feeLabel = (f, regulator) => {
  const reg = regulator && regulator.label ? ` (${regulator.label})` : ''
  if (f.fee_type === 'provider_current_tuition') return /total/i.test(f.basis || '') ? 'Tuition for the whole course (provider, indicative)' : 'Tuition per year (provider)'
  if (f.fee_type === 'tuition') return `Registered tuition for the whole course${reg}`
  if (f.fee_type === 'non_tuition') return `Non-tuition fees for the whole course${reg}`
  if (f.fee_type === 'estimated_total_course_cost') return `Estimated total course cost${reg}`
  return sentence(f.fee_type) || 'Fee'
}
// s1356: "Lowest per year" compares annual fees only when every fee is in one currency; amounts in different currencies are never ranked against each other (no conversion is held).
export function lowestAnnualFee(fees) {
  const held = (fees || []).filter(f => f && Number(f.per_year) > 0)
  if (held.length < 2) return null
  const cur = new Set(held.map(f => String(f.currency || '').toUpperCase()))
  return cur.size === 1 ? Math.min(...held.map(f => Number(f.per_year))) : null
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
  if (/^[A-Z]{3}$/.test(String(o.unit || ''))) return money(n, o.unit) // s1355: any ISO currency unit (AUD, NZD, CAD, GBP ...), not AUD only
  if (o.unit === 'percent') return `${Math.round(n * 10) / 10}%`
  return String(n)
}
export const intakeText = i => [i.label || dateText(i.start_date, 'day'), i.year && !String(i.label || '').includes(String(i.year)) ? i.year : ''].filter(Boolean).join(' ') || NOT_RECORDED
export const deliveryText = m => DELIVERY[m] || NOT_RECORDED
export { durationText }

// s1220: the provider's country-by-country entry matrix (portal_course_detail_v1 entry_matrix, s1216). Each row is shown as recorded;
// a row that names no country applies to every country.
const valueText = (v, scale) => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? '' : `${Number(v)}${/percent/i.test(scale || '') ? '%' : ''}`)
const scaleText = scale => (scale && !/^(none|percent(age)?)$/i.test(scale) ? sentence(scale).replace(/\b(gpa|atar|ib|cgpa|wam)\b/gi, w => w.toUpperCase()) : '')
function itemText(x) {
  if (x === null || x === undefined) return ''
  if (typeof x !== 'object') return String(x).trim()
  const name = x.subject || x.name || x.label || x.qualification || ''
  const grade = x.min_grade || x.grade || (x.min_value !== undefined && x.min_value !== null ? String(x.min_value) : '')
  return [name, grade].filter(Boolean).join(' ') || Object.values(x).filter(v => v !== null && typeof v !== 'object').join(' ')
}
export function conditionsText(c) {
  if (!c || typeof c !== 'object') return ''
  const parts = []
  if (Number.isFinite(Number(c.best_n)) && c.best_n !== null) parts.push(`Best ${Number(c.best_n)} subjects`)
  const subs = Array.isArray(c.subject_minimums) ? c.subject_minimums.map(itemText).filter(Boolean) : []
  if (subs.length) parts.push(`Subject minimums: ${subs.join('; ')}`)
  const alts = Array.isArray(c.alternatives) ? c.alternatives.map(itemText).filter(Boolean) : []
  if (alts.length) parts.push(`Alternatives: ${alts.join('; ')}`)
  return parts.join(' · ')
}
export function matrixLine(r) {
  const value = valueText(r.min_value, r.grade_scale)
  return {
    country: r.country_name || r.country_code || 'Every country',
    countryCode: r.country_code || '',
    qualification: r.qualification || '',
    grade: r.min_grade || value,
    scale: scaleText(r.grade_scale),
    band: r.benchmark_band ? sentence(r.benchmark_band) : '',
    level: [r.course_label, r.level_label].filter(Boolean).join(' · '),
    forCourse: r.for_this_course === true,
    scope: r.scope || (r.for_this_course === true ? 'course' : ''),
    conditions: conditionsText(r.conditions),
    asAt: r.as_at || '',
    url: r.source_url || '',
  }
}
// The rows for the student's country, with the rows that name no country; every row when no country is chosen.
export const matrixForMarket = (rows, market) => (rows || []).filter(r => !market || !r.country_code || r.country_code === market)

// s1222: matrix rows grouped as the counsellor reads them: this course, this study level, every course at the provider.
export const SCOPES = [['course', 'This course'], ['study_level', 'This study level'], ['provider', 'Every course at the provider']]
export function groupByScope(lines) {
  const out = SCOPES.map(([key, label]) => ({ key, label, rows: lines.filter(l => (l.scope || 'provider') === key) }))
  const known = new Set(SCOPES.map(s => s[0]))
  const other = lines.filter(l => l.scope && !known.has(l.scope))
  if (other.length) out[2].rows.push(...other)
  return out.filter(g => g.rows.length)
}
// s1222: the one annual tuition fee (portal.primary_fee_v1): the amount, and "per year" with its year and source.
export const primaryFeeAmount = f => (f && (Number(f.per_year) || Number(f.amount)) ? money(Number(f.per_year) || Number(f.amount), f.currency) : null)
export const primaryFeeNote = f => (f ? ['per year', f.year ? `${f.year} fee` : '', 'provider'].filter(Boolean).join(' · ') : '')
// s1222: a concise card shows only what is held; these return '' rather than "Not recorded".
export const lengthOrBlank = (v, u) => { const t = durationText(v, u); return t === NOT_RECORDED ? '' : t }

