// CF-247 (S59) Decision 267: Build adapter, one click per university (Platform Admin 17 Oct 18:56; 18 Oct 11:58 and 12:43).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261018070000_cf247_build_adapter.sql', 'utf8')
const adapters = fs.readFileSync('supabase/functions/coverage-sweep/adapters.ts', 'utf8')
const builder = fs.readFileSync('supabase/functions/coverage-sweep/builder.ts', 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('guarded, nothing dropped, the consumer API untouched and checked after', () => {
  expect(mig).toContain("<> 'c51ffc49c0cbfd1590cf02061c44645e' then")
  expect(mig).not.toMatch(/^(delete|drop|truncate)\b/im)
  expect(mig).toContain("v_drift := security.consumer_api_check_v1()->'drift';")
  expect(mig).not.toMatch(/create\s+or\s+replace\s+function\s+(public\.)?(website_|zoho_|api\.)/i)
  expect(mig.indexOf("('adapter-build-readiness', 'Course pages'")).toBeLessThan(mig.indexOf("cron.schedule('adapter-build-readiness'"))
  expect(mig).toMatch(/comment on table catalogue\.course_specialisations/)
  expect(mig).toMatch(/comment on table pipeline\.adapter_builds/)
})

test('eight fields; Ready needs the read share and the agreement share the qualify settings give', () => {
  expect(mig).toContain("unnest(array['intakes', 'fee', 'english', 'delivery', 'duration', 'campus', 'study_level', 'majors'])")
  expect(mig).toContain("security.firecrawl_setting('eval_field_share')")
  expect(mig).toContain("security.firecrawl_setting('qualify_agree_share')")
  expect(mig).toContain("security.pipeline_num_v1('build.duration_tolerance_years', 0.25)")
  expect(mig).toContain("elsif v_share < v_min_read then v_state := 'review'")
})

test('one click admits only Ready fields, through the existing routes, by a Platform Admin with a reason', () => {
  expect(mig).toContain("if v_rank < 6 then raise exception 'Platform Admin required'")
  expect(mig).toContain("-- only Ready fields are admitted, whatever was asked")
  expect(mig).toContain("perform public.admin_uni_adapter_control('admit'")
  expect(mig).toContain("v_job := public.admin_enrich_fields('start'")
  expect(mig).toContain("v_m := security.adapter_build_admit_majors_v1(p);")
  expect(mig).toContain("perform public.admin_provider_onboarding('retry'")
  expect(mig).toContain("perform public.admin_provider_onboarding('start'")
})

test('worker v0.30.0 reads majors as a pattern field (every match kept)', () => {
  expect(adapters).toMatch(/EXTRA_FIELDS = \[[^\]]*"majors"\]/)
  expect(builder).toMatch(/PATTERN_FIELDS = \[[^\]]*"majors"\]/)
  expect(builder).toContain('for majors capture one major or specialisation name per match and set pick "all"')
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.30\.\d+";/)
  expect(mig).toContain("'english_level', 'majors']")
})

const fix = fs.readFileSync('supabase/migrations/20261018080000_cf247_build_readiness_active_courses.sql', 'utf8')
test('first wave fix: readiness is measured on active courses only; qualification and admission unchanged', () => {
  expect(fix).toContain("<> '602d5ab6df40864d987cec1d8dd8b701' then")
  expect(fix).toContain("join catalogue.courses c0 on c0.id = pg.course_id and c0.lifecycle_status = 'active'")
  expect(fix).not.toMatch(/create\s+or\s+replace\s+function\s+security\.adapter_qualify_one_v1/i)
  expect(fix).not.toMatch(/^(delete|drop|truncate)\b/im)
  expect(fix).toContain("v := security.consumer_api_check_v1()->'drift';")
})
