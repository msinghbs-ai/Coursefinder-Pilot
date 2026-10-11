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
  expect(w).toContain('const WORKER = "coverage-sweep-worker-v0.20.1"')
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
  const x = page.locator('[data-scholarship-extraction]')
  await expect(x.locator('[data-sx-admission]')).toContainText('Off')
  const q = x.locator('[data-sx-model="qwen3-30b"]')
  await expect(q).toContainText('38 / 41')
  await expect(q).toContainText('22 / 29')
  await expect(x.locator('[data-sx-model="gpt-4.1-mini"]')).toContainText('40 / 41')
  // a model still qualifying cannot be made active; switching admission on needs an active model
  await expect(x.locator('[data-sx-model="gpt-4.1-mini"] [data-sx-action="activate-gpt-4.1-mini"]')).toBeDisabled()
  await expect(x.locator('[data-sx-action="admission-on"]')).toBeDisabled()
  await expect(x.locator('[data-sx-sample-row="31"] [data-sx-answer="gpt-4.1-mini"]')).toContainText('differs')
  await x.locator('[data-sx-recent-row="501"]').click()
  await expect(x.locator('.sx-detail')).toContainText('valued at $15,548')
  await expect(x.locator('.sx-detail')).toContainText('Bachelor of Engineering (Honours)')
})

test('mocked browser: making a qualified model active asks for a reason and leaves AI admission off', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scholarships?tab=extraction')
  const x = page.locator('[data-scholarship-extraction]')
  await x.locator('[data-sx-action="activate-qwen3-30b"]').click()
  await expect(x.locator('[data-sx-confirm="activate-qwen3-30b"]')).toBeDisabled()
  await x.getByLabel('Reason: Make active').fill('Best scores on the sample')
  await x.locator('[data-sx-confirm="activate-qwen3-30b"]').click()
  await expect(x.locator('[data-sx-note]')).toContainText('AI admission is unchanged')
  const call = page.l3calls.find(c => c.scholarshipAi?.p_action === 'activate')
  expect(call.scholarshipAi.p_args).toEqual({ model_code: 'qwen3-30b', reason: 'Best scores on the sample' })
  expect(page.l3calls.some(c => c.scholarshipAi?.p_action === 'set_admission')).toBe(false)
})
