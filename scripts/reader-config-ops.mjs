// CF-247 s1310 (S1-Build; SS-Programme-Control 27 Nov 2026 13:39 and 13:43 AEDT; Platform Admin direction 27 Nov 2026, coursefinder-admin #1293):
// reader configuration operations without a person at the screen and without CI per configuration. Each operation is one call of the governed
// writer public.svc_reader_configs_v1 (the same closed list, checks, reason and log as Layer 2/3 › Adapter builder › Reader configurations); a list
// writes nothing. No SQL other than that call is ever sent, and activation authority is never granted here.
import { need, op, lit, summary } from './boost-live-lib.mjs'
import fs from 'node:fs'

const ACTIONS = ['list', 'save_draft', 'discard_draft', 'qualify', 'requalify', 'activate', 'pause', 'resume', 'rollback']
need()
const [opsJson, by] = process.argv.slice(2)
let ops
try { ops = JSON.parse(opsJson || '[]') } catch { console.error('::error::ops is a JSON list of {action, args}'); process.exit(1) }
if (!Array.isArray(ops) || !ops.length || ops.length > 20) { console.error('::error::ops is a list of 1 to 20 operations'); process.exit(1) }  // fixed: operations per run
if (!by || !String(by).trim()) { console.error('::error::who is acting (by) is required'); process.exit(1) }
const out = []
for (const o of ops) {
  if (!ACTIONS.includes(o?.action)) { console.error(`::error::unknown action ${o?.action}`); process.exit(1) }
  if (o.action !== 'list' && !String(o?.args?.reason || '').trim()) { console.error(`::error::${o.action} needs a reason`); process.exit(1) }
  const q = `select public.svc_reader_configs_v1(${lit(o.action)}, ${lit(JSON.stringify(o.args || {}))}::jsonb, ${lit(by)}) as r`
  try {
    // s1310b: the Management API's read-only role may not run the service function, so every operation is one op() call; list writes nothing (the function)
    const rows = await op(q)
    out.push({ action: o.action, ok: true, result: rows?.[0]?.r ?? null })
  } catch (e) { out.push({ action: o.action, ok: false, error: String(e.message || e).slice(0, 600) }); break }
}
fs.mkdirSync('out', { recursive: true })
fs.writeFileSync('out/reader-config-ops.json', JSON.stringify(out, null, 2))
await summary(['| Action | Result |', '|---|---|', ...out.map((x) => `| ${x.action} | ${x.ok ? JSON.stringify(x.result).slice(0, 300).replace(/\|/g, '/') : 'failed: ' + x.error.slice(0, 300).replace(/\|/g, '/')} |`)].join('\n'))
if (out.some((x) => !x.ok)) process.exit(1)
