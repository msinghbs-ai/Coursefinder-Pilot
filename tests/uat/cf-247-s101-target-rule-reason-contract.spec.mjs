// Guards: CF-247 v2.15.349 (Platform Admin 24 Oct 2026 19:23, D1.4): the targets rule reports which condition each university fails, kept with the cache row (rule_reason) so it survives…
// CF-247 v2.15.349 (Platform Admin 24 Oct 2026 19:23, D1.4): the targets rule reports which condition each university fails, kept with
// the cache row (rule_reason) so it survives the minute refresh; override_reason keeps its meaning (set by hand).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024012000_cf247_target_rule_reason.sql', 'utf8')
const adp = fs.readFileSync('src/AdaptersWorkspace.jsx', 'utf8')
const fc = fs.readFileSync('src/FirecrawlWork.jsx', 'utf8')

test('rule_reason: a new column, filled by the minute refresh, conditions in the rule order', () => {
  expect(m).toContain('alter table pipeline.firecrawl_target_cache add column if not exists rule_reason text;')
  expect(m).toContain('comment on column pipeline.firecrawl_target_cache.rule_reason')
  const order = ['is not a target country', 'name does not match the target name pattern', 'name has an excluded word', 'active courses (', 'no international registration']
  const at = order.map(w => m.indexOf(w))
  expect(at.every(i => i > 0)).toBe(true)
  expect([...at].sort((a, b) => a - b)).toEqual(at)
  expect(m).toMatch(/pg_temp\.edit_n\('security\.firecrawl_targets_refresh_v1\(\)', '[0-9a-f]{32}'/)
  expect(m).toContain('from security.firecrawl_target_rule_reasons_v1() r where r.provider_id = c.provider_id and c.rule_reason is distinct from r.reason')
  // the rule and who is included are not changed
  expect(m).not.toMatch(/firecrawl_targets_v1\(\)', '/)
  expect(m).not.toMatch(/set\s+included\s*=\s*true/i)
  expect(m).toMatch(/-- Replaces: .*\n-- Retires: nothing/)
})

test('screens: "not matched by the rule" says why; "set by hand" stays for overrides', () => {
  expect(adp).toContain('row.target?.rule_reason?` Not matched by the targets rule: ${row.target.rule_reason}.`')
  expect(fc).toContain("t.rule_match?'':` · not matched by the rule${t.rule_reason?`: ${t.rule_reason}`:''}`")
  expect(m).toContain("'override_reason', t.override_reason, 'rule_reason', t.rule_reason)")
})
