// Guards: CF-247 Layer 4 course link (Platform Admin mandate 3 Nov 2026 20:47 §5-§6; Decision 179 for refused pages with no held page, 3 Nov
// 2026 20:29; Decision 263 rule validation): stored copies are linked to course-link and fee cards without a read; a refused page of a course
// with no held page goes to one Course page needed list (grouped by university; add the page, search again, no page exists) and its waiting
// items move there with their history; Refuse this proposal claims no held page; a held scholarship can be closed as a duplicate of a named
// published one; the CRICOS wording is for Australian providers only; the approved university rules are validated per item and executed
// item by item only by the rule executor, through the existing decision path. The behaviour runs on isolated fixtures by tests/fixtures/l4-course-link/run.sh (scratch PostgreSQL; the four edited live definitions
// rebuilt from the repository and checked against the live md5s; the migration applied, applied again unchanged; every case asserted).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104260000_cf247_l4_course_link.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/l4-course-link'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const ui = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')

const EDITS = {
  'security.layer4_inbox_kinds_v1()': ['f5fc812e0971a415b664926ec5dbdf8c', 'e79ce1815952b4a0e59108981bf62c36'],
  'security.layer4_inbox_items_v1()': ['a56bc3313e02ac0611deb5657da95ce0', '4fc05d14f4ba49335ff90496a20f582d'],
  'public.admin_layer4_inbox(text,jsonb)': ['f1f0d760b682d6d132af0e8b55151292', '1fb975482d29c7c9f1ecdf3cdb011a10'],
  'security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)': ['488ef1836fa2ba842009168b9e499d73', '717fb44dd693550cb58f41a400aff455'],
}

test('four live definitions are edited, md5-guarded both ways, and the fixture starts from the live text', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}', array[`)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(m).not.toMatch(/edit_once\('security\.(layer4_review_decide_impl|layer4_course_link_apply_impl|coverage_admission_apply_v1)/)
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('stored copies: linked on arrival and by an audited backfill, never by a read; fee cards show the bound page copy', () => {
  expect(m).toContain('create trigger layer4_review_items_zz_evidence before insert on pipeline.layer4_review_items')
  expect(m).toContain("'list', '[\"official_course_url\", \"provider_current_tuition_validation\", \"provider_current_tuition\"]'::jsonb")
  expect(m).toContain("update pipeline.layer4_review_items set evidence_id = v_ev where id = r.id and status = 'pending' and evidence_id is null;")
  expect(m).toContain("values ('layer4', 'evidence_backfill', 'pipeline.layer4_review_items'")
  expect(m).toContain("'evidence_id', g.evidence_id, 'captured_at', gev.captured_at, 'source_url', gev.source_url)")
  for (const k of ['E1 ok', 'E2 ok', 'E3 ok']) expect(fixtures).toContain(`raise notice '${k}`)
})

test('Course page needed (Decision 179): refusals with no held page join one list; existing items move with history; disputes stay', () => {
  expect(m).toContain("if security.pipeline_num_v1('layer4.page_needed_on', 1) >= 1")
  expect(m).toContain("and not exists (select 1 from catalogue.course_links l where l.course_id = p_course and l.link_type = 'official_course' and l.status = 'active') then")
  expect(m).toContain("when r.claimed_at is not null or r.assigned_to is not null then 'claimed_by_reviewer'")
  expect(m).toContain("'held_page_when_raised'")
  expect(m).toContain("update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),")
  expect(m).toContain("if p_provider is null then raise exception 'one university at a time: give its provider id'")
  expect(m).toContain('"course_page_needed": {"label": "Course page needed", "order": 19, "choices": [')
  expect(m).toContain("v_r := public.admin_course_edit(p_course, 'set_official_url'")
  expect(m).toContain("insert into pipeline.course_no_page as x(course_id, provider_id, kind, state, basis, decided_at, updated_at)")
  expect(m).toContain("security.pipeline_num_v1('layer4.page_needed_search_max', 3)")
  expect(m).not.toMatch(/delete from|drop (table|function)/i)
  for (const k of ['P1 ok', 'P2 ok', 'P3 ok']) expect(fixtures).toContain(`raise notice '${k}`)
})

