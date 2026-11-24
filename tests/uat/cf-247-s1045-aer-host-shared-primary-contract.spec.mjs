// Guards: CF-247 s1045 AER shared-host primary record and Curtin CDN alias (Platform Admin 24 Nov 2026 15:16, S2-RM-Design brief decisions 2 and 3; Standing Authority Charter):
// the machine check goes on for the one provider with the most active courses on a shared website host (a tie stays held), Curtin University alone gains s30991.pcdn.co, both by anchored md5-guarded edits.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261124213000_cf247_s1045_aer_host_shared_primary_curtin_alias.sql', 'utf8')
const code = sql.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('primary record: switch setting, strictly-more-courses rule, one md5-guarded anchored edit', () => {
  expect(code).toContain("'aer.host_shared_primary_on'")
  expect(code).toContain('c08b4151e77f16fdbfef38e29fe1035c')
  expect(code).toContain('guard: host_shared anchor absent or repeated')
  expect((code.match(/execute replace/g) || []).length).toBe(1)
  expect(code).toMatch(/>= \(select count\(\*\) from catalogue\.courses c1/)  // a tie or a larger sibling keeps host_shared
})
test('Curtin alias is scoped to one provider and the read-back holds the smaller VU record', () => {
  expect(code).toContain("':s30991.pcdn.co'")
  expect(code).toContain("canonical_name = 'Curtin University'")
  expect(code).toContain('expected one active Curtin University record')
  expect(code).toContain("'0f5373c8-d724-4303-9267-739530a5ce53'")
  expect(sql).toMatch(/-- Replaces: nothing/)
  expect(sql).toMatch(/-- Retires: nothing/)
  expect(code.replace(/on commit drop/g, '')).not.toMatch(/\b(drop|delete from|truncate)\b/i)
})
