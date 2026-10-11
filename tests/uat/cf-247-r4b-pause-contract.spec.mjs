// CF-247 v2.15.237 (R4 part 2): Platform Admin bug list of 10 Oct 2026 — Feature 4, decision "Hide and pause work". Automatic
// background work skips providers that are unpublished or not active; work started by hand is not blocked.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261010006900_cf247_r4b_pause_unpublished_work.sql'
const PICKERS = ['svc_coverage_discovery_next(integer)', 'svc_coverage_site_next(integer)', 'svc_coverage_read_next(integer)', 'svc_coverage_ai_match_next(integer)',
  'svc_course_link_search_next(integer)', 'svc_site_hint_next(integer)', 'svc_provider_contact_next(integer)', 'svc_cricos_peo_next(integer)',
  'svc_provider_facts_read_next(integer)', 'svc_provider_facts_search_next(integer)', 'svc_scholarship_candidate_next(integer)', 'svc_scholarship_discover_next(integer)',
  'svc_scholarship_read_next(integer)', 'svc_scholarship_search_next(integer)', 'svc_coverage_tuition_handoff_next(integer)', 'svc_coverage_reextract_next(integer,text)',
  'svc_coverage_reidentify_next(integer,text)', 'coverage_bind_tick_v1(integer)', 'course_link_search_tick_v1(integer)', 'adapter_overwrite_v1(integer)']

test('server: every automatic picker skips hidden providers, md5-guarded, nothing dropped', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  for (const p of PICKERS) expect(sql).toContain(p)
  // 21 = 20 pickers, plus the second place in the course link search tick
  expect(sql.match(/not exists \(select 1 from security\.provider_hidden_v1 h where h\.provider_id = /g).length).toBe(21)
  for (const md5 of ['fbf36cac0afff896ea3c57d78f267321', '1fa1e0343306c940074cb71deb212dcd', '56a2166538e89ffcfb78ec86acb5fdcc', '4ac19108008011bf23a98bdd77d63957', '6ec9d1c6b0cc116d389d753af6cadb00']) expect(sql).toContain(md5)
  // hand-started work is not blocked: the Firecrawl run and adapter apply pickers are not replaced
  for (const f of ['svc_fc_run_next', 'svc_adapter_apply_next', 'firecrawl_backlog_v1', 'firecrawl_targets_v1']) expect(sql).not.toContain(`FUNCTION public.${f}`)
  expect(sql).not.toMatch(/\b(drop\s+(table|function|schema|index|view)|delete\s+from|truncate)\b/i)
  expect(sql).toContain("update catalogue.providers p set email = null, updated_at = now() from _r4b_bad b where p.id = b.provider_id and p.email = b.email;")
})

test('worker: contact email must be on the provider\'s own domain; library and similar mailboxes skipped', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toMatch(/coverage-sweep-worker-v0\.(?:17\.(3[5-9]|[4-9][0-9])|1[8-9]\.\d+)/)
  expect(w).toContain('(SUF.test(d) && regLabel(d) === regLabel(siteHost))')
  expect(w).not.toContain('d.split(".")[0] === label')
  expect(w).toContain('const NEG2 = /(librar|vethosp|veterinar|hospital|clinic|ethics|philanthrop|partnership|helpdesk|facilit|research)/i;')
})

test('UI: the Published switch says background work pauses', () => {
  expect(fs.readFileSync('src/mature-main.jsx', 'utf8')).toContain('and pause its background work')
  expect(fs.readFileSync('src/guide/platformGuide.js', 'utf8')).toContain('pauses its background work')
})
