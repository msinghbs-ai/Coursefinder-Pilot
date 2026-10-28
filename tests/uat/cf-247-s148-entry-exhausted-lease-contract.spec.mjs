// Guards: CF-247 AER programme holds are recorded, never a silent skip (Platform Admin consolidated mandate 28 Oct 2026 23:22): an entry-matrix read whose lease ran out on its last try is closed as failed with the tries and last error named, by the existing fire job; nothing re-read, nothing spent, nothing dropped
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029006000_cf247_aer_exhausted_lease_closed.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('md5-guarded edit of the fire job; only expired leases with no tries left are closed, the reason named', () => {
  expect(code).toContain("select pg_temp.edit_n('security.entry_matrix_fire_v1()', '85d54db58fe5718080a69cd4a6937b36'")
  expect(code).toContain("where r.state = 'leased' and r.leased_until < now() and r.attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3);")
  expect(code).toContain("error = left('stopped after ' || r.attempts || ' tries without a reply: ' || coalesce(r.error, 'no error recorded'), 400)")
  expect(code).not.toMatch(/\b(drop|delete from|truncate|insert into)\b/i)
  expect(code).not.toMatch(/cron\.schedule/)
  expect(m).toMatch(/^-- Replaces: security\.entry_matrix_fire_v1/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
})
