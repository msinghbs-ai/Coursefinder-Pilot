// CF-247 production readiness phase 1 (10 Oct 2026): live-only website code is held in git.
import { test, expect } from '@playwright/test'
import { readFileSync, readdirSync } from 'node:fs'
import { createHash } from 'node:crypto'

const dir = 'supabase/live-capture/functions'
const md5 = (b) => createHash('md5').update(b).digest('hex')

test('every captured database function matches its manifest md5', () => {
  const rows = readFileSync(`${dir}/MANIFEST.tsv`, 'utf8').trim().split('\n').slice(1).map((l) => l.split('\t'))
  expect(rows.length).toBe(22)
  for (const [, name, , hash, file] of rows) {
    expect(name).toMatch(/^(website_v2_|website_edge_course_search_v3_1$)/)
    expect(md5(readFileSync(`${dir}/${file}`))).toBe(hash)
  }
  expect(readdirSync(dir).filter((f) => f.endsWith('.sql')).length).toBe(22)
})

test('website edge functions hold the live contracts', () => {
  const site = readFileSync('supabase/functions/website-course-api/index.ts', 'utf8')
  expect(site).toContain('website-integration-v3.1-pilot')
  expect(site).toContain('website_edge_course_search_v3_1')
  const wix = readFileSync('supabase/functions/wix-course-api/index.ts', 'utf8')
  expect(wix).toContain('website-search-v2')
  expect(wix).toContain('website_v2_course_search')
})

test('ranking-publisher-import deploys through CI', () => {
  const wf = readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')
  expect(wf).toContain('[ranking-publisher-import]=false')
})
