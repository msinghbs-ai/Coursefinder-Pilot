// Guards: Atlas brief 26 Nov 2026 09:30 AEDT for the Platform Admin (s1212, follow-up to s1211 after its live read-back): the portal meaning step reads the full-vector index by default (portal_search.meaning_index = full), the compact one-bit index stays only as the compact choice, and every other s1211 speed-up stays (city and filter steps by key, indexed country and level lists, phrase meanings kept and renewed, example searches pre-warmed).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261129050000_cf247_s1212_portal_meaning_full_index.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = code.slice(code.indexOf('create or replace function catalogue.portal_course_search_v1'), code.indexOf('$function$;'))

test('s1212: housekeeping header and guards; written against the s1211 body', () => {
  expect(sql).toMatch(/^-- Replaces: catalogue\.portal_course_search_v1 s1211 body/m)
  expect(sql).toMatch(/^-- Retires: nothing \(the compact index stays/m)
  expect(code).toContain("if (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_search_v1(jsonb)'::regprocedure) <> '18adc778ee10d2962b32dd704bfd12f8' then")
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain('if (select count(*) from cron.job where active) <> (select cron_before from s1212_guard)')
  expect(code).toContain('if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1212_guard)')
  expect(code).not.toMatch(/\bdrop\s+(table|function|index|view)\b/i)
  expect(code).not.toMatch(/\bdelete\s+from\b/i)
})

test('s1212: the meaning step reads the full-vector index unless the setting chooses compact', () => {
  expect(code).toContain("('portal_search', 'meaning_index', 'Courses: meaning index',")
  expect(code).toMatch(/'text', '"full"'::jsonb, null, null, 'full or compact', 6263, 'Portal search', 'catalogue\.portal_course_search_v1', 'CF-247 s1212'\)/)
  expect(fn).toContain("if security.portal_search_text_v1('meaning_index', 'full') = 'compact' then")
  expect(fn).toContain("perform set_config('hnsw.ef_search', v_pool::text, true);")
  expect(fn).toContain('where e.profile_id = v_profile and e.model_name = v_model order by e.embedding operator(extensions.<=>) v_vec limit v_pool) x')
  expect(fn).toContain('order by (extensions.binary_quantize(b.embedding)::bit(1536)) operator(extensions.<~>) extensions.binary_quantize(v_vec) limit v_cand) k')
  expect(code).toContain("if v_plan not like '%course_embeddings_hnsw_idx%' then")
})

test('s1212: the other s1211 speed-ups stay', () => {
  expect(fn).toContain('select (select min(d.country_code) from search.course_documents d where d.country_code > t.c) from t where t.c is not null')
  expect(fn).toContain('where cc.campus_id = any(v_city_campuses)')
  expect(fn).toContain('analyze pg_temp.portal_search_topic;')
  expect(fn).toContain("expires_at = greatest(expires_at, now() + make_interval(hours => security.portal_search_num_v1('query_cache_hours', 720)::int))")
  expect(fn).toContain('order by 2, 3, 1 limit v_page) x;')
  expect(fn).toContain("perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'portal_search_embed', 'query_key', v_key, 'text', v_topic));")
})
