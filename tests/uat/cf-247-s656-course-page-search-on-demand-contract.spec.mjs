// Guards: Course page needed on-demand search (Platform Admin 18 Nov 2026 16:54): the items rule l4-page-needed-search-v1 sent to the course-link search lane are searched through one on-demand request scoped to course search, with an estimate from recorded searches, never by a direct bind or a domain alias; the lane runs at most 10 searches at a time
// CF-247 S656. Migration 20261118200000_cf247_course_page_search_on_demand. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const code = fs.readFileSync(migrationPath('20261118200000_cf247_course_page_search_on_demand.sql'), 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('one on-demand request through the operating-model functions: Firecrawl only, scoped to course search', () => {
  expect(code).toContain("v_res := security.on_demand_open_v1('claude_session',")
  expect(code).toContain("null, '{firecrawl}');")
  expect(code).toContain("perform security.on_demand_scope_v1(v_id, '{course_search}');")
  expect(code).toContain("if v_r.purpose_groups <> '{course_search}' then raise exception")
  expect(code).toContain("r.reason like v_tag || '%'")
  expect(code.match(/security\.on_demand_open_v1\(/g)).toHaveLength(1)
})

test('only providers of items the rule sent to the lane; hidden providers left out; no provider written into the file', () => {
  expect(code).toContain("where n.state = 'search_requested'")
  expect(code).toContain("exists (select 1 from pipeline.course_link_search s where s.course_id = n.course_id and s.state = 'queued')")
  expect(code).toContain('not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = n.provider_id)')
  expect(code).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/)
  expect(code).not.toMatch(/adelaide/i)
})

test('the estimate comes from recorded searches and must fit the credit left on the plan', () => {
  expect(code).toContain("where c.use_case = 'link_search' and c.endpoint = 'search' and c.credits_used is not null")
  expect(code).toContain("if v_unit is null then raise exception 'no course page search is on record to estimate from'; end if;")
  expect(code).toContain("v_left := (security.on_demand_credit_left_v1()->>'firecrawl_left_on_plan')::numeric;")
  expect(code).toContain('if v_left is null or ceil(v_q * v_unit) > v_left then')
})

test('no page is bound, no queue row or setting is written, nothing is created or dropped', () => {
  expect(code).not.toMatch(/insert into (catalogue|binding)\.|update (catalogue|binding)\.|insert into pipeline\.(course_link_search|coverage_course_pages|platform_toolset_settings)|update pipeline\./i)
  expect(code).not.toMatch(/create (or replace )?(function|table(?! cf_s656)|view|index|trigger)|alter table|cron\.schedule/i)
  expect(code).toContain('create temp table cf_s656 on commit drop')
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})

test('the course-link search worker runs at most 10 searches at a time', () => {
  const i = worker.indexOf('if (mode === "link_search") {')
  const lane = worker.slice(i, worker.indexOf('// 1 Oct 2026 (Decision 205)', i))
  const pools = lane.match(/await pool\((groups|items), ([^,]+, \d+\)),/g)
  expect(pools).toHaveLength(2)
  for (const p of pools) expect(p).toContain('Math.min(Number(body.concurrency || 6), 10)')
})
