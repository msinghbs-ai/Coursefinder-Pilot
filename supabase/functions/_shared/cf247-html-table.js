// CF-247 Wave 2 Track B (S2-Build, 18 Nov 2026; Platform Admin 08:19): a deterministic reader for tables on a web page. Shared by the Layer 1
// declarative reader (supabase/functions/_shared/cf247-layer1-read.ts, format html_table), the AI induction mapper's re-infer, and the
// induction wizard's sample upload (src/lib/sample-parse.js), so the sample the mapper sees and the rows the dry run reads come from the same code.
// It scans tags in document order; it evaluates no script, loads nothing and follows no link. Comments, script, style, noscript, template and svg
// are removed first. Each <table> (nested tables included, numbered in the order they open) becomes a grid of text cells: colspan repeats a cell
// across columns and rowspan carries it down, entities are decoded, inner tags are dropped and white space is collapsed. Unclosed cells, rows and
// tables are closed at the next row, table end or end of the page.
const ENTITIES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', ensp: ' ', emsp: ' ', thinsp: ' ', ndash: '–', mdash: '—',
  lsquo: '‘', rsquo: '’', sbquo: '‚', ldquo: '“', rdquo: '”', hellip: '…', bull: '•', middot: '·',
  copy: '©', reg: '®', trade: '™', deg: '°', times: '×', pound: '£', euro: '€', cent: '¢', yen: '¥',
  eacute: 'é', egrave: 'è', ecirc: 'ê', euml: 'ë', aacute: 'á', agrave: 'à', acirc: 'â', auml: 'ä',
  iacute: 'í', icirc: 'î', iuml: 'ï', oacute: 'ó', ocirc: 'ô', ouml: 'ö', uacute: 'ú', ucirc: 'û',
  uuml: 'ü', ccedil: 'ç', ntilde: 'ñ', Eacute: 'É', Egrave: 'È', Aacute: 'Á', Oacute: 'Ó', shy: '',
}
const LIMITS = { tables: 50, cellsPerRow: 300, span: 100, rowspan: 1000, cellChars: 2000 } // fixed: input-safety bounds

export function decodeEntities(s) {
  return String(s ?? '').replace(/&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[A-Za-z][A-Za-z0-9]{1,15});?/g, (m, e) => {
    if (e[0] === '#') {
      const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)
      return Number.isFinite(n) && n > 0 && n < 0x110000 && !(n >= 0xd800 && n <= 0xdfff) ? String.fromCodePoint(n) : m
    }
    return Object.prototype.hasOwnProperty.call(ENTITIES, e) ? ENTITIES[e] : Object.prototype.hasOwnProperty.call(ENTITIES, e.toLowerCase()) ? ENTITIES[e.toLowerCase()] : m
  })
}

const clean = (s) => decodeEntities(s).replace(/[\s ]+/g, ' ').trim().slice(0, LIMITS.cellChars)
const spanOf = (attrs, name, max) => {
  const m = String(attrs || '').match(new RegExp(`\\b${name}\\s*=\\s*["']?\\s*(\\d+)`, 'i'))
  const n = m ? parseInt(m[1], 10) : 1
  return Number.isFinite(n) && n >= 1 ? Math.min(n, max) : 1
}

function strip(html) {
  return String(html ?? '')
    .replace(/<!--[\s\S]*?(-->|$)/g, ' ')
    .replace(/<(script|style|noscript|template|svg)\b[^>]*>[\s\S]*?(<\/\1\s*>|$)/gi, ' ')
}

// a finished table: rows of {cells:[{text, colspan, rowspan, th}], head} → a grid of text with spans resolved
function toGrid(t) {
  const carry = []
  const grid = [], headRows = []
  for (const row of t.rows) {
    const out = []
    let c = 0
    const fill = () => { while (carry[c] && carry[c].left > 0) { out[c] = carry[c].text; carry[c].left--; c++ } }
    for (const cell of row.cells) {
      fill()
      for (let k = 0; k < cell.colspan && c < LIMITS.cellsPerRow; k++, c++) {
        out[c] = cell.text
        if (cell.rowspan > 1) carry[c] = { text: cell.text, left: cell.rowspan - 1 }
      }
    }
    fill()
    for (let i = c; i < carry.length; i++) if (carry[i] && carry[i].left > 0 && out[i] === undefined) { out[i] = carry[i].text; carry[i].left-- }
    const cells = Array.from({ length: out.length }, (_, i) => out[i] ?? '')
    if (!cells.length) continue
    grid.push(cells)
    headRows.push(row.head || (row.cells.length > 0 && row.cells.every((x) => x.th)))
  }
  const width = grid.reduce((w, r) => Math.max(w, r.length), 0)
  for (const r of grid) while (r.length < width) r.push('')
  const firstHead = headRows.indexOf(true)
  return { index: t.index, caption: clean(t.caption), rows: grid, head_rows: headRows, header_row_guess: firstHead >= 0 && firstHead < 5 ? firstHead + 1 : 1, width }
}

