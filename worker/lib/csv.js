export function parseCsv(text) {
  const rows = []
  let row = [], field = '', quoted = false
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++ }
      else if (ch === '"') quoted = false
      else field += ch
    } else {
      if (ch === '"') quoted = true
      else if (ch === ',') { row.push(field); field = '' }
      else if (ch === '\n') { row.push(field.replace(/\r$/, '')); rows.push(row); row = []; field = '' }
      else field += ch
    }
  }
  if (field.length || row.length) { row.push(field.replace(/\r$/, '')); rows.push(row) }
  if (rows.length < 2) return []
  const headers = rows[0].map(v => v.replace(/^\uFEFF/, '').trim())
  return rows.slice(1).filter(r => r.some(v => v.trim())).map(values => Object.fromEntries(headers.map((h, i) => [h, values[i] ?? ''])))
}

export function normaliseRow(row) {
  return Object.fromEntries(Object.entries(row).map(([k, v]) => [normaliseHeader(k), String(v ?? '').trim()]))
}
export function normaliseHeader(value) { return String(value).toLowerCase().replace(/[_-]+/g, ' ').replace(/\s+/g, ' ').trim() }
export function pick(row, aliases) { for (const a of aliases) { const v = row[normaliseHeader(a)]; if (v) return v } return '' }
export function cleanCode(value) { return String(value || '').trim().toUpperCase() }
export function numericText(value) { const m = String(value || '').replace(/,/g, '').match(/\d+(?:\.\d+)?/); return m ? m[0] : '' }
