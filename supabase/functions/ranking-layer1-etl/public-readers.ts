// CF-247 s966 (Platform Admin 22 Nov 2026 09:22 AEDT, IR-005 / RM1J): Layer 1 readers for the attributed public university rankings of
// Times Higher Education (THE) and QS. "We can attribute and use both ... directly. Do NOT gate them behind a manual publisher file upload
// or a terms = restricted hold."
// Pure functions: no network, no AI, no browser. ranking-layer1-etl fetches the publisher's own JSON with a plain HTTP GET and these
// turn it into ranking observations (exact ranks, ties, bands, reporters, overall and pillar scores, edition year, attribution).
// Guarded by tests/uat/cf-247-s966-public-ranking-readers-contract.spec.mjs.

export const PUBLIC_READER_VERSION = "public-ranking-readers-v1.1.0"
// v1.1.0 (CF-247 s971, Platform Admin 22 Nov 2026 14:22): ARWU (ShanghaiRanking) from its public ranking API, the third institutional ranking.
export const USER_AGENT = "StudySearch-Layer1-ranking-reader/1.0 (Supabase Edge Function; plain GET, robots.txt honoured)"

export const PUBLIC_SOURCES = {
  the_wur: {
    publisher: "Times Higher Education",
    rankingName: "Times Higher Education World University Rankings",
    origin: "https://www.timeshighereducation.com",
    jsonUrl: (year: number) => `https://www.timeshighereducation.com/json/ranking_tables/world_university_rankings/${year}`,
    pageUrl: (year: number) => `https://www.timeshighereducation.com/world-university-rankings/${year}/world-ranking`,
    revision: "the_public_json_v1",
  },
  qs_wur: {
    publisher: "QS World University Rankings",
    rankingName: "QS World University Rankings",
    origin: "https://www.topuniversities.com",
    pageUrl: (year: number) => `https://www.topuniversities.com/world-university-rankings/${year}`,
    revision: "qs_public_json_v1",
  },
  arwu: {
    publisher: "ShanghaiRanking",
    rankingName: "Academic Ranking of World Universities (ARWU)",
    origin: "https://www.shanghairanking.com",
    jsonUrl: (year: number) => `https://www.shanghairanking.com/api/pub/v1/arwu/rank?version=${year}`,
    pageUrl: (year: number) => `https://www.shanghairanking.com/rankings/arwu/${year}`,
    revision: "arwu_public_json_v1",
  },
} as const

export type PublicSystem = keyof typeof PUBLIC_SOURCES

export function attribution(system: PublicSystem, year: number): string {
  const s = PUBLIC_SOURCES[system]
  const site = new URL(s.origin).hostname.replace(/^www\./, "")
  if (system === "arwu") return `${s.rankingName} ${year}, ShanghaiRanking. Source: ShanghaiRanking (${site}, ${s.pageUrl(year)}). Attributed public ranking, read by the StudySearch Layer 1 reader and published with this attribution (Platform Admin decision 22 Nov 2026).`
  return `${s.rankingName} ${year}. Source: ${s.publisher} (${site}). Attributed public ranking, read by the StudySearch Layer 1 reader and published with this attribution (Platform Admin decision 22 Nov 2026).`
}

const clean = (v: unknown) => String(v ?? "").replace(/^﻿/, "").trim()
const key = (v: unknown) => clean(v).toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()

export type RankParts = { rank_display: string | null; rank_exact: number | null; rank_low: number | null; rank_high: number | null; is_tied: boolean; rank_status: string }

