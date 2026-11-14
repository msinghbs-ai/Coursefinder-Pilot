// Guards: CF-247 v2.15.249 (S15): Platform Admin bugs 11/10-6. "Just like courses adapter i need scholarship to be read by code using Firecrawl but then use AI to extract attributes.
// CF-247 v2.15.249 (S15): Platform Admin bugs 11/10-6. "Just like courses adapter i need scholarship to be read by code using
// Firecrawl but then use AI to extract attributes. Simple code extraction fields are making too many mistakes and rejecting the
// values. I can't validate and check every page." Decisions: AI reads every page; qualify two models and keep the better; AI-admitted
// scholarships pass the same hourly publish checks; the watch list first, then the rest in nightly batches.
// Qualifying never switches anything on: a model is made active, and AI admission switched on, as separate deliberate steps.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')

test('migration: models, instructions, sample, queue, answers; pinned models; activation and admission are separate gated steps; nothing dropped', () => {
  const sql = read('supabase/migrations/20261011010300_cf247_scholarship_ai_extraction.sql')
  for (const s of ['create table if not exists pipeline.scholarship_ai_models', 'create table if not exists pipeline.scholarship_ai_prompts', 'create table if not exists pipeline.scholarship_ai_extract_settings',
    'create table if not exists pipeline.scholarship_ai_sample', 'create table if not exists pipeline.scholarship_ai_queue', 'create table if not exists pipeline.scholarship_ai_extractions',
    "'qwen/qwen3-30b-a3b-instruct-2507'", "'openai/gpt-4.1-mini'", 'create or replace function public.admin_scholarship_ai', 'create or replace function public.svc_scholarship_ai_record',
    "raise exception 'qualify this model with the current instructions first'", "raise exception 'make a qualified model active first'",
    "if p_error is null and v_on and q.run_kind in ('admit', 'reread') then r := security.scholarship_ai_apply_v1(v_id); end if;",
    "'scholarship-ai-extract'", "'scholarship-ai-backfill'", "'scholarship_ai_qualify'", "'scholarship_ai_backfill'"]) expect(sql).toContain(s)
  // the unused earlier scaffold (pipeline.scholarship_ai_settings, keyed by country) is left alone
  expect(sql).not.toContain('pipeline.scholarship_ai_settings(')
  // a qualification run never activates a model or switches admission on
  const qualify = sql.slice(sql.indexOf("elsif p_action = 'qualify' then"), sql.indexOf("elsif p_action = 'activate' then"))
  expect(qualify).not.toMatch(/status = 'active'|ai_admission = /)
  expect(sql).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(sql).not.toMatch(/^alter table .* drop /im)
})

test('worker v0.20.1: the model is pinned, answers are strict JSON, and every fact is proven by a quote on the page', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toMatch(/const WORKER = "coverage-sweep-worker-v(?:[1-9]\d*\.\d+\.\d+|0\.(20\.[1-9]|2[1-9]\.\d+|[3-9]\d\.\d+))"/)
  expect(w).toContain('if (mode === "scholarship_ai") {')
  expect(w).toContain('provider: { require_parameters: true }')
  expect(w).toContain('json_schema: { name: "scholarship_page", strict: true')
  expect(w).toContain('if (d?.model && !String(d.model).startsWith(it.model)) throw Error(`returned model ${d.model}, not ${it.model}`);')
  expect(w).toContain('const verdict = !a.is_scholarship ? "not_scholarship" : !a.single_scholarship ? "listing" : !checks.name ? "unproven" : "scholarship";')
  // storedHtml is declared before the AI block uses it
  expect(w.indexOf('const storedHtml = async')).toBeLessThan(w.indexOf('if (mode === "scholarship_ai") {'))
})

test('mocked browser: Extraction shows models with qualification scores, the sample, and proven answers', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scholarships?tab=extraction')
  let x = page.locator('[data-scholarship-extraction="config"]')
  await expect(x.locator('[data-sx-admission]')).toContainText('Off')
  const q = x.locator('[data-sx-model="qwen3-30b"]')
  await expect(q).toContainText('38 / 41')
  await expect(q).toContainText('22 / 29')
  await expect(x.locator('[data-sx-model="gpt-4.1-mini"]')).toContainText('40 / 41')
  // v2.16.0: a model is made active by the cascade of the Scholarship pages service (Models & services › AI), not here; switching admission on needs an active model
  await expect(x.locator('[data-sx-action^="activate-"]')).toHaveCount(0)
  await expect(x.locator('[data-model-line="scholarship"] a')).toHaveAttribute('href', /#models-services\?tab=ai/)
  await expect(x.locator('[data-sx-action="admission-on"]')).toBeDisabled()
  await expect(x.locator('[data-sx-sample-row="31"] [data-sx-answer="gpt-4.1-mini"]')).toContainText('differs')
  // v2.16.0 (Platform Admin 13 Nov 2026 22:10): the configuration is on Models & services; the recent answers (results) stay on Scholarships › Coverage
  await expect(x.locator('[data-sx-recent-row]')).toHaveCount(0)
  await page.goto('/#scholarships?tab=coverage&at=sch-extraction')
  x = page.locator('[data-scholarship-extraction="results"]')
  await expect(x.locator('[data-sx-config-link] a')).toHaveAttribute('href', /#models-services\?tab=ai/)
  await x.locator('[data-sx-recent-row="501"]').click()
  await expect(x.locator('.sx-detail')).toContainText('valued at $15,548')
  await expect(x.locator('.sx-detail')).toContainText('Bachelor of Engineering (Honours)')
})

// v2.16.0 (Platform Admin 13 Nov 2026 19:14): "making a qualified model active asks for a reason and leaves AI admission off" is retired with the
// Make active button; the order of the models is the cascade of the Scholarship pages service, saved with a reason on Models & services › AI.
