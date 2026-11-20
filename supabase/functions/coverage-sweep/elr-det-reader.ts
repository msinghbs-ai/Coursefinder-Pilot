// CF-247 s840 (session S1-ELR, Platform Admin 20 Nov 2026 15:10 and 15:21 AEDT): elr-det-v1.0, a pure, deterministic reader of the English language proficiency requirements a stored
// course page states in words (IELTS, TOEFL iBT, PTE Academic, OET, CELPIP, Cambridge C1 Advanced and C2 Proficiency). English only: academic entry requirements are the S1-AER lane's
// (aer-det-reader.ts, unchanged). No model, no fetch, no write. Every reading carries a verbatim quote that is a substring of the page text (checked here), and flags that tell the
// promotion gate (security.elr_det_record_v1) why a reading may not be promoted on its own: a pathway or foundation context, a value without minimum words, or a line that is a
// flattened table of several programmes (skipped, never cross-assigned).
export const ELR_DET_VERSION = "elr-det-v1.0"

export type ElrKey = "ielts" | "toefl_ibt" | "pte" | "oet" | "celpip" | "cambridge"
export type ElrComponents = { reading?: number; writing?: number; speaking?: number; listening?: number }
export type ElrValue = {
  overall?: number               // IELTS band, TOEFL iBT total, PTE overall (decimals kept), CELPIP level, Cambridge scale score
  components?: ElrComponents     // the minimum for each skill the quote states (a "no band below" minimum is written to all four)
  grade?: string                 // OET overall grade (A, B, C+, C)
  level?: "C1" | "C2"            // Cambridge: C1 Advanced or C2 Proficiency, when the quote names it
}
export type ElrReading = {
  key: ElrKey
  value: ElrValue
  quote: string                  // verbatim, on the page text
  strength: "stated_minimum" | "mentioned"
  flags: string[]                // pathway: the quote is about a pathway, foundation or ELICOS course; no_minimum: no minimum words
}

const SECTION_REACH = 8  // fixed: lines after an English requirement heading that it governs (a heading, its lead-in and a short test list)
const MAX_QUOTE = 360  // fixed: a quote is a sentence or a line, not a paragraph
const N = (s: string) => Number(s)
const inRange = (v: number, lo: number, hi: number) => Number.isFinite(v) && v >= lo && v <= hi
const MIN_WORDS = /\b(minimum|min\.?|at least|required|requires?|requirement|overall|total|score of|must|need(?:s|ed)?|no (?:individual )?(?:band|sub-?score|section|component|skill)|each (?:band|component|section|skill|sub-?test)|or (?:above|higher|better|more)|equivalent|no (?:\w+ ){0,3}(?:below|less than|lower than|under))\b/i
// a heading or lead-in that says the lines after it are the English language requirement (a bare "IELTS 6.5" under it is a stated requirement)
const SECTION = /\b(?:English (?:language )?(?:proficiency )?requirements?|English language proficiency|English (?:language )?entry requirements?|minimum English|English test scores?)\b/i
const PATHWAY = /\b(?:foundation (?:program|programme|studies|year|course)|pathway (?:program|programme|course)|ELICOS|English language (?:course|program|programme|bridging)|bridging (?:course|program|programme)|direct entry English|packaged with|conditional offer with English|Diploma of English|English for Academic Purposes|EAP\b)/i

// test names: acronyms and the spelled-out names
const NAME: Record<ElrKey, RegExp> = {
  ielts: /\bIELTS\b|\bInternational English Language Testing System\b/i,
  toefl_ibt: /\bTOEFL\b|\bTest of English as a Foreign Language\b/i,
  pte: /\bPTE\b|\bPearson Test of English\b|\bPearson English\b/i,
  oet: /\bOET\b|\bOccupational English Test\b/,
  celpip: /\bCELPIP\b|\bCanadian English Language Proficiency Index Program\b/i,
  cambridge: /\bCambridge (?:English|Assessment English|C1|C2|Advanced|Proficiency|CAE|CPE)\b|\b(?:C1 Advanced|C2 Proficiency|Certificate in Advanced English|Certificate of Proficiency in English|CAE|CPE)\b/i,
}
// other English tests and qualifications whose numbers must never be read as one of ours (their names end a value window)
const OTHERS: RegExp[] = [/\bDuolingo\b|\bDET\b/i, /\bLANGUAGECERT\b/i, /\bMET\b|\bMichigan\b/, /\bCAEL\b/, /\bCanTEST\b/i, /\bNCUK\b/, /\bTOEIC\b/, /\bITEP\b/i, /\bPassword (?:English|Skills)\b/i,
  /\bATAR\b/, /\bGPA\b/, /\bA[- ]levels?\b/i, /\bIB Diploma\b|\bInternational Baccalaureate\b/, /\bNCEA\b/, /\bUniversity Entrance\b/i]
