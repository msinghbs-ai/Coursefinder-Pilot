// Decision 216: every background function signs in with one-time run passes; the old automation key is accepted nowhere.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { errorReading } from '../../src/lib/workerErrors.js'

const MOVED = ['layer1-ca-ab-alis-degrees','layer1-ca-algonquin-catalogue','layer1-ca-bc-epbc-programs','layer1-ca-cna-programs',
  'layer1-ca-conestoga-catalogue','layer1-ca-durham-programs','layer1-ca-fanshawe-pgwp','layer1-ca-firstparty-catalogues',
  'layer1-ca-mb-programs','layer1-ca-mohawk-catalogue','layer1-ca-ns-sk-programs','layer1-ca-on-college-programs',
  'layer1-ca-provider-geography','layer1-ca-qc-university-programs','layer1-ca-sk-programs','layer2-acquire-v2',
  'layer2-batch-runner','layer2-course-fact-extract-v2','layer2-extract-v2','layer2-hotcourses-directory-parse',
  'layer2-provider-asset-promote','layer2-provider-page-fanout','layer2-scholarship-catalogue-enumerate',
  'layer2-scholarship-extract','layer2-scholarship-extract-v2','layer2-v2-diagnostic','scholarship-scope-job-execute']

test('no edge function accepts the old automation key', () => {
  for (const fn of fs.readdirSync('supabase/functions')) {
    const p = `supabase/functions/${fn}/index.ts`
    if (!fs.existsSync(p)) continue
    const s = fs.readFileSync(p, 'utf8')
    expect(s, fn).not.toContain('x-cf-pilot-key')
    expect(s, fn).not.toContain('svc_pilot_automation_authorize')
  }
})

// Clean-up batch 2 (9 Oct 2026): these moved functions were retired (source removed, on the retired list).
const RETIRED_B2 = ['layer2-batch-runner', 'layer2-scholarship-extract-v2', 'layer2-v2-diagnostic', 'scholarship-scope-job-execute',
  // clean-up batch 4 (9 Oct 2026)
  'layer2-extract-v2', 'layer2-course-fact-extract-v2', 'layer2-scholarship-extract', 'layer2-scholarship-catalogue-enumerate']

test('each moved function consumes a pass under its own name and is deployable by CI', () => {
  const wf = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
  for (const fn of MOVED.filter(f => !RETIRED_B2.includes(f))) {
    const s = fs.readFileSync(`supabase/functions/${fn}/index.ts`, 'utf8')
    expect(s, fn).toMatch(new RegExp(`svc_pilot_consume_nonce["'],\\{p_function:["']${fn}["']`))
    expect(s, fn).toContain('x-cf-run-nonce')
    expect(wf, fn).toContain(`[${fn}]=false`)
  }
  for (const fn of RETIRED_B2) expect(fs.existsSync(`supabase/functions/${fn}`), fn).toBe(false)
  expect(fs.readFileSync('supabase/functions/layer1-ca-on-college-programs/index.ts', 'utf8')).toContain('v0.4.0')
})

test('migration: one allow-list, pass issuer for the service role, callers patched behind md5 guards', () => {
  const m = fs.readFileSync('supabase/migrations/20261002181200_cf247_run_passes_everywhere.sql', 'utf8')
  expect(m).toContain('create table if not exists pipeline.pilot_nonce_functions')
  expect(m).toContain('grant execute on function public.svc_pilot_issue_nonce(text) to service_role;')
  expect(m).toContain('revoke all on function public.svc_pilot_issue_nonce(text) from public, anon, authenticated;')
  for (const g of ['c670c862016d2c3bfd242367b1229c9e','9917b5203c5029ccd06dd1c2c7430c10','a0868a29773268e3817d4d5a7d3013f1',
                   '0720356ac40709e9d813904b0d1c58c9','9a68ea0441fefb0450a07c26c24a0019','7f8518e34cddce0235907ff2f5078990']) expect(m).toContain(g)
  for (const fn of MOVED) expect(m).toContain(`'${fn}'`)
})

test('guide and error reading describe run passes everywhere', () => {
  expect(errorReading({ status: 401, message: '{"error":"invalid_pilot_automation_key"}' })).toContain('No worker accepts it')
  const g = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  expect(g).toContain('there is no shared key to rotate')
})
