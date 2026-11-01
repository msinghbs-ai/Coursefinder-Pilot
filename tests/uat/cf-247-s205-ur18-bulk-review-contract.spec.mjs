// Guards: D-B1, D-B2, D-B3 (Platform Admin 2 Nov 2026 05:18)
// CF-247 SS-016 UR-18, slice 1: provider bulk review for country, state, campus and course delivery. D-B1 eligible-field policy (AER never in
// bulk), D-B2 role boundary (Platform Admin applies, reviewers preview; locks and course-specific exclusions protected), D-B3 build and isolated
// fixture testing with production bulk writes off (layer4.bulk_review_enabled = 0; D-B4 activation not approved).
// The database behaviour is proven on an isolated local Postgres (tests/uat/fixtures/cf-247-s205: schema.sql, cases.sql, run-fixture.sh); its
// result.txt is tied to this migration by md5, so a change to the migration fails here until the fixture is run again. The two edits are
// checked against the live definitions captured on 1-2 Nov 2026 (before md5s), as in s212.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'
import { mockAdmin } from './support/admin-mock.mjs'

const FILE = 'supabase/migrations/20261102020000_cf247_ur18_bulk_review_slice1.sql'
const FX = 'tests/uat/fixtures/cf-247-s205'
const m = fs.readFileSync(FILE, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s, 'utf8').digest('hex')
const code = (s) => s.replace(/--[^\n]*/g, '')
const outside = (s) => s.replace(/\$function\$[\s\S]*?\$function\$/g, '')
const fn = (name) => { const i = m.indexOf(`create or replace function ${name}(`); return m.slice(i, m.indexOf('$function$;', i)) }
const EDITS = {
  'security.layer4_review_decide_impl(uuid,text,text,jsonb)': { file: 'layer4_review_decide_impl', before: '67966cebe3184b9acad1a3451fd0021b', after: '26efc646bd65c181da99b4c6b5945205' },
  'public.admin_layer4_inbox(text,jsonb)': { file: 'admin_layer4_inbox', before: '417f181d12155f79f68c1e70c27a1892', after: 'ce6e8c4c5bf89a319eb7bc5e9c05f07d' },
}

test('migration: header, housekeeping, settings with the switch off, no job, nothing dropped, consumer API untouched', () => {
  expect(m).toMatch(/^-- Replaces: security\.layer4_review_decide_impl, public\.admin_layer4_inbox/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
  expect(m).toContain("comment on table pipeline.layer4_bulk_operations is '")
  expect(m).toContain("comment on table pipeline.layer4_bulk_operation_items is '")
  expect(m).toContain("('pipeline', 'layer4.bulk_review_enabled', 'Bulk review: apply switched on',")
  expect(m).toMatch(/to_jsonb\(0\), 0, 1, 'on\/off', 888, 'Layer 4', 'security\.layer4_bulk_review_v1 \(bulk_apply\); Layer 4 › Review bulk panel'/)
  for (const k of ['layer4.bulk_batch_size', 'layer4.bulk_max_courses', 'layer4.bulk_open_minutes']) expect(m).toContain(`('pipeline', '${k}', 'Bulk review:`)
  expect(m).toContain("raise exception 'UR-18 post-check: layer4.bulk_review_enabled must be 0 after this migration")
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/i)
  expect(m).not.toMatch(/cron\.schedule\(/)
  expect(outside(code(m))).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\./)
  expect(code(m)).not.toMatch(/alter\s+table\s+(catalogue|ref|search|api)\./i)
  expect(m).not.toMatch(/Consumer API change approved/)
})

test('the two md5-guarded edits apply exactly once to the live definitions and give the after md5s', () => {
  const edits = [...m.matchAll(/select pg_temp\.edit_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})', array\[\s*array\[\$o\$([\s\S]*?)\$o\$,\s*\$n\$([\s\S]*?)\$n\$\]\s*\], array\[1\]\);/g)]
  expect(edits.map((e) => e[1])).toEqual(Object.keys(EDITS))
  for (const [, sig, before, after, o, n] of edits) {
    const e = EDITS[sig]
    const def = fs.readFileSync(`${FX}/${e.file}.before.sql`, 'utf8')
    expect([before, after]).toEqual([e.before, e.after])
    expect(md5(def), sig).toBe(before)
    expect(def.split(o).length - 1, sig).toBe(1)
    expect(md5(def.split(o).join(n)), sig).toBe(after)
    expect(m).toContain(`Before: ${before}. After: ${after}`)
  }
  // the decision path routes only the four bulk field codes; the inbox routes only the four bulk actions
  expect(m).toContain("elsif v_item.field_code = any (security.layer4_bulk_field_codes_v1()) then")
  expect(m).toContain("if p_action in ('bulk_preview', 'bulk_apply', 'bulk_reverse', 'bulk_operation') then return security.layer4_bulk_review_v1(p_action, p_args); end if;")
})

