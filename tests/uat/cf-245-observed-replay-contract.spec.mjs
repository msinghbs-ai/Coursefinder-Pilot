import{test,expect}from'@playwright/test'
import fs from'node:fs/promises'

const read=p=>fs.readFile(p,'utf8')

test.describe('CF-245 stored Evidence replay contract',()=>{
 test('reuses only qualified deterministic facts and isolates tuition for Layer 3',async()=>{
  const base=await read('supabase/migrations/20260915014733_cf_245_observed_artifact_replay_and_layer3_backlog_v1.sql')
  const fix=await read('supabase/migrations/20260915014810_cf_245_observed_artifact_replay_boolean_fix_v1_1.sql')
  const fee=await read('supabase/migrations/20260915020403_cf_245_layer3_tuition_validation_profile_v1.sql')
  const sql=base+'\n'+fix
  for(const text of [
   'svc_cf245_replay_observed_coursefacts',"qualification_status in ('qualified','bounded')",'apply_admitted','identity_match','regulatory_code_seen',
   "layer4_entity_or_parent_blocked('course'","'intake'=any(admitted_domains)","'english_requirement'=any(admitted_domains)",
   'between 1 and 9','between 10 and 90','between 1 and 120','deterministic_observed_replay','cf245_layer3_fee_validation_backlog_v1',
   'requires_layer3_fee_validation','benchmark_required_before_automatic_interpretation','CF-CHG-20260915-245'
  ])expect(sql).toContain(text)
  expect(sql).toMatch(/revoke all on function public\.svc_cf245_replay_observed_coursefacts\(integer,boolean,uuid\) from public,anon,authenticated/i)
  expect(sql).toMatch(/grant execute on function public\.svc_cf245_replay_observed_coursefacts\(integer,boolean,uuid\) to service_role/i)
  expect(sql).toMatch(/revoke all on pipeline\.cf245_layer3_fee_validation_backlog_v1 from public,anon,authenticated/i)
  expect(sql).not.toContain('insert into catalogue.course_fees')
  expect(fix).toContain("coalesce(('english_requirement'=any(admitted_domains))")
  for(const text of ['openrouter-provider-tuition-validation-v1','provider_current_tuition_validation','configured_but_paused_pending_fee_specific_benchmark',"'pass',false",'benchmark_required','loan cap','international_student_required'])expect(fee).toContain(text)
  expect(fee).toContain('enabled=true,paused=true')
  expect(fee).not.toContain("'pass',true")
 })
})
