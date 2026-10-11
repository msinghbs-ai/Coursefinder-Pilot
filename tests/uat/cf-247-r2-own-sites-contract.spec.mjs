// CF-247 v2.15.233 (R2): Platform Admin bug list of 10 Oct 2026 — Fix 1, Feature 1, Feature 3. Only the provider's own website, the
// regulator, or a value entered by hand may be a provider's website, course finder or course page. Hotcourses stays for logos only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261010006500_cf247_r2_own_sites_only.sql'

test('server: governed third-party list, verdict helper, refusals and data clean-up without deletes', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  for (const md5 of ['aa5234b75a902340aeac72c1f041f175', '153b3bd42d3c751deb5d37231feec9b8', 'b1cae71d7fa98cf35c42b73ec2846730', '21b1ff3858ad64d52e4ff36bcce85e23', '14a90dea54f2e42c7a3f3341b070871d', 'b616552481613710ccb923e84880cf16']) expect(sql).toContain(md5)
  for (const d of ['search.acir.com.au', 'higherstudy.com', 'oneuedu.com', 'coursesearch.studymelbourne.vic.gov.au', 'findthecourses.com.au', 'studyspy.ac.nz']) expect(sql).toContain(`'${d}')`)
  expect(sql).toContain('create or replace function security.third_party_host_v1(p_url text)')
  expect(sql).toContain('create or replace function security.provider_site_verdict_v1(p_provider_id uuid, p_url text)')
  expect(sql).toContain('or security.third_party_host_v1(p_url)  -- v2.15.233 (Feature 3)')
  expect(sql).toContain("'refused_why', 'third-party site, not the provider''s own'")
  expect(sql).not.toContain("union select d.provider_id, d.website_hint, d.site from pipeline.directory_institutions")
  expect(sql).toContain("raise exception 'that is a third-party course directory: use the provider''s own website or the regulator''s page'")
  expect(sql).toContain("raise exception 'that is a third-party course directory: the official page must be on the provider''s own website'")
  expect(sql).toContain("update catalogue.course_intakes x set status = 'withdrawn'")
  expect(sql).toContain("update catalogue.course_english_requirements x set status = 'withdrawn'")
  expect(sql).toContain("security.provider_site_verdict_v1(p.id, d.website) = 'own'")
  expect(sql).toContain("insert into search.refresh_requests(requested_by)")
  const data = sql.slice(sql.indexOf('-- 4. Existing data'), sql.indexOf('do $post$')) // the data steps delete nothing (function bodies kept as they were)
  expect(data.length).toBeGreaterThan(1000)
  expect(data).not.toMatch(/\b(drop\s+(table|function|schema|index|view)|delete\s+from|truncate)\b/i)
  expect(sql).not.toMatch(/\bdrop\s+(table|function|schema)\b/i)
  // Hotcourses is still a logo directory
  expect(sql).not.toMatch(/hotcourses[^\n]*retired_at\s*=/i)
})

test('worker: an AU site needs the CRICOS code on its home page, or a deeper page on an address that fits the name', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toMatch(/coverage-sweep-worker-v0\.(?:17\.(3[2-9]|[4-9][0-9])|1[8-9]\.\d+)/)
  expect(w).toContain('const ok = found && (home || fits) && !SKIP.test(finalHost);')
  expect(fs.readFileSync('supabase/functions/coverage-sweep/extract.ts', 'utf8')).toContain('const siteNorm = (s: string) =>') // shared file unchanged
})

test('UI: the provider panel says whose the website and course finder are', () => {
  const ed = fs.readFileSync('src/RecordEditor.jsx', 'utf8')
  expect(ed).toContain("third_party:['Third-party site: not used','tone-danger']")
  expect(ed).toContain('<SiteVerdict v={cf.verdict}/>')
  expect(ed).toContain('<SiteVerdict v={p.website_verdict}/>')
})
