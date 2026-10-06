import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 1850 adds the superseded Layer 3 work item status, is guarded, and only changes the status check', () => {
  const m = fs.readFileSync('supabase/migrations/20261006001850_cf247_layer3_work_item_superseded_status.sql', 'utf8')
  expect(m).toContain("conname = 'layer3_work_items_status_check'")
  expect(m).toContain("not like '%superseded%'")
  expect(m).toContain("raise exception 'layer3_work_items_status_check is not the expected definition; refusing to replace it'")
  expect(m).toContain("'failed','superseded']")
  for (const s of ['pending', 'reserved', 'interpreting', 'validated', 'no_candidate', 'rejected', 'admission_pending', 'layer4_required', 'admitted', 'parked', 'failed']) {
    expect(m).toContain(`'${s}'`)
  }
  expect(m).not.toMatch(/\b(truncate|cascade)\b/i)
  expect(m).not.toMatch(/delete\s+from|update\s+pipeline/i)
})
