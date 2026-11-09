// Guards: Platform Admin engineering hold 4 Nov 2026 21:59 (PR-first gate: fixtures reproducing the production outcome, regression coverage for the exact defect and the refused path, no silent drift from live) and its lifting for remediation 9 Nov 2026 ("complete the PR-first gate, migration renumbering and regression tests before merging"); first-run verification of v2.15.473 (AER held step order and the aer_technical_correction measure); the AER shared recovery rule (20261107130100) is not edited.
// CF-247 AER selector fix, PR #875 re-based on live 9 Nov 2026: migration 20261109150000 (renumbered from 20261104620000) edits security.aer_schedule_held_v1 and
// security.progress_measure_v1 under their live md5s and moves the producer of aer_technical_correction. The behaviour runs on a production-shaped seed by
// tests/fixtures/aer-selector-fix/run.sh (scratch PostgreSQL 16; live md5s checked; applied twice). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const NAME = '20261109150000_cf247_aer_selector_fix.sql'
const M = fs.readFileSync(`supabase/migrations/${NAME}`, 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)
const FX = 'tests/fixtures/aer-selector-fix'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')
const wf = fs.readFileSync('.github/workflows/aer-selector-fix-test.yml', 'utf8')
const files = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).sort()

test('renumbered: one file, after every migration it depends on, the old held number is gone, and nothing else uses its timestamp', () => {
  expect(files.filter((f) => f.includes('aer_selector_fix'))).toEqual([NAME])
  expect(files.filter((f) => f.startsWith('20261109150000'))).toEqual([NAME])
  for (const dep of ['20261104580000', '20261106400000', '20261107130100']) expect(files.find((f) => f.startsWith(dep)), dep).toBeTruthy()
  expect(NAME.slice(0, 14) > '20261107130100').toBe(true)
  for (const t of [M, run, fixtures, seed]) expect(t).not.toContain('20261104620000_')
  expect(run).toContain(`MIG=supabase/migrations/${NAME}`)
})

