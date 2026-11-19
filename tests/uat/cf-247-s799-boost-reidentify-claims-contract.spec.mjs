// Guards: Platform Admin 20 Nov 2026 05:42 AEDT (chat S1-Build, s799): the boost study-load claim and the coverage re-identify claim hand out the same work as before, faster: indexes that match each claim, the due set found once (no per-country hash grouping), the page check only on pages still due, the same lease, lock and lanes, and a measured before/after in the migration.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261120095000_cf247_s799_boost_and_reidentify_claims.sql', 'utf8')
const body = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const boost = body.slice(body.indexOf('create or replace function security.boost_extract_claim_v1'), body.indexOf('create or replace function public.svc_coverage_reidentify_next'))
const reid = body.slice(body.indexOf('create or replace function public.svc_coverage_reidentify_next'))

test('indexes match the claims', () => {
  expect(body).toContain("create index if not exists evidence_artifacts_page_text_hash_idx on pipeline.evidence_artifacts (content_hash, entity_id)")
  expect(body).toContain("create index if not exists evidence_artifacts_page_text_entity_idx on pipeline.evidence_artifacts (entity_id, captured_at desc nulls last) include (id, content_hash)")
  expect(body).toContain('create index if not exists coverage_reidentify_done_rule_idx on pipeline.coverage_reidentify_done (rule, course_id, evidence_id);')
})

test('the boost claim keeps its rules: lanes and weights, lock, lease, shared pages, locks, the s797 rule value; no per-country hash grouping', () => {
  expect(boost).not.toContain('group by e.content_hash having count(distinct e.entity_id) > 1')
  expect(boost).toContain("perform pg_advisory_xact_lock(hashtext('cf247:boost_extract_claim'));")
  expect(boost).toContain("x.state = 'claimed' and x.claimed_at > now() - interval '30 minutes'")
  expect(boost).toContain('h.content_hash = pick.content_hash')
  expect(boost).toContain("(c.study_load is null or (c.study_load_source = 'register' and c.study_load_evidence_id is null))")
  expect(boost).toContain('order by m.priority_rank')
  expect(boost).toContain("v_left int := least(greatest(coalesce(p_limit, 0), 0), 500);")
})

test('re-identify drops pages already done under the rule before the page check, and still locks what it hands out', () => {
  expect(reid).toContain('with done as materialized (')
  expect(reid).toContain('ok as materialized (')
  expect(reid).toContain('where not security.page_refused_v1(due.course_id, due.url)')
  expect(reid).toContain('for update of p skip locked')
  expect(body).toContain("'7ff3b754b2f78c04835587e0799ece8a'")
  expect(body).toContain("raise exception 'post-check: the boost pool differs: old % new %'")
  expect(body).not.toMatch(/^\s*(delete|drop|truncate)\b/im)
})
