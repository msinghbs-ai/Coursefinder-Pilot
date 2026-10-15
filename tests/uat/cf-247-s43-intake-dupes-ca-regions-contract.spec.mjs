// CF-247 (S43): Platform Admin, 15 Oct 2026 12:31: "Bug/Fix: intake are duplicated and state is not listed for CA courses."
// Writers key a course's intakes differently, so the same month was stored twice (410 courses); a guard on the table now keeps one active
// row per course, month, year, campus and start date, whichever writer sends it. Canadian courses with no campus take the provider's province
// (setting, 14 Oct decision "keep CA"); the course detail gives the provider's country and province.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261015040000_cf247_intake_duplicates_and_ca_regions.sql', 'utf8')

test('one active intake per course and month: guard on the table, duplicates withdrawn (kept), post-check', () => {
  expect(mig).toContain('create trigger course_intake_same_month_guard before insert or update on catalogue.course_intakes')
  expect(mig).toContain("and lower(btrim(i.intake_label)) = lower(btrim(new.intake_label))")
  expect(mig).toContain("w as (update catalogue.course_intakes i set status = 'withdrawn' from d where d.id = i.id and d.rn > 1 returning i.course_id)")
  expect(mig).toContain("raise exception 'intake post-check: duplicates remain';")
})

test('provinces: from a campus, else the provider for the listed countries (setting); course detail shows the provider province', () => {
  expect(mig).toContain("('pipeline', 'search.region_from_provider_countries',")
  expect(mig).toContain("'[\"CA\"]'::jsonb")
  expect(mig).toContain("when co.iso_alpha2 = any (security.region_fallback_countries_v1()) and psd.code is not null then array[psd.code]")
  expect(mig).toContain("'subdivision_name',(select s2.name from catalogue.courses c2 join catalogue.providers p2 on p2.id=c2.provider_id join ref.subdivisions s2 on s2.id=p2.subdivision_id where c2.id=v_id),")
  expect(fs.readFileSync('src/CourseDetailPolish.jsx', 'utf8')).toContain('subtitle={[data.country_code,data.subdivision_name||data.subdivision_code].filter(Boolean).join')
})

test('md5-guarded; replaces and retires named; nothing dropped', () => {
  expect(mig).toContain("raise exception 'live % differs from the definition this change replaces', v_sig;")
  expect(mig).toMatch(/^-- Retires: search\.refresh_course_documents_v2/m)
  expect(mig.replace(/\$function\$[\s\S]*?\$function\$/g, '')).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
