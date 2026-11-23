// v1.1 Counsellor UI (REQ-115): saved courses, kept on the server per signed-in user (s997: saved_courses_read_v1, saved_course_toggle_v1;
// is_saved arrives on every course-list row). The callers keep the interface the first browser-only adapter had: has, list, count, toggle, subscribe.
// A toggle shows at once and is put back, with the server's own words, if the server refuses it.
import { supabase } from '../lib/supabase.js'

export function createSavedStore(userId, rpc = (fn, args) => supabase.rpc(fn, args)) {
  const map = new Map()
  const subs = new Set()
  const state = { error: '', loaded: false, max: null }
  const emit = () => subs.forEach(f => f())
  const call = async (fn, args) => { const { data, error } = await rpc(fn, args); if (error) throw new Error(error.message || 'The request could not be completed.'); return data }
  const load = async () => {
    try {
      const d = await call('saved_courses_read_v1', {})
      for (const x of d?.items || []) map.set(x.course_id, { id: x.course_id, saved_at: x.saved_at, title: x.title, provider: x.provider_name, ...(map.get(x.course_id) || {}) })
      state.max = d?.max ?? null
    } catch (e) { state.error = 'Your saved courses could not be loaded. ' + e.message }
    state.loaded = true; emit()
  }
  if (userId) load()
  return {
    has: id => map.has(id),
    list: () => [...map.values()].sort((a, b) => String(b.saved_at).localeCompare(String(a.saved_at))),
    count: () => map.size,
    get error() { return state.error },
    get max() { return state.max },
    clearError() { state.error = ''; emit() },
    // reconcile the rows of a course list with the server's own is_saved
    sync(rows) { let changed = false; for (const r of rows || []) { if (r.is_saved === true && !map.has(r.id)) { map.set(r.id, { id: r.id, saved_at: new Date().toISOString() }); changed = true } if (r.is_saved === false && map.has(r.id) && !map.get(r.id).pending) { map.delete(r.id); changed = true } } if (changed) emit() },
    async toggle(id, snapshot) {
      const was = map.get(id)
      if (was) map.delete(id); else map.set(id, { id, saved_at: new Date().toISOString(), pending: true, ...snapshot })
      state.error = ''; emit()
      try {
        const d = await call('saved_course_toggle_v1', { p_course_id: id, p_saved: !was })
        const cur = map.get(id); if (cur) { delete cur.pending; if (d?.saved_at) cur.saved_at = d.saved_at }
        if (d?.max != null) state.max = d.max
      } catch (e) {
        if (was) map.set(id, was); else map.delete(id)
        state.error = e.message.replace(/^INVALID_INPUT:\s*/, '')
      }
      emit()
    },
    subscribe(f) { subs.add(f); return () => subs.delete(f) },
  }
}
export const COMPARE_MAX = 4
