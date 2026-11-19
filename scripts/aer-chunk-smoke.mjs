#!/usr/bin/env node
// CF-247 S747 (session S2-BOOST-AER, Platform Admin 19 Nov 2026 10:48 AEDT): the 10-table smoke test of the AER v2 matrix reader on the row chunker, run by
// GitHub Actions through the Supabase Management API with no person and no prompt:
//   1. reads the three candidate prompt versions aer-v2-matrix-chunk-v1 (pipeline.ai_instruction_versions, migration 20261119110500) and the 10 tables
//      chosen from the exported stored copies (tests/fixtures/aer-chunks/smoke-tables.json);
//   2. opens an on-demand window (security.on_demand_open_v1, OpenRouter only, the 10 tables' providers) and reports the estimate and the credit left;
//   3. asks worker mode aer_chunk_smoke for each pinned model and table, with one spend total across every call: a call is never started at or above the cap
//      (at most US$0.10, the Platform Admin's ceiling), and the worker refuses one too;
//   4. whatever happened, closes the window at once and reports the actual use and the credit left;
//   5. records the figures (row completeness, quote fidelity, minimum in quote, cost) as one control event (area aer, action matrix_chunk_smoke).
// Nothing is qualified, admitted or switched on: meeting the bar is a recommendation for the Platform Admin's own decision.
import fs from 'node:fs'
import { need, read, lit, summary } from './boost-live-lib.mjs'
need()
const CAP = Math.min(0.10, Number(process.argv[2]) || 0.10)  // the Platform Admin's ceiling of 19 Nov 2026 10:48 (US$0.10); an input may only lower it (S750: 0.05)
// S750 (Platform Admin 19 Nov 2026 13:05): which pinned model (version suffix, or "all"), rows a call (blank: the version's own), which table set, and an
// inspect list (source ids): with an inspect list the run only returns those tables' row chunks, with no model call, no spend and no window
const MODEL = String(process.argv[3] || 'all').replace(/[^a-z0-9.-]/gi, '').slice(0, 40) || 'all'
const ROWS = Math.max(0, Math.min(40, Math.floor(Number(process.argv[4]) || 0)))
const SET = /^[a-z0-9-]+\.json$/.test(String(process.argv[5] || '')) ? String(process.argv[5]) : 'smoke-tables.json'
const INSPECT = String(process.argv[6] || '').split(/[\s,]+/).filter((x) => /^[0-9a-f-]{36}$/.test(x))
// S751 (Platform Admin 19 Nov 2026 14:25): which prompt version (aer-v2-matrix-chunk-v1, or -v2 with one record per row and study level)
const PV = /^aer-v2-matrix-chunk-v[0-9]+$/.test(String(process.argv[7] || '')) ? String(process.argv[7]) : 'aer-v2-matrix-chunk-v1'
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN, REF = process.env.REF
const write = async (query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ query }) })
  const t = await r.text(); if (!r.ok) throw Error(`database write failed (HTTP ${r.status}): ${t.slice(0, 600)}`); return JSON.parse(t)
}
const sel = JSON.parse(fs.readFileSync(`tests/fixtures/aer-chunks/${SET}`, 'utf8')).tables
const all = await read(`select id, version, body, spec, model_identifier from pipeline.ai_instruction_versions where code = 'aer-v2-matrix-chunk' and spec->>'prompt_version' = ${lit(PV)} and status = 'candidate' order by id`)
const versions = MODEL === 'all' ? all : all.filter((v) => v.version === `${PV}-${MODEL}`)
if (![10, 20].includes(sel.length) || !all.length || !versions.length) { await summary(`Refused: expected 10 or 20 tables and a candidate version of ${PV} for ${MODEL}, found ${sel.length} tables and ${versions.length} of ${all.length} versions`); process.exit(1) }
const src = await read(`select s.id::text as source_id, s.provider_id::text as provider_id, p.name as provider from pipeline.entry_matrix_sources s left join catalogue.providers p on p.id = s.provider_id
  where s.id in (${sel.map((t) => lit(t.source_id) + '::uuid').join(', ')})`).catch(async () => read(`select s.id::text as source_id, s.provider_id::text as provider_id, null::text as provider from pipeline.entry_matrix_sources s where s.id in (${sel.map((t) => lit(t.source_id) + '::uuid').join(', ')})`))
