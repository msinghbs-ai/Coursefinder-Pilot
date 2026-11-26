#!/usr/bin/env node
// CF-247 S742 (S2-BOOST-AER, Platform Admin 19 Nov 2026 05:42 item 3): read-only export of the stored copies behind the entry-matrix reads waiting in Layer 4, as the fixture source
// for the deterministic table chunker (S744, regression suite S745). It lists the waiting entry-matrix items with the machine check's rule, asks the coverage-sweep worker's read-only
// mode entry_inspect (stored copy's title, h1 and raw table markup with its content hash; no model call, no web fetch, no write) for their sources, and writes out/aer-entry-pages.json.
// Argument 1: the rules to export (comma-separated; default gate_incomplete,all_rows_held). Nothing is changed anywhere.
import fs from 'node:fs'
import { need, read, lit, worker, summary } from './boost-live-lib.mjs'
need()
// The read-only database role cannot run security functions (first run, 19 Nov 2026 06:24: "permission denied for function aer_matrix_machine_check_v1"), so the list is taken
// from the tables: every entry-matrix first read waiting in Layer 4, with its run's completeness verdict and dropped rows. Argument 1 is kept for the record only.
const rules = String(process.argv[2] || 'all').split(',').map((s) => s.trim()).filter(Boolean)
// s1253 (S2-AER, 26 Nov 2026): argument 2 selects stored sources (comma-separated entry-matrix source ids, at most 12, each a UUID), and argument 3 a PDF page range ("15-33"; at most 60 pages).
// Only a source the database lists in pipeline.entry_matrix_sources is asked for; the worker returns its stored copy as before, the copy's hash is compared with the hash recorded for it, and nothing
// else is reachable (no path, no bucket listing, no export of a whole document).
const pick = String(process.argv[3] || '').split(',').map((s) => s.trim()).filter(Boolean)
if (pick.length > 12 || pick.some((x) => !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x))) throw Error('source_ids: at most 12 UUIDs')
const range = String(process.argv[4] || '').match(/^(\d{1,4})-(\d{1,4})$/)
const pageFrom = range ? Number(range[1]) : 1, pageTo = range ? Math.min(Number(range[2]), pageFrom + 59) : 60
const items = pick.length
  ? await read(`select null::uuid as item_id, null::uuid as run_id, s.id as source_id, s.url, null::text as rule, 0 as proposed_rows, 0 as dropped_lost,
      (select e.content_hash from pipeline.evidence_artifacts e where e.storage_path like '%' || s.id::text || '%' order by e.captured_at desc limit 1) as recorded_hash,
      (select e.id from pipeline.evidence_artifacts e where e.storage_path like '%' || s.id::text || '%' order by e.captured_at desc limit 1) as evidence_id
    from pipeline.entry_matrix_sources s where s.id in (${pick.map((x) => lit(x)).join(', ')}) order by s.url`)
  : await read(`select i.id as item_id, r.id as run_id, r.source_id, s.url, r.result->'completeness'->>'status' as rule,
    (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed') as proposed_rows,
    jsonb_array_length(coalesce(r.result->'dropped', '[]'::jsonb)) as dropped_lost
  from pipeline.layer4_review_items i join pipeline.entry_matrix_runs r on r.review_item_id = i.id left join pipeline.entry_matrix_sources s on s.id = r.source_id
  where i.status = 'pending' and i.field_code = 'entry_matrix_first_run' and r.source_id is not null order by s.url`)
const pages = []
const step = pick.length ? 1 : 4  // a selected source is asked alone: a PDF's positioned text is large
for (let k = 0; k < items.length; k += step) {  // a small batch keeps one worker answer well under the response size pg_net keeps
  const chunk = items.slice(k, k + step)
  const res = await worker(`jsonb_build_object('mode', 'entry_inspect', 'source_ids', to_jsonb(array[${chunk.map((x) => lit(x.source_id)).join(', ')}]::text[]), 'pages', ${lit(pick.length ? `${pageFrom}-${pageTo}` : '')}, 'links', ${pick.length ? 'true' : 'false'}, 'scope_check', ${pick.length ? 'true' : 'false'}, 'geometry', ${pick.length && pageTo - pageFrom < 3 ? 'true' : 'false'})`)
  if (res.mode !== 'entry_inspect') throw Error('the worker did not answer in mode entry_inspect')
  for (const p of res.pages || []) {
    const it = chunk.find((x) => x.source_id === p.source_id) || null
    if (pick.length && Array.isArray(p.pages)) p.pages = p.pages.filter((q) => q.p >= pageFrom && q.p <= pageTo)
    pages.push({ ...p, item: it, worker: res.worker, workerVersion: res.workerVersion, hash_verified: it && it.recorded_hash ? it.recorded_hash === (p.content_hash || p.sha256) || it.recorded_hash === p.sha256 : null })
  }
}
fs.mkdirSync('out', { recursive: true })
fs.writeFileSync('out/aer-entry-pages.json', JSON.stringify({ rules, at: new Date().toISOString(), items: items.length, pages }, null, 1))
const ok = pages.filter((p) => !p.error)
let md = `### AER entry-matrix stored pages (read only)\n\n${items.length} waiting first reads; ${ok.length} stored copies exported, ${pages.length - ok.length} not read. No model call, no fetch, no write.\n\n| Rule | Source | Tables | Characters | Proposed rows | Dropped |\n|---|---|---|---|---|---|\n`
for (const p of pages) md += `| ${p.item?.rule ?? ''} | ${String(p.url).replace(/\|/g, '/').slice(0, 100)} | ${p.tables ?? p.error ?? ''} | ${p.chars ?? ''} | ${p.item?.proposed_rows ?? ''} | ${p.item?.dropped_lost ?? ''} |\n`
await summary(md)
