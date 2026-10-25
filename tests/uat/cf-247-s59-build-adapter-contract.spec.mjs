// Guards: CF-247 (S59) Decision 267: Build adapter, one click per university (Platform Admin 17 Oct 18:56;
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
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.[3-9]\d\.\d+";/)
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

const fix2 = fs.readFileSync('supabase/migrations/20261018090000_cf247_build_admit_approvals_and_campus.sql', 'utf8')
test('first wave fix 2: approvals made once at admit; campus agrees only with the university\'s own campuses', () => {
  expect(fix2).toContain("<> '3d301d9c786776704868a183f8c478bb' then")
  expect(fix2).toContain("<> '96fda6f52cbd77022ec0b1346c015ea9' then")
  expect(fix2).toContain("'CF-CHG-20260915-247; Decision 267 (Build adapter: a Platform Admin admits Ready fields)', now(), now(), now()")
  expect(fix2).toContain('        on conflict do nothing;\n        perform public.admin_uni_adapter_control(\'admit\'')
  expect(fix2).toContain("readings name no campus the university has")
  expect(fix2).not.toMatch(/^(delete|drop|truncate)\b/im)
  expect(fix2).not.toMatch(/create\s+or\s+replace\s+function\s+security\.coverage_admission/i) // the admit jobs are unchanged
})

const fix3 = fs.readFileSync('supabase/migrations/20261018100000_cf247_enrich_reads_page_reading.sql', 'utf8')
test('follow-up 3: Enrichment reads the current page reading first; admit releases only holds the page reading now answers', () => {
  expect(fix3).toContain("<> '3428eef302a7086bb045ddc683ca41ba' then")
  expect(fix3).toContain("if md5(d) <> '03cc5526a082f59867a8313cdefa04fd' then")
  expect(fix3).toContain("if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then")
  expect(fix3).toContain("release_reason = 'Build adapter: the course page reading now gives a value (Decision 267)'")
  expect(fix3).toContain("where f.entity = 'course' and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting')")
  expect(fix3).not.toMatch(/^(delete|drop|truncate)\b/im)
})

const fix4 = fs.readFileSync('supabase/migrations/20261018110000_cf247_build_readiness_fee_check_english.sql', 'utf8')
test('follow-up 4: readiness uses the admit fee cross-check and counts any English requirement as held', () => {
  expect(fix4).toContain("<> '178b0fdbbb3ed2b359d612de7a2f5a47' then")
  expect(fix4).toContain("security.pipeline_num_v1('admit.fee_crosscheck_pct', 25)")
  expect(fix4).toContain("exists (select 1 from catalogue.course_english_requirements e2 where e2.course_id = pg.course_id and e2.status = 'active') held")
  expect(fix4).not.toMatch(/create\s+or\s+replace\s+function\s+security\.(fee_crosscheck_guard_v1|coverage_admission)/i)
  expect(fix4).not.toMatch(/^(delete|drop|truncate)\b/im)
})
