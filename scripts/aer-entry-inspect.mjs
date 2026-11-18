#!/usr/bin/env node
// CF-247 S742 (S2-BOOST-AER, Platform Admin 19 Nov 2026 05:42 item 3): read-only export of the stored copies behind the entry-matrix reads waiting in Layer 4, as the fixture source
// for the deterministic table chunker (S744, regression suite S745). It lists the waiting entry-matrix items with the machine check's rule, asks the coverage-sweep worker's read-only
// mode entry_inspect (stored copy's title, h1 and raw table markup with its content hash; no model call, no web fetch, no write) for their sources, and writes out/aer-entry-pages.json.
// Argument 1: the rules to export (comma-separated; default gate_incomplete,all_rows_held). Nothing is changed anywhere.
import fs from 'node:fs'
import { need, read, lit, worker, summary } from './boost-live-lib.mjs'
need()
const rules = String(process.argv[2] || 'gate_incomplete,all_rows_held').split(',').map((s) => s.trim()).filter(Boolean)
const items = await read(`select i.id as item_id, c->>'rule' as rule, (c->'checks'->>'run_id') as run_id, (c->'checks'->>'source_id') as source_id, c->'checks'->>'source_url' as url,
    (select count(*) from catalogue.provider_entry_matrix m where m.run_id = (c->'checks'->>'run_id')::uuid and m.status = 'proposed') as proposed_rows,
    (c->'checks'->'gate'->>'read_rows')::int as read_rows, jsonb_array_length(coalesce(c->'checks'->'gate'->'dropped_lost', '[]'::jsonb)) as dropped_lost
  from (select i.*, security.aer_matrix_machine_check_v1(i.id) c from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'entry_matrix_first_run') i
  where c->>'rule' in (${rules.map(lit).join(', ')}) and c->'checks'->>'source_id' is not null order by c->>'rule', c->'checks'->>'source_url'`)
const pages = []
for (let k = 0; k < items.length; k += 4) {  // a small batch keeps one worker answer well under the response size pg_net keeps
  const chunk = items.slice(k, k + 4)
  const res = await worker(`jsonb_build_object('mode', 'entry_inspect', 'source_ids', to_jsonb(array[${chunk.map((x) => lit(x.source_id)).join(', ')}]::text[]))`)
  if (res.mode !== 'entry_inspect') throw Error('the worker did not answer in mode entry_inspect')
  for (const p of res.pages || []) pages.push({ ...p, item: chunk.find((x) => x.source_id === p.source_id) || null, worker: res.worker })
}
fs.mkdirSync('out', { recursive: true })
fs.writeFileSync('out/aer-entry-pages.json', JSON.stringify({ rules, at: new Date().toISOString(), items: items.length, pages }, null, 1))
const ok = pages.filter((p) => !p.error)
let md = `### AER entry-matrix stored pages (read only)\n\n${items.length} waiting items (${rules.join(', ')}); ${ok.length} stored copies exported, ${pages.length - ok.length} not read. No model call, no fetch, no write.\n\n| Rule | Source | Tables | Characters | Proposed rows | Dropped |\n|---|---|---|---|---|---|\n`
for (const p of pages) md += `| ${p.item?.rule ?? ''} | ${String(p.url).replace(/\|/g, '/').slice(0, 100)} | ${p.tables ?? p.error ?? ''} | ${p.chars ?? ''} | ${p.item?.proposed_rows ?? ''} | ${p.item?.dropped_lost ?? ''} |\n`
await summary(md)