// every table on the page, in the order the tables open
export function extractHtmlTables(html, opts = {}) {
  const maxTables = Math.min(Number(opts.maxTables) || LIMITS.tables, LIMITS.tables)
  const maxRows = Number.isFinite(Number(opts.maxRows)) && Number(opts.maxRows) > 0 ? Number(opts.maxRows) : Infinity
  const src = strip(html)
  const done = []
  const stack = []
  let opened = 0
  const top = () => stack[stack.length - 1]
  const closeCell = (t) => { if (t && t.cell) { t.cell.text = clean(t.cell.raw); delete t.cell.raw; t.cell = null } }
  const closeRow = (t) => { if (!t) return; closeCell(t); if (t.row) { if (t.row.cells.length && t.rows.length < maxRows + 10) t.rows.push(t.row); t.row = null } } // fixed: header rows on top of maxRows
  const closeTable = () => { const t = stack.pop(); closeRow(t); if (t.index < maxTables) done.push(toGrid(t)) }
  const re = /<(\/?)([A-Za-z][A-Za-z0-9]*)\b([^>]*)>|([^<]+)|(<)/g
  let m
  while ((m = re.exec(src))) {
    const t = top()
    if (m[4] !== undefined || m[5] !== undefined) {
      const text = m[4] ?? m[5]
      if (t && t.cell) t.cell.raw += text
      else if (t && t.inCaption) t.caption += text
      continue
    }
    const close = m[1] === '/', tag = m[2].toLowerCase(), attrs = m[3]
    if (tag === 'table') {
      if (!close) { stack.push({ index: opened++, rows: [], row: null, cell: null, caption: '', inCaption: false, section: '' }); continue }
      if (stack.length) closeTable()
      continue
    }
    if (!t) continue
    if (tag === 'caption') { t.inCaption = !close; continue }
    if (tag === 'thead' || tag === 'tbody' || tag === 'tfoot') { closeRow(t); t.section = close ? '' : tag; continue }
    if (tag === 'tr') { closeRow(t); if (!close) t.row = { cells: [], head: t.section === 'thead' }; continue }
    if (tag === 'td' || tag === 'th') {
      closeCell(t)
      if (close) continue
      if (!t.row) t.row = { cells: [], head: t.section === 'thead' }
      if (t.row.cells.length >= LIMITS.cellsPerRow) continue
      t.cell = { raw: '', text: '', th: tag === 'th', colspan: spanOf(attrs, 'colspan', LIMITS.span), rowspan: spanOf(attrs, 'rowspan', LIMITS.rowspan) }
      t.row.cells.push(t.cell)
      continue
    }
    // inside a cell, line-level tags separate words
    if (t.cell && /^(br|p|div|li|ul|ol|h[1-6]|dt|dd|tr)$/.test(tag)) t.cell.raw += ' '
  }
  while (stack.length) closeTable()
  return done.sort((a, b) => a.index - b.index).map((x) => ({ ...x, rows: x.rows.slice(0, maxRows + x.header_row_guess) }))
}

// one table as headers and data rows: source.table_index (0 = first table on the page) and source.header_row (1-based; default: the first
// row of header cells, else row 1). Empty header cells are named column_N; a repeated name gets " (2)", " (3)"; data rows that repeat the header
// row, and empty rows, are dropped.
export function htmlTableRows(html, source = {}, maxRows = Infinity) {
  const tables = extractHtmlTables(html)
  if (!tables.length) throw new Error('no table was found on the page')
  const want = Number.isInteger(Number(source.table_index)) ? Number(source.table_index) : 0
  const t = tables.find((x) => x.index === want)
  if (!t) throw new Error(`table ${want} was not found on the page (tables found: ${tables.map((x) => x.index).join(', ')})`)
  const hr = Number.isInteger(Number(source.header_row)) && Number(source.header_row) >= 1 ? Number(source.header_row) : t.header_row_guess
  if (t.rows.length < hr) throw new Error(`table ${want} has no row ${hr} to use as its header`)
  const seen = new Map()
  const headers = t.rows[hr - 1].map((h, i) => {
    let name = h || `column_${i + 1}`
    const n = (seen.get(name) || 0) + 1
    seen.set(name, n)
    if (n > 1) name = `${name} (${n})`
    return name
  })
  const raw = t.rows[hr - 1].join('\u0001')
  const limit = Number.isFinite(maxRows) ? maxRows : Infinity
  const arrays = []
  for (const r of t.rows.slice(hr)) {
    if (arrays.length >= limit) break
    if (r.every((v) => v === '') || r.join('\u0001') === raw) continue
    arrays.push(r)
  }
  return { headers, arrays, table: { index: t.index, caption: t.caption, width: t.width, data_rows: t.rows.length - hr }, tables: tables.map((x) => ({ index: x.index, caption: x.caption, rows: x.rows.length, width: x.width })) }
}

// for a sample: the table with the most data rows, unless a table index is given
export function pickHtmlTable(html, keep = 20) {
  const tables = extractHtmlTables(html).filter((t) => t.width >= 2 && t.rows.length >= 2)
  if (!tables.length) return null
  const best = tables.reduce((a, b) => (b.rows.length - b.header_row_guess > a.rows.length - a.header_row_guess ? b : a))
  const r = htmlTableRows(html, { table_index: best.index }, keep)
  return { ...r, table_index: best.index, header_row: best.header_row_guess, total_rows: best.rows.length - best.header_row_guess }
}
