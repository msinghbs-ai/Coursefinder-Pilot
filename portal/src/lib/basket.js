// The "proposal basket": courses a Counsellor has picked from search results or Saved courses on the way to a new proposal.
// It lives in this browser tab only (session storage) and is cleared once the proposal is started. A light convenience, so
// every read and write is guarded: a blocked store simply means an empty basket.
const KEY = 'studysearch-portal-proposal-basket'

const KEEP = ['course_id', 'title', 'provider_name', 'state_code', 'city', 'level', 'duration_value', 'duration_unit', 'delivery_mode', 'fee', 'next_intake']
const slim = c => { const o = {}; for (const k of KEEP) if (c[k] !== undefined) o[k] = c[k]; return o }

export function makeBasket(storage) {
  const read = () => { try { const v = JSON.parse(storage.getItem(KEY) || '[]'); return Array.isArray(v) ? v : [] } catch { return [] } }
  const write = list => { try { storage.setItem(KEY, JSON.stringify(list)) } catch { /* blocked store: the basket stays empty */ } }
  return {
    list: read,
    count: () => read().length,
    has: id => read().some(c => c.course_id === id),
    add(course) { const list = read(); if (!course?.course_id || list.some(c => c.course_id === course.course_id)) return list.length; write([...list, slim(course)]); return list.length + 1 },
    addMany(courses) { const list = read(); const have = new Set(list.map(c => c.course_id)); const next = [...list]; for (const c of courses) if (c?.course_id && !have.has(c.course_id)) { have.add(c.course_id); next.push(slim(c)) } write(next); return next.length },
    remove(id) { write(read().filter(c => c.course_id !== id)) },
    clear() { try { storage.removeItem(KEY) } catch { /* nothing to clear */ } },
  }
}

export const basket = makeBasket({
  getItem: k => { try { return sessionStorage.getItem(k) } catch { return null } },
  setItem: (k, v) => sessionStorage.setItem(k, v),
  removeItem: k => sessionStorage.removeItem(k),
})