const by = Object.fromEntries(src.map((s) => [s.source_id, s]))
if (sel.some((t) => !by[t.source_id]?.provider_id)) { await summary('Refused: a chosen table has no entry-matrix source with a provider'); process.exit(1) }
const direct = async (body) => {
  const [{ n }] = await write(`select public.svc_pilot_issue_nonce('coverage-sweep') as n`)
  const r = await fetch(`https://${REF}.supabase.co/functions/v1/coverage-sweep`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-cf-run-nonce': String(n) },
    body: JSON.stringify(body), signal: AbortSignal.timeout(150000) })  // longer than the worker's 110 s budget for one call
  const t = await r.text()
  try { return { http: r.status, ...JSON.parse(t) } } catch { return { http: r.status, error: `answer not JSON: ${t.trim().slice(0, 200)}` } }
}
if (INSPECT.length) {
  for (const t of sel.filter((x) => INSPECT.includes(x.source_id))) {
    const v = versions[0], res = await direct({ mode: 'aer_chunk_smoke', inspect_only: true, source_id: t.source_id, table: t.table, expect_rows: t.rows, expect_first: t.first,
      version: { id: v.id, version: v.version, body: v.body, spec: v.spec, model_identifier: v.model_identifier } }).catch((e) => ({ error: String(e.message || e) }))
    console.log('AERINSPECT:' + JSON.stringify({ file: t.file, ...res }))
  }
  await summary(`Inspected ${INSPECT.length} table(s): no model call, no spend, no window.`)
  process.exit(0)
}
let od = null, failure = null, spent = 0
const results = []
const providerIds = [...new Set(sel.map((t) => by[t.source_id].provider_id))]
await write(`select security.on_demand_close_v1(id) from pipeline.on_demand_requests where closed_at is null and reason like 'S747 AER matrix chunk smoke test%'`)
try {
  const [{ r }] = await write(`select security.on_demand_open_v1('claude_session', ${lit(`S747 AER matrix chunk smoke test (Platform Admin 19 Nov 2026 10:48 and 13:05 AEDT): ${versions.length} pinned model(s) x ${sel.length} chunked tables, ${ROWS || 'version'} rows a call, at most US$${CAP}`)},
      array[${providerIds.map((p) => lit(p) + '::uuid').join(', ')}]::uuid[],
      jsonb_build_object('calls', ${Math.ceil(sel.reduce((a, t) => a + t.rows, 0) / (ROWS || 25)) * versions.length}, 'openrouter_usd', ${Math.min(CAP, 0.03)}, 'firecrawl_credits', 0, 'cap_usd', ${CAP}, 'detail', ${lit(`${sel.reduce((a, t) => a + t.rows, 0)} rows in ${sel.length} tables, ${ROWS || 'the version\'s'} rows a call; ${versions.map((v) => v.model_identifier).join(', ')}; hard cap US$${CAP}`)}),
      null, array['openrouter']) as r`)
  od = r
  await summary(`### S747 AER matrix chunk smoke test\n\nOn-demand window \`${od.id}\` opened: estimate ${JSON.stringify(od.estimate)}; credit before ${JSON.stringify(od.credit_left_before ?? od.credit_left ?? null)}.`)
  outer: for (const v of versions) {
    for (const t of sel) {
      // one call's groups run in parallel inside the worker, so a call is not started within one call's cost (US$0.01, measured at about US$0.002) of the cap
      if (spent >= CAP - Math.min(0.01, CAP / 10)) { failure = failure || `spend cap reached before ${v.version} ${t.file}`; break outer }
      const res = await direct({ mode: 'aer_chunk_smoke', source_id: t.source_id, table: t.table, expect_rows: t.rows, expect_first: t.first, provider: by[t.source_id].provider || '',
        version: { id: v.id, version: v.version, body: v.body, spec: v.spec, model_identifier: v.model_identifier }, rows_per_call: ROWS || Number(v.spec?.rows_per_call) || 25, max_usd: CAP, spent_usd: spent })
        .catch((e) => ({ error: String(e.message || e) }))
      spent += Number(res.cost_usd) || 0
      results.push({ version: v.version, model: v.model_identifier, file: t.file, source_id: t.source_id, table: t.table, rows: t.rows, ok: !!res.ok, http: res.http ?? null, error: res.error ?? null,
        totals: res.totals ?? null, cost_usd: Number(res.cost_usd) || 0, group_errors: (res.groups || []).filter((g) => g.error).map((g) => g.error.slice(0, 120)),
        misses: (res.groups || []).flatMap((g) => (g.verified?.checks || []).filter((c) => !c.answered || c.quote_in_row === false || c.minimum_in_quote === false).map((c) => ({ r: c.r, ...c }))).slice(0, 40),
        call_ms: (res.groups || []).map((g) => Number(g.call_ms) || null).filter(Boolean), input: res.input ?? null, detail: (res.groups || []).flatMap((g) => g.misses || []).slice(0, 12) })
      console.log(`${v.version} ${t.file}: ${res.ok ? JSON.stringify(res.totals) : 'error ' + (res.error || res.http)} cost ${res.cost_usd ?? 0} spent ${spent.toFixed(5)}`)
    }
  }
} catch (e) { failure = String(e.message || e) } finally {
  if (od?.id) { try { const [{ c }] = await write(`select security.on_demand_close_v1(${lit(od.id)}::uuid) as c`); od.closed = c; await summary(`On-demand window closed: ${JSON.stringify(c)}`) } catch (e) { failure = (failure ? failure + '; ' : '') + 'window close failed: ' + e.message } }
}
// per model, over every row of the 10 tables (a table that returned no answer counts its rows as unanswered)
const models = versions.map((v) => {
  const rs = results.filter((r) => r.version === v.version), s = (k) => rs.reduce((a, r) => a + (Number(r.totals?.[k]) || 0), 0)
  const rows = rs.reduce((a, r) => a + r.rows, 0), answered = s('answered'), quotes = s('quotes'), inRow = s('quotes_in_row'), mins = s('minimums'), minIn = s('minimums_in_quote'), invented = s('invented')
  const pct = (a, b) => (b ? Math.round((a / b) * 1000) / 10 : null)
  const m = { version: v.version, model: v.model_identifier, tables: rs.length, tables_answered: rs.filter((r) => r.ok).length, rows, answered, invented, quotes, quotes_in_row: inRow, minimums: mins, minimums_in_quote: minIn,
    row_completeness_pct: pct(answered, rows), quote_fidelity_pct: pct(inRow, quotes), minimum_in_quote_pct: pct(minIn, mins), cost_usd: Math.round(rs.reduce((a, r) => a + r.cost_usd, 0) * 1e6) / 1e6 }
  m.meets_bar = rs.length === sel.length && rs.every((r) => r.ok) && m.row_completeness_pct === 100 && m.quote_fidelity_pct === 100 && (m.minimum_in_quote_pct ?? 100) === 100 && invented === 0
  return m
})
const callMs = results.flatMap((r) => r.call_ms)
const record = { prompt_version: PV, set: SET, model_filter: MODEL, rows_per_call: ROWS || null, tables: sel.length, rows: sel.reduce((a, t) => a + t.rows, 0), cap_usd: CAP,
  calls: callMs.length, max_call_ms: callMs.length ? Math.max(...callMs) : null, calls_over_60s: callMs.filter((x) => x > 60000).length, timeout_ms: 90000, spent_usd: Math.round(spent * 1e6) / 1e6, on_demand: od?.id ?? null,
  actual: od?.closed?.actual ?? od?.closed ?? null, bar: { row_completeness_pct: 100, quote_fidelity_pct: 100, minimum_in_quote_pct: 100, invented: 0 }, models, failure,
  tables_detail: results.map((r) => ({ v: r.version.replace('aer-v2-matrix-chunk-v1-', ''), f: r.file.slice(0, 40), rows: r.rows, in: r.input, ms: r.call_ms.length ? Math.max(...r.call_ms) : null, t: r.totals && { a: r.totals.answered, q: r.totals.quotes_in_row + '/' + r.totals.quotes, m: r.totals.minimums_in_quote + '/' + r.totals.minimums, i: r.totals.invented }, c: r.cost_usd, e: r.error || (r.group_errors.length ? r.group_errors : undefined) })) }
