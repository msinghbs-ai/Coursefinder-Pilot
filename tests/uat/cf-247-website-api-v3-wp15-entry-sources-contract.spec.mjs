// Guards: Website API v3 build brief WP-1.5 (O20, REQ-28): quote and source_url on provider entry_matrix[] items and source_url on course entry.resolution.rows[], Decision 277: v3 only
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113220000_cf247_website_api_v3_entry_sources.sql', 'utf8')

test('provider entry_matrix[]: the v2 items in the v2 order, plus quote and source_url, with or without edu_country', () => {
  expect(m).toContain("'quote', m.quote, 'source_url', m.source_url)")
  expect(m).toContain('order by m.country_code, m.level_label, m.benchmark_band, m.qualification_name')
  expect(m).toContain("security.entry_matrix_payload_v3(v_pid, null)")
  expect(m).toContain("security.entry_matrix_payload_v3(v_pid, upper(btrim(p_edu_country)))")
  expect(m.match(/v := jsonb_set\(v, '\{item\}', public\.website_v3_provider_item\(v->'item'\)\);/g)).toHaveLength(2)
})

test('course entry.resolution.rows[]: source_url from the row quote (provider table for the country, else the course page); R28 kept; md5-guarded', () => {
  expect(m).toContain("m.country_code = v_cc and m.quote = r->>'quote'")
  expect(m).toContain("x.course_id = v_course and x.status = 'active' and x.quote = r->>'quote'")
  expect(m).toContain("public.website_v3_course_item_r28(v->'item')")
  for (const k of ['public.website_v3_provider(text)', 'public.website_v3_provider(text,text)', 'public.website_v3_course(text,text)'])
    expect(m).toMatch(new RegExp(`'${k.replace(/[()]/g, '\\$&')}', '[0-9a-f]{32}'`))
})
