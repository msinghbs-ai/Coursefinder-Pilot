// Guards: CF-247 AU completion week step 6 (Platform Admin 26 Oct 2026 17:01): entry-matrix reader staged for the AU top 20, off until the Platform Admin confirms
// The provider list is a setting (G2); the one gate every entry-matrix path uses honours it; nothing is switched on by this change.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261026005000_cf247_entry_matrix_au_top20_staged.sql', 'utf8')

test('entry.providers holds exactly the 20 AU providers; the gate honours it, md5-guarded', () => {
  const row = m.slice(m.indexOf("('pipeline', 'entry.providers'"), m.indexOf('on conflict (toolset_key, key) do nothing;'))
  const ids = row.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g)
  expect(new Set(ids).size).toBe(20)
  expect(m).toContain("pg_temp.edit_n('security.entry_matrix_enabled_v1(uuid)', 'a238a2c24f19f8dd9fa1bb6435d8ca75'")
  expect(m).toContain("or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text)")
  expect(m).toContain("jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb)) = 0")
})

test('nothing switched on: no change to entry.matrix_enabled or the job; nothing dropped or deleted', () => {
  expect(m).not.toMatch(/update\s+pipeline\.platform_toolset_settings/i)
  expect(m).not.toMatch(/cron\.(schedule|alter_job)/)
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
