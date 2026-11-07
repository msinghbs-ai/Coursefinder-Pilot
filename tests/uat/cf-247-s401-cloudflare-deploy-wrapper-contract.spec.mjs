// Guards: D-382 cutover (Platform Admin 2026-11-07 11:18): the Git-connected Cloudflare Deploy command is a guarded wrapper that fails closed
import { test, expect } from '@playwright/test'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, writeFileSync, chmodSync, readFileSync, existsSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const WRAPPER = 'scripts/ci/cloudflare-deploy.sh'
const src = readFileSync(WRAPPER, 'utf8')

function run(env, curlBody) {
  const bin = mkdtempSync(join(tmpdir(), 'cfw-'))
  const marker = join(bin, 'wrangler-ran')
  writeFileSync(join(bin, 'npx'), `#!/bin/sh\ntouch "${marker}"\n`); chmodSync(join(bin, 'npx'), 0o755)
  writeFileSync(join(bin, 'curl'), `#!/bin/sh\nprintf '%s' '${curlBody}'\n`); chmodSync(join(bin, 'curl'), 0o755)
  const r = spawnSync('bash', [WRAPPER], { env: { PATH: `${bin}:${process.env.PATH}`, HOME: bin, ...env }, encoding: 'utf8' })
  return { status: r.status, out: r.stdout + r.stderr, published: existsSync(marker) }
}

test('the wrapper is short, strict, pins the guard by commit and digest, and publishes only after the guard', () => {
  expect(statSync(WRAPPER).mode & 0o111).toBeTruthy()
  expect(src).toContain('set -euo pipefail')
  expect(src).toMatch(/guard_commit=[a-f0-9]{40}\n/)
  expect(src).toMatch(/guard_sha256=[a-f0-9]{64}\n/)
  expect(src).toContain('--entry-point cloudflare-frontend')
  expect(src.indexOf('python3 "$guard_file"')).toBeGreaterThan(0)
  expect(src.indexOf('exec npx wrangler deploy')).toBeGreaterThan(src.indexOf('python3 "$guard_file"'))
  expect(src.match(/wrangler deploy/g)).toHaveLength(1) // the single publish line
  expect(src.split('\n').length).toBeLessThan(40)
})

test('it fails closed before wrangler: no build commit, or a guard that does not match its digest', () => {
  const none = run({}, 'x')
  expect(none.status).not.toBe(0); expect(none.published).toBe(false); expect(none.out).toContain('BLOCKED')
  const tampered = run({ WORKERS_CI_COMMIT_SHA: 'a'.repeat(40) }, 'print("allow")')
  expect(tampered.status).not.toBe(0); expect(tampered.published).toBe(false); expect(tampered.out).toContain('digest mismatch')
})
