// Guards: F-SCH redesign R1 first-cohort check (12 Nov 2026 17:05): the detail fill writes no eligibility conditions until exclusions and their headings are represented; unsupported claims stay protected (directive 12 Nov 2026 16:12 §5, §14 item 5)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration 20261113063000 holds the condition fill (md5-guarded) and supersedes, never deletes, the passages written', () => {
  const m = fs.readFileSync('supabase/migrations/20261113063000_cf247_sch_detail_criteria_hold.sql', 'utf8')
  expect(m).toContain("'476dbc9eefac8a3567adc690d6576b04'")
  expect(m).toContain("if false and jsonb_array_length(coalesce(c->'criteria', '[]')) > 0")
  expect(m).toContain("update scholarship.criteria set status = 'superseded'\n where status = 'active' and criterion_type = 'published_eligibility_narrative' and value_json->>'by' = 'sch-extract-v3';")
  expect(m).not.toMatch(/^\s*delete\b/im)
})
