#!/usr/bin/env node
// CF-247 S672 (session S1-AER, Platform Admin standing mandate 18 Nov 2026 19:28 AEDT, step 3): the AER v2 offline model qualification replay through the
// on-demand open/close route, run by GitHub Actions with no person and no prompt. It answers the queued round runs that migration 20261118239000 opened
// (proposals aer-v2-course-v3-*-<round>) and nothing else:
//   1. opens an on-demand window (security.on_demand_open_v1, OpenRouter only, the frozen set's providers) and reports the estimate and the credit left;
//   2. turns reading.aer_v2_long_page_sections_on, ai_eval.offline_runs_on and ai_eval.aer_v3_runs_on to 1 for the run only (reason and control event each);
//   3. asks worker mode aer_v3_eval (public.svc_aer_v3_eval_next_v1 leases one run at a time, under ai_eval.aer_v3_max_usd) until no round run is left;
//      after each call returns, the call is over, so a lease it left on a part-answered run is released at once (lesson 7: a 30-minute lease idled the run);
//   4. scores each recorded run (security.ai_eval_score_v1, the ai-eval job's own scorer) and reads the gate unchanged: source integrity 100%,
//      error rate at most 10 points, no false positives;
//   5. whatever happened, turns the three switches back to 0 and closes the window, reporting the actual use and the credit left.
// Nothing is qualified or switched on: qualification evidence is written as pending at most, and a qualification is the Platform Admin's decision.
import { need, read, lit, summary } from './boost-live-lib.mjs'
need()
const ROUND = String(process.argv[2] || 'r4').replace(/[^a-z0-9]/gi, '').slice(0, 8)
const MAX_MIN = Math.max(10, Math.min(110, Number(process.argv[3]) || 100))
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN, REF = process.env.REF
const write = async (query) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ query }) })
  const t = await r.text(); if (!r.ok) throw Error(`database write failed (HTTP ${r.status}): ${t.slice(0, 600)}`); return JSON.parse(t)
}
const SW = ['reading.aer_v2_long_page_sections_on', 'ai_eval.offline_runs_on', 'ai_eval.aer_v3_runs_on']
const CODE = `aer-v2-course-v3%-${ROUND}`  // v3 and v3.1 versions (s674)
const switches = (to, why) => write(`with u as (update pipeline.platform_toolset_settings set value = '${to}'::jsonb, updated_at = now(), reason = ${lit(why)}
   where toolset_key = 'pipeline' and key in (${SW.map(lit).join(', ')}) and value is distinct from '${to}'::jsonb returning key)
  insert into pipeline.admin_control_events(area, action, target, detail, actor) select 'settings', 'workflow', u.key, jsonb_build_object('workflow', 'aer-v3-replay', 'round', ${lit(ROUND)}, 'after', ${to}, 'why', ${lit(why)}), null from u returning target`)
const runs = () => read(`select x.id, p.code, x.state, x.leased_until, v.model_identifier as model, x.metrics from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
   join pipeline.ai_instruction_versions v on v.id = x.version_id where p.code like ${lit(CODE)} and x.arm = 'candidate' order by x.id`)

