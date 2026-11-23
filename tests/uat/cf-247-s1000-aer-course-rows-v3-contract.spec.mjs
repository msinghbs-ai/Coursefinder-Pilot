// Guards: Platform Admin 23 Nov 2026 12:29 AEDT, Priority 1 (AER admission recovery: courses with active, evidence-backed academic entry rows read "no reader" and "contact the provider"); admin DESTINATION-DATA-DESIGN.md v1.12 section A; G3 (v2 and security.entry_resolve_v1 unchanged)
// Website and Zoho API v3 serve a course's own evidence-backed academic rows where the frozen resolver answers step 5; field coverage counts the same rows; every other answer is unchanged.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123100000_cf247_s1000_aer_course_rows_v3_resolver_coverage.sql', 'utf8');

test('s1000: every edit is md5-guarded and found exactly once; v1 resolver and v2 untouched', () => {
  for (const m of ['0d1881c093696f9c6dd46fa974595627', '97f8eee0bd30d093070ea242fe710ebc', '473289a0a58b4a37e951d54f6a99013d',
                   '802659f3ccd66cd419a15d7084495785', 'd493c1b25a2cc55c7dd9d66cee440aa7', '9f59f7d54a8a1bcd9d89302c2c977ae3']) expect(sql).toContain(m);
  expect(sql).toContain('the fragment of % is found % times');
  expect(sql).toContain("post-check: a v2 path changed");
  expect(sql).not.toMatch(/create or replace function security\.entry_resolve_v1\b/);
  expect(sql).not.toMatch(/create or replace function public\.(website|zoho)_v2_/);
});

test('s1000: the v3 resolver only replaces step 5, with quoted, evidence-backed academic rows, in the v1 row shape', () => {
  expect(sql).toContain("if r->>'step' is distinct from '5' then return r; end if;");
  expect(sql).toContain("x.kind in ('minimum_grade', 'prior_qualification', 'subject_prerequisite')");
  expect(sql).toContain("x.audience in ('international', 'all') and x.evidence_id is not null and nullif(btrim(x.quote), '') is not null");
  expect(sql).toContain("'step', 1, 'rule', 'course_override'");
  expect((sql.match(/years of age\|years old/g) || []).length).toBe(3);  // an age limit is never served or counted as an academic minimum
  expect(sql).toContain("if v_res->>'step' is distinct from '5' then v := jsonb_set(v, '{item,entry,resolution}', v_res); end if;");
});

test('s1000: coverage counts the same rows; live post-checks prove the gain and no change elsewhere', () => {
  expect((sql.match(/rule 1 of the v3 resolver, the course page's own evidence-backed academic rows/g) || []).length).toBe(2);
  expect(sql).toContain('post-check: academic entry coverage did not grow');
  expect(sql).toContain('post-check: Website v3 served rule 1 for % of % sampled courses');
  expect(sql).toContain('post-check: a non-step-5 Website v3 answer changed');
  expect(sql).toContain("security.consumer_api_check_v1()");
  expect(sql).not.toMatch(/create table|cron\.schedule|concurrently|PROBE ONLY/i);
});
