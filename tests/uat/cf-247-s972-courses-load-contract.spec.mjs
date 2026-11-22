// Guards: REQ-105 (Platform Admin consolidated batch, 22 Nov 2026 14:22 AEDT): the Courses page opens in under a second; the filter lists open fast and stay exact
// s972: the default Courses list (Active, course order, no other filter) takes the page-first path with its Active index; the six filter lists
// read their small reference tables by semi-join (delivery modes by index probe) and return exactly what they returned before; the
// migration edits only the definitions it was written against and leaves the consumer API, locks and jobs alone. The deployed check times
// the two reads signed in.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { loginAsUatUser, writeRunEnvironment } from './support/runtime-evidence.mjs'

const MIG_PATH = 'supabase/migrations/20261122160000_cf247_s972_courses_list_and_filters_fast.sql'
const MIG = fs.existsSync(MIG_PATH) ? fs.readFileSync(MIG_PATH, 'utf8') : ''

test('migration: the default Active list takes the page-first path, from the guarded definitions only', () => {
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toMatch(/^-- Retires: /m)
  expect(MIG).toContain("create index if not exists courses_active_title_idx on catalogue.courses (lower(canonical_title), id) where lifecycle_status = 'active';")
  // md5 before and after for both list functions
  expect(MIG).toContain("pg_temp.edit_re('security.admin_course_page_unfiltered_fast(jsonb)', '93350f637166fa616b3f4ad7187205e9', '74a49322d1c91ac35bf0e3f0db5581ac'")
  expect(MIG).toContain("pg_temp.edit_re('security.admin_course_page_fast(jsonb)', '0018ad72937c324750888ad37385a42a', '0df468929bc1f30b769496a0d7be109c'")
  expect(MIG).toContain("'and coalesce(nullif(p_args->>''lifecycle_status'',''''),''active'')=''active'''")
  expect(MIG).toContain('where (v_lifecycle is null or c.lifecycle_status=v_lifecycle)')
  expect(MIG).toContain('select count(*) into v_total from catalogue.courses c where (v_lifecycle is null or c.lifecycle_status=v_lifecycle);')
  // the page-first path returns the columns the course-first path returns
  for (const col of ['c.open_to_international,c.open_to_domestic,', 'pg.open_to_international,pg.open_to_domestic,', 'ifee.basis intl_fee_basis,', 'cf.fee_year, cf.basis from catalogue.course_fees']) expect(MIG).toContain(col)
})

test('migration: the filter lists are replaced only from the definition they were written against, with the same answer shape', () => {
  expect(MIG).toContain("if md5(pg_get_functiondef('security.admin_catalogue_filter_page(jsonb)'::regprocedure)) <> '50c21dce0dbdfb23d3c49030f21d8056' then")
  const fn = MIG.slice(MIG.indexOf('CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_page(p_args jsonb'), MIG.indexOf('$function$;', MIG.indexOf('CREATE OR REPLACE FUNCTION security.admin_catalogue_filter_page(p_args jsonb')))
  expect(fn.length).toBeGreaterThan(5000)
  expect(fn).toContain("STABLE SECURITY DEFINER")
  expect(fn).toContain("if v_rank<1 then raise exception 'assigned StudySearch role required'")
  // providers of the country and courses of the region read once; small reference tables by semi-join
  expect(fn).toContain('select coalesce(array_agg(p.id),\'{}\'::uuid[]) into v_pids from catalogue.providers p')
  expect(fn).toContain('into v_cids from (')
  for (const t of ['from ref.countries co', 'from ref.subdivisions s', 'from catalogue.providers p', 'from ref.study_levels sl', 'from ref.fields_of_study fos']) expect(fn).toContain(t)
  // delivery modes by index probe: one probe per mode
  expect(fn).toContain('with recursive t(m) as (')
  expect(fn).toContain("select (select nullif(btrim(c.delivery_mode),'') from catalogue.courses c where nullif(btrim(c.delivery_mode),'')>t.m order by 1 limit 1) from t where t.m is not null")
  expect(MIG).toContain("create index if not exists courses_delivery_mode_norm_idx on catalogue.courses ((nullif(btrim(delivery_mode), '')), provider_id);")
  expect(MIG).toContain('create index if not exists course_campuses_delivery_mode_idx on catalogue.course_campuses (delivery_mode);')
  // the answer: same keys, same order, same limits and empty-list notes
  expect(fn).toContain("case when lower(nullif(trim(coalesce(p_args->>'filter_kind','')),''))='level' then 100 else 10 end")
  expect(fn).toContain("'has_more',(v_offset+jsonb_array_length(v_items))<v_total")
  expect((fn.match(/order by lower\(label\),value limit v_limit offset v_offset/g) || []).length).toBe(6)
  expect(fn).toContain("when 'subdivision' then 'No regions are recorded for this country.'")
  expect(fn).toContain("raise exception 'unsupported catalogue filter kind: %'")
})

