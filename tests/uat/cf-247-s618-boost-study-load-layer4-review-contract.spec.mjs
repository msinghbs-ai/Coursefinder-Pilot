// Guards: Boost study load to Layer 4 (Platform Admin 18 Nov 2026 07:08 decision 4, and 10:10): only refused readings (the page had study-load text and the answer failed the page check) reach Layer 4 › Inbox as kind boost_study_load, never "not stated" or failed calls; up to the setting boost.layer4_open_max, refilled as items are decided; a decision fills the study load only while it is empty and unlocked
// CF-247 S618. Migration 20261118111500_cf247_boost_study_load_layer4_review. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261118111500_cf247_boost_study_load_layer4_review.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (name) => { const i = code.indexOf(`create or replace function ${name}(`); return code.slice(i, code.indexOf('$function$;', i)) }

test('only refused readings under the route\'s current prompt are sent, one open per course, up to the setting', () => {
  const feed = fn('security.boost_study_load_review_feed_v1')
  expect(feed).toContain("where s.lane = 'study_load' and s.worker_status = 'rejected' and s.prompt_version = v_prompt")
  expect(feed).toContain("v_prompt text := (select q.prompt_version from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract'")
  expect(feed).toContain("v_cap int := security.pipeline_num_v1('boost.layer4_open_max', 400)::int;")
  expect(feed).toContain('where c.study_load is null')
  expect(feed).not.toMatch(/worker_status (=|in) \(?'(verified|failed)'/)
  expect(code).toContain("create unique index if not exists boost_study_load_reviews_one_open on pipeline.boost_study_load_reviews (course_id) where status = 'open';")
  expect(code).toMatch(/\('pipeline', 'boost\.layer4_open_max', [^\n]+\n[^\n]+\n\s+'number', to_jsonb\(400\), 0, 2000, 'items'/)
  expect(code).toContain('for each statement execute function security.boost_study_load_review_feed_trg_v1();')
})

test('the Inbox kind is registered with all five functions, Pipeline Operator choices, and an audit row per decision', () => {
  expect(code).toContain("values ('boost_study_load', 'kind', 'security.layer4_boost_study_load_kind_v1()', 'security.layer4_boost_study_load_inbox_counts_v1()', 'security.layer4_boost_study_load_inbox_page_v1(jsonb)',")
  expect(code).toContain("'security.layer4_boost_study_load_inbox_detail_v1(text)', 'security.layer4_boost_study_load_inbox_decide_v1(text,text,text,text)', true,")
  const kind = fn('security.layer4_boost_study_load_kind_v1')
  for (const k of ['accept_full_time', 'accept_part_time', 'accept_both', 'not_stated', 'dismiss']) expect(kind).toContain(`{"key": "${k}"`)
  expect((kind.match(/"rank": 4/g) || []).length).toBe(5)
  const decide = fn('security.layer4_boost_study_load_inbox_decide_v1')
  expect(decide).toContain("update catalogue.courses set study_load = v_val, study_load_source = 'manual', study_load_evidence_id = r.evidence_id\n     where id = r.course_id and study_load is null;")
  expect(decide).toContain("return jsonb_build_object('ok', false, 'kind', 'boost_study_load', 'choice', p_choice, 'ref', p_ref, 'request', 'A manual lock holds this course''s study load; it was not changed.');")
  expect(decide).toContain("values ('layer4', 'inbox_decide', 'boost_study_load:' || p_ref,")
  expect(decide).toContain('perform security.boost_study_load_review_feed_v1();')
  expect(decide).not.toMatch(/updated_at/)
})

test('backfill and post-checks: every eligible reading up to the cap is open, nothing else was sent, the Inbox accepts the kind', () => {
  expect(code).toContain('select security.boost_study_load_review_feed_v1();')
  expect(code).toContain("raise exception 'post-check: % reviews open for % eligible readings', v_open, v_eligible;")
  expect(code).toContain("raise exception 'post-check: a reading that was not refused was sent to review';")
  expect(code).toContain("raise exception 'post-check: the Inbox does not accept kind boost_study_load: %', v_hooks;")
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
  expect(code).toContain('comment on table pipeline.boost_study_load_reviews is')
  expect(code).toContain('alter table pipeline.boost_study_load_reviews enable row level security;')
})
