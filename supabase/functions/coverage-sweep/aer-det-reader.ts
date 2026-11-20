// CF-247 s815 (S1-AER, Platform Admin 20 Nov 2026 10:51 AEDT, Decision 2: "$0 deterministic extraction against the stored pages in Main DB"). A pure, deterministic reader of the English
// proficiency tests and the academic entry qualifications a stored course page states in words. No model, no fetch, no write: it takes the page's text and returns readings, each with a
// verbatim quote that is a substring of that text (checked here, so a reading can never carry words the page does not hold). Readings are SHADOW readings: they are recorded beside Layer 4 and
// are never admitted by this module (Decision 276: AER v1 is frozen and AER v2 admits only through its own gates; the completeness gate, audit sample, page identity and manual locks are untouched).
export const AER_DET_VERSION = "aer-det-v1.1" // v1.1 (20 Nov 2026, s829): Year 12 needs a stated value; University Entrance and NCEA L3 read a same-clause window of 120 characters with a stated credit count and never inside an English-test sentence; IELTS band minimums read in more wordings

export type DetReading = {
  kind: "english_test" | "academic_entry"
  key: string                       // ielts, toefl_ibt, pte, oet, celpip, cambridge, atar, year12, ncea_l3, university_entrance, ca_secondary, bachelor_gpa
  value: Record<string, number | string | boolean | null>
  quote: string                     // verbatim, on the page text
  strength: "stated_minimum" | "mentioned"   // stated_minimum: the quote itself says the score is a minimum, required or overall
}

const MAX_QUOTE = 320  // fixed: a quote is a sentence or line, not a paragraph
const N = (s: string) => Number(s)
const inRange = (v: number, lo: number, hi: number) => Number.isFinite(v) && v >= lo && v <= hi
const MIN_WORDS = /\b(minimum|at least|required|requirement|overall|score of|must|need|no (?:individual )?(?:band|sub-?score|component)|each (?:band|component))\b/i

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

type Rule = { key: string; kind: DetReading["kind"]; win?: boolean; re: RegExp; make: (m: RegExpMatchArray, u: string) => Record<string, number | string | boolean | null> | null }


