// Guards: CF-247 AER programme Platform Admin decision 29 Oct 2026 09:57 items 3 and 4 (admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W17-W18): course-level reading is a settings-controlled, measured programme on the existing Enrich fields lane with the provider selection visible in the workspace, a count and cost preview, bounded batches of never-read eligible courses (refused while a read waits, when AI is stopped or below the OpenRouter credit floor), Platform Admin only, one Layer 4 item a course; a rendered page with no requirements table opens a Layer 4 note in the existing vocabulary whose approval admits and replaces nothing, shown apart from a confirmed no-matrix outcome; no new job, status, Layer 4 field or consumer API change
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029030000_cf247_aer_course_programme_rendered_note.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const ui = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')

test('settings: providers in priority order, batch size and the cost estimate, each with label, range or unit and used_by', () => {
  expect(code).toContain("('pipeline', 'entry.course_read_providers', 'Course entry requirements: providers read',")
  expect(code).toContain("'[\"543b87b8-f0dd-4bc7-80d6-76252cfaabec\", \"2c4f515c-c146-4e90-ba8a-294130aa1f40\", \"8e1adb6c-e069-43db-9584-bd054255e702\",")  // Monash, QUT, RMIT first
  expect(code).toContain("to_jsonb(50), 1, 200, 'courses', 916, 'Entry requirements', 'security.course_entry_batch_v1',")
  expect(code).toContain("to_jsonb(0.005), 0.001, 0.1, 'USD a course', 917, 'Entry requirements',")
})

test('eligibility is the B1 rule: an active course of a plan provider, a bound stored page, the countries read and a strong identity', () => {
  expect(code).toContain("join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'")
  expect(code).toContain("join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null")
  expect(code).toContain("where c.lifecycle_status = 'active'")
  expect(code).toContain("coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '[\"AU\"]'::jsonb) ? k.iso_alpha2")
  expect(code).toContain("and security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')")
})

test('a batch is bounded, never re-reads a course, waits for the last one, respects AI limits and the credit floor, and is the Platform Admin\'s', () => {
  expect(code).toContain("v_n := greatest(1, least(coalesce(p_size, v_max), v_max));")
  expect(code).toContain("and not exists (select 1 from pipeline.field_enrich_items f where f.course_id = el.course_id and f.field = 'entry_requirements')")
  expect(code).toContain("if v_wait > 0 then raise exception 'an earlier course read is still waiting")
  expect(code).toContain("if not security.ai_use_allowed_v1('enrich_fields') then raise exception 'AI reading is stopped (AI limits); nothing was asked'")
  expect(code).toContain("if v_bal is not null and v_bal - v_est < v_floor then")
  expect(code).toContain("v_floor := coalesce((security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric, 0);")
  expect(code).toContain("if length(v_reason) < 5 then raise exception 'give a reason (kept in the history)'")
  // the existing Enrich fields lane: one task, one entry_requirements item a course; nothing scheduled
  expect(code).toContain("values ('enrich_fields', 'enrich', 'queued', left('Entry requirements · ' || array_length(v_ids, 1) || ' courses', 200),")
  expect(code).toContain("select v_job, c.provider_id, c.id, 'entry_requirements', 'queued' from catalogue.courses c where c.id = any (v_ids)")
  expect(code).not.toMatch(/cron\.schedule|insert into pipeline\.(automation_catalogue|admin_job_kinds)/)
  // through the one admin RPC: the programme and preview for every role, the batch for the Platform Admin
  expect(code).toContain("select pg_temp.edit_n('public.admin_aer(text,jsonb)', 'bc7fe7800090daa1135c4087a93c2008'")
  expect(code).toContain("return security.course_entry_programme_v1(v_rank >= 6);")
  expect(code).toContain("return security.course_entry_batch_v1((a->>'provider_id')::uuid, (a->>'size')::int, null, auth.uid(), true);")
  expect(code).toContain("if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;\n    return security.course_entry_batch_v1((a->>'provider_id')::uuid, (a->>'size')::int, v_reason, auth.uid(), false);")
  for (const f of ['course_entry_eligible_v1()', 'course_entry_cost_v1()', 'course_entry_programme_v1(boolean)', 'course_entry_batch_v1(uuid, int, text, uuid, boolean)', 'entry_rendered_note_v1(uuid)'])
    expect(code).toContain(`revoke all on function security.${f} from public, anon, authenticated;`)
})

test('Step C: a rendered page with no requirements table opens a Layer 4 note in the existing vocabulary; approval admits and replaces nothing', () => {
  expect(code).toContain("select pg_temp.edit_n('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', '15fb11f83f24859131866e564875157a'")
  expect(code).toContain("if v_in = 0 and f.read_via = 'firecrawl'")
  expect(code).toContain("v_item := security.entry_rendered_note_v1(r.id);")
  expect(code).toContain("case when v_first then 'entry_matrix_first_run' else 'entry_matrix_change' end")
  expect(code).toContain("'outcome', 'no_requirements_table', 'rendered', true,")
  expect(code).toContain("select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', 'f1152d19721585c7767a9c65ae1d76b5'")
  expect(code).toContain("if r.rows_admitted = 0 and r.result->>'outcome' = 'no_requirements_table' then\n    return jsonb_build_object('entry_matrix_run', r.id, 'admitted', 0, 'quarantined', 0, 'superseded', 0,")
  expect(code).toContain("if v_n > 5 then raise exception 'expected at most 5 rendered no-table reads, found %', v_n; end if;")
  expect(code).toContain("'worker', r3.result->>'worker', 'outcome', r3.result->>'outcome', 'review_item_id', r3.review_item_id,")
  // the screen tells a waiting note from a confirmed outcome, in words
  expect(ui).toContain("label={ok?'No matrix published (confirmed)':'Rendered, no table: in Layer 4'}")
  // nothing dropped or deleted; no status or consumer API change
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/create or replace function (public\.website_|public\.zoho_|api\.|security\.entry_resolve_v1|security\.entry_(course|matrix)_payload_v1)/)
  expect(m).toMatch(/^-- Replaces: public\.admin_aer, public\.svc_entry_matrix_record, security\.entry_matrix_review_apply_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})

