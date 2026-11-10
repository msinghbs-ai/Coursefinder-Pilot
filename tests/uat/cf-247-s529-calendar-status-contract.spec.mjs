// Guards: CF-247 F-INT calendar status (Platform Admin 11 Nov 2026 09:26 AEDT, items 1 and 2): a read-only per-provider calendar status on Adapters (approved 2027, read not approved, earlier edition, stored with no 2027 start, read failed, none found) and the calendar re-read raised to 100 stored copies a run with no Firecrawl.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261111110000_cf247_calendar_status_read.sql', 'utf8')
const UI = fs.readFileSync('src/AdaptersWorkspace.jsx', 'utf8')

test('the status read is read only, needs an assigned role, and names every status', () => {
  const fn = MIG.slice(MIG.indexOf('create or replace function public.admin_calendar_status_read'), MIG.indexOf('revoke all on function'))
  expect(fn).toContain('stable security definer')
  expect(fn).toContain("set search_path to ''")
  expect(fn).toContain('security.current_role_rank() < 3')
  expect(fn).not.toMatch(/\b(insert into|update |delete from|perform )/i)
  for (const s of ['approved_2027', 'read_2027_not_approved', 'approved_earlier_edition', 'stored_no_2027', 'read_failed', 'none_found']) expect(fn).toContain(`'${s}'`)
  expect(MIG).toContain('revoke all on function public.admin_calendar_status_read(jsonb) from public, anon;')
  expect(MIG).toContain('grant execute on function public.admin_calendar_status_read(jsonb) to authenticated;')
})

test('the calendar re-read is raised to 100 with a reason, maximum first, and the change is checked', () => {
  expect(MIG).toMatch(/set max_value = 100, value = to_jsonb\(100\),\s+reason = 'Platform Admin 11 Nov 2026 09:26 AEDT/)
  expect(MIG).toContain("where toolset_key = 'pipeline' and key = 'batch.calendar_reread';")
  expect(MIG).toContain("security.pipeline_num_v1('batch.calendar_reread', 0) <> 100")
  // only this one setting changes
  expect(MIG.match(/update pipeline\.platform_toolset_settings/g)).toHaveLength(1)
})

test('Adapters shows the calendar status card from the read, with a filter by status', () => {
  expect(UI).toContain('<Card id="adapters.calendar-status" title="Academic calendars by provider"')
  expect(UI).toContain("supabase.rpc('admin_calendar_status_read',{p_args:{}})")
  expect(UI).toContain('data-calendar-status-totals')
  expect(UI).toContain('aria-pressed={only===s}')
})
