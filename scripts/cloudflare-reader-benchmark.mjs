// CF-247 s1324 (S1-Build; SS-Programme-Control 27 Nov 2026 22:36 AEDT, Decision 2): one burst read on the isolated Cloudflare reader, through
// the coverage-sweep worker (mode burst_read), which applies the platform's gate (switch, one slot, compute caps, stored public evidence) and
// signs the call. The result and the run log row are printed; nothing else is sent.
import { need, op, read, lit, summary } from './boost-live-lib.mjs'

need()
const [evidence] = process.argv.slice(2)
if (!/^[0-9a-f-]{36}$/.test(String(evidence || ''))) { console.error('::error::evidence_id is an id'); process.exit(1) }
const [{ n }] = await op(`select public.svc_pilot_issue_nonce('coverage-sweep') as n`)
const t0 = Date.now()
const r = await fetch(`https://${process.env.REF}.supabase.co/functions/v1/coverage-sweep`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-cf-run-nonce': String(n) },
  body: JSON.stringify({ mode: 'burst_read', evidence_id: evidence }), signal: AbortSignal.timeout(360000) })  // fixed: longer than the worker's 300 s burst time-out
const text = await r.text(); let res; try { res = JSON.parse(text) } catch { res = { http: r.status, error: text.slice(0, 300) } }
const runs = (await op(`select public.svc_cloudflare_reader_v1('list', '{}'::jsonb, 'benchmark') as r`))?.[0]?.r?.runs || []
await summary([`Burst read of ${evidence}: worker HTTP ${r.status} in ${Date.now() - t0} ms`, '', '```json', JSON.stringify(res, null, 2).slice(0, 6000), '```', '',
  'Latest run log rows:', '```json', JSON.stringify(runs.slice(0, 3), null, 2).slice(0, 3000), '```'].join('\n'))
if (!res.ok) process.exit(1)
