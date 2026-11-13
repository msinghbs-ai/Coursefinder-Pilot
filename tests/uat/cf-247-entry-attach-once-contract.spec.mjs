// Guards: Platform Admin 13 Nov 2026 09:30 (fix the shared throughput cause through a normal release): the entry-source attach step ranks pages exactly as before and checks each provider once, only for pages not attached yet
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113291500_cf247_entry_matrix_attach_once_per_provider.sql', 'utf8')

test('same ranking and limits; the allowed check runs once per remaining provider; nothing deleted', () => {
  expect(M).toContain("'b2a3fbdc77633618cee0b1914fbdc336'")
  expect(M).toContain("row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc, length(e->>'url')) rn")
  expect(M).toContain('and not exists (select 1 from pipeline.entry_matrix_sources m where m.provider_id = x.provider_id and m.url = x.url)')
  expect(M).toContain('ok as materialized (select p.provider_id from (select distinct n.provider_id from n) p where security.entry_matrix_attach_allowed_v1(p.provider_id))')
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
