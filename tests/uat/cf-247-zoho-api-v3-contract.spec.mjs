// Guards: Zoho API v3 (Decision 277; S2-CF directive, Platform Admin 13 Nov 2026 10:25, section 3; register Z1 and Z4): a separate copy beside Zoho v2 built on the live Website v3, with no dispatcher and no release gate; Zoho v2 and Website v2 are only read
import fs from 'node:fs'
import { test, expect } from '@playwright/test'

const M = fs.readFileSync('supabase/migrations/20261113290000_cf247_zoho_api_v3.sql', 'utf8')
const V3 = fs.readFileSync('supabase/functions/zoho-api-v3/index.ts', 'utf8')
const V2 = fs.readFileSync('supabase/functions/zoho-api-v2/index.ts', 'utf8')
const EDGE = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8'))

test('the migration only adds public.zoho_v3_* functions: nothing of v2 is created, altered or dropped, no setting, no gate, no dispatcher', () => {
  const made = [...M.matchAll(/create or replace function ([a-z_.0-9]+)\(/g)].map((m) => m[1])
  expect(made.length).toBe(14)
  for (const f of made) expect(f).toMatch(/^public\.zoho_v3_/)
  expect(M).not.toMatch(/\b(drop|alter|delete|truncate)\b/i)
  expect(M).not.toMatch(/platform_toolset_settings\s*\(|update pipeline\.platform_toolset_settings|v3_released|zoho_v3_call|website_v3_call|create schema/i)
  // every function is closed to public, anon and authenticated and open to the service role only
  expect(M).toContain("execute format('revoke all on function %s from public, anon, authenticated', f);")
  expect(M).toContain("execute format('grant execute on function %s to service_role', f);")
  for (const f of made) expect(M).toContain(`'${f}(`)
  expect(M).toContain('-- Replaces: nothing.')
})

test('search, course, courses and the scholarship actions carry the v3 additions; the other actions are the v2 answer', () => {
  expect(M).toContain("public.website_v3_course_search_item(it.x) || jsonb_build_object('scholarships_top', coalesce(tp.top, '[]'::jsonb))")
  expect(M).toContain('declare v jsonb := public.zoho_v2_course_search(p_filters, p_page, p_page_size, p_sort);')
  // Z1: published scholarships only, not blocked, first five, and the amount rule is checked against the scholarship item when applied
  expect(M).toContain("s.lifecycle_status = 'active' and s.publication_status = 'published'")
  expect(M).toContain('where s.id not in (select b.scholarship_id from blocked b)')
  expect(M).toContain("raise exception 'post-check: the scholarship summary differs from the scholarship item'")
  // Z4: edu_country goes through the Website v3 course (which refuses an unknown country) and only replaces entry
  expect(M).toContain('w := public.website_v3_course(p_identifier, p_edu_country);')
  expect(M).toContain("if w #> '{item,entry}' is not null and w #>> '{item,course_id}' = v #>> '{item,course_id}' then v := jsonb_set(v, '{item,entry}', w #> '{item,entry}'); end if;")
  for (const a of ['website_v3_rankings', 'website_v3_scholarships', 'website_v3_scholarship']) expect(M).toContain(`public.${a}(`)
  for (const a of ['reference()', 'providers(p_filters, p_page, p_page_size, p_sort)', 'provider(p_identifier)', 'list(p_entity, p_filters, p_page, p_page_size)', 'statistics(p_kind, p_filters, p_page, p_page_size)',
    'report(p_body)', 'report_status(p_flag_ids)', 'sync(p_cursor, p_full, p_entities, p_page_size)', 'export_page(p_entity, p_page)']) expect(M).toContain(`$$ select public.zoho_v2_${a} $$`)
})

test('zoho-api-v3 is zoho-api-v2 with the v3 function names: same keys, rate limit and log, every v2 action, no release refusal', () => {
  const norm = (s) => s.slice(s.indexOf('import "jsr:')).split('\n')
  const a = norm(V2), b = norm(V3)
  const changed = b.filter((l) => !a.includes(l))
  // only the lines that name a v3 function, the version label, the log label, edu_country and the linked-course paging differ
  expect(changed.length).toBeLessThanOrEqual(22)
  for (const l of changed) expect(l).toMatch(/zoho_v3_|zoho-v3|v3:\$\{action\}|edu_country|zoho_api_v3_error/)
  expect(V3).toContain('svc.rpc("zoho_v2_auth"'); expect(V3).toContain('svc.rpc("zoho_v2_rate"'); expect(V3).toContain('svc.rpc("zoho_v2_log"')
  expect(V3).toContain('p_action: action ? `v3:${action}` : action')
  expect(V3.match(/const ACTIONS = \[[^\]]+\]/)[0]).toBe(V2.match(/const ACTIONS = \[[^\]]+\]/)[0])
  expect(V3).not.toMatch(/NOT_RELEASED|zoho_v3_call/)
  expect(V3).not.toMatch(/fn = "zoho_v2_/)
  expect(EDGE.functions['zoho-api-v3']).toBe(EDGE.functions['zoho-api-v2'])
  // the frozen v2 function is not part of this change (its baseline is guarded by s57)
  expect(V2).toContain('const API_VERSION = "zoho-v2";')
})