const start = await runs()
// s674: a stopped attempt is continued; runs already recorded stay as they are
if (start.length !== 3 || !start.some((r) => r.state === 'queued' || r.state === 'answering')) { await summary(`Refused: expected 3 ${ROUND} runs with at least one still open, found ${JSON.stringify(start.map((r) => [r.code, r.state]))}`); process.exit(1) }
let od = null, failure = null
// a stopped earlier attempt of this round: its leases are released (no task can still be running after 400 s) and its open window is closed first
if (start.some((r) => r.state === 'answering')) await write(`update pipeline.ai_eval_runs x set leased_until = now() from pipeline.ai_improvement_proposals p where p.id = x.proposal_id and p.code like ${lit(CODE)} and x.state = 'answering' and x.leased_until > now() - interval '1 hour'`)
await write(`select security.on_demand_close_v1(id) from pipeline.on_demand_requests where closed_at is null and reason like ${lit(`S672 AER v3 replay ${ROUND} %`)}`)
try {
  const [{ r }] = await write(`select security.on_demand_open_v1('claude_session', ${lit(`S672 AER v3 replay ${ROUND} (Platform Admin standing mandate 18 Nov 2026 19:28 AEDT, step 3): 3 pinned models x 50 frozen cases`)},
      (select provider_ids from pipeline.on_demand_requests where id = 'ca8dee01-5203-4152-a04c-f39b11091421'),
      jsonb_build_object('calls', 150, 'openrouter_usd', 0.40, 'firecrawl_credits', 0, 'detail', 'Qwen3 30B ~0.05, Mistral Small 3.2 ~0.08, MiMo v2.6 Flash ~0.12 (round 4 x about 1.6 for longer answers); cap ai_eval.aer_v3_max_usd'),
      null, array['openrouter']) as r`)
  od = r
  await summary(`### S672 AER v3 replay ${ROUND}\n\nOn-demand window \`${od.id}\` opened: estimate ${JSON.stringify(od.estimate)}; credit before ${JSON.stringify(od.credit_left_before ?? od.credit_left ?? null)}.`)
  await switches(1, `S672 AER v3 replay ${ROUND} (workflow aer-v3-replay): on for the run only; restored to 0 by the same workflow`)
  const until = Date.now() + MAX_MIN * 60000
  const counts = async () => Object.fromEntries((await read(`select a.run_id, count(*) n from pipeline.ai_eval_answers a join pipeline.ai_eval_runs x on x.id = a.run_id
     join pipeline.ai_improvement_proposals p on p.id = x.proposal_id where p.code like ${lit(CODE)} group by a.run_id`)).map((r) => [String(r.run_id), Number(r.n)]))
  let calls = 0
  const direct = async () => {
    const [{ n }] = await write(`select public.svc_pilot_issue_nonce('coverage-sweep') as n`)
    const r = await fetch(`https://${REF}.supabase.co/functions/v1/coverage-sweep`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-cf-run-nonce': String(n) },
      body: JSON.stringify({ mode: 'aer_v3_eval', stream: true }), signal: AbortSignal.timeout(420000) })  // fixed: longer than the worker's 400 s wall clock
    const t = await r.text()
    try { return JSON.parse(t) } catch { return { error: `HTTP ${r.status}: ${t.trim().slice(0, 200)}` } }
  }
  while (Date.now() < until) {
    const left = (await runs()).filter((r) => r.state === 'queued' || r.state === 'answering')
    if (!left.length) break
    // s674 (worker v1.0.19): each call leases one run and answers it in a background task (up to 180 s a model call inside 360 s), replying 202 at once;
    // one call per open run, in parallel, then wait until each leased run has recorded its answers (or the task's wall clock has surely ended)
    const before = await counts()
    // s674 (22:15): each call goes straight to the worker with a one-time nonce and reads the streamed answer (no pg_net, no background task)
    const res = await Promise.all(left.map(() => direct().catch((e) => ({ error: String(e.message || e) }))))
    calls += res.length
    for (const r of res) console.log(`call: run ${r.run ?? '-'} ${r.why ?? ''} ${r.error ?? ''} ${JSON.stringify({ background: r.background, call_ms: r.call_ms, answered: r.recorded, cost: r.cost_usd }).slice(0, 300)}`)
    const why = res.find((r) => !r.run && r.why)
    if (why) { failure = `worker: ${why.why}`; break }
    const leased = res.filter((r) => r.run).map((r) => String(r.run))
    if (!leased.length && !res.some((r) => r.error)) { await new Promise((r) => setTimeout(r, 20000)); continue }  // nothing leasable this moment
    // a call whose reply was lost may still be answering a run in the background: the wait below covers its wall clock before any lease is released
    const t = Date.now()
    // a streamed call that came back has finished its work; only a lost call can still be running, so only then is there a wait
    while (res.some((r) => r.error) && Date.now() - t < 410000 && Date.now() < until) {  // fixed: longer than the 400 s wall clock of the background task
      await new Promise((r) => setTimeout(r, 15000))
      const now = await counts()
      if (leased.length && !res.some((r) => r.error) && res.filter((r) => r.run).every((r) => (now[String(r.run)] || 0) >= (before[String(r.run)] || 0) + (Number(r.examples) || 1))) break  // s674: every example the task started has its answer
    }
    // the calls are over: a lease they left on a part-answered round run is released, so the next calls continue it
    await write(`update pipeline.ai_eval_runs x set leased_until = now() from pipeline.ai_improvement_proposals p where p.id = x.proposal_id and p.code like ${lit(CODE)} and x.state = 'answering' and x.leased_until > now()`)
  }
  for (const r of (await runs()).filter((r) => r.state === 'recorded')) await write(`select security.ai_eval_score_v1(${Number(r.id)})`)
} catch (e) { failure = String(e.message || e) } finally {
  try { await switches(0, `S672 AER v3 replay ${ROUND} (workflow aer-v3-replay): restored to 0 after the run`) } catch (e) { failure = (failure ? failure + '; ' : '') + 'switch restore failed: ' + e.message }
  if (od?.id) { try { const [{ c }] = await write(`select security.on_demand_close_v1(${lit(od.id)}::uuid) as c`); await summary(`On-demand window closed: ${JSON.stringify(c)}`) } catch (e) { failure = (failure ? failure + '; ' : '') + 'window close failed: ' + e.message } }
}
const end = await runs()
const sw = await read(`select key, value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in (${SW.map(lit).join(', ')}) order by key`)
const q = await read(`select service_code, status, evidence->>'model' as model, evidence->'gate' as gate from pipeline.ai_route_qualifications where updated_at > now() - interval '3 hours' and service_code = 'entry_requirements_v2_shadow' order by updated_at`).catch(() => [])
const rows = end.map((r) => {
  const m = r.metrics || {}
  const pick = (...k) => { for (const x of k) if (m[x] !== undefined) return m[x]; return null }
  return `| ${r.model} | ${r.state} | ${pick('right')} | ${pick('source_integrity_pct', 'quote_on_page_pct')} | ${pick('error_rate_pts', 'error_pts')} | ${pick('false_positives', 'fp')} | ${pick('cost_usd', 'cost')} |`
})
await summary(`\n| Model (pinned) | State | Right of 50 | Source integrity % | Error points | False positives | Cost US$ |\n|---|---|---|---|---|---|---|\n${rows.join('\n')}\n\nGate (unchanged): source integrity 100%, error rate at most 10 points, no false positives. Qualification evidence: ${JSON.stringify(q).slice(0, 1500)}\n\nSwitches after the run: ${JSON.stringify(sw)}\n\n<details><summary>metrics</summary>\n\n\`\`\`json\n${JSON.stringify(end.map((r) => ({ id: r.id, code: r.code, metrics: r.metrics })), null, 1).slice(0, 60000)}\n\`\`\`\n</details>`)
if (failure) { await summary(`Stopped: ${failure}`); process.exit(1) }
if (sw.some((s) => Number(s.value) !== 0)) { await summary('A run switch is not 0 after the run'); process.exit(1) }
