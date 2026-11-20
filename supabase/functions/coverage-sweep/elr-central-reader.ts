// CF-247 s884 (session S1-ELR-Central, Platform Admin 20 Nov 2026 22:07 AEDT, decision "populate the remaining Table 1 English gaps from each university's central
// English requirements page via the governed provider English policy route"): elr-central-v1.0, a pure, deterministic reader of a stored central English requirements page.
// It finds the requirement for each study-level tier the page states (undergraduate, postgraduate coursework, higher degree by research, VET/diploma), for IELTS, TOEFL iBT,
// PTE Academic (decimals kept), OET, CELPIP and Cambridge, by acronym or spelled-out name, using the elr-det-v1.0 test reader. No model, no fetch, no write.
// Strict tiers: a value is given to a tier only when its line, its table row or the heading it sits under names that tier, or the line says it applies to all courses
// (undergraduate and postgraduate only). Two different values of one test for one tier are a conflict: that test is left out of the tier and reported.
// Regulated disciplines (nursing, midwifery, medicine, allied health, education and teaching, law, social work) are never a tier default: a line about one of them is
// reported in discipline_higher, so the plan holds those courses for a person. Named awards ("Bachelor of …") and pathway lines are not defaults either.
import { elrRead, elrUnits, type ElrKey, type ElrReading } from "./elr-det-reader.ts"

export const ELR_CENTRAL_VERSION = "elr-central-v1.2"
// v1.2 (21 Nov 2026, session S1-ELR-Bands-And-Crawl, Platform Admin 09:00 AEDT): IELTS sub-score wording ("band 6.0", "no band less than 6.0", "IELTS band score")
// is no longer taken for an English band scheme; a scheme is flagged only by "English band(s)/level(s)" or a line, row, column or heading labelled "Band A", "Band 2"
// or "English level 3". The test values given for each named band are read into band_defs (one value per band and test; two values are a conflict and the test is
// left out of that band). A band is never a study-level default: it is used only for a course whose own page names that band (elr-band-reader.ts, elr-band-v1.0).
// v1.1 (21 Nov 2026, session S1-ELR-Central-Policy, Platform Admin 07:48 AEDT): tables whose columns are study levels and whose rows are tests; "a score of 6.5 in IELTS"
// (value before the test name); and the values found without a study level are reported (untiered, with the page's band or level scheme flagged) so a page that
// sorts courses into English bands is told apart from a page that states no test at all. Nothing else changes; tiers stay strict.
export type Tier = "undergraduate" | "postgraduate" | "research" | "vet"
export type CentralReq = { test_code: string; overall_score: number; component_scores: Record<string, number>; quote: string }
export type CentralReading = {
  defaults: Partial<Record<Tier, CentralReq[]>>
  conflicts: { tier: Tier; test_code: string; values: number[] }[]
  discipline_higher: { discipline: string; quote: string }[]
  tiers_seen: Tier[]
  readings: number
  values_found: number              // every test value on the page, with or without a study level (v1.1)
  untiered: string[]                // up to 5 lines with a value but no study level (v1.1)
  bands: boolean                    // the page sorts courses into English bands or levels (v1.1; v1.2: IELTS sub-score wording is not a scheme)
  band_defs: Record<string, CentralReq[]>                                   // v1.2: the values each named band states ("band A", "band 2", "level 3")
  band_conflicts: { band: string; test_code: string; values: number[] }[]   // v1.2
}

