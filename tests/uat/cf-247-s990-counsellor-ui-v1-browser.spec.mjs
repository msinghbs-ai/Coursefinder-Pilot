// Guards: Platform Admin 23 Nov 2026 (v1.1 Counsellor UI: MOCKUP-SPEC-AND-RETIREMENT-MAP v1.1 section 4 rules 1 to 6 and 8, IR-021 no operator read for rank 2).
// A rank 2 session is given only the new build: four nav items, no operator text or read, ui-* classes only, Save and a capped Compare, no sideways scroll at 375 px.
import { test, expect } from '@playwright/test';
import { mockAdmin } from './support/admin-mock.mjs';

const OPERATOR_READS = ['admin_course_edit_read', 'admin_provider_edit_read', 'admin_jobs', 'admin_aer', 'admin_boost_queue_read'];
const OPERATOR_TEXT = ['Layer 4 Review', 'Dry-Lane', 'AER & Coverage', 'Settings', 'Coverage & completeness', 'Zoho', 'Firecrawl', 'Manual lock', 'More Filters', 'admin_', 'pipeline.settings'];

async function counsellor(page) {
  await mockAdmin(page, { rank: 2, role: 'counsellor' });
  // s997 (live): saved courses and partner contacts are server reads; this mock keeps the user's saved set the way the server does
  page.saved = new Map(); page.savedRefuse = false; page.rpcs = [];
  const json = (r, data, status = 200) => r.fulfill({ status, contentType: 'application/json', body: JSON.stringify(data) });
  await page.route('https://example.supabase.co/rest/v1/rpc/saved_courses_read_v1', r => { page.rpcs.push('saved_courses_read_v1'); return json(r, { count: page.saved.size, max: 500, items: [...page.saved.keys()].map(id => ({ course_id: id, saved_at: page.saved.get(id), title: 'Saved ' + id, provider_name: 'Test University' })) }); });
  await page.route('https://example.supabase.co/rest/v1/rpc/saved_course_toggle_v1', r => {
    const b = r.request().postDataJSON() || {}; page.rpcs.push('saved_course_toggle_v1');
    if (page.savedRefuse) return json(r, { message: 'INVALID_INPUT: you can keep at most 500 saved courses; remove one first' }, 400);
    if (b.p_saved) page.saved.set(b.p_course_id, new Date().toISOString()); else page.saved.delete(b.p_course_id);
    return json(r, { course_id: b.p_course_id, is_saved: !!b.p_saved, saved_at: page.saved.get(b.p_course_id) || null, saved_count: page.saved.size, max: 500 });
  });
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_representation_read_v1', r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify([{ provider_id: 'p1', representation_status: 'represented', restriction_mode: 'include', restriction_markets: ['IN', 'NP'], effective_from: '2026-01-01', effective_to: null, source: 'agreement' }]) }));
  await page.route('https://example.supabase.co/rest/v1/rpc/provider_partner_contacts_v1', r => json(r, { provider_id: 'p1', status: 'active', active_count: 1, inactive_count: 0, rows: [{ contact_id: 'c1', record_type: 'person', full_name: 'Alex Partner', job_title: 'Partnerships Manager', work_email: 'alex@example.edu.au', verified_on: '2026-10-01', lifecycle_status: 'active' }] }));
  await page.route('https://example.supabase.co/rest/v1/rpc/counsellor_scholarships_list', r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ total: 2, page_rows: 50, offset: 0, today: '2026-11-23', status_counts: { Open: 1, Closed: 1 }, rows: [
    { id: 's1', name: 'International Excellence Scholarship', provider_name: 'Test University', type: 'provider_scholarship', value_text: '20% off tuition', open_date: '2026-09-01', close_date: '2026-12-31', status_key: 'Open', status: 'Open', nationalities: [] },
    { id: 's2', name: 'Placement Bursary', provider_name: 'Test University', type: 'provider_scholarship', value_text: '$2,000', open_date: '2026-06-01', close_date: '2026-11-22', status_key: 'Closed', status: 'Closed', nationalities: [] }] }) }));
}
async function providers(page) {
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_read', async r => {
    let b = {}; try { b = r.request().postDataJSON() || {} } catch {}
    const j = data => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) });
    if (b.p_operation === 'providers_page') return j({ total: 1, limit: 50, offset: 0, items: [{ id: 'p1', display_name: 'Test University', canonical_name: 'Test University', country_code: 'AU', country_name: 'Australia', city: 'MELBOURNE', course_count: 12 }] });
    if (b.p_operation === 'provider_detail') return j({ id: 'p1', course_count: 12, scholarship_count: 2, website: 'https://example.edu.au', campuses_page: { items: [{ subdivision_code: 'AU-VIC', city: 'Bundoora' }, { subdivision_code: 'AU-VIC', city: 'City' }] }, international_contacts: [] });
    return r.fallback();
  });
}
const overflow = page => page.evaluate(() => Math.max(0, document.documentElement.scrollWidth - document.documentElement.clientWidth, ...[...document.querySelectorAll('.ui-drawer-body,.ui-modal,.ui-compare')].map(e => e.scrollWidth - e.clientWidth)));

