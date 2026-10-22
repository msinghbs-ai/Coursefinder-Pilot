// CF-247 v2.15.263 (S27): Platform Admin, 12 Oct 2026 23:54: "Yes, use Firecrawl for pages found by CRICOS code or listed by the uni."
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')

test('worker v0.21.5: Firecrawl reads only pages found by CRICOS code, listed by the university or entered by a person', () => {
  expect(worker).toContain('const FC_TRUSTED_BASIS = ["cricos_search", "cricos_code", "cricos_code_on_page", "title_match", "cms_path_public", "manual", "firecrawl_upgrade", "ai_match", "programme_list"];')
  // v0.38.1 (22 Oct 2026): pages the AI page match chose from the university's own list; v0.39.0: pages from the university's programme list
  for (const b of ['title_search', 'firecrawl_search', 'serper_search']) expect(worker).not.toMatch(new RegExp(`FC_TRUSTED_BASIS = \\[[^\\]]*"${b}"`))
  // v0.36.0 (Platform Admin 22 Oct 2026, NZ review fix 3): a page that needed a browser in pages.render_countries is also rendered (render_ok)
  expect(worker).toContain('const fcTrusted = FC_TRUSTED_BASIS.includes(it.basis || "") || it.manual === true || it.render_ok === true;')
  expect(worker).toContain('const viewRender = viewApplies(it.url, pv) && !searchCandidate && fcTrusted;')
  expect(worker).toContain('if (fcTrusted && (!searchCandidate || searchFound) && !(adDirect?.json_found')
  expect(worker).toContain('it.priority === true && !searchCandidate && fcTrusted && await useFc("scrape"')
  // every Firecrawl scrape in the read path is behind fcTrusted
  const from = worker.indexOf('const fcTrusted =')
  const read = worker.slice(from, worker.indexOf('if (status === "read") {', from) + 2000)
  expect((read.match(/useFc\("scrape"/g) || []).length).toBe(3)
})