// "1", "=34", "34=", "601–650", "1501+", "Reporter", "n/a". Anything else is "unknown" and stops the run (the parser never guesses).
export function parsePublicRank(raw: unknown): RankParts {
  const display = clean(raw).replace(/^#\s*/, "")
  const norm = display.replace(/[–—]/g, "-").replace(/,/g, "").replace(/\s+/g, "")
  const none = { rank_display: display || null, rank_exact: null, rank_low: null, rank_high: null, is_tied: false }
  if (!norm) return { ...none, rank_display: null, rank_status: "unranked" }
  if (/^reporter$/i.test(norm)) return { ...none, rank_status: "reporter" }
  if (/^(n\/?a|-|notranked|unranked)$/i.test(norm)) return { ...none, rank_status: "unranked" }
  const tied = /^=/.test(norm) || /=$/.test(norm)
  const x = norm.replace(/^=/, "").replace(/=$/, "")
  let m = x.match(/^(\d+)-(\d+)$/)
  if (m && +m[1] > 0 && +m[1] <= +m[2]) return { rank_display: display, rank_exact: null, rank_low: +m[1], rank_high: +m[2], is_tied: tied, rank_status: "ranked_band" }
  m = x.match(/^(\d+)\+$/)
  if (m && +m[1] > 0) return { rank_display: display, rank_exact: null, rank_low: +m[1], rank_high: null, is_tied: tied, rank_status: "ranked_band" }
  m = x.match(/^(\d+)$/)
  if (m && +m[1] > 0) return { rank_display: display, rank_exact: +m[1], rank_low: null, rank_high: null, is_tied: tied, rank_status: "ranked_exact" }
  return { ...none, is_tied: tied, rank_status: "unknown" }
}

// "97.9", "43.4–44.4" (a banded score), "n/a", "", "—".
export function scoreParts(raw: unknown): { display: string | null; numeric: number | null; low: number | null; high: number | null } {
  const display = clean(raw)
  const norm = display.replace(/[–—]/g, "-").replace(/,/g, "").replace(/\s+/g, "")
  if (!norm || /^(n\/?a|-|null)$/i.test(norm)) return { display: null, numeric: null, low: null, high: null }
  const range = norm.match(/^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)$/)
  if (range) return { display, numeric: null, low: Number(range[1]), high: Number(range[2]) }
  const n = Number(norm)
  return Number.isFinite(n) ? { display, numeric: n, low: null, high: null } : { display, numeric: null, low: null, high: null }
}

function indicator(label: string, value: unknown, rank: unknown, year: number, group: string | null) {
  const s = scoreParts(value), r = parsePublicRank(rank)
  return { label, value_display: s.display, value_numeric: s.numeric, unit: "score", methodology_version: String(year), group, ...(clean(rank) ? r : {}) }
}

// THE pillars keep the codes of the earlier THE editions (overall, teaching, research, citations, industry_income, international_outlook);
// the label is the publisher's own for the edition (from the JSON "pillars" list), else the 2027 methodology name.
const THE_PILLARS: Array<[code: string, field: string, fallback: string]> = [
  ["teaching", "scores_teaching", "Teaching"],
  ["research", "scores_research", "Research Environment"],
  ["citations", "scores_citations", "Research Quality"],
  ["industry_income", "scores_industry_income", "Industry"],
  ["international_outlook", "scores_international_outlook", "International Outlook"],
]

function thePillarLabels(pillars: unknown): Map<string, string> {
  const out = new Map<string, string>()
  const list = Array.isArray(pillars) ? pillars : pillars && typeof pillars === "object" ? Object.values(pillars as Record<string, unknown>) : []
  for (const p of list as any[]) {
    const machine = key(p?.machine ?? p?.machine_name ?? p?.name).replace(/ /g, "_").replace(/^scores_/, "")
    if (machine && clean(p?.label)) out.set(machine, clean(p.label))
  }
  return out
}

const THE_PAYLOAD_DROP = new Set(["apply_link", "cta_button", "logo_url", "subjects_offered"])

