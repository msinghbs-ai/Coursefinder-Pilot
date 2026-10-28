// Guards: CF-247 AER programme switch-on of Steps B and C and Wave J (Platform Admin consolidated mandate 28 Oct 2026 23:22; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md P1, P4, P5; the 28 Oct deploy-order lesson): switched on only in a change of its own after worker v0.50.0 is live, guarded on the live scope, RMIT kept out, the planned JavaScript-only sources seeded and count-guarded, and only reads stopped by fixed faults given their tries back, bounded
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029003000_cf247_aer_switch_on_pdf_and_rendered.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('a change of its own: settings only, guarded on what is live, no reader code', () => {
  expect(code).toContain("if jsonb_array_length(v_scope) <> 29 or v_scope ? '8e1adb6c-e069-43db-9584-bd054255e702' then raise exception")
  expect(code).toContain("if security.pipeline_num_v1('entry.pdf_enabled', 0) <> 0 then raise exception 'entry.pdf_enabled is already on'; end if;")
  expect(code).toContain("set value = to_jsonb(1), updated_at = now(),")
  expect(code).toContain(`set value = '["wgtn.ac.nz", "whitireiaweltec.ac.nz", "newcastle.edu.au", "griffith.edu.au"]'::jsonb`)
  expect(code).not.toMatch(/create or replace function/i)
})

test('Wave J: four planned sources, count-guarded; scope to 33 providers with RMIT out', () => {
  expect((code.match(/, 1, 'manual'\)/g) || []).length).toBe(4)
  expect(code).toContain("if v_n <> 4 then raise exception 'Wave J: expected 4 new sources, inserted %', v_n; end if;")
  expect(code).toContain("<> 33 then raise exception 'entry.providers widening did not apply'")
  expect(code).toContain("if security.entry_matrix_enabled_v1('8e1adb6c-e069-43db-9584-bd054255e702') then raise exception 'RMIT must stay out of matrix reading scope'")
})

test('only reads stopped by fixed faults get their tries back, bounded; nothing dropped or deleted', () => {
  expect(code).toContain("where found_via = 'manual' and status = 'failed' and error in ('credits_refused', 'credits_reserve') and read_at is null;")
  expect(code).toContain("if v_s > 10 then raise exception")
  expect(code).toContain("where state = 'failed' and error like 'Unterminated string in JSON%' and review_item_id is null;")
  expect(code).toContain("if v_r > 5 then raise exception")
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(code).not.toMatch(/insert into pipeline\.(automation_catalogue|admin_job_kinds)|cron\.schedule/)
  expect(m).toMatch(/^-- Replaces: nothing$/m)
  expect(m).toMatch(/^-- Retires: /m)
})
