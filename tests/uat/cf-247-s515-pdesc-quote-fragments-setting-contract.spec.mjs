// Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026), quote_not_on_page and G2: the switch reading.provider_quote_fragments_on exists as a governed setting (label, range, unit, used_by, section), ships off, is added with on conflict do nothing, and the migration touches no function, job, table or other setting; a passing test never switches it on.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261109184000_cf247_pdesc_quote_fragments_setting.sql', 'utf8')
const CODE = MIG.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n')

test('the setting row is governed (G2) and ships off', () => {
  expect(CODE).toContain("('pipeline', 'reading.provider_quote_fragments_on', 'Provider descriptions: prove a joined quote fragment by fragment'")
  expect(CODE).toContain("'number', to_jsonb(0), 0, 1, 'on/off', 1024, 'Provider descriptions',")
  expect(CODE).toMatch(/used_by|worker coverage-sweep provider_description \(description\.ts providerDescriptionSentences\)/)
  expect(CODE).toContain('on conflict (toolset_key, key) do nothing')
  expect(CODE).toMatch(/coalesce\(label, ''\) <> ''.*coalesce\(unit, ''\) <> ''.*coalesce\(used_by, ''\) <> ''/s)
  expect(MIG).toMatch(/^-- Replaces: nothing/m)
  expect(MIG).toMatch(/^-- Retires: nothing$/m)
})

test('NEGATIVE: it is the only row, it does not turn anything on, and nothing else is touched or dropped', () => {
  expect(CODE.match(/insert into/g)).toHaveLength(1)
  expect(CODE).not.toMatch(/\bupdate\b|\bdelete\b|\bdrop\b|truncate|create (or replace )?function|cron\.|alter table|create table|create (unique )?index/i)
  expect(CODE).not.toMatch(/to_jsonb\(1\)/)
  // the other switches of the provider-description reader are not changed here
  expect(CODE).not.toMatch(/machine_admit_on|registry_factual_on|registry_after_rules|ai_usd_max|firecrawl_reads_max/)
})

test('the worker reads exactly this key from the worker settings, and the database hands the worker pipeline reading.* keys', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  // the worker change ships in its own PR; when it is in, it reads the key as a number and treats anything below 1 as off
  if (ix.includes('reading.provider_quote_fragments_on')) expect(ix).toContain('Number(ws["reading.provider_quote_fragments_on"]) >= 1')
  expect(CODE).toContain("like '%s.key like ''reading.%''%'")
})
