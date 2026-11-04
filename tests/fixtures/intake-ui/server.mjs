// Guards: PR #872 actual PostgreSQL integration transport. Loopback only; never deployed.
// Simulates a Supabase authenticated fixture identity; RPC bodies/results execute real SQL, not mock results.
import http from 'node:http'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
const exec = promisify(execFile)
const text = v => "'" + String(v ?? '').replaceAll("'", "''") + "'"
if (process.env.PGHOST && !['127.0.0.1', 'localhost', '/tmp'].includes(process.env.PGHOST)) throw Error('Local PostgreSQL only')
const database = 'intake_ui_fixtures'
const actor = '21232f29-7a57-a5a7-4389-4a0e4a801fc3' // md5('admin'), controlled fixture identity
const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*'); res.setHeader('Access-Control-Allow-Headers', '*')
  res.setHeader('Content-Type', 'application/json')
  if (req.method === 'OPTIONS') { res.end(); return }
  if (req.url === '/health') { res.end('{}'); return }
  try {
    let body = ''; for await (const c of req) body += c
    const a = JSON.parse(body)
    let call
    if (req.url === '/rest/v1/rpc/admin_intake_run_read_v1') call = `public.admin_intake_run_read_v1(${text(a.p_view)},${text(JSON.stringify(a.p_args || {}))}::jsonb)`
    if (req.url === '/rest/v1/rpc/admin_intake_cohort_prepare_v1') call = `public.admin_intake_cohort_prepare_v1(${text(a.p_scope)},${text(a.p_size)}::integer,${text(a.p_reason)},${text(a.p_preview_token)})`
    if (req.url === '/rest/v1/rpc/admin_intake_run_now_v1') call = `public.admin_intake_run_now_v1(${text(a.p_cohort_id)}::uuid)`
    if (req.url === '/rest/v1/rpc/admin_intake_preview_v1') call = `public.admin_intake_preview_v1(${text(a.p_action)},${text(JSON.stringify(a.p_args || {}))}::jsonb)`
    if (req.url === '/rest/v1/rpc/admin_intake_preview_prepare_v1') call = `public.admin_intake_preview_prepare_v1(${text(a.p_session_id)}::uuid,${text(a.p_reason)})`
    if (!call) throw Error('Unsupported local fixture RPC')
    const sql = `begin; set local statement_timeout='8s'; set local lock_timeout='8s'; set local role authenticated; do $$begin perform set_config('request.jwt.claim.sub',${text(actor)},true); end$$; select ${call}; commit;`
    const { stdout } = await exec('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', database, '-c', sql], { maxBuffer: 8 << 20 })
    res.end(JSON.stringify(JSON.parse(stdout.trim())))
  } catch (e) { res.statusCode = 400; res.end(JSON.stringify({ message: e.stderr || e.message })) }
})
server.listen(55433, '127.0.0.1')
