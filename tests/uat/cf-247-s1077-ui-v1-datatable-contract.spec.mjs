// Guards: UI/UX Unification & Live Guide Parity Plan v1.2, Slice 4 (s1077): the shared catalogue table and the empty-state pill are on the v1.1 build; ui-* classes only, no browser storage in the view, one empty-state pill for every screen.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const read = f => fs.readFileSync(f, 'utf8')

test('s1077: the shared catalogue table is a ui-v1 view with ui-* classes and no browser storage', () => {
  const v = read('src/ui-v1/DataTableView.jsx')
  expect(v).toMatch(/import\s*\{\s*EmptyInline\s*\}\s*from\s*'\.\/kit\.jsx'/)
  expect(v).not.toMatch(/localStorage|from\s*'\.\/ui-kit'|<style|#[0-9a-fA-F]{6}\b/)
  expect(v).not.toMatch(/\bm-(table|fit-table|fluid-table|table-wrap|col-resize|skeleton-row|row-skeleton|empty-row)\b/)
  for (const c of ['ui-tablewrap ui-datatable', 'ui-table ui-fit-table', 'ui-col-resize', 'ui-skeleton-row', 'ui-empty-row', 'data-col-resize', "tableLayout:'fixed'", 'data-skeleton', 'data-empty']) expect(v, c).toContain(c)
  const w = read('src/lib/column-widths.js')
  expect(w).toContain('cf-colw:') // the saved widths keep their key, so every saved layout carries over
})

test('s1077: DataTable.jsx keeps its public names and every screen still imports them from there', () => {
  const d = read('src/DataTable.jsx')
  expect(d).toContain("export{DataTable,useColumnWidths}")
  expect(d).toContain('export function FilterSelect')
  expect(d).not.toMatch(/export function (DataTable|useColumnWidths)/)
  for (const f of ['src/AerWorkspace.jsx', 'src/Layer4Grid.jsx', 'src/mature-main.jsx']) expect(read(f), f).toMatch(/from'\.\/DataTable'/)
})

test('s1077: one empty-state pill serves the whole app', () => {
  expect(read('src/ui-kit.jsx')).toContain("export{EmptyInline}from'./ui-v1/kit.jsx'")
  expect(read('src/ui-kit.jsx')).not.toContain('m-empty-inline')
  expect(read('src/ui-v1/kit.jsx')).toMatch(/export function EmptyInline[^\n]*ui-emptyline[^\n]*<Database/)
})

test('s1077: the table styles are in the ui-v1 stylesheet, tokens only, and the resize helper leaves the table to its own handles', () => {
  const css = read('src/ui-v1/ui-kit.css')
  for (const c of ['.ui-datatable', '.ui-col-resize', '.ui-skeleton-bar', '.ui-sticky-col', '.is-selected']) expect(css, c).toContain(c)
  expect(read('src/table-resize.js')).toContain("table.classList.contains('ui-fit-table')")
  expect(read('src/catalogue-columns.css')).toContain('.ccol-frame{')
})
