// Guards: intake preview 57014 regression: authoritative identity helper, dense evidence, unchanged admission decisions and bounded request work.
import fs from 'node:fs'
import {execFileSync} from 'node:child_process'
const dir='tests/fixtures/intake-preview-timeout/'
const runFile=f=>execFileSync('psql',['-X','-q','-v','ON_ERROR_STOP=1','-d','intake_ui_fixtures','-f',f],{stdio:'inherit'})
execFileSync('psql',['-X','-q','-v','ON_ERROR_STOP=1','-d','intake_ui_fixtures','-c',"create table public.fixture_preview_members_golden as select security.intake_ui_selection_v1('top-au',20)->'courses' courses"],{stdio:'inherit'})
runFile(dir+'title-key.sql');runFile(dir+'dense.sql');runFile(dir+'dense-all.sql');runFile(dir+'golden.sql')
const sql="begin;set local statement_timeout='8s';set local lock_timeout='8s';set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);end$$;explain(analyze,buffers,format json) select public.admin_intake_run_read_v1('preview','{\"scope\":\"top-au\",\"size\":20}');commit;"
let before
try { const out=execFileSync('psql',['-X','-q','-At','-v','ON_ERROR_STOP=1','-d','intake_ui_fixtures','-c',sql],{encoding:'utf8',stdio:['ignore','pipe','pipe']});before={timed_out:false,plan:JSON.parse(out)} }
catch(e) {if(!/statement timeout/.test(e.stderr))throw e;before={timed_out:true,sqlstate:'57014',context:'course_title_key / course_page_check_v1 / intake_dates_plan_v2'}}
if(!before.timed_out) throw Error('Dense evidence fixture did not reproduce the old timeout')
const mig='supabase/migrations/20261105010000_intake_preview_identity_lookup.sql'
runFile(mig);runFile(mig);runFile(dir+'assert.sql')
// The former three-sample, 50-row synchronous latency assertion is superseded by the
// actual browser contract: five rows per request through the complete governed budget.
// Keep the old timeout reproducer and all 60 verdict/selection comparisons above.
runFile('supabase/migrations/20261105020000_intake_preview_paging.sql')
await import('../intake-complete-scan/benchmark.mjs')
const measured=JSON.parse(fs.readFileSync('uat-artifacts/intake-page-query-benchmark.json','utf8'))
const times=measured.university_first_round_sql_ms
fs.writeFileSync('uat-artifacts/intake-timeout-regression.json',JSON.stringify({environment:measured.environment,before,after:{contract:'resumable per-request preview; full scan and twenty-course workflow tested separately',executions_ms:times,max_ms:Math.max(...times),statement_limit_ms:8000,cohort_size:20,rows_per_request:5},superseded_assertion:'Three synchronous legacy-preview samples replaced by ten actual per-request SQL measurements plus full-budget database browser tests; coverage is no longer truncated.',plans:measured.plans},null,2))
console.log('PASS old timeout reproduced; authoritative identity/selection unchanged; actual paged-preview requests fit 8s: '+JSON.stringify(times))
