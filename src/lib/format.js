// StudySearch shared formatters (B2 UI uniformity): one en-AU format for every screen.
//   Dates        29 Sep 2026
//   Date + time  29 Sep 2026, 2:37 pm
//   Numbers      25,978 (en-AU grouping)
//   Money        A$31,680 (AUD); other currencies keep their own prefix (NZ$, CA$, US$ ...)
//   Percentages  49.2% (one decimal)
// Empty or unreadable values render as an em dash, never "Invalid Date" or "NaN".
// Times are shown in Melbourne time (Australia/Melbourne, with daylight saving) for every viewer (v2.15.131);
// plain calendar dates ("YYYY-MM-DD") are shown as written.

export const EMPTY = '—'
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/

/** Parse a Date, ISO string or epoch. Plain "YYYY-MM-DD" strings are calendar dates (no time-zone shift). */
export function toDate(value) {
  if (value === null || value === undefined || value === '') return null
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value
  if (typeof value === 'string') {
    const m = value.match(DATE_ONLY)
    if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  }
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? null : d
}

// Melbourne wall-clock parts of an instant. formatToParts is the one place a time zone is applied.
const MEL = new Intl.DateTimeFormat('en-AU', { timeZone: 'Australia/Melbourne', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', hourCycle: 'h23' })
function mel(d) {
  const p = {}
  for (const x of MEL.formatToParts(d)) p[x.type] = x.value
  return { y: Number(p.year), mo: Number(p.month) - 1, d: Number(p.day), h: Number(p.hour) % 24, mi: Number(p.minute) }
}
// A plain "YYYY-MM-DD" is a calendar date: shown as written, never shifted.
function cal(value, d) {
  const m = typeof value === 'string' ? value.match(DATE_ONLY) : null
  return m ? { y: Number(m[1]), mo: Number(m[2]) - 1, d: Number(m[3]), h: 0, mi: 0 } : mel(d)
}
function clock(h, m) { return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'am' : 'pm'}` }
function time12(d) { const p = mel(d); return clock(p.h, p.mi) }

/** 29 Sep 2026 */
export function fmtDate(value, fallback = EMPTY) {
  const d = toDate(value)
  if (!d) return fallback
  const p = cal(value, d)
  return `${p.d} ${MONTHS[p.mo]} ${p.y}`
}

/** A UTC hour and minute (scheduled jobs run on UTC) as Melbourne clock time today, plus how many days later that is
 *  in Melbourne (0 or 1), so weekly and monthly schedules can name the right day. */
export function utcClockToMelbourne(utcHour, utcMinute, ref = new Date()) {
  const d = new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth(), ref.getUTCDate(), Number(utcHour), Number(utcMinute)))
  const p = mel(d)
  return { time: clock(p.h, p.mi), dayShift: p.d === d.getUTCDate() ? 0 : 1 }
}

/** 29 Sep (charts and compact columns) */
export function fmtDayMonth(value, fallback = EMPTY) {
  const d = toDate(value)
  if (!d) return fallback
  const p = cal(value, d)
  return `${p.d} ${MONTHS[p.mo]}`
}

/** 29 Sep 2026, 2:37 pm  (a plain calendar date renders without a time) */
export function fmtDateTime(value, fallback = EMPTY) {
  if (typeof value === 'string' && DATE_ONLY.test(value)) return fmtDate(value, fallback)
  const d = toDate(value)
  return d ? `${fmtDate(d)}, ${time12(d)}` : fallback
}

/** 2:37 pm */
export function fmtTime(value, fallback = EMPTY) {
  const d = toDate(value)
  return d ? time12(d) : fallback
}

/** "3 min ago", "2 h ago", "5 days ago"; older than 30 days falls back to the date. */
export function fmtRelative(value, fallback = EMPTY, now = Date.now()) {
  const d = toDate(value)
  if (!d) return fallback
  const s = Math.round((now - d.getTime()) / 1000)
  if (s < 0) return fmtDateTime(d)
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.floor(s / 60)} min ago`
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`
  if (s < 86400 * 30) { const n = Math.floor(s / 86400); return `${n} day${n === 1 ? '' : 's'} ago` }
  return fmtDate(d)
}

function finite(value) {
  if (value === null || value === undefined || value === '' || typeof value === 'boolean') return null
  const n = Number(value)
  return Number.isFinite(n) ? n : null
}

/** 25,978 — en-AU grouping. options.decimals fixes decimals; options.maxDecimals caps them (default 0 for integers, 2 otherwise). */
export function fmtNumber(value, options = {}, fallback = EMPTY) {
  const n = finite(value)
  if (n === null) return fallback
  const { decimals, maxDecimals } = options || {}
  const opts = decimals !== undefined
    ? { minimumFractionDigits: decimals, maximumFractionDigits: decimals }
    : { maximumFractionDigits: maxDecimals ?? (Number.isInteger(n) ? 0 : 2) }
  return n.toLocaleString('en-AU', opts)
}

const CURRENCY_PREFIX = { AUD: 'A$', NZD: 'NZ$', CAD: 'CA$', USD: 'US$', GBP: '£', EUR: '€', SGD: 'S$', HKD: 'HK$', INR: '₹' }

/** A$31,680 — whole amounts without cents, otherwise two decimals. options.decimals overrides. */
export function fmtMoney(amount, currency = 'AUD', options = {}, fallback = EMPTY) {
  const n = finite(amount)
  if (n === null) return fallback
  const code = String(currency || 'AUD').toUpperCase()
  const decimals = options?.decimals ?? (Number.isInteger(n) ? 0 : 2)
  const body = Math.abs(n).toLocaleString('en-AU', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })
  const prefix = CURRENCY_PREFIX[code] ?? `${code} `
  return `${n < 0 ? '-' : ''}${prefix}${body}`
}

/** 49.2% — value already in percent (49.2). */
export function fmtPercent(value, fallback = EMPTY) {
  const n = finite(value)
  if (n === null) return fallback
  return `${n.toLocaleString('en-AU', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`
}

/** 49.2% — share of a total (part / total). */
export function fmtShare(part, total, fallback = EMPTY) {
  const p = finite(part), t = finite(total)
  if (p === null || !t) return fallback
  return fmtPercent((p / t) * 100)
}

/** 1.2 MB / 340 KB */
export function fmtBytes(bytes, fallback = EMPTY) {
  const n = finite(bytes)
  if (n === null) return fallback
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  let v = n, i = 0
  while (Math.abs(v) >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return `${fmtNumber(v, { maxDecimals: i === 0 ? 0 : 1 })} ${units[i]}`
}
