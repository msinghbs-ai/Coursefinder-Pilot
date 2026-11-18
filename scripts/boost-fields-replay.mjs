#!/usr/bin/env node
// CF-247 S663 (S2 - BOOST, Platform Admin 18 Nov 2026 17:02 item 3): the offline qualification replay of Boost multi-field reading. The gold
// set is built from the catalogue itself, with no hand labelling: courses that already hold an admitted value (active intakes, an active
// provider-page annual tuition fee, a description) and have a stored course page. The worker's mode boost_fields_replay reads each stored
// page as the live mode does (same sections, prompt and the route's one model) and returns the checked answers; nothing is staged or
// admitted. This script compares each verified answer with the held value and prints the figures per field. It qualifies nothing by
// itself: a qualification is a separate, recorded decision.
// S665 (S2-Courses, Platform Admin 18 Nov 2026 21:59 item 4): a fee answer is compared with held fees of the same basis only. The page period "year" is compared with the
// provider's annual fees (basis annual, indicative_annual, current indicative annual international tuition) and "total" with whole-course totals (provider
// basis total_indicative, and the registered whole-course tuition); an answer in another period (semester, credit point, unit) is counted as not comparable,
// and an answer whose basis the course holds no fee for is counted as no gold of that basis, never as a disagreement.
// S723/S724/S726 (S2-BOOST, Platform Admin 19 Nov 2026 05:40): (1) intakes: the page's announced start months are all captured, and a held primary intake
// that is a subset of them (or they of it) agrees; only months that share no containment disagree. (2) Pages per stratum can be set per stratum
// ("intakes=60,course_fees=160,course_fees_total=60,course_description=40,application_deadlines=40"); the whole-course total stratum also takes the
// registered whole-course totals; a fee agrees only on the same basis (period), currency (the answer must name one) and year (the answer's year, or
// the latest held year when the answer gives none). (3) application_deadlines are compared with held course intake application deadlines.
// (4) The run stops before US$ MAX_COST (argument 4, default 0.15). A field passes when at least 100 verified answers compared, agreement is at
// least 95% and no verified answer disagrees.
// Arguments: pages per stratum (a number, or stratum=n pairs), label (default the date), max cost in US$. Writes out/boost-fields-replay.json.
import fs from 'node:fs'
import { need, read, lit, worker, summary } from './boost-live-lib.mjs'
need()
const STRATA = ['intakes', 'course_fees', 'course_fees_total', 'course_description', 'application_deadlines']
const perArg = String(process.argv[2] || '40'), PER_OF = {}
for (const st of STRATA) PER_OF[st] = /^\d+$/.test(perArg) ? Number(perArg) : 0
for (const kv of perArg.split(',')) { const [k, v] = kv.split('='); if (STRATA.includes(k) && Number(v) > 0) PER_OF[k] = Number(v) }
for (const st of STRATA) PER_OF[st] = Math.max(0, Math.min(200, PER_OF[st]))  // fixed: largest stratum of one replay
const PER = Math.max(...Object.values(PER_OF)), MAX_COST = Math.min(1, Math.max(0.01, Number(process.argv[4]) || 0.15)), LABEL = String(process.argv[3] || new Date().toISOString().slice(0, 10)).replace(/[^a-z0-9-]/gi, '').slice(0, 40)
const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december']
// one stored page per course; at most three courses of a provider in a stratum; the order is fixed by the label, so a run can be repeated
const gold = await read(`with pt as (
    select distinct on (e.entity_id) e.entity_id as course_id, e.storage_path from pipeline.evidence_artifacts e
     where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null order by e.entity_id, e.captured_at desc),
  g as (
    select pt.course_id, pt.storage_path, c.provider_id, c.display_title, (coalesce(c.description, '') <> '') as has_description,
      (select array_agg(distinct extract(month from i.start_date)::int) from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active' and i.start_date is not null) as intake_months,
      (select array_agg(distinct to_char(i.application_deadline, 'YYYY-MM-DD')) from catalogue.course_intakes i where i.course_id = c.id and i.status = 'active' and i.application_deadline is not null) as deadlines,
      (select jsonb_agg(distinct jsonb_build_object('amount', f.amount, 'currency', trim(f.currency_code), 'year', f.fee_year, 'period', case when f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition') then 'year' else 'total' end))
        from catalogue.course_fees f where f.course_id = c.id and f.audience = 'international' and f.status = 'active' and f.amount > 0
          and ((f.fee_type = 'provider_current_tuition' and f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition', 'total_indicative')) or (f.fee_type in ('tuition', 'estimated_total_course_cost') and f.basis = 'registered_total_course'))) as fees,
      exists (select 1 from catalogue.course_fees f where f.course_id = c.id and f.audience = 'international' and f.status = 'active' and f.amount > 0
              and ((f.fee_type = 'provider_current_tuition' and f.basis = 'total_indicative') or (f.fee_type in ('tuition', 'estimated_total_course_cost') and f.basis = 'registered_total_course'))) as has_total_fee
    from pt join catalogue.courses c on c.id = pt.course_id),
  s as (
    select g.*, x.stratum, row_number() over (partition by x.stratum, g.provider_id order by md5(g.course_id::text || ${lit(LABEL)})) as rp, md5(g.course_id::text || ${lit(LABEL)}) as k
    from g cross join lateral (values ('intakes', g.intake_months is not null), ('course_fees', g.fees is not null and exists (select 1 from jsonb_array_elements(g.fees) e where e->>'period' = 'year')), ('course_fees_total', g.has_total_fee), ('course_description', g.has_description), ('application_deadlines', g.deadlines is not null)) x(stratum, holds) where x.holds),
  p as (select s.*, row_number() over (partition by s.stratum order by s.k) as rs from s where s.rp <= 3)
  select course_id, storage_path, display_title, stratum, intake_months, deadlines, fees, has_description from p
   where rs <= case stratum ${STRATA.map((st) => `when ${lit(st)} then ${PER_OF[st]}`).join(' ')} else 0 end order by stratum, k`)
