// CF-247 Firecrawl format profiles (v2.16.2, Platform Admin 14 Nov 2026 19:19; mock-up accepted 20:13). What each Firecrawl page read asks for:
// the screen's own copy of the rules the server (security.fc_scrape_profiles_check_v1) and the worker (coverage-sweep/firecrawl.ts checkProfile)
// apply, so a problem is shown before Save. The server decides; its message is shown when it refuses.
export const FORMATS = ['markdown', 'rawHtml', 'html', 'links', 'screenshot']
export const NEVER_SENT = ['json', 'summary', 'question', 'highlights', 'onlyCleanContent']
export const ACTION_TYPES = ['click', 'wait', 'scroll', 'press', 'write']
export const LANE_OWN = 'lane_own'
const KEYS = new Set(['name', 'about', 'formats', 'onlyMainContent', 'includeTags', 'excludeTags', 'maxAgeMs', 'waitFor', 'timeout', 'actions', 'screenshotFullPage', 'crawl'])
const CRAWL = new Set(['limit', 'maxDiscoveryDepth', 'includePaths', 'excludePaths', 'sitemap'])
const TAG = /^[a-zA-Z][a-zA-Z0-9-]{0,40}$|^[.#][A-Za-z0-9_-]{1,60}$/
const intIn = (v, lo, hi) => typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi
export const HOUR = 3600000

// The lanes that send a scrape (worker coverage-sweep), in words, and whether the read keeps its formats with the evidence.
export const LANES = [
  ['course_read_view', 'Course page, rendered view', 'kept'], ['course_read', 'Course page, plain read', 'kept'], ['course_read_priority', 'Course page, priority read', 'kept'],
  ['read_page', 'Run now page read', 'kept'], ['provider_description', 'About page (provider description)', 'kept'],
  ['entry_render', 'Entry requirements page (AER v1)', 'aer'], ['entry_fallback', 'Entry requirements, second try (AER v1)', 'aer'], ['entry_pdf_render', 'Entry requirements PDF (AER v1)', 'aer'],
  ['course_list_read', 'Course list page', 'read'], ['programme_discover', 'Programme list', 'read'], ['programme_read', 'Programme page', 'read'],
  ['source_find', 'Source page search', 'read'], ['companion_read', 'Companion page', 'read'], ['scholarship_read', 'Scholarship page', 'read'],
  ['provider_facts_read', 'Provider facts document', 'read'], ['cricos_peo', 'CRICOS contact page', 'read'], ['enrich_address', 'Provider address', 'read'],
  ['find_site_register', 'Register page', 'read'], ['site_check', 'Site check', 'read'], ['find_site', 'Official website search', 'read'],
  ['adapter_builder', 'Adapter builder capture', 'own'], ['probe', 'Firecrawl probe (Run now diagnostic)', 'own'],
]
export const LANE_NAME = Object.fromEntries(LANES.map(([k, w]) => [k, w]))
export const FROZEN_LANES = new Set(LANES.filter((l) => l[2] === 'aer').map((l) => l[0]))  // Decision 276: AER v1 lanes keep their own request

/** What the evidence keeps for a lane with this profile, in words. */
export function keptText(lane, prof) {
  const l = LANES.find((x) => x[0] === lane)
  if (!prof) return 'As today (the lane’s own request)'
  if (!l || l[2] !== 'kept') return 'Read only (not kept as evidence)'
  const f = ['rawHtml', 'html'].filter((x) => prof.formats.includes(x)).slice(0, 1).concat(prof.formats.includes('markdown') ? ['markdown'] : [])
  return [f.join(' + ') || 'the page', prof.formats.includes('screenshot') ? 'screenshot' : ''].filter(Boolean).join(' + ')
}

export function checkProfile(p, name = 'profile') {
  const e = []
  if (!p || typeof p !== 'object' || Array.isArray(p)) return [`${name}: not a profile`]
  for (const k of Object.keys(p)) if (!KEYS.has(k)) e.push(k === 'onlyCleanContent' ? `${name}: onlyCleanContent is never sent (an AI pass over the page)` : `${name}: ${k} is not a profile setting`)
  if (!Array.isArray(p.formats) || !p.formats.length) e.push(`${name}: choose at least one format`)
  else {
    for (const f of p.formats) if (!FORMATS.includes(f)) e.push(`${name}: format ${f} is never sent (only ${FORMATS.join(', ')})`)
    if (!p.formats.some((f) => ['markdown', 'rawHtml', 'html', 'links'].includes(f))) e.push(`${name}: a screenshot alone is not a page read; add markdown, rawHtml, html or links`)
  }
  for (const k of ['includeTags', 'excludeTags']) if (p[k] !== undefined && (!Array.isArray(p[k]) || p[k].length > 40 || !p[k].every((t) => typeof t === 'string' && TAG.test(t)))) e.push(`${name}: ${k === 'includeTags' ? 'Keep only tags' : 'Leave out tags'} is a list of tag names or .class/#id selectors`)
  if (p.maxAgeMs != null && !intIn(p.maxAgeMs, 0, 720 * HOUR)) e.push(`${name}: the Firecrawl copy age is 0 to 720 hours`)
  if (p.waitFor != null && !intIn(p.waitFor, 0, 60000)) e.push(`${name}: wait after load is 0 to 60,000 ms`)
  if (p.timeout != null && !intIn(p.timeout, 1000, 300000)) e.push(`${name}: time allowed is 1,000 to 300,000 ms`)
  if (p.waitFor != null && p.timeout != null && p.waitFor >= p.timeout) e.push(`${name}: wait after load must be shorter than the time allowed`)
  if (p.actions != null) {
    if (!Array.isArray(p.actions) || p.actions.length > 20) e.push(`${name}: actions are a list of at most 20 steps`)
    else for (const a of p.actions) if (!a || typeof a !== 'object' || !ACTION_TYPES.includes(a.type)) e.push(`${name}: action ${a?.type ?? JSON.stringify(a)} is not allowed (only ${ACTION_TYPES.join(', ')})`)
  }
  const c = p.crawl
  if (c !== undefined) {
    if (!c || typeof c !== 'object' || Array.isArray(c)) e.push(`${name}: crawl options are a set of values`)
    else {
      for (const k of Object.keys(c)) if (!CRAWL.has(k)) e.push(`${name}: crawl ${k} is not a crawl option`)
      if (c.limit !== undefined && !intIn(c.limit, 1, 1000)) e.push(`${name}: crawl pages at most is 1 to 1,000`)
      if (c.maxDiscoveryDepth !== undefined && !intIn(c.maxDiscoveryDepth, 0, 10)) e.push(`${name}: crawl link depth is 0 to 10`)
      if (c.sitemap !== undefined && !['include', 'skip', 'only'].includes(c.sitemap)) e.push(`${name}: crawl site map is include, skip or only`)
    }
  }
  return e
}

export function checkAll({ profiles, lanes, overrides }) {
  const e = []
  if (!profiles || !Object.keys(profiles).length) e.push('Keep at least one profile')
  for (const [k, p] of Object.entries(profiles || {})) { if (!/^[a-z][a-z0-9_]{0,40}$/.test(k) || k === LANE_OWN) e.push(`Profile name ${k} is not allowed`); e.push(...checkProfile(p, p?.name || k)) }
  for (const [l, k] of Object.entries(lanes || {})) if (k !== LANE_OWN && !profiles?.[k]) e.push(`${LANE_NAME[l] || l}: its profile no longer exists`)
  for (const o of overrides || []) if (!o.provider_id || !o.lane || !(o.profile === LANE_OWN || profiles?.[o.profile])) e.push('An override needs a university, a lane and a profile')
  return e
}

/** The request Firecrawl is sent for this profile (what the worker's applyProfile does), for the preview. */
export function preview(prof, runNow, url = 'https://www.example.edu.au/study/bachelor-of-science') {
  const b = { url, formats: prof.formats.map((f) => (f === 'screenshot' ? { type: 'screenshot', fullPage: prof.screenshotFullPage ?? false } : f)) }
  if (prof.onlyMainContent !== undefined) b.onlyMainContent = prof.onlyMainContent
  if (prof.includeTags?.length) b.includeTags = prof.includeTags
  if (prof.excludeTags?.length) b.excludeTags = prof.excludeTags
  if (runNow) b.maxAge = 0; else if (prof.maxAgeMs != null) b.maxAge = prof.maxAgeMs
  if (prof.waitFor != null) b.waitFor = prof.waitFor
  if (prof.timeout != null) b.timeout = prof.timeout
  if (prof.actions?.length) b.actions = prof.actions
  return b
}

// Comma text <-> list; blank number fields are "the lane's own" (null).
export const listText = (v) => (Array.isArray(v) ? v.join(', ') : '')
export const textList = (s) => String(s || '').split(',').map((x) => x.trim()).filter(Boolean)
export const numOrNull = (s) => (String(s ?? '').trim() === '' ? null : Number(String(s).replace(/,/g, '')))
/** A new profile key from its name. */
export function keyFor(name, taken) {
  let k = String(name || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').replace(/^([^a-z])/, 'p_$1').slice(0, 40) || 'profile'
  if (k === LANE_OWN) k = 'profile'
  let n = k, i = 2
  while (taken.includes(n)) n = `${k}_${i++}`.slice(0, 41)
  return n
}
