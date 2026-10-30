// Guards: CF-247 AER production closure C1 (Platform Admin mandate 30 Oct 2026 §4, admin 2026-10-30-aer-production-closure-response.md §0): one primary, operator-exportable entry-requirement outcome per active course of the entry-read countries, derived and read only, rebuilt by a catalogued job on settings, downloadable at rank 4 and above, never part of the consumer API
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261030300000_cf247_aer_course_outcome_register.sql', 'utf8')
const ui = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')
const fnBody = (name) => { const c = code(m); const a = c.indexOf(`create or replace function ${name}(`); return c.slice(a, c.indexOf('$function$;', a)) }

test('one outcome per course from eight fixed outcomes, in the decided order, for the countries of the entry-read setting', () => {
  const c = code(m)
  expect(c).toContain("check (outcome in ('admitted_course', 'admitted_provider', 'awaiting_review', 'no_requirement_published',")
  expect(c).toContain("'no_course_url', 'identity_unresolved', 'source_unreadable', 'excluded'))")
  expect(c).toContain('course_id uuid primary key')
  const order = ['admitted_course', 'admitted_provider', 'awaiting_review', 'no_requirement_published', 'awaiting_review', 'no_course_url', 'identity_unresolved', 'source_unreadable', 'excluded']
  const b = fnBody('security.aer_course_outcomes_build_v1')
  const cases = [...b.slice(b.indexOf('cross join lateral (select case')).matchAll(/then '([a-z_]+)'|else '([a-z_]+)' end outcome/g)].slice(0, 9).map(x => x[1] || x[2])
  expect(cases).toEqual(order)
  // scope from settings, no country written into code (G2)
  expect(b).toContain("security.toolset_setting('pipeline', 'entry.course_read_countries')")
  expect(b).toContain("security.toolset_setting('pipeline', 'entry.course_read_providers')")
  expect(b).not.toMatch(/'NZ'/)
  // the identity rule is the one the course reader uses
  expect(b).toContain("security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')")
  // the post-check proves every in-scope course has exactly one row
  expect(c).toContain("if v_reg <> v_courses then raise exception 'C1 post-check: the register holds % courses, % are in scope'")
})

test('read only: the build writes only its own derived tables; nothing is admitted, read, queued or decided', () => {
  const c = code(m)
  const writes = [...c.matchAll(/\b(insert\s+into|update|delete\s+from)\s+([a-z_]+\.[a-z_]+)/gi)].map(x => x[2])
  for (const w of writes) expect(['pipeline.aer_course_outcomes', 'pipeline.aer_course_outcome_builds', 'pipeline.platform_toolset_settings', 'pipeline.automation_catalogue', 'pipeline.component_register'], w).toContain(w)
  expect(c).not.toMatch(/layer4_decide|entry_matrix_review_apply|course_entry_review_apply|course_entry_read_enqueue|admin_jobs/)
  // the delete clears its own table inside the build function, never at the top level of the migration
  expect(fnBody('security.aer_course_outcomes_build_v1')).toContain('delete from pipeline.aer_course_outcomes;')
  expect(c.replace(/\$function\$[\s\S]*?\$function\$/g, '')).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(c).toContain("pg_try_advisory_xact_lock(hashtextextended('cf247.aer.outcome_register', 0))")
})

test('G1 and G2: the job is catalogued and scheduled with no number in its command; interval, page size and staleness are settings', () => {
  const c = code(m)
  expect(c.indexOf("insert into pipeline.automation_catalogue")).toBeLessThan(c.indexOf("select cron.schedule('aer-outcome-register'"))
  expect(c).toContain("select cron.schedule('aer-outcome-register', '*/5 * * * *', $$select security.aer_course_outcomes_refresh_v1()$$);")
  for (const k of ['aer.outcome_register_every_minutes', 'aer.outcome_register_page_rows', 'aer.outcome_register_stale_after_minutes']) {
    expect(c).toContain(`('pipeline', '${k}',`)
    expect(c).toContain(`security.pipeline_num_v1('${k}',`)
  }
  expect(m).toContain('-- fixed: fire guard')
  expect(m).toContain('-- Replaces: nothing')
  expect(m).toContain('-- Retires: nothing')
  expect(c).toContain('comment on table pipeline.aer_course_outcomes is')
  expect(c).toContain('comment on table pipeline.aer_course_outcome_builds is')
})

test('the read: rank 4 and above over the API, summary and paged rows, build time and stale flag; not the consumer API', () => {
  const r = fnBody('public.admin_aer_outcomes')
  expect(r).toContain("if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or v_rank < 4) then")
  expect(r).toContain("raise exception 'Pipeline Operator or above required' using errcode = '42501'")
  expect(r).toContain("'stale', now() - b.built_at > make_interval(mins => security.pipeline_num_v1('aer.outcome_register_stale_after_minutes', 180)::int)")
  expect(r).toContain('offset v_off limit v_page')
  expect(code(m)).toContain('revoke all on function public.admin_aer_outcomes(jsonb) from public, anon;')
  // G3: no consumer API object is created or edited
  expect(code(m)).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|function\s+api\.|consumer_api_rebaseline_v1/)
})

