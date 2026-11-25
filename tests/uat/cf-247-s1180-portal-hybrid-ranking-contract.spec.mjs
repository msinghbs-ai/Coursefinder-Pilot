// Guards: Platform Admin 25 Nov 2026 22:53 AEDT (s1180 live UAT bug, "Master of Nursing in Victoria" failed): search.course_candidates_v1's hybrid / vector branch qualifies course_id (it clashed with the function's own output column, SQLSTATE 42702), so a portal search whose query vector is cached ranks by meaning instead of failing; the fix replaces the live definition only after its checksum matches, and G3, locks and cron are checked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261128075000_cf247_s1180_portal_hybrid_ranking_fix.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const body = sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION search.course_candidates_v1('), sql.indexOf('$function$;') + '$function$;'.length)

test('s1180: the hybrid CTEs qualify course_id; no bare course_id is selected in the ranker', () => {
  expect(body).toContain('select fb.course_id,fb.score,row_number() over(order by fb.score desc,fb.course_id) as pos from fts_base fb')
  expect(body).toContain('select vb.course_id,vb.similarity,row_number() over(order by vb.similarity desc,vb.course_id) as pos from vec_base vb')
  expect(body).not.toMatch(/select course_id,/)
  expect(body).not.toMatch(/order by (score|similarity) desc,course_id\)/)
  expect(body).toContain('RETURNS TABLE(course_id uuid, fts_rank real, vector_similarity real, fused_score double precision, mode_used text)')
  expect(body).toContain('select b.*,row_number() over(order by b.score desc,b.course_id) as pos from base b')
})

test('s1180: replaced only after the live checksum matches; G3, locks and cron unchanged; the hybrid branch is exercised after the replace', () => {
  expect(sql).toContain("<> 'cea852088f24fd566999dda4094d071e' then")
  expect(sql).toContain("raise exception 'pre-check: search.course_candidates_v1 is in the frozen consumer API baseline'")
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toContain("post-check: the number of active cron jobs changed")
  expect(sql).toContain("post-check: manual locks changed")
  expect(sql).toContain("'portal-default', 'hybrid',")
  expect(sql).toMatch(/-- Replaces: search\.course_candidates_v1 hybrid/)
  expect(sql).toContain('-- Retires: nothing.')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(code).not.toMatch(/cron\.schedule|openrouter|firecrawl/i)
})
