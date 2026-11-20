// CF-247 s851 (S1-Fees-Intakes, Platform Admin 20 Nov 2026 15:11 AEDT: "$0-spend deterministic pattern-and-quote extractor over already-stored university pages").
// A pure, deterministic reader of three course facts a stored course page states in words: the international tuition fee (amount, currency, basis), the intake
// (start) months and the application closing date (or a rolling-admission statement). No model, no fetch, no write: it takes the page's text and the course's
// country and returns readings, each with a verbatim quote that is a substring of that text (checked here, so a reading never carries words the page does not hold).
// The database decides what is admitted (security.fid_det_record_v1): this module only reads.
export const FID_DET_VERSION = "fid-det-v1.0"

export type FidReading =
  | { kind: "fee"; amount: number; currency: string; basis: "annual" | "per_semester" | "course_total" | "per_unit"; fee_year: number | null; quote: string }
  | { kind: "intake"; months: string[]; labels: string[]; year: number | null; quote: string }
  | { kind: "deadline"; date: string | null; rolling: boolean; intake_hint: string | null; quote: string }

export type FidResult = { readings: FidReading[]; ambiguous: string[] }

const MAX_QUOTE = 320 // fixed: a quote is a sentence or line, not a paragraph
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const MON = "(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)"
const monthOf = (s: string): string | null => { const k = s.slice(0, 3).toLowerCase(); const i = MONTHS.findIndex((m) => m.slice(0, 3).toLowerCase() === k); return i < 0 ? null : MONTHS[i] }
export const CURRENCY: Record<string, string> = { AU: "AUD", NZ: "NZD", CA: "CAD" }

