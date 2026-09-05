import test from'node:test'
import assert from'node:assert/strict'
import{readFile}from'node:fs/promises'

const read=p=>readFile(new URL(`../../${p}`,import.meta.url),'utf8')

test('CF-209 Scheduling remains a bounded governed read surface',async()=>{
 const[src,mature]=await Promise.all([read('src/m2-3-intelligence-entry.jsx'),read('src/mature-main.jsx')])
 assert.match(mature,/key:'scheduling',label:'Scheduling'/)
 assert.match(mature,/RefreshWorkspace/)
 assert.match(src,/refresh_intelligence_overview/)
 assert.match(src,/Source\/entity freshness policies/)
 assert.match(src,/Targeted refresh queue/)
 assert.match(src,/Downstream Search refresh signals/)
 assert.match(src,/next_due_at/)
 assert.match(src,/revalidation_ref/)
 assert.doesNotMatch(src,/Retry scheduled refresh|Replay scheduled refresh|Reset scheduled refresh/)
})

test('CF-209 Layer 2 scheduler dispatch and recovery are bounded and non-destructive',async()=>{
 const sql=await read('supabase/migrations/20260827224000_m2_4_2_layer2_refresh_housekeeping.sql')
 for(const token of[
  'layer2_refresh_scheduler_tick_impl',
  "r.status='queued'",
  'for update of r skip locked',
  'layer2_scope_profile_batch_service',
  "revalidation_ref='L2BATCH:'",
  "status='completed'",
  "status='failed'",
  "interval '45 minutes'",
  'svc_layer2_housekeeping',
  'governed_evidence_deleted',
  'coursefinder-layer2-refresh-dispatcher',
  "'3,18,33,48 * * * *'",
  'coursefinder-layer2-housekeeping'
 ])assert.match(sql,new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')))
 assert.match(sql,/Recovery only: governed Evidence, immutable profile versions, provider-attempt history, run history and canonical history are retained/)
 assert.match(sql,/service_role required/)
})

test('CF-209 Jobs stays server-paged, telemetry-rich and mutation-free',async()=>{
 const src=await read('src/pipeline-ops-entry.jsx')
 for(const token of[
  "adminRead('pipeline_filters')",
  "adminRead('pipeline_jobs_page'",
  "adminRead('pipeline_job_detail'",
  'completion_class',
  'failure_class',
  'evidence_count',
  'duration_ms',
  'resume_cursor',
  'Destructive controls are not generic operations',
  'Retry, replay and reset remain disabled here',
  'adapter-specific scope, idempotency proof, explicit confirmation and an auditable action contract'
 ])assert.match(src,new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')))
 assert.doesNotMatch(src,/adminRead\('pipeline_job_(retry|replay|reset)'/)
})