export function theRowsFromPublicJson(payload: any, year: number) {
  const data = payload?.data
  if (!Array.isArray(data) || data.length === 0) throw new Error("THE ranking JSON has no data rows")
  const labels = thePillarLabels(payload?.pillars)
  const rows: any[] = []
  for (const r of data) {
    const name = clean(r?.name)
    if (!name) continue
    const rank = parsePublicRank(r.rank), overall = scoreParts(r.scores_overall)
    // scores_overall_rank is the table's sort order (rank_order), not a rank, so the overall indicator carries the score only.
    const indicators: Record<string, unknown> = { overall: indicator("Overall", r.scores_overall, undefined, year, "Overall") }
    for (const [code, field, fallback] of THE_PILLARS) {
      if (r[field] === undefined && r[`${field}_rank`] === undefined) continue
      const label = labels.get(field.replace(/^scores_/, "")) || fallback
      indicators[code] = indicator(label, r[field], r[`${field}_rank`], year, label)
    }
    const payloadRow: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(r)) if (!THE_PAYLOAD_DROP.has(k)) payloadRow[k] = v
    rows.push({
      publisher_institution_id: clean(r.nid ?? r.iid) || null, institution_name: name, profile_url: clean(r.url) || null,
      country_text: clean(r.location) || null, location_text: clean(r.location) || null,
      ...rank, overall_score: overall.numeric, overall_score_display: overall.display, overall_score_low: overall.low, overall_score_high: overall.high,
      source_row_ordinal: rows.length + 1, indicators, source_row_payload: { ...payloadRow, edition_year: year, reader: PUBLIC_READER_VERSION },
    })
  }
  return finish("THE", rows)
}

// QS indicator codes are the codes of the QS editions already held (ranking-qs-official-etl), matched on the publisher's indicator name.
const QS_CODES: Array<[code: string, names: string[]]> = [
  ["academic_reputation", ["academic reputation"]],
  ["employer_reputation", ["employer reputation"]],
  ["faculty_student_ratio", ["faculty student ratio", "faculty student"]],
  ["citations_per_faculty", ["citations per faculty"]],
  ["international_faculty_ratio", ["international faculty ratio", "international faculty"]],
  ["international_student_ratio", ["international student ratio", "international students"]],
  ["international_student_diversity", ["international student diversity"]],
  ["international_research_network", ["international research network"]],
  ["employment_outcomes", ["employment outcomes"]],
  ["sustainability", ["sustainability", "sustainability score"]],
]

export function qsIndicatorCode(name: unknown): string {
  const k = key(name)
  for (const [code, names] of QS_CODES) if (names.includes(k)) return code
  return k.replace(/ /g, "_")
}

const QS_PAYLOAD_KEEP = ["nid", "core_id", "score_nid", "title", "path", "region", "country", "city", "rank", "rank_display", "overall_score", "scores", "dagger", "redact"]