// the page's lines and sentences; a quote is one of these, so it is on the text word for word
export function fidUnits(text: string): string[] {
  const out: string[] = []
  for (const line of text.split(/\n+/)) {
    const l = line.replace(/\s+/g, " ").trim()
    if (!l) continue
    // a line is cut at sentence ends (never inside a number such as 7.0 or 1,000.00), so one quote carries one statement
    for (const p of l.split(/(?<=[a-z\)\]"'%0-9][.;!?])\s+(?=[A-Z(])/)) { const q = p.trim(); if (q && q.length <= MAX_QUOTE) out.push(q) }
  }
  return out
}

// ---------- fees ----------
const INTL = /\b(international|overseas|non-?resident|offshore|onshore international|student visa)\b/i
const DOMESTIC = /\b(domestic|commonwealth[- ]supported|CSP|HECS|FEE-?HELP|(new zealand|canadian|australian) (citizens?|residents?|permanent residents?)|residents? of (new zealand|canada|australia)|out-of-province|in-province|Quebec residents?)\b/i
const NOT_TUITION = /\b(application fee|deposit|accommodation|living (costs?|expenses)|cost of living|health (cover|insurance)|OSHC|student services|amenities|ancillary|scholarship|bursary|discount|rebate|refund|late fee|enrolment fee|enrollment fee|levy|SSAF|materials?|textbooks?|uniform|visa application|bond|parking|insurance|per hour|hourly|weekly|per week)\b/i
const AMOUNT = "(?:(AUD|NZD|CAD|A\\$|AU\\$|NZ\\$|C\\$|CA\\$|CAN\\$|\\$)\\s?)((?:\\d{1,3}(?:,\\d{3})+|\\d{4,6})(?:\\.\\d{2})?)(?:\\s?(AUD|NZD|CAD))?"
type Basis = "annual" | "per_semester" | "course_total" | "per_unit"
const BASIS: [Basis, RegExp][] = [
  ["annual", /\b(per (academic )?year|a year|each year|per annum|p\.?\s?a\.?|annual(ly)?|\/\s?(year|yr)|yearly|per 12 months|full[- ]time (annual|year))\b/i],
  ["per_semester", /\b(per (semester|trimester|term)|a (semester|trimester|term)|each (semester|trimester|term)|\/\s?(semester|trimester|term))\b/i],
  ["per_unit", /\b(per (credit( point)?|unit|point|course unit|paper|subject|module|credit hour)|\/\s?(credit|unit|point|paper))\b/i],
  ["course_total", /\b(total (course|program|programme|tuition|fee)|(full|whole|entire|complete) (course|program|programme|degree)|for the (whole|full|entire) (course|program|programme)|total cost)\b/i],
]
const toCur = (sym: string | undefined, post: string | undefined, cc: string): string | null => {
  const s = (post || sym || "").toUpperCase()
  if (s === "AUD" || s === "A$" || s === "AU$") return "AUD"
  if (s === "NZD" || s === "NZ$") return "NZD"
  if (s === "CAD" || s === "C$" || s === "CA$" || s === "CAN$") return "CAD"
  if (s === "$") return CURRENCY[cc] ?? null
  return null
}
const RANGE: Record<string, [number, number]> = { annual: [5000, 150000], per_semester: [2000, 80000], per_unit: [100, 15000], course_total: [5000, 600000] } // fixed: plausibility of a printed figure, not a policy limit
const yearIn = (u: string): number | null => { const m = u.match(/\b(20[2-3]\d)\b/g); if (!m) return null; const ys = [...new Set(m.map(Number))]; return ys.length === 1 ? ys[0] : null }
// the fee year: a year printed within 60 characters of the amount (a date elsewhere in the sentence is not the fee's year)
const feeYearNear = (u: string, at: number): number | null => yearIn(u.slice(Math.max(0, at - 60), at + 60))

function readFees(units: string[], cc: string): { rows: FidReading[]; ambiguous: string[] } {
  const rows: (FidReading & { kind: "fee" })[] = []
  const ambiguous: string[] = []
  const re = new RegExp(AMOUNT, "g")
  for (const u of units) {
    if (!INTL.test(u) || DOMESTIC.test(u) || NOT_TUITION.test(u)) continue
    if (!/\b(tuition|fees?|cost)\b/i.test(u)) continue
    const amts = [...u.matchAll(re)].map((m) => ({ cur: toCur(m[1], m[3], cc), amount: Number(m[2].replace(/,/g, "")), at: m.index ?? 0 })).filter((a) => a.cur && Number.isFinite(a.amount))
    if (!amts.length) continue
    const bases = BASIS.filter(([, r]) => r.test(u)).map(([b]) => b)
    if (bases.length !== 1) { if (bases.length > 1) ambiguous.push(`fee: more than one fee basis in one line: ${u.slice(0, 120)}`); continue }
    const distinct = [...new Set(amts.map((a) => `${a.cur}:${a.amount}`))]
    if (distinct.length !== 1) { ambiguous.push(`fee: ${distinct.length} different figures in one line: ${u.slice(0, 120)}`); continue }
    const a = amts[0]; const [lo, hi] = RANGE[bases[0]]
    if (a.amount < lo || a.amount > hi) continue
    rows.push({ kind: "fee", amount: a.amount, currency: a.cur as string, basis: bases[0], fee_year: feeYearNear(u, a.at), quote: u })
  }
  // one figure per basis: the same figure printed twice is one reading; two figures of one basis are ambiguous (by year, campus or major)
  const out: FidReading[] = []
  for (const b of ["annual", "per_semester", "per_unit", "course_total"] as const) {
    const of = rows.filter((r) => r.basis === b)
    const figs = [...new Set(of.map((r) => `${r.currency}:${r.amount}:${r.fee_year ?? ""}`))]
    if (figs.length === 1) out.push(of[0])
    else if (figs.length > 1) {
      // a later fee year supersedes an earlier one when every row states its year
      const years = of.map((r) => r.fee_year)
      if (years.every((y) => y !== null)) {
        const top = Math.max(...(years as number[])); const latest = of.filter((r) => r.fee_year === top)
        if (new Set(latest.map((r) => `${r.currency}:${r.amount}`)).size === 1) { out.push(latest[0]); continue }
      }
      ambiguous.push(`fee: ${figs.length} different ${b.replace("_", " ")} figures on the page`)
    }
  }
  return { rows: out, ambiguous }
}

// ---------- intakes ----------
const START = /\b(intakes?|start(s|ing)?( dates?| months?)?|commenc(e|es|ing|ement)|entry points?|begins?|available in|offered in|enrol(l)?ment periods?)\b/i
const NOT_START = /\b(deadline|clos(e|es|ing)|apply by|applications? (due|open|close)|census|orientation|exam(s|ination)?|results?|holiday|break|graduat(e|ion)|due date|last day|withdraw|payment|invoice|published|updated|accurate as at|copyright)\b/i
const TERM = /\b(Trimester|Semester|Term|Study Period|Teaching Period)\s?([1-4]|One|Two|Three|Four)\b/gi
function readIntakes(units: string[]): FidReading[] {
  const out: FidReading[] = []
  for (const u of units) {
    if (!START.test(u) || NOT_START.test(u)) continue
    // a month followed by a day number is a date (a deadline or event), not an intake month
    const mons = [...u.matchAll(new RegExp(`\\b${MON}\\b(?!\\s+\\d{1,2}(st|nd|rd|th)?\\b)`, "g"))]
      .filter((m) => !/^\d/.test(u.slice(Math.max(0, (m.index ?? 0) - 3), m.index ?? 0).trim().slice(-2)))
      .map((m) => monthOf(m[1])).filter((x): x is string => !!x)
    // "May" alone is too often the verb; it counts only next to another month or after an intake word in the same short clause
    const months = [...new Set(mons)].filter((m) => m !== "May" || mons.length > 1 || /\b(intake|start)s?\s*(:|in|of)?\s*May\b/i.test(u))
    const labels = [...new Set([...u.matchAll(TERM)].map((m) => `${m[1][0].toUpperCase()}${m[1].slice(1).toLowerCase()} ${({ one: "1", two: "2", three: "3", four: "4" } as Record<string, string>)[m[2].toLowerCase()] ?? m[2]}`))]
    if (!months.length && !labels.length) continue
    if (months.length > 6) continue // fixed: a list of every month is a calendar, not an intake statement
    out.push({ kind: "intake", months, labels, year: yearIn(u), quote: u })
  }
  return out
}

// ---------- deadlines ----------
const CLOSE = /\b(application (deadline|closing date|close date)s?|applications? (close|closes|closing|due|must be (received|submitted) by)|closing date|apply by|deadline)\b/i
const ROLLING = /\b(rolling (admissions?|basis|applications?|intake)|applications? (are )?(accepted|considered|assessed) (year[- ]round|all year|throughout the year|on an ongoing basis)|no (application )?(deadline|closing date))\b/i
const FULL_DATE = new RegExp(`\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+${MON}\\.?,?\\s+(20\\d\\d)\\b|\\b${MON}\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(20\\d\\d)\\b|\\b(20\\d\\d)-(\\d{2})-(\\d{2})\\b`, "g")
const iso = (y: number, m: number, d: number): string | null => { const t = new Date(Date.UTC(y, m - 1, d)); return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d ? `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}` : null }
function readDeadlines(units: string[]): { rows: FidReading[]; ambiguous: string[] } {
  const out: FidReading[] = []; const ambiguous: string[] = []
  for (const u of units) {
    if (ROLLING.test(u) && /\b(appl(y|ication|icants?)|admissions?)\b/i.test(u)) { out.push({ kind: "deadline", date: null, rolling: true, intake_hint: null, quote: u }); continue }
    if (!CLOSE.test(u) || DOMESTIC.test(u) && !INTL.test(u)) continue
    const dates = [...u.matchAll(FULL_DATE)].map((m) => {
      if (m[1]) return iso(Number(m[3]), MONTHS.indexOf(monthOf(m[2]) ?? "") + 1, Number(m[1]))
      if (m[4]) return iso(Number(m[6]), MONTHS.indexOf(monthOf(m[4]) ?? "") + 1, Number(m[5]))
      return iso(Number(m[7]), Number(m[8]), Number(m[9]))
    }).filter((x): x is string => !!x)
    const ds = [...new Set(dates)]
    if (!ds.length) continue
    if (ds.length > 1) { ambiguous.push(`deadline: ${ds.length} dates in one line: ${u.slice(0, 120)}`); continue }
    const hint = (u.match(new RegExp(`\\b${MON}\\b\\s+(?:intake|start|entry|semester|trimester)`, "i")) || u.match(/\b(Trimester|Semester|Term)\s?[1-4]\b/i))
    out.push({ kind: "deadline", date: ds[0], rolling: false, intake_hint: hint ? hint[0] : null, quote: u })
  }
  return { rows: out, ambiguous }
}

export function fidRead(text: string, country: string): FidResult {
  const cc = String(country || "").toUpperCase()
  const units = fidUnits(String(text || ""))
  const f = readFees(units, cc); const d = readDeadlines(units)
  const readings = [...f.rows, ...readIntakes(units), ...d.rows].filter((r) => r.quote && text.replace(/\s+/g, " ").includes(r.quote))
  return { readings, ambiguous: [...f.ambiguous, ...d.ambiguous].slice(0, 10) }
}
