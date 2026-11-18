// CF-247 S2 - BOOST (Platform Admin 17 Nov 2026 22:05 and 18 Nov 2026 17:02): the calls the Boost inspection and replay scripts make to the
// Pilot through the Supabase Management API, so a GitHub Actions run needs no person and answers no prompt. Reads run read-only; the one
// call that is not a read asks the coverage-sweep worker for a mode through the platform's own one-time nonce (pipeline.svc_pilot_submit_nonce).
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN, REF = process.env.REF
export function need() { if (!TOKEN || !REF) { console.error('::error::SUPABASE_ACCESS_TOKEN and REF are required'); process.exit(1) } }
async function call(query, readOnly) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST', headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' },
    body: JSON.stringify(readOnly ? { query, read_only: true } : { query }) })
  const text = await r.text()
  if (!r.ok) throw Error(`database query failed (HTTP ${r.status}): ${text.slice(0, 600)}`)
  return JSON.parse(text)
}
export const read = (query) => call(query, true)
export const lit = (s) => `'${String(s).replace(/'/g, "''")}'`
// asks the worker for a mode and waits for its answer (pg_net keeps the response; the worker answers within its own time budget).
// First run, 18 Nov 2026: the worker answered a replay call in 67 s but pg_net stored the answer 155 s after the request (its queue was
// busy), so the wait is well above the worker's own budget.
export async function worker(bodySql, waitMs = 480000) {
  const [{ id }] = await call(`select pipeline.svc_pilot_submit_nonce('coverage-sweep', ${bodySql}) as id`, false)
  const until = Date.now() + waitMs
  while (Date.now() < until) {
    await new Promise((r) => setTimeout(r, 4000))
    const rows = await read(`select status_code, timed_out, error_msg, convert_from(content::bytea, 'utf8') as content from net._http_response where id = ${Number(id)}`).catch(() => read(`select status_code, timed_out, error_msg, content::text as content from net._http_response where id = ${Number(id)}`))
    if (!rows.length) continue
    const x = rows[0]
    if (x.timed_out || x.error_msg) throw Error(`worker request ${id}: ${x.error_msg || 'timed out'}`)
    let out; try { out = JSON.parse(x.content) } catch { throw Error(`worker request ${id}: HTTP ${x.status_code}, answer not JSON: ${String(x.content).slice(0, 300)}`) }
    if (x.status_code >= 300 || out?.error) throw Error(`worker request ${id}: HTTP ${x.status_code} ${String(out?.error || '').slice(0, 300)}`)
    return out
  }
  throw Error(`worker request ${id}: no answer within ${Math.round(waitMs / 1000)} s`)
}
export const summary = async (md) => { const fs = await import('node:fs'); if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, md + '\n'); console.log(md) }
