// Guards: Platform Admin 26 Nov 2026 03:45 AEDT (s1181 live UAT bug, "Master of  Nursing  in victoria" with extra spaces failed; "make it idiot proof"): portal course search folds any typing one way, ignores malformed request fields, and reads the vector index once, words through the text index and no course row by row, so it answers well inside the API's 8 s limit; the replace runs only over the s1153 body, and G3, locks, cron and the three new settings are checked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261128105000_cf247_s1181_portal_search_hardening.sql', 'utf8')
const code = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = code.slice(code.indexOf('create or replace function catalogue.portal_course_search_v1'), code.indexOf('end $function$;'))
const fold = code.slice(code.indexOf('create or replace function security.portal_fold_v1'), code.indexOf('$fold$;'))

test('s1181: typed text and place names are folded one way (case, accents, quotes, spacing, punctuation)', () => {
  expect(fold).toContain('immutable parallel safe as $fold$')
  expect(fold).toContain("pg_catalog.btrim(pg_catalog.regexp_replace(pg_catalog.translate(pg_catalog.lower(coalesce(p, '')),")
  expect(fold).toContain("'[^a-z0-9$'']+', ' ', 'g'))")
  expect(fn).toContain("v_t := ' ' || security.portal_fold_v1(v_t) || ' ';")
  expect(fn).toContain("security.portal_fold_v1(co.name) nm")
  expect(fn).toContain("security.portal_fold_v1(s.name) nm")
  expect(fn).toContain("select security.portal_fold_v1(z.city) nm")
  expect(fn).toContain("'\\s+', ' ', 'g')) || ' ';")
  expect(fn).toContain("(2, '\\m(graduate|grad)\\s*(diploma|dip)\\M'")
  expect(fn).toContain("(1, '\\m(graduate|grad)\\s*(certificate|cert)\\M'")
  expect(sql).toContain("security.portal_fold_v1(E'  Melbourne,\\tVICTORIA\\u00a0 Montréal–Trois-Rivières  ') <> 'melbourne victoria montreal trois rivieres'")
})

test('s1181: malformed request fields are ignored, never raised; an empty search answers at once', () => {
  expect(fn).toContain("case when jsonb_typeof(p_args->'removed') = 'array' then p_args->'removed' else '[]'::jsonb end")
  expect(fn).toContain("case when jsonb_typeof(p_args->'countries') = 'array' then p_args->'countries' else '[]'::jsonb end) x where trim(x) ~ '^[A-Za-z]{2}$'")
  expect(fn).toContain("case when jsonb_typeof(p_args->'relax') = 'array' then p_args->'relax' else '[]'::jsonb end) x\n            where jsonb_typeof(x) = 'object' loop")
  expect(fn).toMatch(/v_provider uuid := case when trim\(coalesce\(p_args->>'provider_id', ''\)\) ~\* '\^\[0-9a-f\]\{8\}/)
  expect(fn).toContain("security.portal_search_num_v1('query_max_chars', 200)")
  expect(fn).toContain("if cardinality(v_qcountries) = 0 then v_qcountries := array['--']; end if;")
  expect(fn).toContain("return jsonb_build_object('understood', '[]'::jsonb, 'exact', '[]'::jsonb, 'near_misses', '[]'::jsonb, 'relaxations', '[]'::jsonb, 'relaxation', null, 'total', 0, 'ranking', 'title');")
})

test('s1181: the vector index is searched once, words through the text index, no course row read one by one, no second ranker call', () => {
  expect(fn).toContain("perform set_config('hnsw.ef_search', v_pool::text, true);")
  expect(fn).toContain("perform set_config('hnsw.iterative_scan', 'relaxed_order', true);")
  expect(fn).toContain('order by e.embedding operator(extensions.<=>) v_vec limit v_pool) x')
  expect((fn.match(/operator\(extensions\.<=>\)/g) || []).length).toBe(2)
  expect(fn).toContain("select d.course_id, 1 from search.course_documents d where d.search_tsv @@ plainto_tsquery('english', v_w)")
  expect(fn).toContain('d.course_id in (select t.course_id from pg_temp.portal_search_topic t)')
  expect(fn).not.toMatch(/course_candidates_v1\(/)
  expect(fn).not.toMatch(/exists \(select 1 from search\.course_embeddings/)
  expect(fn).not.toMatch(/ts_rank_cd/)
  expect(fn).toContain("coalesce((pr.config->>'rrf_k')::double precision, 60)")
  expect(fn).toContain("security.portal_search_num_v1('topic_vector_pool', 100)")
  expect(fn).toContain("security.portal_search_num_v1('topic_max_words', 8)")
})

test('s1181: guarded replace, three G2 settings, G3, locks and cron checked, nothing dropped, no AI call', () => {
  expect(sql).toContain("<> '2ab79d9e3268818207fad8b7e28eb0b0' then")
  for (const k of ['query_max_chars', 'topic_max_words', 'topic_vector_pool']) expect(sql).toMatch(new RegExp(`\\('portal_search', '${k}', '[^']+', '[^']+', 'number', '\\d+'::jsonb, \\d+, \\d+, '[a-z]+', \\d+, 'Portal search', 'catalogue.portal_course_search_v1', 'CF-247 s1181'\\)`))
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toContain('post-check: the number of active cron jobs changed')
  expect(sql).toContain('post-check: manual locks changed')
  expect(sql).toMatch(/-- Replaces: catalogue\.portal_course_search_v1/)
  expect(sql).toContain('-- Retires: nothing.')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\s+(table|function|from|schema)/im)
  expect(code).not.toMatch(/cron\.schedule|openrouter|firecrawl|svc_pilot_submit_nonce\('coverage-sweep', jsonb_build_object\('mode', 'portal_search_embed', 'query_key', v_key, 'text', 'x'/i)
})