test('D-B1: four fields in the approved order; AER, intake and English refused; AER kinds never bulk field codes', () => {
  expect(fn('security.layer4_bulk_field_codes_v1')).toContain("array['bulk_campus_country', 'bulk_campus_state', 'bulk_course_campus', 'bulk_course_location']")
  expect(m).toContain("check (field in ('country', 'state', 'campus', 'location'))")
  const plan = fn('security.layer4_bulk_plan_v1')
  expect(plan).toContain("raise exception 'bulk review covers country, state, campus and location only (intake and English follow later; academic entry requirements are never bulk-approved)'")
  for (const aer of ['entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read', 'course_english', 'course_intake']) expect(fn('security.layer4_bulk_field_codes_v1')).not.toContain(aer)
  // policy rules from the design (section 3): no physical campus for online-only courses; a city name alone never gives a state; ambiguous campus names refused
  expect(plan).toContain("when p_field = 'campus' and d.said = 'online' then 'excluded_exception'")
  expect(plan).toContain("'the address does not map to one state (no Australian postcode); a city name alone is not used'")
  expect(plan).toContain("raise exception 'this campus cannot be told apart from the university''s other campuses by name: link its courses one at a time'")
  expect(fs.readFileSync('src/Layer4BulkReview.jsx', 'utf8')).toContain("export const BULK_FIELDS=[['country','Country'],['state','State or territory'],['campus','Campus'],['location','Course delivery']]")
})

test('D-B2 and D-B3 in the server: preview reads, apply needs rank 6 and the switch, the plan unchanged, bounded batches, per-row outcome, read-back, audit, reversal', () => {
  const r = fn('security.layer4_bulk_review_v1')
  const apply = r.slice(r.indexOf('-- bulk_apply:'))
  expect(r.indexOf("if p_action = 'bulk_preview' then")).toBeLessThan(r.indexOf('-- bulk_apply:'))
  expect(r.slice(r.indexOf("if p_action = 'bulk_preview' then"), r.indexOf('-- bulk_apply:'))).not.toMatch(/\b(insert into|update|delete from)\b/i)
  expect(apply.indexOf("if v_rank < 6 then raise exception 'Platform Admin role required")).toBeGreaterThan(-1)
  expect(apply.indexOf("if not v_on then raise exception 'bulk apply is switched off")).toBeGreaterThan(apply.indexOf('if v_rank < 6'))
  expect(apply.indexOf("if not v_on then")).toBeLessThan(apply.indexOf('insert into'))
  expect(r).toContain("v_on boolean := security.pipeline_num_v1('layer4.bulk_review_enabled', 0) >= 1;")
  expect(r).toContain("v_batch int := greatest(1, security.pipeline_num_v1('layer4.bulk_batch_size', 50)::int);")
  expect(apply).toContain("raise exception 'the plan has changed since the preview (a value, lock or reading changed): preview again; nothing was changed';")
  expect(apply).toContain('order by i.entity_type, i.entity_id limit v_batch loop')
  expect(apply).toContain("v_dec := security.layer4_review_decide_impl(v_item, 'approve', 'Bulk review: ' || v_reason, null);")
  expect(apply).toContain("if v_after is distinct from r.proposed_value then raise exception 'the destination does not show the value after the write")
  expect(apply).toContain("exception when others then\n      v_out := 'failed'; v_why := left(sqlerrm, 300);")
  expect(apply).toContain("values ('layer4', 'bulk_item_' || v_out, 'pipeline.layer4_bulk_operation_items',")
  expect(apply).toContain("where i.operation_id = v_op.id and i.selected and (i.outcome is null or i.outcome = 'failed')")
  expect(r).toContain("values ('layer4', 'bulk_reverse_' || v_out, 'pipeline.layer4_bulk_operation_items',")
  expect(r).toContain("if v_rank < 6 then raise exception 'Platform Admin role required: only the Platform Admin applies or reverses bulk review (decision D-B2)'")
  // the field writes refuse outside a bulk apply or reversal, and need the Platform Admin
  const w = fn('security.layer4_bulk_field_apply_v1')
  expect(w).toContain("if security.current_role_rank() < 6 then raise exception 'Platform Admin role required")
  expect(w).toContain("raise exception 'bulk review fields are written only inside a bulk apply or reversal';")
  // protected values are classed before anything else
  const plan = fn('security.layer4_bulk_plan_v1')
  expect(plan).toContain("when d.locked or d.del_ex is not null or d.fld_ex or (p_field = 'location' and d.overridden) then 'protected'")
})

