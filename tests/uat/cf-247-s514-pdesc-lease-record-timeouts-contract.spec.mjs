// Guards: F-PDESC (P0, Platform Admin 9 Nov 2026), lease and record statement time-outs: migration 20261109233000 edits only public.svc_provider_description_next and public.svc_provider_description_record (md5-guarded, replaces/retires named), adds one plain index, changes no statement time-out, setting, ceiling, job or data, and the harness shows the same items, order, content and results before and after.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261109233000_cf247_pdesc_lease_record_timeouts.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')   // the statements, without the comments
const HARNESS = fs.readFileSync('tests/fixtures/pdesc-lease-record-timeouts/run.sh', 'utf8')
const SCEN = fs.readFileSync('tests/fixtures/pdesc-lease-record-timeouts/scenarios.sql', 'utf8')
const HELD_RECOVERY = fs.readFileSync('supabase/held/pdesc_lease_record_timeouts_forward_recovery.sql', 'utf8')
const HELD_EQUIV = fs.readFileSync('supabase/held/pdesc_lease_record_timeouts_equivalence.sql', 'utf8')
const WF = fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')
const NEWS = MIG.slice(MIG.indexOf('array[\n$new$'))
const NEXT_ALL = MIG.slice(MIG.indexOf("select pg_temp.edit_all('public.svc_provider_description_next"), MIG.indexOf("select pg_temp.edit_all('public.svc_provider_description_record"))
const NEXT_NEW = NEXT_ALL.slice(NEXT_ALL.indexOf('array[\n$new$'))   // the text the lease edit writes
const REC_NEW = MIG.slice(MIG.indexOf("select pg_temp.edit_all('public.svc_provider_description_record"), MIG.indexOf('create index if not exists'))

