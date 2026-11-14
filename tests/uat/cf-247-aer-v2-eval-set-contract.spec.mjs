// Guards: Platform Admin 14 Nov 2026 item 3 "prepare the shared 50-case stratified evaluation set to benchmark Qwen3 30B (pinned providers + require_parameters), Mistral Small 3.2 24B, and MiMo-V2.6-Flash once Phase 1b is ready. Record the proposed test call count and max spend before starting paid calls": the set is frozen (course and stored page), stratified, and the plan is recorded as proposed with its call count, retry ceiling and spend cap; nothing runs or spends
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261114021500_cf247_aer_v2_eval_set.sql', 'utf8')

test('50 cases in six strata, each frozen to its stored page so every model reads the same bytes', () => {
  expect(M).toContain("('S3', 'v2 trial course (known failure shapes)', 8, 8, 1), ('S1', 'gate_incomplete v1 read in Layer 4', 14, 2, 2), ('S2', 'rows a person decided', 10, 4, 3)")
  expect(M).toContain("('S4', 'six or more active requirement rows', 7, 2, 4), ('S5', 'long stored page (90th to 97th percentile)', 5, 2, 5), ('S6', 'no requirement held, no Layer 4 read', 6, 2, 6)")
  expect(M).toContain("if s <> '{\"S1\": 14, \"S2\": 10, \"S3\": 8, \"S4\": 7, \"S5\": 5, \"S6\": 6}'::jsonb then raise exception")
  expect(M).toContain('evidence_id uuid not null')
  expect(M).toContain("md5(t.course_id::text || 'aer-v2-eval-50-v1')")
  expect(M).toContain("not exists (select 1 from pipeline.aer_v2_eval_cases x where x.eval_set = 'aer-v2-eval-50-v1')")
  expect(M).toMatch(/comment on table pipeline\.aer_v2_eval_cases is '/)
})

test('the plan is recorded before any paid call: 150 calls, at most 300, at most US$2.00, proposed only, three pinned evaluation versions', () => {
  expect(M).toContain("array['aer-v2-course-v3-qwen3-30b', 'aer-v2-course-v3-mistral-small-3.2', 'aer-v2-course-v3-mimo-v2.6-flash']")
  expect(M).toContain('p.calls_proposed <> 150 or p.calls_max <> 300 or p.max_usd <> 2.00')
  expect(M).toContain("status text not null default 'proposed'")
  expect(M).toContain('a cut answer, a page over reading.aer_v2_page_chars or a verifier failure is never retried')
  expect(M).toContain("'Lean AI Input Phase 1b ready (Platform Admin 14 Nov 2026 item 3); the Platform Admin approves this plan and opens an on-demand request before any call'")
  expect(M).toMatch(/comment on table pipeline\.aer_v2_eval_plans is '/)
  expect(M).not.toContain('gpt-4.1-mini')
})

test('nothing is read, called, spent or admitted', () => {
  expect(M).not.toMatch(/svc_pilot_submit_nonce|net\.http_post|on_demand_open_v1|cron\.schedule/)
  expect(M).not.toMatch(/key\s*=\s*'aer\.v2_shadow_on'|aer_v2_shadow_results\s+(set|where)/i)
  expect(M).not.toMatch(/insert into catalogue\.|course_entry_review_apply_v1|layer4_review_items\s*\(/)
  expect(M).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
  expect(M).toContain("if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception")
  expect(M).toMatch(/^-- Replaces: /m)
})
