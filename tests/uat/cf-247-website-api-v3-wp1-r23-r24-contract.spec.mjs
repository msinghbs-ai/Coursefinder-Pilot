// Guards: Website API v3 build brief WP-1.1 (R23 campus names and course counts) and WP-1.2 (R24 nationality eligibility status), Decision 277 and D-5 (Platform Admin 12 Nov 2026 21:29: "proceed"): rebuilt in website_v3_* only, never in v2
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113190000_cf247_website_api_v3_r23_r24.sql', 'utf8')

test('R23: provider campuses one per campus with campus_id, campus_name and course_count, on providers, provider and sync', () => {
  expect(m).toContain("'campus_id', k.stable_key, 'campus_name', nullif(btrim(k.name), ''), 'course_count', coalesce(n.n, 0))")
  expect(m).toContain('order by lower(nullif(btrim(k.name), \'\')) nulls last, k.stable_key')
  expect(m).toContain('(select count(*) from security.layer4_search_blocked_courses b where b.course_id = cc.course_id) = 0')
  expect(m).toContain('jsonb_agg(public.website_v3_provider_item(x) order by o)')
  expect(m.match(/v := jsonb_set\(v, '\{item\}', public\.website_v3_provider_item\(v->'item'\)\)/g)).toHaveLength(2)
  expect(m).toContain("when x->>'entity' = 'provider' then jsonb_set(x, '{item}', public.website_v3_provider_item(x->'item'))")
})

test('R24: nationality_eligibility_status in order under_review, restricted, unrestricted, unknown; an empty list is never unrestricted', () => {
  const at = (s) => m.indexOf(s)
  expect(at("then 'under_review'")).toBeGreaterThan(0)
  expect(at("then 'under_review'")).toBeLessThan(at("then 'restricted'"))
  expect(at("then 'restricted'")).toBeLessThan(at("then 'unrestricted'"))
  expect(at("then 'unrestricted'")).toBeLessThan(at("else 'unknown' end"))
  expect(m).toContain("cardinality(nr.codes) = 0 and nr.phrases ? 'ANY'")
  expect(m).toContain("r.field_code in ('nationalities', 'nationality', 'citizenship_eligibility', 'audience', 'student_type')")
  expect(m).toContain("when x->>'entity' = 'scholarship' then jsonb_set(x, '{item}', public.website_v3_scholarship_item(x->'item'))")
})

test('only the v3 wrappers are replaced, md5-guarded, and R28 on course sync items is kept', () => {
  for (const k of ['public.website_v3_providers(jsonb,integer,integer,text)', 'public.website_v3_provider(text)', 'public.website_v3_provider(text,text)',
    'public.website_v3_scholarships(jsonb,integer,integer)', 'public.website_v3_scholarship(text)', 'public.website_v3_sync(text,boolean,text[],integer)'])
    expect(m).toMatch(new RegExp(`'${k.replace(/[()[\]]/g, '\\$&')}', '[0-9a-f]{32}'`))
  expect(m).not.toContain('@@')
  expect(m).toContain("when x->>'entity' = 'course' then jsonb_set(x, '{item}', public.website_v3_course_item_r28(x->'item'))")
  expect(m).not.toMatch(/create\s+or\s+replace\s+function\s+(public\.)?(website_v2_|zoho_)/i)
})
