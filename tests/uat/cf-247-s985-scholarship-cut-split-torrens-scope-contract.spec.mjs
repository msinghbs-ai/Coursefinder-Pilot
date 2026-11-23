// Guards: Platform Admin 23 Nov 2026 13:13 AEDT (s1001 scholarship coverage for Charles Darwin, Lincoln and Torrens; M3 guardrail: ai:scholarship_extraction stops cutting mid-JSON); IQ-00215 legal-name scope switched on for Torrens.
// A cut answer goes to the next model as the two-part read; Torrens enters scholarship scope; candidates refused only by the old test are admitted again by the canonical function.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123110000_cf247_s985_scholarship_cut_split_and_torrens_scope.sql', 'utf8');

test('s985: record function edited under its md5, two fragments, cut answers carry the sectioned-v1 variant', () => {
  expect(sql).toContain("md5(v_def) <> 'fa3345b7e0fe4ba9b6abafe2ebec4f6a'");
  expect(sql).toContain('root_id, fresh_read, read_request_id, recovery)');
  expect(sql).toContain("case when coalesce(p_error, '') like 'held_partial: output_truncated%' and coalesce(q.prompt_version, 0) >= 3 then 'sectioned-v1' else q.recovery end");
  expect(sql).toContain('fragment % of public.svc_scholarship_ai_record is found % times');
});

test('s985: the legal-name switch goes on with its reason; re-admission uses the canonical function only for scope refusals', () => {
  expect(sql).toContain("key = 'sch_cov.legal_name_identity_on' and value = to_jsonb(0)");
  expect(sql).toContain("security.scholarship_admit_from_provider_page_v1(c.id)");
  expect(sql).toContain("x.admit_reasons::text like '%not a university provider in a scholarship country%'");
  expect(sql).toContain('post-check: Torrens is still out of scholarship scope');
  expect(sql).not.toMatch(/reading\.answer_tokens\.scholarship_page'.*to_jsonb|publication_status = 'published'|create table|cron\.schedule/i);
});
