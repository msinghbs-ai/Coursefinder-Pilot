// Guards: AER missing-university strategy (Platform Admin 3 Nov 2026 16:24; admin docs/platform/aer/2026-11-03-missing-universities-source-and-reader-strategy.md) — verified sources only, attachment by paste file, report classes not status values
// Workstream C: an accountable source inventory for the eight universities with no entry-requirement source (free, read-only discovery; no URL
// invented), report classifications and source fingerprints on the coverage ledger, root causes and remedies for the blocked, rendered-only and
// reader cases; the verified sources are attached only by a count-guarded paste file the Integration Controller applies. The database behaviour runs
// on isolated fixtures by tests/fixtures/ops-aer-missing/run.sh. G2, G3 and housekeeping are guarded centrally (s32, s57, s42) and not re-asserted here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261104090000_cf247_ops_c_aer_missing_universities.sql'
const m = fs.readFileSync(MIG, 'utf8')
const PASTE = fs.readFileSync('docs/paste/PASTE-20261104-aer-missing-university-sources.sql', 'utf8')
const ROLL = fs.readFileSync('docs/paste/PASTE-20261104-aer-missing-university-sources-rollback.sql', 'utf8')
const fx = (f) => fs.readFileSync(`tests/fixtures/ops-aer-missing/${f}`, 'utf8')
const EIGHT = ['6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'c5c5d225-3d4c-4e41-8275-78eddd261073', 'fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'fec52f92-a8a3-4de8-a862-06f355e4e2f7',
  '030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6', '551383f9-7732-4588-a843-dd2b97c13f6f']

test('the inventory covers the eight universities; the migration attaches nothing and edits only workstream C functions, md5-guarded', () => {
  for (const id of EIGHT) expect(m, id).toContain(`('${id}'`)
  expect(m).not.toMatch(/insert into pipeline\.entry_matrix_sources/)
  const guarded = [...m.matchAll(/select pg_temp\.edit_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s]) => s)
  expect(guarded).toEqual(['security.aer_coverage_v1(uuid[])', 'security.coverage_due_v1(text,integer)', 'security.aer_course_population_v1()'])
  // Release C: only the population's order is edited (authorised 3 Nov 2026 18:30), from its live md5, behind a switch
  expect(m).toContain("select pg_temp.edit_once('security.aer_course_population_v1()', 'f6cac5f2357e2091b9884295428341bb', '0eb8ddc8b94133648ced5e8750752011'")
  expect(m).toMatch(/'coverage\.aer_reader_priority_on'[\s\S]{0,900}?'boolean', 'true'::jsonb/)
  expect(fx('fixtures.sql')).toContain("'M4 off: types then name, as before'")
  for (const f of ['aer_schedule_', 'entry_matrix_enabled_v1', 'entry_matrix_fire_v1', 'course_entry_eligible_v1', 'course_entry_programme_v1', 'aer_course_outcomes_build_v1'])
    expect(m, f).not.toMatch(new RegExp(`(create or replace function|edit_once\\(')security\\.${f}`))
  expect(fx('run.sh')).toContain(`grep -c ': already applied$')" = 3`)
})

