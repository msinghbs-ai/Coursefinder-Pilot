// CF-247 (S76) v2.15.295. Platform Admin, 19 Oct 2026 22:47: "finish unis without adapter in waves, following scholarship and data
// enrichment"; choices "20+ and 5-19 re-find; 1-4 CRICOS-only", "AI re-check, then finish", "Check CRICOS, keep with soft flag",
// "Daily figure on Live activity".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const refind = fs.readFileSync('supabase/migrations/20261019110000_cf247_refind_wave.sql', 'utf8')
const adelaide = fs.readFileSync('supabase/migrations/20261019120000_cf247_adelaide_not_on_site_flags.sql', 'utf8')
const recheck = fs.readFileSync('supabase/migrations/20261019130000_cf247_scholarship_recheck.sql', 'utf8')
const reuse = fs.readFileSync('supabase/migrations/20261019140000_cf247_evidence_reuse_today.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const review = fs.readFileSync('src/ScholarshipAiReview.jsx', 'utf8')
const progress = fs.readFileSync('src/Progress.jsx', 'utf8')

test('re-find waves: wave providers are in focus; discovery re-opened only for sites never mapped; md5-guarded', () => {
  expect(refind).toContain("md5(pg_get_functiondef('security.enrich_focus_v1(uuid)'::regprocedure)) <> '73e1bcfd65528f5ae1e922a28437eeef'")
  expect(refind).toContain("or exists (select 1 from pipeline.adapter_builds b where b.provider_id = p_provider_id and b.wave like 'refind-%')")
  expect(refind).toContain("if p_wave is null or p_wave not like 'refind-%' then return 0; end if;")
  expect(refind).toContain("coalesce(d.method, '') like '%map:budget%'")
  expect(refind).toContain('revoke execute on function security.refind_wave_discovery_v1(text) from public, anon, authenticated;')
})

test('Adelaide: 8 courses kept with a soft flag only while CRICOS lists them', () => {
  expect(adelaide).toContain("'not_on_provider_site'")
  expect(adelaide).toContain("'soft', 'raised', 'auto'")
  expect(adelaide).toContain("r.scheme = 'cricos' and r.status = 'active'")
  expect((adelaide.match(/'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/g) || []).length).toBe(8)
})

test('scholarship re-check: cheap first model, a recommendation only, nothing published or rejected', () => {
  expect(recheck).toContain('join pipeline.scholarship_ai_models m on m.code = s.chain[1]')
  expect(recheck).not.toMatch(/scholarship_ai_apply_v1|review_decide|publication_status\s*=|status\s*=\s*'(admitted|refused)'/)
  expect(recheck).toContain("select cron.schedule('scholarship-recheck', '*/2 * * * *', $$select security.scholarship_recheck_fire_v1()$$);")
  expect(recheck).toContain("security.pipeline_num_v1('batch.scholarship_recheck', 12)")
  expect(recheck).toContain("array['''decision'', r.decision,', '''decision'', r.decision, ''recheck'', r.recheck,']")
  expect(worker).toContain('if (mode === "scholarship_recheck") {')
  expect(worker).toContain('const out = judgeScholarshipRecheck(a, `${title} ${h1} ${text}`);')
  expect(worker).toContain('INTL_WORDS.test(aq)')
  expect(worker).toContain('const notNamed = a?.audience === "not_stated" || (["international", "both"].includes(a?.audience) && on(aq) && !INTL_WORDS.test(aq));')
  expect(review).toContain('<Recheck r={v.recheck}/>')
  expect(reuse).toContain("date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne'")
  expect(progress).toContain("supabase.rpc('admin_evidence_reuse_today')")
})

test.describe('mocked browser', () => {
  test('Live activity (Running) shows pages kept once today', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_evidence_reuse_today', r => r.fulfill({ json: { read: 492, kept: 310, new_copies: 182, new_bytes: 12000000, on: true } }))
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_progress_read', r => r.fulfill({ json: { jobs: [], credits_hour: {}, refused_hour: 0 } }))
    await page.goto('/#coverage?tab=progress&view=running')
    const tile = page.locator('[data-progress-tile="pages-kept"]')
    await expect(tile).toContainText('Pages kept once, today')
    await expect(tile.locator('strong')).toHaveText('310')
    await expect(tile).toContainText('of 492 read; 182 new copies')
  })

  test('a held scholarship shows its re-check, and Refuse starts with the reason', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_scholarship_ai', r => r.fulfill({ json: { can_decide: true, pending: 1, reviews: [{ id: 7, url: 'https://uni.example/s/housing', reason: 'who it is for is not proven by a quote on the page', status: 'pending', provider: 'Example University', scholarship: 'Housing Award',
      recheck: { state: 'done', recommendation: 'audience_not_stated', why: 'The page does not say international students may apply; do not publish unless you know otherwise.', audience_quote: '' },
      answers: [{ id: 1, model_code: 'qwen3-30b', answer: { is_scholarship: true, name: 'Housing Award', audience: 'both' }, checks: { audience: false } }] }] } }))
    await page.goto('/#layer4?tab=aireview')
    const row = page.locator('[data-ai-review-row="7"]')
    await expect(row.locator('[data-ai-recheck="audience_not_stated"]')).toContainText('Re-check: international students not mentioned')
    await row.locator('[data-ai-review-refuse]').click()
    await expect(row.getByLabel('Reason for refusing')).toHaveValue('The page does not say international students may apply (AI re-check).')
  })
})
