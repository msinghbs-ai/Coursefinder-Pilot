// Guards: SS-Programme-Control 28 Nov 2026 PC-20261128-1636-RESUME (close the expired capped enrichment leases through the existing path, keep the retry cap and the trace, no extra queue); CLAUDE.md no drop or delete by an applied migration
// CF-247 s1353. supabase/migrations/20261201110000_cf247_s1353_enrich_capped_lease_settle.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201110000_cf247_s1353_enrich_capped_lease_settle.sql', 'utf8')

test('the claim settles an expired lease at the cap as failed, keeping the cap and the trace; guarded edit of the live definition', () => {
  expect(sql).toContain("if md5(d) <> '7756cab77b5e27d4f275003a4c04f76c' then raise exception")
  expect(sql).toContain("where e.state = ''leased'' and e.leased_until < now() and e.attempts >= 3;")
  expect(sql).toContain("set state = ''failed'', leased_until = null")
  expect(sql).not.toMatch(/value\s*=\s*null|quote\s*=\s*null|evidence_id\s*=\s*null|attempts\s*=\s*0/i)
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/cron\.(schedule|alter_job)|create table/i)
})
