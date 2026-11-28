// Guards: Agent Operating Model S2-Scholarship rule 2 (long-page failures are a technical recovery lane; never pay again for the same failed full-page answer) and DR-19 (PC-20261128-CONTINUOUS-BUILD-EXECUTE, S2-Build scholarship reader machinery): a cut scholarship answer retried by the same model is read as the two-part read (sectioned-v1); candidate pages whose version 3 reads all failed are queued once for that read
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201163700_cf247_s1371_scholarship_candidate_cut_recovery.sql', 'utf8')

test('s1371: the same-model retry of a cut answer carries the sectioned-v1 variant (version 3, a try left, an existing variant kept)', () => {
  expect(sql).toContain("'public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)'")
  expect(sql).toContain("recovery = case when coalesce(p_error, '') like 'held_partial: output_truncated%' and coalesce(q.prompt_version, 0) >= 3 and q.attempts < 3 and q.recovery is null")
  expect(sql).toContain("then 'sectioned-v1' else q.recovery end")
})

test('s1371: stranded candidate pages are queued once as admit items with the sectioned-v1 variant, inside the existing recovery limit', () => {
  expect(sql).toContain("'security.scholarship_detail_recovery_queue_v1(integer)'")
  expect(sql).toContain("select a.model_code, a.prompt_version, 'admit', c.id, c.provider_id, coalesce(c.final_url, c.url), c.storage_path, 'sectioned-v1'")
  expect(sql).toContain("c.read_status = 'read' and c.admit_status is null and c.storage_path is not null")
  expect(sql).toContain("x.prompt_version >= 3 and x.error is null")
  expect(sql).toContain("(x.error like 'held_partial: output_truncated%' or x.error like 'no_answer%' or x.error like 'unreadable_answer%')")
  expect(sql).toContain("(q.state in ('queued', 'leased') or q.recovery is not null)")
  expect(sql).toContain('not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)')
  expect(sql).toContain('not security.third_party_host_v1(coalesce(c.final_url, c.url))')
  expect(sql).toContain('limit p_limit - n;')
})

test('s1371: anchored, idempotent, guarded; no table, job, setting or data change', () => {
  expect(sql).toContain('found % times')
  expect(sql).toContain('already applied')
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).toContain('manual locks changed')
  expect(sql).toContain('active job count changed')
  expect(sql).toMatch(/^-- Replaces: /m)
  expect(sql).toMatch(/^-- Retires: nothing\./m)
  expect(sql).not.toMatch(/create table|alter table|cron\.schedule|platform_toolset_settings/i)
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
