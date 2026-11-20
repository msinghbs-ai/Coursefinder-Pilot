#!/usr/bin/env node
// CF-247 S815 (S1-AER, Platform Admin 20 Nov 2026 10:51 AEDT): runs the deterministic academic entry reader (no English test) over stored course pages that have none read yet, in small keyset batches.
// $0: no model, no Firecrawl. Pages are sent to the coverage-sweep worker mode aer_det_read (read only); the shadow readings are recorded by security.aer_det_record_v2. Nothing is admitted.
// Arguments: 1 = mode (status | run), 2 = pages to read this run (run only), 3 = country filter (AU, NZ, CA or all).
import { need, read, lit, worker, summary } from './boost-live-lib.mjs'
import { writeFileSync } from 'node:fs'
need()
const mode = process.argv[2] || 'status', total = Math.max(0, Number(process.argv[3] || 0)), country = String(process.argv[4] || 'all').toUpperCase()
const conc = Math.min(12, Math.max(1, Number(process.argv[5] || 6))) // fixed: bound on parallel worker calls (an operator input of the workflow, default 6)
const ctry = country === 'ALL' ? '' : `and co.iso_alpha2 = ${lit(country)}`
const V = 'aer-det-v1.3'
const base = `from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
  join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id
  join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
 where g.evidence_id is not null and g.read_status is not null ${ctry}
   and not exists (select 1 from catalogue.course_entry_requirements r where r.course_id = c.id and r.status = 'active')`
const status = async () => (await read(`select
  (select count(*) ${base}) as stored_pages_no_active_rule,
  (select count(*) ${base} and exists (select 1 from pipeline.aer_det_academic_pages d where d.course_id = g.course_id and d.evidence_id = g.evidence_id and d.extractor = ${lit(V)})) as pages_read,
  (select count(*) from pipeline.aer_det_academic_readings where extractor = ${lit(V)}) as readings,
  (select coalesce(jsonb_object_agg(test_key, n), '{}'::jsonb) from (select test_key, count(*) n from pipeline.aer_det_academic_readings where extractor = ${lit(V)} group by 1) z) as by_key,
  (select count(distinct course_id) from pipeline.aer_det_academic_readings where extractor = ${lit(V)}) as courses_with_a_reading,
  security.pipeline_num_v1('batch.aer_det_read', 20) as per_call`))[0]
const before = await status()
let md = `### Deterministic entry reader (${mode}, ${country})\n\nStored pages of courses with no active rule: ${before.stored_pages_no_active_rule}; read so far ${before.pages_read}; shadow readings ${before.readings}; courses with a reading ${before.courses_with_a_reading}; by test ${JSON.stringify(before.by_key)}.\n`
if (mode === 'run') {
  const per = Math.min(40, Math.max(5, Number(before.per_call) || 20)); let done = 0, wrote = 0, failed = 0, last = '00000000-0000-0000-0000-000000000000'; const t0 = Date.now(), sample = [], tm = { read: 0, worker: 0, record: 0 }
  const lap = async (k, f) => { const t = Date.now(); try { return await f() } finally { tm[k] += Date.now() - t } }
  const one = async (items) => {
    const res = await lap('worker', () => worker(`jsonb_build_object('mode', 'aer_det_read', 'items', ${lit(JSON.stringify(items))}::jsonb)`))
    if (res.mode !== 'aer_det_read' || res.extractor !== V) throw Error(`the worker did not answer in mode aer_det_read with extractor ${V} (${res.mode} ${res.extractor})`)
    const good = res.pages.filter((p) => !p.error); failed += res.pages.length - good.length
    for (const p of good.slice(0, 2)) for (const r of p.readings.slice(0, 2)) if (sample.length < 40) sample.push({ course_id: p.course_id, ...r })
    if (good.length) { const r = await lap('record', () => call(`select security.aer_det_record_v2(${lit(JSON.stringify(good.map((p) => ({ ...p, extractor: res.extractor }))))}::jsonb) as r`)); wrote += r.pages }
    return good.length
  }
  // a block of conc x per pages is read with one indexed keyset query, then sent as conc calls at the same time; a page the worker could not read is left for the next run (counted)
  while (done < total && Date.now() - t0 < 50 * 60 * 1000) {
    const items = await lap('read', () => read(`select g.course_id, g.evidence_id, e.storage_path ${base}
      and g.course_id > ${lit(last)}
      and not exists (select 1 from pipeline.aer_det_academic_pages d where d.course_id = g.course_id and d.evidence_id = g.evidence_id and d.extractor = ${lit(V)})
      order by g.course_id limit ${Math.min(per * conc, total - done)}`))
    if (!items.length) break
    last = items[items.length - 1].course_id
    const chunks = []; for (let i = 0; i < items.length; i += per) chunks.push(items.slice(i, i + per))
    const ok = await Promise.all(chunks.map(one))
    done += items.length
    if (ok.every((n) => n === 0)) break
  }
  md += `\nTime by step (ms, summed over parallel calls): database read ${tm.read}, worker ${tm.worker}, record ${tm.record}; ${conc} calls at once.\n`
  md += `\nRun: ${done} pages sent, ${wrote} recorded, ${failed} not read (left for the next run), ${Math.round((Date.now() - t0) / 1000)} s.\n`
  writeFileSync('aer-det-sample.json', JSON.stringify(sample, null, 1))
}
const after = await status()
md += `\nAfter: pages read ${after.pages_read} of ${after.stored_pages_no_active_rule}; shadow readings ${after.readings} on ${after.courses_with_a_reading} courses; by test ${JSON.stringify(after.by_key)}.\n`
await summary(md); console.log(md)

async function call(sql) { const r = await fetch(`https://api.supabase.com/v1/projects/${process.env.REF}/database/query`, { method: 'POST', headers: { authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ query: sql }) }); const t = await r.text(); if (!r.ok) throw Error(`database query failed (HTTP ${r.status}): ${t.slice(0, 400)}`); return JSON.parse(t)[0].r }