test('two live functions are edited under their live md5s (read 9 Nov 2026) with a recorded after md5; the shared rule is not edited', () => {
  const EDITS = {
    'security.aer_schedule_held_v1(integer)': ['c866167b55d2494c366fd2700a518ff8', '483fbcead73c7996d02c372fd6128108'],
    'security.progress_measure_v1(text,timestamp with time zone)': ['e758d1c2d36f8f523c3fdbcc1b9dff2f', 'b5fc7aae44039565dc85644352f0c719'],
  }
  for (const [sig, [before, after]] of Object.entries(EDITS)) {
    expect(C).toContain(`pg_temp.edit_once('${sig}', '${before}', '${after}'`)
    expect(M).toContain(`--   ${sig} ${before} -> ${after}`)
    expect(run).toContain(`["${sig}"]=${before}`)
  }
  expect((C.match(/pg_temp\.edit_once\(/g) || []).length).toBe(3) // the definition and two edits
  expect(M).not.toMatch(/AFTER[A-Z_]*|0{32}/)
  // the rule: live 35281a19 (20261107130100) is neither edited nor recreated here; the fixture proves it is untouched
  expect(C).not.toMatch(/edit_once\('security\.aer_recovery_rule_v1|function security\.aer_recovery_rule_v1/)
  expect(run).toContain('["security.aer_recovery_rule_v1(uuid)"]=35281a190b1465699ef3cc7eccaf6d41')
  expect(fixtures).toContain("'35281a190b1465699ef3cc7eccaf6d41'")
  // the measure's after md5 is the one the intake migration (20261106400000) told this change to expect
  expect(fs.readFileSync('supabase/migrations/20261106400000_cf247_intake_automation_progress.sql', 'utf8')).toContain('before e758d1c2d36f8f523c3fdbcc1b9dff2f, after b5fc7aae44039565dc85644352f0c719')
})

test('the held step scans what the rule last made eligible first and keeps its own filters; the measure counts corrected reads, not lane bookkeeping', () => {
  expect(C).toContain("when 'reread_eligible' then 0 when 'changed_conditions' then 1 end")
  expect(C).toContain("w.failure_class = 'aer_reread_eligible'")
  expect(C).toContain('k.checked_at nulls first, i.created_at, i.id')
  expect(C).not.toMatch(/limit v_scan|v_retry|v_tries|aer_schedule_checks/) // the scan size, retry period and tries are untouched settings
  for (const s of ["'processed', (select count(*) from pipeline.aer_read_supersessions s where s.requested_at >= p_since)",
                   "'created', (select count(*) from pipeline.aer_read_supersessions s where s.state = 'superseded' and s.closed_at >= p_since)",
                   "'eligible', (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'aer_reread_eligible' and w.stage <> 'done')"])
    expect(C).toContain(s)
  expect(C).toContain("update pipeline.progress_transitions set producer_jobs = '{aer-scheduled-read}'")
  expect(C).toContain("producer_jobs = '{work-continuity}'")
  // only the AER branch of the measure is edited: the intake branches added by 20261106400000 are not in the edit text
  expect(C).not.toMatch(/intake_selection|intake_admission|intake_publication/)
})

test('scope: no cap, spending limit, switch, setting, job or enqueue changes, and no new object; the lane and the row-limit setting are only read', () => {
  expect(C).not.toMatch(/insert into|cron\.schedule|automation_catalogue|platform_toolset_settings|create table|alter table|course_entry_read_enqueue_v1\(|course_entry_correction_check_v1\(/i)
  expect(C).not.toMatch(/create or replace function (security|public|api|pipeline)\./i) // only the two guarded edits replace a function
  expect((C.match(/\bupdate pipeline\./g) || []).length).toBe(1) // the producer row
})

test('the PostgreSQL fixture rebuilds live (rule 35281a19, measure e758d1c2), reproduces both defects before, and proves the row-limit regression, the order, the filters, the measure and the guard', () => {
  for (const t of ['RULE=supabase/migrations/20261107130100_cf247_aer_row_limit_rule.sql', 'INTAKE=supabase/migrations/20261106400000_cf247_intake_automation_progress.sql',
                   'e758d1c2d36f8f523c3fdbcc1b9dff2f', 'the migration changed a function it does not declare', 'the second run was not a no-op', 'aer-selector-fix fixtures: passed'])
    expect(run).toContain(t)
  // negative and positive, on both sides of the migration
  for (const t of ['none eligible (a setting time alone changes nothing)', "a bare setting touch, a limit below the need and another university''s limit leave the cut a row-limit hold",
                   'a limit of % for its own university did not make the cut eligible',
                   'before (defect reproduced): the held step scans 40 holds and reaches none', 'before (defect reproduced): the measure counts created 0',
                   'ok: the rule is the live rule', 'ok: the held step scans', 'an item with a corrected read inside the retry period is not scanned',
                   'a lane recovery or re-check is not a corrected read', 'the intake and other AER measure branches are intact'])
    expect(fixtures).toContain(t)
  expect(fixtures).toContain('-- R row-limit regression (negative and positive), both parts')
  expect(seed).toContain('"rows": 6') // the production shape of a read cut at the row limit
  expect(run).not.toMatch(/\b(supabase\.co|fxcwkweaxjtknorudmwp|coursefinder-demo)\b/) // never a Supabase project
})

test('CI runs the fixture on an isolated PostgreSQL 16 and nothing else', () => {
  expect(wf).toMatch(/^# Guards: .+/m)
  expect(wf).toContain('postgres:16')
  expect(wf).toContain('bash tests/fixtures/aer-selector-fix/run.sh')
  expect(wf).toContain("'supabase/migrations/20261109150000_cf247_aer_selector_fix.sql'")
  expect(wf).not.toMatch(/SUPABASE_|supabase\.co|secrets\./)
})
