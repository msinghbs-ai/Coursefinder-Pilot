import {test,expect} from '@playwright/test'
import fs from 'node:fs/promises'

test('CF-247 durable Layer 3 work queue is service-owned, idempotent and bounded',async()=>{
  const sql=await fs.readFile('supabase/migrations/20260915113000_cf_247_layer3_work_queue_foundation.sql','utf8')
  for(const token of [
    'pipeline.layer3_work_items',
    'unique(layer2_run_item_id,evidence_id,task_class,policy_version)',
    'for update of w skip locked',
    "status in ('pending','failed')",
    "p.enabled and not p.paused",
    "quality_benchmark->>'pass'",
    'layer3_enqueue_from_layer2_service',
    'layer3_reserve_work_service',
    'layer3_work_item_transition_service',
    "v_item.status<>'layer3_required'",
    'retained governed Evidence required',
    'service_role required',
    'CF-CHG-20260915-247'
  ]) expect(sql).toContain(token)
  expect(sql).toMatch(/revoke all on pipeline\.layer3_work_items from public,anon,authenticated/i)
  expect(sql).toMatch(/grant select,insert,update on pipeline\.layer3_work_items to service_role/i)
  expect(sql).not.toMatch(/grant .*layer3_work_items.*authenticated/i)
  expect(sql).not.toContain('catalogue.course_fees')
  expect(sql).not.toContain('catalogue.course_links')
})