export function qsRowsFromRestPages(pages: any[], year: number) {
  const first = pages.find((p) => p && typeof p === "object")
  const total = Number(first?.total_record)
  const seen = new Set<string>()
  const nodes: any[] = []
  for (const p of pages) for (const n of Array.isArray(p?.score_nodes) ? p.score_nodes : []) {
    const id = clean(n?.nid) || `${key(n?.title)}|${key(n?.country)}`
    if (seen.has(id)) continue
    seen.add(id)
    nodes.push(n)
  }
  if (!nodes.length) throw new Error("QS ranking endpoint returned no institutions")
  if (Number.isFinite(total) && total > 0 && nodes.length !== total) throw new Error(`QS ranking endpoint lists ${total} institutions but returned ${nodes.length}`)
  const rows: any[] = []
  for (const n of nodes) {
    const name = clean(n?.title)
    if (!name) continue
    const rank = parsePublicRank(n.rank_display ?? n.rank), overall = scoreParts(n.overall_score)
    const indicators: Record<string, unknown> = {}
    for (const [group, list] of Object.entries(n.scores && typeof n.scores === "object" ? n.scores : {})) {
      for (const it of Array.isArray(list) ? list : []) {
        const label = clean((it as any)?.indicator_name)
        if (!label) continue
        indicators[qsIndicatorCode(label)] = indicator(label, (it as any)?.score, (it as any)?.rank, year, clean(group) || null)
      }
    }
    const payloadRow: Record<string, unknown> = {}
    for (const k of QS_PAYLOAD_KEEP) if (n[k] !== undefined) payloadRow[k] = n[k]
    rows.push({
      publisher_institution_id: clean(n.nid) || null, institution_name: name, profile_url: clean(n.path) || null,
      country_text: clean(n.country) || null, location_text: [clean(n.city), clean(n.country)].filter(Boolean).join(", ") || null,
      ...rank, overall_score: overall.numeric, overall_score_display: overall.display, overall_score_low: overall.low, overall_score_high: overall.high,
      source_row_ordinal: rows.length + 1, indicators, source_row_payload: { ...payloadRow, edition_year: year, reader: PUBLIC_READER_VERSION },
    })
  }
  // A rank the publisher shows for two institutions is a tie even when it is printed without "=".
  const counts = new Map<number, number>()
  for (const r of rows) if (r.rank_exact != null) counts.set(r.rank_exact, (counts.get(r.rank_exact) || 0) + 1)
  for (const r of rows) if (r.rank_exact != null && (counts.get(r.rank_exact) || 0) > 1 && !r.is_tied) { r.is_tied = true; r.rank_display = `=${r.rank_exact}` }
  return finish("QS", rows)
}

// ARWU indicator codes by the publisher's indicator name (its numeric codes change every edition).
const ARWU_CODES: Record<string, string> = { "alumni": "alumni", "award": "award", "hici": "hici", "n s": "ns", "pub": "pub", "pcp": "pcp" }

export function arwuRowsFromPublicJson(payload: any, year: number) {
  if (Number(payload?.code) !== 200) throw new Error(`ARWU ranking API answered code ${payload?.code ?? "none"}`)
  const data = payload?.data?.rankings
  if (!Array.isArray(data) || data.length === 0) throw new Error("ARWU ranking JSON has no rankings")
  const names = new Map<string, string>()
  for (const ind of Array.isArray(payload?.data?.indicators) ? payload.data.indicators : []) {
    if (ind?.yr !== undefined && Number(ind.yr) !== year) throw new Error(`ARWU indicators are for ${ind.yr}, not ${year}`)
    if (clean(ind?.code) && clean(ind?.nameEn)) names.set(clean(ind.code), clean(ind.nameEn))
  }
  const rows: any[] = []
  for (const r of data) {
    const name = clean(r?.univNameEn)
    if (!name) continue
    const rank = parsePublicRank(r.ranking), overall = scoreParts(r.score)
    const indicators: Record<string, unknown> = {}
    for (const [code, value] of Object.entries(r.indData && typeof r.indData === "object" ? r.indData : {})) {
      const label = names.get(clean(code)) || clean(code)
      indicators[ARWU_CODES[key(label)] || key(label).replace(/ /g, "_") || `indicator_${code}`] = indicator(label, value, undefined, year, "ARWU indicators")
    }
    if (clean(r.regionRanking)) indicators.national_rank = { label: "National rank", value_display: clean(r.regionRanking), value_numeric: null, unit: "rank", methodology_version: String(year), group: "National", ...parsePublicRank(r.regionRanking) }
    rows.push({
      publisher_institution_id: clean(r.univUp) || null, institution_name: name, profile_url: clean(r.univUp) ? `/institution/${clean(r.univUp)}` : null,
      country_text: clean(r.region) || null, location_text: clean(r.region) || null,
      ...rank, overall_score: overall.numeric, overall_score_display: overall.display, overall_score_low: overall.low, overall_score_high: overall.high,
      source_row_ordinal: rows.length + 1, indicators, source_row_payload: { ranking: r.ranking, univNameEn: r.univNameEn, univUp: r.univUp, region: r.region, regionRanking: r.regionRanking, score: r.score, indData: r.indData, edition_year: year, reader: PUBLIC_READER_VERSION },
    })
  }
  // ARWU prints a shared rank as the same number for each institution, without "=".
  const counts = new Map<number, number>()
  for (const r of rows) if (r.rank_exact != null) counts.set(r.rank_exact, (counts.get(r.rank_exact) || 0) + 1)
  for (const r of rows) if (r.rank_exact != null && (counts.get(r.rank_exact) || 0) > 1 && !r.is_tied) { r.is_tied = true; r.rank_display = `=${r.rank_exact}` }
  return finish("ARWU", rows)
}

