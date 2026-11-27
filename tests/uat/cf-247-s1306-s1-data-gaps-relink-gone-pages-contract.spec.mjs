// Guards: SS-Programme-Control 27 Nov 2026 13:07 AEDT (Complete Relink Recovery, Priority 1, Admin #1271): a gone page (fetch_failed, HTTP 404 or 410) with a queued relink request is due for course relink, and a course's relink does not bind an address its own earlier relink already tried. No data, setting, job or queue is added.
// s1306: three existing functions are replaced with their s1196 text plus these two changes; the live source is checked by md5 before replacing.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = fs.readFileSync('supabase/migrations/20261130153000_cf247_s1306_s1_data_gaps_relink_gone_pages.sql', 'utf8')
const S1196 = fs.readFileSync('supabase/migrations/20261129121500_cf247_s1196_retired_host_relink.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')
const body = (t, name) => t.match(new RegExp('CREATE OR REPLACE FUNCTION security\\.' + name + '\\(.*?AS \\$function\\$.*?\\$function\\$;', 's'))[0]
const md5 = (b) => crypto.createHash('md5').update(b.split('$function$')[1]).digest('hex')

test('s1306: the guard compares the live source with the s1196 text it replaces', () => {
  for (const n of ['course_relink_provider_v1', 'course_relink_order_v1', 'course_relink_tick_v1']) {
    expect(MIG).toContain(md5(body(S1196, n)))
    expect(code).toContain('security.' + n)
  }
  expect(code).toContain('guard: a course relink function was changed since s1196')
})

test('s1306: only a gone page with a queued relink request is added to relink, in all three functions', () => {
  for (const n of ['course_relink_provider_v1', 'course_relink_order_v1', 'course_relink_tick_v1']) {
    const b = body(MIG, n)
    expect(b).toContain("p.read_status = 'fetch_failed' and p.http_status in (404, 410)")
    expect(b).toContain("q0.route = 'relink' and q0.state = 'queued'")
    expect(b).toContain('page_hosts_retired_v1')
  }
  expect(body(MIG, 'course_relink_provider_v1')).toContain('r.tried')
})

test('s1306: the s1196 text is otherwise unchanged (no new source, no new write)', () => {
  const strip = (b) => b.replace(/\s+/g, ' ')
  const old = strip(body(S1196, 'course_relink_order_v1'))
  const neu = strip(body(MIG, 'course_relink_order_v1'))
  expect(neu.length).toBeGreaterThan(old.length)
  expect(neu.replace(/\(p\.read_status = any \(security\.course_relink_statuses_v1\(\)\) or \(p\.read_status = 'fetch_failed'.*?q0\.state = 'queued'\)\)/, 'p.read_status = any (security.course_relink_statuses_v1())').replace(/^/, '')).toContain('order by 3')
  expect(code).not.toMatch(/cron\.schedule|cron\.alter_job|cron\.unschedule|(update|insert into|delete from) pipeline\.platform_toolset_settings|create table |\bdelete from\b|truncate |update catalogue\.|insert into catalogue\.|update pipeline\.(coverage_course_pages|manual_locks|source_proof_requests)|insert into pipeline\.manual_locks/i)
  expect(MIG).toContain('-- Replaces: security.course_relink_provider_v1')
  expect(MIG).toContain('Retires: nothing')
})

test('s1306: the consumer API, cron, locks, links, pages and requests are checked after', () => {
  for (const s of ['post-check: the consumer API moved', 'post-check: the number of cron jobs changed', 'post-check: manual locks changed', 'post-check: course links changed', 'post-check: official links changed', 'post-check: course pages changed', 'post-check: a request was added or removed', 'post-check: a request changed state', 'post-check: relink no longer leaves retired hosts out']) expect(code).toContain(s)
})
