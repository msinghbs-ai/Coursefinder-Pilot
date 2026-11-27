// Guards: SS-Programme-Control 28 Nov 2026 00:01 AEDT (direct DOT data intake without routine PR or CI dependency; transport only, the governed writer public.svc_structured_intake_v1 and every check unchanged)
// CF-247 s1326. scripts/structured-intake.mjs, .github/workflows/structured-intake.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const ops = fs.readFileSync('scripts/structured-intake.mjs', 'utf8')
const wf = fs.readFileSync('.github/workflows/structured-intake.yml', 'utf8')

test('a direct file is accepted only with its sha256 and source, and only when its bytes match; nothing is sent otherwise', () => {
  expect(ops).toContain("if (direct && (!/^[0-9a-f]{64}$/.test(wantSha) || !/^drive:[A-Za-z0-9_-]{10,80}$/.test(source)))")
  expect(ops).toContain("if (out.sha256 !== wantSha) { console.error(`::error::the file's sha256 is ${out.sha256}, not the stated ${wantSha}; nothing was sent`); process.exit(1) }")
  expect(ops.indexOf('if (out.sha256 !== wantSha)')).toBeLessThan(ops.indexOf("out.submit = await call('submit'"))
  expect(ops).toContain("maxOutputLength: 4 * 1024 * 1024 })  // fixed: size guard")
  expect(ops).toContain("(m[1] === 'drive') !== direct")
})

test('both routes reach the same governed writer with the same keys; the source and hash travel in the log', () => {
  expect(ops.match(/public\.svc_structured_intake_v1\(/g)).toHaveLength(1)
  expect(ops).toContain('${source.slice(0, 40)} | sha256 ${wantSha.slice(0, 12)}')
  expect(ops).toContain("out.submit = await call('submit', { submitter, batch, items })")
  expect(ops).toContain('https://raw.githubusercontent.com/msinghbs-ai/coursefinder-admin/${ref}/${file}')
})

test('the workflow stays hand-started and passes the direct inputs only as environment values', () => {
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/\bpush:|\bschedule:|pull_request/)
  for (const k of ['IN_CONTENT: ${{ inputs.content }}', 'IN_SHA256: ${{ inputs.sha256 }}', 'IN_SOURCE: ${{ inputs.source }}']) expect(wf).toContain(k)
  expect(wf).not.toMatch(/run:[^\n]*\$\{\{\s*inputs\.(content|sha256|source)/)
})
