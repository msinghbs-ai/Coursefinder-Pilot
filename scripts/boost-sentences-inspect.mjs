#!/usr/bin/env node
// CF-247 S660 (S2 - BOOST, Platform Admin 18 Nov 2026 17:02 item 1): read-only inspection of the sentences the Boost study load reader
// takes as a statement for international students, on the stored pages behind Layer 4 Boost study load readings. It asks the worker's
// read-only mode boost_sentences (no model call) and prints each sentence with the load the page check requires and the answer on record.
// Scope (argument 1): international-not-stated (default: readings rule l4-boost-sl-settle-v1 settled as Not stated although the page check
// found such a sentence), open (readings still open), settled (every reading the rule settled). Writes out/boost-sentences.json.
import fs from 'node:fs'
import { need, read, lit, worker, summary } from './boost-live-lib.mjs'
need()
const scope = process.argv[2] || 'international-not-stated'
const WHERE = {
  'international-not-stated': "r.status = 'not_stated' and r.reason like '[rule l4-boost-sl-settle-v1]%' and r.reason like '%international students%'",
  open: "r.status = 'open'",
  settled: "r.status = 'not_stated' and r.reason like '[rule l4-boost-sl-settle-v1]%'",
}[scope]
if (!WHERE) { console.error(`::error::unknown scope ${scope}`); process.exit(2) }
const rows = await read(`select r.id, r.course_id, r.status, r.source_url, e.storage_path, n.prompt_version, n.worker_status, n.answer->>'study_load' as answered, left(n.answer->>'quote', 300) as quote, n.verdict->'problems' as problems,
    (select c.study_load from catalogue.courses c where c.id = r.course_id) as held
  from pipeline.boost_study_load_reviews r
  join pipeline.evidence_artifacts e on e.id = r.evidence_id
  left join lateral (select s.* from pipeline.boost_inbound_staging s where s.lane = 'study_load' and s.entity_id = r.course_id and s.evidence_id is not distinct from r.evidence_id order by s.id desc limit 1) n on true
  where ${WHERE} and e.storage_path is not null order by r.id`)
const out = []
for (let i = 0; i < rows.length; i += 60) {  // the worker's cap of one call
  const chunk = rows.slice(i, i + 60)
  const res = await worker(`jsonb_build_object('mode', 'boost_sentences', 'storage_paths', to_jsonb(array[${chunk.map((x) => lit(x.storage_path)).join(', ')}]::text[]))`)
  if (res.model_calls !== 0) throw Error('the inspection reported a model call')
  chunk.forEach((x, k) => out.push({ ...x, inspection: res.pages?.[k] ?? null, worker: res.worker }))
}
fs.mkdirSync('out', { recursive: true }); fs.writeFileSync('out/boost-sentences.json', JSON.stringify({ scope, at: new Date().toISOString(), items: out }, null, 1))
const cell = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\s+/g, ' ').trim()
const withSentence = out.filter((x) => x.inspection?.international_total > 0)
let md = `### Boost study load: sentences for international students (${scope})\n\n${out.length} readings, ${withSentence.length} with at least one such sentence, ${out.filter((x) => x.inspection?.error).length} pages not read. No model was called.\n\n| Reading | Page | Answer on record | Load the sentences require | Sentence (load it requires) |\n|---|---|---|---|---|\n`
for (const x of out) {
  const ins = x.inspection || {}
  const s = ins.error ? `not read: ${ins.error}` : (ins.international_sentences || []).map((y) => `${cell(y.text)} **(${y.load ?? 'none'})**`).join('<br>') || '(none found now)'
  md += `| ${x.id} | ${cell(x.source_url).slice(0, 110)} | ${cell(x.answered ?? 'not stated')}${x.quote ? `: "${cell(x.quote).slice(0, 160)}"` : ''} | ${cell(ins.required_load ?? '')} | ${s} |\n`
}
await summary(md)
