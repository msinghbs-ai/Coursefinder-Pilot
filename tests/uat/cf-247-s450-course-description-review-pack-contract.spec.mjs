// Guards: Platform Admin directive 8 Nov 2026 14:06 (course descriptions: review packets and capacity numbers, human approval stays mandatory, claim and evidence guards unchanged, no auto-approval)
// and the 8 Nov 2026 mandate lane C-DESC ("do not create endless new proposals when no reviewer can decide"): migration 20261108130000 plans review capacity, orders and flags the pack,
// pauses new readings on request and retires proposals that can no longer be approved. The database behaviour (31 checks) runs on the production-parity fixture:
// tests/fixtures/course-description-backpressure/run.sh (workflow "Course descriptions fixture"). This spec holds the source contract and the screen contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261108130000_cf247_cdesc_review_pack_capacity_backpressure.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/course-description-backpressure'
const fn = (name) => { const a = code.indexOf(`function ${name}`); return code.slice(a, code.indexOf('$function$;', code.indexOf('$function$', a + 10) + 10)) }

test('migration: capacity and pack are read only and decide nothing', () => {
  for (const f of ['security.course_description_capacity_v1', 'security.course_description_pack_v1']) {
    const body = fn(f)
    expect(body.length, f).toBeGreaterThan(200)
    expect(body, f).toMatch(/\bstable\b/)
    expect(body, f).not.toMatch(/\b(insert\s+into|update\s+\S+\s+set|delete\s+from)\b/i)
    expect(body, f).not.toMatch(/layer4_decisions|search\.refresh_requests|catalogue\.courses\s+set/i)
  }
  expect(code).toContain('revoke all on function security.course_description_capacity_v1() from public, anon, authenticated')
  expect(code).toContain('revoke all on function security.course_description_pack_v1(uuid, integer) from public, anon, authenticated')
})

test('migration: the pack only orders and flags; the flags are the objective four and the checks are not touched', () => {
  const pack = fn('security.course_description_pack_v1')
  for (const f of ['same_words_elsewhere', 'claim_word', 'marketing_word', 'money_or_year']) expect(pack, f).toContain(`'${f}'`)
  expect(pack).toContain('security.course_description_reconcile_v1')
  expect(pack).toContain("q.class = 'ready'")
  // the claim and marketing lists are the ones the admission check reads
  expect(pack).toContain("'enrich.course_description_claim_words'")
  expect(pack).toContain("'enrich.course_description_marketing_words'")
  // nothing in the migration replaces or edits an admission, trust or Layer 4 decision function
  for (const f of ['course_description_check_v1', 'course_description_check_with_v1', 'enrich_course_text_record_v1', 'layer4_course_description_apply_v1', 'course_description_trusted_v1', 'layer4_review_decide_impl', 'course_description_release_held_v1'])
    expect(code, f).not.toMatch(new RegExp(`create or replace function \\S*${f}\\b`))
  expect(code).not.toMatch(/status\s*=\s*'(approved|edited_approved|rejected)'/)
  expect(code).not.toMatch(/enrich\.course_description_review_first'\s*,\s*'/)
  expect(code).not.toMatch(/update\s+pipeline\.platform_toolset_settings/i)
})

test('migration: back-pressure ships off and sits only on the description field of the gap queue; guarded by the live md5', () => {
  expect(MIG).toContain('a6d0da8f6d6fd7d31c6c39c707e2d824')
  expect(MIG).toContain('a7bb9ff0f964c6caaf2537e5ae36c084')
  expect(code).toMatch(/'enrich\.course_description_pending_global_max'[\s\S]*?'number', '0'::jsonb, 0, 20000, 'descriptions'/)
  const gaps = fn('security.enrich_course_text_gaps_v1')
  expect(gaps).toMatch(/continue when f = 'description' and v_gmax > 0/)
  expect(gaps).toContain("pipeline_num_v1('enrich.course_description_pending_global_max', 0)")
  expect(gaps).toContain('-- fixed: the cap is a day')
  // the rest of the selection is the live one: same cap, same states, same exclusions
  for (const k of ["'enrich.course_text_items_per_day', 500", "'gaps.recheck_days', 60", "g.read_status = 'read' and g.identity_basis is not null", 'security.enrich_item_held_v1(m.cid, f)', 'security.provider_hidden_v1']) expect(gaps, k).toContain(k)
})

