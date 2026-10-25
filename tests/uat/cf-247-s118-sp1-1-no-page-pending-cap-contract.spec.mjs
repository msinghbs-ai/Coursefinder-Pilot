// CF-247 SP-1.1: a new no-page / conjoint first run opens only while fewer than bind.no_page_pending_max are waiting in Layer 4.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261025004000_cf247_sp1_1_no_page_pending_cap.sql', 'utf8')
test('pending cap on first runs, as a setting, md5-guarded edit', () => {
  expect(m).toMatch(/pg_temp\.edit_n\('security\.no_page_propose_v1\(\)', '[0-9a-f]{32}'/)
  expect(m).toContain(">= security.pipeline_num_v1('bind.no_page_pending_max', 60))")
  expect(m).toMatch(/\('pipeline', 'bind\.no_page_pending_max', [^\n]*'number', '60'::jsonb, 5, 500,/)
  expect(m).toMatch(/^-- Replaces: nothing \(security\.no_page_propose_v1 edited in place, md5-guarded\)\n-- Retires: nothing$/m)
})
