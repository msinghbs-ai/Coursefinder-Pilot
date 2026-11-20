// CF-247 s861 (session S1-Structure-Outcomes, Platform Admin 20 Nov 2026 15:19 AEDT: "close duration, study mode, delivery and regulatory code gaps from
// stored pages and registers", $0). A pure, deterministic reader of a course's structure as its stored course page states it in words:
//   duration       a full-time length in years, months, weeks or semesters, from a labelled line ("Duration: 3 years full-time") or a sentence that ties
//                  the length to full-time study ("3 years full-time or 6 years part-time");
//   study_load     full_time, part_time or both, from a labelled line ("Study mode: Full-time or part-time") or a duration line that names both;
//   delivery_mode  on_campus, online, blended or on_campus_and_online (the catalogue's own words), from a labelled line only.
// No model, no fetch, no storage, no database: it takes the page's markup (or text), turns it into lines that keep the page's own blocks, and returns
// readings, each with a verbatim quote that is one of those lines (checked here, so a reading can never carry words the page does not hold).
// It never guesses: a range ("1-2 years"), a maximum ("up to 4 years", "within 6 years"), a part-time-only length, a trimester or credit-point length,
// and any line that speaks of international or domestic students or of a visa are not read as a value (they are returned as notes, kind "other").
// Collapsed multi-course tables: a line that holds two or more qualification titles, a table separator beside two or more lengths, or two or more
// lengths with nothing to tell which is the full-time one is marked collapsed and is never offered as a value, so a length printed for one course of a
// table is never given to another. Whether a reading is admitted is decided by the database (security.struct_det_promote_v1), never here.
import { pageDataItems } from "./extract.ts"

export const STRUCT_DET_VERSION = "struct-det-v1.0"

export type StructReading = {
  key: "duration" | "study_load" | "delivery_mode" | "other"
  value: Record<string, number | string | boolean | null>
  quote: string                      // verbatim, one line of the page text (structLines)
  label: string | null               // the label line the value sits under, when the value is on its own line
  strength: "labelled" | "stated"    // labelled: under a Duration / Study mode / Delivery label; stated: a sentence that ties the length to full-time study
  collapsed: boolean                 // true: the line belongs to a table of several courses or holds several lengths; never admitted
}

const MAX_LINE = 320   // fixed: a quote is a line or a sentence, not a paragraph
const MAX_LABEL = 40   // fixed: a label on its own line is short ("Duration", "Study mode")

