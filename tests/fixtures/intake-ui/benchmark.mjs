// Guards: PR #872 cohort selection fits production authenticated statement_timeout=8s.
import {execFileSync} from 'node:child_process'
import fs from 'node:fs'
const sql="begin;set local statement_timeout='8s';set local lock_timeout='8s';set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);end$$;EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) select public.admin_intake_run_read_v1('preview','{\"scope\":\"top-au\",\"size\":20}');commit;"
fs.mkdirSync('uat-artifacts',{recursive:true})
const plans=[]
for(let i=0;i<5;i++) plans.push(JSON.parse(execFileSync('psql',['-X','-q','-At','-v','ON_ERROR_STOP=1','-d','intake_ui_fixtures','-c',sql],{encoding:'utf8'})))
const times=plans.map(p=>p[0]['Execution Time']).sort((a,b)=>a-b)
const result={environment:'Isolated PostgreSQL 17.6, production 8-second authenticated timeout enforced on each query; controlled skewed dataset, not production timing',university_count:10,dominant_active_courses:5200,dominant_intake_candidates:2700,configured_scan_rows:1500,per_university_scan_limit:150,cohort_size:20,executions_ms:times,median_ms:times[2],max_ms:times[4],plans}
if(result.max_ms>=8000) throw Error('Preview exceeded production statement timeout')
fs.writeFileSync('uat-artifacts/intake-benchmark.json',JSON.stringify(result,null,2))
console.log('PASS preview performance '+JSON.stringify({median_ms:result.median_ms,max_ms:result.max_ms,limit_ms:8000}))
