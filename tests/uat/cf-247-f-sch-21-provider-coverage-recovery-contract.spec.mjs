// Guards: F-SCH provider coverage recovery (Platform Admin S2-Scholarship directive 13 Nov 2026 14:50 §1, §3, §4; Developer Requirements v2.26 F-SCH.11/.12): rebranded domains re-mapped with the old host kept, classified universities searched without loaded courses, technical AI reviews read again fresh while reviewer questions stay with people, the scholarship Firecrawl share raised inside the unchanged day total
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261113321500_cf247_sch_provider_coverage_recovery.sql', 'utf8')

test('rebranded domains: the catalogue website is mapped again, the old host stays allowed, own-host register entries are handed to the reader', () => {
  expect(m).toContain('allowed_hosts = (select array_agg(distinct h) from unnest(coalesce(d.allowed_hosts, \'{}\') || m.old_host) h where h is not null)')
  expect(m).toContain("status = 'pending', attempts = 0, next_discover_at = now()")
  expect(m).toContain("select public.svc_scholarship_register_match(r.code) from scholarship.registers r where r.role = 'index';")
})

test('classified universities are legitimate sources without loaded courses; the original rule is kept and widened, not replaced', () => {
  expect(m).toContain("select pg_temp.edit_n('security.scholarship_legitimacy_v1(uuid)', '90bdbf40913bdd120810bd6b7ff3e3bd', array[")
  expect(m).toContain('and security.scholarship_university(p.id))$n$]')
  expect(m).toContain('and p.enrols_international is not false and nullif(btrim(coalesce(p.website, \'\')), \'\') is not null and not security.third_party_host_v1(p.website)')
  expect(m).toContain("select pg_temp.edit_n('security.scholarship_discovery_refill_v1(integer)', 'aa26bbc2b99e3390a4730abc2fa14992', array[")
  expect(m).toContain('where k.scholarship_ingestion_enabled and (co.id is not null or security.scholarship_university(p.id))')
})

test('only technical reviews are read again; reviewer questions stay pending; nothing is admitted or published here', () => {
  expect(m).toContain("where r.status = 'pending' and (r.reason like 'the model''s reply failed%' or r.reason like 'Approved read: the page could not be read%')")
  expect(m).toContain('rv.url, true')
  expect(m).not.toMatch(/publication_status\s*=\s*'published'/)
  expect(m).not.toMatch(/insert into scholarship\.scholarships/)
  expect(m).not.toMatch(/create or replace function (api\.|public\.website_|public\.zoho_)/i)
})

test('the scholarship Firecrawl share is raised inside the unchanged day total, with a control event', () => {
  expect(m).toContain("update pipeline.platform_toolset_settings set value = '1500'::jsonb\n where toolset_key = 'firecrawl' and key = 'daily_share_scholarships' and value = '800'::jsonb;")
  expect(m).not.toMatch(/key = 'daily_budget_total'/)
  expect(m).toContain("'firecrawl_daily_share_scholarships', jsonb_build_object('from', 800, 'to', 1500, 'day_total_unchanged', 4000)")
})
