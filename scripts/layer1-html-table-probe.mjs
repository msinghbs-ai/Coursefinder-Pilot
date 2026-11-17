#!/usr/bin/env node
// CF-247 Wave 2 Track B (S2-Build, 18 Nov 2026): read-only probe of the HTML table extractor against a live page. Prints each table found
// (index, caption, rows, width, header guess) and the first rows of the table the wizard would pick. Writes nothing anywhere.
// Usage: node scripts/layer1-html-table-probe.mjs <https address> [table_index]
import { extractHtmlTables, pickHtmlTable, htmlTableRows } from '../supabase/functions/_shared/cf247-html-table.js'

const url = process.argv[2]
if (!/^https:\/\//i.test(url || '')) { console.error('usage: layer1-html-table-probe.mjs <https address> [table_index]'); process.exit(2) }
const r = await fetch(url, { redirect: 'follow', headers: { 'user-agent': 'coursefinder-layer1-declarative/1.0' } })
if (!r.ok) { console.error(`HTTP ${r.status} from ${url}`); process.exit(1) }
const html = await r.text()
const tables = extractHtmlTables(html)
console.log(`${url}: ${html.length} characters, ${tables.length} table(s)`)
for (const t of tables) console.log(`  table ${t.index}: ${t.rows.length} rows x ${t.width} columns, header row ${t.header_row_guess}${t.caption ? `, caption "${t.caption.slice(0, 80)}"` : ''}`)
const pick = process.argv[3] !== undefined ? { ...htmlTableRows(html, { table_index: Number(process.argv[3]) }, 5), table_index: Number(process.argv[3]) } : pickHtmlTable(html, 5)
if (!pick) { console.log('no table with two or more columns and rows to sample'); process.exit(0) }
console.log(`sample table ${pick.table_index}: headers ${JSON.stringify(pick.headers)}`)
for (const row of pick.arrays) console.log(`  ${JSON.stringify(row)}`)
if (process.env.GITHUB_STEP_SUMMARY) {
  const fs = await import('node:fs')
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `### ${url}\n${tables.length} table(s); sample table ${pick.table_index}: ${pick.headers.length} columns, ${pick.total_rows ?? pick.table?.data_rows} data rows\n\n`)
}
