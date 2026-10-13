// CF-247 v2.15.272 (S35): Platform Admin, 14 Oct 2026 10:14 "Proceed" (settings audit 1.2 correction). The automatic publication flag
// changed nothing, so the Layer 4 publish preview stops reading it; the table is retired by a paste file, never by a migration.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('the publish preview no longer reads or prints the automatic publication flag', () => {
  const mig = fs.readFileSync('supabase/migrations/20261014013400_cf247_publication_preview_stops_reading_flag.sql', 'utf8')
  const fn = mig.slice(mig.indexOf('CREATE OR REPLACE FUNCTION l4_api.publication_control_preview('))
  expect(fn).not.toContain('publication_control_settings')
  expect(fn).not.toContain("'auto_publication_enabled'")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(fs.readFileSync('src/Layer4Intervention.jsx', 'utf8')).not.toContain('Automatic publication')
})
