// CF-247 complete coverage: pure page functions (no I/O), unit-tested in the Pilot repo.
// Fee, intake and English rules follow layer2-course-fact-extract-v2 (the governed generic extractor) with two
// additions: the fee year printed next to an amount, and the IELTS minimum band.

export function clean(s: string) { return String(s ?? "").replace(/\s+/g, " ").trim() }

export function htmlToText(html: string) {
  return clean(html.replace(/<(script|style|noscript|svg|template)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>|<\/(p|li|tr|h[1-6]|div|td|th|dd|dt|section)>/gi, " \n ")
    .replace(/<[^>]+>/g, " ").replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/&#36;|&dollar;/gi, "$")
    .replace(/&#39;|&rsquo;|&lsquo;/gi, "'").replace(/&quot;|&ldquo;|&rdquo;/gi, '"').replace(/&ndash;|&mdash;/gi, "-"))
}

export function titleOf(html: string) { const m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i); return m ? htmlToText(m[1]) : "" }
export function h1Of(html: string) { const m = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i); return m ? htmlToText(m[1]) : "" }
const norm = (s: string) => clean(s).toLowerCase().replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").trim()
// New Zealand titles: "NZ" and "New Zealand" are the same words.
const normNz = (s: string) => norm(clean(s).replace(/\+/g, " and ")).replace(/\bnz\b/g, "new zealand")

// Identity: the CRICOS course code is printed on the page, or the exact course title is the page heading or the
// start of the page title. Anything else is a mismatch and nothing from the page is used.
// Decision 217 (2 Oct 2026, NZ): two more ways a New Zealand page proves it is the course's page:
//  - "nzqa_code": the NZQA qualification number is printed with its label ("NZQA", "qualification", "programme code");
//  - "title_level": the NZQA title ends "(Level N)"; the page heading is that title without the level (or with the same
//    level), no other level appears in the heading, and the page shows "Level N".
export function identity(html: string, text: string, courseTitle: string, courseCode: string, codeOnly = false, country = "") {
  const code = clean(courseCode).toUpperCase()
  if (code.length >= 6 && new RegExp(`\\b${code}\\b`).test(text.toUpperCase())) return "cricos_code"
  if (/^[0-9]{3,5}$/.test(code) && new RegExp(`(nzqa|qualification|programme|program)\\s*(number|code|id|ref(erence)?|no\\.?)?\\s*[:#]?\\s*${code}\\b`, "i").test(text)) return "nzqa_code"
  if (codeOnly) return null
  const t = norm(courseTitle), h1 = norm(h1Of(html)), title = norm(titleOf(html))
  if (t && (h1 === t || title === t || title.startsWith(t + " ") || h1.startsWith(t + " international"))) return "exact_title"
  // v0.5.7 (2 Oct 2026): a vocational page often puts the national qualification code before the title
  // ("CHC52025 Diploma of Community Services", "10973NAT Certificate IV in ..."): the title after that code is still
  // the exact course title. Only the code is removed; everything else must match exactly.
  const codeless = (s: string) => clean(s).replace(/^(?:[A-Z]{3,4}\d{5}|\d{5}NAT)\s*[-–—:|]?\s*/, "")
  const titleHead = clean(titleOf(html)).split(/\s+[|–—]\s+|\s+-\s+/)[0] || ""
  if (t && t.split(" ").length >= 2 && (norm(codeless(h1Of(html))) === t || norm(codeless(titleHead)) === t)) return "exact_title"
  return titleLevel(h1Of(html), titleOf(html), text, courseTitle) ?? (country === "CA" ? fieldAward(h1Of(html), titleOf(html), text, courseTitle) : null)
}

