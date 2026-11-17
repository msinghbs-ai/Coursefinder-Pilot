// Guards: Boost runs continuously, on the course's own page only (Platform Admin 17 Nov 2026 22:50, and the first live results of 23:22 to 23:30): the Boost windows are opened to the whole day by their settings; the squash lock (Thu 19 Nov 2026 01:15 to 03:30 Melbourne) still closes both gates and promotion; a stored page whose text is also stored for another course is never claimed; Boost's spend goes to the AI spend ledger so the route cap counts it; the change qualifies no model, so everything stays shadow
// CF-247 S590. Migration 20261118011000_cf247_boost_continuous_and_page_rules (with worker coverage-sweep v1.0.10, guarded by s587). G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118011000_cf247_boost_continuous_and_page_rules.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const strip = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const fn = (src, name) => { const i = src.indexOf(`create or replace function ${name}`); return src.slice(i, src.indexOf('end $function$;', i)) }
const claim = fn(code, 'security.boost_extract_claim_v1')
const oldClaim = strip(fn(fs.readFileSync('supabase/migrations-archive/20261117235000_cf247_boost_extract.sql', 'utf8'), 'security.boost_extract_claim_v1'))

test('all day is a matter of settings, and the squash lock starts at the freeze', () => {
  expect(code).toContain("(values ('boost.ingest_window_start_minute', to_jsonb(0)), ('boost.ingest_window_end_minute', to_jsonb(1440)),\n               ('boost.quiet_window_start_hour', to_jsonb(0)), ('boost.quiet_window_end_hour', to_jsonb(24))) v(key, value)")
  expect(code).toContain("update pipeline.platform_toolset_settings set value = to_jsonb(1795011300), updated_at = now(),")
  expect(new Date(1795011300 * 1000).toISOString()).toBe('2026-11-18T14:15:00.000Z')   // Thu 19 Nov 2026 01:15 Melbourne
  expect(code).toContain("raise exception 'post-check: a Boost gate is open inside the squash lock (Thu 01:15 to 03:30)'")
  expect(code).toContain("raise exception 'post-check: promotion ran inside the squash lock'")
  expect((code.match(/create or replace function/g) || []).length).toBe(1)   // only the claim; the gates and promotion are not touched
})

test('throughput is settings, the route\'s own caps and the schedules; the job commands are not rewritten', () => {
  expect(code).toContain("(values ('batch.boost_extract', to_jsonb(40)), ('boost.ingest_files_per_run', to_jsonb(10))) v(key, value)")
  expect(code).toContain("update pipeline.ai_service_routes set daily_usd_cap = 3, daily_calls_cap = 5000, changed_at = now(),")
  expect(code).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'boost-extract'), schedule := '* * * * *');")
  expect(code).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'worker-boost-bulk-ingest'), schedule := '*/2 * * * *');")
  expect(code).not.toMatch(/cron\.schedule\(|command :=/)
  expect(code).toContain("raise exception 'post-check: a Boost job is inactive or holds a number'")
})

test('the claim differs from its predecessor only by the shared-page rule and the cost reset', () => {
  const back = claim
    .replace("    with shared as (\n      select e.content_hash from pipeline.evidence_artifacts e\n       where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null and e.content_hash is not null\n       group by e.content_hash having count(distinct e.entity_id) > 1),\n    cand as (\n", '    with cand as (\n')
    .replace('select e.id, e.storage_path, e.source_url, e.content_hash from', 'select e.id, e.storage_path, e.source_url from')
    .replace('         and not exists (select 1 from shared h where h.content_hash = a.content_hash)\n', '')
    .replace(',\n                                          cost = null, model_called = null', '')
  expect(back).toBe(oldClaim)
  expect(claim).toContain('and not exists (select 1 from shared h where h.content_hash = a.content_hash)')
  expect(code).toContain("raise exception 'post-check: a page stored for more than one course was claimed'")
})

test('Boost spend reaches the ledger, the earlier readings are released, and no model is qualified', () => {
  expect(code).toMatch(/create trigger ai_spend_capture after insert or update of cost on pipeline\.boost_extract_items\s+for each row execute function security\.ai_spend_capture_v1\('boost_extract', 'delta', '\{cost\}'\);/)
  expect(code).toContain("raise exception 'post-check: Boost spend would not land on the service boost_extract'")
  expect(code).toContain("update pipeline.boost_extract_items set state = 'released', note = 'read again under study-load-windows-v2 (worker v1.0.10)', done_at = now()")
  expect(code).not.toMatch(/insert into pipeline\.boost_model_qualifications/)
  expect(code).toContain("raise exception 'post-check: no model may be qualified for admission by this change'")
  expect(code).not.toMatch(/update catalogue\.|\b(drop|delete from|truncate)\b/i)
})
