import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 162: RMIT fee basis read deterministically from "(YYYY annual|total)"; totals stay totals.
test('RMIT basis rule matches only the printed fee panel pattern and keeps totals as totals',()=>{
  const m=fs.readFileSync('supabase/migrations/20260928181000_d162_rmit_fee_basis_rule.sql','utf8')
  expect(m).toContain("'full-fee places:\\s*(?:a|au|aud)\\s*\\$\\s*{AMOUNT}\\s*\\((20[2-3][0-9])\\s+(annual|total)\\)'")
  expect(m).toContain('{"annual":"annual","total":"total_indicative"}')
  expect(m).toContain("date '2027-03-31'")
  expect(m).toContain("and not exists (select 1 from catalogue.course_fees f where f.course_id=w.entity_id and f.fee_type='provider_current_tuition' and f.status='active')")
  expect(m).toContain('insert into pipeline.provider_rule_admissions(')
  expect(m).not.toContain('provider_fee_profiles(')                         // not the single-basis UQ table
  const s=fs.readFileSync('supabase/migrations/20260928181100_d162_rmit_fee_basis_rule_schedule.sql','utf8')
  expect(s).toContain("'3-59/10 * * * *'")                                  // just before the Layer 3 dispatcher
})
