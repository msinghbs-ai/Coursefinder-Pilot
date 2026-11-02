// CSV reader for PostgreSQL COPY ... (format csv, header true) output. An unquoted empty field is null; a quoted empty field ("") is
// the empty string, so null stays distinct from '' end to end. Quoted fields may hold commas, quotes ("") and new lines.
// CsvParser is incremental (chunks in, records out), so a file of any size is read line by line with constant memory: the export never
// holds a whole dataset (run 41377240304, 2 Nov 2026, ran out of heap doing that).
import fs from 'node:fs'

// Byte parser: every value is decoded from bytes into a fresh string, so no stored value keeps a 1 MB read chunk alive (a string sliced
// from a chunk does, which is what held the whole file in memory in the first streamed version).
const QUOTE = Buffer.from('"')
export class CsvParser {
  constructor(onRecord) {
    this.onRecord = onRecord
    this.parts = []; this.quoted = false; this.inQuotes = false; this.pendingQuote = false; this.row = []; this.any = false
  }
  endField() {
    const p = this.parts
    this.row.push(p.length === 0 ? (this.quoted ? '' : null) : p.length === 1 ? p[0].toString('utf8') : Buffer.concat(p).toString('utf8'))
    this.parts = []; this.quoted = false
  }
  endRow() { this.endField(); const r = this.row; this.row = []; this.any = false; this.onRecord(r) }
  push(input) {
    const buf = typeof input === 'string' ? Buffer.from(input, 'utf8') : input
    let i = 0
    const n = buf.length
    if (this.pendingQuote) {
      this.pendingQuote = false
      if (n && buf[0] === 34) { this.parts.push(QUOTE); i = 1 } else this.inQuotes = false
    }
    while (i < n) {
      if (this.inQuotes) {
        const j = buf.indexOf(34, i)
        if (j < 0) { this.parts.push(buf.subarray(i)); return }
        if (j > i) this.parts.push(buf.subarray(i, j))
        if (j + 1 >= n) { this.pendingQuote = true; return }
        if (buf[j + 1] === 34) { this.parts.push(QUOTE); i = j + 2 } else { this.inQuotes = false; i = j + 1 }
        continue
      }
      const c = buf[i]
      if (c === 34 && this.parts.length === 0 && !this.quoted) { this.inQuotes = true; this.quoted = true; this.any = true; i++; continue }
      if (c === 44) { this.endField(); this.any = true; i++; continue }
      if (c === 10) { this.endRow(); i++; continue }
      if (c === 13) { i++; continue }
      let j = i + 1
      while (j < n) { const d = buf[j]; if (d === 44 || d === 10 || d === 13 || d === 34) break; j++ }
      this.parts.push(buf.subarray(i, j)); i = j
      this.any = true
    }
  }
  end() {
    if (this.pendingQuote) { this.pendingQuote = false; this.inQuotes = false }
    if (this.inQuotes) throw new Error('unterminated quoted field')
    if (this.any || this.parts.length || this.quoted || this.row.length) this.endRow()
  }
}

// every record of a file as { header, record } through the callback, read in chunks; resolves with the header and the record count
export function eachRecord(file, cb) {
  return new Promise((resolve, reject) => {
    let header = null, n = 0
    const p = new CsvParser((rec) => {
      if (header === null) { header = rec; return }
      if (rec.length === 1 && rec[0] === null && header.length > 1) return
      if (rec.length !== header.length) throw new Error(`${file}: record ${n + 1} has ${rec.length} fields, header has ${header.length}`)
      n++
      cb(rec, header)
    })
    const s = fs.createReadStream(file, { highWaterMark: 1 << 20 })
    s.on('data', (chunk) => { try { p.push(chunk) } catch (e) { s.destroy(); reject(e) } })
    s.on('error', reject)
    s.on('end', () => { try { p.end(); resolve({ header: header || [], rows: n }) } catch (e) { reject(e) } })
  })
}

// async iterator of records as objects (for merge-joins of two sorted files); pauses the stream while the consumer works
export async function* records(file) {
  const queue = []
  let header = null, done = false, err = null, wake = null
  const p = new CsvParser((rec) => {
    if (header === null) { header = rec; return }
    if (rec.length === 1 && rec[0] === null && header.length > 1) return
    const o = {}; for (let c = 0; c < header.length; c++) o[header[c]] = rec[c]
    queue.push(o)
  })
  const s = fs.createReadStream(file, { highWaterMark: 1 << 20 })
  s.on('data', (chunk) => { try { p.push(chunk) } catch (e) { err = e; s.destroy() } if (queue.length > 5000) s.pause(); if (wake) { wake(); wake = null } })
  s.on('error', (e) => { err = e; if (wake) { wake(); wake = null } })
  s.on('end', () => { try { p.end() } catch (e) { err = e } done = true; if (wake) { wake(); wake = null } })
  for (;;) {
    if (err) throw err
    if (queue.length) { yield queue.shift(); if (queue.length < 1000 && s.isPaused()) s.resume(); continue }
    if (done) return
    if (s.isPaused()) s.resume()
    await new Promise((r) => { wake = r })
  }
}

// whole text (small inputs and tests only)
export function parseCsv(text) {
  const recs = []
  const p = new CsvParser((r) => recs.push(r))
  p.push(text); p.end()
  if (!recs.length) return []
  const header = recs[0], out = []
  for (let r = 1; r < recs.length; r++) {
    const rec = recs[r]
    if (rec.length === 1 && rec[0] === null && header.length > 1) continue
    if (rec.length !== header.length) throw new Error(`record ${r} has ${rec.length} fields, header has ${header.length}`)
    const o = {}; for (let c = 0; c < header.length; c++) o[header[c]] = rec[c]
    out.push(o)
  }
  Object.defineProperty(out, 'header', { value: header, enumerable: false })
  return out
}
