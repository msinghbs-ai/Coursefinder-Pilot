// CF-247 RM1I / RM1C / RM1H page facts (S2-Build, Platform Admin 18 Nov 2026 14:23 and 15:32): one figure or rule read from an official
// page with a deterministic pattern, never typed in and never guessed by an AI. The page is reduced to its visible text (scripts, styles and
// tags removed, entities decoded, white space collapsed); each fact's pattern is applied to that text, and the fact keeps the matched value
// and a verbatim quote, the sentence around the match, that can be found again in the same text. A fact whose pattern finds nothing is
// reported as not found and writes nothing.

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ndash: '–', mdash: '—', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“', hellip: '…', dollar: '$' }

export function htmlToText(html) {
  let s = String(html ?? '')
  s = s.replace(/<!--[\s\S]*?-->/g, ' ')
  // 18 Nov 2026 (first live run): a self-closing <svg/>, <script/> or <template/> made the paired removal run on to the next closing tag far
  // down the page and swallow the content. Self-closing tags go first; only script and style (whose closing tag HTML requires) and the head
  // are removed with their content; every other tag is stripped and its text kept.
  s = s.replace(/<(script|style|noscript|template|svg)\b[^>]*\/>/gi, ' ')
  s = s.replace(/<head\b[^>]*>[\s\S]*?<\/head\s*>/i, ' ')
  s = s.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, ' ')
  s = s.replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, ' ')
  s = s.replace(/<(br|\/p|\/div|\/li|\/h[1-6]|\/tr|\/td|\/th|\/section|\/article)\b[^>]*>/gi, ' . ')
  s = s.replace(/<[^>]+>/g, ' ')
  s = s.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
  s = s.replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
  s = s.replace(/&([a-z]+);/gi, (m, n) => ENTITIES[n.toLowerCase()] ?? m)
  s = s.replace(/ /g, ' ')
  s = s.replace(/\s+/g, ' ')
  s = s.replace(/(\s\.)+/g, ' .')
  return s.trim()
}

// the sentence around a match: back to the previous full stop (or 200 characters), on to the next one (or 300 characters)
export function quoteAround(text, start, end) {
  const back = Math.max(0, start - 200) // fixed: the longest lead-in kept in a quote
  let s = text.lastIndexOf('. ', start)
  s = s >= back ? s + 2 : back
  const fwd = Math.min(text.length, end + 300) // fixed: the longest tail kept in a quote
  let e = text.indexOf('. ', end)
  e = e >= 0 && e < fwd ? e + 1 : fwd
  return text.slice(s, e).replace(/^[\s.]+/, '').trim()
}

export function parseNumber(raw) {
  const t = String(raw ?? '').replace(/[^\d.]/g, '')
  if (!t) return null
  const n = Number(t)
  return Number.isFinite(n) ? n : null
}

// pattern: a regular expression source; group 1 is the value. kind: amount, number or text.
export function extractFact(text, spec) {
  let re
  try { re = new RegExp(spec.pattern, spec.flags || 'i') } catch (e) { return { found: false, reason: `bad pattern: ${e.message}` } }
  const m = re.exec(text)
  if (!m) return { found: false, reason: 'pattern not found on the page' }
  const raw = (m[1] ?? m[0]).trim()
  const start = m.index, end = m.index + m[0].length
  const quote = quoteAround(text, start, end)
  if (!quote.includes(m[0].trim())) return { found: false, reason: 'quote does not hold the match' }
  const value = spec.kind === 'text' ? raw : parseNumber(raw)
  if (spec.kind !== 'text' && value == null) return { found: false, reason: `no number in "${raw}"` }
  if (spec.kind !== 'text' && spec.min != null && value < Number(spec.min)) return { found: false, reason: `${value} is below the plausible minimum ${spec.min}` }
  if (spec.kind !== 'text' && spec.max != null && value > Number(spec.max)) return { found: false, reason: `${value} is above the plausible maximum ${spec.max}` }
  return { found: true, raw, value, quote, match: m[0].trim() }
}

// a few windows around an anchor word, so a fact whose pattern missed shows what the page says instead
export function anchorWindows(text, anchor, max = 3) {
  const out = []
  if (!anchor) return out
  const re = new RegExp(anchor, 'gi')
  let m
  while ((m = re.exec(text)) && out.length < max) {
    out.push(text.slice(Math.max(0, m.index - 160), Math.min(text.length, m.index + 240)))
    re.lastIndex = m.index + m[0].length
  }
  return out
}

