// Guards: Platform Admin 9 Nov 2026 ("Continue fixing ... the AER lock mismatch autonomously."): the shared AER recovery rule and D-R2 (Platform Admin 2 Nov 2026 23:24, "locks protected") agree on what a manual lock blocks, in the safe direction; a manual lock is never removed or bypassed; G2 (the locked fields are the setting entry.supersede_lock_fields, not a list in code); G3 (consumer API untouched).
// CF-247 AER lock agreement: migration 20261109190000 edits security.aer_recovery_rule_v1 under its live md5 (read 9 Nov 2026) so that a waiting course entry read whose course has a manual
// lock on a field of entry.supersede_lock_fields is human_assisted, never eligible (D-R2 refuses a corrected read for such a lock). The behaviour runs on production-shaped fixtures by
// tests/fixtures/aer-lock-agreement/run.sh (scratch PostgreSQL 16; live md5s checked; applied twice). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const NAME = '20261109190000_cf247_aer_rule_lock_agreement.sql'
const M = fs.readFileSync(`supabase/migrations/${NAME}`, 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)
const FX = 'tests/fixtures/aer-lock-agreement'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')
const wf = fs.readFileSync('.github/workflows/aer-lock-agreement-test.yml', 'utf8')
const files = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).sort()
const BEFORE = '35281a190b1465699ef3cc7eccaf6d41'
const AFTER = '25dcc4055de135901826ffcae344a96f'

test('one migration, version 20261109190000, after the selector fix it follows, with the housekeeping lines', () => {
  expect(files.filter((f) => f.includes('aer_rule_lock_agreement'))).toEqual([NAME])
  expect(files.filter((f) => f.startsWith('20261109190000'))).toEqual([NAME])
  for (const dep of ['20261103070000', '20261104580000', '20261107130100', '20261109150000']) expect(files.find((f) => f.startsWith(dep)), dep).toBeTruthy()
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(run).toContain(`MIG=supabase/migrations/${NAME}`)
})

test('one function is edited under its live md5 (read 9 Nov 2026) with a recorded after md5; D-R2, the held step and the measure are not edited', () => {
  const sig = 'security.aer_recovery_rule_v1(uuid)'
  expect(C).toContain(`pg_temp.edit_once('${sig}', '${BEFORE}', '${AFTER}'`)
  expect(M).toContain(`--   ${sig} ${BEFORE} -> ${AFTER}`)
  expect(run).toContain(`["${sig}"]=${BEFORE}`)
  expect(run).toContain('["security.course_entry_correction_check_v1(uuid,uuid,text,jsonb,jsonb)"]=2e93bd9b3bc0c2ca7628f3a407b8f57f')
  expect((C.match(/pg_temp\.edit_once\(/g) || []).length).toBe(2) // the definition and the one edit
  expect(M).not.toMatch(/AFTER[A-Z_]*|0{32}/)
  expect(C).not.toMatch(/edit_once\('security\.(course_entry_correction_check_v1|aer_schedule_held_v1|progress_measure_v1|aer_technical_recovery_v1)/)
  expect(C).not.toMatch(/create or replace function (security|public|api|pipeline)\./i) // only the guarded edit replaces a function
})

test('the rule reads the same lock setting as D-R2 (G2), never a list in code; the entry_requirements test stays; only the two eligible classes change', () => {
  expect(C).toContain("security.toolset_setting('pipeline', 'entry.supersede_lock_fields')")
  expect(C).toContain("jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.supersede_lock_fields'), '[]'::jsonb))")
  expect(C).not.toMatch(/'course_url'|'official_url'/) // the page fields come from the setting, not from code
  expect(C).toContain("if v_lockd is not null and v_class in ('reread_eligible', 'changed_conditions') then v_class := 'human_assisted'; else v_lockd := null; end if;")
  expect(C).toContain("and l.field = 'entry_requirements');") // the existing test is the anchor and stays: the rule is never less strict than before
  expect(C).not.toMatch(/v_lock boolean := (true|exists)/)
  expect(C).toContain("coalesce(v_busy, '-'), v_lockd)))") // the key gains the locked fields only when they changed the class (concat_ws skips null)
})

test('scope: no lock, setting, job, cap, table or retry period is touched; a lock is never removed or bypassed', () => {
  expect(C).not.toMatch(/insert into|delete from|truncate|drop |create table|alter table|cron\.schedule|automation_catalogue|platform_toolset_settings\s+set|update pipeline\./i)
  expect(C).not.toMatch(/manual_locks\s+(set|where)[^;]*;\s*$/m)
  expect((C.match(/manual_locks/g) || []).length).toBe(1) // only the read of the locked fields
  expect(C).not.toMatch(/schedule_held_retry_days|schedule_held_max_tries|schedule_held_scan|schedule_lock_fields/) // the retry period, tries, scan and the first-read lock setting are untouched
  expect(C).not.toMatch(/course_entry_read_enqueue_v1|course_entry_correction_v1|manual_edit/)
  expect(M).toMatch(/Nothing is dropped or deleted\. No consumer API object is touched \(G3\)\./)
})

test('the PostgreSQL fixture rebuilds live, reproduces the mismatch before, and proves the agreement after (negative and positive, both directions of the setting, nothing else moves)', () => {
  for (const t of ['aer-selector-fix/run.sh', 'the migration changed a function it does not declare', 'the migration changed a setting, transition, policy or lock', 'the second run was not a no-op',
                   'the md5 guard refuses a drifted definition and edits nothing', 'aer-lock-agreement fixtures: passed'])
    expect(run).toContain(t)
  for (const t of ['before (defect reproduced): a course with a course_url + official_url lock is eligible by the rule and refused by D-R2',
                   'before (defect reproduced): a lock on official_url alone is eligible by the rule and refused by D-R2',
                   'before (defect reproduced): the held step reaches the locked item',
                   'after: a lock on entry_requirements still blocks',
                   'after: an unlocked eligible item is still eligible and passes D-R2',
                   'after: a lock on a field D-R2 does not list (tuition) leaves the item eligible and D-R2 allows it',
                   'after: a locked row-limit, ready, stale and human_assisted item keep their class',
                   'none of the other',
                   'none is refused by D-R2 for a lock',
                   'no lock was removed, added or changed by the migration',
                   'setting without the page fields: the rule makes the page-lock item eligible again and D-R2 allows it',
                   'empty setting: page locks block neither; an entry_requirements lock still stops the rule',
                   'the next run of the lane reports exactly 4 changed items',
                   'only items D-R2 can accept are counted'])
    expect(fixtures).toContain(t)
  expect(seed).toContain("'course_url'") // the production shape: the page-field pair set by hand
  expect(seed).toContain("'entry_requirements'")
  expect(run).not.toMatch(/\b(supabase\.co|fxcwkweaxjtknorudmwp|coursefinder-demo)\b/) // never a Supabase project
})

test('CI runs the fixture on an isolated PostgreSQL 16 and nothing else', () => {
  expect(wf).toMatch(/^# Guards: .+/m)
  expect(wf).toContain('postgres:16')
  expect(wf).toContain('bash tests/fixtures/aer-lock-agreement/run.sh')
  expect(wf).toContain(`'supabase/migrations/${NAME}'`)
  expect(wf).not.toMatch(/SUPABASE_|supabase\.co|secrets\./)
})
