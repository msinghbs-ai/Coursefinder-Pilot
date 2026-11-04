// Guards: retain the original synchronous preview as a measured baseline; actual paged-RPC acceptance is in intake-complete-scan/benchmark.mjs.
import {execFileSync} from 'node:child_process'
import fs from 'node:fs'
const sql="begin;set local statement_timeout='8s';set local lock_timeout='8s';set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);end$$;EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) select public.admin_intake_run_read_v1('preview','{\"scope\":\"top-au\",\"size\":20}');commit;"
fs.mkdirSync('uat-artifacts',{recursive:true})
const samples=[]
for(let i=0;i<5;i++) {
  try {
    const plan=JSON.parse(execFileSync('psql',['-X','-q','-At','-v','ON_ERROR_STOP=1','-d','intake_ui_fixtures','-c',sql],{encoding:'utf8',stdio:['ignore','pipe','pipe']}))
    samples.push({timed_out:false,milliseconds:plan[0]['Execution Time'],plan})
  } catch(e) {
    if(!/statement timeout/.test(e.stderr)) throw e
    samples.push({timed_out:true,sqlstate:'57014',statement_limit_ms:8000})
  }
}
const result={environment:'Isolated PostgreSQL17.6, unchanged 8s statement/lock limit, controlled skewed dataset; not production timing',purpose:'Historical synchronous baseline, not the replacement UI acceptance gate',replacement:'intake-complete-scan/benchmark.mjs enforces 8s on actual resumable requests; database browser suite requires complete scan and twenty-course admission/publication',samples}
fs.writeFileSync('uat-artifacts/intake-benchmark.json',JSON.stringify(result,null,2))
console.log('MEASURED legacy synchronous baseline; actual RPC performance guarded separately: '+JSON.stringify(samples.map(({timed_out,milliseconds,sqlstate})=>({timed_out,milliseconds,sqlstate}))))
