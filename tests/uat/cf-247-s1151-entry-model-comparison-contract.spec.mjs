// Guards: Platform Admin 25 Nov 2026 15:40 AEDT (stop DeepSeek-only cycles; compare gpt-4.1-mini, gpt-5-mini and gpt-5-nano on the 83-page cohort with the same preprocessing, instructions and schema; no new reader, engine, pipeline or qualification mechanism)
// s1151: the existing qualification harness reads the 83 pages on the three OpenAI models; GPT-5 models are catalogued as allowed but in no route; no route, qualification or job changes.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261127000000_cf247_s1151_entry_model_comparison_openai.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1151: the 83 benchmark pages and labels are read on the three OpenAI models in the existing harness', () => {
  expect(MIG).toContain("v_run constant text := 's1151-entry-qualify-openai-v6-2026-11-25'; v_from constant text := 's1150-entry-qualify-deepseek-v6-2026-11-25';")
  expect(MIG).toContain("v_models constant text[] := array['gpt-4.1-mini', 'gpt-5-nano', 'gpt-5-mini'];")
  expect(MIG).toContain("if v_n <> 249 then raise exception")
  expect(MIG).toContain("security.pipeline_num_v1('reading.lean_qualify_ceiling_usd', 0)")
  expect(MIG).toContain("if 6 < coalesce(s.min_value, 6) or 6 > coalesce(s.max_value, 6) then raise exception")
})

test('s1151: GPT-5 models are allowed in the catalogue only; nothing is routed, qualified, scheduled or dropped', () => {
  expect(MIG).toContain("('gpt-5-mini', 'other', 'GPT-5 mini', 'openai/gpt-5-mini', 0.25, 2.00")
  expect(MIG).toContain("('gpt-5-nano', 'other', 'GPT-5 nano', 'openai/gpt-5-nano', 0.05, 0.40")
  expect(code).not.toMatch(/update pipeline\.ai_service_routes|insert into pipeline\.ai_route_qualifications|cron\.schedule|cron\.alter_job|layer4_review_items|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: a route names a GPT-5 model', 'post-check: the course entry route changed', 'post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
