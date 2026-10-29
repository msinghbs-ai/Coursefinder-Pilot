// Guards: CF-247 decision D4 (Platform Admin 30 Oct 2026 08:45): under Approve except only an active row with an explicitly approved replacement (same row identity) is superseded; an active row whose replacement was excluded stays active and unchanged; the retained row, excluded proposal and decision stay linked; conflicting approved replacements hold the whole decision with nothing changed
// Record: implementation decision lodged as admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md §11.1 (commit aef0490f) before code.
// The migration was dry-run on live (rolled back): mixed approve/exclude group, Approve all (W15), C1, C2, course pages with and without active rows.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const [FILE] = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('_cf247_d4_supersede_rule.sql'))
const m = fs.readFileSync(`supabase/migrations/${FILE}`, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const EDITS = [...m.matchAll(/select pg_temp\.edit_n\('([^']+)', '([0-9a-f]{32})', array\[([\s\S]*?)\], array\[([\d, ]+)\]\);/g)].map(([, sig, md5, body, times]) => ({
  sig, md5, old: [...body.matchAll(/\$o\$([\s\S]*?)\$o\$/g)].map((x) => x[1]), neu: [...body.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1]), times: times.split(',').map(Number) }))
const edit = (s) => EDITS.find((e) => e.sig.startsWith(s))
const W15 = `    update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'replaced by run ' || r.id, updated_at = now()
     where m.provider_id = r.provider_id and m.source_id = r.source_id and m.status = 'active' and m.run_id is distinct from r.id;`

// The D4 rule on rows, the same predicates as the migration (asserted against its text below). Rows carry id, hash (row_hash), source, status, run.
function decide({ run, source, rows, exclude = [] }) {
  const waiting = rows.filter((r) => r.run === run && r.status === 'proposed')
  const approved = waiting.filter((r) => !exclude.includes(r.id))
  const excluded = waiting.filter((r) => exclude.includes(r.id))
  const earlier = rows.filter((a) => a.status === 'active' && a.source === source && a.run !== run)
  // C1: two approved rows share one identity
  const byHash = approved.reduce((o, r) => ((o[r.hash] = [...(o[r.hash] || []), r.id]), o), {})
  const c1 = Object.values(byHash).filter((ids) => ids.length > 1)
  if (c1.length) return { held: 'C1', clash: c1, rows }
  // C2: an approved row's identity is active on a row this decision does not replace
  const c2 = approved.flatMap((p) => rows.filter((a) => a.status === 'active' && a.hash === p.hash && !earlier.includes(a)).map((a) => [p.id, a.id]))
  if (c2.length) return { held: 'C2', clash: c2, rows }
  const map = exclude.length === 0 ? null : {
    replaced: earlier.flatMap((a) => approved.filter((p) => p.hash === a.hash).map((p) => ({ active_row_id: a.id, replaced_by_row_id: p.id }))),
    retained_excluded: earlier.filter((a) => !approved.some((p) => p.hash === a.hash)).flatMap((a) => excluded.filter((x) => x.hash === a.hash).map((x) => ({ active_row_id: a.id, excluded_row_id: x.id }))),
    retained_not_in_read: earlier.filter((a) => !waiting.some((p) => p.hash === a.hash)).map((a) => a.id) }
  const superseded = new Set(map ? map.replaced.map((x) => x.active_row_id) : earlier.map((a) => a.id))  // no exclusion: W15, every earlier row of the source
  const after = rows.map((r) => superseded.has(r.id) ? { ...r, status: 'superseded', replaced_by: map?.replaced.find((x) => x.active_row_id === r.id).replaced_by_row_id }
    : excluded.includes(r) ? { ...r, status: 'inactive', retains_active_row_id: earlier.find((a) => a.hash === r.hash && !superseded.has(a.id))?.id ?? null }
    : approved.includes(r) ? { ...r, status: 'active' } : r)
  return { held: null, map, rows: after }
}
const row = (id, hash, extra = {}) => ({ id, hash, source: 'S', status: 'proposed', run: 'R2', ...extra })
const act = (id, hash, extra = {}) => ({ id, hash, source: 'S', status: 'active', run: 'R1', ...extra })

