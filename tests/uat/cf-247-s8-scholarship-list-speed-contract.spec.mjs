// CF-247 bug (11 Oct 2026, Platform Admin screenshot): the Scholarships list timed out. Migration 20261011008300.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('published list skips publishability and builds counts for the page rows only; md5-guarded; nothing dropped', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011008300_cf247_scholarship_list_speed.sql', 'utf8')
  expect(sql).toContain("where coalesce(p_args->>'status', '') <> 'published'),")
  expect(sql).toContain("'value_label',scholarship.value_label(o.id),")
  expect(sql).toContain('"security.admin_scholarships_page(jsonb)": "1e0e5ca08c099dcc4f14e3515997b76b"')
  expect(sql).toContain('"security.admin_scholarships_page(jsonb)": "a27526afafe6d7fbc501224024e0f26f"')
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
})
