// Guards: CF-247 AER v1.1 schema (Platform Admin 26 Oct 2026 21:39 / 21:50): six additive columns, three indexes and the row identity on catalogue.provider_entry_matrix; nothing dropped, renamed or modified
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261026007000_cf247_aer_v11_entry_matrix_columns.sql', 'utf8')
const sql = m.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('additive only: exactly the six approved columns, no drop / rename / delete / truncate / data update', () => {
  const cols = [...sql.matchAll(/alter table catalogue\.provider_entry_matrix add column if not exists (\w+) ([^;]+);/g)].map((x) => `${x[1]} ${x[2]}`)
  expect(cols).toEqual(['routes jsonb', 'valid_to date', 'withdrawal_reason varchar(500)', 'row_hash char(64)', 'version integer default 1', 'aer_level varchar(20)'])
  expect(sql).not.toMatch(/\b(drop|truncate|rename)\b/i)
  expect(sql).not.toMatch(/^\s*(delete|update)\s/im)
  expect(sql).not.toMatch(/alter table [^;]*(alter column|drop constraint|add constraint)/i)
})

test('indexes: row_hash unique among active rows, status, and the lookup on the existing column names', () => {
  expect(sql).toContain("create unique index if not exists provider_entry_matrix_row_hash_uq on catalogue.provider_entry_matrix (row_hash) where status = 'active';")
  expect(sql).toContain('create index if not exists provider_entry_matrix_status_ix on catalogue.provider_entry_matrix (status);')
  expect(sql).toContain('create index if not exists provider_entry_matrix_lookup_ix on catalogue.provider_entry_matrix (provider_id, country_code, study_level_id, benchmark_band, status);')
})

test('row identity: provider, course, country, level, band and sorted condition keys (not grades); filled by trigger; same identity + changed content bumps version', () => {
  expect(sql).toContain("p_provider::text || '|' || coalesce(p_course::text, '') || '|' || coalesce(upper(p_country), '') || '|' || coalesce(p_level::text, '') || '|' ||")
  expect(sql).toMatch(/string_agg\(k, '\|' order by k\)/)
  expect(sql).toMatch(/coalesce\(e->>'board', e->>'era', e->>'key'\)/)
  // the row's own qualification is one of its condition keys (one row per qualification in the live reader)
  expect(sql).toContain("select lower(btrim(p_qualification)) where nullif(btrim(p_qualification), '') is not null")
  expect(sql).not.toMatch(/min_grade'|min_value'/)
  expect(sql).toContain("encode(sha256(convert_to(")
  expect(sql).toContain('create trigger provider_entry_matrix_identity before insert or update on catalogue.provider_entry_matrix')
  expect(sql).toContain('new.version := coalesce(old.version, 1) + 1;')
})