test('counsellor session: the new build only, four nav items, no operator text, no operator read, ui-* classes only', async ({ page }) => {
  await counsellor(page);
  await page.goto('/#courses');
  await expect(page.locator('.ui-shell')).toBeVisible();
  await expect(page).toHaveURL(/#courses$|#ui-v1/);
  await expect(page.locator('.ui-nav a')).toHaveText(['Courses', 'Universities & Providers', 'Scholarships', 'Guide']);
  await expect(page.locator('.ui-grid tbody tr').first()).toBeVisible();
  const body = (await page.locator('body').innerText()).toLowerCase();
  for (const t of OPERATOR_TEXT) expect(body).not.toContain(t.toLowerCase());
  expect(await page.locator('body').innerText()).not.toMatch(/\b\d+\s+regions?\b/i);
  const bad = await page.evaluate(() => [...new Set([...document.querySelectorAll('[class]')].flatMap(e => [...e.classList]))].filter(c => !c.startsWith('ui-')));
  expect(bad).toEqual([]);
  expect((page.readCalls || []).map(c => c.p_operation).filter(o => OPERATOR_READS.includes(o))).toEqual([]);
  expect(await overflow(page)).toBe(0);
});

test('save a course, then compare: capped at four and the header matches the selection', async ({ page }) => {
  await counsellor(page);
  await page.goto('/#ui-v1/courses');
  const saves = page.locator('.ui-save');
  await expect(saves.first()).toBeVisible();
  const n = Math.min(await saves.count(), 5);
  for (let i = 0; i < n; i++) await saves.nth(i).click();
  await page.getByRole('button', { name: /Saved \(/ }).click();
  await expect(page.locator('.ui-grid-caption')).toContainText(`${n} saved courses`);
  const adds = page.getByRole('button', { name: /Add to compare/ });
  for (let i = 0; i < n; i++) { if (await adds.count()) await adds.first().click(); }
  const picked = Math.min(n, 4);
  await expect(page.getByRole('button', { name: /Compare selected/ })).toContainText(`(${picked})`);
  if (n > 4) await expect(page.getByRole('button', { name: /Add to compare/ }).first()).toBeDisabled();
  await page.getByRole('button', { name: /Compare selected/ }).click();
  await expect(page.locator('.ui-modal-wide')).toContainText(`Comparing ${picked} of ${picked} selected`);
  await expect(page.locator('.ui-compare-head')).toHaveCount(picked);
  await expect(page.locator('.ui-compare-label')).toHaveText(['Annual tuition fee', 'Duration', 'State & campus', 'Intakes & exact start dates', 'Academic entry requirements', 'English (IELTS · PTE · TOEFL)', 'Available scholarships']);
  expect(await overflow(page)).toBe(0);
});

test('scholarships show the database status; provider Contacts shows the partner-contact empty state and Not recorded', async ({ page }) => {
  await counsellor(page);
  await page.goto('/#ui-v1/scholarships');
  await expect(page.locator('.ui-grid tbody tr')).toHaveCount(2);
  await expect(page.locator('.ui-grid tbody tr').nth(0).locator('.ui-badge')).toHaveText('Open');
  await expect(page.locator('.ui-grid tbody tr').nth(1).locator('.ui-badge')).toHaveText('Closed');
  await page.route('https://example.supabase.co/rest/v1/rpc/provider_partner_contacts_v1', r => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ provider_id: 'p1', status: 'active', active_count: 0, inactive_count: 0, rows: [] }) }));
  await providers(page);
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_provider_representation_read_v1', r => r.fulfill({ status: 200, contentType: 'application/json', body: '[]' })); // no row held: Not recorded
  await page.goto('/#ui-v1/providers');
  await expect(page.locator('.ui-grid tbody tr').first().locator('[data-rep="not_recorded"]')).toBeVisible();
  await page.locator('.ui-grid tbody tr').first().locator('.ui-btn').click();
  await page.getByRole('tab', { name: 'Contacts' }).click();
  await expect(page.locator('.ui-drawer')).toContainText('No partner contacts recorded for this provider');
  await page.getByRole('tab', { name: 'Overview' }).click();
  await expect(page.locator('.ui-drawer')).toContainText('VIC · Bundoora, City');
  expect(await overflow(page)).toBe(0);
});

