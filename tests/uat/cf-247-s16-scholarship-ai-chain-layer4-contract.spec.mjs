// CF-247 v2.15.250 (S16): Platform Admin 11 Oct 2026, "Qwen 3 then GPT-4.1 mini then to Layer 4. Layer 4 review the current parked items:
// reroute to adapters or the new scholarship mechanism." GPT takes over only when Qwen's reply fails or a fact it states is not proven
// on the page; a page no model settles goes to Layer 4 › AI could not decide, where a person's decision is kept as an exception.
// Parked course items an adapter can settle are closed and the course read again; parked scholarships are read again by the AI.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => fs.readFileSync(p, 'utf8')
const sql = () => read('supabase/migrations/20261011010400_cf247_scholarship_ai_chain_layer4_reroute.sql')

test('migration: model chain, cascade on an unsettled answer, Layer 4 reviews kept as exceptions; nothing dropped', () => {
  const s = sql()
  for (const x of ['add column if not exists chain text[]', 'create or replace function security.scholarship_ai_next_model_v1', 'create or replace function security.scholarship_ai_unsettled_v1',
    'create table if not exists pipeline.scholarship_ai_reviews', 'create or replace function security.scholarship_ai_review_open_v1', 'create or replace function security.scholarship_ai_review_apply_v1',
    "v_next := case when v_why is not null then security.scholarship_ai_next_model_v1(q.model_code) end;", "coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id)",
    "if v_on and v_why is not null and (p_error is null or q.attempts >= 3) then r := security.scholarship_ai_review_open_v1(v_id, v_why);",
    "raise exception 'qualify every model in the chain with the current instructions first'", "r.status in ('admitted', 'refused') and r.url = e.url and coalesce(r.storage_path, '') = coalesce(e.storage_path, '')"]) expect(s).toContain(x)
  // a person's refusal of a known scholarship is a hold a person made; automatic holds alone are released by a passing AI re-read
  expect(s).toContain("values (v.scholarship_id, 'Refused in Layer 4 › AI could not decide: ' || coalesce(p_note, ''), 'admin', now())")
  expect(s).toContain("h.released_at is null and h.held_by = 'auto')")
  expect(s).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(s).not.toMatch(/^alter table .* drop /im)
})

test('migration: parked course items go to the adapter only for a field it admits; new ones are rerouted on arrival', () => {
  const s = sql()
  expect(s).toContain("when 'course_intake' then 'intakes' when 'course_english' then 'english' when 'provider_current_tuition_validation' then 'fee' end")
  expect(s).toContain('and a.enabled and coalesce(a.admit, false) and (a.admit_fields is null or v_f = any (a.admit_fields))')
  expect(s).toContain('create or replace trigger layer4_review_items_reroute before insert on pipeline.layer4_review_items')
  expect(s).toContain('select security.layer4_reroute_parked_courses_v1();')
  // a course address (official_course_url) has no adapter field and stays with a person
  expect(s).not.toMatch(/when 'official_course_url' then '/)
})

test('mocked browser: Extraction sets the reading order and links to the pages no model could settle', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#scholarships?tab=extraction')
  const x = page.locator('[data-scholarship-extraction]')
  await expect(x.locator('[data-sx-chain-editor]')).toBeVisible()
  await x.getByLabel('Model that reads first').selectOption('qwen3-30b')
  // GPT-4.1 mini is still qualifying in the fixture, so it cannot be put in the chain yet
  await x.getByLabel('Model that reads next').selectOption('gpt-4.1-mini')
  await expect(x.locator('[data-sx-action="set-chain"]')).toBeDisabled()
  await x.getByLabel('Model that reads next').selectOption('')
  await x.locator('[data-sx-action="set-chain"]').click()
  await x.getByLabel('Reason: Set the order').fill('Qwen first after qualification')
  await x.locator('[data-sx-confirm="set-chain"]').click()
  await expect(x.locator('[data-sx-note]')).toContainText('AI admission is unchanged')
  expect(page.l3calls.find(c => c.scholarshipAi?.p_action === 'set_chain').scholarshipAi.p_args.models).toEqual(['qwen3-30b'])
  await expect(x.locator('[data-sx-reviews-link]')).toHaveAttribute('href', '#layer-4-review?tab=aireview')
})

test('mocked browser: Layer 4 › AI could not decide shows both answers; admitting sends the chosen answer; refusing needs a reason', async ({ page }) => {
  await mockAdmin(page)
  await page.goto('/#layer-4-review?tab=aireview')
  const v = page.locator('[data-ai-review]')
  await expect(v.locator('[data-ai-review-adapter]')).toContainText('704')
  await expect(v.locator('[data-ai-review-reroutes]')).toContainText('Intakes 625')
  const row = v.locator('[data-ai-review-row="77"]')
  await expect(row).toContainText('who it is for is not proven')
  await expect(row.locator('[data-ai-review-answer="qwen3-30b"]')).toContainText('for students from overseas')
  await expect(row.locator('[data-ai-review-answer="gpt-4.1-mini"]')).toContainText('International and domestic')
  await row.locator('[data-ai-review-refuse]').click()
  await expect(row.locator('[data-ai-review-refuse-confirm]')).toBeDisabled()
  await row.getByLabel('Reason for refusing').fill('')
  await row.locator('[data-ai-review-answer="qwen3-30b"] input').check()
  await row.getByRole('button', { name: 'Cancel' }).click()
  await row.locator('[data-ai-review-admit]').click()
  await expect(v.locator('[data-ai-review-note]')).toContainText('Admitted')
  const call = page.l3calls.find(c => c.scholarshipAi?.p_action === 'review_decide')
  expect(call.scholarshipAi.p_args).toMatchObject({ review_id: 77, decision: 'admit', extraction_id: 901 })
})

test('worker v0.20.2: an audience quote must itself name international (or domestic) students', () => {
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('const INTL_WORDS = /\\b(international|overseas|offshore|student visa|subclass 500|non[- ]?residents?|foreign)\\b/i;')
  expect(w).toContain('["international", "both"].includes(a?.audience) ? INTL_WORDS.test(String(a?.audience_quote || ""))')
  expect(w).toContain('const WORKER = "coverage-sweep-worker-v0.20.2"')
})