async function mockProgramme(page, { rank = 6 } = {}) {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { rank })
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer', async (route) => {
    const b = route.request().postDataJSON() || {}, a = b.p_args || {}
    calls.push({ action: b.p_action, args: a })
    const j = (json) => route.fulfill({ json })
    if (b.p_action === 'summary') return j({ matrix: { active: 343, proposed: 776 }, course: { proposed: 3 }, sources: { total: 102 }, courses_with_active: 0, courses_waiting: 1, can_edit: true, can_reread: rank >= 6 })
    if (b.p_action === 'options') return j({ providers: [], statuses: ['active', 'proposed'] })
    if (b.p_action === 'course_list') return j({ total: 0, rows: [] })
    if (b.p_action === 'course_programme') return j({ providers: [
      { provider_id: 'p-monash', provider_name: 'Monash University', country: 'AU', eligible: 356, read: 0, waiting: 0, in_layer4: 0, proposed_rows: 0, admitted: 0, active_rows: 0, no_rows: 0, remaining: 356, estimate_remaining_usd: 1.78 },
      { provider_id: 'p-rmit', provider_name: 'RMIT University (RMIT)', country: 'AU', eligible: 334, read: 1, waiting: 0, in_layer4: 1, proposed_rows: 3, admitted: 0, active_rows: 0, no_rows: 0, remaining: 333, estimate_remaining_usd: 1.67 }],
      cost_per_course_usd: 0.005, cost_basis: 'setting', batch_size: 50, balance_usd: 8.04, floor_usd: 5, countries: ['AU'], ai_allowed: true, waiting: 0, can_batch: rank >= 6 })
    if (b.p_action === 'course_batch_preview') return j({ preview: true, courses: 50, providers: { 'Monash University': 50 }, estimate_usd: 0.25, balance_usd: 8.04, floor_usd: 5, batch_size: 50, waiting: 0, refusal: null })
    if (b.p_action === 'course_batch') return j({ ok: true, job_id: 'j1', courses: 50, estimate_usd: 0.25 })
    if (b.p_action === 'sources_list') return j({ total: 2, can_reread: rank >= 6, ai_allowed: true, rows: [
      { id: 's1', provider_id: 'p-new', provider_name: 'The University of Newcastle', url: 'https://www.newcastle.edu.au/entry', type: 'Rendered page', status: 'read', read_via: 'firecrawl', in_scope: true, hold_state: 'read', run: { id: 'r1', state: 'done', attempts: 1, rows: 0, not_kept: 0, outcome: 'no_requirements_table', review_item_id: 'li1', review_status: 'pending' } },
      { id: 's2', provider_id: 'p-gri', provider_name: 'Griffith University', url: 'https://www.griffith.edu.au/entry', type: 'Rendered page', status: 'read', read_via: 'firecrawl', in_scope: true, hold_state: 'read', run: { id: 'r2', state: 'done', attempts: 1, rows: 0, not_kept: 0, outcome: 'no_requirements_table', review_item_id: 'li2', review_status: 'approved' } }] })
    return j({})
  })
  return calls
}

test.describe('mocked browser', () => {
  test('Course-level reading: providers and counts for every role; the Platform Admin previews, then asks for a bounded batch with a reason', async ({ page }) => {
    const errors = []; page.on('console', (x) => { if (x.type() === 'error' && !/Failed to load resource|favicon/.test(x.text())) errors.push(x.text()) })
    const calls = await mockProgramme(page)
    await page.goto('/#entry-requirements?tab=course')
    const p = page.locator('[data-aer-programme]')
    await expect(p.locator('table[data-table="aer-course-programme"]')).toContainText('Monash University')
    await expect(p.locator('[data-aer-programme-cost]')).toContainText('OpenRouter balance US$8.04 (floor US$5.00)')
    await expect(p).toContainText('689')  // remaining across providers
    await expect(p.locator('[data-po-action="aer-batch"]')).toHaveCount(0)  // nothing to ask before a preview
    await p.locator('[data-aer-batch-preview]').click()
    await expect(p.locator('[data-aer-batch-result]')).toContainText('50 courses')
    await p.locator('[data-po-action="aer-batch"]').click()
    await page.getByLabel('Reason: Read next batch').fill('course-level programme: Monash first batch')
    await page.locator('[data-po-confirm="aer-batch"]').click()
    await expect.poll(() => calls.filter((c) => c.action === 'course_batch').at(-1)?.args).toMatchObject({ reason: 'course-level programme: Monash first batch' })
    await expect(p).toContainText('Asked: 50 courses')
    expect(errors).toEqual([])
  })

  test('a Curator sees the programme but cannot ask for a batch; a rendered no-table read is told apart from a confirmed no-matrix outcome', async ({ page }) => {
    await mockProgramme(page, { rank: 3 })
    await page.goto('/#entry-requirements?tab=course')
    await expect(page.locator('[data-aer-programme] table')).toContainText('RMIT University (RMIT)')
    await expect(page.locator('[data-aer-batch]')).toHaveCount(0)
    await page.goto('/#entry-requirements?tab=sources')
    await expect(page.locator('[data-aer-hold="no_table_note"]')).toContainText('Rendered, no table: in Layer 4')
    await expect(page.locator('[data-aer-hold="no_matrix_confirmed"]')).toContainText('No matrix published (confirmed)')
  })
})
