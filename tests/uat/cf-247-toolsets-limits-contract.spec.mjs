// CF-247 v2.15.177 (Decision 252, Platform Admin 4 Oct 2026 13:37): OpenRouter observed, not capped by the platform;
// a notice on each layer when a toolset it depends on hits a limit or times out; Serper and ScrapingBee saials across
// every country; every variable a setting the Platform Admin changes in the UI.
import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const read = p => readFileSync(new URL(`../../${p}`, import.meta.url), 'utf8')

test('migrations shaped: observe mode guarded by md5, notices from logs, sample runs record only', () => {
  const samples = ['20261004000700_cf247_toolset_trial_tables', '20261004000710_cf247_toolset_trial_settings', '20261004000720_cf247_toolset_trial_services', '20261004000730_cf247_toolset_trial_backlog',
    '20261004000740_cf247_toolset_trial_write', '20261004000750_cf247_trial_close_probe', '20261004000760_cf247_trial_release_leases', '20261004000770_cf247_trial_run_status',
    '20261004000780_cf247_trial_record', '20261004000790_cf247_trial_next', '20261004000800_cf247_trial_results_read', '20261004000900_cf247_toolset_keys_plans_sample_runs']
  for (const f of ['20261004000600_cf247_toolset_limits_and_notices', ...samples]) {
    const m = read(`supabase/migrations/${f}.sql`)
    for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
    expect(m).not.toMatch(/insert into catalogue\.|update catalogue\.|admitted_value/)
  }
  const a = read('supabase/migrations/20261004000600_cf247_toolset_limits_and_notices.sql')
  for (const h of ['15fcf19b03b42539a912dd0ee1501bf7', 'c081a641b616aa3cc2859730468ff56a', 'ae1a34a92116682c5477cf22bf38f7bb']) expect(a).toContain(`is distinct from '${h}'`)
  expect(a).toContain("('openrouter', 'OpenRouter (AI models)', 'ai', '{3}', null, 'observe',")
  expect(a).toContain("select coalesce((select t.enforcement is distinct from 'observe' from pipeline.platform_toolsets t where t.key = p_toolset), true)")
  expect(a).toContain("raise exception 'Platform Admin required'")
  const b = samples.map(f => read(`supabase/migrations/${f}.sql`)).join('\n')
  expect(b).toContain("pg.read_status in ('needs_render', 'blocked')")
  expect(b).not.toMatch(/read_status in \([^)]*robots_disallowed/)
  expect(b).toMatch(/'serper', 'Serper \(web search, trial\)'[\s\S]*?, false, 'Platform Operations'/)
  // Decision 252 amended (14:26): no trial wording; keys carry plan limits set in the UI; renamed, not recreated
  const k = read('supabase/migrations/20261004000900_cf247_toolset_keys_plans_sample_runs.sql')
  expect(k).toContain('alter table pipeline.toolset_trial_runs rename to toolset_sample_runs;')
  for (const key of ['plan_name', 'plan_credits', 'plan_renews_monthly', 'plan_counted_from', 'plan_reserve', 'plan_max_concurrency']) expect(k).toContain(`('serper', '${key}'`)
  expect(k).toContain("display_name = 'Serper (web search)'")
  // the migration tool reads a semicolon inside text as the end of a statement: none in any text value
  for (const m of k.replace(/--[^\n]*/g, '').matchAll(/'(?:[^']|'')*'/g)) expect(m[0]).not.toContain(';')
})

test('routing worker: the credit floor comes from the register, not a constant', () => {
  const w = read('supabase/functions/layer3-model-routing/index.ts')
  expect(w).not.toContain('CREDIT_FLOOR_USD')
  expect(w).toContain('rpc("svc_layer3_credit_policy", {})')
  expect(w).toContain('pol.enforce && c.remaining < pol.floor')
})

