// Guards: CF-247 gate hotfix (Platform Admin 26 Oct 2026 19:27): adapter-written fees pass through the same tuition identity check as every other path
// Found: Swinburne 087852C's 2027 fee was written live by security.adapter_overwrite_v1 through svc_coursefacts_apply_record, past R1's check
// in coverage_apply_course_v1. The gate now sits at the table (one trigger for every writer) and the adapter's fee branch checks first.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261026006000_cf247_fee_identity_gate_all_writers.sql', 'utf8')
const tg = m.slice(m.indexOf('create or replace function security.course_fee_identity_gate_tg()'), m.indexOf('comment on function security.course_fee_identity_gate_tg()'))

test('one gate at the table: a trigger on catalogue.course_fees for every writer, before insert or update', () => {
  expect(m).toContain('create trigger course_fee_identity_gate before insert or update on catalogue.course_fees')
  expect(m).toContain('for each row execute function security.course_fee_identity_gate_tg();')
  expect(tg).toContain("not security.coverage_identity_allowed(c.provider_id, p.identity_basis, 'tuition')")
  expect(tg).toContain("new.status := 'unverified';")
  expect(tg).toContain("'source', 'identity_basis_reverify', 'state', 'quarantined'")
  // the only exemptions: a person's own write and the manual-edit flag; no writer is named, so none can be left out
  expect(tg).toContain("if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;")
  expect(tg).not.toMatch(/adapter|coursefacts|fee_rule|schedule/i)
  expect(tg).toContain("security.pipeline_num_v1('fees.identity_gate_on', 1)")
  expect(m).toContain("('pipeline', 'fees.identity_gate_on', ")
})

test('the adapter fee branch checks tuition identity before it supersedes anything (md5-guarded)', () => {
  expect(m).toContain("pg_temp.edit_n('security.adapter_overwrite_v1(integer)', 'c96ca02c38878da034758b637abf60a8'")
  expect(m).toMatch(/and security\.coverage_identity_allowed\(r\.provider_id, r\.ib, 'tuition'\)\n\s+and \(\('fee' = any \(r\.af\) and r\.adm\)/)
  expect(m).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
