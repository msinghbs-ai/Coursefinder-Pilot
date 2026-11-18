// Guards: Course-link search pick stays inside a worker call (Platform Admin 18 Nov 2026 17:02 item 2): public.svc_course_link_search_next cuts the providers with a queued search to those the pass can take, not hidden and on the target list, before it runs the provider-level functions; every later condition of the pick is kept
// CF-247 S657. Migration 20261118201000_cf247_course_search_pick_timeout. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const code = fs.readFileSync(migrationPath('20261118201000_cf247_course_search_pick_timeout.sql'), 'utf8').split('\n').filter((l) => !/^\s*--(?! 18 Nov 2026 \(S657\))/.test(l)).join('\n')
const edit = code.slice(code.indexOf('v_new text := $n$'), code.indexOf('$n$;'))

test('the edit is md5-guarded, applies exactly once and is not repeated', () => {
  expect(code).toContain("if md5(v_def) <> 'fdf5f2f5cd6a7a0be15d7909569d5ce2' then raise exception")
  expect(code).toContain("if v_c <> 1 then raise exception 'the provider list must be found exactly once (found %)', v_c; end if;")
  expect(code).toContain("if position('18 Nov 2026 (S657)' in v_def) > 0 then raise notice 'already applied'; return; end if;")
  expect(code).toContain("v_old text := $o$from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') q$o$;")
})

test('the provider list is cut by pass, hidden providers and the target list before the provider-level functions', () => {
  expect(edit).toContain('where (case when v_pass = 1 then d0.provider_id = any (v_od) else not (d0.provider_id = any (v_od)) end)')
  expect(edit).toContain('and not exists (select 1 from security.provider_hidden_v1 h0 where h0.provider_id = d0.provider_id)')
  expect(edit).toContain("and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true) or d0.provider_id = any (v_od)")
  expect(edit).toContain('or exists (select 1 from pipeline.firecrawl_target_cache tc0 where tc0.provider_id = d0.provider_id and tc0.included))')
  expect(edit).toContain('offset 0) q')
  expect(edit).not.toMatch(/enrich_focus_v1|site_few_course_pages_v1|site_not_checked_v1|fc_provider_tier_v1|third_party_host_v1/)
})

test('every later condition of the pick is kept, and the provider-level work must fit half a worker call', () => {
  expect(code).toContain("raise exception 'post-check: a later condition of the pick was lost';")
  expect(code).toContain('$k$where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)$k$')
  expect(code).toContain("$k$and not security.third_party_host_v1('https://' || rc.search_domain)$k$")
  expect(code).toContain('$k$and (case when v_pass = 1 then s.provider_id = any (v_od)$k$')
  expect(code).toContain("from pg_roles r, unnest(r.rolconfig) c where r.rolname = 'authenticator' and c like 'statement_timeout=%';")
  expect(code).toContain('if v_limit is not null and v_ms > extract(epoch from v_limit) * 1000 / 2 then')
})

test('no queue row, setting or page is written and nothing is dropped', () => {
  expect(code).not.toMatch(/insert into |update (pipeline|catalogue|binding)\.|svc_course_link_search_next\(\d/i)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
