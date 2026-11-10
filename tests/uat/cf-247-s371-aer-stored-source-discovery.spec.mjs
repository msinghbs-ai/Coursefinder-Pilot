// Guards: AER source discovery without paid acquisition (Platform Admin mandate 7 Nov 2026 21:57; "do not spend Firecrawl credits") and "a passing qualification never switches anything on by itself"
// Migration 20261107150000 opens the circular gate that kept 1,424 AER-eligible providers from ever being given a first entry-requirements page, and adds a stored-link step
// (job aer-source-stored-find, paused, setting off). The database behaviour (scenarios S1 to S6) runs on a scratch PostgreSQL: tests/fixtures/aer-stored-source-discovery/run.sh.
// This spec holds the source contract. G2, G3 and housekeeping are guarded centrally (s32, s57, s42) and not re-asserted here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261107150000_cf247_aer_source_stored_discovery.sql', 'utf8')
const code = MIG.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/aer-stored-source-discovery'
const fn = (name) => { const a = code.indexOf(`function ${name}`); return code.slice(a, code.indexOf('$function$;', code.indexOf('$function$', a) + 10)) }

test('the step reads stored links only: it fetches nothing, calls no scraper or AI, and writes only the source list and its own record', () => {
  const body = fn('security.entry_source_stored_find_v1')
  expect(body.length).toBeGreaterThan(500)
  expect(body).not.toMatch(/net\.http|http_|firecrawl|openrouter|svc_pilot_submit|pg_net/i)
  expect(body).toMatch(/pipeline\.coverage_provider_urls/)
  expect(body).toMatch(/pipeline\.provider_discovery_links/)
  const writes = [...body.matchAll(/\b(insert\s+into|update|delete\s+from)\s+([a-z_]+\.[a-z_]+)/gi)].map((m) => m[2])   // 'do update set' is not a table
  expect([...new Set(writes)].sort()).toEqual(['pipeline.aer_source_stored_find', 'pipeline.entry_matrix_sources'])
  // the source is attached as the existing path attaches a suggestion (found_via search, status found by default), never as read or admitted
  expect(body).toContain("'search'")
  expect(body).not.toMatch(/status\s*=\s*'read'|layer4_review_items|catalogue\.provider_entry_matrix|course_entry_requirements/)
})

test('identity: own website host only, a host another active provider uses is not attached, third-party hosts and hidden providers are skipped', () => {
  const body = fn('security.entry_source_stored_find_v1')
  expect(body).toContain("right(security.site_host_v1(u.url), length(r.ph) + 1) = '.' || r.ph")
  expect(body).toContain("o.lifecycle_status = 'active' and security.site_host_v1(o.website) = r.ph")
  expect(body).toContain("when v_shared then 'host_shared'")
  expect(body).toContain('not security.third_party_host_v1(p.website)')
  expect(body).toContain('security.entry_matrix_attach_allowed_v1(p.id)')   // hidden providers and countries switched off are refused by the rule
  expect(body).toContain('security.aer_eligible_v1()')
})

test('G2 at the edges: size, wait, cap and score are settings; the switch ships 0 and the job ships paused', () => {
  const body = fn('security.entry_source_stored_find_v1')
  for (const k of ["'batch.aer_source_stored_find'", "'entry.attach_per_provider'", "'central.min_suggest_score'", "'aer.source_stored_find_recheck_days'", "'aer.source_stored_find_on'"]) expect(body, k).toContain(k)
  expect(code).toMatch(/'aer\.source_stored_find_on'[\s\S]{0,900}?'number', '0'::jsonb, 0, 1, 'on\/off'/)
  expect(code).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'aer-source-stored-find'), active := false)")
  expect(code).toContain("raise exception 'post-check: the step must ship off'")
  expect(code).toContain("raise exception 'post-check: the job must ship paused'")
  expect(code).not.toMatch(/update\s+pipeline\.platform_toolset_settings/i)
})

test('the circular gate: attach_v1 is replaced under its live md5; enabled_v1 is not edited; the new rule is enabled_v1 minus the recorded-page clause', () => {
  expect(MIG).toMatch(/^-- Replaces: .*entry_matrix_attach_v1/m)
  expect(MIG).toMatch(/^-- Retires: nothing/m)
  expect(MIG).toContain('b34e95379b61ef98a65837686825857f')
  expect(code).toContain("replace(v_def, v_old, 'security.entry_matrix_attach_allowed_v1(s.provider_id)')")
  expect(code).not.toMatch(/create or replace function security\.entry_matrix_enabled_v1/)
  const rule = fn('security.entry_matrix_attach_allowed_v1')
  expect(rule).not.toContain('pipeline.entry_matrix_sources')
  for (const k of ["'entry.matrix_enabled'", "'entry.countries'", 'security.provider_hidden_v1', 'security.aer_eligible_v1()', 'security.aer_schedule_country_v1', "'entry.providers'"]) expect(rule, k).toContain(k)
  // the live definitions the fixture loads are the ones whose md5 the migration and the runner check
  expect(fs.readFileSync(`${FX}/run.sh`, 'utf8')).toContain('b34e95379b61ef98a65837686825857f')
  expect(fs.readFileSync(`${FX}/run.sh`, 'utf8')).toContain('582a5024ffeca0ac3c5446a903b39b3f')
})