// v1.2: a label at the start of a line, table cell or heading: "Band A", "Band 2", "English Level 3", "**English band B**". Never a score ("Band 6.5", "band 7.0"),
// never an IELTS descriptor ("IELTS band 6"); "Level 2" alone (an AQF or course level) is not a label, only "English (language) level 2".
const BAND_LABEL = /^\s*(?:[-*#>|]\s*)*(?:\*\*|__)?\s*(english\s+(?:language\s+)?(?:proficiency\s+)?)?(band|level)\s+([A-F]|[1-9])(?![.\d])\b/i
export function bandOf(s: string): string | null {
  const m = s.match(BAND_LABEL)
  if (!m) return null
  if (m[2].toLowerCase() === "level" && !m[1]) return null
  return `${m[2].toLowerCase()} ${m[3].toUpperCase()}`
}
const SCHEME = /\bEnglish (?:language )?(?:bands|levels)\b|\bEnglish (?:language )?(?:proficiency )?(?:band|level)\s+(?:[A-F]|[1-9])(?![.\d])\b/i

const CODE: Record<ElrKey, string> = { ielts: "IELTS", toefl_ibt: "TOEFL_IBT", pte: "PTE", oet: "OET", celpip: "CELPIP", cambridge: "CAE" }
const TIERS: Tier[] = ["undergraduate", "postgraduate", "research", "vet"]
const RESEARCH = /\b(?:higher degrees? by research|HDR|research degrees?|research (?:programs?|programmes?|students?|candidates?|candidature)|PhD|doctor(?:al|ate)?s?\b|doctor of philosophy|masters? (?:by|of) research|MPhil)\b/i
const VET = /\b(?:VET|vocational(?: education)?|TAFE|advanced diplomas?|(?<!graduate |post-?graduate )diplomas?|certificates? (?:I{1,3}V?|IV|[1-4])\b|skills? sets?|apprenticeships?|traineeships?)\b/i
const PG = /\b(?:post-?graduate|graduate (?:certificate|diploma)s?|masters?(?:'s)?(?! (?:by|of) research)|coursework|PG)\b/i
const UG = /\b(?:under-?graduate|bachelors?(?:'s)?(?: degrees?)?|associate degrees?|UG)\b/i
const ALL = /\b(?:all (?:undergraduate and postgraduate |)(?:courses|programs?|programmes?|applicants|students|degrees)|any (?:course|program|programme)|every (?:course|program|programme))\b/i
const DISCIPLINE: [string, RegExp][] = [
  ["nursing", /\bnurs(?:e|es|ing)\b/i], ["midwifery", /\bmidwi(?:fe|fery|ves)\b/i], ["medicine", /\b(?:medicine|medical|MBBS|MD)\b/i],
  ["allied health", /\b(?:allied health|physiotherapy|occupational therapy|speech pathology|pharmacy|dentistry|dental|optometry|podiatry|paramedic(?:ine)?|radiograph\w*|dietetics|psychology)\b/i],
  ["education", /\b(?:teach(?:er|ers|ing)|initial teacher education|(?:bachelor|master|graduate diploma) of education)\b/i], ["law", /\b(?:laws?|juris doctor|legal practice)\b/i], ["social work", /\bsocial work\b/i],
]
const NAMED_AWARD = /\b(?:Bachelor|Master|Doctor|Graduate (?:Certificate|Diploma)|Diploma|Advanced Diploma|Associate Degree|Certificate (?:I{1,3}V?|IV))\s+(?:of|in)\s+[A-Z]/
const PATHWAY = /\b(?:foundation (?:program|programme|studies|year|course)|pathway|ELICOS|English language (?:course|program|programme|bridging)|bridging|direct entry|English for Academic Purposes|EAP\b|study abroad|exchange)\b/i
const TEST_NAME = /\b(?:IELTS|TOEFL|PTE|OET|CELPIP|Cambridge|C1 Advanced|C2 Proficiency|Pearson|Occupational English Test)\b/i

// the tiers a piece of text names (research first, so "doctoral" is not read as postgraduate coursework; "graduate diploma" is postgraduate, not VET)
export function tiersOf(s: string): Tier[] {
  const out: Tier[] = []
  if (RESEARCH.test(s) && !/\bcoursework\b/i.test(s)) out.push("research")
  const noPgDip = s.replace(/\b(?:graduate|post-?graduate) (?:certificate|diploma)s?\b/gi, " postgraduate ")
  if (PG.test(noPgDip.replace(RESEARCH, " "))) out.push("postgraduate")
  if (UG.test(s)) out.push("undergraduate")
  if (VET.test(noPgDip)) out.push("vet")
  return out
}
export function disciplineOf(s: string): string | null { for (const [d, re] of DISCIPLINE) if (re.test(s)) return d; return null }

// a markdown table whose header names tests: each body row is read as "<test> <cell>" per column, quoted by its own row line
function tableRows(lines: string[], i: number): { text: string; quote: string; label: string }[] | null {
  const head = lines[i]
  if (!/^\s*\|.*\|\s*$/.test(head) || !TEST_NAME.test(head) || !/^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1] || "")) return null
  const cells = (l: string) => l.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim())
  const hs = cells(head), out: { text: string; quote: string; label: string }[] = []
  for (let j = i + 2; j < lines.length && /^\s*\|.*\|\s*$/.test(lines[j]); j++) {
    const cs = cells(lines[j]); let text = ""
    hs.forEach((h, k) => { if (k > 0 && TEST_NAME.test(h) && cs[k]) text += `${h}: ${cs[k]} overall. ` })
    out.push({ text, quote: lines[j].trim(), label: cs[0] || "" })
  }
  return out
}

// a markdown table whose header names study levels and whose rows name tests ("| Test | Undergraduate | Postgraduate |" / "| IELTS Academic | 6.0 (5.5) | 6.5 (6.0) |")
function tierColumnRows(lines: string[], i: number): { tier: Tier; text: string; quote: string }[] | null {
  const head = lines[i]
  if (!/^\s*\|.*\|\s*$/.test(head) || TEST_NAME.test(head) || !/^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1] || "")) return null
  const cells = (l: string) => l.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim())
  const hs = cells(head).map((h) => { const t = tiersOf(h); return t.length === 1 && !disciplineOf(h) ? t[0] : null })
  if (!hs.some((t, k) => k > 0 && t)) return null
  const out: { tier: Tier; text: string; quote: string }[] = []
  for (let j = i + 2; j < lines.length && /^\s*\|.*\|\s*$/.test(lines[j]); j++) {
    const cs = cells(lines[j])
    if (!TEST_NAME.test(cs[0] || "")) continue
    hs.forEach((t, k) => { if (k > 0 && t && cs[k]) out.push({ tier: t, text: `${cs[0]}: ${cs[k]} overall.`, quote: lines[j].trim() }) })
  }
  return out
}
// v1.2: a markdown table whose header names bands and whose rows name tests ("| Test | Band A | Band B |" / "| IELTS | 6.0 | 6.5 |")
function bandColumnRows(lines: string[], i: number): { band: string; text: string; quote: string }[] | null {
  const head = lines[i]
  if (!/^\s*\|.*\|\s*$/.test(head) || TEST_NAME.test(head) || !/^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1] || "")) return null
  const cells = (l: string) => l.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim())
  const hs = cells(head).map((h) => bandOf(h))
  if (!hs.some((b, k) => k > 0 && b)) return null
  const out: { band: string; text: string; quote: string }[] = []
  for (let j = i + 2; j < lines.length && /^\s*\|.*\|\s*$/.test(lines[j]); j++) {
    const cs = cells(lines[j])
    if (!TEST_NAME.test(cs[0] || "")) continue
    hs.forEach((b, k) => { if (k > 0 && b && cs[k]) out.push({ band: b, text: `${cs[0]}: ${cs[k]} overall.`, quote: lines[j].trim() }) })
  }
  return out
}
// "an overall score of 6.5 in IELTS (Academic)": the value comes before the test name; read it as "IELTS 6.5 overall", quoted by the line itself
const BEFORE = /(\d{1,3}(?:\.\d)?)\s*(?:overall\s*)?(?:or (?:above|higher|more)\s*)?(?:in|on|for|from)\s+(?:the\s+|an?\s+)?(IELTS(?: Academic)?|TOEFL(?: iBT)?|PTE(?: Academic)?|Pearson Test of English(?: Academic)?|CELPIP)\b/gi
function valueFirst(u: string): string {
  let extra = ""
  for (const m of u.matchAll(BEFORE)) extra += ` ${m[2]} ${m[1]} overall.`
  return extra ? u + " |" + extra : u
}

