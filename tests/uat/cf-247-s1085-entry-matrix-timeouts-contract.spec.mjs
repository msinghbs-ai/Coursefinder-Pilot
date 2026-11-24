// Guards: Platform Admin 24 Nov 2026 22:02 and 22:07 AEDT (AER-FU-11 option 3: halve the entry_matrices slice, send a timed-out slice to the next cascade model instead of repeating, log failed calls; SCH-FU-02 UTAS rule in history)
// s1085: worker v1.0.39 entry_matrices cascade, the slice setting, the UTAS skip rule mirror and the named requeue.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261125190000_cf247_s1085_entry_matrix_timeouts_utas_prize_rule.sql', 'utf8')

test('s1085: entry_matrices slices go through the route cascade with the run deadline and a 40 s first-model time-out', () => {
  expect(IX).toContain('cascadeFetch(fetch, { models: it.models, deadline: t0 + BUDGET_MS - 25000, service: "entry_matrices", source: "entry_matrix", source_id: it.run_id }')
  expect(IX).toContain('signal: AbortSignal.timeout(ENTRY_FIRST_MODEL_TIMEOUT_MS)')
  expect(IX).toContain('const ENTRY_FIRST_MODEL_TIMEOUT_MS = 40_000;  // fixed:')
  expect(IX).toContain('if (d?.model && !String(d.model).startsWith(sentModel(d, it.model))) throw Error(`returned model ${d.model}, not ${sentModel(d, it.model)}`);')
  expect(IX).not.toContain('cascadeFetch(fetch, { service: "entry_matrices" }')
})

test('s1085: slice 4000 through the settings path, the UTAS rule only if absent, the 13 named runs queued; no cron or limit change', () => {
  expect(MIG).toContain("update pipeline.platform_toolset_settings set value = to_jsonb(4000), reason = v_reason")
  expect(MIG).toContain("values ('toolsets', 'setting', 'pipeline.entry.matrix_slice_chars'")
  expect(MIG).toContain("where not exists (select 1 from pipeline.scholarship_skip_rules r where r.pattern =")
  expect(MIG).toContain("'UTAS enrolled-student prize', true, 'international'")
  expect(MIG).toContain("where r.state = 'failed' and r.error ~* 'timed out|time budget|without a reply'")
  expect(MIG).not.toMatch(/cron\.schedule|cron\.alter_job|delete from|drop (table|function)/i)
})
