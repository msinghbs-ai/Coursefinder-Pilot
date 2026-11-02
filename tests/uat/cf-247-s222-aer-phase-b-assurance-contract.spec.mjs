// Guards: CF-247 AER Consolidated Development, Coverage Recovery and Continuous Assurance Mandate (Platform Admin 2 Nov 2026 14:45), §16 Phase B with §11, §13, §14 and §17 scenarios 14-21, 23, 24; the Platform Admin's catalogue-first correction (2 Nov 2026 15:43); D-A7 (~16:40); Layer 4 recovery mandate 16:33 §9
// "Introduce evidence-backed source-section manifests. Add persistent gap fingerprints and history. Implement lightweight reconciliation and
// delta detection. Prove source-read versus extraction-completeness distinction. Build initial Admin progress metrics." The behaviour runs on
// isolated fixtures by tests/fixtures/aer-phase-b/run.sh (scratch PostgreSQL with the live column definitions; the edited definitions are
// rebuilt from this repository's migrations and checked against the live md5s; real RMIT runs and admitted rows, other providers labelled
// synthetic, no invented admission value). This spec holds the contract, the fixtures' scenario lines and the Coverage & completeness panel.
// G2, G3 and housekeeping are guarded centrally (s32, s57, s42).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'

const MIG = 'supabase/migrations/20261102110000_cf247_aer_phase_b_assurance.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/aer-phase-b'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const fixtures = fx('fixtures.sql'), setup = fx('setup.sql'), run = fx('run.sh')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('$function$;', a)) }
const ui = fs.readFileSync('src/AerCoverage.jsx', 'utf8')

const EDITS = [
  ['public.admin_aer(text,jsonb)', '5e58f5d6126b3b2fe026e376a56c7686', '0593747bb6ddd55c785fc445a06eb242'],
  ['security.ops_scorecard_record_v1()', 'e0031afa54d1afb992fc74805ee0e623', 'a4b9b21d49bf92c38054858985beecb2'],
]