// Decision 235 (2 Oct 2026, Platform Admin 22:55): Canadian catalogue titles are written "Field: Award (ABBR) - Campus"
// ("Medical Genetics: Doctor of Philosophy (PhD) - UBCV") or "Award Field" ("Master of Science Health Sciences"), while
// the university's page says "Doctor of Philosophy in Medical Genetics". A page matches when its main heading (or the
// first part of its title) holds the same award (in words or its abbreviation) and, once the award and joining words are
// taken out, exactly the same field. Double, combined and dual awards, generic awards and unclear titles never match.
const AWARDS = ["doctor of philosophy", "doctor of education", "master of business administration", "master of public health",
  "master of applied science", "master of engineering", "master of science", "master of arts", "master of education",
  "master of fine arts", "master of music", "master of social work", "master of nursing", "master of public policy",
  "masters in education", "bachelor of applied science", "bachelor of business administration", "bachelor of science",
  "bachelor of arts", "bachelor of education", "bachelor of commerce", "bachelor of fine arts", "bachelor of music",
  "bachelor of engineering", "bachelor of kinesiology", "bachelor of nursing", "bachelor of social work",
  "bachelor of health science", "bachelor of design", "bachelor of computing science", "bachelor of management"]
const JOIN = new Set(["in", "of", "the", "degree", "program", "programme", "major", "and"])
export function parseCaTitle(courseTitle: string): { field: string; award: string; abbr: string; campus: string } | null {
  let s = clean(courseTitle)
  if (/\b(combined|dual|double|joint|concurrent)\b/i.test(s)) return null
  let campus = ""
  const camp = s.match(/\s*[-(]\s*(UBCV|UBCO)\s*\)?\s*$/i) || s.match(/\(\s*(UBCV|UBCO)\s*\)/i)
  if (camp) { campus = camp[1].toUpperCase(); s = s.replace(camp[0], " ").trim() }
  let field = "", award = "", abbr = ""
  if (s.includes(":")) {
    field = s.slice(0, s.indexOf(":"))
    let rest = s.slice(s.indexOf(":") + 1)
    const ab = rest.match(/\(([A-Za-z.]{2,8})\)/); if (ab) { abbr = ab[1].replace(/\./g, ""); rest = rest.replace(ab[0], " ") }
    rest = rest.replace(/\s+-\s+(major|honours|open learning).*$/i, "").replace(/\bdegree\b/i, " ")
    award = norm(rest)
  } else {
    const t = norm(s)
    const a = AWARDS.find((x) => t.startsWith(x + " "))
    if (!a) return null
    award = a; field = t.slice(a.length).replace(/^in\s+/, "")
  }
  field = norm(field)
  if (!AWARDS.includes(award) || !field || field.split(" ").length > 8 || /\bco op\b|\boption\b/.test(field)) return null
  return { field, award, abbr: abbr.toLowerCase(), campus }
}
export function fieldAward(rawH1: string, rawTitle: string, text: string, courseTitle: string) {
  const p = parseCaTitle(courseTitle)
  if (!p) return null
  const titleHead = clean(rawTitle).split(/\s+[|–—]\s+|\s+-\s+|\s*\|\s*/)[0] || ""
  // UBC Okanagan: the heading or the page title must say Okanagan (the Vancouver page can mention it in menus)
  if (p.campus === "UBCO" && !/\bokanagan\b/i.test(rawH1 + " " + rawTitle)) return null
  for (const raw of [rawH1, titleHead]) {
    let h = " " + norm(raw.replace(/\(([A-Za-z.]{2,8})\)/g, (_m, x) => " " + x.replace(/\./g, "") + " ")) + " "
    if (h.trim().length === 0) continue
    if (p.campus === "UBCV" && /\bokanagan\b/.test(h)) continue
    let hasAward = false
    if (h.includes(" " + p.award + " ")) { h = h.replace(" " + p.award + " ", " "); hasAward = true }
    if (p.abbr && h.includes(" " + p.abbr + " ")) { h = h.replace(" " + p.abbr + " ", " "); hasAward = true }
    if (!hasAward) continue
    // the award must not be named twice in different words (a page about two awards)
    if (AWARDS.some((a) => a !== p.award && h.includes(" " + a + " "))) continue
    const words = h.trim().split(/\s+/)
    while (words.length && JOIN.has(words[0]) && !p.field.startsWith(words[0] + " ")) words.shift()
    while (words.length && JOIN.has(words[words.length - 1]) && !p.field.endsWith(" " + words[words.length - 1])) words.pop()
    if (words.join(" ") === p.field) return "field_award"
  }
  return null
}

