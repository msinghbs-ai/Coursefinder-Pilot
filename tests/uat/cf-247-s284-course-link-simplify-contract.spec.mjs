// Guards: Platform Admin mandate 4 Nov 2026 16:32 §3 (Course Link admission, first simplification pilot), §9 (no new admission authority; a new
// automatic rule is a separate Platform Admin decision) and §10 (Course Link cases): every waiting Course Link item gets a class, group, authority,
// reason and recommendation (security.course_link_route_class_v1); the backlog is reconciled one university at a time, counting first, only under
// existing authority (supersede repeats, decided-before, already-active and retired items; Decision 179 through security.course_page_needed_convert_v1;
// Decision 263 rule items counted for the rule executor); nothing is approved or refused, no manual lock or page is touched; the settlement reasons
// never call a question about the page a course shows "already active"; a decided page is not raised again in another spelling. The behaviour runs on
// production-shaped fixtures by tests/fixtures/course-link-simplify/run.sh (scratch PostgreSQL 16; ten live definitions rebuilt from the repository
// and checked against the live md5s; the migration applied, applied again unchanged; C1 and R1-R9 asserted).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104570000_cf247_course_link_simplify.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/course-link-simplify'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')
const fn = (name) => m.slice(m.indexOf(`create or replace function security.${name}(`), m.indexOf(`revoke all on function security.${name}(`))

const EDITS = {
  'security.layer4_resolution_for_v1(uuid,text,uuid,text,jsonb,jsonb,uuid,timestamp with time zone)': ['487fc2ec6283c95c4961255a860aa9fa', 'c5ec24cb4c1be5cc8d832a6c9e89dc19'],
  'security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)': ['717fb44dd693550cb58f41a400aff455', '54070a80e26df9c7aed12deb0c50bec7'],
}

test('two live definitions are edited, md5-guarded both ways, and the fixture starts from the live text', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}', array[`)
    expect(m).toContain(`--   ${sig}`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(run).toContain('applied twice: the second run changed nothing')
  for (const sig of ['security.layer4_course_link_rule_validate_v1(text,uuid)"]=0cf77b67', 'security.course_page_needed_convert_v1(uuid,integer,boolean)"]=6c9671c6',
    'security.layer4_course_link_rule_execute_v1(text,integer,boolean)"]=cafae1b6']) expect(run).toContain(sig)
})

test('the class of one item: groups A-D with authority, plain reason, recommendation and the §3 evidence', () => {
  const c = fn('course_link_route_class_v1')
  expect(c).toContain('language plpgsql stable security definer')
  expect(c).not.toMatch(/\b(insert into|update pipeline|delete from)\b/i)
  for (const k of ['claimed', 'reopened_by_admin', 'entity_retired', 'duplicate_pending', 'decided_before', 'manual_binding', 'page_needed_d179', 'refused_page_course_has_page',
    'refusal_not_recorded', 'covered_by_active', 'rule_d263_pass', 'rule_d263_fail', 'evidence_not_linked', 'evidence_missing', 'active_page_refused', 'off_domain',
    'held_page_dispute', 'cricos_page_differs', 'old_year_address', 'record_names_other_page', 'e16_unclear']) expect(c).toContain(`'class', '${k}'`)
  for (const k of ["'official_site'", "'proposed_site'", "'course_code'", "'manual_lock'", "'proposed_refused'", "'stored_copy'", "'binding'", "'held_when_raised'", "'active_pages'"])
    expect(c).toContain(k)
  expect(c).toContain("Decision 179 (Platform Admin 3 Nov 2026 20:29; admin nz-enrichment-brief/2026-11-03-layer4-course-link-growth-review.md, decision 1)")
  expect(c).toContain("from security.layer4_course_link_rule_validate_v1(r.code, i.id) x;")
  expect(c).toContain("binding.provider_host_aliases")
  expect(c).not.toMatch(/confidence|score/i)
  expect(fixtures).toContain("raise notice 'C1 ok")
})

test('the reconciliation: one university, counting first, only existing authority, nothing decided, locks and pages untouched', () => {
  const r = fn('course_link_reconcile_v1')
  expect(r).toContain("if p_provider is null then raise exception 'one university at a time: give its provider id'")
  expect(r).toContain("if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required'")
  expect(r).toContain("continue when not coalesce(p_apply, false) or v->>'action' not in ('supersede', 'link_evidence');")
  expect(r).toContain('for update nowait;')
  expect(r).toContain("v_conv := security.course_page_needed_convert_v1(p_provider,")
  expect(r).toContain("insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)")
  expect(r).toContain("security.pipeline_num_v1('layer4.course_link_reconcile_batch', 500)")
  expect(r).not.toMatch(/layer4_review_decide_impl|(perform|:=|select) security\.layer4_course_link_rule_execute_v1|manual_locks|catalogue\.course_links|insert into pipeline\.layer4_decisions/)
  expect(m).toContain("'number', to_jsonb(500), 10, 5000, 'items', 1240, 'Layer 4 readiness', 'security.course_link_reconcile_v1'")
  for (const k of ['R1 ok', 'R2 ok', 'R3 ok', 'R4 ok', 'R6 ok', 'R7 ok']) expect(fixtures).toContain(`raise notice '${k}`)
})

test('settlement never calls a question about the shown page "already active"; a decided page is not raised again', () => {
  expect(m).toContain("if p_field = 'official_course_url' and v_key is not null and coalesce(p_l2->>'rule', '') not in ('address_year', 'e16_unclear')")
  expect(m).toContain("and not exists (select 1 from pipeline.page_rejections r where r.course_id = p_entity_id and security.layer4_url_key_v1(r.url) = v_key) then")
  expect(m).toContain("and security.layer4_url_key_v1(i.proposed_value->>'course_url') = security.layer4_url_key_v1(p_url)) then")
  for (const k of ['R5 ok', 'R8 ok', 'R9 ok']) expect(fixtures).toContain(`raise notice '${k}`)
})

test('the fixture backlog is production-shaped and nothing is switched on', () => {
  expect(seed).toContain("('d179', 'p-north', 60, 'page_needed_d179'), ('d179k', 'p-kauri', 56, 'page_needed_d179')")
  expect(seed).toContain("('h13', 'p-north', 9, 'old_year_address')")
  expect(m).not.toMatch(/update pipeline\.platform_toolset_settings/)
  expect(m).not.toMatch(/\bdrop (table|function)|delete from/i)
})
