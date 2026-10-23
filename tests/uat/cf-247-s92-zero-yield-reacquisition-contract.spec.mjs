// CF-247 zero-yield page re-acquisition (Platform Admin 24 Oct 2026 07:43). Contracts on the migration source.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024003000_cf247_zero_yield_reacquisition.sql', 'utf8')

test('negative evidence and snapshots: tables commented, RLS on; settings with ranges; automatic reset off by default', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate|delete\s+from)\b/im)
  expect(m).toContain('create table if not exists pipeline.page_rejections (')
  expect(m).toContain('comment on table pipeline.page_rejections is')
  expect(m).toContain('alter table pipeline.page_rejections enable row level security;')
  expect(m).toContain('create table if not exists pipeline.zero_yield_snapshots (')
  expect(m).toContain('comment on table pipeline.zero_yield_snapshots is')
  for (const k of ['zero_yield.min_bound', 'zero_yield.flag_rate_pct', 'zero_yield.title_overlap_min', 'zero_yield.off_pattern_share_max', 'zero_yield.candidate_overlap_min', 'zero_yield.listing_url_pattern', 'zero_yield.not_found_pattern', 'zero_yield.reset_per_provider', 'zero_yield.providers_per_run', 'zero_yield.auto_reset', 'zero_yield.urls_max_age_days', 'zero_yield.level_words', 'zero_yield.detect_providers_per_run', 'retention.zero_yield_snapshots_days']) expect(m).toContain(`'${k}'`)
  expect(m).toContain(`'number', '0'::jsonb, '0', '1', 'on/off', 710, 'Zero-yield pages'`)
})

test('verify: zero-yield alone never resets; verified-wrong needs a signal; manual bindings never touched', () => {
  expect(m).toContain("(b.enrich_tried and not b.admitted and not b.enrich_stated and not b.fee_stated and not b.extract_stated) zero,")
  expect(m).toContain("(coalesce(z.basis, '') <> 'manual' and ((z.zero and (z.listing or z.not_found or z.title_overlap < s.t_min)) or (z.pattern_share < s.off_max and coalesce(cand.ov, 0) >= s.c_min))) verified_wrong")
  expect(m).toContain("and not exists (select 1 from unnest(u.tokens) w where w = any (s.level_words) and not (w = any (z.ttok)))")
})

test('reset and re-acquire through existing lanes: existing statuses, rejections consumed by reidentify and the AI match, item-5 retraction, finder refresh', () => {
  expect(m).toContain("set status = 'mismatch', read_status = 'identity_mismatch', leased_until = null, next_read_at = now(), read_attempts = 0")
  expect(m).toContain("and p.status = 'bound' and coalesce(p.basis, '') <> 'manual';")
  expect(m).toContain("v_fill := security.course_url_fill_v1();")
  expect(m).toContain("work = jsonb_build_object('again', true, 'reason', 'zero-yield re-acquisition')")
  expect(m).toContain("select pg_temp.edit_n('public.svc_coverage_reidentify_next(integer,text)', 'ddd0fda00a869ce2bcfb2062502775eb', array[")
  expect(m).toContain("and not exists (select 1 from pipeline.page_rejections x where x.course_id = p.course_id and x.url = p.url)")
  expect(m).toContain("select pg_temp.edit_n('security.coverage_ai_match_prepare_v1(integer,integer)', '3d6d0e1d90e210aa02eef8a962906e12', array[")
  expect(m).toContain("array[$o$security.course_list_bonus_v1(co.id, co.provider_id)$o$, $n$security.page_match_bonus_v1(co.id, co.provider_id)$n$],")
  expect(m).toContain("union select x.course_id, x.url from pipeline.page_rejections x join c using (course_id)")
  expect(m.indexOf("insert into pipeline.automation_catalogue(jobname")).toBeLessThan(m.indexOf("select cron.schedule('zero-yield-detect'"))
  expect(m).toContain("select cron.schedule('zero-yield-detect', '21 * * * *', $$select security.zero_yield_detect_v1()$$);")
})
