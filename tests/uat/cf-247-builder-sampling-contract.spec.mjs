import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// v2.15.218 (Platform Admin, 8 Oct 2026 10:31): more samples, any course as a sample, a model per adapter (Platform Admin).
test('sampling and model: server rules and worker', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008000100_cf247_builder_sampling_and_model.sql', 'utf8')
  expect(m).toContain("'0f879e1197ab38ea980286adeb69c7a8'") // guarded against the live definition
  expect(m).toContain("if v_rank < 6 then raise exception 'Platform Admin required'")
  expect(m).toContain("'provider_intake_validation' = any(m.allowed_task_classes)") // only qualified intake models
  expect(m).toContain('m.enabled and not m.paused and m.retired_at is null')
  expect(m).toContain("if jsonb_array_length(v_d.samples) >= 10 then raise exception")
  expect(m).toContain("row_number() over (partition by q.kind order by random()) kr") // spread across course types
  expect(m).toContain("model = v_m->>'model', model_profile = v_m->>'code'")
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain("const kept = prior.find((x: any) => x && x.url === sm.url && !x.error && x.html_path);")
  const b = fs.readFileSync('supabase/functions/coverage-sweep/builder.ts', 'utf8')
  expect(b).toContain('.filter((c: any) => !c.error).slice(0, 10)')
  expect(b).not.toContain('.slice(0, 2).map(')
})

test.describe('mocked browser', () => {
  const basics = { provider_id: 'p-nd', name: 'Notre Dame', country: 'AU', courses: 131, pages: { stored: 131, read: 104 }, central: [], suggested: [], can_manage: true, adapter: null, qualify: null }
  const read = { budget: { used_usd: 0, limit_usd: 1.5, proposals: 0, limit_proposals: 60, model: 'qwen/qwen3-30b-a3b-instruct-2507' }, can_manage: true, max_samples: 10,
    model: { code: 'q', model: 'qwen/qwen3-30b-a3b-instruct-2507', chosen: false },
    models: [{ code: 'q', model: 'qwen/qwen3-30b-a3b-instruct-2507' }, { code: 'h', model: 'anthropic/claude-haiku-4.5' }],
    pages: [{ course: 'Bachelor of Accounting', code: '085834K', url: 'https://x/acc', read: true }, { course: 'Bachelor of 3D Art and Animation', code: '075731M', url: 'https://x/3d', read: false }],
    drafts: [{ id: 'd1', status: 'proposed', samples: [{ course: 'Bachelor of Accounting', url: 'https://x/acc' }], captures: [{ course: 'Bachelor of Accounting', url: 'https://x/acc' }], marks: [],
      proposals: [{ at: '2026-10-08T00:00:00Z', model: 'qwen/qwen3-30b-a3b-instruct-2507', cost: 0.001, reason: 'r', adapter: { patterns: { fee: 'x' } }, output: [{ course: 'Bachelor of Accounting', fee: 30000, intakes: [], extra: { duration: '3 years' } }] }] }] }
  test('Platform Admin picks a model, adds a course as a sample and sees attributes not found', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', r => r.fulfill({ json: basics }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', r => r.fulfill({ json: {} }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_uni_adapter_read', r => r.fulfill({ json: { provider: { name: 'Notre Dame' }, adapter: {}, pages: { read: 104 }, previews: [], can_manage: true } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder', async r => { const b = r.request().postDataJSON() || {}; calls.push(b); return r.fulfill({ json: b.p_action === 'read' ? read : { ok: true } }) })
    page.on('dialog', d => d.accept('Trial sampling'))
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-nd')
    const g = page.locator('[data-guided-build]')
    await g.getByLabel('Model for this adapter').selectOption('h')
    await expect.poll(() => calls.find(c => c.p_action === 'model')?.p_args).toEqual({ provider_id: 'p-nd', profile_code: 'h', reason: 'Trial sampling' })
    await g.getByLabel('Add a course as a sample').fill('3d art')
    await g.getByRole('button', { name: /Bachelor of 3D Art and Animation/ }).click()
    await expect.poll(() => calls.find(c => c.p_action === 'add_sample')?.p_args).toEqual({ provider_id: 'p-nd', url: 'https://x/3d', reason: 'Trial sampling' })
    await expect(page.locator('[data-sample-missing]').first()).toContainText('Intakes')
    await expect(page.locator('[data-sample-missing]').first()).not.toContainText('Fee')
    if (process.env.SAMPLING_SHOT) await page.screenshot({ path: process.env.SAMPLING_SHOT, fullPage: true })
  })
  test('PIM Admin sees the model but cannot change it or add samples', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 5 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder_basics', r => r.fulfill({ json: { ...basics, can_manage: false } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_uni_adapter_read', r => r.fulfill({ json: { provider: { name: 'Notre Dame' }, adapter: {}, pages: {}, previews: [], can_manage: false } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_builder', r => r.fulfill({ json: { ...read, can_manage: false, models: [], pages: [] } }))
    await page.goto('/#layer-2-discovery?tab=builder&provider=p-nd')
    await expect(page.locator('[data-adapter-model]')).toContainText('qwen/qwen3-30b-a3b-instruct-2507')
    await expect(page.getByLabel('Model for this adapter')).toHaveCount(0)
    await expect(page.locator('[data-sample-pick]')).toHaveCount(0)
  })
})
