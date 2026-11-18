// Guards: Course page needed items never leave the list with nothing working on them (Platform Admin 18 Nov 2026 17:02 item 2): rule l4-page-needed-search-v1 returns an item it sent when its search found no page, ended in error or is held by the lane's stop gate, and does not ask for a search the gate would hold or repeat one that found nothing
// CF-247 S658. Migration 20261118233000_cf247_course_page_needed_return_to_list. G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const code = fs.readFileSync(migrationPath('20261118233000_cf247_course_page_needed_return_to_list.sql'), 'utf8').split('\n').filter((l) => !/^--/.test(l)).join('\n')

test('the edit is md5-guarded and each part applies an exact number of times', () => {
  expect(code).toContain("if md5(v_def) <> 'a2677bf22b788fc41434e50300b256e5' then raise exception")
  expect(code).toContain("if v_c <> v_edits[i][3]::int then raise exception 'edit % must apply exactly % times (found %)', i, v_edits[i][3], v_c; end if;")
  expect(code).toContain("if position('18 Nov 2026 (S658)' in v_def) > 0 then raise notice 'already applied'; return; end if;")
})

test('only items this rule sent come back, and only when the search found nothing, failed or is held by the stop gate', () => {
  expect(code).toContain("where n.state = 'search_requested' and n.decision->>'reason' like '[rule l4-page-needed-search-v1]%'")
  expect(code).toContain("and (s.state in ('none', 'error') or (s.state = 'queued' and security.search_stop_gate_v1(n.provider_id, n.course_id) is not null)))")
  expect(code).toContain("set state = 'open', updated_at = now(),")
  expect(code).toContain("jsonb_build_object('returned_by', 'l4-page-needed-search-v1', 'returned_at', now(), 'returned_because', b.why)")
  expect(code).toContain('get diagnostics v_back = row_count;')
  expect(code).not.toMatch(/searches_requested\s*=|set\s+refused|last_refused_reason\s*=/)
})

test('no search is asked that the stop gate would hold, and a search that found no page is not repeated', () => {
  expect(code).toContain('and security.search_stop_gate_v1(n.provider_id, n.course_id) is null')
  expect(code).toContain("and not exists (select 1 from pipeline.course_link_search s0 where s0.course_id = n.course_id and s0.requested_at is not null and s0.state in ('none', 'error'))")
})

test('the on-demand request is closed through its own function; the first run must leave no stranded item; nothing dropped', () => {
  expect(code).toContain('v := security.on_demand_close_v1(r.id);')
  expect(code).toContain("raise exception 'post-check: an item whose search cannot run or found nothing is still off the list';")
  expect(code).toContain("raise exception 'post-check: the S656 on-demand request is still open';")
  expect(code).toContain("security.pipeline_num_v1('layer4.page_needed_search_batch', 300)::int")
  expect(code).not.toMatch(/update pipeline\.on_demand_requests|insert into pipeline\.course_link_search|update catalogue\.|insert into catalogue\./i)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
