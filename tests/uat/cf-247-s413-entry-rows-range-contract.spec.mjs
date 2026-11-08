// Guards: Platform Admin directive 8 Nov 2026 item 1 (RMIT row-limit recovery: the permitted maximum of entry.max_rows_per_course is engineered from 10 to 19, the global value stays 6, other providers and the E13/D-R2 checks are unchanged, nothing is cut or admitted), G2 (a range is setting metadata), G3, Decision 260
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261108010000_cf247_entry_rows_range_19.sql', 'utf8')
const body = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the range maximum becomes 19, guarded on the live values (value 6, maximum 10), and the global value is not changed', () => {
  expect(body).toMatch(/set max_value = 19/)
  expect(body).toMatch(/max_value = 10 and value = to_jsonb\(6\)/)
  expect(body).toMatch(/set max_value = 19, updated_by = v_pa, updated_at = now\(\),\s*reason = '[^']*'\s*where/)   // the SET clause holds the range, the actor and the reason only: the migration never sets a value
  expect(body).toMatch(/if \(v_before->>'max_value'\)::numeric = 19 then return; end if/)   // a second run changes nothing
  expect(body).toMatch(/if v_n <> 1 then raise exception/)
})

test('it touches one setting only, writes an audit event with the values before, and sets no provider override', () => {
  expect((body.match(/update pipeline\.platform_toolset_settings/g) || []).length).toBe(1)
  expect(body).toContain("'toolsets', 'setting', 'pipeline/entry.max_rows_per_course'")
  expect(body).toContain("'before', v_before")
  expect(body).not.toMatch(/entry\.max_rows_by_provider/)
  expect(body).not.toMatch(/layer4_review_items|course_entry_requirements|catalogue\./)   // nothing is approved, admitted or published
})

test('housekeeping lines are present and the consumer API is not touched', () => {
  expect(sql).toMatch(/^-- Replaces: nothing/m)
  expect(sql).toMatch(/^-- Retires: nothing/m)
  expect(body).not.toMatch(/website_v2_|website_edge_|zoho_edge_|svc_website_settings_v1|\bapi\./)
})