function finish(label: string, rows: any[]) {
  const unknown = rows.filter((r) => r.rank_status === "unknown")
  if (unknown.length) throw new Error(`${label} ranking rows with a rank the reader does not recognise: ${unknown.slice(0, 5).map((r) => `${r.institution_name} (${r.rank_display})`).join("; ")}${unknown.length > 5 ? ` and ${unknown.length - 5} more` : ""}`)
  const stats = {
    rows: rows.length,
    exact: rows.filter((r) => r.rank_status === "ranked_exact").length,
    tied: rows.filter((r) => r.is_tied).length,
    bands: rows.filter((r) => r.rank_status === "ranked_band").length,
    reporters: rows.filter((r) => r.rank_status === "reporter").length,
    unranked: rows.filter((r) => r.rank_status === "unranked").length,
    indicatorCells: rows.reduce((n, r) => n + Object.keys(r.indicators || {}).length, 0),
  }
  return { rows, stats }
}

// robots.txt: the rules of the "User-agent: *" group (the readers do not claim a named agent).
export function robotsRules(text: string): { disallow: string[]; allow: string[]; crawlDelaySeconds: number | null } {
  const out = { disallow: [] as string[], allow: [] as string[], crawlDelaySeconds: null as number | null }
  let inStar = false, sawRule = false
  for (const raw of String(text || "").split(/\r?\n/)) {
    const line = raw.replace(/#.*$/, "").trim()
    if (!line) continue
    const m = line.match(/^([A-Za-z-]+)\s*:\s*(.*)$/)
    if (!m) continue
    const field = m[1].toLowerCase(), value = m[2].trim()
    if (field === "user-agent") { if (sawRule) { inStar = false; sawRule = false } inStar = inStar || value === "*"; continue }
    sawRule = true
    if (!inStar) continue
    if (field === "disallow" && value) out.disallow.push(value)
    else if (field === "allow" && value) out.allow.push(value)
    else if (field === "crawl-delay" && Number.isFinite(Number(value))) out.crawlDelaySeconds = Number(value)
  }
  return out
}

function ruleMatches(rule: string, path: string): boolean {
  const anchored = rule.endsWith("$")
  const body = (anchored ? rule.slice(0, -1) : rule).split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*")
  return new RegExp(`^${body}${anchored ? "$" : ""}`).test(path)
}

// Longest matching rule wins; Allow wins a tie (RFC 9309).
export function robotsAllows(text: string, url: string): boolean {
  const u = new URL(url), path = u.pathname + u.search
  const r = robotsRules(text)
  let best = "", allowed = true
  for (const d of r.disallow) if (ruleMatches(d, path) && d.length > best.length) { best = d; allowed = false }
  for (const a of r.allow) if (ruleMatches(a, path) && a.length >= best.length) { best = a; allowed = true }
  return allowed
}

// A Cloudflare (or similar) challenge page instead of the JSON: the reader stops and reports it, and never tries to get past it.
export function isChallenge(status: number, contentType: string | null, body: string): boolean {
  if (status === 403 || status === 503 || status === 429) return true
  const head = String(body || "").slice(0, 2000)
  if (/<title>\s*Just a moment|challenges\.cloudflare\.com|cf-chl-|Attention Required/i.test(head)) return true
  return !/json/i.test(String(contentType || "")) && !/^\s*[\[{]/.test(head)
}
