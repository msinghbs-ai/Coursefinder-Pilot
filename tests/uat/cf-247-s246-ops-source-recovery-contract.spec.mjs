// Guards: P0 Autonomous AI Operations mandate 3 Nov 2026 15:37 §3 and §4 (workstream B: shared identity and matching defects fixed before any
// per-course search; recovery routes in the mandated discovery order; never paying again for stored evidence; the D1 blocked courses as a
// persistent recovery cohort with a costed decision table; D1 stays off; root causes and remedies registered with movement-based verification).
// The behaviour runs on isolated fixtures by tests/fixtures/ops-source-recovery/run.sh (scratch PostgreSQL; workstream A's contract stubbed by its
// exact names; the three live definitions rebuilt from the repository's live files plus the edits that made them, checked against the live md5s;
// today's defects reproduced; the migration applied twice; every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104030000_cf247_ops_source_recovery.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-source-recovery'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const stub = fs.readFileSync(`${FX}/stub-ops-contract.sql`, 'utf8')
const edit = (sig) => {
  const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1)
  return m.slice(a, Math.min(...[m.indexOf(']], array[', a), m.indexOf('\n], array[', a)].filter((x) => x > 0)))
}
const after = (block) => block.split('$n$').filter((_, i) => i % 2 === 1).join('\n')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf('$function$;', a)) }

const MD5 = {
  'security.source_proof_feed_v1()': ['cade6b2de219c216709129ce4bc447ff', '87278b507bcec288603d85c22d8da105'],
  'security.course_relink_provider_v1(uuid,integer)': ['8f2f82c7e2ad360a0ade7cdee1f63cce', '776844024ca5ee99011ad73dfd36360b'],
  'security.course_relink_tick_v1(integer)': ['b159c75a0ed1517fc9305b62984aa141', '0cd20104a975c471ed4dd9060569f3b8'],
}

test('three live definitions are edited only from their live md5 and checked after; A\'s contract must land first', () => {
  for (const [sig, [b, a]] of Object.entries(MD5)) {
    expect(edit(sig)).toContain(`'${b}', '${a}'`)
    expect(m).toContain(`${b} -> ${a}`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m).toContain("raise exception 'source recovery: apply workstream A''s shared contract (migration 20261104010000) first'")
  expect(m).toContain("to_regclass('pipeline.ops_remedies') is null")
  for (const name of ['pipeline.ops_root_causes', 'pipeline.ops_remedies', 'pipeline.ops_remedy_runs', 'security.ops_root_cause_register_v1', 'security.ops_remedy_register_v1']) expect(stub).toContain(name)
})

test('shared defects first: capacity is not paid search, refused states and title forms are settings, addresses compared normalised', () => {
  const feed = after(edit('security.source_proof_feed_v1()'))
  expect(feed).toContain("when r.read_status = any (v_rl) then 'relink_wait'")
  expect(feed).toContain("case when v_route = 'relink_wait' then 'relink' else v_route end")
  expect(feed).toContain("order by coalesce(q.route = 'relink' and q.state = 'held', false) desc")
  expect(feed).toContain("and not r.stored_untried then 'search'")
  expect(feed).toContain('where v_abs and a0.resolved_at is null and a0.absence_class = any (v_abs_classes)')
  expect(feed).not.toMatch(/firecrawl|net\.http_post|openrouter/i)
  const prov = after(edit('security.course_relink_provider_v1(uuid,integer)'))
  expect(prov).toContain("p.read_status = any (security.course_relink_statuses_v1())")
  expect(prov).toContain('security.course_relink_url_norm_v1(q.url) is distinct from security.course_relink_url_norm_v1(r.old_url)')
  expect(prov).toContain('from pipeline.page_rejections pr where pr.course_id = r.course_id')
  for (const k of ['relink.slug_variants_on', 'relink.year_current_on', 'relink.stored_search_reuse_on']) expect(prov).toContain(`security.pipeline_num_v1('${k}', 0) >= 1`)
  expect(after(edit('security.course_relink_tick_v1(integer)'))).toContain('p.read_status = any (security.course_relink_statuses_v1())')
  expect(fn('security.course_relink_slugs_v1')).toContain("'\\s*\\(level [0-9]+\\)'")
  for (const k of ['S1', 'S3', 'S4', 'S6']) expect(before).toContain(`${k}`)
})

test('new routes and inputs ship off; D1 stays off; only recording and waste-stopping ship on', () => {
  expect(m).toMatch(/'relink\.statuses'[\s\S]*?'\["identity_mismatch"\]'::jsonb/)
  for (const k of ['relink.slug_variants_on', 'relink.year_current_on', 'relink.stored_search_reuse_on', 'proof.absence_input_on'])
    expect(m).toMatch(new RegExp(`'${k.replace('.', '\\.')}'[\\s\\S]*?to_jsonb\\(0\\), 0, 1, 'on/off'`))
  expect(m).toContain("raise exception 'source recovery post-check: proof.search_per_run must stay 0 (D1 off)'")
  expect(m).toContain("raise exception 'source recovery post-check: a new free route did not ship off'")
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings set value/)
})

