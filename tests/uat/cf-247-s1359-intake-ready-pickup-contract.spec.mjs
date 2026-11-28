// Guards: SS-Programme-Control PC-20261128-CONTINUOUS-BUILD-EXECUTE (READY manifest pickup enforced at run time before pickup; DOT-EVENING-INTAKE-BOUNDARY-20261128 negative)
// CF-247 s1359. scripts/intake-ready.mjs, scripts/structured-intake.mjs, .github/workflows/structured-intake.yml. A collected file is sent only under its
// released name (<package>-READY_FOR_PICKUP.jsonl, no hold mark); a record stating it is not READY is left out. The writer and admission are unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import zlib from 'node:zlib'
import crypto from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { readyBatch, readyItems } from '../../scripts/intake-ready.mjs'

test('only a file released as READY_FOR_PICKUP is sent; a held or unmarked name is refused', () => {
  expect(readyBatch('DOT-UTS-00099F-107870J-AER-READY_FOR_PICKUP')).toEqual({ ok: true })
  expect(readyBatch('DOT-AU15-107049E-R2-READY_FOR_PICKUP')).toEqual({ ok: true })
  for (const b of ['PRECHECK_PENDING_DO_NOT_SUBMIT', 'DOT-AU16-PRECHECK-READY_FOR_PICKUP', 'DOT-AU16-HELD-READY_FOR_PICKUP', 'DOT-AU16-DRAFT',
    'DOT-AU16', 'owner-intake-01', 'DOT-AU16-READY_FOR_PICKUP-v2', 'DOT-AU16-NOT_READY'])
    expect(readyBatch(b).ok).toBe(false)
})

test('a record that states its readiness is sent only when READY; records without a state are sent as before', () => {
  const r = readyItems([{ course_code: 'A1' }, { course_code: 'A2', state: 'READY' }, { course_code: 'A3', status: 'READY_FOR_PICKUP' },
    { course_code: 'A4', state: 'PRECHECK_PENDING' }, { provisional_key: 'k5', readiness: 'held' }])
  expect(r.send.map((x) => x.course_code)).toEqual(['A1', 'A2', 'A3'])
  expect(r.held).toEqual([{ line: 4, state: 'PRECHECK_PENDING', key: 'A4' }, { line: 5, state: 'held', key: 'k5' }])
})

test('the boundary negative: identical verified bytes under a PRECHECK name stop before anything is sent', () => {
  const bytes = Buffer.from('{"domain":"aer","course_code":"107870J"}\n')
  const run = (name) => spawnSync(process.execPath, ['scripts/structured-intake.mjs', 'submit', `drive/dot/${name}.jsonl`, '', 'spec s1359'], {
    encoding: 'utf8', env: { ...process.env, SUPABASE_ACCESS_TOKEN: 'not-a-token', REF: 'not-a-project', IN_CONTENT: zlib.gzipSync(bytes).toString('base64'),
      IN_SHA256: crypto.createHash('sha256').update(bytes).digest('hex'), IN_SOURCE: 'drive:abcdefghijklmnop' } })
  for (const name of ['PRECHECK_PENDING_DO_NOT_SUBMIT', 'DOT-UTS-107870J-AER']) {
    const r = run(name)
    expect(r.status).toBe(1)
    expect(r.stderr).toMatch(/not released|not marked READY_FOR_PICKUP/)
    expect(r.stderr).not.toMatch(/database query failed/)
  }
})

test('the check runs before the file is read and the writer is called; the workflow names the rule', () => {
  const s = fs.readFileSync('scripts/structured-intake.mjs', 'utf8')
  expect(s).toContain("import { readyBatch, readyItems } from './intake-ready.mjs'")
  const at = (x) => s.indexOf(x)
  expect(at("if (direct && action === 'submit') { const rb = readyBatch(batch)")).toBeGreaterThan(0)
  expect(at("if (direct && action === 'submit') { const rb = readyBatch(batch)")).toBeLessThan(at('zlib.gunzipSync('))
  expect(at('readyItems(all)')).toBeLessThan(at("call('submit'"))
  expect(fs.readFileSync('.github/workflows/structured-intake.yml', 'utf8')).toContain('it must end -READY_FOR_PICKUP')
})
