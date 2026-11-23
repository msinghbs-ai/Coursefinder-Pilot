// CF-247 s815 (S1-AER, Platform Admin 20 Nov 2026 10:51 AEDT, Decision 2: "$0 deterministic extraction against the stored pages in Main DB"). A pure, deterministic reader of the academic entry
// qualifications a stored course page states in words. No model, no fetch, no write: it takes the page's text and returns readings, each with a verbatim quote that is a substring of that text
// (checked here, so a reading can never carry words the page does not hold). Readings are recorded beside Layer 4 and enter it only as ordinary course entry reads, which the existing gates
// (quote on the page, page identity, completeness, manual locks, no-overwrite, audit sample) decide (Decision 276: AER v1 is frozen and the AI reader stays shadow only).
export const AER_DET_VERSION = "aer-det-v1.4" // v1.4 (23 Nov 2026, s1009, Platform Admin 15:52 AEDT): a maximum or "up to" figure is never read as a minimum; a reading's quote carries the value it gives; a mark in one subject ("65% in English") is not read as an overall minimum. v1.3 (20 Nov 2026, s834, Platform Admin 15:08 AEDT: AER and English are separate): English tests are not read at all (the English requirement has its own pipeline); IB points, A-level grades and Indian board averages are read; "42 level 3 credits" reads 42, never the 3 of "level 3"; Year 12 needs a stated score, mark or percentage; the v1.2 collapsed-row guard is kept (a flattened table line is skipped and a value is never taken across another test or qualification)

export type DetReading = {
  kind: "academic_entry"
  key: string                       // atar, year12, ncea_l3, university_entrance, ib, alevel, india_board, ca_secondary, bachelor_gpa
  value: Record<string, number | string | boolean | null>
  quote: string                     // verbatim, on the page text
  strength: "stated_minimum" | "mentioned"   // stated_minimum: the quote itself says the value is a minimum or required
}

const MAX_QUOTE = 320  // fixed: a quote is a sentence or line, not a paragraph
const N = (s: string) => Number(s)
const inRange = (v: number, lo: number, hi: number) => Number.isFinite(v) && v >= lo && v <= hi
const MIN_WORDS = /\b(minimum|at least|required|requirement|overall|score of|must|need|or (?:above|higher|better))\b/i

