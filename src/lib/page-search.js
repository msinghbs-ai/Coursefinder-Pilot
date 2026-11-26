// s1270 (SS-Programme-Control 26 Nov 2026 17:47, "Searchable Admin page navigation and settings"): the matching and ranking behind the page search bar
// (PageSearch.jsx). Pure functions, no screen and no backend: an entry is {id, kind, label, path, keywords, help, key, ...}; a query finds entries whose
// words (or a word's plain synonym) all appear. It searches only what the page has been given, so a person never finds a control their role cannot see.
//
// The synonym sets below are interface vocabulary (words people use for the same thing on these screens), not data: providers, countries, fields,
// settings and years are never written here (s930); they come from the live screen or the settings read.

export const SYNONYMS = [
  ['cap', 'limit', 'ceiling', 'maximum', 'max', 'quota'],
  ['budget', 'spend', 'cost', 'credit', 'credits', 'dollar', 'dollars', 'usd', 'price'],
  ['retry', 'retries', 'reread', 're read', 'again', 'recheck', 'backoff', 'back off'],
  ['schedule', 'scheduled', 'cron', 'cadence', 'frequency', 'interval', 'timing'],
  ['size', 'batch', 'page size', 'chunk', 'per run'],
  ['switch', 'toggle', 'enable', 'enabled', 'disable', 'on off', 'pause', 'paused', 'turn off', 'turn on'],
  ['worker', 'job', 'jobs', 'scheduler', 'automation', 'lane'],
  ['stalled', 'stuck', 'heartbeat', 'hung', 'not running', 'stopped'],
  ['lease', 'leases', 'claim', 'claimed'],
  ['freshness', 'fresh', 'stale', 'refresh', 'out of date', 'old', 'age'],
  ['consumer', 'delivery', 'delivered', 'read back', 'website', 'wix', 'zoho', 'served'],
  ['request', 'requests', 'feedback', 'stakeholder'],
  ['ai', 'model', 'models', 'openrouter', 'llm', 'prompt', 'prompts'],
  ['fee', 'fees', 'tuition', 'cost of study'],
  ['english', 'ielts', 'pte', 'toefl', 'language test'],
  ['intake', 'intakes', 'start date', 'start dates', 'deadline', 'deadlines'],
  ['entry', 'admission', 'academic entry', 'entry requirements', 'requirements'],
  ['scholarship', 'scholarships', 'award', 'awards', 'bursary'],
  ['description', 'descriptions', 'about', 'summary'],
  ['firecrawl', 'scraper', 'fetcher', 'crawl', 'crawler', 'fetch'],
  ['alert', 'alerts', 'notice', 'notices', 'warning', 'warnings', 'notify'],
  ['retention', 'retain', 'keep', 'purge', 'delete after', 'cleanup', 'clean up'],
  ['backup', 'restore', 'rollback'],
  ['role', 'roles', 'permission', 'permissions', 'access'],
  ['hold', 'held', 'blocked', 'block', 'excluded', 'exclusion'],
  ['gain', 'gains', 'throughput', 'speed', 'rate', 'progress'],
  ['coverage', 'complete', 'completeness', 'backlog', 'gap', 'gaps', 'missing'],
]

/** Lower case, accents removed, every run of other characters one space: `batch.matcher_size` reads "batch matcher size". */
export const norm = (s) => String(s ?? '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, ' ').trim()

/** The query's words, in order, each once. */
export const terms = (q) => [...new Set(norm(q).split(' ').filter(Boolean))]

/** Every way a person may say one word: itself, its singular, and the words in the same synonym set. A word is never matched on fewer than 2 characters. */
export function expand(t) {
  const out = new Set([t])
  if (t.length > 3 && t.endsWith('s')) out.add(t.slice(0, -1))
  if (t.length > 2 && !t.endsWith('s')) out.add(`${t}s`)
  for (const g of SYNONYMS) if (g.some((w) => w === t || norm(w) === t)) for (const w of g) out.add(norm(w))
  return [...out].filter((w) => w.length > 1)
}

const FIELDS = [['label', 6], ['key', 4], ['path', 3], ['keywords', 2], ['help', 1]]

/** The search text of an entry, one normalised string per weighted field (padded with spaces so a word matches whole words first). */
export function prepare(e) {
  const f = {}
  for (const [name] of FIELDS) f[name] = ` ${norm(e[name])} `
  return { ...e, _f: f }
}

/** Score of one word on one entry: a whole-word hit in the label is the best, then the key, the path (where it sits), the keywords, then the help text. */
function wordScore(e, variants, exact) {
  let best = 0
  for (const [name, weight] of FIELDS) {
    const text = e._f[name]
    if (!text.trim()) continue
    for (const v of variants) {
      const whole = text.includes(` ${v} `), start = text.includes(` ${v}`), part = text.includes(v)
      if (!part) continue
      const s = weight * (whole ? 3 : start ? 2 : 1) * (v === exact ? 1.2 : 1)
      if (s > best) best = s
    }
  }
  return best
}

/**
 * Rank prepared entries for a query. Every word must be found (a word or one of its synonyms); entries are ordered by score, then tab before view before
 * section before setting, then by label. `limit` keeps the list short enough to read on a phone.
 */
export function rank(entries, query, limit = 12) {
  const ts = terms(query)
  if (!ts.length) return []
  const KIND = { tab: 0, view: 1, section: 2, setting: 3 }
  const out = []
  for (const e of entries) {
    let total = 0
    let ok = true
    for (const t of ts) {
      const s = wordScore(e, expand(t), t)
      if (!s) { ok = false; break }
      total += s
    }
    if (!ok) continue
    const labelN = norm(e.label)
    const q = ts.join(' ')
    if (labelN === q) total += 40
    else if (labelN.startsWith(q)) total += 15
    else if (labelN.includes(q)) total += 8
    out.push({ e, total })
  }
  out.sort((a, b) => b.total - a.total || (KIND[a.e.kind] ?? 9) - (KIND[b.e.kind] ?? 9) || String(a.e.label).localeCompare(String(b.e.label)))
  return out.slice(0, limit).map((x) => x.e)
}

/** Drop later entries with the same id, or the same kind, label and path (a DOM-found section that a screen has also registered). */
export function dedupe(entries) {
  const seen = new Set()
  const out = []
  for (const e of entries) {
    const keys = [`id:${e.id}`, `${e.kind}|${norm(e.label)}|${norm(e.path)}`]
    if (keys.some((k) => seen.has(k))) continue
    keys.forEach((k) => seen.add(k))
    out.push(e)
  }
  return out
}

/** The words shown for an entry's kind. */
export const KIND_WORD = { tab: 'Tab', view: 'View', section: 'Section', setting: 'Setting' }