const pages = new Map()
for (const g of gold) { const p = pages.get(g.course_id) || { ...g, strata: [] }; p.strata.push(g.stratum); pages.set(g.course_id, p) }
const list = [...pages.values()], results = [], LANES = ['course_description', 'intakes', 'course_fees', 'application_deadlines']
let cost = 0, worker_name = null, model = null, versions = null
for (let i = 0; i < list.length; i += 12) {  // half the worker's cap of one call, so each answer is back well inside pg_net's 120 s
  const chunk = list.slice(i, i + 12)
  const items = chunk.map((x) => `jsonb_build_object('ref', ${lit(x.course_id)}, 'storage_path', ${lit(x.storage_path)}, 'title', ${lit(String(x.display_title || '').slice(0, 200))}, 'lanes', '${JSON.stringify(LANES)}'::jsonb)`)
  const res = await worker(`jsonb_build_object('mode', 'boost_fields_replay', 'items', jsonb_build_array(${items.join(', ')}))`)
  if (res.skipped) { await summary(`Replay stopped: ${res.skipped}`); break }
  cost += Number(res.cost) || 0;
  if (cost >= MAX_COST) { await summary(`Replay stopped at US$${cost.toFixed(4)}, the spend limit of this run (US$${MAX_COST})`); for (const r of res.results || []) results.push(r); break } worker_name = res.worker; model = res.model; versions = { prompt: res.prompt_version, check: res.check_version }
  for (const r of res.results || []) results.push(r)
}
const by = new Map(results.filter(Boolean).map((r) => [r.ref, r]))
const tally = {}; const bump = (lane, k) => { tally[lane] ??= {}; tally[lane][k] = (tally[lane][k] || 0) + 1 }
const samples = []
for (const p of list) {
  const r = by.get(p.course_id)
  for (const lane of LANES) {
    const holds = lane === 'intakes' ? !!p.intake_months : lane === 'course_fees' ? !!p.fees : lane === 'application_deadlines' ? !!p.deadlines : !!p.has_description
    const f = (r?.fields || []).find((x) => x.lane === lane)
    if (!r || r.status === 'failed' || r.status === 'given_back') { bump(lane, holds ? 'gold_call_failed' : 'other_call_failed'); continue }
    const st = f?.status || 'not_stated'
    if (!holds) { bump(lane, `no_gold_${st}`); continue }
    bump(lane, 'gold'); bump(lane, `gold_${st}`)
    if (st !== 'verified') continue
    let agree = null
    if (lane === 'intakes') {
      // s723: the page's months are all its announced starts; a held primary intake that they contain (or that contains them) agrees
      const got = [...new Set((f.value || []).map((m) => MONTHS.indexOf(String(m).toLowerCase()) + 1).filter((m) => m > 0))], held = [...new Set(p.intake_months)]
      const sub = got.length > 0 && got.every((m) => held.includes(m)), sup = got.length > 0 && held.every((m) => got.includes(m))
      agree = sub || sup
      if (sub && sup) bump(lane, 'gold_exact'); else if (sup) bump(lane, 'gold_primary_subset'); else if (sub) bump(lane, 'gold_page_subset')
    }
    else if (lane === 'application_deadlines') {
      const held = p.deadlines || [], ans = (f.value || []).map((d) => String(d?.date || ''))
      agree = ans.length > 0 && ans.every((d) => held.some((h) => d.length === 10 ? h === d : h.slice(5) === d))
    }
    else if (lane === 'course_fees') {
      if (f.value?.audience === 'domestic') { bump(lane, 'gold_not_comparable'); continue }  // held fees are international; a domestic answer is another audience
      const cls = f.value?.period === 'year' ? 'year' : f.value?.period === 'total' ? 'total' : null
      if (!cls) { bump(lane, 'gold_not_comparable'); continue }
      const cur = String(f.value?.currency || '').toUpperCase()
      if (!/^[A-Z]{3}$/.test(cur)) { bump(lane, 'gold_not_comparable'); continue }  // s724: strict, the answer names its currency
      let same = p.fees.filter((g) => g.period === cls && g.currency === cur)
      if (!same.length) { bump(lane, `gold_no_${cls}_fee`); continue }
      const yr = Number(f.value?.year) || null, latest = Math.max(...same.map((g) => Number(g.year) || 0))
      same = yr ? same.filter((g) => Number(g.year) === yr) : same.filter((g) => (Number(g.year) || 0) === latest)  // s724: strict on the fee year
      if (!same.length) { bump(lane, `gold_no_${cls}_fee_same_year`); continue }
      agree = same.some((g) => Math.abs(Number(g.amount) - Number(f.value?.amount)) < 0.5)
      bump(lane, `${cls}_${agree ? 'agree' : 'disagree'}`)
    }
    if (agree === null) continue  // a description has no value to compare: its figure is the page check's pass rate
    bump(lane, agree ? 'gold_agree' : 'gold_disagree')
    if (!agree && samples.length < 30) samples.push({ lane, course_id: p.course_id, held: lane === 'intakes' ? p.intake_months : lane === 'application_deadlines' ? p.deadlines : (p.fees || []).filter((g) => g.period === f.value?.period || (f.value?.period === 'year' && g.period === 'year')), answered: f.value, quote: String(f.quote || '').slice(0, 200) })
  }
}
fs.mkdirSync('out', { recursive: true })
fs.writeFileSync('out/boost-fields-replay.json', JSON.stringify({ label: LABEL, per_stratum: PER_OF, max_cost: MAX_COST, pages: list.length, model, worker: worker_name, versions, cost, tally, samples, results }, null, 1))
const n = (lane, k) => tally[lane]?.[k] || 0, pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : 'n/a')
let md = `### Boost multi-field replay (${LABEL})\n\n${list.length} stored pages of courses that already hold a value, model ${model}, prompt ${versions?.prompt}, page check ${versions?.check}, worker ${worker_name}, cost US$${cost.toFixed(4)}. Nothing was staged or admitted.\n\n| Field | Pages holding a value | Verified | Refused | Not stated | Call failed | Verified and agrees with the held value | Disagrees | Agreement of verified |\n|---|---|---|---|---|---|---|---|---|\n`
for (const lane of LANES) md += `| ${lane} | ${n(lane, 'gold')} | ${n(lane, 'gold_verified')} | ${n(lane, 'gold_rejected')} | ${n(lane, 'gold_not_stated')} | ${n(lane, 'gold_call_failed')} | ${lane === 'course_description' ? 'not compared' : n(lane, 'gold_agree')} | ${lane === 'course_description' ? 'not compared' : n(lane, 'gold_disagree')} | ${lane === 'course_description' ? 'n/a' : pct(n(lane, 'gold_agree'), n(lane, 'gold_agree') + n(lane, 'gold_disagree'))} |\n`
md += `\nIntakes (s723): ${n('intakes', 'gold_exact')} agree exactly, ${n('intakes', 'gold_primary_subset')} list the held primary intake among more announced months, ${n('intakes', 'gold_page_subset')} list part of the held months; ${n('intakes', 'gold_disagree')} share no containment.\n`
const passes = (lane) => { const a = n(lane, 'gold_agree'), d = n(lane, 'gold_disagree'); return a + d >= 100 && a / (a + d) >= 0.95 && d === 0 }  // fixed: the qualification bar (100 compared, 95% agreement, no disagreement)
md += `\n**Qualification bar** (at least 100 verified answers compared, at least 95% agreement, no verified answer disagreeing): ${['intakes', 'course_fees', 'application_deadlines'].map((l) => `${l} ${passes(l) ? 'PASSES' : 'does not pass'}`).join('; ')}. A pass is a finding; admission is its own recorded step.\n`
md += `\n**Fees by basis** (an answer is compared with held fees of the same basis only)\n\n| Basis | Verified and agrees | Disagrees | Agreement | Course holds no fee of this basis |\n|---|---|---|---|---|\n`
for (const c of ['year', 'total']) md += `| ${c === 'year' ? 'Annual (period year)' : 'Whole-course total'} | ${n('course_fees', c + '_agree')} | ${n('course_fees', c + '_disagree')} | ${pct(n('course_fees', c + '_agree'), n('course_fees', c + '_agree') + n('course_fees', c + '_disagree'))} | ${n('course_fees', 'gold_no_' + c + '_fee')} |\n`
md += `\nFee answers in another period (semester, credit point, unit): ${n('course_fees', 'gold_not_comparable')}, not compared.\n`
md += `\nApplication deadlines (s726): ${n('application_deadlines', 'gold')} pages hold a deadline; ${n('application_deadlines', 'gold_verified')} verified, ${n('application_deadlines', 'gold_rejected')} refused, ${n('application_deadlines', 'gold_not_stated')} not stated; ${n('application_deadlines', 'gold_agree')} agree and ${n('application_deadlines', 'gold_disagree')} disagree with the held deadline.\n`
if (samples.length) md += `\n**Disagreements (first ${samples.length})**\n\n| Field | Held | Answered | Quote |\n|---|---|---|---|\n` + samples.map((s) => `| ${s.lane} | ${JSON.stringify(s.held).slice(0, 120)} | ${JSON.stringify(s.answered).replace(/\|/g, '/').slice(0, 160)} | ${s.quote.replace(/\|/g, '/').replace(/\s+/g, ' ')} |`).join('\n') + '\n'
await summary(md)
