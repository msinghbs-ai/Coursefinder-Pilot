// Guards: Admin #937 (NZ scoped scholarship recovery), SCH-FU-04, Platform Admin 24 Nov 2026 20:35 and 20:41 AEDT (integrate the existing NZ implementation; no new cron; protected controls kept)
// s1055: the four approved NZ universities leave the listing cap only under the named, scholarships-scoped, unexpired on-demand request; the committed regression fixture runs inside the migration.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261125130000_cf247_s1055_nz_scoped_scholarship_recovery.sql', 'utf8')
const FIX = fs.readFileSync('tests/fixtures/scholarship-recovery/nz-scoped-on-demand-regression.sql', 'utf8')

test('s1055: the exception is only for the approved request: four providers, named reason, scholarships purpose, a cap estimate, not expired', () => {
  for (const id of ['e096aba7-e1eb-4903-9a63-2bfb71e9a8b8', 'db910e88-67d1-4d2b-a65c-cea290aa0692', 'ab12c7f8-e368-453d-9dfe-4ab8bd744829', '34616965-b2b7-42a7-8da7-50ffbf120958']) expect(MIG).toContain(id)
  expect(MIG).toContain("r.reason = 'Admin #937: S3-Scholarship-ChatGPT NZQA listing recovery'")
  expect(MIG).toContain("r.purpose_groups = array['scholarships']::text[]")
  expect(MIG).toContain("r.estimate ? 'cap_firecrawl_units'")
  expect(MIG).toContain("security.on_demand_request_for_v2(p_provider_id, 'sch_listing')")
  expect(MIG).toContain('and security.fc_sch_eligible_v1(p_provider_id)')
  expect(MIG).toContain("if md5(d) <> '1b9bbe30b3570d321b036a75c868683a' then")
})

test('s1055: every assertion of the committed regression fixture runs inside the migration, in a block that always rolls back', () => {
  const checks = FIX.split('\n').filter((l) => /raise exception|on_demand_open_v1|on_demand_scope_v1|expires_at=now\(\)/.test(l)).map((l) => l.trim())
  expect(checks.length).toBeGreaterThanOrEqual(10)
  for (const c of checks) expect(MIG).toContain(c)
  expect(MIG).toContain("raise exception 'S1055_REGRESSION_OK';")
  expect(MIG).toContain("if sqlerrm <> 'S1055_REGRESSION_OK' then raise exception 's1055 regression failed: %', sqlerrm; end if;")
  expect(MIG).not.toMatch(/cron\.schedule|cron\.alter_job|platform_toolset_settings/i)
})
