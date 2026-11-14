// Guards: Platform Admin direction 3 Nov 2026 09:32 §7 and §4 (country-configured orchestration; no failure hidden behind a succeeded schedule)
// Workstream F, acceptance report items 5 and 7. (a) enrich_ai record time-outs (IQ-00053): the admin-jobs runner and its slices held the task
// row FOR UPDATE, which blocks the workers' foreign-key checks; they now lock FOR NO KEY UPDATE. (b) nz_cop worked but looked dead: its picker
// timed out (a correlated max() per file) and its answer had no counts (worker v0.59.3). (c) cricos-peo called the worker every minute with
// nothing due: a fire guard. (d) AU and CA written into shared orchestration move to country lists with today's values; the job command has no
// country. (e) A daily ranking edition check raises one integration issue per ranking system (created paused; imports nothing). (f) Watched
// modes, a picker held by its own daily cap is idle, and the Enrich fields lane in Pipeline yield. The behaviour runs on isolated fixtures by
// tests/fixtures/hidden-failures/run.sh (scratch PostgreSQL; thirteen live definitions loaded and checked against their live md5; the lock defect
// reproduced with two sessions; the migration applied twice). G1, G2, G3 and housekeeping are guarded centrally (s32, s42, s57).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261103140000_cf247_hidden_failures_country_config.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/hidden-failures'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('end $function$;', a) + 15) }
const EDITS = {
  'security.admin_jobs_tick_v1(integer)': ['6a482636d1f67ca41add017f8c241b01', 'e760363a6af21d850f7e6e1c86bca0cb'],
  'security.admin_job_slice_v1(uuid,integer)': ['6d9ba8d97a068061566d2790eec103fc', '88f82c974b0ecde708a0550413791d86'],
  'security.admin_job_watch_v1(uuid)': ['042c960f0f7d6fdb4d83a725e644a4a8', 'ad21305f89ee441bde462cc35e5a8a98'],
  'security.enrich_fields_slice_v1(uuid,integer)': ['b677308fffdc23e5fbd2ad54d1b97d30', '4babdac64e58459fe38d79def27842ea'],
  'public.svc_nz_cop_next(integer)': ['255c75c911ce848c7787a64194fa0722', 'e745750b29d7436a022d2227eb8fc52b'],
  'security.enrich_focus_v1(uuid)': ['803098094b9d8404ad1b9531c7e597bd', '1fe6696838ac6bbf5dec7684a536b492'],
  'security.enrich_focus_refresh_v1()': ['0588c931c545df5ef8a1b58730c9d3b5', '80e467c21f37828c4490314a216d28c7'],
  'security.scholarship_discovery_refill_v1(integer)': ['5a72808f07e2f5219518ed3fc20fcdb7', 'aa26bbc2b99e3390a4730abc2fa14992'],
  'security.integration_yield_checks_v1()': ['4c25bf79db544f8605c9c25b45fc8318', '2bcba102aa776a21c888bae711fd3374'],
  'security.pipeline_yield_v1(integer)': ['87ab2f7e7a6acf18a18c7191c9eb2b98', '2061ab3dd67f20b28f9e6327dc9ad0b0'],
}

test('ten live functions edited only from their live md5 and checked after; the fixtures load the live text and check it first', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}', array[`)
    expect(run).toContain(`["${sig}"]=${b}`)
    expect(fs.existsSync(`${FX}/live/${sig.slice(0, sig.indexOf('('))}.sql`)).toBe(true)
  }
  expect(m.match(/select pg_temp\.edit_once\(/g)).toHaveLength(10)
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(run).toContain("grep -c ': applied' | grep -qx 10")
  expect(run).toContain("grep -c 'already applied' | grep -qx 10")
  expect(run).toContain('echo "a second run added settings, jobs, catalogue or register rows"; exit 1;')
})

test('(a) IQ-00053: the runner and its slices lock the task FOR NO KEY UPDATE; reproduced before, gone after, skip-locked kept', () => {
  expect(fs.readFileSync(`${FX}/live/security.admin_jobs_tick_v1.sql`, 'utf8')).toContain('limit v_n for update skip locked loop')
  expect(fs.readFileSync(`${FX}/live/security.enrich_fields_slice_v1.sql`, 'utf8')).toContain('select * into j from pipeline.admin_jobs where id = p_id for update;')
  expect(m).toContain('limit v_n for no key update skip locked loop')
  expect(m.match(/for no key update;/g)).toHaveLength(3)
  expect(m).toContain('while locking tuple (981,9) in relation')
  expect(run).toContain('[ "$(lockall)" = "blocked blocked blocked" ]')
  expect(run).toContain('[ "$(lockall)" = "free free free" ]')
  expect(run).toContain('ok after: a second runner skips the task the first holds (skip locked unchanged)')
  // the worker's record is two updates of one item in one transaction: the second checks the foreign key
  expect(run).toContain("set cost_usd = 0.01, leased_until = null, updated_at = now() where job_id")
})