test('migration: stale retire supersedes only what cannot be approved, records why, ships off, and is a catalogued job (G1)', () => {
  const r = fn('security.course_description_retire_stale_v1')
  expect(r).toContain("q.class in ('course_inactive', 'already_filled')")
  expect(r).not.toMatch(/page_changed|'locked'/)
  expect(r).toContain("status = 'superseded'")
  expect(r).toContain('pipeline.layer4_supersessions')
  expect(r).toContain("pipeline_num_v1('enrich.course_description_stale_supersede_on', 0)")
  expect(code).toMatch(/'enrich\.course_description_stale_supersede_on'[\s\S]*?'number', '0'::jsonb, 0, 1, 'on\/off'/)
  expect(code).toMatch(/insert into pipeline\.automation_catalogue[\s\S]*?'course-description-stale-retire'/)
  expect(code).toContain("cron.schedule('course-description-stale-retire', '13 * * * *', $j$select security.course_description_retire_stale_v1()$j$)")
})

test('migration: housekeeping, G3 and the Admin entry point', () => {
  expect(MIG).toMatch(/^-- Replaces: .*enrich_course_text_gaps_v1.*admin_course_description_queue/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|\bapi\./)
  expect(code).not.toMatch(/\b(drop|delete\s+from|truncate)\b/i)
  expect(code).toContain("'20261108130000'")
  const q = fn('public.admin_course_description_queue')
  expect(q).toContain('coalesce(security.current_role_rank(), 0) < 4')
  for (const a of ["'capacity'", "'pack'", "'summary'", "'items'", "'held_reasons'", "'claim_words'", "'sample'"]) expect(q, a).toContain(a)
})

test('screen: the Layer 4 Inbox course description panel shows capacity, a by-university pack and the flags, and still decides nothing', () => {
  const ui = fs.readFileSync('src/CourseDescriptionPanel.jsx', 'utf8')
  for (const a of ['data-l4-cd-capacity', 'data-l4-cd-pack', 'data-l4-cd-flags']) expect(ui, a).toContain(a)
  expect(ui).toContain("cdQueue('capacity')")
  expect(ui).toMatch(/mode==='pack'\?cdQueue\('pack'/)
  for (const f of ['same_words_elsewhere', 'claim_word', 'marketing_word', 'money_or_year']) expect(ui, f).toContain(f)
  // the panel is read only: the only server calls are the queue reads
  expect((ui.match(/supabase\.rpc\(/g) || []).length).toBe(1)
  expect(ui).toContain("supabase.rpc('admin_course_description_queue'")
})

test('fixture runner applies the migration twice on the production-parity fixture, checks the captured live md5 and fails on any scenario error', () => {
  const run = fs.readFileSync(`${FX}/run.sh`, 'utf8'), sc = fs.readFileSync(`${FX}/scenarios.sql`, 'utf8')
  expect(run).toContain('set -euo pipefail')
  expect(run.match(/-f \$MIG/g).length).toBe(2)
  expect(run).toContain('a6d0da8f6d6fd7d31c6c39c707e2d824')
  expect(run).toContain('cdesc scenarios FAILED')
  for (const t of ['capacity: pending 9, ready 5', 'pack: University One first', 'pack: shared wording flagged', 'entry point: rank gate and unknown action refused', 'gaps: as many waiting as the limit',
    'gaps: the deadline field is not held back', 'retire off: counts the 2 it could settle and settles none', 'retire on: page-changed (23) and locked (24) stay with a person',
    'retire on: no catalogue description was written', 'review_first untouched and nothing admitted by any of it']) expect(sc, t).toContain(t)
  const wf = fs.readFileSync('.github/workflows/course-descriptions-test.yml', 'utf8')
  expect(wf).toContain('tests/fixtures/course-description-backpressure/run.sh')
})
