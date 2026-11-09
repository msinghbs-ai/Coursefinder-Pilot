// Guards: F-PDESC (Platform Admin Directive 3, 9 Nov 2026, Blocker C registry-factual descriptions): providers held by the register-fact tier for too few verified facts are looked at again when pdesc.registry_min_facts is lowered; holds for every other reason and at the current requirement still block; no new setting, number, job, table or schedule; G2, G3, housekeeping.
// Source contract over migration 20261109140000 (guards on the live body md5 before and after each of three in-place edits).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const body = fs.readFileSync('supabase/migrations/20261109140000_cf247_pdesc_registry_reeval.sql', 'utf8')
const code = body.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('three edits are chained on the live body md5 and each applies exactly once', () => {
  for (const m of ['b14315e77beb36aba6005efbed208b62', '20813d8101fd3878a183c0afe3ca0f8e', '7d19ed9f0010ea77975d42f3b2adb322', '1f9cbb77a59ab392a2e59b6aff317adb']) expect(body).toContain(m)
  expect((code.match(/select pg_temp\.edit_one\(/g) || []).length).toBe(3)
  expect(code).toContain('must apply exactly once')
  expect(code).toContain('already applied')
})

test('a hold made at a higher facts requirement than the current one no longer blocks, and is selected again', () => {
  // negative: a hold at the current or a lower requirement, or without a requirement recorded (any other reason), still blocks
  expect(code).toContain("(h.checks->>'facts_needed')::numeric end, 0) <= security.pipeline_num_v1('pdesc.registry_min_facts', 3)")
  // positive: only this tier's insufficient_verified_facts hold with a recorded higher requirement is retried
  expect(code).toContain("lr.rule = 'insufficient_verified_facts' and lr.checks->>'tier' = 'registry_factual'")
  expect(code).toContain("(lr.checks->>'facts_needed')::numeric > security.pipeline_num_v1('pdesc.registry_min_facts', 3)")
  expect(code).toContain('x.updated_at, x.checks from pipeline.provider_description_reads x')
})

test('nothing else changes: no setting, schedule, table, drop or consumer API object', () => {
  expect(code).not.toMatch(/insert into pipeline\.platform_toolset_settings|update pipeline\.platform_toolset_settings/i)
  expect(code).not.toMatch(/cron\.(schedule|alter_job)/i)
  expect(code).not.toMatch(/create table/i)
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1/)
  expect(body).toMatch(/^-- Replaces: /m)
  expect(body).toMatch(/^-- Retires: nothing/m)
  expect(code).toMatch(/comment on function security\.provider_description_registry_tier_v1\(\)/)
})

test('the isolated PostgreSQL fixture applies it, checks both body md5s and proves retry (positive) and no retry at an unchanged requirement (negative)', () => {
  const run = fs.readFileSync('tests/fixtures/pdesc-machine/run.sh', 'utf8')
  expect(run).toContain('20261109140000_cf247_pdesc_registry_reeval.sql')
  expect(run).toContain('b14315e77beb36aba6005efbed208b62')
  expect(run).toContain('1f9cbb77a59ab392a2e59b6aff317adb')
  const sc = fs.readFileSync('tests/fixtures/pdesc-machine/scenarios.sql', 'utf8')
  for (const l of ['reeval_min3|', 'reeval_min3_again|', 'reeval_min2|', 'reeval_min2_admitted|', 'reeval_min2_again|']) expect(sc).toContain(l)
})
