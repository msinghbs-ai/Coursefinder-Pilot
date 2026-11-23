// Guards: Platform Admin 23 Nov 2026 11:10 AEDT (false-positive admission holds; REQ-94) and 07:16 AEDT Part 1.1 (row-level partial admission for course entry rows); policy of aer-partial-v1 (s914, Platform Admin 21 Nov 2026 10:03); Decision 276 (no reader, word list, threshold or recovery path change).
// Course entry first reads stopped only by the completeness gate admit the rows that pass every machine row rule; the rest stay in Layer 4; the assurance check counts them as admitted.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123050000_cf247_s983_aer_course_partial_admission.sql', 'utf8');

test('s983: both edits are md5-guarded single-fragment edits', () => {
  expect(sql).toContain("'cef712d1644e034078597bdf863f26c7'");
  expect(sql).toContain("'87b8109532ee26748656fce045742895'");
  expect(sql).toContain('the fragment of % is found % times');
});

test('s983: only gate-stopped reads, no lock, no overwrite, machine rule admitting; every row rule kept', () => {
  expect(sql).toContain("continue when coalesce(cc->>'rule', '') <> 'gate_incomplete';");
  expect(sql).toContain("l.field in ('entry_requirements', 'all')");
  expect(sql).toContain("and not exists (select 1 from catalogue.course_entry_requirements a where a.course_id = i.entity_id and a.status = 'active')");
  expect(sql).toContain("security.pipeline_num_v1('aer.machine_mode', 0) >= 2 and security.pipeline_num_v1('aer.machine_suspended', 0) < 1");
  expect(sql).toContain("length(btrim(coalesce(x.quote, ''))) >= v_qmin and coalesce(x.confidence, 0) >= c_conf");
  expect(sql).toContain("and not (x.min_value is not null and coalesce(x.grade_scale, 'none') = 'none')");
  expect(sql).toContain("security.pipeline_num_v1('aer.machine_min_confidence', 0.8)");
});

test('s983: ledger names the rows; the assurance check accepts them; no Layer 4 decision', () => {
  expect(sql).toContain("'admit', 'admitted', 'aer-course-partial-v1', 'partial'");
  expect(sql).toContain("jsonb_build_object('admitted_row_ids', to_jsonb(c_ok)");
  expect(sql).toContain("ma.rule = 'aer-course-partial-v1' and ma.checks->'admitted_row_ids' ? x.id::text)) z");
  expect(sql).toContain("post-check: a Layer 4 item was decided");
  expect(sql).not.toMatch(/set status = '(approved|edited_approved|rejected)'/);
  expect(sql).not.toMatch(/create table|cron\.schedule|concurrently|PROBE ONLY/i);
});
