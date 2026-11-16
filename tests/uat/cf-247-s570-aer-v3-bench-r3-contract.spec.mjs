// Guards: AER v3 benchmark round 3 (Platform Admin 16 Nov 2026 16:52 "Stop Qwen, shadow Mistral" step 3; gate pre-authorised 20:14): the same frozen set 5, prompt text and page and answer limits as round 2, three models each pinned without fallback, the long-page sections switch on for the run only, spend under the existing cap, evidence only (nothing qualified, no route or shadow switched on by the run)
// CF-247 S570. Migration 20261117020000_cf247_aer_v3_bench_r3.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261117020000_cf247_aer_v3_bench_r3.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('three round-3 proposals on the frozen set 5, one per pinned model, Qwen3 30B not among them', () => {
  expect(code).toContain("and v.version in ('aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash', 'aer-v2-course-v3-gemini-2.5-flash')")
  const list = /and v\.version in \(([^)]+)\)/.exec(code)[1]
  expect(list).not.toContain('qwen3-30b')
  expect(code).toContain("v.id, 5,")
  expect(code).toContain("perform security.ai_eval_run_open_v1(p.id, 'candidate');")
  expect(code).toContain("if n <> 3 then raise exception 'post-check: % queued round-3 runs (expected 3)', n; end if;")
  expect(code).toContain("and coalesce((a.routing->>'allow_fallbacks')::boolean, false) = false;")
})

test('the same limits as round 2; the long-page sections switch and the two run switches on with a reason and a control event', () => {
  expect(code).toContain("security.pipeline_num_v1('reading.aer_v2_page_chars', 0) <> 60000 or security.pipeline_num_v1('reading.aer_v2_max_tokens', 0) <> 12000")
  expect(code).toContain("where toolset_key = 'pipeline' and key in ('reading.aer_v2_long_page_sections_on', 'ai_eval.offline_runs_on', 'ai_eval.aer_v3_runs_on')")
  expect(code).toMatch(/insert into pipeline\.admin_control_events\(area, action, target, detail, actor\)\s+select 'settings', 'migration', u\.key/)
  expect(code).not.toMatch(/key\s*=\s*'ai_eval\.aer_v3_max_usd'/)
})

test('evidence only: no qualification, no route or shadow switched on; OpenRouter-only on-demand window', () => {
  expect(code).not.toMatch(/status\s*=\s*'qualified'\s*,/)
  expect(code).not.toMatch(/update pipeline\.ai_service_routes/)
  expect(code).not.toMatch(/update pipeline\.ai_route_qualifications/)
  expect(code).toContain("if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception 'post-check: the AER v2 shadow reader stays off'; end if;")
  expect(code).toContain("raise exception 'post-check: the entry reading routes stay off';")
  expect(code).toMatch(/security\.on_demand_open_v1\('claude_session',[\s\S]*?array\['openrouter'\]\);/)
})
