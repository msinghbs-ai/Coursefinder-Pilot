// Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: browser-to-PostgreSQL transport. Loopback only; never deployed.
// Runs the two RPCs the Course catalogue calls (admin_read courses_page, admin_table_layout) as PostgREST runs them: role authenticated with the
// person's JWT subject. The person is named by the test (x-fixture-user: admin, operator2, viewer); results are real SQL results, never made up.
import http from 'node:http'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import crypto from 'node:crypto'
const exec = promisify(execFile)
if (process.env.PGHOST && !['127.0.0.1', 'localhost', '/tmp'].includes(process.env.PGHOST)) throw Error('Local PostgreSQL only')
const database = process.env.CCOL_DB || 'c_ccol_fixture'
const text = v => "'" + String(v ?? '').replaceAll("'", "''") + "'"
const md5uuid = s => { const h = crypto.createHash('md5').update(s).digest('hex'); return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}` }
const PEOPLE = new Set(['admin', 'operator2', 'viewer', 'norole'])
const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*'); res.setHeader('Access-Control-Allow-Headers', '*'); res.setHeader('Content-Type', 'application/json')
  if (req.method === 'OPTIONS') { res.end(); return }
  if (req.url === '/health') { res.end('{}'); return }
  try {
    const who = String(req.headers['x-fixture-user'] || 'admin')
    if (!PEOPLE.has(who)) throw Error('unknown fixture person')
    let body = ''; for await (const c of req) body += c
    const a = JSON.parse(body || '{}')
    let call
    if (req.url === '/rest/v1/rpc/admin_read' && a.p_operation === 'courses_page') call = `public.admin_read('courses_page',${text(JSON.stringify(a.p_args || {}))}::jsonb)`
    if (req.url === '/rest/v1/rpc/admin_table_layout') call = `public.admin_table_layout(${text(a.p_action)},${text(JSON.stringify(a.p_args || {}))}::jsonb)`
    if (!call) throw Error('Unsupported local fixture RPC')
    const sql = `begin; set local statement_timeout='8s'; select set_config('request.jwt.claim.sub',${text(md5uuid(who))},true); set local role authenticated; select ${call}; commit;`
    const { stdout } = await exec('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', database, '-c', sql], { maxBuffer: 32 << 20 })
    const lines = stdout.trim().split('\n').filter(Boolean)
    res.end(lines[lines.length - 1])
  } catch (e) {
    res.statusCode = 400
    const m = String(e.stderr || e.message).match(/ERROR:\s+(.*)/)
    res.end(JSON.stringify({ message: m ? m[1] : String(e.message), code: /permission|role required|authentication/.test(String(e.stderr)) ? '42501' : '22023' }))
  }
})
server.listen(Number(process.env.CCOL_PORT || 55434), '127.0.0.1')
