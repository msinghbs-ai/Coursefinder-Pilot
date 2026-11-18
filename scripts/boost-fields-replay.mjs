#!/usr/bin/env node
// CF-247 S663 (S2 - BOOST, Platform Admin 18 Nov 2026 17:02 item 3): the offline qualification replay of Boost multi-field reading. The gold
// set is built from the catalogue itself, with no hand labelling: courses that already hold an admitted value (active intakes, an active
// provider-page annual tuition fee, a description) and have a stored course page. The worker's mode boost_fields_replay reads each stored
// page as the live mode does (same sections, prompt and the route's one model) and returns the checked answers; nothing is staged or
// admitted. This script compares each verified answer with the held value and prints the figures per field. It qualifies nothing by
// itself: a qualification is a separate, recorded decision.
// Arguments: pages per stratum (default 40), label (default the date). Writes out/boost-fields-replay.json.
import fs from 'node:fs'
import { need, read, lit, worker, summary } from './boost-live-lib.mjs'
need()
const PER = Math.max(4, Math.min(120, Number(process.argv[2]) || 40)), LABEL = String(process.argv[3] || new Date().toISOString().slice(0, 10)).replace(/[^a-z0-9-]/gi, '').slice(0, 40)
const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december']
// one stored page per course; at most three courses of a provider in a stratum; the order is fixed by the label, so a run can be repeated
const gold = await read(`with pt as (
    select distinct on (e.entity_id) e.entity_id as course_id, e.storage_path from pipeline.evidence_artifacts e
     where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null order by e.entity_id, e.captured_at desc),
  g as (
    select pt.course_id, pt.storage_path, c.provider_id, c.display_title, (coalesce(c.description, '') <> '') as has_description,
      (select array_agg(distinct extract(month from i.start_date)::int) from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active' and i.start_date is not null) as intake_months,
      (select jsonb_agg(distinct jsonb_build_object('amount', f.amount, 'currency', trim(f.currency_code), 'year', f.fee_year)) from catalogue.course_fees f
        where f.course_id = c.id and f.audience = 'international' and f.fee_type = 'provider_current_tuition' and f.basis = 'annual' and f.status = 'active' and f.amount > 0) as fees
    from pt join catalogue.courses c on c.id = pt.course_id),
  s as (
    select g.*, x.stratum, row_number() over (partition by x.stratum, g.provider_id order by md5(g.course_id::text || ${lit(LABEL)})) as rp, md5(g.course_id::text || ${lit(LABEL)}) as k
    from g cross join lateral (values ('intakes', g.intake_months is not null), ('course_fees', g.fees is not null), ('course_description', g.has_description)) x(stratum, holds) where x.holds),
  p as (select s.*, row_number() over (partition by s.stratum order by s.k) as rs from s where s.rp <= 3)
  select course_id, storage_path, display_title, stratum, intake_months, fees, has_description from p where rs <= ${PER} order by stratum, k`)