test('no URL is invented: every inventory URL is on the university\'s own domain, a blocked site has none, only readable pages are attached', () => {
  const urls = [...m.matchAll(/\('[0-9a-f-]{36}', '(https:[^']+)'/g)].map((x) => x[1])
  for (const u of urls) expect(u).toMatch(/^https:\/\/(www\.)?(cdu|une|torrens|acu|jcu|cqu|unisq)\.edu\.au\//)
  expect(m).toMatch(/\('c5c5d225-3d4c-4e41-8275-78eddd261073', null, 'landing', 'blocked_site'/)
  expect(m).toContain("if exists (select 1 from pipeline.aer_source_inventory where attach and outcome not in ('verified_attachable', 'verified_general_only'))")
  expect(fx('fixtures.sql')).toContain("'M1 Deakin: blocked, no URL invented'")
})

test('attachment is a count-guarded paste file of exactly the inventory URLs, with a rollback refused once a page has been read', () => {
  expect(PASTE).toContain('PASTE FILE. Not applied by any migration.')
  expect(PASTE).toContain("if v_n <> 4 then raise exception 'guard: % of 4 sources are in the inventory marked for attachment; nothing changed', v_n; end if;")
  expect(PASTE).toContain("insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via)")
  for (const u of ['https://www.cdu.edu.au/international/how-apply/entry-requirements', 'https://www.unisq.edu.au/international/apply/entry-requirements',
                   'https://www.une.edu.au/international/apply/eligibility/academic-requirements', 'https://www.torrens.edu.au/apply-online/admissions-criteria']) {
    expect(PASTE).toContain(u); expect(m).toContain(u); expect(ROLL).toContain(u)
  }
  expect(ROLL).toContain('s.read_at is null and s.content_hash is null and not exists (select 1 from pipeline.entry_matrix_runs r where r.source_id = s.id)')
  expect(fx('run.sh')).toContain('rollback: removes the 4 while unread; refused once one has been read')
})

test('the staged status keeps attachment, reading, Layer 4 readiness, admission and publication apart; publication only from the projection', () => {
  const st = m.slice(m.indexOf('create or replace function security.aer_provider_stage_v1'), m.indexOf('comment on function security.aer_provider_stage_v1'))
  for (const k of ["'attached'", "'matrix_held_reasons'", "'judgement_ready'", "'technically_blocked'", "'matrix_active'", "'course_rows_active'", "'provider_matrix_rows_published'"]) expect(st, k).toContain(k)
  expect(st).toContain("public.website_v2_provider(r.stable_key)")
  expect(st).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(fx('fixtures.sql')).toContain("'M5 Harbour: read done, blocked, nothing admitted: '")
})

test('report classes are not status values; the ledger carries class, fingerprint and inventory; incremental on inventory changes', () => {
  for (const c of ['no_source', 'source_found', 'read_held', 'awaiting_layer4', 'active', 'course_only', 'evidenced_non_publication'])
    expect(m.slice(m.indexOf('create or replace function security.aer_source_class_v1'), m.indexOf('comment on function security.aer_source_class_v1'))).toContain(`'${c}'`)
  expect(m).not.toMatch(/alter table pipeline\.entry_matrix_sources|check \(status in/)
  expect(m).toContain("'aer_class', security.aer_source_class_v1(h.id),")
  expect(m).toContain("union all select i.provider_id, i.recorded_at from pipeline.aer_source_inventory i, w where p_domain = 'aer' and i.recorded_at > w.since")
  expect(fx('fixtures.sql')).toContain("'M2 no new status value'")
})

test('the rendered pilot uses the existing host list only, is capped to two pages, and rolls back to the four hosts exactly', () => {
  const pilot = fs.readFileSync('docs/paste/PASTE-20261104-aer-render-pilot.sql', 'utf8')
  const back = fs.readFileSync('docs/paste/PASTE-20261104-aer-render-pilot-rollback.sql', 'utf8')
  expect(pilot).toContain("v_before || '[\"jcu.edu.au\", \"unisq.edu.au\"]'::jsonb")
  expect(pilot).toContain("if v_n <> 2 then raise exception 'guard: % entry pages on the pilot hosts, expected exactly 2; rolled back', v_n; end if;")
  expect(pilot).not.toMatch(/toolset_key = 'firecrawl'|key = '(daily_budget|daily_share|scholarship_cap)/)  // no Firecrawl limit is changed
  expect(back).toContain("set value = '[\"wgtn.ac.nz\", \"whitireiaweltec.ac.nz\", \"newcastle.edu.au\", \"griffith.edu.au\"]'::jsonb")
  expect(fs.readFileSync('docs/paste/MEASURE-20261104-aer-render-pilot.sql', 'utf8')).not.toMatch(/\b(insert|update|delete)\b/i)
  expect(fx('run.sh')).toContain('render pilot: two hosts added, exactly two pages')
})
