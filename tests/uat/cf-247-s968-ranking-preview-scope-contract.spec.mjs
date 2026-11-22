// Guards: Platform Admin 22 Nov 2026 09:22 AEDT (IR-005 / RM1J): the THE and QS public readers finish inside the service-role statement limit
// s968 (second fix to s966): ranking-layer1-etl v1.8.1 sends the Australian reconciliation preview the Australian rows only (all 3,146 THE
// rows passed the 8 s limit), and the migration replaces the waiting s967 runs with fresh runs after the deploy.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const ETL = fs.readFileSync('supabase/functions/ranking-layer1-etl/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261122130000_cf247_s968_ranking_runs_after_preview_fix.sql', 'utf8')

test('s968: the Australian preview gets Australian rows only; the runs are queued again after the deploy', () => {
  expect(ETL).toMatch(/const VERSION="ranking-layer1-etl-v1\.8\.[1-9]\d*"/)
  expect(ETL).toContain('const previewRows=rows.filter((r:any)=>/^(australia|au|aus)$/i.test(clean(r.country_text)));')
  expect(ETL).toContain('{p_rows:previewRows,p_country_code:"AU",p_system_code:systemCode}')
  expect(ETL).not.toContain('{p_rows:rows,p_country_code:"AU"')
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toContain("'s968-rerun:' || s.id::text")
  expect(MIG).toContain("now() + interval '7 minutes',  -- fixed: fire guard")
  expect(MIG).toContain('(lease_until is null or lease_until < now())')
  expect(MIG).toContain('security.consumer_api_check_v1()')
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
