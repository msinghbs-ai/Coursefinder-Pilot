// Guards: Platform Admin 19 Nov 2026 16:18 (chat S1-RM-Design, s766): a university's identity hold on a shared host is settled by a recorded host owner, a recorded trading name counts as an identity name, and nothing is deleted, merged or retired; the consumer API is untouched (Decision 266, G3: 75 functions and 48 tables), Firecrawl stays 0, the spend stays inside the provider description route cap, and manual locks are honoured.
// CF-247 S1-RM-Design s766 (the file name is distinct: other lanes also hold an s766 spec for a different change). supabase/migrations/20261119172000_cf247_s766_au_university_identity.sql
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261119172000_cf247_s766_au_university_identity.sql', 'utf8')
const code = M.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('it is guarded: Firecrawl 0, the GPT-4.1 mini route under US$0.50, and the two live definitions it was written against', () => {
  expect(M).toContain("security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0")
  expect(M).toContain("'openai/gpt-4.1-mini'")
  expect(M).toContain("'cap'->>'usd')::numeric > 0.5")
  expect(M).toContain('8c1399260b3c7da5e427452f22ba3c6f')
  expect(M).toContain('f7b463e1df56305e32404c73493781b6')
  expect(M).toContain("jsonb_build_array(p.canonical_name,p.display_name)")
})

test('host owners: one new pipeline table with a comment, three owners by CRICOS key, and the proof honours them', () => {
  expect(M).toContain('create table if not exists pipeline.provider_host_owners (')
  expect(M).toMatch(/comment on table pipeline\.provider_host_owners is /)
  expect(M).toContain('alter table pipeline.provider_host_owners enable row level security;')
  for (const k of ['provider:cricos:00124k', 'provider:cricos:00122a', 'provider:cricos:00917k']) expect(M).toContain(`'${k}'`)
  expect(M).toContain("'rmit.edu.au,vu.edu.au,westernsydney.edu.au'")
  expect(M).toContain("return jsonb_build_object('ok', true, 'rule', 'identity_clear', 'via', 'recorded_host_owner');")
  expect(M).toContain("'rule', 'provider_host_conflict', 'conflicting_provider_id', v_owner")
  // a host with no owner is decided exactly as before
  expect(M).toContain("'reason', 'Another active provider holds the source host; exact provider identity requires resolution.'")
})

test('trading names: "Torrens University" and "Moore Theological College" as trading_name aliases that the reader passes on as identity names', () => {
  expect(M).toContain("('provider:cricos:03389e', 'Torrens University'), ('provider:cricos:00682b', 'Moore Theological College')")
  expect(M).toContain("'trading_name'")
  expect(M).toContain("a.alias_type = ''trading_name'' and a.valid_to is null")
  // the reader still asks the catalogue names first: the replacement appends, it never replaces them
  expect(M).toMatch(/v_old \|\| ' \|\| coalesce\(\(select jsonb_agg\(a\.alias/)
})

test('one stored-page read each for the two, taken by the scheduled worker; no description or lock is overwritten', () => {
  expect(M).toContain("security.provider_description_stored_v1(p.id) is not null")
  expect(M).toContain("nullif(btrim(p.description), '') is null")
  expect(M).toContain("l.field in ('description', 'p_description', 'all')")
  expect(M).toContain("'s766-au-university-identity'")
  expect(M).toContain('if v_n > 2 then raise exception')
})

test('nothing is deleted, merged or retired, and the consumer API is not touched (G3)', () => {
  expect(code).not.toMatch(/\bdelete\s+from\b|\bdrop\s+(table|function|column|index)\b|\btruncate\b/i)
  expect(code).not.toMatch(/\bupdate\s+catalogue\.(providers|courses)\b/i)
  expect(code).not.toMatch(/\b(public\.website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\.)/)
  expect(code).not.toMatch(/create\s+(or replace\s+)?function\s+public\./i)
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing$/m)
  expect(M).toContain('Not changed: the consumer API')
})

// Follow-up 20261119175000: the worker held the two reads on its recovery memory (no model call, nothing spent); they are asked for on demand, the way Fill description asks.
const F = fs.readFileSync('supabase/migrations/20261119175000_cf247_s766_torrens_moore_on_demand_read.sql', 'utf8')
const fcode = F.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n').replaceAll('on commit drop', 'on commit')

test('the follow-up opens an on-demand request with its estimate, scoped to openrouter, and marks the two reads on demand', () => {
  expect(F).toContain("security.on_demand_open_v1('claude_session'")
  expect(F).toContain("array['openrouter']")
  expect(F).toContain("jsonb_build_object('reads', (select count(*) from cf_s766b), 'ai_usd', 0.003, 'firecrawl_credits', 0)")
  expect(F).toContain("'on_demand', jsonb_build_object('by', 'c0ffee00-0000-4000-8000-000000000150', 'at', now())")
  expect(F).toContain("pipeline.svc_pilot_submit_nonce('coverage-sweep'")
  expect(F).toContain("security.pipeline_num_v1('pdesc.acquire_firecrawl', 1) <> 0")
  expect(F).toContain("'openai/gpt-4.1-mini'")
  expect(F).toContain('if v_n > 2 then raise exception')
})

test('the follow-up reads only a stored page, only a provider with no description and no manual lock, deletes and updates nothing', () => {
  expect(F).toContain('security.provider_description_stored_v1(p.id) is not null')
  expect(F).toContain("nullif(btrim(p.description), '') is null")
  expect(F).toContain("l.field in ('description', 'p_description', 'all')")
  expect(fcode).not.toMatch(/\bdelete\s+from\b|\bdrop\b|\btruncate\b|\bupdate\s+(pipeline|catalogue)\./i)
  expect(F).toMatch(/^-- Replaces: .+/m)
  expect(F).toMatch(/^-- Retires: nothing$/m)
})