try {
  await write(`insert into pipeline.admin_control_events(area, action, target, detail) values ('aer', 'matrix_chunk_smoke', 'pipeline.ai_instruction_versions', ${lit(JSON.stringify(record))}::jsonb)`)
} catch (e) { failure = (failure ? failure + '; ' : '') + 'record failed: ' + e.message }
console.log('AERSMOKE:' + JSON.stringify(record))
for (const r of results.filter((r) => r.misses.length)) console.log('AERSMOKE-MISS:' + JSON.stringify({ v: r.version, f: r.file, misses: r.misses, detail: r.detail }))
await summary(`\n| Model (pinned) | Tables answered | Rows | Row completeness % | Quote fidelity % | Minimum in quote % | Invented rows | Cost US$ | Meets the bar |\n|---|---|---|---|---|---|---|---|---|\n` +
  models.map((m) => `| ${m.model} | ${m.tables_answered}/${m.tables} | ${m.answered}/${m.rows} | ${m.row_completeness_pct} | ${m.quote_fidelity_pct} (${m.quotes_in_row}/${m.quotes}) | ${m.minimum_in_quote_pct} (${m.minimums_in_quote}/${m.minimums}) | ${m.invented} | ${m.cost_usd} | ${m.meets_bar ? 'yes' : 'no'} |`).join('\n') +
  `\n\nCalls ${record.calls}, longest ${record.max_call_ms} ms (time-out 90,000 ms), over 60 s: ${record.calls_over_60s}.\n\nSpent US$${record.spent_usd} of the US$${CAP} cap. Bar: every row answered once, every quote inside its own row, every minimum inside its quote, no invented row. Nothing qualified or switched on.`)
if (failure) { await summary(`Stopped: ${failure}`); process.exit(1) }
if (spent > CAP + 1e-9) { await summary('Spend above the cap'); process.exit(1) }
