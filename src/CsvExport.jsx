// CF-247 catalogue CSV export control (Platform Admin 16 Nov 2026 22:12, Feature 2): one control for every catalogue list on the shared table.
// Export CSV opens two choices: Export visible columns (the columns shown, in order) and Export all columns (every field the list's read
// returns). Both write the whole filtered list, not only the page on screen: the list is read again page by page through the same governed
// read, with progress and a Cancel. Helper and rules: src/lib/csv-export.js.
import React, { useEffect, useRef, useState } from 'react'
import { Download } from 'lucide-react'
import { csvFilename, downloadCsv, exportColumns, readAllPages, toCsv } from './lib/csv-export'
import { fmtNumber } from './ui-kit'

const fmt = (n) => fmtNumber(Number(n || 0))

export function CsvExport({ screen, columns, readPage, pageSize, total = 0, onError, disabled = false }) {
  const [open, setOpen] = useState(false)
  const [run, setRun] = useState(null) // { mode, done, total }
  const ctrl = useRef(null)
  const ref = useRef(null)
  useEffect(() => {
    if (!open) return undefined
    const close = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }
    addEventListener('mousedown', close)
    return () => removeEventListener('mousedown', close)
  }, [open])
  useEffect(() => () => ctrl.current?.abort(), [])

  async function start(mode) {
    setOpen(false)
    const ac = new AbortController()
    ctrl.current = ac
    setRun({ mode, done: 0, total })
    try {
      const rows = await readAllPages(readPage, { pageSize, signal: ac.signal, onProgress: (done, t) => setRun({ mode, done, total: t }) })
      if (ac.signal.aborted) return
      downloadCsv(toCsv(rows, exportColumns(columns, mode, rows)), csvFilename(mode === 'all' ? `${screen}-all-columns` : screen))
    } catch (e) {
      if (String(e?.message) !== 'export_cancelled') onError?.(`CSV export failed: ${e?.message || e}`)
    } finally {
      if (ctrl.current === ac) ctrl.current = null
      setRun(null)
    }
  }

  if (run) {
    return <span className="csv-export is-running" role="status" data-csv-export-running={run.mode}>
      <span className="m-spinner tiny" />Exporting {fmt(run.done)} of {fmt(run.total)}…
      <button type="button" className="m-secondary compact" onClick={() => ctrl.current?.abort()}>Cancel</button>
    </span>
  }
  return <span className="csv-export" ref={ref} data-csv-export={screen}>
    <button type="button" className="m-secondary compact" aria-haspopup="menu" aria-expanded={open} disabled={disabled || !total}
      title={total ? `Download the ${fmt(total)} matching rows as a CSV file (Excel opens it)` : 'No rows to export'} onClick={() => setOpen((x) => !x)}>
      <Download size={14} />Export CSV
    </button>
    {open && <span className="csv-export-menu" role="menu">
      <button type="button" role="menuitem" data-csv-export-mode="visible" onClick={() => start('visible')}>
        <strong>Export visible columns</strong><small>The columns shown, in this order · {fmt(total)} rows</small>
      </button>
      <button type="button" role="menuitem" data-csv-export-mode="all" onClick={() => start('all')}>
        <strong>Export all columns</strong><small>Every field the list holds · {fmt(total)} rows</small>
      </button>
    </span>}
  </span>
}
