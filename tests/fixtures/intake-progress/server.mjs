// Guards: Platform Admin decision 5 Nov 2026 16:36 §8: the browser-to-PostgreSQL transport for the Automation Progress screen. Loopback only, never
// deployed. Each RPC runs as the authenticated role with a seeded identity of the chosen rank (as Supabase sets auth.uid()); results are real SQL.
import http from 'node:http'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
const exec = promisify(execFile)
const text = v => "'" + String(v ?? '').replaceAll("'", "''") + "'"
if (process.env.PGHOST && !['127.0.0.1', 'localhost', '/tmp', '/var/run/postgresql'].includes(process.env.PGHOST)) throw Error('Local PostgreSQL only')
const database = process.env.INTAKE_PROGRESS_DB || 'd_intake_progress'
const port = Number(process.env.INTAKE_PROGRESS_PORT || 55443)
let rank = 6
const RPC = {
  admin_intake_progress_v1: a => `public.admin_intake_progress_v1(${text(a.p_view)},${text(JSON.stringify(a.p_args || {}))}::jsonb)`,
  admin_process_results_v1: a => `public.admin_process_results_v1(${text(a.p_view)},${text(JSON.stringify(a.p_args || {}))}::jsonb)`,
  admin_automation_control: a => `public.admin_automation_control(${text(a.p_job)},${text(a.p_action)},${text(JSON.stringify(a.p_args || {}))}::jsonb)`,
}
const psql = sql => exec('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', database, '-c', sql], { maxBuffer: 16 << 20 })
const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*'); res.setHeader('Access-Control-Allow-Headers', '*'); res.setHeader('Content-Type', 'application/json')
  if (req.method === 'OPTIONS') { res.end(); return }
  if (req.url === '/health') { res.end('{}'); return }
  try {
    let body = ''; for await (const c of req) body += c
    const a = body ? JSON.parse(body) : {}
    if (req.url === '/fixture/actor') { rank = Number(a.rank); res.end(JSON.stringify({ rank })); return }
    if (req.url === '/fixture/sql') { const { stdout } = await psql(String(a.sql)); res.end(JSON.stringify({ rows: stdout.trim() })); return }  // test checks and setup, loopback only
    const name = req.url.replace(/^\/rest\/v1\/rpc\//, '')
    if (!RPC[name]) throw Error('Unsupported local fixture RPC')
    const sql = `begin; set local statement_timeout='20s'; set local role authenticated; do $$begin perform set_config('request.jwt.claim.sub',md5('intake-progress:user:${rank}')::uuid::text,true); end$$; select ${RPC[name](a)}; commit;`
    const { stdout } = await psql(sql)
    res.end(stdout.trim() === '' ? 'null' : stdout.trim())
  } catch (e) { res.statusCode = 400; res.end(JSON.stringify({ message: String(e.stderr || e.message).replace(/^.*ERROR:\s*/s, '').split('\n')[0] })) }
})
server.listen(port, '127.0.0.1')
