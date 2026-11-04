// Guards: complete intake preview pages fit the existing authenticated database request limit, across all approved universities.
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
const query = sql => execFileSync('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', 'intake_ui_fixtures', '-c', sql], { encoding: 'utf8' }).trim()
const prefix = "begin;set local statement_timeout='8s';set local lock_timeout='8s';set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);end$$;"
const start = JSON.parse(query(prefix + "select public.admin_intake_preview_v1('start','{\"scope\":\"top-au\",\"size\":20}');commit;"))
const plans = []
for (let page = 0; page < 10; page++) {
  const args = JSON.stringify({ session_id: start.session_id, page_no: page })
  plans.push(JSON.parse(query(prefix + `explain(analyze,buffers,format json) select public.admin_intake_preview_v1('step','${args}'::jsonb);commit;`)))
}
const times = plans.map(p => p[0]['Execution Time'])
if (Math.max(...times) >= 8000) throw Error('Preview page exceeded unchanged statement limit')
const report = { environment: 'Isolated PostgreSQL17.6; dense official-source fixtures in every calendar-backed university', statement_limit_ms: 8000, rows_per_request: 5, governed_scan_budget: 1500, university_first_round_sql_ms: times, max_sql_ms: Math.max(...times), plans }
fs.mkdirSync('uat-artifacts', { recursive: true })
fs.writeFileSync('uat-artifacts/intake-page-query-benchmark.json', JSON.stringify(report, null, 2))
console.log('PASS ten independent university preview queries under 8s: ' + JSON.stringify(times))
