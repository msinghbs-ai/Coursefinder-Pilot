// v1.1 Counsellor UI (S1-API-Frontend-Delivery, s990): pure display helpers. No list of providers, countries or levels is written here (s930).
const SYMBOL = { AUD: 'A$', NZD: 'NZ$', CAD: 'C$', USD: 'US$', GBP: '£', EUR: '€', INR: '₹' }
export const money = (amount, currency) => amount == null || amount === '' ? '—' : (SYMBOL[currency] || (currency ? currency + ' ' : '')) + Number(amount).toLocaleString('en-AU', { maximumFractionDigits: 0 })
export const humanise = v => v ? String(v).replace(/_/g, ' ').replace(/^./, c => c.toUpperCase()) : '—'
export const duration = (value, unit) => {
  if (value == null) return '—'
  if (unit === 'weeks' && value % 52 === 0) return value / 52 + (value === 52 ? ' year' : ' years')
  return value + ' ' + (unit || '')
}
export const stateOf = code => String(code || '').split('-').pop()
export const fdate = d => { if (!d) return ''; const x = new Date(String(d).slice(0, 10) + 'T00:00:00'); return isNaN(x) ? '' : x.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' }) }

/** REQ-117: [{state, names[]}] from a course's cities[] (state code, then one name per distinct locality, campus name when no locality). Never a bare count. */
export function locGroups(cities) {
  const by = new Map()
  for (const c of cities || []) {
    const st = stateOf(c.subdivision_code) || c.subdivision_name || ''
    const name = c.city || c.campus || ''
    if (!by.has(st)) by.set(st, [])
    if (name && !by.get(st).includes(name)) by.get(st).push(name)
  }
  return [...by.entries()].map(([state, names]) => ({ state, names }))
}

/** Best-effort text for a value the read holds as a string, an object or a list (entry and scholarship summaries). */
export function textOf(v) {
  if (v == null || v === '') return ''
  if (typeof v === 'string' || typeof v === 'number') return String(v)
  if (Array.isArray(v)) return v.map(textOf).filter(Boolean).join('; ')
  for (const k of ['summary', 'text', 'label', 'headline', 'name', 'value_text']) if (v[k]) return textOf(v[k])
  return ''
}
/** The international annual tuition from a course detail's fees[]; a total-course fee is labelled as such, never passed off as annual. */
export function annualFee(detail) {
  const fees = (detail?.fees || []).filter(f => f.amount != null && (!f.audience || f.audience === 'international'))
  const annual = fees.find(f => /year|annual/i.test(f.basis || '') || f.year)
  if (annual) return money(annual.amount, annual.currency) + ' a year'
  const other = fees[0]
  return other ? money(other.amount, other.currency) + ' (' + humanise(other.basis || 'total').toLowerCase() + ')' : 'Not published by provider'
}
