import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 162 step 2: provider fee schedules read deterministically and written through the governed path.
test('Fee schedule worker is deterministic and bounded to registered schedules on university hosts',()=>{
  const w=fs.readFileSync('supabase/functions/fee-schedule-etl/index.ts','utf8')
  expect(w).toContain('const CODE_CELL = /^\\d{6}[0-9A-Z]$/;')
  expect(w).toContain('const feeAt = cells.findIndex((c, i) => i > idx[k] && i < end && FEE_CELL.test(c));')   // each course takes the fee after its own code
  expect(w).toContain('if (!(amount >= 12000 && amount <= 150000))')
  expect(w).toContain('english for academic|general english|elicos|english language')
  expect(w).toContain('svc_pilot_consume_nonce')
  expect(w).not.toMatch(/firecrawl|openrouter|json.*schema/i)                         // no AI extraction
})

test('Apply binds within the provider, never overwrites a same-year value, and keeps one current tuition',()=>{
  const m=fs.readFileSync('supabase/migrations-archive/20260928172000_d162_fee_schedule_sources_and_apply.sql','utf8')
  expect(m).toContain("c.provider_id=v_provider and c.lifecycle_status='active'")
  expect(m).toContain("'listed twice with different fees'")
  expect(m).toContain("'same fee year, different amount (Layer 4)'")
  expect(m).toContain("'newer fee year already current'")
  expect(m).toContain('public.svc_coursefacts_apply_record(')
  expect(m).toContain("coalesce(f.fee_year,0)<p_fee_year")
  expect(m).toContain('perform search.refresh_course_enrichment_scoped_v1(v_courses,true)')
})
