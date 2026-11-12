// Guards: F-SCH redesign developer field contract step 1 (Platform Admin 12 Nov 2026 20:19): verified sponsor, award type, rolling applications and benefits are stored beside the consumer tables; nothing the website or Zoho reads changes (G3)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113068000_cf247_sch_award_details.sql', 'utf8')

test('a new table beside the consumer tables, written from verified passages only, empty fields only', () => {
  expect(m).toContain('create table if not exists scholarship.award_details (')
  expect(m).toContain('comment on table scholarship.award_details is')
  expect(m).not.toMatch(/^-- Consumer API change approved:/m) // no consumer change in this step
  expect(m).not.toMatch(/create\s+or\s+replace\s+function\s+(api\.|public\.(website_v2_|website_edge_|zoho_edge_))/i)
  expect(m).toContain("if coalesce((c->>'award_type')::boolean, false)")
  expect(m).toContain("if coalesce((c->>'identity')::boolean, false) then")
  expect(m).toContain("where scholarship_id = p_scholarship and award_type is null")
  expect(m).toContain("not exists (select 1 from scholarship.coverage cv where cv.scholarship_id = p_scholarship and cv.notes like 'sch-extract-v3:%')")
  expect(m).toContain("'36efaa75305b1724fb3daa2afaecd28e'")
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
