// CF-247 F-INT.04: per-course comparison of the catalogue, Website and Zoho intake values, read from the verification report only.
// Pure and read-only: it never starts a job and never changes a value. Null or an error object means "not read", never "matches".
const KEYS = ['year', 'start_date', 'month', 'intake_name']
const isRows = x => Array.isArray(x)
const signature = row => {
  if (!row || typeof row !== 'object') return null
  const parts = KEYS.filter(k => row[k] != null && row[k] !== '').map(k => `${k}=${String(row[k]).trim().toLowerCase()}`)
  return parts.length ? parts.join('|') : null
}
const sigSet = rows => {
  const sigs = rows.map(signature)
  return sigs.includes(null) ? null : new Set(sigs)
}
const same = (a, b) => a.size === b.size && [...a].every(x => b.has(x))

// side: 'match' | 'differs' | 'not_read' | 'cannot_compare'
export function compareSide(canonical, other) {
  if (!isRows(other)) return { state: 'not_read', note: other && typeof other === 'object' && other.error ? 'Read-back reported an error (shown below)' : 'Not read back' }
  if (!isRows(canonical)) return { state: 'not_read', note: 'Catalogue values not supplied' }
  const a = sigSet(canonical), b = sigSet(other)
  if (!a || !b) return { state: 'cannot_compare', note: 'Rows carry no year, start date, month or intake name to compare' }
  return same(a, b) ? { state: 'match', note: `${a.size} intake value${a.size === 1 ? '' : 's'} agree` } : { state: 'differs', note: `Catalogue ${a.size} value${a.size === 1 ? '' : 's'}, other ${b.size}` }
}

export function intakeParity(course) {
  return { website: compareSide(course?.now, course?.website_intakes), zoho: compareSide(course?.now, course?.zoho_intakes) }
}

export const PARITY_LABEL = { match: 'Matches catalogue', differs: 'Differs from catalogue', not_read: 'Not read back', cannot_compare: 'Cannot compare' }

// Roll-up by university for the verification report. Counts every course once per side; nothing is hidden when a side was not read.
export function parityByProvider(courses = []) {
  const out = new Map()
  for (const c of courses) {
    const id = c.provider_id || c.provider_name || 'unknown'
    const row = out.get(id) || { provider: c.provider_name || c.provider_id || 'Unknown provider', courses: 0, website: { match: 0, differs: 0, not_read: 0, cannot_compare: 0 }, zoho: { match: 0, differs: 0, not_read: 0, cannot_compare: 0 } }
    const p = intakeParity(c)
    row.courses++; row.website[p.website.state]++; row.zoho[p.zoho.state]++
    out.set(id, row)
  }
  return [...out.values()]
}
