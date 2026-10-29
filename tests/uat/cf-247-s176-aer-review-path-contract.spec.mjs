// Guards: CF-247 decisions A1–A3 (Platform Admin 30 Oct 2026 06:53): AER items take the evidence-aware review path only: Approve except leaves explicit rows unadmitted and identifiable with reviewer, reason and lineage; AER kinds are skipped by generic bulk and batch decide; AER admission and rejection are the Platform Admin's; W28 re-reads never touch excluded rows
// Record: admin docs/platform/ui-audit/2026-10-30-platform-admin-decision-paper.md Part A. The migration was applied to md5-identical copies of the live
// definitions in a scratch database and exercised (A1 approve except, A2 skips, A3 refusals, W28 re-read after an exclusion) before handback.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const [FILE] = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('_cf247_aer_review_path.sql'))
const m = fs.readFileSync(`supabase/migrations/${FILE}`, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
// each md5-guarded edit: signature, live md5, originals ($o$) and replacements ($n$), and how many times each applies
const EDITS = [...m.matchAll(/select pg_temp\.edit_n\('([^']+)', '([0-9a-f]{32})', array\[([\s\S]*?)\], array\[([\d, ]+)\]\);/g)].map(([, sig, md5, body, times]) => ({
  sig, md5, old: [...body.matchAll(/\$o\$([\s\S]*?)\$o\$/g)].map((x) => x[1]), neu: [...body.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1]).join('\n'), times: times.split(',').map(Number) }))
const edit = (s) => EDITS.find((e) => e.sig.startsWith(s))
const fnBody = (name) => (m.match(new RegExp(`create or replace function ${name.replace('.', '\\.')}\\([\\s\\S]*?\\$function\\$([\\s\\S]*?)\\$function\\$`)) || [])[1] || ''
const AER = ['entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read']

