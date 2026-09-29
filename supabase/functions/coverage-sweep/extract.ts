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

// Identity: the CRICOS course code is printed on the page, or the exact course title is the page heading or the
// start of the page title. Anything else is a mismatch and nothing from the page is used.
export function identity(html: string, text: string, courseTitle: string, courseCode: string, codeOnly = false) {
  const code = clean(courseCode).toUpperCase()
  if (code.length >= 6 && new RegExp(`\\b${code}\\b`).test(text.toUpperCase())) return "cricos_code"
  if (codeOnly) return null
  const t = norm(courseTitle), h1 = norm(h1Of(html)), title = norm(titleOf(html))
  if (t && (h1 === t || title === t || title.startsWith(t + " ") || h1.startsWith(t + " international"))) return "exact_title"
  return null
}

export function fee(text: string) {
  const rows = [...text.matchAll(/(?:AUD\s*\$?|A\$|AU\s?\$|\$)\s*(\d{1,3}(?:,\d{3})+|\d{4,6})(?:\.\d{2})?(?![\d,])/gi)].map((m) => {
    const idx = m.index || 0, amount = Number(m[1].replace(/,/g, ""))
    const before = text.slice(Math.max(0, idx - 180), idx), after = text.slice(idx + m[0].length, idx + m[0].length + 180)
    const context = clean(before + " " + m[0] + " " + after), near = clean(text.slice(Math.max(0, idx - 320), idx + m[0].length + 320))
    const token = clean(text.slice(Math.max(0, idx - 8), idx + m[0].length + 8))
    // audience from the amount's own sentence (a page often lists domestic and international fees side by side)
    const local = clean((before.split(/[.;!?]\s/).pop() || "") + " " + m[0] + " " + (after.split(/[.;!?]\s/)[0] || ""))
    const domestic = /(domestic|csp|commonwealth supported|student contribution|hecs)/i.test(local)
    const international = /(international|overseas)/i.test(local) || (!domestic && /(international|overseas)/i.test(context))
    const indicative = /(indicative fee|indicative annual fee|typical first-year|first year enrolment|annual|per year|a year|yearly cost|per annum)/i.test(context)
    const local2 = clean(before.slice(-120) + " " + m[0] + " " + after.slice(0, 60))
    const total = /(total (indicative |estimated |course |program(me)? )?(tuition )?fees?|total cost|entire (course|program)|full (course|program)|\(\s*20[2-3]\d\s+total\s*\)|fee to complete|full fee to complete)/i.test(local2)
    const annualLocal = /(per year|a year|per annum|annual|first[- ]year|\(\s*20[2-3]\d\s+annual\s*\))/i.test(local2)
    const tuition = /(tuition|fee)/i.test(context)
    const explicitAud = /(?:AUD\s*|A\$|AU\s?\$)\s*[\d,]+/i.test(token)
    const cricosNear = /CRICOS(?:\s+Code)?/i.test(near)
    const year = (after.match(/\b(20[2-3]\d)\b/) || before.slice(-80).match(/\b(20[2-3]\d)\b/) || [])[1]
    const score = (international ? 5 : 0) + (cricosNear ? 4 : 0) + (explicitAud ? 4 : 0) + (indicative ? 3 : 0) + (tuition ? 1 : 0) - (domestic ? 8 : 0)
    return { amount, score, international, domestic, indicative, total, annualLocal, fee_year: year ? Number(year) : null, context: context.slice(0, 300) }
  }).filter((r) => r.amount >= 1000 && r.amount <= 500000).sort((a, b) => b.score - a.score || b.amount - a.amount)
  if (!rows.length) return { value: null, safe: false, ambiguous: false, rejection_reason: "no_fee_candidate", candidates: [] as unknown[] }
  const top = rows[0], same = rows.filter((r) => r.score === top.score && r.amount !== top.amount)
  const ambiguous = same.length > 0, safe = top.score >= 4 && !ambiguous && !top.domestic
  const basis = top.total && !top.annualLocal ? "total" : top.annualLocal && !top.total ? "annual" : null
  return { value: safe ? top.amount : null, safe, ambiguous, basis,
    fee_year: top.fee_year, rejection_reason: safe ? null : ambiguous ? "multiple_equal_rank_fee_candidates" : top.domestic ? "domestic_csp_fee_candidate" : "low_confidence_international_fee_candidate",
    candidates: rows.slice(0, 3) }
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
// Month names must be capitalised ("May" the month, not "may" the verb); the lead-in words are matched in any case.
export function intakes(text: string) {
  const lead = /(?:next intake|intakes?|commenc\w*|semester|trimester|start date|starts?)/gi
  const found = new Set<string>()
  for (const m of text.matchAll(lead)) {
    const win = text.slice((m.index || 0) + m[0].length, (m.index || 0) + m[0].length + 100).split(/[.!?]/)[0]
    for (const mon of MONTHS) if (new RegExp(`\\b${mon}\\b`).test(win)) found.add(mon)
  }
  return MONTHS.filter((m) => found.has(m))
}

// IELTS overall only when the page says "overall" next to the score, or prints the IELTS row of a score table
// (overall then four band scores). A score next to a single band ("7.0 in Writing") is never taken as overall.
const BAND = /(?:no (?:individual |other )?(?:band|sub-?score|section|component)s?(?: score)? (?:less than|lower than|below|under)|\b(?:each|every|all) (?:sub-?)?bands?(?: of| at least)?|minimum (?:of )?(?:\d(?:\.\d)? )?in (?:each|all)|not less than)[^\d]{0,12}(\d(?:\.\d)?)/i
export function english(text: string) {
  const x: Record<string, unknown> = {}
  const ok = (v: number) => v >= 4 && v <= 9
  for (const m of text.matchAll(/IELTS/gi)) {
    const at = m.index || 0, win = text.slice(at, at + 220)
    const table = win.match(/^IELTS[^\d]{0,40}?(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\s+(\d(?:\.\d)?)\b/i)
    const over = win.match(/overall(?: band)?(?: score)?(?: of)?[^\d]{0,20}(\d(?:\.\d)?)/i) || win.match(/(\d(?:\.\d)?)(?: or (?:better|higher|above))?\s+overall/i)
    if (table && ok(+table[1])) { x.ielts_overall = +table[1]; const bands = [2, 3, 4, 5].map((i) => +table[i]).filter(ok); if (bands.length === 4) x.ielts_min_band = Math.min(...bands) }
    else if (over && ok(+over[1])) { x.ielts_overall = +over[1]; const b = win.slice((over.index || 0) + over[0].length).match(BAND); if (b && ok(+b[1])) x.ielts_min_band = +b[1] }
    else continue
    x.context = clean(text.slice(Math.max(0, at - 60), at + 220)).slice(0, 280)
    break
  }
  if (!("ielts_overall" in x) && /IELTS/i.test(text)) x.ielts_unclear = true
  // PTE/TOEFL: the number must be stated as overall, or follow the test name directly ("PTE Academic: 58")
  const p = text.match(/(?:PTE(?: Academic)?|Pearson Test of English(?: Academic)?)\s*(?:\(Academic\))?\s*[:\-–]?\s*(?:overall(?: score)?(?: of)?\s*[:\-–]?\s*)?(\d{2})\b/i)
    || text.match(/(?:PTE|Pearson)[^\d.]{0,40}overall(?: score)?(?: of)?[^\d]{0,10}(\d{2})\b/i)
  if (p && Number(p[1]) >= 30 && Number(p[1]) <= 90) x.pte_overall = Number(p[1])
  const t = text.match(/TOEFL(?: iBT)?\s*(?:\(0-120\))?\s*[:\-–]?\s*(?:overall(?: score)?(?: of)?\s*[:\-–]?\s*)?(\d{2,3})\b/i)
    || text.match(/TOEFL[^\d.]{0,40}overall(?: score)?(?: of)?[^\d]{0,10}(\d{2,3})\b/i)
  if (t && Number(t[1]) >= 40 && Number(t[1]) <= 120) x.toefl_overall = Number(t[1])
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
