// Guards: StudySearch transformation finding F1 (Platform Admin mandate 31 Oct 2026 10:23; admin 2026-10-31-studysearch-transformation.md §7): scheduled pipeline functions evaluate provider-level checks once per provider (a materialised list), never once per course, AI-match row or flag; same rules and writes; time-outs and schedules unchanged; consumer API untouched
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261031010000_cf247_f1_provider_checks_once.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('md5-guarded edits of exactly the two functions, before and after values pinned', () => {
  expect(m).toContain("select pg_temp.edit_once('security.enrichment_flags_refresh_v1()', 'ae5776259a0e5d35478494731cbcc75b', '3bbec96c35136e885e29885d145dd3b7', array[")
  expect(m).toContain("select pg_temp.edit_once('security.coverage_ai_match_prepare_v1(integer,integer)', 'b7db293ca3f9ff521976bb074ed3a85e', 'ab2dd5dc2e897b20c9de8bbc84bd26eb', array[")
  expect(code(m).match(/select pg_temp\.edit_once\(/g)).toHaveLength(2)
  expect(m).toContain('-- Replaces: security.enrichment_flags_refresh_v1, security.coverage_ai_match_prepare_v1')
  expect(m).toContain('-- Retires: nothing')
})

test('each provider check runs over a materialised list of distinct providers; the planner cannot push it back to every row', () => {
  const added = [...m.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map(x => x[1]).join('\n')
  // every new check sits on a materialised distinct-provider list
  expect(added.match(/pv as materialized \(select distinct/g)).toHaveLength(5)
  for (const f of ['enrich_focus_v1(pv.pid)', 'course_search_off_v1(pv.pid)', 'course_list_read_v1(pv.pid)', 'bind_match_scope_v1(pv.pid)']) expect(added).toContain(f)
  // no per-row provider check is introduced
  expect(added).not.toMatch(/(enrich_focus_v1|course_search_off_v1|course_list_read_v1|bind_match_scope_v1)\((d|q|co)\.provider_id\)/)
  // a flag with no provider keeps exactly the per-row check (null behaviour unchanged)
  expect(added).toContain('case when f.provider_id is null then security.enrich_focus_v1(f.provider_id) else f.provider_id in (select fp.pid from fp) end')
  expect(added).toContain('case when f.provider_id is null then security.course_search_off_v1(f.provider_id) else f.provider_id in (select so.pid from so) end')
  // and the post-check refuses a per-row check left behind
  expect(m).toContain("raise exception 'F1 post-check: a per-row provider check is left in coverage_ai_match_prepare_v1'")
})

test('same truth table: a negated check stays negated, a positive check stays positive', () => {
  const pairs = [...m.matchAll(/array\[\$o\$([\s\S]*?)\$o\$,\s*\$n\$([\s\S]*?)\$n\$\]/g)].map(x => [x[1], x[2]])
  expect(pairs).toHaveLength(8)
  const [, , clearFocus, , , clearOff] = pairs
  expect(pairs[0][1]).toContain('where not security.enrich_focus_v1(pv.pid)')          // outside focus: providers NOT in focus
  expect(clearFocus[1]).toContain('where security.enrich_focus_v1(pv.pid)')              // clearing: providers now in focus
  expect(pairs[3][1]).toContain('where not security.course_search_off_v1(pv.pid)')      // page not found: search NOT off
  expect(clearOff[1]).toContain('where security.course_search_off_v1(pv.pid)')           // clearing: search off
  expect(pairs[6][1]).toMatch(/where security\.enrich_focus_v1\(pv\.pid\)[\s\S]*or security\.course_list_read_v1\(pv\.pid\)[\s\S]*or security\.bind_match_scope_v1\(pv\.pid\)/)
})

test('nothing else changes: no time-out, schedule, job command, setting, data or consumer object', () => {
  const c = code(m)
  const top = c.replace(/\$([a-z]*)\$[\s\S]*?\$\1\$/g, '')   // statements outside any dollar-quoted body
  expect(c).not.toMatch(/statement_timeout|cron\.(schedule|alter_job|unschedule)|platform_toolset_settings/)
  expect(c).not.toMatch(/\b(drop|truncate)\b/i)
  expect(top).not.toMatch(/^\s*(insert|update|delete)\b/im)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\.|consumer_api_rebaseline_v1/)
})
