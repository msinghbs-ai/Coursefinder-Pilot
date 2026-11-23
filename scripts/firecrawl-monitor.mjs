// CF-247 s1027 (S1-Build; Platform Admin 24 Nov 2026 06:03 and 09:06 AEDT): the Firecrawl Monitor watchlist, run from GitHub Actions through the
// Management API with no person at a prompt. It asks the firecrawl-monitor-webhook function, with a one-time nonce
// (pipeline.svc_pilot_submit_nonce; the function is allow-listed in pipeline.pilot_nonce_functions), to register the watchlist (create or update
// one monitor per university and its search monitor, within firecrawl.monitor_weekly_credits), report its status, or pause every monitor.
// Usage: node scripts/firecrawl-monitor.mjs register|status|pause
import fs from 'node:fs'

const TOKEN = process.env.SUPABASE_ACCESS_TOKEN, REF = process.env.REF
const ACTIONS = new Set(['register', 'status', 'pause'])
const WAIT_MS = 180000  // fixed: how long to wait for the function's answer (its Firecrawl calls time out at 20 s each)

async function query(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST',
    headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, body: JSON.stringify({ query: sql }) })
  const text = await r.text()
  if (!r.ok) throw Error(`database query failed (HTTP ${r.status}): ${text.slice(0, 400)}`)
  return JSON.parse(text)
}

export async function run(action) {
  if (!ACTIONS.has(action)) throw Error(`action must be one of ${[...ACTIONS].join(', ')}`)
  const [{ id }] = await query(`select pipeline.svc_pilot_submit_nonce('firecrawl-monitor-webhook', '${JSON.stringify({ action })}'::jsonb) as id`)
  const until = Date.now() + WAIT_MS
  while (Date.now() < until) {
    await new Promise((ok) => setTimeout(ok, 4000))
    const rows = await query(`set transaction read only; select status_code, timed_out, error_msg, convert_from(content::bytea, 'utf8') as content from net._http_response where id = ${Number(id)}`)
    if (!rows.length) continue
    const x = rows[0]
    if (x.timed_out || x.error_msg) throw Error(`request ${id}: ${x.error_msg || 'timed out'}`)
    let out; try { out = JSON.parse(x.content) } catch { throw Error(`request ${id}: HTTP ${x.status_code}, answer not JSON`) }
    if (x.status_code >= 300) throw Error(`request ${id}: HTTP ${x.status_code} ${out?.error || ''}`)
    return out
  }
  throw Error(`request ${id}: no answer within ${WAIT_MS / 1000} s`)
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (!TOKEN || REF !== 'fxcwkweaxjtknorudmwp') { console.error('::error::SUPABASE_ACCESS_TOKEN and REF (fxcwkweaxjtknorudmwp) are required'); process.exit(1) }
  run(process.argv[2]).then((out) => {
    const lines = [`## Firecrawl Monitor: ${process.argv[2]}`, '', '```json', JSON.stringify(out, null, 2).slice(0, 60000), '```']
    if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, lines.join('\n') + '\n')
    console.log(JSON.stringify(out, null, 2))
    if (out?.ok === false) process.exit(1)
  }).catch((e) => { console.error(`::error::${e.message}`); process.exit(1) })
}
