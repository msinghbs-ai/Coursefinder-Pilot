// Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026), lease statement time-out: the lease finds each provider's stored About copy once (migration 20261109182000 edits only public.svc_provider_description_next, md5-guarded, replaces/retires named); it changes no statement time-out, setting, ceiling, job or index, and the harness shows the same items, order and content before and after.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261109182000_cf247_pdesc_lease_one_pass.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')   // the statements, without the comments
const HARNESS = fs.readFileSync('tests/fixtures/pdesc-lease-one-pass/run.sh', 'utf8')
const SCEN = fs.readFileSync('tests/fixtures/pdesc-lease-one-pass/scenarios.sql', 'utf8')
const WF = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')

test('the migration names what it replaces and retires, and records the live md5 it was written against and the md5 it produces', () => {
  expect(MIG).toMatch(/^-- Replaces: .*stored_v1/m)
  expect(MIG).toMatch(/^-- Retires: nothing$/m)
  expect(MIG).toContain('public.svc_provider_description_next(integer) cb83dc4e3502d6cc16450c2126368ec9 -> 90275ff3bc7da9989c2a3430b16cb94f')
  expect(CODE.match(/pg_temp\.edit_all\('/g)).toHaveLength(1)
  expect(CODE).toContain("edit_all('public.svc_provider_description_next(integer)', 'cb83dc4e3502d6cc16450c2126368ec9', '90275ff3bc7da9989c2a3430b16cb94f'")
})

test('it refuses, and changes nothing, when the lease, the stored-copy function or the About pattern function is not the one it was written against', () => {
  expect(CODE).toContain("'29200a6a4ad7f38e0cdd30dbadd79857'")   // security.pdesc_about_like_patterns_v1
  expect(CODE).toContain("'733d28159a080abdfd5cec244aed2cb9'")   // security.provider_description_stored_v1
  expect(CODE).toContain("raise exception 'live % differs from the definition this change edits")
  expect(HARNESS).toContain('differs from the definition this change was written against')
  expect(HARNESS).toContain('a hand-changed stored-copy function and a hand-changed lease function are each refused and nothing is applied')
})

test('the one pass: the stored copy is found once for the providers with open work, and every other place reads it from there', () => {
  const news = MIG.slice(MIG.indexOf('array[\n$new$'))
  // the population: only a provider with an address that can be an About page is asked, once
  expect(news).toContain('security.pdesc_about_like_patterns_v1()')
  expect(news).toContain('like any (v_ws)')
  expect(news.match(/security\.provider_description_stored_v1\(/g)).toHaveLength(1)
  // the places that called it per row now read the pass
  for (const read of ['(v_stored->>x.provider_id::text)::uuid', '(v_stored->>r.provider_id::text)::uuid', '(v_stored->>p.id::text)::uuid', '(v_stored->>r.provider_id::text) is not null', '(v_stored->>u.provider_id::text)::uuid end stored_id'])
    expect(news).toContain(read)
  // the six per-row calls it replaces are named exactly once each
  const olds = MIG.slice(MIG.indexOf('array[\n$old$'), MIG.indexOf('array[\n$new$'))
  expect(olds.match(/security\.provider_description_stored_v1\(/g)).toHaveLength(5)
})

test('NEGATIVE: no statement time-out, lock time-out, setting, ceiling, job, index, table or data is touched; nothing is dropped or deleted', () => {
  expect(CODE).not.toMatch(/statement_timeout|lock_timeout|idle_in_transaction/i)
  expect(CODE).not.toMatch(/platform_toolset_settings|cron\.(schedule|alter_job|unschedule)|create (unique )?index|alter table|create table/i)
  expect(CODE).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(CODE).not.toMatch(/ai_usd_max|firecrawl_reads_max|concurrency_max|dispatch_max/)
  // the reservation protocol, the advisory lock and the claim timer stay in the function the migration edits
  expect(CODE).not.toMatch(/pg_try_advisory_xact_lock|provider-description-reserve-v1|interval '20 minutes'/)
})

test('the harness proves the same items, order and content, covers the address shapes and the copy rules, and runs in the integration workflow', () => {
  for (const s of ['manual_five', 'machine_ten', 'not_about_address', 'address_shapes', 'old_copy', 'lease_ran_out', 'lease_running', 'newest_copy', 'nothing_queued'])
    expect(SCEN, s).toContain(`'${s}'`)
  expect(HARNESS).toContain('[ "$AFTERS" = "$BEFORE" ]')
  expect(HARNESS).toContain('applied again: no change')
  expect(WF).toContain('bash tests/fixtures/pdesc-lease-one-pass/run.sh')
  expect(WF).toContain('tests/uat/cf-247-s513-pdesc-lease-one-pass-contract.spec.mjs')
  expect(fs.readFileSync('tests/fixtures/pdesc-lease-one-pass/expected.txt', 'utf8').trim().split('\n')).toHaveLength(9)
})