test('the page rules are the worker\'s: every pattern of central.ts entry_requirements is in the score function', () => {
  const central = fs.readFileSync('supabase/functions/coverage-sweep/central.ts', 'utf8')
  const strong = central.match(/entry_requirements: \{\s*strong: \/(.+?)\/,\s*weak: \/(.+?)\//s)
  expect(strong).toBeTruthy()
  // the latest migration that defines the scorer (20261111100000 F-AER.01 adds the small-provider top-level rule with central.ts v0.64.0)
  const lastDef = fs.readdirSync('supabase/migrations').filter((f) => f.endsWith('.sql')).sort().reverse()
    .map((f) => fs.readFileSync(`supabase/migrations/${f}`, 'utf8')).find((t) => /function security\.entry_source_score_v1\(/i.test(t))
  const lc = lastDef.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n'), la = lc.search(/function security\.entry_source_score_v1\(/i)
  const score = lc.slice(la, lc.indexOf('$function$;', lc.indexOf('$function$', la) + 10))
  expect(score).toContain(strong[1].replace(/\\\//g, '/'))
  expect(score).toContain(strong[2])
  const noise = central.match(/const NOISE = \/(.+?)\/;/)[1]
  const sqlNoise = noise.replace(/\(\?:/g, '(').replace(/\\b/g, '\\y').replace(/\\\//g, '/')
  expect(score.replace(/\\y/g, '\\y')).toContain(sqlNoise.replace(/^\\\//, '/').slice(0, 120))
})

test('housekeeping rows: the five components and the job are registered; the record table states its purpose; the measurement file only reads', () => {
  expect(code).toContain("('job', 'aer-source-stored-find'")
  expect(code).toMatch(/comment on table pipeline\.aer_source_stored_find is '/)
  expect((code.match(/introduced_in|'20261107150000'/g) || []).length).toBeGreaterThan(4)
  const measure = fs.readFileSync('docs/paste/MEASURE-20261107-aer-stored-source-discovery.sql', 'utf8')
  expect(measure).toContain('entry_source_stored_find_v1')
  expect(measure.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')).not.toMatch(/\b(insert|update|delete|drop|alter|truncate)\b/i)
  expect(code).not.toMatch(/website_v2_|website_edge_|zoho_edge_|\bapi\./)   // G3 reading: no consumer API object
})

test('fixture runner: checks the live md5s, reproduces the circular gate, applies the migration twice and fails on any scenario error', () => {
  const run = fs.readFileSync(`${FX}/run.sh`, 'utf8'), sc = fs.readFileSync(`${FX}/scenarios.sql`, 'utf8')
  expect(run).toContain('set -euo pipefail')
  expect(run.match(/-f \$MIG(?!2)/g).length).toBe(2)
  expect(run.match(/-f \$MIG2/g).length).toBe(2)   // the speed fix 20261107160000, applied twice
  expect(run).toContain('refusing a Supabase project database')
  expect(fs.readFileSync(`${FX}/before.sql`, 'utf8')).toContain('B2 the attach cannot give it a suggested first page')
  for (const s of ['S1', 'S2', 'S3', 'S4', 'S5', 'S6']) expect(sc, s).toContain(`-- ${s} `)
  expect(sc).toContain('S3 the measurement wrote nothing')
  expect(sc).toContain('S4 two providers on one website: recorded host_shared')
})

test('speed fix 20261107160000: the eligibility rule is judged one provider at a time, each stored link is scored once, and the step still only reads stored links', () => {
  const sql = fs.readFileSync('supabase/migrations/20261107160000_cf247_aer_stored_find_speed.sql', 'utf8')
  const body = sql.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
  // the rule is no longer a per-row filter of the selection (it rebuilt the eligible set 1,476 times); it is judged in the loop, only as far as the run needs
  expect(body).not.toMatch(/where security\.entry_matrix_attach_allowed_v1\(p\.id\)/)
  expect(body).toMatch(/if not security\.entry_matrix_attach_allowed_v1\(r\.provider_id\) then continue; end if;/)
  expect(body).toMatch(/if v_looked >= v_limit then exit; end if;/)
  expect(body.match(/entry_source_score_v1\(/g).length).toBe(1)   // each link is scored once
  expect(body).not.toMatch(/net\.http|http_|firecrawl|openrouter|pg_net/i)
  expect(sql).toMatch(/^-- Replaces: security\.entry_source_stored_find_v1/m)
  expect(sql).toMatch(/^-- Retires: nothing/m)
})