test('two md5-guarded edits; the fixture run rebuilds the live definitions, checks the same md5s and applies the migration twice', () => {
  const edits = [...m.matchAll(/select pg_temp\.edit_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(edits).toEqual(EDITS)
  expect(code).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(code).not.toContain('__AFTER')
  expect(run).toContain('"5e58f5d6126b3b2fe026e376a56c7686 e0031afa54d1afb992fc74805ee0e623 6880db9e624650116a722853bdea974b c44b2ba7626e74fa46cf19a2561b3499"')
  expect(run).toContain('"0593747bb6ddd55c785fc445a06eb242 a4b9b21d49bf92c38054858985beecb2 6880db9e624650116a722853bdea974b c44b2ba7626e74fa46cf19a2561b3499"')
  expect(run).toContain("grep -c 'already applied' | grep -qx 2")
  expect(m).toMatch(/^-- Replaces: public\.admin_aer, security\.ops_scorecard_record_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})

test('B1-B3: manifests from stored runs; findings by a stable fingerprint; resolved only with closure evidence; reopened when found again', () => {
  expect(fn('security.aer_fingerprint_v1')).toContain("md5(concat_ws('|', p_provider::text, coalesce(p_source::text, ''), p_scope_kind, coalesce(p_scope_key, ''), coalesce(p_level, ''), p_cause))")
  expect(m).toContain('fingerprint text not null unique')
  expect(m).toContain("state text not null default 'open' check (state in ('open', 'resolved', 'reopened'))")
  expect(m).toContain("event text not null check (event in ('opened', 'resolved', 'reopened'))")
  expect(m).toContain('unique (source_id, content_hash)')
  const r = fn('security.aer_reconcile_v1')
  expect(r).toContain("if not pg_try_advisory_xact_lock(hashtext('aer-reconcile')) then  -- fixed: lock key")
  expect(r).toContain("set state = 'reopened', resolved_at = null, reopen_count = g.reopen_count + 1")
  expect(r).toContain('v_ev := security.aer_closure_evidence_v1(f.root_cause, f.provider_id, f.source_id, f.study_level, f.scope_kind, f.scope_key);\n    if v_ev is not null then')
  expect(r).toContain("limit greatest(v_lim, 0)")
  // read-only over the AER data: the reconcile writes only its own tables, the aer health row and aer:* issues; no AI, no fetch
  for (const t of [...r.matchAll(/(?:insert into|update)\s+([a-z_]+\.[a-z_]+)/g)].map((x) => x[1])) expect(['pipeline.aer_reconcile_runs', 'pipeline.aer_source_manifests', 'pg_temp.aer_cur', 'pipeline.aer_gap_findings', 'pipeline.aer_gap_events', 'pipeline.aer_coverage_daily', 'pg_temp.aer_prov', 'pipeline.aer_provider_coverage', 'pipeline.aer_review_readiness', 'pipeline.platform_issues', 'pipeline.platform_health_checks']).toContain(t)
  for (const f of ['security.aer_reconcile_v1', 'security.aer_current_findings_v1', 'security.aer_closure_evidence_v1', 'security.aer_measures_v1', 'security.aer_coverage_read_v1', 'security.aer_weekly_section_v1'])
    expect(fn(f).split('\n').filter((l) => !/^\s*--/.test(l)).join('\n'), f).not.toMatch(/openrouter|firecrawl|net\.http_|svc_pilot_submit|entry_matrix_read|layer4_review_items\s+set|ai_use_/i)
  expect(fn('security.aer_closure_evidence_v1')).toContain("if coalesce(r.c->>'status', '') = 'complete' or (coalesce(r.c->>'status', '') = 'not_applicable' and r.n_rows > 0) then")
})

test('severities and root causes as the mandate defines; one root cause linked to every provider it affects', () => {
  for (const [c, s] of [['consumer_unevidenced', 'P0'], ['consumer_unadmitted', 'P0'], ['consumer_number_without_scale', 'P0'], ['non_country_heading', 'P1'], ['requirement_type_columns', 'P1'],
    ['reader_omission', 'P1'], ['unscaled_column', 'P1'], ['pdf_table_layout', 'P1'], ['policy_hold', 'P1'], ['extraction_failed', 'P1'], ['course_read_held', 'P1'],
    ['manifest_unparsed', 'P2'], ['not_extracted', 'P2'], ['source_unreadable', 'P2'], ['stale_source', 'P2'], ['no_source', 'P2'], ['awaiting_layer4', 'P2'],
    ['row_cap', 'P1'], ['quote_mismatch', 'P1'], ['missing_score_basis', 'P1'], ['programme_variant', 'P1'], ['evidence_incomplete', 'P1'], ['superseded_read', 'P2']]) expect(m).toContain(` ('${c}', `), expect(m).toMatch(new RegExp(` \\('${c}', '[^']+', '${s}', `))
  const c = fn('security.aer_run_cause_v1')
  expect(c).toContain("when p_error ~* '^held_unparsed: not a country table: no country' then 'non_country_heading'")
  expect(c).toContain("when p_state = 'done' and p_completeness = 'incomplete' then 'reader_omission'")
})

test('15:43 correction: the gap queue is the catalogue anti-join, with report dispositions, exact ids, priority and a population delta', () => {
  const st = fn('security.aer_provider_states_v1')
  expect(st).toContain('with el as (select e.provider_id, e.country from security.aer_eligible_v1() e)')
  expect(st).not.toMatch(/entry\.providers|course_read_providers/)
  for (const d of ['not_discovered', 'source_held', 'reader_failed', 'awaiting_layer4', 'active_verified', 'course_only', 'source_not_published_evidenced', 'not_applicable_evidenced'])
    expect(m).toContain(`'${d}'`)
  expect(m).toContain("disposition text not null check (disposition in ('not_discovered', 'source_held', 'reader_failed', 'awaiting_layer4', 'active_verified', 'course_only',")
  expect(st).toContain("when d.cact > 0 then 'course_only'                                   -- no matrix source, but course-level requirements are active")
  expect(st).toContain("left join pipeline.layer4_review_items li on li.id = r.review_item_id")
  expect(st).toContain("case when pv.ptype in (select code from pt) then 1 else 2 end tier")
  expect(m).toContain(`'[{"country": "AU", "providers": 1279}, {"country": "NZ", "providers": 197}]'::jsonb`)
  expect(m).toContain(`'["university", "university_college", "higher_education_institute", "tafe_polytechnic", "wananga"]'::jsonb`)
  expect(m).toMatch(/'aer\.not_applicable_provider_types'[\s\S]*?'\[\]'::jsonb/)
  const r = fn('security.aer_reconcile_v1')
  expect(r).toContain("'joined', case when v_first then null else v_joined end, 'left', v_left,")
  expect(r).toContain("'baseline', (b->>'providers')::int, 'delta', (select count(*) from pg_temp.aer_prov x where x.country = b->>'country') - (b->>'providers')::int")
  const v = fn('security.aer_coverage_verify_v1')
  expect(v).toContain("where k.iso_alpha2 in ('AU', 'NZ') and p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true")
  expect(v).toContain("'missing_from_queue'"); expect(v).toContain("'not_eligible_now'"); expect(v).toContain("'discovery_mismatch'")
  for (const id of ['6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'c5c5d225-3d4c-4e41-8275-78eddd261073', 'fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'fec52f92-a8a3-4de8-a862-06f355e4e2f7',
    '030992c3-72c6-452d-8a3b-10ceb0fd77f2', 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113', 'f02d9d9b-0eb2-4f0e-8215-27a36ae63aa6', '551383f9-7732-4588-a843-dd2b97c13f6f',
    '9109fe0c-9f44-4e2d-a136-eb00dec24701', 'd090e283-9894-49ce-baf3-e9d47f80e468', '30b81368-9003-4775-81af-60439fc3b109']) expect(setup).toContain(`'${id}'`)
  for (const p of ['PASS queue: eight universities not_discovered; RMIT and UWA source-present with distinct states; course_only; related identities apart; global IB/GAC; priority',
    'PASS population: each run reports the exact providers that joined or left; the verification query matches a fresh anti-join']) expect(fixtures).toContain(`raise notice '${p}';`)
  for (const c of ["'queue: the eight universities are not_discovered, tier 1'", "'queue: Deakin University is not Deakin College'", "'queue: RMIT UP is not RMIT'",
    "'queue: IB and GAC held as global qualification scopes'", "'queue: no not-applicable without evidence'", "'queue: admission vocabulary unchanged'"]) expect(fixtures).toContain(c)
})

test('16:33 §9 readiness classes on the same root causes; D-A7 weekly report by e-mail, admin-repository copy and dashboard, all off', () => {
  expect(m).toContain("readiness text not null check (readiness in ('review_ready', 'reader_correction_required', 'evidence_required', 'superseded_invalid', 'awaiting_human_review'))")
  expect(m).toContain('root_cause text references pipeline.aer_gap_root_causes(code)')
  const ld = fn('security.aer_review_readiness_load_v1')
  expect(ld).toContain("if li.id is null or li.status <> 'pending' or li.field_code not in ('entry_matrix_first_run', 'entry_matrix_change', 'course_entry_first_read') then")
  expect(ld).toContain('where z.settled_at is null;')
  expect(ld).not.toMatch(/update pipeline\.layer4_review_items/)
  expect(fn('security.aer_closure_evidence_v1')).toContain("if p_scope_kind = 'review_items' then")
  const md = fn('security.aer_weekly_markdown_v1')
  expect(md).toContain("return '# AER weekly report, week of '")
  expect(m).toContain('grant execute on function security.aer_weekly_markdown_v1(date) to supabase_read_only_user;')
  const wf = fs.readFileSync('.github/workflows/aer-weekly-report.yml', 'utf8')
  expect(wf).toContain("if: vars.AER_WEEKLY_REPORT_ENABLED == 'true'")
  expect(wf).toContain('- cron: "7 21 * * 0"'); expect(wf).toContain('- cron: "7 22 * * 0"')
  expect(wf).toContain(`jq -n '{query: "select security.aer_weekly_markdown_v1() as md", read_only: true}'`)
  expect(wf).toContain('cp "$RUNNER_TEMP/report.md" "docs/platform/aer-weekly/${{ steps.when.outputs.day }}.md"')
  expect(wf).toContain('git push origin aer-weekly-snapshot')
  expect(wf).not.toMatch(/secrets\.(?!SUPABASE_ACCESS_TOKEN\b)/)
  expect(wf).not.toMatch(/push -f|--force/)
  expect(fixtures).toContain("raise notice 'PASS readiness and weekly: classes loaded only for pending AER items; one finding per defect; settled never reopened; Markdown copy and dashboard';")
  expect(ui).toContain('data-aer-weekly'); expect(ui).toContain('data-aer-readiness')
})

test('B4: four measures over the eligible AU/NZ providers, numerator and denominator, by country and in all; never the reference table', () => {
  const e = fn('security.aer_eligible_v1')
  expect(e).toContain("k.iso_alpha2::text in (select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.eligible_countries'), '[]'::jsonb)))")
  expect(e).toContain("p.lifecycle_status = 'active' and p.publication_status = 'published' and p.enrols_international is true")
  const ms = fn('security.aer_measures_v1')
  expect(ms).toContain("count(*) filter (where disc and not ext_gap) extraction_n")
  expect(ms).toContain("count(*) filter (where cons and not p0) consumer_n")
  expect(ms).toContain("o.outcome in ('admitted_course', 'admitted_provider')")
  expect(ms).toContain('group by grouping sets ((c), ())')
  expect(ms).not.toMatch(/from ref\.countries/)
  expect(m).toContain('primary key (day, country)')
})

test('job aer-reconcile: hourly at :27, created paused, clear of the busy minutes; the command reads its size from a setting', () => {
  expect(m).toContain("perform cron.schedule('aer-reconcile', '27 * * * *', 'select security.aer_reconcile_v1(security.pipeline_num_v1(''batch.aer_reconcile'', 5000)::int)');")
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'aer-reconcile'), active := false);")
  const minute = 27
  expect([3, 5, 9]).not.toContain(minute % 10)
  expect(minute >= 35 && minute <= 42).toBe(false); expect([47, 48]).not.toContain(minute)
  expect(m).toContain("raise exception 'AER Phase B post-check: the job must be paused'")
})

test('§14 alerts reuse the existing issues and alert job; P0 and regression only; recovery; the Monday e-mail is built off (D-A7)', () => {
  const r = fn('security.aer_reconcile_v1')
  expect(r).toContain("values ('aer:p0', 'critical', 'admission',")
  expect(r).toContain("values ('aer:regression', 'critical', 'admission',")
  expect(r).toContain("update pipeline.platform_issues set resolved_at = now() where check_key = 'aer:p0' and resolved_at is null;")
  expect(r).toContain("if v_alerts and v_prev is not null and v_prev - coalesce(v_today, 0) >= v_reg then")
  expect(r).toContain("perform security.platform_alerts_add_v1(null, 'aer:weekly', 'raised', 'info',")
  expect(r).toContain("coalesce((security.toolset_setting('pipeline', 'aer.weekly_email_enabled') #>> '{}')::boolean, false)")
  expect(code).not.toMatch(/create table[^;]*alert/i)
  expect(m).toContain("to_jsonb(false), null, null, null, 998, 'Entry requirements'")
  expect(m).toContain("v := v || jsonb_build_object('aer', security.aer_weekly_section_v1(w));  -- CF-247 AER Phase B (mandate §14 weekly)")
})

test('B5 role model: admin_aer coverage actions need Curator (rank 3); counsellors and viewers are refused', () => {
  expect(m).toContain("if v_rank < 3 then raise exception 'curator role required: AER coverage is for operations roles' using errcode = '42501'; end if;")
  expect(m).toContain('return security.aer_coverage_read_v1(p_action, a);')
  // the only grant: the weekly Markdown copy to the read-only role the workflow uses (as the watchdog); nothing to authenticated or anon
  expect([...code.matchAll(/grant execute on function ([^ ]+) to ([a-z_]+);/g)].map((x) => `${x[1]} ${x[2]}`)).toEqual(['security.aer_weekly_markdown_v1(date) supabase_read_only_user'])
  expect(ui).toContain('export const AER_MIN_RANK=3')
  expect(fs.readFileSync('src/mature-main.jsx', 'utf8')).toContain('{rank>=3&&<AerCoverage rank={rank}/>}')
})

test('fixtures: every scenario passes on the scratch run; real data named, synthetic data labelled, no invented admission value', () => {
  for (const p of ['PASS migration: nothing run, job paused and catalogued, Monday e-mail off',
    'PASS 14 15 16 17: read-but-held and omitted sections found; global qualification scoped without a country; one root cause for every provider without a source',
    'PASS 18: an unchanged source adds no finding, event or manifest',
    'PASS 19: a corrected source closes its gap only with verified closure evidence',
    'PASS 20: a regression reopens the earlier gap with its history',
    'PASS 21: proposed and waiting rows are not counted as consumer coverage; an active row without admission is P0',
    'PASS 23: one issue per check, raised once, one recovery notice; no flood; Monday e-mail off',
    'PASS 24: Admin figures equal the database; counsellors refused; weekly scorecard section',
    'PASS read-only: the reconcile changes no catalogue row, source, run or Layer 4 item']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(setup).toContain('SYNTHETIC (named "Synthetic ..." or marked synthetic below)')
  for (const [, name] of setup.matchAll(/\(fx\.prov\('[a-z0-9_]+'\), '([^']+)'/g)) expect(name).toMatch(/^Synthetic /)
  // no synthetic row holds a minimum: min_value is written only by rows.mjs from the real admitted export
  expect(setup + fixtures).not.toMatch(/min_value|min_grade/)
  expect(fx('rows.mjs')).toContain("../entry-matrix/rmit-stored/complete-25-rows.json")
  expect(fixtures).toContain("'16: IB and GAC qualification scope'")
  expect(fixtures).toContain("'18: no new finding, no new event'")
  expect(fixtures).toContain("'20: history opened, resolved, reopened'")
  expect(fixtures).toContain("'23: raised once'")
  expect(fixtures).toContain("'24: a counsellor (rank 2) is refused'")
})

const COVERAGE = {
  as_at: '2026-11-02T05:27:10Z', day: '2026-11-02', job: { active: false, schedule: '27 * * * *' },
  measures: [
    { country: 'ALL', eligible: 1476, discovery_n: 33, extraction_n: 28, admission_n: 7, consumer_n: 21, open_p0: 0, open_p1: 14, open_p2: 1470, detail: { countries_published: 59, qualifications_active: 180, postgraduate: { active_rows: 664, proposed_rows: 807 }, layer4_pending: { course_entry_first_read: 499, entry_matrix_first_run: 40 } } },
    { country: 'AU', eligible: 1279, discovery_n: 18, extraction_n: 13, admission_n: 2, consumer_n: 6, open_p0: 0, open_p1: 13, open_p2: 1273, detail: {} },
    { country: 'NZ', eligible: 197, discovery_n: 15, extraction_n: 15, admission_n: 5, consumer_n: 15, open_p0: 0, open_p1: 1, open_p2: 197, detail: {} }],
  progress: [], open: { P0: 0, P1: 14, P2: 1470 }, changes_7d: { opened: 1484, resolved: 0, reopened: 0 },
  root_causes: [{ code: 'no_source', label: 'No official AER source recorded', severity: 'P2', providers: 1442, findings: 1442, next_action: 'Phase E discovery waves from stored copies, ordered by course count (needs D-A1).', owner_role: 'Pipeline Operator' },
    { code: 'pdf_table_layout', label: 'PDF table layout not read', severity: 'P1', providers: 4, findings: 5, next_action: 'Step B PDF route: extend the table reader for this layout (column edges, missing rules).', owner_role: 'PIM Admin' }],
  population: { eligible: 1476, first_run: false, joined: [], left: [], by_country: { AU: { eligible: 1279, baseline: 1279, delta: 0 }, NZ: { eligible: 197, baseline: 197, delta: 0 } } },
  dispositions: { not_discovered: 1427, source_held: 6, reader_failed: 2, awaiting_layer4: 20, course_only: 8, active_verified: 13 },
  providers: { total: 1476, offset: 0, page_size: 50, items: [
    { provider_id: 'p-rmit', name: 'RMIT University (RMIT)', country: 'AU', priority: 1, disposition: 'source_held', discovery: 'source_read', extraction: 'held', admission: 'active', p0: 0, p1: 8, p2: 1, sources: 36, next_action: 'Phase C2: classify qualification pages (IB, GAC) and read them as qualification rows; RMIT re-entry needs D-A2.', owner_role: 'PIM Admin', primary_url: 'https://www.rmit.edu.au/' },
    { provider_id: 'c5c5d225-3d4c-4e41-8275-78eddd261073', name: 'Deakin University (Deakin)', country: 'AU', priority: 7, disposition: 'not_discovered', discovery: 'not_discovered', extraction: 'none', admission: 'none', p0: 0, p1: 0, p2: 1, sources: 0, next_action: 'Phase E discovery waves from stored copies, ordered by course count (needs D-A1).', owner_role: 'Pipeline Operator' }] },
  alerts: [], weekly_email: false,
  readiness: { awaiting_human_review: 539 },
  weekly: { week_start: '2026-10-26', measures: { discovery: { n: 33, of: 1476, prior_week: null } }, changes: { opened: 0, resolved: 0, reopened: 0 }, decisions: [] },
}

test.describe('mocked browser', () => {
  test('Coverage & completeness › Attributes: the AER field names its measure; the panel shows four measures, open gaps, root causes and providers', async ({ page }) => {
    await mockAdmin(page)
    const calls = [], argsSeen = []
    await page.route('**/rest/v1/rpc/admin_aer', (route) => {
      const b = route.request().postDataJSON() || {}; calls.push(b.p_action); argsSeen.push(b.p_args || {})
      if (b.p_action === 'coverage_provider') return route.fulfill({ json: { active: { rows: 380, countries: ['IN', 'NP'], qualifications: 40 }, course: { active: 1303, proposed: 807 },
        sources: [{ id: 's-uk', url: 'https://www.rmit.edu.au/uk', title: 'RMIT country equivalency: united-kingdom', status: 'read', shape: 'country_table', reason: 'held_incomplete: 2 of 31 published minimums not read' }],
        findings: [{ id: 1, severity: 'P1', state: 'open', label: 'Published minimums not read', scope: 'RMIT country equivalency: united-kingdom', next_action: 'Phase C3', owner_role: 'PIM Admin', reopen_count: 0, first_seen: '2026-11-02T05:27:00Z', last_seen: '2026-11-02T05:27:00Z' }] } })
      return route.fulfill({ json: COVERAGE })
    })
    await page.goto('/#coverage?tab=attributes')
    const panel = page.locator('[data-aer-coverage]')
    await expect(panel).toContainText('Academic entry requirements')
    await expect(panel.locator('[data-aer-measure="discovery_n"]')).toContainText('33 of 1,476')
    await expect(panel.locator('[data-aer-measure="extraction_n"]')).toContainText('28 of 1,476')
    await expect(panel.locator('[data-aer-measure="admission_n"]')).toContainText('7 of 1,476')
    await expect(panel.locator('[data-aer-measure="consumer_n"]')).toContainText('21 of 1,476')
    await expect(panel.locator('[data-aer-country="NZ"]')).toContainText('197')
    await expect(panel.locator('[data-aer-sev="P1"]')).toContainText('14')
    await expect(panel.locator('[data-aer-cause="no_source"]')).toContainText('1,442')
    await expect(panel.locator('[data-aer-asat]')).toContainText('hourly job paused')
    await expect(panel.locator('[data-aer-population]')).toContainText('Australia 1,279 (baseline 1,279, no change) · New Zealand 197 (baseline 197, no change)')
    await expect(panel.locator('[data-aer-disposition="not_discovered"]')).toContainText('1,427')
    await expect(panel.locator('[data-aer-provider="c5c5d225-3d4c-4e41-8275-78eddd261073"] [data-aer-disp]')).toHaveText('Not discovered')
    await expect(panel.locator('[data-aer-provider="p-rmit"] [data-aer-states]')).toHaveText('source read · held · active')
    await expect(panel.locator('[data-aer-readiness]')).toContainText('Awaiting human review 539')
    await expect(panel.locator('[data-aer-weekly] summary')).toContainText('Weekly report, week of 2026-10-26 · Monday e-mail off')
    await panel.getByRole('button', { name: 'RMIT University (RMIT)' }).click()
    await expect(panel.locator('[data-aer-provider-detail]')).toContainText('2 of 31 published minimums not read')
    await expect(panel.locator('[data-aer-finding="open"]')).toContainText('Published minimums not read')
    await panel.locator('[data-aer-disposition="not_discovered"]').click()
    await expect.poll(() => argsSeen.some((a) => a.disposition === 'not_discovered')).toBe(true)
  })

  test('a counsellor (rank 2) sees no AER panel and the server is not asked', async ({ page }) => {
    await mockAdmin(page, { rank: 2, role: 'counsellor' })
    const calls = []
    await page.route('**/rest/v1/rpc/admin_aer', (route) => { calls.push((route.request().postDataJSON() || {}).p_action); return route.fulfill({ json: COVERAGE }) })
    await page.goto('/#coverage?tab=attributes')
    await expect(page.locator('.cc-wrap')).toBeVisible()
    await expect(page.locator('[data-aer-coverage]')).toHaveCount(0)
    expect(calls.filter((c) => c === 'coverage')).toEqual([])
  })
})