// split a line that names two or more tiers into clauses, one tier each ("6.0 for undergraduate and 6.5 for postgraduate coursework", "Undergraduate: 6.0; postgraduate: 6.5");
// a clause without a test name takes the test named last before it on the line
function clauses(u: string): string[] {
  const out: string[] = []; let last = ""
  for (const c of u.split(/;|\.\s+|,\s*(?=and\b)|\band\b|,\s+(?=(?:under|post)?-?graduate|higher|research|vocational|VET|diploma)/i)) {
    const t = c.trim(); if (!t) continue
    const m = t.match(TEST_NAME); if (m) last = m[0]
    out.push(m || !last ? t : `${last} ${t}`)
  }
  return out
}

export function centralRead(text: string): CentralReading {
  const lines = text.split(/\n/)
  type Hit = { tier: Tier; r: ElrReading; quote: string }
  const hits: Hit[] = [], disc: { discipline: string; quote: string }[] = [], seen = new Set<Tier>()
  let ctx: Tier[] = [], ctxDisc: string | null = null, n = 0, found = 0
  const untiered: string[] = []
  const bandHits: { band: string; r: ElrReading; quote: string }[] = []
  let ctxBand: string | null = null
  const takeBand = (band: string, rs: ElrReading[], quote: string) => { for (const r of rs) { if (r.flags.includes("pathway")) continue; n++; bandHits.push({ band, r, quote }) } }
  const take = (tiers: Tier[], rs: ElrReading[], quote: string, discipline: string | null) => {
    for (const r of rs) {
      if (r.flags.includes("pathway")) continue
      n++
      if (discipline) { disc.push({ discipline, quote }); continue }
      for (const t of tiers) { hits.push({ tier: t, r, quote }); seen.add(t) }
    }
  }
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i], line = raw.trim()
    if (!line) continue
    const bcols = bandColumnRows(lines, i)
    if (bcols) {
      for (const c of bcols) { const rs = elrRead(c.text).map((r) => ({ ...r, quote: c.quote })); found += rs.length; takeBand(c.band, rs, c.quote) }
      let j = i + 2; while (j < lines.length && /^\s*\|.*\|\s*$/.test(lines[j])) j++
      i = j - 1
      continue
    }
    const cols = tierColumnRows(lines, i)
    if (cols) {
      for (const c of cols) { const rs = elrRead(c.text).map((r) => ({ ...r, quote: c.quote })); found += rs.length; take([c.tier], rs, c.quote, ctxDisc) }
      let j = i + 2; while (j < lines.length && /^\s*\|.*\|\s*$/.test(lines[j])) j++
      i = j - 1
      continue
    }
    const rows = tableRows(lines, i)
    if (rows) {
      for (const row of rows) {
        if (PATHWAY.test(row.label)) continue
        const rb = bandOf(row.label) ?? (tiersOf(row.label).length ? null : ctxBand)
        if (rb) { const rs = elrRead(row.text).map((r) => ({ ...r, quote: row.quote })); found += rs.length; takeBand(rb, rs, row.quote); continue }
        const d = disciplineOf(row.label) ?? ctxDisc
        const named = NAMED_AWARD.test(row.label)
        let tiers = tiersOf(row.label)
        if (!tiers.length) tiers = ctx
        const rs = elrRead(row.text).map((r) => ({ ...r, quote: row.quote })); found += rs.length
        if (named && !d) continue
        if (!tiers.length && !d) { if (rs.length && untiered.length < 5) untiered.push(row.quote.slice(0, 200)); continue }
        take(tiers, rs, row.quote, d)
      }
      i += rows.length + 1
      continue
    }
    const heading = /^#{1,6}\s/.test(line) || (line.length <= 90 && !TEST_NAME.test(line) && !/\d/.test(line))
    const hb = bandOf(line)
    if (hb && (heading || !TEST_NAME.test(line))) { ctxBand = hb; ctx = []; ctxDisc = null; continue }
    if (heading) {
      const t = tiersOf(line), d = disciplineOf(line)
      if (t.length || d || /^#{1,3}\s/.test(line)) ctxBand = null
      if (t.length || d) { ctx = t; ctxDisc = d } else if (/^#{1,3}\s/.test(line)) { ctx = []; ctxDisc = null }
      continue
    }
    for (const u0 of elrUnits(raw)) {
      if (!TEST_NAME.test(u0) || PATHWAY.test(u0)) continue
      const u = valueFirst(u0)
      const ub = bandOf(u0) ?? (tiersOf(u).length ? null : ctxBand)
      if (ub) { const rs = elrRead(u).map((r) => ({ ...r, quote: u0 })); found += rs.length; takeBand(ub, rs, u0); continue }
      const d = disciplineOf(u) ?? ctxDisc
      const named = NAMED_AWARD.test(u)
      const own = tiersOf(u)
      if (named && !d) continue
      if (own.length >= 2 && !ALL.test(u)) {
        // one requirement for each tier the line names
        for (const p of clauses(u)) { const t = tiersOf(p); const rs = elrRead(p).map((r) => ({ ...r, quote: u0 })); found += rs.length; if (t.length === 1) take(t, rs, u0, disciplineOf(p) ?? (d && disciplineOf(u) ? null : d)) }
        continue
      }
      const tiers = own.length ? own : ALL.test(u) ? (["undergraduate", "postgraduate"] as Tier[]) : ctx
      const rs = elrRead(u).map((r) => ({ ...r, quote: u0 })); found += rs.length
      if (!tiers.length && !d) { if (rs.length && untiered.length < 5) untiered.push(u0.slice(0, 200)); continue }
      take(tiers, rs, u0, d)
    }
  }
  // one value per tier and test; two values are a conflict and the test is left out of that tier
  const defaults: Partial<Record<Tier, CentralReq[]>> = {}, conflicts: CentralReading["conflicts"] = []
  for (const t of TIERS) {
    const byTest = new Map<string, Hit[]>()
    for (const h of hits.filter((x) => x.tier === t)) { const c = CODE[h.r.key]; byTest.set(c, [...(byTest.get(c) || []), h]) }
    const reqs: CentralReq[] = []
    for (const [code, hs] of byTest) {
      const vals = [...new Set(hs.map((h) => JSON.stringify(h.r.value)))]
      if (vals.length > 1) { conflicts.push({ tier: t, test_code: code, values: [...new Set(hs.map((h) => h.r.value.overall ?? 0))] }); continue }
      const v = hs[0].r.value
      let overall = v.overall, comps: Record<string, number> = { ...(v.components || {}) }
      if (code === "OET") { if (!v.components || Object.keys(v.components).length < 4) continue; overall = Math.min(...Object.values(v.components) as number[]) }
      if (overall === undefined) continue
      reqs.push({ test_code: code, overall_score: overall, component_scores: comps, quote: hs[0].quote.slice(0, 400) })
    }
    if (reqs.length) defaults[t] = reqs
  }
  // v1.2: the same rule for each named band
  const band_defs: Record<string, CentralReq[]> = {}, band_conflicts: CentralReading["band_conflicts"] = []
  for (const b of [...new Set(bandHits.map((h) => h.band))]) {
    const byTest = new Map<string, typeof bandHits>()
    for (const h of bandHits.filter((x) => x.band === b)) { const c = CODE[h.r.key]; byTest.set(c, [...(byTest.get(c) || []), h]) }
    const reqs: CentralReq[] = []
    for (const [code, hs] of byTest) {
      const vals = [...new Set(hs.map((h) => JSON.stringify(h.r.value)))]
      if (vals.length > 1) { band_conflicts.push({ band: b, test_code: code, values: [...new Set(hs.map((h) => h.r.value.overall ?? 0))] }); continue }
      const v = hs[0].r.value
      let overall = v.overall
      const comps: Record<string, number> = { ...(v.components || {}) }
      if (code === "OET") { if (!v.components || Object.keys(v.components).length < 4) continue; overall = Math.min(...Object.values(v.components) as number[]) }
      if (overall === undefined) continue
      reqs.push({ test_code: code, overall_score: overall, component_scores: comps, quote: hs[0].quote.slice(0, 400) })
    }
    if (reqs.length) band_defs[b] = reqs
  }
  const bands = Object.keys(band_defs).length > 0 || bandHits.length > 0 || SCHEME.test(text)
  return { defaults, conflicts, discipline_higher: disc.slice(0, 20), tiers_seen: TIERS.filter((t) => seen.has(t)), readings: n, values_found: found, untiered, bands, band_defs, band_conflicts }
}
