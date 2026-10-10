// CF-247 v2.15.239 (S1, S2, S4): scholarship completeness, Platform Admin decisions of 11 Oct 2026 — "Published only, always",
// "Link all intl courses, marked", "Auto-publish, list for morning review".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('S1: the website and Zoho scholarship APIs serve published scholarships only', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011007100_cf247_s1_scholarships_published_only.sql', 'utf8')
  for (const md5 of ['f0a9139a1bbfbe4a4e28eb4d9e35d31c', '1cb75221bdbe043243d89242af388fef', '4168bdab5d6f2a3024adebfd476d8118', 'f30e2ba8bb604d2de77a9229774e9fad', 'a7b69e4e03d639ecd8f5c0e284f7b5e8', '1c1fa5c4cf652b28ad201b591cb8767f', '69a8ea24245da2dee64228492c400f8f']) expect(sql).toContain(md5)
  expect(sql).not.toContain("(not coalesce((f->>'published_only')::boolean,false) or s.publication_status='published')")
  expect(sql).not.toContain("(not v_published or s.publication_status='published')")
  expect(sql.match(/-- v2\.15\.239 \(S1\): published scholarships only, always/g).length).toBe(6)
  expect(sql).not.toMatch(/\b(drop\s+(table|function|schema|index|view)|delete\s+from|truncate)\b/i)
})

test('S2/S4: course links without a stated restriction, editions, hourly auto-publish, values read again', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011007200_cf247_s2_scholarship_fixes_auto_publish.sql', 'utf8')
  for (const md5 of ['1dfa8ba05fd210fe83209f56e751e943', 'dcf4351f9a3dbe3d8c6be09993681dcb']) expect(sql).toContain(md5)
  expect(sql).toContain("v_changes:=v_changes||'course_links_faculty_unmatched'::text;")
  expect(sql).not.toContain("v_changes:=v_changes||'course_links_need_review'::text;")
  expect(sql).toContain("where c.provider_id=s.provider_id and c.lifecycle_status='active' and c.open_to_international is not false;")
  expect(sql).toContain("then 'another edition of this scholarship is listed' end,")
  expect(sql).toContain("select cron.schedule('scholarship-auto-publish', '29 * * * *', 'select security.scholarship_auto_publish_v1()');")
  expect(sql).toContain("return security.scholarship_publish_batch_v1('auto-publish '")
  const own = sql.slice(sql.indexOf('-- 2. The series key'), sql.indexOf('CREATE OR REPLACE FUNCTION security.scholarship_sweep_apply_v1')) + sql.slice(sql.indexOf('-- 4. Data:'))
  expect(own).not.toMatch(/\b(drop\s+(table|function|schema|index|view)|delete\s+from|truncate)\b/i)
})

test('worker: an academic-result percentage is not the award value; value text is a whole sentence', () => {
  const s = fs.readFileSync('supabase/functions/coverage-sweep/scholarship.ts', 'utf8')
  expect(s).toContain('const pctsIn = (t: string) =>')
  expect(s).toContain('const otherPct = pctsIn(t).filter((v) => v >= 5 && v < 100);')
  expect(fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')).toContain('const SCH_VERSION = "scholarship-sweep-v0.6.3";')
})

test('workflow: database migrations applied with the md5 guard, no top-level drops, history checked', () => {
  const w = fs.readFileSync('.github/workflows/db-apply-migration.yml', 'utf8')
  expect(w).toContain("grep -nEi '^(drop|delete|truncate)\\b|^alter table .* drop '")
  expect(w).toContain('if [ "$got" != "$want" ]; then')
})