const pages = new Map()
for (const g of gold) { const p = pages.get(g.course_id) || { ...g, strata: [] }; p.strata.push(g.stratum); pages.set(g.course_id, p) }
const list = [...pages.values()], results = [], LANES = ['course_description', 'intakes', 'course_fees']
let cost = 0, worker_name = null, model = null, versions = null
for (let i = 0; i < list.length; i += 24) {  // the worker's cap of one call
  const chunk = list.slice(i, i + 24)
  const items = chunk.map((x) => `jsonb_build_object('ref', ${lit(x.course_id)}, 'storage_path', ${lit(x.storage_path)}, 'title', ${lit(String(x.display_title || '').slice(0, 200))}, 'lanes', '${JSON.stringify(LANES)}'::jsonb)`)
  const res = await worker(`jsonb_build_object('mode', 'boost_fields_replay', 'items', jsonb_build_array(${items.join(', ')}))`)
  if (res.skipped) { await summary(`Replay stopped: ${res.skipped}`); break }
  cost += Number(res.cost) || 0; worker_name = res.worker; model = res.model; versions = { prompt: res.prompt_version, check: res.check_version }
  for (const r of res.results || []) results.push(r)
}
const by = new Map(results.filter(Boolean).map((r) => [r.ref, r]))
const tally = {}; const bump = (lane, k) => { tally[lane] ??= {}; tally[lane][k] = (tally[lane][k] || 0) + 1 }
const samples = []
for (const p of list) {
  const r = by.get(p.course_id)
  for (const lane of LANES) {
    const holds = lane === 'intakes' ? !!p.intake_months : lane === 'course_fees' ? !!p.fees : !!p.has_description
    const f = (r?.fields || []).find((x) => x.lane === lane)
    if (!r || r.status === 'failed' || r.status === 'given_back') { bump(lane, holds ? 'gold_call_failed' : 'other_call_failed'); continue }
    const st = f?.status || 'not_stated'
    if (!holds) { bump(lane, `no_gold_${st}`); continue }
    bump(lane, 'gold'); bump(lane, `gold_${st}`)
    if (st !== 'verified') continue
    let agree = null
    if (lane === 'intakes') { const got = (f.value || []).map((m) => MONTHS.indexOf(String(m).toLowerCase()) + 1); agree = got.length > 0 && got.every((m) => p.intake_months.includes(m)); if (agree && got.length === new Set(p.intake_months).size) bump(lane, 'gold_exact') }
    else if (lane === 'course_fees') agree = p.fees.some((g) => Math.abs(Number(g.amount) - Number(f.value?.amount)) < 0.5 && (!f.value?.currency || g.currency === f.value.currency))
    if (agree === null) continue  // a description has no value to compare: its figure is the page check's pass rate
    bump(lane, agree ? 'gold_agree' : 'gold_disagree')
    if (!agree && samples.length < 30) samples.push({ lane, course_id: p.course_id, held: lane === 'intakes' ? p.intake_months : p.fees, answered: f.value, quote: String(f.quote || '').slice(0, 200) })
  }
}
fs.mkdirSync('out', { recursive: true })
fs.writeFileSync('out/boost-fields-replay.json', JSON.stringify({ label: LABEL, per_stratum: PER, pages: list.length, model, worker: worker_name, versions, cost, tally, samples, results }, null, 1))
const n = (lane, k) => tally[lane]?.[k] || 0, pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : 'n/a')
let md = `### Boost multi-field replay (${LABEL})\n\n${list.length} stored pages of courses that already hold a value, model ${model}, prompt ${versions?.prompt}, page check ${versions?.check}, worker ${worker_name}, cost US$${cost.toFixed(4)}. Nothing was staged or admitted.\n\n| Field | Pages holding a value | Verified | Refused | Not stated | Call failed | Verified and agrees with the held value | Disagrees | Agreement of verified |\n|---|---|---|---|---|---|---|---|---|\n`
for (const lane of LANES) md += `| ${lane} | ${n(lane, 'gold')} | ${n(lane, 'gold_verified')} | ${n(lane, 'gold_rejected')} | ${n(lane, 'gold_not_stated')} | ${n(lane, 'gold_call_failed')} | ${lane === 'course_description' ? 'not compared' : n(lane, 'gold_agree')} | ${lane === 'course_description' ? 'not compared' : n(lane, 'gold_disagree')} | ${lane === 'course_description' ? 'n/a' : pct(n(lane, 'gold_agree'), n(lane, 'gold_agree') + n(lane, 'gold_disagree'))} |\n`
md += `\nDeadlines: not asked. The Boost fields prompt has no deadline field, so there is no answer to replay.\n`
if (samples.length) md += `\n**Disagreements (first ${samples.length})**\n\n| Field | Held | Answered | Quote |\n|---|---|---|---|\n` + samples.map((s) => `| ${s.lane} | ${JSON.stringify(s.held).slice(0, 120)} | ${JSON.stringify(s.answered).replace(/\|/g, '/').slice(0, 160)} | ${s.quote.replace(/\|/g, '/').replace(/\s+/g, ' ')} |`).join('\n') + '\n'
await summary(md)
