// Guards: SS-Programme-Control 27 Nov 2026 21:08 AEDT item 5 (scholarship dispatcher recovery: the listing picker within its statement limit) and decision D12 (Platform Admin 27 Nov 2026: free listing reads for providers held only by the paid cap; every paid scrape still refused by svc_fc_spend)
// CF-247 s1323. supabase/migrations/20261130210000_cf247_s1323_scholarship_listing_picker_bounded.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130210000_cf247_s1323_scholarship_listing_picker_bounded.sql', 'utf8')

test('providers are checked one at a time in due order and the loop is bounded by the call\'s pages and a fixed time budget', () => {
  expect(sql).toContain("if md5(pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) <> 'dc3b688512a12d5bbf3ed16eecdbd796' then")
  expect(sql).toContain('group by l.provider_id order by 2, 1 loop')
  expect(sql).toContain('exit when v_pages >= v_lim;')
  expect(sql).toContain("exit when clock_timestamp() - v_t0 > interval '2500 milliseconds';  -- fixed: fire guard")
  expect(sql).not.toMatch(/security\.fc_sch_held_v1\(/)
})

test('the hold is hidden providers and discovery eligibility (D12); paid scrapes stay with svc_fc_spend; host, lease, order and output unchanged', () => {
  expect(sql).toContain('continue when exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id);')
  expect(sql).toContain('continue when security.fc_sch_listing_held_v1(r.provider_id);')
  expect(sql).toContain('and not security.third_party_host_v1(l.url)')
  expect(sql).toContain("set next_read_at = now() + interval '15 minutes' from pick where l.id = pick.id  -- fixed: claim lease")
  expect(sql).toContain("order by l.next_read_at nulls first, l.id limit v_lim for update skip locked")
  expect(sql).toContain("'next_url', case when u.page_state = 'partial' then u.next_url end")
  expect(sql).toContain("security.pipeline_num_v1('scholarship.listing_max', 20)")
})

test('the release times the picker in a rolled-back block and refuses a slow one; consumer API, locks and cron checked', () => {
  expect(sql).toContain("raise exception 's1323 timing block';")
  expect(sql).toContain("if ms > 4000 then raise exception 'post-check: the picker took % ms', ms; end if;")
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|\btruncate\s+/i)
  expect(sql).toMatch(/-- Replaces: public\.svc_scholarship_listing_next/)
  expect(sql).toMatch(/-- Retires: nothing\./)
})
