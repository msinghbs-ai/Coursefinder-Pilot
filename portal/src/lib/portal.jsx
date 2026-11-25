import React, { createContext, useContext, useEffect, useMemo, useState, useCallback } from 'react'
import { rpc } from './api.js'

// Settings and lookups come from the database (G2 and s930): no limit, destination or market is written into the screens.
const PortalContext = createContext(null)
export const usePortal = () => useContext(PortalContext)

const prefsKey = id => `studysearch-portal-prefs:${id || 'anon'}`
function readPrefs(id) { try { const v = JSON.parse(localStorage.getItem(prefsKey(id)) || '{}'); return v && typeof v === 'object' ? v : {} } catch { return {} } }
function writePrefs(id, value) { try { localStorage.setItem(prefsKey(id), JSON.stringify(value)) } catch { /* a light per-person convenience; ignored if the browser blocks storage */ } }

export function PortalProvider({ userId, children }) {
  const [state, setState] = useState({ loading: true, error: '', settings: {}, lookups: { destinations: [], markets: [] } })
  const [prefs, setPrefs] = useState(() => readPrefs(userId))

  useEffect(() => {
    let live = true
    Promise.all([rpc('portal_settings_v1'), rpc('portal_lookups_v1')])
      .then(([settings, lookups]) => { if (live) setState({ loading: false, error: '', settings: settings || {}, lookups: lookups || { destinations: [], markets: [] } }) })
      .catch(e => { if (live) setState(s => ({ ...s, loading: false, error: e.message })) })
    return () => { live = false }
  }, [])

  const destinations = state.lookups.destinations || []
  // A saved destination that is no longer live falls back to All.
  const studyIn = destinations.some(d => d.code === prefs.studyIn) ? prefs.studyIn : ''

  const update = useCallback(patch => setPrefs(p => { const next = { ...p, ...patch }; writePrefs(userId, next); return next }), [userId])
  const value = useMemo(() => ({
    ...state, destinations, markets: state.lookups.markets || [], studyIn, market: prefs.market || '',
    setStudyIn: code => update({ studyIn: code }), setMarket: code => update({ market: code }),
  }), [state, destinations, studyIn, prefs.market, update])
  return <PortalContext.Provider value={value}>{children}</PortalContext.Provider>
}

// A server-paged list: filters reset the list, "Show more" appends the next page.
export function usePagedList(name, args, enabled = true) {
  const key = JSON.stringify(args)
  const [s, setS] = useState({ items: [], total: 0, page: 0, facets: {}, loading: enabled, more: false, error: '', unavailable: false })
  const [reload, setReload] = useState(0)

  const fetchPage = useCallback((page, replace, isLive) => {
    return rpc(name, { p_args: { ...args, page } })
      .then(r => { if (isLive()) setS(old => ({ items: replace ? r.items : [...old.items, ...r.items], total: r.total, page: r.page, facets: r.facets || {}, loading: false, more: false, error: '', unavailable: false })) })
      .catch(e => { if (isLive()) setS(old => ({ ...old, loading: false, more: false, error: e.message, unavailable: e.kind === 'missing' })) })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [name, key])

  useEffect(() => {
    if (!enabled) return undefined
    let live = true
    setS(old => ({ ...old, items: [], loading: true, error: '' }))
    fetchPage(1, true, () => live)
    return () => { live = false }
  }, [fetchPage, enabled, reload])

  const showMore = () => { setS(o => ({ ...o, more: true })); fetchPage(s.page + 1, false, () => true) }
  return { ...s, hasMore: s.items.length < s.total, showMore, retry: () => setReload(n => n + 1) }
}

// A short pause while typing, so each key press is not a database call. A typing convenience, not an operating value.
export function useDebounced(value, ms = 300) { // fixed: typing pause in the browser
  const [v, setV] = useState(value)
  useEffect(() => { const t = setTimeout(() => setV(value), ms); return () => clearTimeout(t) }, [value, ms])
  return v
}
