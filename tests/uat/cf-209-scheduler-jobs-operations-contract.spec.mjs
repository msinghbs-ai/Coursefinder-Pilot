// Guards: CF-209 Scheduling remains a bounded governed read surface
import{test}from'@playwright/test'  // 26 Oct 2026 (test governance): was node:test, which Playwright loaded but never counted or failed on
import assert from'node:assert/strict'
import{readFile}from'node:fs/promises'

const read=p=>readFile(new URL(`../../${p}`,import.meta.url),'utf8')
const escaped=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')

test('CF-209 Layer 2 scheduler dispatch and recovery are bounded and non-destructive',async()=>{
 const sql=await read('supabase/migrations-archive/20260827224000_m2_4_2_layer2_refresh_housekeeping.sql')
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
 ])assert.match(sql,new RegExp(escaped(token)))
 assert.match(sql,/Recovery only: governed Evidence, immutable profile versions, provider-attempt history, run history and canonical history are retained/)
 assert.match(sql,/service_role required/)
})

