// CSV reader for PostgreSQL COPY ... (format csv, header true) output. An unquoted empty field is null; a quoted empty field ("") is
// the empty string, so null stays distinct from '' end to end. Quoted fields may hold commas, quotes ("") and newlines.
export function parseCsv(text) {
  const records = []
  let i = 0, field = '', quoted = false, row = []
  const n = text.length
  const endField = () => { row.push(quoted || field !== '' ? field : null); field = ''; quoted = false }
  while (i < n) {
    const ch = text[i]
    if (ch === '"' && field === '' && !quoted) {
      quoted = true; i++
      for (;;) {
        const j = text.indexOf('"', i)
        if (j < 0) throw new Error('unterminated quoted field')
        field += text.slice(i, j)
        if (text[j + 1] === '"') { field += '"'; i = j + 2 } else { i = j + 1; break }
      }
      continue
    }
    if (ch === ',') { endField(); i++; continue }
    if (ch === '\n' || ch === '\r') {
      endField(); records.push(row); row = []
      i += ch === '\r' && text[i + 1] === '\n' ? 2 : 1
      continue
    }
    field += ch; i++
  }
  if (field !== '' || quoted || row.length) { endField(); records.push(row) }
  if (!records.length) return []
  const header = records[0]
  const out = []
  for (let r = 1; r < records.length; r++) {
    const rec = records[r]
    if (rec.length === 1 && rec[0] === null && header.length > 1) continue // blank line
    if (rec.length !== header.length) throw new Error(`record ${r} has ${rec.length} fields, header has ${header.length}`)
    const o = {}
    for (let c = 0; c < header.length; c++) o[header[c]] = rec[c]
    out.push(o)
  }
  Object.defineProperty(out, 'header', { value: header, enumerable: false })
  return out
}