const KEYS = Object.keys(NAME) as ElrKey[]

// the lines and sentences a requirement is printed in; a quote is one of these, so it is on the text word for word
export function elrUnits(text: string): string[] {
  const out: string[] = []
  for (const line of text.split(/\n+/)) {
    const l = line.trim()
    if (!l) continue
    if (l.length <= MAX_QUOTE) { out.push(l); continue }
    for (const p of l.split(/(?<=[a-z\)\]"'%0-9][.;])\s+(?=[A-Z(])/)) { const q = p.trim(); if (q) out.push(q.length > MAX_QUOTE ? q.slice(0, MAX_QUOTE) : q) }
  }
  return out
}

// every place on a line where a test or another qualification is named, in order
type Mark = { at: number; key: ElrKey | "other" }
function marks(u: string): Mark[] {
  const m: Mark[] = []
  for (const k of KEYS) for (const x of u.matchAll(new RegExp(NAME[k].source, NAME[k].flags.includes("g") ? NAME[k].flags : NAME[k].flags + "g"))) m.push({ at: x.index ?? 0, key: k })
  for (const re of OTHERS) for (const x of u.matchAll(new RegExp(re.source, re.flags + "g"))) m.push({ at: x.index ?? 0, key: "other" })
  m.sort((a, b) => a.at - b.at)
  // a spelled-out name followed by its acronym in brackets is one mention ("International English Language Testing System (IELTS)")
  return m.filter((x, i) => !(i > 0 && m[i - 1].key === x.key && x.at - m[i - 1].at < 80 && /\(\s*$/.test(u.slice(m[i - 1].at, x.at).slice(-3))))
}
// the text from a test's name to the next other test or qualification: its value is read only here
function windows(u: string, key: ElrKey, split = false): string[] {
  const m = marks(u), out: string[] = []
  for (let i = 0; i < m.length; i++) {
    if (m[i].key !== key) continue
    // read: a repeated name of the same test continues its window ("Test of English as a Foreign Language (TOEFL iBT) 90"); split: each mention is its own window
    if (!split && i > 0 && m[i - 1].key === key) continue
    let end = u.length
    for (let j = i + 1; j < m.length; j++) if (split || m[j].key !== key) { end = m[j].at; break }
    out.push(u.slice(m[i].at, end))
  }
  return out
}

const DEGREE = /\b(?:Bachelor|Master|Graduate Certificate|Graduate Diploma|Diploma|Advanced Diploma|Associate Degree|Doctor)\s+of\s+[A-Z][\w&-]*(?:\s+[A-Z&][\w&-]*){0,3}/g
// a flattened table line: two or more programme titles, or one test given two different values on the same line (two programmes' rows run together)
export function elrCollapsed(u: string): boolean {
  if (new Set([...u.matchAll(DEGREE)].map((x) => x[0].toLowerCase())).size >= 2) return true
  for (const k of KEYS) {
    const vals = new Set(windows(u, k, true).map((w) => overallOf(k, w)).filter((v): v is number => v !== null))
    if (vals.size >= 2) return true
  }
  return false
}

const SKILLS = ["reading", "writing", "speaking", "listening"] as const
// per-skill minimums named one by one ("Reading 6.0, Writing 6.5", "writing score of 21", "listening: 7")
function namedSkills(w: string, lo: number, hi: number, step: number): ElrComponents {
  const c: ElrComponents = {}
  for (const s of SKILLS) {
    const m = w.match(new RegExp(`\\b${s}\\b\\s*(?:sub-?score|score|band|section)?\\s*(?:of|:|-|–|=|at least|minimum(?: of)?)?\\s*(\\d{1,3}(?:\\.\\d)?)\\b`, "i"))
      || w.match(new RegExp(`\\b(\\d{1,3}(?:\\.\\d)?)\\s+(?:in|for)\\s+${s}\\b`, "i"))
    if (m) { const v = N(m[1]); if (inRange(v, lo, hi) && Math.abs(v / step - Math.round(v / step)) < 1e-9) c[s] = v }
  }
  return c
}
// one minimum for every skill ("no band below 6.0", "6.0 in each band", "no communicative skill below 50", "each section at least 20")
const ALL_PATTERNS = (n: string): RegExp[] => [
  new RegExp(`\\b(?:no|not|none)\\s+(?:\\w+\\s+){0,4}?(?:below|less than|lower than|under)\\s+(?:an?\\s+)?(?:band\\s+|score\\s+of\\s+|grade\\s+)?${n}`, "i"),
  new RegExp(`\\b(?:minimum|min\\.?|at least)\\s+(?:of\\s+)?${n}\\s+(?:in|for|on|per)\\s+(?:each|any|every|all)\\b`, "i"),
  new RegExp(`\\b${n}\\s+(?:or\\s+(?:above|higher|more|better)\\s+)?(?:in|for|on|per)\\s+(?:each|any|every|all)\\b`, "i"),
  new RegExp(`\\b(?:each|every|all)\\s+(?:\\w+\\s+){0,3}?(?:of|at|score of|at least|minimum of|minimum|min\\.?|=|:)\\s*${n}`, "i"),
  new RegExp(`\\b${n}\\s+(?:each|per)\\s+(?:band|component|section|skill|sub-?test|sub-?score)\\b`, "i"),
  new RegExp(`\\bminimum\\s+(?:band|component|sub-?score|sub-?test|section|skill)s?\\s+(?:score\\s+)?(?:of\\s+)?${n}`, "i"),
  new RegExp(`\\b(?:band|component|section|skill|sub-?test|sub-?score)s?\\s+(?:score\\s+)?(?:minimum\\s+)?(?:of\\s+)?${n}\\s+(?:or\\s+(?:above|higher|more))?`, "i"),
]
function allSkills(w: string, num: string, lo: number, hi: number, overall: number | null): number | null {
  for (const re of ALL_PATTERNS(num)) { const m = w.match(re); if (m) { const v = N(m[1]); if (inRange(v, lo, hi) && (overall === null || v <= overall)) return v } }
  return null
}

// the overall (or total) value a test window states; null when none is plausible
const SCALE: Record<Exclude<ElrKey, "oet">, { num: string; lo: number; hi: number; step: number }> = {
  ielts: { num: "([4-9](?:\\.[05])?)", lo: 4, hi: 9, step: 0.5 },
  toefl_ibt: { num: "(\\d{2,3})", lo: 32, hi: 120, step: 1 },
  pte: { num: "(\\d{2}(?:\\.\\d)?)", lo: 30, hi: 90, step: 0.1 },
  celpip: { num: "(\\d{1,2})", lo: 4, hi: 12, step: 1 },
  cambridge: { num: "(1[6-9]\\d|2[0-3]\\d)", lo: 160, hi: 230, step: 1 },
}
function overallOf(k: ElrKey, w: string): number | null {
  if (k === "oet") return null
  const s = SCALE[k]
  // the value next to an overall or total word first, then the first value after the name that is not a skill's own value
  const near = w.match(new RegExp(`(?<![\\d.])${s.num}\\s*(?:\\(\\s*)?(?:overall|total|or (?:above|higher|better|more))\\b`, "i"))
    || w.match(new RegExp(`\\b(?:overall|total|minimum(?: overall)?(?: score)?(?: of)?|score of|at least)\\b(?:(?!reading|writing|speaking|listening|each|any|every|below|less|lower|under|band|section|skill|component)[^\\d]){0,24}?${s.num}\\b`, "i"))
  const cand = near ?? (() => {
    for (const m of w.matchAll(new RegExp(`(?<![\\d.])${s.num}(?![\\d])`, "gi"))) {
      const before = w.slice(Math.max(0, (m.index ?? 0) - 16), m.index ?? 0)
      if (/\b(?:reading|writing|speaking|listening|each|any|below|less than|lower than|under)\b[^\d]*$/i.test(before)) continue
      if (/\b(?:19|20)\d{2}\b/.test(m[0])) continue
      return m
    }
    return null
  })()
  if (!cand) return null
  const v = N(cand[1])
  if (!inRange(v, s.lo, s.hi) || Math.abs(v / s.step - Math.round(v / s.step)) > 1e-9) return null
  if (k === "ielts" && /iBT|TOEFL/i.test(w.slice(0, 12))) return null
  return v
}

// the range of one skill's score for each test (TOEFL iBT sections are 0 to 30; Cambridge skills are on the 140 to 230 scale)
const COMP: Record<Exclude<ElrKey, "oet">, { num: string; lo: number; hi: number; step: number }> = {
  ielts: { num: "([4-9](?:\\.[05])?)", lo: 4, hi: 9, step: 0.5 },
  toefl_ibt: { num: "(\\d{1,2})", lo: 0, hi: 30, step: 1 },
  pte: { num: "(\\d{2}(?:\\.\\d)?)", lo: 10, hi: 90, step: 0.1 },
  celpip: { num: "(\\d{1,2})", lo: 4, hi: 12, step: 1 },
  cambridge: { num: "(1[4-9]\\d|2[0-3]\\d)", lo: 140, hi: 230, step: 1 },
}
function readOne(k: ElrKey, w: string): ElrValue | null {
  if (k === "oet") {
    const g = w.match(/\b(?:grade|grades|overall)\s+(?:of\s+)?([ABC]\+?)(?![\w+])/) || w.match(/\b([ABC]\+?)\s+(?:grade|in each|in all|or (?:above|higher|better))\b/)
    const sc = w.match(/\b([3-5]\d{2})\b/)
    const comps = namedSkills(w, 300, 500, 10)
    const all = sc ? allSkills(w, "([3-5]\\d{2})", 300, 500, null) : null
    if (g) return { grade: g[1] }
    if (all !== null) return { components: { reading: all, writing: all, speaking: all, listening: all } }
    if (Object.keys(comps).length >= 2) return { components: comps }
    return null
  }
  const s = SCALE[k]
  const overall = overallOf(k, w)
  if (overall === null && k !== "celpip") return null
  const cs = COMP[k]
  let comps = namedSkills(w, cs.lo, cs.hi, cs.step)
  const all = allSkills(w, cs.num, cs.lo, cs.hi, k === "toefl_ibt" ? null : overall)
  if (all !== null) comps = { reading: all, writing: all, speaking: all, listening: all, ...comps }
  for (const sk of SKILLS) { const v = comps[sk]; if (v !== undefined && overall !== null && k !== "toefl_ibt" && v > overall) delete comps[sk] }
  if (k === "celpip") {
    // CELPIP is reported as a level: "level 7 in each component" is the requirement for every skill; an overall level alone is read as that level
    const lvl = w.match(/\b(?:level|CLB)\s+(\d{1,2})\b/i)
    const v = overall ?? (lvl ? N(lvl[1]) : null)
    if (v === null || !inRange(v, 4, 12)) return null
    const out: ElrValue = { overall: v }
    if (Object.keys(comps).length) out.components = comps
    return out
  }
  const out: ElrValue = { overall: overall as number }
  if (Object.keys(comps).length) out.components = comps
  if (k === "cambridge") { if (/\bC2\b|Proficiency|\bCPE\b/i.test(w)) out.level = "C2"; else if (/\bC1\b|Advanced|\bCAE\b/i.test(w)) out.level = "C1" }
  return out
}

// every English test reading on the page text. A reading is kept only when its quote is found in the text unchanged and states the test with a value.
export function elrRead(text: string): ElrReading[] {
  const seen = new Set<string>(), out: ElrReading[] = []
  let since = 99   // units since the last English language requirement heading or lead-in
  for (const u of elrUnits(text)) {
    since = SECTION.test(u) ? 0 : since + 1
    const ms = marks(u)
    if (!ms.some((x) => x.key !== "other")) continue
    if (elrCollapsed(u)) continue          // a flattened table line is skipped, never guessed
    for (const k of KEYS) {
      if (k === "toefl_ibt" && /\bTOEFL\s*(?:PBT|paper|ITP|Essentials)\b/i.test(u)) continue   // only the internet-based test
      if (k === "pte" && /\bPTE\s*(?:General|Core|Home)\b/i.test(u)) continue                  // only PTE Academic
      for (const w of windows(u, k)) {
        const value = readOne(k, w)
        if (!value) continue
        const q = u
        if (!text.includes(q)) continue     // the quote must be on the page word for word
        const id = k + "|" + JSON.stringify(value) + "|" + q
        if (seen.has(id)) continue
        seen.add(id)
        const flags: string[] = []
        if (PATHWAY.test(q)) flags.push("pathway")
        const section = since <= SECTION_REACH
        const strong = MIN_WORDS.test(w) || MIN_WORDS.test(q) || section
        if (!strong) flags.push("no_minimum")
        if (section && !(MIN_WORDS.test(w) || MIN_WORDS.test(q))) flags.push("section")
        out.push({ key: k, value, quote: q, strength: strong ? "stated_minimum" : "mentioned", flags })
        break                               // one reading per test per line
      }
    }
  }
  return out
}

// the readings of one test on one page agree when they give the same value; the gate promotes a test only when they do
export function elrAgree(rs: ElrReading[], k: ElrKey): boolean {
  const vals = new Set(rs.filter((r) => r.key === k && !r.flags.includes("pathway")).map((r) => JSON.stringify(r.value)))
  return vals.size <= 1
}
