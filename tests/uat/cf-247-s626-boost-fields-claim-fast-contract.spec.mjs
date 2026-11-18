// Guards: Boost multi-field reading claim (Platform Admin 18 Nov 2026 07:08 decision 3): the claim starts from the stored course pages and works out each one's gap fields once per call, so it answers within the API's time-out; the migration fails if it takes more than 5 seconds under an 8-second time-out or carries other than each course's gap fields
// CF-247 S626. Migration 20261118130000_cf247_boost_fields_claim_fast. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations-archive/20261118130000_cf247_boost_fields_claim_fast.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the claim reads the stored pages once, not a function per course, and keeps the rules', () => {
  expect(code).toContain("if v <> 'ca58e9b4cd2058fceb814806852fe6a6' then raise exception")
  expect(code).toContain("where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null\n     order by e.entity_id, e.captured_at desc nulls last),")
  const fn = code.slice(code.indexOf('create or replace function security.boost_fields_claim_v1('), code.indexOf('$function$;'))
  expect(fn).not.toContain('security.boost_fields_missing_v1(')
  expect(fn).toContain('where not exists (select 1 from shared h where h.content_hash = a.content_hash)')
  expect(fn).toContain('order by m.priority_rank loop')
  expect(fn).toContain('z.lanes && r.cell_lanes')
  for (const l of ['course_description', 'delivery_mode', 'intakes', 'course_fees', 'aer_entry']) expect(fn).toContain(`'${l}' = any (v_lanes)`)
})

test('post-check: under an 8-second time-out the claim takes at most 5 seconds and carries each course\'s gap fields', () => {
  expect(code).toContain("set local statement_timeout = '8s';")
  expect(code).toContain("if v_ms > 5000 then raise exception 'post-check: the claim took % ms', round(v_ms); end if;")
  expect(code).toContain("raise exception 'post-check: a claimed item does not carry the course''s gap fields: %', v_item;")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)\b|\bdelete\s+from\b|\btruncate\s+(table\s+)?pipeline/i)
})
