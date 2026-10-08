import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// 8 Oct 2026 (Platform Admin): one schedule choice per Layer 1 source; any ranking edition year can be uploaded.
test('Layer 1 schedule choice is Platform Admin only and logged; ranking years run two years ahead', () => {
  const m = fs.readFileSync('supabase/migrations/20261008002700_cf247_layer1_schedule_choice.sql', 'utf8')
  expect(m).toContain("coalesce(security.current_role_rank(), 0) < 6")
  expect(m).toContain("'layer1_schedule_set'")
  expect(m).toContain("p_schedule <> 'manual'")
  expect(m).not.toMatch(/update pipeline\.layer1_source_operations set auto_ingest/i)
  const ui = fs.readFileSync('src/layer1-operations-entry.jsx', 'utf8')
  expect(ui).toContain("supabase.rpc('admin_layer1_schedule'")
  expect(ui).toContain('data-l1-schedule')
  expect(ui).toContain('const top=new Date().getFullYear()+2')
  const mm = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(mm).toContain('const rankingYearOptions=()=>{const top=new Date().getFullYear()+2;return Array.from({length:top-2009},(_,i)=>top-i)}')
})