test('phone width: courses, compare and provider drawer do not scroll sideways @responsive', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  expect(page.viewportSize().width).toBe(375);
  await counsellor(page);
  await page.goto('/#ui-v1/courses');
  await expect(page.locator('.ui-grid tbody tr').first()).toBeVisible();
  expect(await overflow(page)).toBe(0);
  await page.locator('.ui-save').first().click();
  await page.getByRole('button', { name: /Saved \(/ }).click();
  await page.getByRole('button', { name: /Add to compare/ }).first().click();
  await page.getByRole('button', { name: /Compare selected/ }).click();
  await expect(page.locator('.ui-modal-wide')).toBeVisible();
  expect(await overflow(page)).toBe(0);
  await providers(page);
  await page.getByRole('button', { name: 'Close' }).first().click();
  await page.goto('/#ui-v1/providers');
  await page.locator('.ui-grid tbody tr').first().locator('.ui-btn').click();
  expect(await overflow(page)).toBe(0);
});

test('opening a course shows its detail drawer with fees, requirements and a Save button, and no operator read', async ({ page }) => {
  await counsellor(page);
  await page.goto('/#ui-v1/courses');
  await page.locator('.ui-grid tbody tr').first().locator('.ui-cell-title .ui-btn').click();
  const drawer = page.locator('.ui-drawer');
  await expect(drawer).toBeVisible();
  for (const tab of ['Overview', 'Fees & intakes', 'Entry & English', 'Links']) await drawer.getByRole('tab', { name: tab }).click();
  await drawer.getByRole('button', { name: /Save course/ }).click();
  await expect(drawer.getByRole('button', { name: /Saved/ })).toBeVisible();
  expect((page.readCalls || []).map(c => c.p_operation).filter(o => OPERATOR_READS.includes(o))).toEqual([]);
  expect(await overflow(page)).toBe(0);
});

test('saves go to the server (saved_course_toggle_v1) and the list is read from it; a refused save is put back with the server\'s words; no browser storage', async ({ page }) => {
  await counsellor(page);
  await page.goto('/#ui-v1/courses');
  await expect(page.locator('.ui-grid tbody tr').first()).toBeVisible();
  await page.locator('.ui-save').first().click();
  await expect.poll(() => page.rpcs.filter(x => x === 'saved_course_toggle_v1').length).toBe(1);
  expect(page.saved.size).toBe(1);
  await expect(page.locator('.ui-save[aria-pressed="true"]')).toHaveCount(1);
  expect(await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('ss.saved_courses')))).toEqual([]);
  page.savedRefuse = true;
  await page.locator('.ui-save[aria-pressed="false"]').first().click();
  await expect(page.locator('[data-save-error]')).toContainText('at most 500 saved courses');
  await expect(page.locator('.ui-save[aria-pressed="true"]')).toHaveCount(1);
});

test('the provider Contacts tab reads provider_partner_contacts_v1 and lists the people', async ({ page }) => {
  await counsellor(page); await providers(page);
  await page.goto('/#ui-v1/providers');
  await page.locator('.ui-grid tbody tr').first().locator('button, a').first().click();
  await page.getByRole('tab', { name: 'Contacts' }).click();
  await expect(page.locator('[data-partner-contacts]')).toContainText('Alex Partner');
  await expect(page.locator('[data-partner-contacts]')).toContainText('alex@example.edu.au');
});

test('REQ-118: the provider list and drawer show Study Square status and the market restriction from the server', async ({ page }) => {
  await counsellor(page); await providers(page);
  await page.goto('/#ui-v1/providers');
  const row = page.locator('.ui-grid tbody tr').first();
  await expect(row.locator('[data-rep="represented"]')).toBeVisible();
  await expect(row.locator('[data-market="include"]')).toContainText('Only IN, NP');
  await row.locator('button').first().click();
  await expect(page.locator('[data-restriction]')).toContainText('Only these markets');
});
