// Guards: Platform Admin decision D1, 26 Nov 2026 15:09 AEDT (retired hosts never reused by relink address learning, stored-list candidates or site-map binding; affected Adelaide courses rediscovered on the current website; canonical requirements and manual locks preserved; no regression to the retired host)
// s1196: hosts a page refind retired are left out of course relink and the site-map binder, a guard on pipeline.coverage_course_pages refuses any machine write onto one, and the affected courses are asked again through the existing relink route.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261129121500_cf247_s1196_retired_host_relink.sql', 'utf8')
const code = MIG.replace(/--.*$/gm, '')

test('s1196: each replaced function is guarded by the definition read live, and each leaves retired hosts out', () => {
  for (const [fn, md5] of [['security.course_relink_provider_v1(uuid,integer)', '07bd965bac8b7cd7b41a3092c447d677'], ['security.course_relink_order_v1()', 'c10ec3367cbd409f255afecf52248ce9'],
    ['security.course_relink_tick_v1(integer)', '656d308b1b12532a7e3e4335cf0f21ea'], ['security.coverage_bind_v2(uuid)', 'ec5087e303c70ecee9cd9fae705b78a8']]) {
    expect(MIG).toContain(`md5(pg_get_functiondef('${fn}'::regprocedure)) <> '${md5}'`)
  }
  expect(MIG).toContain('-- s1196: no address form is learnt from a retired host')
  expect(MIG).toContain('-- s1196: stored addresses on a retired host are not candidates')
  expect(MIG).toContain('-- s1196: no candidate on a retired host, from any source')
  expect(MIG).toContain('-- s1196: a page on a retired host is relinked')
  expect(MIG).toContain('-- s1196: the site-map binder never binds a retired host')
  expect(code.match(/security\.page_hosts_retired_v1\(\)/g).length).toBeGreaterThanOrEqual(10)
})

test('s1196: a retired host is only one a refind moved away from, never the website host or a subdomain of it', () => {
  expect(MIG).toContain("from pipeline.page_refind r join catalogue.providers pr on pr.id = r.provider_id")
  expect(MIG).toContain("security.site_host_v1(r.old_url) <> coalesce(security.site_host_v1(pr.website), '')")
  expect(MIG).toContain("security.site_host_v1(r.old_url) not like '%.' || coalesce(security.site_host_v1(pr.website), '-')")
})

test('s1196: one guard refuses a machine write onto a retired host from any writer; manual bindings and rows already there are left', () => {
  expect(MIG).toContain("create or replace trigger course_page_retired_host_guard before insert or update of url on pipeline.coverage_course_pages")
  expect(MIG).toContain("if new.url is null or coalesce(new.basis, '') = 'manual' then return new; end if;")
  expect(MIG).toContain("if tg_op = 'UPDATE' and old.url is not distinct from new.url then return new; end if;")
  expect(MIG).toContain("if tg_op = 'UPDATE' then return old; end if;")
  expect(MIG).toContain("raise exception 'post-check: the retired-host guard is not on pipeline.coverage_course_pages'")
})

test('s1196: the affected courses are asked again through the existing relink route; locked and other open requests are left', () => {
  expect(MIG).toContain("insert into pipeline.source_proof_requests (course_id, provider_id, route, state, attempts, requested_at, detail)")
  expect(MIG).toContain("where pipeline.source_proof_requests.state = 'done'\n      or (pipeline.source_proof_requests.state = 'held' and pipeline.source_proof_requests.route = 'no_route');")
  expect(MIG).toContain("d.status in ('mapped', 'failed')")
})

test('s1196: no lifecycle, canonical, lock, cron or consumer change, and nothing dropped or deleted (D2: the 35 courses are retained)', () => {
  expect(code).not.toMatch(/update catalogue\.courses|lifecycle_status\s*=\s*'(archived|withdrawn|inactive)'|course_entry_requirements\s+set|delete from|truncate |cron\.schedule|cron\.alter_job|website_v2_|manual_locks\s+set/i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: a cron job was created', 'post-check: more than 140 active cron jobs', 'post-check: manual locks changed', 'post-check: canonical requirements changed', 'post-check: a course page binding changed', 'post-check: the consumer API moved']) expect(MIG).toContain(s)
})
