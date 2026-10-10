// CF-247 v2.15.238 (R5): Platform Admin bug list of 10 Oct 2026 — Features 5, 6 and 7; decision "New 'archived' status".
// Archive is a clean-up workflow with a checklist; Layer 1 departures archive (and restore) providers automatically; Providers › Archived
// lists archived providers and courses that are not active, with why, and Restore.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261010007000_cf247_r5_archived_status.sql'

test('server: archive record, clean-up and restore, Layer 1 triggers, review read, md5-guarded, nothing dropped or deleted', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  for (const md5 of ['88d604e0b4dcb6a012550d2384a63bdb', '3306e12173001cad55424308c605ee2c', 'd319a992fc122798005b616fc7a243d2', 'a8acab9d6f56a5ccca9dafa435318f05', 'e9d755ed1213a79f39276ae9ec093be1']) expect(sql).toContain(md5)
  expect(sql).toContain('create table if not exists pipeline.provider_archives (')
  expect(sql).toContain("update catalogue.providers set lifecycle_status = 'archived', publication_status = 'unpublished', updated_at = now() where id = p_provider_id;")
  expect(sql).toContain("update pipeline.uni_adapters set enabled = false, updated_at = now() where provider_id = p_provider_id and enabled returning 1")
  expect(sql).toContain("update pipeline.course_link_recipes set active = false, updated_at = now() where provider_id = p_provider_id and active returning 1")
  expect(sql).toContain("update pipeline.layer4_review_items x set status = 'pending', decided_at = null")
  expect(sql).toContain('create trigger layer1_departure_archive after insert on pipeline.layer1_provider_departures')
  expect(sql).toContain('create trigger layer1_retirement_restore after update of reactivated_at on pipeline.layer1_course_retirements')
  expect(sql).toContain("perform security.provider_archive_apply_v1(p.id, 'departure_review'")
  expect(sql).toContain("insert into search.refresh_requests(requested_by) values (format('course %s %s by hand'")
  expect(sql).toContain("  WHERE c.lifecycle_status IS DISTINCT FROM 'active'::text;")
  expect(sql).toContain('create or replace function public.admin_archive_read(')
  expect(sql).toContain("if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required'")
  // the new objects and data steps delete nothing (existing function bodies are kept as they were)
  const own = sql.slice(sql.indexOf('-- 1. Archive records'), sql.indexOf('CREATE OR REPLACE FUNCTION public.admin_provider_edit(')) + sql.slice(sql.indexOf('-- 9. The 10 providers'))
  expect(own.length).toBeGreaterThan(5000)
  expect(own).not.toMatch(/\b(drop\s+(table|function|schema|index|view|trigger)|delete\s+from|truncate)\b/i)
  expect(sql).not.toMatch(/\bdrop\s+(table|function|schema|view|trigger)\b/i)
})

test.describe('mocked browser', () => {
  const read = {
    providers: { section: 'providers', total: 1, can_restore: true, counts: { providers: 1, courses: 2, departures_waiting: 1 },
      rows: [{ id: 'p-u', name: 'University of South Australia (UniSA)', country: 'AU', status: 'archived', source: 'layer1_departure', reason: 'All its registered courses left the register', at: '2026-10-11T00:00:00Z', courses: 344, departure: 'needs_review' }] },
    courses: { section: 'courses', total: 1, can_restore: true, counts: { providers: 1, courses: 2, departures_waiting: 1 },
      rows: [{ id: 'c-1', title: 'Bachelor of Nursing', code: '012345A', status: 'inactive', provider_id: 'p-a', provider: 'Alpha College', provider_status: 'active', why: 'Archived by hand', at: '2026-10-10T00:00:00Z' }] },
  }
  async function setup(page, rank) {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page, { rank })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_archive_read', async r => { const b = r.request().postDataJSON(); calls.push({ fn: 'read', ...b }); await r.fulfill({ json: read[b.p_section] }) })
    for (const fn of ['admin_provider_restore', 'admin_course_edit']) await page.route(`https://example.supabase.co/rest/v1/rpc/${fn}`, async r => { calls.push({ fn, ...r.request().postDataJSON() }); await r.fulfill({ json: {} }) })
    return calls
  }

  test('Providers › Archived lists archived providers with why, then courses; Restore works for each', async ({ page }) => {
    const calls = await setup(page, 5)
    await page.goto('/#providers?tab=archived')
    const box = page.locator('[data-archived-review]')
    await expect(box.locator('[data-archived-provider="p-u"]')).toContainText('Left the register')
    await expect(box.locator('[data-departures-waiting]')).toContainText('1 provider departure waits')
    await box.locator('[data-archived-provider="p-u"]').getByRole('button', { name: 'Restore' }).click()
    await expect(box.getByRole('status')).toContainText('restored')
    expect(calls.find(c => c.fn === 'admin_provider_restore')).toEqual({ fn: 'admin_provider_restore', p_provider_id: 'p-u' })
    await box.getByRole('tab', { name: /Courses not active/ }).click()
    await expect(box.locator('[data-archived-course="c-1"]')).toContainText('Archived by hand')
    await box.locator('[data-archived-course="c-1"]').getByRole('button', { name: 'Restore' }).click()
    expect(calls.find(c => c.fn === 'admin_course_edit')).toEqual({ fn: 'admin_course_edit', p_course_id: 'c-1', p_action: 'restore', p_args: {} })
  })

  test('Curator sees the screen without Restore', async ({ page }) => {
    await setup(page, 3)
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_archive_read', r => r.fulfill({ json: { ...read.providers, can_restore: false } }))
    await page.goto('/#providers?tab=archived')
    await expect(page.locator('[data-archived-provider="p-u"]')).toBeVisible()
    await expect(page.locator('[data-archived-provider="p-u"]').getByRole('button', { name: 'Restore' })).toHaveCount(0)
  })
})

test('UI: archive checklist in the provider panel; lists default to active records', () => {
  const ed = fs.readFileSync('src/RecordEditor.jsx', 'utf8')
  expect(ed).toContain("supabase.rpc('admin_provider_archive',{p_provider_id:providerId,p_preview:true})")
  expect(ed).toContain('<ArchiveChecklist providerId={providerId}')
  expect(ed).not.toContain("'Archive this provider? Its courses stay as they are. You can restore it later.'")
  const m = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(m).toContain("if(!filters.lifecycle&&['provider','course'].includes(type))a.lifecycle_status='active';")
  expect(fs.readFileSync('src/nav-map.js', 'utf8')).toContain("{ key: 'archived', label: 'Archived', min: 3 }")
})
