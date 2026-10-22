import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 v2.15.310 (Platform Admin 22 Oct 2026 07:22): NZ enrichment review fixes 1, 2, 3, 4, 6, 7, 8, 9; 07:41: daily backup of the
// provider Published switch and setting values, restored only by the Platform Admin.
const q = fs.readFileSync('supabase/migrations/20261022010000_cf247_nz_review_quick_wins.sql', 'utf8')
const r = fs.readFileSync('supabase/migrations/20261022011000_cf247_nz_review_route_reader_stats.sql', 'utf8')
const b = fs.readFileSync('supabase/migrations/20261022012000_cf247_settings_backup.sql', 'utf8')
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const f = fs.readFileSync('supabase/functions/coverage-sweep/fees.ts', 'utf8')
const ui = fs.readFileSync('src/SettingsBackup.jsx', 'utf8')
const nav = fs.readFileSync('src/nav-map.js', 'utf8')

test('every change is md5-guarded, housekeeping lines present, nothing dropped at top level', () => {
  for (const m of [q, r, b]) {
    expect(m).toMatch(/^-- Replaces: /m)
    expect(m).toMatch(/^-- Retires: /m)
    expect(m).not.toMatch(/^(drop|delete|truncate)\b/im)
  }
  expect(q).toContain('differs from the definition this change replaces')
  expect(r).toContain('differs from the definition this change replaces')
})

test('quick wins: site check before search, render pass, address guesses by country, one provider flag', () => {
  for (const k of ['search.site_check_countries', 'search.min_site_course_pages', 'pages.render_countries', 'retry.course_page_render_hours', 'relink.url_pattern_countries']) expect(q).toContain(`'${k}'`)
  expect(q).toContain('and (s.requested_at is not null or not security.site_few_course_pages_v1(s.provider_id))')
  expect(q).toContain("'render_ok',(u.read_status in ('needs_render','blocked') and security.render_country_v1(u.provider_id))")
  expect(q).toContain("'course_pages_not_listed'")
  expect(w).toContain('|| it.render_ok === true')
})

test('route, reader and daily stats', () => {
  expect(r).toContain('security.site_list_match_done_v1(s.course_id, s.provider_id)')
  expect(r).toContain("security.pipeline_num_v1('ai_match.min_candidates', 2)")
  expect(r).toContain('the same page copy was read for this before and did not state it')
  expect(r).toContain('create table if not exists pipeline.toolset_use_daily')
  expect(r).toContain("select cron.schedule('toolset-use-daily', '58 19 * * *', $$select security.toolset_use_daily_record_v1()$$);")
  expect(r).toContain("('toolset-use-daily', 'Reporting'")
  expect(w).toContain('the quote is not on the page')
  expect(w).toContain('x.hint')
})

test('fee reader: null characters removed, pages without an amount skip the AI', () => {
  expect(f).toContain('export function noNul')
  expect(f).toContain('export const hasFeeAmount')
  expect(w).toContain('if (!hasFeeAmount(text))')
  expect(w).toMatch(/coverage-sweep-worker-v0\.(3[6-9]|[4-9]\d)\.\d/)
})

test('backup and restore: daily job, Platform Admin only, reason and backup before restore', () => {
  expect(b).toContain('create table if not exists pipeline.settings_backups')
  expect(b).toContain("select cron.schedule('settings-backup-daily', '50 19 * * *', $$select security.settings_backup_take_v1('daily')$$);")
  expect(b).toContain("coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required'")
  expect(b).toContain("v_before := security.settings_backup_take_v1('before_restore'")
  expect(b).toContain("if r.then_status = 'published' and r.lifecycle_status <> 'active' then")
  expect(ui).toContain("supabase.rpc('admin_settings_backup'")
  for (const s of ['data-settings-backup', 'data-backup-list', 'data-backup-diff', 'Download SQL file']) expect(ui).toContain(s)
  expect(nav).toContain("{ key: 'backup', label: 'Backup & restore', min: 6 },")
  // v2.15.311 (Platform Admin 22 Oct 2026 11:40): no "Shown" button; Restore on each backup and an always-visible Restore section
  expect(ui).not.toContain("'Shown'")
  for (const s of ['data-backup-restore-row', 'data-backup-restore-all', 'Restore this backup', 'label="Selected"']) expect(ui).toContain(s)
})