test('(b) nz_cop: the picker reads the latest batch once; worker v0.59.3 reports read and failed counts', () => {
  expect(fs.readFileSync(`${FX}/live/public.svc_nz_cop_next.sql`, 'utf8')).toContain('and e.captured_at > (select max(e2.captured_at) from pipeline.evidence_artifacts e2 where e2.source_id = e.source_id')
  expect(m).toContain('join (select e2.source_id, max(e2.captured_at) latest from pipeline.evidence_artifacts e2 join pipeline.sources s2 on s2.id = e2.source_id')
  expect(m).toContain('               and e.captured_at > m.latest')
  // the v0.59.3 note stays in the version chain once a later worker is released ("// was v0.59.3 // ...")
  expect(worker).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.59\.3"; |\n\/\/ was v0\.59\.3 )\/\/ v0\.59\.3 \(3 Nov 2026, CF-247 Workstream F, hidden failures/)
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v(?:[1-9]\d*\.\d+\.\d+|0\.(?:59\.([3-9]|[1-9]\d)|[6-9]\d\.\d+))";/)
  expect(worker).toContain('\n// was v0.59.1 // v0.59.1 (3 Nov 2026, CF-247 Workstream D, intake wording)')
  expect(worker).toContain('return j({ ok: true, mode, files: out, read: out.length, failed: nzFailed, worker: WORKER });')
  expect(fixtures).toContain("'NZ Code of Practice picker: the same files as before'")
})

test('(c) cricos-peo calls the worker only when a provider is due, by the picker\'s own eligibility; schedule and state kept', () => {
  const f = fn('security.cricos_peo_fire_v1')
  expect(f).toContain("security.pipeline_num_v1('recheck.cricos_contact_days', 180)")
  expect(f).toContain('not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)')
  expect(f).toContain("perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'cricos_peo', 'limit', security.pipeline_num_v1('batch.cricos_peo', 2)::int));")
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'cricos-peo'), command := $j$select security.cricos_peo_fire_v1()$j$);")
  expect(m).toContain("('public.svc_cricos_peo_next(integer)', '9b7675ad956065b6ba793b5e744114ad')")
  for (const c of ['cricos-peo with nothing due: the worker is not called', 'a provider due again: one worker call, its size from batch.cricos_peo', 'an unpublished provider is not due (the picker\'\'s pause respected)']) expect(fixtures).toContain(`'${c}'`)
  expect(before).toContain("'before: the job calls the worker with nothing due (the idle call)'")
})

test('(d) country lists with today\'s values; no country comparison left; the gate job carries no country', () => {
  for (const [k, v] of [['enrich.focus_countries', '["AU"]'], ['scholarship.refill_priority_countries', '["AU"]'], ['scholarship.refill_open_countries', '["AU"]'], ['country_scope.gate_countries', '["CA"]']])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}',[^\\n]*\\n[^\\n]*\\n  'list', '${v.replace(/[[\]]/g, '\\$&')}'::jsonb`))
  expect(m).toContain("or coalesce(security.coverage_country(p_provider_id), '') <> all (security.pipeline_list_v1('enrich.focus_countries', '[\"AU\"]'))")
  expect(m).toContain("where d.country_code = any (security.pipeline_list_v1('enrich.focus_countries', '[\"AU\"]')) and not exists")
  expect(m).toContain("and (k.iso_alpha2 = any (v_open) or security.scholarship_admission_provider_ok_v1(p.id))")
  expect(m).toContain("security.pipeline_num_v1('scholarship.refill_priority_focus', 4)::int else security.pipeline_num_v1('scholarship.refill_priority_other', 1)::int end")
  // the new text of the edits compares no country literal
  const newText = [...m.matchAll(/array\[\$e\$[\s\S]*?\$e\$,\s*\$e\$([\s\S]*?)\$e\$\]/g)].map((x) => x[1]).join('\n')
  expect(newText).not.toMatch(/(=|<>)\s*'(AU|NZ|CA)'/)
  expect(fn('security.country_scope_gate_run_v1')).toContain("foreach v_cc in array security.pipeline_list_v1('country_scope.gate_countries', '[\"CA\"]') loop")
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'country-scope-gate'), command := $j$select security.country_scope_gate_run_v1()$j$);")
  for (const c of ['focus with ["AU"]: the same providers searched, the same focus list and ranks as before', 'refill with today\'\'s values: the same providers, priorities and reasons as before',
    'country-scope-gate with ["CA"]: Canada, as before', 'focus with ["AU", "NZ"]: the top 2 within each country', 'country-scope-gate with ["CA", "NZ"]: both, one call each']) expect(fixtures).toContain(`'${c}'`)
})