test('isolated fixture: the recorded run is of this migration and every D-B3 case passed; nothing was switched on', () => {
  const res = fs.readFileSync(`${FX}/result.txt`, 'utf8')
  expect(res).toContain(`migration md5: ${md5(m)}`)
  expect(res).toContain(`before md5 (decide_impl, inbox): ${EDITS['security.layer4_review_decide_impl(uuid,text,text,jsonb)'].before} ${EDITS['public.admin_layer4_inbox(text,jsonb)'].before}`)
  expect(res).toContain(`after md5 (decide_impl, inbox): ${EDITS['security.layer4_review_decide_impl(uuid,text,text,jsonb)'].after} ${EDITS['public.admin_layer4_inbox(text,jsonb)'].after}`)
  for (const c of ['PASS 1 deterministic preview, read only', 'PASS 2 exact counts with course-level evidence', 'PASS 3 eligible-field policy', 'PASS 4 role boundary and switch',
    'PASS 5 stale fingerprint and per-row conflict', 'PASS 6 idempotent, bounded, audited per course', 'PASS 7 partial failure, retry, read-back', 'PASS 8 reversal',
    'PASS 9 bounds and one controller', 'PASS 10 apply path closed outside bulk', 'PASS 11 switch stays off', 'ALL CASES PASSED']) expect(res).toContain(c)
  const cases = fs.readFileSync(`${FX}/cases.sql`, 'utf8')
  for (const label of ["'campus preview twice'", "'campus counts'", "'locked and excluded courses untouched'", "'operator apply'", "'disabled refuses'", "'stale value'",
    "'stale evidence (page read again)'", "'retry writes nothing'", "'no duplicates'", "'partial, never done'", "'K010 read back failed'", "'retry writes only the two that failed'",
    "'reversal counts'", "'K003 left as changed'", "'switch still 0'"]) expect(cases).toContain(label)
  // the runner refuses a Supabase host; the fixture never targets a project
  expect(fs.readFileSync(`${FX}/run-fixture.sh`, 'utf8')).toContain('case "${PGHOST:-}" in *supabase*|*pooler*) echo "refused: run the fixture on a local Postgres only"')
})

