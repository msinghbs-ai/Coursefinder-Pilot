// Guards: F-SCH scholarship AI picker on a bounded window (Platform Admin S2-Scholarship directive 13 Nov 2026 §1 keep extraction running, §7 continuous and efficient operation): a large queue never stops every reading; no item is leased without the directory-site and search-off checks; the checks run once per distinct site and provider, not once per item
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261113311500_cf247_sch_ai_pick_window.sql'
const m = fs.readFileSync(MIG, 'utf8')

test('one md5-guarded edit of the live picker, four edits each applied exactly once', () => {
  expect(m).toContain("select pg_temp.edit_n('public.svc_scholarship_ai_next(integer)', '170f4e72a98bb0bb22d51a1cb4c0d7a7', array[")
  expect(m).toContain('], array[1, 1, 1, 1]);')
  expect(m).toContain('-- Replaces: public.svc_scholarship_ai_next(integer)')
  expect(m).not.toMatch(/create or replace function (api\.|public\.website_|public\.zoho_)/i) // no consumer object (G3)
})

test('the lease and the close step both use the window; nothing is leased from outside it', () => {
  expect(m).toContain('and q.attempts < 3 and q.id = any(v_win)  -- F-SCH 13 Nov 2026: only from the checked window')
  expect(m).toContain("where q.id = any(v_win) and q.state in ('queued', 'leased')")
  // the window is filled in the picker's own order, with its own filters, bounded by the setting
  expect(m).toContain("order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id offset 0) o")
  expect(m).toContain('and (v_paid or security.scholarship_ai_has_copy_v1(o.id))')
  expect(m).toContain('limit greatest(20, least(v_scan, 2000))) w;')
})

test('directory-site and search-off checks: the same functions, once per distinct site and provider', () => {
  expect(m).toContain('security.third_party_host_v1(h.url)')
  expect(m).toContain('security.provider_sch_search_off_v1(p.provider_id)')
  expect(m).toContain('and (security.site_host_v1(q.url) = any(v_tp) or q.provider_id = any(v_off));')
  // the old whole-queue check is the replaced text, not the new one
  const news = [...m.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1]).join('\n')
  expect(news).not.toContain('security.third_party_host_v1(q.url)')
})

test('the window size is a setting (G2), not a literal', () => {
  expect(m).toContain("('pipeline', 'batch.sch_ai_pick_scan', ")
  expect(m).toContain("v_scan int := security.pipeline_num_v1('batch.sch_ai_pick_scan', 60)::int;")
  expect(m).toContain("'number', '60'::jsonb, 20, 2000, 'items'")
})
