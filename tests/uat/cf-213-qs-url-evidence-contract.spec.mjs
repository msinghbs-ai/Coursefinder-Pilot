import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = path => fs.readFileSync(path, 'utf8')

test('CF-213 QS URL acquisition is allowlisted, Evidence-first and fail-closed', async () => {
  const src = read('supabase/functions/ranking-qs-url-import/index.ts')
  expect(src).toContain('https://www.topuniversities.com/world-university-rankings')
  expect(src).toContain('u.hostname!=="www.topuniversities.com"')
  expect(src).toContain('global_completeness_gate_failed_')
  expect(src).toContain('complete_qs_source_unavailable')
  expect(src).toContain('ranking_publisher_raw')
  expect(src).toContain('storage.from("evidence").upload')
  expect(src).toContain('CourseFinder Evidence.xlsx')
  expect(src).toContain('Raw Source')
  expect(src).toContain('Evidence Metadata')
  expect(src).toContain('apply=body.apply===true')
  expect(src).toContain('apply:false') === false
})

test('CF-213 release map uses corrected QS 2023 WUR release and edition-specific indicators', async () => {
  const src = read('supabase/functions/ranking-qs-url-import/index.ts')
  expect(src).toContain('2021:"2057712"')
  expect(src).toContain('2022:"3740566"')
  expect(src).toContain('2023:"3816281"')
  expect(src).not.toContain('2023:"3846211"')
  expect(src).toContain('2024:"3897789"')
  expect(src).toContain('2025:"3990755"')
  expect(src).toContain('2026:"4061771"')
  expect(src).toContain('2027:"4153156"')
  expect(src).toContain('3819456')
  expect(src).toContain('3897497')
})

test('CF-213 QS workbook parser preserves indicator ranks and rejects score sentinels', async () => {
  const src = read('supabase/functions/ranking-qs-official-etl/index.ts')
  expect(src).toContain('n>=0&&n<=100?n:null')
  expect(src).toContain('rank_display')
  expect(src).toContain('rank_exact')
  expect(src).toContain('rank_low')
  expect(src).toContain('rank_high')
  expect(src).toContain('indicator_group') === false
  expect(src).toContain('global edition requires at least 1000')
  expect(src).toContain('International Student Diversity')
})

test('CF-213 ranking ingest persists per-indicator rank semantics with service-only execution', async () => {
  const sql = read('supabase/migrations/20260905085600_cf_213_ranking_indicator_rank_semantics.sql')
  for (const field of ['indicator_group','rank_display','rank_exact','rank_low','rank_high','is_tied','rank_status']) {
    expect(sql).toContain(field)
  }
  expect(sql).toContain('revoke all on function public.svc_ranking_ingest_apply')
  expect(sql).toContain('grant execute on function public.svc_ranking_ingest_apply')
  expect(sql).toContain('to service_role')
})

test('CF-213 XLSX export is private and short-lived', async () => {
  const src = read('supabase/functions/ranking-evidence-export/index.ts')
  expect(src).toContain('createSignedUrl(row.storage_path,300')
  expect(src).toContain('inline://%')
  expect(src).toContain('authorised_role_required')
  expect(src).toContain('exportable_xlsx_evidence_not_found')
})
