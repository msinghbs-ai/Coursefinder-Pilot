// Guards: Platform Admin 23 Nov 2026 22:55 and 22:59 AEDT (S1-Build: Courses keyword search on trigram indexes, approved subject to measured plan validation; same matching, order, filters, paging and role check; admin_toolsets_read recorded in source unchanged; G3 frozen; nothing dropped)
// s1014: pg_trgm in the extensions schema; four GIN trigram indexes (one per course column the keyword is tested against) under a lock retry;
// security.admin_course_page_fast_base tests the keyword as one lookup per column (the same six tests) instead of one OR across tables,
// edited in place from the md5-guarded live definition and checked against the rehearsed result.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261123235000_cf247_s1014_course_keyword_trigram_search.sql', 'utf8')

test('s1014: pg_trgm in extensions and one trigram index per searched course column, each under a lock retry', () => {
  expect(MIG).toContain('create extension if not exists pg_trgm with schema extensions;')
  for (const ix of ["courses_title_trgm_idx on catalogue.courses using gin (canonical_title extensions.gin_trgm_ops)",
    "courses_display_title_trgm_idx on catalogue.courses using gin ((coalesce(display_title, '''')) extensions.gin_trgm_ops)",
    "courses_code_trgm_idx on catalogue.courses using gin ((coalesce(course_code, '''')) extensions.gin_trgm_ops)",
    "courses_stable_key_trgm_idx on catalogue.courses using gin ((coalesce(stable_key, '''')) extensions.gin_trgm_ops)"]) expect(MIG).toContain(ix)
  expect((MIG.match(/create index if not exists/g) || []).length).toBe(4)
  expect(MIG).toContain('exception when lock_not_available then')
})

test('s1014: the keyword test keeps its six tests, as one lookup per column; only that block of the live definition changes', () => {
  const hits = MIG.slice(MIG.indexOf('query_hits as materialized ('), MIG.indexOf('), base as (', MIG.indexOf('query_hits as materialized (')))
  for (const t of ["c.canonical_title ilike '%'||trim(p_args->>'query')||'%'",
    "coalesce(c.display_title,'') ilike '%'||trim(p_args->>'query')||'%'",
    "coalesce(c.course_code,'') ilike '%'||trim(p_args->>'query')||'%'",
    "coalesce(c.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'",
    "coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'",
    "ci.scheme='studysearch' and upper(ci.identifier) like upper(trim(p_args->>'query'))||'%'"]) expect(hits).toContain(t)
  expect(MIG).toContain("where (nullif(trim(coalesce(p_args->>'query','')),'') is null or c.id in (select h.id from query_hits h))")
  expect(MIG).toContain("<> '976353299ff36e0f5c671420eb526e30' then")
  expect(MIG).toContain("<> '22eb2f5e78def853193e672808628e69' then")
  expect(MIG).toContain('guard: the keyword test is not found exactly once')
  expect(MIG).toContain('execute replace(replace(d, v_old_where, v_new_where), v_old_cte, v_new_cte);')
})

test('s1014: no drop or delete; G3, manual locks and active cron checked before and after; the deployed cf-061 wait is unchanged', () => {
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/drop |delete from|truncate /i)
  for (const s of ['guard: the consumer API is not at its baseline before this change', 'post-check: the consumer API moved', 'post-check: manual locks changed',
    'post-check: the number of active cron jobs changed', 'post-check: a trigram index is missing']) expect(MIG).toContain(s)
  const qilt = fs.readFileSync('tests/uat/cf-061-qilt-prisms-comparison-deployed.spec.mjs', 'utf8')
  expect(qilt).toContain(".filter({hasText:'RMIT'}).first()\n  await expect(row).toBeVisible({timeout:DETERMINISTIC_UI_TIMEOUT})")
})

test('s1014: public.admin_toolsets_read is recorded in source exactly as in production (md5 guarded before and after, unchanged)', () => {
  expect(MIG).toContain('CREATE OR REPLACE FUNCTION public.admin_toolsets_read()')
  expect((MIG.match(/df2380c6d541db3756bcc88c5e62641a/g) || []).length).toBe(2)
  expect(MIG).toContain('post-check: public.admin_toolsets_read changed')
  expect(MIG).toContain("from pipeline.platform_toolsets t where t.key <> 'pipeline')")
})