// the page's text, one block (paragraph, list item, table cell, heading, definition) to a line; entities folded as extract.ts htmlToText does
export function structLines(page: string): string[] {
  const isHtml = /<\w+[\s>]/.test(String(page || "").slice(0, 4000))
  let t = String(page || "")
  if (isHtml) {
    const items = pageDataItems(t)
    t = t.replace(/<(script|style|noscript|svg|template)[\s\S]*?<\/\1>/gi, " ")
      .replace(/&lt;(?:\/|&#x2F;|&#47;)?[a-z][a-z0-9-]*(?:\s[^&<>]*?)?(?:\/|&#x2F;)?&gt;/gi, " ")
      .replace(/<br\s*\/?>|<\/(p|li|tr|h[1-6]|div|td|th|dd|dt|section|article|header|footer|ul|ol|table|caption|label|summary|details|button)>|<(p|li|tr|h[1-6]|div|td|th|dd|dt|section|ul|ol|table)\b[^>]*>/gi, "\n")
      .replace(/<[^>]+>/g, " ").replace(/&nbsp;|&#160;/gi, " ").replace(/&amp;/gi, "&").replace(/&#36;|&dollar;/gi, "$")
      .replace(/&#39;|&rsquo;|&lsquo;/gi, "'").replace(/&quot;|&ldquo;|&rdquo;/gi, '"').replace(/&ndash;|&mdash;|&#8211;|&#8212;/gi, "-")
    if (items) t = t + "\n" + items
  }
  const out: string[] = []
  for (const raw of t.split(/\n/)) {
    const l = raw.replace(/[ \t ]+/g, " ").trim()
    if (!l) continue
    if (l.length <= MAX_LINE) { out.push(l); continue }
    for (const p of l.split(/(?<=[a-z\)\]"'%0-9][.;])\s+(?=[A-Z(])/)) { const q = p.trim(); if (q && q.length <= MAX_LINE) out.push(q) }
  }
  return out
}

const WORDS: Record<string, number> = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, twelve: 12, eighteen: 18 }
const NUM = "(\\d{1,3}(?:\\.\\d)?|one|two|three|four|five|six|seven|eight|nine|ten|twelve|eighteen|half(?:\\s+a)?)"
const UNIT = "(years?|yrs?|months?|weeks?|semesters?|trimesters?|terms?|credit points?|credits?|units?|courses?)"
const LEN = new RegExp(`\\b${NUM}(?:\\s*\\(\\s*\\d{1,3}(?:\\.\\d)?\\s*\\))?\\s*-?\\s*${UNIT}\\b`, "gi")
const RANGE = new RegExp(`\\b${NUM}\\s*(?:-|to|or)\\s*${NUM}\\s*-?\\s*${UNIT}\\b`, "i")
const MAXIMUM = /\b(up to|maximum|max\.?|within|no more than|at most|minimum of|at least|completed? in as little as|as little as|over a period)\b/i
const AUDIENCE = /\b(international|domestic|visa|onshore|offshore|student pass|study permit|citizens?|permanent residents?)\b/i
const FT = /\b[Ff][Uu][Ll][Ll][\s-]?[Tt][Ii][Mm][Ee]\b|\bFT\b/   // full-time in any case; the short form only in capitals (ft is also feet)
const PT = /\b[Pp][Aa][Rr][Tt][\s-]?[Tt][Ii][Mm][Ee]\b|\bPT\b/
const TITLES = /\b(bachelor|master|diploma|certificate|doctor(?:ate)?|associate degree|graduate|honours|phd|advanced diploma)\b/gi
const DUR_LABEL = /^(?:(?:course|program|programme|study|degree|qualification)\s+)?(?:duration|length|length of (?:study|program|programme|course)|time to complete|completion time|years? of study)(?:\s*\((?:full[\s-]?time|ft)\))?(?:\s+full[\s-]?time)?\s*[:\-]?\s*/i
const LOAD_LABEL = /^(?:study (?:mode|load|options?|type|pattern)|mode of study|attendance(?: mode| type| pattern)?|enrolment (?:type|mode)|study (?:full|part)[\s-]?time|full[\s-]?time\s*\/\s*part[\s-]?time)\s*[:\-]?\s*/i
const MODE_LABEL = /^(?:delivery(?: mode| method| format| type)?|mode of delivery|study mode|mode of study|learning (?:mode|format)|study (?:format|method|location)|format|campus\s*\/\s*online|location and mode|delivery and location|attendance mode)\s*[:\-]?\s*/i

const unitOf = (u: string): string | null => {
  const x = u.toLowerCase()
  if (/^(years?|yrs?)$/.test(x)) return "years"
  if (/^months?$/.test(x)) return "months"
  if (/^weeks?$/.test(x)) return "weeks"
  if (/^semesters?$/.test(x)) return "semesters"
  return null   // trimester, term, credit point, unit, course: not a length the catalogue holds (returned as a note)
}
const numOf = (s: string): number => {
  const x = s.toLowerCase().trim()
  if (x.startsWith("half")) return 0.5
  return WORDS[x] ?? Number(x)
}
const BOUNDS: Record<string, [number, number]> = { years: [0.5, 8], months: [1, 96], weeks: [1, 416], semesters: [1, 16] }  // fixed: a plausible full course length

type Len = { value: number; unit: string | null; raw: string; at: number; ft: boolean; pt: boolean }

// every length a line prints, with whether full-time or part-time is named right beside it (within 24 characters)
export function lengths(line: string): Len[] {
  const out: Len[] = []
  for (const m of line.matchAll(LEN)) {
    const at = m.index ?? 0
    const before = line.slice(Math.max(0, at - 24), at), after = line.slice(at + m[0].length, at + m[0].length + 24)
    const near = (re: RegExp) => re.test(after.split(/[,;]|\bor\b|\band\b/)[0] ?? "") || re.test(before.split(/[,;]|\bor\b|\band\b/).slice(-1)[0] ?? "")
    out.push({ value: numOf(m[1]), unit: unitOf(m[2]), raw: m[0], at, ft: near(FT), pt: near(PT) })
  }
  return out
}

// a line that belongs to a table or list of several courses: two or more qualification titles, or a table separator beside two or more lengths
export function structCollapsed(line: string): boolean {
  const titles = new Set((line.match(TITLES) || []).map((x) => x.toLowerCase()))
  const lens = lengths(line).filter((x) => x.unit)
  if (titles.size >= 2 && lens.length >= 1) return true
  if (/[|\t]|\s{3,}/.test(line) && lens.length >= 2) return true
  return false
}

const loadOf = (s: string): "full_time" | "part_time" | "both" | null => {
  const f = FT.test(s), p = PT.test(s)
  if (f && p) return "both"
  if (f && /\bfull[\s-]?time only\b|\bonly (?:available |offered )?(?:on a |as )?full[\s-]?time\b/i.test(s)) return "full_time"
  if (p && /\bpart[\s-]?time only\b|\bonly (?:available |offered )?(?:on a |as )?part[\s-]?time\b/i.test(s)) return "part_time"
  return null
}
const loadLabelled = (s: string): "full_time" | "part_time" | "both" | null => {
  const f = FT.test(s), p = PT.test(s)
  if (f && p) return "both"
  if (f) return "full_time"
  if (p) return "part_time"
  return null
}
const modeOf = (s: string): string | null => {
  const camp = /\bon[\s-]?campus\b|\bface[\s-]to[\s-]face\b|\bin[\s-]person\b|\bcampus experience\b|\bon[\s-]?site\b/i.test(s)
  const onl = /\bonline\b|\bdistance\b|\bremote(?:ly)?\b|\bvirtual\b/i.test(s)
  const bl = /\bblended\b|\bhybrid\b|\bmixed[\s-]mode\b/i.test(s)
  if (/\bflexible\b|\bmultiple\b|\bvaries\b|\bvariable\b/i.test(s) && !camp && !onl && !bl) return null
  if (bl) return "blended"
  if (camp && onl) return "on_campus_and_online"
  if (camp) return "on_campus"
  if (onl) return "online"
  return null
}

// the full-time length a duration value states, or a note saying why it is not one
function durationOf(v: string): { value: number; unit: string } | { note: string } | null {
  const lens = lengths(v)
  if (!lens.length) return null
  if (RANGE.test(v)) return { note: "range" }
  if (MAXIMUM.test(v)) return { note: "maximum_or_minimum" }
  const ft = lens.filter((x) => x.ft)
  let pick: Len | undefined
  if (ft.length) pick = new Set(ft.map((x) => `${x.value} ${x.unit}`)).size === 1 ? ft[0] : undefined
  else if (lens.some((x) => x.pt) && !lens.some((x) => !x.pt)) return { note: "part_time_only" }
  else {
    // no full-time word beside a length: one length (or one length restated in another unit, "2 years (4 semesters)") is the course length
    const plain = lens.filter((x) => !x.pt)
    const units = plain.filter((x) => x.unit)
    if (units.length === 1 || (units.length === 2 && /\(\s*\d/.test(v) && v.indexOf("(") > units[0].at && v.indexOf("(") < units[1].at)) pick = units[0]
    else if (plain.length >= 2) return { note: "several_lengths" }
    else pick = plain[0]
  }
  if (!pick) return { note: "several_lengths" }
  if (!pick.unit) return { note: "not_a_catalogue_unit" }
  const [lo, hi] = BOUNDS[pick.unit]
  if (!(pick.value >= lo && pick.value <= hi)) return { note: "out_of_range" }
  return { value: pick.value, unit: pick.unit }
}

export function structRead(page: string): StructReading[] {
  const lines = structLines(page)
  const out: StructReading[] = []
  const push = (r: StructReading) => { if (r.quote.length >= 3 && lines.includes(r.quote)) out.push(r) }  // the quote is a line of the page, word for word
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i]
    // a label on its own line takes the next line as its value ("Duration" / "3 years full-time")
    const alone = l.length <= MAX_LABEL && !/\d/.test(l) ? l.replace(/[:\s]+$/, "") : null
    const next = lines[i + 1] ?? ""
    const cases: { label: string | null; value: string; quote: string }[] = []
    if (alone && next) cases.push({ label: alone, value: next, quote: next })
    cases.push({ label: null, value: l, quote: l })
    for (const c of cases) {
      const text = c.label ? `${c.label}: ${c.value}` : c.value
      const collapsed = structCollapsed(c.value)
      const audience = AUDIENCE.test(c.value)
      const dl = text.match(DUR_LABEL), ll = text.match(LOAD_LABEL), ml = text.match(MODE_LABEL)
      if (dl && dl[0].length && (c.label ? DUR_LABEL.test(c.label + ":") : true) && (c.label || dl.index === 0)) {
        const v = text.slice(dl[0].length)
        const d = durationOf(v)
        if (d && "value" in d) push({ key: "duration", value: d, quote: c.quote, label: c.label, strength: "labelled", collapsed: collapsed || audience })
        else if (d) push({ key: "other", value: { field: "duration", note: d.note }, quote: c.quote, label: c.label, strength: "labelled", collapsed })
        const ld = loadOf(v)
        if (ld && !audience) push({ key: "study_load", value: { load: ld }, quote: c.quote, label: c.label, strength: "labelled", collapsed })
        continue
      }
      if (ll && (c.label ? LOAD_LABEL.test(c.label + ":") : ll.index === 0)) {
        const v = text.slice(ll[0].length)
        const ld = loadLabelled(v)
        if (ld && v.length <= 120) push({ key: "study_load", value: { load: ld }, quote: c.quote, label: c.label, strength: "labelled", collapsed: collapsed || audience })
      }
      if (ml && (c.label ? MODE_LABEL.test(c.label + ":") : ml.index === 0)) {
        const v = text.slice(ml[0].length)
        const md = modeOf(v)
        if (md && v.length <= 120) push({ key: "delivery_mode", value: { mode: md }, quote: c.quote, label: c.label, strength: "labelled", collapsed: collapsed || audience })
      }
      if (!c.label && !dl && !ll && !ml && FT.test(l)) {
        // a sentence that ties a length to full-time study ("The Bachelor of Arts is 3 years full-time or 6 years part-time.")
        const lens = lengths(l).filter((x) => x.ft && x.unit)
        if (lens.length && !RANGE.test(l) && !MAXIMUM.test(l)) {
          const d = durationOf(l)
          if (d && "value" in d) push({ key: "duration", value: d, quote: l, label: null, strength: "stated", collapsed: collapsed || audience })
          const ld = loadOf(l)
          if (ld === "both" && !audience) push({ key: "study_load", value: { load: ld }, quote: l, label: null, strength: "stated", collapsed })
        }
      }
    }
  }
  // one reading per key, value and quote
  const seen = new Set<string>()
  return out.filter((r) => { const k = `${r.key}|${JSON.stringify(r.value)}|${r.quote}`; if (seen.has(k)) return false; seen.add(k); return true })
}

// the value a page gives for each field when it is unambiguous: every reading of the field that is not collapsed says the same value
export function structDecide(rs: StructReading[]): Record<string, { state: "one" | "conflict" | "none"; value?: unknown; quotes: string[] }> {
  const res: Record<string, { state: "one" | "conflict" | "none"; value?: unknown; quotes: string[] }> = {}
  for (const k of ["duration", "study_load", "delivery_mode"] as const) {
    const ok = rs.filter((r) => r.key === k && !r.collapsed)
    const vals = new Map<string, StructReading[]>()
    for (const r of ok) { const v = JSON.stringify(r.value); vals.set(v, [...(vals.get(v) || []), r]) }
    if (vals.size === 0) res[k] = { state: "none", quotes: [] }
    else if (vals.size === 1) { const [[v, list]] = [...vals]; res[k] = { state: "one", value: JSON.parse(v), quotes: list.map((r) => r.quote) } }
    else res[k] = { state: "conflict", quotes: ok.map((r) => r.quote) }
  }
  return res
}
