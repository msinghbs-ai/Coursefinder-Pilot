// Guards: F-CDESC a recovered description keeps its opening sentence (read of recovered descriptions, 13 Nov 2026; Platform Admin 13 Nov 2026 12:16 "deliver verified data"): a reading whose first sentence was set aside is not recovered and stays held.
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261113320000_cf247_cdesc_opening_sentence_kept.sql', 'utf8')
const H = fs.readFileSync('supabase/held/cdesc_opening_kept_forward_recovery.sql', 'utf8')
const RUN = fs.readFileSync('tests/fixtures/cdesc-opening/run.sh', 'utf8')
const WF = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
const P = ['security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '2fd1a050b0e70c0ae9298a0d7419b075', '89e86ee2fe13eb582d7cac0f1ed4f7fa']

test('only the subset plan is edited (md5-guarded) and the held file reverses it', () => {
  expect(M).toContain(`select pg_temp.edit_all('${P[0]}', '${P[1]}', '${P[2]}',`)
  expect(H).toContain(`select pg_temp.edit_all('${P[0]}', '${P[2]}', '${P[1]}',`)
  expect((M.match(/select pg_temp\.edit_all\(/g) || []).length).toBe(1)
  expect(M).not.toMatch(/platform_toolset_settings|create or replace function security\./)
  expect(M).not.toMatch(/^\s*(update|delete|drop)\s/im)
})

test('a remainder without the first sentence of the reading is held, with its own cause', () => {
  expect(M).toContain("if not (1 = any (v_kept)) then return jsonb_build_object('ok', false, 'rule', 'opening_sentence_dropped'")
})

test('the fixture runs in CI and proves the regression', () => {
  expect(RUN).toContain(P[1]); expect(RUN).toContain(P[2])
  expect(RUN).toContain('REGRESSION checks fail on the database from before the migration')
  expect(WF).toContain('bash tests/fixtures/cdesc-opening/run.sh')
  expect(WF).toContain("'tests/fixtures/cdesc-opening/**'")
})
