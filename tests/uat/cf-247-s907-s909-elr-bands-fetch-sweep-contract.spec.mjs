// Guards: CF-247 s907 to s909 (session S1-ELR-Bands-And-Crawl, Platform Admin 21 Nov 2026 09:00 AEDT): the band writer is insert only behind the s842 gates (no overwrite, 7,585 manual locks, Layer 4) and holds an undefined band, sends more than one band, differing values, regulated disciplines, shared pages and the audit sample to Layer 4; the one-off central English fetch is bounded (at most 100 pages, 12 a call), runs only under an on-demand request scoped to central (Firecrawl, no model), never re-sends a lost page, skips pages that are not admission pages and closes the request when done; all inside elr-det-sweep with no new job; G3 75/48, locks and cron count checked
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121110000_cf247_s904_s909_elr_bands_and_central_fetch.sql', 'utf8')
const W = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const fn = (name) => { const a = MIG.indexOf(`create or replace function ${name}(`); return MIG.slice(a, MIG.indexOf('$f$;', a)) }

test('s906: the band writer is insert only behind the s842 gates; Layer 4 and holds as stated', () => {
  const w = fn('security.elr_band_record_v1')
  expect(w).toContain("on conflict (course_id, english_test_id) do nothing")
  expect(w).not.toMatch(/update catalogue\.course_english_requirements|delete from/i)
  for (const s of ["'course already holds an English requirement (no overwrite)'", "'English set by hand (manual lock)'", "'course held by Layer 4'", "'English already waiting in Layer 4'",
                   "'course page names no English band'", "the band is not defined on the university''s central page", "names more than one English band", "give different values for English",
                   "'Regulated discipline ('", "shared by several courses", "'Audit sample: "]) expect(w).toContain(s)
  for (const d of ['nursing', 'midwifery', 'medicine', 'allied health', 'education', 'law', 'social work']) expect(w).toContain(`'${d}'`)
  expect(w).toContain("'elr-band:' || replace(v_bands[1], ' ', '-') || ':' || lower(d.code)")
  expect(fn('security.elr_band_claim_v1')).toContain("not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active')")
})

test('s907: the fetch is bounded, governed by an on-demand request scoped to central, and never re-sends a lost page', () => {
  expect(MIG).toContain("limit security.pipeline_num_v1('elr_central_fetch.max', 100)::int")
  expect(MIG).toMatch(/'elr_central_fetch\.max'[\s\S]{0,400}to_jsonb\(100\), 0, 100,/)
  expect(MIG).toContain("perform security.on_demand_open_v1('claude_session', v_reason, v_ids, v_est, null, array['firecrawl']);")
  expect(MIG).toContain("perform security.on_demand_scope_v1(v_id, array['central']);")
  expect(fn('security.elr_central_fetch_claim_v1')).toContain("r.state = 'open' and r.expires_at > now()")
  expect(fn('security.elr_central_fetch_claim_v1')).toContain('least(p_limit, 12)')
  expect(MIG).toContain("security.on_demand_close_v1(v_od)")
  expect(MIG).toContain("update pipeline.elr_central_fetches set status = 'lost', done_at = now() where request_id = q.id and status = 'sent';")
  expect(MIG).toContain("coalesce(f.http_status, 0) not in (401, 403, 404, 410, 451)")
  expect(MIG).toContain("and f.url ~* '(requirement|proficien|admission|entry|polic|english[-_]language[-_]test)'")
  const at = W.indexOf('if (mode === "elr_central_fetch") {'), block = W.slice(at, W.indexOf('if (mode === "elr_det_read") {', at))
  expect(block).toContain('await useFcWhy("provider_facts_scrape", it.provider_id, it.url)')
  expect(block).toContain('.slice(0, 12)')
  expect(block).not.toMatch(/openrouter|svc_provider_policy_record|englishPolicy\(/i)
})

test('s908: all inside elr-det-sweep; no new job; settings are read, not written in code', () => {
  expect(MIG).not.toMatch(/cron\.schedule\(/)
  for (const k of ['elr_band.on', 'batch.elr_band', 'elr_central_fetch.on', 'batch.elr_central_fetch', 'elr_central_fetch.max']) expect(MIG).toContain(`security.pipeline_num_v1('${k}'`)
  const t = fn('security.elr_det_sweep_tick_v1')
  expect(t).toContain("jsonb_build_object('mode', 'elr_band_read', 'items', v_bpages)")
  expect(t).toContain("jsonb_build_object('mode', 'elr_central_fetch', 'items', v_fitems)")
  expect(t).toContain("security.elr_band_defs_record_v1(v_res->'pages', v_res->>'extractor')")
})

test('s909: housekeeping and safety', () => {
  for (const h of ['41ad1af0f4e92763cbd4a906c420e42b', '53cb89fe0e2b9173b4366860491b2e42', 'a82317fb3f481021336b4fb45d5bf461']) expect(MIG).toContain(`'${h}'`)
  expect(MIG).toMatch(/^-- Replaces: .+\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(MIG).toContain("raise exception 'post-check: the manual locks changed'")
  expect(MIG).toContain("raise exception 'post-check: the number of active cron jobs changed'")
  expect((MIG.match(/comment on table pipeline\.elr_/g) || []).length).toBe(6)
  expect(MIG).not.toMatch(/openrouter|enrich_ai/i)
})
