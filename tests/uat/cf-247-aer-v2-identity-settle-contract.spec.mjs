// Guards: S1-AER Platform Admin decision 2 (13 Nov 2026; AER v2 design §10.2, F-AER.08): stored pages are bound to a course only with the page's own proof, exact heading, own host, E16 and one catalogue course; zero incorrect bindings on the 200-case fixture
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261113361500_cf247_aer_v2_identity_settle.sql', 'utf8')

test('the settle check holds anything a person decided, rejected or is to decide, and anything E16 refuses', () => {
  expect(M).toContain("return jsonb_build_object('decision', 'held', 'reason', 'manual_binding')")
  expect(M).toContain("return jsonb_build_object('decision', 'held', 'reason', 'page_rejected_before')")
  expect(M).toContain("return jsonb_build_object('decision', 'held', 'reason', 'person_course_link')")
  expect(M).toContain("v_chk := security.course_page_check_v1(g.course_id, g.url, g.page_title, g.identity_basis);")
  expect(M).toContain("if not security.coverage_identity_allowed(g.provider_id, g.identity_basis, 'official_url')")
})

test('identity comes from the page heading on the provider host, never from a code or title anywhere in the text', () => {
  expect(M).toContain("if not (v_host = any (security.provider_hosts_v1(g.provider_id)))")
  expect(M).toContain("if v_heads ~* '\\m(package|pathway)\\M'")
  expect(M).toContain("'other_code_in_heading'")
  expect(M).toContain("if v_h1 <> '' and (v_h1 like v_t || ' %' or v_h1 like v_nl || ' %') then return false; end if;")
  expect(M).toContain('if cardinality(v_parts) > 2 then return false; end if;')
  expect(M).toContain("if not v_own_code and (v_twin or v_shared) then")
})

test('binding goes through the existing trigger, every decision is recorded, the job is governed', () => {
  expect(M).toContain("update pipeline.coverage_course_pages set status = 'bound', leased_until = null where course_id = r.course_id and url = r.url and status = 'ambiguous';")
  expect(M).toContain("if v_after is distinct from 'bound' then v_dec := 'refused_by_guard'; end if;")
  expect(M).toContain("perform cron.schedule('aer-v2-identity-settle', '22,52 * * * *', 'select security.aer_v2_identity_settle_v1()');")
  expect(M).toMatch(/insert into pipeline\.automation_catalogue[\s\S]*'aer-v2-identity-settle'/)
  expect(M).toMatch(/comment on table pipeline\.aer_v2_identity_settlements/)
  expect(M).toMatch(/comment on table pipeline\.aer_v2_identity_fixture/)
  expect(M).toMatch(/^-- Replaces: /m)
  expect(M).toMatch(/^-- Retires: |Retires: nothing/m)
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})

test('the fixture has 200 stratified cases and the release fails on any incorrect binding', () => {
  const cases = M.match(/^ \('F\d{3}', 'S[1-9]', '/gm) || []
  expect(cases.length).toBe(200)
  for (const s of ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9']) expect(M).toContain(`, '${s}', '`)
  expect(M).toContain("if (v->>'incorrect_bindings')::int <> 0 then raise exception")
  expect(M).toContain("if (v->>'cases')::int <> 200 then raise exception")
})
