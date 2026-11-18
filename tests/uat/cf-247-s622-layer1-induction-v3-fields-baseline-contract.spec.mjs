// Guards: Layer 1 induction backend supports the API v3 fields and baseline records for a new country source (Platform Admin 18 Nov 2026 10:31: study_load, empty_reason_code, provider_accreditations, campuses.is_primary, grade_scale_conversions; "allows creating/seeding new baseline records when onboarding a new country source"): the targets are extended md5-guarded, the apply step fills only what is not held (never overwrites, publishes or deletes; grade scales load inactive), and the runner calls it only inside an apply run.
// CF-247 S622. supabase/migrations-archive/20261118124000_cf247_layer1_induction_v3_fields_baseline.sql; supabase/functions/layer1-declarative-runner/index.ts 1.1.0.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118124000_cf247_layer1_induction_v3_fields_baseline.sql', 'utf8')
const R = fs.readFileSync('supabase/functions/layer1-declarative-runner/index.ts', 'utf8')

test('targets and record types are extended from the live definitions, md5-guarded', () => {
  expect(M).toContain("if md5(v_src) <> '1460dc3b35db43c51d77b1d6d912c215' then raise exception")
  expect(M).toContain("if md5(v_src) <> 'ea669f7005430039e17316c7111c5697' then raise exception")
  expect(M).toContain("'{course_register,fields,study_load}', jsonb_build_object('type', 'text')")
  expect(M).toContain("'{course_register,fields,empty_reason_code}', jsonb_build_object('type', 'code')")
  for (const t of ['provider_accreditations', 'campuses', 'grade_scale_conversions']) expect(M).toContain(`'${t}', jsonb_build_object('target_table',`)
  expect(M).toContain("'is_primary', jsonb_build_object('type', 'boolean')")
  expect(M).toContain("raise exception 'post-check: the register apply step is unchanged'")
  expect(M).toMatch(/-- Replaces: nothing/)
  expect(M).toMatch(/-- Retires: nothing\./)
})

test('the apply step fills only what is not held and never overwrites, publishes or deletes', () => {
  expect(M).toContain("where id = v_course and study_load is null;")
  expect(M).toContain("study_load_source = 'register'")
  expect(M).toContain("where id = v_course and empty_reason_code is null;")
  expect(M).toContain("if exists (select 1 from catalogue.campuses c where c.provider_id = v_provider and lower(btrim(c.name)) = lower(v_name)) then c_existing := c_existing + 1; continue; end if;")
  expect(M).toContain("and not exists (select 1 from catalogue.campuses c where c.provider_id = v_provider and c.is_primary);")
  expect(M).toContain("'active', 'unpublished', p_source_id, p_evidence_id, now(), v_primary,")
  expect(M).toContain("if exists (select 1 from catalogue.provider_accreditations a where a.provider_id = v_provider and a.body_code = v_body) then c_existing := c_existing + 1; continue; end if;")
  expect(M).toContain("(r->>'normalized_0_100')::numeric, false, r->>'source_url', 'Layer 1 source '")
  expect(M).toContain("if v_provider is null then c_no_provider := c_no_provider + 1; continue; end if;")
  expect(M).toContain("if v_country is null then raise exception 'country seed missing: %', p_country_code; end if;")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/publication_status\s*=\s*'published'/)
  expect(M).toContain('grant execute on function public.svc_layer1_apply_baseline_records_v1(text, text, uuid, uuid, text, jsonb) to service_role;')
})

test('the runner applies baseline records only in an apply run, with the unchanged gates', () => {
  expect(R).toContain('const VERSION = "1.1.0";')
  expect(R).toContain('const BASELINE_FN = "public.svc_layer1_apply_baseline_records_v1";')
  expect(R).toContain('const isApplied = (t: any) => t?.apply === APPLY_FN || t?.apply === BASELINE_FN;')
  expect(R).toContain('if (applied && !scheme && recordType !== "grade_scale_conversions") return fail(')
  expect(R).toContain('const extras = recordType === "course_register" ? courseExtras(part2) : [];')
  expect(R).toContain('if (p.terms_status !== "approved") return fail(')
  expect(R).toContain('if (!ops?.active || ops?.paused) return fail(')
  const apply = R.slice(R.indexOf('async function applyRun'))
  expect(apply).toContain('"svc_layer1_apply_baseline_records_v1"')
  expect(R.slice(0, R.indexOf('async function applyRun'))).not.toContain('"svc_layer1_apply_baseline_records_v1"')
})
