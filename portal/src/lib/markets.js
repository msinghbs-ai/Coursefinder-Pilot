// s1222: student-country lists put the countries in portal.priority_source_countries first (a G2 setting read through
// portal_settings_v1, India and Nepal at release), then every other country alphabetically. No country is written here.
export function orderMarkets(markets, priority) {
  const list = Array.isArray(markets) ? markets : []
  const codes = (Array.isArray(priority) ? priority : []).map(c => String(c || '').trim().toUpperCase()).filter(Boolean)
  const byCode = new Map(list.map(m => [String(m.code || '').toUpperCase(), m]))
  const pinned = [...new Set(codes)].map(c => byCode.get(c)).filter(Boolean)
  const rest = list.filter(m => !codes.includes(String(m.code || '').toUpperCase())).sort((a, b) => String(a.name || '').localeCompare(String(b.name || ''), 'en'))
  return { pinned, rest }
}
