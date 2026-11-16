// CF-247 catalogue CSV export (Platform Admin 16 Nov 2026 22:12, Feature 2). One helper for every catalogue list that uses the shared
// DataTable (Providers, Courses, Locations, Scholarships): "Export visible columns" writes the columns in the person's layout, in order, with
// their headings; "Export all columns" writes every field the catalogue read returned. The rows are the active filtered list, every page of it
// (the list is paged on the server, so the export reads the same governed read page by page; nothing beyond the person's role is read).
// RFC 4180: fields with a comma, quote, CR or LF are quoted and quotes doubled; records end with CRLF; null and undefined are empty.
// UTF-8 with a byte order mark so Excel opens accents correctly. A text cell that starts with = + - @ (and is not a number) gets a leading
// apostrophe so a spreadsheet does not run it as a formula.

const BOM = '﻿'
const NEEDS_QUOTES = /[",\r\n]/
const FORMULA_START = /^[=+\-@\t\r]/
const NUMERIC = /^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/

/** The plain text of one value: arrays joined with "; ", objects as JSON, null and undefined empty. */
export function csvText(value) {
  if (value === null || value === undefined) return ''
  if (Array.isArray(value)) return value.map(csvText).filter((v) => v !== '').join('; ')
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? '' : value.toISOString()
  if (typeof value === 'object') { try { return JSON.stringify(value) } catch { return '' } }
  return String(value)
}

/** One RFC 4180 field. */
export function csvCell(value) {
  let s = csvText(value)
  if (typeof value === 'string' && FORMULA_START.test(s) && !NUMERIC.test(s.trim())) s = `'${s}`
  return NEEDS_QUOTES.test(s) ? `"${s.replaceAll('"', '""')}"` : s
}

/** columns: [{ key, label, value?(row) }]. Returns the CSV text with a BOM, a header record and CRLF line ends. */
export function toCsv(rows, columns, { bom = true } = {}) {
  const head = columns.map((c) => csvCell(c.label ?? c.key)).join(',')
  const body = (rows || []).map((r) => columns.map((c) => csvCell(c.value ? c.value(r) : r?.[c.key])).join(','))
  return (bom ? BOM : '') + [head, ...body].join('\r\n') + '\r\n'
}

/** The words of a rendered cell (a React element tree, not mounted): its text children, or else its label, text or title. Used when a
 *  visible column is worked out on screen rather than held under its own key in the row. */
export function elementText(node) {
  if (node === null || node === undefined || typeof node === 'boolean') return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(elementText).filter(Boolean).join(' ')
  const p = node && typeof node === 'object' ? node.props : null
  if (!p) return ''
  const inner = p.children !== undefined ? elementText(p.children) : ''
  const own = [p.label, p.text, p.title].find((v) => typeof v === 'string' && v.trim()) || ''
  return (inner || own).replace(/\s+/g, ' ').trim()
}

const cellValue = (c) => (r) => {
  const raw = r?.[c.key]
  if (raw !== undefined) return raw
  if (typeof c.render !== 'function') return undefined
  try { return elementText(c.render(r)) } catch { return '' }
}

const plainLabel = (c) => (typeof c.label === 'string' && c.label.trim() ? c.label.trim() : String(c.key))

/** The columns to write. mode 'visible': the table's columns in order: a column's csv(row) if it gives one, else the row's own field, else the
 *  words of its rendered cell.
 *  mode 'all': every field key the rows carry, in the order first seen. */
export function exportColumns(tableColumns, mode, rows) {
  if (mode === 'all') {
    const keys = []
    const seen = new Set()
    for (const r of rows || []) for (const k of Object.keys(r || {})) if (!seen.has(k)) { seen.add(k); keys.push(k) }
    return keys.map((k) => ({ key: k, label: k }))
  }
  return (tableColumns || []).filter((c) => c && c.key && !c.noExport).map((c) => ({ key: c.key, label: plainLabel(c), value: c.csv || cellValue(c) }))
}

/** <screen>-<yyyy-mm-dd>.csv, in the person's own date. */
export function csvFilename(screen, date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0')
  const slug = String(screen || 'export').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'export'
  return `${slug}-${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}.csv`
}

/** Reads every page of a paged read. readPage(offset, limit) returns { rows, total }. Stops when the total is reached, a page is empty, or
 *  the signal is aborted (then it throws 'export_cancelled'). onProgress(done, total) after each page. The page size asked for is the read's
 *  own maximum; the server may return fewer, and the next page starts after what came back. */
export async function readAllPages(readPage, { pageSize, onProgress, signal } = {}) {
  const out = []
  let total = Infinity
  while (out.length < total) {
    if (signal?.aborted) throw new Error('export_cancelled')
    const { rows, total: t } = await readPage(out.length, pageSize)
    if (Number.isFinite(Number(t))) total = Number(t)
    if (!rows || !rows.length) break
    out.push(...rows)
    onProgress?.(out.length, Number.isFinite(total) ? total : out.length)
  }
  return out
}

/** Saves the text as a file in the browser. */
export function downloadCsv(text, filename) {
  const blob = new Blob([text], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