test('the migration names what it replaces and retires, and records the live md5 of both bodies and the md5 it produces', () => {
  expect(MIG).toMatch(/^-- Replaces: .*svc_provider_description_next.*svc_provider_description_record/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain('public.svc_provider_description_next(integer) 54c8856ec36465059d41d71a5a5d462b -> 7583808609dc2dea1d3fc251607405a1')
  expect(MIG).toContain('public.svc_provider_description_record(jsonb) f7c3debc11b67d6de7b2c6d47c8c9b9c -> 9b2137954bc05501e55e93c8ef9cf448')
  expect(CODE.match(/pg_temp\.edit_all\('/g)).toHaveLength(2)
  expect(CODE).toContain("edit_all('public.svc_provider_description_next(integer)', '54c8856ec36465059d41d71a5a5d462b', '7583808609dc2dea1d3fc251607405a1'")
  expect(CODE).toContain("edit_all('public.svc_provider_description_record(jsonb)', 'f7c3debc11b67d6de7b2c6d47c8c9b9c', '9b2137954bc05501e55e93c8ef9cf448'")
})

test('it refuses, and changes nothing, when either live function is not the one it was written against, and is a no-op the second time', () => {
  expect(CODE).toContain("raise exception 'live % differs from the definition this change edits")
  expect(CODE).toContain("return p_sig || ': already applied'")
  expect(CODE).toContain("raise exception '% after the edit has body md5 %, expected %'")
  expect(HARNESS).toContain('a hand-changed lease function and a hand-changed record function are each refused and nothing is applied')
  expect(HARNESS).toContain('applied again: no change')
})

test('the lease pick is lazy: cheap tests and the order for every due read, the per-provider tests only until the limit, the same lock and the same limit', () => {
  // the optimisation fence keeps the dear tests above the sort and under the limit
  expect(NEXT_NEW).toContain('offset 0) c')
  expect(NEXT_NEW.indexOf('offset 0) c')).toBeLessThan(NEXT_NEW.indexOf('security.provider_description_scope_v1(c.provider_id)'))
  for (const dear of ['security.provider_description_scope_v1(c.provider_id)', 'security.ops_learning_retry_check_v1(', 'security.provider_description_identity_v1(p.id', 'security.provider_hidden_v1'])
    expect(NEXT_NEW.indexOf(dear), dear).toBeGreaterThan(NEXT_NEW.indexOf('offset 0) c'))
  // the order, the row lock with skip locked, the due test repeated on the locked row, and the limit are as before
  expect(NEXT_NEW).toContain('order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at')
  expect(NEXT_NEW).toContain('for update skip locked) l')
  expect(NEXT_NEW).toContain("(q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'reading' and q.leased_until < now())")
  expect(NEXT_NEW).toContain("limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))")
  // the two settings are still read through pipeline_num_v1, with their defaults, now once
  expect(NEXT_NEW).toContain("v_tries numeric := security.pipeline_num_v1('pdesc.tries', 3)")
  expect(NEXT_NEW).toContain("v_acq boolean := security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1")
})

test('the record finds the sweep source once and asks the identity check once per read; the volatile function is no longer a test on every row', () => {
  expect(REC_NEW.match(/v_src := security\.coverage_sweep_source\(r\.provider_id\);/g)).toHaveLength(1)
  expect(REC_NEW).toContain('a.source_id = v_src and a.content_hash = v_hash and a.source_url = v_url')
  expect(REC_NEW).toContain('public.svc_coursefacts_register_evidence(v_src, v_url,')
  expect(REC_NEW.slice(REC_NEW.indexOf('array[\n$new$')).match(/security\.coverage_sweep_source\(/g)).toHaveLength(1)
  expect(REC_NEW.slice(REC_NEW.indexOf('array[\n$new$')).match(/security\.provider_description_identity_v1\(/g)).toHaveLength(1)
  expect(REC_NEW).toContain("v_idc->>'rule'")
  expect(REC_NEW).toContain("v_idc->>'reason'")
})

test('the one index is plain and commented, and nothing else is created', () => {
  expect(CODE.match(/create (unique )?index/gi)).toHaveLength(1)
  expect(CODE).toContain('create index if not exists evidence_artifacts_source_url_idx on pipeline.evidence_artifacts (source_id, source_url);')
  expect(CODE).toContain('comment on index pipeline.evidence_artifacts_source_url_idx is')
  expect(CODE).not.toMatch(/create (table|view|function|trigger)|alter table|add column|create or replace function public\./i)
  expect(CODE).not.toMatch(/\bconcurrently\b/i)
})

test('NEGATIVE: no statement time-out, lock time-out, setting, ceiling, job or data is touched; nothing is dropped or deleted', () => {
  expect(CODE).not.toMatch(/statement_timeout|lock_timeout|idle_in_transaction|plan_cache_mode/i)
  expect(CODE).not.toMatch(/platform_toolset_settings|cron\.(schedule|alter_job|unschedule)/i)
  expect(CODE).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(CODE).not.toMatch(/\b(insert into|update)\s+(pipeline|catalogue|public)\./i)
  expect(CODE).not.toMatch(/ai_usd_max|firecrawl_reads_max|concurrency_max|dispatch_max/)
  // the reservation protocol, the advisory lock and the claim timer stay in the functions the migration edits
  expect(CODE).not.toMatch(/pg_try_advisory_xact_lock|pg_advisory_xact_lock|provider-description-reserve-v1|interval '20 minutes'/)
  // the consumer API is not touched (G3)
  expect(CODE).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
})

test('the held scripts: the forward recovery restores both bodies behind the md5 guard and drops nothing itself; the equivalence script only reads', () => {
  expect(HELD_RECOVERY).toContain('54c8856ec36465059d41d71a5a5d462b')
  expect(HELD_RECOVERY).toContain('f7c3debc11b67d6de7b2c6d47c8c9b9c')
  expect(HELD_RECOVERY.match(/CREATE OR REPLACE FUNCTION/g)).toHaveLength(2)
  const recoveryCode = HELD_RECOVERY.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')
  expect(recoveryCode).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(HELD_RECOVERY).toMatch(/^-- drop index if exists pipeline\.evidence_artifacts_source_url_idx;$/m)
  const equivCode = HELD_EQUIV.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')
  expect(equivCode).toContain('raise exception')
  expect(equivCode).not.toMatch(/\b(insert into|update|delete from|drop|truncate|alter)\b/i)
})

test('the harness proves the same items, order, content and results, covers the skipped providers, the setting limit and a direct read, and runs in the integration workflow', () => {
  for (const s of ['scope_skip', 'draft_skip', 'setting_limit', 'record_direct'])
    expect(SCEN, s).toContain(`'${s}'`)
  expect(HARNESS).toContain('[ "$AFTERS" = "$BEFORE" ]')
  expect(HARNESS).toContain('[ "$AFTER_OP" = "$BEFORE_OP" ]')
  expect(HARNESS).toContain("PDCC_KEEP=1 PDCC_DB=$DB bash tests/fixtures/pdesc-claim-context/run.sh")
  expect(WF).toContain('bash tests/fixtures/pdesc-lease-record-timeouts/run.sh')
  expect(WF).toContain('tests/uat/cf-247-s514-pdesc-lease-record-timeouts-contract.spec.mjs')
  expect(fs.readFileSync('tests/fixtures/pdesc-lease-record-timeouts/expected.txt', 'utf8').trim().split('\n')).toHaveLength(4)
})