export function titleLevel(rawH1: string, rawTitle: string, text: string, courseTitle: string) {
  const m = clean(courseTitle).match(/^(.*?)\s*\(\s*Level\s+(\d{1,2})\s*\)\s*$/i)
  if (!m) return null
  const base = normNz(m[1]), lvl = m[2], withLevel = `${base} level ${lvl}`
  if (base.split(" ").length < 3) return null
  // the page title's first part, before the site name ("Bachelor of X | Wintec", "Bachelor of X - EIT")
  const titleHead = clean(rawTitle).split(/\s+[|\u2013\u2014:-]\s+|\s*\|\s*/)[0] || ""
  for (const h of [normNz(rawH1), normNz(titleHead)]) {
    if (!h) continue
    if (h === withLevel) return "title_level"
    // a provider may drop "New Zealand" from the qualification name ("Certificate in Cookery"); the level must still show
    const sameName = h === base || ("new zealand " + h === base && h.split(" ").length >= 3)
    if (sameName && new RegExp(`\\blevel\\s*${lvl}\\b`, "i").test(text)) {
      // the same qualification named at another level on the page: the page is not this course's alone
      const t = normNz(text), other = [...t.matchAll(new RegExp(`${base.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")} level (\\d{1,2})`, "g"))].some((x) => x[1] !== lvl)
      if (!other) return "title_level"
    }
  }
  return null
}

