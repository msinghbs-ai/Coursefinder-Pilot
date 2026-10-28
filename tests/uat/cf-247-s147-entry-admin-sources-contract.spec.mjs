// Guards: CF-247 AER programme admin experience (Platform Admin consolidated mandate 28 Oct 2026 23:22, item 1: operators inspect provider data, evidence, statuses, runs and holds through bounded UI reads; admission stays in Layer 4; no new dashboard): the provider's Academic entry requirements section lists its sources and each one's latest read, holds and refusals included, read only and bounded
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029005000_cf247_aer_admin_sources_and_reads.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const ui = fs.readFileSync('src/EntryRequirements.jsx', 'utf8')

test('server: md5-guarded edit of the existing read; sources bounded at 50 with their latest read; nothing written', () => {
  expect(code).toContain("select pg_temp.edit_n('public.admin_entry_requirements(text,jsonb)', '961150b37ec7c752b10bffbd18c39ed0'")
  expect(code).toContain("from pipeline.entry_matrix_sources s where s.provider_id = v_pid order by 1, 2 limit 50) z),")
  expect(code).toContain("from pipeline.entry_matrix_runs r where r.source_id = s.id order by r.updated_at desc limit 1)) x")
  for (const k of ["'error', r.error", "'not_kept', r.rows_dropped", "'basis', r.result->>'page_basis'", "'review_status', (select li.status from pipeline.layer4_review_items li where li.id = r.review_item_id)"]) expect(code).toContain(k)
  expect(code).not.toMatch(/\b(update|delete from|insert into|drop|truncate)\b/i)
})

test('UI: the same section in the Provider drawer, holds visible even with no row; no new screen, no direct table access', () => {
  expect(ui).toContain('<details data-entry-sources open={!total}><summary>Sources and reads (')
  expect(ui).toContain("<td><small>{String(x.run?.error||x.error||'').slice(0,140)||'—'}</small></td>")
  expect(ui).toContain("{!total?<small>{sources.length?'No row read for this provider yet.':'No entry requirements read for this provider.'}</small>:<>")
  expect(ui).not.toMatch(/supabase\.from\(/)
  expect(fs.readFileSync('src/mature-main.jsx', 'utf8')).toContain('{data.id&&<ProviderEntryMatrix providerId={data.id}/>}')
})
