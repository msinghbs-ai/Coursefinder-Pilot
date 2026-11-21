// CF-247 s930 (Platform Admin 21 Nov 2026, S1-Dynamic-Lookups): the lookups every admin screen reads live from the database
// (public.admin_lookups_v1): countries (active providers or admission target countries), study levels and the rolling intake years.
// No screen writes a country, level or year list of its own. Read once a page load and shared; a failed read leaves the lists empty
// (each screen still shows the values its own data holds) and is read again on the next use.
import { useEffect, useState } from 'react'

const EMPTY = { countries: [], study_levels: [], intake_years: [], providers: {} }
let cache = null
let pending = null

export async function loadLookups() {
  if (cache) return cache
  // the client is loaded on first use, so the pure helpers below can be tested without it
  if (!pending) pending = import('./supabase.js').then(({ supabase }) => supabase.rpc('admin_lookups_v1', { p_args: {} }))
    .then(({ data, error }) => { if (error) throw error; cache = { ...EMPTY, ...(data || {}) }; return cache })
    .finally(() => { pending = null })
  return pending
}

/** The live lookups; EMPTY until the read answers. */
export function useLookups() {
  const [lk, setLk] = useState(cache || EMPTY)
  useEffect(() => { let on = true; if (!cache) loadLookups().then(x => on && setLk(x)).catch(() => {}); return () => { on = false } }, [])
  return lk
}

const regionNames = (() => { try { return new Intl.DisplayNames(['en-AU'], { type: 'region' }) } catch { return null } })()
/** A country's name from the lookups, else the browser's own name for the code, else the code. */
export function countryName(lk, code) {
  const c = (lk?.countries || []).find(x => x.code === code)
  if (c?.name) return c.name
  try { return regionNames?.of(code) || code } catch { return code }
}

/** The target countries (where admission runs), in the order the lookups give (target first, then by providers). */
export const targetCountries = lk => (lk?.countries || []).filter(c => c.target)

/** [code, label] pairs for a country picker: the lookups' countries, then any code the screen's own data holds that they do not. */
export function countryPairs(lk, { only = 'target', extra = [], label = c => c.name } = {}) {
  const list = only === 'target' ? targetCountries(lk) : (lk?.countries || [])
  const seen = new Set(list.map(c => c.code))
  return [...list.map(c => [c.code, label(c)]), ...extra.filter(code => code && !seen.has(code)).map(code => [code, label({ code, name: countryName(lk, code) })])]
}

/** The rolling intake years joined with the years a screen's own data holds, in order. */
export const intakeYears = (lk, held = []) => [...new Set([...(lk?.intake_years || []), ...held].map(Number).filter(Boolean))].sort((a, b) => a - b)