// Decision 217: New Zealand pages are read in NZD (NZD, NZ$ or a bare $); amounts marked as another currency
// (AUD, A$, US$) are left out there. Australian pages are read exactly as before.
// Decision 220: Canadian pages are read in CAD (CAD, CA$, C$ or a bare $) the same way.
// a currency marker written immediately before "$" (US$, A$, AU$) or as a word before it (AUD 5,000 / USD $5,000)
const foreignBefore = (pre: string) => /(?:^|[^A-Za-z])(?:US|AU|A|C|S|HK)$/.test(pre) || /(?:^|[^A-Za-z])(?:AUD|USD|CAD|SGD|HKD|NZD)\s*$/i.test(pre)
const FEE_RE: Record<string, { re: RegExp; own: RegExp; explicit: RegExp }> = {
  NZD: { re: /(?:NZD\s*\$?|NZ\s?\$|\$)\s*(\d{1,3}(?:,\d{3})+|\d{4,6})(?:\.\d{2})?(?![\d,])/gi, own: /^NZ/i, explicit: /(?:NZD\s*|NZ\s?\$)\s*[\d,]+/i },
  CAD: { re: /(?:CAD\s*\$?|CA\s?\$|C\$|\$)\s*(\d{1,3}(?:,\d{3})+|\d{4,6})(?:\.\d{2})?(?![\d,])/gi, own: /^C/i, explicit: /(?:CAD\s*|CA\s?\$|C\$)\s*[\d,]+/i },
}
export function currencyFor(country: string | null | undefined): "AUD" | "NZD" | "CAD" {
  return country === "NZ" ? "NZD" : country === "CA" ? "CAD" : "AUD"
}
// v0.5.5: which student view the text just before an amount belongs to, from the last view marker in it.
const VIEW_MARKERS: [RegExp, "domestic" | "international"][] = [
  [/content is for domestic students|switch(?: from domestic)? to international|local student fee|fees? for (?:australian|domestic|local) students|domestic students? fees?|domestic (?:student )?fee breakdown|commonwealth supported place/gi, "domestic"],
  [/content is for international students|switch(?: from international)? to (?:domestic|local)|international students? fees?|fees? for (?:international|overseas) students|international (?:indicative )?(?:annual )?(?:course |tuition )?fees?|overseas students? fees?/gi, "international"],
]
export function viewBefore(pre: string): "domestic" | "international" | null {
  let best = -1, view: "domestic" | "international" | null = null
  for (const [re, v] of VIEW_MARKERS) for (const m of pre.matchAll(re)) if ((m.index ?? -1) > best) { best = m.index ?? -1; view = v }
  return view
}
export function fee(text: string, currency: "AUD" | "NZD" | "CAD" = "AUD") {
  const own = FEE_RE[currency], nz = Boolean(own)
  const re = own ? new RegExp(own.re.source, "gi")
                : /(?:AUD\s*\$?|A\$|AU\s?\$|\$)\s*(\d{1,3}(?:,\d{3})+|\d{4,6})(?:\.\d{2})?(?![\d,])/gi
  const rows = [...text.matchAll(re)].filter((m) => !own || own.own.test(m[0]) || !foreignBefore(text.slice(Math.max(0, (m.index || 0) - 6), m.index || 0))).map((m) => {
    const idx = m.index || 0, amount = Number(m[1].replace(/,/g, ""))
    const before = text.slice(Math.max(0, idx - 180), idx), after = text.slice(idx + m[0].length, idx + m[0].length + 180)
    const context = clean(before + " " + m[0] + " " + after), near = clean(text.slice(Math.max(0, idx - 320), idx + m[0].length + 320))
    const token = clean(text.slice(Math.max(0, idx - 8), idx + m[0].length + 8))
    // audience from the amount's own sentence (a page often lists domestic and international fees side by side)
    const local = clean((before.split(/[.;!?]\s/).pop() || "") + " " + m[0] + " " + (after.split(/[.;!?]\s/)[0] || ""))
    // v0.5.5: a page that switches between a domestic and an international view says which view a block belongs to
    // ("This content is for domestic students", "Local Student Fee", "Switch to International Student"); the last such
    // marker before the amount decides its audience, ahead of words further away.
    const view = viewBefore(text.slice(Math.max(0, idx - 1500), idx))
    const domestic = view === "domestic" || (view !== "international" && /(domestic|csp|commonwealth supported|student contribution|hecs)/i.test(local))
    const international = view === "international" || (view !== "domestic" && (/(international|overseas)/i.test(local) || (!domestic && /(international|overseas)/i.test(context))))
    const indicative = /(indicative fee|indicative annual fee|typical first-year|first year enrolment|annual|per year|a year|yearly cost|per annum)/i.test(context)
    // v0.5.5: the wording that belongs to this amount starts after the previous amount ("Total Course Cost A$20,550
    // Tuition Fee A$18,000": "total" is about the first amount only)
    const pre120 = before.slice(-120), lastAmt = [...pre120.matchAll(/\$\s?\d[\d,]{2,}(?:\.\d{2})?/g)].pop()
    const ownPre = lastAmt ? pre120.slice((lastAmt.index || 0) + lastAmt[0].length) : pre120
    const after60 = after.slice(0, 60), nextAmt = after60.search(/\$\s?\d[\d,]{2,}/)
    const local2 = clean(ownPre + " " + m[0] + " " + (nextAmt >= 0 ? after60.slice(0, nextAmt) : after60))
    // v0.5.6: amounts that are not tuition at all: bursaries, scholarships, loan caps, health cover, salaries, deposits
    // and payment limits, from the amount's own wording just before or after it
    // the label before the amount, or one or two words straight after it ("AUD$5,000 Regional bursary")
    const label = clean(ownPre.slice(-80)), tail = (nextAmt >= 0 ? after60.slice(0, nextAmt) : after60)
    const notTuition = (!/(?<!non[- ])tuition/i.test(label.slice(-40)) && /(bursary|scholarship|worth up to|student loan|vsl\b|loan cap|health cover|oshc|salary|earnings?\b|deposit|accept payment of more than|refund|application fee|enrolment fee|enrollment fee|materials? fee|resource fee|uniform|ppe\b|non[- ]tuition|service fee|amenit|levy|insurance|accommodation|living cost|airport|homestay)[^$]{0,40}$/i.test(label))
      || /^[\s*)\]-]*(?:[A-Za-z]+\s){0,2}(bursary|scholarship|salary|health cover|oshc|deposit)\b/i.test(tail)
      || /not accept payment of more than\s*$/i.test(label)
    // UOW-style table "Session fee* Course fee*": the first amount of each row is one session, the second the course
    const sessionHdr = before.search(/session fee\*?\s+course fee\*?/i)
    const sessionCol = sessionHdr >= 0 ? ([...before.slice(sessionHdr).matchAll(/\$\s?\d[\d,]{2,}/g)].length % 2 === 0 ? "session" : "course") : null
    // a fee for part of a year ("Study Period 1: $11,484", "Trimester $12,844", "per unit") is not an annual fee
    const partial = sessionCol === "session" || /\b\d{1,3}\s*x\s*$/i.test(ownPre) || /(study period|trimester|semester|term|per unit|per subject|per credit|unit fee|per course unit)\s*\d?\s*:?\s*(fees?)?\s*:?\s*$/i.test(clean(ownPre)) || /^\s*(per|a|each)\s+(unit|subject|credit|trimester|semester|term|study period|session)\b/i.test(after60)
    const total = sessionCol === "course" || /(total (indicative |estimated |course |program(me)? )?(tuition )?fees?|total (indicative |estimated )?(course |program(me)? )+(tuition )?(fees?|costs?)|estimated total (course |program(me)? )?(fees?|costs?)|total cost|course total|entire (course|program)|full (course|program)|\(\s*20[2-3]\d\s+total\s*\)|fee to complete|full fee to complete)/i.test(local2)
    const annualLocal = !partial && /(per year|a year|per annum|annual|first[- ]year|for 1 (?:yr|year)|1 year full[- ]time|\(\s*20[2-3]\d\s+annual\s*\))/i.test(local2)
    const tuition = /(tuition|fee)/i.test(context)
    const explicitAud = own ? own.explicit.test(token) : /(?:AUD\s*|A\$|AU\s?\$)\s*[\d,]+/i.test(token)
    const cricosNear = /CRICOS(?:\s+Code)?/i.test(near)
    const year = (after.match(/\b(20[2-3]\d)\b/) || before.slice(-80).match(/\b(20[2-3]\d)\b/) || [])[1]
    const score = (international ? 5 : 0) + (cricosNear ? 4 : 0) + (explicitAud ? 4 : 0) + (indicative ? 3 : 0) + (tuition ? 1 : 0) + (/(?<!non[- ])tuition(?: fees?)?\s*:?\s*$/i.test(label) ? 1 : 0) - (domestic ? 8 : 0) - (total && !annualLocal ? 1 : 0) - (partial ? 3 : 0) // v0.5.5: an annual fee outranks a course total of equal standing
    return { amount, score, international, domestic, indicative, total, annualLocal, partial, notTuition, fee_year: year ? Number(year) : null, context: context.slice(0, 300) }
  }).filter((r) => r.amount >= 1000 && r.amount <= 500000 && !r.notTuition).sort((a, b) => b.score - a.score || b.amount - a.amount)
  if (!rows.length) return { value: null, safe: false, ambiguous: false, rejection_reason: "no_fee_candidate", candidates: [] as unknown[], ...(nz ? { currency } : {}) }
  const top = rows[0], same = rows.filter((r) => r.score === top.score && r.amount !== top.amount)
  const ambiguous = same.length > 0, safe = top.score >= 4 && !ambiguous && !top.domestic
  const basis = top.total && !top.annualLocal ? "total" : top.annualLocal && !top.total ? "annual" : null
  return { value: safe ? top.amount : null, safe, ambiguous, basis, ...(nz ? { currency } : {}),
    fee_year: top.fee_year, rejection_reason: safe ? null : ambiguous ? "multiple_equal_rank_fee_candidates" : top.domestic ? "domestic_csp_fee_candidate" : "low_confidence_international_fee_candidate",
    candidates: rows.slice(0, 3) }
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
// Month names must be capitalised ("May" the month, not "may" the verb); the lead-in words are matched in any case.
// Windows about money, visas, deadlines, holidays, exams or events are not intakes.
const NOT_INTAKE = /(living cost|visa|fee|payment|tuition|deadline|clos(?:e|es|ing)|census|orientation|exam|holiday|break|results?|graduation|open day|webinar|event|updated|published|as of|from \w+ 20\d\d,)/i
export function intakeEvidence(text: string) {
  const lead = /(?:next intake|intakes?|commenc\w*|semester|trimester|start date|starts?)/gi
  const out: string[] = []
  for (const m of text.matchAll(lead)) {
    const win = text.slice((m.index || 0) + m[0].length, (m.index || 0) + m[0].length + 100).split(/[.!?]/)[0]
    if (NOT_INTAKE.test(win) || !MONTHS.some((mon) => new RegExp(`\\b${mon}\\b`).test(win))) continue
    out.push(clean(text.slice(Math.max(0, (m.index || 0) - 40), (m.index || 0) + m[0].length + win.length)).slice(0, 200))
    if (out.length >= 3) break
  }
  return out
}
export function intakes(text: string) {
  const lead = /(?:next intake|intakes?|commenc\w*|semester|trimester|start date|starts?)/gi
  const found = new Set<string>()
  for (const m of text.matchAll(lead)) {
    const win = text.slice((m.index || 0) + m[0].length, (m.index || 0) + m[0].length + 100).split(/[.!?]/)[0]
    if (NOT_INTAKE.test(win)) continue
    for (const mon of MONTHS) if (new RegExp(`\\b${mon}\\b`).test(win)) found.add(mon)
  }
  return MONTHS.filter((m) => found.has(m))
}