test('(e) ranking edition check: one issue per ranking system, created paused, imports nothing', () => {
  const f = fn('security.ranking_edition_check_v1')
  expect(f).toContain("v_fp := 'ranking_edition:' || r.code;")
  expect(f).toContain("security.pipeline_list_v1('ranking.edition_calendar'")
  expect(f).toContain("make_interval(days => v_age)")
  expect(f).not.toMatch(/\b(insert into|update|delete from)\s+ranking\./i)
  expect(m).toContain("perform cron.schedule('ranking-edition-check', '14 4 * * *', 'select security.ranking_edition_check_v1()');")
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'ranking-edition-check'), active := false);")
  for (const c of ['repeated runs: no duplicate issues', 'nothing imported or changed in the ranking tables', 'an import older than ranking.import_max_age_days raises one for QS',
    'a malformed calendar entry is ignored, never an error']) expect(fixtures).toContain(`'${c}'`)
})

test('(f) watched modes, a picker held by its own daily cap is idle, the Enrich fields lane', () => {
  expect(m).toContain("or (r.failures >= v_wmin and split_part(r.key, ':', 2) = any (v_watch)) then")
  expect(m).toContain("'list', '[\"provider_description\", \"enrich_ai\"]'::jsonb")
  expect(m).toContain('v_cap := case when r.failures = 0 then security.worker_mode_capped_v1(r.key) end;')
  expect(fn('security.worker_mode_capped_v1')).toContain("when 'link_search' then security.course_link_search_cap_reason_v1()")
  expect(m).toContain("jsonb_build_object('lane', 'enrich_fields', 'label', 'Enrich fields (AI reads)', 'stages', jsonb_build_object(")
  for (const c of ['a watched mode (provider_description, 2 of 2 failed) opens its hidden-error issue on the next check',
    'link_search held by its own daily cap, no failures: idle, the zero-yield issue marked cleared (not closed)',
    'with a failure in the window the cap does not hide it: zero yield again', 'Enrich fields: invoked 2, one failed (the 500 is not success)', 'the four lanes are unchanged']) expect(fixtures).toContain(`'${c}'`)
})

test('Platform health › Integration queue shows the Enrich fields lane beside the four', async ({ page }) => {
  await mockAdmin(page, { rank: 5 })
  await page.route('**/rest/v1/rpc/admin_integration_queue', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ mode: { mode: 1, set_by: 'x', set_at: '2026-11-03T00:00:00Z', reason: 'r' }, by_status: {}, by_severity: {}, by_workstream: {}, issues: [] }) }))
  const st = (o) => ({ invoked: { calls: 1, failed_calls: 0 }, source_accessed: 0, pages_discovered: 0, read_completely: 0, extracted: 0, accepted_or_held: { accepted: 0, held: 0 }, published: 0, consumer_read_back: 0, ...o })
  await page.route('**/rest/v1/rpc/admin_pipeline_yield', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ window_hours: 24, lanes: [
    { lane: 'scholarships', label: 'Scholarships', stages: st({}) }, { lane: 'course_pages', label: 'Course pages and official links', stages: st({}) },
    { lane: 'aer', label: 'Academic entry requirements', stages: st({}) }, { lane: 'descriptions', label: 'University descriptions', stages: st({}) },
    { lane: 'enrich_fields', label: 'Enrich fields (AI reads)', stages: st({ invoked: { calls: 398, failed_calls: 173 }, pages_discovered: null, consumer_read_back: null,
      accepted_or_held: { accepted: 1265, held: 73, not_stated: 8998, failed: 2243 } }) }] }) }))
  await page.goto('/#platform-health?tab=queues') // SS-020 step 3 (Decision 269): Pipeline yield is on Queues & yield
  const y = page.locator('[data-pipeline-yield]')
  await expect(y.getByRole('columnheader', { name: 'Enrich fields (AI reads)' })).toBeVisible()
  await expect(y.locator('[data-yield-stage="invoked"] [data-yield-lane="enrich_fields"]')).toHaveText('398 calls · 173 failed calls')
  await expect(y.locator('[data-yield-stage="pages_discovered"] [data-yield-lane="enrich_fields"]')).toHaveText('—')
  await expect(y.locator('[data-yield-stage="accepted_or_held"] [data-yield-lane="enrich_fields"]')).toHaveText('1,265 accepted · 73 held · 8,998 not stated · 2,243 failed')
})
