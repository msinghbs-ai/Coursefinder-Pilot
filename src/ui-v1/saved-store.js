// v1.1 Counsellor UI (REQ-115): the saved-courses adapter. The interface is the one the server-backed list will use (S2-Build owns the table);
// until it merges, saves are kept in this browser (localStorage, per signed-in user). Swap the body of load/save, never the callers.
const key = uid => 'ss.saved_courses.v1:' + (uid || 'anon')
export function createSavedStore(userId) {
  let map = new Map()
  const subs = new Set()
  try { const raw = globalThis.localStorage?.getItem(key(userId)); if (raw) map = new Map(JSON.parse(raw).map(x => [x.id, x])) } catch { /* storage unavailable: saves last this visit */ }
  const persist = () => { try { globalThis.localStorage?.setItem(key(userId), JSON.stringify([...map.values()])) } catch { /* see above */ } subs.forEach(f => f()) }
  return {
    has: id => map.has(id),
    list: () => [...map.values()].sort((a, b) => String(b.saved_at).localeCompare(String(a.saved_at))),
    count: () => map.size,
    toggle(id, snapshot) { if (map.has(id)) map.delete(id); else map.set(id, { id, saved_at: new Date().toISOString(), ...snapshot }); persist() },
    subscribe(f) { subs.add(f); return () => subs.delete(f) },
  }
}
export const COMPARE_MAX = 4
