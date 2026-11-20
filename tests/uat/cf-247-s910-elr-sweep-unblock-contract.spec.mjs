// Guards: CF-247 s910 (session S1-ELR-Bands-And-Crawl, 21 Nov 2026): elr-det-sweep never stops on one answer: each answer is recorded in its own sub-transaction and one that fails is marked failed with its error; the central writer never proposes a page text that already has a proposal (the unique key provider_policy_proposals_key), it holds its reads with that reason
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261121120000_cf247_s910_elr_sweep_unblock.sql', 'utf8')
const fn = (name) => { const a = MIG.indexOf(`create or replace function ${name}(`); return MIG.slice(a, MIG.indexOf('$f$;', a)) }

test('the central writer does not propose the same page text twice', () => {
  const w = fn('security.elr_central_record_v1')
  expect(w).toContain('on conflict (fact_source_id, parser, content_hash) do nothing')
  expect(w).toContain("'held: this page text was read before and its reading was superseded or rejected'")
})

test('each answer is recorded on its own; a failing one is marked failed and the run goes on', () => {
  const t = fn('security.elr_det_sweep_tick_v1')
  expect((t.match(/exception when others then\n\s+v_rec := jsonb_build_object\('record_error', left\(sqlerrm, 300\)\);/g) || []).length).toBe(3)
  for (const tbl of ['elr_det_requests', 'elr_central_requests', 'elr_band_requests'])
    expect(t).toContain(`update pipeline.${tbl} set status = 'failed', finished_at = now(), result = v_rec where id = q.id;`)
})

test('housekeeping and safety', () => {
  for (const h of ['0be7443fed0de9e78250a8f5e20db812', '1e9d7b44a5f6c2114c47edc1244d81fc']) expect(MIG).toContain(`'${h}'`)
  expect(MIG).toMatch(/^-- Replaces: .+\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\./m)
  expect(MIG).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(MIG).not.toMatch(/cron\.schedule\(|create table/i)
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
})