// the lowest band a sentence says no part of the test may fall below ("no lower than 5.0 in any subtest", "5.5 in each band", "Writing 7 Speaking 7 Reading 7 Listening 7"); null when it states none; never above the overall
const BAND = "([4-9](?:\\.[05])?)"
const BAND_PATTERNS: RegExp[] = [
  new RegExp(`\\b(?:no|not|none)\\s+(?:\\w+\\s+){0,4}?(?:below|less than|lower than|under)\\s+${BAND}`, "i"),            // no band less than 6.0; no sub-score below 5.5; no lower than 5.0
  new RegExp(`\\b(?:not|no)\\s+(?:lower|less)\\s+than\\s+${BAND}`, "i"),
  new RegExp(`\\bwith(?:\\s+a)?\\s+(?:minimum|min\\.?)\\s+(?:of\\s+)?${BAND}\\s+(?:in|for|per|on)\\s+(?:each|any|every|all)\\b`, "i"),
  new RegExp(`\\b${BAND}\\s+(?:in|for|on|per)\\s+(?:each|any|every|all)\\b`, "i"),                                 // 5.5 in each band; 6.0 in any subtest
  new RegExp(`\\b${BAND}\\s+(?:or\\s+(?:above|higher|more)\\s+)?(?:in|for)\\s+(?:each|every|all)\\b`, "i"),
  new RegExp(`\\b(?:each|every)\\s+(?:\\w+\\s+){0,2}?(?:of|at|score of|at least|minimum of)\\s+${BAND}`, "i"),         // each band of 6.0
  new RegExp(`\\b${BAND}\\s+(?:each|per)\\s+(?:band|component|section|skill|subtest|sub-test)\\b`, "i"),            // 5.5 each band
  new RegExp(`\\bminimum\\s+(?:band|component|sub-?score|sub-?test|section)s?\\s+(?:score\\s+)?(?:of\\s+)?${BAND}`, "i"), // minimum band score of 5.5
]
function ieltsBandMin(u: string, overall: number): number | null {
  const comps = [...u.matchAll(/\b(?:Writing|Speaking|Reading|Listening)\s*[:\-]?\s*([4-9](?:\.[05])?)\b/gi)].map((x) => N(x[1]))
  if (comps.length >= 2) { const lo = Math.min(...comps); if (lo <= overall) return lo }
  for (const re of BAND_PATTERNS) { const b = u.match(re); if (b) { const v = N(b[1]); if (inRange(v, 4, 9) && v <= overall) return v } }
  return null
}
// a window of at most 120 characters from the match to the end of its clause; the quote of the three rules that read it
function clause(u: string, at: number): string { const w = u.slice(at, at + 120); const e = w.search(/[.;](?=\s+[A-Z(]|$)/); return (e > 0 ? w.slice(0, e + 1) : w).trim() }
const ENGLISH_TEST = /\b(?:IELTS|TOEFL|PTE|OET|CELPIP|Cambridge|Duolingo)\b/i

const RULES: Rule[] = [
  { key: "ielts", kind: "english_test", re: /\bIELTS\b(?:\s+Academic)?[^.\n]{0,90}?\b([4-9](?:\.[05])?)\b/i, make: (m, u) => {
      const overall = N(m[1]); if (!inRange(overall, 4, 9) || (overall * 2) % 1 !== 0) return null
      return { overall, band_min: ieltsBandMin(u, overall) } } },
  { key: "toefl_ibt", kind: "english_test", re: /\bTOEFL(?:\s*iBT)?\b[^.\n]{0,90}?\b(\d{2,3})\b/i, make: (m) => { const v = N(m[1]); return inRange(v, 32, 120) ? { overall: v } : null } },
  { key: "pte", kind: "english_test", re: /\bPTE(?:\s*Academic)?\b[^.\n]{0,90}?\b(\d{2})\b/i, make: (m) => { const v = N(m[1]); return inRange(v, 30, 90) ? { overall: v } : null } },
  { key: "oet", kind: "english_test", re: /\bOET\b[^.\n]{0,90}?\b(?:grade\s+)?([A-E][+]?|[3-5]\d{2})\b(?!\w)/, make: (m): Record<string, number | string> | null => { if (/^[A-E]\+?$/.test(m[1])) return { grade: m[1] }; return inRange(N(m[1]), 300, 500) ? { score: N(m[1]) } : null } },
  { key: "celpip", kind: "english_test", re: /\bCELPIP\b[^.\n]{0,90}?\b(\d{1,2})\b/i, make: (m) => { const v = N(m[1]); return inRange(v, 3, 12) ? { level: v } : null } },
  { key: "cambridge", kind: "english_test", re: /\b(?:Cambridge|C1 Advanced|C2 Proficiency|CAE|CPE)\b[^.\n]{0,100}?\b(1[5-9]\d|2[0-3]\d)\b/i, make: (m) => { const v = N(m[1]); return inRange(v, 160, 230) ? { score: v } : null } },
  { key: "atar", kind: "academic_entry", re: /\bATAR\b[^.\n]{0,70}?\b(\d{2}(?:\.\d{1,2})?)\b(?!\s*(?:%|per cent|credits))/i, make: (m) => { const v = N(m[1]); return inRange(v, 30, 99.95) && !(v >= 1990 && v <= 2100) ? { atar: v } : null } },
  { key: "ncea_l3", kind: "academic_entry", win: true, re: /\b(?:\d{2,3}\s+credits?[^.\n]{0,60}?)?\bNCEA\b[^.\n]{0,40}?\bLevel\s*3\b/i, make: (_m, q) => { if (ENGLISH_TEST.test(q)) return null; const c = q.match(/\b(\d{2,3})\s+credits?\b/i); return c ? { credits: N(c[1]) } : null } },
  { key: "university_entrance", kind: "academic_entry", win: true, re: /\bUniversity Entrance\b/i, make: (_m, q) => { if (ENGLISH_TEST.test(q)) return null; const c = q.match(/\b(\d{1,3})\s+credits?\b/i); return c ? { credits: N(c[1]) } : null } },
  { key: "year12", kind: "academic_entry", win: true, re: /\b(?:Year 12|Victorian Certificate of Education|VCE|HSC|Higher School Certificate|QCE|Queensland Certificate of Education|South Australian Certificate of Education|SACE|WACE|Tasmanian Certificate of Education|TCE|NTCET|ACT Senior Secondary)\b/, make: (_m, q): Record<string, number | string> | null => { if (ENGLISH_TEST.test(q) || /\bATAR\b/.test(q)) return null; const v = q.match(/\b(?:score|mark|grade|rank|result|average|percent|units? 3 and 4)\b[^.\n]{0,30}?\b(\d{1,3}(?:\.\d{1,2})?)\b(?!\s*(?:and|credits?))/i) || q.match(/\b(\d{1,3}(?:\.\d{1,2})?)\s*(?:%|per cent|or (?:above|higher|more))/i); if (v) { const n = N(v[1]); return inRange(n, 1, 100) && n !== 12 ? { value: n } : null } const g = q.match(/\bgrade\s+([A-E][+-]?)\b/i) || q.match(/\b(?:an?\s+)?([A-E][+-]?)\s+grade\b/); return g ? { grade: g[1].toUpperCase() } : null } },
  { key: "ca_secondary", kind: "academic_entry", re: /\b(?:Ontario Secondary School Diploma|OSSD|Grade 12|secondary school diploma|high school diploma|senior matriculation|BC Dogwood|Baccalaur[eé]at)\b[^.\n]{0,200}?\b(\d{2}(?:\.\d)?)\s*(?:%|per cent)/i, make: (m) => { const v = N(m[1]); return inRange(v, 50, 95) ? { average_percent: v } : null } },
  { key: "bachelor_gpa", kind: "academic_entry", re: /\b(?:bachelor|honours|undergraduate|first degree)\b[^.\n]{0,140}?\b(?:GPA|grade point average|GPA of)\b[^.\n]{0,40}?\b(\d(?:\.\d{1,2})?)\b(?:\s*(?:out of|\/)\s*(\d(?:\.\d)?))?/i, make: (m) => { const v = N(m[1]); const sc = m[2] ? N(m[2]) : null; return inRange(v, 1, 10) && (sc === null || [4, 5, 7, 10].includes(sc)) ? { gpa: v, scale: sc } : null } },
]

// every reading on the page text; a reading is kept only when its quote is found in the text unchanged (the quote check) and states the test or qualification with a value
export function detRead(text: string): DetReading[] {
  const seen = new Set<string>(), out: DetReading[] = []
  for (const u of detUnits(text)) {
    for (const r of RULES) {
      const m = u.match(r.re); if (!m) continue
      const q = r.win ? clause(u, m.index ?? 0) : u
      const value = r.make(m, q); if (!value) continue
      if (!text.includes(q)) continue  // the quote must be on the page word for word
      const k = r.key + "|" + q
      if (seen.has(k)) continue
      seen.add(k)
      out.push({ kind: r.kind, key: r.key, value, quote: q, strength: MIN_WORDS.test(q) ? "stated_minimum" : "mentioned" })
    }
  }
  return out
}
