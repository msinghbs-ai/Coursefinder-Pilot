// Guards: F-CDESC course description throughput (CF-247; Platform Admin 10 Nov 2026 23:17): a course description reading recorded through the API (the AI worker's svc_enrich_ai_record) is never admitted inside that recording call, so a slow admission cannot cancel the worker's whole batch; the job course-description-machine admits it. The behaviour is proved by the PostgreSQL fixture tests/fixtures/cdesc-admit-outside-record/run.sh (live bodies, the failure reproduced on the old body first); this spec pins the migration text.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261111000000_cf247_cdesc_admit_outside_ai_record.sql', 'utf8')
const R = fs.readFileSync('supabase/held/cdesc_admit_outside_ai_record_forward_recovery.sql', 'utf8')
const LIVE = fs.readFileSync('tests/fixtures/cdesc-admit-outside-record/live/security.course_description_machine_trg_v1.sql', 'utf8')
const BEFORE = 'ec9b96498c54e37f8492a1003ea97520'
const AFTER = 'c75d63a6390f4cb0e3ed7276e70c25f8'
const body = (s) => s.match(/as \$function\$([\s\S]*?)\$function\$/i)[1]

test('the migration follows the house pattern: header, one md5-guarded body replacement, a post-check, nothing dropped, no setting or job touched', () => {
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  expect(M).toContain(`--   security.course_description_machine_trg_v1()   ${BEFORE} -> ${AFTER}`)
  expect(M).toContain(`md5(v_src) = '${AFTER}' then raise notice 'security.course_description_machine_trg_v1(): already applied'`)
  expect(M).toContain(`md5(v_src) <> '${BEFORE}' then raise exception`)
  expect(M).toContain('supabase/held/cdesc_admit_outside_ai_record_forward_recovery.sql')
  expect(M.match(/create or replace function/gi)).toHaveLength(1)
  expect(M).toMatch(/post-check: security\.course_description_machine_trg_v1\(\) is not the body this change states/)
  expect(M).toMatch(/post-check: trigger field_enrich_items_cdesc_machine is missing, disabled or calls another function/)
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(M).not.toMatch(/\b(alter\s+table|create\s+(or\s+replace\s+)?trigger|create\s+index)\b/i)
  expect(M).not.toMatch(/platform_toolset_settings|cron\.(schedule|job)|automation_catalogue/i)
})

test('the only difference from the live body is the API guard placed before the admission; the admission call, the swallow and the switch are unchanged', () => {
  const after = body(M).split('\n').map((l) => l.trimEnd())
  const before = body(LIVE).split('\n').map((l) => l.trimEnd())
  const added = after.filter((l) => !before.includes(l))
  expect(added).toHaveLength(3)
  expect(added.filter((l) => l.trim().startsWith('--'))).toHaveLength(2)
  expect(added).toContain("  if nullif(current_setting('request.method', true), '') is not null then return null; end if;")
  for (const l of before) expect(after, l).toContain(l)
  const b = body(M)
  expect(b.indexOf("current_setting('request.method', true)")).toBeGreaterThan(b.indexOf("'enrich.course_description_machine_on'"))
  expect(b.indexOf("current_setting('request.method', true)")).toBeLessThan(b.indexOf("course_description_machine_admit_v1(v_item, 'fresh_reading')"))
})

test('the forward recovery restores the live body byte for byte', () => {
  expect(R).toContain(BEFORE)
  expect(R).toContain(AFTER)
  expect(R).toContain("raise notice 'already the original'")
  expect(R).toContain('differs from both texts this recovery knows')
  expect(R).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(body(R)).toBe(body(LIVE))
  expect(body(R)).not.toContain('request.method')
})

test('the database fixture runs the migration, the live settle and the recovery, and runs in the course descriptions workflow', () => {
  const run = fs.readFileSync('tests/fixtures/cdesc-admit-outside-record/run.sh', 'utf8')
  expect(run).toContain(`BEFORE=${BEFORE}`)
  expect(run).toContain(`AFTER=${AFTER}`)
  expect(run).toContain('supabase/held/cdesc_admit_outside_ai_record_forward_recovery.sql')
  expect(run).toContain('live/security.course_description_machine_settle_v1.sql')
  expect(run).toContain('canceling statement due to statement timeout')
  const wf = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
  expect(wf).toContain('tests/fixtures/cdesc-admit-outside-record/**')
  expect(wf).toContain('bash tests/fixtures/cdesc-admit-outside-record/run.sh')
})