test('the screen: Resolution inspection shows the register to rank 4 and above, with counts by outcome and a full CSV download', () => {
  expect(ui).toContain("export function ResolveView({onError,routeParams,rank}){")
  expect(ui).toContain('{Number(rank||0)>=4&&<OutcomeRegister/>}')
  expect(ui).toContain("if(tab==='resolve')return <ResolveView onError={onError} routeParams={routeParams} rank={rank}/>")
  expect(ui).toContain("supabase.rpc('admin_aer_outcomes',{p_args:args})")
  expect(ui).toContain("outcomes({part:'rows',offset:off})")
  expect(ui).toContain('if(!(d.rows||[]).length||off>=total)break')
  expect(ui).toContain('data-aer-outcomes-download')
  // every outcome the database can return has a plain label
  for (const k of ['admitted_course', 'admitted_provider', 'awaiting_review', 'no_requirement_published', 'no_course_url', 'identity_unresolved', 'source_unreadable', 'excluded']) expect(ui).toContain(`['${k}',`)
})

test('CSV cells are quoted when they hold a comma, quote or line break', async () => {
  const src = ui.match(/export const csvCell=(v=>\{[^\n]*\})\n/)[1]
  const csvCell = eval(src)
  expect(csvCell(null)).toBe('')
  expect(csvCell('plain')).toBe('plain')
  expect(csvCell('a, b')).toBe('"a, b"')
  expect(csvCell('say "x"')).toBe('"say ""x"""')
  expect(csvCell('two\nlines')).toBe('"two\nlines"')
  expect(csvCell(false)).toBe('false')
})

async function mockOutcomes(page, { rank = 4 } = {}) {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { rank })
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer', route => route.fulfill({ json: { providers: [], countries: [], all_countries: [{ code: 'IN', name: 'India' }], scales: ['percentage', 'none'] } }))
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer_outcomes', async route => {
    const a = (route.request().postDataJSON() || {}).p_args || {}
    calls.push(a)
    const build = { built: true, built_at: '2026-10-30T12:00:00Z', courses: 3, age_seconds: 60, stale: false, took_ms: 13000 }
    if (a.part === 'summary') return route.fulfill({ json: { build, by_outcome: [
      { outcome: 'admitted_provider', country: 'AU', courses: 1, published: 1, providers: 1 },
      { outcome: 'awaiting_review', country: 'AU', courses: 1, published: 1, providers: 1 },
      { outcome: 'no_course_url', country: 'NZ', courses: 1, published: 0, providers: 1 }], by_detail: [] } })
    const all = [
      ['c1', '0100714', 'Bachelor of Engineering (Honours)', 'RMIT University', true, 'AU', 'admitted_provider', 'provider table active (343 rows): the resolver answers by country', 'https://www.rmit.edu.au/x', 'bound', 'exact_title', null, null, null, '2026-10-30T12:00:00Z'],
      ['c2', null, 'Master of Business, Finance', 'Curtin University', true, 'AU', 'awaiting_review', 'the provider\'s table waits in Layer 4 (1 item(s))', null, null, null, null, null, 'li-1', '2026-10-30T12:00:00Z'],
      ['c3', null, 'Diploma "Applied" Arts', 'Ara', false, 'NZ', 'no_course_url', 'no official course page found', null, null, null, null, null, null, '2026-10-30T12:00:00Z']]
    const off = a.offset || 0
    return route.fulfill({ json: { build, total: 3, offset: off, limit: 2, rows: all.slice(off, off + 2),
      columns: ['course_id', 'course_code', 'course_title', 'provider', 'provider_published', 'country', 'outcome', 'detail', 'course_url', 'page_status', 'identity_basis', 'read_state', 'read_reason', 'review_item_id', 'built_at'] } })
  })
  return calls
}

test.describe('mocked browser', () => {
  test('a Pipeline Operator sees the counts by outcome and country and downloads every row as CSV, page by page', async ({ page }) => {
    const errors = []; page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource|favicon/.test(m.text())) errors.push(m.text()) })
    const calls = await mockOutcomes(page, { rank: 4 })
    await page.goto('/#entry-requirements?tab=resolve')
    const reg = page.locator('[data-aer-outcome-register]')
    await expect(reg.locator('h2')).toHaveText('Course outcome register')
    await expect(page.locator('[data-aer-outcomes-build]')).toContainText('3')
    await expect(page.locator('[data-aer-outcome-row="admitted_provider"]')).toContainText('Admitted provider resolution')
    await expect(page.locator('[data-aer-outcome-row="no_course_url"]')).toContainText('No official course URL')
    await expect(page.locator('[data-aer-outcome-row="identity_unresolved"]')).toHaveCount(0)   // no courses, no row
    const [dl] = await Promise.all([page.waitForEvent('download'), page.locator('[data-aer-outcomes-download]').click()])
    expect(dl.suggestedFilename()).toBe('aer-course-outcomes-2026-10-30-12-00.csv')
    const csv = fs.readFileSync(await dl.path(), 'utf8').replace(/^﻿/, '').split('\r\n')
    expect(csv[0]).toBe('course_id,course_code,course_title,provider,provider_published,country,outcome,detail,course_url,page_status,identity_basis,read_state,read_reason,review_item_id,built_at')
    expect(csv.length).toBe(4)                                                                  // header and all three rows over two pages
    expect(csv[3]).toContain('"Diploma ""Applied"" Arts"')
    expect(calls.filter(c => c.part === 'rows').map(c => c.offset)).toEqual([0, 2])
    expect(errors).toEqual([])
  })

  test('a Curator (rank 3) sees Resolution inspection without the register, and it is never asked for', async ({ page }) => {
    const calls = await mockOutcomes(page, { rank: 3 })
    await page.goto('/#entry-requirements?tab=resolve')
    await expect(page.locator('[data-aer-view="resolve"] h2').first()).toHaveText('Resolution inspection')
    await expect(page.locator('[data-aer-outcome-register]')).toHaveCount(0)
    expect(calls).toEqual([])
  })
})
