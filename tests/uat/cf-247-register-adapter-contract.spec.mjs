import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 Phase 2 (8 Oct 2026): CRICOS as the first register adapter, replayed side by side with today's Layer 1 code.
test('register adapter: spec stored switched off, replay is read only, reference is a copy of Layer 1', () => {
  const m = fs.readFileSync('supabase/migrations/20261008002000_cf247_phase2_cricos_register_adapter.sql', 'utf8')
  expect(m).toContain("switched_on boolean not null default false")
  expect(m).toContain("'au_cricos'")
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/update\s+catalogue\./i)
  expect(m).toContain("'pass'")
  const r = fs.readFileSync('supabase/functions/coverage-sweep/register.ts', 'utf8')
  // the reference must stay byte-for-byte the Layer 1 fingerprint rule
  const depth = fs.readFileSync('supabase/functions/layer1-au-depth/index.ts', 'utf8')
  expect(depth).toContain('rows.push([cc,[J(raw),inst.get(get("CRICOS Provider Code"))||"",...(cl.get(cc)||[]).sort()].join("\\u001d")]);')
  expect(r).toContain('rows.push([cc, [J(raw), inst.get(get("CRICOS Provider Code")) || "", ...(cl.get(cc) || []).sort()].join("\\u001d")])')
  expect(r).toContain('export async function adapterRecords(spec: RegisterSpec, zipBytes: Uint8Array, from = 0, to = Infinity)')
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('if (mode === "register_replay")')
  expect(w).toContain('svc_register_replay_save_v2')
  expect(fs.readFileSync('supabase/migrations/20261008002200_cf247_phase2_replay_slices.sql', 'utf8')).toContain('reference_pos')
  const k = fs.readFileSync('supabase/migrations/20261008002100_cf247_keep_register_files.sql', 'utf8')
  expect(k).toContain("not like 'regulatory/%'")
  const d = fs.readFileSync('supabase/migrations/20261008002300_cf247_phase2_replay_driver.sql', 'utf8')
  expect(d).toContain("perform cron.unschedule('register-replay')")
  const c = fs.readFileSync('supabase/migrations/20261008002600_cf247_replay_compare_numeric.sql', 'utf8')
  expect(c).toContain("'a92345aef63ffb480d636f586d00d58e'")
  expect(c).toContain('then (a.fields->>\'duration_weeks\')::numeric end weeks')
})
