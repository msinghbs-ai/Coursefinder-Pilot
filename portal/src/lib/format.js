// Plain-language formatting. A value the platform does not hold is "Not recorded"; a value the provider does not state is
// "Not published". The two are never mixed (design decisions, 25 Nov 2026).
export const NOT_RECORDED = 'Not recorded'
export const NOT_PUBLISHED = 'Not published'

export function money(amount, currency) {
  const n = Number(amount)
  if (amount === null || amount === undefined || amount === '' || !Number.isFinite(n)) return null
  const code = String(currency || '').toUpperCase()
  try {
    // en-US so the dollar of each country is told apart (A$, NZ$, CA$).
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: code || 'AUD', maximumFractionDigits: 0 }).format(n)
  } catch { return `${n.toLocaleString('en-AU')}${code ? ` ${code}` : ''}` }
}

// Calendar facts (a year is 52 weeks or 12 months), not operational values.
export function durationInYears(value, unit) {
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return null
  const u = String(unit || '').toLowerCase()
  if (u.startsWith('week')) return n / 52
  if (u.startsWith('month')) return n / 12
  if (u.startsWith('semester')) return n / 2
  if (u.startsWith('year')) return n
  return null
}

export function durationText(value, unit) {
  const n = Number(value)
  if (!Number.isFinite(n) || n <= 0) return NOT_RECORDED
  const u = String(unit || '').toLowerCase()
  const plural = (x, word) => `${x} ${word}${x === 1 ? '' : 's'}`
  if (u.startsWith('year')) return plural(n, 'year')
  if (u.startsWith('semester')) return plural(n, 'semester')
  if (u.startsWith('month')) return n >= 12 && n % 6 === 0 ? plural(n / 12, 'year') : plural(n, 'month')
  if (u.startsWith('week')) {
    if (n < 52) return plural(n, 'week')
    const years = Math.round((n / 52) * 2) / 2
    return plural(years, 'year')
  }
  return NOT_RECORDED
}

const dateParts = (iso, timeZone) => {
  const d = new Date(/^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso}T00:00:00Z` : iso)
  return Number.isNaN(d.getTime()) ? null : { d, timeZone: /^\d{4}-\d{2}-\d{2}$/.test(iso) ? 'UTC' : timeZone }
}

export function dateText(iso, precision) {
  if (!iso) return null
  const p = dateParts(iso, 'Australia/Melbourne')
  if (!p) return null
  const fmt = opts => new Intl.DateTimeFormat('en-AU', { timeZone: p.timeZone, ...opts }).format(p.d)
  const kind = String(precision || 'day').toLowerCase()
  if (kind === 'year') return fmt({ year: 'numeric' })
  if (kind === 'month') return fmt({ month: 'short', year: 'numeric' })
  return fmt({ day: 'numeric', month: 'short', year: 'numeric' })
}

export function initials(name) {
  const words = String(name || '').replace(/\(.*?\)/g, '').split(/\s+/).filter(w => /^[A-Za-z]/.test(w) && !/^(of|the|and|for)$/i.test(w))
  return (words.slice(0, 2).map(w => w[0]).join('') || '?').toUpperCase()
}

const FEE_TYPE_WORDS = { tuition: 'tuition', tuition_fee: 'tuition' }

// The scholarship value is built from the structured award fields. The free-text value is not shown: it often holds page text.
export function awardValue(s) {
  const maximum = s.award_value_is_maximum ? 'Up to ' : ''
  const of = FEE_TYPE_WORDS[s.award_applies_to_fee_type] || ''
  if (s.award_value_type === 'percentage' && Number(s.award_percentage) > 0) {
    return `${maximum}${Number(s.award_percentage)}%${of ? ` of ${of}` : ''}`
  }
  if (s.award_value_type === 'fixed_amount' && Number(s.award_amount) > 0) {
    const m = money(s.award_amount, s.award_currency_code)
    return m ? `${maximum}${m}${of ? ` towards ${of}` : ''}` : NOT_RECORDED
  }
  return NOT_RECORDED
}

// State codes are held as AU-QLD, CA-ON; people read QLD, ON.
export const stateShort = code => String(code || '').replace(/^[A-Z]{2}-/, '')
