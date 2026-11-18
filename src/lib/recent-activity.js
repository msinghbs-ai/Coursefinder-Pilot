// Dashboard › Continue where you left off (v2.16.35, Platform Admin 18 Nov 2026 10:31 and 10:33): the person's last searches, review queues and pages,
// kept on this browser only (localStorage, one list per signed-in user). Nothing is sent to the server and nothing here is shared between people.
// A search is resumed exactly: the catalogue's own remembered state (ui-kit rememberedStateKey) is set back before its page opens.
import { rememberedStateKey } from '../ui-kit'

const KEY = (userId) => `cf-recent:v1:${userId || 'anonymous'}`
export const RECENT_MAX = 8 // fixed: how many entries the Dashboard list shows (presentation, not an operational limit)

export function readRecent(userId) {
  try { const v = JSON.parse(localStorage.getItem(KEY(userId)) || '[]'); return Array.isArray(v) ? v.filter((x) => x && x.id && x.href) : [] } catch { return [] }
}

// entry: { id, kind: 'search' | 'queue' | 'page', label, detail, href, state?: { screen, patch } }. The newest is first; the same id replaces its older entry.
export function recordRecent(userId, entry) {
  if (!userId || !entry?.id || !entry?.href) return
  try {
    const next = [{ ...entry, at: new Date().toISOString() }, ...readRecent(userId).filter((x) => x.id !== entry.id)].slice(0, RECENT_MAX)
    localStorage.setItem(KEY(userId), JSON.stringify(next))
  } catch { /* storage may be full or blocked: the list is a convenience */ }
}

export function clearRecent(userId) { try { localStorage.removeItem(KEY(userId)) } catch { /* ignore */ } }

// Opens an entry: a search writes its query and filters back into the catalogue's remembered state first.
export function resumeRecent(userId, entry) {
  if (entry?.state?.screen && entry.state.patch) {
    try {
      const k = rememberedStateKey(entry.state.screen, userId)
      const saved = JSON.parse(localStorage.getItem(k) || '{}')
      localStorage.setItem(k, JSON.stringify({ ...(saved && typeof saved === 'object' ? saved : {}), ...entry.state.patch }))
    } catch { /* ignore */ }
  }
  if (location.hash === entry.href) location.reload()
  else location.hash = entry.href.replace(/^#/, '')
}

// A page or tab opened in the shell. The Dashboard itself and the sign-in are not recorded; a Layer 4 Review address with a kind is a review queue.
export function routeEntry(route, pages, tabLabel) {
  if (!route?.page || route.page === 'dashboard') return null
  const p = pages[route.page]; if (!p) return null
  const params = route.params && typeof route.params.toString === 'function' ? route.params.toString() : ''
  const href = `#${location.hash.replace(/^#/, '').split('?')[0] || p.slug}${params ? `?${params}` : ''}`
  const kind = route.page === 'layer4' && route.params?.get?.('kind') ? 'queue' : 'page'
  const label = [p.label, tabLabel].filter(Boolean).join(' › ')
  const detail = kind === 'queue' ? String(route.params.get('kind')).replace(/_/g, ' ') : ''
  return { id: `${kind}:${href}`, kind, label, detail, href }
}

// A catalogue search: what was typed and the filter labels shown on its chips.
export function searchEntry(type, noun, { query = '', filters = {}, filterLabels = {} } = {}) {
  const active = Object.entries(filters || {}).filter(([, v]) => v !== '' && v != null && !(Array.isArray(v) && !v.length))
  if (!String(query).trim() && !active.length) return null
  const bits = [String(query).trim() ? `“${String(query).trim()}”` : '', ...active.map(([k, v]) => filterLabels?.[k] || `${k.replace(/_/g, ' ')}: ${Array.isArray(v) ? v.join(', ') : v}`)].filter(Boolean)
  const href = location.hash || '#'
  return { id: `search:${type}:${JSON.stringify([String(query).trim(), active])}`, kind: 'search', label: noun, detail: bits.join(' · '), href, state: { screen: type, patch: { query, filters, filterLabels } } }
}
