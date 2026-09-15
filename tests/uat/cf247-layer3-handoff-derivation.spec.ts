import {test,expect} from '@playwright/test'
import fs from 'node:fs/promises'

test('CF-247 handoff derivation is explicit, evidence-backed and benchmark gated',async()=>{
  const sql=await fs.readFile('supabase/migrations/20260915144000_cf_247_layer3_handoff_derivation.sql','utf8')
  for(const token of [
    'layer3_enqueue_eligible_layer2_service',
    "provider_current_tuition_validation",
    "quality_benchmark->>'pass'",
    'enabled and not paused',
    'layer2_provider_attempts',
    'html_evidence_id',
    'raw_evidence_id',
    'storage_path is not null',
    'content_hash is not null',
    'multiple_equal_rank_fee_candidates',
    'low_confidence_international_fee_candidate',
    'no_fee_candidate',
    'service_role required',
    'CF-CHG-20260915-247'
  ]) expect(sql).toContain(token)
  expect(sql).not.toContain("task_class='course_description'")
  expect(sql).not.toContain('catalogue.course_fees')
  expect(sql).not.toContain('catalogue.course_links')
  expect(sql).toMatch(/revoke all on function public\.layer3_enqueue_eligible_layer2_service\(integer\) from public,anon,authenticated/i)
})
