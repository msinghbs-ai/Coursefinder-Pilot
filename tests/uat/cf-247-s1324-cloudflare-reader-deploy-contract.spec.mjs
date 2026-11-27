// Guards: SS-Programme-Control 27 Nov 2026 22:36 AEDT, Decision 2 (isolated studysearch-reader-burst deployment, token restricted to Techm only, one Standard-3 instance, minimum zero, five-minute idle shutdown, US$2 daily and US$20 monthly compute ceilings, public stored university evidence only, Supabase the default runtime)
// CF-247 s1324. .github/workflows/cloudflare-reader-deploy.yml, .github/workflows/cloudflare-reader-benchmark.yml, scripts/cloudflare-reader-benchmark.mjs, supabase/migrations/20261130213000_cf247_s1324_cloudflare_reader_burst.sql, coverage-sweep mode burst_read
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const dep = fs.readFileSync('.github/workflows/cloudflare-reader-deploy.yml', 'utf8')
const bm = fs.readFileSync('.github/workflows/cloudflare-reader-benchmark.yml', 'utf8')
const sql = fs.readFileSync('supabase/migrations/20261130213000_cf247_s1324_cloudflare_reader_burst.sql', 'utf8')
const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('deployment is by hand, checks the token reaches Techm only before anything else, and deploys only the isolated reader', () => {
  expect(dep).toContain('workflow_dispatch:')
  expect(dep).not.toMatch(/\bpush:|\bschedule:|pull_request/)
  expect(dep).toContain('if [ "$n" != 1 ] || [ "$name" != "Techm" ]; then echo "::error::HELD:TOKEN_SCOPE')
  expect(dep.indexOf('HELD:TOKEN_SCOPE')).toBeLessThan(dep.indexOf('wrangler@4.161.0 deploy'))
  expect(dep).toContain('working-directory: cloudflare/reader-burst')
  expect(dep.match(/wrangler@4\.161\.0 deploy[^\n]*/g)).toEqual(['wrangler@4.161.0 deploy --config wrangler.jsonc 2>&1 | tee /tmp/deploy.log | grep -vi "token" | tail -25'])
  expect(JSON.parse(fs.readFileSync('wrangler.jsonc', 'utf8')).name).toBe('coursefinder-pilot')
})

test('the signing key is generated in the run, masked, never printed, and shared only with the Worker and the Supabase edge functions', () => {
  expect(dep).toContain('key=$(openssl rand -hex 32); echo "::add-mask::$key"')
  expect(dep).toContain("printf '%s' \"$key\" | npx --yes wrangler@4.161.0 secret put READER_BURST_SIGNING_KEY")
  expect(dep).not.toMatch(/echo[^\n]*\$key\b(?!")/)
  expect(dep).toContain('https://api.supabase.com/v1/projects/$REF/secrets')
  expect(dep).toContain('(expected 401, 401, 404)')
})

test('limits are settings at the approved values; the gate holds on the switch, the slot, both caps and non-public evidence', () => {
  for (const [k, v, max] of [['on', 1, 1], ['slots', 1, 1], ['idle_minutes', 5, 5], ['daily_usd_cap', 2, 2], ['monthly_usd_cap', 20, 20]]) {
    expect(sql).toMatch(new RegExp(`'cloudflare_reader\\.${k}'[\\s\\S]{0,400}?to_jsonb\\(${v}\\), [0-9.]+, ${max},`))
  }
  for (const h of ['HELD:SWITCHED_OFF', 'HELD:BUDGET_GATE', 'HELD:SLOT_BUSY', 'HELD:NOT_PUBLIC_STORED_EVIDENCE']) expect(sql).toContain(h)
  expect(sql).toContain("e.storage_path !~ '^layer2/'")
  expect(sql).toMatch(/comment on table pipeline\.cloudflare_reader_runs is/)
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|cron\.schedule/i)
})

test('the worker calls Cloudflare only after the gate, signs the call, sends no credential and records the result; the benchmark checks shutdown', () => {
  const m = ix.slice(ix.indexOf('if (mode === "burst_read") {'), ix.indexOf('if (mode === "adapter_preview") {'))
  expect(m.indexOf('p_action: "gate"')).toBeLessThan(m.indexOf('await fetch('))
  expect(m).toContain('"x-ss-signature": sig')
  expect(m).not.toMatch(/SUPABASE_SERVICE_ROLE_KEY|Authorization|apikey/)
  expect(m).toContain('p_action: "record"')
  expect(bm).toContain('sleep 420')
  expect(bm).toContain('default: "751ba9e8-659f-493b-9a3e-456b9ae59b55"')
  expect(fs.readFileSync('cloudflare/reader-burst/wrangler.jsonc', 'utf8')).toContain('"READER_SLOTS": "reader-01"')
})
