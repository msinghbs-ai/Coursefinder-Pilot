// Guards: CF-247 UI audit Phase 3 (Platform Admin 24 Oct 2026 11:27): one source for the Inbox counts, reconciled scholarship figures, one header on Provider contacts, the ranking-import…
// CF-247 UI audit Phase 3 (Platform Admin 24 Oct 2026 11:27): one source for the Inbox counts, reconciled scholarship figures,
// one header on Provider contacts, the ranking-import kicker under its own screen, unnamed register records said plainly.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations-archive/20261024008000_cf247_ui_audit_phase3_dedupe.sql', 'utf8')
const dash = fs.readFileSync('src/ui-v1/DashboardView.jsx', 'utf8')
const pc = fs.readFileSync('src/ProviderContactsWorkspace.jsx', 'utf8')
const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')

test('migration: additive scholarship figures on the dashboard read (md5-guarded); one campus city corrected under a count guard; nothing dropped', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate|delete\s+from)\b/im)
  expect(m).toContain("select pg_temp.edit_n('security.admin_dashboard_maturity_compute()', '240d606e62a4ae008712e0d18e99eba5', array[")
  expect(m).toContain("'scholarships_published',(select count(*) from scholarship.scholarships where lifecycle_status='active' and publication_status='published')")
  expect(m).toContain("if n <> 1 then raise exception 'expected exactly one active campus with a street for a city, found %', n; end if;")
})


test('Provider contacts has one header; the ranking-import kicker names its own screen; a register placeholder name is said plainly', () => {
  expect(pc).not.toContain('<h2>Provider Contacts</h2>')
  expect(pc).not.toContain('pc-hero ') // Phase 1 (24 Oct 2026): the actions-only hero band became a plain toolbar
  expect(pc).toContain('<div className="pc-toolbar" data-pc-toolbar>')
  expect(ui).toContain('<div className="m-section-kicker">Rankings &amp; statistics / Ranking imports</div>')
  expect(ui).not.toContain('Reference data / Ranking imports')
  expect(ui).toContain("const NO_NAME=/^(n\\/?a|-+|—|none|null|unknown)$/i")
  expect(ui).toContain("return{text:`Unnamed on the register${code?` (${code})`:''}`,unnamed:true}")
})