// IELTS overall only when the page says "overall" next to the score, or prints the IELTS row of a score table
// (overall then four band scores). A score next to a single band ("7.0 in Writing") is never taken as overall.
const BAND = /(?:no (?:individual |other )?(?:band|sub-?score|section|component)s?(?: score)?(?: of)? (?:less than|lower than|below|under)|\b(?:each|every|all) (?:sub-?)?bands?(?: of| at least)?|minimum (?:of )?(?:\d(?:\.\d)? )?in (?:each|all)|not less than|no less than|(?:with )?(?:a )?minimum(?: score)? of)[^\d]{0,12}(\d(?:\.\d)?)/i
// "5.5 in each band" / "6.0 or above in all sub-bands": the band score written before the words
const BAND_PRE = /(\d(?:\.\d)?)\s*(?:or (?:above|higher|better)\s*)?(?:in|for|on) (?:each|every|all|any)(?: (?:of the )?(?:four )?)?(?:sub-?)?(?:bands?|sections?|components?|skills?|sub-?scores?)/i
export function english(text: string) {
  const x: Record<string, unknown> = {}
  const ok = (v: number) => v >= 4 && v <= 9
  const OTHER_TEST = /(TOEFL|PTE\b|Pearson|Cambridge|C1 Advanced|CAE\b|OET\b|Duolingo|Occupational English)/i
  for (const m of text.matchAll(/IELTS/gi)) {
    const at = m.index || 0
    // the IELTS section ends where another test starts, so another test's "overall" is never read as IELTS
    let win = text.slice(at, at + 220)
    const cut = win.slice(5).search(OTHER_TEST); if (cut >= 0) win = win.slice(0, cut + 5)
    // several different overall scores in one IELTS section (different entry paths or courses) -> unclear
    const overalls = new Set([...win.matchAll(/overall(?:\s+band)?(?:\s+score)?(?:\s+(?:of|minimum|min\.?|at least|is|required|requirement))*\s*[:\-–=]?\s*(\d(?:\.\d)?)(?!\d)/gi)].map((o) => o[1]).filter((v) => ok(+v)))
    if (overalls.size > 1) { x.ielts_unclear = true; break }
    // "a minimum overall band score of 6.5 on IELTS (Academic)": the score written just before the test name
    const pre = text.slice(Math.max(0, at - 70), at).match(/overall(?:\s+band)?(?:\s+score)?(?:\s+of)?\s*(\d(?:\.\d)?)\s*(?:on|in|for)?\s*(?:the\s+)?(?:academic\s+)?\(?\s*$/i)
    if (pre && ok(+pre[1])) { x.ielts_overall = +pre[1]; const b = win.match(BAND) || win.match(BAND_PRE); if (b && ok(+b[1]) && +b[1] <= +pre[1]) x.ielts_min_band = +b[1]; x.context = clean(text.slice(Math.max(0, at - 70), at + 220)).slice(0, 290); break }
    const table = win.match(/^IELTS[^\d]{0,40}?(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\b/i)
    // "overall 6.5" / "overall band score of 6.5" first (only these words between); then "6.5 (or better) overall".
    // Never a number reached across other words ("6.0 overall, no less than 5.5 in each band" is 6.0, not 5.5).
    const over = win.match(/overall(?:\s+band)?(?:\s+score)?(?:\s+(?:of|minimum|min\.?|at least|is|required|requirement))*\s*[:\-–=]?\s*(\d(?:\.\d)?)(?!\d)/i)
      || win.match(/(\d(?:\.\d)?)(?:\s*\(?or (?:better|higher|above)\)?)?\s+overall/i)
    if (table && ok(+table[1])) { x.ielts_overall = +table[1]; const bands = [2, 3, 4, 5].map((i) => +table[i]).filter(ok); if (bands.length === 4) x.ielts_min_band = Math.min(...bands) }
    else if (over && ok(+over[1])) { x.ielts_overall = +over[1]; const rest = win.slice((over.index || 0) + over[0].length); const b = rest.match(BAND) || rest.match(BAND_PRE); if (b && ok(+b[1]) && +b[1] <= +over[1]) x.ielts_min_band = +b[1] }
    else continue
    x.context = clean(text.slice(Math.max(0, at - 60), at + 220)).slice(0, 280)
    break
  }
  if (!("ielts_overall" in x) && /IELTS/i.test(text)) x.ielts_unclear = true
  // PTE/TOEFL: the number must be stated as overall, or follow the test name directly ("PTE Academic: 58")
  const p = text.match(/(?:PTE(?: Academic)?|Pearson Test of English(?: Academic)?)\s*(?:\(Academic\))?\s*[:\-–]?\s*(?:overall(?: score)?(?: of)?\s*[:\-–]?\s*)?(\d{2})\b/i)
    || text.match(/(?:PTE|Pearson)[^\d.]{0,40}overall(?: score)?(?: of)?[^\d]{0,10}(\d{2})\b/i)
  if (p && Number(p[1]) >= 30 && Number(p[1]) <= 90) { x.pte_overall = Number(p[1]); x.pte_context = clean(text.slice(Math.max(0, (p.index || 0) - 40), (p.index || 0) + p[0].length + 60)).slice(0, 200) }
  const t = text.match(/TOEFL(?: iBT)?\s*(?:\(0-120\))?\s*[:\-–]?\s*(?:overall(?: score)?(?: of)?\s*[:\-–]?\s*)?(\d{2,3})\b/i)
    || text.match(/TOEFL[^\d.]{0,40}overall(?: score)?(?: of)?[^\d]{0,10}(\d{2,3})\b/i)
  if (t && Number(t[1]) >= 40 && Number(t[1]) <= 120) { x.toefl_overall = Number(t[1]); x.toefl_context = clean(text.slice(Math.max(0, (t.index || 0) - 40), (t.index || 0) + t[0].length + 60)).slice(0, 200) }
  return x
}

// Map filter: pages that can be course pages (by address or title); obvious non-course pages dropped.
const KEEP = /(course|program|degree|bachelor|master|diploma|certificate|graduate|doctor|associate|qualification|undergraduate|postgraduate|elicos|english|foundation|cricos|\bcert-?i|\bmba\b|\bvet\b)/i
const DROP = /(\/news\/|\/blog|\/events?\/|\/staff|\/people\/|\/profile|\/research\/|wp-content|\/tag\/|\/category\/|\/media\/|login|\/feed|\/(inherent|entry|admission|english)-requirements\/|\/scholarships?\/|\/how-to-apply|\/applying|\.(pdf|jpe?g|png|gif|docx?|xlsx?|zip|mp4)(\?|$))/i
export function keepUrl(u: { url: string; title?: string }, host: string) {
  try {
    const x = new URL(u.url)
    const base = (h: string) => h.replace(/^www\./, "").split(".").slice(-3).join(".")
    if (base(x.hostname) !== base(host) && !x.hostname.endsWith("." + base(host))) return false
    const s = x.pathname + " " + (u.title || "")
    return KEEP.test(s) && !DROP.test(x.pathname)
  } catch { return false }
}

// robots.txt: rules for User-agent * (and our agent), longest match wins between Allow and Disallow.
export function robotsAllows(robots: string, path: string) {
  const groups: { agents: string[]; rules: { allow: boolean; p: string }[] }[] = []
  let cur: { agents: string[]; rules: { allow: boolean; p: string }[] } | null = null
  for (const raw of robots.split(/\r?\n/)) {
    const line = raw.replace(/#.*/, "").trim(); if (!line) continue
    const [k, ...rest] = line.split(":"); const v = rest.join(":").trim(); const key = k.trim().toLowerCase()
    if (key === "user-agent") { if (!cur || cur.rules.length) { cur = { agents: [], rules: [] }; groups.push(cur) } cur.agents.push(v.toLowerCase()) }
    else if (cur && (key === "allow" || key === "disallow")) cur.rules.push({ allow: key === "allow", p: v })
  }
  const g = groups.find((x) => x.agents.some((a) => a.includes("coursefinder"))) || groups.find((x) => x.agents.includes("*"))
  if (!g) return true
  let best: { allow: boolean; len: number } | null = null
  for (const r of g.rules) {
    if (!r.p) continue
    const re = new RegExp("^" + r.p.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\\\$$/, "$"))
    if (re.test(path) && (!best || r.p.length > best.len || (r.p.length === best.len && r.allow))) best = { allow: r.allow, len: r.p.length }
  }
  return best ? best.allow : true
}

// Decision 220: a Canadian provider's own site is accepted when its home page prints the provider's IRCC DLI number, or
// names the provider in the page title or main heading (accents, "The", "&" and punctuation ignored). Names of three
// letters or fewer, or a single word, are never matched by name alone.
const siteNorm = (s: string) => clean(s).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/&/g, " and ").replace(/[’']/g, "").replace(/[^a-z0-9]+/g, " ").replace(/\bthe\b/g, " ").replace(/\s+/g, " ").trim()
export function siteNameMatch(html: string, text: string, name: string, dli: string, host = ""): "dli_number" | "name_on_home_page" | "name_in_page_and_domain" | null {
  const code = clean(dli).toUpperCase()
  if (/^O\d{9,13}$/.test(code) && new RegExp(`\\b${code}\\b`).test(text.toUpperCase())) return "dli_number"
  const n = siteNorm(name)
  if (n.length <= 3 || n.split(" ").length < 2) return null
  for (const h of [titleOf(html), h1Of(html)]) { const t = siteNorm(h); if (t && (" " + t + " ").includes(" " + n + " ")) return "name_on_home_page" }
  // Decision 235 (Platform Admin, 22:50): many universities use a short name in the page title (BCIT, UFV). The full
  // name anywhere on the home page (often the footer or copyright line) is enough when the address itself fits the
  // name: its first label is the name's initials (bcit.ca, ufv.ca, nic.bc.ca, ecuad.ca) or holds a distinctive word of
  // the name (royalroads.ca, macewan.ca, kingsu.ca).
  if (host && (" " + siteNorm(text) + " ").includes(" " + n + " ") && domainFitsName(host, n)) return "name_in_page_and_domain"
  return null
}
const GENERIC = new Set(["university", "college", "institute", "technology", "school", "polytechnic", "community", "art", "arts", "design", "of", "and", "the", "at", "for", "in"])
export function domainFitsName(host: string, normName: string) {
  const label = host.toLowerCase().replace(/^www\./, "").split(".")[0].replace(/[^a-z0-9]/g, "")
  if (label.length < 3) return false
  const words = normName.split(" ").filter(Boolean)
  const sig = words.filter((w) => !["of", "and", "the", "at", "for", "in"].includes(w))
  const initials = sig.map((w) => w[0]).join(""), allInitials = words.map((w) => w[0]).join("")
  if (label === initials || label === allInitials || label === initials + "u") return true
  return words.some((w) => w.length >= 4 && !GENERIC.has(w) && label.includes(w))
}
