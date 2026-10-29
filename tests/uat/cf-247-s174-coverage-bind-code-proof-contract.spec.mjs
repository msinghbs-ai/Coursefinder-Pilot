// Guards: CF-247 decision W31 (course-page identity and eligibility, 30 Oct 2026): the site-map binder (security.coverage_bind_v2) never re-scores, demotes or releases a page the reader has proved with a code or manual proof unless it is refused, and its release step only releases rows it bound itself; the labelled NZQA number rule in the reader's identity() applies to New Zealand pages only; md5-guarded edit, no re-binding, re-reading or promotion in the migration, identity gates unchanged
// No network: the migration text and the worker's pure identity() function.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { identity } from '../../supabase/functions/coverage-sweep/extract.ts'

const MIG = 'supabase/migrations/20261030030000_cf247_coverage_bind_code_proof.sql'
const sql = fs.readFileSync(MIG, 'utf8')

test('W31 migration: one md5-guarded edit of coverage_bind_v2 from the live definition read on 30 Oct 2026', () => {
  expect(sql).toContain("pg_temp.edit_n('security.coverage_bind_v2(uuid)', 'bc1872ed7df7d2837821600a8a18d55e'")
  expect(sql).toContain('-- Replaces: security.coverage_bind_v2 (same name, md5-guarded edit)')
  expect(sql).toContain('-- Retires: nothing')
  // the edit applies exactly once per change
  expect(sql).toMatch(/\], array\[1, 1\]\);/)
})

test('W31 upsert guard: a page read with a code or manual proof is left alone unless refused', () => {
  expect(sql).toContain("and not (pipeline.coverage_course_pages.read_status = 'read'")
  expect(sql).toContain("pipeline.coverage_course_pages.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual')")
  expect(sql).toContain('and not security.page_refused_v1(pipeline.coverage_course_pages.course_id, pipeline.coverage_course_pages.url));')
})

test('W31 release step: only rows the binder bound, never a code-proved page', () => {
  expect(sql).toContain("coalesce(p.basis,'') in ('title_match','cricos_code','nzqa_code','adapter_code')  -- W31: rows this binder bound")
  expect(sql).toContain("and not (p.read_status = 'read' and p.identity_basis in ('cricos_code','nzqa_code','adapter_code','manual') and not security.page_refused_v1(p.course_id, p.url))")
})

test('W31 changes nothing else: no re-bind, re-read, promotion, drop or delete; identity settings untouched', () => {
  const body = sql.replace(/^--.*$/gm, '')
  expect(body).not.toMatch(/\bnext_read_at\s*=/)
  expect(body).not.toMatch(/\bdrop\s+(table|function|view)\b/i)
  expect(body).not.toMatch(/\bdelete\s+from\b/i)
  expect(body).not.toMatch(/update\s+pipeline\.coverage_course_pages/i)
  expect(body).not.toMatch(/coverage_identity_allowed|identity_admission/i)
})

test('reader identity(): the labelled number proves an NZ page only; a Canadian page falls to the title rules', () => {
  const html = '<html><head><title>Business Administration</title></head><body><h1>Business Administration</h1><p>Program code 4521. Two years.</p></body></html>'
  const text = 'Business Administration Program code 4521. Two years.'
  expect(identity(html, text, 'Business Administration', '4521', false, 'NZ')).toBe('nzqa_code')
  expect(identity(html, text, 'Business Administration', '4521', false, 'CA')).not.toBe('nzqa_code')
  // an Australian page still needs its CRICOS code, unchanged
  expect(identity(html, 'Business Administration CRICOS 012345K', 'Business Administration', '012345K', false, 'AU')).toBe('cricos_code')
})