test('migration: consumer API, locks and jobs guarded; nothing dropped, deleted or scheduled', () => {
  expect(MIG).toContain("security.consumer_api_check_v1()")
  expect((MIG.match(/\(v->>'functions'\)::int <> 75|\(v_api->>'functions'\)::int <> 75/g) || []).length).toBe(2)
  expect(MIG).toContain("post-check: the manual locks changed")
  expect(MIG).toContain("post-check: the number of active cron jobs changed")
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|alter table [^;]* drop |delete from |truncate /i)
  expect(MIG).not.toMatch(/create\s+or\s+replace\s+function\s+(public\.)?(website_|zoho_|api\.)/i)
})

test.describe('REQ-105 Courses reads signed in @deployed', () => {
  test.beforeAll(async () => { await writeRunEnvironment({ suite: 'cf-247-s972-courses-load', change_control: 'CF-CHG-20260915-247' }) })

  test('the first Courses read and the filter lists answer in under a second', async ({ page }) => {
    let seen = null
    page.on('request', (r) => {
      if (seen || !r.url().includes('/rest/v1/')) return
      const h = r.headers()
      if (h.apikey && /^Bearer /i.test(h.authorization || '') && h.authorization !== `Bearer ${h.apikey}`) seen = { origin: new URL(r.url()).origin, authorization: h.authorization, apikey: h.apikey }
    })
    await loginAsUatUser(page)
    await expect.poll(() => seen, { timeout: 30_000 }).not.toBeNull()
    const time = (args, op = 'courses_page') => page.evaluate(async ({ origin, headers, op, args }) => {
      const t0 = performance.now()
      const r = await fetch(`${origin}/rest/v1/rpc/admin_read`, { method: 'POST', headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify({ p_operation: op, p_args: args }) })
      const body = await r.json().catch(() => null)
      return { status: r.status, ms: performance.now() - t0, total: body?.total, profile: body?.execution_profile }
    }, { origin: seen.origin, headers: { apikey: seen.apikey, authorization: seen.authorization }, op, args })
    const list = { limit: 50, offset: 0, query: null, sort: 'course', direction: 'asc', lifecycle_status: 'active' }
    const runs = []
    for (let i = 0; i < 3; i++) runs.push(await time(list))
    for (const r of runs) expect(r.status, JSON.stringify(r)).toBe(200)
    expect(runs[0].profile).toBe('page_first_unfiltered_v1')
    expect(Math.min(...runs.map((r) => r.ms)), JSON.stringify(runs)).toBeLessThan(1000)
    for (const kind of ['country', 'provider', 'level', 'field', 'delivery']) {
      const f = []
      for (let i = 0; i < 2; i++) f.push(await time({ filter_kind: kind, country_code: 'AU', limit: 10, offset: 0 }, 'catalogue_filter_page'))
      expect(f[0].status, JSON.stringify(f)).toBe(200)
      expect(Math.min(...f.map((r) => r.ms)), `${kind} ${JSON.stringify(f)}`).toBeLessThan(1000)
    }
  })
})
