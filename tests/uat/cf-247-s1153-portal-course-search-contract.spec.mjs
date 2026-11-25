// Guards: Platform Admin 25 Nov 2026 17:13 AEDT (s1153 Portal Release 1 search activation): catalogue.portal_course_search_v1 and public.portal_course_search_v1(p_args) to the as-built contract; portal_search.* settings (G2); text-embedding-3-small vectors under a new portal-default profile so the frozen Zoho ranker (zoho-default) and the website profile get none (G3); backfill and re-embedding through a dispatcher lane and edge function portal-search-embed with no new cron job.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261127020000_cf247_s1153_portal_course_search.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/portal-search-embed/index.ts', 'utf8')
const edge = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions
const screen = fs.readFileSync('portal/src/screens/Courses.jsx', 'utf8')

test('s1153: the public entry point is the one the Courses screen calls, Viewer and above, signed-in only', () => {
  expect(screen).toContain("const FN = 'portal_course_search_v1'")
  expect(screen).toContain('p_args: { q, countries:')
  expect(sql).toContain('create or replace function public.portal_course_search_v1(p_args jsonb default')
  expect(sql).toContain("perform security.portal_rank_v1(1);  -- fixed: Viewer and above")
  expect(sql).toContain('grant execute on function public.portal_course_search_v1(jsonb) to authenticated;')
  expect(sql).toContain('revoke all on function public.portal_course_search_v1(jsonb) from public, anon;')
})

test('s1153: the response carries every key of the contract', () => {
  for (const k of ["'understood'", "'exact'", "'near_misses'", "'relaxations'", "'relaxation'", "'total'"]) expect(sql).toContain(`${k}, `)
  for (const k of ["'course_id'", "'title'", "'provider_name'", "'level'", "'state_code'", "'city'", "'duration_value'", "'duration_unit'",
                   "'fee'", "'per_year'", "'currency'", "'next_intake'", "'topic_match'", "'topic_score'", "'why'", "'course_url'", "'saved'"]) expect(sql).toContain(k)
  for (const k of ["'misses'", "'miss_text'", "'would_return'", "'note'", "'removable'", "'kind', 'topic'"]) expect(sql).toContain(k)
  expect(sql).toContain("v_removed text[] := array(select jsonb_array_elements_text(coalesce(p_args->'removed'")
  expect(sql).toContain("jsonb_array_elements(coalesce(p_args->'relax'")
})

test('s1153: relaxation follows the settings (third-cheapest + headroom, rounded up, capped) and is never applied by the function', () => {
  expect(sql).toContain("v_third := v_fees[least(3, v_all)];")
  expect(sql).toContain("v_to := ceil(v_third * (1 + v_head / 100) / v_round) * v_round;")
  expect(sql).toContain("if v_to > v_budget and v_to <= v_budget * (1 + v_maxraise / 100) then")
  expect(sql).toContain("if v_total < v_min then")
  for (const k of ['result_page_size', 'relax_min_matches', 'relax_budget_headroom_pct', 'relax_budget_round_to', 'relax_budget_max_raise_pct',
                   'topic_min_similarity', 'city_postcode_min_share', 'query_cache_hours', 'query_embed_daily_max', 'embed_batch', 'enqueue_chunk',
                   'embed_daily_ceiling_usd', 'embed_usd_per_mtok', 'embedding_model', 'visibility_scope']) expect(sql).toContain(`('portal_search', '${k}'`)
  expect(sql).toContain(`'"openai/text-embedding-3-small"'::jsonb`)
  expect(sql).toContain(`'"active"'::jsonb`)
})

test('s1153: vectors live only under portal-default; the existing fusion function is called, not changed', () => {
  expect(sql).toContain("insert into search.profiles (code, name, channel_code, version, config, status)")
  expect(sql).toContain("'portal-default'")
  expect(sql).toContain("post-check: a website or Zoho profile holds vectors")
  expect(sql).toContain("from search.course_candidates_v1(v_tsq, v_vec, v_model, 'portal-default', case when v_hybrid then 'hybrid' else 'keyword' end,")
  expect(sql).not.toMatch(/create or replace function search\.course_candidates_v1|alter table search\.|alter function api\./i)
})

test('s1153: no cron job; a registry lane that starts the edge function only when jobs wait; nonce allowlisted; G3 and locks checked', () => {
  expect(sql).not.toMatch(/cron\.schedule|cron\.unschedule/)
  expect(sql).toContain("values ('portal-search-embed', 'worker_lane', 'portal-search-embed', 'select security.portal_search_embed_fire_v1()', md5('select security.portal_search_embed_fire_v1()'),")
  expect(sql).toContain("return pipeline.svc_pilot_submit_nonce('portal-search-embed', jsonb_build_object('mode', 'courses'));")
  expect(sql).toContain("insert into pipeline.pilot_nonce_functions (function_name) values ('portal-search-embed')")
  expect(sql).toContain("post-check: the number of active cron jobs changed")
  expect(sql).toContain("post-check: manual locks changed")
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toContain('create or replace trigger portal_search_doc_updated after update on search.course_documents referencing new table as new_rows')
})

test('s1153: the edge function is registered, nonce-authenticated, pinned, denies provider data collection and logs spend', () => {
  expect(edge['portal-search-embed']).toBe(false)
  expect(fn).toContain('const FN = "portal-search-embed";')
  expect(fn).toContain('svc_pilot_consume_nonce')
  expect(fn).toContain('https://openrouter.ai/api/v1/embeddings')
  expect(fn).toMatch(/provider: \{ data_collection: "deny" \}/)
  expect(fn).toContain('svc_portal_search_embed_record')
  expect(sql).toContain("'portal_search_embedding'")
  expect(sql).toContain("security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 5)")
})