test('sample-run worker: classifiers, plan limits respected, no constants for limits, no trial wording', async () => {
  const t = read('supabase/functions/toolset-runner/index.ts')
  expect(t.toLowerCase()).not.toContain('trial')
  expect(t).toContain('Math.min(Number(s.sample_concurrency) || 1, planMax)')
  for (const k of ['sample_seconds_per_call', 'sample_concurrency', 'title_match_min', 'course_query', 'provider_query', 'render_js', 'premium_proxy', 'wait_ms', 'directory_hosts']) expect(t).toContain(`s.${k}`)
  const { execFileSync } = await import('node:child_process'); const os = await import('node:os'); const path = await import('node:path')
  const out = path.join(os.tmpdir(), `toolset-runner-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/toolset-runner/index.ts', '--bundle', '--format=esm', '--platform=neutral', '--external:npm:*', '--external:jsr:*', `--outfile=${out}`])
  const src = readFileSync(out, 'utf8').replace(/^import .*$/gm, '').replace(/Deno\.serve\([\s\S]*$/, '')
  const mod = await import('data:text/javascript;base64,' + Buffer.from(src + '\nexport { classifyCourseSearch, classifyProviderSearch, classifyRender, titleScore, fill };').toString('base64'))
  expect(mod.fill('{course} {provider}', { course: 'Bachelor of Nursing', provider: 'Example University' })).toBe('Bachelor of Nursing Example University')
  const c = mod.classifyCourseSearch({ course: 'Bachelor of Nursing', domain: 'example.edu.au', earlier_candidate: 'https://www.example.edu.au/study/nursing/' },
    [{ title: 'Bachelor of Nursing | Example University', link: 'https://www.example.edu.au/study/nursing', position: 1 }], 0.6)
  expect(c).toMatchObject({ outcome: 'found_on_provider_site', same_as_earlier_candidate: true })
  expect(mod.classifyCourseSearch({ course: 'Bachelor of Nursing', domain: 'example.edu.au' }, [{ title: 'Nursing degrees', link: 'https://studyportals.com/x' }], 0.6).outcome).toBe('other_sites_only')
  expect(mod.classifyProviderSearch({ provider: 'Lakeside College' }, [{ title: 'Lakeside College - Facebook', link: 'https://facebook.com/lakeside' }, { title: 'Lakeside College | Home', link: 'https://lakeside.ca/' }], 0.6, ['facebook.com'])).toMatchObject({ outcome: 'likely_official_site', suggested_site: 'https://lakeside.ca' })
  const r = mod.classifyRender({ course: 'Master of Data Science', code: '012345K' }, 200, '<html><title>Master of Data Science</title><body><h1>Master of Data Science</h1><p>Intakes: February and July. IELTS 6.5. A$42,000 a year.</p></body></html>', 0.6)
  expect(r).toMatchObject({ outcome: 'rendered_course_page', markers: { intake: true, english: true, tuition: true } })
  expect(mod.classifyRender({ course: 'X' }, 403, '<html>Access denied</html>', 0.6).outcome).toBe('blocked')
})

test('browser: notices on the layer page, acknowledged with a reason', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.accept('Seen; reviewing the batch size'))
  await page.goto('/#layer-2-discovery')
  const strip = page.locator('[data-layer-notices="2"]')
  await expect(strip.locator('[data-notice="scheduled_jobs:2:timeout:scholarship-nationality"]')).toContainText('hit the database time limit')
  await expect(strip.locator('.tn-seen summary')).toHaveText('1 acknowledged')
  await strip.locator('[data-notice="scheduled_jobs:2:timeout:scholarship-nationality"]').getByRole('button', { name: 'Acknowledge' }).click()
  await expect.poll(() => page.l3calls.find(c => c.toolsets === 'ack')?.args).toMatchObject({ notice_key: 'scheduled_jobs:2:timeout:scholarship-nationality', reason: 'Seen; reviewing the batch size' })
  await page.goto('/#layer-3-ai')
  await expect(page.locator('[data-layer-notices="3"]')).toContainText('the key\'s own spending limit')
})

test('browser: Models & services — OpenRouter observe only, key and plan limits, settings by section, sample runs started and continued', async ({ page }) => {
  await mockAdmin(page)
  page.on('dialog', d => d.accept('Decision 252 sample'))
  await page.goto('/#models-services')
  const or = page.locator('[data-toolset="openrouter"]')
  await expect(or.locator('[data-toolset-mode="openrouter"]')).toContainText('Observe only')
  await expect(or.locator('[data-openrouter]')).toContainText('Balance US$27.67')
  await or.getByRole('button', { name: 'Switch to stop at limits' }).click()
  await expect.poll(() => page.l3calls.find(c => c.toolsets === 'enforcement')?.args).toMatchObject({ toolset: 'openrouter', enforcement: 'stop' })
  const q = page.locator('[data-toolset-setting="serper.course_query"]')
  await q.getByRole('textbox').fill('"{course}" {provider}')
  await q.getByRole('button', { name: 'Save' }).click()
  await expect.poll(() => page.l3calls.find(c => c.toolsets === 'setting')?.args).toMatchObject({ toolset: 'serper', key: 'course_query', value: '"{course}" {provider}' })
  const cc = page.locator('[data-toolset-setting="serper.sample_countries"]')
  await cc.getByRole('textbox').fill('AU, NZ, CA, GB')
  await cc.getByRole('button', { name: 'Save' }).click()
  await expect.poll(() => page.l3calls.filter(c => c.toolsets === 'setting').map(c => c.args.value)).toContainEqual(['AU', 'NZ', 'CA', 'GB'])
  await expect(page.locator('[data-toolset-key="scrapingbee"]')).toContainText('No key saved')
  const plan = page.locator('[data-toolset-plan="serper"]')
  await expect(plan).toContainText('Free plan')
  await expect(plan).toContainText('48 of 2,500 credits used since 2026-10-04')
  await expect(page.locator('[data-toolset-key="serper"]')).toContainText('Replace the key on Environment & integrations')
  for (const sec of ['Key and plan limits', 'How the service is used', 'Sample runs']) await expect(page.locator(`[data-toolset-section="serper:${sec}"]`)).toBeVisible()
  const credits = page.locator('[data-toolset-setting="serper.plan_credits"]')
  await credits.getByRole('textbox').fill('50000')
  await credits.getByRole('button', { name: 'Save' }).click()
  await expect.poll(() => page.l3calls.filter(c => c.toolsets === 'setting').map(c => c.args)).toContainEqual(expect.objectContaining({ toolset: 'serper', key: 'plan_credits', value: '50000' }))
  await expect(page.locator('[data-toolsets]')).not.toContainText(/trial/i)
  const tr = page.locator('[data-toolset-samples]')
  await expect(tr.getByRole('button', { name: 'Run a sample with ScrapingBee: Read pages that need a browser' })).toBeDisabled()
  await tr.getByRole('button', { name: 'Run a sample with Serper: Find provider websites' }).click()
  await expect.poll(() => page.l3calls.find(c => c.sample === 'start')?.args).toMatchObject({ toolset: 'serper', purpose: 'find_provider_site' })
  await expect.poll(() => page.l3calls.find(c => c.runnerKick)?.runnerKick).toMatchObject({ action: 'run', run_id: '7d1e0000-0000-4000-8000-000000000002' })
  await tr.locator('[data-sample-run="7d1e0000-0000-4000-8000-000000000001"]').getByRole('button', { name: 'Continue' }).click()
  await expect.poll(() => page.l3calls.filter(c => c.runnerKick).length).toBe(2)
  await expect(tr.locator('[data-sample-results] [data-sample-outcome="found_on_provider_site"]')).toContainText('14 (70%)')
  await expect(tr.locator('[data-sample-projection]')).toContainText('US$7.33')
})