test('the edits are md5-guarded against the live definitions (read 30 Oct 2026) and each applies exactly once', () => {
  expect(code).toContain('if md5(v_def) <> p_md5 then raise exception')
  expect(EDITS.map((e) => [e.sig, e.md5])).toEqual([
    ['security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '7c718987b496cad38352f8dfa1f727b7'],
    ['security.course_entry_review_apply_v1(uuid,text,jsonb,text)', '25899209725990622fea50e533316f49'],
    ['security.layer4_inbox_kinds_v1()', '08e7999c3f4639f02b9607e1fd9ac506']])
  for (const e of EDITS) { expect(e.old.length, e.sig).toBe(e.times.length); expect(e.neu.length, e.sig).toBe(e.times.length); expect(e.times.every((t) => t === 1), e.sig).toBe(true) }
  // the decide function, the Approve except check and the lineage are read, not changed: the apply result already reaches the event as "result"
  expect(code).not.toMatch(/layer4_review_decide_impl|aer_approve_except_v1|aer_review_lineage_v1|svc_entry_matrix_record|entry_matrix_review_trg_v1/)
  expect(m).toMatch(/^-- Replaces: security\.entry_matrix_review_apply_v1, security\.course_entry_review_apply_v1, security\.layer4_inbox_kinds_v1 \(same names, md5-guarded edits\)$/m)
  expect(m).toMatch(/^-- Retires: nothing \(the implicit supersede of an excluded row's active counterpart under Approve except is switched off here\)$/m)
  expect(m).toContain('§11.1, commit aef0490f')
  // no new status, table, column or job; nothing dropped or deleted
  expect(code).not.toMatch(/^\s*(drop|delete|truncate|alter table|create table)\b/im)
  expect(code).not.toMatch(/cron\.schedule|platform_toolset_settings/)
  for (const e of EDITS) for (const st of [...e.neu.join('\n').matchAll(/status = '([a-z_]+)'/g)].map((v) => v[1])) expect(['active', 'proposed', 'superseded']).toContain(st)
})

test('provider tables: Approve all rows keeps W15 byte for byte; Approve except supersedes only rows an approved row replaces by identity', () => {
  const e = edit('security.entry_matrix_review_apply_v1')
  expect(e.old[2]).toBe(`${W15}\n    get diagnostics v_sup = row_count;`)
  const n = e.neu[2]
  expect(n).toContain(`    if cardinality(v_ex) = 0 then\n${W15}\n    get diagnostics v_sup = row_count;\n    else`)
  // the D4 supersede: an approved waiting row (not ticked) with the same row_hash, in W15's scope (same provider and source, an earlier run)
  const sup = n.slice(n.indexOf("      update catalogue.provider_entry_matrix m set status = 'superseded'"))
  expect(sup).toContain("where p.run_id = r.id and p.status = 'proposed' and not (p.id = any(v_ex)) and p.row_hash = m.row_hash\n         and m.provider_id = r.provider_id and m.source_id = r.source_id and m.status = 'active' and m.run_id is distinct from r.id;")
  expect(sup).toContain("jsonb_build_object('aer_supersede', jsonb_build_object('review_item_id', coalesce(p_item, r.review_item_id),\n               'run_id', r.id, 'replaced_by_row_id', p.id, 'decision', 'approve_except (D4)', 'at', now()))")
  // no other statement in the change writes an active row: the retained rows are never in an update's where
  const ups = [...e.neu.join('\n').matchAll(/update catalogue\.provider_entry_matrix m set[\s\S]*?;/g)].map((x) => x[0])
  expect(ups).toHaveLength(2)
  for (const u of ups) expect(u).toMatch(/status = 'superseded'/)
  // the map is taken before anything changes; retained rows are those with no approved replacement
  expect(n.indexOf('v_map := jsonb_build_object(')).toBeLessThan(n.indexOf("      update catalogue.provider_entry_matrix m set status = 'superseded'"))
  for (const k of ["'replaced'", "'retained_excluded'", "'retained_not_in_read'"]) expect(n).toContain(k)
})

test('holds: conflicting approved replacements refuse the whole decision with a clear message and nothing changed (C1, C2)', () => {
  const e = edit('security.entry_matrix_review_apply_v1')
  expect(e.old[1]).toContain('proposed rows share an identity; nothing admitted')
  expect(e.neu[1]).toContain("raise exception 'Held (decision D4): entry matrix run %: approved rows % share one identity, so it is not clear which replaces the active value; nothing was changed.")
  expect(e.neu[1]).toContain("using errcode = '23505';")
  const n = e.neu[2]
  expect(n).toContain("raise exception 'Held (decision D4): entry matrix run %: approved row(s) have the identity of an active row this decision does not replace (%); nothing was changed.")
  expect(n).toContain("and not coalesce(a.provider_id = r.provider_id and a.source_id = r.source_id and a.run_id is distinct from r.id, false)) then")
  // C2 runs before either supersede statement, on both paths (a raise inside the decide transaction leaves the item pending and writes nothing)
  expect(n.indexOf('Held (decision D4)')).toBeLessThan(n.indexOf('if cardinality(v_ex) = 0 then'))
  expect(code).toContain("v_m ~ 'proposed rows share an identity; nothing admitted' then")
})

test('audit: the excluded proposal names the active row it leaves in place; the result carries retained and the supersede map', () => {
  const e = edit('security.entry_matrix_review_apply_v1')
  expect(e.old[3]).toContain("'decision', 'approve_except (A1)')),")
  for (const k of ["'retains_active_row_id', (select a.id from catalogue.provider_entry_matrix a where a.row_hash = m.row_hash and a.status = 'active'",
    "'retains_active_row_hash', (select a.row_hash from catalogue.provider_entry_matrix a where a.row_hash = m.row_hash and a.status = 'active'"]) expect(e.neu[3]).toContain(k)
  expect(e.neu[4]).toContain("|| case when v_map is not null then jsonb_build_object('retained', v_ret, 'supersede_map', v_map) else '{}'::jsonb end;")
  // the decide function records the apply result in the aer_approve_except event (A1, unchanged here)
  const a1 = fs.readFileSync('supabase/migrations/20261030070000_cf247_aer_review_path.sql', 'utf8')
  expect(a1).toContain("'lineage', v_aer, 'excluded_row_ids', coalesce(v_final->'exclude_row_ids', '[]'::jsonb), 'result', v_scalar), v_actor);")
})

test('regression: a mixed approve/exclude group keeps the active row whose replacement was excluded, and replaces the one that was approved', () => {
  const rows = [act('A-in', 'h-in'), act('A-cn', 'h-cn'), act('A-gone', 'h-gone'), act('B-other', 'h-ot', { source: 'S2' }),
    row('P-in', 'h-in'), row('X-cn', 'h-cn'), row('P-new', 'h-new')]
  const r = decide({ run: 'R2', source: 'S', rows, exclude: ['X-cn'] })
  const s = Object.fromEntries(r.rows.map((x) => [x.id, x]))
  expect(r.held).toBeNull()
  expect(s['A-in']).toMatchObject({ status: 'superseded', replaced_by: 'P-in' })
  expect(s['A-cn']).toEqual(act('A-cn', 'h-cn'))            // active and unchanged
  expect(s['A-gone']).toEqual(act('A-gone', 'h-gone'))      // not in this read: literal reading, kept
  expect(s['B-other']).toEqual(act('B-other', 'h-ot', { source: 'S2' }))
  expect(s['X-cn']).toMatchObject({ status: 'inactive', retains_active_row_id: 'A-cn' })
  expect(s['P-in'].status).toBe('active'); expect(s['P-new'].status).toBe('active')
  expect(r.map).toEqual({ replaced: [{ active_row_id: 'A-in', replaced_by_row_id: 'P-in' }], retained_excluded: [{ active_row_id: 'A-cn', excluded_row_id: 'X-cn' }], retained_not_in_read: ['A-gone'] })
  // never two active rows with one identity
  const live = r.rows.filter((x) => x.status === 'active').map((x) => x.hash)
  expect(new Set(live).size).toBe(live.length)
})

test('regression: an approved and an excluded reading of one identity replace it; a band ladder with one band excluded keeps that band only', () => {
  // the approved reading is an explicit replacement even when another reading of the same identity was excluded
  let r = decide({ run: 'R2', source: 'S', rows: [act('A', 'h'), row('P', 'h'), row('X', 'h'), row('Q', 'q')], exclude: ['X'] })
  expect(r.held).toBeNull()
  expect(r.rows.find((x) => x.id === 'A')).toMatchObject({ status: 'superseded', replaced_by: 'P' })
  expect(r.rows.find((x) => x.id === 'X')).toMatchObject({ status: 'inactive', retains_active_row_id: null })
  // band ladder (band and level are part of the identity): band B's new reading excluded, bands A and C approved
  r = decide({ run: 'R2', source: 'S', rows: [act('A1', 'in|A'), act('B1', 'in|B'), act('C1', 'in|C'), row('A2', 'in|A'), row('B2', 'in|B'), row('C2', 'in|C')], exclude: ['B2'] })
  expect(r.rows.filter((x) => x.status === 'active').map((x) => x.id).sort()).toEqual(['A2', 'B1', 'C2'])
  expect(r.map.retained_excluded).toEqual([{ active_row_id: 'B1', excluded_row_id: 'B2' }])
  // no exclusion: W15, every earlier active row of the source is superseded, including one the new read does not carry
  r = decide({ run: 'R2', source: 'S', rows: [act('A1', 'a'), act('G1', 'gone'), row('A2', 'a')] })
  expect(r.map).toBeNull()
  expect(r.rows.filter((x) => x.status === 'superseded').map((x) => x.id).sort()).toEqual(['A1', 'G1'])
})

test('regression: conflicting approved replacements hold the decision and change nothing (C1 within the read, C2 against another source)', () => {
  const c1rows = [act('A', 'h'), row('P1', 'h'), row('P2', 'h'), row('X', 'x')]
  let r = decide({ run: 'R2', source: 'S', rows: c1rows, exclude: ['X'] })
  expect(r).toMatchObject({ held: 'C1', clash: [['P1', 'P2']] })
  expect(r.rows).toEqual(c1rows)
  // excluding one of the pair resolves it
  expect(decide({ run: 'R2', source: 'S', rows: c1rows, exclude: ['X', 'P2'] }).held).toBeNull()
  const c2rows = [act('A', 'h'), act('O', 'o', { source: 'S2' }), row('P', 'h'), row('Q', 'o'), row('X', 'x')]
  for (const exclude of [['X'], []]) {
    r = decide({ run: 'R2', source: 'S', rows: c2rows, exclude })
    expect(r).toMatchObject({ held: 'C2', clash: [['Q', 'O']] })
    expect(r.rows).toEqual(c2rows)
  }
})

test('course pages: Approve except on a course with active rows is held (no identity to match); with none it works as before', () => {
  const e = edit('security.course_entry_review_apply_v1')
  expect(e.old[0]).toBe("    update catalogue.course_entry_requirements x set status = 'superseded', status_reason = 'replaced by Layer 4 item ' || p_item, updated_at = now()")
  const n = e.neu[0]
  expect(n).toContain("if cardinality(v_ex) > 0 and exists (select 1 from catalogue.course_entry_requirements x\n                                         where x.course_id = r.entity_id and x.status = 'active' and x.provenance->>'reader' = 'enrich_ai') then")
  expect(n).toContain("raise exception 'Held (decision D4): course % has % active entry requirement rows and course rows have no identity to match an excluded row to the row it would replace; nothing was changed. Use Approve all rows if every waiting row is right, or Reject the read',")
  expect(n).toContain("using errcode = '55000';")
  // the hold comes before the supersede, which is then the unchanged W15 statement
  expect(n.endsWith(e.old[0])).toBe(true)
})

test('Layer 4 > Inbox: the Approve except choice says an active row whose replacement is left out stays active', () => {
  const e = edit('security.layer4_inbox_kinds_v1')
  expect(e.neu[0]).toBe('"The ticked rows stay unadmitted, marked excluded with your reason; every other row becomes active once the same checks pass. An earlier active row is replaced only by an approved row with its identity; one whose replacement you leave out stays active (D4)"')
  expect(e.neu[0]).not.toContain("'")
})

test.describe('mocked browser', () => {
  test('a held Approve except is shown to the reviewer with its reason and the item stays waiting', async ({ page }) => {
    await mockAdmin(page, { rank: 6 })
    const calls = []
    const held = 'Held (decision D4): entry matrix run e07eeaf5: approved rows [row-in, row-in2] share one identity, so it is not clear which replaces the active value; nothing was changed. Leave out all but one of them, or Reject the read'
    await page.route('https://example.supabase.co/rest/v1/rpc/admin_layer4_inbox', async (route) => {
      const b = route.request().postDataJSON(); calls.push(b)
      const kinds = { aer_review: { label: 'Entry requirements (AER)', order: 17, choices: [
        { key: 'approve', label: 'Approve all rows', rank: 6, returns: 'Every waiting row becomes active once the checks pass' },
        { key: 'approve_except', label: 'Approve except…', rank: 6, input: 'rows', returns: 'An earlier active row is replaced only by an approved row with its identity; one whose replacement you leave out stays active (D4)' },
        { key: 'reject', label: 'Reject the read', rank: 6, returns: 'No row is admitted' }] } }
      if (b.p_action === 'summary') return route.fulfill({ json: { kinds, target_days: 7, rank: 6, total: 1, universities: 1, late: 0, by_kind: { aer_review: { n: 1 } } } })
      if (b.p_action === 'universities') return route.fulfill({ json: { total: 1, items: [{ provider_id: 'p-monash', name: 'Monash University', country: 'AU', n: 1, by_kind: { aer_review: 1 } }] } })
      if (b.p_action === 'items') return route.fulfill({ json: { total: 1, items: [{ kind: 'aer_review', ref: '9adbeada-0000-4000-8000-000000000001', provider_id: 'p-monash',
        subject: 'Entry requirements: the provider table changed', why: 'Needs a decision', created_at: '2026-10-29T00:19:00Z', detail: { field_code: 'entry_matrix_change' } }] } })
      if (b.p_action === 'decide') return route.fulfill({ status: 400, json: { code: '23505', message: held } })
      return route.fulfill({ json: {} })
    })
    await page.goto('/#layer-4-review')
    const item = page.locator('[data-l4-item="aer_review"]')
    await expect(item.locator('[data-l4-aer-rows]')).toContainText('India | CBSE Year 12 | 75%')
    await item.locator('[data-l4-choice="approve_except"]').click()
    await expect(item).toContainText('one whose replacement you leave out stays active (D4)')
    await item.getByLabel('Reason').fill('A minimum age is not an academic entry requirement')
    await item.locator('[data-l4-aer-tick="row-age"]').check()
    await item.locator('[data-l4-confirm]').click()
    await expect(item.locator('[role="alert"]')).toContainText('Held (decision D4)')
    await expect(item.locator('[role="alert"]')).toContainText('nothing was changed')
    await expect(item).toBeVisible()
    expect(calls.filter((c) => c.p_action === 'decide')).toHaveLength(1)
  })
})