test.describe('mocked browser', () => {
  const PID = '11111111-1111-4111-8111-111111111111'
  const CAMPUS = '22222222-2222-4222-8222-222222222222'
  const rows = Array.from({ length: 3 }, (_, i) => ({ entity_type: 'course', entity_id: `c${i}`, code: `K00${i}`, title: `Course ${i}`, level: 'Bachelor', campus: '—',
    current: { campus_id: CAMPUS, linked: false }, proposed: { campus_id: CAMPUS, linked: true }, class: i === 2 ? 'protected' : 'eligible',
    reason: i === 2 ? 'set by hand on the course record' : 'the course page names Melbourne City Campus', evidence: { page_url: `https://uni.example/c${i}`, read_at: '2026-10-21T01:00:00Z' } }))
  const counts = { candidate: 130, eligible: 122, unchanged: 1, protected: 2, excluded_exception: 2, excluded_conflict: 1, excluded_unsupported: 2, courses_affected: 122 }
  async function setup(page, { rank, enabled }) {
    await mockAdmin(page, { rank })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      const a = b.p_args || {}
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds: {}, target_days: 7, rank, total: 0, universities: 1, late: 0, by_kind: {} } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: PID, name: 'Fixture University', country: 'AU', courses: 130, n: 1, by_kind: {} }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 0, items: [] } })
      if (b.p_action === 'bulk_preview' && !a.value?.campus_id) return route.fulfill({ json: { needs_value: true, enabled, can_apply: rank >= 6, country: 'AU',
        campuses: [{ campus_id: CAMPUS, name: 'Melbourne City Campus', city: 'Melbourne', courses: 1 }] } })
      if (b.p_action === 'bulk_preview') return route.fulfill({ json: { provider_id: PID, field: 'campus', value: a.value, unit: 'course', fingerprint: 'f'.repeat(32), counts,
        enabled, can_apply: rank >= 6, batch_size: 50, max_rows: 500, total: a.class ? 2 : 130, limit: 200, offset: 0, rows: a.class === 'protected' ? rows.slice(2) : rows } })
      if (b.p_action === 'bulk_apply') return route.fulfill({ json: { ok: true, operation_key: 'k1', state: 'partial', this_call: [{ entity_id: 'c9', outcome: 'failed', reason: 'database error' }],
        totals: { applied: 49, unchanged: 1, excluded: 7, conflicted: 0, failed: 1, remaining: 72 } } })
      if (b.p_action === 'bulk_reverse') return route.fulfill({ json: { ok: true, operation_key: 'k1', state: 'reversed', reversal: { reversed: 49 } } })
      return route.fulfill({ json: {} })
    })
    await page.goto(`/#layer-4-review?provider=${PID}`)
    await page.locator('[data-l4-bulk-toggle]').click()
    await page.locator('[data-bulk-field="campus"]').click()
    await page.locator('[data-bulk-value]').selectOption(CAMPUS)
    await page.locator('[data-bulk-preview]').click()
    await expect(page.locator('[data-bulk-count="eligible"]')).toContainText('122')
    return calls
  }

  test('a reviewer previews exact counts and rows with their evidence, filters by class, and is told only the Platform Admin applies', async ({ page }) => {
    const calls = await setup(page, { rank: 4, enabled: true })
    await expect(page.locator('[data-bulk-count="candidate"]')).toContainText('Candidate courses')
    await expect(page.locator('[data-bulk-count="candidate"]')).toContainText('130')
    await expect(page.locator('[data-bulk-count="protected"]')).toContainText('2')
    await expect(page.locator('[data-bulk-row]')).toHaveCount(3)
    await expect(page.locator('[data-bulk-row="protected"]')).toContainText('set by hand on the course record')
    await expect(page.locator('[data-bulk-row="eligible"]').first().getByRole('link', { name: /course page/ })).toHaveAttribute('href', 'https://uni.example/c0')
    await page.locator('[data-bulk-count="protected"]').click()
    await expect(page.locator('[data-bulk-row]')).toHaveCount(1)
    expect(calls.filter((c) => c.p_action === 'bulk_preview').at(-1).p_args).toMatchObject({ provider_id: PID, field: 'campus', value: { campus_id: CAMPUS }, class: 'protected' })
    await expect(page.locator('[data-bulk-preview-only]')).toContainText('Only the Platform Admin applies bulk changes')
    await expect(page.locator('[data-bulk-apply]')).toHaveCount(0)
    expect(calls.some((c) => c.p_action === 'bulk_apply')).toBe(false)
  })

  test('the Platform Admin sees plainly that bulk apply is switched off, and no apply control', async ({ page }) => {
    const calls = await setup(page, { rank: 6, enabled: false })
    await expect(page.locator('[data-bulk-off]')).toContainText('Bulk apply is switched off (setting layer4.bulk_review_enabled is 0)')
    await expect(page.locator('[data-bulk-apply]')).toHaveCount(0)
    expect(calls.some((c) => c.p_action === 'bulk_apply')).toBe(false)
  })

  test('while switched on, the Platform Admin applies with a reason and the preview fingerprint, sees a partial result as partial, and can reverse', async ({ page }) => {
    const calls = await setup(page, { rank: 6, enabled: true })
    const apply = page.locator('[data-bulk-apply]')
    await expect(apply).toContainText('Apply to 50 of 122 eligible courses')
    await expect(apply).toBeDisabled()
    await page.locator('[data-bulk-reason]').fill('Official course pages name the campus')
    await apply.click()
    expect(calls.find((c) => c.p_action === 'bulk_apply').p_args).toEqual({ provider_id: PID, field: 'campus', value: { campus_id: CAMPUS }, fingerprint: 'f'.repeat(32), reason: 'Official course pages name the campus' })
    await expect(page.locator('[data-bulk-result="partial"]')).toContainText('Partly applied: not finished')
    await expect(page.locator('[data-bulk-result="partial"]')).toContainText('failed: database error')
    await expect(apply).toContainText('Apply the next batch')
    await page.locator('[data-bulk-reverse-reason]').fill('Wrong campus for this university')
    await page.locator('[data-bulk-reverse]').click()
    expect(calls.find((c) => c.p_action === 'bulk_reverse').p_args).toEqual({ operation_key: 'k1', reason: 'Wrong campus for this university' })
    await expect(page.locator('[data-bulk-reversed]')).toContainText('reversed 49')
  })
})