test('flags show the toolset used before them (Platform Admin 22 Oct 2026 08:12)', () => {
  const t = fs.readFileSync('supabase/migrations/20261022013000_cf247_flag_tool_stats.sql', 'utf8')
  const fp = fs.readFileSync('src/FlagsPanel.jsx', 'utf8')
  expect(t).toContain('create or replace function security.flag_tool_summary_v1(p_provider uuid, p_course uuid default null)')
  expect(t).toContain("'tools', case when x.entity in ('provider', 'course') and x.provider_id is not null")
  expect(t).toMatch(/^-- Replaces: /m)
  expect(t).not.toMatch(/^(drop|delete|truncate)\b/im)
  expect(fp).toContain('data-flag-tools')
  expect(fp).toContain('data-flag-toolline')
  expect(fp).toContain("course_pages_not_listed:'Search off: the site lists too few course pages'")
})

test('unpublished providers wait in every scheduled queue; publishing brings them back (Platform Admin 22 Oct 2026 11:42)', () => {
  const u = fs.readFileSync('supabase/migrations/20261022014000_cf247_unpublished_providers_pause.sql', 'utf8')
  expect(u).toMatch(/^-- Replaces: /m)
  expect(u).not.toMatch(/^(drop|delete|truncate)\b/im)
  for (const f of ['svc_fee_ai_next', 'svc_companion_next', 'svc_logo_find_next', 'svc_central_ai_next', 'svc_flag_check_next', 'svc_provider_policy_add_tests_next',
    'svc_scholarship_recheck_next', 'svc_scholarship_ai_next', 'svc_enrich_ai_next', 'enrich_plan_auto_v1', 'enrich_plan_tick_v1', 'field_gap_queue_tick_v1',
    'provider_onboarding_tick_v1', 'scholarship_ai_backfill_tick_v1', 'scholarship_discovery_refill_v1']) expect(u).toContain(`select pg_temp.edit_once('`)
  expect((u.match(/select pg_temp\.edit_once\('/g) || []).length).toBe(15)
  expect(u).toContain("reason = 'provider unpublished'")
  expect(u).toContain("or l.reason = 'provider unpublished'")
})

test('v2.15.312: course shows its provider switch; Adapter filter and sort; onboarding backfill; users last active', () => {
  const ds = fs.readFileSync('src/DetailSummary.jsx', 'utf8')
  const mm = fs.readFileSync('src/mature-main.jsx', 'utf8')
  const ad = fs.readFileSync('supabase/migrations/20261022016000_cf247_adapter_filter_and_backfill.sql', 'utf8')
  const um = fs.readFileSync('supabase/functions/admin-user-management/index.ts', 'utf8')
  const ar = fs.readFileSync('src/access-roles-entry.jsx', 'utf8')
  expect(ds).toContain('{onWebsite(data.provider_publication_status)}')
  expect(fs.readFileSync('supabase/migrations/20261022015000_cf247_course_detail_provider_published.sql', 'utf8')).toContain("'provider_publication_status',")
  expect(mm).toContain("{key:'_adapter',label:'Adapter',width:150,sortKey:'adapter',")
  expect(mm).toContain('label="Adapter" value={filters.adapter')
  expect(mm).toContain("if(filters.adapter&&type==='provider')a.adapter=filters.adapter;")
  expect(ad).toContain('FUNCTION security.admin_providers_page_v2(')
  expect(ad).toContain("nullif(p_args->>'adapter',''));")
  expect(ad).toContain("insert into pipeline.provider_onboarding(provider_id, source, reason, priority)")
  expect(um).toContain('serviceClient.rpc("svc_admin_access_last_active")')
  expect(ar).toContain('<th>Last active</th>')
})

test('hotfix: the pause check names its table (onboarding and automatic plans moved again)', () => {
  const h = fs.readFileSync('supabase/migrations/20261022018000_cf247_pause_hotfix.sql', 'utf8')
  expect(h).toContain('h.provider_id = q.provider_id')
  expect(h).toContain('h.provider_id = pipeline.enrich_plan_runs.provider_id')
})

test('NZ resolutions finished (Platform Admin 22 Oct 2026 13:28) and search gates pass only a person\'s request', () => {
  const f = fs.readFileSync('supabase/migrations/20261022019000_cf247_nz_resolutions_finish.sql', 'utf8')
  const g = fs.readFileSync('supabase/migrations/20261022020000_cf247_search_gates_automatic_requests.sql', 'utf8')
  for (const m of [f, g]) { expect(m).toMatch(/^-- Replaces: /m); expect(m).not.toMatch(/^(drop|delete|truncate)\b/im) }
  expect(f).toContain('create or replace function security.site_not_checked_v1(p_provider uuid)')
  expect(f).toContain("'pages_refuse_reading'")
  expect(f).toContain('create or replace function security.enrich_fallback_v1(p_item bigint)')
  expect(f).toContain('create or replace function security.nz_resolution_measures_v1(p_country text default')
  expect((g.match(/security\.search_asked_by_person_v1\(s\.provider_id, s\.requested_at\)/g) || []).length).toBe(3)
})

test('v2.15.313 fee reader: a fee printed for a number of points is not read per point', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022021000_cf247_fee_reader_units_covered.sql', 'utf8')
  const fees = fs.readFileSync('supabase/functions/coverage-sweep/fees.ts', 'utf8')
  expect(mig).toContain('create or replace function security.fee_row_units_v1(p_row jsonb)')
  expect(mig).toContain("'b34253b9806cfb1b6d0aa14992412250'")
  expect(mig).toContain("update pipeline.fee_reader_rows set outcome = 'replaced' where queue_id = q.id;")
  expect(mig).toContain("where x.queue_id = q.id and x.outcome = 'pending';")
  expect(mig).toMatch(/^-- Replaces: public\.svc_fee_ai_record/m)
  expect(fees).toContain('units_covered: { type: ["number", "null"] }')
  expect(fees).toContain('"unit", "units_covered", "audience"')
  expect(fees).toContain('NOT a fee per point')
})

test('v2.15.314 fee reader screen shows the points a fee is for and how the yearly figure was worked out', () => {
  const ui = fs.readFileSync('src/FeeReader.jsx', 'utf8')
  expect(ui).toContain('data-fee-quote')
  expect(ui).toContain('for ${fmtNumber(r.units_covered)} points')
  expect(ui).toContain('÷ ${r.units_covered} × ${ft}')
  expect(ui).toContain('data-fee-replaced')
  expect(ui).toContain('data-fee-finding-detail')
})

test('v2.15.315 fee pages can be added by hand, stopped and started again', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022022000_cf247_fee_pages_add_stop.sql', 'utf8')
  const ui = fs.readFileSync('src/FeeReader.jsx', 'utf8')
  expect(mig).toContain("'5a99e8d420aac5e1428bf1c3995d5c32'")
  expect(mig).toContain("elsif p_action in ('page_add', 'page_stop', 'page_resume') then")
  expect(mig).toContain("sf.status = 'rejected'")
  expect(ui).toContain('data-fee-page-add')
  expect(ui).toContain("page('page_stop'")
  expect(ui).toContain("page('page_resume'")
  expect(ui).toContain("no_values:'Fetched'")
})

test('v2.15.316 no-course providers need no adapter; builder course list says what is wrong with a page', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022023000_cf247_no_courses_and_course_pages_card.sql', 'utf8')
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(mig).toContain("then 'no_courses' end")
  expect(mig).toContain("stop_reason = 'no_courses'")
  expect(mig).toContain("then 'wrong_page'")
  expect(mig).toContain("then 'old_site'")
  expect(ui).toContain("wrong_page:['Wrong page (about another course)'")
  expect(ui).toContain('Tick all shown')
  expect(main).toContain("['no_courses','Not needed: no courses']")
})

test('Sydney course data file is a companion read directly; values recorded, nothing admitted', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022024000_cf247_sydney_course_data_file.sql', 'utf8')
  expect(mig).toContain("'ce56347eb846de075a33146a5101f4f9'")
  expect(mig).toContain("'\\1.coredata.json'")
  expect(mig).toContain("'direct'")
  expect(mig).toContain('"type":"INTFEE"')
  expect(mig).not.toMatch(/coverage_apply_course_v1/)
})

