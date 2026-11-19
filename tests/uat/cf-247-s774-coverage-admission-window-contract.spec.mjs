// Guards: Platform Admin 19 Nov 2026 15:18 AEDT (chat S1-Build, s774; IQ-00588): admission runner C stays inside the 120-second statement limit. The coverage admission plans one window of admit.window_pages pages a run from a course-id cursor (security.coverage_admission_gated_v1), with the Layer 4 block check as one anti-join; the consumer API before snapshot (Decision 163 evidence) is taken just before a batch's first change, never for a batch that changes nothing; without a window the plan covers every page as before (platform health).
// The live rolled-back dry run (label live-dry-run) runs the migration's pre- and post-checks against production (one window: plan 1.3 s, apply 1.2 s on 19 Nov 2026); these checks keep the rules in the file.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119155500_cf247_s774_coverage_admission_window.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const gated = c.slice(c.indexOf('create or replace function security.coverage_admission_gated_v1('), c.indexOf('$function$;', c.indexOf('create or replace function security.coverage_admission_gated_v1(')))

test('each function is changed only from the definition that was read; nothing is created, dropped or deleted but one setting', () => {
  expect(c).toContain("select pg_temp.cf_edit_def('security.coverage_admission_plan_v1(text)'::regprocedure, 'f9dceaf2ff05e2b410d06ed968cfcac0',")
  expect(c).toContain("select pg_temp.cf_edit_def('security.coverage_admission_apply_v1(integer,text,text[])'::regprocedure, '82110032efa36af06d6117bde03e50d6',")
  expect(c).toContain("<> 'adc4cf19720f361fbce223eb64297ba0' then")
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: nothing/m)
  expect(c).not.toMatch(/\b(create\s+(temp\w*\s+|unlogged\s+)?table|drop\s+(table|function|index)|truncate|delete\s+from|alter\s+table|create\s+(unique\s+)?index)\b/i)
  expect(c).toContain("('pipeline', 'admit.window_pages', 'Coverage admission: pages planned per run',")
  expect(c).not.toMatch(/zoho_edge_|website_v2_|website_edge_|website_api_v2_/)
})

test('the plan checks Layer 4 blocks set-based and reads only the run window when one is set', () => {
  expect(c).toContain("and not exists (select 1 from security.layer4_active_blocks b where b.block_scope='operational'")
  expect(c).toContain("and ((b.entity_type='course' and b.entity_id=p.course_id) or (b.entity_type='provider' and b.entity_id=co.provider_id)))")
  expect(c).toContain("and (nullif(current_setting('cf247.adm_hi', true), '') is null")
})

test('the before snapshot is taken lazily before the first write and before a rule takes a page', () => {
  expect(c).toContain("array[$o$  v_before:=security.consumer_api_snapshot_v1();")
  expect(c.match(/if v_before is null then v_before:=security\.consumer_api_snapshot_v1\(\); end if;/g)).toHaveLength(4) // two edits, and twice in the post-check that counts them
  expect(c).toContain("raise exception 'post-check: the before snapshot is not taken lazily before each kind of change'")
})

test('the gated job walks a cursor, re-plans a window that reached a limit, and skips between passes as before', () => {
  expect(gated).toContain("v_win int := greatest(100, security.pipeline_num_v1('admit.window_pages', 1500)::int);")
  expect(gated).toContain("where p.read_status = 'read' and p.candidates->>'extractor' = p_extractor and (v_lo is null or p.course_id > v_lo)")
  expect(gated).toContain("v_hit := coalesce((v->>'written')::int, 0) >= p_limit or coalesce((v->>'stopped_at_limit')::boolean, false);")
  expect(gated).toContain("v_cur := case when v_hit then v_lo when v_last then null else v_hi end;")
  expect(gated).toContain("perform set_config('cf247.adm_hi', '', true);")
  expect(gated).not.toMatch(/max\(w\.course_id/)
})
