// Guards: Platform Admin directive 8 Nov 2026 (fees lane: IQ-00111 verification, IQ-00040; fee plausibility rules are not weakened; the guard reports and never changes a fee; a person's ruling is not asked again; withdrawals are count-guarded paste files, nothing is applied by a migration)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const G = fs.readFileSync('supabase/migrations/20261108110000_cf247_fee_plausibility_guard.sql', 'utf8')
const D = fs.readFileSync('supabase/migrations/20261108111000_cf247_fee_decision_memory.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/fee-lane/run.sh', 'utf8')
const fx = fs.readFileSync('tests/fixtures/fee-lane/fixtures.sql', 'utf8')
const p1 = fs.readFileSync('docs/paste/FEE-20261108-withdraw-year-as-fee-lacite.md', 'utf8')
const p2 = fs.readFileSync('docs/paste/FEE-20261108-withdraw-ai-fees-on-held-courses.md', 'utf8')
const p3 = fs.readFileSync('docs/paste/FEE-20261108-supersede-repeat-validation-items.md', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const GC = code(G)
const DC = code(D)

test('both migrations carry the housekeeping lines and drop or delete nothing', () => {
  for (const m of [G, D]) {
    expect(m).toMatch(/^-- Replaces: .+/m)
    expect(m).toMatch(/^-- Retires: nothing/m)
  }
  for (const c of [GC, DC]) {
    expect(c).not.toMatch(/\b(drop|truncate|delete\s+from)\b/i)
  }
})

test('the guard reads fees and writes only flags: it never changes, withdraws or admits a fee', () => {
  expect(GC).not.toMatch(/(insert\s+into|update|delete\s+from)\s+(catalogue|scholarship|search|api)\./i)
  expect(GC).not.toMatch(/update\s+pipeline\.layer4_review_items/i)
  expect(GC).toContain('from catalogue.course_fees f')
  expect(GC).toContain("f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.audience = 'international'")
  for (const reason of ['fee_amount_is_a_year', 'fee_ai_on_held_course', 'fee_year_out_of_range', 'fee_annual_equals_registered_total']) {
    expect(GC).toContain(reason)
  }
  // hard reasons are hard, the two watch reasons are soft
  expect(GC).toContain("('fee_amount_is_a_year', 'hard'")
  expect(GC).toContain("('fee_ai_on_held_course', 'hard'")
  expect(GC).toContain("('fee_year_out_of_range', 'soft'")
  expect(GC).toContain("('fee_annual_equals_registered_total', 'soft'")
  // a flag clears itself once no fee matches
  expect(GC).toContain("release_kind = 'auto'")
  // the fee floor, cross-check and holds are not redefined here
  expect(GC).not.toMatch(/create or replace function (security\.fee_below_floor_v1|security\.fee_reader_yearly_v1|security\.fee_reader_hold_v1|security\.fee_integrity_measure_v1|public\.svc_fee_ai_record)/)
})

test('G1 and G2: the job is catalogued, its command holds no number, every threshold is a setting with a range, a unit and a used_by line', () => {
  expect(GC).toContain("insert into pipeline.automation_catalogue(jobname")
  expect(GC).toContain("'fee-plausibility-guard'")
  const cmd = GC.match(/cron\.schedule\('fee-plausibility-guard', '[^']+', \$\$([^$]+)\$\$\)/)
  expect(cmd).not.toBeNull()
  expect(cmd[1].replace(/_v1/g, '')).not.toMatch(/[0-9]/)
  const keys = ['fees.guard_on', 'fees.guard_year_min', 'fees.guard_year_max', 'fees.guard_year_old_gap', 'fees.guard_year_ahead', 'fees.guard_total_min_years', 'fees.guard_total_match_pct', 'fees.guard_sample']
  for (const k of keys) {
    expect(GC).toContain(`('pipeline', '${k}'`)
    expect(GC).toContain(`security.pipeline_num_v1('${k}'`)
  }
  expect(GC).toMatch(/to_jsonb\(1\), 0, 1, 'on\/off'/)
  expect(GC).toContain("'fees.guard_on', 1) < 1")
  expect(G).toContain('fees.guard_on 1 (read-only, ships on)')
  expect(GC).toContain("revoke execute on function security.fee_plausibility_check_v1() from public, anon, authenticated")
})

test('decision memory: edits one live function under its md5, ships OFF, and decides nothing', () => {
  expect(D).toContain('public.svc_fee_ai_record(uuid,jsonb,numeric,text) 5ec65e53403933b98381bd5c9c79b6d1 -> 90a9bfb569e6a1ff97e08f01ff20c855')
  expect(DC).toContain("pg_temp.edit_once('public.svc_fee_ai_record(uuid,jsonb,numeric,text)', '5ec65e53403933b98381bd5c9c79b6d1', '90a9bfb569e6a1ff97e08f01ff20c855'")
  expect(D).not.toContain('00000000000000000000000000000000')
  expect(DC).toContain("('pipeline', 'fees.respect_decisions_on'")
  expect(DC).toMatch(/to_jsonb\(0\), 0, 1, 'on\/off'/)
  expect(DC).toContain("security.pipeline_num_v1('fees.respect_decisions_on', 0) >= 1")
  expect(DC).toContain("security.pipeline_num_v1('fees.decision_memory_days', 90)")
  expect(DC).toContain("security.pipeline_num_v1('fees.decision_same_pct', 1)")
  // only a Layer 4 insert is suppressed: no item is decided, approved or rejected, nothing is admitted
  expect(DC).not.toMatch(/update\s+pipeline\.layer4_review_items/i)
  expect(DC).not.toMatch(/status\s*=\s*'(approved|rejected|edited_approved)'/)
  expect(DC).toContain("v_outcome in ('review', 'conflict') and v_ruled is null and not exists")
  expect(DC).toContain('not raised again')
  expect(D).toContain('FEE-20261108-supersede-repeat-validation-items.md')
})

test('the fixture proves the guard, the settings, the off switch and the ruling in a scratch Postgres on the live definitions', () => {
  expect(run).toContain('fee-units-holds')
  expect(fx).toContain('===== plausibility guard =====')
  expect(fx).toContain('===== decision memory (IQ-00040) =====')
  expect(fx).toContain('provider_current_tuition_validation')
})

test('consumer API untouched (G3 stays with s57): no migration here names a consumer object as a target', () => {
  for (const c of [GC, DC]) {
    expect(c).not.toMatch(/create or replace function (api\.|public\.website_|public\.website_edge_|public\.zoho_edge_)/)
    expect(c).not.toMatch(/(alter|comment on)\s+(table|function)\s+(api\.|public\.website_|public\.zoho_edge_)/i)
  }
})

test('the paste files are count- and hash-guarded, audited, reversible, and are not run by a migration', () => {
  expect(p1).toContain('7245d69736814b5156c22ac60e224624')
  expect(p1).toMatch(/v_n <> 65 or v_h <> '7245d69736814b5156c22ac60e224624'/)
  expect(p1).toContain("'FEE-20261108-LACITE'")
  expect(p1).toContain("array_remove(admit_fields, 'fee')")
  expect(p1).toContain('## Rollback')
  expect(p2).toMatch(/v_n <> 4 or v_h <> 'e29c033acb86c3904897ffc2677d100a'/)
  expect(p2).toContain("'FEE-20261108-AIHELD'")
  expect(p2).toContain('Rollback')
  // Reach 105389A was kept by the 4 Nov paste: it is named, not withdrawn
  expect(p2).toContain('NOT included')
  expect(p2).not.toMatch(/'51ebae9d-67d3-4221-9cb3-1308260f4801'/)
  expect(p3).toMatch(/v_n <> 53 or v_h <> '6ad6722331a096c89d7457daddf5e565'/)
  // supersede only: no decision, approval or rejection is made
  expect(p3).toContain("set status = 'superseded'")
  expect(p3).not.toMatch(/set status = '(approved|rejected|edited_approved)'/)
  for (const p of [p1, p2, p3]) {
    expect(p).toContain('begin;')
    expect(p).toContain('commit;')
    expect(p).toContain('pipeline.admin_control_events')
  }
  for (const m of [G, D]) {
    expect(m).not.toContain('FEE-20261108-LACITE')
    expect(m).not.toContain('FEE-20261108-AIHELD')
  }
})