test('worker v0.36.2 reads an address ending in .json as JSON text', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('v0.36.2 (22 Oct 2026')
  expect(w).toContain('const isJson = /\\.json$/i.test(u.pathname);')
})

test('v2.15.317 course list page per provider feeds the page matcher; weekly re-read; worker mode', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022026000_cf247_course_list_pages.sql', 'utf8')
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  expect(mig).toContain("'7ee31f407e29af54aa32e5cd6104f294'")
  expect(mig).toContain("comment on table pipeline.provider_course_lists")
  expect(mig).toContain("insert into pipeline.automation_catalogue(jobname")
  expect(mig).toContain("'course_list.reread_days'")
  expect(mig).toContain('or security.course_list_read_v1(co.provider_id))')
  expect(fs.readFileSync('supabase/migrations/20261022027000_cf247_course_list_attempt_rule.sql', 'utf8')).toContain("or security.course_list_bonus_v1(co.id, co.provider_id) = 1)")
  expect(w).toContain('if (mode === "course_list_read") {')
  expect(w).toContain('v0.37.0 (22 Oct 2026')
  expect(w).toContain('const under = (links')
  expect(ui).toContain('data-course-list-pages')
  expect(ui).toContain("supabase.rpc('admin_course_list'")
})

test('course search pick works out provider checks once per provider (it timed out per row)', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022028000_cf247_search_next_per_provider.sql', 'utf8')
  expect(mig).toContain("'d74f17bdf20b971b584291ef20f637c4'")
  expect(mig).toContain('with prov as materialized (')
  expect(mig).toContain('coverage_vendor_usage_purpose_at_idx')
  expect(mig).toContain("when s.requested_at is not null and not pv.bulk then true")
})

