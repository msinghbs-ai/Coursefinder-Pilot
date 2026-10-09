// v2.15.227 (Platform Admin, 9 Oct 2026: "modern UI standardised through the app"): every table on every page gets the
// same column resizing as the catalogue lists. Drag the right edge of a heading to resize (double-click to reset). The
// first drag fixes the table's current column widths so only the dragged column changes. Widths are remembered per page
// and table in this browser only. Lists built with DataTable (m-fit-table) keep their own handles; any table can opt out
// with data-no-resize.
const KEY = 'cf-tw:'
const signature = table => [...table.querySelectorAll(':scope > thead > tr:first-child > th')].map(th => (th.textContent || '').trim().toLowerCase()).join('|')
const storageKey = table => `${KEY}${(location.hash || '#').split('?')[0]}:${signature(table)}`
const load = table => { try { return JSON.parse(localStorage.getItem(storageKey(table)) || 'null') } catch { return null } }
const save = (table, widths) => { try { localStorage.setItem(storageKey(table), JSON.stringify(widths)) } catch {} }
const forget = table => { try { localStorage.removeItem(storageKey(table)) } catch {} }
const heads = table => [...table.querySelectorAll(':scope > thead > tr:first-child > th')]

function freeze(table, widths) {
  const ths = heads(table)
  const w = widths || ths.map(th => Math.round(th.getBoundingClientRect().width))
  ths.forEach((th, i) => { th.style.width = `${w[i]}px` })
  table.style.tableLayout = 'fixed'
  table.style.width = `${w.reduce((a, b) => a + b, 0)}px`
  table.style.minWidth = '0'
  table.dataset.resized = '1'
  return w
}
function unfreeze(table) {
  heads(table).forEach(th => { th.style.width = '' })
  table.style.tableLayout = ''; table.style.width = ''; table.style.minWidth = ''
  delete table.dataset.resized
}

function enhance(table) {
  if (table.classList.contains('m-fit-table') || table.hasAttribute('data-no-resize')) return
  const ths = heads(table)
  if (ths.length < 2) return
  const sig = signature(table)
  if (table.dataset.resizeSig !== sig) { // first sight, or React rebuilt the headings
    table.dataset.resizeSig = sig
    const saved = load(table)
    if (Array.isArray(saved) && saved.length === ths.length) freeze(table, saved)
  }
  ths.forEach((th, i) => {
    if (th.querySelector(':scope > .m-col-resize')) return
    if (getComputedStyle(th).position === 'static') th.style.position = 'relative'
    const h = document.createElement('span')
    h.className = 'm-col-resize'
    h.setAttribute('role', 'separator'); h.setAttribute('aria-orientation', 'vertical')
    h.setAttribute('aria-label', `Resize column ${i + 1}`) // not the heading text, so the heading keeps its own label
    h.title = 'Drag to resize · double-click to reset'
    h.dataset.colResize = String(i)
    h.addEventListener('click', e => e.stopPropagation())
    h.addEventListener('dblclick', e => { e.stopPropagation(); unfreeze(table); forget(table) })
    h.addEventListener('pointerdown', e => {
      e.preventDefault(); e.stopPropagation()
      const widths = freeze(table, table.dataset.resized ? heads(table).map(x => Math.round(x.getBoundingClientRect().width)) : null)
      const x0 = e.clientX, w0 = widths[i]
      const move = ev => { widths[i] = Math.max(56, Math.round(w0 + ev.clientX - x0)); freeze(table, widths) }
      const up = () => { removeEventListener('pointermove', move); removeEventListener('pointerup', up); save(table, widths) }
      addEventListener('pointermove', move); addEventListener('pointerup', up)
    })
    th.appendChild(h)
  })
}

/** Watches the page and adds resize handles to tables as they appear. Returns a stop function. */
export function startTableResize(root = document.body) {
  if (typeof MutationObserver === 'undefined') return () => {}
  let frame = 0
  const run = () => { frame = 0; root.querySelectorAll('table').forEach(enhance) }
  const schedule = () => { if (!frame) frame = requestAnimationFrame(run) }
  const mo = new MutationObserver(schedule)
  mo.observe(root, { childList: true, subtree: true })
  schedule()
  return () => { mo.disconnect(); if (frame) cancelAnimationFrame(frame) }
}
