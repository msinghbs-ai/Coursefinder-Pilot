// v2.15.119: Parse.bot removed completely (Platform Admin, 1 Oct 2026). Ranking imports are file upload only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'

const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)])

test('no screen, API helper or edge function refers to Parse.bot; the URL import functions are gone', () => {
  const files = [...walk('src'), ...walk('supabase/functions')].filter(f => /\.(jsx?|tsx?|css)$/.test(f) && !f.endsWith('pim-version-entry.js') && !f.endsWith('release-manifest.js'))
  for (const f of files) expect(fs.readFileSync(f, 'utf8'), f).not.toMatch(/parse\.?bot/i)
  for (const fn of ['ranking-publisher-url-import', 'ranking-qs-url-import', 'ranking-the-url-import']) expect(fs.existsSync(`supabase/functions/${fn}`)).toBe(false)
  const m = fs.readFileSync('supabase/migrations-archive/20260930170000_cf247_remove_parsebot.sql', 'utf8')
  expect(m).toContain("raise exception 'Parse.bot has fetch history; refusing to delete it'")
  expect(m).toContain('delete from pipeline.layer2_profile_provider_routes where acquisition_provider_id = v_id;')
  expect(m).toContain("<> 'f86a250be8b9ef8e4a3372bf6d563f88'")
  expect(m).toContain("<> '717772bc7b7bd0d4b99997ab298b407e'")
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain('Publisher file(s)<input type="file" multiple')
  expect(main).not.toContain('Import method')
})