test('contact pick runs the directory-site test only after the cheap filters', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022029000_cf247_contact_next_cheap_first.sql', 'utf8')
  expect(mig).toContain("'b759b7e0badf624d8e5c931f3d5bb7a6'")
  expect(mig).toContain('with cand as materialized (')
})

test('Firecrawl spend checks the stopped search for the one provider', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022030000_cf247_fc_spend_stopped_one_provider.sql', 'utf8')
  expect(mig).toContain("'db2f642b7a70400bd62452ec282913ff'")
  expect(mig).toContain('security.fc_search_stopped_for_v1(p_provider_id)')
})

test('v2.15.318 Adapter builder manual mode: tab back, hand-saved settings count, admit by decision, screenshots of an open build kept', () => {
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  const ba = fs.readFileSync('src/BuildAdapter.jsx', 'utf8')
  const mig = fs.readFileSync('supabase/migrations/20261022031000_cf247_builder_screenshots_open_build.sql', 'utf8')
  expect(nav).toContain("{ key: 'builder', label: 'Adapter builder', min: 5 },")
  expect(ui).toContain('const handSaved=Boolean(a)&&!proposalOk')
  expect(ui).toContain('data-manual-settings')
  expect(ui).toContain('data-manual-admit')
  expect(ui).toContain('{read>=1?')
  expect(ui).not.toContain('window.prompt')
  expect(ba).toContain('data-open-builder')
  expect(mig).toContain("'44fe53e8d1a4e92b88c8cbee102d3402'")
  expect(mig).toContain("'retention.screenshot_open_build_days'")
})

test('v2.15.319 progress watchdog: queue states, alerts for Stuck and Out of toolset, safe one-more-try fixes, Work queues tab', () => {
  const mig = fs.readFileSync('supabase/migrations/20261022033000_cf247_queue_watchdog.sql', 'utf8')
  const ui = fs.readFileSync('src/QueueWatch.jsx', 'utf8')
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  for (const s of ["'moving'", "'waiting'", "'stuck'", "'failing'", "'out_of_toolset'", "'nothing_left'", "'done'", "'paused'"]) expect(mig).toContain(s)
  expect(mig).toContain("if v_state in ('stuck', 'out_of_toolset')")
  expect(mig).toContain("channel text not null check (channel in ('notify', 'report'))")
  expect(mig).toContain("cardinality(v_out) = 0 and cardinality(v_wait) = 0")
  expect(mig).toContain("select cron.schedule('queue-watch'")
  expect(mig.indexOf("('queue-watch', 'Platform upkeep'")).toBeLessThan(mig.indexOf("select cron.schedule('queue-watch'"))
  for (const k of ['window_minutes', 'stuck_minutes', 'fail_percent', 'fail_min', 'alert_repeat_hours', 'retry_batch', 'retry_days', 'retry_after_hours', 'report_hours']) expect(mig).toContain(`'queue_watch.${k}'`)
  expect(nav).toContain("{ key: 'queues', label: 'Work queues', min: 3 },")
  expect(ui).toContain("supabase.rpc('admin_queue_watch'")
  expect(ui).not.toContain('window.prompt')
})
