// Guards: CF-247 v2.15.264 (S28): Platform Admin, 13 Oct 2026 00:09: "Layer 3 has removed the configuration of OpenAI and access to toolsets and limits;
// CF-247 v2.15.264 (S28): Platform Admin, 13 Oct 2026 00:09: "Layer 3 has removed the configuration of OpenAI and access to toolsets
// and limits; restore them as a tab in Models & services." Decisions: three tabs; scholarship AI models editable in the AI tab.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const sql = fs.readFileSync('supabase/migrations/20261013012100_cf247_ai_openrouter_tab.sql', 'utf8')

test('12100: one read for the AI tab; central pages model and switch by a Platform Admin with a reason; nothing dropped', () => {
  expect(sql).toContain('create or replace function public.admin_ai_config_read() returns jsonb')
  expect(sql).toContain("if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required'")
  expect(sql).toContain("if length(v_reason) < 4 then raise exception 'a reason is required'; end if;")
  expect(sql).toContain("x.status <> 'retired' and x.model_identifier <> 'person'")
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('nav: Models & services has Services, AI & OpenRouter and Toolsets & limits tabs', () => {
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  expect(nav).toContain("{ key: 'services', label: 'Services', min: 4 },")
  expect(nav).toContain("{ key: 'ai', label: 'AI & OpenRouter', min: 3 },") // v2.15.301: Scholarship extraction (Curator) is on this tab; AiConfig stays rank 4
  expect(fs.readFileSync('src/mature-main.jsx', 'utf8')).toContain("{rank>=4&&<AiConfig onError={err}/>}")
  expect(nav).toContain("{ key: 'limits', label: 'Toolsets & limits', min: 4 },")
})

test.describe('mocked browser', () => {
  test('AI & OpenRouter: balance and mode, guards per use, central pages model, scholarship models, profiles', async ({ page }) => {
    page.on('dialog', d => d.accept('Testing the AI tab'))
    await mockAdmin(page)
    await page.goto('/#models-services?tab=ai')
    const t = page.locator('[data-ai-config]')
    await expect(t).toBeVisible()
    for (const id of ['services.ai.openrouter', 'services.ai.uses', 'services.ai.scholarship-models', 'services.ai.profiles']) await t.locator(`[data-card="${id}"] .cf-card-toggle`).click()
    await expect(t.locator('[data-ai-openrouter]')).toContainText('US$29.25')
    await expect(t.locator('[data-ai-key]')).toContainText('shared by 55 model profiles')
    await expect(t.locator('[data-ai-use="central_ai"]')).toContainText('GPT 4.1 Mini') // UI audit Phase 1: the list names the model; the identifier is on hover
    await expect(t.locator('[data-ai-use="central_ai"] [title="openai/gpt-4.1-mini"]')).toHaveCount(1)
    await t.locator('[data-ai-use="scholarship_ai"] input').fill('25')
    await t.locator('[data-ai-use="scholarship_ai"]').getByRole('button', { name: 'Save' }).click()
    await expect.poll(() => page.l3calls.find(c => c.toolsets === 'setting')?.args).toMatchObject({ toolset: 'openrouter', key: 'guard_scholarship_ai', value: '25', reason: 'Testing the AI tab' })
    await t.locator('[data-ai-central] select').selectOption('gpt-4.1')
    await expect.poll(() => page.l3calls.find(c => c.aiConfig === 'central_model')?.args).toMatchObject({ code: 'gpt-4.1', reason: 'Testing the AI tab' })
    await expect(t.locator('[data-ai-scholarship-models] [data-sx-models]')).toBeVisible()
    await expect(t.locator('[data-ai-profile="openrouter-intake-l3c-qwen3-30b-a3b-2507-v1"]')).toContainText('0ef16b1996e1')
  })
  test('Toolsets & limits is its own tab', async ({ page }) => {
    await mockAdmin(page)
    await page.goto('/#models-services?tab=limits')
    await expect(page.locator('[data-toolsets]')).toBeVisible()
    await page.goto('/#models-services')
    await expect(page.locator('[data-card="services.ai-models"]')).toBeVisible()
    await expect(page.locator('[data-toolsets]')).toHaveCount(0)
  })
})
