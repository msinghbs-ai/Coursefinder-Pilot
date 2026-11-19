// Guards: S753 AER Layer 4 triage and bounded drain (Platform Admin 19 Nov 2026 15:59 AEDT, session S2-BOOST-AER): run by GitHub Actions through the Management API (no interactive prompt), zero AI and Firecrawl spend, every pending AER item through its rule's read-only check, only items that pass handed to the cron's own admission functions at most 250 a tick with FOR UPDATE SKIP LOCKED, clear of the cron's :24 and :54 runs; no rule, threshold, switch, manual lock, claim or held item changed; no migration.
// CF-247 S753. scripts/aer-l4-drain.mjs; .github/workflows/aer-l4-drain.yml. G2, G3 and housekeeping: s32, s57, s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const S = fs.readFileSync('scripts/aer-l4-drain.mjs', 'utf8')
const Y = fs.readFileSync('.github/workflows/aer-l4-drain.yml', 'utf8')
const code = S.split('\n').filter((l) => !l.trim().startsWith('//')).join('\n')

test('triage puts every pending AER item through its own rule check, read only', () => {
  expect(S).toContain("i.status = 'pending' and ((i.field_code = 'course_entry_first_read' and i.entity_type = 'course') or (i.field_code in ('entry_matrix_first_run', 'entry_matrix_change') and i.entity_type = 'provider'))")
  expect(S).toContain("case when p.field_code = 'course_entry_first_read' then security.aer_machine_check_v1(p.id) else security.aer_matrix_machine_check_v1(p.id) end r")
  expect(S).toContain("x.ok === 'true' ? 'passes the rule' : x.rule || '?'")
  expect(S).toContain('claimed_at > now() - interval \'1 hour\'')
})

test('drain hands only passing items to the cron admission functions, at most 250 a tick, rows locked with SKIP LOCKED, clear of the cron', () => {
  expect(S).toContain('const MAX = Math.max(1, Math.min(250, Math.floor(Number(process.argv[3]) || 40)))')
  // run 1 (16:40): 400 checks in one statement passed the 60 s statement time; triage and drain halve on a time-out (down to 5), never above the bound
  expect(S).toContain('let BATCH = Math.max(5, Math.min(400, Math.floor(Number(process.argv[4]) || 50)))')
  expect(S).toContain("const timedOut = (e) => /57014|statement timeout/.test(String(e?.message || e))")
  expect(S).toContain("size = Math.max(5, Math.floor(part.length / 2)); part = ids.slice(i, i + size)")
  expect(S).toContain('const ids = before.pass')
  expect(S).toContain("and i.status = 'pending' for update of i skip locked)")
  expect(S).toContain("then security.aer_machine_admit_v1(c.id, 'run') else security.aer_matrix_machine_admit_v1(c.id, 'run') end v")
  expect(S).toContain('if (!(m >= 22 && m <= 26) && !(m >= 52 && m <= 56)) return')
  expect(S).toContain("values ('aer', ${lit(MODE === 'drain' ? 'l4_drain' : 'l4_triage')}, 'pipeline.layer4_review_items'")
})

test('nothing else changes: no setting, lock, claim, rule, decision or held item is written; no model or scraper call', () => {
  expect(code).not.toMatch(/platform_toolset_settings|manual_locks\s+(set|where)|delete\s+from|update\s+pipeline\.layer4_review_items|insert\s+into\s+pipeline\.layer4_decisions|claimed_at\s*=|assigned_to\s*=/i)
  expect(code).not.toMatch(/openrouter|firecrawl|coverage-sweep|functions\/v1/i)
  expect(code).not.toMatch(/create\s+(or\s+replace\s+)?(function|table)|alter\s+table|drop\s/i)
  expect(Y).toMatch(/on:\n  workflow_dispatch:/); expect(Y).not.toMatch(/schedule:|push:|pull_request/)
  expect(Y).toContain('if [ -z "$REF" ] || [ "$CONFIRM" != "$REF" ]')
  expect(Y).toContain('run: node scripts/aer-l4-drain.mjs "$MODE" "$MAX"')
})
