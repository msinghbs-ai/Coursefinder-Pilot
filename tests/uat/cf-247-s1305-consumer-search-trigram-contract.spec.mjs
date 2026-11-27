// Guards: IQ-00615 (SS-Programme-Control 27 Nov 2026 12:08, "Consumer Search Performance", s1305): the consumer free-text search (course_title and provider_name ILIKE) is answered from trigram indexes on search.course_documents, no later migration drops them, and the fix touches no frozen function or table shape (G3 stays with s57)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { migrationNames, migrationPath } from './support/migration-files.mjs'

const FILE = '20261130140000_cf247_s1305_consumer_search_trigram_indexes.sql'
const sql = fs.readFileSync(migrationPath(FILE), 'utf8')
const stripComments = s => s.replace(/--.*$/gm, '')
const code = stripComments(sql)

test('the migration adds a GIN trigram index on course_title and on provider_name', () => {
  expect(code).toMatch(/create index if not exists course_documents_title_trgm_idx on search\.course_documents using gin \(course_title extensions\.gin_trgm_ops\)/)
  expect(code).toMatch(/create index if not exists course_documents_provider_name_trgm_idx on search\.course_documents using gin \(provider_name extensions\.gin_trgm_ops\)/)
})

test('the migration is index-only: no function, table shape or grant changes, and no concurrent build', () => {
  expect(code).not.toMatch(/create\s+(or\s+replace\s+)?function|alter\s+table|drop\s+(table|function|view|index)|create\s+table|\bgrant\b|\brevoke\b/i)
  expect(code).not.toMatch(/concurrently/i)
  expect(sql).toMatch(/^-- Replaces: nothing/m)
  expect(sql).toMatch(/Retires: nothing/)
})

test('it checks the consumer API baseline before and after and holds the lesson in the recovery knowledge', () => {
  expect((code.match(/consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect(code).toContain("'consumer_search:unindexed_free_text:latency'")
  expect(code).toContain("not auto_eligible")
})

test('no later migration drops the trigram indexes', () => {
  const later = migrationNames().filter(f => f.endsWith('.sql') && f > FILE)
  for (const f of later) {
    const s = stripComments(fs.readFileSync(migrationPath(f), 'utf8'))
    expect(/drop\s+index[^;]*course_documents_(title|provider_name)_trgm_idx/i.test(s), `${f} drops a consumer search index`).toBe(false)
  }
})