// splits the page text into the lines and sentences a requirement is printed in; a quote is one of these, so it is on the text word for word
export function detUnits(text: string): string[] {
  const out: string[] = []
  for (const line of text.split(/\n+/)) {
    const l = line.trim()
    if (!l) continue
    if (l.length <= MAX_QUOTE) { out.push(l); continue }
    // a long line is cut at sentence ends, never inside a number (7.0) or an abbreviation of one letter
    const parts = l.split(/(?<=[a-z\)\]"'%0-9][.;])\s+(?=[A-Z(])/)
    for (const p of parts) { const q = p.trim(); if (q) out.push(q.length > MAX_QUOTE ? q.slice(0, MAX_QUOTE) : q) }
  }
  return out
}

type Rule = { key: string; win?: boolean; re: RegExp; make: (m: RegExpMatchArray, q: string) => Record<string, number | string | boolean | null> | null }

// a window of at most 120 characters from the match to the end of its clause; the quote of the rules that read it
function clause(u: string, at: number): string { const w = u.slice(at, at + 120); const e = w.search(/[.;](?=\s+[A-Z(]|$)/); return (e > 0 ? w.slice(0, e + 1) : w).trim() }

// the English tests: never read here (their own pipeline), but a number printed beside one is never taken as an academic value
const ENGLISH_TEST = /\b(?:IELTS|TOEFL|PTE|OET|CELPIP|Cambridge English|C1 Advanced|C2 Proficiency|Duolingo|LANGUAGECERT|International English Language Testing System|Pearson Test of English|Occupational English Test)\b/i

// the qualifications a page names beside each other. A reading takes its value only from words that name its own qualification, so a score that belongs to another test, an IB Diploma,
// NCUK or a foundation course is never read as the course's ATAR, Year 12 or Canadian average. A flattened table line (several programmes or qualifications on one line) is skipped.
const FAMILIES: [string, RegExp][] = [
  ["english", ENGLISH_TEST],
  ["atar", /\bATAR\b/], ["year12", /\b(?:Year 12|Victorian Certificate of Education|VCE|HSC|Higher School Certificate|QCE|Queensland Certificate of Education|South Australian Certificate of Education|SACE|WACE|Tasmanian Certificate of Education|TCE|NTCET|ACT Senior Secondary)\b/],
  ["ncea", /\bNCEA\b/], ["ue", /\bUniversity Entrance\b/i], ["ca", /\b(?:Ontario Secondary School Diploma|OSSD|Grade 12|secondary school diploma|high school diploma|senior matriculation|BC Dogwood|(?<!national )Baccalaur[eé]at)/i],  // v1.4 (s1009): "International Baccalaureate" is the IB, never the Québec or French baccalauréat (it cut IB quotes to "International")
  ["gpa", /\b(?:GPA|grade point average)\b/i], ["ncuk", /\bNCUK\b/], ["alevel", /\bA[- ]?levels?\b/i], ["ib", /\bInternational Baccalaureate\b|\bIB Diploma\b|\bIB\b/],
  ["india", /\b(?:CBSE|CISCE|ICSE|ISC|Indian School Certificate|State Board|Senior School Certificate)\b/],
]
const OWN: Record<string, string> = { atar: "atar", year12: "year12", ncea_l3: "ncea", university_entrance: "ue", ib: "ib", alevel: "alevel", india_board: "india", ca_secondary: "ca", bachelor_gpa: "gpa" }
function families(s: string): Set<string> { const o = new Set<string>(); for (const [id, re] of FAMILIES) if (re.test(s)) o.add(id); return o }
const DEGREE = /\b(?:Bachelor|Master|Graduate Certificate|Graduate Diploma|Diploma|Associate Degree|Doctor)\s+of\s+[A-Z][\w&-]*(?:\s+[A-Z&][\w&-]*){0,3}/g
export function detCollapsed(u: string): boolean {
  const titles = new Set([...u.matchAll(DEGREE)].map((x) => x[0].toLowerCase()))
  if (titles.size >= 2) return true
  const f = families(u).size
  if (/\||\t/.test(u) && f >= 2) return true
  return f >= 3 && u.length > 200
}
// the text from a match to the start of the next other test or qualification; a quote or a value never runs into another one
function untilOther(u: string, at: number, own: string): string {
  let end = u.length
  for (const [id, re] of FAMILIES) { if (id === own) continue; const g = new RegExp(re.source, re.flags.replace("g", "")); const m = g.exec(u.slice(at + 1)); if (m && at + 1 + m.index < end) end = at + 1 + m.index }
  return u.slice(at, end)
}

// the first credit count in a clause that is a count, never the level number: "42 level 3 credits" gives 42, "level 3 credits" alone gives nothing
function creditCount(q: string): number | null {
  for (const m of q.matchAll(/\b(\d{1,3})\s+(?:(?:at\s+)?(?:NCEA\s+)?level\s+[1-3]\s+)?credits?\b/gi)) {
    const at = m.index ?? 0
    if (/\blevel\s+$/i.test(q.slice(Math.max(0, at - 8), at))) continue
    const v = N(m[1]); if (inRange(v, 1, 240)) return v
  }
  return null
}

const RULES: Rule[] = [
  { key: "atar", re: /\bATAR\b[^.\n]{0,70}?\b(\d{2}(?:\.\d{1,2})?)\b(?!\s*(?:%|per cent|credits))/i, make: (m) => { const v = N(m[1]); return inRange(v, 30, 99.95) && !(v >= 1990 && v <= 2100) ? { atar: v, basis: "ATAR" } : null } },
  { key: "ncea_l3", win: true, re: /\b(?:\d{2,3}\s+credits?[^.\n]{0,60}?)?\bNCEA\b[^.\n]{0,40}?\bLevel\s*3\b/i, make: (_m, q) => { if (ENGLISH_TEST.test(q)) return null; const c = creditCount(q); return c ? { credits: c, basis: "credits" } : null } },
  { key: "university_entrance", win: true, re: /\bUniversity Entrance\b/i, make: (_m, q) => { if (ENGLISH_TEST.test(q)) return null; const c = creditCount(q); return c ? { credits: c, basis: "credits" } : null } },
  // Year 12 needs a stated threshold: a score, mark, rank, aggregate, average or percentage with its number (or a grade letter with "or higher"); "Units 3 and 4" and bare mentions of Year 12 give nothing
  { key: "year12", win: true, re: /\b(?:Year 12|Victorian Certificate of Education|VCE|HSC|Higher School Certificate|QCE|Queensland Certificate of Education|South Australian Certificate of Education|SACE|WACE|Tasmanian Certificate of Education|TCE|NTCET|ACT Senior Secondary)\b/,
    make: (_m, q): Record<string, number | string> | null => {
      if (ENGLISH_TEST.test(q) || /\bATAR\b/.test(q)) return null
      const v = q.match(/\b(score|mark|rank|result|aggregate|average|percent(?:age)?)\b[^.\n]{0,30}?\b(\d{1,3}(?:\.\d{1,2})?)\b(?!\s*(?:and|credits?|units?))/i) || q.match(/\b()(\d{1,3}(?:\.\d{1,2})?)\s*(?:%|per cent|or (?:above|higher|more))/i)
      if (v) { const n = N(v[2]); const pre = q.slice(Math.max(0, (v.index ?? 0) - 8), v.index ?? 0); return inRange(n, 1, 100) && n !== 12 && !/units?\s*$/i.test(pre) ? { value: n, basis: v[1] ? v[1].toLowerCase() : "%" } : null }
      const g = q.match(/\bgrade\s+([A-E][+-]?)\s+or\s+(?:higher|above|better)\b/i)
      return g ? { grade: g[1].toUpperCase() } : null } },
  { key: "ib", win: true, re: /\b(?:International Baccalaureate|IB Diploma|IB)\b[^.\n]{0,60}?\b(\d{2})\s*(?:points?|total)\b/i, make: (m) => { const v = N(m[1]); return inRange(v, 24, 45) ? { points: v, basis: "points" } : null } },
  { key: "alevel", win: true, re: /\bA[- ]?levels?\b[^.\n]{0,60}?\b((?:A\*|[A-E]){2,4})\b/, make: (m) => /^(?:A\*|[A-E]){2,4}$/.test(m[1]) && !/^E+$/.test(m[1]) ? { grades: m[1] } : null },
  { key: "india_board", win: true, re: /\b(?:CBSE|CISCE|ICSE|ISC|Indian School Certificate|Senior School Certificate|State Board)\b[^.\n]{0,100}?\b(\d{2}(?:\.\d)?)\s*(?:%|per ?cent)/i, make: (m) => { const v = N(m[1]); return inRange(v, 40, 100) ? { average_percent: v } : null } },
  { key: "ca_secondary", re: /\b(?:Ontario Secondary School Diploma|OSSD|Grade 12|secondary school diploma|high school diploma|senior matriculation|BC Dogwood|(?<!national )Baccalaur[eé]at)\b[^.\n]{0,200}?\b(\d{2}(?:\.\d)?)\s*(?:%|per cent)/i, make: (m) => { const v = N(m[1]); return inRange(v, 50, 95) ? { average_percent: v } : null } },
  { key: "bachelor_gpa", re: /\b(?:bachelor|honours|undergraduate|first degree)\b[^.\n]{0,140}?\b(?:GPA|grade point average|GPA of)\b[^.\n]{0,40}?\b(\d(?:\.\d{1,2})?)\b(?:\s*(?:out of|\/)\s*(\d(?:\.\d)?))?/i, make: (m) => { const v = N(m[1]); const sc = m[2] ? N(m[2]) : null; return inRange(v, 1, 10) && (sc === null || [4, 5, 7, 10].includes(sc)) ? { gpa: v, scale: sc } : null } },
]

// every reading on the page text; a reading is kept only when its quote is found in the text unchanged (the quote check) and states the qualification with a value
export function detRead(text: string): DetReading[] {
  const seen = new Set<string>(), out: DetReading[] = []
  for (const u of detUnits(text)) {
    if (detCollapsed(u)) continue  // a flattened table line is skipped, never guessed
    for (const r of RULES) {
      const m = u.match(r.re); if (!m) continue
      const own = OWN[r.key]
      const at = m.index ?? 0
      let q: string, value: ReturnType<Rule["make"]>
      if (r.win) {
        q = untilOther(clause(u, at), 0, own).replace(/[\s,;]+(?:and|or|plus|with)?\s*$/i, "").trim()
        value = r.make(m, q)
      } else {
        // the words from the qualification name to its value name no other test or qualification
        const other = [...families(m[0])].filter((id) => id !== own)
        if (other.length) continue
        q = u
        value = r.make(m, untilOther(u, at, own))
      }
      if (!value) continue
      if (!q || !text.includes(q)) continue  // the quote must be on the page word for word
      // v1.4 (s1009): a maximum or an "up to" figure ("Up to a maximum international ATAR of 99.95") is never a minimum
      if (/\b(?:maximum|up to|max\.)/i.test(q)) continue
      // v1.4 (s1009): the quote carries the value it gives (never a value read from words outside its own quote)
      const vals = Object.entries(value).filter(([k, v]) => k !== "basis" && (typeof v === "number" || typeof v === "string")).map(([, v]) => String(v))
      if (vals.length && !vals.some((v) => q.includes(v))) continue
      // v1.4 (s1009): an overall average is never taken from a mark in one subject ("CBSE ... 65% in English")
      if (value.average_percent !== undefined && vals.some((v) => /^\d/.test(v) && new RegExp("(?:^|[^0-9.])" + v.replace(/\./g, "\\.") + "(?:\\.0+)?\\s*(?:%|per ?cent)?\\s+(?:in|for)\\s+[A-Z][a-z]").test(q))) continue
      const k = r.key + "|" + q
      if (seen.has(k)) continue
      seen.add(k)
      out.push({ kind: "academic_entry", key: r.key, value, quote: q, strength: MIN_WORDS.test(q) ? "stated_minimum" : "mentioned" })
    }
  }
  return out
}

// the other requirements a page prints that this reader does not read (a prerequisite subject, a portfolio, an interview, work experience, bridging study): up to 6 lines, never a line a reading
// quotes or an English test line. A page that prints any of them is not a complete read: the proposal carries each as a dropped requirement and the completeness gate holds the read for a person.
const OTHER_REQ = /\b(?:prerequisites?|pre-requisites?|assumed knowledge|portfolio|folio|audition|interview|work experience|bridging|must have (?:completed|studied)|including (?:[A-Za-z ]{0,30})?(?:mathematics|chemistry|physics|biology|english))\b/i
export function detUncovered(text: string, readings: DetReading[]): string[] {
  const out: string[] = []
  for (const u of detUnits(text)) {
    if (out.length >= 6) break  // fixed: bound on the lines carried
    if (!OTHER_REQ.test(u) || ENGLISH_TEST.test(u) || u.length < 12) continue
    if (readings.some((r) => r.quote.includes(u) || u.includes(r.quote))) continue
    out.push(u.slice(0, 300))
  }
  return out
}
