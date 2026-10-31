// Guards: CF-247 v2.15.241 (S6) and StudySearch SS-013 (Platform Admin 31 Oct 2026 14:27): the platform's visible identity is StudySearch; history, saved-settings keys, identifiers, contracts and repositories are kept
// CF-247 v2.15.241 (S6): the platform is renamed StudySearch (customer request, 11 Oct 2026). Visible text only; identifiers,
// saved-settings keys, Wix/Zoho contract names and the repositories are unchanged until production.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('app text says StudySearch; identifiers stay', () => {
  expect(fs.readFileSync('index.html', 'utf8')).toContain('<title>StudySearch PIM Admin</title>')
  const m = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(m).toContain('<span className="m-brand-mark">SS</span><span className="m-brand-copy"><strong>StudySearch</strong>')
  expect(m).not.toMatch(/\bCoursefinder\b|\bCourseFinder\b/)
  expect(fs.readFileSync('src/ReleaseNotes.jsx', 'utf8')).toContain('StudySearch PIM Admin v') // v2.15.291: replaces release-currentness-entry.js
  expect(fs.readFileSync('src/ui-kit.jsx', 'utf8')).toContain('coursefinder:pim:screen-state:v1:') // saved screen settings keep their key
})

test('SS-013 (31 Oct 2026): no screen, title, test name or workflow name uses the former name; history, keys and identifiers stay', () => {
  const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(`${d}/${e.name}`) : [`${d}/${e.name}`])
  // release history is a record (release-history-legacy.js; the accepted releases in release-manifest.js) and is never rewritten
  for (const f of walk('src').filter((f) => /\.(jsx?|css|html)$/.test(f) && !/release-history-legacy\.js$|release-manifest\.js$/.test(f)))
    expect(fs.readFileSync(f, 'utf8'), f).not.toMatch(/CourseFinder|Course-Finder/)
  const manifest = fs.readFileSync('src/release-manifest.js', 'utf8')
  expect(manifest.slice(manifest.indexOf('export const RELEASE='), manifest.indexOf('// Ordered accepted releases.'))).not.toMatch(/CourseFinder/)
  for (const f of walk('tests/uat')) for (const m of fs.readFileSync(f, 'utf8').matchAll(/test(?:\.describe)?\([`'"]([^`'"]*)/g)) expect(m[1], f).not.toMatch(/CourseFinder/)
  for (const f of walk('.github/workflows')) expect(fs.readFileSync(f, 'utf8').match(/^name: .*$/m)?.[0] || '', f).not.toMatch(/CourseFinder/)
  // identifiers kept for compatibility (inventory: admin docs/platform/STUDYSEARCH-IDENTITY-INVENTORY.md)
  expect(fs.readFileSync('package.json', 'utf8')).toContain('"name": "coursefinder-pilot"')
  expect(fs.readFileSync('src/ProviderLogo.jsx', 'utf8')).toContain("'coursefinder:provider-logo-refresh'")
})

test('database messages renamed in 82 functions, md5-guarded, nothing dropped', () => {
  const sql = fs.readFileSync('supabase/migrations/20261011007700_cf247_s6_studysearch_messages.sql', 'utf8')
  expect(sql).not.toContain('CourseFinder role required')
  expect(sql).toContain('StudySearch role required')
  expect(sql.match(/CREATE OR REPLACE FUNCTION/g).length).toBe(82)
  expect(sql).toContain("raise exception 'CF-247 v2.15.241 post-check: a function still says CourseFinder'")
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
})