test('the edits are md5-guarded against the live definitions (read 30 Oct 2026) and each applies exactly once', () => {
  expect(code).toContain('if md5(v_def) <> p_md5 then raise exception')
  expect(EDITS.map((e) => [e.sig, e.md5])).toEqual([
    ['security.layer4_review_decide_impl(uuid,text,text,jsonb)', '22f17fa1cc5e9a3644b18c199a6c5518'],
    ['security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '5531f0198f89c1246587118ccb8344a6'],
    ['security.course_entry_review_apply_v1(uuid,text,jsonb,text)', 'e2ae70b0077bf458d505b430f77fdebd'],
    ['l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer)', 'e6a2ffddff142a81d9a6d6a050661b2d'],
    ['security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text)', 'f8e9e97314096ff24cea8e8c7d5641ce'],
    ['security.layer4_inbox_kinds_v1()', '3f1fddbe89ed4e5c18262cade82e817a'],
    ['security.layer4_inbox_items_v1()', 'cc42a3d524545fb518186d81971da56f'],
    ['public.admin_layer4_inbox(text,jsonb)', '272438c275c6707280d5d29cdfbd8729']])
  for (const e of EDITS) { expect(e.old.length, e.sig).toBe(e.times.length); expect(e.times.every((t) => t === 1), e.sig).toBe(true) }
  // the AER kinds are named once and used everywhere
  expect(fnBody('security.aer_review_kinds_v1')).toContain(`array[${AER.map((k) => `'${k}'`).join(', ')}]::text[]`)
  for (const s of ['security.layer4_review_decide_impl', 'l4_api.layer4_review_bulk_decide', 'security.layer4_batch_decide_v1_impl', 'security.layer4_inbox_items_v1'])
    expect(edit(s).neu, s).toContain('= any (security.aer_review_kinds_v1())')
})

test('A3: AER admission and rejection need the Platform Admin, on the server and in the Inbox; Curators keep the workspace', () => {
  const d = edit('security.layer4_review_decide_impl').neu
  expect(d).toContain("if v_item.field_code = any (security.aer_review_kinds_v1()) then")
  expect(d).toContain("if v_rank<6 then raise exception 'Platform Admin role required: AER items are admitted or rejected by the Platform Admin (decision A3)' using errcode='42501'; end if;")
  // only inside the AER branch: the Curator check for every other kind is untouched
  expect(edit('security.layer4_review_decide_impl').old.join('\n')).not.toContain('v_rank<3')
  const kinds = JSON.parse(`{${edit('security.layer4_inbox_kinds_v1').neu.replace(/''/g, "'").replace(/,\s*"provider_departure"[\s\S]*$/, '')}}`)
  expect(kinds.aer_review.choices.map((c) => [c.key, c.rank, c.input || null])).toEqual([['approve', 6, null], ['approve_except', 6, 'rows'], ['reject', 6, null]])
  // the workspace's operational editing (public.admin_aer) is not changed
  expect(code).not.toMatch(/admin_aer\(/)
})

test('A1: Approve except is explicit, evidenced, attributed and audited; no other inline edit of an AER item', () => {
  const d = edit('security.layer4_review_decide_impl').neu
  expect(d).toContain("v_final:=v_item.proposed_value-'exclude_row_ids';  -- A1: a plain approval never carries an exclusion")
  expect(d).toContain('v_final:=security.aer_approve_except_v1(v_item.id,p_final_value,trim(p_reason),v_actor,v_aer);')
  expect(d).toContain("values ('layer4', case when p_action='edit_and_approve' then 'aer_approve_except' else 'aer_'||p_action end, 'pipeline.layer4_review_items',")
  expect(d).toContain("'lineage', v_aer, 'excluded_row_ids', coalesce(v_final->'exclude_row_ids', '[]'::jsonb), 'result', v_scalar), v_actor);")
  const x = fnBody('security.aer_approve_except_v1')
  for (const msg of ['AER items are not edited inline: use Approve except', 'tick at least one row to leave out, or use Approve',
    'ticked row(s) are not waiting rows of this item', 'every row is left out; use Reject instead', 'a row to leave out is not a row id']) expect(x).toContain(msg)
  for (const k of ["'mode', 'approve_except'", "'exclude_row_ids', to_jsonb(v_ex)", "'reviewer', p_actor", "'reason', p_reason", "'excluded'", "'lineage', p_lineage"]) expect(x).toContain(k)
  // lineage: item -> run -> source -> stored copy hash -> rows
  const l = fnBody('security.aer_review_lineage_v1')
  for (const k of ["'run_id', r.id", "'source_id', r.source_id", "'content_hash', r.content_hash", "'proposed_row_ids'", "'row_content_hashes'", "'completeness'", "'enrich_item_id'"]) expect(l).toContain(k)
})

test('A1: excluded rows stay inactive and identifiable; admitted rows pass the same gates; the complete read is accounted for', () => {
  for (const s of ['security.entry_matrix_review_apply_v1', 'security.course_entry_review_apply_v1']) {
    const n = edit(s).neu
    expect(n, s).toContain("set status = 'inactive',")
    expect(n, s).toMatch(/status_reason = 'excluded by approve except \(Layer 4 item ' \|\| .+ \|\| ', reviewer ' \|\| coalesce\(p_final->>'reviewer', 'unknown'\) \|\| '\): ' \|\| coalesce\(p_reason, ''\),/)
    expect(n, s).toContain("jsonb_build_object('aer_exclusion', jsonb_build_object('review_item_id',")
    // no new row status
    for (const st of [...n.matchAll(/status = '([a-z_]+)'/g)].map((v) => v[1])) expect(['inactive', 'proposed']).toContain(st)
  }
  const mx = edit('security.entry_matrix_review_apply_v1')
  // the identity and verdict gates stay ahead of admission (not edited); the complete-admission count now counts every waiting row
  expect(mx.old.join('\n')).not.toContain('proposed rows share an identity')
  expect(mx.old.join('\n')).not.toContain('has not passed the completeness guard')
  expect(mx.neu).toContain("and (select count(*) from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed')\n           is distinct from nullif(r.result->'completeness'->>'matched', '')::int then")
  expect(mx.neu).toContain('every row of a complete read is admitted or explicitly excluded')
  expect(mx.neu).not.toContain('admitted whole or rejected')
})

test('A2: generic bulk decide and batch decide skip AER kinds, decide nothing and report how many they skipped', () => {
  const b = edit('l4_api.layer4_review_bulk_decide').neu
  expect(b).toContain("if p_field_code = any (security.aer_review_kinds_v1()) then")
  expect(b).toContain("return jsonb_build_object('ok',false,'action',p_action,'processed',0,'failed',0,'skipped_aer',v_count,")
  expect(b).toContain(",'publication_changed',false,'skipped_aer',0);")
  // the skip returns before the mass-operation row and before any decision
  expect(b.indexOf('aer_review_path_only')).toBeGreaterThan(-1)
  expect(b).not.toContain('layer4_mass_operations')
  const t = edit('security.layer4_batch_decide_v1_impl').neu
  expect(t).toContain("if v_field = any (security.aer_review_kinds_v1()) then")
  expect(t).toContain("return jsonb_build_object('ok',false,'decided',0,'skipped_aer',v_n,'action',p_action,'reason','aer_review_path_only',")
  expect(t).not.toContain('layer4_review_decide_impl')
})

test('W28: Read again supersedes only waiting rows, so an excluded row is never superseded, made stale or reclassified by it', () => {
  // this change does not edit the re-read paths; their row updates (W28, live since #744) all select status = 'proposed'
  expect(code).not.toMatch(/aer_reread_v1|admin_entry_matrix_reread/)
  const w28 = fs.readFileSync('supabase/migrations/20261029120000_cf247_aer_reread_newest_copy.sql', 'utf8')
  const n = [...w28.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1]).join('\n')
  const ups = [...n.matchAll(/update catalogue\.provider_entry_matrix[\s\S]*?;$/gm)].map((x) => x[0])
  expect(ups.length).toBeGreaterThanOrEqual(2)
  for (const u of ups) expect(u, u).toMatch(/where (m\.)?status = 'proposed'|and status = 'proposed'/)
  // the rule on rows: a re-read moves proposed to superseded and nothing else
  const reread = (rows) => rows.map((r) => (r.status === 'proposed' ? { ...r, status: 'superseded' } : r))
  const after = reread([
    { id: 'row-in', status: 'active' },
    { id: 'row-age', status: 'inactive', status_reason: 'excluded by approve except (Layer 4 item 81d14690, reviewer pa): minimum age is not academic' },
    { id: 'row-new', status: 'proposed' }])
  expect(after.find((r) => r.id === 'row-age')).toEqual({ id: 'row-age', status: 'inactive', status_reason: 'excluded by approve except (Layer 4 item 81d14690, reviewer pa): minimum age is not academic' })
  expect(after.find((r) => r.id === 'row-new').status).toBe('superseded')
  // the workspace cannot restore or edit it either: Restore needs a workspace withdraw or quarantine, Edit needs active or quarantined (admin_aer, unchanged)
  const ws = fs.readFileSync('supabase/migrations/20261029010000_cf247_aer_workspace.sql', 'utf8')
  expect(ws).toContain("a row never admitted is decided in Layer 4")
})

test('the Inbox shows AER items as their own kind with their rows; the AER workspace names an excluded row', () => {
  expect(edit('security.layer4_inbox_items_v1').neu).toContain("when r.field_code = any (security.aer_review_kinds_v1()) then 'aer_review'")
  const ib = edit('public.admin_layer4_inbox').neu
  expect(ib).toContain("elsif v_kind = 'aer_review' then")
  expect(ib).toContain("case when v_choice = 'approve_except' then jsonb_build_object('mode', 'approve_except', 'exclude_row_ids', to_jsonb(v_ids)) end);")
  expect(fnBody('security.aer_review_read_v1')).toContain("raise exception 'Curator role or above required'")
  expect(fnBody('security.aer_review_read_v1')).toContain("'can_decide', v_rank >= 6")
  const ui = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
  expect(ui).toContain("supabase.rpc('layer4_aer_review_read',{p_review_item_id:id})")
  const aer = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')
  expect(aer).toContain("const ex=status==='inactive'&&/^excluded by /.test(title||'')")
  expect(aer).toContain("['neutral','Excluded in Layer 4']")
})

test.describe('mocked browser', () => {
  const inbox = (rank, calls) => async (route) => {
    const b = route.request().postDataJSON(); calls.push(b)
    const kinds = { aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [
      { key: 'approve', label: 'Approve all rows', rank: 6, returns: 'Every waiting row becomes active once the checks pass' },
      { key: 'approve_except', label: 'Approve except…', rank: 6, input: 'rows', returns: 'The ticked rows stay unadmitted, marked excluded with your reason' },
      { key: 'reject', label: 'Reject the read', rank: 6, returns: 'No row is admitted' }] } }
    if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank, total: 1, universities: 1, late: 0, by_kind: { aer_review: { n: 1 } } } })
    if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p-monash', name: 'Monash University', country: 'AU', n: 1, by_kind: { aer_review: 1 } }] } })
    if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [{ kind: 'aer_review', ref: '81d14690-0000-4000-8000-000000000001', provider_id: 'p-monash',
      subject: 'Entry requirements: first read of the provider table', why: 'Needs a decision', created_at: '2026-10-29T00:19:00Z', detail: { field_code: 'entry_matrix_first_run' } }] } })
    if (b.p_action === 'decide') return route.fulfill({ json: { ok: true, returns: 'The ticked rows stay unadmitted' } })
    return route.fulfill({ json: {} })
  }

  test('Platform Admin: the rows with quotes and the stored copy; Approve except ticks one row, needs a reason, never all rows', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', inbox(6, calls))
    await page.goto('/#layer-4-review')
    const item = page.locator('[data-l4-item="aer_review"]')
    await expect(item.locator('[data-l4-aer-rows]')).toContainText('India | CBSE Year 12 | 75%')
    await expect(item.locator('[data-l4-aer-row="row-age"]')).toContainText('Applicants must be 17')
    await expect(item.locator('[data-l4-aer-lineage]')).toContainText('https://www.monash.edu/admissions/entry-requirements/international')
    await expect(item.locator('[data-l4-aer-evidence]')).toHaveText('Open the stored copy')
    await expect(item.locator('[data-l4-aer-read]')).toContainText('completeness complete (3 matched)')
    await expect(item.locator('[data-l4-aer-pa-only]')).toHaveCount(0)
    for (const c of ['approve', 'approve_except', 'reject']) await expect(item.locator(`[data-l4-choice="${c}"]`)).toBeEnabled()
    await expect(item.locator('[data-l4-aer-tick]')).toHaveCount(0) // no ticking until Approve except is chosen
    await item.locator('[data-l4-choice="approve_except"]').click()
    await item.getByLabel('Reason').fill('A minimum age is not an academic entry requirement')
    await expect(item.locator('[data-l4-confirm]')).toBeDisabled()
    for (const id of ['row-in', 'row-cn', 'row-age']) await item.locator(`[data-l4-aer-tick="${id}"]`).check()
    await expect(item.locator('[data-l4-aer-except-count]')).toContainText('Every row is ticked: use Reject the read instead.')
    await expect(item.locator('[data-l4-confirm]')).toBeDisabled()
    for (const id of ['row-in', 'row-cn']) await item.locator(`[data-l4-aer-tick="${id}"]`).uncheck()
    await expect(item.locator('[data-l4-aer-except-count]')).toContainText('Leaving out 1 of 3 rows; the other 2 become active once the checks pass.')
    await item.locator('[data-l4-confirm]').click()
    await expect(page.getByRole('status')).toContainText('Done.')
    const d = calls.filter((c) => c.p_action === 'decide')
    expect(d).toHaveLength(1)
    expect(d[0].p_args).toMatchObject({ kind: 'aer_review', ref: '81d14690-0000-4000-8000-000000000001', choice: 'approve_except', reason: 'A minimum age is not an academic entry requirement' })
    expect(JSON.parse(d[0].p_args.value)).toEqual(['row-age'])
  })

  test('Curator: reads the AER item and its rows, but every decision is the Platform Admin\'s (A3)', async ({ page }) => {
    await mockAdmin(page, { rank: 3 })
    const calls = []
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', inbox(3, calls))
    await page.goto('/#layer-4-review')
    const item = page.locator('[data-l4-item="aer_review"]')
    await expect(item.locator('[data-l4-aer-rows]')).toContainText('China | Gao Kao | 75%')
    await expect(item.locator('[data-l4-aer-pa-only]')).toContainText('admitted or rejected by the Platform Admin (decision A3)')
    for (const c of ['approve', 'approve_except', 'reject']) await expect(item.locator(`[data-l4-choice="${c}"]`)).toBeDisabled()
    expect(calls.some((c) => c.p_action === 'decide')).toBe(false)
  })
})
