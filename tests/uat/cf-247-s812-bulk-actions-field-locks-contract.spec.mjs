// Guards: Platform Admin 20 Nov 2026 08:06 (chat S1-RM-Design, s812): Bulk Queue to Intake Run & Validate (a hand-off, nothing run), Bulk Flag Primary Campus (preview then apply, Platform Admin, one audit event, no new public object, G3 unchanged) and the Human Locked pills in the Provider and Course drawers.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { lockFor, otherLocked, lockWord, saveIntakeQueue, readIntakeQueue, clearIntakeQueue, PROVIDER_LOCK_COLUMNS, COURSE_LOCK_COLUMNS, COURSE_TRACKED_FIELDS, COURSE_FIELD_WORDS, PRIMARY_OUTCOME } from '../../src/field-provenance.js'

const read = f => fs.readFileSync(f, 'utf8')
const MIG = read('supabase/migrations/20261120104000_cf247_s812_bulk_primary_campus_field_provenance.sql')
const BAR = read('src/CompletenessBar.jsx'), MAIN = read('src/mature-main.jsx'), INTAKE = read('src/IntakeRunValidate.jsx'), PRIM = read('src/BulkPrimaryCampus.jsx'), FP = read('src/FieldProvenance.jsx')

test('lock helpers: the first locked column of a field, locks no tracked field covers, and the pill words', () => {
  const locks = { website: { mode: 'value', set_at: '2026-11-01T00:00:00Z' }, postcode: { mode: 'removed' }, canonical_name: { mode: 'value' }, course_finder: { mode: 'value' } }
  expect(lockFor(locks, PROVIDER_LOCK_COLUMNS.website)?.column).toBe('website')
  expect(lockFor(locks, PROVIDER_LOCK_COLUMNS.address)?.column).toBe('postcode')
  expect(lockFor(locks, PROVIDER_LOCK_COLUMNS.phone)).toBeNull()
  expect(lockFor(null, ['x'])).toBeNull()
  expect(otherLocked(locks, PROVIDER_LOCK_COLUMNS)).toEqual(['Course Finder switch', 'Name'])
  expect(lockWord({ mode: 'value' })).toBe('Human Locked')
  expect(lockWord({ mode: 'removed' })).toBe('Human Locked · empty')
  // every tracked course field has a word and at least one lock column; the live lock fields (course_url, official_url, english, intakes, tuition, lifecycle_status) are covered
  for (const f of COURSE_TRACKED_FIELDS) { expect(COURSE_FIELD_WORDS[f]).toBeTruthy(); expect(COURSE_LOCK_COLUMNS[f].length).toBeGreaterThan(0) }
  for (const c of ['course_url', 'official_url', 'english', 'intakes', 'tuition', 'lifecycle_status']) expect(Object.values(COURSE_LOCK_COLUMNS).flat()).toContain(c)
  expect(Object.keys(PRIMARY_OUTCOME)).toEqual(['will_mark', 'has_primary', 'locked', 'tie', 'no_campus', 'not_active', 'outside_rule'])
})

test('the intake hand-off keeps only ids and names for this tab, and clears', () => {
  const store = new Map()
  globalThis.sessionStorage = { getItem: k => store.has(k) ? store.get(k) : null, setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) }
  expect(saveIntakeQueue([{ id: 'a', name: 'Alpha', extra: 'x' }, { id: '', name: 'none' }, null, { id: 7 }])).toEqual([{ id: 'a', name: 'Alpha' }, { id: '7', name: '' }])
  expect(readIntakeQueue()).toEqual([{ id: 'a', name: 'Alpha' }, { id: '7', name: '' }])
  clearIntakeQueue(); expect(readIntakeQueue()).toEqual([])
  delete globalThis.sessionStorage; expect(readIntakeQueue()).toEqual([])
})

