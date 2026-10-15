// CF-247 (S45): the flag unit. Platform Admin, 15 Oct 2026 15:20: "we don't keep burning the toolset on repetitive waste and produce nothing ...
// have flag unit that can be removed or raised manually and automatically by tried burn. evidence of that flag will details why it was raised or
// released manually and the said entry or provider get re-entered in queue." Decisions: providers, course fields and jobs; hard at once, soft
// after 2 tries; change detected + free recheck on a back-off; a person raises or releases with a reason.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261015080000_cf247_flag_unit.sql', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const panel = fs.readFileSync('src/FlagsPanel.jsx', 'utf8')

test('one flag table with state, evidence and a history every writer fills; settings for tries and back-offs', () => {
  expect(mig).toContain("add column if not exists state text not null default 'raised' check (state in ('counting', 'raised', 'released'))")
  expect(mig).toContain('create table pipeline.enrichment_flag_events (')
  expect(mig).toContain('create trigger enrichment_flags_sync before insert or update on pipeline.enrichment_flags')
  expect(mig).toContain("if old.release_kind = 'person' then new.cleared_at := old.cleared_at; return new; end if;  -- a person's release stands against automatic re-raising")
  for (const k of ['flag.soft_tries', 'flag.recheck_days', 'flag.job_recheck_hours', 'flag.empty_calls_to_pause', 'flag.never_pause_modes', 'flag.manage_min_rank', 'batch.flag_check', 'batch.flag_change_scan'])
    expect(mig).toContain(`('pipeline', '${k}',`)
})

test('raise: hard at once, soft after the set tries; release puts the item back in its queue', () => {
  expect(mig).toContain("v_state := case when p_kind = 'hard' or v_tries >= v_soft then 'raised' else 'counting' end;")
  expect(mig).toContain("v_q := security.flag_requeue_v1(f.id);")
  expect(mig).toContain("'Back in the queue: ' || v_q")
})

test('Enrich fields: held items are not queued, a second try needs new input, a skip counts, a fill releases', () => {
  expect(mig).toContain('create trigger field_enrich_items_gate before insert on pipeline.field_enrich_items')
  expect(mig).toContain("return null;  -- held, or tried once on the same input: not queued")
  expect(mig).toContain("'Value found by Enrich fields'")
})

test('central pages held until due; logo finder and website checks; worker jobs that run empty are paused and tried again', () => {
  expect(mig).toContain("'central_not_due',")
  expect(mig).toContain("and (s.requested_at is not null or not security.flag_provider_held_v1(s.provider_id, array['central_not_due', 'central_budget', 'site_unreachable']))")
  expect(mig).toContain("'site_unreachable', 'Website did not answer: ' || p_reason, 'hard'")
  expect(mig).toContain("perform cron.alter_job(j.jobid, active := false);")
  expect(mig).toContain("'Trial run: switched on again to look for new work'")
  expect(mig).toContain("select cron.schedule('flag-recheck', '*/10 * * * *', 'select security.flag_recheck_v1()');")
  expect(worker).toContain('if (mode === "flag_check") {')
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(2[6-9])\.\d+";/)
})

test.describe('mocked browser', () => {
  test('Flags: held items with reasons, history with evidence, release with a reason', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_flags', async route => {
      const b = route.request().postDataJSON(); calls.push(b)
      const a = b.p_action
      if (a === 'summary') return route.fulfill({ json: { can_change: true, by_reason: [{ entity: 'provider', reason_code: 'site_unreachable', held: 1, counting: 0, released: 0 }], last_24h: { raised: 1 } } })
      if (a === 'list') return route.fulfill({ json: { can_change: true, total: 1, items: [{ id: 7, entity: 'provider', entity_key: 'p1', provider_name: 'Alpha University', field: '', reason_code: 'site_unreachable', reason: 'Website did not answer: home page not read (blocked 403)', kind: 'hard', state: 'raised', tries: 1, raised_by: 'logo-find', raised_by_kind: 'auto', flagged_at: '2026-10-15T04:00:00Z', next_check_at: '2026-10-18T04:00:00Z' }] } })
      if (a === 'events') return route.fulfill({ json: { flag: { reason_code: 'site_unreachable', reason: 'Website did not answer', evidence: { http: 403 } }, events: [{ id: 1, action: 'raised', actor: 'logo-find', actor_kind: 'auto', reason: 'Website did not answer', evidence: { http: 403 }, at: '2026-10-15T04:00:00Z' }] } })
      if (a === 'release') return route.fulfill({ json: { released: 1, items: [{ id: 7, requeued: 'logo finder and central pages' }] } })
      return route.fulfill({ json: {} })
    })
    page.on('dialog', d => d.accept('Site is back, checked by hand'))
    await page.goto('/#coverage?tab=flags')
    await expect(page.getByText('Alpha University')).toBeVisible()
    await expect(page.getByText('Website does not answer').first()).toBeVisible()
    await page.getByRole('button', { name: 'History' }).click()
    await expect(page.getByRole('dialog', { name: 'Flag history' })).toContainText('"http": 403')
    await page.getByRole('button', { name: 'Close' }).click()
    await page.getByRole('button', { name: 'Release', exact: true }).click()
    await expect(page.locator('.cf-flag-note')).toHaveText('1 released and re-queued.')
    expect(calls.find(c => c.p_action === 'release').p_args).toEqual({ ids: [7], reason: 'Site is back, checked by hand' })
  })
})
