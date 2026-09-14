import {test,expect} from '@playwright/test'
import fs from 'node:fs'

const migration='supabase/migrations/20260913101000_cf_093_layer2_discovery_terminal_timestamp_observability.sql'

test('Layer 2 discovery terminal timestamp guard is narrow and observability-only',()=>{
  const sql=fs.readFileSync(migration,'utf8')
  expect(sql).toContain("new.job_type='layer2_discovery'")
  expect(sql).toContain("new.status in ('completed','failed','cancelled','blocked','succeeded','success')")
  expect(sql).toContain('new.completed_at is null')
  expect(sql).toContain('new.completed_at:=clock_timestamp()')
  expect(sql).toContain('before insert or update of status,completed_at on pipeline.jobs')
  expect(sql).not.toMatch(/layer2_provider|layer2_evidence|search_|publication|retry_max|concurrency|batch_size/i)
})
