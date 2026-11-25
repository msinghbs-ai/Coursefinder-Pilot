// Guards: Platform Admin decision 26 Nov 2026 06:57 AEDT (option 2) and 08:19 AEDT (complete the sibling identity in the AI reader and recorder; correct routing defects through the existing mechanism; no blanket approval, lower threshold or new mechanism)
// s1192: the approved proven sibling page beside the existing title-identity extension in the machine check, AI read gate (entry only) and AI recorder; nothing else changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129010000_cf247_s1192_entry_sibling_identity_machine_and_ai.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1192: three md5-guarded one-line identity edits, each beside the existing title-identity extension', () => {
  for (const m of ['13aa1f26d18234413907861fd8b11642', 'd68665cb163bb99f7cca088d39cf595b', 'add21880f6671ed5dfc73fe6fd82f118']) expect(MIG).toContain(m)
  expect(MIG).toContain("or coalesce((security.entry_sibling_identity_v1(c.id, g.url)->>''ok'')::boolean, false)) then")
  expect(MIG).toContain("or (it.field = ''entry_requirements'' and coalesce((security.entry_sibling_identity_v1(it.course_id, g.url)->>''ok'')::boolean, false)));")
  expect(MIG).toContain("or coalesce((security.entry_sibling_identity_v1(i.course_id, g.url)->>''ok'')::boolean, false)) then")
  expect((MIG.match(/is not found exactly once/g) || []).length).toBe(3)
})

test('s1192: admission goes through the existing machine admission; no threshold, blanket approval or new mechanism; nothing dropped', () => {
  expect(MIG).toContain("v := security.aer_machine_admit_v1(r.id, 'run');")
  expect(code).not.toMatch(/update pipeline\.layer4_review_items|insert into catalogue\.course_entry_requirements|update catalogue\.course_entry_requirements|platform_toolset_settings|aer\.machine_mode|machine_daily_max|cron\.schedule|cron\.alter_job|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: a function does not use the proven sibling page', 'post-check: the identity rule of other fields changed', 'post-check: the number of active cron jobs changed', 'post-check: manual locks changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