test('review controls: course link keeps its three choices and adds an honest refuse; held scholarship adds the duplicate route', () => {
  expect(m).toContain('{"key": "refuse", "label": "Refuse this proposal"')
  expect(m).toContain('{"key": "duplicate", "label": "Duplicate of a published scholarship", "input": "scholarship"')
  expect(m).toContain("v_r := security.layer4_course_link_refuse_v1(v_ref::uuid, v_reason);")
  expect(m).toContain("raise exception 'this item is a fee, not a proposed page: use its own choices'")
  expect(m).toContain("s.publication_status = 'published' and s.lifecycle_status = 'active' and s.provider_id = r.provider_id")
  expect(ui).toContain(".filter(c=>!((fee||feeCheck)&&c.key==='refuse'))")
  expect(ui).toContain("open.input==='scholarship'&&<input")
  expect(fixtures).toContain('K1 ok: course link keeps keep/use/enter word for word')
  for (const k of ['R1 ok', 'D1 ok']) expect(fixtures).toContain(`raise notice '${k}`)
})

test('wording: no CRICOS code is named for a provider outside Australia', () => {
  expect(m).toContain("case when coalesce(kc.iso_alpha2, 'AU') <> 'AU' and r.escalation_reason ilike '%CRICOS%'")
  expect(ui).toContain('{d.code_label||"CRICOS"} {d.course_code}')
  expect(fixtures).toContain('W1 ok')
})

test('the rule executor: item by item through the existing decision path, validated again at execution, owners respected, failures stay waiting', () => {
  const x = m.slice(m.indexOf('create or replace function security.layer4_course_link_rule_execute_v1'), m.indexOf('revoke all on function security.layer4_course_link_rule_execute_v1'))
  expect(x).toContain("v_res := security.layer4_review_decide_impl(v.item_id, case r.choice when 'keep' then 'reject' else 'approve' end, v_reason, null);")
  expect(x).toContain('for update nowait;')
  expect(x).toContain('from security.layer4_course_link_rule_validate_v1(r.code, v.item_id) x;')
  expect(x).toContain("perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);")
  expect(x).toContain("v_reason := left(format('[rule %s] %s. %s: %s. Approved by %s (%s)'")
  expect(x).toContain("if v_caller is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required'")
  expect(x).not.toMatch(/insert into pipeline\.layer4_decisions|update pipeline\.layer4_review_items|manual_locks/)
  expect(m).toContain("'university owned by the parallel reviewer (ownership register)'")
  expect(m).toContain("'no ownership row for the Integration Controller (ownership register)'")
  expect(m).toContain("case when m.strict then security.course_page_check_v1(m.course_id, m.target_url) end chk")
  expect(m).toMatch(/\('sfu_no_term'[\s\S]*?array\['field_award'\], 59,[\s\S]*?D2 \(field-and-award matches with identity, current evidence and course level verified\)', true,/)
  expect(run).toContain('["security.layer4_review_decide_impl(uuid,text,text,jsonb)"]=55353f1903c97b268255c8c1e4f5ca6f')
  for (const k of ['X0 ok', 'X1 ok', 'X2 ok', 'X3 ok', 'X4 ok']) expect(fixtures).toContain(`raise notice '${k}`)
})

test('approved university rules are validated per item; search spend is measured against refusals', () => {
  for (const code of ['adelaide_keep_held', 'canberra_no_year', 'sfu_no_term']) expect(m).toContain(`('${code}', `)
  expect(m).toContain('returns table(rule text, item_id uuid, course_id uuid, course_code text, choice text, held_url text, proposed_url text, target_url text, pass boolean, reasons text[], detail jsonb)')
  const v = m.slice(m.indexOf('create or replace function security.layer4_course_link_rule_validate_v1'), m.indexOf('revoke all on function security.layer4_course_link_rule_validate_v1(text, uuid)'))
  expect(v).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(v).toContain("'manual lock on the official page'")
  expect(m).toContain("'list', '[\"firecrawl_search=fc_search\", \"cricos_search=course_link_search\", \"title_search=course_link_search\"]'::jsonb")
  for (const k of ['V1 ok', 'C1 ok', 'Z1 ok']) expect(fixtures).toContain(`raise notice '${k}`)
})
