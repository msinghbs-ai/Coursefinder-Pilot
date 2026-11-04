// Guards: Platform Admin direction 4 Nov 2026 10:00 §1-§2 (IQ-00264): classified scholarship cases one decision from publication reach a Layer 4
// reviewer (lane sch_value), decided refusals keep an explicit disposition, nothing is duplicated, a failing provider never stops the others,
// a reviewer's value is applied only as that reviewer's own locked edit, and publication is verified through the consumer read-back. The behaviour
// runs on isolated fixtures by tests/fixtures/sch-l4-handoff/run.sh (scratch PostgreSQL 16; the released coverage and human-assisted recovery
// migrations loaded as on main; every called or edited definition checked against its live md5; the defects reproduced first; the migration
// applied twice). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104480000_cf247_sch_l4_handoff.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/sch-l4-handoff'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')

test('one md5-guarded edit of the case classification; every called definition is checked against live', () => {
  expect(m).toContain("select pg_temp.edit_once('security.scholarship_coverage_items_v1(uuid[])', 'd3dfacf0e70fd33162eab7a57aca72e4', '5605660603d40b3917001c37807a09bb'")
  for (const [sig, h] of [['security.layer4_intervention_raise_v1(jsonb)', '8fcabf1137cf126158c260759ac9f9aa'], ['security.layer4_intervention_resolve_v1(bigint,text,jsonb)', '1385d22605acc549b545beb4f6a7d312'],
    ['security.layer4_interventions_tick_v1()', 'da2aaf0fd207edf4c36a55a8e2172424'], ['security.scholarship_publishability_for_v1(uuid[])', 'd8123efd7e6e0d36fb6ebe9c8d38fdf7'],
    ['public.admin_scholarship_edit(uuid,text,jsonb)', '0147553263d5a1b8795a0b31ebf11019']]) {
    expect(m).toContain(`('${sig}', '${h}')`)
    expect(run).toContain(`]=${h}`)
  }
  // the live-only Curator edit route is transcribed from production and proved by its md5
  expect(md5(fs.readFileSync(`${FX}/live/public.admin_scholarship_edit.def`, 'utf8'))).toBe('0147553263d5a1b8795a0b31ebf11019')
  expect(md5(fs.readFileSync(`${FX}/live/security.scholarship_publishability_for_v1.def`, 'utf8'))).toBe('d8123efd7e6e0d36fb6ebe9c8d38fdf7')
  expect(run).toContain('["public.admin_scholarship_edit(uuid,text,jsonb)"]=0147553263d5a1b8795a0b31ebf11019')
})

test('the hand-off: value-only cases of admission-eligible providers, read pages, no lock, no waiting decision; one per case; isolated per provider', () => {
  expect(m).toContain(`x.state = 'admitted_not_published' and x.evidence->'missing' = '["no stated award value"]'::jsonb`)
  expect(m).toContain('coalesce(security.scholarship_admission_provider_ok_v1(x.provider_id), false)')
  expect(m).toContain("and sp.read_status = 'read'")
  expect(m).toContain("not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id")
  expect(m).toContain("not exists (select 1 from pipeline.scholarship_ai_reviews rv where rv.scholarship_id = s.id and rv.status = 'pending')")
  expect(m).toContain("i.closed_fingerprint = md5('sch_value_missing|' || c2.sig)")
  expect(m).toMatch(/exception when others then\s+v_err := v_err \+ 1; v_last := left\(r\.entity/)
  // its own lane, so the full scholarship coverage lane never starves it
  expect(m).toContain("('sch_value', 'Scholarships: award value for publication', 'security.har_sch_value_validate_v1(bigint,text,jsonb)'")
})

test('decided cases keep an explicit disposition; the failing checks are on the case', () => {
  expect(m).toContain("h.held_by = 'admin'")
  expect(m).toContain("(h.reason ~* '^Refused in Layer 4' or h.reason ~* '^Prize or award, not a scholarship')")
  expect(m).toContain("v.status = 'not_published') then 'rejected_correctly'")
  expect(m).toContain("'publishing checks: ' || array_to_string(x.missing, '; ')")
})

test("a reviewer's value is that reviewer's locked edit through the Curator route; publication is verified by the consumer read-back", () => {
  expect(m).toContain("v := public.admin_scholarship_edit(v_sid, 'set_core'")
  expect(m).toContain("security.pipeline_num_v1('sch_cov.value_apply_on', 1) < 1")
  expect(m).toContain("api.website_v2_scholarship_item(v_sid) is not null then")
  expect(m).toContain("'outcome', 'published_consumer_verified', 'admitted', true, 'published', true")
  expect(m).not.toMatch(/publication_status\s*=\s*'published'\s*,|scholarship_ai_apply_v1|layer4_review_items\s+set/)
})

test('the fixture reproduces the defects and asserts every required proof', () => {
  for (const s of ['before: an admitted scholarship held only by its award value (S1) gets no review', 'before: a scholarship a person refused in Layer 4 (S2)']) expect(before).toContain(s)
  for (const s of ['S1: one "Human input needed" item', 'S9 (TAFE Queensland, outside the admission policy) keeps an explicit, evidence-backed disposition',
    'a further tick creates nothing: no duplicate', 'a failing provider (Southern Cross, first in order) is counted and the others still progress',
    'the next stage ran unattended: published, read back through the consumer API, verified', 'never asked again',
    'switch off: the value is kept as a proposal only', 'the waiting Layer 4 decision (S4) is untouched']) expect(fixtures).toContain(s)
  expect(run).toContain("grep -c ': applied$')\" = 1")
  expect(run).toContain("grep -c ': already applied$')\" = 1")
})
