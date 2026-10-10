// CF-247 v2.15.241 (S6): the platform is renamed StudySearch (customer request, 11 Oct 2026). Visible text only; identifiers,
// saved-settings keys, Wix/Zoho contract names and the repositories are unchanged until production.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('app text says StudySearch; identifiers stay', () => {
  expect(fs.readFileSync('index.html', 'utf8')).toContain('<title>StudySearch PIM Admin</title>')
  const m = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(m).toContain('<span className="m-brand-mark">SS</span><span className="m-brand-copy"><strong>StudySearch</strong>')
  expect(m).not.toMatch(/\bCoursefinder\b|\bCourseFinder\b/)
  expect(fs.readFileSync('src/release-currentness-entry.js', 'utf8')).toContain('StudySearch PIM Admin v')
  expect(fs.readFileSync('src/ui-kit.jsx', 'utf8')).toContain('coursefinder:pim:screen-state:v1:') // saved screen settings keep their key
})

test('database messages renamed in 82 functions, md5-guarded, nothing dropped', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011007700_cf247_s6_studysearch_messages.sql', 'utf8')
  expect(sql).not.toContain('CourseFinder role required')
  expect(sql).toContain('StudySearch role required')
  expect(sql.match(/CREATE OR REPLACE FUNCTION/g).length).toBe(82)
  expect(sql).toContain("raise exception 'CF-247 v2.15.241 post-check: a function still says CourseFinder'")
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
})
