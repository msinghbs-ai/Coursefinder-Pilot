// Guards: Atlas brief 26 Nov 2026 09:30 AEDT for the Platform Admin (s1211, portal course search slow in UAT on first-time and broad phrases): the meaning step reads a compact one-bit index (search.course_embeddings_bq_hnsw_idx) and scores its portal_search.topic_vector_candidates exactly; countries and levels come through their indexes; a typed city is matched once and only against the topic's courses; the topic set is analysed once filled; a phrase's meaning is kept 30 days and renewed on use; the Dashboard example searches are a setting equal to EXAMPLE_PROMPTS and are pre-warmed; a phrase not yet embedded never waits for the embedding service.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261129040000_cf247_s1211_portal_search_latency.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = code.slice(code.indexOf('create or replace function catalogue.portal_course_search_v1'), code.indexOf('$function$;'))
const copy = fs.readFileSync('portal/src/copy.js', 'utf8')

test('s1211: housekeeping header, guards and the body it replaces', () => {
  expect(sql).toMatch(/^-- Replaces: .+/m)
  expect(sql).toMatch(/^-- Retires: nothing \(search\.course_embeddings_hnsw_idx stays/m)
  expect(code).toContain("if (select md5(prosrc) from pg_proc where oid = 'catalogue.portal_course_search_v1(jsonb)'::regprocedure) <> 'af093059e6e787bbf53b082ca08a4eab' then")
  expect(code).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(code).toContain("if (select count(*) from cron.job where active) <> (select cron_before from s1211_guard)")
  expect(code).toContain("if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1211_guard)")
  expect(code).not.toMatch(/\bdrop\s+(table|function|index|view)\b/i)
  expect(code).not.toMatch(/\bdelete\s+from\b/i)
  expect(code).not.toContain('cron.schedule')
})

test('s1211: the meaning step reads the compact one-bit index, then scores its candidates exactly', () => {
  expect(code).toContain('create index if not exists course_embeddings_bq_hnsw_idx on search.course_embeddings\n  using hnsw ((extensions.binary_quantize(embedding)::bit(1536)) extensions.bit_hamming_ops) with (m = 16, ef_construction = 32);')
  expect(fn).toContain("perform set_config('hnsw.ef_search', v_cand::text, true);")
  expect(fn).toContain('order by (extensions.binary_quantize(b.embedding)::bit(1536)) operator(extensions.<~>) extensions.binary_quantize(v_vec) limit v_cand) k')
  expect(fn).toContain('order by 3 limit v_pool) x')
  expect(fn).toContain("security.portal_search_num_v1('topic_vector_candidates', 300)")
  expect(fn).not.toContain('order by e.embedding operator(extensions.<=>) v_vec limit v_pool')
  expect(code).toContain("if v_plan not like '%course_embeddings_bq_hnsw_idx%' then")
})

test('s1211: countries and levels through their indexes; a typed city matched once and only against the topic', () => {
  expect(fn).not.toContain('select distinct d.country_code from search.course_documents d')
  expect(fn).not.toContain('select distinct d.study_level_code from search.course_documents d')
  expect(fn).toContain('select (select min(d.country_code) from search.course_documents d where d.country_code > t.c) from t where t.c is not null')
  expect(fn).toContain('select (select min(d.study_level_code) from search.course_documents d where d.study_level_code > t.c) from t where t.c is not null')
  expect(fn).toContain('v_levels := array(select l from unnest(v_doc_levels) l where l like r.code);')
  expect(fn).toContain('v_city_campuses := array(select ca.id from catalogue.campuses ca')
  expect(fn).toContain('v_city_providers := array(select p.id from catalogue.providers p')
  expect(fn).toContain('where cc.campus_id = any(v_city_campuses)')
  expect(fn).toContain('and (v_topic is null or cardinality(v_words) = 0 or cc.course_id in (select t.course_id from pg_temp.portal_search_topic t))')
  expect(fn).toContain('select t.course_id from pg_temp.portal_search_topic t join catalogue.courses c on c.id = t.course_id')
})

test('s1211: the topic set is analysed once filled; courses with the same title keep one order', () => {
  expect(fn).toContain('analyze pg_temp.portal_search_topic;')
  expect(fn).toContain('order by 2, 3, 1 limit v_page) x;')
})

test('s1211: a phrase not yet embedded never waits; a cached phrase is renewed on use for query_cache_hours (now 720)', () => {
  expect(fn).toContain("perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'portal_search_embed', 'query_key', v_key, 'text', v_topic));")
  expect(fn).not.toMatch(/net\.http_(get|post)|pg_sleep|http_collect_response/)
  expect(fn).toContain("expires_at = greatest(expires_at, now() + make_interval(hours => security.portal_search_num_v1('query_cache_hours', 720)::int))")
  expect(code).toContain("update pipeline.platform_toolset_settings set value = to_jsonb(720), updated_at = now(),")
  expect(code).toContain("where toolset_key = 'portal_search' and key = 'query_cache_hours';")
})

test('s1211: the Dashboard example searches are a setting equal to EXAMPLE_PROMPTS, and each is pre-warmed', () => {
  const block = copy.slice(copy.indexOf('export const EXAMPLE_PROMPTS = ['), copy.indexOf(']', copy.indexOf('export const EXAMPLE_PROMPTS = [')))
  const prompts = [...block.matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((m) => m[1])
  expect(prompts.length).toBeGreaterThan(0)
  const m = code.match(/\('portal_search', 'prewarm_phrases', [^\n]*'list', '(\[.*?\])'::jsonb/)
  expect(m).not.toBeNull()
  expect(JSON.parse(m[1].replace(/''/g, "'"))).toEqual(prompts)
  expect(code).toContain("for p in select jsonb_array_elements_text(value) from pipeline.platform_toolset_settings where toolset_key = 'portal_search' and key = 'prewarm_phrases' loop")
  expect(code).toContain("x := catalogue.portal_course_search_v1(jsonb_build_object('q', p));")
})

test('s1211: G2 settings carry label, range, unit and used_by', () => {
  expect(code).toContain("('portal_search', 'topic_vector_candidates', 'Courses: meaning candidates scored exactly',")
  expect(code).toMatch(/'number', '300'::jsonb, 100, 1000, 'courses', 6265, 'Portal search', 'catalogue\.portal_course_search_v1', 'CF-247 s1211'\)/)
  expect(code).toMatch(/'list', '\[.*\]'::jsonb, null, null, 'phrases', 6275, 'Portal search', 'migration 20261129040000 \(pre-warm\); portal Dashboard EXAMPLE_PROMPTS', 'CF-247 s1211'\)/)
})