test('the Providers bulk bar offers Queue to Intake Run & Validate and, for the Platform Admin only, Flag primary campus', () => {
  expect(BAR).toMatch(/data-bulk-queue/); expect(BAR).toMatch(/data-bulk-primary-open/)
  expect(BAR).toMatch(/\{onQueue&&/); expect(BAR).toMatch(/\{onPrimary&&/)
  expect(MAIN).toMatch(/onPrimary=\{Number\(rank\)>=6\?/)                 // the button exists only for rank 6 and above (the server checks again)
  expect(MAIN).toMatch(/saveIntakeQueue\(picked\.map/); expect(MAIN).toMatch(/navigate\?\.\('layer2',\{tab:'operations'\}\)/)
  // the hand-off runs nothing: the queue block on the intake page only picks a provider
  const q = INTAKE.slice(INTAKE.indexOf('data-intake-queue'), INTAKE.indexOf('<div className="intake-form">'))
  expect(q).toMatch(/pickProvider/); expect(q).not.toMatch(/client\.(run|prepare)|start\(|prepare\(/)
})

test('Flag primary campus previews first, applies only with a reason, and reports every skip', () => {
  expect(PRIM).toMatch(/campus_primary_preview/); expect(PRIM).toMatch(/campus_primary_apply/)
  expect(PRIM).toMatch(/reason\.trim\(\)\.length < 4/); expect(PRIM).toMatch(/will === 0/)
  expect(PRIM).toMatch(/PRIMARY_OUTCOME/)
})

test('migration 20261120104000: no new public object, one md5-guarded edit of the Inbox, preview writes nothing, apply is Platform Admin with a reason and one audit event, G3 read before and after', () => {
  expect(MIG).not.toMatch(/create\s+(or replace\s+)?function\s+public\./i)
  expect(MIG).not.toMatch(/create\s+(table|view|materialized view)\b/i)
  expect(MIG).not.toMatch(/\b(drop|truncate)\s+(table|function|view|schema|column)/i)
  expect(MIG).not.toMatch(/delete\s+from/i)
  expect(MIG).toMatch(/cf_edit_def\('public\.admin_layer4_inbox\(text,jsonb\)'::regprocedure, '52024a627bc04976b2e5b489a7d969af'/)
  expect(MIG).toMatch(/revoke all on function security\.s812_bulk_admin_v1\(text, jsonb\) from public, anon, authenticated/)
  expect(MIG).toMatch(/v_rank < 6 then raise exception 'Platform Admin role required'/)
  expect(MIG).toMatch(/v_rank < 3 then raise exception 'Curator role or above required'/)
  expect(MIG).toMatch(/p_action = 'campus_primary_apply' and char_length\(v_reason\) < 4/)
  expect((MIG.match(/insert into pipeline\.admin_control_events/g) || []).length).toBe(1)   // one audit insert, inside the apply branch
  expect(MIG.slice(MIG.indexOf("if p_action = 'campus_primary_apply' then\n    insert into pipeline.admin_control_events"))).toMatch(/campus_primary_bulk_flag/)
  expect(MIG).toMatch(/is_primary = true, primary_basis = 'highest_course_count'/)
  expect(MIG).toMatch(/l\.field in \('is_primary', 'primary_basis'\)/)            // a hand lock on the primary campus is respected
  expect(MIG).toMatch(/not exists \(select 1 from catalogue\.campuses x where x\.provider_id = r\.provider_id and x\.is_primary\)/)
  expect((MIG.match(/consumer_api_check_v1/g) || []).length).toBeGreaterThanOrEqual(2)
  expect(MIG).toMatch(/\(v->>'functions'\)::int <> 75 or \(v->>'relations'\)::int <> 48/)
  expect(MIG).toMatch(/^-- Replaces:/m); expect(MIG).toMatch(/^-- Retires:/m)
  // G2: the one limit is a setting with a label, a range, a unit and a used_by line
  expect(MIG).toMatch(/'bulk\.primary_campus_max'[\s\S]*to_jsonb\(100\), 1, 500, 'providers'/)
  expect(MIG).toMatch(/pipeline_num_v1\('bulk\.primary_campus_max', 100\)/)
})

test('the drawers show Human Locked from the lock table, and the guides say what is and is not recorded', () => {
  expect(BAR).toMatch(/useFieldLocks\('provider'/); expect(BAR).toMatch(/<LockPill lock=\{lk\}\/>/)
  expect(MAIN).toMatch(/<FieldProvenancePanel entity="course"/); expect(FP).toMatch(/Locks by hand/)
  expect(FP).toMatch(/source of each course field is not recorded per field yet/)
  expect(read('src/guide/platformGuide.js')).toMatch(/Queue to Intake Run & Validate[\s\S]*Flag primary campus[\s\S]*Human Locked/)
  expect(read('src/guide/roleGuides.js')).toMatch(/Flag primary campus \(Platform Admin\)/)
})

const dayRow = (id, name, missing, extra = {}) => ({ id, canonical_name: name, display_name: name, country_code: 'AU', course_count: 10, lifecycle_status: 'active', publication_status: 'published', last_verified_at: '2026-10-01T00:00:00Z', stable_key: `provider:cricos:${id}`, pdesc: missing === null ? undefined : { missing_fields: missing, description_filled: !missing.includes('description'), source_tier: missing.includes('description') ? null : 'registry_factual', admission_state: 'admitted' }, ...extra })
const ROWS = [dayRow('11111111-1111-4111-8111-111111111111', 'University of Alpha', []), dayRow('22222222-2222-4222-8222-222222222222', 'Beta Institute', ['website'])]

async function mount(page, rank, inbox) {
  await mockAdmin(page, { rank })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async route => {
    const b = route.request().postDataJSON() || {}
    if (b.p_operation !== 'providers_page') return route.fallback()
    return route.fulfill({ json: { items: ROWS, total: ROWS.length, limit: 50, offset: 0, columns_profile: 'provider_columns_v1' } })
  })
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_adapter_autobuild', r => r.fulfill({ json: {} }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_type_rules', r => r.fulfill({ json: { rules: [], types: [], counts: {}, can_edit: true } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_description_run_v1', async route => route.fulfill({ json: (route.request().postDataJSON() || {}).p_action === 'fill_caps' ? { max_size: 5 } : {} }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async route => { const b = route.request().postDataJSON() || {}; inbox.push(b); return route.fulfill({ json: await (inbox.handler ? inbox.handler(b) : {}) }) })
  await page.goto('/#providers')
  await expect(page.locator('table[data-table="provider"] tbody tr[data-row]').first()).toBeVisible()
}

test('Providers: the bar has Queue to Intake Run & Validate for a curator and Flag primary campus only from the Platform Admin role', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  const calls = []
  await mount(page, 3, calls)
  await page.locator('table[data-table="provider"] tbody tr[data-row] .pff-pick input').first().check()
  await expect(page.locator('[data-bulk-queue]')).toBeVisible()
  await expect(page.locator('[data-bulk-primary-open]')).toHaveCount(0)
})

test('Providers: Flag primary campus previews with nothing written, then applies only with a reason, as the Platform Admin', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  const calls = []
  calls.handler = b => {
    if (b.p_action === 'campus_primary_preview') return { action: 'campus_primary_preview', applied: false, ticked: 2, will_mark: 1, marked: 0, by_outcome: { will_mark: 1, has_primary: 1 }, limit: 100,
      rows: [{ provider_id: b.p_args.provider_ids[0], name: 'University of Alpha', outcome: 'will_mark', campus: 'Main campus', courses: 42 }, { provider_id: b.p_args.provider_ids[1], name: 'Beta Institute', outcome: 'has_primary' }] }
    if (b.p_action === 'campus_primary_apply') return { action: 'campus_primary_apply', applied: true, ticked: 2, will_mark: 1, marked: 1, by_outcome: { will_mark: 1, has_primary: 1 }, rows: [] }
    return {}
  }
  await mount(page, 6, calls)
  const picks = page.locator('table[data-table="provider"] tbody tr[data-row] .pff-pick input')
  await picks.nth(0).check(); await picks.nth(1).check()
  await page.locator('[data-bulk-primary-open]').click()
  const box = page.locator('[data-bulk-primary]')
  await expect(box).toContainText('Flag primary campus for 2 ticked providers')
  await box.locator('[data-bulk-primary-preview]').click()
  await expect(box.locator('[data-bulk-primary-summary]')).toContainText('1 of 2 would be marked')
  await expect(box.locator('tr[data-outcome="has_primary"]')).toContainText('Already has a primary campus')
  expect(calls.filter(c => c.p_action === 'campus_primary_apply')).toHaveLength(0)
  const apply = box.locator('[data-bulk-primary-apply]')
  await expect(apply).toBeDisabled()
  await box.getByLabel('Reason').fill('Approved by the Platform Admin')
  await expect(apply).toBeEnabled()
  await apply.click()
  await expect(box.locator('[data-bulk-primary-done]')).toContainText('1 provider marked')
  expect(calls.filter(c => c.p_action === 'campus_primary_apply')).toHaveLength(1)
  expect(calls.find(c => c.p_action === 'campus_primary_apply').p_args.reason).toBe('Approved by the Platform Admin')
})