test('the D1 cohort is persistent, read-only and fingerprinted; the decision table is measured, not assumed', () => {
  const k = fn('security.field_absence_recovery_classify_v1')
  for (const s of ['recovered_free', 'waiting_current_work', 'waiting_layer4', 'locked', 'free_route_capacity', 'free_route_refused_status', 'free_route_stored_search',
    'free_route_provider_list', 'free_route_canonical_year', 'needs_authorised_read', 'needs_paid_research', 'needs_paid_discovery']) expect(k).toContain(`'${s}'`)
  expect(k).toContain("-- inputs only: a lane's own outcome never re-triggers it")
  const r = fn('security.field_absence_recovery_refresh_v1')
  expect(r).not.toMatch(/insert into pipeline\.(course_link_search|course_relink|coverage_course_pages)|security\.course_link_bind_v1/)
  expect(m).toContain("perform cron.schedule('field-absence-recovery', '26 * * * *', $c$select security.field_absence_recovery_refresh_v1()$c$);")
  const d = fn('security.field_absence_d1_decision_v1')
  expect(d).toContain("f.use_case = 'find_page'")
  expect(d).toContain("'paid_search_enabled', security.pipeline_num_v1('proof.search_per_run', 0) > 0")
  expect(d).not.toMatch(/\b(insert into|update|delete from)\s+pipeline\./)
  for (const f of ['F1 ok', 'F2 ok', 'F3 ok', 'F4 ok', 'F5 ok', 'F8 off ok', 'F8 on ok', 'F9 ok', 'F10 ok']) expect(fixtures).toContain(f)
})

test('root causes and remedies: one auto remedy, verified by pages proven then fields filled, never by a run alone', () => {
  for (const c of ['src_proof_capacity_overflow', 'src_relink_refused_status', 'src_feed_input_gap', 'src_title_slug_match', 'src_url_normalisation',
    'src_paid_evidence_unused', 'src_handbook_year', 'src_read_blocked', 'src_page_check_rule']) expect(m).toContain(`('${c}', jsonb_build_object('class', '`)
  expect(m).toContain("'authority', 'auto', 'action_fn', 'security.field_absence_recovery_action_v1(bigint)', 'verify_fn', 'security.field_absence_recovery_verify_v1(bigint)'")
  expect((m.match(/'authority', 'auto'/g) || []).length).toBe(1)
  const v = fn('security.field_absence_recovery_verify_v1')
  expect(v).toContain("'passed', v_dp > 0 or v_df > 0")
  expect(v).toContain("'no baseline: the remedy has not run for this issue'")
  expect(fixtures).toContain('F6 ok')
  expect(fixtures).toContain('F7 ok')
})
