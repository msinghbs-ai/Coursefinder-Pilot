// CF-247 AER country order (Platform Admin mandate 29 Oct 2026 12:23, section A4): one shared order for every country of prior
// education list in Academic entry requirements — the Course detail selector and the Entry requirements workspace's country filters and
// pickers. 1. India 2. Nepal 3. Singapore 4. every other available country alphabetically by name.
// Pure: it orders only the countries it is given (the server's reference data), drops repeats and blanks, and never adds a country that
// is not in the list (a priority country with no data is simply not shown).
export const AER_PRIORITY_COUNTRIES = Object.freeze(['IN', 'NP', 'SG'])

const codeOf = c => String(c?.code ?? '').trim().toUpperCase()
const nameOf = c => String(c?.name ?? c?.code ?? '').trim()

export function orderAerCountries(list) {
  const seen = new Set(), out = []
  for (const c of Array.isArray(list) ? list : []) {
    const code = codeOf(c)
    if (!code || seen.has(code)) continue
    seen.add(code); out.push(c)
  }
  const rank = c => { const i = AER_PRIORITY_COUNTRIES.indexOf(codeOf(c)); return i < 0 ? AER_PRIORITY_COUNTRIES.length : i }
  return out.sort((a, b) => rank(a) - rank(b) || nameOf(a).localeCompare(nameOf(b), 'en', { sensitivity: 'base' }) || codeOf(a).localeCompare(codeOf(b)))
}

// The Course detail selector keeps the chosen country across reloads (a per-viewer convenience; storage may be unavailable).
export const AER_COURSE_COUNTRY_KEY = 'cf.aer.course-country'
export function readAerCountry() { try { return globalThis.localStorage?.getItem(AER_COURSE_COUNTRY_KEY) || '' } catch { return '' } }
export function saveAerCountry(code) { try { if (code) globalThis.localStorage?.setItem(AER_COURSE_COUNTRY_KEY, code); else globalThis.localStorage?.removeItem(AER_COURSE_COUNTRY_KEY) } catch { /* storage blocked: the choice lasts this visit only */ } }