// JSA: the download links on a data page (href and link text), so the workbook is found by its name, not by a fixed address
export function xlsxLinks(html, base) {
  const out = []
  // href in double, single or no quotes; a file ending .xlsx or a download route ending /xlsx (jobsandskills.gov.au/download/<id>/<name>/<id>/<name>/xlsx)
  const re = /<a\b[^>]*?href\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>([\s\S]*?)<\/a>/gi
  let m
  while ((m = re.exec(String(html ?? '')))) {
    const href = (m[1] ?? m[2] ?? m[3] ?? '').replace(/&amp;/g, '&')
    if (!/(\.xlsx|\/xlsx)(\?|#|$)/i.test(href)) continue
    let abs = href
    try { abs = new URL(href, base).href } catch { /* keep as is */ }
    out.push({ href: abs, text: htmlToText(m[4]) })
  }
  return out
}

// RM1D JSA occupation workbook: the header row is found by its words, not by a fixed position. A sheet loads only when it has an occupation
// code column, an occupation title column and at least one measure (median weekly earnings or employed persons); anything else is reported
// with its sheet name and first header cells so the column map can be added, and nothing is guessed.
const H = {
  code: /^(osca|anzsco)?\s*(occupation\s*)?code$|^(osca|anzsco)\s*(unit group\s*)?code|occupation code/i,
  title: /^(osca|anzsco)?\s*(occupation|unit group)(\s*(title|name))?$|occupation (title|name)/i,
  earnings: /median.*weekly.*(earn|income|pay)|weekly.*median.*(earn|income)/i,
  employed: /^(number\s+)?employed(\s*persons)?$|^employment(\s*\(?(persons|number|count)\)?)?$|employed.*\(?(persons|number|'?000)/i,
}

export function findOccupationHeader(grid, scanRows = 40) {
  for (let i = 0; i < Math.min(grid.length, scanRows); i++) {
    const cells = (grid[i] || []).map((c) => htmlToText(String(c ?? '')))
    const col = (re) => cells.findIndex((c) => re.test(c))
    const code = col(H.code)
    const title = cells.findIndex((c, j) => j !== code && H.title.test(c))
    const earnings = col(H.earnings)
    const employed = col(H.employed)
    if (code >= 0 && title >= 0 && (earnings >= 0 || employed >= 0)) return { row: i, code, title, earnings, employed, header: cells }
  }
  return null
}

export function parseOccupationGrid(grid) {
  const h = findOccupationHeader(grid)
  if (!h) return { header: null, rows: [] }
  const rows = []
  const thousands = h.employed >= 0 && /'?000|thousand/i.test(h.header[h.employed])
  for (let i = h.row + 1; i < grid.length; i++) {
    const r = grid[i] || []
    const code = String(r[h.code] ?? '').trim().replace(/\.0+$/, '')
    const title = htmlToText(String(r[h.title] ?? ''))
    if (!/^\d{4,7}$/.test(code) || !title) continue
    const earn = h.earnings >= 0 ? (typeof r[h.earnings] === 'number' ? r[h.earnings] : parseNumber(r[h.earnings])) : null
    let emp = h.employed >= 0 ? (typeof r[h.employed] === 'number' ? r[h.employed] : parseNumber(r[h.employed])) : null
    if (emp != null && thousands) emp = Math.round(emp * 1000)
    if (earn == null && emp == null) continue
    rows.push({ code, title, median_weekly_earnings: earn, employment_count: emp })
  }
  return { header: { row: h.row, code: h.header[h.code], title: h.header[h.title], earnings: h.earnings >= 0 ? h.header[h.earnings] : null,
    employed: h.employed >= 0 ? h.header[h.employed] : null, thousands }, rows }
}

// the words of a link: its text and its address with separators read as spaces, so "osca-occupation-data" matches /OSCA\s+Occupation\s+data/
export function linkWords(link) {
  let h = String(link?.href ?? '')
  try { h = decodeURIComponent(h) } catch { /* keep as is */ }
  return `${link?.text ?? ''} ${h.replace(/[-_/.]+/g, ' ')}`
}
